const std = @import("std");
const clap = @import("clap").core;

const debug = std.debug;
const mem = std.mem;

const Names = clap.Names;
const Param = clap.Param;

const Command = enum {
    Help,
    Build,
    BuildExe,
    BuildLib,
    BuildObj,
    Fmt,
    Run,
    Targets,
    Test,
    Version,
    Zen,
};

const params = []Param(Command){
    Param(Command).init(Command.Help, false, Names.prefix("help")),
    Param(Command).init(Command.Build, false, Names.bare("build")),
    Param(Command).init(Command.BuildExe, false, Names.bare("build-exe")),
    Param(Command).init(Command.BuildLib, false, Names.bare("build-lib")),
    Param(Command).init(Command.BuildObj, false, Names.bare("build-obj")),
    Param(Command).init(Command.Fmt, false, Names.bare("fmt")),
    Param(Command).init(Command.Run, false, Names.bare("run")),
    Param(Command).init(Command.Targets, false, Names.bare("targets")),
    Param(Command).init(Command.Test, false, Names.bare("test")),
    Param(Command).init(Command.Version, false, Names.bare("version")),
    Param(Command).init(Command.Zen, false, Names.bare("zen")),
};

const usage =
    \\usage: zig [command] [options]
    \\
    \\Commands:
    \\
    \\  build                        Build project from build.zig
    \\  build-exe   [source]         Create executable from source or object files
    \\  build-lib   [source]         Create library from source or object files
    \\  build-obj   [source]         Create object from source or assembly
    \\  fmt         [source]         Parse file and render in canonical zig format
    \\  run         [source]         Create executable and run immediately
    \\  targets                      List available compilation targets
    \\  test        [source]         Create and run a test build
    \\  translate-c [source]         Convert c code to zig code
    \\  version                      Print version number and exit
    \\  zen                          Print zen of zig and exit
    \\
    \\
;

pub fn main() !void {
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();
    var arena = std.heap.ArenaAllocator.init(&direct_allocator.allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    var args = clap.OsArgIterator.init();
    var parser = clap.Clap(Command).init(params, &args.iter, allocator);
    defer parser.deinit();

    const exe = try parser.nextNoParse();
    const maybe_arg = parser.next() catch |err| b: {
        debug.warn("{}.\n", @errorName(err));
        // debug.warn(usage); TODO: error: evaluation exceeded 1000 backwards branches
        return err;
    };
    const arg = maybe_arg ?? {
        debug.warn("No command found.\n");
        // debug.warn(usage); TODO: error: evaluation exceeded 1000 backwards branches
        return error.NoCommandFound;
    };

    switch (arg.id) {
        Command.Help => return, // debug.warn(usage), TODO: error: evaluation exceeded 1000 backwards branches
        Command.Build => try cmdBuild(allocator, parser.iter),
        Command.BuildExe,
        Command.BuildLib,
        Command.BuildObj,
        Command.Fmt,
        Command.Run,
        Command.Targets,
        Command.Test,
        Command.Version,
        Command.Zen => unreachable,
    }
}

// cmd:build ///////////////////////////////////////////////////////////////////////////////////////

const BuildArg = enum {
    Help,
    Init,
    BuildFile,
    CacheDir,
    Verbose,
    Prefix,
    VerboseTokenize,
    VerboseAst,
    VerboseLink,
    VerboseIr,
    VerboseLlvmIr,
    VerboseCImport,
};

const build_params = []Param(BuildArg){
    Param(BuildArg).init(BuildArg.Help, false, Names.prefix("help")),
    Param(BuildArg).init(BuildArg.Init, false, Names.long("init")),
    Param(BuildArg).init(BuildArg.BuildFile, true, Names.long("build-file")),
    Param(BuildArg).init(BuildArg.CacheDir, true, Names.long("cache-dir")),
    Param(BuildArg).init(BuildArg.Verbose, false, Names.prefix("verbose")),
    Param(BuildArg).init(BuildArg.Prefix, true, Names.long("prefix")),

    Param(BuildArg).init(BuildArg.VerboseTokenize, false, Names.prefix("verbose-tokenize")),
    Param(BuildArg).init(BuildArg.VerboseAst, false, Names.prefix("verbose-ast")),
    Param(BuildArg).init(BuildArg.VerboseLink, false, Names.prefix("verbose-link")),
    Param(BuildArg).init(BuildArg.VerboseIr, false, Names.prefix("verbose-ir")),
    Param(BuildArg).init(BuildArg.VerboseLlvmIr, false, Names.prefix("verbose-llvm-ir")),
    Param(BuildArg).init(BuildArg.VerboseCImport, false, Names.prefix("verbose-cimport")),
};

const build_usage =
    \\usage: zig build <options>
    \\
    \\General Options:
    \\   -h, --help                   Print this help and exit
    \\       --init                   Generate a build.zig template
    \\       --build-file [file]      Override path to build.zig
    \\       --cache-dir [path]       Override path to cache directory
    \\   -v, --verbose                Print commands before executing them
    \\       --prefix [path]          Override default install prefix
    \\
    \\Project-Specific Options:
    \\
    \\   Project-specific options become available when the build file is found.
    \\
    \\Advanced Options:
    \\       --verbose-tokenize       Enable compiler debug output for tokenization
    \\       --verbose-ast            Enable compiler debug output for parsing into an AST
    \\       --verbose-link           Enable compiler debug output for linking
    \\       --verbose-ir             Enable compiler debug output for Zig IR
    \\       --verbose-llvm-ir        Enable compiler debug output for LLVM IR
    \\       --verbose-cimport        Enable compiler debug output for C imports
    \\
    \\
;

const missing_build_file =
    \\No 'build.zig' file found.
    \\
    \\Initialize a 'build.zig' template file with `zig build --init`,
    \\or build an executable directly with `zig build-exe $FILENAME.zig`.
    \\
    \\See: `zig build --help` or `zig help` for more options.
    \\
;

fn cmdBuild(allocator: &mem.Allocator, args: &clap.ArgIterator) !void {
    var init = false;
    var build_file: []const u8 = "build.zig";
    var cache_dir: []const u8 = "zig-cache";
    var verbose = false;
    var prefix: []const u8 = "";
    var verbose_tokenize = false;
    var verbose_ast = false;
    var verbose_link = false;
    var verbose_ir = false;
    var verbose_llvm_ir = false;
    var verbose_cimport = false;

    var parser = clap.Clap(BuildArg).init(build_params, args, allocator);
    defer parser.deinit();

    while (parser.next() catch |err| {
        debug.warn("{}.\n", @errorName(err));
        // debug.warn(build_usage); TODO: error: evaluation exceeded 1000 backwards branches
        return err;
    }) |arg| switch (arg.id) {
        BuildArg.Help => return, // debug.warn(build_usage) TODO: error: evaluation exceeded 1000 backwards branches,
        BuildArg.Init => init = true,
        BuildArg.BuildFile => build_file = ??arg.value,
        BuildArg.CacheDir => cache_dir = ??arg.value,
        BuildArg.Verbose => verbose = true,
        BuildArg.Prefix => prefix = ??arg.value,
        BuildArg.VerboseTokenize => verbose_tokenize = true,
        BuildArg.VerboseAst => verbose_ast = true,
        BuildArg.VerboseLink => verbose_link = true,
        BuildArg.VerboseIr => verbose_ir = true,
        BuildArg.VerboseLlvmIr => verbose_llvm_ir = true,
        BuildArg.VerboseCImport => verbose_cimport = true,
    };

    debug.warn("command: build\n");
    debug.warn("init             = {}\n", init);
    debug.warn("build_file       = {}\n", build_file);
    debug.warn("cache_dir        = {}\n", cache_dir);
    debug.warn("verbose          = {}\n", verbose);
    debug.warn("prefix           = {}\n", prefix);
    debug.warn("verbose_tokenize = {}\n", verbose_tokenize);
    debug.warn("verbose_ast      = {}\n", verbose_ast);
    debug.warn("verbose_link     = {}\n", verbose_link);
    debug.warn("verbose_ir       = {}\n", verbose_ir);
    debug.warn("verbose_llvm_ir  = {}\n", verbose_llvm_ir);
    debug.warn("verbose_cimport  = {}\n", verbose_cimport);
}

// cmd:build-exe ///////////////////////////////////////////////////////////////////////////////////

const BuildGeneric = enum {
    File,
    Help,
    Color,

    Assembly,
    CacheDir,
    Emit,
    EnableTimingInfo,
    LibCDir,
    Name,
    Output,
    OutputH,
    PkgBegin,
    PkgEnd,
    ReleaseFast,
    ReleaseSafe,
    Static,
    Strip,
    TargetArch,
    TargetEnviron,
    TargetOs,
    VerboseTokenize,
    VerboseAst,
    VerboseLink,
    VerboseIr,
    VerboseLlvmIr,
    VerboseCImport,
    DirAfter,
    ISystem,
    MLlvm,

    ArPath,
    DynamicLinker,
    EachLibRPath,
    LibcLibDir,
    LibcStaticLibDir,
    MsvcLibDir,
    Kernel32LibDir,
    Library,
    ForbidLibrary,
    LibraryPath,
    LinkerScript,
    Object,
    RDynamic,
    RPath,
    MConsole,
    MWindows,
    Framework,
    MiOsVersionMin,
    MMacOsXVersonMin,
    VerMajor,
    VerMinor,
    VerPatch,
};

const build_generic_params = []Param(BuildArg){
    Param(BuildArg).init(BuildArg.Help, false, Names.prefix("help")),
};

const build_generic_usage =
    \\usage: zig build-exe <options> [file]
    \\       zig build-lib <options> [file]
    \\       zig build-obj <options> [file]
    \\
    \\General Options:
    \\  -h, --help                       Print this help and exit
    \\  -c, --color [auto|off|on]        Enable or disable colored error messages
    \\
    \\Compile Options:
    \\  --assembly [source]          Add assembly file to build
    \\  --cache-dir [path]           Override the cache directory
    \\  --emit [filetype]            Emit a specific file format as compilation output
    \\  --enable-timing-info         Print timing diagnostics
    \\  --libc-include-dir [path]    Directory where libc stdlib.h resides
    \\  --name [name]                Override output name
    \\  --output [file]              Override destination path
    \\  --output-h [file]            Override generated header file path
    \\  --pkg-begin [name] [path]    Make package available to import and push current pkg
    \\  --pkg-end                    Pop current pkg
    \\  --release-fast               Build with optimizations on and safety off
    \\  --release-safe               Build with optimizations on and safety on
    \\  --static                     Output will be statically linked
    \\  --strip                      Exclude debug symbols
    \\  --target-arch [name]         Specify target architecture
    \\  --target-environ [name]      Specify target environment
    \\  --target-os [name]           Specify target operating system
    \\  --verbose-tokenize           Turn on compiler debug output for tokenization
    \\  --verbose-ast-tree           Turn on compiler debug output for parsing into an AST (tree view)
    \\  --verbose-ast-fmt            Turn on compiler debug output for parsing into an AST (render source)
    \\  --verbose-link               Turn on compiler debug output for linking
    \\  --verbose-ir                 Turn on compiler debug output for Zig IR
    \\  --verbose-llvm-ir            Turn on compiler debug output for LLVM IR
    \\  --verbose-cimport            Turn on compiler debug output for C imports
    \\  --dirafter [dir]             Same as --isystem but do it last
    \\  --isystem [dir]              Add additional search path for other .h files
    \\  --mllvm [arg]                Additional arguments to forward to LLVM's option processing
    \\
    \\Link Options:
    \\  --ar-path [path]             Set the path to ar
    \\  --dynamic-linker [path]      Set the path to ld.so
    \\  --each-lib-rpath             Add rpath for each used dynamic library
    \\  --libc-lib-dir [path]        Directory where libc crt1.o resides
    \\  --libc-static-lib-dir [path] Directory where libc crtbegin.o resides
    \\  --msvc-lib-dir [path]        (windows) directory where vcruntime.lib resides
    \\  --kernel32-lib-dir [path]    (windows) directory where kernel32.lib resides
    \\  --library [lib]              Link against lib
    \\  --forbid-library [lib]       Make it an error to link against lib
    \\  --library-path [dir]         Add a directory to the library search path
    \\  --linker-script [path]       Use a custom linker script
    \\  --object [obj]               Add object file to build
    \\  --rdynamic                   Add all symbols to the dynamic symbol table
    \\  --rpath [path]               Add directory to the runtime library search path
    \\  --mconsole                   (windows) --subsystem console to the linker
    \\  --mwindows                   (windows) --subsystem windows to the linker
    \\  --framework [name]           (darwin) link against framework
    \\  --mios-version-min [ver]     (darwin) set iOS deployment target
    \\  --mmacosx-version-min [ver]  (darwin) set Mac OS X deployment target
    \\  --ver-major [ver]            Dynamic library semver major version
    \\  --ver-minor [ver]            Dynamic library semver minor version
    \\  --ver-patch [ver]            Dynamic library semver patch version
    \\
    \\
;
