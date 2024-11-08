pub fn Params(comptime T: type) type {
    const info = @typeInfo(T).@"struct";

    var params: [info.fields.len + 2]std.builtin.Type.StructField = undefined;
    const name_default_value: ?[]const u8 = null;
    params[0] = .{
        .name = "name",
        .type = ?[]const u8,
        .alignment = @alignOf(?[]const u8),
        .default_value = @ptrCast(&name_default_value),
        .is_comptime = false,
    };

    const description_default_value: []const u8 = "";
    params[1] = .{
        .name = "description",
        .type = []const u8,
        .alignment = @alignOf([]const u8),
        .default_value = @ptrCast(&description_default_value),
        .is_comptime = false,
    };

    var used_shorts = std.StaticBitSet(std.math.maxInt(u8) + 1).initEmpty();

    // Reserver 'h' and 'v' for `--help` and `--version`
    used_shorts.set('h');
    used_shorts.set('v');

    for (info.fields, params[2..]) |field, *param| {
        const FieldType = field.type;
        const field_info = @typeInfo(FieldType);

        const Command = switch (field_info) {
            .@"union" => |un| blk: {
                var cmd_fields: [un.fields.len]std.builtin.Type.StructField = undefined;
                for (un.fields, &cmd_fields) |un_field, *cmd_field| {
                    const CmdParam = Params(un_field.type);
                    const cmd_default_value = CmdParam{};
                    cmd_field.* = .{
                        .name = un_field.name,
                        .type = CmdParam,
                        .alignment = @alignOf(CmdParam),
                        .default_value = @ptrCast(&cmd_default_value),
                        .is_comptime = false,
                    };
                }

                break :blk @Type(.{ .@"struct" = .{
                    .layout = .auto,
                    .fields = &cmd_fields,
                    .decls = &.{},
                    .is_tuple = false,
                } });
            },
            else => struct {},
        };

        const default_short = if (used_shorts.isSet(field.name[0])) null else blk: {
            used_shorts.set(field.name[0]);
            break :blk field.name[0];
        };

        const Param = struct {
            short: ?u8 = default_short,
            long: ?[]const u8 = field.name,
            value: []const u8 = blk: {
                var res_buf: [field.name.len]u8 = undefined;
                for (&res_buf, field.name) |*r, c|
                    r.* = std.ascii.toUpper(c);

                const res = res_buf;
                break :blk &res;
            },
            description: []const u8 = "",
            init: Init(FieldType) = defaultInit(FieldType, field.default_value),
            deinit: Deinit(FieldType) = defaultDeinit(FieldType),
            next: Next(FieldType) = defaultNext(FieldType),
            parse: ParseInto(FieldType) = defaultParseInto(FieldType),
            command: Command = .{},
            required: bool = field.default_value == null,
            kind: enum {
                flag,
                option,
                positional,
                positionals,
                command,
            } = switch (@typeInfo(field.type)) {
                .@"union" => .command,
                .bool => .flag,
                else => .option,
            },
        };

        const default_value = Param{};
        param.* = .{
            .name = field.name,
            .type = Param,
            .alignment = @alignOf(Param),
            .default_value = @ptrCast(&default_value),
            .is_comptime = false,
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &params,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn Init(comptime T: type) type {
    return ?*const fn (std.mem.Allocator) ParseError!T;
}

fn defaultInit(comptime T: type, comptime default_value: ?*const anyopaque) Init(T) {
    if (default_value) |v| {
        return struct {
            fn init(_: std.mem.Allocator) ParseError!T {
                return @as(*const T, @alignCast(@ptrCast(v))).*;
            }
        }.init;
    }
    if (types.allFieldsHaveDefaults(T)) {
        return struct {
            fn init(_: std.mem.Allocator) ParseError!T {
                return .{};
            }
        }.init;
    }

    return switch (@typeInfo(T)) {
        .void => return struct {
            fn init(_: std.mem.Allocator) ParseError!T {
                return {};
            }
        }.init,
        .bool => return struct {
            fn init(_: std.mem.Allocator) ParseError!T {
                return false;
            }
        }.init,
        .int, .float => return struct {
            fn init(_: std.mem.Allocator) ParseError!T {
                return 0;
            }
        }.init,
        .optional => return struct {
            fn init(_: std.mem.Allocator) ParseError!T {
                return null;
            }
        }.init,
        else => null,
    };
}

fn Deinit(comptime T: type) type {
    return ?*const fn (*T, std.mem.Allocator) void;
}

fn defaultDeinit(comptime T: type) Deinit(T) {
    switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union" => {
            if (!@hasDecl(T, "deinit"))
                return null;
        },
        else => return null,
    }

    return switch (@TypeOf(T.deinit)) {
        fn (*const T) void,
        fn (*T) void,
        fn (T) void,
        => struct {
            fn deinit(v: *T, _: std.mem.Allocator) void {
                v.deinit();
            }
        }.deinit,
        fn (*const T, std.mem.Allocator) void,
        fn (*T, std.mem.Allocator) void,
        fn (T, std.mem.Allocator) void,
        => struct {
            fn deinit(v: *T, gpa: std.mem.Allocator) void {
                v.deinit(gpa);
            }
        }.deinit,
        else => null,
    };
}

fn Next(comptime T: type) type {
    return ?*const fn (T) ParseError!T;
}

fn defaultNext(comptime T: type) Next(T) {
    return switch (@typeInfo(T)) {
        .bool => struct {
            fn next(_: T) !bool {
                return true;
            }
        }.next,
        .int => struct {
            fn next(i: T) !T {
                return i + 1;
            }
        }.next,
        else => null,
    };
}

fn Parse(comptime T: type) type {
    return ?*const fn ([]const u8) ParseError!T;
}

fn defaultParse(comptime T: type) Parse(T) {
    return switch (@typeInfo(T)) {
        .bool => struct {
            fn parse(str: []const u8) ParseError!T {
                const res = std.meta.stringToEnum(enum { false, true }, str) orelse
                    return error.ParsingFailed;
                return res == .true;
            }
        }.parse,
        .int => struct {
            fn parse(str: []const u8) ParseError!T {
                return std.fmt.parseInt(T, str, 0) catch
                    return error.ParsingFailed;
            }
        }.parse,
        .@"enum" => struct {
            fn parse(str: []const u8) ParseError!T {
                return std.meta.stringToEnum(T, str) orelse
                    return error.ParsingFailed;
            }
        }.parse,
        else => null,
    };
}

fn ParseInto(comptime T: type) type {
    return ?*const fn (*T, std.mem.Allocator, []const u8) ParseError!void;
}

fn defaultParseInto(comptime T: type) ParseInto(T) {
    if (types.isArrayListUnmanaged(T)) {
        const Child = @typeInfo(T.Slice).pointer.child;
        const parseChild = defaultParse(Child) orelse return null;
        return struct {
            fn parseInto(list: *T, allocator: std.mem.Allocator, str: []const u8) ParseError!void {
                const ptr = try list.addOne(allocator);
                errdefer _ = list.pop();

                ptr.* = try parseChild(str);
            }
        }.parseInto;
    } else switch (@typeInfo(T)) {
        .optional => |o| {
            const parse = defaultParse(o.child) orelse return null;
            return struct {
                fn parseInto(ptr: *T, allocator: std.mem.Allocator, str: []const u8) ParseError!void {
                    _ = allocator;
                    ptr.* = try parse(str);
                }
            }.parseInto;
        },
        else => {
            const parse = defaultParse(T) orelse return null;
            return struct {
                fn parseInto(ptr: *T, allocator: std.mem.Allocator, str: []const u8) ParseError!void {
                    _ = allocator;
                    ptr.* = try parse(str);
                }
            }.parseInto;
        },
    }
}

fn validateParams(comptime T: type, name: []const u8, opt: ParseOptions(T)) !void {
    const stderr_writer = std.io.getStdErr().writer();
    const stderr = opt.stderr orelse stderr_writer.any();

    var res: anyerror!void = {};
    var first_command: ?[]const u8 = null;
    var first_positionals: ?[]const u8 = null;
    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |field| switch (@field(opt.params, field.name).kind) {
        .flag, .option, .positional, .positionals => {
            const param = @field(opt.params, field.name);
            if (param.init == null) {
                try stderr.print("error: '{s}.{s}.init' is null\n", .{ name, field.name });
                try stderr.print("note: could not infer 'init' for type '{s}'\n", .{@typeName(field.type)});
                try stderr.print("note: or it was set to null by the caller (don't do that)\n\n", .{});
                res = error.InvalidParameter;
            }
            if (param.kind == .flag and param.next == null) {
                try stderr.print("error: '{s}.{s}.next' is null\n", .{ name, field.name });
                try stderr.print("note: could not infer 'next' for type '{s}'\n", .{@typeName(field.type)});
                try stderr.print("note: or it was set to null by the caller (don't do that)\n\n", .{});
                res = error.InvalidParameter;
            }
            if (param.kind != .flag and param.parse == null) {
                try stderr.print("error: '{s}.{s}.parse' is null\n", .{ name, field.name });
                try stderr.print("note: could not infer 'parse' for type '{s}'\n", .{@typeName(field.type)});
                try stderr.print("note: or it was set to null by the caller (don't do that)\n\n", .{});
                res = error.InvalidParameter;
            }
            if (first_command) |command| {
                if (param.kind == .positional or param.kind == .positionals) {
                    try stderr.print("error: cannot have positionals after a command\n", .{});
                    try stderr.print("note: '{s}.{s}' is the command\n", .{ name, command });
                    try stderr.print("note: '{s}.{s}' is the positional\n\n", .{ name, field.name });
                    res = error.InvalidParameter;
                }
            }
            if (first_positionals) |positional| {
                if (param.kind == .positional or param.kind == .positionals) {
                    try stderr.print("error: cannot have positionals after a positional taking many values\n", .{});
                    try stderr.print("note: '{s}.{s}' is the positional taking many values\n", .{ name, positional });
                    try stderr.print("note: '{s}.{s}' is the positional after it\n\n", .{ name, field.name });
                    res = error.InvalidParameter;
                }
            }

            if (param.kind == .positionals and first_positionals == null)
                first_positionals = field.name;
        },
        .command => case: {
            if (first_positionals) |positional| {
                try stderr.print("error: cannot have command after a positional taking many values\n", .{});
                try stderr.print("note: '{s}.{s}' is the positional\n", .{ name, positional });
                try stderr.print("note: '{s}.{s}' is the command\n\n", .{ name, field.name });
                res = error.InvalidParameter;
            }

            const param = @field(opt.params, field.name);
            const union_info = @typeInfo(field.type);
            if (union_info != .@"union" or union_info.@"union".tag_type == null) {
                try stderr.print(
                    "error: expected command '{s}.{s}' to be a tagged union, but found '{s}'\n\n",
                    .{ name, field.name, @typeName(field.type) },
                );
                res = error.InvalidParameter;
                break :case;
            }

            if (first_command) |command| {
                try stderr.print("error: only one field can be a command\n", .{});
                try stderr.print("note: both '{s}.{s}' and '{s}.{s}' are commands\n\n", .{ name, command, name, field.name });
                res = error.InvalidParameter;
                break :case;
            } else {
                first_command = field.name;
            }

            const union_field = union_info.@"union".fields;
            inline for (union_field) |cmd_field| {
                const cmd_params = @field(param.command, cmd_field.name);
                const cmd_opt = opt.withNewParams(cmd_field.type, cmd_params);

                const new_name = try std.fmt.allocPrint(opt.gpa, "{s}.{s}", .{
                    name,
                    cmd_field.name,
                });
                defer opt.gpa.free(new_name);

                validateParams(cmd_field.type, new_name, cmd_opt) catch |err| {
                    res = err;
                };
            }
        },
    };

    return res;
}

fn testValidateParams(comptime T: type, opt: struct {
    params: Params(T),
    expected: anyerror!void,
    expected_err: []const u8,
}) !void {
    const gpa = std.testing.allocator;

    var err = std.ArrayList(u8).init(gpa);
    const err_writer = err.writer();
    defer err.deinit();

    const actual = validateParams(T, "", .{
        .gpa = gpa,
        .params = opt.params,
        .stderr = err_writer.any(),
    });

    try std.testing.expectEqualStrings(opt.expected_err, err.items);
    try std.testing.expectEqualDeep(opt.expected, actual);
}

test validateParams {
    try testValidateParams(struct { a: *const void }, .{
        .params = .{ .a = .{ .kind = .flag } },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: '.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.a.next' is null
        \\note: could not infer 'next' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: *const void }, .{
        .params = .{ .a = .{ .kind = .option } },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: '.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.a.parse' is null
        \\note: could not infer 'parse' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: *const void }, .{
        .params = .{ .a = .{ .kind = .positional } },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: '.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.a.parse' is null
        \\note: could not infer 'parse' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: *const void }, .{
        .params = .{ .a = .{ .kind = .positionals } },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: '.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.a.parse' is null
        \\note: could not infer 'parse' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: *const void }, .{
        .params = .{ .a = .{ .kind = .command } },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: expected command '.a' to be a tagged union, but found '*const void'
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: union(enum) {}, b: union(enum) {} }, .{
        .params = .{
            .a = .{ .kind = .command },
            .b = .{ .kind = .command },
        },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: only one field can be a command
        \\note: both '.a' and '.b' are commands
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: union(enum) {}, b: u8 }, .{
        .params = .{
            .a = .{ .kind = .command },
            .b = .{ .kind = .positional },
        },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: cannot have positionals after a command
        \\note: '.a' is the command
        \\note: '.b' is the positional
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: union(enum) {}, b: u8 }, .{
        .params = .{
            .a = .{ .kind = .command },
            .b = .{ .kind = .positionals },
        },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: cannot have positionals after a command
        \\note: '.a' is the command
        \\note: '.b' is the positional
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: u8, b: union(enum) {} }, .{
        .params = .{
            .a = .{ .kind = .positionals },
            .b = .{ .kind = .command },
        },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: cannot have command after a positional taking many values
        \\note: '.a' is the positional
        \\note: '.b' is the command
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: u8, b: u8 }, .{
        .params = .{
            .a = .{ .kind = .positionals },
            .b = .{ .kind = .positional },
        },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: cannot have positionals after a positional taking many values
        \\note: '.a' is the positional taking many values
        \\note: '.b' is the positional after it
        \\
        \\
        ,
    });
    try testValidateParams(struct { a: u8, b: u8 }, .{
        .params = .{
            .a = .{ .kind = .positionals },
            .b = .{ .kind = .positionals },
        },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: cannot have positionals after a positional taking many values
        \\note: '.a' is the positional taking many values
        \\note: '.b' is the positional after it
        \\
        \\
        ,
    });

    try testValidateParams(struct { a: union(enum) {
        a: struct { a: *const void },
        b: struct { a: *const void },
        c: struct { a: *const void },
        d: struct { a: *const void },
        e: struct {
            a: union(enum) {},
            b: union(enum) {},
        },
    } }, .{
        .params = .{ .a = .{ .command = .{
            .a = .{ .a = .{ .kind = .flag } },
            .b = .{ .a = .{ .kind = .option } },
            .c = .{ .a = .{ .kind = .positional } },
            .d = .{ .a = .{ .kind = .positionals } },
            .e = .{ .a = .{ .kind = .command }, .b = .{ .kind = .command } },
        } } },
        .expected = error.InvalidParameter,
        .expected_err =
        \\error: '.a.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.a.a.next' is null
        \\note: could not infer 'next' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.b.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.b.a.parse' is null
        \\note: could not infer 'parse' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.c.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.c.a.parse' is null
        \\note: could not infer 'parse' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.d.a.init' is null
        \\note: could not infer 'init' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: '.d.a.parse' is null
        \\note: could not infer 'parse' for type '*const void'
        \\note: or it was set to null by the caller (don't do that)
        \\
        \\error: only one field can be a command
        \\note: both '.e.a' and '.e.b' are commands
        \\
        \\
        ,
    });
}

pub const HelpParam = struct {
    short: ?u8 = 'h',
    long: ?[]const u8 = "help",
    command: ?[]const u8 = "help",
    description: []const u8 = "Print help",
};

pub const VersionParam = struct {
    string: []const u8 = "0.0.0",
    short: ?u8 = 'v',
    long: ?[]const u8 = "version",
    command: ?[]const u8 = "version",
    description: []const u8 = "Print version",
};

pub const ExtraParams = struct {
    help: HelpParam = .{},
    version: VersionParam = .{},
};

pub fn ParseOptions(comptime T: type) type {
    return struct {
        gpa: std.mem.Allocator,
        params: Params(T) = .{},
        extra_params: ExtraParams = .{},

        assignment_separators: []const u8 = "=",

        /// The Writer used to write expected output like the help message when `-h` is passed. If
        /// `null`, `std.io.getStdOut` will be used
        stdout: ?std.io.AnyWriter = null,

        /// The Writer used to write errors. `std.io.getStdErr` will be used. If `null`,
        /// `std.io.getStdOut` will be used
        stderr: ?std.io.AnyWriter = null,

        pub fn withNewParams(opt: @This(), comptime T2: type, params: Params(T2)) ParseOptions(T2) {
            var res: ParseOptions(T2) = undefined;
            res.params = params;
            inline for (@typeInfo(@This()).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "params"))
                    continue;

                @field(res, field.name) = @field(opt, field.name);
            }

            return res;
        }
    };
}

pub const ParseError = error{
    ParsingInterrupted,
    ParsingFailed,
} || std.mem.Allocator.Error;

pub fn parseIter(it: anytype, comptime T: type, opt: ParseOptions(T)) ParseError!T {
    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => {
            validateParams(T, "", opt) catch @panic("Invalid parameters. See errors above.");
        },
        .ReleaseFast, .ReleaseSmall => {},
    }

    var parser = try Parser(@TypeOf(it), T).init(it, opt);
    return parser.parse();
}

fn Parser(comptime Iter: type, comptime T: type) type {
    return struct {
        it: Iter,
        opt: Options,
        result: T,
        has_been_set: HasBeenSet,
        current_positional: usize,

        stdout_writer: std.fs.File.Writer,
        stderr_writer: std.fs.File.Writer,

        const Options = ParseOptions(T);
        const Field = std.meta.FieldEnum(T);
        const HasBeenSet = std.EnumSet(Field);
        const fields = @typeInfo(T).@"struct".fields;

        fn init(it: Iter, opt: Options) ParseError!@This() {
            var res = @This(){
                .it = it,
                .opt = opt,
                .result = undefined,
                .has_been_set = .{},
                .current_positional = 0,

                .stdout_writer = std.io.getStdOut().writer(),
                .stderr_writer = std.io.getStdErr().writer(),
            };
            inline for (fields) |field| {
                const param = @field(opt.params, field.name);
                if (!param.required) {
                    const initValue = param.init orelse unreachable; // Shouldn't happen (validateParams)
                    @field(res.result, field.name) = try initValue(opt.gpa);
                    res.has_been_set.insert(@field(Field, field.name));
                }
            }

            return res;
        }

        fn parse(parser: *@This()) ParseError!T {
            errdefer {
                // If we fail, deinit fields that can be deinited
                inline for (fields) |field| continue_field_loop: {
                    const param = @field(parser.opt.params, field.name);
                    const deinit = param.deinit orelse break :continue_field_loop;
                    if (parser.has_been_set.contains(@field(Field, field.name)))
                        deinit(&@field(parser.result, field.name), parser.opt.gpa);
                }
            }

            while (parser.it.next()) |arg| {
                if (std.mem.eql(u8, arg, "--"))
                    break;

                if (std.mem.startsWith(u8, arg, "--")) {
                    try parser.parseLong(arg[2..]);
                } else if (std.mem.startsWith(u8, arg, "-")) {
                    try parser.parseShorts(arg[1..]);
                } else if (try parser.parseCommand(arg)) {
                    return parser.result;
                } else {
                    try parser.parsePositional(arg);
                }
            }

            while (parser.it.next()) |arg|
                try parser.parsePositional(arg);

            inline for (fields) |field| {
                const param = @field(parser.opt.params, field.name);
                _ = param;
                if (!parser.has_been_set.contains(@field(Field, field.name))) {
                    // TODO: Proper error. Required argument not specified
                    return error.ParsingFailed;
                }
            }

            return parser.result;
        }

        fn parseLong(parser: *@This(), name: []const u8) ParseError!void {
            if (parser.opt.extra_params.help.long) |h|
                if (std.mem.eql(u8, name, h))
                    return parser.printHelp();
            if (parser.opt.extra_params.version.long) |v|
                if (std.mem.eql(u8, name, v))
                    return parser.printVersion();

            inline for (fields) |field| switch (@field(parser.opt.params, field.name).kind) {
                .flag => switch_case: {
                    const param = @field(parser.opt.params, field.name);
                    const long_name = param.long orelse break :switch_case;
                    if (!std.mem.eql(u8, name, long_name))
                        break :switch_case;

                    return parser.parseNext(@field(Field, field.name));
                },
                .option => switch_case: {
                    const param = @field(parser.opt.params, field.name);
                    const long_name = param.long orelse break :switch_case;
                    if (!std.mem.startsWith(u8, name, long_name))
                        break :switch_case;

                    const value = if (name.len == long_name.len) blk: {
                        break :blk parser.it.next() orelse {
                            // TODO: Report proper error
                            return error.ParsingFailed;
                        };
                    } else if (std.mem.indexOfScalar(u8, parser.opt.assignment_separators, name[long_name.len]) != null) blk: {
                        break :blk name[long_name.len + 1 ..];
                    } else {
                        break :switch_case;
                    };

                    return parser.parseValue(@field(Field, field.name), value);
                },
                .positional, .positionals, .command => {},
            };

            // TODO: Report proper error
            return error.ParsingFailed;
        }

        fn parseShorts(parser: *@This(), shorts: []const u8) ParseError!void {
            var i: usize = 0;
            while (i < shorts.len)
                i = try parser.parseShort(shorts, i);
        }

        fn parseShort(parser: *@This(), shorts: []const u8, pos: usize) ParseError!usize {
            if (parser.opt.extra_params.help.short) |h|
                if (shorts[pos] == h)
                    return parser.printHelp();
            if (parser.opt.extra_params.version.short) |v|
                if (shorts[pos] == v)
                    return parser.printVersion();

            inline for (fields) |field| switch (@field(parser.opt.params, field.name).kind) {
                .flag => switch_case: {
                    const param = @field(parser.opt.params, field.name);
                    const short_name = param.short orelse break :switch_case;
                    if (shorts[pos] != short_name)
                        break :switch_case;

                    try parser.parseNext(@field(Field, field.name));
                    return pos + 1;
                },
                .option => switch_case: {
                    const param = @field(parser.opt.params, field.name);
                    const short_name = param.short orelse break :switch_case;
                    if (shorts[pos] != short_name)
                        break :switch_case;

                    const value = if (pos + 1 == shorts.len) blk: {
                        break :blk parser.it.next() orelse {
                            // TODO: Report proper error
                            return error.ParsingFailed;
                        };
                    } else blk: {
                        const assignment_separators = parser.opt.assignment_separators;
                        const has_assignment_separator =
                            std.mem.indexOfScalar(u8, assignment_separators, shorts[pos + 1]) != null;
                        break :blk shorts[pos + 1 + @intFromBool(has_assignment_separator) ..];
                    };

                    try parser.parseValue(@field(Field, field.name), value);
                    return shorts.len;
                },
                .positional, .positionals, .command => {},
            };

            // TODO: Report proper error
            return error.ParsingFailed;
        }

        fn parseCommand(parser: *@This(), arg: []const u8) ParseError!bool {
            if (parser.opt.extra_params.help.command) |h|
                if (std.mem.eql(u8, arg, h))
                    return parser.printHelp();
            if (parser.opt.extra_params.version.command) |v|
                if (std.mem.eql(u8, arg, v))
                    return parser.printVersion();

            inline for (fields) |field| continue_field_loop: {
                const union_field = switch (@typeInfo(field.type)) {
                    .@"union" => |u| u.fields,
                    else => continue,
                };
                const param = @field(parser.opt.params, field.name);
                if (param.kind != .command)
                    break :continue_field_loop;

                inline for (union_field) |cmd_field| continue_cmd_field_loop: {
                    const cmd_params = @field(param.command, cmd_field.name);
                    if (!std.mem.eql(u8, arg, cmd_params.name orelse cmd_field.name))
                        break :continue_cmd_field_loop;

                    var cmd_parser = try Parser(Iter, cmd_field.type).init(
                        parser.it,
                        parser.opt.withNewParams(cmd_field.type, cmd_params),
                    );

                    const cmd_result = try cmd_parser.parse();
                    const cmd_union = @unionInit(field.type, cmd_field.name, cmd_result);
                    @field(parser.result, field.name) = cmd_union;
                    parser.has_been_set.insert(@field(Field, field.name));
                    return true;
                }
            }

            return false;
        }

        fn parsePositional(parser: *@This(), arg: []const u8) ParseError!void {
            var i: usize = 0;
            inline for (fields) |field| continue_field_loop: {
                const param = @field(parser.opt.params, field.name);
                const next_positional = switch (param.kind) {
                    .positional => parser.current_positional + 1,
                    .positionals => parser.current_positional,
                    else => break :continue_field_loop,
                };
                if (parser.current_positional != i) {
                    i += 1;
                    break :continue_field_loop;
                }

                try parser.parseValue(@field(Field, field.name), arg);
                parser.current_positional = next_positional;
                return;
            }

            // TODO: Proper error. Too many positionals
            return error.ParsingFailed;
        }

        fn parseNext(parser: *@This(), comptime field: Field) ParseError!void {
            const field_name = @tagName(field);
            const param = @field(parser.opt.params, field_name);

            if (!parser.has_been_set.contains(field)) {
                const initValue = param.init orelse unreachable; // Shouldn't happen (validateParams)
                @field(parser.result, field_name) = try initValue(parser.opt.gpa);
            }

            const next = param.next orelse unreachable; // Shouldn't happen (validateParams)
            const field_ptr = &@field(parser.result, field_name);
            field_ptr.* = try next(field_ptr.*);
            parser.has_been_set.insert(field);
        }

        fn parseValue(parser: *@This(), comptime field: Field, value: []const u8) ParseError!void {
            const field_name = @tagName(field);
            const param = @field(parser.opt.params, field_name);

            if (!parser.has_been_set.contains(field)) {
                const initValue = param.init orelse unreachable; // Shouldn't happen (validateParams)
                @field(parser.result, field_name) = try initValue(parser.opt.gpa);
            }

            const parseInto = param.parse orelse unreachable; // Shouldn't happen (validateParams)
            try parseInto(&@field(parser.result, field_name), parser.opt.gpa, value);
            parser.has_been_set.insert(field);
        }

        fn printHelp(parser: *@This()) ParseError {
            help(parser.stdout(), T, .{
                .params = parser.opt.params,
                .extra_params = parser.opt.extra_params,
            }) catch {};
            return error.ParsingInterrupted;
        }

        fn printVersion(parser: *@This()) ParseError {
            parser.stdout().writeAll(parser.opt.extra_params.version.string) catch {};
            return error.ParsingInterrupted;
        }

        fn stdout(parser: *@This()) std.io.AnyWriter {
            return parser.opt.stdout orelse parser.stdout_writer.any();
        }

        fn stderr(parser: *@This()) std.io.AnyWriter {
            return parser.opt.stderr orelse parser.stderr_writer.any();
        }
    };
}

fn testParseIter(comptime T: type, opt: struct {
    args: []const u8,
    params: Params(T) = .{},

    expected: anyerror!T,
    expected_out: []const u8 = "",
    expected_err: []const u8 = "",
}) !void {
    const gpa = std.testing.allocator;
    var it = try std.process.ArgIteratorGeneral(.{}).init(gpa, opt.args);
    defer it.deinit();

    var out = std.ArrayList(u8).init(gpa);
    const out_writer = out.writer();
    defer out.deinit();

    var err = std.ArrayList(u8).init(gpa);
    const err_writer = err.writer();
    defer err.deinit();

    const actual = parseIter(&it, T, .{
        .gpa = gpa,
        .params = opt.params,
        .stdout = out_writer.any(),
        .stderr = err_writer.any(),
    });
    defer blk: {
        var v = actual catch break :blk;
        if (@hasDecl(T, "deinit"))
            v.deinit(gpa);
    }

    try std.testing.expectEqualDeep(opt.expected, actual);
    try std.testing.expectEqualStrings(opt.expected_out, out.items);
    try std.testing.expectEqualStrings(opt.expected_err, err.items);
}

test "parseIterParams" {
    const S = struct {
        a: bool = false,
        b: u8 = 0,
        c: enum { a, b, c, d } = .a,
        d: std.ArrayListUnmanaged(usize) = .{},
        e: ?u8 = null,

        fn deinit(s: *@This(), allocator: std.mem.Allocator) void {
            s.d.deinit(allocator);
        }
    };

    try testParseIter(S, .{
        .args = "--a",
        .expected = .{ .a = true },
    });
    try testParseIter(S, .{
        .args = "-a",
        .expected = .{ .a = true },
    });

    try testParseIter(S, .{
        .args = "--b",
        .expected = .{ .b = 1 },
        .params = .{ .b = .{ .kind = .flag } },
    });
    try testParseIter(S, .{
        .args = "-b",
        .expected = .{ .b = 1 },
        .params = .{ .b = .{ .kind = .flag } },
    });
    try testParseIter(S, .{
        .args = "-bb",
        .expected = .{ .b = 2 },
        .params = .{ .b = .{ .kind = .flag } },
    });

    try testParseIter(S, .{
        .args = "-aabb",
        .expected = .{ .a = true, .b = 2 },
        .params = .{ .b = .{ .kind = .flag } },
    });

    try testParseIter(S, .{
        .args = "--b 1",
        .expected = .{ .b = 1 },
    });
    try testParseIter(S, .{
        .args = "--b=2",
        .expected = .{ .b = 2 },
    });

    try testParseIter(S, .{
        .args = "-b 1",
        .expected = .{ .b = 1 },
    });
    try testParseIter(S, .{
        .args = "-b=2",
        .expected = .{ .b = 2 },
    });
    try testParseIter(S, .{
        .args = "-b3",
        .expected = .{ .b = 3 },
    });

    try testParseIter(S, .{
        .args = "-aab4",
        .expected = .{ .a = true, .b = 4 },
    });

    try testParseIter(S, .{
        .args = "--c b",
        .expected = .{ .c = .b },
    });
    try testParseIter(S, .{
        .args = "--c=c",
        .expected = .{ .c = .c },
    });

    try testParseIter(S, .{
        .args = "-c b",
        .expected = .{ .c = .b },
    });
    try testParseIter(S, .{
        .args = "-c=c",
        .expected = .{ .c = .c },
    });
    try testParseIter(S, .{
        .args = "-cd",
        .expected = .{ .c = .d },
    });

    try testParseIter(S, .{
        .args = "-bbcd",
        .expected = .{ .b = 2, .c = .d },
        .params = .{ .b = .{ .kind = .flag } },
    });

    var expected_items = [_]usize{ 0, 1, 2 };
    try testParseIter(S, .{
        .args = "-d 0 -d 1 -d 2",
        .expected = .{ .d = .{ .items = &expected_items, .capacity = 8 } },
    });

    try testParseIter(S, .{
        .args = "-e 2",
        .expected = .{ .e = 2 },
    });

    // Tests that `d` is not leaked when an error occurs
    try testParseIter(S, .{
        .args = "-d 0 -d 1 -d 2 -qqqq",
        .expected = error.ParsingFailed,
    });
}

test "parseIterRequired" {
    const S = struct {
        a: bool = false,
        b: bool,
    };

    try testParseIter(S, .{
        .args = "",
        .expected = error.ParsingFailed,
    });
    try testParseIter(S, .{
        .args = "-b",
        .expected = .{ .b = true },
    });
    try testParseIter(S, .{
        .args = "",
        .expected = error.ParsingFailed,
        .params = .{ .a = .{ .required = true } },
    });
    try testParseIter(S, .{
        .args = "-a",
        .expected = error.ParsingFailed,
        .params = .{ .a = .{ .required = true } },
    });
    try testParseIter(S, .{
        .args = "-b",
        .expected = error.ParsingFailed,
        .params = .{ .a = .{ .required = true } },
    });
    try testParseIter(S, .{
        .args = "-a -b",
        .expected = .{ .a = true, .b = true },
        .params = .{ .a = .{ .required = true } },
    });
}

test "parseIterPositional" {
    const S = struct {
        a: bool = false,
        b: u8 = 0,
        c: enum { a, b, c, d } = .a,
    };

    try testParseIter(S, .{
        .args = "true",
        .expected = .{ .a = true },
        .params = .{ .a = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "false",
        .expected = .{ .a = false },
        .params = .{ .a = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "0",
        .expected = .{ .b = 0 },
        .params = .{ .b = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "2",
        .expected = .{ .b = 2 },
        .params = .{ .b = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "a",
        .expected = .{ .c = .a },
        .params = .{ .c = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "c",
        .expected = .{ .c = .c },
        .params = .{ .c = .{ .kind = .positional } },
    });

    try testParseIter(S, .{
        .args = "true 2 d",
        .expected = .{ .a = true, .b = 2, .c = .d },
        .params = .{
            .a = .{ .kind = .positional },
            .b = .{ .kind = .positional },
            .c = .{ .kind = .positional },
        },
    });
    try testParseIter(S, .{
        .args = "false 4 c",
        .expected = .{ .a = false, .b = 4, .c = .c },
        .params = .{
            .a = .{ .kind = .positional },
            .b = .{ .kind = .positional },
            .c = .{ .kind = .positional },
        },
    });

    try testParseIter(S, .{
        .args = "false true",
        .expected = error.ParsingFailed,
        .params = .{ .a = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "false true",
        .expected = .{ .a = true },
        .params = .{ .a = .{ .kind = .positionals } },
    });
    try testParseIter(S, .{
        .args = "2 3",
        .expected = error.ParsingFailed,
        .params = .{ .b = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "2 3",
        .expected = .{ .b = 3 },
        .params = .{ .b = .{ .kind = .positionals } },
    });
    try testParseIter(S, .{
        .args = "c d",
        .expected = error.ParsingFailed,
        .params = .{ .c = .{ .kind = .positional } },
    });
    try testParseIter(S, .{
        .args = "c d",
        .expected = .{ .c = .d },
        .params = .{ .c = .{ .kind = .positionals } },
    });

    try testParseIter(S, .{
        .args = "true 2 d d",
        .expected = error.ParsingFailed,
        .params = .{
            .a = .{ .kind = .positional },
            .b = .{ .kind = .positional },
            .c = .{ .kind = .positional },
        },
    });
    try testParseIter(S, .{
        .args = "true 2 c d",
        .expected = .{ .a = true, .b = 2, .c = .d },
        .params = .{
            .a = .{ .kind = .positional },
            .b = .{ .kind = .positional },
            .c = .{ .kind = .positionals },
        },
    });
}

test "parseIterCommand" {
    const S = struct {
        a: bool = false,
        b: bool = false,
        command: union(enum) {
            sub1: struct { a: bool = false },
            sub2: struct { b: bool = false },
        },
    };

    try testParseIter(S, .{
        .args = "sub1",
        .expected = .{ .command = .{ .sub1 = .{} } },
    });
    try testParseIter(S, .{
        .args = "sub1 --a",
        .expected = .{ .command = .{ .sub1 = .{ .a = true } } },
    });
    try testParseIter(S, .{
        .args = "--a --b sub1 --a",
        .expected = .{
            .a = true,
            .b = true,
            .command = .{ .sub1 = .{ .a = true } },
        },
    });
    try testParseIter(S, .{
        .args = "sub2",
        .expected = .{ .command = .{ .sub2 = .{} } },
    });
    try testParseIter(S, .{
        .args = "sub2 --b",
        .expected = .{ .command = .{ .sub2 = .{ .b = true } } },
    });
    try testParseIter(S, .{
        .args = "--a --b sub2 --b",
        .expected = .{
            .a = true,
            .b = true,
            .command = .{ .sub2 = .{ .b = true } },
        },
    });

    try testParseIter(S, .{
        .args = "bob",
        .params = .{ .command = .{ .command = .{
            .sub1 = .{ .name = "bob" },
            .sub2 = .{ .name = "kurt" },
        } } },
        .expected = .{ .command = .{ .sub1 = .{} } },
    });
    try testParseIter(S, .{
        .args = "kurt",
        .params = .{ .command = .{ .command = .{
            .sub1 = .{ .name = "bob" },
            .sub2 = .{ .name = "kurt" },
        } } },
        .expected = .{ .command = .{ .sub2 = .{} } },
    });
}

test "parseIterHelp" {
    const S = struct {
        alice: bool = false,
        bob: bool = false,
        ben: bool = false,
        kurt: usize = 0,
        command: union(enum) {
            cmd1: struct {
                kurt: bool = false,
                mark: bool = false,
            },
            cmd2: struct {
                jim: bool = false,
                frans: bool = false,
            },
        },
    };

    const help_args = [_][]const u8{ "-h", "--help", "help" };
    for (help_args) |args| {
        try testParseIter(S, .{
            .args = args,
            .params = .{ .name = "testing-program" },
            .expected = error.ParsingInterrupted,
            .expected_out =
            \\Usage: testing-program [OPTIONS] [COMMAND]
            \\
            \\Commands:
            \\    cmd1
            \\    cmd2
            \\    help     Print help
            \\    version  Print version
            \\
            \\Options:
            \\    -a, --alice
            \\    -b, --bob
            \\        --ben
            \\    -k, --kurt <KURT>
            \\    -h, --help         Print help
            \\    -v, --version      Print version
            \\
            ,
        });
        try testParseIter(S, .{
            .args = args,
            .params = .{
                .name = "testing-program",
                .description = "This is a test",
                .alice = .{ .description = "Who is this?" },
                .bob = .{ .description = "Bob the builder" },
                .ben = .{ .description = "One of the people of all time" },
                .kurt = .{ .description = "No fun allowed" },
                .command = .{ .command = .{
                    .cmd1 = .{ .name = "command1", .description = "Command 1" },
                    .cmd2 = .{ .name = "command2", .description = "Command 2" },
                } },
            },
            .expected = error.ParsingInterrupted,
            .expected_out =
            \\This is a test
            \\
            \\Usage: testing-program [OPTIONS] [COMMAND]
            \\
            \\Commands:
            \\    command1  Command 1
            \\    command2  Command 2
            \\    help      Print help
            \\    version   Print version
            \\
            \\Options:
            \\    -a, --alice        Who is this?
            \\    -b, --bob          Bob the builder
            \\        --ben          One of the people of all time
            \\    -k, --kurt <KURT>  No fun allowed
            \\    -h, --help         Print help
            \\    -v, --version      Print version
            \\
            ,
        });
    }
}

pub fn HelpOptions(comptime T: type) type {
    return struct {
        params: Params(T) = .{},
        extra_params: ExtraParams = .{},
    };
}

const help_long_prefix_len = 4;
const help_value_prefix_len = 3;
const help_description_spacing = 2;

pub fn help(writer: anytype, comptime T: type, opt: HelpOptions(T)) !void {
    const fields = @typeInfo(T).@"struct".fields;

    var self_exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const program_name = opt.params.name orelse blk: {
        const self_exe_path = std.fs.selfExePath(&self_exe_path_buf) catch
            break :blk "program";
        break :blk std.fs.path.basename(self_exe_path);
    };

    if (opt.params.description.len != 0) {
        try writer.writeAll(opt.params.description);
        try writer.writeAll("\n\n");
    }

    try writer.writeAll("Usage: ");
    try writer.writeAll(program_name);
    try writer.writeAll(" [OPTIONS] [COMMAND]");

    var padding: usize = 0;
    if (opt.extra_params.help.command) |h|
        padding = @max(padding, h.len);
    if (opt.extra_params.version.command) |v|
        padding = @max(padding, v.len);

    inline for (fields) |field| switch (@field(opt.params, field.name).kind) {
        .flag, .option, .positional, .positionals => {},
        .command => {
            const param = @field(opt.params, field.name);
            inline for (@typeInfo(@TypeOf(param.command)).@"struct".fields) |cmd_field| {
                const cmd_param = @field(param.command, cmd_field.name);
                padding = @max(padding, (cmd_param.name orelse cmd_field.name).len);
            }
        },
    };

    try writer.writeAll("\n\nCommands:\n");
    inline for (fields) |field| switch (@field(opt.params, field.name).kind) {
        .flag, .option, .positional, .positionals => {},
        .command => {
            const param = @field(opt.params, field.name);
            inline for (@typeInfo(@TypeOf(param.command)).@"struct".fields) |cmd_field| {
                const cmd_param = @field(param.command, cmd_field.name);
                try printCommand(writer, padding, .{
                    .name = cmd_param.name orelse cmd_field.name,
                    .description = cmd_param.description,
                });
            }
        },
    };
    if (opt.extra_params.help.command) |h|
        try printCommand(writer, padding, .{
            .name = h,
            .description = opt.extra_params.help.description,
        });
    if (opt.extra_params.version.command) |v|
        try printCommand(writer, padding, .{
            .name = v,
            .description = opt.extra_params.version.description,
        });

    padding = 0;
    if (opt.extra_params.help.long) |h|
        padding = @max(padding, h.len + help_long_prefix_len);
    if (opt.extra_params.version.long) |v|
        padding = @max(padding, v.len + help_long_prefix_len);
    inline for (fields) |field| {
        const param = @field(opt.params, field.name);

        var pad: usize = 0;
        if (param.long) |long|
            pad += long.len + help_long_prefix_len;
        if (param.kind == .option)
            pad += param.value.len + help_value_prefix_len;
        padding = @max(padding, pad);
    }

    try writer.writeAll("\nOptions:\n");
    inline for (fields) |field| {
        const param = @field(opt.params, field.name);
        switch (param.kind) {
            .command, .positional, .positionals => {},
            .flag => try printParam(writer, padding, .{
                .short = param.short,
                .long = param.long,
                .description = param.description,
            }),
            .option => try printParam(writer, padding, .{
                .short = param.short,
                .long = param.long,
                .description = param.description,
                .value = param.value,
            }),
        }
    }
    try printParam(writer, padding, .{
        .short = opt.extra_params.help.short,
        .long = opt.extra_params.help.long,
        .description = opt.extra_params.help.description,
    });
    try printParam(writer, padding, .{
        .short = opt.extra_params.version.short,
        .long = opt.extra_params.version.long,
        .description = opt.extra_params.version.description,
    });
}

fn printCommand(writer: anytype, padding: usize, command: struct {
    name: []const u8,
    description: []const u8,
}) !void {
    try writer.writeByteNTimes(' ', 4);
    try writer.writeAll(command.name);
    if (command.description.len != 0) {
        try writer.writeByteNTimes(' ', padding - command.name.len);
        try writer.writeAll("  ");
        try writer.writeAll(command.description);
    }
    try writer.writeAll("\n");
}

fn printParam(writer: anytype, padding: usize, param: struct {
    short: ?u8,
    long: ?[]const u8,
    description: []const u8,
    value: ?[]const u8 = null,
}) !void {
    if (param.short == null and param.long == null)
        return;

    try writer.writeByteNTimes(' ', 4);
    if (param.short) |short| {
        try writer.writeByte('-');
        try writer.writeByte(short);
    } else {
        try writer.writeAll("  ");
    }
    if (param.long) |long| {
        try writer.writeByte(if (param.short) |_| ',' else ' ');
        try writer.writeAll(" --");
        try writer.writeAll(long);
    }
    if (param.value) |value| {
        try writer.writeAll(" <");
        try writer.writeAll(value);
        try writer.writeAll(">");
    }
    if (param.description.len != 0) {
        var pad = padding;
        if (param.long) |long|
            pad -= (long.len + help_long_prefix_len);
        if (param.value) |value|
            pad -= (value.len + help_value_prefix_len);
        try writer.writeByteNTimes(' ', pad + help_description_spacing);
        try writer.writeAll(param.description);
    }

    try writer.writeByte('\n');
}

fn testHelp(comptime T: type, opt: struct {
    params: Params(T) = .{},
    expected: []const u8,
}) !void {
    var buf: [std.mem.page_size]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try help(fbs.writer(), T, .{
        .params = opt.params,
    });
    try std.testing.expectEqualStrings(opt.expected, fbs.getWritten());
}

const types = @import("types.zig");
const std = @import("std");
