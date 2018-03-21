# zig-clap
A non allocating, fast and easy to use command line argument parser library for Zig.

# Example

```
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
};

pub fn main() !void {
    const parser = comptime Clap(Options).Builder
        .init(
            Options {
                .print_values = false,
                .a = 0,
                .b = 0,
                .c = 0,
            }
        )
        .programName("My Test Command")
        .author("Hejsil")
        .version("v1")
        .about("Prints some values to the screen... Maybe.")
        .command(
            Command.Builder
                .init("command")
                .arguments(
                    []Argument {
                        Argument.Builder
                            .init("a")
                            .help("Set the a field of Option.")
                            .short('a')
                            .takesValue(true)
                            .build(),
                        Argument.Builder
                            .init("b")
                            .help("Set the b field of Option.")
                            .short('b')
                            .takesValue(true)
                            .build(),
                        Argument.Builder
                            .init("c")
                            .help("Set the c field of Option.")
                            .short('c')
                            .takesValue(true)
                            .build(),
                        Argument.Builder
                            .init("print_values")
                            .help("Print all not 0 values.")
                            .short('p')
                            .long("print-values")
                            .build(),
                    }
                )
                .build()
        )
        .build();

    const args = try os.argsAlloc(debug.global_allocator);
    defer os.argsFree(debug.global_allocator, args);

    const options = try parser.parse(args[1..]);

    if (options.print_values) {
        if (options.a != 0) debug.warn("a = {}\n", options.a);
        if (options.b != 0) debug.warn("b = {}\n", options.b);
        if (options.c != 0) debug.warn("c = {}\n", options.c);
    }
}
```

Running example:
```
sample % ./sample                                                                                                                                               [0]
sample % ./sample -a 2 -b 4 -c 6                                                                                                                                [0]
sample % ./sample -a 2 -b 4 -c 6 -p                                                                                                                             [0]
a = 2
b = 4
c = 6
sample % ./sample -a 2 -b 4 -c 6 --print-values                                                                                                                 [0]
a = 2
b = 4
c = 6
```
