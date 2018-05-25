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
        var res = *param;
        @field(res, field_name) = v;
        return res;
    }
};

pub fn Clap(comptime Result: type) type {
    return struct {
        const Self = this;

        defaults: Result,
        params: []const Param,

        pub fn parse(comptime clap: &const Self, allocator: &mem.Allocator, arg_iter: &core.ArgIterator) !Result {
            var result = clap.defaults;
            const core_params = comptime blk: {
                var res: [clap.params.len]core.Param(usize) = undefined;

                for (clap.params) |p, i| {
                    res[i] = core.Param(usize) {
                        .id = i,
                        .command = null,
                        .short = p.short,
                        .long = p.long,
                        .takes_value = p.takes_value != null,
                    };
                }

                break :blk res;
            };

            var handled = comptime blk: {
                var res: [clap.params.len]bool = undefined;
                for (clap.params) |p, i| {
                    res[i] = !p.required;
                }

                break :blk res;
            };

            var pos: usize = 0;
            var iter = core.Iterator(usize).init(core_params, arg_iter, allocator);
            defer iter.deinit();

            arg_loop:
            while (try iter.next()) |arg| : (pos += 1) {
                inline for(clap.params) |param, i| {
                    if (arg.id == i and (param.position ?? pos) == pos) {
                        if (param.takes_value) |parser| {
                            try parser.parse(getFieldPtr(&result, param.field), ??arg.value);
                        } else {
                            *getFieldPtr(&result, param.field) = true;
                        }
                        handled[i] = true;
                        continue :arg_loop;
                    }
                }

                return error.InvalidArgument;
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
    var arg_iter = core.ArgSliceIterator.init(args);
    const actual = clap.parse(debug.global_allocator, &arg_iter.iter) catch unreachable;
    assert(mem.eql(u8, expected.str, actual.str));
    assert(expected.int == actual.int);
    assert(expected.uint == actual.uint);
    assert(expected.a == actual.a);
    assert(expected.b == actual.b);
    assert(expected.cc == actual.cc);
}

fn testErr(comptime clap: &const Clap(Options), args: []const []const u8, expected: error) void {
    var arg_iter = core.ArgSliceIterator.init(args);
    if (clap.parse(debug.global_allocator, &arg_iter.iter)) |actual| {
        unreachable;
    } else |err| {
        assert(err == expected);
    }
}

test "clap.core" {
    _ = core;
}

test "clap: short" {
    const clap = comptime Clap(Options) {
        .defaults = default,
        .params = []Param {
            Param.smart("a"),
            Param.smart("b"),
            Param.smart("int")
                .with("short", 'i')
                .with("takes_value", Parser.int(i64, 10))
        }
    };

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

test "clap: long" {
    const clap = comptime Clap(Options) {
        .defaults = default,
        .params = []Param {
            Param.smart("cc"),
            Param.smart("int").with("takes_value", Parser.int(i64, 10)),
            Param.smart("uint").with("takes_value", Parser.int(u64, 10)),
            Param.smart("str").with("takes_value", Parser.string),
        }
    };

    testNoErr(clap, [][]const u8 { "--cc" },         default.with("cc",  true));
    testNoErr(clap, [][]const u8 { "--int", "100" }, default.with("int",  100));
}

test "clap: value bool" {
    const clap = comptime Clap(Options) {
        .defaults = default,
        .params = []Param {
            Param.smart("a"),
        }
    };

    testNoErr(clap, [][]const u8 { "-a" }, default.with("a",  true));
}

test "clap: value str" {
    const clap = comptime Clap(Options) {
        .defaults = default,
        .params = []Param {
            Param.smart("str").with("takes_value", Parser.string),
        }
    };

    testNoErr(clap, [][]const u8 { "--str", "Hello World!" }, default.with("str", "Hello World!"));
}

test "clap: value int" {
    const clap = comptime Clap(Options) {
        .defaults = default,
        .params = []Param {
            Param.smart("int").with("takes_value", Parser.int(i64, 10)),
        }
    };

    testNoErr(clap, [][]const u8 { "--int", "100" }, default.with("int", 100));
}

test "clap: position" {
    const clap = comptime Clap(Options) {
        .defaults = default,
        .params = []Param {
            Param.smart("a").with("position", 0),
            Param.smart("b").with("position", 1),
        }
    };

    testNoErr(clap, [][]const u8 { "-a", "-b" }, default.with("a", true).with("b", true));
    testErr(clap, [][]const u8 { "-b", "-a" }, error.InvalidArgument);
}

test "clap: sub fields" {
    const B = struct {
        a: bool,
    };
    const A = struct {
        b: B,
    };

    const clap = comptime Clap(A) {
        .defaults = A { .b = B { .a = false } },
        .params = []Param {
            Param.short('a')
                .with("field", "b.a"),
        }
    };

    var arg_iter = core.ArgSliceIterator.init([][]const u8{ "-a" });
    const res = clap.parse(debug.global_allocator, &arg_iter.iter) catch unreachable;
    debug.assert(res.b.a == true);
}
