const std = @import("std");
const benchmarks = @import("@bench").benchmarks;

pub fn main() !void {
    // You can configure the target time and the maximum number of executions here:
    const target = std.time.ns_per_s * 10; // Target time, in nanoseconds
    const limit = 10_000_000_000; // Maximum number of benchmark executions

    inline for (std.meta.declarations(benchmarks)) |decl| {
        if (!decl.is_pub) continue;
        if (runBench(@field(benchmarks, decl.name), target, limit)) |res| {
            std.debug.print("{s:<40} {:>10}    {} ({}/op)\n", .{
                decl.name,
                res.n,
                std.fmt.fmtDuration(res.t),
                std.fmt.fmtDuration(res.t / res.n),
            });
        } else |err| {
            if (err == error.BenchmarkCanceled) {
                std.debug.print("{s:<20} CANCELED\n", .{decl.name});
            } else {
                std.debug.print("{s:<20} FAILED: {s}\n", .{ decl.name, @errorName(err) });
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            }
        }
    }
}
fn runBench(comptime benchFn: anytype, target: u64, limit: u64) anyerror!BenchResult {
    var r = BenchResult{};
    try r.run(benchFn, 1);
    if (100 * r.t < target) {
        try r.run(benchFn, target / (100 * r.t));
    }
    while (r.t < target and r.n < limit) {
        try r.run(benchFn, r.n * (target - r.t) / r.t);
    }
    return r;
}

const BenchResult = struct {
    t: u64 = 0,
    n: u64 = 0,

    fn run(self: *BenchResult, comptime benchFn: anytype, n: u64) !void {
        var b = B{ .timer = try std.time.Timer.start(), .n = n };
        try @call(.{ .modifier = .never_inline }, benchFn, .{&b});
        self.t += b.timer.read();
        self.n += n;
    }
};

pub const B = struct {
    timer: std.time.Timer,
    n: u64,
    _i: u64 = 0,

    pub fn cancel(_: B) !void {
        return error.BenchmarkCanceled;
    }
    pub fn use(_: B, x: anytype) void {
        std.mem.doNotOptimizeAway(&x);
    }

    pub fn step(self: *B) bool {
        self._i += 1;
        return self._i <= self.n;
    }
};
