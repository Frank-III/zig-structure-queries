const std = @import("std");
const sqlite = @import("sqlite");
const simple_query = @import("simple_query.zig");

pub const Database = struct {
    db: sqlite.Db,
    allocator: std.mem.Allocator,

    pub const TransactionMode = enum {
        deferred,
        immediate,
        exclusive,
    };

    pub const Transaction = struct {
        db: *Database,
        finished: bool = false,

        pub fn deinit(self: *Transaction) void {
            if (self.finished) return;
            self.db.execute("ROLLBACK") catch {};
            self.finished = true;
        }

        pub fn execute(self: *Transaction, sql: []const u8) !void {
            if (self.finished) return error.TransactionAlreadyClosed;
            try self.db.execute(sql);
        }

        pub fn executeWith(self: *Transaction, sql: []const u8, params: anytype) !void {
            if (self.finished) return error.TransactionAlreadyClosed;
            var stmt = try self.db.prepare(sql);
            defer stmt.deinit();
            try stmt.bind(params);
        }

        pub fn prepare(self: *Transaction, sql: []const u8) !Statement {
            if (self.finished) return error.TransactionAlreadyClosed;
            return self.db.prepare(sql);
        }

        pub fn prepareQuery(self: *Transaction, query: *simple_query.QueryBuilder) !Statement {
            if (self.finished) return error.TransactionAlreadyClosed;
            return self.db.prepareQuery(query);
        }

        pub fn queryOne(self: *Transaction, comptime T: type, sql: []const u8, params: anytype) !?T {
            if (self.finished) return error.TransactionAlreadyClosed;
            var stmt = try self.db.prepare(sql);
            defer stmt.deinit();
            return stmt.one(T, params);
        }

        pub fn queryAll(self: *Transaction, comptime T: type, sql: []const u8, params: anytype) ![]T {
            if (self.finished) return error.TransactionAlreadyClosed;
            var stmt = try self.db.prepare(sql);
            defer stmt.deinit();
            return stmt.all(T, params);
        }

        pub fn commit(self: *Transaction) !void {
            if (self.finished) return error.TransactionAlreadyClosed;
            try self.db.execute("COMMIT");
            self.finished = true;
        }

        pub fn rollback(self: *Transaction) !void {
            if (self.finished) return error.TransactionAlreadyClosed;
            try self.db.execute("ROLLBACK");
            self.finished = true;
        }
    };

    pub fn init(allocator: std.mem.Allocator, path: [:0]const u8) !Database {
        const db = try sqlite.Db.init(.{
            .mode = if (std.mem.eql(u8, path, ":memory:")) sqlite.Db.Mode{ .Memory = {} } else sqlite.Db.Mode{ .File = path },
            .open_flags = .{
                .write = true,
                .create = true,
            },
        });

        return Database{
            .db = db,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Database) void {
        self.db.deinit();
    }

    pub fn execute(self: *Database, sql: []const u8) !void {
        try self.db.execDynamic(sql, .{}, .{});
    }

    pub fn executeWith(self: *Database, sql: []const u8, params: anytype) !void {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        try stmt.bind(params);
    }

    pub fn begin(self: *Database) !Transaction {
        return self.beginWithMode(.deferred);
    }

    pub fn beginWithMode(self: *Database, mode: TransactionMode) !Transaction {
        const begin_sql = switch (mode) {
            .deferred => "BEGIN",
            .immediate => "BEGIN IMMEDIATE",
            .exclusive => "BEGIN EXCLUSIVE",
        };

        try self.execute(begin_sql);
        return .{ .db = self };
    }

    pub fn executeQuery(self: *Database, query: *simple_query.QueryBuilder) !void {
        const sql = try query.toSql(self.allocator);
        defer self.allocator.free(sql);
        try self.execute(sql);
    }

    pub fn prepare(self: *Database, sql: []const u8) !Statement {
        const stmt = try self.db.prepareDynamic(sql);
        return Statement{
            .stmt = stmt,
            .allocator = self.allocator,
        };
    }

    pub fn queryOne(self: *Database, comptime T: type, sql: []const u8, params: anytype) !?T {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        return stmt.one(T, params);
    }

    pub fn queryAll(self: *Database, comptime T: type, sql: []const u8, params: anytype) ![]T {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        return stmt.all(T, params);
    }

    pub fn prepareQuery(self: *Database, query: *simple_query.QueryBuilder) !Statement {
        const sql = try query.toSql(self.allocator);
        defer self.allocator.free(sql);
        return try self.prepare(sql);
    }

    pub fn createTable(self: *Database, comptime T: type) !void {
        const sql = comptime generateCreateTableSql(T);
        try self.execute(sql);
    }
};

pub const Statement = struct {
    stmt: sqlite.DynamicStatement,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Statement) void {
        self.stmt.deinit();
    }

    pub fn exec(self: *Statement) !void {
        try self.stmt.exec(.{}, .{});
    }

    pub fn bind(self: *Statement, params: anytype) !void {
        try self.stmt.exec(.{}, params);
    }

    pub fn one(self: *Statement, comptime T: type, params: anytype) !?T {
        // zig-sqlite's non-Alloc APIs cannot populate pointer/slice fields.
        // Use the Alloc variant so callers can use `[]const u8` etc.
        return try self.stmt.oneAlloc(T, self.allocator, .{}, params);
    }

    pub fn all(self: *Statement, comptime T: type, params: anytype) ![]T {
        return try self.stmt.all(T, self.allocator, .{}, params);
    }
};

fn generateCreateTableSql(comptime T: type) []const u8 {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("Expected struct type");
    }

    var sql: []const u8 = "CREATE TABLE IF NOT EXISTS " ++ @typeName(T) ++ " (";
    var first = true;

    inline for (info.@"struct".fields) |field| {
        if (!first) sql = sql ++ ", ";
        first = false;

        sql = sql ++ field.name ++ " ";
        sql = sql ++ sqliteTypeForZigType(field.type);

        if (std.mem.eql(u8, field.name, "id")) {
            sql = sql ++ " PRIMARY KEY";
        }
    }

    sql = sql ++ ")";
    return sql;
}

fn sqliteTypeForZigType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => |int| if (int.signedness == .signed) "INTEGER" else "INTEGER",
        .float => "REAL",
        .bool => "INTEGER",
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .array => |arr| if (arr.child == u8) "TEXT" else @compileError("Unsupported array type"),
            else => if (ptr.child == u8) "TEXT" else @compileError("Unsupported pointer type"),
        },
        .optional => |opt| sqliteTypeForZigType(opt.child),
        else => @compileError("Unsupported type for SQLite: " ++ @typeName(T)),
    };
}

pub const Row = struct {
    allocator: std.mem.Allocator,
    columns: []Column,
    values: []Value,

    pub const Column = struct {
        name: []const u8,
        type: ColumnType,
    };

    pub const ColumnType = enum {
        integer,
        real,
        text,
        blob,
        null,
    };

    pub const Value = union(ColumnType) {
        integer: i64,
        real: f64,
        text: []const u8,
        blob: []const u8,
        null: void,
    };

    pub fn deinit(self: *Row) void {
        for (self.values) |value| {
            switch (value) {
                .text => |s| self.allocator.free(s),
                .blob => |b| self.allocator.free(b),
                else => {},
            }
        }
        self.allocator.free(self.columns);
        self.allocator.free(self.values);
    }

    pub fn getValue(self: Row, column_name: []const u8) ?Value {
        for (self.columns, 0..) |col, i| {
            if (std.mem.eql(u8, col.name, column_name)) {
                return self.values[i];
            }
        }
        return null;
    }

    pub fn getInt(self: Row, column_name: []const u8) ?i64 {
        if (self.getValue(column_name)) |val| {
            switch (val) {
                .integer => |i| return i,
                else => return null,
            }
        }
        return null;
    }

    pub fn getFloat(self: Row, column_name: []const u8) ?f64 {
        if (self.getValue(column_name)) |val| {
            switch (val) {
                .real => |f| return f,
                else => return null,
            }
        }
        return null;
    }

    pub fn getText(self: Row, column_name: []const u8) ?[]const u8 {
        if (self.getValue(column_name)) |val| {
            switch (val) {
                .text => |t| return t,
                else => return null,
            }
        }
        return null;
    }
};

const SeedDocument = struct {
    title: []const u8,
    body: []const u8,
    category: []const u8,
    published: i32,
};

const FtsSearchRow = struct {
    id: i64,
    title: []const u8,
    category: []const u8,
    rank: f64,
    highlighted_title: []const u8,
};

fn freeFtsSearchRows(allocator: std.mem.Allocator, rows: []FtsSearchRow) void {
    for (rows) |row| {
        allocator.free(row.title);
        allocator.free(row.category);
        allocator.free(row.highlighted_title);
    }
    allocator.free(rows);
}

fn seedFtsDocuments(db: *Database) !bool {
    const docs: [5]SeedDocument = .{
        .{
            .title = "Zig parser techniques",
            .body = "Build a Pratt parser in Zig and keep the grammar explicit.",
            .category = "engineering",
            .published = 1,
        },
        .{
            .title = "SQLite full text search",
            .body = "Use FTS5 MATCH queries and bm25 ranking for fast search.",
            .category = "database",
            .published = 1,
        },
        .{
            .title = "Draft parser notes",
            .body = "Unpublished zig parser draft for internal review.",
            .category = "engineering",
            .published = 0,
        },
        .{
            .title = "Building CLI tools in Zig",
            .body = "Command-line tooling with clear error handling and tests.",
            .category = "engineering",
            .published = 1,
        },
        .{
            .title = "Rust parser comparison",
            .body = "Compare parser ergonomics across Rust projects.",
            .category = "engineering",
            .published = 1,
        },
    };

    var tx = try db.beginWithMode(.immediate);
    defer tx.deinit();

    var fts_available = false;

    const CompileOptionRow = struct {
        enabled: i32,
    };

    try tx.execute(
        \\CREATE TABLE docs (
        \\  id INTEGER PRIMARY KEY,
        \\  title TEXT NOT NULL,
        \\  body TEXT NOT NULL,
        \\  category TEXT NOT NULL,
        \\  published INTEGER NOT NULL
        \\)
    );

    var option_stmt = try tx.prepare("SELECT sqlite_compileoption_used('ENABLE_FTS5') AS enabled");
    defer option_stmt.deinit();

    const compile_option = (try option_stmt.one(CompileOptionRow, .{})) orelse return error.TestUnexpectedNull;
    fts_available = compile_option.enabled == 1;

    if (fts_available) {
        try tx.execute(
            \\CREATE VIRTUAL TABLE docs_fts USING fts5(
            \\  title,
            \\  body,
            \\  content='docs',
            \\  content_rowid='id'
            \\)
        );
    }

    for (docs) |doc| {
        var insert_stmt = try tx.prepare(
            "INSERT INTO docs (title, body, category, published) VALUES (?, ?, ?, ?)"
        );
        defer insert_stmt.deinit();

        try insert_stmt.bind(.{ doc.title, doc.body, doc.category, doc.published });
    }

    if (fts_available) {
        // Rebuild the linked FTS index after seeding content rows.
        try tx.execute("INSERT INTO docs_fts(docs_fts) VALUES('rebuild')");
    }
    try tx.commit();

    return fts_available;
}

test "database basic operations" {
    var db = try Database.init(std.testing.allocator, ":memory:");
    defer db.deinit();

    try db.execute(
        \\CREATE TABLE users (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  age INTEGER
        \\)
    );

    try db.execute("INSERT INTO users (name, age) VALUES ('Alice', 30)");
    try db.execute("INSERT INTO users (name, age) VALUES ('Bob', 25)");

    var stmt = try db.prepare("SELECT * FROM users WHERE age > ?");
    defer stmt.deinit();

    const User = struct {
        id: i32,
        name: []const u8,
        age: ?i32,
    };

    const users = try stmt.all(User, .{20});
    defer {
        for (users) |user| {
            std.testing.allocator.free(user.name);
        }
        std.testing.allocator.free(users);
    }

    try std.testing.expect(users.len == 2);
}

test "query builder integration" {
    var db = try Database.init(std.testing.allocator, ":memory:");
    defer db.deinit();

    try db.execute(
        \\CREATE TABLE customers (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL
        \\)
    );

    try db.execute(
        \\CREATE TABLE orders (
        \\  id INTEGER PRIMARY KEY,
        \\  customer_id INTEGER,
        \\  order_date TEXT,
        \\  status TEXT
        \\)
    );

    try db.execute("INSERT INTO customers (name) VALUES ('Alice')");
    try db.execute("INSERT INTO orders (customer_id, order_date, status) VALUES (1, '2024-01-01', 'completed')");

    var query = simple_query.QueryBuilder.init(std.testing.allocator);
    defer query.deinit();
    query.from_table = "orders";
    query.from_alias = "o";

    try query.select_fields.append(std.testing.allocator, .{ .expression = "c.name", .alias = "customer_name" });
    try query.select_fields.append(std.testing.allocator, .{ .expression = "o.order_date", .alias = null });
    try query.joins.append(std.testing.allocator, .{
        .join_type = "INNER JOIN",
        .table = "customers",
        .alias = "c",
        .on_condition = "o.customer_id = c.id",
    });
    try query.where_conditions.append(std.testing.allocator, .{ .condition = "o.status = 'completed'" });

    const sql = try query.toSql();
    defer std.testing.allocator.free(sql);

    var stmt = try db.prepare(sql);
    defer stmt.deinit();

    const Result = struct {
        customer_name: []const u8,
        order_date: []const u8,
    };

    const results = try stmt.all(Result, .{});
    defer {
        for (results) |row| {
            std.testing.allocator.free(row.customer_name);
            std.testing.allocator.free(row.order_date);
        }
        std.testing.allocator.free(results);
    }

    try std.testing.expect(results.len == 1);
    try std.testing.expectEqualStrings(results[0].customer_name, "Alice");
}

test "transaction commit and rollback behavior" {
    var db = try Database.init(std.testing.allocator, ":memory:");
    defer db.deinit();

    try db.execute(
        \\CREATE TABLE ledger (
        \\  id INTEGER PRIMARY KEY,
        \\  note TEXT NOT NULL
        \\)
    );

    {
        var tx = try db.beginWithMode(.immediate);
        defer tx.deinit();

        try tx.execute("INSERT INTO ledger (note) VALUES ('committed row')");
        try tx.commit();
    }

    {
        var tx = try db.begin();
        defer tx.deinit();

        try tx.execute("INSERT INTO ledger (note) VALUES ('rolled back row')");
        // No commit: defer tx.deinit() should rollback automatically.
    }

    var stmt = try db.prepare("SELECT COUNT(*) AS total FROM ledger");
    defer stmt.deinit();

    const CountRow = struct { total: i64 };
    const count_row = (try stmt.one(CountRow, .{})) orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(i64, 1), count_row.total);
}

test "transaction closed-state guard" {
    var db = try Database.init(std.testing.allocator, ":memory:");
    defer db.deinit();

    var tx = try db.begin();
    defer tx.deinit();

    try tx.commit();
    try std.testing.expectError(error.TransactionAlreadyClosed, tx.execute("SELECT 1"));
    try std.testing.expectError(error.TransactionAlreadyClosed, tx.commit());
}

test "database typed runtime query helpers" {
    var db = try Database.init(std.testing.allocator, ":memory:");
    defer db.deinit();

    try db.execute(
        \\CREATE TABLE events (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  severity INTEGER NOT NULL
        \\)
    );

    try db.executeWith(
        "INSERT INTO events (name, severity) VALUES (?, ?)",
        .{ "disk warning", @as(i32, 2) },
    );
    try db.executeWith(
        "INSERT INTO events (name, severity) VALUES (?, ?)",
        .{ "cpu critical", @as(i32, 5) },
    );

    const Event = struct {
        id: i64,
        name: []const u8,
        severity: i32,
    };

    const one = (try db.queryOne(Event, "SELECT id, name, severity FROM events WHERE severity >= ? ORDER BY severity DESC LIMIT 1", .{@as(i32, 4)})) orelse return error.TestUnexpectedNull;
    defer std.testing.allocator.free(one.name);
    try std.testing.expectEqualStrings("cpu critical", one.name);

    const rows = try db.queryAll(Event, "SELECT id, name, severity FROM events WHERE severity >= ? ORDER BY id ASC", .{@as(i32, 2)});
    defer {
        for (rows) |row| std.testing.allocator.free(row.name);
        std.testing.allocator.free(rows);
    }
    try std.testing.expectEqual(@as(usize, 2), rows.len);
}

test "transaction typed runtime query helpers" {
    var db = try Database.init(std.testing.allocator, ":memory:");
    defer db.deinit();

    try db.execute(
        \\CREATE TABLE notes (
        \\  id INTEGER PRIMARY KEY,
        \\  body TEXT NOT NULL
        \\)
    );

    {
        var tx = try db.beginWithMode(.immediate);
        defer tx.deinit();

        try tx.executeWith("INSERT INTO notes (body) VALUES (?)", .{"first"});
        try tx.executeWith("INSERT INTO notes (body) VALUES (?)", .{"second"});

        const Note = struct {
            id: i64,
            body: []const u8,
        };

        const items = try tx.queryAll(Note, "SELECT id, body FROM notes ORDER BY id ASC", .{});
        defer {
            for (items) |item| std.testing.allocator.free(item.body);
            std.testing.allocator.free(items);
        }
        try std.testing.expectEqual(@as(usize, 2), items.len);

        try tx.commit();
    }

    const CountRow = struct { total: i64 };
    const count = (try db.queryOne(CountRow, "SELECT COUNT(*) AS total FROM notes", .{})) orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(i64, 2), count.total);
}

test "sqlite runtime raw SQL with FTS5 seeded data" {
    var db = try Database.init(std.testing.allocator, ":memory:");
    defer db.deinit();

    const fts_available = try seedFtsDocuments(&db);

    var count_stmt = try db.prepare("SELECT COUNT(*) AS total FROM docs WHERE published = @published");
    defer count_stmt.deinit();

    const CountRow = struct { total: i64 };
    const published_count = (try count_stmt.one(CountRow, .{ .published = @as(i32, 1) })) orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(i64, 4), published_count.total);

    const search_sql = if (fts_available)
        \\SELECT
        \\  d.id,
        \\  d.title,
        \\  d.category,
        \\  bm25(docs_fts) AS rank,
        \\  highlight(docs_fts, 0, '[', ']') AS highlighted_title
        \\FROM docs_fts
        \\JOIN docs d ON d.id = docs_fts.rowid
        \\WHERE docs_fts MATCH ?
        \\  AND d.published = ?
        \\ORDER BY rank ASC
        \\LIMIT ?
    else
        \\SELECT
        \\  d.id,
        \\  d.title,
        \\  d.category,
        \\  0.0 AS rank,
        \\  d.title AS highlighted_title
        \\FROM docs d
        \\WHERE (d.title LIKE '%' || ? || '%' OR d.body LIKE '%' || ? || '%')
        \\  AND (d.title LIKE '%' || ? || '%' OR d.body LIKE '%' || ? || '%')
        \\  AND d.published = ?
        \\ORDER BY d.id ASC
        \\LIMIT ?
    ;

    var search_stmt = try db.prepare(search_sql);
    defer search_stmt.deinit();

    const rows = if (fts_available)
        try search_stmt.all(FtsSearchRow, .{ "zig parser", @as(i32, 1), @as(i32, 10) })
    else
        try search_stmt.all(FtsSearchRow, .{ "zig", "zig", "parser", "parser", @as(i32, 1), @as(i32, 10) });
    defer freeFtsSearchRows(std.testing.allocator, rows);

    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(@as(i64, 1), rows[0].id);
    try std.testing.expectEqualStrings("Zig parser techniques", rows[0].title);
    try std.testing.expectEqualStrings("engineering", rows[0].category);
    if (fts_available) {
        try std.testing.expect(std.mem.indexOf(u8, rows[0].highlighted_title, "[") != null);
    } else {
        try std.testing.expectEqualStrings(rows[0].title, rows[0].highlighted_title);
    }

    // bm25 ranks should be finite numeric values.
    try std.testing.expect(!std.math.isNan(rows[0].rank));
}
