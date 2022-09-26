const std = @import("std");
const sqlite = @import("sqlite");
const migrations = @import("migrations.zig");
const TabWriter = @import("TabWriter.zig");
const Db = @import("Db.zig");

pub const TodoState = enum {
    new,
    in_progress,
    in_review,
    blocked,
    done,
    cancelled,
};

fn listTodos(allocator: std.mem.Allocator, db: *Db) !void {
    var query = try db.prepare("SELECT id, title, priority, state FROM todos ORDER BY priority ASC;");
    defer query.deinit();

    var tw = TabWriter.init(allocator, "|");
    defer tw.deinit();
    try tw.append("ID\tTitle\tPriority\tState\t");

    var it = try query.iterator(struct { id: i64, title: []const u8, priority: i64, state: i64 }, .{});
    while (try it.nextAlloc(allocator, .{})) |todo| {
        const state = std.meta.tagName(@intToEnum(TodoState, todo.state));
        try tw.append(try std.fmt.allocPrint(
            allocator,
            "{}\t{s}\t{}\t{s}\t",
            .{ todo.id, todo.title, todo.priority, state },
        ));
    }

    if (tw.strings.items.len > 1) {
        const stdout = std.io.getStdOut();
        try tw.writeTo(stdout.writer());
    }
}

fn newTodo(_: std.mem.Allocator, args: [][]const u8, db: *Db) !void {
    var name = args[0];
    var priority: i64 = 3;
    var state: []const u8 = "new";

    if (args.len > 1) {
        for (args[1..]) |arg| {
            const index = std.mem.indexOf(u8, arg, ":") orelse return error.CouldNotParseField;
            if (index == arg.len - 1) return error.CouldNotParseField;
            const k = arg[0..index];
            const v = arg[index + 1 ..];
            if (std.mem.eql(u8, "priority", k)) {
                priority = std.fmt.parseInt(i64, v, 10) catch return error.CouldNotParseField;
            } else if (std.mem.eql(u8, "state", k)) {
                state = v;
            }
        }
    }

    const real_state = std.meta.stringToEnum(TodoState, state) orelse return error.CouldNotParseField;

    var stmt = try db.prepare("INSERT INTO todos(title, priority, state) VALUES(?, ?, ?)");
    defer stmt.deinit();

    try stmt.exec(.{}, .{ name, priority, @enumToInt(real_state) });
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
                error.CouldNotParseField => {},
                else => return err,
            };
        }
    }
}
