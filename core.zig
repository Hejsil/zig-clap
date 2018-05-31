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

        pub fn init(id: Id, takes_value: bool, names: &const Names) Self {
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

        id: Id,
        value: ?[]const u8,

        pub fn init(id: Id, value: ?[]const u8) Self {
            return Self {
                .id = id,
                .value = value,
            };
        }
    };
}

/// A interface for iterating over command line arguments
pub const ArgIterator = struct {
    const Error = error{OutOfMemory};

    nextFn: fn(iter: &ArgIterator, allocator: &mem.Allocator) Error!?[]const u8,

    pub fn next(iter: &ArgIterator, allocator: &mem.Allocator) Error!?[]const u8 {
        return iter.nextFn(iter, allocator);
    }
};

/// An ::ArgIterator, which iterates over a slice of arguments.
/// This implementation does not allocate.
pub const ArgSliceIterator = struct {
    args: []const []const u8,
    index: usize,
    iter: ArgIterator,

    pub fn init(args: []const []const u8) ArgSliceIterator {
        return ArgSliceIterator {
            .args = args,
            .index = 0,
            .iter = ArgIterator {
                .nextFn = nextFn,
            },
        };
    }

    fn nextFn(iter: &ArgIterator, allocator: &mem.Allocator) ArgIterator.Error!?[]const u8 {
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
    args: os.ArgIterator,
    iter: ArgIterator,

    pub fn init() OsArgIterator {
        return OsArgIterator {
            .args = os.args(),
            .iter = ArgIterator {
                .nextFn = nextFn,
            },
        };
    }

    fn nextFn(iter: &ArgIterator, allocator: &mem.Allocator) ArgIterator.Error!?[]const u8 {
        const self = @fieldParentPtr(OsArgIterator, "iter", iter);
        if (builtin.os == builtin.Os.windows) {
            return try self.args.next(allocator) ?? return null;
        } else {
            return self.args.nextPosix();
        }
    }
};

/// A command line argument parser which, given an ::ArgIterator, will parse arguments according
/// to the ::params. ::Clap parses in an iterating manner, so you have to use a loop together with
/// ::Clap.next to parse all the arguments of your program.
pub fn Clap(comptime Id: type) type {
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

        arena: heap.ArenaAllocator,
        params: []const Param(Id),
        inner: &ArgIterator,
        state: State,

        pub fn init(params: []const Param(Id), inner: &ArgIterator, allocator: &mem.Allocator) Self {
            var res = Self {
                .arena = heap.ArenaAllocator.init(allocator),
                .params = params,
                .inner = inner,
                .state = State.Normal,
            };

            return res;
        }

        pub fn deinit(iter: &Self) void {
            iter.arena.deinit();
        }

        /// Get the next ::Arg that matches a ::Param.
        pub fn next(iter: &Self) !?Arg(Id) {
            const ArgInfo = struct {
                const Kind = enum { Long, Short, Bare };

                arg: []const u8,
                kind: Kind,
            };

            switch (iter.state) {
                State.Normal => {
                    const full_arg = (try iter.innerNext()) ?? return null;
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

                        if (arg.len == 0)
                            return error.ArgWithNoName;

                        break :blk ArgInfo { .arg = arg, .kind = kind };
                    };

                    const arg = arg_info.arg;
                    const kind = arg_info.kind;
                    const eql_index = mem.indexOfScalar(u8, arg, '=');

                    switch (kind) {
                        ArgInfo.Kind.Bare,
                        ArgInfo.Kind.Long => {
                            for (iter.params) |*param| {
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

                                    return Arg(Id).init(param.id, null);
                                }

                                const value = blk: {
                                    if (maybe_value) |v|
                                        break :blk v;

                                    break :blk (try iter.innerNext()) ?? return error.MissingValue;
                                };

                                return Arg(Id).init(param.id, value);
                            }
                        },
                        ArgInfo.Kind.Short => {
                            return try iter.chainging(State.Chaining {
                                .arg = full_arg,
                                .index = (full_arg.len - arg.len),
                            });
                        },
                    }

                    // We do a final pass to look for value parameters matches
                    if (kind == ArgInfo.Kind.Bare) {
                        for (iter.params) |*param| {
                            if (param.names.bare) |_| continue;
                            if (param.names.short) |_| continue;
                            if (param.names.long) |_| continue;

                            return Arg(Id).init(param.id, arg);
                        }
                    }

                    return error.InvalidArgument;
                },
                @TagType(State).Chaining => |state| return try iter.chainging(state),
            }
        }

        fn chainging(iter: &Self, state: &const State.Chaining) !?Arg(Id) {
            const arg = state.arg;
            const index = state.index;
            const next_index = index + 1;

            for (iter.params) |param| {
                const short = param.names.short ?? continue;
                if (short != arg[index])
                    continue;

                // Before we return, we have to set the new state of the iterator
                defer {
                    if (arg.len <= next_index or param.takes_value) {
                        iter.state = State.Normal;
                    } else {
                        iter.state = State { .Chaining = State.Chaining {
                            .arg = arg,
                            .index = next_index,
                        }};
                    }
                }

                if (!param.takes_value)
                    return Arg(Id).init(param.id, null);

                if (arg.len <= next_index) {
                    const value = (try iter.innerNext()) ?? return error.MissingValue;
                    return Arg(Id).init(param.id, value);
                }

                if (arg[next_index] == '=') {
                    return Arg(Id).init(param.id, arg[next_index + 1..]);
                }

                return Arg(Id).init(param.id, arg[next_index..]);
            }

            return error.InvalidArgument;
        }

        fn innerNext(iter: &Self) !?[]const u8 {
            return try iter.inner.next(&iter.arena.allocator);
        }
    };
}

fn testNoErr(params: []const Param(u8), args: []const []const u8, ids: []const u8, values: []const ?[]const u8) void {
    var arg_iter = ArgSliceIterator.init(args);
    var iter = Clap(u8).init(params, &arg_iter.iter, debug.global_allocator);

    var i: usize = 0;
    while (iter.next() catch unreachable) |arg| : (i += 1) {
        debug.assert(ids[i] == arg.id);
        const expected_value = values[i] ?? {
            debug.assert(arg.value == null);
            continue;
        };
        const actual_value = arg.value ?? unreachable;

        debug.assert(mem.eql(u8, expected_value, actual_value));
    }
}

test "clap.core: short" {
    const params = []Param(u8) {
        Param(u8).init(0, false, Names.short('a')),
        Param(u8).init(1, false, Names.short('b')),
        Param(u8).init(2, true,  Names.short('c')),
    };

    testNoErr(params, [][]const u8 { "-a" },          []u8{0},   []?[]const u8{null});
    testNoErr(params, [][]const u8 { "-a", "-b" },    []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-ab" },         []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-c=100" },      []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c100" },       []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c", "100" },   []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-abc", "100" }, []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc=100" },    []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc100" },     []u8{0,1,2}, []?[]const u8{null,null,"100"});
}

test "clap.core: long" {
    const params = []Param(u8) {
        Param(u8).init(0, false, Names.long("aa")),
        Param(u8).init(1, false, Names.long("bb")),
        Param(u8).init(2, true,  Names.long("cc")),
    };

    testNoErr(params, [][]const u8 { "--aa" },         []u8{0},   []?[]const u8{null});
    testNoErr(params, [][]const u8 { "--aa", "--bb" }, []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "--cc=100" },     []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "--cc", "100" },  []u8{2},   []?[]const u8{"100"});
}

test "clap.core: bare" {
    const params = []Param(u8) {
        Param(u8).init(0, false, Names.bare("aa")),
        Param(u8).init(1, false, Names.bare("bb")),
        Param(u8).init(2, true,  Names.bare("cc")),
    };

    testNoErr(params, [][]const u8 { "aa" },        []u8{0},   []?[]const u8{null});
    testNoErr(params, [][]const u8 { "aa", "bb" },  []u8{0,1}, []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "cc=100" },    []u8{2},   []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "cc", "100" }, []u8{2},   []?[]const u8{"100"});
}

test "clap.core: none" {
    const params = []Param(u8) {
        Param(u8).init(0, true, Names.none()),
    };

    testNoErr(params, [][]const u8 { "aa" }, []u8{0}, []?[]const u8{"aa"});
}

test "clap.core: all" {
    const params = []Param(u8) {
        Param(u8).init(
            0,
            false,
            Names{
                .bare = "aa",
                .short = 'a',
                .long = "aa",
            }
        ),
        Param(u8).init(
            1,
            false,
            Names{
                .bare = "bb",
                .short = 'b',
                .long = "bb",
            }
        ),
        Param(u8).init(
            2,
            true,
            Names{
                .bare = "cc",
                .short = 'c',
                .long = "cc",
            }
        ),
        Param(u8).init(3, true, Names.none()),
    };

    testNoErr(params, [][]const u8 { "-a" },           []u8{0},     []?[]const u8{null});
    testNoErr(params, [][]const u8 { "-a", "-b" },     []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-ab" },          []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "-c=100" },       []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c100" },        []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-c", "100" },    []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "-abc", "100" },  []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc=100" },     []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "-abc100" },      []u8{0,1,2}, []?[]const u8{null,null,"100"});
    testNoErr(params, [][]const u8 { "--aa" },         []u8{0},     []?[]const u8{null});
    testNoErr(params, [][]const u8 { "--aa", "--bb" }, []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "--cc=100" },     []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "--cc", "100" },  []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "aa" },           []u8{0},     []?[]const u8{null});
    testNoErr(params, [][]const u8 { "aa", "bb" },     []u8{0,1},   []?[]const u8{null,null});
    testNoErr(params, [][]const u8 { "cc=100" },       []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "cc", "100" },    []u8{2},     []?[]const u8{"100"});
    testNoErr(params, [][]const u8 { "dd" },           []u8{3},     []?[]const u8{"dd"});
}
