const std = @import("std");
const zsq = @import("zsq");

// Define schemas
const User = struct {
    id: i32,
    name: []const u8,
    email: []const u8,
};

const Post = struct {
    id: i32,
    user_id: i32,
    title: []const u8,
    content: []const u8,
};

const UserTable = zsq.Table(User, .{ .name = "users" });
const PostTable = zsq.Table(Post, .{ .name = "posts" });

pub fn main() !void {
    const print = std.debug.print;

    print("JOIN example - demonstrates type-safe joins\n\n", .{});

    // This would be the query API (not fully implemented yet)
    // const query = zsq.Query(UserTable)
    //     .join(PostTable, .{ .id = .user_id })
    //     .where(.{ .post.title = .{ .like = "%Zig%" } })
    //     .select(.{
    //         .user_name = .user.name,
    //         .post_title = .post.title,
    //     });

    print("Join queries will allow:\n", .{});
    print("  - Type-safe join conditions\n", .{});
    print("  - Compile-time validation of foreign keys\n", .{});
    print("  - Automatic result type generation\n", .{});
}
