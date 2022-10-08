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
        if (selected_index < ws.ws_row/2) {
            self.offset = 0;
            return;
        }

        const offset = selected_index - ws.ws_row/2;
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

        else => {
            std.log.debug("unrecognised input {d}", .{buf[0]});
            return true;
        },
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
