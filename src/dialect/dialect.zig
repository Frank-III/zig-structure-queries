const std = @import("std");
const sqlite = @import("sqlite.zig");

/// SQL dialect enumeration
pub const Dialect = enum {
    sqlite,
    postgres,
    mysql,

    /// Get the dialect from compile-time config
    pub fn current() Dialect {
        // This can be set via build options
        // For now, default to SQLite
        return if (@hasDecl(@import("root"), "sql_dialect"))
            @field(Dialect, @import("root").sql_dialect)
        else
            .sqlite;
    }
};

/// Type-safe join builder that adapts to the dialect
pub fn TypeSafeJoin(comptime dialect: Dialect) type {
    return struct {
        const Self = @This();

        /// Validate that two columns can be joined based on dialect rules
        pub fn validateJoin(comptime left_table: anytype, comptime left_column: []const u8, comptime right_table: anytype, comptime right_column: []const u8) void {
            switch (dialect) {
                .sqlite => validateSqliteJoin(left_table, left_column, right_table, right_column),
                .postgres => @compileError("PostgreSQL dialect not yet implemented"),
                .mysql => @compileError("MySQL dialect not yet implemented"),
            }
        }

        fn validateSqliteJoin(comptime left_table: anytype, comptime left_column: []const u8, comptime right_table: anytype, comptime right_column: []const u8) void {
            // Find columns
            const left_col = findColumn(left_table.Columns, left_column);
            const right_col = findColumn(right_table.Columns, right_column);

            if (left_col == null) {
                @compileError(std.fmt.comptimePrint("Column '{}' not found in left table", .{left_column}));
            }

            if (right_col == null) {
                @compileError(std.fmt.comptimePrint("Column '{}' not found in right table", .{right_column}));
            }

            // Check type compatibility for SQLite
            // SQLite is very permissive, but we enforce stricter rules
            const left_type = left_col.?.type;
            const right_type = right_col.?.type;

            const compatible = switch (left_type) {
                .integer => right_type == .integer,
                .real => right_type == .real or right_type == .integer,
                .text => right_type == .text,
                .blob => right_type == .blob,
                .null => true, // NULL can join with anything in SQLite
            };

            if (!compatible) {
                @compileError(std.fmt.comptimePrint("Cannot join {} column '{}' with {} column '{}'", .{ left_type, left_column, right_type, right_column }));
            }
        }

        fn findColumn(comptime columns: anytype, comptime name: []const u8) ?@TypeOf(columns[0]) {
            inline for (columns) |col| {
                if (std.mem.eql(u8, col.name, name)) {
                    return col;
                }
            }
            return null;
        }
    };
}

/// Query builder that generates dialect-specific SQL
pub fn QueryBuilder(comptime dialect: Dialect) type {
    return struct {
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Generate JOIN SQL based on dialect
        pub fn generateJoinSql(
            self: Self,
            join_type: []const u8,
            left_table: []const u8,
            left_alias: []const u8,
            right_table: []const u8,
            right_alias: []const u8,
            left_column: []const u8,
            right_column: []const u8,
        ) ![]u8 {
            return switch (dialect) {
                .sqlite => try std.fmt.allocPrint(self.allocator, "{s} JOIN {s} {s} ON {s}.{s} = {s}.{s}", .{ join_type, right_table, right_alias, left_alias, left_column, right_alias, right_column }),
                .postgres => try std.fmt.allocPrint(self.allocator, "{s} JOIN {s} AS {s} ON {s}.{s} = {s}.{s}", .{ join_type, right_table, right_alias, left_alias, left_column, right_alias, right_column }),
                .mysql => try std.fmt.allocPrint(self.allocator, "{s} JOIN `{s}` `{s}` ON `{s}`.`{s}` = `{s}`.`{s}`", .{ join_type, right_table, right_alias, left_alias, left_column, right_alias, right_column }),
            };
        }

        /// Quote identifier based on dialect
        pub fn quoteIdentifier(self: Self, identifier: []const u8) ![]u8 {
            return switch (dialect) {
                .sqlite => try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{identifier}),
                .postgres => try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{identifier}),
                .mysql => try std.fmt.allocPrint(self.allocator, "`{s}`", .{identifier}),
            };
        }

        /// Generate parameter placeholder based on dialect
        pub fn parameterPlaceholder(self: Self, index: usize) ![]u8 {
            return switch (dialect) {
                .sqlite => try std.fmt.allocPrint(self.allocator, "?{}", .{index}),
                .postgres => try std.fmt.allocPrint(self.allocator, "${}", .{index + 1}),
                .mysql => try std.fmt.allocPrint(self.allocator, "?", .{}),
            };
        }
    };
}

// Conditional compilation example
pub fn getDialectFeatures() type {
    const dialect = Dialect.current();

    return struct {
        pub const supports_returning = switch (dialect) {
            .sqlite => true, // SQLite 3.35.0+
            .postgres => true,
            .mysql => false,
        };

        pub const supports_upsert = switch (dialect) {
            .sqlite => true, // ON CONFLICT
            .postgres => true, // ON CONFLICT
            .mysql => true, // ON DUPLICATE KEY UPDATE
        };

        pub const supports_window_functions = switch (dialect) {
            .sqlite => true, // SQLite 3.25.0+
            .postgres => true,
            .mysql => true, // MySQL 8.0+
        };

        pub const max_identifier_length = switch (dialect) {
            .sqlite => 255,
            .postgres => 63,
            .mysql => 64,
        };
    };
}

test "dialect system" {
    const SqliteJoin = TypeSafeJoin(.sqlite);
    const users_table = sqlite.SqliteTable("users", .{
        sqlite.SqliteColumn(i64){
            .name = "id",
            .type = .integer,
            .constraints = &.{.primary_key},
        },
    });

    const posts_table = sqlite.SqliteTable("posts", .{
        sqlite.SqliteColumn(i64){
            .name = "user_id",
            .type = .integer,
        },
    });

    // This would validate at compile time
    SqliteJoin.validateJoin(users_table, "id", posts_table, "user_id");

    // Test query builder
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const builder = QueryBuilder(.sqlite).init(gpa.allocator());
    const join_sql = try builder.generateJoinSql("INNER", "users", "u", "posts", "p", "id", "user_id");
    defer gpa.allocator().free(join_sql);

    try std.testing.expectEqualStrings("INNER JOIN posts p ON u.id = p.user_id", join_sql);
}
