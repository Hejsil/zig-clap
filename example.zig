const std  = @import("std");
const clap = @import("clap.zig");

const debug = std.debug;
const os    = std.os;

const Clap     = clap.Clap;
const Command  = clap.Command;
const Argument = clap.Argument;

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
// zig-clap> .\example.exe -pd friend
// d = friend
// zig-clap> .\example.exe -pd=friend
// d = friend
// zig-clap> .\example.exe -p -d=friend
// d = friend
pub fn main() !void {
    const parser = comptime Clap(Options).init(
            Options {
                .print_values = false,
                .a = 0,
                .b = 0,
                .c = 0,
                .d = "",
            }
        )
        .with("program_name", "My Test Command")
        .with("author", "Hejsil")
        .with("version", "v1")
        .with("about", "Prints some values to the screen... Maybe.")
        .with("command", Command.init("command")
            .with("arguments",
                []Argument {
                    Argument.arg("a")
                        .with("help", "Set the a field of Option.")
                        .with("takes_value", clap.parse.int(i64, 10)),
                    Argument.arg("b")
                        .with("help", "Set the b field of Option.")
                        .with("takes_value", clap.parse.int(u64, 10)),
                    Argument.arg("c")
                        .with("help", "Set the c field of Option.")
                        .with("takes_value", clap.parse.int(u8, 10)),
                    Argument.arg("d")
                        .with("help", "Set the d field of Option.")
                        .with("takes_value", clap.parse.string),
                    Argument.field("print_values")
                        .with("help", "Print all not 0 values.")
                        .with("short", 'p')
                        .with("long", "print-values"),
                }
            )
        );

    const args = try os.argsAlloc(debug.global_allocator);
    defer os.argsFree(debug.global_allocator, args);

    const options = try parser.parse(args[1..]);

    if (options.print_values) {
        if (options.a != 0) debug.warn("a = {}\n", options.a);
        if (options.b != 0) debug.warn("b = {}\n", options.b);
        if (options.c != 0) debug.warn("c = {}\n", options.c);
        if (options.d.len != 0) debug.warn("d = {}\n", options.d);
    }
}
