const builtin = @import("builtin");
const clap = @import("../clap.zig");
const std = @import("std");

const args = clap.args;
const testing = std.testing;
const heap = std.heap;
const mem = std.mem;
const os = std.os;

/// The result returned from ::StreamingClap.next
pub fn Arg(comptime Id: type) type {
    return struct {
        const Self = @This();

        param: *const clap.Param(Id),
        value: ?[]const u8 = null,
    };
}

/// A command line argument parser which, given an ::ArgIterator, will parse arguments according
/// to the ::params. ::StreamingClap parses in an iterating manner, so you have to use a loop together with
/// ::StreamingClap.next to parse all the arguments of your program.
pub fn StreamingClap(comptime Id: type, comptime ArgIterator: type) type {
    return struct {
        const State = union(enum) {
            Normal,
            Chaining: Chaining,

            const Chaining = struct {
                arg: []const u8,
                index: usize,
            };
        };

        params: []const clap.Param(Id),
        iter: *ArgIterator,
        state: State = State.Normal,

        /// Get the next ::Arg that matches a ::Param.
        pub fn next(parser: *@This()) !?Arg(Id) {
            const ArgInfo = struct {
                const Kind = enum {
                    Long,
                    Short,
                    Positional,
                };

                arg: []const u8,
                kind: Kind,
            };

            switch (parser.state) {
                State.Normal => {
                    const full_arg = (try parser.iter.next()) orelse return null;
                    const arg_info = blk: {
                        var arg = full_arg;
                        var kind = ArgInfo.Kind.Positional;

                        if (mem.startsWith(u8, arg, "--")) {
                            arg = arg[2..];
                            kind = ArgInfo.Kind.Long;
                        } else if (mem.startsWith(u8, arg, "-")) {
                            arg = arg[1..];
                            kind = ArgInfo.Kind.Short;
                        }

                        // We allow long arguments to go without a name.
                        // This allows the user to use "--" for something important
                        if (kind != ArgInfo.Kind.Long and arg.len == 0)
                            return error.InvalidArgument;

                        break :blk ArgInfo{ .arg = arg, .kind = kind };
                    };

                    const arg = arg_info.arg;
                    const kind = arg_info.kind;
                    const eql_index = mem.indexOfScalar(u8, arg, '=');

                    switch (kind) {
                        ArgInfo.Kind.Long => {
                            for (parser.params) |*param| {
                                const match = param.names.long orelse continue;
                                const name = if (eql_index) |i| arg[0..i] else arg;
                                const maybe_value = if (eql_index) |i| arg[i + 1 ..] else null;

                                if (!mem.eql(u8, name, match))
                                    continue;
                                if (!param.takes_value) {
                                    if (maybe_value != null)
                                        return error.DoesntTakeValue;

                                    return Arg(Id){ .param = param };
                                }

                                const value = blk: {
                                    if (maybe_value) |v|
                                        break :blk v;

                                    break :blk (try parser.iter.next()) orelse return error.MissingValue;
                                };

                                return Arg(Id){ .param = param, .value = value };
                            }
                        },
                        ArgInfo.Kind.Short => {
                            return try parser.chainging(State.Chaining{
                                .arg = full_arg,
                                .index = (full_arg.len - arg.len),
                            });
                        },
                        ArgInfo.Kind.Positional => {
                            for (parser.params) |*param| {
                                if (param.names.long) |_|
                                    continue;
                                if (param.names.short) |_|
                                    continue;

                                return Arg(Id){ .param = param, .value = arg };
                            }
                        },
                    }

                    return error.InvalidArgument;
                },
                @TagType(State).Chaining => |state| return try parser.chainging(state),
            }
        }

        fn chainging(parser: *@This(), state: State.Chaining) !?Arg(Id) {
            const arg = state.arg;
            const index = state.index;
            const next_index = index + 1;

            for (parser.params) |*param| {
                const short = param.names.short orelse continue;
                if (short != arg[index])
                    continue;

                // Before we return, we have to set the new state of the clap
                defer {
                    if (arg.len <= next_index or param.takes_value) {
                        parser.state = State.Normal;
                    } else {
                        parser.state = State{
                            .Chaining = State.Chaining{
                                .arg = arg,
                                .index = next_index,
                            },
                        };
                    }
                }

                if (!param.takes_value)
                    return Arg(Id){ .param = param };

                if (arg.len <= next_index) {
                    const value = (try parser.iter.next()) orelse return error.MissingValue;
                    return Arg(Id){ .param = param, .value = value };
                }

                if (arg[next_index] == '=')
                    return Arg(Id){ .param = param, .value = arg[next_index + 1 ..] };

                return Arg(Id){ .param = param, .value = arg[next_index..] };
            }

            return error.InvalidArgument;
        }
    };
}

fn testNoErr(params: []const clap.Param(u8), args_strings: []const []const u8, results: []const Arg(u8)) void {
    var iter = args.SliceIterator{ .args = args_strings };
    var c = StreamingClap(u8, args.SliceIterator){
        .params = params,
        .iter = &iter
    };

    for (results) |res| {
        const arg = (c.next() catch unreachable) orelse unreachable;
        testing.expectEqual(res.param, arg.param);
        const expected_value = res.value orelse {
            testing.expectEqual(@typeOf(arg.value)(null), arg.value);
            continue;
        };
        const actual_value = arg.value orelse unreachable;
        testing.expectEqualSlices(u8, expected_value, actual_value);
    }

    if (c.next() catch @panic("")) |_| {
        @panic("");
    }
}

test "clap.streaming.StreamingClap: short params" {
    const params = [_]clap.Param(u8){
        clap.Param(u8){
            .id = 0,
            .names = clap.Names{ .short = 'a' },
        },
        clap.Param(u8){
            .id = 1,
            .names = clap.Names{ .short = 'b' },
        },
        clap.Param(u8){
            .id = 2,
            .names = clap.Names{ .short = 'c' },
            .takes_value = true,
        },
    };

    const a = &params[0];
    const b = &params[1];
    const c = &params[2];

    testNoErr(
        params,
        [_][]const u8{
            "-a", "-b", "-ab", "-ba",
            "-c", "0", "-c=0", "-ac",
            "0", "-ac=0",
        },
        [_]Arg(u8){
            Arg(u8){ .param = a },
            Arg(u8){ .param = b },
            Arg(u8){ .param = a },
            Arg(u8){ .param = b },
            Arg(u8){ .param = b },
            Arg(u8){ .param = a },
            Arg(u8){ .param = c, .value = "0" },
            Arg(u8){ .param = c, .value = "0" },
            Arg(u8){ .param = a },
            Arg(u8){ .param = c, .value = "0" },
            Arg(u8){ .param = a },
            Arg(u8){ .param = c, .value = "0" },
        },
    );
}

test "clap.streaming.StreamingClap: long params" {
    const params = [_]clap.Param(u8){
        clap.Param(u8){
            .id = 0,
            .names = clap.Names{ .long = "aa" },
        },
        clap.Param(u8){
            .id = 1,
            .names = clap.Names{ .long = "bb" },
        },
        clap.Param(u8){
            .id = 2,
            .names = clap.Names{ .long = "cc" },
            .takes_value = true,
        },
    };

    const aa = &params[0];
    const bb = &params[1];
    const cc = &params[2];

    testNoErr(
        params,
        [_][]const u8{
            "--aa", "--bb",
            "--cc", "0",
            "--cc=0",
        },
        [_]Arg(u8){
            Arg(u8){ .param = aa },
            Arg(u8){ .param = bb },
            Arg(u8){ .param = cc, .value = "0" },
            Arg(u8){ .param = cc, .value = "0" },
        },
    );
}

test "clap.streaming.StreamingClap: positional params" {
    const params = [_]clap.Param(u8){
        clap.Param(u8){
            .id = 0,
            .takes_value = true,
        },
    };

    testNoErr(
        params,
        [_][]const u8{ "aa", "bb" },
        [_]Arg(u8){
            Arg(u8){ .param = &params[0], .value = "aa" },
            Arg(u8){ .param = &params[0], .value = "bb" },
        },
    );
}

test "clap.streaming.StreamingClap: all params" {
    const params = [_]clap.Param(u8){
        clap.Param(u8){
            .id = 0,
            .names = clap.Names{
                .short = 'a',
                .long = "aa",
            },
        },
        clap.Param(u8){
            .id = 1,
            .names = clap.Names{
                .short = 'b',
                .long = "bb",
            },
        },
        clap.Param(u8){
            .id = 2,
            .names = clap.Names{
                .short = 'c',
                .long = "cc",
            },
            .takes_value = true,
        },
        clap.Param(u8){
            .id = 3,
            .takes_value = true,
        },
    };

    const aa = &params[0];
    const bb = &params[1];
    const cc = &params[2];
    const positional = &params[3];

    testNoErr(
        params,
        [_][]const u8{
            "-a", "-b", "-ab", "-ba",
            "-c", "0", "-c=0", "-ac",
            "0", "-ac=0", "--aa", "--bb",
            "--cc", "0", "--cc=0", "something",
        },
        [_]Arg(u8){
            Arg(u8){ .param = aa },
            Arg(u8){ .param = bb },
            Arg(u8){ .param = aa },
            Arg(u8){ .param = bb },
            Arg(u8){ .param = bb },
            Arg(u8){ .param = aa },
            Arg(u8){ .param = cc, .value = "0" },
            Arg(u8){ .param = cc, .value = "0" },
            Arg(u8){ .param = aa },
            Arg(u8){ .param = cc, .value = "0" },
            Arg(u8){ .param = aa },
            Arg(u8){ .param = cc, .value = "0" },
            Arg(u8){ .param = aa },
            Arg(u8){ .param = bb },
            Arg(u8){ .param = cc, .value = "0" },
            Arg(u8){ .param = cc, .value = "0" },
            Arg(u8){ .param = positional, .value = "something" },
        },
    );
}
