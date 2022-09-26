const std = @import("std");
const sqlite = @import("sqlite");

gpa: std.mem.Allocator,
db: sqlite.Db,
diags: sqlite.Diagnostics,

const Self = @This();

pub fn init(gpa: std.mem.Allocator) !Self {
    const data_dir = try std.fs.getAppDataDir(gpa, "brenda");
    defer gpa.free(data_dir);
    std.os.mkdir(data_dir, 0o774) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const db_path = try std.fs.path.joinZ(gpa, &.{ data_dir, "data.db" });
    defer gpa.free(db_path);

    return initWithOptions(gpa, .{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{ .write = true, .create = true },
        .threading_mode = .MultiThread,
    });
}

pub fn initWithOptions(gpa: std.mem.Allocator, opts: sqlite.InitOptions) !Self {
    return Self{ .gpa = gpa, .db = try sqlite.Db.init(opts), .diags = sqlite.Diagnostics{} };
}

pub fn deinit(self: *Self) void {
    self.db.deinit();
}

pub fn prepare(self: *Self, comptime q: []const u8) !b: {
    @setEvalBranchQuota(100000);
    break :b sqlite.StatementType(.{}, q);
} {
    var stmt = self.db.prepareWithDiags(q, .{ .diags = &self.diags }) catch |err| {
        std.log.err("got error {}: {s}", .{ err, self.diags });
        return err;
    };
    return stmt;
}
