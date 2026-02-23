const std = @import("std");
const zsq = @import("zsq");

// Complex schema with relationships
const Organization = struct {
    id: i32,
    name: []const u8,
    created_at: i64,
};

const Team = struct {
    id: i32,
    org_id: i32,
    name: []const u8,
    description: ?[]const u8,
};

const Member = struct {
    id: i32,
    team_id: i32,
    user_id: i32,
    role: []const u8,
    joined_at: i64,
};

pub fn main() !void {
    const print = std.debug.print;

    print("Advanced ZSQ Features\n", .{});
    print("=====================\n\n", .{});

    print("1. Subqueries and CTEs\n", .{});
    print("   - WITH clauses for complex queries\n", .{});
    print("   - Recursive CTEs for hierarchical data\n\n", .{});

    print("2. Window Functions\n", .{});
    print("   - ROW_NUMBER, RANK, DENSE_RANK\n", .{});
    print("   - Partitioning and ordering\n\n", .{});

    print("3. JSON Operations\n", .{});
    print("   - JSON path queries\n", .{});
    print("   - JSON aggregation\n\n", .{});

    print("4. Compile-Time Optimizations\n", .{});
    print("   - Query plan analysis at compile time\n", .{});
    print("   - Automatic index usage hints\n", .{});
    print("   - Dead code elimination for unused columns\n\n", .{});

    print("All with zero runtime overhead!\n", .{});
}
