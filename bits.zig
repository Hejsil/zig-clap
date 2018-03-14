const math = @import("std").math;

pub fn set(comptime Int: type, num: Int, bit: math.Log2Int(Int), value: bool) Int {
    return (num & ~(Int(1) << bit)) | (Int(value) << bit);
}

pub fn get(comptime Int: type, num: Int, bit: math.Log2Int(Int)) bool {
    return ((num >> bit) & 1) != 0;
}
