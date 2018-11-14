const builtin = @import("builtin");
const std = @import("std");

const Mode = builtin.Mode;
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const example_step = b.step("examples", "Build examples");
    inline for ([][]const u8{
        "comptime-clap",
        "streaming-clap",
    }) |example_name| {
        const example = b.addExecutable(example_name, "example/" ++ example_name ++ ".zig");
        example.addPackagePath("clap", "src/index.zig");
        example.setBuildMode(mode);
        example_step.dependOn(&example.step);
    }

    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for ([]Mode{ Mode.Debug, Mode.ReleaseFast, Mode.ReleaseSafe, Mode.ReleaseSmall }) |test_mode| {
        const mode_str = comptime modeToString(test_mode);

        const tests = b.addTest("src/index.zig");
        tests.setBuildMode(test_mode);
        tests.setNamePrefix(mode_str ++ " ");

        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&tests.step);
        test_all_step.dependOn(test_step);
    }

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_all_step);
    all_step.dependOn(example_step);

    b.default_step.dependOn(all_step);
}

fn modeToString(mode: Mode) []const u8 {
    return switch (mode) {
        Mode.Debug => "debug",
        Mode.ReleaseFast => "release-fast",
        Mode.ReleaseSafe => "release-safe",
        Mode.ReleaseSmall => "release-small",
    };
}
