const std = @import("std");
const clap = @import("../index.zig");

const debug = std.debug;
const mem = std.mem;
const core = clap.core;

const assert = debug.assert;

const ArgSliceIterator = core.ArgSliceIterator;
const Names = core.Names;
const Param = core.Param;
const Clap = core.Clap;

fn testNoErr(params: []const Param(u8), args: []const []const u8, ids: []const u8, values: []const ?[]const u8) void {
    var arg_iter = ArgSliceIterator.init(args);
    var iter = Clap(u8, ArgSliceIterator.Error).init(params, &arg_iter.iter);

    var i: usize = 0;
    while (iter.next() catch unreachable) |arg| : (i += 1) {
        debug.assert(ids[i] == arg.param.id);
        const expected_value = values[i] ?? {
            debug.assert(arg.value == null);
            continue;
        };
        const actual_value = arg.value ?? unreachable;

        debug.assert(mem.eql(u8, expected_value, actual_value));
    }
}

test "clap.core: short" {
    const params = []Param(u8) {
        Param(u8).init(0, false, Names.short('a')),
        Param(u8).init(1, false, Names.short('b')),
        Param(u8).init(2, true,  Names.short('c')),
    };

    testNoErr(params, [][]const u8 { "-a" },          []u8{0},   []?[]const u8{null});
    testNoErr(params, [][]const u8 { "-a", "-b" },    []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-ab" },         []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-c=100" },      []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c100" },       []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c", "100" },   []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-abc", "100" }, []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc=100" },    []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc100" },     []u8{0,1,2}, []?[]const u8{null,null,"100"});
}

test "clap.core: long" {
    const params = []Param(u8) {
        Param(u8).init(0, false, Names.long("aa")),
        Param(u8).init(1, false, Names.long("bb")),
        Param(u8).init(2, true,  Names.long("cc")),
    };

    testNoErr(params, [][]const u8 { "--aa" },         []u8{0},   []?[]const u8{null});
    testNoErr(params, [][]const u8 { "--aa", "--bb" }, []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "--cc=100" },     []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "--cc", "100" },  []u8{2},   []?[]const u8{"100"});
}

test "clap.core: bare" {
    const params = []Param(u8) {
        Param(u8).init(0, false, Names.bare("aa")),
        Param(u8).init(1, false, Names.bare("bb")),
        Param(u8).init(2, true,  Names.bare("cc")),
    };

    testNoErr(params, [][]const u8 { "aa" },        []u8{0},   []?[]const u8{null});
    testNoErr(params, [][]const u8 { "aa", "bb" },  []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "cc=100" },    []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "cc", "100" }, []u8{2},   []?[]const u8{"100"});
}

test "clap.core: none" {
    const params = []Param(u8) {
        Param(u8).init(0, true, Names.none()),
    };

    testNoErr(params, [][]const u8 { "aa" }, []u8{0}, []?[]const u8{"aa"});
}

test "clap.core: all" {
    const params = []Param(u8) {
        Param(u8).init(
            0,
            false,
            Names{
                .bare = "aa",
                .short = 'a',
                .long = "aa",
            }
        ),
        Param(u8).init(
            1,
            false,
            Names{
                .bare = "bb",
                .short = 'b',
                .long = "bb",
            }
        ),
        Param(u8).init(
            2,
            true,
            Names{
                .bare = "cc",
                .short = 'c',
                .long = "cc",
            }
        ),
        Param(u8).init(3, true, Names.none()),
    };

    testNoErr(params, [][]const u8 { "-a" },           []u8{0},     []?[]const u8{null});
    testNoErr(params, [][]const u8 { "-a", "-b" },     []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-ab" },          []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-c=100" },       []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c100" },        []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c", "100" },    []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-abc", "100" },  []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc=100" },     []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc100" },      []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "--aa" },         []u8{0},     []?[]const u8{null});
    testNoErr(params, [][]const u8 { "--aa", "--bb" }, []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "--cc=100" },     []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "--cc", "100" },  []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "aa" },           []u8{0},     []?[]const u8{null});
    testNoErr(params, [][]const u8 { "aa", "bb" },     []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "cc=100" },       []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "cc", "100" },    []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "dd" },           []u8{3},     []?[]const u8{"dd"});
}
