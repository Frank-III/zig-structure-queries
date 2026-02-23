const std = @import("std");

/// Simple, working SQL query builder for SQLite
/// This version focuses on generating correct SQL strings
pub const QueryBuilder = struct {
    allocator: std.mem.Allocator,

    // Store table information
    from_table: []const u8,
    from_alias: []const u8,

    // Store joins
    joins: std.ArrayListUnmanaged(Join),

    // Store conditions
    where_conditions: std.ArrayListUnmanaged(WhereCondition),

    // Store selected fields
    select_fields: std.ArrayListUnmanaged(SelectField),

    // Limit and offset
    limit_value: ?usize,
    offset_value: ?usize,

    const Join = struct {
        join_type: []const u8, // "INNER JOIN", "LEFT JOIN", etc
        table: []const u8,
        alias: []const u8,
        on_condition: []const u8, // The full ON clause
    };

    const WhereCondition = struct {
        condition: []const u8, // Full condition like "u.id = 1"
    };

    const SelectField = struct {
        expression: []const u8, // Like "u.name" or "COUNT(*)"
        alias: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator) QueryBuilder {
        return .{
            .allocator = allocator,
            .from_table = "",
            .from_alias = "",
            .joins = .{},
            .where_conditions = .{},
            .select_fields = .{},
            .limit_value = null,
            .offset_value = null,
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        self.joins.deinit(self.allocator);
        self.where_conditions.deinit(self.allocator);
        self.select_fields.deinit(self.allocator);
    }

    pub fn from(self: *QueryBuilder, table: []const u8, alias: []const u8) *QueryBuilder {
        self.from_table = table;
        self.from_alias = alias;
        return self;
    }

    pub fn join(self: *QueryBuilder, join_type: []const u8, table: []const u8, alias: []const u8, on: []const u8) !*QueryBuilder {
        try self.joins.append(self.allocator, .{
            .join_type = join_type,
            .table = table,
            .alias = alias,
            .on_condition = on,
        });
        return self;
    }

    pub fn where(self: *QueryBuilder, condition: []const u8) !*QueryBuilder {
        try self.where_conditions.append(self.allocator, .{
            .condition = condition,
        });
        return self;
    }

    pub fn select(self: *QueryBuilder, expression: []const u8, alias: ?[]const u8) !*QueryBuilder {
        try self.select_fields.append(self.allocator, .{
            .expression = expression,
            .alias = alias,
        });
        return self;
    }

    pub fn limit(self: *QueryBuilder, value: usize) *QueryBuilder {
        self.limit_value = value;
        return self;
    }

    pub fn offset(self: *QueryBuilder, value: usize) *QueryBuilder {
        self.offset_value = value;
        return self;
    }

    pub fn toSql(self: *QueryBuilder) ![]u8 {
        var sql = std.ArrayList(u8).empty;
        errdefer sql.deinit(self.allocator);

        // SELECT clause
        try sql.appendSlice(self.allocator, "SELECT ");
        if (self.select_fields.items.len == 0) {
            try sql.appendSlice(self.allocator, "*");
        } else {
            for (self.select_fields.items, 0..) |field, i| {
                if (i > 0) try sql.appendSlice(self.allocator, ", ");
                try sql.appendSlice(self.allocator, field.expression);
                if (field.alias) |a| {
                    try sql.appendSlice(self.allocator, " AS ");
                    try sql.appendSlice(self.allocator, a);
                }
            }
        }

        // FROM clause
        if (self.from_table.len > 0) {
            try sql.appendSlice(self.allocator, "\nFROM ");
            try sql.appendSlice(self.allocator, self.from_table);
            if (self.from_alias.len > 0) {
                try sql.appendSlice(self.allocator, " ");
                try sql.appendSlice(self.allocator, self.from_alias);
            }
        }

        // JOIN clauses
        for (self.joins.items) |j| {
            try sql.appendSlice(self.allocator, "\n");
            try sql.appendSlice(self.allocator, j.join_type);
            try sql.appendSlice(self.allocator, " ");
            try sql.appendSlice(self.allocator, j.table);
            try sql.appendSlice(self.allocator, " ");
            try sql.appendSlice(self.allocator, j.alias);
            try sql.appendSlice(self.allocator, " ON ");
            try sql.appendSlice(self.allocator, j.on_condition);
        }

        // WHERE clause
        if (self.where_conditions.items.len > 0) {
            try sql.appendSlice(self.allocator, "\nWHERE ");
            for (self.where_conditions.items, 0..) |condition, i| {
                if (i > 0) try sql.appendSlice(self.allocator, " AND ");
                try sql.appendSlice(self.allocator, condition.condition);
            }
        }

        // LIMIT and OFFSET
        if (self.limit_value) |lim| {
            const limit_str = try std.fmt.allocPrint(self.allocator, "\nLIMIT {}", .{lim});
            defer self.allocator.free(limit_str);
            try sql.appendSlice(self.allocator, limit_str);
        }

        if (self.offset_value) |off| {
            const offset_str = try std.fmt.allocPrint(self.allocator, "\nOFFSET {}", .{off});
            defer self.allocator.free(offset_str);
            try sql.appendSlice(self.allocator, offset_str);
        }

        return sql.toOwnedSlice(self.allocator);
    }
};

test "simple query generation" {
    var query = QueryBuilder.init(std.testing.allocator);
    defer query.deinit();

    _ = query.from("users", "u");
    _ = try query.select("u.id", null);
    _ = try query.select("u.name", "user_name");
    _ = try query.where("u.active = 1");
    _ = query.limit(10);

    const sql = try query.toSql();
    defer std.testing.allocator.free(sql);

    std.debug.print("\n=== Simple Query ===\n{s}\n\n", .{sql});

    // Check that SQL contains expected parts
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT u.id, u.name AS user_name") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM users u") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE u.active = 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 10") != null);
}

test "join query generation" {
    var query = QueryBuilder.init(std.testing.allocator);
    defer query.deinit();

    _ = query.from("users", "u");
    _ = try query.join("LEFT JOIN", "posts", "p", "u.id = p.user_id");
    _ = try query.join("LEFT JOIN", "comments", "c", "p.id = c.post_id");
    _ = try query.select("u.name", null);
    _ = try query.select("COUNT(DISTINCT p.id)", "post_count");
    _ = try query.select("COUNT(c.id)", "comment_count");
    _ = try query.where("u.created_at > '2024-01-01'");
    _ = try query.where("p.published = 1");

    const sql = try query.toSql();
    defer std.testing.allocator.free(sql);

    std.debug.print("=== Join Query ===\n{s}\n\n", .{sql});

    // Check that SQL contains expected parts
    try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN posts p ON u.id = p.user_id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "LEFT JOIN comments c ON p.id = c.post_id") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "COUNT(DISTINCT p.id) AS post_count") != null);
}

test "complex query with everything" {
    var query = QueryBuilder.init(std.testing.allocator);
    defer query.deinit();

    _ = query.from("orders", "o");
    _ = try query.join("INNER JOIN", "customers", "c", "o.customer_id = c.id");
    _ = try query.join("LEFT JOIN", "order_items", "oi", "o.id = oi.order_id");
    _ = try query.join("LEFT JOIN", "products", "p", "oi.product_id = p.id");

    _ = try query.select("c.name", "customer_name");
    _ = try query.select("o.order_date", null);
    _ = try query.select("SUM(oi.quantity * oi.price)", "total_amount");
    _ = try query.select("COUNT(DISTINCT p.category)", "category_count");

    _ = try query.where("o.status = 'completed'");
    _ = try query.where("o.order_date >= '2024-01-01'");
    _ = try query.where("c.country = 'USA'");

    _ = query.limit(100).offset(50);

    const sql = try query.toSql();
    defer std.testing.allocator.free(sql);

    std.debug.print("=== Complex Query ===\n{s}\n\n", .{sql});

    // Verify the structure
    try std.testing.expect(std.mem.indexOf(u8, sql, "SELECT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "FROM orders o") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "INNER JOIN customers c") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "WHERE") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "LIMIT 100") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "OFFSET 50") != null);
}
