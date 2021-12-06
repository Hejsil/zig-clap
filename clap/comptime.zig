const clap = @import("../clap.zig");
const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

/// Deprecated: Use `parseEx` instead
pub fn ComptimeClap(
    comptime Id: type,
    comptime params: []const clap.Param(Id),
) type {
    comptime var flags: usize = 0;
    comptime var single_options: usize = 0;
    comptime var multi_options: usize = 0;
    comptime var converted_params: []const clap.Param(usize) = &.{};
    for (params) |param| {
        var index: usize = 0;
        if (param.names.long != null or param.names.short != null) {
            const ptr = switch (param.takes_value) {
                .none => &flags,
                .one => &single_options,
                .many => &multi_options,
            };
            index = ptr.*;
            ptr.* += 1;
        }

        converted_params = converted_params ++ [_]clap.Param(usize){.{
            .id = index,
            .names = param.names,
            .takes_value = param.takes_value,
        }};
    }

    return struct {
        multi_options: [multi_options][]const []const u8,
        single_options: [single_options][]const u8,
        single_options_is_set: std.PackedIntArray(u1, single_options),
        flags: std.PackedIntArray(u1, flags),
        pos: []const []const u8,
        allocator: mem.Allocator,

        pub fn parse(iter: anytype, opt: clap.ParseOptions) !@This() {
            const allocator = opt.allocator;
            var multis = [_]std.ArrayList([]const u8){undefined} ** multi_options;
            for (multis) |*multi|
                multi.* = std.ArrayList([]const u8).init(allocator);

            var pos = std.ArrayList([]const u8).init(allocator);

            var res = @This(){
                .multi_options = .{undefined} ** multi_options,
                .single_options = .{undefined} ** single_options,
                .single_options_is_set = std.PackedIntArray(u1, single_options).init(
                    .{0} ** single_options,
                ),
                .flags = std.PackedIntArray(u1, flags).init(.{0} ** flags),
                .pos = undefined,
                .allocator = allocator,
            };

            var stream = clap.StreamingClap(usize, @typeInfo(@TypeOf(iter)).Pointer.child){
                .params = converted_params,
                .iter = iter,
                .diagnostic = opt.diagnostic,
            };
            while (try stream.next()) |arg| {
                const param = arg.param;
                if (param.names.long == null and param.names.short == null) {
                    try pos.append(arg.value.?);
                } else if (param.takes_value == .one) {
                    debug.assert(res.single_options.len != 0);
                    if (res.single_options.len != 0) {
                        res.single_options[param.id] = arg.value.?;
                        res.single_options_is_set.set(param.id, 1);
                    }
                } else if (param.takes_value == .many) {
                    debug.assert(multis.len != 0);
                    if (multis.len != 0)
                        try multis[param.id].append(arg.value.?);
                } else {
                    debug.assert(res.flags.len != 0);
                    if (res.flags.len != 0)
                        res.flags.set(param.id, 1);
                }
            }

            for (multis) |*multi, i|
                res.multi_options[i] = multi.toOwnedSlice();
            res.pos = pos.toOwnedSlice();

            return res;
        }

        pub fn deinit(parser: @This()) void {
            for (parser.multi_options) |o|
                parser.allocator.free(o);
            parser.allocator.free(parser.pos);
        }

        pub fn flag(parser: @This(), comptime name: []const u8) bool {
            const param = comptime findParam(name);
            if (param.takes_value != .none)
                @compileError(name ++ " is an option and not a flag.");

            return parser.flags.get(param.id) != 0;
        }

        pub fn option(parser: @This(), comptime name: []const u8) ?[]const u8 {
            const param = comptime findParam(name);
            if (param.takes_value == .none)
                @compileError(name ++ " is a flag and not an option.");
            if (param.takes_value == .many)
                @compileError(name ++ " takes many options, not one.");
            if (parser.single_options_is_set.get(param.id) == 0)
                return null;
            return parser.single_options[param.id];
        }

        pub fn options(parser: @This(), comptime name: []const u8) []const []const u8 {
            const param = comptime findParam(name);
            if (param.takes_value == .none)
                @compileError(name ++ " is a flag and not an option.");
            if (param.takes_value == .one)
                @compileError(name ++ " takes one option, not multiple.");

            return parser.multi_options[param.id];
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

test "" {
    const params = comptime &.{
        clap.parseParam("-a, --aa") catch unreachable,
        clap.parseParam("-b, --bb") catch unreachable,
        clap.parseParam("-c, --cc <V>") catch unreachable,
        clap.parseParam("-d, --dd <V>...") catch unreachable,
        clap.parseParam("<P>") catch unreachable,
    };

    var iter = clap.args.SliceIterator{
        .args = &.{
            "-a", "-c", "0", "something", "-d", "a", "--dd", "b",
        },
    };
    var args = try clap.parseEx(clap.Help, params, &iter, .{ .allocator = testing.allocator });
    defer args.deinit();

    try testing.expect(args.flag("-a"));
    try testing.expect(args.flag("--aa"));
    try testing.expect(!args.flag("-b"));
    try testing.expect(!args.flag("--bb"));
    try testing.expectEqualStrings("0", args.option("-c").?);
    try testing.expectEqualStrings("0", args.option("--cc").?);
    try testing.expectEqual(@as(usize, 1), args.positionals().len);
    try testing.expectEqualStrings("something", args.positionals()[0]);
    try testing.expectEqualSlices([]const u8, &.{ "a", "b" }, args.options("-d"));
    try testing.expectEqualSlices([]const u8, &.{ "a", "b" }, args.options("--dd"));
}

test "empty" {
    var iter = clap.args.SliceIterator{ .args = &.{} };
    var args = try clap.parseEx(u8, &.{}, &iter, .{ .allocator = testing.allocator });
    defer args.deinit();
}

fn testErr(
    comptime params: []const clap.Param(u8),
    args_strings: []const []const u8,
    expected: []const u8,
) !void {
    var diag = clap.Diagnostic{};
    var iter = clap.args.SliceIterator{ .args = args_strings };
    _ = clap.parseEx(u8, params, &iter, .{
        .allocator = testing.allocator,
        .diagnostic = &diag,
    }) catch |err| {
        var buf: [1024]u8 = undefined;
        var fbs = io.fixedBufferStream(&buf);
        diag.report(fbs.writer(), err) catch return error.TestFailed;
        try testing.expectEqualStrings(expected, fbs.getWritten());
        return;
    };

    try testing.expect(false);
}

test "errors" {
    const params = [_]clap.Param(u8){
        .{
            .id = 0,
            .names = .{ .short = 'a', .long = "aa" },
        },
        .{
            .id = 1,
            .names = .{ .short = 'c', .long = "cc" },
            .takes_value = .one,
        },
    };

    try testErr(&params, &.{"q"}, "Invalid argument 'q'\n");
    try testErr(&params, &.{"-q"}, "Invalid argument '-q'\n");
    try testErr(&params, &.{"--q"}, "Invalid argument '--q'\n");
    try testErr(&params, &.{"--q=1"}, "Invalid argument '--q'\n");
    try testErr(&params, &.{"-a=1"}, "The argument '-a' does not take a value\n");
    try testErr(&params, &.{"--aa=1"}, "The argument '--aa' does not take a value\n");
    try testErr(&params, &.{"-c"}, "The argument '-c' requires a value but none was supplied\n");
    try testErr(
        &params,
        &.{"--cc"},
        "The argument '--cc' requires a value but none was supplied\n",
    );
}
