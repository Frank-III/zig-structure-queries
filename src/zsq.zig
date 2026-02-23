/// Zig Structured Queries - A type-safe SQL query builder for Zig
const std = @import("std");

// ===========================================================================
// MAIN EXPORTS
// ===========================================================================

// Type-safe query builder with field operators (PRIMARY API)
pub const TypeSafe = @import("core/type_safe.zig");
pub const Query = TypeSafe.Query; // The new comptime builder
pub const query = TypeSafe.query;
pub const from = TypeSafe.from;
pub const QueryBuilder = TypeSafe.QueryBuilder; // The old builder (kept for now)
pub const Field = TypeSafe.Field;
pub const schema = TypeSafe.schema;
pub const table = TypeSafe.table;
pub const col = TypeSafe.col;
pub const columns = TypeSafe.columns;
pub const param = TypeSafe.param;
pub const params = TypeSafe.params;
pub const tableMatch = TypeSafe.tableMatch;
pub const Condition = TypeSafe.Condition;
pub const OrderBy = TypeSafe.OrderBy;
pub const Operator = TypeSafe.Operator;
pub const Value = TypeSafe.Value;

// Mutation builders (INSERT/UPDATE/DELETE)
pub const Mutations = @import("core/mutations.zig");
pub const InsertBuilder = Mutations.InsertBuilder;
pub const UpdateBuilder = Mutations.UpdateBuilder;
pub const DeleteBuilder = Mutations.DeleteBuilder;

// Aggregate functions
pub const Aggregates = @import("core/aggregates.zig");
pub const count = Aggregates.count;
pub const countDistinct = Aggregates.countDistinct;
pub const sum = Aggregates.sum;
pub const avg = Aggregates.avg;
pub const max = Aggregates.max;
pub const min = Aggregates.min;

// Database abstraction (SQLite)
pub const Database = @import("core/database.zig").Database;
pub const Statement = @import("core/database.zig").Statement;
pub const Row = @import("core/database.zig").Row;

// Simple runtime query builder (legacy, kept for compatibility)
pub const SimpleQuery = @import("core/simple_query.zig").QueryBuilder;

// ===========================================================================
// USAGE EXAMPLE
// ===========================================================================
// Define your schema (compact Zig-style):
// const DB = schema(.{
//     .users = table("users", .{
//         .id = col(i32),
//         .name = col([]const u8),
//         .age = col(i32),
//     }),
//     .posts = table("posts", .{
//         .id = col(i32),
//         .user_id = col(i32),
//         .title = col([]const u8),
//     }),
// });
//
// Build query + use inferred result type:
// var q = query(DB.users, allocator)
//     .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
//     .select(.{ .user_name = DB.users.name, .post_title = DB.posts.title });
// defer q.deinit();
//
// try q.where(DB.users.age, .gt, 25);
// const sql = try q.toSql();
// const args = try q.flattenedValues();
// const ResultType = @TypeOf(q).ResultType;
// ===========================================================================

// Tests
test {
    _ = @import("core/type_safe.zig");
    _ = @import("core/simple_query.zig");
    _ = @import("core/database.zig");
}
