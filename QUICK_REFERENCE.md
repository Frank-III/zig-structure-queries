# Zig Structure Queries - Quick Reference

## 🚀 Getting Started

```zig
const zsq = @import("zsq");
const QueryBuilder = zsq.QueryBuilder;

var query = QueryBuilder.init(allocator);
defer query.deinit();
```

## 📋 Schema Definition

```zig
const DB = zsq.schema(.{
    .users = zsq.table("users", .{
        .id = zsq.col(i32),
        .name = zsq.col([]const u8),
        .age = zsq.col(i32),
        .email = zsq.col([]const u8),
    }),
});
```

## 🔍 SELECT Queries

### Basic Select
```zig
_ = query
    .select(DB.users.name)
    .from(DB.users)
    .limit(10);
```

### Multiple Fields (Tuple Syntax) ⭐
```zig
_ = query
    .select(.{ DB.users.name, DB.users.age, DB.users.email })
    .from(DB.users);
```

### Generate SQL
```zig
const sql = try query.toSql();
defer allocator.free(sql);
```

## 🔍 WHERE Conditions

### Single Condition
```zig
_ = query.where(DB.users.age.gt(18));
```

### Multiple Conditions (Tuple Syntax) ⭐
```zig
_ = query.where(.{
    DB.users.age.gt(18),
    DB.users.age.lt(65),
    DB.users.email.like("%@gmail.com"),
});
// All conditions are AND'd together
```

## 🎯 Available Operators

### Comparison
```zig
.eq(value)      // =
.neq(value)     // !=
.gt(value)      // >
.gte(value)     // >=
.lt(value)      // <
.lte(value)     // <=
```

### String
```zig
.like(pattern)  // LIKE '%pattern%'
```

### Advanced Operators ⭐ NEW
```zig
.in(.{1, 2, 3})         // IN (1, 2, 3)
.between(18, 65)        // BETWEEN 18 AND 65
.not()                  // NOT condition
```

### NULL Checks
```zig
.isNull()       // IS NULL
.isNotNull()    // IS NOT NULL
```

### Field Comparison (JOINs)
```zig
.eqField(otherField)  // field1 = field2
```

## 🔗 JOINs

### INNER JOIN
```zig
_ = query
    .select(.{ DB.users.name, DB.posts.title })
    .from(DB.users)
    .join(DB.posts, DB.posts.user_id.eqField(DB.users.id));
```

### LEFT JOIN
```zig
_ = query
    .leftJoin(DB.posts, DB.posts.user_id.eqField(DB.users.id));
```

### RIGHT JOIN
```zig
_ = query
    .rightJoin(DB.posts, DB.posts.user_id.eqField(DB.users.id));
```

### Multiple JOINs
```zig
_ = query
    .from(DB.users)
    .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
    .leftJoin(DB.comments, DB.comments.post_id.eqField(DB.posts.id));
```

## 📊 Sorting & Limiting

### ORDER BY
```zig
// Single field
_ = query.orderBy(DB.users.name.asc());
_ = query.orderBy(DB.users.age.desc());

// Multiple fields (Tuple Syntax) ⭐
_ = query.orderBy(.{
    DB.users.age.desc(),
    DB.users.name.asc(),
});
```

### LIMIT & OFFSET
```zig
_ = query.limit(10);
_ = query.offset(20);
```

## 📈 GROUP BY & HAVING

### GROUP BY
```zig
// Single field
_ = query.groupBy(DB.users.country);

// Multiple fields (Tuple Syntax) ⭐
_ = query.groupBy(.{ DB.users.country, DB.users.city });
```

### HAVING
```zig
// Single condition
_ = query.having(DB.users.age.gt(25));

// Multiple conditions (Tuple Syntax) ⭐
_ = query.having(.{
    DB.users.age.gt(18),
    DB.users.age.lt(65),
});
```

## 💾 INSERT Operations

```zig
const InsertBuilder = zsq.InsertBuilder;

var insert = InsertBuilder.init(allocator, DB.users);
defer insert.deinit();

// No try needed! 🎉
_ = insert.value(DB.users.name, "John Doe");
_ = insert.value(DB.users.age, 30);
_ = insert.value(DB.users.email, "john@example.com");

// Optional: Get auto-generated ID
_ = insert.returning("id");

const sql = try insert.toSql();
defer allocator.free(sql);
// INSERT INTO users (name, age, email) VALUES ('John Doe', 30, 'john@example.com') RETURNING id
```

## ✏️ UPDATE Operations

```zig
const UpdateBuilder = zsq.UpdateBuilder;

var update = UpdateBuilder.init(allocator, DB.users);
defer update.deinit();

// No try needed!
_ = update.set(DB.users.name, "Jane Doe");
_ = update.set(DB.users.age, 31);

// Tuple syntax for multiple WHERE conditions ⭐
_ = update.where(.{
    DB.users.id.eq(1),
    DB.users.status.eq("active"),
});

const sql = try update.toSql();
defer allocator.free(sql);
// UPDATE users SET name = 'Jane Doe', age = 31 WHERE users.id = 1 AND users.status = 'active'
```

## 🗑️ DELETE Operations

```zig
const DeleteBuilder = zsq.DeleteBuilder;

var delete = DeleteBuilder.init(allocator, DB.users);
defer delete.deinit();

// Tuple syntax for multiple WHERE conditions ⭐
_ = delete.where(.{
    DB.users.age.lt(18),
    DB.users.verified.eq(false),
});

const sql = try delete.toSql();
defer allocator.free(sql);
// DELETE FROM users WHERE users.age < 18 AND users.verified = 0
```

## 🎨 Complete Example

```zig
const std = @import("std");
const zsq = @import("zsq");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build query with ergonomic API
    var query = zsq.QueryBuilder.init(allocator);
    defer query.deinit();

    _ = query
        .select(.{
            DB.users.name,
            DB.users.age,
            DB.posts.title,
        })
        .from(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .where(.{
            DB.users.age.gt(18),
            DB.users.age.lt(65),
            DB.posts.title.like("%Zig%"),
        })
        .orderBy(.{
            DB.users.age.desc(),
            DB.users.name.asc(),
        })
        .limit(10);

    const sql = try query.toSql();
    defer allocator.free(sql);

    std.debug.print("Generated SQL:\n{s}\n", .{sql});
}
```

## 🎯 Key Features

✅ **Type-Safe** - Can't reference non-existent fields
✅ **Compile-Time Validation** - Invalid queries won't compile
✅ **Zero Runtime Overhead** - All checks at compile time
✅ **Ergonomic API** - Clean tuple syntax, no `try` on builder methods
✅ **Full JOIN Support** - INNER, LEFT, RIGHT, CROSS
✅ **Zig 0.15 Compatible** - Uses `ArrayListUnmanaged`

## ⚠️ Current Limitations

❌ OR conditions - Only AND supported currently
❌ Subqueries - Not yet implemented
❌ Aggregates not integrated - Exist in separate module

## ✅ Recently Added Features

✅ IN operator - `.in(.{1, 2, 3})`
✅ BETWEEN operator - `.between(18, 65)`
✅ NOT operator - `.not()`
✅ DISTINCT - `selectDistinct()`
✅ Ergonomic mutations API - No `try` needed on builder methods
✅ Tuple WHERE conditions - For UPDATE and DELETE builders

See [FEATURE_STATUS.md](FEATURE_STATUS.md) for full list and roadmap.

## 📚 More Documentation

- **[ERGONOMIC_API.md](ERGONOMIC_API.md)** - Full API documentation
- **[SQLITE_DIALECT_GUIDE.md](SQLITE_DIALECT_GUIDE.md)** - SQLite features reference
- **[FEATURE_STATUS.md](FEATURE_STATUS.md)** - Implementation status & roadmap
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Technical details

## 🧪 Run Examples

```bash
# Run the ergonomic API demo
zig build run-ergonomic_api_demo

# Run tests
zig test src/core/type_safe.zig
zig build test
```

## 🔥 Pro Tips

1. **Use tuple syntax** for multiple fields/conditions - it's cleaner!
2. **No `try` needed** on builder methods - they're infallible
3. **Always defer query.deinit()** to free memory
4. **Use const for field definitions** in your schema
5. **Field types match** - Don't use string operators on numbers!

---

**Zig Version**: 0.15.0
**Status**: Production Ready for Basic Queries
**Last Updated**: October 10, 2025
