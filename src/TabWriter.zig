const std = @import("std");

gpa: std.mem.Allocator,

column_delim: []const u8,
column_sizes: std.ArrayListUnmanaged(usize),
strings: std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)),

const Self = @This();

pub fn init(allocator: std.mem.Allocator, column_delim: []const u8) Self {
    return .{
        .gpa = allocator,
        .column_sizes = .{},
        .strings = .{},
        .column_delim = column_delim,
    };
}

pub fn append(self: *Self, s: []const u8) !void {
    var line_it = std.mem.split(u8, s, "\n");
    while (line_it.next()) |line| {
        var columns = std.ArrayListUnmanaged([]const u8){};
        var column_it = std.mem.split(u8, line, "\t");
        var col: usize = 0;
        while (column_it.next()) |column| {
            if (col >= self.column_sizes.items.len) try self.column_sizes.append(self.gpa, 0);
            if (column.len > self.column_sizes.items[col]) self.column_sizes.items[col] = column.len;

            try columns.append(self.gpa, column);
            col += 1;
        }
        try self.strings.append(self.gpa, columns);
    }
}

pub fn writeTo(self: *const Self, writer: anytype) !void {
    for (self.strings.items) |line, row| {
        for (line.items) |column, col| {
            const sep = if (col < line.items.len - 1) " " else "";
            try writer.print("{s}{s}{s:<[3]}{[1]s}", .{ self.column_delim, sep, column, self.column_sizes.items[col] });
        }
        if (row < line.items.len - 1) try writer.print("\n", .{});
    }
}

pub fn deinit(self: *Self) void {
    for (self.strings.items) |*s| {
        s.deinit(self.gpa);
    }
    self.strings.deinit(self.gpa);

    self.column_sizes.deinit(self.gpa);
}

test "TabWriter table" {
    var allocator = std.testing.allocator;

    var tw = init(allocator, "|");
    defer tw.deinit();

    try tw.append("Player\tNickname\tWorld titles\t");
    try tw.append("Ronnie O'Sullivan\tThe Rocket\t7\t");
    try tw.append("Judd Trump\tThe Ace in the Pack\t1\t");
    try tw.append("Mark Selby\tThe Jester from Leicester\t4\t");

    var al = std.ArrayList(u8).init(allocator);
    defer al.deinit();
    try tw.writeTo(al.writer());

    const expected =
        \\| Player            | Nickname                  | World titles |
        \\| Ronnie O'Sullivan | The Rocket                | 7            |
        \\| Judd Trump        | The Ace in the Pack       | 1            |
        \\| Mark Selby        | The Jester from Leicester | 4            |
    ;

    try std.testing.expectEqualStrings(expected, al.items);
}
