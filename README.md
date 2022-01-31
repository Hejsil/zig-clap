# zig-clap

A simple and easy to use command line argument parser library for Zig.

## Features

* Short arguments `-a`
  * Chaining `-abc` where `a` and `b` does not take values.
* Long arguments `--long`
* Supports both passing values using spacing and `=` (`-a 100`, `-a=100`)
  * Short args also support passing values with no spacing or `=` (`-a100`)
  * This all works with chaining (`-ba 100`, `-ba=100`, `-ba100`)
* Supports options that can be specified multiple times (`-e 1 -e 2 -e 3`)
* Print help message from parameter specification.
* Parse help message to parameter specification.

## Examples

### `clap.parse`

The simplest way to use this library is to just call the `clap.parse` function.

```zig
const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;

pub fn main() !void {
    // First we specify what parameters our program can take.
    // We can use `parseParam` to parse a string to a `Param(Help)`
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help             Display this help and exit.              ") catch unreachable,
        clap.parseParam("-n, --number <NUM>     An option parameter, which takes a value.") catch unreachable,
        clap.parseParam("-s, --string <STR>...  An option parameter which can be specified multiple times.") catch unreachable,
        clap.parseParam("<POS>...") catch unreachable,
    };

    // Initalize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostics` provides.
    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, .{ .diagnostic = &diag }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.flag("--help"))
        debug.print("--help\n", .{});
    if (args.option("--number")) |n|
        debug.print("--number = {s}\n", .{n});
    for (args.options("--string")) |s|
        debug.print("--string = {s}\n", .{s});
    for (args.positionals()) |pos|
        debug.print("{s}\n", .{pos});
}

```

The data structure returned has lookup speed on par with array access (`arr[i]`) and validates
that the strings you pass to `option`, `options` and `flag` are actually parameters that the
program can take:

```zig
const clap = @import("clap");
const std = @import("std");

pub fn main() !void {
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help  Display this help and exit.") catch unreachable,
    };

    var args = try clap.parse(clap.Help, &params, .{});
    defer args.deinit();

    _ = args.flag("--helps");
}

```

```
zig-clap/clap/comptime.zig:109:17: error: --helps is not a parameter.
                @compileError(name ++ " is not a parameter.");
                ^
zig-clap/clap/comptime.zig:77:45: note: called from here
            const param = comptime findParam(name);
                                            ^
zig-clap/clap.zig:238:31: note: called from here
            return a.clap.flag(name);
                              ^
zig-clap/example/simple-error.zig:16:18: note: called from here
    _ = args.flag("--helps");
```

There is also a `parseEx` variant that takes an argument iterator.

### `StreamingClap`

The `StreamingClap` is the base of all the other parsers. It's a streaming parser that uses an
`args.Iterator` to provide it with arguments lazily.

```zig
const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const process = std.process;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // First we specify what parameters our program can take.
    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
        .{
            .id = 'n',
            .names = .{ .short = 'n', .long = "number" },
            .takes_value = .one,
        },
        .{ .id = 'f', .takes_value = .one },
    };

    var iter = try process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // Skip exe argument
    _ = iter.next();

    // Initalize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also leave the `diagnostic` field unset if you
    // don't care about the extra information `Diagnostic` provides.
    var diag = clap.Diagnostic{};
    var parser = clap.StreamingClap(u8, process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'h' => debug.print("Help!\n", .{}),
            'n' => debug.print("--number = {s}\n", .{arg.value.?}),

            // arg.value == null, if arg.param.takes_value == .none.
            // Otherwise, arg.value is the value passed with the argument, such as "-a=10"
            // or "-a 10".
            'f' => debug.print("{s}\n", .{arg.value.?}),
            else => unreachable,
        }
    }
}

```

Currently, this parse is the only parser that allow an array of `Param` tha
is generated at runtime.

### `help`

The `help`, `helpEx` and `helpFull` are functions for printing a simple list of all parameters the
program can take.

```zig
const clap = @import("clap");
const std = @import("std");

pub fn main() !void {
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help     Display this help and exit.         ") catch unreachable,
        clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    };

    var args = try clap.parse(clap.Help, &params, .{});
    defer args.deinit();

    // clap.help is a function that can print a simple help message, given a
    // slice of Param(Help). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    if (args.flag("--help"))
        return clap.help(std.io.getStdErr().writer(), &params);
}

```

```
$ zig-out/bin/help --help
	-h, --help   	Display this help and exit.
	-v, --version	Output version information and exit.
```

The `help` functions are the simplest to call. It only takes an `OutStream` and a slice of
`Param(Help)`.

The `helpEx` is the generic version of `help`. It can print a help message for any
`Param` give that the caller provides functions for getting the help and value strings.

The `helpFull` is even more generic, allowing the functions that get the help and value strings
to return errors and take a context as a parameter.

### `usage`

The `usage`, `usageEx` and `usageFull` are functions for printing a small abbreviated version
of the help message.

```zig
const clap = @import("clap");
const std = @import("std");

pub fn main() !void {
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help       Display this help and exit.              ") catch unreachable,
        clap.parseParam("-v, --version    Output version information and exit.     ") catch unreachable,
        clap.parseParam("    --value <N>  An option parameter, which takes a value.") catch unreachable,
    };

    var args = try clap.parse(clap.Help, &params, .{});
    defer args.deinit();

    // clap.usage is a function that can print a simple usage message, given a
    // slice of Param(Help). There is also a usageEx, which can print a
    // usage message for any Param, but it is more verbose to call.
    if (args.flag("--help"))
        return clap.usage(std.io.getStdErr().writer(), &params);
}

```

```
$ zig-out/bin/usage --help
[-hv] [--value <N>]
```

