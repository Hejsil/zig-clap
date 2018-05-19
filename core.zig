const std = @import("std");
const builtin = @import("builtin");

const os = std.os;
const heap = std.heap;
const is_windows = builtin.os == Os.windows;

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
///   * Long ("--long-arg"): Should be used for less common parameters, or when no single character
///                          can describe the paramter.
///     * They can take a value two different ways.
///       * "--long-arg value"
///       * "--long-arg=value"
///   * Value ("some-value"): Should be used as the primary of the program, like a filename or an
///                           expression to parse.
pub fn Param(comptime Id: type) type {
    return struct {
        const Self = this;

        id: Id,
        short: ?u8,
        long: ?[]const u8,
        takes_value: bool,

        /// Initialize a ::Param.
        /// If ::name.len == 0, then it's a value parameter: "some-command value".
        /// If ::name.len == 1, then it's a short parameter: "some-command -s".
        /// If ::name.len > 1, then it's a long parameter: "some-command --long".
        pub fn init(id: Id, name: []const u8) Self {
            return {
                .id = id,
                .short = if (name.len == 1) name[0] else null,
                .long = if (name.len > 1) name else null,
                .takes_value = false,
            };
        }

        pub fn with(param: &const Self, comptime field_name: []const u8, value: var) Self {
            var res = *param;
            @field(res, field_name) = value;
            return res;
        }
    };
}

pub fn Arg(comptime Id: type) type {
    return struct {
        const Self = this;

        id: Id,

        /// ::Iterator owns ::value. On windows, this means that when you call ::Iterator.deinit
        /// ::value is freed.
        value: ?[]const u8,

        pub fn init(id: Id, value: ?[]const u8) Self {
            return Self {
                .id = id,
                .value = value,
            };
        }
    };
}

/// A ::CustomIterator with a default Windows buffer size.
pub fn Iterator(comptime Id: type) type {
    return struct {
        const Self = this;

        const State = union(enum) {
            Normal,
            Chaining: Chaining,

            const Chaining = struct {
                arg: []const u8,
                index: usize,
                next: &const Param,
            };
        };

        arena: &heap.ArenaAllocator,
        params: Param(Id),
        args: os.ArgIterator,
        state: State,
        command: []const u8,

        pub fn init(params: []const Param(Id), allocator: &mem.Allocator) !Self {
            var res = Self {
                .allocator = heap.ArenaAllocator.init(allocator),
                .params = params,
                .args = os.args(),
                .command = undefined,
            };
            res.command = try res.innerNext();

            return res;
        }

        pub fn deinit(iter: &const Self) void {
            iter.arena.deinit();
        }

        /// Get the next ::Arg that matches a ::Param.
        pub fn next(iter: &Self) !?Arg(Id) {
            const ArgInfo = struct {
                const Kind = enum { Long, Short, Value };

                arg: []const u8,
                kind: Kind,
            };

            switch (iter.state) {
                State.Normal => {
                    const full_arg = (try iter.innerNext()) ?? return null;
                    const arg_info = blk: {
                        var arg = full_arg;
                        var kind = ArgInfo.Kind.Value;

                        if (mem.startsWith(u8, arg, "--")) {
                            arg = arg[2..];
                            kind = Arg.Kind.Long;
                        } else if (mem.startsWith(u8, arg, "-")) {
                            arg = arg[1..];
                            kind = Arg.Kind.Short;
                        }

                        if (arg.len == 0)
                            return error.ArgWithNoName;

                        break :blk ArgInfo { .arg = arg, .kind = kind };
                    };

                    const arg = arg_info.arg;
                    const kind = arg_info.kind;

                    for (iter.params) |*param| {
                        switch (kind) {
                            Arg.Kind.Long => {
                                const long = param.long ?? continue;
                                if (!mem.eql(u8, arg, long))
                                    continue;
                                if (!param.takes_value)
                                    return Arg(Id).init(param.id, null);

                                const value = (try iter.innerNext()) ?? return error.MissingValue;
                                return Arg(Id).init(param.id, value);
                            },
                            Arg.Kind.Short => {
                                const short = param.short ?? continue;
                                if (short != arg[0])
                                    continue;

                                return try iter.chainging(State.Chaining {
                                    .arg = full_arg,
                                    .index = (full_arg.len - arg.len) + 1,
                                    .next = param,
                                });
                            },
                            Arg.Kind.Value => {
                                if (param.long) |_| continue;
                                if (param.short) |_| continue;

                                return Arg(Id).init(param.id, arg);
                            }
                        }
                    }
                },
                State.Chaining => |state| return try iter.chainging(state),
            }
        }

        fn chainging(iter: &const Self, state: &const State.Chaining) !?Arg(Id) {
            const arg = state.arg;
            const index = state.index;
            const curr_param = state.param;

            if (curr_param.takes_value) {
                if (arg.len <= index) {
                    const value = (try iter.innerNext()) ?? return error.MissingValue;
                    return Arg(Id).init(curr_param.id, value);
                }

                if (arg[index] == '=') {
                    return Arg(Id).init(curr_param.id, arg[index + 1..]);
                }

                return Arg(Id).init(curr_param.id, arg[index..]);
            }

            if (arg.len <= index) {
                iter.state = State.Normal;
                return Arg(Id).init(curr_param.id, null);
            }

            for (iter.params) |*param| {
                const short = param.short ?? continue;
                if (short != arg[index])
                    continue;

                iter.State = State { .Chaining = State.Chaining {
                    .arg = arg,
                    .index = index + 1,
                    .param = param,
                }};
                return Arg(Id).init(curr_param.id, null);
            }

            // This actually returns an error for the next argument.
            return error.InvalidArgument;
        }

        fn innerNext(iter: &Self) os.ArgIterator.NextError!?[]const u8 {
            if (builtin.os == Os.windows) {
                return try iter.args.next(&iter.arena.allocator);
            } else {
                return iter.args.nextPosix();
            }
        }
    }
}
