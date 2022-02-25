const clap = @import("../clap.zig");
const std = @import("std");

const builtin = std.builtin;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const process = std.process;
const testing = std.testing;

/// Same as `parseEx` but uses the `args.OsIterator` by default.
pub fn parse(
    comptime Id: type,
    comptime params: []const clap.Param(Id),
    opt: clap.ParseOptions,
) !Result(Arguments(Id, params, []const []const u8, &[_][]const u8{})) {
    var arena = heap.ArenaAllocator.init(opt.allocator);
    errdefer arena.deinit();

    var iter = try process.ArgIterator.initWithAllocator(arena.allocator());
    const exe_arg = iter.next();

    const result = try parseEx(Id, params, &iter, .{
        // Let's reuse the arena from the `OSIterator` since we already have it.
        .allocator = arena.allocator(),
        .diagnostic = opt.diagnostic,
    });

    return Result(Arguments(Id, params, []const []const u8, &.{})){
        .args = result.args,
        .positionals = result.positionals,
        .exe_arg = exe_arg,
        .arena = arena,
    };
}

pub fn Result(comptime Args: type) type {
    return struct {
        args: Args,
        positionals: []const []const u8,
        exe_arg: ?[]const u8,
        arena: std.heap.ArenaAllocator,

        pub fn deinit(result: @This()) void {
            result.arena.deinit();
        }
    };
}

/// Parses the command line arguments passed into the program based on an
/// array of `Param`s.
pub fn parseEx(
    comptime Id: type,
    comptime params: []const clap.Param(Id),
    iter: anytype,
    opt: clap.ParseOptions,
) !ResultEx(Arguments(Id, params, []const []const u8, &.{})) {
    const allocator = opt.allocator;
    var positionals = std.ArrayList([]const u8).init(allocator);
    var args = Arguments(Id, params, std.ArrayListUnmanaged([]const u8), .{}){};
    errdefer deinitArgs(allocator, &args);

    var stream = clap.streaming.Clap(Id, @typeInfo(@TypeOf(iter)).Pointer.child){
        .params = params,
        .iter = iter,
        .diagnostic = opt.diagnostic,
    };
    while (try stream.next()) |arg| {
        inline for (params) |*param| {
            if (param == arg.param) {
                const longest = comptime param.names.longest();
                switch (longest.kind) {
                    .short, .long => switch (param.takes_value) {
                        .none => @field(args, longest.name) = true,
                        .one => @field(args, longest.name) = arg.value.?,
                        .many => try @field(args, longest.name).append(allocator, arg.value.?),
                    },
                    .positinal => try positionals.append(arg.value.?),
                }
            }
        }
    }

    var result_args = Arguments(Id, params, []const []const u8, &.{}){};
    inline for (@typeInfo(@TypeOf(args)).Struct.fields) |field| {
        if (field.field_type == std.ArrayListUnmanaged([]const u8)) {
            const slice = @field(args, field.name).toOwnedSlice(allocator);
            @field(result_args, field.name) = slice;
        } else {
            @field(result_args, field.name) = @field(args, field.name);
        }
    }

    return ResultEx(@TypeOf(result_args)){
        .args = result_args,
        .positionals = positionals.toOwnedSlice(),
        .allocator = allocator,
    };
}

pub fn ResultEx(comptime Args: type) type {
    return struct {
        args: Args,
        positionals: []const []const u8,
        allocator: mem.Allocator,

        pub fn deinit(result: *@This()) void {
            deinitArgs(result.allocator, &result.args);
            result.allocator.free(result.positionals);
        }
    };
}

fn deinitArgs(allocator: mem.Allocator, args: anytype) void {
    const Args = @TypeOf(args.*);
    inline for (@typeInfo(Args).Struct.fields) |field| {
        if (field.field_type == []const []const u8)
            allocator.free(@field(args, field.name));
        if (field.field_type == std.ArrayListUnmanaged([]const u8))
            @field(args, field.name).deinit(allocator);
    }
}

fn Arguments(
    comptime Id: type,
    comptime params: []const clap.Param(Id),
    comptime MultiArgsType: type,
    comptime multi_args_default: MultiArgsType,
) type {
    var fields: [params.len]builtin.TypeInfo.StructField = undefined;

    var i: usize = 0;
    for (params) |param| {
        const longest = param.names.longest();
        if (longest.kind == .positinal)
            continue;

        const field_type = switch (param.takes_value) {
            .none => bool,
            .one => ?[]const u8,
            .many => MultiArgsType,
        };
        fields[i] = .{
            .name = longest.name,
            .field_type = field_type,
            .default_value = switch (param.takes_value) {
                .none => &false,
                .one => &@as(?[]const u8, null),
                .many => &multi_args_default,
            },
            .is_comptime = false,
            .alignment = @alignOf(field_type),
        };
        i += 1;
    }

    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = fields[0..i],
        .decls = &.{},
        .is_tuple = false,
    } });
}

test "" {
    const params = comptime &.{
        parseParam("-a, --aa") catch unreachable,
        parseParam("-b, --bb") catch unreachable,
        parseParam("-c, --cc <V>") catch unreachable,
        parseParam("-d, --dd <V>...") catch unreachable,
        parseParam("<P>") catch unreachable,
    };

    var iter = clap.args.SliceIterator{
        .args = &.{
            "-a", "-c", "0", "something", "-d", "a", "--dd", "b",
        },
    };
    var res = try clap.untyped.parseEx(clap.Help, params, &iter, .{
        .allocator = testing.allocator,
    });
    defer res.deinit();

    try testing.expect(res.args.aa);
    try testing.expect(!res.args.bb);
    try testing.expectEqualStrings("0", res.args.cc.?);
    try testing.expectEqual(@as(usize, 1), res.positionals.len);
    try testing.expectEqualStrings("something", res.positionals[0]);
    try testing.expectEqualSlices([]const u8, &.{ "a", "b" }, res.args.dd);
}

test "empty" {
    var iter = clap.args.SliceIterator{ .args = &.{} };
    var res = try clap.untyped.parseEx(u8, &.{}, &iter, .{ .allocator = testing.allocator });
    defer res.deinit();
}

fn testErr(
    comptime params: []const clap.Param(u8),
    args_strings: []const []const u8,
    expected: []const u8,
) !void {
    var diag = clap.Diagnostic{};
    var iter = clap.args.SliceIterator{ .args = args_strings };
    _ = clap.untyped.parseEx(u8, params, &iter, .{
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

/// Takes a string and parses it to a Param(clap.Help).
/// This is the reverse of 'help' but for at single parameter only.
pub fn parseParam(line: []const u8) !clap.Param(clap.Help) {
    // This function become a lot less ergonomic to use once you hit the eval branch quota. To
    // avoid this we pick a sane default. Sadly, the only sane default is the biggest possible
    // value. If we pick something a lot smaller and a user hits the quota after that, they have
    // no way of overriding it, since we set it here.
    // We can recosider this again if:
    // * We get parseParams: https://github.com/Hejsil/zig-clap/issues/39
    // * We get a larger default branch quota in the zig compiler (stage 2).
    // * Someone points out how this is a really bad idea.
    @setEvalBranchQuota(std.math.maxInt(u32));

    var found_comma = false;
    var it = mem.tokenize(u8, line, " \t");
    var param_str = it.next() orelse return error.NoParamFound;

    const short_name = if (!mem.startsWith(u8, param_str, "--") and
        mem.startsWith(u8, param_str, "-"))
    blk: {
        found_comma = param_str[param_str.len - 1] == ',';
        if (found_comma)
            param_str = param_str[0 .. param_str.len - 1];

        if (param_str.len != 2)
            return error.InvalidShortParam;

        const short_name = param_str[1];
        if (!found_comma) {
            var res = parseParamRest(it.rest());
            res.names.short = short_name;
            return res;
        }

        param_str = it.next() orelse return error.NoParamFound;
        break :blk short_name;
    } else null;

    const long_name = if (mem.startsWith(u8, param_str, "--")) blk: {
        if (param_str[param_str.len - 1] == ',')
            return error.TrailingComma;

        break :blk param_str[2..];
    } else if (found_comma) {
        return error.TrailingComma;
    } else if (short_name == null) {
        return parseParamRest(mem.trimLeft(u8, line, " \t"));
    } else null;

    var res = parseParamRest(it.rest());
    res.names.long = long_name;
    res.names.short = short_name;
    return res;
}

fn parseParamRest(line: []const u8) clap.Param(clap.Help) {
    if (mem.startsWith(u8, line, "<")) blk: {
        const len = mem.indexOfScalar(u8, line, '>') orelse break :blk;
        const takes_many = mem.startsWith(u8, line[len + 1 ..], "...");
        const help_start = len + 1 + @as(usize, 3) * @boolToInt(takes_many);
        return .{
            .takes_value = if (takes_many) .many else .one,
            .id = .{
                .msg = mem.trim(u8, line[help_start..], " \t"),
                .value = line[1..len],
            },
        };
    }

    return .{ .id = .{ .msg = mem.trim(u8, line, " \t") } };
}

fn expectParam(expect: clap.Param(clap.Help), actual: clap.Param(clap.Help)) !void {
    try testing.expectEqualStrings(expect.id.msg, actual.id.msg);
    try testing.expectEqualStrings(expect.id.value, actual.id.value);
    try testing.expectEqual(expect.names.short, actual.names.short);
    try testing.expectEqual(expect.takes_value, actual.takes_value);
    if (expect.names.long) |long| {
        try testing.expectEqualStrings(long, actual.names.long.?);
    } else {
        try testing.expectEqual(@as(?[]const u8, null), actual.names.long);
    }
}

test "parseParam" {
    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .short = 's', .long = "long" },
        .takes_value = .one,
    }, try parseParam("-s, --long <value> Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .short = 's', .long = "long" },
        .takes_value = .many,
    }, try parseParam("-s, --long <value>... Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .long = "long" },
        .takes_value = .one,
    }, try parseParam("--long <value> Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .short = 's' },
        .takes_value = .one,
    }, try parseParam("-s <value> Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text" },
        .names = .{ .short = 's', .long = "long" },
    }, try parseParam("-s, --long Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text" },
        .names = .{ .short = 's' },
    }, try parseParam("-s Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text" },
        .names = .{ .long = "long" },
    }, try parseParam("--long Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text", .value = "A | B" },
        .names = .{ .long = "long" },
        .takes_value = .one,
    }, try parseParam("--long <A | B> Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text", .value = "A" },
        .names = .{},
        .takes_value = .one,
    }, try parseParam("<A> Help text"));

    try expectParam(clap.Param(clap.Help){
        .id = .{ .msg = "Help text", .value = "A" },
        .names = .{},
        .takes_value = .many,
    }, try parseParam("<A>... Help text"));

    try testing.expectError(error.TrailingComma, parseParam("--long, Help"));
    try testing.expectError(error.TrailingComma, parseParam("-s, Help"));
    try testing.expectError(error.InvalidShortParam, parseParam("-ss Help"));
    try testing.expectError(error.InvalidShortParam, parseParam("-ss <value> Help"));
    try testing.expectError(error.InvalidShortParam, parseParam("- Help"));
}
