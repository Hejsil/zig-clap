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

```rust
const params = []clap.Param(u8){
    clap.Param(u8).flag('h', clap.Names.both("help")),
    clap.Param(u8).option('n', clap.Names.both("number")),
    clap.Param(u8).positional('f'),
};

var iter = clap.args.OsIterator.init(allocator);
defer iter.deinit();
const exe = try iter.next();

var parser = clap.StreamingClap(u8, clap.args.OsIterator).init(params, &iter);

while (try parser.next()) |arg| {
    switch (arg.param.id) {
        'h' => debug.warn("Help!\n"),
        'n' => debug.warn("--number = {}\n", arg.value.?),
        'f' => debug.warn("{}\n", arg.value.?),
        else => unreachable,
    }
}
```

### `ComptimeClap`

The `ComptimeClap` is a wrapper for `StreamingClap`, which parses all the arguments and makes
them available through three functions (`flag`, `option`, `positionals`).

```rust
const params = comptime []clap.Param(void){
    clap.Param(void).flag({}, clap.Names.both("help")),
    clap.Param(void).option({}, clap.Names.both("number")),
    clap.Param(void).positional({}),
};

var iter = clap.args.OsIterator.init(allocator);
defer iter.deinit();
const exe = try iter.next();

var args = try clap.ComptimeClap(void, params).parse(allocator, clap.args.OsIterator, &iter);
defer args.deinit();

if (args.flag("--help"))
    debug.warn("Help!\n");
if (args.option("--number")) |n|
    debug.warn("--number = {}\n", n);
for (args.positionals()) |pos|
    debug.warn("{}\n", pos);
```

The data structure returned from this parser has lookup speed on par with array access (`arr[i]`)
and validates that the strings you pass to `option` and `flag` are actually parameters that the
program can take:

```rust
const params = comptime []clap.Param(void){
    clap.Param(void).flag({}, clap.Names.both("help")),
};

var os_iter = clap.args.OsIterator.init(allocator);
const iter = &os_iter.iter;
defer os_iter.deinit();

var iter = clap.args.OsIterator.init(allocator);
defer iter.deinit();
const exe = try iter.next();

var args = try clap.ComptimeClap(void, params).parse(allocator, clap.args.OsIterator, &iter);
defer args.deinit();

if (args.flag("--helps"))
    debug.warn("Help!\n");
```

```
zig-clap/src/comptime.zig:103:17: error: --helps is not a parameter.
                @compileError(name ++ " is not a parameter.");
                ^
zig-clap/src/comptime.zig:71:45: note: called from here
            const param = comptime findParam(name);
                                            ^
zig-clap/example/comptime-clap.zig:41:18: note: called from here
    if (args.flag("--helps"))
                 ^
```

Ofc, this limits you to parameters that are comptime known.

### `help`

The `help`, `helpEx` and `helpFull` are functions for printing a simple list of all parameters the
program can take.

```rust
const stderr_file = try std.io.getStdErr();
var stderr_out_stream = stderr_file.outStream();
const stderr = &stderr_out_stream.stream;

try clap.help(
    stderr,
    []clap.Param([]const u8){
        clap.Param([]const u8).flag(
            "Display this help and exit.",
            clap.Names.both("help"),
        ),
        clap.Param([]const u8).flag(
            "Output version information and exit.",
            clap.Names.both("version"),
        ),
    },
);
```

```
        -h, --help      Display this help and exit.
        -v, --version   Output version information and exit.
```

The `help` function is the simplest to call. It only takes an `OutStream` and a slice of
`Param([]const u8)`. This function assumes that the id of each parameter is the help message.

The `helpEx` is the generic version of `help`. It can print a help message for any
`Param` give that the caller provides functions for getting the help and value strings.

The `helpFull` is even more generic, allowing the functions that get the help and value strings
to return errors and take a context as a parameter.
