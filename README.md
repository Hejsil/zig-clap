# zig-clap

A simple and easy to use command line argument parser library for Zig.

## Features

* Short arguments `-a`
  * Chaining `-abc` where `a` and `b` does not take values.
* Long arguments `--long`
* Supports both passing values using spacing and `=` (`-a 100`, `-a=100`)
  * Short args also support passing values with no spacing or `=` (`-a100`)
  * This all works with chaining (`-ba 100`, `-ba=100`, `-ba100`)

## Examples

### `StreamingClap`

The `StreamingClap` is the base of all the other parsers. It's a streaming parser that uses an
`args.Iterator` to provide it with arguments lazily.

```zig
const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    const allocator = std.heap.direct_allocator;

    // First we specify what parameters our program can take.
    const params = [_]clap.Param(u8){
        clap.Param(u8){
            .id = 'h',
            .names = clap.Names{ .short = 'h', .long = "help" },
        },
        clap.Param(u8){
            .id = 'n',
            .names = clap.Names{ .short = 'n', .long = "number" },
            .takes_value = true,
        },
        clap.Param(u8){
            .id = 'f',
            .takes_value = true,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we initialize our streaming parser.
    var parser = clap.StreamingClap(u8, clap.args.OsIterator){
        .params = params,
        .iter = &iter,
    };

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (try parser.next()) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'h' => debug.warn("Help!\n"),
            'n' => debug.warn("--number = {}\n", arg.value.?),

            // arg.value == null, if arg.param.takes_value == false.
            // Otherwise, arg.value is the value passed with the argument, such as "-a=10"
            // or "-a 10".
            'f' => debug.warn("{}\n", arg.value.?),
            else => unreachable,
        }
    }
}

```

### `ComptimeClap`

The `ComptimeClap` is a wrapper for `StreamingClap`, which parses all the arguments and makes
them available through three functions (`flag`, `option`, `positionals`).

```zig
const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    const allocator = std.heap.direct_allocator;

    // First we specify what parameters our program can take.
    const params = [_]clap.Param([]const u8){
        clap.Param([]const u8){
            .id = "Display this help and exit.",
            .names = clap.Names{ .short = 'h', .long = "help" },
        },
        clap.Param([]const u8){
            .id = "An option parameter, which takes a value.",
            .names = clap.Names{ .short = 'n', .long = "number" },
            .takes_value = true,
        },
        clap.Param([]const u8){
            .id = "",
            .takes_value = true,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we can parse the arguments
    var args = try clap.ComptimeClap([]const u8, params).parse(allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    if (args.flag("--help"))
        debug.warn("--help\n");
    if (args.option("--number")) |n|
        debug.warn("--number = {}\n", n);
    for (args.positionals()) |pos|
        debug.warn("{}\n", pos);
}

```

The data structure returned from this parser has lookup speed on par with array access (`arr[i]`)
and validates that the strings you pass to `option` and `flag` are actually parameters that the
program can take:

```zig
const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const params = [_]clap.Param(void){clap.Param(void){
        .names = clap.Names{ .short = 'h', .long = "help" },
    }};

    var direct_allocator = std.heap.DirectAllocator.init();
    const allocator = &direct_allocator.allocator;
    defer direct_allocator.deinit();

    var iter = clap.args.OsIterator.init(allocator);
    defer iter.deinit();
    const exe = try iter.next();

    var args = try clap.ComptimeClap(void, params).parse(allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    _ = args.flag("--helps");
}

```

```
zig-clap/src/comptime.zig:116:17: error: --helps is not a parameter.
                @compileError(name ++ " is not a parameter.");
                ^
zig-clap/src/comptime.zig:84:45: note: called from here
            const param = comptime findParam(name);
                                            ^
zig-clap/example/comptime-clap-error.zig:22:18: note: called from here
    _ = args.flag("--helps");
                 ^
```

Ofc, this limits you to parameters that are comptime known.

### `help`

The `help`, `helpEx` and `helpFull` are functions for printing a simple list of all parameters the
program can take.

```zig
const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const stderr_file = try std.io.getStdErr();
    var stderr_out_stream = stderr_file.outStream();
    const stderr = &stderr_out_stream.stream;

    // clap.help is a function that can print a simple help message, given a
    // slice of Param([]const u8). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    try clap.help(
        stderr,
        [_]clap.Param([]const u8){
            clap.Param([]const u8){
                .id = "Display this help and exit.",
                .names = clap.Names{ .short = 'h', .long = "help" },
            },
            clap.Param([]const u8){
                .id = "Output version information and exit.",
                .names = clap.Names{ .short = 'v', .long = "version" },
            },
        },
    );
}

```

```
	-h, --help   	Display this help and exit.
	-v, --version	Output version information and exit.
```

The `help` function is the simplest to call. It only takes an `OutStream` and a slice of
`Param([]const u8)`. This function assumes that the id of each parameter is the help message.

The `helpEx` is the generic version of `help`. It can print a help message for any
`Param` give that the caller provides functions for getting the help and value strings.

The `helpFull` is even more generic, allowing the functions that get the help and value strings
to return errors and take a context as a parameter.
