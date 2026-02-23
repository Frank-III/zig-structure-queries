const std = @import("std");

// ===========================================================================
// INSERT/UPDATE/DELETE BUILDERS
// ===========================================================================

// INSERT Builder
pub const InsertBuilder = struct {
    allocator: std.mem.Allocator,
    table: []const u8,
    columns: std.ArrayListUnmanaged([]const u8),
    values: std.ArrayListUnmanaged(Value),
    returning_column: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, table: anytype) InsertBuilder {
        return .{
            .allocator = allocator,
            .table = table._table_name,
            .columns = .{},
            .values = .{},
        };
    }

    pub fn deinit(self: *InsertBuilder) void {
        self.columns.deinit(self.allocator);
        self.values.deinit(self.allocator);
    }

    pub fn value(self: *InsertBuilder, field: anytype, val: anytype) *InsertBuilder {
        const field_ref = field.toFieldRef();
        self.columns.append(self.allocator, field_ref.column) catch unreachable;
        self.values.append(self.allocator, Value.from(val)) catch unreachable;
        return self;
    }

    pub fn returning(self: *InsertBuilder, column: []const u8) *InsertBuilder {
        self.returning_column = column;
        return self;
    }

    pub fn toSql(self: *InsertBuilder) ![]u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        const writer = buffer.writer(self.allocator);

        try writer.print("INSERT INTO {s} (", .{self.table});

        // Columns
        for (self.columns.items, 0..) |col, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(col);
        }

        try writer.writeAll(") VALUES (");

        // Values
        for (self.values.items, 0..) |val, i| {
            if (i > 0) try writer.writeAll(", ");
            try val.toSql(writer);
        }

        try writer.writeAll(")");

        // RETURNING clause (for getting auto-generated IDs)
        if (self.returning_column) |ret| {
            try writer.print(" RETURNING {s}", .{ret});
        }

        return buffer.toOwnedSlice(self.allocator);
    }
};

// UPDATE Builder
pub const UpdateBuilder = struct {
    allocator: std.mem.Allocator,
    table: []const u8,
    sets: std.ArrayListUnmanaged(SetClause),
    where_conditions: std.ArrayListUnmanaged(Condition),

    const SetClause = struct {
        column: []const u8,
        value: Value,
    };

    pub fn init(allocator: std.mem.Allocator, table: anytype) UpdateBuilder {
        return .{
            .allocator = allocator,
            .table = table._table_name,
            .sets = .{},
            .where_conditions = .{},
        };
    }

    pub fn deinit(self: *UpdateBuilder) void {
        self.sets.deinit(self.allocator);
        self.where_conditions.deinit(self.allocator);
    }

    pub fn set(self: *UpdateBuilder, field: anytype, value: anytype) *UpdateBuilder {
        const field_ref = field.toFieldRef();
        self.sets.append(self.allocator, .{
            .column = field_ref.column,
            .value = Value.from(value),
        }) catch unreachable;
        return self;
    }

    pub fn where(self: *UpdateBuilder, conditions: anytype) *UpdateBuilder {
        const conds_info = @typeInfo(@TypeOf(conditions));
        switch (conds_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    // Multiple conditions (tuple)
                    inline for (conditions) |cond| {
                        self.where_conditions.append(self.allocator, cond) catch unreachable;
                    }
                } else {
                    // Single condition
                    self.where_conditions.append(self.allocator, conditions) catch unreachable;
                }
            },
            else => {
                // Fallback for non-struct types
                self.where_conditions.append(self.allocator, conditions) catch unreachable;
            },
        }
        return self;
    }

    pub fn toSql(self: *UpdateBuilder) ![]u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        const writer = buffer.writer(self.allocator);

        try writer.print("UPDATE {s} SET ", .{self.table});

        // SET clauses
        for (self.sets.items, 0..) |s, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s} = ", .{s.column});
            try s.value.toSql(writer);
        }

        // WHERE clauses
        if (self.where_conditions.items.len > 0) {
            try writer.writeAll(" WHERE ");
            for (self.where_conditions.items, 0..) |cond, i| {
                if (i > 0) try writer.writeAll(" AND ");
                try writer.print("{s}.{s} {s} ", .{
                    cond.field.table,
                    cond.field.column,
                    cond.op.toSql(),
                });
                try cond.value.toSql(writer);
            }
        }

        return buffer.toOwnedSlice(self.allocator);
    }
};

// DELETE Builder
pub const DeleteBuilder = struct {
    allocator: std.mem.Allocator,
    table: []const u8,
    where_conditions: std.ArrayListUnmanaged(Condition),

    pub fn init(allocator: std.mem.Allocator, table: anytype) DeleteBuilder {
        return .{
            .allocator = allocator,
            .table = table._table_name,
            .where_conditions = .{},
        };
    }

    pub fn deinit(self: *DeleteBuilder) void {
        self.where_conditions.deinit(self.allocator);
    }

    pub fn where(self: *DeleteBuilder, conditions: anytype) *DeleteBuilder {
        const conds_info = @typeInfo(@TypeOf(conditions));
        switch (conds_info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    // Multiple conditions (tuple)
                    inline for (conditions) |cond| {
                        self.where_conditions.append(self.allocator, cond) catch unreachable;
                    }
                } else {
                    // Single condition
                    self.where_conditions.append(self.allocator, conditions) catch unreachable;
                }
            },
            else => {
                // Fallback for non-struct types
                self.where_conditions.append(self.allocator, conditions) catch unreachable;
            },
        }
        return self;
    }

    pub fn toSql(self: *DeleteBuilder) ![]u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        const writer = buffer.writer(self.allocator);

        try writer.print("DELETE FROM {s}", .{self.table});

        // WHERE clauses (important for safety!)
        if (self.where_conditions.items.len > 0) {
            try writer.writeAll(" WHERE ");
            for (self.where_conditions.items, 0..) |cond, i| {
                if (i > 0) try writer.writeAll(" AND ");
                try writer.print("{s}.{s} {s} ", .{
                    cond.field.table,
                    cond.field.column,
                    cond.op.toSql(),
                });
                try cond.value.toSql(writer);
            }
        }
        // WARNING: No WHERE clause means DELETE ALL!

        return buffer.toOwnedSlice(self.allocator);
    }
};

// Shared types (simplified versions for testing)
pub const FieldRef = struct {
    table: []const u8,
    column: []const u8,
};

pub const Condition = struct {
    field: FieldRef,
    op: Operator,
    value: Value,
};

pub const Operator = enum {
    eq,
    neq,
    gt,
    lt,

    pub fn toSql(self: Operator) []const u8 {
        return switch (self) {
            .eq => "=",
            .neq => "!=",
            .gt => ">",
            .lt => "<",
        };
    }
};

pub const Value = union(enum) {
    null_value: void,
    int: i64,
    float: f64,
    string: []const u8,
    bool_val: bool,

    pub fn from(value: anytype) Value {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        if (type_info == .int or type_info == .comptime_int) {
            return .{ .int = @as(i64, @intCast(value)) };
        } else if (type_info == .float or type_info == .comptime_float) {
            return .{ .float = @as(f64, @floatCast(value)) };
        } else if (type_info == .pointer) {
            // Assume it's a string
            return .{ .string = value };
        } else if (type_info == .bool) {
            return .{ .bool_val = value };
        } else if (type_info == .null) {
            return .null_value;
        } else {
            return .{ .int = 0 }; // Default fallback
        }
    }

    pub fn toSql(self: Value, writer: anytype) !void {
        switch (self) {
            .int => |v| try writer.print("{}", .{v}),
            .float => |v| try writer.print("{}", .{v}),
            .string => |v| try writer.print("'{s}'", .{v}),
            .bool_val => |v| try writer.print("{}", .{@as(i32, if (v) 1 else 0)}),
            .null_value => try writer.writeAll("NULL"),
        }
    }
};

// ===========================================================================
// TESTS
// ===========================================================================

test "INSERT builder" {
    const allocator = std.testing.allocator;

    // Test table and field mocks
    const TestTable = struct {
        pub const _table_name = "users";
    };

    const TestField = struct {
        table: []const u8,
        column: []const u8,

        pub fn toFieldRef(self: @This()) FieldRef {
            return .{ .table = self.table, .column = self.column };
        }
    };

    // Simple INSERT
    {
        var insert = InsertBuilder.init(allocator, TestTable);
        defer insert.deinit();

        const name_field = TestField{ .table = "users", .column = "name" };
        const age_field = TestField{ .table = "users", .column = "age" };
        const email_field = TestField{ .table = "users", .column = "email" };

        _ = insert.value(name_field, "John Doe");
        _ = insert.value(age_field, 30);
        _ = insert.value(email_field, "john@example.com");

        const sql = try insert.toSql();
        defer allocator.free(sql);

        try std.testing.expectEqualStrings("INSERT INTO users (name, age, email) VALUES ('John Doe', 30, 'john@example.com')", sql);
    }

    // INSERT with RETURNING
    {
        var insert = InsertBuilder.init(allocator, TestTable);
        defer insert.deinit();

        const name_field = TestField{ .table = "users", .column = "name" };

        _ = insert.value(name_field, "Jane Doe");
        _ = insert.returning("id");

        const sql = try insert.toSql();
        defer allocator.free(sql);

        try std.testing.expectEqualStrings("INSERT INTO users (name) VALUES ('Jane Doe') RETURNING id", sql);
    }

    std.debug.print("\n✓ INSERT builder tests passed!\n", .{});
}

test "UPDATE builder" {
    const allocator = std.testing.allocator;

    const TestTable = struct {
        pub const _table_name = "users";
    };

    const TestField = struct {
        table: []const u8,
        column: []const u8,

        pub fn toFieldRef(self: @This()) FieldRef {
            return .{ .table = self.table, .column = self.column };
        }

        pub fn eq(self: @This(), value: anytype) Condition {
            return .{
                .field = self.toFieldRef(),
                .op = .eq,
                .value = Value.from(value),
            };
        }
    };

    // UPDATE with WHERE
    {
        var update = UpdateBuilder.init(allocator, TestTable);
        defer update.deinit();

        const name_field = TestField{ .table = "users", .column = "name" };
        const age_field = TestField{ .table = "users", .column = "age" };
        const id_field = TestField{ .table = "users", .column = "id" };

        _ = update.set(name_field, "John Updated");
        _ = update.set(age_field, 31);
        _ = update.where(id_field.eq(1));

        const sql = try update.toSql();
        defer allocator.free(sql);

        try std.testing.expectEqualStrings("UPDATE users SET name = 'John Updated', age = 31 WHERE users.id = 1", sql);
    }

    // UPDATE with multiple WHERE conditions (tuple syntax)
    {
        var update = UpdateBuilder.init(allocator, TestTable);
        defer update.deinit();

        const name_field = TestField{ .table = "users", .column = "name" };
        const status_field = TestField{ .table = "users", .column = "status" };
        const id_field = TestField{ .table = "users", .column = "id" };

        _ = update.set(name_field, "Jane Updated");
        _ = update.where(.{
            id_field.eq(1),
            status_field.eq("active"),
        });

        const sql = try update.toSql();
        defer allocator.free(sql);

        try std.testing.expectEqualStrings("UPDATE users SET name = 'Jane Updated' WHERE users.id = 1 AND users.status = 'active'", sql);
    }

    std.debug.print("✓ UPDATE builder tests passed!\n", .{});
}

test "DELETE builder" {
    const allocator = std.testing.allocator;

    const TestTable = struct {
        pub const _table_name = "posts";
    };

    const TestField = struct {
        table: []const u8,
        column: []const u8,

        pub fn toFieldRef(self: @This()) FieldRef {
            return .{ .table = self.table, .column = self.column };
        }

        pub fn gt(self: @This(), value: anytype) Condition {
            return .{
                .field = self.toFieldRef(),
                .op = .gt,
                .value = Value.from(value),
            };
        }
    };

    // DELETE with WHERE
    {
        var delete = DeleteBuilder.init(allocator, TestTable);
        defer delete.deinit();

        const created_field = TestField{ .table = "posts", .column = "created_at" };

        _ = delete.where(created_field.gt(30));

        const sql = try delete.toSql();
        defer allocator.free(sql);

        try std.testing.expectEqualStrings("DELETE FROM posts WHERE posts.created_at > 30", sql);
    }

    // DELETE without WHERE (dangerous!)
    {
        var delete = DeleteBuilder.init(allocator, TestTable);
        defer delete.deinit();

        const sql = try delete.toSql();
        defer allocator.free(sql);

        try std.testing.expectEqualStrings("DELETE FROM posts", sql);
    }

    // DELETE with multiple WHERE conditions (tuple syntax)
    {
        var delete = DeleteBuilder.init(allocator, TestTable);
        defer delete.deinit();

        const TestField2 = struct {
            table: []const u8,
            column: []const u8,

            pub fn toFieldRef(self: @This()) FieldRef {
                return .{ .table = self.table, .column = self.column };
            }

            pub fn gt(self: @This(), value: anytype) Condition {
                return .{
                    .field = self.toFieldRef(),
                    .op = .gt,
                    .value = Value.from(value),
                };
            }

            pub fn lt(self: @This(), value: anytype) Condition {
                return .{
                    .field = self.toFieldRef(),
                    .op = .lt,
                    .value = Value.from(value),
                };
            }
        };

        const created_field = TestField2{ .table = "posts", .column = "created_at" };
        const views_field = TestField2{ .table = "posts", .column = "views" };

        _ = delete.where(.{
            created_field.gt(30),
            views_field.lt(100),
        });

        const sql = try delete.toSql();
        defer allocator.free(sql);

        try std.testing.expectEqualStrings("DELETE FROM posts WHERE posts.created_at > 30 AND posts.views < 100", sql);
    }

    std.debug.print("✓ DELETE builder tests passed!\n", .{});
}
