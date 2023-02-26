const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    b.addModule(.{ .name = "clap", .source_file = .{ .path = "clap.zig" } });

    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "clap.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&tests.step);

    const example_step = b.step("examples", "Build examples");
    inline for (.{
        "simple",
        "simple-ex",
        "streaming-clap",
        "help",
        "usage",
    }) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = .{ .path = "example/" ++ example_name ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        example.addAnonymousModule("clap", .{ .source_file = .{ .path = "clap.zig" } });
        example.install();
        example_step.dependOn(&example.step);
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
    s.* = std.build.Step.init(.custom, "ReadMeStep", b.allocator, struct {
        fn make(step: *std.build.Step) anyerror!void {
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
    }.make);
    return s;
}
