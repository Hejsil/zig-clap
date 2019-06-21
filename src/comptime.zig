const clap = @import("../clap.zig");
const std = @import("std");

const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const debug = std.debug;

pub fn ComptimeClap(comptime Id: type, comptime params: []const clap.Param(Id)) type {
    var flags: usize = 0;
    var options: usize = 0;
    var converted_params: []const clap.Param(usize) = [_]clap.Param(usize){};
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

        const converted = clap.Param(usize){
            .id = index,
            .names = param.names,
            .takes_value = param.takes_value,
        };
        converted_params = converted_params ++ [_]clap.Param(usize){converted};
    }

    return struct {
        options: [options]?[]const u8,
        flags: [flags]bool,
        pos: []const []const u8,
        allocator: *mem.Allocator,

        pub fn parse(allocator: *mem.Allocator, comptime ArgIter: type, iter: *ArgIter) !@This() {
            var pos = std.ArrayList([]const u8).init(allocator);
            var res = @This(){
                .options = [_]?[]const u8{null} ** options,
                .flags = [_]bool{false} ** flags,
                .pos = undefined,
                .allocator = allocator,
            };

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
                        res.options[param.id] = arg.value.?;
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
    const Clap = ComptimeClap(void, [_]clap.Param(void){
        clap.Param(void){
            .names = clap.Names{
                .short = 'a',
                .long = "aa",
            },
        },
        clap.Param(void){
            .names = clap.Names{
                .short = 'b',
                .long = "bb",
            },
        },
        clap.Param(void){
            .names = clap.Names{
                .short = 'c',
                .long = "cc",
            },
            .takes_value = true,
        },
        clap.Param(void){
            .takes_value = true,
        },
    });

    var buf: [1024]u8 = undefined;
    var fb_allocator = heap.FixedBufferAllocator.init(buf[0..]);
    var iter = clap.args.SliceIterator{
        .args = [_][]const u8{
            "-a", "-c", "0", "something",
        },
    };
    var args = try Clap.parse(&fb_allocator.allocator, clap.args.SliceIterator, &iter);
    defer args.deinit();

    testing.expect(args.flag("-a"));
    testing.expect(args.flag("--aa"));
    testing.expect(!args.flag("-b"));
    testing.expect(!args.flag("--bb"));
    testing.expectEqualSlices(u8, "0", args.option("-c").?);
    testing.expectEqualSlices(u8, "0", args.option("--cc").?);
    testing.expectEqual(usize(1), args.positionals().len);
    testing.expectEqualSlices(u8, "something", args.positionals()[0]);
}
