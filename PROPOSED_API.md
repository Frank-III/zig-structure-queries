# Comprehensive Zig SQL Query Builder API Design
## Supporting Full SQLite Dialect with Maximum Type Safety

## Table of Contents
1. [Schema Definition](#schema-definition)
2. [Basic SELECT Queries](#basic-select-queries)
3. [JOINs with Type Safety](#joins-with-type-safety)
4. [Aggregate Functions](#aggregate-functions)
5. [Subqueries](#subqueries)
6. [Common Table Expressions (CTEs)](#common-table-expressions)
7. [INSERT Operations](#insert-operations)
8. [UPDATE Operations](#update-operations)
9. [DELETE Operations](#delete-operations)
10. [Advanced SQLite Features](#advanced-sqlite-features)

---

## Schema Definition

### Basic Table Definition

```zig
pub const DB = struct {
    pub const reminders = struct {
        pub const _table = "reminders";
        pub const id = Field(i32, "reminders", "id");
        pub const title = Field([]const u8, "reminders", "title");
        pub const completed = Field(bool, "reminders", "completed");
        pub const priority = Field(i32, "reminders", "priority");
        pub const category_id = Field(?i32, "reminders", "category_id");
        pub const created_at = Field(i64, "reminders", "created_at");
    };

    pub const tags = struct {
        pub const _table = "tags";
        pub const id = Field(i32, "tags", "id");
        pub const name = Field([]const u8, "tags", "name");
    };

    pub const reminder_tags = struct {
        pub const _table = "reminder_tags";
        pub const reminder_id = Field(i32, "reminder_tags", "reminder_id");
        pub const tag_id = Field(i32, "reminder_tags", "tag_id");
    };

    pub const categories = struct {
        pub const _table = "categories";
        pub const id = Field(i32, "categories", "id");
        pub const name = Field([]const u8, "categories", "name");
        pub const parent_id = Field(?i32, "categories", "parent_id");
    };
};
```

---

## Basic SELECT Queries

### Simple SELECT

```zig
// Comptime approach
const AllReminders = Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title, .completed },
});

const reminders = try AllReminders.execute(db);
// Type: []struct { id: i32, title: []const u8, completed: bool }

// Runtime approach
var query = QueryBuilder.init(allocator);
defer query.deinit();

_ = try query.select(DB.reminders.id);
_ = try query.select(DB.reminders.title);
_ = query.from(DB.reminders);

const results = try query.executeAs(
    struct { id: i32, title: []const u8 },
    db
);
```

### SELECT with WHERE

```zig
// Comptime
const HighPriorityReminders = Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title, .priority },
    .where = .{
        .completed = false,
        .priority_gte = 3,  // Field name + operator
    },
});

// Runtime
_ = try query.where(DB.reminders.completed.eq(false));
_ = try query.where(DB.reminders.priority.gte(3));
```

### Complex WHERE Conditions

```zig
// AND/OR/NOT combinations
_ = try query.where(
    DB.reminders.priority.gte(3)
        .and(DB.reminders.completed.eq(false))
        .or(DB.reminders.title.like("%urgent%"))
);

// IN clause
_ = try query.where(
    DB.reminders.category_id.in(&[_]i32{ 1, 2, 3 })
);

// BETWEEN
_ = try query.where(
    DB.reminders.created_at.between(start_time, end_time)
);

// NULL checks
_ = try query.where(DB.reminders.category_id.isNull());
_ = try query.where(DB.reminders.category_id.isNotNull());
```

### SELECT with ORDER BY, LIMIT, OFFSET

```zig
const RecentReminders = Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title, .created_at },
    .order_by = .{
        .{ .field = .created_at, .direction = .desc },
        .{ .field = .priority, .direction = .desc },
    },
    .limit = 10,
    .offset = 20,
});

// Runtime
_ = try query.orderBy(DB.reminders.created_at.desc());
_ = try query.orderBy(DB.reminders.priority.desc());
_ = query.limit(10);
_ = query.offset(20);
```

---

## JOINs with Type Safety

### INNER JOIN

```zig
// Comptime - Type-safe join with result inference
const RemindersWithCategories = Query.define(.{
    .from = DB.reminders,
    .joins = .{
        .{
            .type = .inner,
            .table = DB.categories,
            .on = .{ .id = .category_id },  // categories.id = reminders.category_id
        },
    },
    .select = .{
        .reminder_title = .reminders_title,
        .category_name = .categories_name,
        .priority = .reminders_priority,
    },
});

const results = try RemindersWithCategories.execute(db);
// Type: []struct {
//   reminder_title: []const u8,
//   category_name: []const u8,
//   priority: i32,
// }

// Runtime with type-safe join tracking
const JoinedQuery = QueryBuilder
    .from(DB.reminders)
    .innerJoin(DB.categories, .{
        .on = DB.categories.id.eqField(DB.reminders.category_id),
    });

const results = try JoinedQuery
    .select(.{
        .reminder = DB.reminders.title,
        .category = DB.categories.name,
    })
    .executeAs(struct {
        reminder: []const u8,
        category: []const u8,
    }, db);
```

### LEFT JOIN (with Optional Types)

```zig
// LEFT JOIN makes joined table fields OPTIONAL!
const RemindersWithOptionalCategories = Query.define(.{
    .from = DB.reminders,
    .joins = .{
        .{
            .type = .left,  // ← Makes category fields optional
            .table = DB.categories,
            .on = .{ .id = .category_id },
        },
    },
    .select = .{
        .reminder_title = .reminders_title,
        .category_name = .categories_name,  // ← Becomes ?[]const u8
    },
});

const results = try RemindersWithOptionalCategories.execute(db);
// Type: []struct {
//   reminder_title: []const u8,
//   category_name: ?[]const u8,  // ← Optional due to LEFT JOIN!
// }

for (results) |row| {
    if (row.category_name) |category| {
        std.debug.print("{s}: {s}\n", .{ row.reminder_title, category });
    } else {
        std.debug.print("{s}: (no category)\n", .{row.reminder_title});
    }
}
```

### Multiple JOINs (Many-to-Many)

```zig
// Get reminders with their tags (many-to-many through junction table)
const RemindersWithTags = Query.define(.{
    .from = DB.reminders,
    .joins = .{
        .{
            .type = .inner,
            .table = DB.reminder_tags,
            .on = .{ .reminder_id = .reminders_id },
        },
        .{
            .type = .inner,
            .table = DB.tags,
            .on = .{ .id = .reminder_tags_tag_id },
        },
    },
    .select = .{
        .reminder_id = .reminders_id,
        .reminder_title = .reminders_title,
        .tag_name = .tags_name,
    },
    .order_by = .{
        .{ .field = .reminders_id, .direction = .asc },
    },
});

// Multiple rows per reminder (one per tag)
const results = try RemindersWithTags.execute(db);
```

### Self-Join (Recursive Relationships)

```zig
// Self-join for hierarchical data (categories with parent categories)
const CategoriesWithParents = Query.define(.{
    .from = DB.categories,
    .joins = .{
        .{
            .type = .left,
            .table = DB.categories,
            .as = "parent_categories",  // Alias for self-join
            .on = .{ .id = .categories_parent_id },
        },
    },
    .select = .{
        .category_name = .categories_name,
        .parent_name = .parent_categories_name,
    },
});
```

---

## Aggregate Functions

### Basic Aggregates

```zig
const ReminderStats = Query.define(.{
    .from = DB.reminders,
    .select = .{
        .total_count = .{ .count_star = {} },
        .completed_count = .{ .count = .completed, .filter = .{ .completed = true } },
        .avg_priority = .{ .avg = .priority },
        .max_priority = .{ .max = .priority },
        .min_priority = .{ .min = .priority },
    },
});

const stats = try ReminderStats.execute(db);
// Type: []struct {
//   total_count: i32,
//   completed_count: i32,
//   avg_priority: f64,
//   max_priority: i32,
//   min_priority: i32,
// }
```

### GROUP BY with HAVING

```zig
const CategoryStats = Query.define(.{
    .from = DB.reminders,
    .joins = .{
        .{ .type = .inner, .table = DB.categories, .on = .{ .id = .category_id } },
    },
    .select = .{
        .category_name = .categories_name,
        .reminder_count = .{ .count = .reminders_id },
        .avg_priority = .{ .avg = .reminders_priority },
    },
    .group_by = .{ .categories_id },
    .having = .{
        .reminder_count_gte = 5,  // HAVING COUNT(*) >= 5
        .avg_priority_gt = 2.0,    // HAVING AVG(priority) > 2.0
    },
    .order_by = .{
        .{ .field = .reminder_count, .direction = .desc },
    },
});

// Runtime
_ = try query.select(DB.categories.name);
_ = try query.select(count(DB.reminders.id).as("count"));
_ = try query.groupBy(DB.categories.id);
_ = try query.having(count(DB.reminders.id).gte(5));
```

### String Aggregation

```zig
const RemindersWithTagList = Query.define(.{
    .from = DB.reminders,
    .joins = .{
        .{ .type = .left, .table = DB.reminder_tags, .on = .{ .reminder_id = .reminders_id } },
        .{ .type = .left, .table = DB.tags, .on = .{ .id = .reminder_tags_tag_id } },
    },
    .select = .{
        .reminder_title = .reminders_title,
        .tags = .{ .group_concat = .tags_name, .separator = ", " },
    },
    .group_by = .{ .reminders_id },
});

const results = try RemindersWithTagList.execute(db);
// Type: []struct {
//   reminder_title: []const u8,
//   tags: ?[]const u8,  // "work, urgent, home"
// }
```

---

## Subqueries

### Scalar Subquery (Single Value)

```zig
// SELECT with scalar subquery
const RemindersWithCategoryCount = Query.define(.{
    .from = DB.reminders,
    .select = .{
        .title = .title,
        .category_reminder_count = .{
            .subquery = Query.define(.{
                .from = DB.reminders,
                .select = .{ .count_star = {} },
                .where = .{
                    .category_id_eq = .reminders_category_id,  // Correlated!
                },
            }),
        },
    },
});
```

### Table Subquery (IN/EXISTS)

```zig
// WHERE ... IN (subquery)
const RemindersInActiveCategories = Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title },
    .where = .{
        .category_id_in = .{
            .subquery = Query.define(.{
                .from = DB.categories,
                .select = .{ .id },
                .where = .{ .active = true },
            }),
        },
    },
});

// WHERE EXISTS (subquery)
const RemindersWithTags = Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title },
    .where = .{
        .exists = Query.define(.{
            .from = DB.reminder_tags,
            .select = .{ .value = 1 },
            .where = .{ .reminder_id_eq = .reminders_id },
        }),
    },
});
```

---

## Common Table Expressions (CTEs)

### Basic CTE

```zig
const HighPriorityCTE = CTE("high_priority", Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title, .priority },
    .where = .{ .priority_gte = 3 },
}));

const RemindersWithHighPriorityCount = Query.with(
    .{ HighPriorityCTE },
    Query.define(.{
        .from = DB.reminders,
        .select = .{
            .title = .title,
            .high_priority_count = .{
                .subquery = Query.define(.{
                    .from = HighPriorityCTE.table,
                    .select = .{ .count_star = {} },
                    .where = .{ .category_id_eq = .reminders_category_id },
                }),
            },
        },
    })
);
```

### Recursive CTE

```zig
// Recursive CTE for hierarchical data
const CategoryTree = CTE.recursive("category_tree", .{
    // Base case
    .base = Query.define(.{
        .from = DB.categories,
        .select = .{
            .id = .id,
            .name = .name,
            .parent_id = .parent_id,
            .level = .{ .value = 0 },
        },
        .where = .{ .parent_id_is_null = {} },
    }),
    // Recursive case
    .recursive = Query.define(.{
        .from = DB.categories,
        .joins = .{
            .{
                .type = .inner,
                .table = "category_tree",
                .on = .{ .id = .categories_parent_id },
            },
        },
        .select = .{
            .id = .categories_id,
            .name = .categories_name,
            .parent_id = .categories_parent_id,
            .level = .{ .add = .{ .category_tree_level, 1 } },
        },
    }),
});

const AllCategories = Query.with(
    .{ CategoryTree },
    Query.define(.{
        .from = CategoryTree.table,
        .select = .{ .id, .name, .level },
        .order_by = .{ .{ .field = .level, .direction = .asc } },
    })
);
```

---

## INSERT Operations

### Simple INSERT

```zig
var insert = InsertBuilder.init(allocator, DB.reminders);
defer insert.deinit();

_ = try insert.value(DB.reminders.title, "Buy groceries");
_ = try insert.value(DB.reminders.priority, 2);
_ = try insert.value(DB.reminders.completed, false);

const sql = try insert.toSql();
// INSERT INTO reminders (title, priority, completed)
// VALUES ('Buy groceries', 2, 0)
```

### INSERT with RETURNING

```zig
_ = insert.returning("id");
const sql = try insert.toSql();
// INSERT INTO reminders (...) VALUES (...) RETURNING id

// Execute and get the ID
const new_id = try insert.execute(db);
```

### Batch INSERT

```zig
const batch = try InsertBuilder.batch(allocator, DB.reminders, .{
    .{ .title = "Task 1", .priority = 1, .completed = false },
    .{ .title = "Task 2", .priority = 2, .completed = false },
    .{ .title = "Task 3", .priority = 3, .completed = true },
});

const sql = try batch.toSql();
// INSERT INTO reminders (title, priority, completed) VALUES
//   ('Task 1', 1, 0),
//   ('Task 2', 2, 0),
//   ('Task 3', 3, 1)
```

### UPSERT (ON CONFLICT)

```zig
var insert = InsertBuilder.init(allocator, DB.reminders);
_ = try insert.value(DB.reminders.title, "Unique task");
_ = try insert.value(DB.reminders.priority, 1);

// SQLite UPSERT syntax
_ = insert.onConflict(.{
    .target = DB.reminders.title,  // ON CONFLICT(title)
    .action = .{
        .do_update = .{
            .priority = .excluded_priority,  // SET priority = excluded.priority
        },
    },
});

const sql = try insert.toSql();
// INSERT INTO reminders (title, priority) VALUES ('Unique task', 1)
// ON CONFLICT(title) DO UPDATE SET priority = excluded.priority
```

---

## UPDATE Operations

### Simple UPDATE

```zig
var update = UpdateBuilder.init(allocator, DB.reminders);
defer update.deinit();

_ = try update.set(DB.reminders.completed, true);
_ = try update.set(DB.reminders.title, "Updated title");
_ = try update.where(DB.reminders.id.eq(5));

const sql = try update.toSql();
// UPDATE reminders SET completed = 1, title = 'Updated title' WHERE id = 5
```

### UPDATE with Expressions

```zig
_ = try update.set(DB.reminders.priority,
    DB.reminders.priority.add(1)  // priority = priority + 1
);

_ = try update.set(DB.reminders.title,
    concat(&.{ DB.reminders.title, " (updated)" })
);
```

### UPDATE with JOIN (SQLite 3.33+)

```zig
var update = UpdateBuilder.init(allocator, DB.reminders);
_ = try update.set(DB.reminders.priority, 5);
_ = try update.from(DB.categories);
_ = try update.where(
    DB.reminders.category_id.eqField(DB.categories.id)
        .and(DB.categories.name.eq("Work"))
);

const sql = try update.toSql();
// UPDATE reminders SET priority = 5
// FROM categories
// WHERE reminders.category_id = categories.id
//   AND categories.name = 'Work'
```

---

## DELETE Operations

### Simple DELETE

```zig
var delete = DeleteBuilder.init(allocator, DB.reminders);
defer delete.deinit();

_ = try delete.where(DB.reminders.completed.eq(true));
_ = try delete.where(DB.reminders.created_at.lt(cutoff_date));

const sql = try delete.toSql();
// DELETE FROM reminders
// WHERE completed = 1 AND created_at < ?
```

### DELETE with RETURNING

```zig
_ = delete.returning(&.{ "id", "title" });
const deleted = try delete.execute(db);
// Returns the deleted rows
```

---

## Advanced SQLite Features

### Window Functions

```zig
const RemindersWithRowNumber = Query.define(.{
    .from = DB.reminders,
    .select = .{
        .title = .title,
        .priority = .priority,
        .row_num = .{
            .window = .{
                .function = .row_number,
                .partition_by = .{ .category_id },
                .order_by = .{ .{ .field = .priority, .direction = .desc } },
            },
        },
    },
});

// ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY priority DESC)
```

### JSON Functions (SQLite 3.38+)

```zig
// Assuming reminders.metadata is JSON column
const RemindersWithJsonExtract = Query.define(.{
    .from = DB.reminders,
    .select = .{
        .title = .title,
        .tag = .{ .json_extract = .{ .metadata, "$.tags[0]" } },
    },
    .where = .{
        .json_type_eq = .{ .metadata, "object" },
    },
});

// SELECT title, json_extract(metadata, '$.tags[0]') AS tag
// FROM reminders
// WHERE json_type(metadata) = 'object'
```

### Full-Text Search (FTS5)

```zig
// Create FTS5 virtual table (schema)
pub const reminders_fts = struct {
    pub const _table = "reminders_fts";
    pub const _virtual = "fts5(title, content)";
    pub const title = Field([]const u8, "reminders_fts", "title");
    pub const content = Field([]const u8, "reminders_fts", "content");
};

// Full-text search query
const SearchResults = Query.define(.{
    .from = DB.reminders_fts,
    .select = .{ .title, .content },
    .where = .{
        .match = "grocery OR shopping",  // FTS5 MATCH operator
    },
    .order_by = .{
        .{ .field = .{ .bm25 = {} }, .direction = .asc },  // Rank by BM25
    },
});
```

### UNION/INTERSECT/EXCEPT

```zig
const HighPriority = Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title },
    .where = .{ .priority_gte = 3 },
});

const RecentlyCreated = Query.define(.{
    .from = DB.reminders,
    .select = .{ .id, .title },
    .where = .{ .created_at_gte = last_week },
});

// UNION
const Combined = Query.union(.{ HighPriority, RecentlyCreated });

// UNION ALL (keeps duplicates)
const CombinedAll = Query.unionAll(.{ HighPriority, RecentlyCreated });

// INTERSECT (only items in both)
const Intersection = Query.intersect(.{ HighPriority, RecentlyCreated });

// EXCEPT (items in first but not second)
const Difference = Query.except(.{ HighPriority, RecentlyCreated });
```

---

## Type Safety Features

### Null Safety with LEFT JOIN

```zig
// The type system tracks nullability from JOINs
const Q = Query.define(.{
    .from = DB.reminders,
    .joins = .{
        .{ .type = .left, .table = DB.categories, .on = .{ .id = .category_id } },
    },
    .select = .{
        .title = .reminders_title,           // []const u8 (NOT NULL)
        .category = .categories_name,         // ?[]const u8 (LEFT JOIN)
    },
});

const results = try Q.execute(db);
for (results) |row| {
    // Must handle optional!
    const category = row.category orelse "(none)";
    std.debug.print("{s}: {s}\n", .{ row.title, category });
}
```

### Compile-Time Field Validation

```zig
// ✅ Compiles - field exists
_ = try query.select(DB.reminders.title);

// ❌ Compile error - field doesn't exist
_ = try query.select(DB.reminders.typo);
//                    error: no field named 'typo' in struct

// ✅ Compiles - correct operator for type
_ = try query.where(DB.reminders.priority.gte(3));  // numeric

// ❌ Compile error - wrong operator for type
_ = try query.where(DB.reminders.title.gte(3));
//                  error: no method 'gte' on Field([]const u8)

// ✅ Compiles - correct operator for type
_ = try query.where(DB.reminders.title.like("%test%"));  // string
```

### Type-Safe JOIN Conditions

```zig
// ✅ Compiles - matching types
_ = try query.innerJoin(DB.categories,
    DB.categories.id.eqField(DB.reminders.category_id)
);
// Both are i32 or ?i32

// ❌ Compile error - type mismatch
_ = try query.innerJoin(DB.categories,
    DB.categories.name.eqField(DB.reminders.id)
);
// error: expected []const u8, found i32
```

---

## Implementation Notes

### Key Design Principles

1. **Two Modes of Operation**:
   - **Comptime queries**: Full type inference, zero runtime overhead
   - **Runtime queries**: Flexible but require manual type specification

2. **Type Safety Levels**:
   - **Level 1**: Field existence (both modes)
   - **Level 2**: Operator validity (both modes)
   - **Level 3**: Result type inference (comptime only)
   - **Level 4**: NULL safety tracking (comptime only)

3. **Ergonomics vs. Safety**:
   - Comptime mode: Maximum safety, requires planning
   - Runtime mode: Maximum flexibility, manual types
   - Both modes share the same field definitions

4. **SQLite Dialect Coverage**:
   - All standard SQL features
   - SQLite-specific: UPSERT, FTS5, JSON, window functions
   - Version-gated features with comptime checks

---

## Examples: Real-World Queries

### Complex Analytics Query

```zig
// Get category statistics with trend analysis
const CategoryAnalytics = Query.with(
    .{
        // CTE: Last 30 days
        CTE("recent", Query.define(.{
            .from = DB.reminders,
            .select = .{ .id, .category_id, .priority, .created_at },
            .where = .{
                .created_at_gte = thirtyDaysAgo(),
            },
        })),
    },
    Query.define(.{
        .from = DB.categories,
        .joins = .{
            .{ .type = .left, .table = "recent", .on = .{ .category_id = .categories_id } },
        },
        .select = .{
            .category = .categories_name,
            .total_recent = .{ .count = .recent_id },
            .avg_priority = .{ .avg = .recent_priority },
            .trend = .{
                .case = .{
                    .when = .{ .{ .count_gt = 10, .then = "growing" } },
                    .when = .{ .{ .count_gt = 5, .then = "steady" } },
                    .else = "declining",
                },
            },
        },
        .group_by = .{ .categories_id },
        .order_by = .{ .{ .field = .total_recent, .direction = .desc } },
    })
);
```

### Hierarchical Data Query

```zig
// Get full category tree with reminder counts
const CategoryTreeWithCounts = Query.with(
    .{
        // Recursive CTE for tree
        CTE.recursive("tree", .{
            .base = Query.define(.{
                .from = DB.categories,
                .select = .{
                    .id = .id,
                    .name = .name,
                    .parent_id = .parent_id,
                    .path = .name,
                    .level = .{ .value = 0 },
                },
                .where = .{ .parent_id_is_null = {} },
            }),
            .recursive = Query.define(.{
                .from = DB.categories,
                .joins = .{
                    .{ .type = .inner, .table = "tree", .on = .{ .id = .categories_parent_id } },
                },
                .select = .{
                    .id = .categories_id,
                    .name = .categories_name,
                    .parent_id = .categories_parent_id,
                    .path = .{ .concat = .{ .tree_path, " > ", .categories_name } },
                    .level = .{ .add = .{ .tree_level, 1 } },
                },
            }),
        }),
    },
    Query.define(.{
        .from = "tree",
        .joins = .{
            .{ .type = .left, .table = DB.reminders, .on = .{ .category_id = .tree_id } },
        },
        .select = .{
            .path = .tree_path,
            .level = .tree_level,
            .reminder_count = .{ .count = .reminders_id },
        },
        .group_by = .{ .tree_id },
        .order_by = .{ .{ .field = .tree_path, .direction = .asc } },
    })
);
```

---

This comprehensive API design provides:
- ✅ Type-safe JOINs with NULL tracking
- ✅ Full SQLite dialect coverage
- ✅ Both comptime and runtime modes
- ✅ Ergonomic and discoverable API
- ✅ Works within Zig's constraints
- ✅ Zero runtime overhead for comptime mode
