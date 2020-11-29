const builtin = @import("builtin");
const std = @import("std");

const Mode = builtin.Mode;
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for ([_]Mode{ Mode.Debug, Mode.ReleaseFast, Mode.ReleaseSafe, Mode.ReleaseSmall }) |test_mode| {
        const mode_str = comptime modeToString(test_mode);

        const tests = b.addTest("clap.zig");
        tests.setBuildMode(test_mode);
        tests.setTarget(target);
        tests.setNamePrefix(mode_str ++ " ");

        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&tests.step);
        test_all_step.dependOn(test_step);
    }

    const example_step = b.step("examples", "Build examples");
    inline for ([_][]const u8{
        "simple",
        "simple-ex",
        //"simple-error",
        "streaming-clap",
        "help",
        "usage",
    }) |example_name| {
        const example = b.addExecutable(example_name, "example/" ++ example_name ++ ".zig");
        example.addPackagePath("clap", "clap.zig");
        example.setBuildMode(mode);
        example.setTarget(target);
        example.install();
        example_step.dependOn(&example.step);
    }

    const readme_step = b.step("readme", "Remake README.");
    const readme = readMeStep(b);
    readme.dependOn(example_step);
    readme_step.dependOn(readme);

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_all_step);
    all_step.dependOn(example_step);
    all_step.dependOn(readme_step);

    b.default_step.dependOn(all_step);
}

fn readMeStep(b: *Builder) *std.build.Step {
    const s = b.allocator.create(std.build.Step) catch unreachable;
    s.* = std.build.Step.init(.Custom, "ReadMeStep", b.allocator, struct {
        fn make(step: *std.build.Step) anyerror!void {
            @setEvalBranchQuota(10000);
            const file = try std.fs.cwd().createFile("README.md", .{});
            const stream = &file.outStream();
            try stream.print(@embedFile("example/README.md.template"), .{
                @embedFile("example/simple.zig"),
                @embedFile("example/simple-error.zig"),
                @embedFile("example/streaming-clap.zig"),
                @embedFile("example/help.zig"),
                @embedFile("example/usage.zig"),
            });
        }
    }.make);
    return s;
}

fn modeToString(mode: Mode) []const u8 {
    return switch (mode) {
        Mode.Debug => "debug",
        Mode.ReleaseFast => "release-fast",
        Mode.ReleaseSafe => "release-safe",
        Mode.ReleaseSmall => "release-small",
    };
}
