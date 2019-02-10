const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const mem = std.mem;
const os = std.os;

/// An example of what methods should be implemented on an arg iterator.
pub const ExampleArgIterator = struct {
    const Error = error{};

    pub fn next(iter: *ExampleArgIterator) Error!?[]const u8 {
        return "2";
    }
};

/// An argument iterator which iterates over a slice of arguments.
/// This implementation does not allocate.
pub const SliceIterator = struct {
    const Error = error{};

    args: []const []const u8,
    index: usize,

    pub fn init(args: []const []const u8) SliceIterator {
        return SliceIterator{
            .args = args,
            .index = 0,
        };
    }

    pub fn next(iter: *SliceIterator) Error!?[]const u8 {
        if (iter.args.len <= iter.index)
            return null;

        defer iter.index += 1;
        return iter.args[iter.index];
    }
};

test "clap.args.SliceIterator" {
    const args = [][]const u8{ "A", "BB", "CCC" };
    var iter = SliceIterator.init(args);

    for (args) |a| {
        const b = try iter.next();
        debug.assert(mem.eql(u8, a, b.?));
    }
}

/// An argument iterator which wraps the ArgIterator in ::std.
/// On windows, this iterator allocates.
pub const OsIterator = struct {
    const Error = os.ArgIterator.NextError;

    arena: heap.ArenaAllocator,
    args: os.ArgIterator,

    pub fn init(allocator: *mem.Allocator) OsIterator {
        return OsIterator{
            .arena = heap.ArenaAllocator.init(allocator),
            .args = os.args(),
        };
    }

    pub fn deinit(iter: *OsIterator) void {
        iter.arena.deinit();
    }

    pub fn next(iter: *OsIterator) Error!?[]const u8 {
        if (builtin.os == builtin.Os.windows) {
            return try iter.args.next(&iter.arena.allocator) orelse return null;
        } else {
            return iter.args.nextPosix();
        }
    }
};
