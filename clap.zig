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
                after_eql: ?[]const u8,
            };

            const Iterator = struct {
                index: usize,
                slice: []const []const u8,

                pub fn next(it: &this) ?[]const u8 {
                    if (it.index >= it.slice.len)
                        return null;

                    defer it.index += 1;
                    return it.slice[it.index];
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
            while (it.next()) |item| {
                const arg_info = blk: {
                    var arg = item;
                    var kind = Arg.Kind.Value;

                    if (mem.startsWith(u8, arg, "--")) {
                        arg = arg[2..];
                        kind = Arg.Kind.Long;
                    } else if (mem.startsWith(u8, arg, "-")) {
                        arg = arg[1..];
                        kind = Arg.Kind.Short;
                    }

                    if (kind == Arg.Kind.Value)
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
                        // TODO: Handle subcommands
                        Arg.Kind.Value => {
                            var required_index = usize(0);
                            inline for (command.arguments) |option| {
                                defer if (option.required) required_index += 1;
                                if (option.short != null) continue;
                                if (option.long  != null) continue;

                                if (option.takes_value) |parser| {
                                    try parser.parse(&@field(result, option.field), arg);
                                } else {
                                    @field(result, option.field) = true;
                                }

                                required = newRequired(option, required, required_index);
                                break :success;
                            }
                        },
                        Arg.Kind.Short => {
                            const arg_len = arg.len;
                            if (arg.len == 0) return error.FoundShortOptionWithNoName;
                            short_arg_loop: for (arg[0..arg.len - 1]) |short_arg| {
                                var required_index = usize(0);
                                inline for (command.arguments) |option| {
                                    defer if (option.required) required_index += 1;
                                    const short = option.short ?? continue;
                                    if (short_arg == short) {
                                        if (option.takes_value) |_| return error.OptionMissingValue;

                                        @field(result, option.field) = true;
                                        required = newRequired(option, required, required_index);
                                        continue :short_arg_loop;
                                    }
                                }

                                return error.InvalidArgument;
                            }

                            const last_arg = arg[arg.len - 1];
                            var required_index = usize(0);
                            inline for (command.arguments) |option| {
                                defer if (option.required) required_index += 1;
                                const short = option.short ?? continue;

                                if (last_arg == short) {
                                    if (option.takes_value) |parser| {
                                        const value = after_eql ?? it.next() ?? return error.OptionMissingValue;
                                        try parser.parse(&@field(result, option.field), value);
                                    } else {
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

                                if (mem.eql(u8, arg, long)) {
                                    if (option.takes_value) |parser| {
                                        const value = after_eql ?? it.next() ?? return error.OptionMissingValue;
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

                    return error.InvalidArgument;
                }
            }

            if (required != 0) {
                return error.RequiredArgumentWasntHandled;
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

    pub fn field(field_name: []const u8) Argument {
        return Argument {
            .field = field_name,
            .help = "",
            .takes_value = null,
            .required = false,
            .short = null,
            .long = null,
        };
    }

    pub fn arg(s: []const u8) Argument {
        return Argument {
            .field = s,
            .help = "",
            .takes_value = null,
            .required = false,
            .short = if (s.len == 1) s[0] else null,
            .long = if (s.len != 1) s else null,
        };
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

fn testErr(args: []const []const u8, expected: error) void {
    if (clap.parse(case.args)) |actual| {
        unreachable;
    } else |err| {
        assert(err == expected);
    }
}

test "clap.parse: short" {
    @breakpoint();
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
    testNoErr(clap, [][]const u8 { "-i", "100" },   default.with("int", 100));
    testNoErr(clap, [][]const u8 { "-ab" },      default.with("a", true).with("b",  true));
    testNoErr(clap, [][]const u8 { "-abi 100" }, default.with("a", true).with("b", true).with("int",  100));
    testNoErr(clap, [][]const u8 { "-abi=100" }, default.with("a", true).with("b", true).with("int",  100));
}

test "clap.parse: long" {
    @breakpoint();
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
    @breakpoint();
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
    @breakpoint();
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
    @breakpoint();
    const clap = comptime Clap(Options).init(default).with("command",
        Command.init("").with("arguments",
            []Argument {
                Argument.field("int").with("takes_value", parse.int(i64, 10)),
            }
        )
    );

    testNoErr(clap, [][]const u8 { "100" }, default.with("int", 100));
}
