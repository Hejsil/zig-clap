const std  = @import("std");
const clap = @import("index.zig");

const debug = std.debug;
const os    = std.os;

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
    const parser = comptime clap.Clap(Options) {
        .defaults = Options {
            .print_values = false,
            .a = 0,
            .b = 0,
            .c = 0,
            .d = "",
        },
        .params = []clap.Param {
            clap.Param.smart("a")
                .with("takes_value", clap.Parser.int(i64, 10)),
            clap.Param.smart("b")
                .with("takes_value", clap.Parser.int(u64, 10)),
            clap.Param.smart("c")
                .with("takes_value", clap.Parser.int(u8, 10)),
            clap.Param.smart("d")
                .with("takes_value", clap.Parser.string),
            clap.Param.smart("print_values")
                .with("short", 'p')
                .with("long", "print-values"),
        }
    };

    var arg_iter = clap.core.OsArgIterator.init();
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
