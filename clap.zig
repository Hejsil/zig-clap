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
    var res = Param(Help){
        .id = Help{
            .msg = line[0..0],
            .value = line[0..0],
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
            .value = text[0..0],
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
            .value = text[0..0],
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
            .value = text[0..0],
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
///     -s, --long <value_text> help_text
///     -s,                     help_text
///     -s <value_text>         help_text
///         --long              help_text
///         --long <value_text> help_text
pub fn helpFull(
    stream: var,
    comptime Id: type,
    params: []const Param(Id),
    comptime Error: type,
    context: var,
    help_text: fn (@TypeOf(context), Param(Id)) Error![]const u8,
    value_text: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) !void {
    const max_spacing = blk: {
        var res: usize = 0;
        for (params) |param| {
            var counting_stream = io.CountingOutStream(io.NullOutStream.Error).init(io.null_out_stream);
            try printParam(&counting_stream.stream, Id, param, Error, context, value_text);
            if (res < counting_stream.bytes_written)
                res = counting_stream.bytes_written;
        }

        break :blk res;
    };

    for (params) |param| {
        if (param.names.short == null and param.names.long == null)
            continue;

        var counting_stream = io.CountingOutStream(@TypeOf(stream.*).Error).init(stream);
        try stream.print("\t", .{});
        try printParam(&counting_stream.stream, Id, param, Error, context, value_text);
        try stream.writeByteNTimes(' ', max_spacing - counting_stream.bytes_written);
        try stream.print("\t{}\n", .{ try help_text(context, param) });
    }
}

fn printParam(
    stream: var,
    comptime Id: type,
    param: Param(Id),
    comptime Error: type,
    context: var,
    value_text: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) @TypeOf(stream.*).Error!void {
    if (param.names.short) |s| {
        try stream.print("-{c}", .{ s });
    } else {
        try stream.print("  ", .{});
    }
    if (param.names.long) |l| {
        if (param.names.short) |_| {
            try stream.print(", ", .{});
        } else {
            try stream.print("  ", .{});
        }

        try stream.print("--{}", .{ l });
    }
    if (param.takes_value)
        try stream.print(" <{}>", .{ value_text(context, param) });
}

/// A wrapper around helpFull for simple help_text and value_text functions that
/// cant return an error or take a context.
pub fn helpEx(
    stream: var,
    comptime Id: type,
    params: []const Param(Id),
    help_text: fn (Param(Id)) []const u8,
    value_text: fn (Param(Id)) []const u8,
) !void {
    const Context = struct {
        help_text: fn (Param(Id)) []const u8,
        value_text: fn (Param(Id)) []const u8,

        pub fn help(c: @This(), p: Param(Id)) error{}![]const u8 {
            return c.help_text(p);
        }

        pub fn value(c: @This(), p: Param(Id)) error{}![]const u8 {
            return c.value_text(p);
        }
    };

    return helpFull(
        stream,
        Id,
        params,
        error{},
        Context{
            .help_text = help_text,
            .value_text = value_text,
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
    var slice_stream = io.SliceOutStream.init(buf[0..]);
    try help(
        &slice_stream.stream,
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
        debug.warn("{}", .{ expected });
        debug.warn("============= Actual =============\n", .{});
        debug.warn("{}", .{ actual });

        var buffer: [1024 * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        debug.warn("============ Expected (escaped) ============\n", .{});
        debug.warn("{x}\n", .{ expected });
        debug.warn("============ Actual (escaped) ============\n", .{});
        debug.warn("{x}\n", .{ actual });
        testing.expect(false);
    }
}
