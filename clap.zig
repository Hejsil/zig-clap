const std = @import("std");

const builtin = std.builtin;
const debug = std.debug;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const process = std.process;
const testing = std.testing;

pub const args = @import("clap/args.zig");
pub const parsers = @import("clap/parsers.zig");
pub const streaming = @import("clap/streaming.zig");

test "clap" {
    testing.refAllDecls(@This());
}

/// The names a `Param` can have.
pub const Names = struct {
    /// '-' prefix
    short: ?u8 = null,

    /// '--' prefix
    long: ?[]const u8 = null,

    pub fn longest(names: *const Names) Longest {
        if (names.long) |long|
            return .{ .kind = .long, .name = long };
        if (names.short) |*short| {
            // TODO: Zig cannot figure out @as(*const [1]u8, short) in the ano literal
            const casted: *const [1]u8 = short;
            return .{ .kind = .short, .name = casted };
        }

        return .{ .kind = .positinal, .name = "" };
    }

    pub const Longest = struct {
        kind: enum { long, short, positinal },
        name: []const u8,
    };
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
                .desc = mem.trim(u8, line[help_start..], " \t"),
                .val = line[1..len],
            },
        };
    }

    return .{ .id = .{ .desc = mem.trim(u8, line, " \t") } };
}

fn expectParam(expect: Param(Help), actual: Param(Help)) !void {
    try testing.expectEqualStrings(expect.id.desc, actual.id.desc);
    try testing.expectEqualStrings(expect.id.val, actual.id.val);
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
        .id = .{ .desc = "Help text", .val = "val" },
        .names = .{ .short = 's', .long = "long" },
        .takes_value = .one,
    }, try parseParam("-s, --long <val> Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text", .val = "val" },
        .names = .{ .short = 's', .long = "long" },
        .takes_value = .many,
    }, try parseParam("-s, --long <val>... Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text", .val = "val" },
        .names = .{ .long = "long" },
        .takes_value = .one,
    }, try parseParam("--long <val> Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text", .val = "val" },
        .names = .{ .short = 's' },
        .takes_value = .one,
    }, try parseParam("-s <val> Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text" },
        .names = .{ .short = 's', .long = "long" },
    }, try parseParam("-s, --long Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text" },
        .names = .{ .short = 's' },
    }, try parseParam("-s Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text" },
        .names = .{ .long = "long" },
    }, try parseParam("--long Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text", .val = "A | B" },
        .names = .{ .long = "long" },
        .takes_value = .one,
    }, try parseParam("--long <A | B> Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text", .val = "A" },
        .names = .{},
        .takes_value = .one,
    }, try parseParam("<A> Help text"));

    try expectParam(Param(Help){
        .id = .{ .desc = "Help text", .val = "A" },
        .names = .{},
        .takes_value = .many,
    }, try parseParam("<A>... Help text"));

    try testing.expectError(error.TrailingComma, parseParam("--long, Help"));
    try testing.expectError(error.TrailingComma, parseParam("-s, Help"));
    try testing.expectError(error.InvalidShortParam, parseParam("-ss Help"));
    try testing.expectError(error.InvalidShortParam, parseParam("-ss <val> Help"));
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
            streaming.Error.DoesntTakeValue => try stream.print(
                "The argument '{s}{s}' does not take a value\n",
                .{ a.prefix, a.name },
            ),
            streaming.Error.MissingValue => try stream.print(
                "The argument '{s}{s}' requires a value but none was supplied\n",
                .{ a.prefix, a.name },
            ),
            streaming.Error.InvalidArgument => try stream.print(
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
    comptime value_parsers: anytype,
    opt: ParseOptions,
) !Result(Id, params, value_parsers) {
    var arena = heap.ArenaAllocator.init(opt.allocator);
    errdefer arena.deinit();

    var iter = try process.ArgIterator.initWithAllocator(arena.allocator());
    const exe_arg = iter.next();

    const result = try parseEx(Id, params, value_parsers, &iter, .{
        // Let's reuse the arena from the `OSIterator` since we already have it.
        .allocator = arena.allocator(),
        .diagnostic = opt.diagnostic,
    });

    return Result(Id, params, value_parsers){
        .args = result.args,
        .positionals = result.positionals,
        .exe_arg = exe_arg,
        .arena = arena,
    };
}

pub fn Result(
    comptime Id: type,
    comptime params: []const Param(Id),
    comptime value_parsers: anytype,
) type {
    return struct {
        args: Arguments(Id, params, value_parsers, .slice),
        positionals: []const FindPositionalType(Id, params, value_parsers),
        exe_arg: ?[]const u8,
        arena: std.heap.ArenaAllocator,

        pub fn deinit(result: @This()) void {
            result.arena.deinit();
        }
    };
}

/// Parses the command line arguments passed into the program based on an array of parameters.
///
/// The result will contain an `args` field which contains all the non positional arguments passed
/// in. There is a field in `args` for each parameter. The name of that field will be the result
/// of this expression:
/// ```
/// param.names.longest().name`
/// ```
///
/// The fields can have types other that `[]const u8` and this is based on what `value_parsers`
/// you provide. The parser to use for each parameter is determined by the following expression:
/// ```
/// @field(value_parsers, param.id.value())
/// ```
///
/// Where `value` is a function that returns the name of the value this parameter takes. A parser
/// is simple a function with the signature:
/// ```
/// fn ([]const u8) Error!T
/// ```
///
/// `T` can be any type and `Error` can be any error. You can pass `clap.parsers.default` if you
/// just wonna get something up and running.
///
/// Caller ownes the result and should free it by calling `result.deinit()`
pub fn parseEx(
    comptime Id: type,
    comptime params: []const Param(Id),
    comptime value_parsers: anytype,
    iter: anytype,
    opt: ParseOptions,
) !ResultEx(Id, params, value_parsers) {
    const allocator = opt.allocator;
    var positionals = std.ArrayList(
        FindPositionalType(Id, params, value_parsers),
    ).init(allocator);

    var arguments = Arguments(Id, params, value_parsers, .list){};
    errdefer deinitArgs(Id, params, value_parsers, .list, allocator, &arguments);

    var stream = streaming.Clap(Id, @typeInfo(@TypeOf(iter)).Pointer.child){
        .params = params,
        .iter = iter,
        .diagnostic = opt.diagnostic,
    };
    while (try stream.next()) |arg| {
        inline for (params) |*param| {
            if (param == arg.param) {
                const parser = comptime switch (param.takes_value) {
                    .none => undefined,
                    .one, .many => @field(value_parsers, param.id.value()),
                };

                // TODO: Update opt.diagnostics when `parser` fails. This is blocked by compiler
                //       bugs that causes an infinit loop.
                const longest = comptime param.names.longest();
                switch (longest.kind) {
                    .short, .long => switch (param.takes_value) {
                        .none => @field(arguments, longest.name) = true,
                        .one => @field(arguments, longest.name) = try parser(arg.value.?),
                        .many => {
                            const value = try parser(arg.value.?);
                            try @field(arguments, longest.name).append(allocator, value);
                        },
                    },
                    .positinal => try positionals.append(try parser(arg.value.?)),
                }
            }
        }
    }

    var result_args = Arguments(Id, params, value_parsers, .slice){};
    inline for (@typeInfo(@TypeOf(arguments)).Struct.fields) |field| {
        if (@typeInfo(field.field_type) == .Struct and
            @hasDecl(field.field_type, "toOwnedSlice"))
        {
            const slice = @field(arguments, field.name).toOwnedSlice(allocator);
            @field(result_args, field.name) = slice;
        } else {
            @field(result_args, field.name) = @field(arguments, field.name);
        }
    }

    return ResultEx(Id, params, value_parsers){
        .args = result_args,
        .positionals = positionals.toOwnedSlice(),
        .allocator = allocator,
    };
}

pub fn ResultEx(
    comptime Id: type,
    comptime params: []const Param(Id),
    comptime value_parsers: anytype,
) type {
    return struct {
        args: Arguments(Id, params, value_parsers, .slice),
        positionals: []const FindPositionalType(Id, params, value_parsers),
        allocator: mem.Allocator,

        pub fn deinit(result: *@This()) void {
            deinitArgs(Id, params, value_parsers, .slice, result.allocator, &result.args);
            result.allocator.free(result.positionals);
        }
    };
}

fn FindPositionalType(
    comptime Id: type,
    comptime params: []const Param(Id),
    comptime value_parsers: anytype,
) type {
    for (params) |param| {
        const longest = param.names.longest();
        if (longest.kind == .positinal)
            return ParamType(Id, param, value_parsers);
    }

    return []const u8;
}

fn ParamType(
    comptime Id: type,
    comptime param: Param(Id),
    comptime value_parsers: anytype,
) type {
    const parser = switch (param.takes_value) {
        .none => parsers.string,
        .one, .many => @field(value_parsers, param.id.value()),
    };
    return parsers.Result(@TypeOf(parser));
}

fn deinitArgs(
    comptime Id: type,
    comptime params: []const Param(Id),
    comptime value_parsers: anytype,
    comptime multi_arg_kind: MultiArgKind,
    allocator: mem.Allocator,
    arguments: *Arguments(Id, params, value_parsers, multi_arg_kind),
) void {
    inline for (params) |param| {
        const longest = comptime param.names.longest();
        if (longest.kind == .positinal)
            continue;
        if (param.takes_value != .many)
            continue;

        switch (multi_arg_kind) {
            .slice => allocator.free(@field(arguments, longest.name)),
            .list => @field(arguments, longest.name).deinit(allocator),
        }
    }
}

const MultiArgKind = enum { slice, list };

fn Arguments(
    comptime Id: type,
    comptime params: []const Param(Id),
    comptime value_parsers: anytype,
    comptime multi_arg_kind: MultiArgKind,
) type {
    var fields: [params.len]builtin.TypeInfo.StructField = undefined;

    var i: usize = 0;
    for (params) |param| {
        const longest = param.names.longest();
        if (longest.kind == .positinal)
            continue;

        const T = ParamType(Id, param, value_parsers);
        const FieldType = switch (param.takes_value) {
            .none => bool,
            .one => ?T,
            .many => switch (multi_arg_kind) {
                .slice => []const T,
                .list => std.ArrayListUnmanaged(T),
            },
        };
        fields[i] = .{
            .name = longest.name,
            .field_type = FieldType,
            .default_value = switch (param.takes_value) {
                .none => &false,
                .one => &@as(?T, null),
                .many => switch (multi_arg_kind) {
                    .slice => &@as([]const T, &[_]T{}),
                    .list => &std.ArrayListUnmanaged(T){},
                },
            },
            .is_comptime = false,
            .alignment = @alignOf(FieldType),
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
        parseParam("-c, --cc <str>") catch unreachable,
        parseParam("-d, --dd <usize>...") catch unreachable,
        parseParam("<str>") catch unreachable,
    };

    var iter = args.SliceIterator{
        .args = &.{ "-a", "-c", "0", "something", "-d", "1", "--dd", "2" },
    };
    var res = try parseEx(Help, params, parsers.default, &iter, .{
        .allocator = testing.allocator,
    });
    defer res.deinit();

    try testing.expect(res.args.aa);
    try testing.expect(!res.args.bb);
    try testing.expectEqualStrings("0", res.args.cc.?);
    try testing.expectEqual(@as(usize, 1), res.positionals.len);
    try testing.expectEqualStrings("something", res.positionals[0]);
    try testing.expectEqualSlices(usize, &.{ 1, 2 }, res.args.dd);
}

test "empty" {
    var iter = args.SliceIterator{ .args = &.{} };
    var res = try parseEx(u8, &.{}, parsers.default, &iter, .{ .allocator = testing.allocator });
    defer res.deinit();
}

fn testErr(
    comptime params: []const Param(Help),
    args_strings: []const []const u8,
    expected: []const u8,
) !void {
    var diag = Diagnostic{};
    var iter = args.SliceIterator{ .args = args_strings };
    _ = parseEx(Help, params, parsers.default, &iter, .{
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
    const params = comptime [_]Param(Help){
        parseParam("-a, --aa") catch unreachable,
        parseParam("-c, --cc <str>") catch unreachable,
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

pub const Help = struct {
    desc: []const u8 = "",
    val: []const u8 = "",

    pub fn description(h: Help) []const u8 {
        return h.desc;
    }

    pub fn value(h: Help) []const u8 {
        return h.val;
    }
};

/// Will print a help message in the following format:
///     -s, --long <valueText> helpText
///     -s,                    helpText
///     -s <valueText>         helpText
///         --long             helpText
///         --long <valueText> helpText
pub fn help(stream: anytype, comptime Id: type, params: []const Param(Id)) !void {
    const max_spacing = blk: {
        var res: usize = 0;
        for (params) |param| {
            var cs = io.countingWriter(io.null_writer);
            try printParam(cs.writer(), Id, param);
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
        try printParam(cs.writer(), Id, param);
        try stream.writeByteNTimes(' ', max_spacing - @intCast(usize, cs.bytes_written));

        const description = param.id.description();
        var it = mem.split(u8, description, "\n");
        var indent_line = false;
        while (it.next()) |line| : (indent_line = true) {
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
    try stream.writeAll(param.id.value());
    try stream.writeAll(">");
    if (param.takes_value == .many)
        try stream.writeAll("...");
}

test "clap.help" {
    var buf: [1024]u8 = undefined;
    var slice_stream = io.fixedBufferStream(&buf);

    @setEvalBranchQuota(10000);
    try help(
        slice_stream.writer(),
        Help,
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
/// [-abc] [--longa] [-d <T>] [--longb <T>] <T>
///
/// First all none value taking parameters, which have a short name are printed, then non
/// positional parameters and finally the positinal.
pub fn usage(stream: anytype, comptime Id: type, params: []const Param(Id)) !void {
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
            try cs.writeAll(param.id.value());
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
        try cs.writeAll(p.id.value());
        try cs.writeAll(">");
    }
}

fn testUsage(expected: []const u8, params: []const Param(Help)) !void {
    var buf: [1024]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    try usage(fbs.writer(), Help, params);
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
