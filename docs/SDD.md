## Software Design Document: CORM (A Comptime-Driven, Type-Safe Query Builder for Zig)

### 1. Vision & Goals

**Vision:** To create a Zig query builder where the Zig compiler itself becomes the primary tool for validating database query correctness. If the Zig code compiles, the SQL query is guaranteed to be syntactically valid and type-correct against the application's schema as defined in Zig structs.

**Core Goals:**

1.  **Absolute Type Safety:** A query that attempts to select a non-existent column, compare a column to a value of an incompatible type, or join on mismatched types **must fail to compile**.
2.  **Zero-Cost Abstraction:** The query-building API is a compile-time construct. The final output at runtime is a simple, optimized SQL string and a perfectly-typed result struct, incurring no performance penalty over hand-written SQL.
3.  **Developer Ergonomics:** Provide a clear, chainable, and Zig-idiomatic API that reduces the cognitive load of writing and maintaining complex queries.
4.  **Extensibility:** The design should allow for different database backends (e.g., PostgreSQL, SQLite) through an adapter pattern, similar to `jetquery`.

### 2. Analysis of `jetquery` as a Foundation

`jetquery` is an excellent starting point and provides a solid foundation. Let's analyze its design choices in the context of our type-safety goal.

**What `jetquery` does well:**

*   **SQL Generation:** `src/jetquery/sql/render.zig` shows a robust system for comptime-rendering SQL strings from a set of clauses. This is a pattern we will heavily reuse.
*   **Adapter Pattern:** `src/jetquery/adapters.zig` defines a clean interface for supporting different SQL dialects. This is a proven and necessary design.
*   **Chainable API:** The `Query()` builder provides a fluent interface that is intuitive for developers.

**Where the Type-Safety Gaps Exist (and why it's by design for `jetquery`):**

*   **String-Based Columns:** In `Query.select`, columns are specified as anonymous structs of enums (e.g., `.select(.{ .name, .paws })`). These are converted to strings. If you misspell a column (`.naem`), it will compile, but the error will only be caught if the generated SQL is invalid or the database rejects it at runtime.
*   **`anytype` in `WHERE` Clauses:** `Repo.zig` and `Query.zig` pass `anytype` arguments for `where` clauses. The values are eventually coerced (`src/jetquery/coercion.zig`), but this is a runtime or late-`comptime` process. The critical link—checking the value's type against the schema's column type *at the point of the call*—is missing. You can pass a string to an integer column, and it will compile, failing later during coercion.
*   **Lack of Result-Type Generation:** A `SELECT` query in `jetquery` returns a generic `Result` type. The actual shape of the returned data is known, but it's not encoded into a unique, static Zig struct type for each query. This means you access columns by name on the result object, which again is not checked by the compiler. A typo (`result.naem`) is a runtime error.

**Our Path Forward:** We will build a new "code layer" on top of these foundational ideas. This layer will not exist at runtime. It is a `comptime` state machine that replaces string-based and `anytype`-based logic with strict, type-driven validation.

### 3. The `comptime` State Machine Architecture

The core of CORM is a series of immutable `comptime`-known structs. Each method call in the query builder doesn't modify a state object; it returns a **new, distinct struct type** that encodes the added information at the type level.

This is the state machine flow:

1.  `Query(T)` -> returns `QueryBuilder(T)`
2.  `.select(...)` on `QueryBuilder(T)` -> returns `SelectBuilder(T, SelectedColumns)`
3.  `.where(...)` on `SelectBuilder(...)` -> returns `WhereBuilder(T, SelectedColumns, WhereClauses)`
4.  `.join(...)` on `WhereBuilder(...)` -> returns `JoinBuilder(T, JoinedTables, SelectedColumns, WhereClauses)`
5.  `.all()` on any builder -> returns `![]const FinalResultType`

**The structure of a builder struct:**

```zig
fn SelectBuilder(
    comptime BaseTable: type,
    comptime Selected: anytype, // A tuple of structs describing selected columns/aliases
) type {
    return struct {
        // ... builder methods for .where(), .join(), etc.

        // This method does the final comptime work
        pub fn build() type {
            return struct {
                pub const sql_string = comptime //... generate SQL here ...//;
                pub const ResultType = comptime //... generate result struct here ...//;
            };
        }
    };
}
```

### 4. Detailed API and Syntax Design

This section provides concrete examples of the proposed API and the `comptime` validation that underpins it.

#### 4.1. Schema Definition (Source of Truth)

```zig
pub const User = struct {
    id: u64,
    name: []const u8,
    is_active: bool,
    age: u32,

    pub const schema = struct {
        pub const table_name = "users";
        pub const primary_key = "id";
    };
};
// ... other tables
```

#### 4.2. SELECT Statements

**Syntax:**
```zig
// SELECT name, age FROM users;
const query = Query(User).select(.{ .name = .{}, .age = .{} });
const results = try query.all(db, allocator);
// typeof(results) is `![]const struct { name: []const u8, age: u32 }`
```

**`comptime` Mechanism:**
*   `select` takes an anonymous struct. The field names (`.name`, `.age`) are iterated at `comptime`.
*   `@hasField(User, "name")` is used to validate each selection. A compile error is thrown on failure.
*   The empty struct `.{}` is a placeholder. To alias, we provide a value:
    ```zig
    // SELECT name AS user_name FROM users;
    const query = Query(User).select(.{ .name = .{ .as = "user_name" } });
    // typeof(results) is `![]const struct { user_name: []const u8 }`
    ```
*   The `ResultType` is generated using `@Type` based on the validated fields and aliases.

#### 4.3. WHERE Clauses

**Syntax:**
```zig
// WHERE age > 18 AND is_active = true
.where(.{
    .age = .{ .gt = 18 },
    .and = .{
        .is_active = .{ .eq = true },
    },
})
```

**`comptime` Mechanism:**
*   `.where` receives an anonymous struct. It recursively walks this struct at `comptime`.
*   Field names (`.age`, `.is_active`) are validated against the `User` schema.
*   Operator fields (`.gt`, `.eq`) are mapped to SQL operators.
*   **Type Validation:**
    ```zig
    // Inside the comptime logic for `.where`:
    const column_type = @TypeOf(@field(User, "age")); // u32
    const value_type = @TypeOf(18); // comptime_int
    if (!@canCoerce(column_type, value_type)) {
        @compileError("Mismatched type for column 'age'. Expected u32, got " ++ @typeName(value_type));
    }
    ```
    This compile error is the cornerstone of the system's safety.

#### 4.4. JOIN Clauses (The Hard Part)

**Syntax:**
```zig
// SELECT users.name, posts.title FROM users JOIN posts ON users.id = posts.author_id
const query = Query(User)
    .join(Post, .on(.{ .id = .{ .eq = .author_id } }))
    .select(.{
        .users = .{ .name = .{} }, // Namespacing for clarity
        .posts = .{ .title = .{} },
    });

const results = try query.all(db, allocator);
// typeof(results) is `![]const struct { name: []const u8, title: []const u8 }`
```

**`comptime` Mechanism:**
*   `.join(Post, ...)` transitions the state to a `JoinBuilder(User, Post, ...)`.
*   The `.on` condition is validated at `comptime`:
    *   `.id` is resolved against the first table in the `JoinBuilder`'s state (`User`).
    *   `.author_id` is resolved against the second table (`Post`).
    *   The types of `User.id` (`u64`) and `Post.author_id` (`u64`) are checked for compatibility. A compile error is thrown on mismatch.
*   Subsequent `.select` and `.where` calls now have access to both schemas. The nested struct syntax (`.users = .{...}`) is used to disambiguate columns. The `comptime` logic will check `.name` against `User` and `.title` against `Post`.

#### 4.5. INSERT and UPDATE

**Syntax:**
```zig
// INSERT
try Query(User).insert(.{
    .name = "Ziggy",
    .age = 5,
    .is_active = true,
}).exec(db);

// UPDATE
try Query(User).update(.{ .age = 6 }).where(.{ .name = .{ .eq = "Ziggy" } }).exec(db);
```

**`comptime` Mechanism:**
*   The `insert` and `update` methods take a struct literal.
*   At `comptime`, the builder iterates the fields of the literal.
*   It validates that each field exists in the `User` schema.
*   It validates that the type of each value in the literal matches the type of the corresponding column in the `User` struct.
*   A compile error is thrown if you provide an extra field not in `User`, or if a type is wrong.

### 5. Implementation Details: Key `comptime` Functions

This section details the functions that would form the core of the library.

**`ComptimeSchema(comptime T: type)`**
A utility struct to cache introspection results for a given table type.
```zig
fn ComptimeSchema(comptime T: type) type {
    return struct {
        pub const columns = comptime blk: {
            const fields = @typeInfo(T).Struct.fields;
            var map = std.ComptimeStringMap(std.builtin.Type.StructField).initEmpty();
            for (fields) |field| {
                try map.put(field.name, field);
            }
            break :blk map;
        };

        pub fn hasColumn(name: []const u8) bool { ... }
        pub fn columnType(name: []const u8) type { ... }
    };
}
```

**`generateResultType(comptime selections: anytype)`**
This function, as described in section 3.3, is the heart of the `SELECT` statement. It takes the validated selection state and uses `@Type` to forge a new struct type.

**`generateSql(comptime builder_state: anytype)`**
A large `comptime` function that takes the final builder state struct (`WhereBuilder`, `JoinBuilder`, etc.) and renders the final SQL string. It iterates through the `comptime`-known fields of the builder (like `selected_columns`, `where_clauses`) to construct the string.

### 6. Timeline and Effort Estimation

This is a significant but achievable project for an experienced Zig developer.

*   **Total Estimated Effort:** 3-6 developer-months.
*   **Phase 1 (1 month):** Core `comptime` utilities, schema introspection, and a complete `SELECT` implementation (including columnar select, aliasing, and result type generation). This phase is crucial and delivers the core value proposition.
*   **Phase 2 (2-3 weeks):** Full `WHERE` clause implementation with all common operators and robust type checking.
*   **Phase 3 (2-3 weeks):** `INSERT`, `UPDATE`, `DELETE` implementations. This is relatively straightforward once the schema validation from Phase 1 is done.
*   **Phase 4 (1.5 months):** `JOIN` implementation. This is the most complex part due to the need to manage multiple schemas and disambiguate columns throughout the builder state.
*   **Phase 5 (1 month):** Add support for aggregates (`GROUP BY`, `HAVING`, `SUM`, etc.), ordering, and limits. Refine the API and add extensive documentation and examples.

### 7. Conclusion

The path to a type-safe Zig query builder is not through emulating the features of other languages, but by mastering Zig's own unique and powerful `comptime` capabilities. The design proposed here is not only feasible but is fundamentally "Zig-native." It trades the syntactic sugar of other languages for the explicit, compile-time guarantees that are central to Zig's philosophy.

While `jetquery` provides an excellent foundation for SQL generation and adapter logic, CORM builds a new, uncompromisingly type-safe `comptime` layer on top. The effort is substantial, but the result would be a library that could drastically improve the robustness and maintainability of any data-driven Zig application.
