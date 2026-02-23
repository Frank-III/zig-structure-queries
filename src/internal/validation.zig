const std = @import("std");

/// Validates WHERE conditions at compile time
pub fn validateWhereConditions(comptime TableType: type, comptime conditions: anytype) void {
    comptime {
        const T = @TypeOf(conditions);
        if (@typeInfo(T) != .@"struct") {
            @compileError("WHERE conditions must be a struct");
        }

        const fields = std.meta.fields(T);
        for (fields) |field| {
            // Check if field exists in table
            if (!@hasField(TableType.Definition, field.name)) {
                @compileError("Field '" ++ field.name ++ "' does not exist in table '" ++ TableType.name ++ "'");
            }

            // Validate type compatibility
            const table_field_type = @TypeOf(@field(@as(TableType.Definition, undefined), field.name));
            const condition_value = @field(conditions, field.name);
            validateTypeCompatibility(table_field_type, @TypeOf(condition_value), field.name);
        }
    }
}

/// Validates that a value type is compatible with a field type
fn validateTypeCompatibility(comptime FieldType: type, comptime ValueType: type, comptime field_name: []const u8) void {
    comptime {
        // Handle null values for optional fields
        if (ValueType == @TypeOf(null)) {
            if (@typeInfo(FieldType) != .Optional) {
                @compileError("Cannot compare non-optional field '" ++ field_name ++ "' with null");
            }
            return;
        }

        // Handle operator structs like .{ .gt = 5 }
        if (@typeInfo(ValueType) == .@"struct") {
            const fields = std.meta.fields(ValueType);
            if (fields.len == 1) {
                // This is an operator struct, validate the inner value
                const inner_value = @field(@as(ValueType, undefined), fields[0].name);
                const InnerType = @TypeOf(inner_value);

                // Check basic type compatibility
                if (!isCompatibleType(FieldType, InnerType)) {
                    @compileError("Type mismatch for field '" ++ field_name ++ "': expected " ++
                        @typeName(FieldType) ++ ", got " ++ @typeName(InnerType));
                }
                return;
            }
        }

        // Direct value comparison
        if (!isCompatibleType(FieldType, ValueType)) {
            @compileError("Type mismatch for field '" ++ field_name ++ "': expected " ++
                @typeName(FieldType) ++ ", got " ++ @typeName(ValueType));
        }
    }
}

/// Check if two types are compatible for comparison
fn isCompatibleType(comptime FieldType: type, comptime ValueType: type) bool {
    // Handle optionals
    const field_base = if (@typeInfo(FieldType) == .Optional)
        @typeInfo(FieldType).Optional.child
    else
        FieldType;

    const value_base = if (@typeInfo(ValueType) == .Optional)
        @typeInfo(ValueType).Optional.child
    else
        ValueType;

    // Exact match
    if (field_base == value_base) return true;

    // Allow comptime_int to match runtime integer types
    if (ValueType == comptime_int) {
        return switch (@typeInfo(field_base)) {
            .Int => true,
            else => false,
        };
    }

    // Allow comptime_float to match runtime float types
    if (ValueType == comptime_float) {
        return switch (@typeInfo(field_base)) {
            .Float => true,
            else => false,
        };
    }

    return false;
}

test "validation" {
    const TestTable = struct {
        pub const Definition = struct {
            id: i32,
            name: []const u8,
            age: ?u32,
        };
        pub const name = "test";
    };

    // These should compile
    validateWhereConditions(TestTable, .{ .id = 1 });
    validateWhereConditions(TestTable, .{ .name = "test" });
    validateWhereConditions(TestTable, .{ .age = null });
    validateWhereConditions(TestTable, .{ .age = .{ .gt = 18 } });

    // These would cause compile errors:
    // validateWhereConditions(TestTable, .{ .nonexistent = 1 });
    // validateWhereConditions(TestTable, .{ .id = "wrong type" });
    // validateWhereConditions(TestTable, .{ .name = 123 });
}
