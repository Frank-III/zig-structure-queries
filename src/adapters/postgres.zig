const std = @import("std");

/// PostgreSQL database adapter
pub const PostgresAdapter = struct {
    pub fn quoteIdentifier(name: []const u8) []const u8 {
        // PostgreSQL uses double quotes for identifiers
        return std.fmt.comptimePrint("\"{s}\"", .{name});
    }

    pub fn parameterPlaceholder(index: usize) []const u8 {
        // PostgreSQL uses $1, $2, etc. for parameters
        return std.fmt.comptimePrint("${}", .{index + 1});
    }

    pub const dialect = "postgresql";
};
