const std  = @import("std");
const bits = @import("bits.zig");

const mem   = std.mem;
const fmt   = std.fmt;
const debug = std.debug;
const io    = std.io;

const assert = debug.assert;

// TODO: Missing a few convinient features
//     * Short arguments that doesn't take values should probably be able to be
//       chain like many linux programs: "rm -rf"
//     * Handle "--something=VALUE"
pub fn Option(comptime Result: type, comptime ParseError: type) type {
    return struct {
        const Self = this;

        pub const Kind = enum {
            Optional,
            Required,
            IgnoresRequired
        };

        parser: fn(&Result, []const u8) ParseError!void,
        help: []const u8,
        kind: Kind,
        takes_value: bool,
        short: ?u8,
        long: ?[]const u8,

        pub fn init(parser: fn(&Result, []const u8) ParseError!void) Self {
            return Self {
                .parser = parser,
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
        kind: Kind
    };

    // NOTE: For now, a bitfield is used to keep track of the required arguments.
    //       This limits the user to 128 required arguments, which is more than
    //       enough.
    const required_mask = comptime blk: {
        var required_res : u128 = 0;
        for (options) |option, i| {
            if (option.kind == OptionT.Kind.Required) {
                required_res = (required_res << 1) | 0x1;
            }
        }

        break :blk required_res;
    };

    return struct {
        fn parse(args: []const []const u8) !Result {
            var result = *defaults;
            var required = required_mask;

            var arg_i = usize(0);
            loop: while (arg_i < args.len) : (arg_i += 1) {
                const pair = blk: {
                    const tmp = args[arg_i];
                    if (mem.startsWith(u8, tmp, "--"))
                        break :blk Arg { .arg = tmp[2..], .kind = Arg.Kind.Long };
                    if (mem.startsWith(u8, tmp, "-"))
                        break :blk Arg { .arg = tmp[1..], .kind = Arg.Kind.Short };

                    break :blk Arg { .arg = tmp, .kind = Arg.Kind.None };
                };
                const arg = pair.arg;
                const kind = pair.kind;

                comptime var required_index : usize = 0;
                inline_loop: inline for (options) |option, op_i| {

                    switch (kind) {
                        Arg.Kind.None => {
                            if (option.short != null) continue :inline_loop;
                            if (option.long  != null) continue :inline_loop;

                            try option.parser(&result, arg);

                            switch (option.kind) {
                                OptionT.Kind.Required => {
                                    required = bits.set(u128, required, u7(required_index), false);
                                    required_index += 1;
                                },
                                OptionT.Kind.IgnoresRequired => {
                                    required = 0;
                                    required_index += 1;
                                },
                                else => {}
                            }

                            continue :loop;
                        },
                        Arg.Kind.Short => {
                            const short = option.short ??        continue :inline_loop;
                            if (arg.len != 1 or arg[0] != short) continue :inline_loop;
                        },
                        Arg.Kind.Long => {
                            const long = option.long ??  continue :inline_loop;
                            if (!mem.eql(u8, long, arg)) continue :inline_loop;
                        }
                    }

                    if (option.takes_value) arg_i += 1;
                    if (args.len <= arg_i) return error.MissingValueToArgument;
                    try option.parser(&result, args[arg_i]);

                    switch (option.kind) {
                        OptionT.Kind.Required => {
                            required = bits.set(u128, required, u7(required_index), false);
                            required_index += 1;
                        },
                        OptionT.Kind.IgnoresRequired => {
                            required = 0;
                            required_index += 1;
                        },
                        else => {}
                    }

                    continue :loop;
                } else {
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

            inline for (options) |option| {
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
                        res -= 2 + long.len;

                        if (option.takes_value) {
                            res -= equal_value.len;
                        }
                    }

                    break :blk res;
                };

                if (option.long) |long| {
                    try out_stream.print("--{}", long);

                    if (option.takes_value) {
                        try out_stream.print("{}", equal_value);
                    }
                }

                try out_stream.print(" " ** missing_spaces);
                try out_stream.print("{}\n", option.help_message);
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
    };

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
            .err = error.MissingValueToArgument,
        },
    };

    const COption = Option(Color, @typeOf(Color.rFromStr).ReturnType.ErrorSet);
    const Clap = Parser(Color, @typeOf(Color.rFromStr).ReturnType.ErrorSet,
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
        }
    );

    for (cases) |case, i| {
        if (Clap.parse(case.args)) |res| {
            assert(res.r == case.res.r);
            assert(res.g == case.res.g);
            assert(res.b == case.res.b);
        } else |err| {
            assert(err == (case.err ?? unreachable));
        }
    }
}
