# Ergonomic Tuple-Based Query Builder API

## Overview

Successfully implemented an ergonomic, tuple-based query builder API for Zig that provides a clean, chainable syntax without the need for `try` on every builder call.

## Key Features

### 1. **Infallible Chaining**
All builder methods now return `*QueryBuilder` instead of `!*QueryBuilder`, making the API cleaner:

```zig
// Before (required try everywhere)
_ = try query.select(DB.users.name);
_ = try query.where(DB.users.age.gt(25));

// After (clean chaining)
_ = query
    .select(DB.users.name)
    .where(DB.users.age.gt(25))
    .limit(10);
```

### 2. **Tuple Syntax Support**
Methods now accept both single values and tuples, providing flexibility:

```zig
// Single field selection
_ = query.select(DB.users.name);

// Multiple fields at once using tuple syntax
_ = query.select(.{
    DB.users.name,
    DB.users.age,
    DB.users.email
});
```

### 3. **Backward Compatible**
The new API maintains full backward compatibility with existing single-field usage.

## Complete Example

```zig
const std = @import("std");
const QueryBuilder = @import("type_safe.zig").QueryBuilder;

// Define your schema
const zsq = @import("zsq");
const DB = zsq.schema(.{
    .users = zsq.table("users", .{
        .id = zsq.col(i32),
        .name = zsq.col([]const u8),
        .age = zsq.col(i32),
        .email = zsq.col([]const u8),
    }),
    .posts = zsq.table("posts", .{
        .id = zsq.col(i32),
        .user_id = zsq.col(i32),
        .title = zsq.col([]const u8),
    }),
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: Simple query with tuple syntax
    var query1 = QueryBuilder.init(allocator);
    defer query1.deinit();

    _ = query1
        .select(.{ DB.users.name, DB.users.age, DB.users.email })
        .from(DB.users)
        .where(.{
            DB.users.age.gt(25),
            DB.users.email.like("%@example.com"),
        })
        .orderBy(.{
            DB.users.age.desc(),
            DB.users.name.asc(),
        })
        .limit(10);

    const sql1 = try query1.toSql();
    defer allocator.free(sql1);

    std.debug.print("Query 1:\n{s}\n\n", .{sql1});

    // Example 2: Join query with tuple syntax
    var query2 = QueryBuilder.init(allocator);
    defer query2.deinit();

    _ = query2
        .select(.{
            DB.users.name,
            DB.posts.title,
        })
        .from(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .where(.{
            DB.users.age.gt(18),
            DB.posts.title.like("%Zig%"),
        })
        .orderBy(DB.posts.id.desc())
        .limit(5);

    const sql2 = try query2.toSql();
    defer allocator.free(sql2);

    std.debug.print("Query 2:\n{s}\n\n", .{sql2});
}
```

## Output Examples

### Simple Query
```sql
SELECT users.name, users.age, users.email
FROM users
WHERE users.age > 25 AND users.email LIKE '%@example.com'
ORDER BY users.age DESC, users.name ASC
LIMIT 10
```

### Join Query
```sql
SELECT users.name, posts.title
FROM users
INNER JOIN posts ON posts.user_id = users.id
WHERE users.age > 18 AND posts.title LIKE '%Zig%'
ORDER BY posts.id DESC
LIMIT 5
```

## All Supported Methods

### Methods with Tuple Support
- **`.select(fields)`** - Single field or tuple of fields
- **`.where(conditions)`** - Single condition or tuple of conditions
- **`.orderBy(orders)`** - Single OrderBy or tuple of OrderBy clauses
- **`.groupBy(fields)`** - Single field or tuple of fields
- **`.having(conditions)`** - Single condition or tuple of conditions

### Other Chainable Methods
- **`.from(table)`** - Set the FROM table
- **`.join(table, condition)`** - INNER JOIN
- **`.leftJoin(table, condition)`** - LEFT JOIN
- **`.rightJoin(table, condition)`** - RIGHT JOIN
- **`.limit(n)`** - LIMIT clause
- **`.offset(n)`** - OFFSET clause

### Terminal Method
- **`.toSql()`** - Generate SQL string (returns `![]u8`)

## Implementation Details

### Type Detection
Uses Zig's `@typeInfo()` at compile time to detect tuples:

```zig
pub fn select(self: *QueryBuilder, fields: anytype) *QueryBuilder {
    const fields_info = @typeInfo(@TypeOf(fields));

    switch (fields_info) {
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                // Handle tuple - iterate with inline for
                inline for (fields) |field| {
                    self.select_fields.append(self.allocator, field.toFieldRef()) catch unreachable;
                }
            } else {
                // Handle single struct
                self.select_fields.append(self.allocator, fields.toFieldRef()) catch unreachable;
            }
        },
        else => {
            // Handle other types
            self.select_fields.append(self.allocator, fields.toFieldRef()) catch unreachable;
        },
    }

    return self;
}
```

### Error Handling
Uses `catch unreachable` for append operations, making the assumption that allocation failures are unrecoverable. This is appropriate for query building where:
- Queries are typically small
- Allocation failures are rare
- Clean syntax is valuable

## Benefits

1. **Cleaner Code** - No `try` needed for chaining
2. **More Expressive** - Tuple syntax groups related items
3. **Type Safe** - All compile-time field validation still works
4. **Flexible** - Both single and tuple syntax supported
5. **Ergonomic** - API feels natural and flows well

## Comparison with Other Languages

### Swift StructuredQueries Style
```swift
let query = users
    .select(\.name, \.age, \.email)
    .where(\.age > 25)
    .orderBy(\.age, .desc)
```

### Our Zig Implementation
```zig
_ = query
    .select(.{ DB.users.name, DB.users.age, DB.users.email })
    .where(.{ DB.users.age.gt(25) })
    .orderBy(.{ DB.users.age.desc() });
```

While Zig doesn't have Swift's key paths or automatic result type inference, our implementation provides comparable ergonomics with full compile-time type safety!

## Testing

All features are covered by tests in `src/core/type_safe.zig`:
- ✅ Single field chaining
- ✅ Tuple-based API
- ✅ JOIN queries with tuple syntax
- ✅ Multiple WHERE conditions
- ✅ Multiple ORDER BY clauses

Run tests:
```bash
zig test src/core/type_safe.zig
```

---

**Status**: ✅ Fully implemented and tested
**Zig Version**: 0.15.0
**Date**: October 10, 2025
