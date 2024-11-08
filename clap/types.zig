pub fn isArrayListUnmanaged(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct" or !@hasDecl(T, "Slice"))
        return false;

    const ptr_info = switch (@typeInfo(T.Slice)) {
        .pointer => |info| info,
        else => return false,
    };

    return T == std.ArrayListAlignedUnmanaged(ptr_info.child, null) or
        T == std.ArrayListAlignedUnmanaged(ptr_info.child, ptr_info.alignment);
}

test isArrayListUnmanaged {
    try std.testing.expect(!isArrayListUnmanaged(u8));
    try std.testing.expect(!isArrayListUnmanaged([]const u8));
    try std.testing.expect(!isArrayListUnmanaged(struct {
        pub const Slice = []const u8;
    }));
    try std.testing.expect(isArrayListUnmanaged(std.ArrayListUnmanaged(u8)));
}

pub fn allFieldsHaveDefaults(comptime T: type) bool {
    const info = switch (@typeInfo(T)) {
        .@"struct" => |s| s,
        else => return false,
    };

    inline for (info.fields) |field| {
        if (field.default_value == null)
            return false;
    }

    return true;
}

test allFieldsHaveDefaults {
    try std.testing.expect(!allFieldsHaveDefaults(u8));
    try std.testing.expect(!allFieldsHaveDefaults([]const u8));
    try std.testing.expect(allFieldsHaveDefaults(struct {}));
    try std.testing.expect(allFieldsHaveDefaults(struct {
        a: u8 = 0,
    }));
    try std.testing.expect(!allFieldsHaveDefaults(struct {
        a: u8,
    }));
    try std.testing.expect(!allFieldsHaveDefaults(struct {
        a: u8,
        b: u8 = 0,
        c: u8,
    }));
    try std.testing.expect(allFieldsHaveDefaults(struct {
        a: u8 = 1,
        b: u8 = 0,
        c: u8 = 3,
    }));
}

const std = @import("std");
