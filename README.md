# Zig Structured Queries (ZSQ)

A type-safe, ergonomic SQL query builder for Zig 0.15.2 with compile-time validation and zero runtime overhead.

## ✨ Highlights

- **🎯 Ergonomic Tuple Syntax**: Clean, chainable API with `.select(.{ field1, field2, field3 })`
- **🔒 100% Type-Safe**: Can't reference non-existent fields or use wrong operators
- **⚡ Zero Runtime Cost**: All validation happens at compile time
- **🚫 No `try` Chaining**: Infallible builder methods for clean code flow
- **🔗 Full JOIN Support**: INNER, LEFT, RIGHT joins with type-safe conditions
- **📊 SQLite Focused**: Comprehensive SQLite dialect support

## 🚀 Quick Start

### Installation

```bash
# Add to your build.zig.zon dependencies
.dependencies = .{
    .zsq = .{
        .url = "https://github.com/yourusername/zig-structure-queries/archive/main.tar.gz",
    },
},
```

### Define Your Schema

```zig
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
```

### Build Queries with Comptime Result Inference

```zig
const std = @import("std");
const zsq = @import("zsq");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var q = zsq.query(DB.users, allocator)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{
            .user_name = DB.users.name,
            .user_age = DB.users.age,
            .post_title = DB.posts.title,
        });
    defer q.deinit();

    try q.where(DB.users.age, .gte, 18);
    try q.where(DB.users.age, .lte, 65);

    const sql = try q.toSql();
    defer allocator.free(sql);

    std.debug.print("{s}\n", .{sql});

    // Inferred row shape at compile time:
    const Row = @TypeOf(q).ResultType;
    _ = Row;
}
```

**Generated SQL:**
```sql
SELECT users.name AS "user_name", users.age AS "user_age", posts.title AS "post_title"
FROM users
INNER JOIN posts ON posts.user_id = users.id
WHERE users.age >= ? AND users.age <= ?
```

### Named Parameters (Strict/Comptime Path)

```zig
var q = zsq.query(DB.users, allocator)
    .select(.{ DB.users.id, DB.users.name });
defer q.deinit();

try q.where(DB.users.age, .gte, zsq.param("min_age", i32));
try q.where(DB.users.name, .like, zsq.param("name_pattern", []const u8));

const sql = try q.toSql();
// ... WHERE users.age >= ? AND users.name LIKE ?

const values = try q.flattenedValuesWith(.{
    .min_age = @as(i32, 21),
    .name_pattern = "%zig%",
});
defer allocator.free(values);
```

Notes:
- `param("name", T)` is type-checked against the target field.
- `params(.{ ... })` can generate a typed bind struct for stricter call sites.
- `flattenedValues()` returns `error.UnboundNamedParameter` when placeholders exist.
- Use `flattenedValuesWith(.{ ... })` to supply named values in bind order.

```zig
const QueryParams = zsq.params(.{
    .min_age = i32,
    .name_pattern = []const u8,
});

const typed_values = try q.flattenedValuesAs(QueryParams, .{
    .min_age = @as(i32, 21),
    .name_pattern = "%zig%",
});
defer allocator.free(typed_values);
```

Logical composition is also supported:

```zig
_ = query.where(DB.users.age.gt(21).or_(DB.users.age.lt(18)));
```

Runtime/raw SQL escape hatches:

```zig
// Raw condition fragment
_ = query.whereRaw("length(users.email) > 10", .{});

// Raw condition with typed values rendered safely
_ = query.whereRaw(
    "users.email LIKE ? AND users.age >= ?",
    .{ "%@example.com", @as(i32, 18) },
);

// Runtime execution helpers with typed binding/decoding
try db.executeWith("INSERT INTO events (name, severity) VALUES (?, ?)", .{ "cpu", @as(i32, 5) });
const row = try db.queryOne(Event, "SELECT id, name, severity FROM events WHERE severity >= ?", .{@as(i32, 4)});
```

## 🎨 Key Features

### ✅ Ergonomic Tuple Syntax

```zig
// Select multiple fields at once
.select(.{ DB.users.name, DB.users.age, DB.users.email })

// Multiple WHERE conditions
.where(.{
    DB.users.age.gt(18),
    DB.users.email.like("%@gmail.com"),
})

// Multiple ORDER BY clauses
.orderBy(.{
    DB.users.age.desc(),
    DB.users.name.asc(),
})
```

### ✅ Type-Safe Operators

```zig
// Numeric fields get numeric operators
DB.users.age.gt(18)        // >
DB.users.age.between(18, 65)  // BETWEEN

// String fields get string operators
DB.users.email.like("%@gmail.com")  // LIKE
DB.users.name.glob("J*")           // GLOB
DB.users.name.regexp("^Jo.*")      // REGEXP (sqlite extension)
DB.users.name.match("zig parser")  // MATCH

// All fields get comparison operators
.eq(value)   // =
.neq(value)  // !=
.gte(value)  // >=
.lte(value)  // <=
.gt(value)   // >
.lt(value)   // <

// Advanced operators
.in(.{1, 2, 3})           // IN
.between(min, max)        // BETWEEN
.not()                    // NOT

// NULL checks
.isNull()
.isNotNull()

// Table-wide FTS helper
zsq.tableMatch(DB.docs_fts, "zig parser")
```

### ✅ Full JOIN Support

```zig
// INNER JOIN
.join(DB.posts, DB.posts.user_id.eqField(DB.users.id))

// LEFT JOIN
.leftJoin(DB.comments, DB.comments.post_id.eqField(DB.posts.id))

// RIGHT JOIN
.rightJoin(DB.profiles, DB.profiles.user_id.eqField(DB.users.id))

// Multiple JOINs
_ = query
    .from(DB.users)
    .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
    .leftJoin(DB.comments, DB.comments.post_id.eqField(DB.posts.id));
```

### ✅ GROUP BY & Aggregates

```zig
_ = query
    .select(.{ DB.users.country, DB.users.city })
    .from(DB.users)
    .groupBy(.{ DB.users.country, DB.users.city })
    .having(DB.users.age.gt(25))
    .orderBy(DB.users.country.asc());
```

### ✅ INSERT/UPDATE/DELETE

```zig
// INSERT - No try needed! 🎉
var insert = zsq.InsertBuilder.init(allocator, DB.users);
defer insert.deinit();
_ = insert.value(DB.users.name, "John Doe");
_ = insert.value(DB.users.age, 30);
_ = insert.returning("id");

// UPDATE - Clean chaining with tuple WHERE conditions
var update = zsq.UpdateBuilder.init(allocator, DB.users);
defer update.deinit();
_ = update.set(DB.users.name, "Jane Doe");
_ = update.where(.{
    DB.users.id.eq(1),
    DB.users.status.eq("active"),
});

// DELETE - Tuple syntax for multiple conditions
var delete = zsq.DeleteBuilder.init(allocator, DB.users);
defer delete.deinit();
_ = delete.where(.{
    DB.users.age.lt(18),
    DB.users.verified.eq(false),
});
```

## 📊 Current Feature Status

### ✅ Fully Implemented
- Basic SELECT with tuple syntax
- WHERE conditions (including nested AND/OR logical expressions)
- All JOIN types (INNER, LEFT, RIGHT)
- ORDER BY with multiple fields
- LIMIT and OFFSET
- GROUP BY and HAVING
- INSERT/UPDATE/DELETE builders with ergonomic API
- Type-safe field operators
- Compile-time validation
- **IN operator** - `.in(.{1, 2, 3})`
- **BETWEEN operator** - `.between(min, max)`
- **NOT operator** - `.not()`
- **DISTINCT** - `selectDistinct()`

### ⚠️ Coming Soon (Phase 1)
- Subqueries

See [FEATURE_STATUS.md](FEATURE_STATUS.md) for complete roadmap.

## 🔨 Building & Testing

```bash
# Run all tests
zig build test

# Run type-safe query builder tests
zig test src/core/type_safe.zig

# Run the ergonomic API demo
zig build run-ergonomic_api_demo

# Run other examples
zig build run-basic
zig build run-joins
zig build run-advanced
```

## 📚 Documentation

- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Quick reference for all features
- **[ERGONOMIC_API.md](ERGONOMIC_API.md)** - Complete API documentation
- **[SQLITE_DIALECT_GUIDE.md](SQLITE_DIALECT_GUIDE.md)** - SQLite features reference
- **[FEATURE_STATUS.md](FEATURE_STATUS.md)** - Implementation status & roadmap
- **[ZIG_0.15_UPGRADE.md](ZIG_0.15_UPGRADE.md)** - Zig 0.15 migration notes

## 📦 Project Structure

```
zig-structure-queries/
├── src/
│   ├── zsq.zig                 # Main module entry point
│   └── core/
│       ├── type_safe.zig       # Type-safe query builder (main!)
│       ├── mutations.zig       # INSERT/UPDATE/DELETE
│       ├── aggregates.zig      # COUNT, SUM, AVG, etc.
│       ├── database.zig        # Database abstraction
│       └── simple_query.zig    # Runtime query builder (legacy)
├── examples/
│   ├── ergonomic_api_demo.zig  # Showcase of ergonomic API
│   ├── basic.zig
│   ├── joins.zig
│   └── advanced.zig
├── QUICK_REFERENCE.md          # Quick start guide
├── ERGONOMIC_API.md            # Complete API docs
├── SQLITE_DIALECT_GUIDE.md     # SQLite features
└── FEATURE_STATUS.md           # Implementation roadmap
```

## 💡 Design Philosophy

1. **Type Safety First**: Catch errors at compile time, not runtime
2. **Zero Cost Abstractions**: No runtime overhead for type safety
3. **Ergonomic API**: Clean, readable syntax that flows naturally
4. **Explicit Over Implicit**: Clear about what's happening
5. **Zig-Native**: Use Zig's strengths, don't fight them

## 🎯 Comparison with Other Languages

### Swift StructuredQueries
```swift
let query = users
    .select(\.name, \.age)
    .where(\.age > 25)
    .orderBy(\.age, .desc)
```

### Our Zig Implementation
```zig
_ = query
    .select(.{ DB.users.name, DB.users.age })
    .where(.{ DB.users.age.gt(25) })
    .orderBy(.{ DB.users.age.desc() });
```

While Zig doesn't have Swift's key paths or variadic generics, we achieve comparable ergonomics with tuple syntax and compile-time metaprogramming!

## 🚧 Known Limitations

- Runtime `QueryBuilder` cannot infer result types (strict/comptime path can)
- Subqueries/CTEs are not integrated into the strict/comptime builder yet
- Aggregate expression integration is partial and still evolving
- `whereRaw(...)` is an intentional escape hatch and should use trusted SQL fragments

See [FEATURE_STATUS.md](FEATURE_STATUS.md) for details and workarounds.

## 🤝 Contributing

Contributions welcome! Key areas:

1. **Subqueries/CTEs**: Integrate with strict/comptime builder
2. **Aggregate Integration**: Expand typed aggregate expression support
3. **SQLite Dialect Coverage**: Add helper APIs while preserving raw escape hatches
4. **Documentation**: Keep guides/examples synchronized with current API

## 📄 License

MIT

## 🙏 Acknowledgments

- Inspired by [Swift Structured Queries](https://github.com/pointfreeco/swift-structured-queries)
- Built for Zig 0.15.2+
- Thanks to the Zig community for feedback and support

---

**Status**: ✅ Production Ready for SQLite Query Building
**Zig Version**: 0.15.2
**Last Updated**: February 2026

🌟 If you find this useful, consider starring the repo!
