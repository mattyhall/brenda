foreground: Colour = .{ .r = 255, .g = 255, .b = 255 },
background: Colour = .{ .r = 0, .g = 0, .b = 0 },
bold: bool = false,
faint: bool = false,
italic: bool = false,

const Self = @This();

pub const black = Colour{ .r = 0, .g = 0, .b = 0 };
pub const grey = Colour{ .r = 68, .g = 71, .b = 90 };
pub const pink = Colour{ .r = 255, .g = 121, .b = 198 };
pub const white = Colour{ .r = 255, .g = 255, .b = 255 };
pub const green = Colour{ .r = 80, .g = 250, .b = 123 };
pub const red = Colour{ .r = 255, .g = 85, .b = 85 };
pub const blue = Colour{ .r = 139, .g = 233, .b = 253 };

pub const Colour = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn eql(a: Colour, b: Colour) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b;
    }
};

fn colour(writer: anytype, c: Colour) !void {
    try writer.print("2;{};{};{}m", .{ c.r, c.g, c.b });
}

pub fn start(self: Self, writer: anytype) !void {
    if (!self.foreground.eql(white)) {
        _ = try writer.write("\x1b[38;");
        try colour(writer, self.foreground);
    }
    if (!self.background.eql(Colour{ .r = 0, .g = 0, .b = 0 })) {
        _ = try writer.write("\x1b[48;");
        try colour(writer, self.background);
    }

    if (self.bold)
        _ = try writer.write("\x1b[1m");
    if (self.faint)
        _ = try writer.write("\x1b[2m");
    if (self.italic)
        _ = try writer.write("\x1b[3m");
}

pub fn end(_: Self, writer: anytype) !void {
    _ = try writer.write("\x1b[0m");
}

pub fn print(self: Self, writer: anytype, comptime format: []const u8, args: anytype) !void {
    try self.start(writer);
    try writer.print(format, args);
    try self.end(writer);
}
