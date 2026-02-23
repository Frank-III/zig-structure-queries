const std = @import("std");

/// SQLite type system
/// SQLite uses a dynamic type system with 5 storage classes
pub const SqliteType = enum {
    // Storage classes
    integer, // 1, 2, 3, 4, 6, or 8 bytes
    real, // 8-byte floating point
    text, // UTF-8, UTF-16BE or UTF-16LE
    blob, // Binary data
    null, // NULL value

    /// Convert from common SQL types to SQLite storage class
    pub fn fromCommonType(common_type: []const u8) SqliteType {
        // Integer types
        if (std.mem.eql(u8, common_type, "INTEGER") or
            std.mem.eql(u8, common_type, "INT") or
            std.mem.eql(u8, common_type, "SMALLINT") or
            std.mem.eql(u8, common_type, "BIGINT") or
            std.mem.eql(u8, common_type, "BOOLEAN"))
        {
            return .integer;
        }

        // Real types
        if (std.mem.eql(u8, common_type, "REAL") or
            std.mem.eql(u8, common_type, "DOUBLE") or
            std.mem.eql(u8, common_type, "FLOAT") or
            std.mem.eql(u8, common_type, "DECIMAL"))
        {
            return .real;
        }

        // Text types
        if (std.mem.eql(u8, common_type, "TEXT") or
            std.mem.eql(u8, common_type, "VARCHAR") or
            std.mem.eql(u8, common_type, "CHAR") or
            std.mem.eql(u8, common_type, "DATE") or
            std.mem.eql(u8, common_type, "DATETIME") or
            std.mem.eql(u8, common_type, "TIMESTAMP"))
        {
            return .text;
        }

        // Blob types
        if (std.mem.eql(u8, common_type, "BLOB") or
            std.mem.eql(u8, common_type, "BYTEA"))
        {
            return .blob;
        }

        return .text; // Default to text
    }

    /// Get the Zig type that maps to this SQLite type
    pub fn toZigType(self: SqliteType) type {
        return switch (self) {
            .integer => i64, // SQLite integers can be up to 8 bytes
            .real => f64,
            .text => []const u8,
            .blob => []const u8,
            .null => @TypeOf(null),
        };
    }

    /// SQL declaration for this type
    pub fn toSql(self: SqliteType) []const u8 {
        return switch (self) {
            .integer => "INTEGER",
            .real => "REAL",
            .text => "TEXT",
            .blob => "BLOB",
            .null => "NULL",
        };
    }
};

/// SQLite-specific column constraints
pub const SqliteConstraint = enum {
    primary_key,
    autoincrement, // Only valid with INTEGER PRIMARY KEY
    not_null,
    unique,
    check,
    default,
    collate,

    pub fn toSql(self: SqliteConstraint) []const u8 {
        return switch (self) {
            .primary_key => "PRIMARY KEY",
            .autoincrement => "AUTOINCREMENT",
            .not_null => "NOT NULL",
            .unique => "UNIQUE",
            .check => "CHECK",
            .default => "DEFAULT",
            .collate => "COLLATE",
        };
    }
};

/// SQLite column definition
pub fn SqliteColumn(comptime T: type) type {
    return struct {
        name: []const u8,
        type: SqliteType,
        constraints: []const SqliteConstraint = &.{},
        default_value: ?T = null,
        check_expr: ?[]const u8 = null,

        /// Generate SQL for this column
        pub fn toSql(self: @This(), allocator: std.mem.Allocator) ![]u8 {
            var parts = std.ArrayList([]const u8).init(allocator);
            defer parts.deinit();

            // Column name
            try parts.append(self.name);

            // Type
            try parts.append(self.type.toSql());

            // Constraints
            for (self.constraints) |constraint| {
                try parts.append(constraint.toSql());
            }

            // Default value
            if (self.default_value) |val| {
                try parts.append("DEFAULT");
                // Format the value based on type
                const val_str = try std.fmt.allocPrint(allocator, "{}", .{val});
                try parts.append(val_str);
            }

            // Check constraint
            if (self.check_expr) |expr| {
                const check_str = try std.fmt.allocPrint(allocator, "CHECK ({})", .{expr});
                try parts.append(check_str);
            }

            return std.mem.join(allocator, " ", parts.items);
        }

        /// Validate that T matches the SQLite type
        pub fn validate(comptime self: @This()) void {
            const expected = self.type.toZigType();
            const is_nullable = for (self.constraints) |c| {
                if (c == .not_null) break false;
            } else true;

            if (is_nullable) {
                if (T != ?expected and T != expected) {
                    @compileError(std.fmt.comptimePrint("Type mismatch for column '{}': expected {} or ?{}, got {}", .{ self.name, @typeName(expected), @typeName(expected), @typeName(T) }));
                }
            } else {
                if (T != expected) {
                    @compileError(std.fmt.comptimePrint("Type mismatch for column '{}': expected {}, got {}", .{ self.name, @typeName(expected), @typeName(T) }));
                }
            }
        }
    };
}

/// SQLite table definition
pub fn SqliteTable(comptime name: []const u8, comptime columns: anytype) type {
    return struct {
        pub const table_name = name;
        pub const Columns = columns;

        /// Generate CREATE TABLE SQL
        pub fn createTableSql(allocator: std.mem.Allocator) ![]u8 {
            var parts = std.ArrayList([]const u8).init(allocator);
            defer parts.deinit();

            try parts.append("CREATE TABLE");
            try parts.append(table_name);
            try parts.append("(");

            var col_defs = std.ArrayList([]const u8).init(allocator);
            defer col_defs.deinit();

            inline for (columns) |col| {
                const col_sql = try col.toSql(allocator);
                try col_defs.append(col_sql);
            }

            const cols_str = try std.mem.join(allocator, ", ", col_defs.items);
            try parts.append(cols_str);
            try parts.append(")");

            return std.mem.join(allocator, " ", parts.items);
        }

        /// Generate the Zig struct type for this table
        pub fn RowType() type {
            var fields: [columns.len]std.builtin.Type.StructField = undefined;

            inline for (columns, 0..) |col, i| {
                const is_nullable = for (col.constraints) |c| {
                    if (c == .not_null) break false;
                } else true;

                const FieldType = if (is_nullable)
                    ?col.type.toZigType()
                else
                    col.type.toZigType();

                fields[i] = .{
                    .name = col.name,
                    .type = FieldType,
                    .default_value = if (col.default_value) |d| &d else null,
                    .is_comptime = false,
                    .alignment = @alignOf(FieldType),
                };
            }

            return @Type(.{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = &fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        }
    };
}

// Example usage
test "SQLite dialect" {
    const users_table = SqliteTable("users", .{
        SqliteColumn(i64){
            .name = "id",
            .type = .integer,
            .constraints = &.{ .primary_key, .autoincrement },
        },
        SqliteColumn([]const u8){
            .name = "email",
            .type = .text,
            .constraints = &.{ .not_null, .unique },
        },
        SqliteColumn(?[]const u8){
            .name = "name",
            .type = .text,
        },
        SqliteColumn(i64){
            .name = "created_at",
            .type = .integer, // Unix timestamp
            .constraints = &.{.not_null},
            .default_value = 0,
        },
    });

    const posts_table = SqliteTable("posts", .{
        SqliteColumn(i64){
            .name = "id",
            .type = .integer,
            .constraints = &.{ .primary_key, .autoincrement },
        },
        SqliteColumn(i64){
            .name = "user_id",
            .type = .integer,
            .constraints = &.{.not_null},
        },
        SqliteColumn([]const u8){
            .name = "title",
            .type = .text,
            .constraints = &.{.not_null},
        },
        SqliteColumn(?[]const u8){
            .name = "content",
            .type = .text,
        },
    });

    // Generate row types
    const User = users_table.RowType();
    const Post = posts_table.RowType();

    // These types are now properly aligned with SQLite's type system
    _ = User;
    _ = Post;
}
