const std = @import("std");
const sqlite = @import("sqlite");
const Db = @import("Db.zig");
const Style = @import("Style.zig");
const Statements = @import("Statements.zig");

const dead_style = Style{ .foreground = Style.grey, .faint = true };
const selected_dead_style = Style{ .foreground = Style.white, .background = Style.grey, .faint = true };

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

    pub fn dead(self: TodoState) bool {
        return switch (self) {
            .done, .cancelled => true,
            else => false,
        };
    }

    pub fn style(self: TodoState, selected: bool) Style {
        const bg = if (selected) Style.grey else Style.black;
        return switch (self) {
            .in_progress => .{ .foreground = Style.blue, .background = bg },
            .in_review => .{ .foreground = Style.pink, .background = bg },
            .todo => .{ .foreground = Style.green, .background = bg },
            .blocked => .{ .foreground = Style.red, .background = bg },
            .done => if (selected) selected_dead_style else dead_style,
            .cancelled => if (selected) selected_dead_style else dead_style,
        };
    }
};

pub const Link = struct {
    shortcode: []const u8,
    variable: []const u8,
    format_string: []const u8,
};

pub const Todo = struct {
    id: i64,
    title: []const u8,
    priority: i64,
    state: TodoState,
    tags: []const u8,
    timed: bool,

    const Self = @This();

    fn background(_: *const Self, selected: bool) Style.Colour {
        return if (selected) Style.grey else Style.black;
    }

    fn style_if_dead(_: *const Self, selected: bool) Style {
        return if (selected) selected_dead_style else dead_style;
    }

    pub fn title_style(self: *const Self, selected: bool) Style {
        if (self.state.dead()) return self.style_if_dead(selected);

        return .{ .foreground = Style.pink, .background = self.background(selected) };
    }

    pub fn id_style(self: *const Self, selected: bool) Style {
        if (self.state.dead()) return self.style_if_dead(selected);

        return .{ .bold = true, .background = self.background(selected) };
    }

    pub fn priority_style(self: *const Self, selected: bool) Style {
        if (self.state.dead()) return self.style_if_dead(selected);

        return .{ .background = self.background(selected) };
    }

    pub fn tag_style(self: *const Self, selected: bool) Style {
        if (self.state.dead()) return self.style_if_dead(selected);

        return .{ .faint = true, .background = self.background(selected) };
    }

    pub fn write(self: *const Self, allocator: std.mem.Allocator, writer: anytype, cols: usize, selected: bool) !void {
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

        // For the space and the leading and trailing colon
        const tag_extra_length: usize = if (self.tags.len != 0) 3 else 0;
        const used = al_unformatted.items.len + self.tags.len + tag_extra_length;
        if (used + self.title.len > cols) {
            try (Style{ .foreground = Style.pink }).print(writer, "{s}", .{self.title});
            return;
        }

        const title_space = cols - used;

        var al = std.ArrayList(u8).init(allocator);
        defer al.deinit();

        try (self.id_style(selected)).print(writer, "{} ", .{self.id});
        if (self.timed) try self.priority_style(selected).print(writer, "⏰ ", .{});
        try (self.state.style(selected)).print(writer, "{s} ", .{state});
        try (self.priority_style(selected)).print(writer, "[P-{d}] ", .{self.priority});
        try (self.title_style(selected)).print(writer, "{s:^[1]}", .{ self.title, title_space });

        if (self.tags.len != 0) {
            try (self.tag_style(selected)).print(writer, " :{s}:", .{self.tags});
        } else {
            try al.append('\n');
        }
    }
};

pub fn clockedInTodo(allocator: std.mem.Allocator, stmts: *Statements) !?Todo {
    return try stmts.get_clocked_in_todo.oneAlloc(Todo, allocator, .{}, .{});
}

pub fn clockOut(allocator: std.mem.Allocator, stmts: *Statements, print: bool) !void {
    var writer = std.io.getStdOut().writer();

    const todo = (try clockedInTodo(allocator, stmts)) orelse {
        if (print) try writer.writeAll("Not clocked in\n");
        return;
    };

    try stmts.clock_out.exec(.{}, .{todo.id});

    if (!print) return;

    try writer.print("Clocking out of ", .{});
    try (Style{ .foreground = Style.pink }).print(writer, "{s}\n", .{todo.title});
}
