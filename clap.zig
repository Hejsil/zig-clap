const std = @import("std");

const debug = std.debug;
const io = std.io;
const mem = std.mem;

pub const @"comptime" = @import("src/comptime.zig");
pub const args = @import("src/args.zig");
pub const streaming = @import("src/streaming.zig");

test "clap" {
    _ = @"comptime";
    _ = args;
    _ = streaming;
}

pub const ComptimeClap = @"comptime".ComptimeClap;
pub const StreamingClap = streaming.StreamingClap;

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

/// Will print a help message in the following format:
///     -s, --long=value_text help_text
///     -s,                   help_text
///         --long            help_text
pub fn helpFull(
    stream: var,
    comptime Id: type,
    params: []const Param(Id),
    comptime Error: type,
    context: var,
    help_text: fn (@typeOf(context), Param(Id)) Error![]const u8,
    value_text: fn (@typeOf(context), Param(Id)) Error![]const u8,
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

        var counting_stream = io.CountingOutStream(@typeOf(stream.*).Error).init(stream);
        try stream.print("\t");
        try printParam(&counting_stream.stream, Id, param, Error, context, value_text);
        try stream.writeByteNTimes(' ', max_spacing - counting_stream.bytes_written);
        try stream.print("\t{}\n", try help_text(context, param));
    }
}

fn printParam(
    stream: var,
    comptime Id: type,
    param: Param(Id),
    comptime Error: type,
    context: var,
    value_text: fn (@typeOf(context), Param(Id)) Error![]const u8,
) @typeOf(stream.*).Error!void {
    if (param.names.short) |s| {
        try stream.print("-{c}", s);
    } else {
        try stream.print("  ");
    }
    if (param.names.long) |l| {
        if (param.names.short) |_| {
            try stream.print(", ");
        } else {
            try stream.print("  ");
        }

        try stream.print("--{}", l);
    }
    if (param.takes_value)
        try stream.print("={}", value_text(context, param));
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

/// A wrapper around helpEx that takes a Param([]const u8) and uses the string id
/// as the help text for each paramter.
pub fn help(stream: var, params: []const Param([]const u8)) !void {
    try helpEx(stream, []const u8, params, getHelpSimple, getValueSimple);
}

fn getHelpSimple(param: Param([]const u8)) []const u8 {
    return param.id;
}

fn getValueSimple(param: Param([]const u8)) []const u8 {
    return "VALUE";
}

test "clap.help" {
    var buf: [1024]u8 = undefined;
    var slice_stream = io.SliceOutStream.init(buf[0..]);
    try help(
        &slice_stream.stream,
        [_]Param([]const u8){
            Param([]const u8){
                .id = "Short flag.",
                .names = Names{ .short = 'a' },
            },
            Param([]const u8){
                .id = "Short option.",
                .names = Names{ .short = 'b' },
                .takes_value = true,
            },
            Param([]const u8){
                .id = "Long flag.",
                .names = Names{ .long = "aa" },
            },
            Param([]const u8){
                .id = "Long option.",
                .names = Names{ .long = "bb" },
                .takes_value = true,
            },
            Param([]const u8){
                .id = "Both flag.",
                .names = Names{ .short = 'c', .long = "cc" },
            },
            Param([]const u8){
                .id = "Both option.",
                .names = Names{ .short = 'd', .long = "dd" },
                .takes_value = true,
            },
            Param([]const u8){
                .id = "Positional. This should not appear in the help message.",
                .takes_value = true,
            },
        },
    );

    const expected = "" ++
        "\t-a            \tShort flag.\n" ++
        "\t-b=VALUE      \tShort option.\n" ++
        "\t    --aa      \tLong flag.\n" ++
        "\t    --bb=VALUE\tLong option.\n" ++
        "\t-c, --cc      \tBoth flag.\n" ++
        "\t-d, --dd=VALUE\tBoth option.\n";

    if (!mem.eql(u8, slice_stream.getWritten(), expected)) {
        debug.warn("============ Expected ============\n");
        debug.warn("{}", expected);
        debug.warn("============= Actual =============\n");
        debug.warn("{}", slice_stream.getWritten());
        return error.NoMatch;
    }
}
