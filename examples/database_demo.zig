const std = @import("std");
const zsq = @import("zsq");
const sqlite = @import("sqlite");

const Customer = struct {
    id: i32,
    name: []const u8,
    email: []const u8,
};

const Order = struct {
    id: i32,
    customer_id: i32,
    order_date: []const u8,
    total_amount: f64,
    status: []const u8,
};

const OrderItem = struct {
    id: i32,
    order_id: i32,
    product_name: []const u8,
    quantity: i32,
    price: f64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create in-memory database
    var db = try zsq.Database.init(allocator, ":memory:");
    defer db.deinit();

    // Create tables
    try createTables(&db);

    // Insert sample data
    try insertSampleData(&db);

    // Example 1: Simple query using our query builder
    std.debug.print("\n=== Example 1: Recent Orders ===\n", .{});
    try queryRecentOrders(&db, allocator);

    // Example 2: Join query with aggregation
    std.debug.print("\n=== Example 2: Customer Order Summary ===\n", .{});
    try queryCustomerOrderSummary(&db, allocator);

    // Example 3: Complex join with WHERE clause
    std.debug.print("\n=== Example 3: Completed Order Details ===\n", .{});
    try queryCompletedOrderDetails(&db, allocator);
}

fn createTables(db: *zsq.Database) !void {
    try db.execute(
        \\CREATE TABLE customers (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL,
        \\  email TEXT UNIQUE NOT NULL
        \\)
    );

    try db.execute(
        \\CREATE TABLE orders (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  customer_id INTEGER NOT NULL,
        \\  order_date TEXT NOT NULL,
        \\  total_amount REAL NOT NULL,
        \\  status TEXT NOT NULL,
        \\  FOREIGN KEY (customer_id) REFERENCES customers(id)
        \\)
    );

    try db.execute(
        \\CREATE TABLE order_items (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  order_id INTEGER NOT NULL,
        \\  product_name TEXT NOT NULL,
        \\  quantity INTEGER NOT NULL,
        \\  price REAL NOT NULL,
        \\  FOREIGN KEY (order_id) REFERENCES orders(id)
        \\)
    );
}

fn insertSampleData(db: *zsq.Database) !void {
    // Insert customers
    try db.execute("INSERT INTO customers (name, email) VALUES ('Alice Johnson', 'alice@example.com')");
    try db.execute("INSERT INTO customers (name, email) VALUES ('Bob Smith', 'bob@example.com')");
    try db.execute("INSERT INTO customers (name, email) VALUES ('Charlie Brown', 'charlie@example.com')");

    // Insert orders
    try db.execute("INSERT INTO orders (customer_id, order_date, total_amount, status) VALUES (1, '2024-01-15', 150.00, 'completed')");
    try db.execute("INSERT INTO orders (customer_id, order_date, total_amount, status) VALUES (2, '2024-01-16', 89.99, 'completed')");
    try db.execute("INSERT INTO orders (customer_id, order_date, total_amount, status) VALUES (1, '2024-01-17', 220.50, 'processing')");
    try db.execute("INSERT INTO orders (customer_id, order_date, total_amount, status) VALUES (3, '2024-01-18', 45.00, 'completed')");

    // Insert order items
    try db.execute("INSERT INTO order_items (order_id, product_name, quantity, price) VALUES (1, 'Laptop Stand', 1, 50.00)");
    try db.execute("INSERT INTO order_items (order_id, product_name, quantity, price) VALUES (1, 'USB Cable', 2, 25.00)");
    try db.execute("INSERT INTO order_items (order_id, product_name, quantity, price) VALUES (1, 'Mouse Pad', 3, 25.00)");
    try db.execute("INSERT INTO order_items (order_id, product_name, quantity, price) VALUES (2, 'Keyboard', 1, 89.99)");
    try db.execute("INSERT INTO order_items (order_id, product_name, quantity, price) VALUES (3, 'Monitor', 1, 220.50)");
    try db.execute("INSERT INTO order_items (order_id, product_name, quantity, price) VALUES (4, 'HDMI Cable', 3, 15.00)");
}

fn queryRecentOrders(db: *zsq.Database, allocator: std.mem.Allocator) !void {
    var query = zsq.Query.init();
    query.addSelect(.{ .expression = "id", .alias = null });
    query.addSelect(.{ .expression = "customer_id", .alias = null });
    query.addSelect(.{ .expression = "order_date", .alias = null });
    query.addSelect(.{ .expression = "total_amount", .alias = null });
    query.addSelect(.{ .expression = "status", .alias = null });
    query.setFrom("orders");
    query.setOrderBy("order_date DESC");
    query.setLimit(5);

    const sql = try query.toSql(allocator);
    defer allocator.free(sql);

    std.debug.print("SQL: {s}\n\n", .{sql});

    const stmt = try db.prepare(sql);
    defer stmt.deinit();

    const results = try stmt.all(Order, .{});
    defer allocator.free(results);

    for (results) |order| {
        std.debug.print("Order #{}: Customer {}, Date: {s}, Amount: ${d:.2}, Status: {s}\n", .{
            order.id,
            order.customer_id,
            order.order_date,
            order.total_amount,
            order.status,
        });
    }
}

fn queryCustomerOrderSummary(db: *zsq.Database, allocator: std.mem.Allocator) !void {
    var query = zsq.Query.init();
    query.addSelect(.{ .expression = "c.name", .alias = "customer_name" });
    query.addSelect(.{ .expression = "COUNT(o.id)", .alias = "order_count" });
    query.addSelect(.{ .expression = "SUM(o.total_amount)", .alias = "total_spent" });
    query.setFrom("customers c");
    query.addJoin(.{
        .join_type = .left,
        .table = "orders o",
        .condition = "c.id = o.customer_id",
    });
    query.setGroupBy("c.id, c.name");
    query.setOrderBy("total_spent DESC");

    const sql = try query.toSql(allocator);
    defer allocator.free(sql);

    std.debug.print("SQL: {s}\n\n", .{sql});

    const stmt = try db.prepare(sql);
    defer stmt.deinit();

    const CustomerSummary = struct {
        customer_name: []const u8,
        order_count: i32,
        total_spent: ?f64,
    };

    const results = try stmt.all(CustomerSummary, .{});
    defer allocator.free(results);

    for (results) |summary| {
        const total = summary.total_spent orelse 0.0;
        std.debug.print("Customer: {s}, Orders: {}, Total Spent: ${d:.2}\n", .{
            summary.customer_name,
            summary.order_count,
            total,
        });
    }
}

fn queryCompletedOrderDetails(db: *zsq.Database, allocator: std.mem.Allocator) !void {
    var query = zsq.Query.init();
    query.addSelect(.{ .expression = "c.name", .alias = "customer" });
    query.addSelect(.{ .expression = "o.order_date", .alias = "date" });
    query.addSelect(.{ .expression = "oi.product_name", .alias = "product" });
    query.addSelect(.{ .expression = "oi.quantity", .alias = "qty" });
    query.addSelect(.{ .expression = "oi.price", .alias = "price" });
    query.addSelect(.{ .expression = "(oi.quantity * oi.price)", .alias = "subtotal" });
    query.setFrom("orders o");
    query.addJoin(.{
        .join_type = .inner,
        .table = "customers c",
        .condition = "o.customer_id = c.id",
    });
    query.addJoin(.{
        .join_type = .inner,
        .table = "order_items oi",
        .condition = "o.id = oi.order_id",
    });
    query.addWhere("o.status = 'completed'");
    query.setOrderBy("o.order_date, c.name");

    const sql = try query.toSql(allocator);
    defer allocator.free(sql);

    std.debug.print("SQL: {s}\n\n", .{sql});

    const stmt = try db.prepare(sql);
    defer stmt.deinit();

    const OrderDetail = struct {
        customer: []const u8,
        date: []const u8,
        product: []const u8,
        qty: i32,
        price: f64,
        subtotal: f64,
    };

    const results = try stmt.all(OrderDetail, .{});
    defer allocator.free(results);

    for (results) |detail| {
        std.debug.print("{s} | {s} | {s} | Qty: {} | ${d:.2} | Subtotal: ${d:.2}\n", .{
            detail.customer,
            detail.date,
            detail.product,
            detail.qty,
            detail.price,
            detail.subtotal,
        });
    }
}
