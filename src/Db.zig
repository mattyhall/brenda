const std = @import("std");
const sqlite = @import("sqlite");

gpa: std.mem.Allocator,
db: sqlite.Db,
diags: sqlite.Diagnostics,

const Self = @This();

pub fn StatementWrapper(comptime q: []const u8) type {
    const T = b: {
        @setEvalBranchQuota(100000);
        break :b sqlite.StatementType(.{}, q);
    };

    return struct {
        diags: sqlite.Diagnostics,
        stmt: T,

        const Wrapper = @This();

        pub fn exec(self: *Wrapper, opts: sqlite.QueryOptions, values: anytype) !void {
            defer self.stmt.reset();

            var custom_opts = opts;
            custom_opts.diags = &self.diags;
            self.stmt.exec(custom_opts, values) catch |err| {
                std.log.err("got error {}: {s}", .{ err, self.diags });
                return err;
            };
        }

        pub fn one(
            self: *Wrapper,
            comptime Type: type,
            opts: sqlite.QueryOptions,
            values: anytype,
        ) !?Type {
            defer self.stmt.reset();

            var custom_opts = opts;
            custom_opts.diags = &self.diags;
            return self.stmt.one(Type, custom_opts, values) catch |err| {
                std.log.err("got error {}: {s}", .{ err, self.diags });
                return err;
            };
        }

        pub fn oneAlloc(
            self: *Wrapper,
            comptime Type: type,
            allocator: std.mem.Allocator,
            opts: sqlite.QueryOptions,
            values: anytype,
        ) !?Type {
            defer self.stmt.reset();

            var custom_opts = opts;
            custom_opts.diags = &self.diags;
            return self.stmt.oneAlloc(Type, allocator, custom_opts, values) catch |err| {
                std.log.err("got error {}: {s}", .{ err, self.diags });
                return err;
            };
        }

        pub fn all(
            self: *Wrapper,
            comptime Type: type,
            allocator: std.mem.Allocator,
            opts: sqlite.QueryOptions,
            values: anytype,
        ) ![]Type {
            defer self.stmt.reset();

            var custom_opts = opts;
            custom_opts.diags = &self.diags;
            return self.stmt.all(Type, allocator, custom_opts, values) catch |err| {
                std.log.err("got error {}: {s}", .{ err, self.diags });
                return err;
            };
        }

        pub fn deinit(self: *Wrapper) void {
            self.stmt.deinit();
        }
    };
}

pub fn getDataDir(gpa: std.mem.Allocator) ![]const u8 {
    if (std.os.getenv("BRENDA_PATH")) |path| return path;

    const data_dir = try std.fs.getAppDataDir(gpa, "brenda");
    errdefer gpa.free(data_dir);
    std.os.mkdir(data_dir, 0o774) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    return data_dir;
}

fn getDatabasePath(gpa: std.mem.Allocator) ![:0]const u8 {
    const data_dir = try getDataDir(gpa);
    return try std.fs.path.joinZ(gpa, &.{ data_dir, "data.db" });
}

pub fn init(gpa: std.mem.Allocator) !Self {
    var db_path = try getDatabasePath(gpa);
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

pub fn prepare(self: *Self, comptime q: []const u8) !StatementWrapper(q) {
    const Wrapper = StatementWrapper(q);

    const stmt = self.db.prepareWithDiags(q, .{ .diags = &self.diags }) catch |err| {
        std.log.err("got error {}: {s}", .{ err, self.diags });
        return err;
    };

    return Wrapper{ .diags = sqlite.Diagnostics{}, .stmt = stmt };
}
