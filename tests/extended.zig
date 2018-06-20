const std = @import("std");
const clap = @import("../index.zig");

const debug = std.debug;
const mem = std.mem;
const core = clap.core;
const extended = clap.extended;

const assert = debug.assert;

const ArgSliceIterator = core.ArgSliceIterator;
const Names = core.Names;
const Clap = extended.Clap;
const Param = extended.Param;
const Parser = extended.Parser;

pub fn Test(comptime Expect: type) type {
    return struct {
        const Self = this;

        args: []const []const u8,
        kind: Kind,

        const Kind = union(enum) {
            Success: Expect,
            Fail: error,
        };

        pub fn success(args: []const []const u8, expected: Expect) Self {
            return Self{
                .args = args,
                .kind = Kind{ .Success = expected },
            };
        }

        pub fn fail(args: []const []const u8, err: error) Self {
            return Self{
                .args = args,
                .kind = Kind{ .Fail = err },
            };
        }

        pub fn run(t: Self, comptime parser: var) void {
            var iter = ArgSliceIterator.init(t.args);
            const actual = parser.parse(ArgSliceIterator.Error, &iter.iter);

            switch (t.kind) {
                Kind.Success => |expected| {
                    const actual_value = actual catch unreachable;
                    inline for (@typeInfo(Expect).Struct.fields) |field| {
                        assert(@field(expected, field.name) == @field(actual_value, field.name));
                    }
                },
                Kind.Fail => |expected| {
                    if (actual) |_| {
                        unreachable;
                    } else |actual_err| {
                        assert(actual_err == expected);
                    }
                },
            }
        }
    };
}

test "clap.extended: short" {
    const S = struct {
        a: bool,
        b: u8,
    };

    const parser = comptime Clap(S){
        .default = S{
            .a = false,
            .b = 0,
        },
        .params = []Param{
            p: {
                var res = Param.flag("a", Names.short('a'));
                res.required = true;
                res.position = 0;
                break :p res;
            },
            Param.option("b", Names.short('b'), Parser.int(u8, 10)),
        },
    };

    const T = Test(S);
    const tests = []T{
        T.success(
            [][]const u8{"-a"},
            S{
                .a = true,
                .b = 0,
            },
        ),
        T.success(
            [][]const u8{ "-a", "-b", "100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.success(
            [][]const u8{ "-a", "-b=100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.success(
            [][]const u8{ "-a", "-b100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.success(
            [][]const u8{ "-ab", "100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.success(
            [][]const u8{"-ab=100"},
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.success(
            [][]const u8{"-ab100"},
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.fail(
            [][]const u8{"-q"},
            error.InvalidArgument,
        ),
        T.fail(
            [][]const u8{"--a"},
            error.InvalidArgument,
        ),
        T.fail(
            [][]const u8{"-b=100"},
            error.ParamNotHandled,
        ),
        T.fail(
            [][]const u8{ "-b=100", "-a" },
            error.InvalidArgument,
        ),
    };

    for (tests) |t| {
        t.run(parser);
    }
}

test "clap.extended: long" {
    const S = struct {
        a: bool,
        b: u8,
    };

    const parser = comptime Clap(S){
        .default = S{
            .a = false,
            .b = 0,
        },
        .params = []Param{
            p: {
                var res = Param.flag("a", Names.long("a"));
                res.required = true;
                res.position = 0;
                break :p res;
            },
            Param.option("b", Names.long("b"), Parser.int(u8, 10)),
        },
    };

    const T = Test(S);
    const tests = []T{
        T.success(
            [][]const u8{"--a"},
            S{
                .a = true,
                .b = 0,
            },
        ),
        T.success(
            [][]const u8{ "--a", "--b", "100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.success(
            [][]const u8{ "--a", "--b=100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.fail(
            [][]const u8{"--a=100"},
            error.DoesntTakeValue,
        ),
        T.fail(
            [][]const u8{"--q"},
            error.InvalidArgument,
        ),
        T.fail(
            [][]const u8{"-a"},
            error.InvalidArgument,
        ),
        T.fail(
            [][]const u8{"--b=100"},
            error.ParamNotHandled,
        ),
        T.fail(
            [][]const u8{ "--b=100", "--a" },
            error.InvalidArgument,
        ),
    };

    for (tests) |t| {
        t.run(parser);
    }
}

test "clap.extended: bare" {
    const S = struct {
        a: bool,
        b: u8,
    };

    const parser = comptime Clap(S){
        .default = S{
            .a = false,
            .b = 0,
        },
        .params = []Param{
            p: {
                var res = Param.flag("a", Names.bare("a"));
                res.required = true;
                res.position = 0;
                break :p res;
            },
            Param.option("b", Names.bare("b"), Parser.int(u8, 10)),
        },
    };

    const T = Test(S);
    const tests = []T{
        T.success(
            [][]const u8{"a"},
            S{
                .a = true,
                .b = 0,
            },
        ),
        T.success(
            [][]const u8{ "a", "b", "100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.success(
            [][]const u8{ "a", "b=100" },
            S{
                .a = true,
                .b = 100,
            },
        ),
        T.fail(
            [][]const u8{"a=100"},
            error.DoesntTakeValue,
        ),
        T.fail(
            [][]const u8{"--a"},
            error.InvalidArgument,
        ),
        T.fail(
            [][]const u8{"-a"},
            error.InvalidArgument,
        ),
        T.fail(
            [][]const u8{"b=100"},
            error.ParamNotHandled,
        ),
        T.fail(
            [][]const u8{ "b=100", "--a" },
            error.InvalidArgument,
        ),
    };

    for (tests) |t| {
        t.run(parser);
    }
}

// TODO: Test sub commands and sub field access
