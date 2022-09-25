const std = @import("std");
const sqlite = @import("sqlite");
const migrations = @import("migrations.zig");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    const data_dir = try std.fs.getAppDataDir(allocator, "brenda");
    defer allocator.free(data_dir);
    std.os.mkdir(data_dir, 0o774) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err
    };

    const db_path = try std.fs.path.joinZ(allocator, &.{ data_dir, "data.db" });
    defer allocator.free(db_path);

    std.log.debug("Opening '{s}'", .{db_path});

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{ .write = true, .create = true },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    _ = try migrations.run(&db);
}
