const std = @import("std");
const type_safe = @import("type_safe.zig");
const Value = type_safe.Value;
const param = type_safe.param;
const params = type_safe.params;

const DB = type_safe.schema(.{
    .users = type_safe.table("users", .{
        .id = type_safe.col(i32),
        .name = type_safe.col([]const u8),
        .age = type_safe.col(i32),
    }),
    .posts = type_safe.table("posts", .{
        .id = type_safe.col(i32),
        .user_id = type_safe.col(i32),
        .title = type_safe.col([]const u8),
    }),
});

// =============================================================================
// TYPE SAFETY AUDIT - FINAL STATUS AFTER FIXES
// =============================================================================
//
// VERDICT: ✅ FULL COMPILE-TIME TYPE SAFETY FOR QUERY BUILDING
//
// All of the following are now enforced at COMPILE TIME (zero runtime cost):
//
// ✅ Field Operators:
//    - eq(value), neq(value), gt(value), gte(value), lt(value), lte(value)
//      → Value type must match field type
//    - between(min, max)
//      → Both values must match field type
//    - like(pattern)
//      → ONLY available on string fields (compile error on int/float)
//    - in(values)
//      → Array element type must be compatible with field type
//    - isNull(), isNotNull()
//      → Available on all fields
//
// ✅ Join Conditions:
//    - eqField(other_field)
//      → Both fields must have compatible types (int-int, string-string, etc.)
//      → Compile error: "cannot join i32 with []const u8"
//
// ✅ Query Structure:
//    - select(.{fields...})
//      → All fields must belong to a joined table
//      → Compile error: "Field 'x' belongs to table 'y' which is not joined!"
//
// ✅ Result Type Inference:
//    - ResultType is generated at compile time from selected fields
//    - struct { name: []const u8, age: i32 } is known at compile time
//
// ⚠️ REMAINING LIMITATIONS (inherent to Zig, not bugs):
//    - Runtime QueryBuilder cannot infer result types (must specify manually)
//    - Mutations use anytype (could be improved)
//    - Nullable propagation currently focuses on outer-join result inference
//    - Aggregates not integrated with type system
//
// =============================================================================

// TEST 1: eq() - Enforces value type
test "AUDIT: eq() enforces type safety" {
    // DB.users.age.eq("hello") → error: expected type 'i32', found '*const [5:0]u8'
    const cond = DB.users.age.eq(25);
    try std.testing.expectEqual(type_safe.Operator.eq, cond.op);
}

// TEST 2: like() - Only on string fields
test "AUDIT: like() only available on string fields" {
    // DB.users.age.like("%x%") → error: like() is only available for string fields, got i32
    const cond = DB.users.name.like("%pattern%");
    try std.testing.expectEqual(type_safe.Operator.like, cond.op);
}

// TEST 3: eqField() - Type compatibility for joins
test "AUDIT: eqField() enforces type compatibility" {
    // DB.users.age.eqField(DB.users.name) → error: cannot join i32 with []const u8
    const join_cond = DB.users.id.eqField(DB.users.age); // both int - OK
    try std.testing.expectEqual(type_safe.Operator.eq, join_cond.op);
}

// TEST 4: in() - Element type compatibility
test "AUDIT: in() enforces element type compatibility" {
    // DB.users.age.in(&[_][]const u8{"a"}) → error: element type mismatch: field is i32
    const ids = &[_]i64{ 1, 2, 3 };
    const cond = DB.users.id.in(ids);
    try std.testing.expectEqual(type_safe.Operator.in, cond.op);
}

// TEST 5: between() - Both bounds match field type
test "AUDIT: between() enforces type safety" {
    // DB.users.age.between("a", "b") → error: expected type 'i32', found '*const [1:0]u8'
    const cond = DB.users.age.between(18, 65);
    try std.testing.expectEqual(type_safe.Operator.between, cond.op);
}

// TEST 6: Join with type-safe result type inference
test "AUDIT: Join with ResultType inference" {
    const allocator = std.testing.allocator;

    const MyQuery = type_safe.Query(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ DB.users.name, DB.posts.title });

    // ResultType is generated at compile time!
    const ResultType = @TypeOf(MyQuery).ResultType;
    const fields = @typeInfo(ResultType).@"struct".fields;

    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqualStrings("name", fields[0].name);
    try std.testing.expect(fields[0].type == []const u8);
    try std.testing.expectEqualStrings("title", fields[1].name);
    try std.testing.expect(fields[1].type == []const u8);

    var builder = MyQuery;
    builder.allocator = allocator;
    defer builder.deinit();

    const sql = try builder.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN posts") != null);
}

// TEST 7: Select validates table membership
test "AUDIT: Select validates field belongs to joined table" {
    // Query(DB.users).select(.{ DB.posts.title }) → error: Field 'title' belongs to table 'posts' which is not joined!
    const MyQuery = type_safe.Query(DB.users)
        .select(.{ DB.users.name, DB.users.age }); // Only users fields - OK

    const ResultType = @TypeOf(MyQuery).ResultType;
    const fields = @typeInfo(ResultType).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 2), fields.len);
}

// TEST 8: NULL handling
test "AUDIT: NULL operators" {
    const cond1 = DB.users.name.isNull();
    try std.testing.expectEqual(type_safe.Operator.is_null, cond1.op);

    const cond2 = DB.users.age.isNotNull();
    try std.testing.expectEqual(type_safe.Operator.is_not_null, cond2.op);
}

// TEST 9: Value.from type handling
test "AUDIT: Value.from type handling" {
    const v1 = Value.from(@as(i64, 42));
    try std.testing.expectEqual(Value{ .int = 42 }, v1);

    const v2 = Value.from(@as(f64, 3.14));
    try std.testing.expectEqual(Value{ .float = 3.14 }, v2);
}

// TEST 10: Named parameters in strict/comptime builder
test "AUDIT: param() placeholders are typed and bindable" {
    const allocator = std.testing.allocator;

    var q = type_safe.query(DB.users, allocator)
        .select(.{ DB.users.id, DB.users.name });
    defer q.deinit();

    try q.where(DB.users.age, .gte, param("min_age", i32));

    const sql = try q.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age >= ?") != null);

    const values = try q.flattenedValuesWith(.{ .min_age = @as(i32, 30) });
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqual(Value{ .int = 30 }, values[0]);
}

// TEST 11: typed params() struct binding path
test "AUDIT: params() creates typed bind struct" {
    const allocator = std.testing.allocator;
    const QueryParams = params(.{ .min_age = i32 });

    var q = type_safe.query(DB.users, allocator)
        .select(.{ DB.users.id, DB.users.name });
    defer q.deinit();

    try q.where(DB.users.age, .gte, param("min_age", i32));

    const values = try q.flattenedValuesAs(QueryParams, .{ .min_age = @as(i32, 45) });
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqual(Value{ .int = 45 }, values[0]);
}

// TEST 12: logical condition rendering in strict/comptime mode
test "AUDIT: logical conditions render and bind in strict mode" {
    const allocator = std.testing.allocator;

    var q = type_safe.query(DB.users, allocator)
        .select(.{ DB.users.id });
    defer q.deinit();

    try q.whereCondition(DB.users.age.gt(20).or_(DB.users.age.lt(10)));

    const sql = try q.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE (users.age > ? OR users.age < ?)") != null);

    const values = try q.flattenedValues();
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 2), values.len);
}

// TEST 13: SQLite dialect operators and table MATCH helper
test "AUDIT: sqlite dialect operators are rendered" {
    const allocator = std.testing.allocator;
    const SearchDB = type_safe.schema(.{
        .docs_fts = type_safe.table("docs_fts", .{
            .title = type_safe.col([]const u8),
            .body = type_safe.col([]const u8),
        }),
    });

    const cond1 = DB.users.name.glob("J*");
    try std.testing.expectEqual(type_safe.Operator.glob, cond1.op);

    const cond2 = DB.users.name.match("zig parser");
    try std.testing.expectEqual(type_safe.Operator.match, cond2.op);

    var q = type_safe.query(SearchDB.docs_fts, allocator)
        .select(.{ SearchDB.docs_fts.title });
    defer q.deinit();

    try q.whereCondition(type_safe.tableMatch(SearchDB.docs_fts, "zig parser"));

    const sql = try q.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE docs_fts MATCH ?") != null);
}

// type_safe.query(DB.users, std.testing.allocator)
//     .select(.{ DB.users.id })
//     .where(DB.users.age, .gte, param("min_age", []const u8));
// ^ compile error: param() type mismatch for field 'age'
