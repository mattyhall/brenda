const std = @import("std");
const sqlite = @import("sqlite");
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
    timed: bool,

    const Self = @This();

    pub fn write(self: *const Self, allocator: std.mem.Allocator, writer: anytype, cols: usize) !void {
        var state = try std.ascii.allocUpperString(allocator, std.meta.tagName(self.state));
        defer allocator.free(state);

        var al_unformatted = std.ArrayList(u8).init(allocator);
        defer al_unformatted.deinit();

        try al_unformatted.writer().print("{} ", .{self.id});

        if (self.title.len + al_unformatted.items.len > cols) return error.NotEnoughSpace;

        // We're guessing here the emojis are two chars. I'm not sure how correct that is
        if (self.timed) try al_unformatted.writer().writeAll("   ");
        try al_unformatted.writer().print("{s} ", .{state});
        try al_unformatted.writer().print("[P-{d}] ", .{self.priority});

        const used = al_unformatted.items.len + self.tags.len + 3;
        if (used + self.title.len > cols) {
            try (Style{ .foreground = Style.pink }).print(writer, "{s}", .{self.title});
            return;
        }

        const title_space = cols - used;

        var al = std.ArrayList(u8).init(allocator);
        defer al.deinit();

        try (Style{ .bold = true }).print(writer, "{} ", .{self.id});
        if (self.timed) try writer.writeAll("⏰ ");
        try (Style{ .foreground = Style.green }).print(writer, "{s} ", .{state});
        try (Style{}).print(writer, "[P-{d}] ", .{self.priority});
        try (Style{ .foreground = Style.pink }).print(writer, "{s:^[1]}", .{ self.title, title_space });

        if (self.tags.len != 0) {
            try (Style{ .faint = true }).print(writer, " :{s}:", .{self.tags});
        } else {
            try al.append('\n');
        }
    }
};
