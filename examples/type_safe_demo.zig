const std = @import("std");
const zsq = @import("../src/zsq.zig");

const DB = zsq.schema(.{
    .users = zsq.table("users", .{
        .id = zsq.col(i32),
        .name = zsq.col([]const u8),
        .age = zsq.col(i32),
    }),
    .posts = zsq.table("posts", .{
        .id = zsq.col(i32),
        .user_id = zsq.col(i32),
        .title = zsq.col([]const u8),
    }),
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build query with comptime result inference.
    var q = zsq.query(DB.users, allocator)
        .join(DB.posts, DB.posts.user_id.eqField(DB.users.id))
        .select(.{ .user_name = DB.users.name, .post_title = DB.posts.title });
    defer q.deinit();

    try q.where(DB.users.age, .gt, 25);
    try q.whereCondition(DB.posts.title.like("%Zig%"));

    const sql = try q.toSql();
    defer allocator.free(sql);
 
    std.debug.print("Generated SQL:\n{s}\n", .{sql});

    const Res = @TypeOf(q).ResultType;
    std.debug.print("\nResult Type Fields:\n", .{});
    inline for (@typeInfo(Res).@"struct".fields) |f| {
        std.debug.print("- {s}: {s}\n", .{f.name, @typeName(f.type)});
    }

    const bindings = try q.flattenedValues();
    defer allocator.free(bindings);

    std.debug.print("\nBindings:\n", .{});
    for (bindings) |b| {
        switch (b) {
            .int => |v| std.debug.print("- {d}\n", .{v}),
            .string => |v| std.debug.print("- \"{s}\"\n", .{v}),
            else => std.debug.print("- (other)\n", .{}),
        }
    }
}
