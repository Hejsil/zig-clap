# zig-clap

An easy to use command line argument parser library for Zig.

## Features

See [example](example.zig).

* Assosiate arguements with fields of a struct.
  * When an arguement is found by the clap, the field is set to a parsed version of the value.
  * `zig-clap` provides some default parses, but you can make your own as well.
* Short arguments `-a`
  * Chaining `-abc` where `a` and `b` does not take values.
* Long arguments `--long`
* Supports both passing values using spacing and `=` (`-a 100`, `-a=100`)
  * Short args also support passing values with no spacing or `=` (`-a100`)
  * This all works with chaining (`-ba 100`, `-ba=100`, `-ba100`)
