const std = @import("std");

// ============================================================
// TYPE-SAFE SQL QUERY BUILDER FOR ZIG
// ============================================================
// This provides:
// 1. Type-safe field references with operators
// 2. Compile-time SQL validation
// 3. Clean schema declaration syntax
// 4. Zero runtime overhead

// ============================================================
// FIELD TYPE WITH OPERATORS
// ============================================================

pub fn Field(comptime T: type) type {
    return struct {
        table: []const u8,
        column: []const u8,

        pub const field_type = T;
        const Self = @This();

        // Comparison operators
        pub fn eq(self: Self, value: T) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .eq,
                .value = Value.from(value),
            };
        }

        pub fn neq(self: Self, value: T) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .neq,
                .value = Value.from(value),
            };
        }

        pub fn gt(self: Self, value: T) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .gt,
                .value = Value.from(value),
            };
        }

        pub fn gte(self: Self, value: T) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .gte,
                .value = Value.from(value),
            };
        }

        pub fn lt(self: Self, value: T) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .lt,
                .value = Value.from(value),
            };
        }

        pub fn lte(self: Self, value: T) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .lte,
                .value = Value.from(value),
            };
        }

        // String operators - only available for string types
        pub const like = if (isStringType(T)) likeFn else @compileError("like() is only available for string fields, got " ++ @typeName(T));
        pub const glob = if (isStringType(T)) globFn else @compileError("glob() is only available for string fields, got " ++ @typeName(T));
        pub const match = if (isStringType(T)) matchFn else @compileError("match() is only available for string fields, got " ++ @typeName(T));
        pub const regexp = if (isStringType(T)) regexpFn else @compileError("regexp() is only available for string fields, got " ++ @typeName(T));

        fn likeFn(self: Self, pattern: []const u8) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .like,
                .value = Value.from(pattern),
            };
        }

        fn globFn(self: Self, pattern: []const u8) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .glob,
                .value = Value.from(pattern),
            };
        }

        fn matchFn(self: Self, search_query: []const u8) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .match,
                .value = Value.from(search_query),
            };
        }

        fn regexpFn(self: Self, pattern: []const u8) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .regexp,
                .value = Value.from(pattern),
            };
        }

        // NULL checks
        pub fn isNull(self: Self) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .is_null,
                .value = Value.null_value,
            };
        }

        pub fn isNotNull(self: Self) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .is_not_null,
                .value = Value.null_value,
            };
        }

        // IN operator - validates element type matches field type
        pub fn in(self: Self, values: anytype) Condition {
            const ValuesType = @TypeOf(values);
            const values_info = @typeInfo(ValuesType);

            // Must be a pointer to array or slice
            if (values_info != .pointer) {
                @compileError("in() expects a slice or array pointer, got " ++ @typeName(ValuesType));
            }

            const child_info = @typeInfo(values_info.pointer.child);
            const ElementType = switch (child_info) {
                .array => |arr| arr.child,
                else => values_info.pointer.child,
            };

            // Validate element type matches field type (with coercion for numeric types)
            const t_info = @typeInfo(T);
            const elem_info = @typeInfo(ElementType);

            const compatible = comptime blk: {
                // Exact match
                if (T == ElementType) break :blk true;
                // Both integers (different sizes OK - i32 field can use i64 array)
                if (t_info == .int and elem_info == .int) break :blk true;
                // Both floats
                if (t_info == .float and elem_info == .float) break :blk true;
                // Both strings
                if (isStringType(T) and isStringType(ElementType)) break :blk true;
                break :blk false;
            };

            if (!compatible) {
                @compileError("in() element type mismatch: field is " ++ @typeName(T) ++ " but got elements of " ++ @typeName(ElementType));
            }

            return Condition{
                .field = self.toFieldRef(),
                .op = .in,
                .value = Value.fromArray(values),
            };
        }

        // BETWEEN operator
        pub fn between(self: Self, min: T, max: T) Condition {
            return Condition{
                .field = self.toFieldRef(),
                .op = .between,
                .value = Value.fromRange(min, max),
            };
        }

        // For JOINs - compare with another field (type-safe)
        pub fn eqField(self: Self, other: anytype) JoinCondition {
            const OtherType = @TypeOf(other);

            // Check that other has field_type declaration (is a Field)
            if (!@hasDecl(OtherType, "field_type")) {
                @compileError("eqField() expects a Field type, got " ++ @typeName(OtherType));
            }
            const OtherFieldType = OtherType.field_type;

            // Check type compatibility for join at comptime
            const compatible = comptime typesCompatible(T, OtherFieldType);
            if (!compatible) {
                @compileError("eqField() type mismatch: cannot join " ++ @typeName(T) ++ " with " ++ @typeName(OtherFieldType));
            }

            return JoinCondition{
                .left = self.toFieldRef(),
                .right = other.toFieldRef(),
                .op = .eq,
            };
        }

        // Ordering
        pub fn asc(self: Self) OrderBy {
            return OrderBy{
                .field = self.toFieldRef(),
                .direction = .asc,
            };
        }

        pub fn desc(self: Self) OrderBy {
            return OrderBy{
                .field = self.toFieldRef(),
                .direction = .desc,
            };
        }

        pub fn toFieldRef(self: Self) FieldRef {
            return FieldRef{
                .table = self.table,
                .column = self.column,
            };
        }
    };
}

// Helper: Check if type is a string type
fn isStringType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .pointer) {
        if (info.pointer.child == u8) return true;
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.child == u8) return true;
    }
    if (info == .array and info.array.child == u8) {
        return true;
    }
    return false;
}

// Helper: Check if two types are compatible for comparison/join
fn typesCompatible(comptime A: type, comptime B: type) bool {
    // Exact match
    if (A == B) return true;

    // Both are integers (allow different sizes)
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    const a_is_int = (a_info == .int or a_info == .comptime_int);
    const b_is_int = (b_info == .int or b_info == .comptime_int);
    if (a_is_int and b_is_int) return true;

    const a_is_float = (a_info == .float or a_info == .comptime_float);
    const b_is_float = (b_info == .float or b_info == .comptime_float);
    if (a_is_float and b_is_float) return true;

    // Both are string types
    if (isStringType(A) and isStringType(B)) return true;

    return false;
}

/// Column type marker used by the schema DSL.
/// Example: `.id = col(i64)`
pub fn col(comptime T: type) type {
    return T;
}

fn tableType(comptime column_defs: anytype) type {
    const ColumnsType = @TypeOf(column_defs);
    const columns_info = @typeInfo(ColumnsType);

    switch (columns_info) {
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                @compileError("table() columns must be a named struct literal like .{ .id = col(i64) }");
            }

            var table_fields: [struct_info.fields.len + 1]std.builtin.Type.StructField = undefined;

            table_fields[0] = .{
                .name = "_table_name",
                .type = []const u8,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf([]const u8),
            };

            inline for (struct_info.fields, 0..) |sf, i| {
                const field_type_value = @field(column_defs, sf.name);
                if (@TypeOf(field_type_value) != type) {
                    @compileError("table() field '" ++ sf.name ++ "' must use col(T), got " ++ @typeName(@TypeOf(field_type_value)));
                }
                const ColumnType: type = field_type_value;
                const SqlFieldType = Field(ColumnType);

                table_fields[i + 1] = .{
                    .name = sf.name,
                    .type = SqlFieldType,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(SqlFieldType),
                };
            }

            const out_struct = std.builtin.Type.Struct{
                .layout = .auto,
                .fields = &table_fields,
                .decls = &.{},
                .is_tuple = false,
            };

            return @Type(std.builtin.Type{ .@"struct" = out_struct });
        },
        else => @compileError("table() columns must be a named struct literal like .{ .id = col(i64) }"),
    }
}

/// Generate a strongly-typed table value from a compact schema declaration.
///
/// Example:
/// `const users = table("users", .{ .id = col(i64), .name = col([]const u8) });`
pub fn table(comptime table_name: []const u8, comptime column_defs: anytype) tableType(column_defs) {
    const ColumnsType = @TypeOf(column_defs);
    const columns_info = @typeInfo(ColumnsType);
    const struct_info = switch (columns_info) {
        .@"struct" => |s| s,
        else => @compileError("table() columns must be a named struct literal like .{ .id = col(i64) }"),
    };
    if (struct_info.is_tuple) {
        @compileError("table() columns must be a named struct literal like .{ .id = col(i64) }");
    }

    const TableType = tableType(column_defs);
    var result: TableType = undefined;
    result._table_name = table_name;

    inline for (struct_info.fields) |sf| {
        const ColumnType: type = @field(column_defs, sf.name);
        @field(result, sf.name) = Field(ColumnType){
            .table = table_name,
            .column = sf.name,
        };
    }

    return result;
}

/// Group generated tables into a single schema value.
pub fn schema(comptime tables: anytype) @TypeOf(tables) {
    return tables;
}

fn columnsTupleType(comptime table_value: anytype) type {
    const TableType = @TypeOf(table_value);
    if (TableType == type) {
        @compileError("columns() expects a generated table value (from table()), not a table type");
    }

    const info = @typeInfo(TableType);
    const struct_info = switch (info) {
        .@"struct" => |s| s,
        else => @compileError("columns() expects a table struct value"),
    };

    comptime var count: usize = 0;
    inline for (struct_info.fields) |sf| {
        if (comptime std.mem.eql(u8, sf.name, "_table_name")) continue;
        count += 1;
    }

    var types: [count]type = undefined;
    comptime var i: usize = 0;
    inline for (struct_info.fields) |sf| {
        if (comptime std.mem.eql(u8, sf.name, "_table_name")) continue;
        types[i] = sf.type;
        i += 1;
    }

    return std.meta.Tuple(&types);
}

/// Return all typed column handles for a generated table, preserving declaration order.
///
/// Example:
/// `query.select(columns(DB.users))`
pub fn columns(comptime table_value: anytype) columnsTupleType(table_value) {
    const TupleType = columnsTupleType(table_value);
    const struct_info = @typeInfo(@TypeOf(table_value)).@"struct";

    var out: TupleType = undefined;
    comptime var i: usize = 0;
    inline for (struct_info.fields) |sf| {
        if (comptime std.mem.eql(u8, sf.name, "_table_name")) continue;
        @field(out, std.fmt.comptimePrint("{d}", .{i})) = @field(table_value, sf.name);
        i += 1;
    }

    return out;
}

fn tableNameOfComptime(comptime table_ref: anytype) []const u8 {
    const T = @TypeOf(table_ref);

    if (T == type) {
        if (@hasDecl(table_ref, "_table_name")) return table_ref._table_name;
        if (@hasDecl(table_ref, "table_name")) return table_ref.table_name;
        @compileError("table must expose _table_name or table_name; got " ++ @typeName(table_ref));
    }

    if (@hasField(T, "_table_name")) return @field(table_ref, "_table_name");
    if (@hasDecl(T, "_table_name")) return T._table_name;
    if (@hasDecl(T, "table_name")) return T.table_name;

    @compileError("table value must expose _table_name; got " ++ @typeName(T));
}

fn tableNameOfRuntime(table_ref: anytype) []const u8 {
    const T = @TypeOf(table_ref);
    if (comptime T == type) {
        return tableNameOfComptime(table_ref);
    }
    if (comptime @hasField(T, "_table_name")) return @field(table_ref, "_table_name");
    if (comptime @hasDecl(T, "_table_name")) return T._table_name;
    if (comptime @hasDecl(T, "table_name")) return T.table_name;
    @compileError("table value must expose _table_name; got " ++ @typeName(T));
}

/// SQLite FTS helper for table-wide MATCH expressions.
/// Generates SQL like: `docs_fts MATCH ?`
pub fn tableMatch(table_ref: anytype, search_query: []const u8) Condition {
    return .{
        .field = .{
            .table = tableNameOfRuntime(table_ref),
            .column = "",
        },
        .op = .match_table,
        .value = Value.from(search_query),
    };
}

/// Typed placeholder marker for comptime query parameters.
pub fn QueryParam(comptime T: type) type {
    return struct {
        name: []const u8,

        pub const is_query_param = true;
        pub const param_type = T;
    };
}

/// Declare a typed named parameter placeholder for strict/comptime queries.
///
/// Example: `param("min_age", i32)`
pub fn param(comptime name: []const u8, comptime T: type) QueryParam(T) {
    if (name.len == 0) {
        @compileError("param() name cannot be empty");
    }
    return .{ .name = name };
}

fn isQueryParamType(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") {
        return false;
    }
    return @hasDecl(T, "is_query_param") and @hasDecl(T, "param_type") and @hasField(T, "name");
}

const ParamKind = enum {
    int,
    float,
    string,
    bool,
};

fn paramKindFromType(comptime T: type) ParamKind {
    return switch (@typeInfo(T)) {
        .int, .comptime_int => .int,
        .float, .comptime_float => .float,
        .bool => .bool,
        .pointer => |ptr| {
            if (ptr.child == u8) return .string;

            const child_info = @typeInfo(ptr.child);
            if (child_info == .array and child_info.array.child == u8) {
                return .string;
            }

            @compileError("Unsupported param type: " ++ @typeName(T));
        },
        else => @compileError("Unsupported param type: " ++ @typeName(T)),
    };
}

fn paramsType(comptime defs: anytype) type {
    const DefsType = @TypeOf(defs);
    const defs_info = @typeInfo(DefsType);

    switch (defs_info) {
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                @compileError("params() expects a named struct literal like .{ .min_age = i32 }");
            }

            var out_fields: [struct_info.fields.len]std.builtin.Type.StructField = undefined;

            inline for (struct_info.fields, 0..) |sf, i| {
                const field_type_value = @field(defs, sf.name);
                if (@TypeOf(field_type_value) != type) {
                    @compileError("params() field '" ++ sf.name ++ "' must be a type, got " ++ @typeName(@TypeOf(field_type_value)));
                }

                const ParamType: type = field_type_value;
                out_fields[i] = .{
                    .name = sf.name,
                    .type = ParamType,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(ParamType),
                };
            }

            return @Type(std.builtin.Type{ .@"struct" = .{
                .layout = .auto,
                .fields = &out_fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        },
        else => @compileError("params() expects a named struct literal like .{ .min_age = i32 }"),
    }
}

/// Generate a typed parameter struct for strict/comptime query binding.
///
/// Example:
/// `const QueryParams = params(.{ .min_age = i32, .name_pattern = []const u8 });`
pub fn params(comptime defs: anytype) type {
    return paramsType(defs);
}

fn logicalOpToSql(op: LogicalOp) []const u8 {
    return switch (op) {
        .and_ => "AND",
        .or_ => "OR",
    };
}

fn writeConditionSql(writer: anytype, cond: Condition, comptime placeholder_mode: bool) !void {
    if (cond.negated) try writer.writeAll("NOT (");

    if (cond.op == .match_table) {
        try writer.print("{s} {s}", .{ cond.field.table, cond.op.toSql() });
    } else {
        try writer.print("{s}.{s} {s}", .{
            cond.field.table,
            cond.field.column,
            cond.op.toSql(),
        });
    }

    if (cond.op != .is_null and cond.op != .is_not_null) {
        try writer.writeAll(" ");
        if (placeholder_mode) {
            try cond.value.toSqlParam(writer);
        } else {
            try cond.value.toSql(writer);
        }
    }

    if (cond.negated) try writer.writeAll(")");
}

fn conditionToOwnedSql(allocator: std.mem.Allocator, cond: Condition, comptime placeholder_mode: bool) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    errdefer buffer.deinit(allocator);

    try writeConditionSql(buffer.writer(allocator), cond, placeholder_mode);
    return buffer.toOwnedSlice(allocator);
}

fn writeLogicalConditionSql(writer: anytype, allocator: std.mem.Allocator, logical: LogicalCondition, comptime placeholder_mode: bool) !void {
    var parts: std.ArrayListUnmanaged([]u8) = .{};
    defer {
        for (parts.items) |item| allocator.free(item);
        parts.deinit(allocator);
    }

    for (logical.tokens[0..logical.len]) |token| {
        switch (token) {
            .condition => |cond| {
                const part = try conditionToOwnedSql(allocator, cond, placeholder_mode);
                try parts.append(allocator, part);
            },
            .op => |op| {
                if (parts.items.len < 2) return error.InvalidLogicalConditionExpression;

                const right = parts.items[parts.items.len - 1];
                parts.items.len -= 1;
                const left = parts.items[parts.items.len - 1];
                parts.items.len -= 1;

                var combined: std.ArrayListUnmanaged(u8) = .{};
                errdefer combined.deinit(allocator);
                const combined_writer = combined.writer(allocator);
                try combined_writer.writeAll("(");
                try combined_writer.writeAll(left);
                try combined_writer.print(" {s} ", .{logicalOpToSql(op)});
                try combined_writer.writeAll(right);
                try combined_writer.writeAll(")");

                allocator.free(left);
                allocator.free(right);

                try parts.append(allocator, try combined.toOwnedSlice(allocator));
            },
        }
    }

    if (parts.items.len != 1) return error.InvalidLogicalConditionExpression;
    try writer.writeAll(parts.items[0]);
}

// ============================================================
// COMPTIME TYPE-STATE QUERY BUILDER
// ============================================================

const ComptimeJoinDef = struct {
    join_type: JoinType,
    table_name: []const u8,
    condition: JoinCondition,
};

fn tableIndexByName(comptime Tables: anytype, comptime table_name: []const u8) usize {
    inline for (Tables, 0..) |T, i| {
        if (comptime std.mem.eql(u8, tableNameOfComptime(T), table_name)) {
            return i;
        }
    }
    @compileError("Unknown table in join graph: " ++ table_name);
}

fn isNullableJoinTable(comptime Tables: anytype, comptime Joins: anytype, comptime table_name: []const u8) bool {
    var nullable: [Tables.len]bool = [_]bool{false} ** Tables.len;

    inline for (Joins) |join_def| {
        const joined_index = tableIndexByName(Tables, join_def.table_name);

        switch (join_def.join_type) {
            .left => {
                nullable[joined_index] = true;
            },
            .right => {
                comptime var i: usize = 0;
                while (i < joined_index) : (i += 1) {
                    nullable[i] = true;
                }
            },
            else => {},
        }
    }

    return nullable[tableIndexByName(Tables, table_name)];
}

fn maybeOptionalType(comptime T: type, comptime is_nullable: bool) type {
    if (!is_nullable) return T;
    if (@typeInfo(T) == .optional) return T;
    return ?T;
}

fn GenerateResultStruct(comptime Tables: anytype, comptime Joins: anytype, comptime fields: anytype) type {
    const FieldsType = @TypeOf(fields);
    const info = @typeInfo(FieldsType);

    switch (info) {
        .@"struct" => |struct_info| {
            var struct_fields: [struct_info.fields.len]std.builtin.Type.StructField = undefined;

            if (struct_info.is_tuple) {
                for (fields, 0..) |field, i| {
                    var collision = false;

                    // Check for name collisions with other fields
                    for (fields, 0..) |other, j| {
                        if (i != j and std.mem.eql(u8, field.column, other.column)) {
                            collision = true;
                            break;
                        }
                    }

                    var final_name = field.column;
                    // Simple collision resolution: table_column
                    if (collision) {
                        final_name = field.table ++ "_" ++ field.column;
                    }

                    // Get the field type via the type's declaration
                    const FieldType = @TypeOf(field).field_type;
                    const OutType = maybeOptionalType(FieldType, isNullableJoinTable(Tables, Joins, field.table));

                    struct_fields[i] = .{
                        .name = final_name ++ "",
                        .type = OutType,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = @alignOf(OutType),
                    };
                }
            } else {
                // Named selection: `.{ .alias = DB.table.col, ... }`
                for (struct_info.fields, 0..) |sf, i| {
                    const field = @field(fields, sf.name);
                    if (!@hasDecl(@TypeOf(field), "field_type")) {
                        @compileError("Named select fields must be Field(...) values; got: " ++ @typeName(@TypeOf(field)));
                    }

                    const FieldType = @TypeOf(field).field_type;
                    const OutType = maybeOptionalType(FieldType, isNullableJoinTable(Tables, Joins, field.table));
                    struct_fields[i] = .{
                        .name = sf.name ++ "",
                        .type = OutType,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = @alignOf(OutType),
                    };
                }
            }

            const struct_info_out = std.builtin.Type.Struct{
                .layout = .auto,
                .fields = &struct_fields,
                .decls = &.{},
                .is_tuple = false,
            };

            const type_info = std.builtin.Type{ .@"struct" = struct_info_out };
            return @Type(type_info);
        },
        else => {
            @compileError("select() expects a tuple of fields or a named struct literal like .{ .name = DB.users.name }");
        },
    }
}

fn GenerateSql(comptime Tables: anytype, comptime Joins: anytype, comptime fields: anytype) []const u8 {
    comptime {
        var sql: []const u8 = "SELECT ";

        // 1. SELECT clause
        const FieldsType = @TypeOf(fields);
        const info = @typeInfo(FieldsType);
        switch (info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    for (fields, 0..) |field, i| {
                        if (i > 0) sql = sql ++ ", ";
                        sql = sql ++ field.table ++ "." ++ field.column;
                    }
                } else {
                    for (struct_info.fields, 0..) |sf, i| {
                        const field = @field(fields, sf.name);
                        if (i > 0) sql = sql ++ ", ";
                        sql = sql ++ field.table ++ "." ++ field.column ++ " AS \"" ++ sf.name ++ "\"";
                    }
                }
            },
            else => @compileError("select() expects a tuple of fields or a named struct literal"),
        }

        // 2. FROM clause (First table)
        const FirstTable = Tables[0];
        sql = sql ++ " FROM " ++ tableNameOfComptime(FirstTable);

        // 3. JOIN clauses
        for (Joins) |join_def| {
            sql = sql ++ " " ++ join_def.join_type.toSql() ++ " ";

            // Table name
            sql = sql ++ join_def.table_name;

            // ON condition
            sql = sql ++ " ON " ++ join_def.condition.left.table ++ "." ++ join_def.condition.left.column ++ " " ++ join_def.condition.op.toSql() ++ " " ++ join_def.condition.right.table ++ "." ++ join_def.condition.right.column;
        }

        return sql;
    }
}

fn placeholderListComptime(comptime count: usize) []const u8 {
    comptime var sql: []const u8 = "(";
    inline for (0..count) |index| {
        if (index > 0) sql = sql ++ ", ";
        sql = sql ++ "?";
    }
    sql = sql ++ ")";
    return sql;
}

fn valueSqlParamComptime(comptime value: Value) []const u8 {
    return switch (value) {
        .int, .float, .string, .bool_val, .named_param => "?",
        .null_value => "NULL",
        .array_int => |arr| placeholderListComptime(arr.len),
        .array_float => |arr| placeholderListComptime(arr.len),
        .array_string => |arr| placeholderListComptime(arr.len),
        .range_int, .range_float => "? AND ?",
    };
}

fn conditionSqlComptime(comptime cond: Condition, comptime placeholder_mode: bool) []const u8 {
    comptime var sql: []const u8 = "";
    if (cond.negated) sql = sql ++ "NOT (";

    if (cond.op == .match_table) {
        sql = sql ++ cond.field.table ++ " " ++ cond.op.toSql();
    } else {
        sql = sql ++ cond.field.table ++ "." ++ cond.field.column ++ " " ++ cond.op.toSql();
    }

    if (cond.op != .is_null and cond.op != .is_not_null) {
        sql = sql ++ " ";
        if (placeholder_mode) {
            sql = sql ++ valueSqlParamComptime(cond.value);
        } else {
            @compileError("conditionSqlComptime currently supports placeholder mode only");
        }
    }

    if (cond.negated) sql = sql ++ ")";
    return sql;
}

fn logicalConditionSqlComptime(comptime logical: LogicalCondition, comptime placeholder_mode: bool) []const u8 {
    comptime var stack: [MAX_LOGICAL_TOKENS][]const u8 = undefined;
    comptime var stack_len: usize = 0;

    inline for (logical.tokens[0..logical.len]) |token| {
        switch (token) {
            .condition => |cond| {
                stack[stack_len] = conditionSqlComptime(cond, placeholder_mode);
                stack_len += 1;
            },
            .op => |op| {
                if (stack_len < 2) {
                    @compileError("invalid logical condition expression");
                }

                const right = stack[stack_len - 1];
                const left = stack[stack_len - 2];
                stack_len -= 2;

                stack[stack_len] = "(" ++ left ++ " " ++ logicalOpToSql(op) ++ " " ++ right ++ ")";
                stack_len += 1;
            },
        }
    }

    if (stack_len != 1) {
        @compileError("invalid logical condition expression");
    }

    return stack[0];
}

fn staticConditionSqlComptime(comptime expr: anytype, comptime placeholder_mode: bool) []const u8 {
    const ExprType = @TypeOf(expr);
    if (ExprType == Condition) return conditionSqlComptime(expr, placeholder_mode);
    if (ExprType == LogicalCondition) return logicalConditionSqlComptime(expr, placeholder_mode);
    @compileError("comptimeSql conditions must be Condition or LogicalCondition, got " ++ @typeName(ExprType));
}

fn GenerateSqlWithStaticConditions(comptime base_sql: []const u8, comptime static_conditions: anytype) []const u8 {
    comptime {
        const CondType = @TypeOf(static_conditions);
        const cond_info = @typeInfo(CondType);
        switch (cond_info) {
            .@"struct" => |struct_info| {
                if (!struct_info.is_tuple) {
                    @compileError("comptimeSql expects a tuple literal, e.g. .{ cond1, cond2 }");
                }
            },
            else => @compileError("comptimeSql expects a tuple literal, e.g. .{ cond1, cond2 }"),
        }

        var sql: []const u8 = base_sql;
        if (static_conditions.len > 0) {
            sql = sql ++ " WHERE ";
            for (static_conditions, 0..) |cond, index| {
                if (index > 0) sql = sql ++ " AND ";
                sql = sql ++ staticConditionSqlComptime(cond, true);
            }
        }

        return sql;
    }
}

pub fn JoinBuilder(comptime Tables: anytype, comptime Joins: anytype) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn join(self: Self, comptime NewTable: anytype, comptime condition: JoinCondition) JoinBuilder(Tables ++ .{NewTable}, Joins ++ .{ComptimeJoinDef{ .join_type = .inner, .table_name = tableNameOfComptime(NewTable), .condition = condition }}) {
            return JoinBuilder(Tables ++ .{NewTable}, Joins ++ .{ComptimeJoinDef{ .join_type = .inner, .table_name = tableNameOfComptime(NewTable), .condition = condition }}).init(self.allocator);
        }

        pub fn leftJoin(self: Self, comptime NewTable: anytype, comptime condition: JoinCondition) JoinBuilder(Tables ++ .{NewTable}, Joins ++ .{ComptimeJoinDef{ .join_type = .left, .table_name = tableNameOfComptime(NewTable), .condition = condition }}) {
            return JoinBuilder(Tables ++ .{NewTable}, Joins ++ .{ComptimeJoinDef{ .join_type = .left, .table_name = tableNameOfComptime(NewTable), .condition = condition }}).init(self.allocator);
        }

        pub fn rightJoin(self: Self, comptime NewTable: anytype, comptime condition: JoinCondition) JoinBuilder(Tables ++ .{NewTable}, Joins ++ .{ComptimeJoinDef{ .join_type = .right, .table_name = tableNameOfComptime(NewTable), .condition = condition }}) {
            return JoinBuilder(Tables ++ .{NewTable}, Joins ++ .{ComptimeJoinDef{ .join_type = .right, .table_name = tableNameOfComptime(NewTable), .condition = condition }}).init(self.allocator);
        }

        pub fn select(self: Self, comptime fields: anytype) SelectBuilder(Tables, Joins, fields) {
            // Validation: Ensure every field belongs to a joined table
            const FieldsType = @TypeOf(fields);
            const info = @typeInfo(FieldsType);
            switch (info) {
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple) {
                        inline for (fields) |f| {
                            comptime var found = false;
                            inline for (Tables) |T| {
                                const t_name = comptime tableNameOfComptime(T);
                                if (comptime std.mem.eql(u8, t_name, f.table)) found = true;
                            }
                            if (!found) {
                                @compileError("Field '" ++ f.column ++ "' belongs to table '" ++ f.table ++ "' which is not joined!");
                            }
                        }
                    } else {
                        inline for (struct_info.fields) |sf| {
                            const f = @field(fields, sf.name);
                            comptime var found = false;
                            inline for (Tables) |T| {
                                const t_name = comptime tableNameOfComptime(T);
                                if (comptime std.mem.eql(u8, t_name, f.table)) found = true;
                            }
                            if (!found) {
                                @compileError("Field '" ++ f.column ++ "' belongs to table '" ++ f.table ++ "' which is not joined!");
                            }
                        }
                    }
                },
                else => @compileError("select() expects a tuple of fields or a named struct literal"),
            }
            return SelectBuilder(Tables, Joins, fields).init(self.allocator);
        }
    };
}

pub fn SelectBuilder(comptime Tables: anytype, comptime Joins: anytype, comptime selected_fields: anytype) type {
    return struct {
        const Self = @This();

        pub const ResultType = GenerateResultStruct(Tables, Joins, selected_fields);
        pub const base_sql = GenerateSql(Tables, Joins, selected_fields);

        const ParamRequirement = struct {
            name: []const u8,
            kind: ParamKind,
        };

        allocator: std.mem.Allocator,
        conditions: std.ArrayListUnmanaged(Condition),
        logical_conditions: std.ArrayListUnmanaged(LogicalCondition),
        param_requirements: std.ArrayListUnmanaged(ParamRequirement),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .conditions = .{},
                .logical_conditions = .{},
                .param_requirements = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.conditions.deinit(self.allocator);
            self.logical_conditions.deinit(self.allocator);
            self.param_requirements.deinit(self.allocator);
        }

        fn recordParamRequirement(self: *Self, param_name: []const u8, kind: ParamKind) !void {
            for (self.param_requirements.items) |existing| {
                if (!std.mem.eql(u8, existing.name, param_name)) continue;
                if (existing.kind != kind) return error.NamedParameterTypeMismatch;
                return;
            }

            try self.param_requirements.append(self.allocator, .{ .name = param_name, .kind = kind });
        }

        pub fn where(self: *Self, comptime field: anytype, op: Operator, value: anytype) !void {
            const FieldType = @TypeOf(field).field_type;
            const InputType = @TypeOf(value);

            const condition_value: Value = if (comptime isQueryParamType(InputType)) blk: {
                const ParamType = InputType.param_type;
                if (FieldType != ParamType and !typesCompatible(FieldType, ParamType)) {
                    @compileError("param() type mismatch: field '" ++ field.column ++ "' expects " ++ @typeName(FieldType) ++ " but got " ++ @typeName(ParamType));
                }
                try self.recordParamRequirement(value.name, paramKindFromType(ParamType));
                break :blk .{ .named_param = value.name };
            } else blk: {
                const typed_value: FieldType = value;
                break :blk Value.from(typed_value);
            };

            try self.conditions.append(self.allocator, Condition{
                .field = .{ .table = field.table, .column = field.column },
                .op = op,
                .value = condition_value,
            });
        }

        fn appendWhereExpression(self: *Self, expression: anytype) !void {
            const ExprType = @TypeOf(expression);
            if (ExprType == Condition) {
                try self.conditions.append(self.allocator, expression);
                return;
            }
            if (ExprType == LogicalCondition) {
                try self.logical_conditions.append(self.allocator, expression);
                return;
            }

            @compileError("where()/whereCondition() expects Condition or LogicalCondition, got " ++ @typeName(ExprType));
        }

        pub fn whereCondition(self: *Self, condition: anytype) !void {
            try self.appendWhereExpression(condition);
        }

        fn resolveNamedParam(bound_params: anytype, target_name: []const u8) ?Value {
            const ParamsType = @TypeOf(bound_params);
            const info = @typeInfo(ParamsType);

            switch (info) {
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple) {
                        @compileError("flattenedValuesWith() expects a named struct, e.g. .{ .min_age = 18 }");
                    }

                    inline for (struct_info.fields) |sf| {
                        if (std.mem.eql(u8, sf.name, target_name)) {
                            const v = @field(bound_params, sf.name);
                            return Value.from(v);
                        }
                    }
                },
                else => {
                    @compileError("flattenedValuesWith() expects a named struct, e.g. .{ .min_age = 18 }");
                },
            }

            return null;
        }

        fn kindFromParamsType(comptime Params: type, target_name: []const u8) ?ParamKind {
            const info = @typeInfo(Params);
            switch (info) {
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple) {
                        @compileError("flattenedValuesAs expects a named params struct type from params(.{ ... })");
                    }

                    inline for (struct_info.fields) |sf| {
                        if (std.mem.eql(u8, sf.name, target_name)) {
                            return paramKindFromType(sf.type);
                        }
                    }
                },
                else => {
                    @compileError("flattenedValuesAs expects a named params struct type from params(.{ ... })");
                },
            }
            return null;
        }

        fn validateParamsSpec(self: *Self, comptime Params: type) !void {
            for (self.param_requirements.items) |required| {
                const actual_kind = kindFromParamsType(Params, required.name) orelse return error.MissingNamedParameter;
                if (actual_kind != required.kind) return error.NamedParameterTypeMismatch;
            }
        }

        pub fn toSqlInto(self: *Self, writer: anytype) !void {
            try writer.writeAll(base_sql);
            if (self.conditions.items.len > 0 or self.logical_conditions.items.len > 0) {
                try writer.writeAll(" WHERE ");
                var wrote_any = false;

                for (self.conditions.items) |cond| {
                    if (wrote_any) try writer.writeAll(" AND ");
                    try writeConditionSql(writer, cond, true);
                    wrote_any = true;
                }

                for (self.logical_conditions.items) |logical| {
                    if (wrote_any) try writer.writeAll(" AND ");
                    try writeLogicalConditionSql(writer, self.allocator, logical, true);
                    wrote_any = true;
                }
            }
        }

        pub fn toSql(self: *Self) ![]const u8 {
            var sql = try std.ArrayListUnmanaged(u8).initCapacity(self.allocator, base_sql.len + 100);
            errdefer sql.deinit(self.allocator);

            try self.toSqlInto(sql.writer(self.allocator));
            return sql.toOwnedSlice(self.allocator);
        }

        /// Generate SQL fully at comptime for fixed query shapes.
        ///
        /// `static_conditions` must be a tuple literal of `Condition` and/or `LogicalCondition`.
        /// Values are rendered as placeholders (`?`), matching runtime `toSql` behavior.
        pub fn comptimeSql(comptime static_conditions: anytype) []const u8 {
            return comptime GenerateSqlWithStaticConditions(base_sql, static_conditions);
        }

        fn appendConditionValueNoParams(self: *Self, values: *std.ArrayListUnmanaged(Value), cond: Condition) !void {
            switch (cond.value) {
                .int, .float, .string, .bool_val, .null_value => {
                    try values.append(self.allocator, cond.value);
                },
                .array_int => |arr| {
                    for (arr) |v| try values.append(self.allocator, .{ .int = v });
                },
                .array_float => |arr| {
                    for (arr) |v| try values.append(self.allocator, .{ .float = v });
                },
                .array_string => |arr| {
                    for (arr) |v| try values.append(self.allocator, .{ .string = v });
                },
                .range_int => |r| {
                    try values.append(self.allocator, .{ .int = r.min });
                    try values.append(self.allocator, .{ .int = r.max });
                },
                .range_float => |r| {
                    try values.append(self.allocator, .{ .float = r.min });
                    try values.append(self.allocator, .{ .float = r.max });
                },
                .named_param => return error.UnboundNamedParameter,
            }
        }

        fn appendConditionValueWithParams(self: *Self, values: *std.ArrayListUnmanaged(Value), cond: Condition, bound_params: anytype) !void {
            switch (cond.value) {
                .int, .float, .string, .bool_val, .null_value => {
                    try values.append(self.allocator, cond.value);
                },
                .array_int => |arr| {
                    for (arr) |v| try values.append(self.allocator, .{ .int = v });
                },
                .array_float => |arr| {
                    for (arr) |v| try values.append(self.allocator, .{ .float = v });
                },
                .array_string => |arr| {
                    for (arr) |v| try values.append(self.allocator, .{ .string = v });
                },
                .range_int => |r| {
                    try values.append(self.allocator, .{ .int = r.min });
                    try values.append(self.allocator, .{ .int = r.max });
                },
                .range_float => |r| {
                    try values.append(self.allocator, .{ .float = r.min });
                    try values.append(self.allocator, .{ .float = r.max });
                },
                .named_param => |param_name| {
                    const resolved = resolveNamedParam(bound_params, param_name) orelse return error.MissingNamedParameter;
                    try values.append(self.allocator, resolved);
                },
            }
        }

        pub fn flattenedValues(self: *Self) ![]Value {
            var values = std.ArrayListUnmanaged(Value){};
            defer values.deinit(self.allocator);

            for (self.conditions.items) |cond| {
                try self.appendConditionValueNoParams(&values, cond);
            }

            for (self.logical_conditions.items) |logical| {
                for (logical.tokens[0..logical.len]) |token| {
                    switch (token) {
                        .condition => |cond| try self.appendConditionValueNoParams(&values, cond),
                        .op => {},
                    }
                }
            }
            return values.toOwnedSlice(self.allocator);
        }

        pub fn flattenedValuesWith(self: *Self, bound_params: anytype) ![]Value {
            var values = std.ArrayListUnmanaged(Value){};
            defer values.deinit(self.allocator);

            for (self.conditions.items) |cond| {
                try self.appendConditionValueWithParams(&values, cond, bound_params);
            }

            for (self.logical_conditions.items) |logical| {
                for (logical.tokens[0..logical.len]) |token| {
                    switch (token) {
                        .condition => |cond| try self.appendConditionValueWithParams(&values, cond, bound_params),
                        .op => {},
                    }
                }
            }

            return values.toOwnedSlice(self.allocator);
        }

        pub fn flattenedValuesAs(self: *Self, comptime Params: type, bound_params: Params) ![]Value {
            const info = @typeInfo(Params);
            switch (info) {
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple) {
                        @compileError("flattenedValuesAs expects a named params struct type from params(.{ ... })");
                    }
                },
                else => {
                    @compileError("flattenedValuesAs expects a named params struct type from params(.{ ... })");
                },
            }
            try self.validateParamsSpec(Params);
            return self.flattenedValuesWith(bound_params);
        }
    };
}

pub fn Query(comptime Table: anytype) JoinBuilder(.{Table}, .{}) {
    return query(Table, std.heap.page_allocator);
}

/// Build a fixed-shape query intended for comptime SQL generation via `.comptimeSql(...)`.
pub fn QueryStatic(comptime Table: anytype) JoinBuilder(.{Table}, .{}) {
    return Query(Table);
}

/// Build a comptime query using a concrete allocator immediately.
pub fn query(comptime Table: anytype, allocator: std.mem.Allocator) JoinBuilder(.{Table}, .{}) {
    return JoinBuilder(.{Table}, .{}).init(allocator);
}

/// Alias for QueryStatic() for ergonomic API symmetry.
pub fn queryStatic(comptime Table: anytype) JoinBuilder(.{Table}, .{}) {
    return QueryStatic(Table);
}

/// Alias for Query() to support a more SQL-like entrypoint style.
pub fn from(comptime Table: anytype) JoinBuilder(.{Table}, .{}) {
    return Query(Table);
}

// ============================================================
// SHARED TYPES
// ============================================================

pub const JoinType = enum {
    inner,
    left,
    right,
    full,

    pub fn toSql(self: JoinType) []const u8 {
        return switch (self) {
            .inner => "INNER JOIN",
            .left => "LEFT JOIN",
            .right => "RIGHT JOIN",
            .full => "FULL OUTER JOIN",
        };
    }
};

pub const Join = struct {
    join_type: JoinType,
    table: []const u8,
    condition: JoinCondition,
};

pub const Condition = struct {
    field: FieldRef,
    op: Operator,
    value: Value,
    negated: bool = false,

    pub fn not(self: Condition) Condition {
        var result = self;
        result.negated = !result.negated;
        return result;
    }

    pub fn and_(self: Condition, other: anytype) LogicalCondition {
        return LogicalCondition.combine(logicalToExpression(self), .and_, logicalToExpression(other));
    }

    pub fn or_(self: Condition, other: anytype) LogicalCondition {
        return LogicalCondition.combine(logicalToExpression(self), .or_, logicalToExpression(other));
    }
};

const MAX_LOGICAL_TOKENS = 64;

pub const LogicalToken = union(enum) {
    condition: Condition,
    op: LogicalOp,
};

pub const LogicalCondition = struct {
    len: usize,
    tokens: [MAX_LOGICAL_TOKENS]LogicalToken,

    fn single(cond: Condition) LogicalCondition {
        var out: LogicalCondition = .{
            .len = 0,
            .tokens = undefined,
        };
        out.append(.{ .condition = cond });
        return out;
    }

    fn append(self: *LogicalCondition, token: LogicalToken) void {
        std.debug.assert(self.len < MAX_LOGICAL_TOKENS);
        self.tokens[self.len] = token;
        self.len += 1;
    }

    fn combine(left: LogicalCondition, op: LogicalOp, right: LogicalCondition) LogicalCondition {
        var out: LogicalCondition = .{
            .len = 0,
            .tokens = undefined,
        };

        for (left.tokens[0..left.len]) |token| out.append(token);
        for (right.tokens[0..right.len]) |token| out.append(token);
        out.append(.{ .op = op });

        return out;
    }

    pub fn and_(self: LogicalCondition, other: anytype) LogicalCondition {
        return combine(self, .and_, logicalToExpression(other));
    }

    pub fn or_(self: LogicalCondition, other: anytype) LogicalCondition {
        return combine(self, .or_, logicalToExpression(other));
    }
};

fn logicalToExpression(term: anytype) LogicalCondition {
    const T = @TypeOf(term);
    if (T == Condition) return LogicalCondition.single(term);
    if (T == LogicalCondition) return term;
    @compileError("logical expression expects Condition or LogicalCondition, got " ++ @typeName(T));
}

pub const LogicalOp = enum {
    and_,
    or_,
};

pub const Operator = enum {
    eq,
    neq,
    gt,
    gte,
    lt,
    lte,
    like,
    glob,
    match,
    regexp,
    match_table,
    in,
    between,
    is_null,
    is_not_null,

    pub fn toSql(self: Operator) []const u8 {
        return switch (self) {
            .eq => "=",
            .neq => "!=",
            .gt => ">",
            .gte => ">=",
            .lt => "<",
            .lte => "<=",
            .like => "LIKE",
            .glob => "GLOB",
            .match => "MATCH",
            .regexp => "REGEXP",
            .match_table => "MATCH",
            .in => "IN",
            .between => "BETWEEN",
            .is_null => "IS NULL",
            .is_not_null => "IS NOT NULL",
        };
    }
};

pub const Value = union(enum) {
    null_value: void,
    int: i64,
    float: f64,
    string: []const u8,
    bool_val: bool,
    // For IN operator
    array_int: []const i64,
    array_float: []const f64,
    array_string: []const []const u8,
    // For BETWEEN operator
    range_int: struct { min: i64, max: i64 },
    range_float: struct { min: f64, max: f64 },
    named_param: []const u8,

    pub fn from(value: anytype) Value {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .int, .comptime_int => return .{ .int = @intCast(value) },
            .float, .comptime_float => return .{ .float = @floatCast(value) },
            .pointer => |ptr| {
                if (ptr.child == u8) {
                    return .{ .string = value };
                }

                const child_info = @typeInfo(ptr.child);
                if (child_info == .array and child_info.array.child == u8) {
                    return .{ .string = value };
                }

                @compileError("Unsupported pointer type");
            },
            .bool => return .{ .bool_val = value },
            .null => return .null_value,
            else => @compileError("Unsupported value type"),
        }
    }

    pub fn fromArray(values: anytype) Value {
        const T = @TypeOf(values);
        const type_info = @typeInfo(T);

        if (type_info != .pointer) {
            @compileError("fromArray expects a slice or array pointer");
        }

        const child_type = type_info.pointer.child;
        const child_info = @typeInfo(child_type);

        return switch (child_info) {
            .int => .{ .array_int = values },
            .float => .{ .array_float = values },
            .array => |arr_info| {
                // Handle array types like [5]i64 or [3][]const u8
                const elem_info = @typeInfo(arr_info.child);
                return switch (elem_info) {
                    .int => .{ .array_int = values },
                    .float => .{ .array_float = values },
                    .pointer => |ptr| {
                        // Handle string arrays like [3][]const u8
                        if (ptr.child == u8) {
                            return .{ .array_string = values };
                        }
                        @compileError("Unsupported array element type");
                    },
                    else => @compileError("Unsupported array element type"),
                };
            },
            .pointer => |ptr| {
                if (ptr.child == u8) {
                    return .{ .array_string = values };
                }
                @compileError("Unsupported array element type");
            },
            else => @compileError("Unsupported array type"),
        };
    }

    pub fn fromRange(min: anytype, max: anytype) Value {
        const T = @TypeOf(min);
        return switch (@typeInfo(T)) {
            .int => .{
                .range_int = .{
                    .min = @intCast(min),
                    .max = @intCast(max),
                },
            },
            .float => .{
                .range_float = .{
                    .min = @floatCast(min),
                    .max = @floatCast(max),
                },
            },
            else => @compileError("BETWEEN only supports numeric types"),
        };
    }

    pub fn toSqlParam(self: Value, writer: anytype) !void {
        switch (self) {
            .int, .float, .string, .bool_val, .named_param => try writer.writeAll("?"),
            .null_value => try writer.writeAll("NULL"), // NULL is usually literal in SQL
            .array_int => |arr| {
                try writer.writeAll("(");
                for (arr, 0..) |_, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll("?");
                }
                try writer.writeAll(")");
            },
            .array_float => |arr| {
                try writer.writeAll("(");
                for (arr, 0..) |_, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll("?");
                }
                try writer.writeAll(")");
            },
            .array_string => |arr| {
                try writer.writeAll("(");
                for (arr, 0..) |_, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll("?");
                }
                try writer.writeAll(")");
            },
            .range_int, .range_float => {
                try writer.writeAll("? AND ?");
            },
        }
    }

    pub fn toSql(self: Value, writer: anytype) !void {
        switch (self) {
            .int => |v| try writer.print("{}", .{v}),
            .float => |v| try writer.print("{}", .{v}),
            .string => |v| try writer.print("'{s}'", .{v}),
            .bool_val => |v| try writer.print("{}", .{v}),
            .null_value => try writer.writeAll("NULL"),
            .array_int => |arr| {
                try writer.writeAll("(");
                for (arr, 0..) |val, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{}", .{val});
                }
                try writer.writeAll(")");
            },
            .array_float => |arr| {
                try writer.writeAll("(");
                for (arr, 0..) |val, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{}", .{val});
                }
                try writer.writeAll(")");
            },
            .array_string => |arr| {
                try writer.writeAll("(");
                for (arr, 0..) |val, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("'{s}'", .{val});
                }
                try writer.writeAll(")");
            },
            .range_int => |r| {
                try writer.print("{} AND {}", .{ r.min, r.max });
            },
            .range_float => |r| {
                try writer.print("{} AND {}", .{ r.min, r.max });
            },
            .named_param => |name| {
                try writer.print(":{s}", .{name});
            },
        }
    }
};

pub const FieldRef = struct {
    table: []const u8,
    column: []const u8,
    // field_type removed for runtime compatibility
};

pub const SelectedField = struct {
    field: FieldRef,
    /// Optional SQL column alias for the SELECT list.
    /// When set, we emit: `table.column AS "alias"`.
    alias: ?[]const u8 = null,
};

pub const JoinCondition = struct {
    left: FieldRef,
    right: FieldRef,
    op: Operator,
};

pub const OrderBy = struct {
    field: FieldRef,
    direction: Direction,

    pub const Direction = enum {
        asc,
        desc,
    };
};

// ============================================================
// SIMPLE RUNTIME QUERY BUILDER
// ============================================================
// Since Zig's comptime has limitations with complex state tracking,
// we provide a runtime query builder that still maintains type safety
// through the Field types

pub const QueryBuilder = struct {
    allocator: std.mem.Allocator,
    select_fields: std.ArrayListUnmanaged(SelectedField),
    from_table: ?[]const u8 = null,
    joins: std.ArrayListUnmanaged(Join),
    where_conditions: std.ArrayListUnmanaged(Condition),
    logical_where_conditions: std.ArrayListUnmanaged(LogicalCondition),
    raw_where_fragments: std.ArrayListUnmanaged([]u8),
    group_by_fields: std.ArrayListUnmanaged(FieldRef),
    having_conditions: std.ArrayListUnmanaged(Condition),
    order_by: std.ArrayListUnmanaged(OrderBy),
    limit_value: ?usize = null,
    offset_value: ?usize = null,
    distinct: bool = false,

    pub fn init(allocator: std.mem.Allocator) QueryBuilder {
        return .{
            .allocator = allocator,
            .select_fields = .{},
            .joins = .{},
            .where_conditions = .{},
            .logical_where_conditions = .{},
            .raw_where_fragments = .{},
            .group_by_fields = .{},
            .having_conditions = .{},
            .order_by = .{},
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        self.select_fields.deinit(self.allocator);
        self.joins.deinit(self.allocator);
        self.where_conditions.deinit(self.allocator);
        self.logical_where_conditions.deinit(self.allocator);
        for (self.raw_where_fragments.items) |fragment| {
            self.allocator.free(fragment);
        }
        self.raw_where_fragments.deinit(self.allocator);
        self.group_by_fields.deinit(self.allocator);
        self.having_conditions.deinit(self.allocator);
        self.order_by.deinit(self.allocator);
    }

    fn renderRawWhere(self: *QueryBuilder, sql_fragment: []const u8, values: anytype) []u8 {
        var rendered: std.ArrayListUnmanaged(u8) = .{};
        const writer = rendered.writer(self.allocator);

        const ValuesType = @TypeOf(values);
        const info = @typeInfo(ValuesType);
        var remaining = sql_fragment;

        switch (info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    inline for (values) |v| {
                        const marker_index = std.mem.indexOfScalar(u8, remaining, '?') orelse unreachable;
                        writer.writeAll(remaining[0..marker_index]) catch unreachable;
                        Value.from(v).toSql(writer) catch unreachable;
                        remaining = remaining[marker_index + 1 ..];
                    }
                } else {
                    const marker_index = std.mem.indexOfScalar(u8, remaining, '?') orelse unreachable;
                    writer.writeAll(remaining[0..marker_index]) catch unreachable;
                    Value.from(values).toSql(writer) catch unreachable;
                    remaining = remaining[marker_index + 1 ..];
                }
            },
            else => {
                const marker_index = std.mem.indexOfScalar(u8, remaining, '?') orelse unreachable;
                writer.writeAll(remaining[0..marker_index]) catch unreachable;
                Value.from(values).toSql(writer) catch unreachable;
                remaining = remaining[marker_index + 1 ..];
            },
        }

        std.debug.assert(std.mem.indexOfScalar(u8, remaining, '?') == null);
        writer.writeAll(remaining) catch unreachable;

        return rendered.toOwnedSlice(self.allocator) catch unreachable;
    }

    pub fn select(self: *QueryBuilder, fields: anytype) *QueryBuilder {
        const fields_info = @typeInfo(@TypeOf(fields));

        // Check if it's a struct (tuple)
        switch (fields_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    // It's a tuple - iterate and add all fields
                    inline for (fields) |field| {
                        self.select_fields.append(self.allocator, .{ .field = field.toFieldRef() }) catch unreachable;
                    }
                } else {
                    if (@hasDecl(@TypeOf(fields), "toFieldRef")) {
                        // It's a single Field
                        self.select_fields.append(self.allocator, .{ .field = fields.toFieldRef() }) catch unreachable;
                    } else {
                        // Named selection: `.{ .alias = DB.table.col, ... }`
                        inline for (struct_info.fields) |sf| {
                            const v = @field(fields, sf.name);
                            self.select_fields.append(self.allocator, .{ .field = v.toFieldRef(), .alias = sf.name }) catch unreachable;
                        }
                    }
                }
            },
            else => {
                // Single field
                self.select_fields.append(self.allocator, .{ .field = fields.toFieldRef() }) catch unreachable;
            },
        }

        return self;
    }

    pub fn selectDistinct(self: *QueryBuilder, fields: anytype) *QueryBuilder {
        self.distinct = true;
        return self.select(fields);
    }

    pub fn from(self: *QueryBuilder, source_table: anytype) *QueryBuilder {
        self.from_table = tableNameOfRuntime(source_table);
        return self;
    }

    fn appendWhereExpression(self: *QueryBuilder, expression: anytype) void {
        const ExprType = @TypeOf(expression);
        if (ExprType == Condition) {
            self.where_conditions.append(self.allocator, expression) catch unreachable;
            return;
        }
        if (ExprType == LogicalCondition) {
            self.logical_where_conditions.append(self.allocator, expression) catch unreachable;
            return;
        }

        @compileError("where() expects Condition or LogicalCondition, got " ++ @typeName(ExprType));
    }

    pub fn where(self: *QueryBuilder, conditions: anytype) *QueryBuilder {
        const conditions_info = @typeInfo(@TypeOf(conditions));

        // Check if it's a struct (tuple)
        switch (conditions_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    // It's a tuple - iterate and add all conditions
                    inline for (conditions) |condition| {
                        self.appendWhereExpression(condition);
                    }
                } else {
                    // It's a single condition struct
                    self.appendWhereExpression(conditions);
                }
            },
            else => {
                // Single condition
                self.appendWhereExpression(conditions);
            },
        }

        return self;
    }

    pub fn whereRaw(self: *QueryBuilder, sql_fragment: []const u8, values: anytype) *QueryBuilder {
        const rendered = self.renderRawWhere(sql_fragment, values);
        self.raw_where_fragments.append(self.allocator, rendered) catch unreachable;
        return self;
    }

    pub fn orderBy(self: *QueryBuilder, orders: anytype) *QueryBuilder {
        const orders_info = @typeInfo(@TypeOf(orders));

        // Check if it's a struct (tuple)
        switch (orders_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    // It's a tuple - iterate and add all order clauses
                    inline for (orders) |order| {
                        self.order_by.append(self.allocator, order) catch unreachable;
                    }
                } else {
                    // It's a single order clause struct
                    self.order_by.append(self.allocator, orders) catch unreachable;
                }
            },
            else => {
                // Single order clause
                self.order_by.append(self.allocator, orders) catch unreachable;
            },
        }

        return self;
    }

    pub fn join(self: *QueryBuilder, join_table: anytype, condition: JoinCondition) *QueryBuilder {
        self.joins.append(self.allocator, Join{
            .join_type = .inner,
            .table = tableNameOfRuntime(join_table),
            .condition = condition,
        }) catch unreachable;
        return self;
    }

    pub fn leftJoin(self: *QueryBuilder, join_table: anytype, condition: JoinCondition) *QueryBuilder {
        self.joins.append(self.allocator, Join{
            .join_type = .left,
            .table = tableNameOfRuntime(join_table),
            .condition = condition,
        }) catch unreachable;
        return self;
    }

    pub fn rightJoin(self: *QueryBuilder, join_table: anytype, condition: JoinCondition) *QueryBuilder {
        self.joins.append(self.allocator, Join{
            .join_type = .right,
            .table = tableNameOfRuntime(join_table),
            .condition = condition,
        }) catch unreachable;
        return self;
    }

    pub fn groupBy(self: *QueryBuilder, fields: anytype) *QueryBuilder {
        const fields_info = @typeInfo(@TypeOf(fields));

        // Check if it's a struct (tuple)
        switch (fields_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    // It's a tuple - iterate and add all fields
                    inline for (fields) |field| {
                        self.group_by_fields.append(self.allocator, field.toFieldRef()) catch unreachable;
                    }
                } else {
                    // It's a single field struct
                    self.group_by_fields.append(self.allocator, fields.toFieldRef()) catch unreachable;
                }
            },
            else => {
                // Single field
                self.group_by_fields.append(self.allocator, fields.toFieldRef()) catch unreachable;
            },
        }

        return self;
    }

    pub fn having(self: *QueryBuilder, conditions: anytype) *QueryBuilder {
        const conditions_info = @typeInfo(@TypeOf(conditions));

        // Check if it's a struct (tuple)
        switch (conditions_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    // It's a tuple - iterate and add all conditions
                    inline for (conditions) |condition| {
                        self.having_conditions.append(self.allocator, condition) catch unreachable;
                    }
                } else {
                    // It's a single condition struct
                    self.having_conditions.append(self.allocator, conditions) catch unreachable;
                }
            },
            else => {
                // Single condition
                self.having_conditions.append(self.allocator, conditions) catch unreachable;
            },
        }

        return self;
    }

    pub fn limit(self: *QueryBuilder, n: usize) *QueryBuilder {
        self.limit_value = n;
        return self;
    }

    pub fn offset(self: *QueryBuilder, n: usize) *QueryBuilder {
        self.offset_value = n;
        return self;
    }

    pub fn toSql(self: *QueryBuilder) ![]u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        errdefer buffer.deinit(self.allocator);
        const writer = buffer.writer(self.allocator);

        // SELECT
        try writer.writeAll("SELECT ");
        if (self.distinct) try writer.writeAll("DISTINCT ");
        if (self.select_fields.items.len == 0) {
            try writer.writeAll("*");
        } else {
            for (self.select_fields.items, 0..) |item, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}.{s}", .{ item.field.table, item.field.column });
                if (item.alias) |alias| {
                    try writer.print(" AS \"{s}\"", .{alias});
                }
            }
        }

        // FROM
        const from_name = self.from_table orelse return error.MissingFromTable;
        try writer.print("\nFROM {s}", .{from_name});

        // JOINs
        for (self.joins.items) |j| {
            try writer.print("\n{s} {s} ON {s}.{s} = {s}.{s}", .{
                j.join_type.toSql(),
                j.table,
                j.condition.left.table,
                j.condition.left.column,
                j.condition.right.table,
                j.condition.right.column,
            });
        }

        // WHERE
        if (self.where_conditions.items.len > 0 or self.logical_where_conditions.items.len > 0 or self.raw_where_fragments.items.len > 0) {
            try writer.writeAll("\nWHERE ");
            var wrote_any = false;

            for (self.where_conditions.items) |cond| {
                if (wrote_any) try writer.writeAll(" AND ");
                try writeConditionSql(writer, cond, false);
                wrote_any = true;
            }

            for (self.logical_where_conditions.items) |logical| {
                if (wrote_any) try writer.writeAll(" AND ");
                try writeLogicalConditionSql(writer, self.allocator, logical, false);
                wrote_any = true;
            }

            for (self.raw_where_fragments.items) |fragment| {
                if (wrote_any) try writer.writeAll(" AND ");
                try writer.writeAll(fragment);
                wrote_any = true;
            }
        }

        // GROUP BY
        if (self.group_by_fields.items.len > 0) {
            try writer.writeAll("\nGROUP BY ");
            for (self.group_by_fields.items, 0..) |field, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}.{s}", .{ field.table, field.column });
            }
        }

        // HAVING
        if (self.having_conditions.items.len > 0) {
            try writer.writeAll("\nHAVING ");
            for (self.having_conditions.items, 0..) |cond, i| {
                if (i > 0) try writer.writeAll(" AND ");
                try writeConditionSql(writer, cond, false);
            }
        }

        // ORDER BY
        if (self.order_by.items.len > 0) {
            try writer.writeAll("\nORDER BY ");
            for (self.order_by.items, 0..) |order, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}.{s} {s}", .{
                    order.field.table,
                    order.field.column,
                    if (order.direction == .asc) "ASC" else "DESC",
                });
            }
        }

        // LIMIT
        if (self.limit_value) |lim| {
            try writer.print("\nLIMIT {}", .{lim});
        }

        // OFFSET
        if (self.offset_value) |off| {
            try writer.print("\nOFFSET {}", .{off});
        }

        return buffer.toOwnedSlice(self.allocator);
    }
};

// ============================================================
// RUNTIME QUERY APPROACHES
// ============================================================
//
// There are THREE ways to build queries in this library:
//
// 1. COMPTIME QUERY (Query) - Full type inference, best for static queries
//    const MyQuery = Query(DB.users)
//        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
//        .select(.{ DB.users.name, DB.posts.title });
//    // ResultType is auto-generated!
//
// 2. RUNTIME QUERYBUILDER - Flexible, for dynamic queries with runtime conditions
//    var query = QueryBuilder.init(allocator);
//    _ = query.select(.{ DB.users.name }).from(DB.users);
//    if (filter.age != null) _ = query.where(DB.users.age.gt(filter.age.?));
//    // Result type must be specified when executing
//
// 3. TYPED MUTATIONS - Type-safe INSERT/UPDATE/DELETE
//    var insert = TypedInsert(DB.users).init(allocator);
//    _ = insert.set(DB.users.name, "John");  // Type checked!
//    _ = insert.set(DB.users.age, 25);       // Type checked!
//
// The key insight: Field operations (eq, gt, like, etc.) are ALWAYS type-safe
// because they're defined on Field(T) and enforce the type at the call site.
// Runtime builders just collect these pre-validated conditions.

// ============================================================
// TYPE-SAFE MUTATIONS
// ============================================================

pub fn TypedInsert(comptime Table: anytype) type {
    return struct {
        const Self = @This();
        const table_name_comptime = tableNameOfComptime(Table);

        allocator: std.mem.Allocator,
        table_name: []const u8,
        columns: std.ArrayListUnmanaged([]const u8),
        values: std.ArrayListUnmanaged(Value),
        returning_column: ?[]const u8 = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .table_name = table_name_comptime,
                .columns = .{},
                .values = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.columns.deinit(self.allocator);
            self.values.deinit(self.allocator);
        }

        /// Type-safe value setting - field type must match value type
        pub fn set(self: *Self, comptime field: anytype, value: @TypeOf(field).field_type) *Self {
            // Validate field belongs to this table at compile time
            comptime {
                if (!std.mem.eql(u8, field.table, table_name_comptime)) {
                    @compileError("Field '" ++ field.column ++ "' belongs to table '" ++ field.table ++ "', not '" ++ table_name_comptime ++ "'");
                }
            }

            self.columns.append(self.allocator, field.column) catch unreachable;
            self.values.append(self.allocator, Value.from(value)) catch unreachable;
            return self;
        }

        pub fn returning(self: *Self, column: []const u8) *Self {
            self.returning_column = column;
            return self;
        }

        pub fn toSql(self: *Self) ![]u8 {
            var buffer = std.ArrayListUnmanaged(u8){};
            const writer = buffer.writer(self.allocator);

            try writer.print("INSERT INTO {s} (", .{self.table_name});

            for (self.columns.items, 0..) |column_name, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(column_name);
            }

            try writer.writeAll(") VALUES (");

            for (self.values.items, 0..) |val, i| {
                if (i > 0) try writer.writeAll(", ");
                try val.toSql(writer);
            }

            try writer.writeAll(")");

            if (self.returning_column) |ret| {
                try writer.print(" RETURNING {s}", .{ret});
            }

            return buffer.toOwnedSlice(self.allocator);
        }
    };
}

pub fn TypedUpdate(comptime Table: anytype) type {
    return struct {
        const Self = @This();
        const table_name_comptime = tableNameOfComptime(Table);

        allocator: std.mem.Allocator,
        table_name: []const u8,
        sets: std.ArrayListUnmanaged(SetClause),
        where_conditions: std.ArrayListUnmanaged(Condition),

        const SetClause = struct {
            column: []const u8,
            value: Value,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .table_name = table_name_comptime,
                .sets = .{},
                .where_conditions = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.sets.deinit(self.allocator);
            self.where_conditions.deinit(self.allocator);
        }

        /// Type-safe set - field type must match value type
        pub fn set(self: *Self, comptime field: anytype, value: @TypeOf(field).field_type) *Self {
            comptime {
                if (!std.mem.eql(u8, field.table, table_name_comptime)) {
                    @compileError("Field '" ++ field.column ++ "' belongs to table '" ++ field.table ++ "', not '" ++ table_name_comptime ++ "'");
                }
            }

            self.sets.append(self.allocator, .{
                .column = field.column,
                .value = Value.from(value),
            }) catch unreachable;
            return self;
        }

        pub fn where(self: *Self, conditions: anytype) *Self {
            const conditions_info = @typeInfo(@TypeOf(conditions));
            switch (conditions_info) {
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple) {
                        inline for (conditions) |condition| {
                            self.where_conditions.append(self.allocator, condition) catch unreachable;
                        }
                    } else {
                        self.where_conditions.append(self.allocator, conditions) catch unreachable;
                    }
                },
                else => {
                    self.where_conditions.append(self.allocator, conditions) catch unreachable;
                },
            }
            return self;
        }

        pub fn toSql(self: *Self) ![]u8 {
            var buffer = std.ArrayListUnmanaged(u8){};
            const writer = buffer.writer(self.allocator);

            try writer.print("UPDATE {s} SET ", .{self.table_name});

            for (self.sets.items, 0..) |s, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s} = ", .{s.column});
                try s.value.toSql(writer);
            }

            if (self.where_conditions.items.len > 0) {
                try writer.writeAll(" WHERE ");
                for (self.where_conditions.items, 0..) |cond, i| {
                    if (i > 0) try writer.writeAll(" AND ");
                    try writer.print("{s}.{s} {s} ", .{
                        cond.field.table,
                        cond.field.column,
                        cond.op.toSql(),
                    });
                    if (cond.op != .is_null and cond.op != .is_not_null) {
                        try cond.value.toSql(writer);
                    }
                }
            }

            return buffer.toOwnedSlice(self.allocator);
        }
    };
}

pub fn TypedDelete(comptime Table: anytype) type {
    return struct {
        const Self = @This();
        const table_name_comptime = tableNameOfComptime(Table);

        allocator: std.mem.Allocator,
        table_name: []const u8,
        where_conditions: std.ArrayListUnmanaged(Condition),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .table_name = table_name_comptime,
                .where_conditions = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.where_conditions.deinit(self.allocator);
        }

        pub fn where(self: *Self, conditions: anytype) *Self {
            const conditions_info = @typeInfo(@TypeOf(conditions));
            switch (conditions_info) {
                .@"struct" => |struct_info| {
                    if (struct_info.is_tuple) {
                        inline for (conditions) |condition| {
                            self.where_conditions.append(self.allocator, condition) catch unreachable;
                        }
                    } else {
                        self.where_conditions.append(self.allocator, conditions) catch unreachable;
                    }
                },
                else => {
                    self.where_conditions.append(self.allocator, conditions) catch unreachable;
                },
            }
            return self;
        }

        pub fn toSql(self: *Self) ![]u8 {
            var buffer = std.ArrayListUnmanaged(u8){};
            const writer = buffer.writer(self.allocator);

            try writer.print("DELETE FROM {s}", .{self.table_name});

            if (self.where_conditions.items.len > 0) {
                try writer.writeAll(" WHERE ");
                for (self.where_conditions.items, 0..) |cond, i| {
                    if (i > 0) try writer.writeAll(" AND ");
                    try writer.print("{s}.{s} {s} ", .{
                        cond.field.table,
                        cond.field.column,
                        cond.op.toSql(),
                    });
                    if (cond.op != .is_null and cond.op != .is_not_null) {
                        try cond.value.toSql(writer);
                    }
                }
            }

            return buffer.toOwnedSlice(self.allocator);
        }

        /// Safe delete - requires WHERE clause (prevents accidental DELETE ALL)
        pub fn toSqlSafe(self: *Self) ![]u8 {
            if (self.where_conditions.items.len == 0) {
                return error.DeleteRequiresWhereClause;
            }
            return self.toSql();
        }
    };
}

// ============================================================
// EXAMPLE SCHEMA DEFINITION
// ============================================================

pub const ExampleDB = schema(.{
    .users = table("users", .{
        .id = col(i32),
        .name = col([]const u8),
        .email = col([]const u8),
        .age = col(i32),
    }),
    .posts = table("posts", .{
        .id = col(i32),
        .user_id = col(i32),
        .title = col([]const u8),
        .content = col([]const u8),
    }),
});

// ============================================================
// TESTS
// ============================================================

test "field operators" {
    const DB = ExampleDB;

    // Test comparison operators
    const cond1 = DB.users.age.gt(25);
    try std.testing.expectEqual(Operator.gt, cond1.op);
    try std.testing.expectEqual(@as(i64, 25), cond1.value.int);

    // Test string operators
    const cond2 = DB.users.name.like("%john%");
    try std.testing.expectEqual(Operator.like, cond2.op);
    try std.testing.expectEqualStrings("%john%", cond2.value.string);

    const cond3 = DB.users.name.glob("J*");
    try std.testing.expectEqual(Operator.glob, cond3.op);
    try std.testing.expectEqualStrings("J*", cond3.value.string);

    const cond4 = DB.users.name.match("zig parser");
    try std.testing.expectEqual(Operator.match, cond4.op);
    try std.testing.expectEqualStrings("zig parser", cond4.value.string);

    // Test join conditions
    const join_cond = DB.posts.user_id.eqField(DB.users.id);
    try std.testing.expectEqualStrings("posts", join_cond.left.table);
    try std.testing.expectEqualStrings("users", join_cond.right.table);

    // Test ordering
    const order = DB.users.name.asc();
    try std.testing.expectEqual(OrderBy.Direction.asc, order.direction);
}

test "schema DSL - generates typed table values" {
    const DB = schema(.{
        .users = table("users", .{
            .id = col(i32),
            .name = col([]const u8),
            .age = col(i32),
        }),
        .posts = table("posts", .{
            .id = col(i32),
            .user_id = col(i32),
            .title = col([]const u8),
        }),
    });

    try std.testing.expectEqualStrings("users", DB.users._table_name);
    try std.testing.expectEqualStrings("users", DB.users.id.table);
    try std.testing.expectEqualStrings("id", DB.users.id.column);

    comptime {
        if (@TypeOf(DB.users.id).field_type != i32) @compileError("id should be i32");
        if (@TypeOf(DB.users.name).field_type != []const u8) @compileError("name should be []const u8");
    }

    const join_cond = DB.posts.user_id.eqField(DB.users.id);
    try std.testing.expectEqualStrings("posts", join_cond.left.table);
    try std.testing.expectEqualStrings("users", join_cond.right.table);
}

test "schema DSL - columns helper" {
    const allocator = std.testing.allocator;
    const DB = schema(.{
        .users = table("users", .{
            .id = col(i32),
            .name = col([]const u8),
            .age = col(i32),
        }),
    });

    const cols = columns(DB.users);
    comptime {
        const ColsType = @TypeOf(cols);
        const info = @typeInfo(ColsType).@"struct";
        if (!info.is_tuple) @compileError("columns() should return a tuple");
        if (info.fields.len != 3) @compileError("columns() should include all non-_table_name fields");
    }

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb.select(cols).from(DB.users);

    const sql = try qb.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.id, users.name, users.age") != null);
}

test "query builder - select star and missing from guard" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var no_from_query = QueryBuilder.init(allocator);
    defer no_from_query.deinit();
    _ = no_from_query.select(DB.users.name);
    try std.testing.expectError(error.MissingFromTable, no_from_query.toSql());

    var star_query = QueryBuilder.init(allocator);
    defer star_query.deinit();
    _ = star_query.from(DB.users);

    const sql = try star_query.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT *") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users") != null);
}

test "query builder - raw where fragment" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(DB.users.name)
        .from(DB.users)
        .where(DB.users.age.gte(18))
        .whereRaw("length(users.email) > 10", .{});

    const sql = try qb.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age >= 18 AND length(users.email) > 10") != null);
}

test "query builder - raw where with typed values" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(DB.users.name)
        .from(DB.users)
        .whereRaw("users.email LIKE ? AND users.age >= ?", .{ "%@example.com", @as(i32, 18) });

    const sql = try qb.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.email LIKE '%@example.com' AND users.age >= 18") != null);
}

test "comptime builder - schema DSL values" {
    const allocator = std.testing.allocator;
    const DB = schema(.{
        .users = table("users", .{
            .id = col(i32),
            .name = col([]const u8),
            .age = col(i32),
        }),
        .posts = table("posts", .{
            .id = col(i32),
            .user_id = col(i32),
            .title = col([]const u8),
        }),
    });

    var builder = query(DB.users, allocator)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ .user_name = DB.users.name, .post_title = DB.posts.title });
    defer builder.deinit();

    const ResType = @TypeOf(builder).ResultType;
    comptime {
        if (!@hasField(ResType, "user_name")) @compileError("ResultType missing user_name");
        if (!@hasField(ResType, "post_title")) @compileError("ResultType missing post_title");
    }

    try builder.where(DB.users.age, .gte, 18);

    const sql = try builder.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name AS \"user_name\", posts.title AS \"post_title\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN posts ON posts.user_id = users.id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age >= ?") != null);
}

test "comptime builder - toSqlInto avoids intermediate string allocation" {
    const allocator = std.testing.allocator;
    const DB = schema(.{
        .users = table("users", .{
            .id = col(i32),
            .name = col([]const u8),
            .age = col(i32),
        }),
    });

    var builder = query(DB.users, allocator)
        .select(.{ DB.users.id, DB.users.name });
    defer builder.deinit();

    try builder.where(DB.users.age, .gte, 21);

    var sql_buffer: std.ArrayListUnmanaged(u8) = .{};
    defer sql_buffer.deinit(allocator);
    try builder.toSqlInto(sql_buffer.writer(allocator));

    const sql = try sql_buffer.toOwnedSlice(allocator);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.id, users.name FROM users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age >= ?") != null);
}

test "comptime builder - static SQL path with fixed shape" {
    const DB = ExampleDB;

    const q = queryStatic(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ .user_name = DB.users.name, .post_title = DB.posts.title });

    const static_sql = comptime @TypeOf(q).comptimeSql(.{
        DB.users.age.gte(18),
        DB.posts.title.like("%Zig%"),
    });

    try std.testing.expect(std.mem.indexOf(u8, static_sql, "SELECT users.name AS \"user_name\", posts.title AS \"post_title\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, static_sql, "INNER JOIN posts ON posts.user_id = users.id") != null);
    try std.testing.expect(std.mem.indexOf(u8, static_sql, "WHERE users.age >= ? AND posts.title LIKE ?") != null);
}

test "comptime builder - static SQL supports logical expressions" {
    const DB = ExampleDB;

    const q = QueryStatic(DB.users)
        .select(.{ DB.users.id, DB.users.name });

    const static_sql = comptime @TypeOf(q).comptimeSql(.{
        DB.users.age.gt(21).or_(DB.users.age.lt(18)),
    });

    try std.testing.expect(std.mem.indexOf(u8, static_sql, "WHERE (users.age > ? OR users.age < ?)") != null);
}

test "comptime builder - columns helper" {
    const allocator = std.testing.allocator;
    const DB = schema(.{
        .users = table("users", .{
            .id = col(i32),
            .name = col([]const u8),
            .age = col(i32),
        }),
    });

    var builder = query(DB.users, allocator)
        .select(columns(DB.users));
    defer builder.deinit();

    const Row = @TypeOf(builder).ResultType;
    comptime {
        if (!@hasField(Row, "id")) @compileError("Row missing id");
        if (!@hasField(Row, "name")) @compileError("Row missing name");
        if (!@hasField(Row, "age")) @compileError("Row missing age");
    }

    const sql = try builder.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.id, users.name, users.age FROM users") != null);
}

test "query builder - single field chaining" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb.select(DB.users.name);
    _ = qb.select(DB.users.age);
    _ = qb.from(DB.users);
    _ = qb.where(DB.users.age.gt(25));
    _ = qb.orderBy(DB.users.name.asc());
    _ = qb.limit(10);

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (single field):\n{s}\n", .{sql});

    // Verify SQL contains expected parts
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name, users.age") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age > 25") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "ORDER BY users.name ASC") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
}

test "query builder - tuple-based API" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    // Use tuple syntax for ergonomic API
    _ = qb
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

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (tuple-based):\n{s}\n", .{sql});

    // Verify SQL contains expected parts
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name, users.age, users.email") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age > 25 AND users.email LIKE '%@example.com'") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "ORDER BY users.age DESC, users.name ASC") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
}

test "query builder - named select aliases" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(.{ .user_name = DB.users.name, .user_age = DB.users.age })
        .from(DB.users)
        .where(DB.users.age.gt(25));

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (named select):\n{s}\n", .{sql});

    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name AS \"user_name\", users.age AS \"user_age\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age > 25") != null);
}

test "query builder - join with tuple API" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(.{
            DB.users.name,
            DB.posts.title,
            DB.posts.content,
        })
        .from(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .where(.{
            DB.users.age.gt(18),
            DB.posts.title.like("%Zig%"),
        })
        .orderBy(DB.posts.id.desc())
        .limit(5);

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (join with tuples):\n{s}\n", .{sql});

    // Verify SQL contains expected parts
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name, posts.title, posts.content") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN posts ON posts.user_id = users.id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age > 18 AND posts.title LIKE '%Zig%'") != null);
}

test "IN operator - integers" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    // Use i64 for storage (Value uses i64 internally)
    const ids = &[_]i64{ 1, 2, 3, 4, 5 };
    _ = qb
        .select(DB.users.name)
        .from(DB.users)
        .where(DB.users.id.in(ids));

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (IN operator - integers):\n{s}\n", .{sql});

    // Verify SQL contains IN clause
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.id IN (1, 2, 3, 4, 5)") != null);
}

test "IN operator - strings" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    const statuses = &[_][]const u8{ "active", "premium", "vip" };
    _ = qb
        .select(DB.users.name)
        .from(DB.users)
        .where(DB.users.email.in(statuses));

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (IN operator - strings):\n{s}\n", .{sql});

    // Verify SQL contains IN clause with strings
    try std.testing.expect(std.mem.indexOf(u8, sql, "IN ('active', 'premium', 'vip')") != null);
}

test "SQLite dialect operators - GLOB and REGEXP" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(DB.users.name)
        .from(DB.users)
        .where(.{
        DB.users.name.glob("J*"),
        DB.users.email.regexp(".+@example\\.com"),
    });

    const sql = try qb.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "users.name GLOB 'J*'") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "users.email REGEXP '.+@example\\.com'") != null);
}

test "SQLite FTS table MATCH helper" {
    const allocator = std.testing.allocator;
    const DB = schema(.{
        .docs_fts = table("docs_fts", .{
            .title = col([]const u8),
            .body = col([]const u8),
        }),
    });

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(DB.docs_fts.title)
        .from(DB.docs_fts)
        .where(tableMatch(DB.docs_fts, "zig parser"));

    const sql = try qb.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE docs_fts MATCH 'zig parser'") != null);
}

test "BETWEEN operator" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(.{ DB.users.name, DB.users.age })
        .from(DB.users)
        .where(DB.users.age.between(18, 65));

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (BETWEEN operator):\n{s}\n", .{sql});

    // Verify SQL contains BETWEEN clause
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age BETWEEN 18 AND 65") != null);
}

test "NOT operator" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(DB.users.name)
        .from(DB.users)
        .where(DB.users.email.like("%@spam.com").not());

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (NOT operator):\n{s}\n", .{sql});

    // Verify SQL contains NOT clause
    try std.testing.expect(std.mem.indexOf(u8, sql, "NOT (") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "users.email LIKE '%@spam.com'") != null);
}

test "DISTINCT" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .selectDistinct(DB.users.email)
        .from(DB.users);

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (DISTINCT):\n{s}\n", .{sql});

    // Verify SQL contains DISTINCT
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT DISTINCT users.email") != null);
}

test "Combined new features" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    const status_values = [_][]const u8{ "active", "premium" };
    _ = qb
        .selectDistinct(.{ DB.users.name, DB.users.email })
        .from(DB.users)
        .where(.{
            DB.users.age.between(18, 65),
            DB.users.email.like("%@spam.com").not(),
        })
        .orderBy(DB.users.name.asc())
        .limit(10);

    const sql = try qb.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (combined new features):\n{s}\n", .{sql});

    // Verify all new features
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT DISTINCT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "BETWEEN 18 AND 65") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "NOT (") != null);
    _ = status_values; // Acknowledge unused variable
}

test "comptime select builder with join" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    // 1. Define the query structure (Comptime)
    // Query(Table) -> JoinBuilder. join(Table, condition) -> JoinBuilder. select(...) -> SelectBuilder
    const MyQueryBuilder = Query(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ DB.users.name, DB.posts.title });

    // 2. Instantiate the builder (Runtime)
    // Note: Query()... returns an INSTANCE of JoinBuilder.
    // .select() returns an INSTANCE of SelectBuilder.
    // We need to re-assign allocator because the default one is dummy.
    var builder = MyQueryBuilder;
    builder.allocator = allocator;
    defer builder.deinit();

    // 3. Use runtime values
    try builder.where(DB.users.age, .gt, 25);
    try builder.where(DB.posts.title, .like, "%Zig%");

    // 4. Generate SQL
    const sql = try builder.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (comptime join):\n{s}\n", .{sql});

    // 5. Verify SQL (Parameterized)
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name, posts.title") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN posts ON posts.user_id = users.id") != null);
    // Expect ? placeholders
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age > ? AND posts.title LIKE ?") != null);

    // 6. Verify ResultType existence (compile-time check)
    const ResType = @TypeOf(MyQueryBuilder).ResultType;
    const fields = @typeInfo(ResType).@"struct".fields;
    try std.testing.expectEqual(2, fields.len);
    // Collision handling check (if collision existed)
}

test "comptime select builder with named result" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    const MyQueryBuilder = Query(DB.users)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ .user_name = DB.users.name, .post_title = DB.posts.title });

    // Verify ResultType field names exist (compile-time intent)
    const ResType = @TypeOf(MyQueryBuilder).ResultType;
    comptime {
        if (!@hasField(ResType, "user_name")) @compileError("ResultType missing field user_name");
        if (!@hasField(ResType, "post_title")) @compileError("ResultType missing field post_title");
    }

    var builder = MyQueryBuilder;
    builder.allocator = allocator;
    defer builder.deinit();

    try builder.where(DB.users.age, .gt, 25);

    const sql = try builder.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated SQL (comptime named select):\n{s}\n", .{sql});

    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT users.name AS \"user_name\", posts.title AS \"post_title\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN posts ON posts.user_id = users.id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age > ?") != null);
}

test "comptime join nullability - left join optional right side" {
    const DB = ExampleDB;

    const Q = Query(DB.users)
        .leftJoin(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{
        .user_name = DB.users.name,
        .post_title = DB.posts.title,
    });

    const Row = @TypeOf(Q).ResultType;
    comptime {
        const sample: Row = undefined;
        if (@TypeOf(sample.user_name) != []const u8) {
            @compileError("left join should keep left table field non-optional");
        }
        if (@TypeOf(sample.post_title) != ?[]const u8) {
            @compileError("left join should make right table field optional");
        }
    }
}

test "comptime join nullability - right join optional left side" {
    const DB = ExampleDB;

    const Q = Query(DB.users)
        .rightJoin(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{
        .user_name = DB.users.name,
        .post_title = DB.posts.title,
    });

    const Row = @TypeOf(Q).ResultType;
    comptime {
        const sample: Row = undefined;
        if (@TypeOf(sample.user_name) != ?[]const u8) {
            @compileError("right join should make left table field optional");
        }
        if (@TypeOf(sample.post_title) != []const u8) {
            @compileError("right join should keep right table field non-optional");
        }
    }
}

test "comptime select builder with named params" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var builder = query(DB.users, allocator)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ .user_name = DB.users.name, .post_title = DB.posts.title });
    defer builder.deinit();

    try builder.where(DB.users.age, .gte, param("min_age", i32));
    try builder.where(DB.posts.title, .like, param("title_pattern", []const u8));

    const sql = try builder.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age >= ? AND posts.title LIKE ?") != null);

    try std.testing.expectError(error.UnboundNamedParameter, builder.flattenedValues());
    try std.testing.expectError(error.MissingNamedParameter, builder.flattenedValuesWith(.{ .min_age = 18 }));

    const values = try builder.flattenedValuesWith(.{
        .min_age = @as(i32, 21),
        .title_pattern = "%Zig%",
    });
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqual(Value{ .int = 21 }, values[0]);
    try std.testing.expectEqualStrings("%Zig%", values[1].string);
}

test "comptime select builder with params type" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;
    const QueryParams = params(.{
        .min_age = i32,
        .title_pattern = []const u8,
    });

    var builder = query(DB.users, allocator)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ .user_name = DB.users.name, .post_title = DB.posts.title });
    defer builder.deinit();

    try builder.where(DB.users.age, .gte, param("min_age", i32));
    try builder.where(DB.posts.title, .like, param("title_pattern", []const u8));

    const values = try builder.flattenedValuesAs(QueryParams, .{
        .min_age = @as(i32, 30),
        .title_pattern = "%Zig%",
    });
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqual(Value{ .int = 30 }, values[0]);
    try std.testing.expectEqualStrings("%Zig%", values[1].string);
}

test "comptime builder - SQLite MATCH with typed params" {
    const allocator = std.testing.allocator;
    const DB = schema(.{
        .docs_fts = table("docs_fts", .{
            .title = col([]const u8),
            .body = col([]const u8),
        }),
    });
    const SearchParams = params(.{ .q = []const u8 });

    var builder = query(DB.docs_fts, allocator)
        .select(.{DB.docs_fts.title});
    defer builder.deinit();

    try builder.where(DB.docs_fts.title, .match, param("q", []const u8));

    const sql = try builder.toSql();
    defer allocator.free(sql);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE docs_fts.title MATCH ?") != null);

    const values = try builder.flattenedValuesAs(SearchParams, .{ .q = "zig parser" });
    defer allocator.free(values);
    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqualStrings("zig parser", values[0].string);
}

test "query builder - logical OR condition" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(DB.users.name)
        .from(DB.users)
        .where(DB.users.age.gt(21).or_(DB.users.age.lt(18)));

    const sql = try qb.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE (users.age > 21 OR users.age < 18)") != null);
}

test "comptime builder - logical AND condition" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var builder = query(DB.users, allocator)
        .select(.{ DB.users.id, DB.users.name });
    defer builder.deinit();

    try builder.whereCondition(DB.users.age.gte(21).and_(DB.users.age.lte(65)));

    const sql = try builder.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE (users.age >= ? AND users.age <= ?)") != null);

    const values = try builder.flattenedValues();
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqual(Value{ .int = 21 }, values[0]);
    try std.testing.expectEqual(Value{ .int = 65 }, values[1]);
}

test "query builder - is null renders without extra value" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var qb = QueryBuilder.init(allocator);
    defer qb.deinit();

    _ = qb
        .select(DB.users.id)
        .from(DB.users)
        .where(DB.users.email.isNull());

    const sql = try qb.toSql();
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.email IS NULL") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "IS NULL NULL") == null);
}

// ============================================================
// TYPE SAFETY VERIFICATION TESTS
// ============================================================
// Uncomment any of these to verify compile-time type errors work:

// TEST: like() should only work on string fields
// Uncomment to verify: error: "like() is only available for string fields, got i32"
// test "COMPILE_ERROR: like on integer field" {
//     const cond = ExampleDB.users.age.like("%x%");
//     _ = cond;
// }

// TEST: eqField() should check type compatibility
// Uncomment to verify: error: "eqField() type mismatch: cannot join i32 with []const u8"
// test "COMPILE_ERROR: eqField with incompatible types" {
//     const cond = ExampleDB.users.age.eqField(ExampleDB.users.name);
//     _ = cond;
// }

// TEST: in() should check element types
// Uncomment to verify: error: "in() element type mismatch: field is i32 but got elements of []const u8"
// test "COMPILE_ERROR: in with wrong element types" {
//     const strings = &[_][]const u8{ "a", "b" };
//     const cond = ExampleDB.users.age.in(strings);
//     _ = cond;
// }

// TEST: param() should enforce placeholder type compatibility
// Uncomment to verify: error: "param() type mismatch: field 'age' expects i32 but got []const u8"
// test "COMPILE_ERROR: param type mismatch" {
//     var builder = Query(ExampleDB.users).select(.{ ExampleDB.users.id });
//     defer builder.deinit();
//     try builder.where(ExampleDB.users.age, .gte, param("min_age", []const u8));
// }

// ============================================================
// TYPED MUTATION TESTS
// ============================================================

test "TypedInsert - type-safe insert" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var insert = TypedInsert(DB.users).init(allocator);
    defer insert.deinit();

    // Type-safe: DB.users.name expects []const u8, DB.users.age expects i32
    _ = insert.set(DB.users.name, "John Doe");
    _ = insert.set(DB.users.age, 30);
    _ = insert.set(DB.users.email, "john@example.com");
    _ = insert.returning("id");

    const sql = try insert.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated INSERT SQL:\n{s}\n", .{sql});

    try std.testing.expect(std.mem.indexOf(u8, sql, "INSERT INTO users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "name, age, email") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "'John Doe', 30, 'john@example.com'") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "RETURNING id") != null);
}

test "TypedUpdate - type-safe update" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var update = TypedUpdate(DB.users).init(allocator);
    defer update.deinit();

    // Type-safe: values must match field types
    _ = update.set(DB.users.name, "Jane Doe");
    _ = update.set(DB.users.age, 31);
    _ = update.where(DB.users.id.eq(1));

    const sql = try update.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated UPDATE SQL:\n{s}\n", .{sql});

    try std.testing.expect(std.mem.indexOf(u8, sql, "UPDATE users SET") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "name = 'Jane Doe'") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "age = 31") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.id = 1") != null);
}

test "TypedDelete - type-safe delete" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var delete = TypedDelete(DB.users).init(allocator);
    defer delete.deinit();

    _ = delete.where(.{
        DB.users.age.lt(18),
        DB.users.email.like("%@spam.com"),
    });

    const sql = try delete.toSql();
    defer allocator.free(sql);

    std.debug.print("\nGenerated DELETE SQL:\n{s}\n", .{sql});

    try std.testing.expect(std.mem.indexOf(u8, sql, "DELETE FROM users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE users.age < 18") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "users.email LIKE '%@spam.com'") != null);
}

test "TypedDelete - safe delete requires WHERE" {
    const DB = ExampleDB;
    const allocator = std.testing.allocator;

    var delete = TypedDelete(DB.users).init(allocator);
    defer delete.deinit();

    // No WHERE clause - toSqlSafe should fail
    const result = delete.toSqlSafe();
    try std.testing.expectError(error.DeleteRequiresWhereClause, result);
}

test "Typed mutations - schema table values" {
    const allocator = std.testing.allocator;
    const DB = schema(.{
        .users = table("users", .{
            .id = col(i32),
            .name = col([]const u8),
            .age = col(i32),
        }),
    });

    var insert = TypedInsert(DB.users).init(allocator);
    defer insert.deinit();
    _ = insert.set(DB.users.name, "Taylor");
    _ = insert.set(DB.users.age, 40);

    const insert_sql = try insert.toSql();
    defer allocator.free(insert_sql);
    try std.testing.expect(std.mem.indexOf(u8, insert_sql, "INSERT INTO users") != null);

    var update = TypedUpdate(DB.users).init(allocator);
    defer update.deinit();
    _ = update.set(DB.users.age, 41);
    _ = update.where(DB.users.id.eq(1));

    const update_sql = try update.toSql();
    defer allocator.free(update_sql);
    try std.testing.expect(std.mem.indexOf(u8, update_sql, "UPDATE users SET") != null);

    var delete = TypedDelete(DB.users).init(allocator);
    defer delete.deinit();
    _ = delete.where(DB.users.id.eq(1));

    const delete_sql = try delete.toSqlSafe();
    defer allocator.free(delete_sql);
    try std.testing.expect(std.mem.indexOf(u8, delete_sql, "DELETE FROM users") != null);
}

// Uncomment to verify compile error: field belongs to wrong table
// test "COMPILE_ERROR: TypedInsert wrong table field" {
//     const DB = ExampleDB;
//     var insert = TypedInsert(DB.users).init(std.testing.allocator);
//     _ = insert.set(DB.posts.title, "Wrong table!"); // ERROR!
// }

// Uncomment to verify compile error: wrong value type
// test "COMPILE_ERROR: TypedInsert wrong value type" {
//     const DB = ExampleDB;
//     var insert = TypedInsert(DB.users).init(std.testing.allocator);
//     _ = insert.set(DB.users.age, "not an int"); // ERROR: expected i32, got string
// }
