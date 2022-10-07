const std = @import("std");
const Db = @import("Db.zig");
const shared = @import("shared.zig");
const term = @import("terminal.zig");
const Statements = @import("Statements.zig");

gpa: std.mem.Allocator,
stdout: std.fs.File,
original_terminal_settings: std.os.termios = undefined,
todos: []shared.Todo = &[0]shared.Todo{},
stmts: *Statements,
arena: std.heap.ArenaAllocator,

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

pub fn draw(self: *Self) !void {
    try self.stdout.writeAll("\x1b[2J"); // Erase entire screen
    try self.stdout.writeAll("\x1b[H"); // Move cursor to home


    var winsz = std.mem.zeroes(term.winsize);
    _ = std.os.system.ioctl(std.os.system.STDOUT_FILENO, term.TIOCGWINSZ, @ptrToInt(&winsz));

    for (self.todos) |todo| {
        try todo.write(self.arena.allocator(), self.stdout.writer(), winsz.ws_col);
    }
}

fn fetch(self: *Self) !void {
    self.arena.deinit();
    self.arena = std.heap.ArenaAllocator.init(self.gpa);
    self.todos = try self.stmts.list_todos.all(shared.Todo, self.arena.allocator(), .{}, .{});
}

fn update(self: *Self) !bool {
    var stdin = std.io.getStdIn();
    var buf: [1]u8 = undefined;
    _ = try stdin.read(&buf);

    switch (buf[0]) {
        'q' => return true,
        'o' => try shared.clockOut(self.gpa, self.stmts, false),
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
