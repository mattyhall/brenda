const std = @import("std");
const sqlite = @import("sqlite");
const Db = @import("Db.zig");

pub const CURRENT_VERSION = 3;

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
            \\CREATE TABLE todos (
            \\  id       INTEGER PRIMARY KEY,
            \\  title    TEXT              NOT NULL,
            \\  priority INTEGER DEFAULT 3 NOT NULL,
            \\  state    TEXT              NOT NULL
            \\);
            ,
            \\CREATE TABLE tags (
            \\  id  INTEGER PRIMARY KEY,
            \\  val TEXT        NOT NULL
            \\);
            ,
            \\CREATE TABLE taggings (
            \\  tag  INTEGER NOT NULL,
            \\  todo INTEGER,
            \\
            \\  FOREIGN KEY(tag)  REFERENCES tags(id)
            \\  FOREIGN KEY(todo) REFERENCES todos(id)
            \\);
            ,
            \\CREATE TABLE periods (
            \\  todo  INTEGER NOT NULL,
            \\  start TEXT    NOT NULL,
            \\  end   TEXT
            \\);
        },
    },
    .{
        .from = 1,
        .to = 2,
        .description = "journal entries",
        .ups = &.{
            \\CREATE TABLE journals (
            \\  id      INTEGER PRIMARY KEY,
            \\  todo    INTEGER,
            \\  created TEXT    NOT NULL,
            \\  entry   TEXT    NOT NULL,
            \\
            \\  FOREIGN KEY(todo) REFERENCES todos(id)
            \\);
        },
    },
    .{
        .from = 2,
        .to = 3,
        .description = "fts5 for journal entries",
        .ups = &.{
            \\CREATE VIRTUAL TABLE journals_fts USING fts5(
            \\  entry,
            \\  content = 'journals',
            \\  content_rowid = 'id',
            \\);
        },
    },
};

fn createVersionTable(db: *Db) !void {
    std.log.debug("creating version table", .{});

    var stmt = try db.prepare(CREATE_VERSION_TABLE);
    defer stmt.deinit();

    try stmt.exec(.{}, .{});
}

pub fn run(db: *Db) !bool {
    var version = b: {
        var version_query = db.prepare(VERSION_QUERY) catch {
            try createVersionTable(db);
            break :b 0;
        };
        defer version_query.deinit();

        const version = (try version_query.one(i64, .{}, .{})) orelse 0;
        break :b version;
    };

    std.log.debug("current db version is {}", .{version});

    var executed = false;

    inline for (migrations) |migration| {
        if (comptime migration.from >= version) {
            std.log.debug("running migration '{s}' ({}->{})", .{ migration.description, migration.from, migration.to });

            executed = true;

            inline for (migration.ups) |up| {
                var query = try db.prepare(up);
                defer query.deinit();

                try query.exec(.{}, .{});
            }
        }
    }

    if (executed) {
        inline for ([_][]const u8{ DELETE_VERSION_STMT, UPDATE_VERSION_STMT }) |s| {
            var stmt = try db.prepare(s);
            defer stmt.deinit();

            try stmt.exec(.{}, .{CURRENT_VERSION});
        }
    }

    return executed;
}
