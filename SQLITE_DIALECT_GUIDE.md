# SQLite Dialect Support Guide

## Overview
This document covers SQLite's SQL dialect features and their implementation status in our query builder.

## 🎯 Currently Implemented Features

### ✅ SELECT Queries
- [x] Basic SELECT with field selection
- [x] SELECT * (implicit when no fields specified)
- [x] Multiple field selection with tuples
- [x] Field aliasing (via manual specification)

### ✅ JOIN Operations
- [x] INNER JOIN
- [x] LEFT JOIN / LEFT OUTER JOIN
- [x] RIGHT JOIN / RIGHT OUTER JOIN
- [x] CROSS JOIN (via cartesian product)
- [x] Join conditions with `eqField()`

### ✅ WHERE Clauses
- [x] Comparison operators: `=`, `!=`, `>`, `>=`, `<`, `<=`
- [x] LIKE pattern matching
- [x] IS NULL / IS NOT NULL
- [x] Multiple conditions (automatically AND'd)
- [x] Type-safe operators per field type

### ✅ ORDER BY
- [x] ASC / DESC ordering
- [x] Multiple fields ordering with tuples

### ✅ LIMIT & OFFSET
- [x] LIMIT clause
- [x] OFFSET clause

### ✅ GROUP BY & HAVING
- [x] GROUP BY with single/multiple fields
- [x] HAVING clause with conditions

### ✅ Operators
```zig
// Numeric comparisons
.eq(value)    // =
.neq(value)   // !=
.gt(value)    // >
.gte(value)   // >=
.lt(value)    // <
.lte(value)   // <=

// String operations
.like(pattern)  // LIKE

// NULL checks
.isNull()       // IS NULL
.isNotNull()    // IS NOT NULL

// Field comparisons (for JOINs)
.eqField(otherField)  // field1 = field2
```

## ⚠️ Partially Implemented Features

### ⚠️ Aggregate Functions
Currently limited support. Available in separate `Aggregates` module:
- [x] COUNT(*)
- [x] COUNT(DISTINCT field)
- [x] SUM(field)
- [x] AVG(field)
- [x] MAX(field)
- [x] MIN(field)

**Missing**: Integration with main QueryBuilder

### ⚠️ Logical Operators
- [x] AND (automatic for multiple WHERE conditions)
- [ ] OR conditions
- [ ] NOT operator
- [ ] Complex parenthesized expressions

## ❌ Missing SQLite Features

### Critical Missing Features

#### 1. OR Conditions
```sql
-- Not currently supported:
SELECT * FROM users
WHERE age > 18 OR status = 'premium'
```

**Proposed API:**
```zig
_ = query
    .where(DB.users.age.gt(18).or_(DB.users.status.eq("premium")));
```

#### 2. IN Operator
```sql
-- Not currently supported:
SELECT * FROM users WHERE id IN (1, 2, 3, 4)
SELECT * FROM users WHERE status IN ('active', 'premium')
```

**Proposed API:**
```zig
_ = query.where(DB.users.id.in(&[_]i32{1, 2, 3, 4}));
_ = query.where(DB.users.status.in(&[_][]const u8{"active", "premium"}));
```

#### 3. BETWEEN Operator
```sql
-- Not currently supported:
SELECT * FROM users WHERE age BETWEEN 18 AND 65
```

**Proposed API:**
```zig
_ = query.where(DB.users.age.between(18, 65));
```

#### 4. Subqueries
```sql
-- Not currently supported:
SELECT * FROM users
WHERE id IN (SELECT user_id FROM posts WHERE views > 1000)
```

#### 5. DISTINCT
```sql
-- Not currently supported:
SELECT DISTINCT status FROM users
```

**Proposed API:**
```zig
_ = query
    .selectDistinct(DB.users.status)
    .from(DB.users);
```

### Advanced SQLite Features

#### 6. CASE Expressions
```sql
SELECT name,
  CASE
    WHEN age < 18 THEN 'minor'
    WHEN age < 65 THEN 'adult'
    ELSE 'senior'
  END as age_group
FROM users
```

#### 7. Window Functions
```sql
SELECT
  name,
  age,
  ROW_NUMBER() OVER (ORDER BY age DESC) as rank
FROM users
```

#### 8. Common Table Expressions (CTEs / WITH)
```sql
WITH adult_users AS (
  SELECT * FROM users WHERE age >= 18
)
SELECT * FROM adult_users WHERE status = 'active'
```

#### 9. UNION / INTERSECT / EXCEPT
```sql
SELECT name FROM users_table1
UNION
SELECT name FROM users_table2
```

#### 10. INSERT / UPDATE / DELETE Operations
Currently no mutation support in type-safe builder.

**Note**: There's a separate `mutations.zig` file, but integration with QueryBuilder is needed.

### String Functions

#### 11. String Manipulation
```sql
SELECT
  UPPER(name) as name_upper,
  LOWER(email) as email_lower,
  LENGTH(description) as desc_length,
  SUBSTR(content, 1, 100) as preview
FROM users
```

#### 12. String Concatenation
```sql
SELECT first_name || ' ' || last_name as full_name
FROM users
```

### Date/Time Functions

#### 13. DateTime Operations
```sql
SELECT
  date('now') as today,
  datetime('now', '+1 day') as tomorrow,
  strftime('%Y-%m', created_at) as month
FROM users
```

### JSON Support

#### 14. JSON Functions (SQLite 3.38+)
```sql
SELECT
  json_extract(metadata, '$.name') as extracted_name,
  json_array_length(tags) as tag_count
FROM documents
```

## 🔧 Recommended Implementation Priority

### High Priority (Essential)
1. **OR conditions** - Critical for complex queries
2. **IN operator** - Very common use case
3. **DISTINCT** - Frequently needed
4. **BETWEEN** - Common range queries

### Medium Priority (Important)
5. **NOT operator** - Logical completeness
6. **Subqueries** - Advanced queries
7. **String functions** - Data manipulation
8. **Aggregate functions integration** - Already have them, need to integrate

### Lower Priority (Nice to Have)
9. **CASE expressions** - Complex logic
10. **Window functions** - Advanced analytics
11. **CTEs** - Query organization
12. **Set operations** - UNION, INTERSECT, EXCEPT
13. **JSON functions** - Modern SQLite feature

## 💡 Implementation Examples

### How to Add OR Support

```zig
// In type_safe.zig

pub const LogicalExpr = union(enum) {
    and_: struct {
        left: *Condition,
        right: *Condition,
    },
    or_: struct {
        left: *Condition,
        right: *Condition,
    },
    not: *Condition,
    single: Condition,
};

// Add to Condition struct:
pub fn or_(self: Condition, other: Condition) LogicalExpr {
    return LogicalExpr{
        .or_ = .{
            .left = &self,
            .right = &other
        }
    };
}

// Usage:
_ = query.where(
    DB.users.age.gt(18).or_(DB.users.status.eq("premium"))
);
```

### How to Add IN Operator

```zig
// In Field type:
pub fn in(self: Self, values: []const T) Condition {
    return Condition{
        .field = self.toFieldRef(),
        .op = .in,
        .value = Value.fromArray(values),
    };
}

// Add to Value union:
pub const Value = union(enum) {
    // ... existing variants
    array_int: []const i64,
    array_string: []const []const u8,

    pub fn fromArray(values: anytype) Value {
        const T = @TypeOf(values);
        const child_type = @typeInfo(T).Pointer.child;

        switch (@typeInfo(child_type)) {
            .int => return .{ .array_int = values },
            .pointer => return .{ .array_string = values },
            else => @compileError("Unsupported array type"),
        }
    }
};

// Usage:
_ = query.where(DB.users.id.in(&[_]i32{1, 2, 3}));
```

### How to Add BETWEEN

```zig
// In Field type:
pub fn between(self: Self, min: T, max: T) Condition {
    return Condition{
        .field = self.toFieldRef(),
        .op = .between,
        .value = Value.fromRange(min, max),
    };
}

// Add to Value union:
pub const Value = union(enum) {
    // ... existing variants
    range_int: struct { min: i64, max: i64 },
    range_float: struct { min: f64, max: f64 },

    pub fn fromRange(min: anytype, max: anytype) Value {
        switch (@typeInfo(@TypeOf(min))) {
            .int => return .{
                .range_int = .{
                    .min = @intCast(min),
                    .max = @intCast(max)
                }
            },
            .float => return .{
                .range_float = .{
                    .min = @floatCast(min),
                    .max = @floatCast(max)
                }
            },
            else => @compileError("Unsupported range type"),
        }
    }
};

// SQL generation:
pub fn toSql(self: Value, writer: anytype) !void {
    switch (self) {
        .range_int => |r| try writer.print("{} AND {}", .{r.min, r.max}),
        .range_float => |r| try writer.print("{} AND {}", .{r.min, r.max}),
        // ... other cases
    }
}

// Usage:
_ = query.where(DB.users.age.between(18, 65));
```

## 🎯 Current API Completeness

| Feature Category | Support Level | Notes |
|-----------------|---------------|-------|
| Basic SELECT | ✅ Complete | Tuple syntax, aliasing |
| JOINs | ✅ Complete | All join types supported |
| WHERE (simple) | ✅ Complete | Basic comparisons, LIKE, NULL |
| WHERE (complex) | ⚠️ Partial | Missing OR, IN, BETWEEN |
| ORDER BY | ✅ Complete | Multiple fields, ASC/DESC |
| LIMIT/OFFSET | ✅ Complete | Full support |
| GROUP BY/HAVING | ✅ Complete | Tuple syntax support |
| Aggregates | ⚠️ Separate | Needs integration |
| Mutations | ⚠️ Separate | INSERT/UPDATE/DELETE exist but not integrated |
| Subqueries | ❌ None | Not implemented |
| Set Operations | ❌ None | UNION, etc. not supported |
| Functions | ❌ None | String, date, math functions |

## 📝 SQLite-Specific Features We Should Support

### PRAGMA Statements
```sql
PRAGMA table_info(users);
PRAGMA foreign_keys = ON;
```

### ATTACH/DETACH Databases
```sql
ATTACH DATABASE 'other.db' AS other;
SELECT * FROM other.users;
```

### RETURNING Clause (SQLite 3.35+)
```sql
INSERT INTO users (name, email)
VALUES ('John', 'john@example.com')
RETURNING id, created_at;
```

### UPSERT (ON CONFLICT)
```sql
INSERT INTO users (id, name, email)
VALUES (1, 'John', 'john@example.com')
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  email = excluded.email;
```

## 🚀 Next Steps

To achieve full SQLite coverage, we should implement in this order:

1. **Phase 1: Essential Operators** (1-2 days)
   - OR conditions
   - IN operator
   - BETWEEN operator
   - NOT operator

2. **Phase 2: Query Features** (2-3 days)
   - DISTINCT
   - Aggregate function integration
   - String concatenation
   - Basic string functions (UPPER, LOWER, LENGTH)

3. **Phase 3: Advanced Features** (3-5 days)
   - Subqueries
   - CASE expressions
   - Common string/date functions
   - Better alias support

4. **Phase 4: Mutations Integration** (2-3 days)
   - Integrate INSERT/UPDATE/DELETE with type-safe builder
   - RETURNING clause support
   - UPSERT support

5. **Phase 5: Advanced SQL** (5+ days)
   - CTEs (WITH clauses)
   - Window functions
   - Set operations
   - Full JSON support

---

**Current Status**: Phase 0 Complete (Basic query building with ergonomic API)
**Next Target**: Phase 1 (Essential Operators)
