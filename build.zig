const std = @import("std");

pub fn build(b: *std.Build) void {
    const clap_mod = b.addModule("clap", .{ .source_file = .{ .path = "clap.zig" } });

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "clap.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const example_step = b.step("examples", "Build examples");
    for ([_][]const u8{
        "simple",
        "simple-ex",
        "streaming-clap",
        "help",
        "usage",
    }) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = .{ .path = b.fmt("example/{s}.zig", .{example_name}) },
            .target = target,
            .optimize = optimize,
        });
        const install_example = b.addInstallArtifact(example, .{});
        example.addModule("clap", clap_mod);
        example_step.dependOn(&example.step);
        example_step.dependOn(&install_example.step);
    }

    const readme_step = b.step("readme", "Remake README.");
    const readme = readMeStep(b);
    readme.dependOn(example_step);
    readme_step.dependOn(readme);

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_step);
    all_step.dependOn(example_step);
    all_step.dependOn(readme_step);

    b.default_step.dependOn(all_step);
}

fn readMeStep(b: *std.Build) *std.Build.Step {
    const s = b.allocator.create(std.build.Step) catch unreachable;
    s.* = std.build.Step.init(.{
        .id = .custom,
        .name = "ReadMeStep",
        .owner = b,
        .makeFn = struct {
            fn make(step: *std.build.Step, _: *std.Progress.Node) anyerror!void {
                @setEvalBranchQuota(10000);
                _ = step;
                const file = try std.fs.cwd().createFile("README.md", .{});
                const stream = file.writer();
                try stream.print(@embedFile("example/README.md.template"), .{
                    @embedFile("example/simple.zig"),
                    @embedFile("example/simple-ex.zig"),
                    @embedFile("example/streaming-clap.zig"),
                    @embedFile("example/help.zig"),
                    @embedFile("example/usage.zig"),
                });
            }
        }.make,
    });
    return s;
}
