const std = @import("std");
const builtin = @import("builtin");

const os = std.os;
const heap = std.heap;
const mem = std.mem;
const debug = std.debug;

/// The names a ::Param can have.
pub const Names = struct {
    /// No prefix
    bare: ?[]const u8,

    /// '-' prefix
    short: ?u8,

    /// '--' prefix
    long: ?[]const u8,

    /// Initializes no names
    pub fn none() Names {
        return Names{
            .bare = null,
            .short = null,
            .long = null,
        };
    }

    /// Initializes a bare name
    pub fn bare(b: []const u8) Names {
        return Names{
            .bare = b,
            .short = null,
            .long = null,
        };
    }

    /// Initializes a short name
    pub fn short(s: u8) Names {
        return Names{
            .bare = null,
            .short = s,
            .long = null,
        };
    }

    /// Initializes a long name
    pub fn long(l: []const u8) Names {
        return Names{
            .bare = null,
            .short = null,
            .long = l,
        };
    }

    /// Initializes a name with a prefix.
    /// ::short is set to ::name[0], and ::long is set to ::name.
    /// This function asserts that ::name.len != 0
    pub fn prefix(name: []const u8) Names {
        debug.assert(name.len != 0);

        return Names{
            .bare = null,
            .short = name[0],
            .long = name,
        };
    }
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
///   * Bare ("bare"): Should be used as for sub-commands and other keywords.
///     * They can take a value two different ways.
///       * "command value"
///       * "command=value"
///   * Value ("value"): Should be used as the primary parameter of the program, like a filename or
///                      an expression to parse.
///     * Value parameters must take a value.
pub fn Param(comptime Id: type) type {
    return struct {
        const Self = this;

        id: Id,
        takes_value: bool,
        names: Names,

        pub fn init(id: Id, takes_value: bool, names: *const Names) Self {
            // Assert, that if the param have no name, then it has to take
            // a value.
            debug.assert(
                names.bare != null or
                names.long != null or
                names.short != null or
                takes_value
            );

            return Self{
                .id = id,
                .takes_value = takes_value,
                .names = names.*,
            };
        }
    };
}

/// The result returned from ::Clap.next
pub fn Arg(comptime Id: type) type {
    return struct {
        const Self = this;

        param: *const Param(Id),
        value: ?[]const u8,

        pub fn init(param: *const Param(Id), value: ?[]const u8) Self {
            return Self {
                .param = param,
                .value = value,
            };
        }
    };
}

/// A interface for iterating over command line arguments
pub fn ArgIterator(comptime E: type) type {
    return struct {
        const Self = this;
        const Error = E;

        nextFn: fn(iter: *Self) Error!?[]const u8,

        pub fn next(iter: *Self) Error!?[]const u8 {
            return iter.nextFn(iter);
        }
    };
}

/// An ::ArgIterator, which iterates over a slice of arguments.
/// This implementation does not allocate.
pub const ArgSliceIterator = struct {
    const Error = error{};

    args: []const []const u8,
    index: usize,
    iter: ArgIterator(Error),

    pub fn init(args: []const []const u8) ArgSliceIterator {
        return ArgSliceIterator {
            .args = args,
            .index = 0,
            .iter = ArgIterator(Error) {
                .nextFn = nextFn,
            },
        };
    }

    fn nextFn(iter: *ArgIterator(Error)) Error!?[]const u8 {
        const self = @fieldParentPtr(ArgSliceIterator, "iter", iter);
        if (self.args.len <= self.index)
            return null;

        defer self.index += 1;
        return self.args[self.index];
    }
};

/// An ::ArgIterator, which wraps the ArgIterator in ::std.
/// On windows, this iterator allocates.
pub const OsArgIterator = struct {
    const Error = os.ArgIterator.NextError;

    arena: heap.ArenaAllocator,
    args: os.ArgIterator,
    iter: ArgIterator(Error),

    pub fn init(allocator: *mem.Allocator) OsArgIterator {
        return OsArgIterator {
            .arena = heap.ArenaAllocator.init(allocator),
            .args = os.args(),
            .iter = ArgIterator(Error) {
                .nextFn = nextFn,
            },
        };
    }

    pub fn deinit(iter: *OsArgIterator) void {
        iter.arena.deinit();
    }

    fn nextFn(iter: *ArgIterator(Error)) Error!?[]const u8 {
        const self = @fieldParentPtr(OsArgIterator, "iter", iter);
        if (builtin.os == builtin.Os.windows) {
            return try self.args.next(self.allocator) ?? return null;
        } else {
            return self.args.nextPosix();
        }
    }
};

/// A command line argument parser which, given an ::ArgIterator, will parse arguments according
/// to the ::params. ::Clap parses in an iterating manner, so you have to use a loop together with
/// ::Clap.next to parse all the arguments of your program.
pub fn Clap(comptime Id: type, comptime ArgError: type) type {
    return struct {
        const Self = this;

        const State = union(enum) {
            Normal,
            Chaining: Chaining,

            const Chaining = struct {
                arg: []const u8,
                index: usize,
            };
        };

        params: []const Param(Id),
        iter: *ArgIterator(ArgError),
        state: State,

        pub fn init(params: []const Param(Id), iter: *ArgIterator(ArgError)) Self {
            var res = Self {
                .params = params,
                .iter = iter,
                .state = State.Normal,
            };

            return res;
        }

        /// Get the next ::Arg that matches a ::Param.
        pub fn next(clap: *Self) !?Arg(Id) {
            const ArgInfo = struct {
                const Kind = enum { Long, Short, Bare };

                arg: []const u8,
                kind: Kind,
            };

            switch (clap.state) {
                State.Normal => {
                    const full_arg = (try clap.iter.next()) ?? return null;
                    const arg_info = blk: {
                        var arg = full_arg;
                        var kind = ArgInfo.Kind.Bare;

                        if (mem.startsWith(u8, arg, "--")) {
                            arg = arg[2..];
                            kind = ArgInfo.Kind.Long;
                        } else if (mem.startsWith(u8, arg, "-")) {
                            arg = arg[1..];
                            kind = ArgInfo.Kind.Short;
                        }

                        // We allow long arguments to go without a name.
                        // This allows the user to use "--" for something important
                        if (kind != ArgInfo.Kind.Long and arg.len == 0)
                            return error.InvalidArgument;

                        break :blk ArgInfo { .arg = arg, .kind = kind };
                    };

                    const arg = arg_info.arg;
                    const kind = arg_info.kind;
                    const eql_index = mem.indexOfScalar(u8, arg, '=');

                    switch (kind) {
                        ArgInfo.Kind.Bare,
                        ArgInfo.Kind.Long => {
                            for (clap.params) |*param| {
                                const match = switch (kind) {
                                    ArgInfo.Kind.Bare => param.names.bare ?? continue,
                                    ArgInfo.Kind.Long => param.names.long ?? continue,
                                    else => unreachable,
                                };
                                const name = if (eql_index) |i| arg[0..i] else arg;
                                const maybe_value = if (eql_index) |i| arg[i + 1..] else null;

                                if (!mem.eql(u8, name, match))
                                    continue;
                                if (!param.takes_value) {
                                    if (maybe_value != null)
                                        return error.DoesntTakeValue;

                                    return Arg(Id).init(param, null);
                                }

                                const value = blk: {
                                    if (maybe_value) |v|
                                        break :blk v;

                                    break :blk (try clap.iter.next()) ?? return error.MissingValue;
                                };

                                return Arg(Id).init(param, value);
                            }
                        },
                        ArgInfo.Kind.Short => {
                            return try clap.chainging(State.Chaining {
                                .arg = full_arg,
                                .index = (full_arg.len - arg.len),
                            });
                        },
                    }

                    // We do a final pass to look for value parameters matches
                    if (kind == ArgInfo.Kind.Bare) {
                        for (clap.params) |*param| {
                            if (param.names.bare) |_| continue;
                            if (param.names.short) |_| continue;
                            if (param.names.long) |_| continue;

                            return Arg(Id).init(param, arg);
                        }
                    }

                    return error.InvalidArgument;
                },
                @TagType(State).Chaining => |state| return try clap.chainging(state),
            }
        }

        fn chainging(clap: *Self, state: *const State.Chaining) !?Arg(Id) {
            const arg = state.arg;
            const index = state.index;
            const next_index = index + 1;

            for (clap.params) |*param| {
                const short = param.names.short ?? continue;
                if (short != arg[index])
                    continue;

                // Before we return, we have to set the new state of the clap
                defer {
                    if (arg.len <= next_index or param.takes_value) {
                        clap.state = State.Normal;
                    } else {
                        clap.state = State { .Chaining = State.Chaining {
                            .arg = arg,
                            .index = next_index,
                        }};
                    }
                }

                if (!param.takes_value)
                    return Arg(Id).init(param, null);

                if (arg.len <= next_index) {
                    const value = (try clap.iter.next()) ?? return error.MissingValue;
                    return Arg(Id).init(param, value);
                }

                if (arg[next_index] == '=') {
                    return Arg(Id).init(param, arg[next_index + 1..]);
                }

                return Arg(Id).init(param, arg[next_index..]);
            }

            return error.InvalidArgument;
        }
    };
}
