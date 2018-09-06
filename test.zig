const std = @import("std");
const clap = @import("clap.zig");

const debug = std.debug;
const mem = std.mem;

const assert = debug.assert;

const ArgSliceIterator = clap.ArgSliceIterator;
const Names = clap.Names;
const Param = clap.Param(u8);
const Clap = clap.Clap(u8, ArgSliceIterator.Error);
const Arg = clap.Arg(u8);
   
fn testNoErr(params: []const Param, args: []const []const u8, results: []const Arg) void {
    var arg_iter = ArgSliceIterator.init(args);
    var c = Clap.init(params, &arg_iter.iter);

    for (results) |res| {
        const arg = (c.next() catch unreachable) orelse unreachable;
        debug.assert(res.param == arg.param);
        const expected_value = res.value orelse {
            debug.assert(arg.value == null);
            continue;
        };
        const actual_value = arg.value orelse unreachable;
        debug.assert(mem.eql(u8, expected_value, actual_value));
    }
    
    if (c.next() catch unreachable) |_| {
        unreachable;
    }
}

test "clap: short" {
    const params = []Param{
        Param.init(0, false, Names.short('a')),
        Param.init(1, false, Names.short('b')),
        Param.init(2, true, Names.short('c')),
    };
    
    const a = &params[0];
    const b = &params[1];
    const c = &params[2];
    
    testNoErr(
        params,
        [][]const u8{
            "-a", "-b", "-ab", "-ba",
            "-c", "0", "-c=0",
            "-ac", "0", "-ac=0",
        },
        []const Arg{
            Arg.init(a, null),
            Arg.init(b, null),
            Arg.init(a, null),
            Arg.init(b, null),
            Arg.init(b, null),
            Arg.init(a, null),
            Arg.init(c, "0"),
            Arg.init(c, "0"),
            Arg.init(a, null),
            Arg.init(c, "0"),
            Arg.init(a, null),
            Arg.init(c, "0"),
        },
    );
}

test "clap: long" {
    const params = []Param{
        Param.init(0, false, Names.long("aa")),
        Param.init(1, false, Names.long("bb")),
        Param.init(2, true, Names.long("cc")),
    };
    
    const aa = &params[0];
    const bb = &params[1];
    const cc = &params[2];
    
    testNoErr(
        params,
        [][]const u8{
            "--aa", "--bb",
            "--cc", "0", "--cc=0",
        },
        []const Arg{
            Arg.init(aa, null),
            Arg.init(bb, null),
            Arg.init(cc, "0"),
            Arg.init(cc, "0"),
        },
    );
}

test "clap: bare" {
    const params = []Param{
        Param.init(0, false, Names.bare("aa")),
        Param.init(1, false, Names.bare("bb")),
        Param.init(2, true, Names.bare("cc")),
    };
    
    const aa = &params[0];
    const bb = &params[1];
    const cc = &params[2];
    
    testNoErr(
        params,
        [][]const u8{
            "aa", "bb",
            "cc", "0", "cc=0",
        },
        []const Arg{
            Arg.init(aa, null),
            Arg.init(bb, null),
            Arg.init(cc, "0"),
            Arg.init(cc, "0"),
        },
    );
}

test "clap: none" {
    const params = []Param{
        Param.init(0, true, Names.none()),
    };
    
    testNoErr(
        params,
        [][]const u8{"aa", "bb"},
        []const Arg{
            Arg.init(&params[0], "aa"),
            Arg.init(&params[0], "bb"),
        },
    );
}

test "clap: all" {
    const params = []Param{
        Param.init(0, false, Names{
            .bare = "aa",
            .short = 'a',
            .long = "aa",
        }),
        Param.init(1, false, Names{
            .bare = "bb",
            .short = 'b',
            .long = "bb",
        }),
        Param.init(2, true, Names{
            .bare = "cc",
            .short = 'c',
            .long = "cc",
        }),
        Param.init(3, true, Names.none()),
    };
    
    const aa = &params[0];
    const bb = &params[1];
    const cc = &params[2];
    const bare = &params[3];
    
    testNoErr(
        params,
        [][]const u8{
            "-a", "-b", "-ab", "-ba",
            "-c", "0", "-c=0",
            "-ac", "0", "-ac=0",
            "--aa", "--bb",
            "--cc", "0", "--cc=0",
            "aa", "bb",
            "cc", "0", "cc=0",
            "something",
        },
        []const Arg{
            Arg.init(aa, null),
            Arg.init(bb, null),
            Arg.init(aa, null),
            Arg.init(bb, null),
            Arg.init(bb, null),
            Arg.init(aa, null),
            Arg.init(cc, "0"),
            Arg.init(cc, "0"),
            Arg.init(aa, null),
            Arg.init(cc, "0"),
            Arg.init(aa, null),
            Arg.init(cc, "0"),
            Arg.init(aa, null),
            Arg.init(bb, null),
            Arg.init(cc, "0"),
            Arg.init(cc, "0"),
            Arg.init(aa, null),
            Arg.init(bb, null),
            Arg.init(cc, "0"),
            Arg.init(cc, "0"),
            Arg.init(bare, "something"),
        },
    );
}
