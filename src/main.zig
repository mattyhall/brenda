const std = @import("std");
const sqlite = @import("sqlite");
const migrations = @import("migrations.zig");
const TabWriter = @import("TabWriter.zig");
const Db = @import("Db.zig");

pub const TodoState = enum {
    in_progress,
    in_review,
    new,
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
};

fn listTodos(allocator: std.mem.Allocator, db: *Db) !void {
    var query = try db.prepare("SELECT id, title, priority, state FROM todos ORDER BY state, priority ASC;");
    defer query.deinit();

    var tw = TabWriter.init(allocator, "|");
    defer tw.deinit();
    try tw.append("ID\tTitle\tPriority\tState\t");

    var it = try query.stmt.iterator(struct { id: i64, title: []const u8, priority: i64, state: i64 }, .{});
    while (try it.nextAlloc(allocator, .{})) |todo| {
        const state = std.meta.tagName(try std.meta.intToEnum(TodoState, todo.state));
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

fn newTodo(_: std.mem.Allocator, args: [][]const u8, db: *Db) !void {
    var name = args[0];
    var priority: i64 = 3;
    var state: []const u8 = "new";

    if (args.len > 1) {
        for (args[1..]) |arg| {
            const a = try Arg.parse(arg);
            if (std.mem.eql(u8, "priority", a.key)) {
                priority = std.fmt.parseInt(i64, a.value, 10) catch return error.CouldNotParseField;
            } else if (std.mem.eql(u8, "state", a.key)) {
                state = a.value;
            }
        }
    }

    const real_state = std.meta.stringToEnum(TodoState, state) orelse return error.CouldNotParseField;

    var stmt = try db.prepare("INSERT INTO todos(title, priority, state) VALUES(?, ?, ?)");
    defer stmt.deinit();

    try stmt.exec(.{}, .{ name, priority, @enumToInt(real_state) });
}

fn editTodo(gpa: std.mem.Allocator, args: [][]const u8, db: *Db) !void {
    var tid = std.fmt.parseInt(i64, args[0], 10) catch return error.CouldNotParseField;
    var stmt = try db.prepare("SELECT id, title, priority, state FROM todos WHERE id=? LIMIT 1");
    defer stmt.deinit();
    var todo = (try stmt.oneAlloc(Todo, gpa, .{}, .{tid})) orelse return error.NotFound;

    for (args[1..]) |arg| {
        const a = try Arg.parse(arg);
        if (std.mem.eql(u8, "title", a.key)) {
            todo.title = a.value;
        } else if (std.mem.eql(u8, "priority", a.key)) {
            todo.priority = std.fmt.parseInt(i64, a.value, 10) catch return error.CouldNotParseField;
        } else if (std.mem.eql(u8, "state", a.key)) {
            todo.state = std.meta.stringToEnum(TodoState, a.value) orelse return error.CouldNotParseField;
        }
    }

    var update_stmt = try db.prepare("UPDATE todos SET title = $title, priority = $priority, state = $state WHERE id = $id ;");
    defer update_stmt.deinit();

    try update_stmt.exec(.{}, todo);
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
    }
}
