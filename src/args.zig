const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const mem = std.mem;
const os = std.os;

/// A interface for iterating over command line arguments
pub fn Iterator(comptime E: type) type {
    return struct {
        const Self = @This();
        const Error = E;

        nextFn: fn (iter: *Self) Error!?[]const u8,

        pub fn next(iter: *Self) Error!?[]const u8 {
            return iter.nextFn(iter);
        }
    };
}

/// An ::ArgIterator, which iterates over a slice of arguments.
/// This implementation does not allocate.
pub const SliceIterator = struct {
    const Error = error{};

    args: []const []const u8,
    index: usize,
    iter: Iterator(Error),

    pub fn init(args: []const []const u8) SliceIterator {
        return SliceIterator{
            .args = args,
            .index = 0,
            .iter = Iterator(Error){ .nextFn = nextFn },
        };
    }

    fn nextFn(iter: *Iterator(Error)) Error!?[]const u8 {
        const self = @fieldParentPtr(SliceIterator, "iter", iter);
        if (self.args.len <= self.index)
            return null;

        defer self.index += 1;
        return self.args[self.index];
    }
};

test "clap.args.SliceIterator" {
    const args = [][]const u8{ "A", "BB", "CCC" };
    var slice_iter = SliceIterator.init(args);
    const iter = &slice_iter.iter;

    for (args) |a| {
        const b = try iter.next();
        debug.assert(mem.eql(u8, a, b.?));
    }
}

/// An ::ArgIterator, which wraps the ArgIterator in ::std.
/// On windows, this iterator allocates.
pub const OsIterator = struct {
    const Error = os.ArgIterator.NextError;

    arena: heap.ArenaAllocator,
    args: os.ArgIterator,
    iter: Iterator(Error),

    pub fn init(allocator: *mem.Allocator) OsIterator {
        return OsIterator{
            .arena = heap.ArenaAllocator.init(allocator),
            .args = os.args(),
            .iter = Iterator(Error){ .nextFn = nextFn },
        };
    }

    pub fn deinit(iter: *OsIterator) void {
        iter.arena.deinit();
    }

    fn nextFn(iter: *Iterator(Error)) Error!?[]const u8 {
        const self = @fieldParentPtr(OsIterator, "iter", iter);
        if (builtin.os == builtin.Os.windows) {
            return try self.args.next(&self.arena.allocator) orelse return null;
        } else {
            return self.args.nextPosix();
        }
    }
};
