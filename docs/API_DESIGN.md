# Zig Structured Queries - API Design Document

## Overview
This document captures the current state of our type-safe SQL query builder API, what we've achieved, and what limitations we've encountered with Zig's compile-time capabilities.

## Current Architecture

### Core Files (Clean Implementation)
- `src/core/type_safe.zig` - Main query builder with runtime construction
- `src/core/field_types.zig` - Type-specific field operators
- `src/core/simple_query.zig` - Legacy runtime query builder
- `src/core/database.zig` - Database abstraction layer

### Experimental/Archive
- `src/core/experimental/` - Contains all experimental approaches and explorations

## What We've Achieved ✅

### 1. Type-Safe Field Definitions
```zig
const DB = struct {
    pub const users = struct {
        pub const id = Field(i32, "users", "id");
        pub const name = Field([]const u8, "users", "name");
        pub const age = Field(i32, "users", "age");
        pub const active = Field(bool, "users", "active");
    };
};
```

### 2. Type-Specific Operators
Each field type gets only the operators that make semantic sense:

#### Numeric Fields (i32, f64)
- ✅ `.eq()`, `.neq()`, `.gt()`, `.lt()`, `.gte()`, `.lte()`
- ✅ `.between(min, max)`
- ✅ `.in(values)`
- ❌ `.like()` - Doesn't exist, won't compile

#### String Fields ([]const u8)
- ✅ `.eq()`, `.neq()`
- ✅ `.like()`, `.notLike()`
- ✅ `.startsWith()`, `.endsWith()`, `.contains()`
- ✅ `.in(values)`
- ❌ `.gt()`, `.lt()` - Don't exist, won't compile

#### Boolean Fields
- ✅ `.isTrue()`, `.isFalse()`
- ✅ `.eq()`, `.neq()`
- ❌ `.gt()`, `.like()` - Don't exist, won't compile

#### DateTime Fields
- ✅ `.before()`, `.after()`
- ✅ `.onOrBefore()`, `.onOrAfter()`
- ✅ `.between(start, end)`
- ❌ `.like()` - Doesn't exist, won't compile

### 3. Query Building (Runtime)

#### Basic Queries
```zig
var query = QueryBuilder.init(allocator);
defer query.deinit();

_ = try query.select(DB.users.name);
_ = try query.select(DB.users.age);
_ = query.from(DB.users);
_ = try query.where(DB.users.age.gt(25));
_ = try query.where(DB.users.name.like("%john%"));
_ = try query.orderBy(DB.users.age.desc());
_ = query.limit(10);

const sql = try query.toSql();
// Generates: SELECT users.name, users.age FROM users WHERE users.age > 25 AND users.name LIKE '%john%' ORDER BY users.age DESC LIMIT 10
```

#### JOIN Queries
```zig
_ = try query.select(DB.users.name);
_ = try query.select(DB.posts.title);
_ = query.from(DB.users);
_ = try query.join(DB.posts, DB.posts.user_id.eqField(DB.users.id));
_ = try query.leftJoin(DB.comments, DB.comments.post_id.eqField(DB.posts.id));
_ = try query.where(DB.posts.views.gt(100));
// Generates: SELECT users.name, posts.title FROM users INNER JOIN posts ON posts.user_id = users.id LEFT JOIN comments ON comments.post_id = posts.id WHERE posts.views > 100
```

#### Aggregate Functions
```zig
_ = try query.select(DB.users.name);
_ = try query.select(count(DB.posts.id).as("post_count"));
_ = try query.select(avg(DB.posts.views).as("avg_views"));
_ = query.from(DB.users);
_ = try query.join(DB.posts, DB.posts.user_id.eqField(DB.users.id));
_ = try query.groupBy(DB.users.id);
_ = try query.groupBy(DB.users.name);
_ = try query.having(count(DB.posts.id).gt(5));
// Generates: SELECT users.name, COUNT(posts.id) AS post_count, AVG(posts.views) AS avg_views FROM users INNER JOIN posts ON posts.user_id = users.id GROUP BY users.id, users.name HAVING COUNT(posts.id) > 5
```

### 4. Type Safety Guarantees
- **Compile-time field validation**: Can't reference non-existent fields
- **Type-appropriate operators**: Can't use wrong operators for field types
- **No runtime type checking needed**: All validation at compile time

### 5. Advanced Query Features (NEW!)
- **JOIN Support**: INNER, LEFT, RIGHT joins with type-safe field comparisons
- **GROUP BY**: Group results by one or more fields
- **HAVING**: Filter grouped results
- **Aggregate Functions**: COUNT, SUM, AVG, MAX, MIN with aliasing
- **COUNT(DISTINCT)**: Count unique values
- **OFFSET**: Pagination support alongside LIMIT

### 6. Data Mutations (NEW!)
- **INSERT Builder**: Type-safe inserts with RETURNING support
- **UPDATE Builder**: Type-safe updates with WHERE conditions
- **DELETE Builder**: Type-safe deletes with WHERE conditions

#### INSERT Example
```zig
var insert = InsertBuilder.init(allocator, DB.users);
_ = try insert.value(DB.users.name, "John Doe");
_ = try insert.value(DB.users.email, "john@example.com");
_ = try insert.value(DB.users.age, 30);
_ = insert.returning("id");
// Generates: INSERT INTO users (name, email, age) VALUES ('John Doe', 'john@example.com', 30) RETURNING id
```

#### UPDATE Example
```zig
var update = UpdateBuilder.init(allocator, DB.users);
_ = try update.set(DB.users.name, "Jane Doe");
_ = try update.set(DB.users.age, 31);
_ = try update.where(DB.users.id.eq(1));
// Generates: UPDATE users SET name = 'Jane Doe', age = 31 WHERE users.id = 1
```

#### DELETE Example
```zig
var delete = DeleteBuilder.init(allocator, DB.posts);
_ = try delete.where(DB.posts.user_id.eq(5));
_ = try delete.where(DB.posts.created_at.lt("2023-01-01"));
// Generates: DELETE FROM posts WHERE posts.user_id = 5 AND posts.created_at < '2023-01-01'
```

## What We Wanted But Couldn't Achieve ❌

### 1. Automatic Field Generation from Schema
**Wanted:**
```zig
const DB = struct {
    pub const schema = .{
        .users = .{ .id = i32, .name = []const u8, .age = i32 },
    };
    pub usingnamespace GenerateTables(schema);
};

// Then use: DB.users.id.eq(5)
```

**Why it failed:** Zig's fundamental comptime limitation:
- **Cannot dynamically generate `pub const` struct fields at compile time**
- Struct field declarations must be known at **parse time**, not compile time
- `@field()` can only set field values, not create new field declarations
- `inline for` cannot generate new struct field declarations
- `usingnamespace` requires a type known at parse time

**The Core Issue:**
```zig
// This is what we need to generate:
pub const id = Field(i32, "users", "id");

// But at comptime, we can only:
// 1. Set values of existing fields
// 2. Create new types
// 3. Call functions
// We CANNOT add new field declarations to a struct
```

**What we have instead:** Manual field declarations
```zig
pub const users = struct {
    pub const id = Field(i32, "users", "id");
    pub const name = Field([]const u8, "users", "name");
};
```
This is more verbose but works reliably and is still type-safe.

### 2. Full Compile-Time Query Building with Method Chaining
**Wanted:**
```zig
const query = Query(DB)
    .select(.{ DB.users.name, DB.users.age })
    .from(DB.users)
    .where(DB.users.age.gt(25))
    .limit(10);

// Everything resolved at compile time
const sql = query.sql; // Known at compile time
const ResultType = query.ResultType; // Inferred at compile time
```

**Why it failed:** Zig's comptime limitations:
- Complex state tracking through method chaining hits comptime evaluation limits
- Arrays and slices in comptime contexts have restrictions
- Recursive type generation issues

**What we have instead:** Runtime query building with compile-time field validation

### 3. Automatic Result Type Inference
**Wanted:**
```zig
const results = try query.execute(db);
// results: []struct { name: []const u8, age: i32 } - automatically inferred
```

**Why it failed:** 
- Would need full compile-time query resolution
- Dynamic struct generation based on selected fields is complex

**What we have instead:** Manual result type specification

## Zig Limitations We Encountered

1. **Comptime field generation**: Can't use `@field()` to dynamically create public constants
2. **Complex comptime state**: Method chaining with state accumulation hits limits
3. **Comptime arrays**: Restrictions on array manipulation in comptime contexts
4. **Recursive types**: Union/struct types can't be self-referential (Value type issue)
5. **Generic constraints**: No way to express "T must be numeric" as a constraint

## Current Best Practices

### Schema Definition
```zig
const DB = zsq.schema(.{
    .users = zsq.table("users", .{
        .id = zsq.col(i32),
        .name = zsq.col([]const u8),
        .age = zsq.col(i32),
    }),
});
```

### Query Building
```zig
// Runtime construction with compile-time validation
var query = QueryBuilder.init(allocator);
defer query.deinit();

// Each operation validated at compile time
_ = query.select(DB.users.name);  // Field exists, correct type
_ = query.where(DB.users.age.gt(25));  // .gt() valid for numeric
```

## Comparison with Other Languages

### What Swift StructuredQueries Can Do (That We Can't)
- Full compile-time query resolution
- Automatic result type inference
- Complex generic constraints
- Macro-based code generation

### What We Can Do (That's Still Impressive)
- Type-safe field references
- Compile-time operator validation
- Zero runtime overhead for field definitions
- Clean, explicit API without macros

## Future Improvements (When Zig Evolves)

1. **If Zig adds better comptime struct generation:**
   - Could achieve automatic field generation from schema
   - Could generate result types automatically

2. **If Zig improves comptime evaluation limits:**
   - Could do full compile-time query building
   - Could track complex state through method chains

3. **If Zig adds generic constraints:**
   - Could have cleaner type-specific field definitions
   - Could express "numeric types only" constraints

## Summary

### What Works Well ✅
- Type-safe field definitions with appropriate operators
- Compile-time validation of field usage
- Clean separation of concerns (fields, conditions, query building)
- Practical, usable API despite limitations

### What's Pragmatic 🤝
- Runtime query building (instead of full compile-time)
- Manual field declarations (instead of automatic generation)
- Explicit type specification (instead of inference)

### What's Still Type-Safe 🛡️
- Can't use wrong operators on fields
- Can't reference non-existent fields
- Can't mix incompatible types
- All validation at compile time, no runtime checks

## Conclusion

We've achieved a **practical, type-safe SQL query builder** that provides compile-time guarantees within Zig's current capabilities. While we couldn't achieve everything we wanted (like Swift's StructuredQueries), we have a solid foundation that:

1. **Prevents common SQL errors at compile time**
2. **Provides type-appropriate operations**
3. **Has a clean, understandable API**
4. **Works reliably with current Zig**

The gap between "ideal" and "achieved" is mostly due to Zig's evolving compile-time capabilities, not fundamental design issues. As Zig matures, we can enhance the API without breaking changes.
