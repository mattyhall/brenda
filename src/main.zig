const std = @import("std");
const sqlite = @import("sqlite");
const migrations = @import("migrations.zig");
const Db = @import("Db.zig");
const Statements = @import("Statements.zig");
const Style = @import("Style.zig");
const Ui = @import("Ui.zig");
const shared = @import("shared.zig");
const term = @import("terminal.zig");

fn listTodos(allocator: std.mem.Allocator, stmts: *Statements) !void {
    var stdout = std.io.getStdOut();

    var winsz = std.mem.zeroes(term.winsize);
    _ = std.os.system.ioctl(std.os.system.STDOUT_FILENO, term.TIOCGWINSZ, @ptrToInt(&winsz));

    var it = try stmts.list_todos.stmt.iterator(shared.Todo, .{});
    while (try it.nextAlloc(allocator, .{})) |todo| {
        try todo.write(allocator, stdout.writer(), winsz.ws_col);
    }
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

fn addTagsToTodo(stmts: *Statements, id: i64, tags: []const u8) !void {
    var tag_it = std.mem.split(u8, tags, ",");
    while (tag_it.next()) |tag| {
        const tag_id = (try stmts.get_tag.one(i64, .{}, .{tag})) orelse b: {
            const tag_id = (try stmts.insert_tag.one(i64, .{}, .{tag})) orelse return error.SqliteError;
            break :b tag_id;
        };

        try stmts.insert_tagging.exec(.{}, .{ tag_id, id });
    }
}

fn newTodo(args: [][]const u8, stmts: *Statements) !void {
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

    const real_state = std.meta.stringToEnum(shared.TodoState, state) orelse return error.CouldNotParseField;

    const id = (try stmts.insert_todo.one(i64, .{}, .{ name, priority, @enumToInt(real_state) })) orelse return error.SqliteError;
    if (tags) |tags_s| try addTagsToTodo(stmts, id, tags_s);
}

fn editTodo(gpa: std.mem.Allocator, args: [][]const u8, stmts: *Statements) !void {
    var tid = std.fmt.parseInt(i64, args[0], 10) catch return error.CouldNotParseField;
    var todo = (try stmts.get_todo.oneAlloc(shared.Todo, gpa, .{}, .{tid})) orelse return error.NotFound;

    var tags: ?[]const u8 = null;

    for (args[1..]) |arg| {
        const a = try Arg.parse(arg);
        if (std.mem.eql(u8, "title", a.key)) {
            todo.title = a.value;
        } else if (std.mem.eql(u8, "priority", a.key)) {
            todo.priority = std.fmt.parseInt(i64, a.value, 10) catch return error.CouldNotParseField;
        } else if (std.mem.eql(u8, "state", a.key)) {
            todo.state = std.meta.stringToEnum(shared.TodoState, a.value) orelse return error.CouldNotParseField;
        } else if (std.mem.eql(u8, "tags", a.key)) {
            tags = a.value;
        }
    }

    try stmts.update_todo.exec(.{}, .{ .title = todo.title, .priority = todo.priority, .state = todo.state, .id = todo.id });

    if (tags) |tags_s| try addTagsToTodo(stmts, todo.id, tags_s);
}

fn clockIn(gpa: std.mem.Allocator, arg: []const u8, stmts: *Statements) !void {
    var tid = std.fmt.parseInt(i64, arg, 10) catch return error.CouldNotParseField;
    var in_todo = (try stmts.get_todo.oneAlloc(shared.Todo, gpa, .{}, .{tid})) orelse return error.NotFound;

    if (try shared.clockedInTodo(gpa, stmts)) |todo| {
        std.debug.print("Already clocked in to ", .{});
        try (Style{ .bold = true }).print(std.io.getStdErr().writer(), "{} ", .{todo.id});
        try (Style{ .foreground = Style.pink }).print(std.io.getStdErr().writer(), "{s}", .{todo.title});
        std.debug.print(", clock out first\n", .{});
        return;
    }

    try stmts.insert_period.exec(.{}, .{tid});

    var writer = std.io.getStdOut().writer();
    try writer.print("Clocking in to ", .{});
    try (Style{ .foreground = Style.pink }).print(writer, "{s}\n", .{in_todo.title});
}

fn clockOut(gpa: std.mem.Allocator, stmts: *Statements) !void {
    const todo = (try shared.clockedInTodo(gpa, stmts)) orelse {
        std.debug.print("Not clocked in\n", .{});
        return;
    };

    try stmts.clock_out.exec(.{}, .{todo.id});

    var writer = std.io.getStdOut().writer();
    try writer.print("Clocking out of ", .{});
    try (Style{ .foreground = Style.pink }).print(writer, "{s}\n", .{todo.title});
}

fn printDuration(writer: anytype, diff: f32) !void {
    if (diff == 0) {
        try writer.writeAll("none");
        return;
    }

    var h = false;

    var d = diff;
    if (d >= 60 * 60) {
        const hrs = d / (60 * 60);
        try writer.print("{} hrs ", .{@floatToInt(i64, hrs)});
        d -= 60 * 60 * hrs;
        h = true;
    }

    if (d >= 60) {
        const mins = d / 60;
        if (h) try writer.writeAll(" ");
        try writer.print("{} mins", .{@floatToInt(i64, mins)});
        return;
    } else if (h) return;

    try writer.print("{} secs", .{@floatToInt(i64, d)});
}

fn report(gpa: std.mem.Allocator, stmts: *Statements) !void {
    var writer = std.io.getStdOut().writer();

    const total = (try stmts.total_time.one(f32, .{}, .{})) orelse {
        try writer.writeAll("Nothing logged this week\n");
        return;
    };

    try (Style{ .bold = true, .foreground = Style.blue }).print(writer, "Todos\n", .{});

    {
        var it = try stmts.todo_time.stmt.iterator(struct { id: i64, title: []const u8, diff: f32 }, .{});
        while (try it.nextAlloc(gpa, .{})) |todo| {
            try (Style{ .bold = true }).print(writer, "{} ", .{todo.id});
            try (Style{ .foreground = Style.pink }).print(writer, "{s} ", .{todo.title});
            try printDuration(writer, todo.diff);
            try writer.print(" {d:.1}%\n", .{todo.diff / total * 100});
        }
    }

    try (Style{ .bold = true, .foreground = Style.blue }).print(writer, "\nTags\n", .{});

    {
        var it = try stmts.tag_time.stmt.iterator(struct { val: []const u8, diff: f32 }, .{});
        while (try it.nextAlloc(gpa, .{})) |tag| {
            try (Style{ .faint = true }).print(writer, ":{s}: ", .{tag.val});
            try printDuration(writer, tag.diff);
            try writer.print(" {d:.1}%\n", .{tag.diff / total * 100});
        }
    }

    try (Style{ .bold = true, .foreground = Style.blue }).print(writer, "\nTotal\n", .{});
    try printDuration(writer, total);
    try writer.writeAll("logged this week\n");
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    var db = try Db.init(allocator);
    defer db.deinit();

    _ = try migrations.run(&db);

    var stmts = try Statements.init(&db);
    defer stmts.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        var ui = try Ui.init(allocator, &stmts);
        defer ui.deinit() catch {};

        try ui.run();
        return;
    }

    if (std.mem.eql(u8, "todo", std.mem.span(args[1]))) {
        if (args.len < 3) {
            try listTodos(allocator, &stmts);
            return;
        }

        if (std.mem.eql(u8, "new", std.mem.span(args[2]))) {
            if (args.len < 4) {
                std.debug.print("Please pass a todo name\n", .{});
                std.process.exit(1);
            }

            const rest = args[3..];
            newTodo(rest, &stmts) catch |err| switch (err) {
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
            editTodo(allocator, rest, &stmts) catch |err| switch (err) {
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

            try clockIn(allocator, args[3], &stmts);
        } else if (std.mem.eql(u8, "out", std.mem.span(args[2]))) {
            if (args.len != 3) {
                std.debug.print("No arguments are needed to clock out", .{});
                std.process.exit(1);
            }

            try shared.clockOut(allocator, &stmts, true);
        }
    } else if (std.mem.eql(u8, "report", std.mem.span(args[1]))) {
        try report(allocator, &stmts);
    }
}
