#!/bin/sh
curl "$(curl https://ziglang.org/download/index.json | grep x86_64-linux -A 1 | head -n 2 | grep tarball | sed -E 's/.*"tarball": "([^"]*)".*/\1/g')" > zig.tar.xz
tar -xf zig.tar.xz