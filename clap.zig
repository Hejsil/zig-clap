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

/// Takes a string and parses it into many Param(Help). Returned is a newly allocated slice
/// containing all the parsed params. The caller is responsible for freeing the slice.
pub fn parseParams(allocator: mem.Allocator, str: []const u8) ![]Param(Help) {
    var list = std.ArrayList(Param(Help)).init(allocator);
    errdefer list.deinit();

    try parseParamsIntoArrayList(&list, str);
    return list.toOwnedSlice();
}

/// Takes a string and parses it into many Param(Help) at comptime. Returned is an array of
/// exactly the number of params that was parsed from `str`. A parse error becomes a compiler
/// error.
pub fn parseParamsComptime(comptime str: []const u8) [countParams(str)]Param(Help) {
    var res: [countParams(str)]Param(Help) = undefined;
    _ = parseParamsIntoSlice(&res, str) catch unreachable;
    return res;
}

fn countParams(str: []const u8) usize {
    // See parseParam for reasoning. I would like to remove it from parseParam, but people depend
    // on that function to still work conveniently at comptime, so leaving it for now.
    @setEvalBranchQuota(std.math.maxInt(u32));

    var res: usize = 0;
    var it = mem.split(u8, str, "\n");
    while (it.next()) |line| {
        const trimmed = mem.trimLeft(u8, line, " \t");
        if (mem.startsWith(u8, trimmed, "-") or
            mem.startsWith(u8, trimmed, "<"))
        {
            res += 1;
        }
    }

    return res;
}

/// Takes a string and parses it into many Param(Help), which are written to `slice`. A subslice
/// is returned, containing all the parameters parsed. This function will fail if the input slice
/// is to small.
pub fn parseParamsIntoSlice(slice: []Param(Help), str: []const u8) ![]Param(Help) {
    var null_alloc = heap.FixedBufferAllocator.init("");
    var list = std.ArrayList(Param(Help)){
        .allocator = null_alloc.allocator(),
        .items = slice[0..0],
        .capacity = slice.len,
    };

    try parseParamsIntoArrayList(&list, str);
    return list.items;
}

/// Takes a string and parses it into many Param(Help), which are appended onto `list`.
pub fn parseParamsIntoArrayList(list: *std.ArrayList(Param(Help)), str: []const u8) !void {
    var i: usize = 0;
    while (i != str.len) {
        var end: usize = undefined;
        try list.append(try parseParamEx(str[i..], &end));
        i += end;
    }
}

pub fn parseParam(str: []const u8) !Param(Help) {
    var end: usize = undefined;
    return parseParamEx(str, &end);
}

/// Takes a string and parses it to a Param(Help).
pub fn parseParamEx(str: []const u8, end: *usize) !Param(Help) {
    // This function become a lot less ergonomic to use once you hit the eval branch quota. To
    // avoid this we pick a sane default. Sadly, the only sane default is the biggest possible
    // value. If we pick something a lot smaller and a user hits the quota after that, they have
    // no way of overriding it, since we set it here.
    // We can recosider this again if:
    // * We get parseParams: https://github.com/Hejsil/zig-clap/issues/39
    // * We get a larger default branch quota in the zig compiler (stage 2).
    // * Someone points out how this is a really bad idea.
    @setEvalBranchQuota(std.math.maxInt(u32));

    var res = Param(Help){};
    var start: usize = 0;
    var state: enum {
        start,

        start_of_short_name,
        end_of_short_name,

        before_long_name_or_value_or_description,

        before_long_name,
        start_of_long_name,
        first_char_of_long_name,
        rest_of_long_name,

        before_value_or_description,

        first_char_of_value,
        rest_of_value,
        end_of_one_value,
        second_dot_of_multi_value,
        third_dot_of_multi_value,

        before_description,
        before_description_new_line,

        rest_of_description,
        rest_of_description_new_line,
    } = .start;
    for (str) |c, i| {
        errdefer end.* = i;

        switch (state) {
            .start => switch (c) {
                ' ', '\t', '\n' => {},
                '-' => state = .start_of_short_name,
                '<' => state = .first_char_of_value,
                else => return error.InvalidParameter,
            },

            .start_of_short_name => switch (c) {
                '-' => state = .first_char_of_long_name,
                'a'...'z', 'A'...'Z', '0'...'9' => {
                    res.names.short = c;
                    state = .end_of_short_name;
                },
                else => return error.InvalidParameter,
            },
            .end_of_short_name => switch (c) {
                ' ', '\t' => state = .before_long_name_or_value_or_description,
                '\n' => state = .before_description_new_line,
                ',' => state = .before_long_name,
                else => return error.InvalidParameter,
            },

            .before_long_name => switch (c) {
                ' ', '\t' => {},
                '-' => state = .start_of_long_name,
                else => return error.InvalidParameter,
            },
            .start_of_long_name => switch (c) {
                '-' => state = .first_char_of_long_name,
                else => return error.InvalidParameter,
            },
            .first_char_of_long_name => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9' => {
                    start = i;
                    state = .rest_of_long_name;
                },
                else => return error.InvalidParameter,
            },
            .rest_of_long_name => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9' => {},
                ' ', '\t' => {
                    res.names.long = str[start..i];
                    state = .before_value_or_description;
                },
                '\n' => {
                    res.names.long = str[start..i];
                    state = .before_description_new_line;
                },
                else => return error.InvalidParameter,
            },

            .before_long_name_or_value_or_description => switch (c) {
                ' ', '\t' => {},
                ',' => state = .before_long_name,
                '<' => state = .first_char_of_value,
                else => {
                    start = i;
                    state = .rest_of_description;
                },
            },

            .before_value_or_description => switch (c) {
                ' ', '\t' => {},
                '<' => state = .first_char_of_value,
                else => {
                    start = i;
                    state = .rest_of_description;
                },
            },
            .first_char_of_value => switch (c) {
                '>' => return error.InvalidParameter,
                else => {
                    start = i;
                    state = .rest_of_value;
                },
            },
            .rest_of_value => switch (c) {
                '>' => {
                    res.takes_value = .one;
                    res.id.val = str[start..i];
                    state = .end_of_one_value;
                },
                else => {},
            },
            .end_of_one_value => switch (c) {
                '.' => state = .second_dot_of_multi_value,
                ' ', '\t' => state = .before_description,
                '\n' => state = .before_description_new_line,
                else => {
                    start = i;
                    state = .rest_of_description;
                },
            },
            .second_dot_of_multi_value => switch (c) {
                '.' => state = .third_dot_of_multi_value,
                else => return error.InvalidParameter,
            },
            .third_dot_of_multi_value => switch (c) {
                '.' => {
                    res.takes_value = .many;
                    state = .before_description;
                },
                else => return error.InvalidParameter,
            },

            .before_description => switch (c) {
                ' ', '\t' => {},
                '\n' => state = .before_description_new_line,
                else => {
                    start = i;
                    state = .rest_of_description;
                },
            },
            .before_description_new_line => switch (c) {
                ' ', '\t', '\n' => {},
                '-', '<' => {
                    end.* = i;
                    break;
                },
                else => {
                    start = i;
                    state = .rest_of_description;
                },
            },
            .rest_of_description => switch (c) {
                '\n' => state = .rest_of_description_new_line,
                else => {},
            },
            .rest_of_description_new_line => switch (c) {
                ' ', '\t', '\n' => {},
                '-', '<' => {
                    res.id.desc = mem.trimRight(u8, str[start..i], " \t\n\r");
                    end.* = i;
                    break;
                },
                else => state = .rest_of_description,
            },
        }
    } else {
        end.* = str.len;
        switch (state) {
            .rest_of_description, .rest_of_description_new_line => {
                res.id.desc = mem.trimRight(u8, str[start..], " \t\n\r");
            },
            .rest_of_long_name => res.names.long = str[start..],
            .end_of_short_name,
            .end_of_one_value,
            .before_value_or_description,
            .before_description,
            .before_description_new_line,
            => {},
            else => return error.InvalidParameter,
        }
    }

    return res;
}

fn testParseParams(str: []const u8, expected_params: []const Param(Help)) !void {
    const actual_params = try parseParams(testing.allocator, str);
    defer testing.allocator.free(actual_params);

    try testing.expectEqual(expected_params.len, actual_params.len);
    for (expected_params) |_, i|
        try expectParam(expected_params[i], actual_params[i]);
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

test "parseParams" {
    try testParseParams(
        \\-s
        \\--str
        \\-s, --str
        \\--str <str>
        \\-s, --str <str>
        \\-s, --long <val> Help text
        \\-s, --long <val>... Help text
        \\--long <val> Help text
        \\-s <val> Help text
        \\-s, --long Help text
        \\-s Help text
        \\--long Help text
        \\--long <A | B> Help text
        \\<A> Help text
        \\<A>... Help text
        \\--aa This is
        \\    help spanning multiple
        \\    lines
        \\
        \\--aa This msg should end and the newline cause of new param
        \\--bb This should be a new param
        \\
    , &.{
        .{ .names = .{ .short = 's' } },
        .{ .names = .{ .long = "str" } },
        .{ .names = .{ .short = 's', .long = "str" } },
        .{
            .id = .{ .val = "str" },
            .names = .{ .long = "str" },
            .takes_value = .one,
        },
        .{
            .id = .{ .val = "str" },
            .names = .{ .short = 's', .long = "str" },
            .takes_value = .one,
        },
        .{
            .id = .{ .desc = "Help text", .val = "val" },
            .names = .{ .short = 's', .long = "long" },
            .takes_value = .one,
        },
        .{
            .id = .{ .desc = "Help text", .val = "val" },
            .names = .{ .short = 's', .long = "long" },
            .takes_value = .many,
        },
        .{
            .id = .{ .desc = "Help text", .val = "val" },
            .names = .{ .long = "long" },
            .takes_value = .one,
        },
        .{
            .id = .{ .desc = "Help text", .val = "val" },
            .names = .{ .short = 's' },
            .takes_value = .one,
        },
        .{
            .id = .{ .desc = "Help text" },
            .names = .{ .short = 's', .long = "long" },
        },
        .{
            .id = .{ .desc = "Help text" },
            .names = .{ .short = 's' },
        },
        .{
            .id = .{ .desc = "Help text" },
            .names = .{ .long = "long" },
        },
        .{
            .id = .{ .desc = "Help text", .val = "A | B" },
            .names = .{ .long = "long" },
            .takes_value = .one,
        },
        .{
            .id = .{ .desc = "Help text", .val = "A" },
            .takes_value = .one,
        },
        .{
            .id = .{ .desc = "Help text", .val = "A" },
            .names = .{},
            .takes_value = .many,
        },
        .{
            .id = .{
                .desc = 
                \\This is
                \\    help spanning multiple
                \\    lines
                ,
            },
            .names = .{ .long = "aa" },
            .takes_value = .none,
        },
        .{
            .id = .{ .desc = "This msg should end and the newline cause of new param" },
            .names = .{ .long = "aa" },
            .takes_value = .none,
        },
        .{
            .id = .{ .desc = "This should be a new param" },
            .names = .{ .long = "bb" },
            .takes_value = .none,
        },
    });

    try testing.expectError(error.InvalidParameter, parseParam("--long, Help"));
    try testing.expectError(error.InvalidParameter, parseParam("-s, Help"));
    try testing.expectError(error.InvalidParameter, parseParam("-ss Help"));
    try testing.expectError(error.InvalidParameter, parseParam("-ss <val> Help"));
    try testing.expectError(error.InvalidParameter, parseParam("- Help"));
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
        // TODO: We cannot use `try` inside the inline for because of a compiler bug that
        //       generates an infinit loop. For now, use a variable to store the error
        //       and use `try` outside. The downside of this is that we have to use
        //       `anyerror` :(
        var res: anyerror!void = {};
        inline for (params) |*param| {
            if (param == arg.param) {
                res = parseArg(
                    Id,
                    param.*,
                    value_parsers,
                    allocator,
                    &arguments,
                    &positionals,
                    arg,
                );
            }
        }

        try res;
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

fn parseArg(
    comptime Id: type,
    comptime param: Param(Id),
    comptime value_parsers: anytype,
    allocator: mem.Allocator,
    arguments: anytype,
    positionals: anytype,
    arg: streaming.Arg(Id),
) !void {
    const parser = comptime switch (param.takes_value) {
        .none => undefined,
        .one, .many => @field(value_parsers, param.id.value()),
    };

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

test "str and u64" {
    const params = comptime parseParamsComptime(
        \\--str <str>
        \\--num <u64>
        \\
    );

    var iter = args.SliceIterator{
        .args = &.{ "--num", "10", "--str", "cooley_rec_inp_ptr" },
    };
    var res = try parseEx(Help, &params, parsers.default, &iter, .{
        .allocator = testing.allocator,
    });
    defer res.deinit();
}

test "" {
    const params = comptime parseParamsComptime(
        \\-a, --aa
        \\-b, --bb
        \\-c, --cc <str>
        \\-d, --dd <usize>...
        \\<str>
        \\
    );

    var iter = args.SliceIterator{
        .args = &.{ "-a", "-c", "0", "something", "-d", "1", "--dd", "2" },
    };
    var res = try parseEx(Help, &params, parsers.default, &iter, .{
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
    const params = comptime parseParamsComptime(
        \\-a, --aa
        \\-c, --cc <str>
        \\
    );

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
            try stream.writeAll(mem.trimLeft(u8, line, " \t"));
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

    const params = comptime parseParamsComptime(
        \\-a                Short flag.
        \\-b <V1>           Short option.
        \\--aa              Long flag.
        \\--bb <V2>         Long option.
        \\-c, --cc          Both flag.
        \\--complicate      Flag with a complicated and
        \\    very long description that
        \\    spans multiple lines.
        \\-d, --dd <V3>     Both option.
        \\-d, --dd <V3>...  Both repeated option.
        \\<P>               Positional. This should not appear in the help message.
        \\
    );

    try help(slice_stream.writer(), Help, &params);
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
    try testUsage("[-ab]", &comptime parseParamsComptime(
        \\-a
        \\-b
        \\
    ));
    try testUsage("[-a <value>] [-b <v>]", &comptime parseParamsComptime(
        \\-a <value>
        \\-b <v>
        \\
    ));
    try testUsage("[--a] [--b]", &comptime parseParamsComptime(
        \\--a
        \\--b
        \\
    ));
    try testUsage("[--a <value>] [--b <v>]", &comptime parseParamsComptime(
        \\--a <value>
        \\--b <v>
        \\
    ));
    try testUsage("<file>", &comptime parseParamsComptime(
        \\<file>
        \\
    ));
    try testUsage(
        "[-ab] [-c <value>] [-d <v>] [--e] [--f] [--g <value>] [--h <v>] [-i <v>...] <file>",
        &comptime parseParamsComptime(
            \\-a
            \\-b
            \\-c <value>
            \\-d <v>
            \\--e
            \\--f
            \\--g <value>
            \\--h <v>
            \\-i <v>...
            \\<file>
            \\
        ),
    );
}
