const std  = @import("std");

const mem   = std.mem;
const fmt   = std.fmt;
const debug = std.debug;
const io    = std.io;

const assert = debug.assert;

// TODO:
//     * Inform the caller which argument caused the error.
pub fn Option(comptime Result: type, comptime ParseError: type) type {
    return struct {
        const Self = this;

        pub const Kind = enum {
            Optional,
            Required,
            IgnoresRequired
        };

        parse: fn(&Result, []const u8) ParseError!void,
        help: []const u8,
        kind: Kind,
        takes_value: bool,
        short: ?u8,
        long: ?[]const u8,

        pub fn init(parse_fn: fn(&Result, []const u8) ParseError!void) Self {
            return Self {
                .parse = parse_fn,
                .help = "",
                .kind = Kind.Optional,
                .takes_value = false,
                .short = null,
                .long = null,
            };
        }

        pub fn setHelp(option: &const Self, help_str: []const u8) Self {
            var res = *option; res.help = help_str;
            return res;
        }

        pub fn setKind(option: &const Self, kind: Kind) Self {
            var res = *option; res.kind = kind;
            return res;
        }

        pub fn takesValue(option: &const Self, takes_value: bool) Self {
            var res = *option; res.takes_value = takes_value;
            return res;
        }

        pub fn setShort(option: &const Self, short: u8) Self {
            var res = *option; res.short = short;
            return res;
        }

        pub fn setLong(option: &const Self, long: []const u8) Self {
            var res = *option; res.long = long;
            return res;
        }
    };
}

pub fn Parser(comptime Result: type, comptime ParseError: type, comptime defaults: &const Result,
    comptime options: []const Option(Result, ParseError)) type {

    const OptionT = Option(Result, ParseError);
    const Arg = struct {
        const Kind = enum { Long, Short, None };

        arg: []const u8,
        kind: Kind,
        after_eql: ?[]const u8,
    };

    const Iterator = struct {
        slice: []const []const u8,

        pub fn next(it: &this) ?[]const u8 {
            if (it.slice.len == 0)
                return null;

            defer it.slice = it.slice[1..];
            return it.slice[0];
        }
    };

    // NOTE: For now, a bitfield is used to keep track of the required arguments.
    //       This limits the user to 128 required arguments, which is more than
    //       enough.
    const required_mask = comptime blk: {
        var required_index : u128 = 0;
        var required_res : u128 = 0;
        for (options) |option, i| {
            if (option.kind == OptionT.Kind.Required) {
                required_res |= 0x1 << required_index;
                required_index += 1;
            }
        }

        break :blk required_res;
    };

    return struct {
        fn newRequired(option: &const OptionT, old_required: u128, index: usize) u128 {
            switch (option.kind) {
                OptionT.Kind.Required => {
                    return old_required & ~(u128(1) << u7(index));
                },
                OptionT.Kind.IgnoresRequired => return 0,
                else => return old_required,
            }
        }

        pub fn parse(args: []const []const u8) !Result {
            var result = *defaults;
            var required = required_mask;

            var it = Iterator { .slice = args };
            while (it.next()) |item| {
                const arg_info = blk: {
                    var arg = item;
                    var kind = Arg.Kind.None;

                    if (mem.startsWith(u8, arg, "--")) {
                        arg = arg[2..];
                        kind = Arg.Kind.Long;
                    } else if (mem.startsWith(u8, arg, "-")) {
                        arg = arg[1..];
                        kind = Arg.Kind.Short;
                    }

                    if (kind == Arg.Kind.None)
                        break :blk Arg { .arg = arg, .kind = kind, .after_eql = null };


                    if (mem.indexOfScalar(u8, arg, '=')) |index| {
                        break :blk Arg { .arg = arg[0..index], .kind = kind, .after_eql = arg[index + 1..] };
                    } else {
                        break :blk Arg { .arg = arg, .kind = kind, .after_eql = null };
                    }
                };
                const arg = arg_info.arg;
                const kind = arg_info.kind;
                const after_eql = arg_info.after_eql;

                success: {

                    switch (kind) {
                        Arg.Kind.None => {
                            var required_index = usize(0);
                            inline for (options) |option| {
                                defer if (option.kind == OptionT.Kind.Required) required_index += 1;
                                if (option.short != null) continue;
                                if (option.long  != null) continue;

                                try option.parse(&result, arg);
                                required = newRequired(option, required, required_index);
                                break :success;
                            }
                        },
                        Arg.Kind.Short => {
                            if (arg.len == 0) return error.FoundShortOptionWithNoName;
                            short_arg_loop: for (arg[0..arg.len - 1]) |short_arg| {
                                var required_index = usize(0);
                                inline for (options) |option| {
                                    defer if (option.kind == OptionT.Kind.Required) required_index += 1;
                                    const short = option.short ?? continue;
                                    if (short_arg == short) {
                                        if (option.takes_value) return error.OptionMissingValue;

                                        try option.parse(&result, []u8{});
                                        required = newRequired(option, required, required_index);
                                        continue :short_arg_loop;
                                    }
                                }

                                return error.InvalidArgument;
                            }

                            const last_arg = arg[arg.len - 1];
                            var required_index = usize(0);
                            inline for (options) |option| {
                                defer if (option.kind == OptionT.Kind.Required) required_index += 1;
                                const short = option.short ?? continue;

                                if (last_arg == short) {
                                    if (option.takes_value) {
                                        const value = after_eql ?? it.next() ?? return error.OptionMissingValue;
                                        try option.parse(&result, value);
                                    } else {
                                        try option.parse(&result, []u8{});
                                    }

                                    required = newRequired(option, required, required_index);
                                    break :success;
                                }
                            }
                        },
                        Arg.Kind.Long => {
                            var required_index = usize(0);
                            inline for (options) |option| {
                                defer if (option.kind == OptionT.Kind.Required) required_index += 1;
                                const long = option.long ?? continue;
                                if (mem.eql(u8, arg, long)) {
                                    if (option.takes_value) {
                                        const value = after_eql ?? it.next() ?? return error.OptionMissingValue;
                                        try option.parse(&result, value);
                                    } else {
                                        try option.parse(&result, []u8{});
                                    }

                                    required = newRequired(option, required, required_index);
                                    break :success;
                                }
                            }
                        }
                    }

                    return error.InvalidArgument;
                }
            }

            if (required != 0) {
                return error.RequiredArgumentWasntHandled;
            }

            return result;
        }

        // TODO:
        //    * Usage
        //    * Description
        pub fn help(out_stream: var) !void {
            const equal_value : []const u8 = "=OPTION";
            const longest_long = comptime blk: {
                var res = usize(0);
                for (options) |option| {
                    const long = option.long ?? continue;
                    var len = long.len;

                    if (option.takes_value)
                        len += equal_value.len;

                    if (res < len)
                        res = len;
                }

                break :blk res;
            };

            for (options) |option| {
                if (option.short == null and option.long == null) continue;

                try out_stream.print("    ");
                if (option.short) |short| {
                    try out_stream.print("-{c}", short);
                } else {
                    try out_stream.print("  ");
                }

                if (option.short != null and option.long != null) {
                    try out_stream.print(", ");
                } else {
                    try out_stream.print("  ");
                }

                // We need to ident by:
                // "--<longest_long> ".len
                const missing_spaces = comptime blk: {
                    var res = longest_long + 3;
                    if (option.long) |long| {
                        try out_stream.print("--{}", long);
                        res -= 2 + long.len;

                        if (option.takes_value) {
                            try out_stream.print("{}", equal_value);
                            res -= equal_value.len;
                        }
                    }

                    break :blk res;
                };

                var i = usize(0);
                while (i < missing_spaces) : (i += 1) {
                    try out_stream.print(" ");
                }
                try out_stream.print("{}\n", option.help);
            }
        }
    };
}

test "clap.parse.Example" {
    const Color = struct {
        const Self = this;

        r: u8, g: u8, b: u8,

        fn rFromStr(color: &Self, str: []const u8) !void {
            color.r = try fmt.parseInt(u8, str, 10);
        }

        fn gFromStr(color: &Self, str: []const u8) !void {
            color.g = try fmt.parseInt(u8, str, 10);
        }

        fn bFromStr(color: &Self, str: []const u8) !void {
            color.b = try fmt.parseInt(u8, str, 10);
        }

        // TODO: There is a segfault when we try to use the error set: @typeOf(fmt.parseInt).ReturnType.ErrorSet
        fn setMax(color: &Self, str: []const u8) !void {
            color.r = try fmt.parseInt(u8, "255", 10);
            color.g = try fmt.parseInt(u8, "255", 10);
            color.b = try fmt.parseInt(u8, "255", 10);
        }
    };
    const Error = @typeOf(Color.setMax).ReturnType.ErrorSet;

    const Case = struct { args: []const []const u8, res: Color, err: ?error };
    const cases = []Case {
        Case {
            .args = [][]const u8 { "-r", "100", "-g", "100", "-b", "100", },
            .res = Color { .r = 100, .g = 100, .b = 100 },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "--red", "100", "-g", "100", "--blue", "50", },
            .res = Color { .r = 100, .g = 100, .b = 50 },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "--red=100", "-g=100", "--blue=50", },
            .res = Color { .r = 100, .g = 100, .b = 50 },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-g", "200", "--blue", "100", "--red", "100", },
            .res = Color { .r = 100, .g = 200, .b = 100 },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-r", "200", "-r", "255" },
            .res = Color { .r = 255, .g = 0, .b = 0 },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-mr", "100" },
            .res = Color { .r = 100, .g = 255, .b = 255 },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-mr=100" },
            .res = Color { .r = 100, .g = 255, .b = 255 },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-g", "200", "-b", "255" },
            .res = Color { .r = 0, .g = 0, .b = 0 },
            .err = error.RequiredArgumentWasntHandled,
        },
        Case {
            .args = [][]const u8 { "-p" },
            .res = Color { .r = 0, .g = 0, .b = 0 },
            .err = error.InvalidArgument,
        },
        Case {
            .args = [][]const u8 { "-g" },
            .res = Color { .r = 0, .g = 0, .b = 0 },
            .err = error.OptionMissingValue,
        },
        Case {
            .args = [][]const u8 { "-" },
            .res = Color { .r = 0, .g = 0, .b = 0 },
            .err = error.FoundShortOptionWithNoName,
        },
        Case {
            .args = [][]const u8 { "-rg", "100" },
            .res = Color { .r = 0, .g = 0, .b = 0 },
            .err = error.OptionMissingValue,
        },
    };

    const COption = Option(Color, Error);
    const Clap = Parser(Color, Error,
        Color { .r = 0, .g = 0, .b = 0 },
        comptime []COption {
            COption.init(Color.rFromStr)
                .setHelp("The amount of red in our color")
                .setShort('r')
                .setLong("red")
                .takesValue(true)
                .setKind(COption.Kind.Required),
            COption.init(Color.gFromStr)
                .setHelp("The amount of green in our color")
                .setShort('g')
                .setLong("green")
                .takesValue(true),
            COption.init(Color.bFromStr)
                .setHelp("The amount of blue in our color")
                .setShort('b')
                .setLong("blue")
                .takesValue(true),
            COption.init(Color.setMax)
                .setHelp("Set all values to max")
                .setShort('m')
                .setLong("max"),
        }
    );

    for (cases) |case, i| {
        if (Clap.parse(case.args)) |res| {
            assert(case.err == null);
            assert(res.r == case.res.r);
            assert(res.g == case.res.g);
            assert(res.b == case.res.b);
        } else |err| {
            assert(err == ??case.err);
        }
    }
}
