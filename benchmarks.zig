const std = @import("std");
const B = @import("root").B;
const gpu = @import("gpu.zig");

const quadgrams = @import("quadgrams.zig").quadgram_log_freq;
const quadgrams_int = @import("quadgrams_int.zig").quadgram_log_freq;

const Vector = std.meta.Vector;

fn quadFitness(text: []const u8, step: usize) f32 {
    var fitness: f32 = 0.0;
    var i: usize = 0;

    const coef = std.meta.Vector(4, u32){ 17576, 676, 26, 1 };
    while (i < text.len - 3) : (i += step) {
        const qg8: std.meta.Vector(4, u8) = text[i..][0..4].*;
        const qgn: std.meta.Vector(4, u8) = qg8 & @splat(4, @as(u8, 31));
        const qg: std.meta.Vector(4, u32) = qgn - @splat(4, @as(u8, 1));
        const pos = @reduce(.Add, qg * coef);
        fitness += quadgrams[pos];
    }
    return fitness;
}

fn quadFitnessNorm(text: []const u8, step: usize) f32 {
    var fitness: f32 = 0.0;
    const coef = std.meta.Vector(4, u32){ 17576, 676, 26, 1 };

    var i: usize = 0;
    while (i < text.len - 3) : (i += step) {
        const qg8: std.meta.Vector(4, u8) = text[i..][0..4].*;
        const qg: std.meta.Vector(4, u32) = qg8;
        const pos = @reduce(.Add, qg * coef);
        fitness += quadgrams[pos];
    }
    return fitness;
}

fn quadFitnessMulti(text: []const u8, _: usize) f32 {
    var fitness: f32 = 0.0;

    const coefs = [_]std.meta.Vector(16, u32){
        @splat(16, @as(u32, 17576)),
        @splat(16, @as(u32, 676)),
        @splat(16, @as(u32, 26)),
        @splat(16, @as(u32, 1)),
    };

    var i: usize = 0;
    while (i < text.len - 19) : (i += 16) {
        var idxs: std.meta.Vector(16, u32) = @splat(16, @as(u32, 0));

        inline for (.{ 0, 1, 2, 3 }) |d| {
            const qg8: std.meta.Vector(16, u8) = text[i + d ..][0..16].*;
            const qg: std.meta.Vector(16, u32) = qg8;
            idxs += qg * coefs[d];
        }

        for (@as([16]u32, idxs)) |idx| {
            fitness += quadgrams[idx];
        }
    }
    return fitness;
}

fn quadFitnessMultiInt(text: []const u8, _: usize) u32 {
    @setRuntimeSafety(false);
    var fitness: u32 = 0;

    const coefs = [_]std.meta.Vector(16, u32){
        @splat(16, @as(u32, 17576)),
        @splat(16, @as(u32, 676)),
        @splat(16, @as(u32, 26)),
        @splat(16, @as(u32, 1)),
    };

    var i: usize = 0;
    while (i < text.len - 19) : (i += 16) {
        var idxs: std.meta.Vector(16, u32) = @splat(16, @as(u32, 0));

        inline for (.{ 0, 1, 2, 3 }) |d| {
            const qg8: std.meta.Vector(16, u8) = text[i + d ..][0..16].*;
            const qg: std.meta.Vector(16, u32) = qg8;
            idxs += qg * coefs[d];
        }

        for (@as([16]u32, idxs)) |idx| {
            fitness += quadgrams_int[idx];
        }
    }
    return fitness;
}

pub const benchmarks = struct {
    pub fn multiGpu(b: *B) !void {
        var rand = std.rand.DefaultPrng.init(1234456);

        var texts: [1000][10_000]u8 = undefined;
        for (texts) |*text| {
            for (text.*) |*ch| {
                ch.* = rand.random().intRangeAtMost(u8, 0, 25);
            }
        }

        var ctx: gpu.GpuContext = undefined;
        try ctx.init();
        defer ctx.deinit();

        b.timer.reset();
        // This is the actual benchmark, which will be run a variable number of times to meet the target time
        var count: usize = 0;
        while (b.step()) {
            const text = texts[count % 1000];
            count += 1;

            std.mem.doNotOptimizeAway(try ctx.quadFitness(&text, 1));
        }
    }

    pub fn multiInt(b: *B) !void {
        var rand = std.rand.DefaultPrng.init(1234456);

        var texts: [1000][10_000]u8 = undefined;
        for (texts) |*text| {
            for (text.*) |*ch| {
                ch.* = rand.random().intRangeAtMost(u8, 0, 25);
            }
        }

        b.timer.reset();
        // This is the actual benchmark, which will be run a variable number of times to meet the target time
        var count: usize = 0;
        while (b.step()) {
            const text = texts[count % 1000];
            count += 1;

            std.mem.doNotOptimizeAway(quadFitnessMultiInt(&text, 1));
        }
    }

    pub fn original(b: *B) !void {
        var rand = std.rand.DefaultPrng.init(1234456);

        var texts: [1000][1000]u8 = undefined;
        for (texts) |*text| {
            for (text.*) |*ch| {
                ch.* = rand.random().intRangeAtMost(u8, 'a', 'z');
            }
        }

        b.timer.reset();
        // This is the actual benchmark, which will be run a variable number of times to meet the target time
        var count: usize = 0;
        while (b.step()) {
            const text = texts[count % 1000];
            count += 1;

            std.mem.doNotOptimizeAway(quadFitness(&text, 1));
        }
    }

    pub fn normalized(b: *B) !void {
        var rand = std.rand.DefaultPrng.init(1234456);

        var texts: [1000][1000]u8 = undefined;
        for (texts) |*text| {
            for (text.*) |*ch| {
                ch.* = rand.random().intRangeAtMost(u8, 0, 25);
            }
        }

        b.timer.reset();
        // This is the actual benchmark, which will be run a variable number of times to meet the target time
        var count: usize = 0;
        while (b.step()) {
            const text = texts[count % 1000];
            count += 1;

            std.mem.doNotOptimizeAway(quadFitnessNorm(&text, 1));
        }
    }

    pub fn multi(b: *B) !void {
        var rand = std.rand.DefaultPrng.init(1234456);

        var texts: [1000][1000]u8 = undefined;
        for (texts) |*text| {
            for (text.*) |*ch| {
                ch.* = rand.random().intRangeAtMost(u8, 0, 25);
            }
        }

        b.timer.reset();
        // This is the actual benchmark, which will be run a variable number of times to meet the target time
        var count: usize = 0;
        while (b.step()) {
            const text = texts[count % 1000];
            count += 1;

            std.mem.doNotOptimizeAway(quadFitnessMulti(&text, 1));
        }
    }
};
