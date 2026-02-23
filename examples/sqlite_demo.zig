const std = @import("std");
const sqlite = @import("sqlite");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("SQLite Integration Demo\n", .{});
    std.debug.print("=======================\n\n", .{});

    // Initialize database in memory
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .Memory = {} },
        .open_flags = .{
            .write = true,
            .create = true,
        },
    });
    defer db.deinit();

    // Create a table
    try db.exec(
        \\CREATE TABLE users (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    name TEXT NOT NULL,
        \\    email TEXT UNIQUE NOT NULL,
        \\    age INTEGER
        \\)
    , .{}, .{});

    std.debug.print("✓ Created users table\n", .{});

    // Insert some data
    try db.exec(
        \\INSERT INTO users (name, email, age) VALUES
        \\    ('Alice Johnson', 'alice@example.com', 30),
        \\    ('Bob Smith', 'bob@example.com', 25),
        \\    ('Charlie Brown', 'charlie@example.com', 35)
    , .{}, .{});

    std.debug.print("✓ Inserted 3 users\n\n", .{});

    // Query data with prepared statement
    const query = "SELECT id, name, email, age FROM users WHERE age > ?";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const User = struct {
        id: i32,
        name: []const u8,
        email: []const u8,
        age: ?i32,
    };

    std.debug.print("Users older than 26:\n", .{});
    std.debug.print("--------------------\n", .{});

    var iter = try stmt.iteratorAlloc(User, allocator, .{26});
    while (try iter.nextAlloc(allocator, .{})) |user| {
        const age = user.age orelse 0;
        std.debug.print("  #{}: {s} ({s}) - age {}\n", .{
            user.id,
            user.name,
            user.email,
            age,
        });
    }

    // Test dynamic SQL generation
    std.debug.print("\n", .{});
    std.debug.print("Dynamic SQL Test\n", .{});
    std.debug.print("----------------\n", .{});

    // Build a dynamic query

    const table_name = "users";
    const columns = [_][]const u8{ "name", "email" };
    const where_clause = "age >= 30";

    var query_parts = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer query_parts.deinit(allocator);

    try query_parts.append(allocator, "SELECT");
    for (columns, 0..) |col, i| {
        if (i > 0) try query_parts.append(allocator, ",");
        try query_parts.append(allocator, col);
    }
    try query_parts.append(allocator, "FROM");
    try query_parts.append(allocator, table_name);
    try query_parts.append(allocator, "WHERE");
    try query_parts.append(allocator, where_clause);

    const dynamic_sql = try std.mem.join(allocator, " ", query_parts.items);
    defer allocator.free(dynamic_sql);

    std.debug.print("Generated SQL: {s}\n", .{dynamic_sql});

    // Execute the dynamic query
    var dynamic_stmt = try db.prepareDynamic(dynamic_sql);
    defer dynamic_stmt.deinit();

    const NameEmail = struct {
        name: []const u8,
        email: []const u8,
    };

    std.debug.print("\nResults:\n", .{});
    var dynamic_iter = try dynamic_stmt.iteratorAlloc(NameEmail, allocator, .{});
    while (try dynamic_iter.nextAlloc(allocator, .{})) |row| {
        std.debug.print("  - {s} ({s})\n", .{ row.name, row.email });
    }

    std.debug.print("\n✓ SQLite integration successful!\n", .{});
}
