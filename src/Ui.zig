const std = @import("std");
const Db = @import("Db.zig");
const shared = @import("shared.zig");

gpa: std.mem.Allocator,
stdout: std.fs.File,
db: *Db,

const Self = @This();

pub fn init(gpa: std.mem.Allocator, db: *Db) !Self {
    var stdout = std.io.getStdOut();
    try stdout.writeAll("\x1b[?47h"); // Save screen
    try stdout.writeAll("\x1b[s"); // Save cursor pos
    try stdout.writeAll("\x1b[?25l"); // Make cursor invisible
    return Self{ .gpa = gpa, .stdout = stdout, .db = db };
}

pub fn draw(self: *const Self) !void {
    var arena = std.heap.ArenaAllocator.init(self.gpa);
    defer arena.deinit();
    var allocator = arena.allocator();

    try self.stdout.writeAll("\x1b[2J"); // Erase entire screen
    try self.stdout.writeAll("\x1b[H"); // Move cursor to home

    const q =
        \\SELECT a.id, title, priority, state, GROUP_CONCAT(c.val, ":") AS tags
        \\FROM todos a
        \\LEFT JOIN taggings b ON b.todo = a.id
        \\LEFT JOIN tags c ON c.id = b.tag
        \\GROUP BY a.id
        \\ORDER BY state ASC
    ;
    var query = try self.db.prepare(q);
    defer query.deinit();

    var winsz = std.mem.zeroes(std.os.system.winsize);
    _ = std.os.system.ioctl(std.os.system.STDOUT_FILENO, std.os.system.T.IOCGWINSZ, @ptrToInt(&winsz));

    var it = try query.stmt.iterator(shared.Todo, .{});
    while (try it.nextAlloc(allocator, .{})) |todo| {
        try todo.write(allocator, self.stdout.writer(), winsz.ws_col);
    }
}

pub fn deinit(self: *const Self) !void {
    try self.stdout.writeAll("\x1b[?47l"); // Restore screen
    try self.stdout.writeAll("\x1b[u"); // Restore cursor pos
    try self.stdout.writeAll("\x1b[?25h"); // Make cursor visible
}
