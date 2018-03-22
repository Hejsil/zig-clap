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

        pub fn parse(comptime clap: &const Self, arguments: []const []const u8) !Result {
            return clap.command.parse(Result, clap.defaults, arguments);
        }

        pub const Builder = struct {
            result: Self,

            pub fn init(defaults: &const Result) Builder {
                return Builder {
                    .result = Self {
                        .program_name = "",
                        .author = "",
                        .version = "",
                        .about = "",
                        .command = Command.Builder.init("").build(),
                        .defaults = *defaults,
                    }
                };
            }

            pub fn programName(builder: &const Builder, name: []const u8) Builder {
                var res = *builder;
                res.result.program_name = name;
                return res;
            }

            pub fn author(builder: &const Builder, name: []const u8) Builder {
                var res = *builder;
                res.result.author = name;
                return res;
            }

            pub fn version(builder: &const Builder, version_str: []const u8) Builder {
                var res = *builder;
                res.result.author = version_str;
                return res;
            }

            pub fn about(builder: &const Builder, text: []const u8) Builder {
                var res = *builder;
                res.result.about = text;
                return res;
            }

            pub fn command(builder: &const Builder, cmd: &const Command) Builder {
                var res = *builder;
                res.result.command = *cmd;
                return res;
            }

            pub fn build(builder: &const Builder) Self {
                return builder.result;
            }
        };
    };
}

pub const Command = struct {
    field: ?[]const u8,
    name: []const u8,
    arguments: []const Argument,
    sub_commands: []const Command,

    pub fn parse(comptime command: &const Command, comptime Result: type, defaults: &const Result, arguments: []const []const u8) !Result {
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

                            try option.parse(&result, arg);
                            required = newRequired(option, required, required_index);
                            break :success;
                        }
                    },
                    Arg.Kind.Short => {
                        if (arg.len == 0) return error.FoundShortOptionWithNoName;
                        short_arg_loop: for (arg[0..arg.len - 1]) |short_arg| {
                            var required_index = usize(0);
                            inline for (command.arguments) |option| {
                                defer if (option.required) required_index += 1;
                                const short = option.short ?? continue;
                                if (short_arg == short) {
                                    if (option.takes_value) return error.OptionMissingValue;

                                    *getFieldPtr(Result, &result, option.field) = true;
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
                                if (option.takes_value) {
                                    const value = after_eql ?? it.next() ?? return error.OptionMissingValue;
                                    *getFieldPtr(Result, &result, option.field) = try strToValue(FieldType(Result, option.field), value);
                                } else {
                                    *getFieldPtr(Result, &result, option.field) = true;
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
                                if (option.takes_value) {
                                    const value = after_eql ?? it.next() ?? return error.OptionMissingValue;
                                    *getFieldPtr(Result, &result, option.field) = try strToValue(FieldType(Result, option.field), value);
                                } else {
                                    *getFieldPtr(Result, &result, option.field) = true;
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

    fn FieldType(comptime Result: type, comptime field: []const u8) type {
        var i = usize(0);
        inline while (i < @memberCount(Result)) : (i += 1) {
            if (mem.eql(u8, @memberName(Result, i), field))
                return @memberType(Result, i);
        }

        @compileError("Field not found!");
    }

    fn getFieldPtr(comptime Result: type, res: &Result, comptime field: []const u8) &FieldType(Result, field) {
        return @intToPtr(&FieldType(Result, field), @ptrToInt(res) + @offsetOf(Result, field));
    }

    fn strToValue(comptime Result: type, str: []const u8) !Result {
        const TypeId = builtin.TypeId;
        switch (@typeId(Result)) {
            TypeId.Type, TypeId.Void, TypeId.NoReturn, TypeId.Pointer,
            TypeId.Array, TypeId.Struct, TypeId.UndefinedLiteral,
            TypeId.NullLiteral, TypeId.ErrorUnion, TypeId.ErrorSet,
            TypeId.Union, TypeId.Fn, TypeId.Namespace, TypeId.Block,
            TypeId.BoundFn, TypeId.ArgTuple, TypeId.Opaque, TypeId.Promise => @compileError("Type not supported!"),

            TypeId.Bool => {
                if (mem.eql(u8, "true", str))
                    return true;
                if (mem.eql(u8, "false", str))
                    return false;

                return error.CannotParseStringAsBool;
            },
            TypeId.Int, TypeId.IntLiteral => return fmt.parseInt(Result, str, 10),
            TypeId.Float, TypeId.FloatLiteral => @compileError("TODO: Implement str to float"),
            TypeId.Nullable => {
                if (mem.eql(u8, "null", str))
                    return null;

                return strToValue(Result.Child, str);
            },
            TypeId.Enum => @compileError("TODO: Implement str to enum"),
        }
    }

    fn newRequired(argument: &const Argument, old_required: u128, index: usize) u128 {
        if (argument.required)
            return old_required & ~(u128(1) << u7(index));

        return old_required;
    }

    pub const Builder = struct {
        result: Command,

        pub fn init(command_name: []const u8) Builder {
            return Builder {
                .result = Command {
                    .field = null,
                    .name = command_name,
                    .arguments = []Argument{ },
                    .sub_commands = []Command{ },
                }
            };
        }

        pub fn field(builder: &const Builder, field_name: []const u8) Builder {
            var res = *builder;
            res.result.field = field_name;
            return res;
        }

        pub fn name(builder: &const Builder, n: []const u8) Builder {
            var res = *builder;
            res.result.name = n;
            return res;
        }

        pub fn arguments(builder: &const Builder, args: []const Argument) Builder {
            var res = *builder;
            res.result.arguments = args;
            return res;
        }

        pub fn subCommands(builder: &const Builder, commands: []const Command) Builder {
            var res = *builder;
            res.result.commands = commands;
            return res;
        }

        pub fn build(builder: &const Builder) Command {
            return builder.result;
        }
    };
};

pub const Argument = struct {
    field: []const u8,
    help: []const u8,
    takes_value: bool,
    required: bool,
    short: ?u8,
    long: ?[]const u8,

    pub const Builder = struct {
        result: Argument,

        pub fn init(field_name: []const u8) Builder {
            return Builder {
                .result = Argument {
                    .field = field_name,
                    .help = "",
                    .takes_value = false,
                    .required = false,
                    .short = null,
                    .long = null,
                }
            };
        }

        pub fn field(builder: &const Builder, field_name: []const u8) Builder {
            var res = *builder;
            res.result.field = field_name;
            return res;
        }

        pub fn help(builder: &const Builder, text: []const u8) Builder {
            var res = *builder;
            res.result.help = text;
            return res;
        }

        pub fn takesValue(builder: &const Builder, takes_value: bool) Builder {
            var res = *builder;
            res.result.takes_value = takes_value;
            return res;
        }

        pub fn required(builder: &const Builder, is_required: bool) Builder {
            var res = *builder;
            res.result.required = is_required;
            return res;
        }

        pub fn short(builder: &const Builder, name: u8) Builder {
            var res = *builder;
            res.result.short = name;
            return res;
        }

        pub fn long(builder: &const Builder, name: []const u8) Builder {
            var res = *builder;
            res.result.long = name;
            return res;
        }

        pub fn build(builder: &const Builder) Argument {
            return builder.result;
        }
    };
};

test "clap.parse.Example" {
    const Color = struct {
        r: u8, g: u8, b: u8, max: bool
    };

    const Case = struct { args: []const []const u8, res: Color, err: ?error };
    const cases = []Case {
        Case {
            .args = [][]const u8 { "-r", "100", "-g", "100", "-b", "100", },
            .res = Color { .r = 100, .g = 100, .b = 100, .max = false },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "--red", "100", "-g", "100", "--blue", "50", },
            .res = Color { .r = 100, .g = 100, .b = 50, .max = false },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "--red=100", "-g=100", "--blue=50", },
            .res = Color { .r = 100, .g = 100, .b = 50, .max = false },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-g", "200", "--blue", "100", "--red", "100", },
            .res = Color { .r = 100, .g = 200, .b = 100, .max = false },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-r", "200", "-r", "255" },
            .res = Color { .r = 255, .g = 0, .b = 0, .max = false },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-mr", "100" },
            .res = Color { .r = 100, .g = 0, .b = 0, .max = true },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-mr=100" },
            .res = Color { .r = 100, .g = 0, .b = 0, .max = true },
            .err = null,
        },
        Case {
            .args = [][]const u8 { "-g", "200", "-b", "255" },
            .res = Color { .r = 0, .g = 0, .b = 0, .max = false },
            .err = error.RequiredArgumentWasntHandled,
        },
        Case {
            .args = [][]const u8 { "-p" },
            .res = Color { .r = 0, .g = 0, .b = 0, .max = false },
            .err = error.InvalidArgument,
        },
        Case {
            .args = [][]const u8 { "-g" },
            .res = Color { .r = 0, .g = 0, .b = 0, .max = false },
            .err = error.OptionMissingValue,
        },
        Case {
            .args = [][]const u8 { "-" },
            .res = Color { .r = 0, .g = 0, .b = 0, .max = false },
            .err = error.FoundShortOptionWithNoName,
        },
        Case {
            .args = [][]const u8 { "-rg", "100" },
            .res = Color { .r = 0, .g = 0, .b = 0, .max = false },
            .err = error.OptionMissingValue,
        },
    };

    const clap = comptime Clap(Color).Builder
        .init(
            Color {
                .r = 0,
                .b = 0,
                .g = 0,
                .max = false,
            }
        )
        .command(
            Command.Builder
                .init("color")
                .arguments(
                    []Argument {
                        Argument.Builder
                            .init("r")
                            .help("The amount of red in our color")
                            .short('r')
                            .long("red")
                            .takesValue(true)
                            .required(true)
                            .build(),
                        Argument.Builder
                            .init("g")
                            .help("The amount of green in our color")
                            .short('g')
                            .long("green")
                            .takesValue(true)
                            .build(),
                        Argument.Builder
                            .init("b")
                            .help("The amount of blue in our color")
                            .short('b')
                            .long("blue")
                            .takesValue(true)
                            .build(),
                        Argument.Builder
                            .init("max")
                            .help("Set all values to max")
                            .short('m')
                            .long("max")
                            .build(),
                    }
                )
                .build()
        )
        .build();

    for (cases) |case, i| {
        if (clap.parse(case.args)) |res| {
            assert(case.err == null);
            assert(res.r == case.res.r);
            assert(res.g == case.res.g);
            assert(res.b == case.res.b);
            assert(res.max == case.res.max);
        } else |err| {
            assert(err == ??case.err);
        }
    }
}
