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
    \\ORDER BY state ASC, priority ASC
;
const GET_CLOCKED_IN_TODO =
    \\SELECT a.id, a.title, a.priority, a.state, "" AS tags, 1 AS timed
    \\FROM todos a
    \\JOIN periods b ON b.todo = a.id
    \\WHERE b.end IS NULL
    \\LIMIT 1
;

const INSERT_TAG = "INSERT INTO tags(val) VALUES (?) RETURNING id";
const GET_TAG = "SELECT id FROM tags WHERE val=?";

const INSERT_TAGGING = "INSERT INTO taggings(tag, todo, journal) VALUES ($tag_id, $todo_id, $journal_id);";

const INSERT_PERIOD = "INSERT INTO periods(todo, start) VALUES (?, strftime('%Y-%m-%dT%H:%M:%S'))";
const CLOCK_OUT = "UPDATE periods SET end = strftime('%Y-%m-%dT%H:%M:%S') WHERE todo = ? AND end IS NULL";

const TOTAL_TIME =
    \\SELECT 24*60*60*SUM(JULIANDAY(p.end) - JULIANDAY(p.start)) as diff
    \\FROM periods p
    \\WHERE
    \\  DATE(p.start) > strftime('%Y-%m-%dT%H:%M:%S', datetime('now', 'weekday 0', 'start of day', '-7 days')) AND
    \\  DATE(p.start) <= strftime('%Y-%m-%dT%H:%M:%S', datetime('now'))
;
const TODO_TIME =
    \\SELECT t.id, t.title, 24*60*60*SUM(JULIANDAY(p.end) - JULIANDAY(p.start)) as diff
    \\FROM todos t
    \\LEFT JOIN periods p ON p.todo = t.id
    \\WHERE
    \\  DATE(p.start) > strftime('%Y-%m-%dT%H:%M:%S', datetime('now', 'weekday 0', 'start of day', '-7 days')) AND
    \\  DATE(p.start) <= strftime('%Y-%m-%dT%H:%M:%S', datetime('now'))
    \\GROUP BY t.id HAVING diff IS NOT NULL
    \\ORDER BY diff DESC
;
const TAG_TIME =
    \\SELECT g.val, 24*60*60*SUM(JULIANDAY(p.end) - JULIANDAY(p.start)) as diff
    \\FROM periods p
    \\JOIN todos t ON t.id = p.todo 
    \\LEFT JOIN taggings i ON i.todo = t.id
    \\LEFT JOIN tags g ON g.id = i.tag
    \\WHERE
    \\  DATE(p.start) > strftime('%Y-%m-%dT%H:%M:%S', datetime('now', 'weekday 0', 'start of day', '-7 days')) AND
    \\  DATE(p.start) <= strftime('%Y-%m-%dT%H:%M:%S', datetime('now'))
    \\GROUP BY g.val HAVING g.val IS NOT NULL
    \\ORDER BY diff DESC
;

const INSERT_JOURNAL_ENTRY =
    \\INSERT INTO journals (todo, created, entry)
    \\VALUES (?, strftime('%Y-%m-%dT%H:%M:%S', datetime('now')), "")
    \\RETURNING id, time(created)
;
const UPDATE_JOURNAL_ENTRY = "UPDATE journals SET entry = ? WHERE id = ?";
const DELETE_JOURNAL_ENTRY = "DELETE FROM journals WHERE id = ?";
const LIST_JOURNAL_ENTRIES =
    \\SELECT j.id, entry, created, date(created) as dt, time(created) as tm, GROUP_CONCAT(b.val, ":") AS tags, c.title
    \\FROM journals j
    \\LEFT JOIN taggings t ON t.journal = j.id
    \\LEFT JOIN tags b ON b.id = t.tag
    \\LEFT JOIN todos c ON j.todo = c.id
    \\GROUP BY j.id
    \\ORDER BY dt DESC, created ASC
;
const LIST_JOURNAL_ENTRIES_FOR_TODO =
    \\SELECT j.id, entry, created, date(created) as dt, time(created) as tm, GROUP_CONCAT(b.val, ":") AS tags, NULL as title
    \\FROM journals j
    \\LEFT JOIN taggings t ON t.journal = j.id
    \\LEFT JOIN tags b ON b.id = t.tag
    \\WHERE j.todo = ?
    \\GROUP BY j.id
    \\ORDER BY dt DESC, created ASC
;

const GET_LINKS =
    \\SELECT l.shortcode, l.variable, s.format_string
    \\FROM links l
    \\JOIN link_shortcodes s ON s.shortcode = l.shortcode
    \\WHERE l.todo=?
;
const INSERT_LINK_SHORTCODE = "INSERT INTO link_shortcodes(shortcode, format_string) VALUES(?, ?)";
const INSERT_LINK = "INSERT INTO links(todo, shortcode, variable) VALUES (?, ?, ?)";

insert_todo: Db.StatementWrapper(INSERT_TODO),
update_todo: Db.StatementWrapper(UPDATE_TODO),
get_todo: Db.StatementWrapper(GET_TODO),
list_todos: Db.StatementWrapper(LIST_TODOS),
get_clocked_in_todo: Db.StatementWrapper(GET_CLOCKED_IN_TODO),

insert_tag: Db.StatementWrapper(INSERT_TAG),
get_tag: Db.StatementWrapper(GET_TAG),

insert_tagging: Db.StatementWrapper(INSERT_TAGGING),

insert_period: Db.StatementWrapper(INSERT_PERIOD),
clock_out: Db.StatementWrapper(CLOCK_OUT),

total_time: Db.StatementWrapper(TOTAL_TIME),
todo_time: Db.StatementWrapper(TODO_TIME),
tag_time: Db.StatementWrapper(TAG_TIME),

insert_journal_entry: Db.StatementWrapper(INSERT_JOURNAL_ENTRY),
update_journal_entry: Db.StatementWrapper(UPDATE_JOURNAL_ENTRY),
delete_journal_entry: Db.StatementWrapper(DELETE_JOURNAL_ENTRY),
list_journal_entries: Db.StatementWrapper(LIST_JOURNAL_ENTRIES),
list_journal_entries_for_todo: Db.StatementWrapper(LIST_JOURNAL_ENTRIES_FOR_TODO),

get_links: Db.StatementWrapper(GET_LINKS),
insert_link_shortcode: Db.StatementWrapper(INSERT_LINK_SHORTCODE),
insert_link: Db.StatementWrapper(INSERT_LINK),

const Self = @This();

pub fn init(db: *Db) !Self {
    return Self{
        .insert_todo = try db.prepare(INSERT_TODO),
        .update_todo = try db.prepare(UPDATE_TODO),
        .get_todo = try db.prepare(GET_TODO),
        .list_todos = try db.prepare(LIST_TODOS),
        .get_clocked_in_todo = try db.prepare(GET_CLOCKED_IN_TODO),

        .insert_tag = try db.prepare(INSERT_TAG),
        .get_tag = try db.prepare(GET_TAG),

        .insert_tagging = try db.prepare(INSERT_TAGGING),

        .insert_period = try db.prepare(INSERT_PERIOD),
        .clock_out = try db.prepare(CLOCK_OUT),

        .total_time = try db.prepare(TOTAL_TIME),
        .todo_time = try db.prepare(TODO_TIME),
        .tag_time = try db.prepare(TAG_TIME),

        .insert_journal_entry = try db.prepare(INSERT_JOURNAL_ENTRY),
        .update_journal_entry = try db.prepare(UPDATE_JOURNAL_ENTRY),
        .delete_journal_entry = try db.prepare(DELETE_JOURNAL_ENTRY),
        .list_journal_entries = try db.prepare(LIST_JOURNAL_ENTRIES),
        .list_journal_entries_for_todo = try db.prepare(LIST_JOURNAL_ENTRIES_FOR_TODO),

        .get_links = try db.prepare(GET_LINKS),
        .insert_link_shortcode = try db.prepare(INSERT_LINK_SHORTCODE),
        .insert_link = try db.prepare(INSERT_LINK),
    };
}

pub fn deinit(self: *Self) void {
    self.insert_todo.deinit();
    self.update_todo.deinit();
    self.list_todos.deinit();
    self.get_todo.deinit();
    self.get_clocked_in_todo.deinit();

    self.insert_tag.deinit();
    self.get_tag.deinit();

    self.insert_tagging.deinit();
    self.clock_out.deinit();

    self.total_time.deinit();
    self.todo_time.deinit();
    self.tag_time.deinit();

    self.insert_journal_entry.deinit();
    self.update_journal_entry.deinit();
    self.delete_journal_entry.deinit();
    self.list_journal_entries.deinit();
    self.list_journal_entries_for_todo.deinit();

    self.get_links.deinit();
    self.insert_link_shortcode.deinit();
    self.insert_link.deinit();
}
