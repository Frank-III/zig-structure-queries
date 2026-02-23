const std = @import("std");

// Import the query builder through the main module
const zsq = @import("zsq");
const QueryBuilder = zsq.QueryBuilder;

// ============================================================
// SCHEMA DEFINITION
// ============================================================

const DB = zsq.schema(.{
    .users = zsq.table("users", .{
        .id = zsq.col(i32),
        .name = zsq.col([]const u8),
        .age = zsq.col(i32),
        .email = zsq.col([]const u8),
        .created_at = zsq.col([]const u8),
    }),
    .posts = zsq.table("posts", .{
        .id = zsq.col(i32),
        .user_id = zsq.col(i32),
        .title = zsq.col([]const u8),
        .content = zsq.col([]const u8),
        .views = zsq.col(i32),
    }),
    .comments = zsq.table("comments", .{
        .id = zsq.col(i32),
        .post_id = zsq.col(i32),
        .user_id = zsq.col(i32),
        .text = zsq.col([]const u8),
    }),
});

// ============================================================
// EXAMPLES
// ============================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🎯 Ergonomic Query Builder API Demo\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    // Example 1: Simple select with multiple fields
    try example1_simpleSelect(allocator);

    // Example 2: Complex WHERE with multiple conditions
    try example2_multipleConditions(allocator);

    // Example 3: JOIN queries
    try example3_joinQueries(allocator);

    // Example 4: Aggregation with GROUP BY
    try example4_aggregation(allocator);

    // Example 5: Advanced query with everything
    try example5_advancedQuery(allocator);

    std.debug.print("\n✅ All examples completed successfully!\n", .{});
}

fn example1_simpleSelect(allocator: std.mem.Allocator) !void {
    std.debug.print("📝 Example 1: Simple SELECT with tuple syntax\n", .{});
    std.debug.print("-" ** 60 ++ "\n", .{});

    var query = QueryBuilder.init(allocator);
    defer query.deinit();

    // Clean, ergonomic tuple syntax!
    _ = query
        .select(.{ DB.users.name, DB.users.email, DB.users.age })
        .from(DB.users)
        .where(DB.users.age.gt(18))
        .orderBy(DB.users.name.asc())
        .limit(10);

    const sql = try query.toSql();
    defer allocator.free(sql);

    std.debug.print("Generated SQL:\n{s}\n\n", .{sql});
}

fn example2_multipleConditions(allocator: std.mem.Allocator) !void {
    std.debug.print("📝 Example 2: Multiple WHERE conditions\n", .{});
    std.debug.print("-" ** 60 ++ "\n", .{});

    var query = QueryBuilder.init(allocator);
    defer query.deinit();

    // Multiple conditions in a single call!
    _ = query
        .select(.{ DB.users.name, DB.users.email })
        .from(DB.users)
        .where(.{
        DB.users.age.gt(21),
        DB.users.age.lt(65),
        DB.users.email.like("%@gmail.com"),
    })
        .orderBy(.{
        DB.users.age.desc(),
        DB.users.name.asc(),
    })
        .limit(20);

    const sql = try query.toSql();
    defer allocator.free(sql);

    std.debug.print("Generated SQL:\n{s}\n\n", .{sql});
}

fn example3_joinQueries(allocator: std.mem.Allocator) !void {
    std.debug.print("📝 Example 3: JOIN queries\n", .{});
    std.debug.print("-" ** 60 ++ "\n", .{});

    var query = QueryBuilder.init(allocator);
    defer query.deinit();

    // Join with tuple syntax for fields and conditions
    _ = query
        .select(.{
        DB.users.name,
        DB.posts.title,
        DB.posts.views,
    })
        .from(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .where(.{
        DB.users.age.gt(18),
        DB.posts.views.gt(100),
    })
        .orderBy(.{
        DB.posts.views.desc(),
        DB.posts.title.asc(),
    })
        .limit(10);

    const sql = try query.toSql();
    defer allocator.free(sql);

    std.debug.print("Generated SQL:\n{s}\n\n", .{sql});
}

fn example4_aggregation(allocator: std.mem.Allocator) !void {
    std.debug.print("📝 Example 4: Aggregation with GROUP BY\n", .{});
    std.debug.print("-" ** 60 ++ "\n", .{});

    var query = QueryBuilder.init(allocator);
    defer query.deinit();

    // GROUP BY with tuple syntax
    _ = query
        .select(.{ DB.users.name, DB.users.age })
        .from(DB.users)
        .groupBy(.{ DB.users.name, DB.users.age })
        .having(DB.users.age.gt(25))
        .orderBy(DB.users.age.desc());

    const sql = try query.toSql();
    defer allocator.free(sql);

    std.debug.print("Generated SQL:\n{s}\n\n", .{sql});
}

fn example5_advancedQuery(allocator: std.mem.Allocator) !void {
    std.debug.print("📝 Example 5: Advanced query with multiple JOINs\n", .{});
    std.debug.print("-" ** 60 ++ "\n", .{});

    var query = QueryBuilder.init(allocator);
    defer query.deinit();

    // Complex query with multiple JOINs and conditions
    _ = query
        .select(.{
        DB.users.name,
        DB.posts.title,
        DB.comments.text,
    })
        .from(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .leftJoin(DB.comments, DB.comments.post_id.eqField(DB.posts.id))
        .where(.{
        DB.users.age.gt(18),
        DB.posts.views.gt(50),
        DB.posts.title.like("%Zig%"),
    })
        .orderBy(.{
        DB.posts.views.desc(),
        DB.users.name.asc(),
    })
        .limit(15)
        .offset(5);

    const sql = try query.toSql();
    defer allocator.free(sql);

    std.debug.print("Generated SQL:\n{s}\n\n", .{sql});
}

// ============================================================
// COMPARISON: Old vs New API
// ============================================================

// ============================================================
// COMPARISON: Old vs New API (for reference, not executed)
// ============================================================

// fn oldApiStyle(allocator: std.mem.Allocator) !void {
//     var query = QueryBuilder.init(allocator);
//     defer query.deinit();
//
//     // Old style: verbose with try everywhere
//     _ = query.select(DB.users.name);
//     _ = query.select(DB.users.email);
//     _ = query.select(DB.users.age);
//     _ = query.from(DB.users);
//     _ = query.where(DB.users.age.gt(18));
//     _ = query.where(DB.users.email.like("%@gmail.com"));
//     _ = query.orderBy(DB.users.name.asc());
//     _ = query.orderBy(DB.users.age.desc());
//     _ = query.limit(10);
//
//     const sql = try query.toSql();
//     defer allocator.free(sql);
// }
//
// fn newApiStyle(allocator: std.mem.Allocator) !void {
//     var query = QueryBuilder.init(allocator);
//     defer query.deinit();
//
//     // New style: clean and concise with tuple syntax
//     _ = query
//         .select(.{ DB.users.name, DB.users.email, DB.users.age })
//         .from(DB.users)
//         .where(.{
//         DB.users.age.gt(18),
//         DB.users.email.like("%@gmail.com"),
//     })
//         .orderBy(.{
//         DB.users.name.asc(),
//         DB.users.age.desc(),
//     })
//         .limit(10);
//
//     const sql = try query.toSql();
//     defer allocator.free(sql);
// }
