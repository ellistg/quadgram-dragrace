const std = @import("std");
const Deps = @import("Deps.zig");

pub fn build(b: *std.build.Builder) void {
    const safe = b.option(bool, "safe", "Build in ReleaseSafe mode rather than ReleaseFast") orelse false;

    const deps = Deps.init(b);
    deps.add("https://github.com/silversquirl/zcompute", "main");
    deps.addPackagePath("@bench", "benchmarks.zig");

    const exe = b.addExecutable("benchmark", "benchmark.zig");
    deps.addTo(exe);
    exe.linkLibC();
    exe.setBuildMode(if (safe) .ReleaseSafe else .ReleaseFast);
    exe.install();

    b.step("run", "Run the benchmarks").dependOn(&exe.run().step);

    const t = b.addTest("gpu.zig");
    deps.addTo(t);
    t.linkLibC();
    b.step("test", "Run tests").dependOn(&t.step);
}
