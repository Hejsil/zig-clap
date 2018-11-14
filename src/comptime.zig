const clap = @import("index.zig");
const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const mem = std.mem;

pub fn ComptimeClap(comptime Id: type, comptime params: []const clap.Param(Id)) type {
    var flags: usize = 0;
    var options: usize = 0;
    var converted_params: []const clap.Param(usize) = []clap.Param(usize){};
    for (params) |param| {
        const index = blk: {
            if (param.names.long == null and param.names.short == null)
                break :blk 0;
            if (param.takes_value) {
                const res = options;
                options += 1;
                break :blk res;
            }

            const res = flags;
            flags += 1;
            break :blk res;
        };

        const converted = clap.Param(usize).init(index, param.takes_value, param.names);
        converted_params = converted_params ++ []clap.Param(usize){converted};
    }

    return struct {
        options: [options]?[]const u8,
        flags: [flags]bool,
        pos: []const []const u8,
        allocator: *mem.Allocator,

        pub fn parse(allocator: *mem.Allocator, comptime ArgError: type, iter: *clap.args.Iterator(ArgError)) !@This() {
            var pos = std.ArrayList([]const u8).init(allocator);
            var res = @This(){
                .options = []?[]const u8{null} ** options,
                .flags = []bool{false} ** flags,
                .pos = undefined,
                .allocator = allocator,
            };

            var stream = clap.StreamingClap(usize, ArgError).init(converted_params, iter);
            while (try stream.next()) |arg| {
                const param = arg.param;
                if (param.names.long == null and param.names.short == null) {
                    try pos.append(arg.value.?);
                } else if (param.takes_value) {
                    // We slice before access to avoid false positive access out of bound
                    // compile error.
                    res.options[0..][param.id] = arg.value.?;
                } else {
                    res.flags[0..][param.id] = true;
                }
            }

            res.pos = pos.toOwnedSlice();
            return res;
        }

        pub fn deinit(parser: *@This()) void {
            parser.allocator.free(parser.pos);
            parser.* = undefined;
        }

        pub fn flag(parser: @This(), comptime name: []const u8) bool {
            const param = comptime findParam(name);
            if (param.takes_value)
                @compileError(name ++ " is an option and not a flag.");

            return parser.flags[param.id];
        }

        pub fn option(parser: @This(), comptime name: []const u8) ?[]const u8 {
            const param = comptime findParam(name);
            if (!param.takes_value)
                @compileError(name ++ " is a flag and not an option.");

            return parser.options[param.id];
        }

        pub fn positionals(parser: @This()) []const []const u8 {
            return parser.pos;
        }

        fn findParam(comptime name: []const u8) clap.Param(usize) {
            comptime {
                for (converted_params) |param| {
                    if (param.names.short) |s| {
                        if (mem.eql(u8, name, "-" ++ []u8{s}))
                            return param;
                    }
                    if (param.names.long) |l| {
                        if (mem.eql(u8, name, "--" ++ l))
                            return param;
                    }
                }

                @compileError(name ++ " is not a parameter.");
            }
        }
    };
}

test "clap.comptime.ComptimeClap" {
    const Clap = ComptimeClap(void, comptime []clap.Param(void){
        clap.Param(void).flag({}, clap.Names{
            .short = 'a',
            .long = "aa",
        }),
        clap.Param(void).flag({}, clap.Names{
            .short = 'b',
            .long = "bb",
        }),
        clap.Param(void).option({}, clap.Names{
            .short = 'c',
            .long = "cc",
        }),
        clap.Param(void).positional({}),
    });

    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);
    var arg_iter = clap.args.SliceIterator.init([][]const u8{
        "-a", "-c", "0", "something",
    });
    var args = try Clap.parse(&fb_allocator.allocator, clap.args.SliceIterator.Error, &arg_iter.iter);
    defer args.deinit();

    debug.assert(args.flag("-a"));
    debug.assert(args.flag("--aa"));
    debug.assert(!args.flag("-b"));
    debug.assert(!args.flag("--bb"));
    debug.assert(mem.eql(u8, args.option("-c").?, "0"));
    debug.assert(mem.eql(u8, args.option("--cc").?, "0"));
    debug.assert(args.positionals().len == 1);
    debug.assert(mem.eql(u8, args.positionals()[0], "something"));
}
