const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const process = std.process;
const testing = std.testing;

pub const args = @import("clap/args.zig");

test "clap" {
    testing.refAllDecls(@This());
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

/// Whether a param takes no value (a flag), one value, or can be specified multiple times.
pub const Values = enum {
    none,
    one,
    many,
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
///   * Long ("--long-param"): Should be used for less common parameters, or when no single
///                            character can describe the paramter.
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
        takes_value: Values = .none,
    };
}

/// Takes a string and parses it to a Param(Help).
/// This is the reverse of 'help' but for at single parameter only.
pub fn parseParam(line: []const u8) !Param(Help) {
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

fn parseParamRest(line: []const u8) Param(Help) {
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

fn expectParam(expect: Param(Help), actual: Param(Help)) !void {
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
    try expectParam(Param(Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .short = 's', .long = "long" },
        .takes_value = .one,
    }, try parseParam("-s, --long <value> Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .short = 's', .long = "long" },
        .takes_value = .many,
    }, try parseParam("-s, --long <value>... Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .long = "long" },
        .takes_value = .one,
    }, try parseParam("--long <value> Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text", .value = "value" },
        .names = .{ .short = 's' },
        .takes_value = .one,
    }, try parseParam("-s <value> Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text" },
        .names = .{ .short = 's', .long = "long" },
    }, try parseParam("-s, --long Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text" },
        .names = .{ .short = 's' },
    }, try parseParam("-s Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text" },
        .names = .{ .long = "long" },
    }, try parseParam("--long Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text", .value = "A | B" },
        .names = .{ .long = "long" },
        .takes_value = .one,
    }, try parseParam("--long <A | B> Help text"));

    try expectParam(Param(Help){
        .id = .{ .msg = "Help text", .value = "A" },
        .names = .{},
        .takes_value = .one,
    }, try parseParam("<A> Help text"));

    try expectParam(Param(Help){
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

/// Optional diagnostics used for reporting useful errors
pub const Diagnostic = struct {
    arg: []const u8 = "",
    name: Names = Names{},

    /// Default diagnostics reporter when all you want is English with no colors.
    /// Use this as a reference for implementing your own if needed.
    pub fn report(diag: Diagnostic, stream: anytype, err: anyerror) !void {
        const Arg = struct {
            prefix: []const u8,
            name: []const u8,
        };
        const a = if (diag.name.short) |*c|
            Arg{ .prefix = "-", .name = @as(*const [1]u8, c)[0..] }
        else if (diag.name.long) |l|
            Arg{ .prefix = "--", .name = l }
        else
            Arg{ .prefix = "", .name = diag.arg };

        switch (err) {
            error.DoesntTakeValue => try stream.print(
                "The argument '{s}{s}' does not take a value\n",
                .{ a.prefix, a.name },
            ),
            error.MissingValue => try stream.print(
                "The argument '{s}{s}' requires a value but none was supplied\n",
                .{ a.prefix, a.name },
            ),
            error.InvalidArgument => try stream.print(
                "Invalid argument '{s}{s}'\n",
                .{ a.prefix, a.name },
            ),
            else => try stream.print("Error while parsing arguments: {s}\n", .{@errorName(err)}),
        }
    }
};

fn testDiag(diag: Diagnostic, err: anyerror, expected: []const u8) !void {
    var buf: [1024]u8 = undefined;
    var slice_stream = io.fixedBufferStream(&buf);
    diag.report(slice_stream.writer(), err) catch unreachable;
    try testing.expectEqualStrings(expected, slice_stream.getWritten());
}

test "Diagnostic.report" {
    try testDiag(.{ .arg = "c" }, error.InvalidArgument, "Invalid argument 'c'\n");
    try testDiag(
        .{ .name = .{ .long = "cc" } },
        error.InvalidArgument,
        "Invalid argument '--cc'\n",
    );
    try testDiag(
        .{ .name = .{ .short = 'c' } },
        error.DoesntTakeValue,
        "The argument '-c' does not take a value\n",
    );
    try testDiag(
        .{ .name = .{ .long = "cc" } },
        error.DoesntTakeValue,
        "The argument '--cc' does not take a value\n",
    );
    try testDiag(
        .{ .name = .{ .short = 'c' } },
        error.MissingValue,
        "The argument '-c' requires a value but none was supplied\n",
    );
    try testDiag(
        .{ .name = .{ .long = "cc" } },
        error.MissingValue,
        "The argument '--cc' requires a value but none was supplied\n",
    );
    try testDiag(
        .{ .name = .{ .short = 'c' } },
        error.InvalidArgument,
        "Invalid argument '-c'\n",
    );
    try testDiag(
        .{ .name = .{ .long = "cc" } },
        error.InvalidArgument,
        "Invalid argument '--cc'\n",
    );
    try testDiag(
        .{ .name = .{ .short = 'c' } },
        error.SomethingElse,
        "Error while parsing arguments: SomethingElse\n",
    );
    try testDiag(
        .{ .name = .{ .long = "cc" } },
        error.SomethingElse,
        "Error while parsing arguments: SomethingElse\n",
    );
}

pub fn Args(comptime Id: type, comptime params: []const Param(Id)) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        clap: ComptimeClap(Id, params),
        exe_arg: ?[]const u8,

        pub fn deinit(a: *@This()) void {
            a.arena.deinit();
        }

        pub fn flag(a: @This(), comptime name: []const u8) bool {
            return a.clap.flag(name);
        }

        pub fn option(a: @This(), comptime name: []const u8) ?[]const u8 {
            return a.clap.option(name);
        }

        pub fn options(a: @This(), comptime name: []const u8) []const []const u8 {
            return a.clap.options(name);
        }

        pub fn positionals(a: @This()) []const []const u8 {
            return a.clap.positionals();
        }
    };
}

/// Options that can be set to customize the behavior of parsing.
pub const ParseOptions = struct {
    /// The allocator used for all memory allocations. Defaults to the `heap.page_allocator`.
    /// Note: You should probably override this allocator if you are calling `parseEx`. Unlike
    ///       `parse`, `parseEx` does not wrap the allocator so the heap allocator can be
    ///       quite expensive. (TODO: Can we pick a better default? For `parse`, this allocator
    ///       is fine, as it wraps it in an arena)
    allocator: mem.Allocator = heap.page_allocator,
    diagnostic: ?*Diagnostic = null,
};

/// Same as `parseEx` but uses the `args.OsIterator` by default.
pub fn parse(
    comptime Id: type,
    comptime params: []const Param(Id),
    opt: ParseOptions,
) !Args(Id, params) {
    var arena = heap.ArenaAllocator.init(opt.allocator);
    errdefer arena.deinit();

    var iter = try process.ArgIterator.initWithAllocator(arena.allocator());
    const exe_arg = iter.next();

    const clap = try parseEx(Id, params, &iter, .{
        // Let's reuse the arena from the `OSIterator` since we already have it.
        .allocator = arena.allocator(),
        .diagnostic = opt.diagnostic,
    });

    return Args(Id, params){
        .exe_arg = exe_arg,
        .arena = arena,
        .clap = clap,
    };
}

/// Parses the command line arguments passed into the program based on an
/// array of `Param`s.
pub fn parseEx(
    comptime Id: type,
    comptime params: []const Param(Id),
    iter: anytype,
    opt: ParseOptions,
) !ComptimeClap(Id, params) {
    const Clap = ComptimeClap(Id, params);
    return try Clap.parse(iter, opt);
}

/// Will print a help message in the following format:
///     -s, --long <valueText> helpText
///     -s,                    helpText
///     -s <valueText>         helpText
///         --long             helpText
///         --long <valueText> helpText
pub fn helpFull(
    stream: anytype,
    comptime Id: type,
    params: []const Param(Id),
    comptime Error: type,
    context: anytype,
    helpText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
    valueText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) !void {
    const max_spacing = blk: {
        var res: usize = 0;
        for (params) |param| {
            var cs = io.countingWriter(io.null_writer);
            try printParam(cs.writer(), Id, param, Error, context, valueText);
            if (res < cs.bytes_written)
                res = @intCast(usize, cs.bytes_written);
        }

        break :blk res;
    };

    for (params) |param| {
        if (param.names.short == null and param.names.long == null)
            continue;

        var cs = io.countingWriter(stream);
        try stream.writeAll("\t");
        try printParam(cs.writer(), Id, param, Error, context, valueText);
        try stream.writeByteNTimes(' ', max_spacing - @intCast(usize, cs.bytes_written));

        const help_text = try helpText(context, param);
        var help_text_line_it = mem.split(u8, help_text, "\n");
        var indent_line = false;
        while (help_text_line_it.next()) |line| : (indent_line = true) {
            if (indent_line) {
                try stream.writeAll("\t");
                try stream.writeByteNTimes(' ', max_spacing);
            }
            try stream.writeAll("\t");
            try stream.writeAll(line);
            try stream.writeAll("\n");
        }
    }
}

fn printParam(
    stream: anytype,
    comptime Id: type,
    param: Param(Id),
    comptime Error: type,
    context: anytype,
    valueText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) !void {
    if (param.names.short) |s| {
        try stream.writeAll(&[_]u8{ '-', s });
    } else {
        try stream.writeAll("  ");
    }
    if (param.names.long) |l| {
        if (param.names.short) |_| {
            try stream.writeAll(", ");
        } else {
            try stream.writeAll("  ");
        }

        try stream.writeAll("--");
        try stream.writeAll(l);
    }

    if (param.takes_value == .none)
        return;

    try stream.writeAll(" <");
    try stream.writeAll(try valueText(context, param));
    try stream.writeAll(">");
    if (param.takes_value == .many)
        try stream.writeAll("...");
}

/// A wrapper around helpFull for simple helpText and valueText functions that
/// cant return an error or take a context.
pub fn helpEx(
    stream: anytype,
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
pub fn help(stream: anytype, params: []const Param(Help)) !void {
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
        slice_stream.writer(),
        comptime &.{
            parseParam("-a                Short flag.") catch unreachable,
            parseParam("-b <V1>           Short option.") catch unreachable,
            parseParam("--aa              Long flag.") catch unreachable,
            parseParam("--bb <V2>         Long option.") catch unreachable,
            parseParam("-c, --cc          Both flag.") catch unreachable,
            parseParam("--complicate      Flag with a complicated and\nvery long description that\nspans multiple lines.") catch unreachable,
            parseParam("-d, --dd <V3>     Both option.") catch unreachable,
            parseParam("-d, --dd <V3>...  Both repeated option.") catch unreachable,
            parseParam(
                "<P>               Positional. This should not appear in the help message.",
            ) catch unreachable,
        },
    );

    const expected = "" ++
        "\t-a              \tShort flag.\n" ++
        "\t-b <V1>         \tShort option.\n" ++
        "\t    --aa        \tLong flag.\n" ++
        "\t    --bb <V2>   \tLong option.\n" ++
        "\t-c, --cc        \tBoth flag.\n" ++
        "\t    --complicate\tFlag with a complicated and\n" ++
        "\t                \tvery long description that\n" ++
        "\t                \tspans multiple lines.\n" ++
        "\t-d, --dd <V3>   \tBoth option.\n" ++
        "\t-d, --dd <V3>...\tBoth repeated option.\n";

    try testing.expectEqualStrings(expected, slice_stream.getWritten());
}

/// Will print a usage message in the following format:
/// [-abc] [--longa] [-d <valueText>] [--longb <valueText>] <valueText>
///
/// First all none value taking parameters, which have a short name are
/// printed, then non positional parameters and finally the positinal.
pub fn usageFull(
    stream: anytype,
    comptime Id: type,
    params: []const Param(Id),
    comptime Error: type,
    context: anytype,
    valueText: fn (@TypeOf(context), Param(Id)) Error![]const u8,
) !void {
    var cos = io.countingWriter(stream);
    const cs = cos.writer();
    for (params) |param| {
        const name = param.names.short orelse continue;
        if (param.takes_value != .none)
            continue;

        if (cos.bytes_written == 0)
            try stream.writeAll("[-");
        try cs.writeByte(name);
    }
    if (cos.bytes_written != 0)
        try cs.writeAll("]");

    var positional: ?Param(Id) = null;
    for (params) |param| {
        if (param.takes_value == .none and param.names.short != null)
            continue;

        const prefix = if (param.names.short) |_| "-" else "--";

        const name = if (param.names.short) |*s|
            // Seems the zig compiler is being a little wierd. I doesn't allow me to write
            // @as(*const [1]u8, s)
            @ptrCast([*]const u8, s)[0..1]
        else
            param.names.long orelse {
                positional = param;
                continue;
            };

        if (cos.bytes_written != 0)
            try cs.writeAll(" ");

        try cs.writeAll("[");
        try cs.writeAll(prefix);
        try cs.writeAll(name);
        if (param.takes_value != .none) {
            try cs.writeAll(" <");
            try cs.writeAll(try valueText(context, param));
            try cs.writeAll(">");
            if (param.takes_value == .many)
                try cs.writeAll("...");
        }

        try cs.writeByte(']');
    }

    if (positional) |p| {
        if (cos.bytes_written != 0)
            try cs.writeAll(" ");

        try cs.writeAll("<");
        try cs.writeAll(try valueText(context, p));
        try cs.writeAll(">");
    }
}

/// A wrapper around usageFull for a simple valueText functions that
/// cant return an error or take a context.
pub fn usageEx(
    stream: anytype,
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
pub fn usage(stream: anytype, params: []const Param(Help)) !void {
    try usageEx(stream, Help, params, getValueSimple);
}

fn testUsage(expected: []const u8, params: []const Param(Help)) !void {
    var buf: [1024]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    try usage(fbs.writer(), params);
    try testing.expectEqualStrings(expected, fbs.getWritten());
}

test "usage" {
    @setEvalBranchQuota(100000);
    try testUsage("[-ab]", &.{
        try parseParam("-a"),
        try parseParam("-b"),
    });
    try testUsage("[-a <value>] [-b <v>]", &.{
        try parseParam("-a <value>"),
        try parseParam("-b <v>"),
    });
    try testUsage("[--a] [--b]", &.{
        try parseParam("--a"),
        try parseParam("--b"),
    });
    try testUsage("[--a <value>] [--b <v>]", &.{
        try parseParam("--a <value>"),
        try parseParam("--b <v>"),
    });
    try testUsage("<file>", &.{
        try parseParam("<file>"),
    });
    try testUsage(
        "[-ab] [-c <value>] [-d <v>] [--e] [--f] [--g <value>] [--h <v>] [-i <v>...] <file>",
        &.{
            try parseParam("-a"),
            try parseParam("-b"),
            try parseParam("-c <value>"),
            try parseParam("-d <v>"),
            try parseParam("--e"),
            try parseParam("--f"),
            try parseParam("--g <value>"),
            try parseParam("--h <v>"),
            try parseParam("-i <v>..."),
            try parseParam("<file>"),
        },
    );
}
