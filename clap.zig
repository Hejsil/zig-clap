const builtin = @import("builtin");
const std     = @import("std");

const mem   = std.mem;
const fmt   = std.fmt;
const debug = std.debug;
const io    = std.io;

const assert = debug.assert;

pub fn Clap(comptime Result: type) type {
    return struct {
        const Self = this;

        program_name: []const u8,
        author: []const u8,
        version: []const u8,
        about: []const u8,
        command: Command,
        defaults: Result,

        pub fn init(defaults: &const Result) Self {
            return Self {
                .program_name = "",
                .author = "",
                .version = "",
                .about = "",
                .command = Command.init(""),
                .defaults = *defaults,
            };
        }

        pub fn with(parser: &const Self, comptime field: []const u8, value: var) Self {
            var res = *parser;
            @field(res, field) = value;
            return res;
        }

        pub fn parse(comptime clap: &const Self, arguments: []const []const u8) !Result {
            return parseCommand(CommandList { .command = clap.command, .prev = null }, clap.defaults, arguments);
        }

        const CommandList = struct {
            command: &const Command,
            prev: ?&const CommandList,
        };

        fn parseCommand(comptime list: &const CommandList, defaults: &const Result, arguments: []const []const u8) !Result {
            const command = list.command;

            const Arg = struct {
                const Kind = enum { Long, Short, Value };

                arg: []const u8,
                kind: Kind,
            };

            const Iterator = struct {
                index: usize,
                slice: []const []const u8,

                const Pair = struct {
                    value: []const u8,
                    index: usize,
                };

                pub fn next(it: &this) ?[]const u8 {
                    const res = it.nextWithIndex() ?? return null;
                    return res.value;
                }

                pub fn nextWithIndex(it: &this) ?Pair {
                    if (it.index >= it.slice.len)
                        return null;

                    defer it.index += 1;
                    return Pair {
                        .value = it.slice[it.index],
                        .index = it.index,
                    };
                }
            };

            // NOTE: For now, a bitfield is used to keep track of the required arguments.
            //       This limits the user to 128 required arguments, which should be more
            //       than enough.
            var required = comptime blk: {
                var required_index : u128 = 0;
                var required_res : u128 = 0;
                for (command.arguments) |option| {
                    if (option.required) {
                        required_res |= 0x1 << required_index;
                        required_index += 1;
                    }
                }

                break :blk required_res;
            };

            var result = *defaults;

            var it = Iterator { .index = 0, .slice = arguments };
            while (it.nextWithIndex()) |item| {
                const arg_info = blk: {
                    var arg = item.value;
                    var kind = Arg.Kind.Value;

                    if (mem.startsWith(u8, arg, "--")) {
                        arg = arg[2..];
                        kind = Arg.Kind.Long;
                    } else if (mem.startsWith(u8, arg, "-")) {
                        arg = arg[1..];
                        kind = Arg.Kind.Short;
                    }

                    break :blk Arg { .arg = arg, .kind = kind };
                };
                const arg = arg_info.arg;
                const arg_index = item.index;
                const kind = arg_info.kind;
                const eql_index = mem.indexOfScalar(u8, arg, '=');

                success: {
                    // TODO: Revert a lot of if statements when inline loop compiler bugs have been fixed
                    switch (kind) {
                        // TODO: Handle subcommands
                        Arg.Kind.Value => {
                            var required_index = usize(0);
                            inline for (command.arguments) |option| {
                                defer if (option.required) required_index += 1;

                                if (option.short != null) continue;
                                if (option.long  != null) continue;
                                const has_right_index = if (option.index) |index| index == it.index else true;

                                if (has_right_index) {
                                    if (option.takes_value) |parser| {
                                        try parser.parse(&@field(result, option.field), arg);
                                    } else {
                                        @field(result, option.field) = true;
                                    }

                                    required = newRequired(option, required, required_index);
                                    break :success;
                                }
                            }
                        },
                        Arg.Kind.Short => {
                            if (arg.len == 0) return error.InvalidArg;

                            const end = (eql_index ?? arg.len) - 1;

                            short_arg_loop:
                            for (arg[0..end]) |short_arg, i| {
                                var required_index = usize(0);

                                inline for (command.arguments) |option| {
                                    defer if (option.required) required_index += 1;

                                    const short = option.short ?? continue;
                                    const has_right_index = if (option.index) |index| index == arg_index else true;

                                    if (has_right_index) {
                                        if (short_arg == short) {
                                            if (option.takes_value) |parser| {
                                                const value = arg[i + 1..];
                                                try parser.parse(&@field(result, option.field), value);
                                                break :success;
                                            } else {
                                                @field(result, option.field) = true;
                                                continue :short_arg_loop;
                                            }

                                            required = newRequired(option, required, required_index);
                                        }
                                    }
                                }
                            }

                            const last_arg = arg[end];
                            var required_index = usize(0);
                            inline for (command.arguments) |option| {
                                defer if (option.required) required_index += 1;

                                const short = option.short ?? continue;
                                const has_right_index = if (option.index) |index| index == arg_index else true;

                                if (has_right_index and last_arg == short) {
                                    if (option.takes_value) |parser| {
                                        const value = if (eql_index) |index| arg[index + 1..] else it.next() ?? return error.ArgMissingValue;
                                        try parser.parse(&@field(result, option.field), value);
                                    } else {
                                        if (eql_index) |_| return error.ArgTakesNoValue;
                                        @field(result, option.field) = true;
                                    }

                                    required = newRequired(option, required, required_index);
                                    break :success;
                                }
                            }
                        },
                        Arg.Kind.Long => {
                            var required_index = usize(0);
                            inline for (command.arguments) |option| {
                                defer if (option.required) required_index += 1;

                                const long = option.long ?? continue;
                                const has_right_index = if (option.index) |index| index == arg_index else true;

                                if (has_right_index and mem.eql(u8, arg, long)) {
                                    if (option.takes_value) |parser| {
                                        const value = if (eql_index) |index| arg[index + 1..] else it.next() ?? return error.ArgMissingValue;
                                        try parser.parse(&@field(result, option.field), value);
                                    } else {
                                        @field(result, option.field) = true;
                                    }

                                    required = newRequired(option, required, required_index);
                                    break :success;
                                }
                            }
                        }
                    }

                    return error.InvalidArg;
                }
            }

            if (required != 0) {
                return error.RequiredArgNotHandled;
            }

            return result;
        }

        fn newRequired(argument: &const Argument, old_required: u128, index: usize) u128 {
            if (argument.required)
                return old_required & ~(u128(1) << u7(index));

            return old_required;
        }
    };
}

pub const Command = struct {
    field: ?[]const u8,
    name: []const u8,
    arguments: []const Argument,
    sub_commands: []const Command,

    pub fn init(command_name: []const u8) Command {
        return Command {
            .field = null,
            .name = command_name,
            .arguments = []Argument{ },
            .sub_commands = []Command{ },
        };
    }

    pub fn with(command: &const Command, comptime field: []const u8, value: var) Command {
        var res = *command;
        @field(res, field) = value;
        return res;
    }
};

const Parser = struct {
    const UnsafeFunction = &const void;

    FieldType: type,
    Errors: type,
    func: UnsafeFunction,

    fn init(comptime FieldType: type, comptime Errors: type, func: parseFunc(FieldType, Errors)) Parser {
        return Parser {
            .FieldType = FieldType,
            .Errors = Errors,
            .func = @ptrCast(UnsafeFunction, func),
        };
    }

    fn parse(comptime parser: Parser, field_ptr: takePtr(parser.FieldType), arg: []const u8) parser.Errors!void {
        return @ptrCast(parseFunc(parser.FieldType, parser.Errors), parser.func)(field_ptr, arg);
    }

    // TODO: This is a workaround, since we don't have pointer reform yet.
    fn takePtr(comptime T: type) type { return &T; }

    fn parseFunc(comptime FieldType: type, comptime Errors: type) type {
        return fn(&FieldType, []const u8) Errors!void;
    }
};

pub const Argument = struct {
    field: []const u8,
    help: []const u8,
    takes_value: ?Parser,
    required: bool,
    short: ?u8,
    long: ?[]const u8,
    index: ?usize,

    pub fn field(field_name: []const u8) Argument {
        return Argument {
            .field = field_name,
            .help = "",
            .takes_value = null,
            .required = false,
            .short = null,
            .long = null,
            .index = null,
        };
    }

    pub fn arg(s: []const u8) Argument {
        return Argument.field(s)
            .with("short", if (s.len == 1) s[0] else null)
            .with("long", if (s.len != 1) s else null);
    }

    pub fn with(argument: &const Argument, comptime field_name: []const u8, value: var) Argument {
        var res = *argument;
        @field(res, field_name) = value;
        return res;
    }
};

pub const parse = struct {
    pub fn int(comptime Int: type, comptime radix: u8) Parser {
        const func = struct {
            fn i(field_ptr: &Int, arg: []const u8) !void {
                *field_ptr = try fmt.parseInt(Int, arg, radix);
            }
        }.i;
        return Parser.init(
            Int,
            @typeOf(func).ReturnType.ErrorSet,
            func
        );
    }

    const string = Parser.init(
        []const u8,
        error{},
        struct {
            fn s(field_ptr: &[]const u8, arg: []const u8) (error{}!void) {
                *field_ptr = arg;
            }
        }.s
    );

    const boolean = Parser.init(
        []const u8,
        error{InvalidBoolArg},
        struct {
            fn b(comptime T: type, field_ptr: &T, arg: []const u8) (error{InvalidBoolArg}!void) {
                if (mem.eql(u8, arg, "true")) {
                    *field_ptr = true;
                } else if (mem.eql(u8, arg, "false")) {
                    *field_ptr = false;
                } else {
                    return error.InvalidBoolArg;
                }
            }
        }.b
    );
};


const Options = struct {
    str: []const u8,
    int: i64,
    uint: u64,
    a: bool,
    b: bool,
    cc: bool,

    pub fn with(op: &const Options, comptime field: []const u8, value: var) Options {
        var res = *op;
        @field(res, field) = value;
        return res;
    }
};

const default = Options {
    .str = "",
    .int = 0,
    .uint = 0,
    .a = false,
    .b = false,
    .cc = false,
};

fn testNoErr(comptime clap: &const Clap(Options), args: []const []const u8, expected: &const Options) void {
    const actual = clap.parse(args) catch |err| { debug.warn("{}\n", @errorName(err)); unreachable; };
    assert(mem.eql(u8, expected.str, actual.str));
    assert(expected.int == actual.int);
    assert(expected.uint == actual.uint);
    assert(expected.a == actual.a);
    assert(expected.b == actual.b);
    assert(expected.cc == actual.cc);
}

fn testErr(comptime clap: &const Clap(Options), args: []const []const u8, expected: error) void {
    if (clap.parse(args)) |actual| {
        unreachable;
    } else |err| {
        assert(err == expected);
    }
}

test "clap.parse: short" {
        const clap = comptime Clap(Options).init(default).with("command",
        Command.init("").with("arguments",
            []Argument {
                Argument.arg("a"),
                Argument.arg("b"),
                Argument.field("int")
                    .with("short", 'i')
                    .with("takes_value", parse.int(i64, 10))
            }
        )
    );

    testNoErr(clap, [][]const u8 { "-a" },       default.with("a", true));
    testNoErr(clap, [][]const u8 { "-a", "-b" }, default.with("a", true).with("b",  true));
    testNoErr(clap, [][]const u8 { "-i=100" },   default.with("int", 100));
    testNoErr(clap, [][]const u8 { "-i100" },   default.with("int", 100));
    testNoErr(clap, [][]const u8 { "-i", "100" },   default.with("int", 100));
    testNoErr(clap, [][]const u8 { "-ab" },      default.with("a", true).with("b",  true));
    testNoErr(clap, [][]const u8 { "-abi", "100" }, default.with("a", true).with("b", true).with("int",  100));
    testNoErr(clap, [][]const u8 { "-abi=100" }, default.with("a", true).with("b", true).with("int",  100));
    testNoErr(clap, [][]const u8 { "-abi100" }, default.with("a", true).with("b", true).with("int",  100));
}

test "clap.parse: long" {
        const clap = comptime Clap(Options).init(default).with("command",
        Command.init("").with("arguments",
            []Argument {
                Argument.arg("cc"),
                Argument.arg("int").with("takes_value", parse.int(i64, 10)),
                Argument.arg("uint").with("takes_value", parse.int(u64, 10)),
                Argument.arg("str").with("takes_value", parse.string),
            }
        )
    );

    testNoErr(clap, [][]const u8 { "--cc" },         default.with("cc",  true));
    testNoErr(clap, [][]const u8 { "--int", "100" }, default.with("int",  100));
}

test "clap.parse: value bool" {
        const clap = comptime Clap(Options).init(default).with("command",
        Command.init("").with("arguments",
            []Argument {
                Argument.field("a"),
            }
        )
    );

    testNoErr(clap, [][]const u8 { "Hello World!" }, default.with("a",  true));
}

test "clap.parse: value str" {
        const clap = comptime Clap(Options).init(default).with("command",
        Command.init("").with("arguments",
            []Argument {
                Argument.field("str").with("takes_value", parse.string),
            }
        )
    );

    testNoErr(clap, [][]const u8 { "Hello World!" }, default.with("str", "Hello World!"));
}

test "clap.parse: value int" {
        const clap = comptime Clap(Options).init(default).with("command",
        Command.init("").with("arguments",
            []Argument {
                Argument.field("int").with("takes_value", parse.int(i64, 10)),
            }
        )
    );

    testNoErr(clap, [][]const u8 { "100" }, default.with("int", 100));
}

test "clap.parse: index" {
        const clap = comptime Clap(Options).init(default).with("command",
        Command.init("").with("arguments",
            []Argument {
                Argument.arg("a").with("index", 0),
                Argument.arg("b").with("index", 1),
            }
        )
    );

    testNoErr(clap, [][]const u8 { "-a", "-b" }, default.with("a", true).with("b", true));
    testErr(clap, [][]const u8 { "-b", "-a" }, error.InvalidArg);
}
