const std = @import("std");

const debug = std.debug;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

pub const args = @import("clap/args.zig");

test "clap" {
    _ = args;
    _ = ComptimeClap;
    _ = StreamingClap;
}

pub const ComptimeClap = @import("clap/comptime.zig").ComptimeClap;
pub const StreamingClap = @import("clap/streaming.zig").StreamingClap;

/// The names a ::Param can have.
pub const Names = struct {
    /// '-' prefix
    short: ?u8 = null,

    /// '--' prefix
    long: ?[]const u8 = null,
};

/// Represents a parameter for the command line.
/// Parameters come in three kinds:
///   * Short ("-a"): Should be used for the most commonly used parameters in your program.
///     * They can take a value three different ways.
///       * "-a value"
///       * "-a=value"
///       * "-avalue"
///     * They chain if they don't take values: "-abc".
///       * The last given parameter can take a value in the same way that a single parameter can:
///         * "-abc value"
///         * "-abc=value"
///         * "-abcvalue"
///   * Long ("--long-param"): Should be used for less common parameters, or when no single character
///                            can describe the paramter.
///     * They can take a value two different ways.
///       * "--long-param value"
///       * "--long-param=value"
///   * Positional: Should be used as the primary parameter of the program, like a filename or
///                 an expression to parse.
///     * Positional parameters have both names.long and names.short == null.
///     * Positional parameters must take a value.
pub fn Param(comptime Id: type) type {
    return struct {
        id: Id = Id{},
        names: Names = Names{},
        takes_value: bool = false,
    };
}

/// Takes a string and parses it to a Param(Help).
/// This is the reverse of 'help' but for at single parameter only.
pub fn parseParam(line: []const u8) !Param(Help) {
    var z: usize = 0;
    var res = Param(Help){
        .id = Help{
            // For testing, i want to be able to easily compare slices just by pointer,
            // so I slice by a runtime value here, so that zig does not optimize this
            // out. Maybe I should write the test better, geeh.
            .msg = line[z..z],
            .value = line[z..z],
        },
    };

    var it = mem.tokenize(line, " \t");
    var param_str = it.next() orelse return error.NoParamFound;
    if (!mem.startsWith(u8, param_str, "--") and mem.startsWith(u8, param_str, "-")) {
        const found_comma = param_str[param_str.len - 1] == ',';
        if (found_comma)
            param_str = param_str[0 .. param_str.len - 1];

        if (param_str.len != 2)
            return error.InvalidShortParam;

        res.names.short = param_str[1];
        if (!found_comma) {
            var help_msg = it.rest();
            if (it.next()) |next| blk: {
                if (mem.startsWith(u8, next, "<")) {
                    const start = mem.indexOfScalar(u8, help_msg, '<').? + 1;
                    const len = mem.indexOfScalar(u8, help_msg[start..], '>') orelse break :blk;
                    res.id.value = help_msg[start..][0..len];
                    res.takes_value = true;
                    help_msg = help_msg[start + len + 1 ..];
                }
            }

            res.id.msg = mem.trim(u8, help_msg, " \t");
            return res;
        }

        param_str = it.next() orelse return error.NoParamFound;
    }

    if (mem.startsWith(u8, param_str, "--")) {
        res.names.long = param_str[2..];

        if (param_str[param_str.len - 1] == ',')
            return error.TrailingComma;

        var help_msg = it.rest();
        if (it.next()) |next| blk: {
            if (mem.startsWith(u8, next, "<")) {
                const start = mem.indexOfScalar(u8, help_msg, '<').? + 1;
                const len = mem.indexOfScalar(u8, help_msg[start..], '>') orelse break :blk;
                res.id.value = help_msg[start..][0..len];
                res.takes_value = true;
                help_msg = help_msg[start + len + 1 ..];
            }
        }

        res.id.msg = mem.trim(u8, help_msg, " \t");
        return res;
    }

    return error.NoParamFound;
}

test "parseParam" {
    var z: usize = 0;
    var text: []const u8 = "-s, --long <value> Help text";
    testing.expectEqual(Param(Help){
        .id = Help{
            .msg = find(text, "Help text"),
            .value = find(text, "value"),
        },
        .names = Names{
            .short = 's',
            .long = find(text, "long"),
        },
        .takes_value = true,
    }, try parseParam(text));

    text = "--long <value> Help text";
    testing.expectEqual(Param(Help){
        .id = Help{
            .msg = find(text, "Help text"),
            .value = find(text, "value"),
        },
        .names = Names{
            .short = null,
            .long = find(text, "long"),
        },
        .takes_value = true,
    }, try parseParam(text));

    text = "-s <value> Help text";
    testing.expectEqual(Param(Help){
        .id = Help{
            .msg = find(text, "Help text"),
            .value = find(text, "value"),
        },
        .names = Names{
            .short = 's',
            .long = null,
        },
        .takes_value = true,
    }, try parseParam(text));

    text = "-s, --long Help text";
    testing.expectEqual(Param(Help){
        .id = Help{
            .msg = find(text, "Help text"),
            .value = text[z..z],
        },
        .names = Names{
            .short = 's',
            .long = find(text, "long"),
        },
        .takes_value = false,
    }, try parseParam(text));

    text = "-s Help text";
    testing.expectEqual(Param(Help){
        .id = Help{
            .msg = find(text, "Help text"),
            .value = text[z..z],
        },
        .names = Names{
            .short = 's',
            .long = null,
        },
        .takes_value = false,
    }, try parseParam(text));

    text = "--long Help text";
    testing.expectEqual(Param(Help){
        .id = Help{
            .msg = find(text, "Help text"),
            .value = text[z..z],
        },
        .names = Names{
            .short = null,
            .long = find(text, "long"),
        },
        .takes_value = false,
    }, try parseParam(text));

    text = "--long <A | B> Help text";
    testing.expectEqual(Param(Help){
        .id = Help{
            .msg = find(text, "Help text"),
            .value = find(text, "A | B"),
        },
        .names = Names{
            .short = null,
            .long = find(text, "long"),
        },
        .takes_value = true,
    }, try parseParam(text));

    testing.expectError(error.NoParamFound, parseParam("Help"));
    testing.expectError(error.TrailingComma, parseParam("--long, Help"));
    testing.expectError(error.NoParamFound, parseParam("-s, Help"));
    testing.expectError(error.InvalidShortParam, parseParam("-ss Help"));
    testing.expectError(error.InvalidShortParam, parseParam("-ss <value> Help"));
    testing.expectError(error.InvalidShortParam, parseParam("- Help"));
}

fn find(str: []const u8, f: []const u8) []const u8 {
    const i = mem.indexOf(u8, str, f).?;
    return str[i..][0..f.len];
}

pub fn Args(comptime Id: type, comptime params: []const Param(Id)) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        clap: ComptimeClap(Id, params),
        exe_arg: ?[]const u8,

        pub fn deinit(a: *@This()) void {
            a.clap.deinit();
            a.arena.deinit();
        }

        pub fn flag(a: @This(), comptime name: []const u8) bool {
            return a.clap.flag(name);
        }

        pub fn option(a: @This(), comptime name: []const u8) ?[]const u8 {
            return a.clap.option(name);
        }

        pub fn positionals(a: @This()) []const []const u8 {
            return a.clap.positionals();
        }
    };
}

/// Parses the command line arguments passed into the program based on an
/// array of `Param`s.
pub fn parse(
    comptime Id: type,
    comptime params: []const Param(Id),
    allocator: *mem.Allocator,
) !Args(Id, params) {
    var iter = try args.OsIterator.init(allocator);
    const clap = try ComptimeClap(Id, params).parse(allocator, args.OsIterator, &iter);
    return Args(Id, params){
        .arena = iter.arena,
        .clap = clap,
        .exe_arg = iter.exe_arg,
    };
}

/// Will print a help message in the following format:
///     -s, --long <valueText> helpText
///     -s,                    helpText
///     -s <valueText>         helpText
///         --long             helpText
///         --long <valueText> helpText
pub fn helpFull(
    stream: var,
    comptime Id: type,
    params: []const Param(Id),
    comptime Error: type,
    context: var,
    helpText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
    valueText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) !void {
    const max_spacing = blk: {
        var res: usize = 0;
        for (params) |param| {
            var counting_stream = io.countingOutStream(io.null_out_stream);
            try printParam(counting_stream.outStream(), Id, param, Error, context, valueText);
            if (res < counting_stream.bytes_written)
                res = @intCast(usize, counting_stream.bytes_written);
        }

        break :blk res;
    };

    for (params) |param| {
        if (param.names.short == null and param.names.long == null)
            continue;

        var counting_stream = io.countingOutStream(stream);
        try stream.print("\t", .{});
        try printParam(counting_stream.outStream(), Id, param, Error, context, valueText);
        try stream.writeByteNTimes(' ', max_spacing - @intCast(usize, counting_stream.bytes_written));
        try stream.print("\t{}\n", .{try helpText(context, param)});
    }
}

fn printParam(
    stream: var,
    comptime Id: type,
    param: Param(Id),
    comptime Error: type,
    context: var,
    valueText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) !void {
    if (param.names.short) |s| {
        try stream.print("-{c}", .{s});
    } else {
        try stream.print("  ", .{});
    }
    if (param.names.long) |l| {
        if (param.names.short) |_| {
            try stream.print(", ", .{});
        } else {
            try stream.print("  ", .{});
        }

        try stream.print("--{}", .{l});
    }
    if (param.takes_value)
        try stream.print(" <{}>", .{valueText(context, param)});
}

/// A wrapper around helpFull for simple helpText and valueText functions that
/// cant return an error or take a context.
pub fn helpEx(
    stream: var,
    comptime Id: type,
    params: []const Param(Id),
    helpText: fn (Param(Id)) []const u8,
    valueText: fn (Param(Id)) []const u8,
) !void {
    const Context = struct {
        helpText: fn (Param(Id)) []const u8,
        valueText: fn (Param(Id)) []const u8,

        pub fn help(c: @This(), p: Param(Id)) error{}![]const u8 {
            return c.helpText(p);
        }

        pub fn value(c: @This(), p: Param(Id)) error{}![]const u8 {
            return c.valueText(p);
        }
    };

    return helpFull(
        stream,
        Id,
        params,
        error{},
        Context{
            .helpText = helpText,
            .valueText = valueText,
        },
        Context.help,
        Context.value,
    );
}

pub const Help = struct {
    msg: []const u8 = "",
    value: []const u8 = "",
};

/// A wrapper around helpEx that takes a Param(Help).
pub fn help(stream: var, params: []const Param(Help)) !void {
    try helpEx(stream, Help, params, getHelpSimple, getValueSimple);
}

fn getHelpSimple(param: Param(Help)) []const u8 {
    return param.id.msg;
}

fn getValueSimple(param: Param(Help)) []const u8 {
    return param.id.value;
}

test "clap.help" {
    var buf: [1024]u8 = undefined;
    var slice_stream = io.fixedBufferStream(&buf);

    @setEvalBranchQuota(10000);
    try help(
        slice_stream.outStream(),
        comptime &[_]Param(Help){
            parseParam("-a             Short flag.  ") catch unreachable,
            parseParam("-b <V1>        Short option.") catch unreachable,
            parseParam("--aa           Long flag.   ") catch unreachable,
            parseParam("--bb <V2>      Long option. ") catch unreachable,
            parseParam("-c, --cc       Both flag.   ") catch unreachable,
            parseParam("-d, --dd <V3>  Both option. ") catch unreachable,
            Param(Help){
                .id = Help{
                    .msg = "Positional. This should not appear in the help message.",
                },
                .takes_value = true,
            },
        },
    );

    const expected = "" ++
        "\t-a           \tShort flag.\n" ++
        "\t-b <V1>      \tShort option.\n" ++
        "\t    --aa     \tLong flag.\n" ++
        "\t    --bb <V2>\tLong option.\n" ++
        "\t-c, --cc     \tBoth flag.\n" ++
        "\t-d, --dd <V3>\tBoth option.\n";

    const actual = slice_stream.getWritten();
    if (!mem.eql(u8, actual, expected)) {
        debug.warn("\n============ Expected ============\n", .{});
        debug.warn("{}", .{expected});
        debug.warn("============= Actual =============\n", .{});
        debug.warn("{}", .{actual});

        var buffer: [1024 * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        debug.warn("============ Expected (escaped) ============\n", .{});
        debug.warn("{x}\n", .{expected});
        debug.warn("============ Actual (escaped) ============\n", .{});
        debug.warn("{x}\n", .{actual});
        testing.expect(false);
    }
}

/// Will print a usage message in the following format:
/// [-abc] [--longa] [-d <valueText>] [--longb <valueText>] <valueText>
///
/// First all none value taking parameters, which have a short name are
/// printed, then non positional parameters and finally the positinal.
pub fn usageFull(
    stream: var,
    comptime Id: type,
    params: []const Param(Id),
    comptime Error: type,
    context: var,
    valueText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) !void {
    var cos = io.countingOutStream(stream);
    const cs = cos.outStream();
    for (params) |param| {
        const name = param.names.short orelse continue;
        if (param.takes_value)
            continue;

        if (cos.bytes_written == 0)
            try stream.writeAll("[-");
        try cs.writeByte(name);
    }
    if (cos.bytes_written != 0)
        try cs.writeByte(']');

    var positional: ?Param(Id) = null;
    for (params) |param| {
        if (!param.takes_value and param.names.short != null)
            continue;

        const prefix = if (param.names.short) |_| "-" else "--";

        // Seems the zig compiler is being a little wierd. I doesn't allow me to write
        // @as(*const [1]u8, s)                  VVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
        const name = if (param.names.short) |*s| @ptrCast([*]const u8, s)[0..1] else param.names.long orelse {
            positional = param;
            continue;
        };
        if (cos.bytes_written != 0)
            try cs.writeByte(' ');

        try cs.print("[{}{}", .{ prefix, name });
        if (param.takes_value)
            try cs.print(" <{}>", .{try valueText(context, param)});

        try cs.writeByte(']');
    }

    if (positional) |p| {
        if (cos.bytes_written != 0)
            try cs.writeByte(' ');
        try cs.print("<{}>", .{try valueText(context, p)});
    }
}

/// A wrapper around usageFull for a simple valueText functions that
/// cant return an error or take a context.
pub fn usageEx(
    stream: var,
    comptime Id: type,
    params: []const Param(Id),
    valueText: fn (Param(Id)) []const u8,
) !void {
    const Context = struct {
        valueText: fn (Param(Id)) []const u8,

        pub fn value(c: @This(), p: Param(Id)) error{}![]const u8 {
            return c.valueText(p);
        }
    };

    return usageFull(
        stream,
        Id,
        params,
        error{},
        Context{ .valueText = valueText },
        Context.value,
    );
}

/// A wrapper around usageEx that takes a Param(Help).
pub fn usage(stream: var, params: []const Param(Help)) !void {
    try usageEx(stream, Help, params, getValueSimple);
}

fn testUsage(expected: []const u8, params: []const Param(Help)) !void {
    var buf: [1024]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    try usage(fbs.outStream(), params);

    const actual = fbs.getWritten();
    if (!mem.eql(u8, actual, expected)) {
        debug.warn("\n============ Expected ============\n", .{});
        debug.warn("{}\n", .{expected});
        debug.warn("============= Actual =============\n", .{});
        debug.warn("{}\n", .{actual});

        var buffer: [1024 * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        debug.warn("============ Expected (escaped) ============\n", .{});
        debug.warn("{x}\n", .{expected});
        debug.warn("============ Actual (escaped) ============\n", .{});
        debug.warn("{x}\n", .{actual});
        testing.expect(false);
    }
}

test "usage" {
    @setEvalBranchQuota(100000);
    try testUsage("[-ab]", comptime &[_]Param(Help){
        parseParam("-a") catch unreachable,
        parseParam("-b") catch unreachable,
    });
    try testUsage("[-a <value>] [-b <v>]", comptime &[_]Param(Help){
        parseParam("-a <value>") catch unreachable,
        parseParam("-b <v>") catch unreachable,
    });
    try testUsage("[--a] [--b]", comptime &[_]Param(Help){
        parseParam("--a") catch unreachable,
        parseParam("--b") catch unreachable,
    });
    try testUsage("[--a <value>] [--b <v>]", comptime &[_]Param(Help){
        parseParam("--a <value>") catch unreachable,
        parseParam("--b <v>") catch unreachable,
    });
    try testUsage("<file>", comptime &[_]Param(Help){
        Param(Help){
            .id = Help{
                .value = "file",
            },
            .takes_value = true,
        },
    });
    try testUsage("[-ab] [-c <value>] [-d <v>] [--e] [--f] [--g <value>] [--h <v>] <file>", comptime &[_]Param(Help){
        parseParam("-a") catch unreachable,
        parseParam("-b") catch unreachable,
        parseParam("-c <value>") catch unreachable,
        parseParam("-d <v>") catch unreachable,
        parseParam("--e") catch unreachable,
        parseParam("--f") catch unreachable,
        parseParam("--g <value>") catch unreachable,
        parseParam("--h <v>") catch unreachable,
        Param(Help){
            .id = Help{
                .value = "file",
            },
            .takes_value = true,
        },
    });
}
