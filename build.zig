const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    {
        const example_step = b.step("examples", "Build all examples");
        const examples = [][]const u8{};

        b.default_step.dependOn(example_step);
        inline for (examples) |example| {
            comptime const path = "examples/" ++ example ++ ".zig";
            const exe = b.addExecutable(example, path);
            exe.setBuildMode(mode);
            exe.addPackagePath("clap", "index.zig");

            const step = b.step("build-" ++ example, "Build '" ++ path ++ "'");
            step.dependOn(&exe.step);
            example_step.dependOn(step);
        }
    }

    {
        const test_step = b.step("tests", "Run all tests");
        const tests = [][]const u8{
            "core",
            "extended",
        };

        b.default_step.dependOn(test_step);
        inline for (tests) |test_name| {
            comptime const path = "tests/" ++ test_name ++ ".zig";
            const t = b.addTest(path);
            t.setBuildMode(mode);
            //t.addPackagePath("clap", "index.zig");

            const step = b.step("test-" ++ test_name, "Run test '" ++ test_name ++ "'");
            step.dependOn(&t.step);
            test_step.dependOn(step);
        }
    }
}
