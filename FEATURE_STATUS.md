# Feature Status & Roadmap

## 📊 Current Implementation Status

### ✅ Fully Implemented & Tested

#### Query Building (SELECT)
- **Module**: `src/core/type_safe.zig`
- **Status**: ✅ Production Ready with Ergonomic API

Features:
- ✅ SELECT with tuple syntax: `.select(.{ field1, field2, field3 })`
- ✅ FROM clause
- ✅ WHERE with multiple conditions (tuple syntax)
- ✅ ORDER BY with ASC/DESC (tuple syntax)
- ✅ LIMIT and OFFSET
- ✅ GROUP BY with tuple syntax
- ✅ HAVING with tuple syntax
- ✅ All JOIN types: INNER, LEFT, RIGHT, CROSS
- ✅ Infallible chaining (no `try` needed on builder methods)
- ✅ Type-safe field operators
- ✅ Compile-time field validation

Operators Available:
```zig
.eq(value)      // =
.neq(value)     // !=
.gt(value)      // >
.gte(value)     // >=
.lt(value)      // <
.lte(value)     // <=
.like(pattern)  // LIKE
.in(values)     // IN (...)
.between(min, max) // BETWEEN
.isNull()       // IS NULL
.isNotNull()    // IS NOT NULL
.not()          // NOT (...)
.or_(other)     // (a) OR (b)
.eqField(field) // field1 = field2 (for JOINs)
```

Example Usage:
```zig
var query = QueryBuilder.init(allocator);
defer query.deinit();

_ = query
    .select(.{ DB.users.name, DB.users.age, DB.users.email })
    .from(DB.users)
    .where(.{
        DB.users.age.gt(18),
        DB.users.email.like("%@gmail.com"),
    })
    .orderBy(.{ DB.users.age.desc(), DB.users.name.asc() })
    .limit(10);

const sql = try query.toSql();
defer allocator.free(sql);
```

#### Mutations (INSERT/UPDATE/DELETE)
- **Module**: `src/core/mutations.zig`
- **Status**: ✅ Implemented with infallible chaining

Features:
- ✅ INSERT with multiple values
- ✅ INSERT with RETURNING clause
- ✅ UPDATE with SET clauses
- ✅ UPDATE with WHERE conditions
- ✅ DELETE with WHERE conditions

Example Usage (Current API):
```zig
// INSERT
var insert = InsertBuilder.init(allocator, DB.users);
defer insert.deinit();
_ = insert.value(DB.users.name, "John");
_ = insert.value(DB.users.age, 30);
_ = insert.returning("id");
const sql = try insert.toSql();

// UPDATE
var update = UpdateBuilder.init(allocator, DB.users);
defer update.deinit();
_ = update.set(DB.users.name, "Jane");
_ = update.where(DB.users.id.eq(1));
const sql = try update.toSql();

// DELETE
var delete = DeleteBuilder.init(allocator, DB.users);
defer delete.deinit();
_ = delete.where(DB.users.id.eq(1));
const sql = try delete.toSql();
```

#### Aggregates
- **Module**: `src/core/aggregates.zig`
- **Status**: ✅ Implemented but not integrated with QueryBuilder

Functions Available:
```zig
count()              // COUNT(*)
countDistinct(field) // COUNT(DISTINCT field)
sum(field)           // SUM(field)
avg(field)           // AVG(field)
max(field)           // MAX(field)
min(field)           // MIN(field)
```

#### Database Abstraction
- **Module**: `src/core/database.zig`
- **Status**: ✅ Working with SQLite

Features:
- ✅ Database connection management
- ✅ Query execution
- ✅ Prepared statements
- ✅ Type-safe result mapping

### ⚠️ Needs Improvement

#### 1. Mutations Need TypeSafe Alignment
**Priority**: High
**Effort**: Medium (2-4 hours)

Mutations are ergonomic, but they currently use a separate `FieldRef` / `Condition` model from `src/core/type_safe.zig`. Aligning them would let mutations reuse the full operator set (`IN`, `BETWEEN`, `NOT`, etc.) and share compile-time validation.

```zig
// Proposed ergonomic API:
var insert = InsertBuilder.init(allocator, DB.users);
defer insert.deinit();

_ = insert
    .values(.{
        .{ DB.users.name, "John" },
        .{ DB.users.age, 30 },
        .{ DB.users.email, "john@example.com" },
    })
    .returning("id");

const sql = try insert.toSql();
```

#### 2. Aggregate Integration
**Priority**: Medium
**Effort**: Medium (2-3 hours)

Aggregates exist but aren't integrated with QueryBuilder. Should allow:

```zig
_ = query
    .select(.{
        DB.users.name,
        count(),
        avg(DB.posts.views),
    })
    .from(DB.users)
    .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
    .groupBy(DB.users.name);
```

### ✅ Implemented (Already In `src/core/type_safe.zig`)

The following were previously listed as missing, but are implemented and covered by tests:
- OR conditions via `.or_()`
- `IN` via `.in(...)`
- `BETWEEN` via `.between(min, max)`
- `NOT` via `.not()`
- `DISTINCT` via `.selectDistinct(...)`

### ❌ Not Implemented - Important

#### 6. Subqueries
**Priority**: Medium
**Effort**: High (5+ hours)
**Complexity**: Requires recursive query building

Proposed API:
```zig
const subquery = QueryBuilder.init(allocator);
_ = subquery
    .select(DB.posts.user_id)
    .from(DB.posts)
    .where(DB.posts.views.gt(1000));

_ = query
    .select(.{ DB.users.name, DB.users.email })
    .from(DB.users)
    .where(DB.users.id.inSubquery(subquery));

// Generated SQL:
// SELECT users.name, users.email
// FROM users
// WHERE users.id IN (SELECT posts.user_id FROM posts WHERE posts.views > 1000)
```

#### 7. String Functions
**Priority**: Medium
**Effort**: Medium (3-4 hours)

Proposed API:
```zig
_ = query
    .select(.{
        DB.users.name.upper().as("name_upper"),
        DB.users.email.lower(),
        DB.users.bio.length().as("bio_length"),
        DB.users.content.substr(1, 100).as("preview"),
    });

// Generated SQL:
// SELECT
//   UPPER(users.name) AS name_upper,
//   LOWER(users.email),
//   LENGTH(users.bio) AS bio_length,
//   SUBSTR(users.content, 1, 100) AS preview
```

#### 8. CASE Expressions
**Priority**: Medium
**Effort**: High (4-5 hours)

Proposed API:
```zig
const age_group = case()
    .when(DB.users.age.lt(18), "minor")
    .when(DB.users.age.lt(65), "adult")
    .else_("senior")
    .as("age_group");

_ = query
    .select(.{ DB.users.name, age_group })
    .from(DB.users);

// Generated SQL:
// SELECT users.name,
//   CASE
//     WHEN users.age < 18 THEN 'minor'
//     WHEN users.age < 65 THEN 'adult'
//     ELSE 'senior'
//   END AS age_group
// FROM users
```

#### 9. String Concatenation
**Priority**: Medium
**Effort**: Low (1-2 hours)

Proposed API:
```zig
_ = query
    .select(.{
        concat(.{ DB.users.first_name, " ", DB.users.last_name }).as("full_name"),
        DB.users.email,
    })
    .from(DB.users);

// Generated SQL:
// SELECT
//   first_name || ' ' || last_name AS full_name,
//   email
// FROM users
```

### ❌ Not Implemented - Advanced

#### 10. Common Table Expressions (CTEs)
**Priority**: Low
**Effort**: High (6+ hours)

#### 11. Window Functions
**Priority**: Low
**Effort**: High (6+ hours)

#### 12. Set Operations (UNION, INTERSECT, EXCEPT)
**Priority**: Low
**Effort**: Medium (3-4 hours)

#### 13. UPSERT (ON CONFLICT)
**Priority**: Medium
**Effort**: Medium (3-4 hours)

## 🎯 Recommended Implementation Order

### Phase 1: Critical Operators (Week 1)
**Total Effort**: ~12 hours

1. ✅ **OR conditions** (4 hours)
   - Most requested feature
   - Required for complex queries
   - Moderate complexity

2. ✅ **IN operator** (3 hours)
   - Very common use case
   - Straightforward implementation

3. ✅ **BETWEEN operator** (2 hours)
   - Common for range queries
   - Simple to implement

4. ✅ **DISTINCT** (1 hour)
   - Frequently needed
   - Easy to add

5. ✅ **NOT operator** (1 hour)
   - Logical completeness
   - Simple addition

6. ✅ **Update mutations to ergonomic API** (1 hour)
   - Consistency with QueryBuilder

### Phase 2: Integration & Functions (Week 2)
**Total Effort**: ~10 hours

7. ✅ **Aggregate integration** (3 hours)
   - Already have aggregates, just need to integrate

8. ✅ **String functions** (4 hours)
   - UPPER, LOWER, LENGTH, SUBSTR
   - Common data manipulation

9. ✅ **String concatenation** (1 hour)
   - Useful for display

10. ✅ **Better alias support** (2 hours)
    - Cleaner API for AS clauses

### Phase 3: Advanced Queries (Week 3-4)
**Total Effort**: ~20 hours

11. ✅ **Subqueries** (6 hours)
    - Complex but powerful

12. ✅ **CASE expressions** (5 hours)
    - Conditional logic in queries

13. ✅ **UPSERT support** (4 hours)
    - Modern SQLite feature

14. ✅ **Date/Time functions** (3 hours)
    - Common operations

15. ✅ **Math functions** (2 hours)
    - ROUND, ABS, etc.

### Phase 4: Expert Features (Future)
**Total Effort**: ~25+ hours

16. ⏭️ CTEs (WITH clauses)
17. ⏭️ Window functions
18. ⏭️ Set operations
19. ⏭️ JSON support
20. ⏭️ Full-text search

## 📝 Implementation Templates

### Template: Adding a New Operator

```zig
// 1. Add to Operator enum (type_safe.zig)
pub const Operator = enum {
    // ... existing
    between,  // NEW
    in,       // NEW

    pub fn toSql(self: Operator) []const u8 {
        return switch (self) {
            // ... existing
            .between => "BETWEEN",
            .in => "IN",
        };
    }
};

// 2. Extend Value union for new data types
pub const Value = union(enum) {
    // ... existing
    range_int: struct { min: i64, max: i64 },
    array_int: []const i64,

    pub fn toSql(self: Value, writer: anytype) !void {
        switch (self) {
            // ... existing
            .range_int => |r| try writer.print("{} AND {}", .{r.min, r.max}),
            .array_int => |arr| {
                try writer.writeAll("(");
                for (arr, 0..) |val, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{}", .{val});
                }
                try writer.writeAll(")");
            },
            else => {},
        }
    }
};

// 3. Add method to Field type
pub fn between(self: Self, min: T, max: T) Condition {
    return Condition{
        .field = self.toFieldRef(),
        .op = .between,
        .value = Value{ .range_int = .{ .min = min, .max = max } },
    };
}

pub fn in(self: Self, values: []const T) Condition {
    return Condition{
        .field = self.toFieldRef(),
        .op = .in,
        .value = Value{ .array_int = values },
    };
}
```

## 🧪 Testing Requirements

Each new feature must include:
1. ✅ Unit tests in the module file
2. ✅ Integration test showing real usage
3. ✅ SQL output verification
4. ✅ Example in demo file

## 📚 Documentation Requirements

Each new feature must have:
1. ✅ Entry in this FEATURE_STATUS.md
2. ✅ Example in SQLITE_DIALECT_GUIDE.md
3. ✅ Update to ERGONOMIC_API.md if API changes
4. ✅ Demo code in examples/

---

**Last Updated**: October 10, 2025
**Zig Version**: 0.15.0
**Status**: Phase 0 Complete, Ready for Phase 1
