const std = @import("std");

/// SQLite database adapter
pub const SqliteAdapter = struct {
    pub fn quoteIdentifier(name: []const u8) []const u8 {
        // SQLite uses double quotes for identifiers
        return std.fmt.comptimePrint("\"{s}\"", .{name});
    }

    pub fn parameterPlaceholder(index: usize) []const u8 {
        _ = index;
        // SQLite uses ? for parameters
        return "?";
    }

    pub const dialect = "sqlite";
};
