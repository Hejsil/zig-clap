pub const core = @import("core.zig");

const builtin = @import("builtin");
const std     = @import("std");

const mem   = std.mem;
const fmt   = std.fmt;
const debug = std.debug;
const io    = std.io;

const assert = debug.assert;

const Opaque = @OpaqueType();

pub const Param = struct {
    field: []const u8,
    short: ?u8,
    long: ?[]const u8,
    takes_value: ?Parser,
    required: bool,
    position: ?usize,

    pub fn short(s: u8) Param {
        return Param{
            .field = []u8{s},
            .short = s,
            .long = null,
            .takes_value = null,
            .required = false,
            .position = null,
        };
    }

    pub fn long(l: []const u8) Param {
        return Param{
            .field = l,
            .short = null,
            .long = l,
            .takes_value = null,
            .required = false,
            .position = null,
        };
    }

    pub fn value(f: []const u8) Param {
        return Param{
            .field = f,
            .short = null,
            .long = null,
            .takes_value = null,
            .required = false,
            .position = null,
        };
    }

    /// Initialize a ::Param.
    /// If ::name.len == 0, then it's a value parameter: "value".
    /// If ::name.len == 1, then it's a short parameter: "-s".
    /// If ::name.len > 1, then it's a long parameter: "--long".
    pub fn smart(name: []const u8) Param {
        return Param{
            .field = name,
            .short = if (name.len == 1) name[0] else null,
            .long = if (name.len > 1) name else null,
            .takes_value = null,
            .required = false,
            .position = null,
        };
    }

    pub fn with(param: &const Param, comptime field_name: []const u8, v: var) Param {
        var res = param.*;
        @field(res, field_name) = v;
        return res;
    }
};

pub const Command = struct {
    field: []const u8,
    name: []const u8,
    params: []const Param,
    sub_commands: []const Command,

    Result: type,
    defaults: &const Opaque,
    parent: ?&const Command,

    pub fn init(name: []const u8, comptime Result: type, defaults: &const Result, params: []const Param, sub_commands: []const Command) Command {
        return Command{
            .field = name,
            .name = name,
            .params = params,
            .sub_commands = sub_commands,
            .Result = Result,
            .defaults = @ptrCast(&const Opaque, defaults),
            .parent = null,
        };
    }

    pub fn with(command: &const Command, comptime field_name: []const u8, v: var) Param {
        var res = command.*;
        @field(res, field_name) = v;
        return res;
    }

    pub fn parse(comptime command: &const Command, allocator: &mem.Allocator, arg_iter: &core.ArgIterator) !command.Result {
        const Parent = struct {};
        var parent = Parent{};
        return command.parseHelper(&parent, allocator, arg_iter);
    }

    fn parseHelper(comptime command: &const Command, parent: var, allocator: &mem.Allocator, arg_iter: &core.ArgIterator) !command.Result {
        const Result = struct {
            parent: @typeOf(parent),
            result: command.Result,
        };

        var result = Result{
            .parent = parent,
            .result = @ptrCast(&const command.Result, command.defaults).*,
        };

        // In order for us to wrap the core api, we have to translate clap.Param into core.Param.
        const core_params = comptime blk: {
            var res: [command.params.len + command.sub_commands.len]core.Param(usize) = undefined;

            for (command.params) |p, i| {
                const id = i;
                res[id] = core.Param(usize) {
                    .id = id,
                    .takes_value = p.takes_value != null,
                    .names = core.Names{
                        .bare = null,
                        .short = p.short,
                        .long = p.long,
                    },
                };
            }

            for (command.sub_commands) |c, i| {
                const id = i + command.params.len;
                res[id] = core.Param(usize) {
                    .id = id,
                    .takes_value = false,
                    .names = core.Names.bare(c.name),
                };
            }

            break :blk res;
        };

        var handled = comptime blk: {
            var res: [command.params.len]bool = undefined;
            for (command.params) |p, i| {
                res[i] = !p.required;
            }

            break :blk res;
        };

        var pos: usize = 0;
        var iter = core.Clap(usize).init(core_params, arg_iter, allocator);
        defer iter.deinit();

        arg_loop:
        while (try iter.next()) |arg| : (pos += 1) {
            inline for(command.params) |param, i| {
                comptime const field = "result." ++ param.field;

                if (arg.param.id == i and (param.position ?? pos) == pos) {
                    if (param.takes_value) |parser| {
                        try parser.parse(getFieldPtr(&result, field), ??arg.value);
                    } else {
                        getFieldPtr(&result, field).* = true;
                    }
                    handled[i] = true;
                    continue :arg_loop;
                }
            }

            inline for(command.sub_commands) |c, i| {
                comptime const field = "result." ++ c.field;
                comptime var sub_command = c;
                sub_command.parent = command;

                if (arg.param.id == i + command.params.len) {
                    getFieldPtr(&result, field).* = try sub_command.parseHelper(&result, allocator, arg_iter);
                    continue :arg_loop;
                }
            }

            return error.InvalidArgument;
        }

        return result.result;
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

pub const Parser = struct {
    const UnsafeFunction = &const void;

    FieldType: type,
    Errors: type,
    func: UnsafeFunction,

    pub fn init(comptime FieldType: type, comptime Errors: type, func: parseFunc(FieldType, Errors)) Parser {
        return Parser {
            .FieldType = FieldType,
            .Errors = Errors,
            .func = @ptrCast(UnsafeFunction, func),
        };
    }

    fn parse(comptime parser: Parser, field_ptr: TakePtr(parser.FieldType), arg: []const u8) parser.Errors!void {
        return @ptrCast(parseFunc(parser.FieldType, parser.Errors), parser.func)(field_ptr, arg);
    }

    // TODO: This is a workaround, since we don't have pointer reform yet.
    fn TakePtr(comptime T: type) type { return &T; }

    fn parseFunc(comptime FieldType: type, comptime Errors: type) type {
        return fn(&FieldType, []const u8) Errors!void;
    }

    pub fn int(comptime Int: type, comptime radix: u8) Parser {
        const func = struct {
            fn i(field_ptr: &Int, arg: []const u8) !void {
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
            fn s(field_ptr: &[]const u8, arg: []const u8) (error{}!void) {
                field_ptr.* = arg;
            }
        }.s
    );
};
