pub const FieldMap = struct {
    b: []const u8, // base
    v: []const u8, // variant
};

pub fn assertSameOffsetsFromMap(
    comptime Base: type,
    comptime Variant: type,
    comptime map: []const FieldMap,
) void {
    inline for (map) |m| {
        assertSameFieldOffset(Base, m.b, Variant, m.v);
    }
}

pub fn assertSameFieldOffset(
    comptime A: type,
    comptime aField: []const u8,
    comptime B: type,
    comptime bField: []const u8,
) void {
    if (@offsetOf(A, aField) != @offsetOf(B, bField)) {
        @compileError("Offset mismatch: " ++ @typeName(A) ++ "." ++ aField ++
            " != " ++ @typeName(B) ++ "." ++ bField);
    }
}
/// Asserts that all common fields listed in `commonFields` exist in `Variant`
/// with the same type as in `Base`.
pub fn assertCommonFieldTypes(
    comptime Base: type,
    comptime Variant: type,
    comptime commonFields: []const []const u8,
) void {
    const baseInfo = switch (@typeInfo(Base)) {
        .@"struct" => |s| s,
        else => @compileError(@typeName(Base) ++ " is not a struct"),
    };
    const variantInfo = switch (@typeInfo(Variant)) {
        .@"struct" => |s| s,
        else => @compileError(@typeName(Variant) ++ " is not a struct"),
    };

    inline for (commonFields) |fieldName| {
        const baseField = comptime blk: {
            for (baseInfo.fields) |field| {
                if (std.mem.eql(u8, field.name, fieldName)) {
                    break :blk field;
                }
            }
            @compileError("Field '" ++ fieldName ++ "' not found in base type " ++ @typeName(Base));
        };

        const variantField = comptime blk: {
            for (variantInfo.fields) |field| {
                if (std.mem.eql(u8, field.name, fieldName)) {
                    break :blk field;
                }
            }
            @compileError("Field '" ++ fieldName ++ "' not found in variant type " ++ @typeName(Variant));
        };

        if (baseField.type != variantField.type) {
            @compileError("Field '" ++ fieldName ++ "' type mismatch: " ++
                @typeName(Base) ++ "." ++ fieldName ++ " is " ++ @typeName(baseField.type) ++
                " but " ++ @typeName(Variant) ++ "." ++ fieldName ++ " is " ++ @typeName(variantField.type));
        }
    }
}

/// Asserts that all common fields listed in `commonFields` exist in `Variant`
/// with the same default value as in `Base`.
pub fn assertCommonFieldDefaults(
    comptime Base: type,
    comptime Variant: type,
    comptime commonFields: []const []const u8,
) void {
    const baseInfo = switch (@typeInfo(Base)) {
        .@"struct" => |s| s,
        else => @compileError(@typeName(Base) ++ " is not a struct"),
    };
    const variantInfo = switch (@typeInfo(Variant)) {
        .@"struct" => |s| s,
        else => @compileError(@typeName(Variant) ++ " is not a struct"),
    };

    inline for (commonFields) |fieldName| {
        const baseField = comptime blk: {
            for (baseInfo.fields) |field| {
                if (std.mem.eql(u8, field.name, fieldName)) {
                    break :blk field;
                }
            }
            @compileError("Field '" ++ fieldName ++ "' not found in base type " ++ @typeName(Base));
        };

        const variantField = comptime blk: {
            for (variantInfo.fields) |field| {
                if (std.mem.eql(u8, field.name, fieldName)) {
                    break :blk field;
                }
            }
            @compileError("Field '" ++ fieldName ++ "' not found in variant type " ++ @typeName(Variant));
        };

        if (baseField.default_value_ptr != null and variantField.default_value_ptr != null) {
            const baseDefault = baseField.defaultValue().?;
            const variantDefault = variantField.defaultValue().?;

            if (!std.meta.eql(baseDefault, variantDefault)) {
                @compileError("Field '" ++ fieldName ++ "' default value mismatch between " ++
                    @typeName(Base) ++ " and " ++ @typeName(Variant));
            }
        } else if (baseField.default_value_ptr != null or variantField.default_value_ptr != null) {
            @compileError("Field '" ++ fieldName ++ "' default value presence mismatch: one has default, other doesn't");
        }
    }
}

const std = @import("std");
