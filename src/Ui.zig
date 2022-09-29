const std = @import("std");
const Db = @import("Db.zig");
const shared = @import("shared.zig");
const term = @import("terminal.zig");

gpa: std.mem.Allocator,
stdout: std.fs.File,
db: *Db,
original_terminal_settings: std.os.termios,

const Self = @This();

pub fn init(gpa: std.mem.Allocator, db: *Db) !Self {
    var stdout = std.io.getStdOut();
    var self = Self{ .gpa = gpa, .stdout = stdout, .db = db, .original_terminal_settings = undefined };
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

    var winsz = std.mem.zeroes(term.winsize);
    _ = std.os.system.ioctl(std.os.system.STDOUT_FILENO, term.TIOCGWINSZ, @ptrToInt(&winsz));

    var it = try query.stmt.iterator(shared.Todo, .{});
    while (try it.nextAlloc(allocator, .{})) |todo| {
        try todo.write(allocator, self.stdout.writer(), winsz.ws_col);
    }
}

fn update(_: *Self) !bool {
    var stdin = std.io.getStdIn();
    var buf: [1]u8 = undefined;
    _ = try stdin.read(&buf);

    switch (buf[0]) {
        'q' => return true,
        else => {},
    }

    return false;
}

pub fn run(self: *Self) !void {
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
