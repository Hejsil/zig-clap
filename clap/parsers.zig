const std = @import("std");

const fmt = std.fmt;
const testing = std.testing;

pub const default = .{
    .string = string,
    .str = string,
    .u8 = int(u8, 0),
    .u16 = int(u16, 0),
    .u32 = int(u32, 0),
    .u64 = int(u64, 0),
    .usize = int(usize, 0),
    .i8 = int(i8, 0),
    .i16 = int(i16, 0),
    .i32 = int(i32, 0),
    .i64 = int(i64, 0),
    .isize = int(isize, 0),
    .f32 = float(f32),
    .f64 = float(f64),
};

/// A parser that does nothing.
pub fn string(in: []const u8) error{}![]const u8 {
    return in;
}

test "string" {
    try testing.expectEqualStrings("aa", try string("aa"));
}

/// A parser that uses `std.fmt.parseInt` to parse the string into an integer value.
/// See `std.fmt.parseInt` documentation for more information.
pub fn int(comptime T: type, comptime base: u8) fn ([]const u8) fmt.ParseIntError!T {
    return struct {
        fn parse(in: []const u8) fmt.ParseIntError!T {
            return fmt.parseInt(T, in, base);
        }
    }.parse;
}

test "int" {
    try testing.expectEqual(@as(u8, 0), try int(u8, 10)("0"));
    try testing.expectEqual(@as(u8, 1), try int(u8, 10)("1"));
    try testing.expectEqual(@as(u8, 10), try int(u8, 10)("10"));
    try testing.expectEqual(@as(u8, 0b10), try int(u8, 2)("10"));
    try testing.expectEqual(@as(u8, 0x10), try int(u8, 0)("0x10"));
    try testing.expectEqual(@as(u8, 0b10), try int(u8, 0)("0b10"));
    try testing.expectEqual(@as(u16, 0), try int(u16, 10)("0"));
    try testing.expectEqual(@as(u16, 1), try int(u16, 10)("1"));
    try testing.expectEqual(@as(u16, 10), try int(u16, 10)("10"));
    try testing.expectEqual(@as(u16, 0b10), try int(u16, 2)("10"));
    try testing.expectEqual(@as(u16, 0x10), try int(u16, 0)("0x10"));
    try testing.expectEqual(@as(u16, 0b10), try int(u16, 0)("0b10"));
}

/// A parser that uses `std.fmt.parseFloat` to parse the string into an float value.
/// See `std.fmt.parseFloat` documentation for more information.
pub fn float(comptime T: type) fn ([]const u8) fmt.ParseFloatError!T {
    return struct {
        fn parse(in: []const u8) fmt.ParseFloatError!T {
            return fmt.parseFloat(T, in);
        }
    }.parse;
}

test "float" {
    try testing.expectEqual(@as(f32, 0), try float(f32)("0"));
}

pub const EnumError = error{
    NameNotPartOfEnum,
};

/// A parser that uses `std.meta.stringToEnum` to parse the string into an enum value. On `null`,
/// this function returns the error `NameNotPartOfEnum`.
/// See `std.meta.stringToEnum` documentation for more information.
pub fn enumeration(comptime T: type) fn ([]const u8) EnumError!T {
    return struct {
        fn parse(in: []const u8) EnumError!T {
            return std.meta.stringToEnum(T, in) orelse error.NameNotPartOfEnum;
        }
    }.parse;
}

test "enumeration" {
    const E = enum { a, b, c };
    try testing.expectEqual(E.a, try enumeration(E)("a"));
    try testing.expectEqual(E.b, try enumeration(E)("b"));
    try testing.expectEqual(E.c, try enumeration(E)("c"));
    try testing.expectError(EnumError.NameNotPartOfEnum, enumeration(E)("d"));
}

fn ReturnType(comptime P: type) type {
    return @typeInfo(P).Fn.return_type.?;
}

pub fn Result(comptime P: type) type {
    return @typeInfo(ReturnType(P)).ErrorUnion.payload;
}
