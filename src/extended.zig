pub const core = @import("core.zig");

const builtin = @import("builtin");
const std     = @import("std");

const mem   = std.mem;
const fmt   = std.fmt;
const debug = std.debug;
const io    = std.io;

const assert = debug.assert;

pub const Param = struct {
    field: []const u8,
    names: core.Names,
    settings: Settings,
    kind: Kind,

    pub fn flag(field: []const u8, names: *const core.Names, settings: *const Settings) Param {
        return Param{
            .field = field,
            .names = names.*,
            .settings = settings.*,
            .kind = Kind.Flag,
        };
    }

    pub fn option(
        field: []const u8,
        names: *const core.Names,
        settings: *const Settings,
        comptime parser: *const Parser,
    ) Param {
        return Param{
            .field = field,
            .names = names.*,
            .settings = settings.*,
            .kind = Kind{ .Option = parser.* },
        };
    }

    pub fn subcommand(
        field: []const u8,
        names: *const core.Names,
        settings: *const Settings,
        comptime command: *const Command,
    ) Param {
        return Param{
            .field = field,
            .names = names.*,
            .settings = settings.*,
            .kind = Kind{ .Subcommand = Command.* },
        };
    }

    pub const Kind = union(enum) {
        Flag,
        Option: Parser,
        Subcommand: Command,
    };

    pub const Settings = struct {
        required: bool,
        position: ?usize,

        pub fn default() Settings {
            return Settings{
                .required = false,
                .position = null,
            };
        }
    };
};

const Opaque = @OpaqueType();
pub const Command = struct {
    params: []const Param,

    Result: type,
    default: *const Opaque,

    pub fn init(comptime Result: type, default: *const Result, params: []const Param) Command {
        return Command{
            .params = params,
            .Result = Result,
            .default = @ptrCast(*const Opaque, default),
        };
    }
};

pub const Parser = struct {
    const UnsafeFunction = *const void;

    FieldType: type,
    Errors: type,
    func: UnsafeFunction,

    pub fn init(comptime FieldType: type, comptime Errors: type, func: ParseFunc(FieldType, Errors)) Parser {
        return Parser {
            .FieldType = FieldType,
            .Errors = Errors,
            .func = @ptrCast(UnsafeFunction, func),
        };
    }

    fn parse(comptime parser: Parser, field_ptr: *parser.FieldType, arg: []const u8) parser.Errors!void {
        return @ptrCast(ParseFunc(parser.FieldType, parser.Errors), parser.func)(field_ptr, arg);
    }

    fn ParseFunc(comptime FieldType: type, comptime Errors: type) type {
        return fn(*FieldType, []const u8) Errors!void;
    }

    pub fn int(comptime Int: type, comptime radix: u8) Parser {
        const func = struct {
            fn i(field_ptr: *Int, arg: []const u8) !void {
                field_ptr.* = try fmt.parseInt(Int, arg, radix);
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
            fn s(field_ptr: *[]const u8, arg: []const u8) (error{}!void) {
                field_ptr.* = arg;
            }
        }.s
    );
};

pub fn Clap(comptime Result: type) type {
    return struct {
        const Self = this;

        default: Result,
        params: []const Param,

        pub fn parse(
            comptime clap: *const Self,
            comptime Error: type,
            iter: *core.ArgIterator(Error),
        ) !Result {
            // We initialize the core.Clap without any params, and fill them out in parseHelper.
            var c = core.Clap(usize, Error).init([]core.Param(usize){}, iter);

            const top_level_command = comptime Command.init(Result, &clap.default, clap.params);
            return try parseHelper(&top_level_command, Error, &c);
        }

        fn parseHelper(
            comptime command: *const Command,
            comptime Error: type,
            clap: *core.Clap(usize, Error),
        ) !command.Result {
            var result = @ptrCast(*const command.Result, command.default).*;

            var handled = comptime blk: {
                var res: [command.params.len]bool = undefined;
                for (command.params) |p, i| {
                    res[i] = !p.settings.required;
                }

                break :blk res;
            };

            // We replace the current clap with the commands parameters, so that we preserve the that
            // claps state. This is important, as core.Clap could be in a Chaining state, and
            // constructing a new core.Clap would skip the last chaining arguments.
            clap.params = comptime blk: {
                var res: [command.params.len]core.Param(usize) = undefined;

                for (command.params) |p, i| {
                    const id = i;
                    res[id] = core.Param(usize) {
                        .id = id,
                        .takes_value = p.kind == Param.Kind.Option,
                        .names = p.names,
                    };
                }

                break :blk res;
            };

            var pos: usize = 0;

            arg_loop:
            while (try clap.next()) |arg| : (pos += 1) {
                inline for(command.params) |param, i| {
                    if (arg.param.id == i and (param.settings.position ?? pos) == pos) {
                        handled[i] = true;

                        switch (param.kind) {
                            Param.Kind.Flag => {
                                getFieldPtr(&result, param.field).* = true;
                            },
                            Param.Kind.Option => |parser| {
                                try parser.parse(getFieldPtr(&result, param.field), ??arg.value);
                            },
                            Param.Kind.Subcommand => |sub_command| {
                                getFieldPtr(&result, param.field).* = try sub_command.parseHelper(Error, clap);

                                // After parsing a subcommand, there should be no arguments left.
                                break :arg_loop;
                            },
                        }
                        continue :arg_loop;
                    }
                }

                return error.InvalidArgument;
            }

            for (handled) |h| {
                if (!h)
                    return error.ParamNotHandled;
            }

            return result;
        }

        fn GetFieldPtrReturn(comptime Struct: type, comptime field: []const u8) type {
            var inst: Struct = undefined;
            const dot_index = comptime mem.indexOfScalar(u8, field, '.') ?? {
                return @typeOf(&@field(inst, field));
            };

            return GetFieldPtrReturn(@typeOf(@field(inst, field[0..dot_index])), field[dot_index + 1..]);
        }

        fn getFieldPtr(curr: var, comptime field: []const u8) GetFieldPtrReturn(@typeOf(curr).Child, field) {
            const dot_index = comptime mem.indexOfScalar(u8, field, '.') ?? {
                return &@field(curr, field);
            };

            return getFieldPtr(&@field(curr, field[0..dot_index]), field[dot_index + 1..]);
        }
    };
}
