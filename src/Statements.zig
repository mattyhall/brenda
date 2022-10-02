const Db = @import("Db.zig");

const INSERT_TODO = "INSERT INTO todos(title, priority, state) VALUES(?, ?, ?) RETURNING id";
const UPDATE_TODO = "UPDATE todos SET title = $title, priority = $priority, state = $state WHERE id = $id";
const GET_TODO =
    \\SELECT a.id, title, priority, state, GROUP_CONCAT(c.val, ":") AS tags, d.start is NOT NULL AS timed
    \\FROM todos a
    \\LEFT JOIN taggings b ON b.todo = a.id
    \\LEFT JOIN tags c ON c.id = b.tag
    \\LEFT JOIN periods d ON d.todo = a.id AND (d.start IS NOT NULL AND d.end IS NULL)
    \\WHERE a.id = ?
    \\GROUP BY a.id
    \\LIMIT 1
;
const LIST_TODOS =
    \\SELECT a.id, title, priority, state, GROUP_CONCAT(c.val, ":") AS tags, d.start is NOT NULL AS timed
    \\FROM todos a
    \\LEFT JOIN taggings b ON b.todo = a.id
    \\LEFT JOIN tags c ON c.id = b.tag
    \\LEFT JOIN periods d ON d.todo = a.id AND (d.start IS NOT NULL AND d.end IS NULL)
    \\GROUP BY a.id
    \\ORDER BY state ASC
;

const INSERT_TAG = "INSERT INTO tags(val) VALUES (?) RETURNING id";
const GET_TAG = "SELECT id FROM tags WHERE val=?";

const INSERT_TAGGING = "INSERT INTO taggings(tag, todo) VALUES (?, ?);";

const INSERT_PERIOD = "INSERT INTO periods(todo, start) VALUES (?, strftime('%Y-%m-%dT%H:%M:%S'))";
const CLOCK_OUT = "UPDATE periods SET end = strftime('%Y-%m-%dT%H:%M:%S') WHERE todo = ? AND end IS NULL";

const TOTAL_TIME =
    \\SELECT 24*60*60*SUM(JULIANDAY(p.end) - JULIANDAY(p.start)) as diff
    \\FROM periods p
    \\WHERE p.start BETWEEN datetime('now', 'weekday 1', '-7 days') AND datetime('now')
;
const TODO_TIME =
    \\SELECT t.id, t.title, 24*60*60*SUM(JULIANDAY(p.end) - JULIANDAY(p.start)) as diff
    \\FROM todos t
    \\LEFT JOIN periods p ON p.todo = t.id
    \\WHERE p.start IS NULL OR p.start BETWEEN datetime('now', 'weekday 1', '-7 days') AND datetime('now')
    \\GROUP BY t.id
    \\ORDER BY diff DESC
;
const TAG_TIME =
    \\SELECT g.val, 24*60*60*SUM(JULIANDAY(p.end) - JULIANDAY(p.start)) as diff
    \\FROM periods p
    \\JOIN todos t ON t.id = p.todo 
    \\LEFT JOIN taggings i ON i.todo = t.id
    \\LEFT JOIN tags g ON g.id = i.tag
    \\WHERE p.start BETWEEN datetime('now', 'weekday 1', '-7 days') AND datetime('now')
    \\GROUP BY g.val
    \\ORDER BY diff DESC
;

insert_todo: Db.StatementWrapper(INSERT_TODO),
update_todo: Db.StatementWrapper(UPDATE_TODO),
get_todo: Db.StatementWrapper(GET_TODO),
list_todos: Db.StatementWrapper(LIST_TODOS),

insert_tag: Db.StatementWrapper(INSERT_TAG),
get_tag: Db.StatementWrapper(GET_TAG),

insert_tagging: Db.StatementWrapper(INSERT_TAGGING),

insert_period: Db.StatementWrapper(INSERT_PERIOD),
clock_out: Db.StatementWrapper(CLOCK_OUT),

total_time: Db.StatementWrapper(TOTAL_TIME),
todo_time: Db.StatementWrapper(TODO_TIME),
tag_time: Db.StatementWrapper(TAG_TIME),

const Self = @This();

pub fn init(db: *Db) !Self {
    return Self{
        .insert_todo = try db.prepare(INSERT_TODO),
        .update_todo = try db.prepare(UPDATE_TODO),
        .get_todo = try db.prepare(GET_TODO),
        .list_todos = try db.prepare(LIST_TODOS),

        .insert_tag = try db.prepare(INSERT_TAG),
        .get_tag = try db.prepare(GET_TAG),

        .insert_tagging = try db.prepare(INSERT_TAGGING),

        .insert_period = try db.prepare(INSERT_PERIOD),
        .clock_out = try db.prepare(CLOCK_OUT),

        .total_time = try db.prepare(TOTAL_TIME),
        .todo_time = try db.prepare(TODO_TIME),
        .tag_time = try db.prepare(TAG_TIME),
    };
}

pub fn deinit(self: *Self) void {
    self.insert_todo.deinit();
    self.update_todo.deinit();
    self.list_todos.deinit();
    self.get_todo.deinit();

    self.insert_tag.deinit();
    self.get_tag.deinit();

    self.insert_tagging.deinit();
    self.clock_out.deinit();

    self.total_time.deinit();
    self.todo_time.deinit();
    self.tag_time.deinit();
}