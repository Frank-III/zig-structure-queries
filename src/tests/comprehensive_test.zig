const std = @import("std");
const zsq = @import("zsq");

// ===========================================================================
// COMPREHENSIVE TEST SUITE
// ===========================================================================

// Test database schema
const TestDB = struct {
    pub const users = struct {
        pub const _table_name = "users";
        pub const id = zsq.Field(i32){ .table = "users", .column = "id" };
        pub const name = zsq.Field([]const u8){ .table = "users", .column = "name" };
        pub const email = zsq.Field([]const u8){ .table = "users", .column = "email" };
        pub const age = zsq.Field(i32){ .table = "users", .column = "age" };
        pub const active = zsq.Field(bool){ .table = "users", .column = "active" };
        pub const created_at = zsq.Field([]const u8){ .table = "users", .column = "created_at" };
    };

    pub const posts = struct {
        pub const _table_name = "posts";
        pub const id = zsq.Field(i32){ .table = "posts", .column = "id" };
        pub const user_id = zsq.Field(i32){ .table = "posts", .column = "user_id" };
        pub const title = zsq.Field([]const u8){ .table = "posts", .column = "title" };
        pub const content = zsq.Field([]const u8){ .table = "posts", .column = "content" };
        pub const views = zsq.Field(i32){ .table = "posts", .column = "views" };
        pub const published = zsq.Field(bool){ .table = "posts", .column = "published" };
    };

    pub const comments = struct {
        pub const _table_name = "comments";
        pub const id = zsq.Field(i32){ .table = "comments", .column = "id" };
        pub const post_id = zsq.Field(i32){ .table = "comments", .column = "post_id" };
        pub const user_id = zsq.Field(i32){ .table = "comments", .column = "user_id" };
        pub const content = zsq.Field([]const u8){ .table = "comments", .column = "content" };
        pub const likes = zsq.Field(i32){ .table = "comments", .column = "likes" };
    };
};

test "SELECT queries" {
    const allocator = std.testing.allocator;

    // Simple SELECT
    {
        var query = zsq.QueryBuilder.init(allocator);
        defer query.deinit();

        _ = try query.select(TestDB.users.name);
        _ = try query.select(TestDB.users.email);
        _ = query.from(TestDB.users);
        _ = try query.where(TestDB.users.active.eq(true));
        _ = query.limit(10);

        const sql = try query.toSql();
        defer allocator.free(sql);

        try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name, users.email") != null);
        try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users") != null);
        try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.active = 1") != null);
        try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
    }

    std.debug.print("✓ SELECT query tests passed\n", .{});
}

test "JOIN queries" {
    const allocator = std.testing.allocator;

    // INNER JOIN
    {
        var query = zsq.QueryBuilder.init(allocator);
        defer query.deinit();

        _ = try query.select(TestDB.users.name);
        _ = try query.select(TestDB.posts.title);
        _ = query.from(TestDB.users);
        _ = try query.join(TestDB.posts, TestDB.posts.user_id.eqField(TestDB.users.id));
        _ = try query.where(TestDB.posts.published.eq(true));

        const sql = try query.toSql();
        defer allocator.free(sql);

        try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN posts") != null);
        try std.testing.expect(std.mem.indexOf(u8, sql, "posts.user_id = users.id") != null);
    }

    // Multiple JOINs
    {
        var query = zsq.QueryBuilder.init(allocator);
        defer query.deinit();

        _ = try query.select(TestDB.users.name);
        _ = try query.select(TestDB.posts.title);
        _ = try query.select(TestDB.comments.content);
        _ = query.from(TestDB.users);
        _ = try query.join(TestDB.posts, TestDB.posts.user_id.eqField(TestDB.users.id));
        _ = try query.leftJoin(TestDB.comments, TestDB.comments.post_id.eqField(TestDB.posts.id));

        const sql = try query.toSql();
        defer allocator.free(sql);

        try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN posts") != null);
        try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN comments") != null);
    }

    std.debug.print("✓ JOIN query tests passed\n", .{});
}

test "Aggregate functions" {
    const allocator = std.testing.allocator;

    // COUNT
    {
        const agg = zsq.count(TestDB.posts.id).as("post_count");

        var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        try agg.toSql(writer);
        const result = buffer.items;

        try std.testing.expectEqualStrings("COUNT(posts.id) AS post_count", result);
    }

    // SUM
    {
        const agg = zsq.sum(TestDB.posts.views).as("total_views");

        var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        try agg.toSql(writer);
        const result = buffer.items;

        try std.testing.expectEqualStrings("SUM(posts.views) AS total_views", result);
    }

    // AVG
    {
        const agg = zsq.avg(TestDB.comments.likes).as("avg_likes");

        var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        try agg.toSql(writer);
        const result = buffer.items;

        try std.testing.expectEqualStrings("AVG(comments.likes) AS avg_likes", result);
    }

    std.debug.print("✓ Aggregate function tests passed\n", .{});
}

test "GROUP BY and HAVING" {
    const allocator = std.testing.allocator;

    var query = zsq.QueryBuilder.init(allocator);
    defer query.deinit();

    _ = try query.select(TestDB.users.name);
    _ = try query.select(TestDB.users.id); // Would be COUNT in real query
    _ = query.from(TestDB.users);
    _ = try query.join(TestDB.posts, TestDB.posts.user_id.eqField(TestDB.users.id));
    _ = try query.groupBy(TestDB.users.id);
    _ = try query.groupBy(TestDB.users.name);
    _ = try query.having(TestDB.users.id.gt(0)); // Would be COUNT(posts.id) > 5

    const sql = try query.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "GROUP BY users.id, users.name") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "HAVING users.id > 0") != null);

    std.debug.print("✓ GROUP BY and HAVING tests passed\n", .{});
}

test "Field operators" {
    const allocator = std.testing.allocator;
    _ = allocator;

    // Numeric operators
    {
        const cond1 = TestDB.users.age.gt(25);
        try std.testing.expectEqual(zsq.FieldTypes.Operator.gt, cond1.op);

        const cond2 = TestDB.users.age.lte(65);
        try std.testing.expectEqual(zsq.FieldTypes.Operator.lte, cond2.op);
    }

    // String operators
    {
        const cond1 = TestDB.users.name.like("%john%");
        try std.testing.expectEqual(zsq.FieldTypes.Operator.like, cond1.op);

        const cond2 = TestDB.users.email.eq("test@example.com");
        try std.testing.expectEqual(zsq.FieldTypes.Operator.eq, cond2.op);
    }

    // Boolean operators
    {
        const cond1 = TestDB.users.active.eq(true);
        try std.testing.expectEqual(zsq.FieldTypes.Operator.eq, cond1.op);

        const cond2 = TestDB.posts.published.neq(false);
        try std.testing.expectEqual(zsq.FieldTypes.Operator.neq, cond2.op);
    }

    // NULL checks
    {
        const cond1 = TestDB.users.email.isNull();
        try std.testing.expectEqual(zsq.FieldTypes.Operator.is_null, cond1.op);

        const cond2 = TestDB.users.created_at.isNotNull();
        try std.testing.expectEqual(zsq.FieldTypes.Operator.is_not_null, cond2.op);
    }

    std.debug.print("✓ Field operator tests passed\n", .{});
}

test "ORDER BY and pagination" {
    const allocator = std.testing.allocator;

    var query = zsq.QueryBuilder.init(allocator);
    defer query.deinit();

    _ = try query.select(TestDB.posts.title);
    _ = try query.select(TestDB.posts.views);
    _ = query.from(TestDB.posts);
    _ = try query.orderBy(TestDB.posts.views.desc());
    _ = try query.orderBy(TestDB.posts.title.asc());
    _ = query.limit(20);
    _ = query.offset(40);

    const sql = try query.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "ORDER BY posts.views DESC, posts.title ASC") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 20") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "OFFSET 40") != null);

    std.debug.print("✓ ORDER BY and pagination tests passed\n", .{});
}

test "Complex WHERE conditions" {
    const allocator = std.testing.allocator;

    var query = zsq.QueryBuilder.init(allocator);
    defer query.deinit();

    _ = try query.select(TestDB.users.name);
    _ = query.from(TestDB.users);
    _ = try query.where(TestDB.users.age.gte(18));
    _ = try query.where(TestDB.users.age.lte(65));
    _ = try query.where(TestDB.users.active.eq(true));
    _ = try query.where(TestDB.users.email.like("%@example.com"));

    const sql = try query.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "users.age >= 18") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "users.age <= 65") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "users.active = 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "users.email LIKE '%@example.com'") != null);

    std.debug.print("✓ Complex WHERE condition tests passed\n", .{});
}

pub fn main() !void {
    std.debug.print("\n=== Running Comprehensive Test Suite ===\n\n", .{});

    // Run all tests
    try std.testing.runTests(std.testing.allocator);

    std.debug.print("\n=== All Tests Completed Successfully! ===\n", .{});
    std.debug.print("\nFeatures Tested:\n", .{});
    std.debug.print("  ✓ SELECT queries with type-safe fields\n", .{});
    std.debug.print("  ✓ JOIN queries (INNER, LEFT, multiple)\n", .{});
    std.debug.print("  ✓ Aggregate functions (COUNT, SUM, AVG)\n", .{});
    std.debug.print("  ✓ GROUP BY and HAVING clauses\n", .{});
    std.debug.print("  ✓ Field operators (numeric, string, boolean)\n", .{});
    std.debug.print("  ✓ NULL checks (IS NULL, IS NOT NULL)\n", .{});
    std.debug.print("  ✓ ORDER BY with ASC/DESC\n", .{});
    std.debug.print("  ✓ Pagination (LIMIT, OFFSET)\n", .{});
    std.debug.print("  ✓ Complex WHERE conditions\n", .{});
    std.debug.print("\n", .{});
}
