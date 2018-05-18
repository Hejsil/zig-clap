const std = @import("std");
const builtin = @import("builtin");

const os = std.os;
const is_windows = builtin.os == Os.windows;

pub fn Param(comptime Id: type) type {
    return struct {
        const Self = this;

        id: Id,
        short: ?u8,
        long: ?[]const u8,
        index: ?usize,
        takes_value: bool,
        required: bool,

        /// Initialize a parameter.
        /// If ::name.len == 0, then it's a value parameter: "some-command value".
        /// If ::name.len == 1, then it's a short parameter: "some-command -s".
        /// If ::name.len > 1, then it's a long parameter: "some-command --long".
        pub fn init(id: Id, name: []const u8) Self {
            return {
                .id = id,
                .short = if (name.len == 1) name[0] else null,
                .long = if (name.len > 1) name else null,
                .index = null,
                .takes_value = false,
                .required = false,
            };
        }

        pub fn with(param: &const Self, comptime field_name: []const u8, value: var) Self {
            var res = *param;
            @field(res, field_name) = value;
            return res;
        }
    };
}

pub fn Arg(comptime Id: type) type {
    return struct {
        id: Id,
        value: ?[]const u8,
    };
}


pub fn args() ArgIterator {
    return ArgIterator.init();
}

pub fn Iterator(comptime Id: type) type {
    return struct {
        const Self = this;
        const Buffer = if (is_windows) [1024 * 2]u8 else void;

        windows_buffer: Buffer,
        params: Param(Id),
        args: os.ArgIterator,
        exe: []const u8,

        pub fn init(params: []const Param(Id)) Self {
            return Self {
                .params = params,
                .
            };
        }

        fn innerNext(iter: &Self) ?[]const u8 {
            //if (builtin.os == Os.windows) {
            //    return iter.args.next(allocator);
            //} else {
            //    return iter.args.nextPosix();
            //}
        }
    }
}
