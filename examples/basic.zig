const std = @import("std");
const zsq = @import("zsq");

// Define your schema
const Reminder = struct {
    id: i32,
    title: []const u8,
    is_completed: bool,
    priority: ?i32,
};

// Configure the table
const ReminderTable = zsq.Table(Reminder, .{
    .name = "reminders",
    .primary_key = "id",
});

pub fn main() !void {
    const print = std.debug.print;

    // Create a query
    const query = zsq.Query(ReminderTable)
        .where(.{
            .is_completed = false,
            .priority = .{ .gt = 2 },
        })
        .limit(10);

    // Print query info (in real use, this would generate SQL)
    print("Query created with:\n", .{});
    print("  - WHERE conditions: {} conditions\n", .{query.where_conditions.len});
    print("  - LIMIT: {?}\n", .{query.limit_value});

    // Demonstrate compile-time validation
    // This would cause a compile error:
    // const bad_query = zsq.Query(ReminderTable).where(.{ .nonexistent_field = 5 });

    print("\nCompile-time validation successful!\n", .{});
}
