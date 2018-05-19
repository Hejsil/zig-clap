const std  = @import("std");
const core = @import("core.zig");
const clap = @import("extended.zig");

const debug = std.debug;
const os    = std.os;

const Clap   = clap.Clap;
const Param  = clap.Param;
const Parser = clap.Parser;

const Options = struct {
    print_values: bool,
    a: i64,
    b: u64,
    c: u8,
    d: []const u8,
};

// Output on windows:
// zig-clap> .\example.exe -a 1
// zig-clap> .\example.exe -p -a 1
// a = 1
// zig-clap> .\example.exe -pa 1
// a = 1
// zig-clap> .\example.exe -pd V1
// d = V1
// zig-clap> .\example.exe -pd=V2
// d = V2
// zig-clap> .\example.exe -p -d=V3
// d = V3
// zig-clap> .\example.exe -pdV=4
// d = V=4
// zig-clap> .\example.exe -p -dV=5
// d = V=5

pub fn main() !void {
    const parser = comptime Clap(Options) {
        .defaults = Options {
            .print_values = false,
            .a = 0,
            .b = 0,
            .c = 0,
            .d = "",
        },
        .params = []Param {
            Param.init("a")
                .with("takes_value", Parser.int(i64, 10)),
            Param.init("b")
                .with("takes_value", Parser.int(u64, 10)),
            Param.init("c")
                .with("takes_value", Parser.int(u8, 10)),
            Param.init("d")
                .with("takes_value", Parser.string),
            Param.init("print_values")
                .with("short", 'p')
                .with("long", "print-values"),
        }
    };

    var arg_iter = core.OsArgIterator.init();
    const iter = &arg_iter.iter;
    const command = iter.next(debug.global_allocator);

    const options = try parser.parse(debug.global_allocator, iter);

    if (options.print_values) {
        if (options.a != 0) debug.warn("a = {}\n", options.a);
        if (options.b != 0) debug.warn("b = {}\n", options.b);
        if (options.c != 0) debug.warn("c = {}\n", options.c);
        if (options.d.len != 0) debug.warn("d = {}\n", options.d);
    }
}
