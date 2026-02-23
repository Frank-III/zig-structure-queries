# Software Design Document: Zig Structured Queries (ZSQ)
## A Swift-Inspired, Comptime-Powered Query Builder for Zig

### Executive Summary

This document outlines the design for **Zig Structured Queries (ZSQ)**, a type-safe SQL query builder that combines the elegant API design of Swift Structured Queries with Zig's powerful compile-time capabilities. Unlike the original CORM proposal which focused on complex type state machines, ZSQ takes a pragmatic approach inspired by Swift's successful patterns while leveraging Zig's unique strengths.

**Key Innovation**: Where Swift relies on macros and protocols, ZSQ uses Zig's `comptime` to achieve superior compile-time validation, zero runtime overhead, and perfect type safety—all while maintaining a clean, intuitive API.

---

## 1. Vision & Goals

### Core Philosophy
"Write SQL queries in Zig that are impossible to get wrong at compile time."

### Primary Goals

1. **Swift-like Ergonomics**: Adopt the proven, intuitive API patterns from Swift Structured Queries
2. **Comptime Supremacy**: Leverage Zig's compile-time execution for validation that Swift cannot achieve
3. **Zero-Cost Abstraction**: All query building happens at compile time—runtime sees only optimized SQL strings
4. **Progressive Disclosure**: Simple queries are simple to write; complex queries are possible
5. **Learn from Both**: Combine JetQuery's SQL generation with Swift's API design

### Non-Goals

- Creating a full ORM (we're a query builder)
- Supporting every SQL dialect initially (start with SQLite, PostgreSQL)
- Replacing all SQL knowledge (developers should understand SQL)

---

## 2. Architecture Overview

### Three-Layer Design

```
┌─────────────────────────────────────┐
│         User API Layer              │  <- Swift-inspired chainable methods
├─────────────────────────────────────┤
│     Comptime Validation Layer       │  <- Zig's unique strength
├─────────────────────────────────────┤
│      SQL Generation Layer           │  <- Adapted from JetQuery
└─────────────────────────────────────┘
```

### Key Components

1. **Schema Definition** (`@Table` equivalent)
   - Simple struct-based table definitions
   - Comptime validation of all fields
   - Automatic column type inference

2. **Query Builder** (Swift-inspired API)
   - Chainable method syntax
   - Type-safe column references
   - Comptime-validated predicates

3. **SQL Renderer** (JetQuery-inspired)
   - Adapter pattern for different databases
   - Parameterized query generation
   - Bind parameter management

4. **Result Types** (Beyond Swift)
   - Automatic result struct generation
   - Perfect type matching with queries
   - Zero allocation patterns

---

## 3. Detailed Design

### 3.1 Schema Definition

Unlike Swift's macro-based approach, ZSQ uses simple Zig structs with comptime helpers:

```zig
// User defines their schema
const Reminder = struct {
    id: i32,
    title: []const u8,
    is_completed: bool,
    priority: ?i32,
    created_at: DateTime,
    
    // Comptime configuration
    pub const Config = TableConfig{
        .name = "reminders",
        .primary_key = "id",
    };
};

// Alternative: Use a helper function for common patterns
const User = Table(struct {
    id: i32,
    email: []const u8,
    name: []const u8,
}, .{
    .name = "users",
    .indexes = .{ .{ "email", .unique = true } },
});
```

**Key Advantages Over Swift**:
- No macro preprocessing needed
- Full IDE support and debugging
- Can inspect and modify at comptime

### 3.2 Query Builder API

Inspired by Swift's elegant syntax but powered by Zig's comptime:

```zig
// Simple select
const query = Query(Reminder)
    .where(.{ .is_completed = false })
    .order(.{ .priority = .desc })
    .limit(10);

// Complex query with joins
const results = Query(RemindersList)
    .join(Reminder, .{ .id = .reminders_list_id })
    .where(.{ .reminder.is_completed = false })
    .select(.{ 
        .list_title = .title,
        .reminder_count = count(.reminder.id),
    })
    .group(.{ .id });

// Comptime validation examples
Query(Reminder)
    .where(.{ .nonexistent = true })  // ❌ Compile error: Field 'nonexistent' not found

Query(Reminder)
    .where(.{ .priority = "high" })   // ❌ Compile error: Type mismatch: expected ?i32, got []const u8
```

### 3.3 Comptime Validation Engine

This is where ZSQ truly shines compared to Swift:

```zig
fn validateQuery(comptime T: type, comptime query_spec: QuerySpec) void {
    comptime {
        // Validate all fields exist
        for (query_spec.selections) |field| {
            if (!@hasField(T, field.name)) {
                @compileError("Unknown field: " ++ field.name);
            }
        }
        
        // Validate type compatibility
        for (query_spec.where_clauses) |clause| {
            const field_type = @TypeOf(@field(@as(T, undefined), clause.field));
            if (!isCompatible(field_type, clause.value_type)) {
                @compileError("Type mismatch in WHERE clause");
            }
        }
        
        // Validate joins
        for (query_spec.joins) |join| {
            validateJoinCondition(T, join.table, join.condition);
        }
    }
}
```

### 3.4 SQL Generation

Adapted from JetQuery but simplified and enhanced:

```zig
fn renderSQL(comptime query: QuerySpec, comptime adapter: Adapter) []const u8 {
    comptime {
        var buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();
        
        // SELECT clause
        try writer.writeAll("SELECT ");
        for (query.selections, 0..) |col, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s}.{s}", .{ 
                adapter.quote(col.table), 
                adapter.quote(col.name) 
            });
        }
        
        // FROM clause
        try writer.print(" FROM {s}", .{adapter.quote(query.table_name)});
        
        // WHERE clause
        if (query.where_clauses.len > 0) {
            try writer.writeAll(" WHERE ");
            try renderWhere(writer, query.where_clauses, adapter);
        }
        
        return stream.getWritten();
    }
}
```

### 3.5 Advanced Features

#### Dynamic Result Types
```zig
// Automatically generate result type based on selection
const query = Query(Reminder)
    .select(.{ .title, .priority });

// ResultType is automatically: struct { title: []const u8, priority: ?i32 }
const results = try db.execute(query);
```

#### Safe SQL Fragments (Like Swift's #sql)
```zig
const query = Query(Reminder)
    .where(sql("date({}) < date('now')", .{.created_at}));
```

#### Subqueries and CTEs
```zig
const high_priority = Query(Reminder)
    .where(.{ .priority = .{ .gt = 2 } })
    .as("high_priority");

const query = With(high_priority)
    .query(Query("high_priority").count());
```

---

## 4. Implementation Roadmap

### Phase 1: Core Foundation (Weeks 1-2)
- [x] Define basic table schema structure
- [ ] Implement simple SELECT query builder
- [ ] Basic WHERE clause support
- [ ] Comptime field validation
- [ ] SQLite adapter

**Deliverable**: Can write simple SELECT queries with WHERE clauses

### Phase 2: Swift Feature Parity (Weeks 3-4)
- [ ] JOIN support (INNER, LEFT, RIGHT)
- [ ] GROUP BY and HAVING
- [ ] ORDER BY and LIMIT
- [ ] Aggregate functions (COUNT, SUM, AVG, etc.)
- [ ] Result type generation

**Deliverable**: Most Swift Structured Queries features working

### Phase 3: Zig-Specific Enhancements (Weeks 5-6)
- [ ] Comptime query optimization
- [ ] Zero-allocation result streaming
- [ ] Compile-time SQL validation
- [ ] Custom function support
- [ ] Transaction helpers

**Deliverable**: Features that showcase Zig's advantages

### Phase 4: Production Ready (Weeks 7-8)
- [ ] PostgreSQL adapter
- [ ] Comprehensive testing
- [ ] Performance benchmarks
- [ ] Documentation and examples
- [ ] Migration guide from JetQuery

**Deliverable**: Production-ready library

---

## 5. Code Examples

### Basic CRUD Operations

```zig
// INSERT
const insert = Insert(Reminder, .{
    .title = "Buy groceries",
    .is_completed = false,
    .priority = 2,
});

// SELECT
const active_reminders = Query(Reminder)
    .where(.{ .is_completed = false })
    .order(.{ .priority = .desc, .created_at = .asc });

// UPDATE
const update = Update(Reminder)
    .set(.{ .is_completed = true })
    .where(.{ .id = reminder_id });

// DELETE
const delete = Delete(Reminder)
    .where(.{ 
        .is_completed = true,
        .created_at = .{ .lt = "2024-01-01" },
    });
```

### Complex Query Example

```zig
// Find users with their incomplete high-priority reminders
const UserWithReminders = struct {
    user_name: []const u8,
    email: []const u8,
    reminder_count: i64,
    titles: []const u8,  // GROUP_CONCAT result
};

const query = Query(User)
    .join(Reminder, .{ .id = .user_id })
    .where(.{
        .reminder = .{
            .is_completed = false,
            .priority = .{ .gte = 3 },
        },
    })
    .select(UserWithReminders, .{
        .user_name = .user.name,
        .email = .user.email,
        .reminder_count = count(.reminder.id),
        .titles = group_concat(.reminder.title, ", "),
    })
    .group(.{ .user.id })
    .having(.{ count(.reminder.id) = .{ .gt = 5 } });

// Compile-time generated SQL:
// SELECT 
//   "users"."name" AS "user_name",
//   "users"."email" AS "email",
//   COUNT("reminders"."id") AS "reminder_count",
//   GROUP_CONCAT("reminders"."title", ', ') AS "titles"
// FROM "users"
// JOIN "reminders" ON "users"."id" = "reminders"."user_id"
// WHERE "reminders"."is_completed" = ? 
//   AND "reminders"."priority" >= ?
// GROUP BY "users"."id"
// HAVING COUNT("reminders"."id") > ?
```

### Compile-Time Safety Examples

```zig
// ✅ These compile and work
Query(Reminder).where(.{ .priority = 3 })
Query(Reminder).where(.{ .priority = null })
Query(Reminder).where(.{ .title = .{ .like = "%urgent%" } })

// ❌ These fail at compile time
Query(Reminder).where(.{ .priorty = 3 })  // Typo in field name
Query(Reminder).where(.{ .priority = "high" })  // Wrong type
Query(Reminder).where(.{ .id = .{ .like = "%1%" } })  // LIKE on integer
Query(Reminder).join(NonExistentTable, .{})  // Unknown table
```

---

## 6. Comparison Matrix

| Feature | Swift Structured Queries | JetQuery | ZSQ (This Proposal) |
|---------|-------------------------|----------|---------------------|
| **API Ergonomics** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐ Good | ⭐⭐⭐⭐⭐ Excellent |
| **Compile-Time Safety** | ⭐⭐⭐⭐ Via Macros | ⭐⭐⭐ Basic | ⭐⭐⭐⭐⭐ Full Comptime |
| **Runtime Overhead** | ⭐⭐⭐ Some | ⭐⭐⭐⭐ Minimal | ⭐⭐⭐⭐⭐ Zero |
| **Error Messages** | ⭐⭐⭐⭐ Good | ⭐⭐⭐ Basic | ⭐⭐⭐⭐⭐ Excellent |
| **IDE Support** | ⭐⭐⭐⭐ Good | ⭐⭐⭐⭐ Good | ⭐⭐⭐⭐⭐ Excellent |
| **Learning Curve** | ⭐⭐⭐ Moderate | ⭐⭐⭐⭐ Easy | ⭐⭐⭐⭐ Easy |
| **Flexibility** | ⭐⭐⭐⭐ Good | ⭐⭐⭐ Limited | ⭐⭐⭐⭐⭐ Excellent |

---

## 7. Technical Challenges & Solutions

### Challenge 1: Column Name Resolution
**Problem**: How to reference columns in a type-safe way without strings?
**Solution**: Use Zig's `@field` and field enums:
```zig
.where(.{ .priority = 3 })  // Field name as identifier
.where(.{ @field("priority") = 3 })  // Dynamic field access
```

### Challenge 2: Result Type Generation
**Problem**: How to create result types that match the query?
**Solution**: Use `@Type()` to generate structs at compile time:
```zig
fn ResultType(comptime selections: []const Selection) type {
    comptime {
        var fields: [selections.len]std.builtin.Type.StructField = undefined;
        for (selections, 0..) |sel, i| {
            fields[i] = .{
                .name = sel.alias orelse sel.name,
                .type = sel.type,
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            };
        }
        return @Type(.{ .Struct = .{
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
            .layout = .auto,
        }});
    }
}
```

### Challenge 3: Operator Overloading
**Problem**: Zig doesn't support operator overloading like Swift
**Solution**: Use method chaining and struct literals:
```zig
// Instead of: where { $0.priority > 3 && $0.isCompleted == false }
.where(.{ 
    .priority = .{ .gt = 3 },
    .is_completed = false,
})
```

### Challenge 4: Generic Adapters
**Problem**: Supporting multiple SQL dialects
**Solution**: Adapter pattern with comptime interface:
```zig
const PostgresAdapter = struct {
    pub fn quote(name: []const u8) []const u8 {
        return std.fmt.comptimePrint("\"{s}\"", .{name});
    }
    pub fn placeholder(index: usize) []const u8 {
        return std.fmt.comptimePrint("${}", .{index + 1});
    }
};
```

---

## 8. Migration Strategy

### From JetQuery
```zig
// JetQuery style
const cats = try repo.find(Cat, .{
    .where = .{ .paws = 4 },
});

// ZSQ style
const cats = try db.execute(
    Query(Cat).where(.{ .paws = 4 })
);
```

### From Raw SQL
```zig
// Before: Raw SQL with manual binding
try db.exec(
    "SELECT * FROM reminders WHERE priority > ? AND is_completed = ?",
    .{ 2, false },
);

// After: Type-safe with compile-time validation
try db.execute(
    Query(Reminder)
        .where(.{ 
            .priority = .{ .gt = 2 },
            .is_completed = false,
        })
);
```

---

## 9. Success Metrics

1. **Compile-Time Safety**: 100% of type errors caught at compile time
2. **Performance**: Zero runtime overhead vs. hand-written SQL
3. **Adoption**: Easier to learn than JetQuery, more powerful than Swift version
4. **Coverage**: Support 90% of common SQL patterns
5. **Error Quality**: Clear, actionable compile errors with suggestions

---

## 10. Conclusion

Zig Structured Queries represents a unique opportunity to create the world's most type-safe SQL query builder. By combining Swift's proven API design with Zig's unmatched compile-time capabilities, we can create a library that is:

- **Safer** than any existing solution (including Swift's)
- **Faster** due to zero runtime overhead
- **Easier** to use thanks to Swift-inspired ergonomics
- **More powerful** through Zig's comptime metaprogramming

This is not just a port—it's an evolution that showcases what's uniquely possible in Zig.

---

## Appendix A: Quick Start Example

```zig
const std = @import("std");
const zsq = @import("zsq");

// Define your schema
const Todo = struct {
    id: i32,
    title: []const u8,
    completed: bool,
    created_at: i64,
};

pub fn main() !void {
    // Initialize database
    var db = try zsq.Database.init(.sqlite, "todos.db");
    defer db.deinit();
    
    // Insert a new todo
    try db.execute(Insert(Todo, .{
        .title = "Learn Zig Structured Queries",
        .completed = false,
        .created_at = std.time.timestamp(),
    }));
    
    // Query incomplete todos
    const incomplete = try db.execute(
        Query(Todo)
            .where(.{ .completed = false })
            .order(.{ .created_at = .desc })
    );
    defer db.free(incomplete);
    
    // Use the results (type-safe!)
    for (incomplete) |todo| {
        std.debug.print("TODO: {s}\n", .{todo.title});
    }
}
```

---

## Appendix B: API Reference (Preview)

### Core Functions
- `Query(T)` - Start a SELECT query
- `Insert(T, values)` - Create an INSERT statement  
- `Update(T)` - Start an UPDATE statement
- `Delete(T)` - Start a DELETE statement
- `With(cte)` - Create a CTE

### Query Methods
- `.where(conditions)` - Add WHERE clause
- `.select(fields)` - Specify SELECT columns
- `.join(Table, on)` - Add JOIN
- `.group(fields)` - Add GROUP BY
- `.having(conditions)` - Add HAVING
- `.order(fields)` - Add ORDER BY
- `.limit(n)` - Add LIMIT
- `.offset(n)` - Add OFFSET

### Operators
- `.eq` - Equals
- `.neq` - Not equals
- `.gt` - Greater than
- `.gte` - Greater than or equal
- `.lt` - Less than
- `.lte` - Less than or equal
- `.like` - Pattern matching
- `.in` - In list
- `.between` - Range check