const std = @import("std");
const sqlite = @import("sqlite");

pub const CURRENT_VERSION = 1;

const CREATE_VERSION_TABLE =
    \\ CREATE TABLE _version(
    \\   version INTEGER NOT NULL
    \\ );
;

const VERSION_QUERY = "SELECT version FROM _version LIMIT 1";
const DELETE_VERSION_STMT = "DELETE FROM _version WHERE version != ?;";
const UPDATE_VERSION_STMT = "INSERT INTO _version(version) VALUES (?);";

pub const Migration = struct {
    from: i64,
    to: i64,
    description: []const u8,
    ups: []const []const u8,
};

const migrations: [CURRENT_VERSION]Migration = [_]Migration{
    .{
        .from = 0,
        .to = 1,
        .description = "initial tables (todos)",
        .ups = &.{
            \\ CREATE TABLE todos (
            \\   id       PRIMARY KEY       NOT NULL,
            \\   title    TEXT              NOT NULL,
            \\   priority INTEGER DEFAULT 3 NOT NULL,
            \\   state    TEXT              NOT NULL
            \\ );
            ,
            \\ CREATE TABLE tags (
            \\   id  PRIMARY KEY NOT NULL,
            \\   val TEXT        NOT NULL
            \\ );
            ,
            \\ CREATE TABLE taggings (
            \\   tag  INTEGER NOT NULL,
            \\   todo INTEGER,
            \\
            \\   FOREIGN KEY(tag)  REFERENCES tags(id)
            \\   FOREIGN KEY(todo) REFERENCES todos(id)
            \\ );
            ,
            \\ CREATE TABLE periods (
            \\   todo  INTEGER NOT NULL,
            \\   start TEXT    NOT NULL,
            \\   end   TEXT    NOT NULL
            \\ );
        },
    },
};

fn createVersionTable(db: *sqlite.Db) !void {
    std.log.debug("creating version table", .{});

    var diags = sqlite.Diagnostics{};
    var stmt = db.prepareWithDiags(CREATE_VERSION_TABLE, .{ .diags = &diags }) catch |err| {
        std.log.err("got error {}: {s}", .{ err, diags });
        return err;
    };
    defer stmt.deinit();

    stmt.exec(.{ .diags = &diags }, .{}) catch |err| {
        std.log.err("got error {}: {s}", .{ err, diags });
        return err;
    };
}

pub fn run(db: *sqlite.Db) !bool {
    var diags = sqlite.Diagnostics{};
    var version = b: {
        var version_query = db.prepareWithDiags(VERSION_QUERY, .{ .diags = &diags }) catch |err| {
            if (std.mem.startsWith(u8, "no such table", diags.message)) {
                try createVersionTable(db);
                break :b 0;
            }

            std.log.err("got error {}: {s}", .{ err, diags });
            return err;
        };
        defer version_query.deinit();

        const version = version_query.one(i64, .{ .diags = &diags }, .{}) catch |err| {
            std.log.err("got error {}: {s}", .{ err, diags });
            return err;
        } orelse 0;

        break :b version;
    };

    std.log.debug("current db version is {}", .{version});

    var executed = false;

    for (migrations) |migration| {
        if (migration.to <= version) continue;

        std.log.debug("running migration '{s}' ({}->{})", .{ migration.description, migration.from, migration.to });

        executed = true;

        for (migration.ups) |up| {
            var query = db.prepareDynamicWithDiags(up, .{ .diags = &diags }) catch |err| {
                std.log.err("got error {}: {s}", .{ err, diags });
                return err;
            };
            defer query.deinit();

            query.exec(.{ .diags = &diags }, .{}) catch |err| {
                std.log.err("got error {}: {s}", .{ err, diags });
                return err;
            };
        }
    }

    if (executed) {
        inline for ([_][]const u8{DELETE_VERSION_STMT, UPDATE_VERSION_STMT}) |s| {
            var stmt = db.prepareDynamicWithDiags(s, .{ .diags = &diags }) catch |err| {
                std.log.err("got error {}: {s}", .{ err, diags });
                return err;
            };
            defer stmt.deinit();

            stmt.exec(.{ .diags = &diags }, .{CURRENT_VERSION}) catch |err| {
                std.log.err("got error {}: {s}", .{ err, diags });
                return err;
            };
        }
    }

    return executed;
}
