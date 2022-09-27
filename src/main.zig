const std = @import("std");
const sqlite = @import("sqlite");
const migrations = @import("migrations.zig");
const Db = @import("Db.zig");
const Style = @import("Style.zig");

pub const TodoState = enum {
    in_progress,
    in_review,
    todo,
    blocked,
    done,
    cancelled,

    pub const BaseType = i64;

    pub fn bindField(self: TodoState, _: std.mem.Allocator) !BaseType {
        return @enumToInt(self);
    }

    pub fn readField(_: std.mem.Allocator, value: BaseType) !TodoState {
        return std.meta.intToEnum(TodoState, value);
    }
};

pub const Todo = struct {
    id: i64,
    title: []const u8,
    priority: i64,
    state: TodoState,
    tags: []const u8,
};

fn listTodos(allocator: std.mem.Allocator, db: *Db) !void {
    const q =
        \\SELECT a.id, title, priority, state, GROUP_CONCAT(c.val, ":") AS tags
        \\FROM todos a
        \\LEFT JOIN taggings b ON b.todo = a.id
        \\LEFT JOIN tags c ON c.id = b.tag
        \\GROUP BY a.id
        \\ORDER BY state ASC
    ;
    var query = try db.prepare(q);
    defer query.deinit();

    var al = std.ArrayList(u8).init(allocator);
    defer al.deinit();
    var al_unformatted = std.ArrayList(u8).init(allocator);
    defer al_unformatted.deinit();

    var winsz = std.mem.zeroes(std.os.system.winsize);
    _ = std.os.system.ioctl(std.os.system.STDOUT_FILENO, std.os.system.T.IOCGWINSZ, @ptrToInt(&winsz));
    std.log.debug("winsz: {}", .{winsz});

    var it = try query.stmt.iterator(Todo, .{});
    while (try it.nextAlloc(allocator, .{})) |todo| {
        try (Style{ .bold = true }).print(al.writer(), "{} ", .{todo.id});
        try al_unformatted.writer().print("{} ", .{todo.id});

        var state = try std.ascii.allocUpperString(allocator, std.meta.tagName(todo.state));
        defer allocator.free(state);
        try (Style{ .foreground = Style.green }).print(al.writer(), "{s} ", .{state});
        try al_unformatted.writer().print("{s} ", .{state});

        try (Style{}).print(al.writer(), "[P-{d}] ", .{todo.priority});
        try al_unformatted.writer().print("[P-{d}] ", .{todo.priority});

        const used = al_unformatted.items.len + todo.tags.len + 3;
        const title_space = if (used + todo.title.len > winsz.ws_col) todo.title.len else winsz.ws_col - used;
        try (Style{ .foreground = Style.pink }).print(al.writer(), "{s:^[1]}", .{ todo.title, title_space });

        if (todo.tags.len != 0) {
            try (Style{ .faint = true }).print(al.writer(), " :{s}:", .{todo.tags});
        } else {
            try al.append('\n');
        }
    }

    if (al.items.len == 0) return;

    var stdout = std.io.getStdOut();
    try stdout.writer().writeAll(al.items);
}

const Arg = struct {
    key: []const u8,
    value: []const u8,

    fn parse(arg: []const u8) !Arg {
        const index = std.mem.indexOf(u8, arg, ":") orelse return error.CouldNotParseField;
        if (index == arg.len - 1) return error.CouldNotParseField;
        const k = arg[0..index];
        const v = arg[index + 1 ..];
        return Arg{ .key = k, .value = v };
    }
};

fn getTag(db: *Db, tag: []const u8) !?i64 {
    var stmt = try db.prepare("SELECT id FROM tags WHERE val= ?");
    defer stmt.deinit();

    return try stmt.one(i64, .{}, .{tag});
}

fn addTagsToTodo(db: *Db, id: i64, tags: []const u8) !void {
    var taggings_insert_stmt = try db.prepare("INSERT INTO taggings(tag, todo) VALUES (?, ?);");
    defer taggings_insert_stmt.deinit();

    var tag_it = std.mem.split(u8, tags, ",");
    while (tag_it.next()) |tag| {
        const tag_id = (try getTag(db, tag)) orelse b: {
            var tag_insert_stmt = try db.prepare("INSERT INTO tags(val) VALUES (?) RETURNING id");
            defer tag_insert_stmt.deinit();

            const tag_id = (try tag_insert_stmt.one(i64, .{}, .{tag})) orelse return error.SqliteError;
            break :b tag_id;
        };

        try taggings_insert_stmt.exec(.{}, .{ tag_id, id });
        taggings_insert_stmt.stmt.reset();
    }
}

fn newTodo(_: std.mem.Allocator, args: [][]const u8, db: *Db) !void {
    var name = args[0];
    var priority: i64 = 3;
    var state: []const u8 = "todo";
    var tags: ?[]const u8 = null;

    if (args.len > 1) {
        for (args[1..]) |arg| {
            const a = try Arg.parse(arg);
            if (std.mem.eql(u8, "priority", a.key)) {
                priority = std.fmt.parseInt(i64, a.value, 10) catch return error.CouldNotParseField;
            } else if (std.mem.eql(u8, "state", a.key)) {
                state = a.value;
            } else if (std.mem.eql(u8, "tags", a.key)) {
                tags = a.value;
            }
        }
    }

    const real_state = std.meta.stringToEnum(TodoState, state) orelse return error.CouldNotParseField;

    var stmt = try db.prepare("INSERT INTO todos(title, priority, state) VALUES(?, ?, ?) RETURNING id");
    defer stmt.deinit();

    const id = (try stmt.one(i64, .{}, .{ name, priority, @enumToInt(real_state) })) orelse return error.SqliteError;
    if (tags) |tags_s| try addTagsToTodo(db, id, tags_s);
}

fn editTodo(gpa: std.mem.Allocator, args: [][]const u8, db: *Db) !void {
    var tid = std.fmt.parseInt(i64, args[0], 10) catch return error.CouldNotParseField;
    var stmt = try db.prepare("SELECT id, title, priority, state FROM todos WHERE id=? LIMIT 1");
    defer stmt.deinit();
    var todo = (try stmt.oneAlloc(struct { id: i64, title: []const u8, priority: i64, state: TodoState }, gpa, .{}, .{tid})) orelse return error.NotFound;

    var tags: ?[]const u8 = null;

    for (args[1..]) |arg| {
        const a = try Arg.parse(arg);
        if (std.mem.eql(u8, "title", a.key)) {
            todo.title = a.value;
        } else if (std.mem.eql(u8, "priority", a.key)) {
            todo.priority = std.fmt.parseInt(i64, a.value, 10) catch return error.CouldNotParseField;
        } else if (std.mem.eql(u8, "state", a.key)) {
            todo.state = std.meta.stringToEnum(TodoState, a.value) orelse return error.CouldNotParseField;
        } else if (std.mem.eql(u8, "tags", a.key)) {
            tags = a.value;
        }
    }

    var update_stmt = try db.prepare("UPDATE todos SET title = $title, priority = $priority, state = $state WHERE id = $id ;");
    defer update_stmt.deinit();

    try update_stmt.exec(.{}, .{ .title = todo.title, .priority = todo.priority, .state = todo.state, .id = todo.id });

    if (tags) |tags_s| try addTagsToTodo(db, todo.id, tags_s);
}

fn clockedInTodo(allocator: std.mem.Allocator, db: *Db) !?Todo {
    var stmt = try db.prepare(
        \\SELECT a.id, a.title, a.priority, a.state, "" as tags
        \\FROM todos a
        \\LEFT JOIN periods b ON b.todo = a.id
        \\WHERE b.end IS NULL
        \\LIMIT 1
    );
    defer stmt.deinit();

    return try stmt.oneAlloc(Todo, allocator, .{}, .{});
}

fn clockIn(gpa: std.mem.Allocator, arg: []const u8, db: *Db) !void {
    var tid = std.fmt.parseInt(i64, arg, 10) catch return error.CouldNotParseField;
    var stmt = try db.prepare("SELECT title FROM todos WHERE id=? LIMIT 1");
    defer stmt.deinit();
    var title = (try stmt.oneAlloc([]const u8, gpa, .{}, .{tid})) orelse return error.NotFound;

    if (try clockedInTodo(gpa, db)) |todo| {
        std.debug.print("Already clocked in to ", .{});
        try (Style{ .foreground = Style.pink }).print(std.io.getStdErr().writer(), "{s}", .{todo.title});
        std.debug.print(", clock out first\n", .{});
        return;
    }

    var insert_stmt = try db.prepare("INSERT INTO periods(todo, start) VALUES (?, strftime('%Y-%m-%dT%H:%M:%S'))");
    defer insert_stmt.deinit();

    try insert_stmt.exec(.{}, .{tid});

    var writer = std.io.getStdOut().writer();
    try writer.print("Clocking in to ", .{});
    try (Style{ .foreground = Style.pink }).print(writer, "{s}\n", .{title});
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    var db = try Db.init(allocator);
    defer db.deinit();

    _ = try migrations.run(&db);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        std.debug.print("Please pass some arguments\n", .{});
        std.process.exit(1);
    }

    if (std.mem.eql(u8, "todo", std.mem.span(args[1]))) {
        if (args.len < 3) {
            try listTodos(allocator, &db);
            return;
        }

        if (std.mem.eql(u8, "new", std.mem.span(args[2]))) {
            if (args.len < 4) {
                std.debug.print("Please pass a todo name\n", .{});
                std.process.exit(1);
            }

            const rest = args[3..];
            newTodo(allocator, rest, &db) catch |err| switch (err) {
                error.CouldNotParseField => {
                    std.debug.print("Could not parse field\n", .{});
                    std.process.exit(1);
                },
                else => return err,
            };
        } else if (std.mem.eql(u8, "edit", std.mem.span(args[2]))) {
            if (args.len < 4) {
                std.debug.print("Please pass a todo id\n", .{});
                std.process.exit(1);
            }

            const rest = args[3..];
            editTodo(allocator, rest, &db) catch |err| switch (err) {
                error.CouldNotParseField => {},
                else => return err,
            };
        }
    } else if (std.mem.eql(u8, "clock", std.mem.span(args[1]))) {
        if (args.len < 3) {
            std.debug.print("Please choose either 'in' or 'out'\n", .{});
            std.process.exit(1);
        }

        if (std.mem.eql(u8, "in", std.mem.span(args[2]))) {
            if (args.len != 4) {
                std.debug.print("Please pass a todo id\n", .{});
                std.process.exit(1);
            }

            try clockIn(allocator, args[3], &db);
        }
    }
}
