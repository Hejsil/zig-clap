const std = @import("std");
const clap = @import("../index.zig");

const debug = std.debug;
const mem = std.mem;
const core = clap.core;
const extended = clap.extended;

const assert = debug.assert;

const ArgSliceIterator = core.ArgSliceIterator;
const Command = extended.Command;
const Param = extended.Param;
const Parser = extended.Parser;

const Options = struct {
    str: []const u8,
    int: i64,
    uint: u64,
    a: bool,
    b: bool,
    cc: bool,
    sub: &const SubOptions,

    pub fn with(op: &const Options, comptime field: []const u8, value: var) Options {
        var res = op.*;
        @field(res, field) = value;
        return res;
    }
};

const SubOptions = struct {
    a: bool,
    b: u64,
    qq: bool,

    pub fn with(op: &const SubOptions, comptime field: []const u8, value: var) SubOptions {
        var res = op.*;
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
    .sub = SubOptions{
        .a = false,
        .b = 0,
        .qq = false,
    },
};

fn testNoErr(comptime command: &const Command, args: []const []const u8, expected: &const command.Result) void {
    var arg_iter = ArgSliceIterator.init(args);
    const actual = command.parse(debug.global_allocator, &arg_iter.iter) catch unreachable;
    assert(mem.eql(u8, expected.str, actual.str));
    assert(expected.int == actual.int);
    assert(expected.uint == actual.uint);
    assert(expected.a == actual.a);
    assert(expected.b == actual.b);
    assert(expected.cc == actual.cc);
    assert(expected.sub.a == actual.sub.a);
    assert(expected.sub.b == actual.sub.b);
}

fn testErr(comptime command: &const Command, args: []const []const u8, expected: error) void {
    var arg_iter = ArgSliceIterator.init(args);
    if (command.parse(debug.global_allocator, &arg_iter.iter)) |actual| {
        unreachable;
    } else |err| {
        assert(err == expected);
    }
}

test "clap.extended: short" {
    const command = comptime Command.init(
        "",
        Options,
        default,
        []Param {
            Param.smart("a"),
            Param.smart("b"),
            Param.smart("int")
                .with("short", 'i')
                .with("takes_value", Parser.int(i64, 10)),
        },
        []Command{},
    );

    testNoErr(command, [][]const u8 { "-a" },       default.with("a", true));
    testNoErr(command, [][]const u8 { "-a", "-b" }, default.with("a", true).with("b",  true));
    testNoErr(command, [][]const u8 { "-i=100" },   default.with("int", 100));
    testNoErr(command, [][]const u8 { "-i100" },   default.with("int", 100));
    testNoErr(command, [][]const u8 { "-i", "100" },   default.with("int", 100));
    testNoErr(command, [][]const u8 { "-ab" },      default.with("a", true).with("b",  true));
    testNoErr(command, [][]const u8 { "-abi", "100" }, default.with("a", true).with("b", true).with("int",  100));
    testNoErr(command, [][]const u8 { "-abi=100" }, default.with("a", true).with("b", true).with("int",  100));
    testNoErr(command, [][]const u8 { "-abi100" }, default.with("a", true).with("b", true).with("int",  100));
}

test "clap.extended: long" {
    const command = comptime Command.init(
        "",
        Options,
        default,
        []Param {
            Param.smart("cc"),
            Param.smart("int").with("takes_value", Parser.int(i64, 10)),
            Param.smart("uint").with("takes_value", Parser.int(u64, 10)),
            Param.smart("str").with("takes_value", Parser.string),
        },
        []Command{},
    );

    testNoErr(command, [][]const u8 { "--cc" },         default.with("cc",  true));
    testNoErr(command, [][]const u8 { "--int", "100" }, default.with("int",  100));
}

test "clap.extended: value bool" {
    const command = comptime Command.init(
        "",
        Options,
        default,
        []Param {
            Param.smart("a"),
        },
        []Command{},
    );

    testNoErr(command, [][]const u8 { "-a" }, default.with("a",  true));
}

test "clap.extended: value str" {
    const command = comptime Command.init(
        "",
        Options,
        default,
        []Param {
            Param.smart("str").with("takes_value", Parser.string),
        },
        []Command{},
    );

    testNoErr(command, [][]const u8 { "--str", "Hello World!" }, default.with("str", "Hello World!"));
}

test "clap.extended: value int" {
    const command = comptime Command.init(
        "",
        Options,
        default,
        []Param {
            Param.smart("int").with("takes_value", Parser.int(i64, 10)),
        },
        []Command{},
    );

    testNoErr(command, [][]const u8 { "--int", "100" }, default.with("int", 100));
}

test "clap.extended: position" {
    const command = comptime Command.init(
        "",
        Options,
        default,
        []Param {
            Param.smart("a").with("position", 0),
            Param.smart("b").with("position", 1),
        },
        []Command{},
    );

    testNoErr(command, [][]const u8 { "-a", "-b" }, default.with("a", true).with("b", true));
    testErr(command, [][]const u8 { "-b", "-a" }, error.InvalidArgument);
}

test "clap.extended: sub fields" {
    const B = struct {
        a: bool,
    };
    const A = struct {
        b: B,
    };

    const command = comptime Command.init(
        "",
        A,
        A { .b = B { .a = false } },
        []Param {
            Param.short('a')
                .with("field", "b.a"),
        },
        []Command{},
    );

    var arg_iter = ArgSliceIterator.init([][]const u8{ "-a" });
    const res = command.parse(debug.global_allocator, &arg_iter.iter) catch unreachable;
    debug.assert(res.b.a == true);
}

test "clap.extended: sub commands" {
    const command = comptime Command.init(
        "",
        Options,
        default,
        []Param {
            Param.smart("a"),
            Param.smart("b"),
        },
        []Command{
            Command.init(
                "sub",
                SubOptions,
                default.sub,
                []Param {
                    Param.smart("a"),
                    Param.smart("b")
                        .with("takes_value", Parser.int(u64, 10)),
                },
                []Command{},
            ),
        },
    );

    testNoErr(command, [][]const u8 { "sub", "-a" }, default.with("sub", default.sub.with("a", true)));
    testNoErr(command, [][]const u8 { "sub", "-b", "100" }, default.with("sub", default.sub.with("b", 100)));
    testNoErr(command, [][]const u8 { "-a", "sub", "-a" }, default.with("a", true).with("sub", default.sub.with("a", true)));
    testErr(command, [][]const u8 { "-qq", "sub" }, error.InvalidArgument);
}
