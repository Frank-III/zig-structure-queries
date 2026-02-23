const std = @import("std");

// ===========================================================================
// AGGREGATE FUNCTIONS
// ===========================================================================

pub const AggregateType = enum {
    count,
    sum,
    avg,
    max,
    min,
    count_distinct,

    pub fn toSql(self: AggregateType) []const u8 {
        return switch (self) {
            .count => "COUNT",
            .sum => "SUM",
            .avg => "AVG",
            .max => "MAX",
            .min => "MIN",
            .count_distinct => "COUNT(DISTINCT",
        };
    }
};

pub const AggregateField = struct {
    func: AggregateType,
    field: ?FieldRef, // null for COUNT(*)
    alias: []const u8,

    pub fn toSql(self: AggregateField, writer: anytype) !void {
        if (self.func == .count_distinct) {
            try writer.writeAll("COUNT(DISTINCT ");
            if (self.field) |f| {
                try writer.print("{s}.{s}", .{ f.table, f.column });
            }
            try writer.writeAll(")");
        } else {
            try writer.writeAll(self.func.toSql());
            try writer.writeAll("(");

            if (self.field) |f| {
                try writer.print("{s}.{s}", .{ f.table, f.column });
            } else {
                // COUNT(*)
                try writer.writeAll("*");
            }
            try writer.writeAll(")");
        }

        if (self.alias.len > 0) {
            try writer.print(" AS {s}", .{self.alias});
        }
    }
};

pub const FieldRef = struct {
    table: []const u8,
    column: []const u8,
};

// ===========================================================================
// AGGREGATE BUILDERS
// ===========================================================================

pub fn count(field: anytype) AggregateBuilder {
    if (@TypeOf(field) == @TypeOf(null)) {
        return AggregateBuilder{
            .aggregate = AggregateField{
                .func = .count,
                .field = null,
                .alias = "",
            },
        };
    } else {
        return AggregateBuilder{
            .aggregate = AggregateField{
                .func = .count,
                .field = field.toFieldRef(),
                .alias = "",
            },
        };
    }
}

pub fn countDistinct(field: anytype) AggregateBuilder {
    return AggregateBuilder{
        .aggregate = AggregateField{
            .func = .count_distinct,
            .field = field.toFieldRef(),
            .alias = "",
        },
    };
}

pub fn sum(field: anytype) AggregateBuilder {
    return AggregateBuilder{
        .aggregate = AggregateField{
            .func = .sum,
            .field = field.toFieldRef(),
            .alias = "",
        },
    };
}

pub fn avg(field: anytype) AggregateBuilder {
    return AggregateBuilder{
        .aggregate = AggregateField{
            .func = .avg,
            .field = field.toFieldRef(),
            .alias = "",
        },
    };
}

pub fn max(field: anytype) AggregateBuilder {
    return AggregateBuilder{
        .aggregate = AggregateField{
            .func = .max,
            .field = field.toFieldRef(),
            .alias = "",
        },
    };
}

pub fn min(field: anytype) AggregateBuilder {
    return AggregateBuilder{
        .aggregate = AggregateField{
            .func = .min,
            .field = field.toFieldRef(),
            .alias = "",
        },
    };
}

pub const AggregateBuilder = struct {
    aggregate: AggregateField,

    pub fn as(self: AggregateBuilder, alias: []const u8) AggregateField {
        var result = self.aggregate;
        result.alias = alias;
        return result;
    }

    // For conditions in HAVING clause
    pub fn gt(self: AggregateBuilder, value: anytype) AggregateCondition {
        return AggregateCondition{
            .aggregate = self.aggregate,
            .op = .gt,
            .value = @intCast(value),
        };
    }

    pub fn gte(self: AggregateBuilder, value: anytype) AggregateCondition {
        return AggregateCondition{
            .aggregate = self.aggregate,
            .op = .gte,
            .value = @intCast(value),
        };
    }

    pub fn lt(self: AggregateBuilder, value: anytype) AggregateCondition {
        return AggregateCondition{
            .aggregate = self.aggregate,
            .op = .lt,
            .value = @intCast(value),
        };
    }

    pub fn lte(self: AggregateBuilder, value: anytype) AggregateCondition {
        return AggregateCondition{
            .aggregate = self.aggregate,
            .op = .lte,
            .value = @intCast(value),
        };
    }

    pub fn eq(self: AggregateBuilder, value: anytype) AggregateCondition {
        return AggregateCondition{
            .aggregate = self.aggregate,
            .op = .eq,
            .value = @intCast(value),
        };
    }
};

pub const AggregateCondition = struct {
    aggregate: AggregateField,
    op: ComparisonOp,
    value: i64,

    pub const ComparisonOp = enum {
        eq,
        neq,
        gt,
        gte,
        lt,
        lte,

        pub fn toSql(self: ComparisonOp) []const u8 {
            return switch (self) {
                .eq => "=",
                .neq => "!=",
                .gt => ">",
                .gte => ">=",
                .lt => "<",
                .lte => "<=",
            };
        }
    };

    pub fn toSql(self: AggregateCondition, writer: anytype) !void {
        try self.aggregate.toSql(writer);
        try writer.print(" {s} {}", .{ self.op.toSql(), self.value });
    }
};

// ===========================================================================
// TESTS
// ===========================================================================

test "aggregate functions" {
    const allocator = std.testing.allocator;

    // Test COUNT(*)
    {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        const agg = count(null).as("total_count");
        try agg.toSql(writer);

        const result = buffer.items;
        try std.testing.expectEqualStrings("COUNT(*) AS total_count", result);
    }

    // Test COUNT(field)
    {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        const TestField = struct {
            pub fn toFieldRef(_: @This()) FieldRef {
                return .{ .table = "users", .column = "id" };
            }
        };

        const field = TestField{};
        const agg = count(field).as("user_count");
        try agg.toSql(writer);

        const result = buffer.items;
        try std.testing.expectEqualStrings("COUNT(users.id) AS user_count", result);
    }

    // Test SUM
    {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        const TestField = struct {
            pub fn toFieldRef(_: @This()) FieldRef {
                return .{ .table = "orders", .column = "amount" };
            }
        };

        const field = TestField{};
        const agg = sum(field).as("total_amount");
        try agg.toSql(writer);

        const result = buffer.items;
        try std.testing.expectEqualStrings("SUM(orders.amount) AS total_amount", result);
    }

    // Test AVG
    {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        const TestField = struct {
            pub fn toFieldRef(_: @This()) FieldRef {
                return .{ .table = "products", .column = "price" };
            }
        };

        const field = TestField{};
        const agg = avg(field).as("avg_price");
        try agg.toSql(writer);

        const result = buffer.items;
        try std.testing.expectEqualStrings("AVG(products.price) AS avg_price", result);
    }

    // Test COUNT(DISTINCT field)
    {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        const TestField = struct {
            pub fn toFieldRef(_: @This()) FieldRef {
                return .{ .table = "orders", .column = "customer_id" };
            }
        };

        const field = TestField{};
        const agg = countDistinct(field).as("unique_customers");
        try agg.toSql(writer);

        const result = buffer.items;
        try std.testing.expectEqualStrings("COUNT(DISTINCT orders.customer_id) AS unique_customers", result);
    }

    // Test aggregate conditions for HAVING
    {
        var buffer: std.ArrayListUnmanaged(u8) = .{};
        defer buffer.deinit(allocator);
        const writer = buffer.writer(allocator);

        const TestField = struct {
            pub fn toFieldRef(_: @This()) FieldRef {
                return .{ .table = "posts", .column = "id" };
            }
        };

        const field = TestField{};
        const condition = count(field).gt(5);
        try condition.toSql(writer);

        const result = buffer.items;
        try std.testing.expectEqualStrings("COUNT(posts.id) > 5", result);
    }

    std.debug.print("\n✓ All aggregate function tests passed!\n", .{});
}
