# zig-clap

A simple and easy to use command line argument parser library for Zig.
It's ment as a thin layer of abstraction over parsing arguments. Users
can then build on top to parse arguments into their own data structures.

## Features

See [example](https://github.com/Hejsil/zig-clap/blob/38a51948069f405864ab327826b5975a6d0c93a8/test.zig#L200-L247).
* Short arguments `-a`
  * Chaining `-abc` where `a` and `b` does not take values.
* Long arguments `--long`
* Bare arguments `bare`
* Supports both passing values using spacing and `=` (`-a 100`, `-a=100`)
  * Short args also support passing values with no spacing or `=` (`-a100`)
  * This all works with chaining (`-ba 100`, `-ba=100`, `-ba100`)

