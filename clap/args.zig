const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const mem = std.mem;
const process = std.process;

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
    index: usize = 0,

    pub fn next(iter: *SliceIterator) Error!?[]const u8 {
        if (iter.args.len <= iter.index)
            return null;

        defer iter.index += 1;
        return iter.args[iter.index];
    }
};

test "clap.args.SliceIterator" {
    const args = &[_][]const u8{ "A", "BB", "CCC" };
    var iter = SliceIterator{ .args = args };

    for (args) |a| {
        const b = try iter.next();
        debug.assert(mem.eql(u8, a, b.?));
    }
}

/// An argument iterator which wraps the ArgIterator in ::std.
/// On windows, this iterator allocates.
pub const OsIterator = struct {
    const Error = process.ArgIterator.NextError;

    arena: heap.ArenaAllocator,
    args: process.ArgIterator,

    /// The executable path (this is the first argument passed to the program)
    /// TODO: Is it the right choice for this to be null? Maybe `init` should
    ///       return an error when we have no exe.
    exe_arg: ?[]const u8,

    pub fn init(allocator: *mem.Allocator) Error!OsIterator {
        var res = OsIterator{
            .arena = heap.ArenaAllocator.init(allocator),
            .args = process.args(),
            .exe_arg = undefined,
        };
        res.exe_arg = try res.next();
        return res;
    }

    pub fn deinit(iter: *OsIterator) void {
        iter.arena.deinit();
    }

    pub fn next(iter: *OsIterator) Error!?[]const u8 {
        if (builtin.os.tag == .windows) {
            return try iter.args.next(&iter.arena.allocator) orelse return null;
        } else {
            return iter.args.nextPosix();
        }
    }
};
