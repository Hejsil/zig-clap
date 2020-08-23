const clap = @import("../clap.zig");
const std = @import("std");

const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const debug = std.debug;

pub fn ComptimeClap(comptime Id: type, comptime params: []const clap.Param(Id)) type {
    var flags: usize = 0;
    var options: usize = 0;
    var converted_params: []const clap.Param(usize) = &[_]clap.Param(usize){};
    for (params) |param| {
        var index: usize = 0;
        if (param.names.long != null or param.names.short != null) {
            const ptr = if (param.takes_value) &options else &flags;
            index = ptr.*;
            ptr.* += 1;
        }

        const converted = clap.Param(usize){
            .id = index,
            .names = param.names,
            .takes_value = param.takes_value,
        };
        converted_params = converted_params ++ [_]clap.Param(usize){converted};
    }

    return struct {
        options: [options]std.ArrayList([]const u8),
        flags: [flags]bool,
        pos: []const []const u8,
        allocator: *mem.Allocator,

        pub fn parse(allocator: *mem.Allocator, comptime ArgIter: type, iter: *ArgIter) !@This() {
            var pos = std.ArrayList([]const u8).init(allocator);
            var res = @This(){
                .options = [_]std.ArrayList([]const u8){undefined} ** options,
                .flags = [_]bool{false} ** flags,
                .pos = undefined,
                .allocator = allocator,
            };
            for (res.options) |*init_opt| {
                init_opt.* = std.ArrayList([]const u8).init(allocator);
            }

            var stream = clap.StreamingClap(usize, ArgIter){
                .params = converted_params,
                .iter = iter,
            };
            while (try stream.next()) |arg| {
                const param = arg.param;
                if (param.names.long == null and param.names.short == null) {
                    try pos.append(arg.value.?);
                } else if (param.takes_value) {
                    // If we don't have any optional parameters, then this code should
                    // never be reached.
                    debug.assert(res.options.len != 0);

                    // Hack: Utilize Zigs lazy analyzis to avoid a compiler error
                    if (res.options.len != 0)
                        try res.options[param.id].append(arg.value.?);
                } else {
                    debug.assert(res.flags.len != 0);
                    if (res.flags.len != 0)
                        res.flags[param.id] = true;
                }
            }

            res.pos = pos.toOwnedSlice();
            return res;
        }

        pub fn deinit(parser: *@This()) void {
            for (parser.options) |o|
                o.deinit();
            parser.allocator.free(parser.pos);
            parser.* = undefined;
        }

        pub fn flag(parser: @This(), comptime name: []const u8) bool {
            const param = comptime findParam(name);
            if (param.takes_value)
                @compileError(name ++ " is an option and not a flag.");

            return parser.flags[param.id];
        }

        pub fn allOptions(parser: @This(), comptime name: []const u8) [][]const u8 {
            const param = comptime findParam(name);
            if (!param.takes_value)
                @compileError(name ++ " is a flag and not an option.");

            return parser.options[param.id].items;
        }

        pub fn option(parser: @This(), comptime name: []const u8) ?[]const u8 {
            const items = parser.allOptions(name);
            return if (items.len > 0) items[0] else null;
        }

        pub fn positionals(parser: @This()) []const []const u8 {
            return parser.pos;
        }

        fn findParam(comptime name: []const u8) clap.Param(usize) {
            comptime {
                for (converted_params) |param| {
                    if (param.names.short) |s| {
                        if (mem.eql(u8, name, "-" ++ [_]u8{s}))
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
    const Clap = ComptimeClap(clap.Help, comptime &[_]clap.Param(clap.Help){
        clap.parseParam("-a, --aa    ") catch unreachable,
        clap.parseParam("-b, --bb    ") catch unreachable,
        clap.parseParam("-c, --cc <V>") catch unreachable,
        clap.parseParam("-d, --dd <V>") catch unreachable,
        clap.Param(clap.Help){
            .takes_value = true,
        },
    });

    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);
    var iter = clap.args.SliceIterator{
        .args = &[_][]const u8{
            "-a", "-c", "0", "something", "-d", "a", "--dd", "b",
        },
    };
    var args = try Clap.parse(&fb_allocator.allocator, clap.args.SliceIterator, &iter);
    defer args.deinit();

    testing.expect(args.flag("-a"));
    testing.expect(args.flag("--aa"));
    testing.expect(!args.flag("-b"));
    testing.expect(!args.flag("--bb"));
    testing.expectEqualStrings("0", args.option("-c").?);
    testing.expectEqualStrings("0", args.option("--cc").?);
    testing.expectEqual(@as(usize, 1), args.positionals().len);
    testing.expectEqualStrings("something", args.positionals()[0]);
    testing.expectEqualStrings("a", args.option("-d").?);
    testing.expectEqualSlices([]const u8, &[_][]const u8{ "a", "b" }, args.allOptions("--dd"));
}
