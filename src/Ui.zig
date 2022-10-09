const std = @import("std");
const Db = @import("Db.zig");
const shared = @import("shared.zig");
const term = @import("terminal.zig");
const Statements = @import("Statements.zig");
const Style = @import("Style.zig");

gpa: std.mem.Allocator,
stdout: std.fs.File,
stmts: *Statements,
arena: std.heap.ArenaAllocator,
selected: ?i64 = null,
offset: u64 = 0,
original_terminal_settings: std.os.termios = undefined,
todos: []shared.Todo = &[0]shared.Todo{},

const Self = @This();

pub fn init(gpa: std.mem.Allocator, stmts: *Statements) !Self {
    var stdout = std.io.getStdOut();
    var self = Self{ .gpa = gpa, .stdout = stdout, .stmts = stmts, .arena = std.heap.ArenaAllocator.init(gpa) };
    try self.setupTerminal();
    return self;
}

fn setupTerminal(self: *Self) !void {
    self.original_terminal_settings = try std.os.tcgetattr(std.os.STDIN_FILENO);

    var raw = self.original_terminal_settings;
    raw.iflag &= ~@intCast(c_uint, term.BRKINT | term.ICRNL | term.INPCK | term.ISTRIP | term.IXON);
    raw.lflag &= ~@intCast(c_uint, term.ECHO | term.ICANON | term.IEXTEN | term.ISIG);
    raw.cc[term.VMIN] = 1;

    try std.os.tcsetattr(std.os.STDIN_FILENO, std.os.TCSA.NOW, raw);

    try self.stdout.writeAll("\x1b[?47h"); // Save screen
    try self.stdout.writeAll("\x1b[s"); // Save cursor pos
    try self.stdout.writeAll("\x1b[?25l"); // Make cursor invisible
}

fn getWinsz(_: *const Self) term.winsize {
    var winsz = std.mem.zeroes(term.winsize);
    _ = std.os.system.ioctl(std.os.system.STDOUT_FILENO, term.TIOCGWINSZ, @ptrToInt(&winsz));
    return winsz;
}

pub fn draw(self: *Self) !void {
    try self.stdout.writeAll("\x1b[2J"); // Erase entire screen
    try self.stdout.writeAll("\x1b[H"); // Move cursor to home

    const winsz = self.getWinsz();
    var writer = self.stdout.writer();

    for (self.todos) |todo, i| {
        if (i < self.offset) continue;
        if (i - self.offset >= winsz.ws_row) break;

        const is_selected = if (self.selected) |s| todo.id == s else false;
        try todo.write(self.arena.allocator(), writer, winsz.ws_col, is_selected);
    }
}

fn fetch(self: *Self) !void {
    self.arena.deinit();
    self.arena = std.heap.ArenaAllocator.init(self.gpa);
    self.todos = try self.stmts.list_todos.all(shared.Todo, self.arena.allocator(), .{}, .{});

    const selected = self.selected orelse {
        self.selected = self.todos[0].id;
        return;
    };

    const selected_index = b: {
        for (self.todos) |t, i| {
            if (t.id == selected) break :b i;
        }

        unreachable;
    };

    const ws = self.getWinsz();
    if (selected_index < self.offset or selected_index > self.offset + ws.ws_row) {
        if (selected_index < ws.ws_row / 2) {
            self.offset = 0;
            return;
        }

        const offset = selected_index - ws.ws_row / 2;
        self.offset = std.math.min(offset, self.todos.len - ws.ws_row);
    }
}

fn getSelected(self: *Self) ?*shared.Todo {
    const s = self.selected orelse return null;
    for (self.todos) |*todo| {
        if (todo.id == s) return todo;
    }

    return null;
}

fn selectedIndexInc(self: *Self, inc: enum { up, down }) void {
    if (self.todos.len == 0) return;

    const s = self.selected orelse return;
    const winsz = self.getWinsz();

    if (s == self.todos[0].id and inc == .up) {
        self.selected = self.todos[self.todos.len - 1].id;
        if (self.todos.len >= winsz.ws_row) self.offset = self.todos.len - winsz.ws_row;
        return;
    } else if (s == self.todos[self.todos.len - 1].id and inc == .down) {
        self.selected = self.todos[0].id;
        self.offset = 0;
        return;
    }

    for (self.todos) |todo, i| {
        if (todo.id == s) {
            var index = if (inc == .down) i + 1 else i - 1;
            self.selected = self.todos[index].id;
            if (inc == .down and i - self.offset + 1 >= winsz.ws_row) self.offset += 1;
            if (inc == .up and i <= self.offset) self.offset -= 1;
            return;
        }
    }

    unreachable;
}

fn changeSelectedState(self: *Self, state: shared.TodoState) !void {
    var todo = self.getSelected() orelse return;
    todo.state = state;
    try self.stmts.update_todo.exec(.{}, .{ .title = todo.title, .priority = todo.priority, .state = todo.state, .id = todo.id });
}

fn clockIn(self: *Self) !void {
    const selected = self.selected orelse return;
    if (try shared.clockedInTodo(self.arena.allocator(), self.stmts)) |_| {
        return;
    }

    try self.stmts.insert_period.exec(.{}, .{selected});
}

fn changePriority(self: *Self, dir: i64) !void {
    var todo = self.getSelected() orelse return;
    todo.priority += dir;
    try self.stmts.update_todo.exec(.{}, .{ .title = todo.title, .priority = todo.priority, .state = todo.state, .id = todo.id });
}

const JournalContents = struct {
    contents: []const u8,
    tags: ?[][]const u8,
};

fn parseJournalContents(allocator: std.mem.Allocator, time: []const u8, entry: []const u8) !JournalContents {
    if (entry.len < 11) return error.InvalidParse;
    if (entry[0] != '#' or entry[1] != ' ') return error.InvalidParse;
    if (!std.mem.eql(u8, entry[2..10], time)) return error.InvalidParse;

    var i: usize = 10;
    while (i < entry.len - 1) : (i += 1) {
        if (entry[i] == '\n')
            return JournalContents{ .contents = entry[i + 1 ..], .tags = null };
        if (entry[i] == ':') {
            break;
        }
    }

    if (i == entry.len - 1) return JournalContents{ .contents = "", .tags = null };

    var end = i + 1;
    while (end < entry.len - 1) : (end += 1) {
        if (entry[end] == '\n')
            break;
    }

    var tags = std.ArrayList([]const u8).init(allocator);
    errdefer tags.deinit();

    var it = std.mem.split(u8, entry[i..end], ":");
    while (it.next()) |v| {
        const stripped = std.mem.trim(u8, v, " \t");
        if (stripped.len != 0) try tags.append(stripped);
    }

    return JournalContents{ .contents = entry[end + 1 ..], .tags = tags.toOwnedSlice() };
}

fn tagJournalEntry(self: *Self, id: i64, tags: [][]const u8) !void {
    for (tags) |tag| {
        const tag_id = (try self.stmts.get_tag.one(i64, .{}, .{tag})) orelse b: {
            const tag_id = (try self.stmts.insert_tag.one(i64, .{}, .{tag})) orelse return error.SqliteError;
            break :b tag_id;
        };

        try self.stmts.insert_tagging.exec(.{}, .{ .tag_id = tag_id, .journal_id = id, .todo_id = null });
    }
}

fn createJournalEntry(self: *Self, linked_to_selected: bool) !void {
    if (linked_to_selected and self.selected == null) return;

    const tid = if (linked_to_selected) self.selected else null;

    var allocator = self.arena.allocator();
    const v = (try self.stmts.insert_journal_entry.oneAlloc(struct { id: i64, time: []const u8 }, allocator, .{}, .{tid})) orelse return;

    const tmpl =
        \\# {s}
        \\
        \\
    ;
    const contents = try std.fmt.allocPrint(allocator, tmpl, .{v.time});

    const data_dir = try Db.getDataDir(allocator);
    const filename = try std.fmt.allocPrint(allocator, "tmp-journal-{}.md", .{v.id});
    const tmp_file_path = try std.fs.path.join(allocator, &.{ data_dir, filename });

    std.log.debug("opening {s}", .{tmp_file_path});

    var f = try std.fs.createFileAbsolute(tmp_file_path, .{ .read = true });
    defer f.close();
    defer std.fs.deleteFileAbsolute(tmp_file_path) catch {};
    errdefer self.stmts.delete_journal_entry.exec(.{}, .{v.id}) catch {};

    try f.writeAll(contents);

    while (true) {
        // TODO: allow different editors
        var proc = std.ChildProcess.init(&.{ "kak", tmp_file_path, "+2" }, allocator);
        switch (try proc.spawnAndWait()) {
            .Exited => |e| if (e == 0) b: {
                try f.seekTo(0);
                const new_contents = try f.readToEndAlloc(allocator, 2 * 1024 * 1024);
                // User didn't change anything so presume they don't want a journal entry
                if (std.mem.eql(u8, new_contents, contents)) {
                    break :b;
                }

                var res = parseJournalContents(allocator, v.time, new_contents) catch |err| switch (err) {
                    error.InvalidParse => continue, // User made an error - dump them back in the editor
                    else => return err, // Something else went wrong, propagate the error
                };

                const trimmed = std.mem.trim(u8, res.contents, "\n\t ");
                try self.stmts.update_journal_entry.exec(.{}, .{ trimmed, v.id });

                if (res.tags) |tags| try self.tagJournalEntry(v.id, tags);

                return;
            },
            else => {},
        }

        try self.stmts.delete_journal_entry.exec(.{}, .{v.id});
        return;
    }
}

fn showHistory(self: *Self) !void {
    const selected = self.selected orelse return;

    var allocator = self.arena.allocator();

    var proc = std.ChildProcess.init(&.{ "kak", "-e", "set buffer filetype markdown" }, allocator);
    proc.stdin_behavior = .Pipe;
    try proc.spawn();
    var writer = proc.stdin.?.writer();

    var it = try self.stmts.list_journal_entries_for_todo.stmt.iterator(struct {
        id: i64,
        entry: []const u8,
        created: []const u8,
        dt: []const u8,
        tm: []const u8,
    }, .{selected});

    var last_dt: ?[]const u8 = null;
    while (try it.nextAlloc(allocator, .{})) |entry| {
        if (last_dt == null or !std.mem.eql(u8, entry.dt, last_dt.?)) {
            if (last_dt != null) try writer.writeAll("\n");
            last_dt = entry.dt;
            try writer.print("# {s}\n", .{entry.dt});
        }

        try writer.print("## {s}\n", .{entry.tm});
        try writer.writeAll(entry.entry);
        try writer.writeAll("\n");
    }

    _ = try proc.wait();
}

fn update(self: *Self) !bool {
    var stdin = std.io.getStdIn();
    var buf: [1]u8 = undefined;
    _ = try stdin.read(&buf);

    switch (buf[0]) {
        'q' => return true,

        'j' => self.selectedIndexInc(.down),
        'k' => self.selectedIndexInc(.up),

        'r' => try self.changeSelectedState(.in_review),
        'p' => try self.changeSelectedState(.in_progress),
        't' => try self.changeSelectedState(.todo),
        'b' => try self.changeSelectedState(.blocked),
        'd' => try self.changeSelectedState(.done),
        'c' => try self.changeSelectedState(.cancelled),

        'i' => try self.clockIn(),
        'o' => try shared.clockOut(self.gpa, self.stmts, false),

        '{' => try self.changePriority(1),
        '}' => try self.changePriority(-1),

        13 => try self.createJournalEntry(true),
        'J' => try self.createJournalEntry(false),
        'h' => try self.showHistory(),

        else => {},
    }

    try self.fetch();

    return false;
}

pub fn run(self: *Self) !void {
    try self.fetch();

    while (true) {
        try self.draw();
        if (try self.update()) return;
    }
}

pub fn deinit(self: *const Self) !void {
    try std.os.tcsetattr(std.os.STDIN_FILENO, std.os.TCSA.NOW, self.original_terminal_settings);

    try self.stdout.writeAll("\x1b[?47l"); // Restore screen
    try self.stdout.writeAll("\x1b[u"); // Restore cursor pos
    try self.stdout.writeAll("\x1b[?25h"); // Make cursor visible
}

test "parseJournalContents invalid parses" {
    var allocator = std.testing.allocator;

    try std.testing.expectError(error.InvalidParse, parseJournalContents(allocator, "13:42:01", "foo"));
    try std.testing.expectError(error.InvalidParse, parseJournalContents(allocator, "13:42:01", "# foo"));
    try std.testing.expectError(error.InvalidParse, parseJournalContents(allocator, "13:42:01", "# 13:4"));
    try std.testing.expectError(error.InvalidParse, parseJournalContents(allocator, "13:42:01", "# 13:42:02"));
    try std.testing.expectError(error.InvalidParse, parseJournalContents(allocator, "13:42:01", "# 13:42:01"));
}

test "parseJournalContents valid parses" {
    var allocator = std.testing.allocator;

    var res = try parseJournalContents(allocator, "13:42:01", "# 13:42:01\nA");
    try std.testing.expectEqualStrings("A", res.contents);
    try std.testing.expectEqual(null, res.tags);

    res = try parseJournalContents(allocator, "13:42:01", "# 13:42:01\nFOO");
    try std.testing.expectEqualStrings("FOO", res.contents);
    try std.testing.expectEqual(null, res.tags);

    res = try parseJournalContents(allocator, "13:42:01", "# 13:42:01\nFOO\nBAR\nBAZ");
    try std.testing.expectEqualStrings("FOO\nBAR\nBAZ", res.contents);
    try std.testing.expectEqual(null, res.tags);

    res = try parseJournalContents(allocator, "13:42:01", "# 13:42:01 foo:\nCONTENT");
    try std.testing.expectEqualStrings("CONTENT", res.contents);
    try std.testing.expectEqual(null, res.tags);

    res = try parseJournalContents(allocator, "13:42:01", "# 13:42:01 :foo:\nCONTENT");
    try std.testing.expectEqualStrings("CONTENT", res.contents);
    try std.testing.expect(res.tags != null);
    try std.testing.expectEqual(@intCast(usize, 1), res.tags.?.len);
    try std.testing.expectEqualStrings("foo", res.tags.?[0]);
    allocator.free(res.tags.?);

    res = try parseJournalContents(allocator, "13:42:01", "# 13:42:01 :foo:bar:\nCONTENT");
    try std.testing.expectEqualStrings("CONTENT", res.contents);
    try std.testing.expect(res.tags != null);
    try std.testing.expectEqual(@intCast(usize, 2), res.tags.?.len);
    try std.testing.expectEqualStrings("foo", res.tags.?[0]);
    try std.testing.expectEqualStrings("bar", res.tags.?[1]);
    allocator.free(res.tags.?);
}
