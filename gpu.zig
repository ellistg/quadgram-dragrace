const std = @import("std");
const zc = @import("zcompute");
const quadgrams_int = @import("quadgrams_int.zig").quadgram_log_freq;

pub const GpuContext = struct {
    ctx: zc.Context,
    shad: Shader,
    qg: zc.Buffer(u32),
    res: zc.Buffer(u32),
    text: zc.Buffer(u8),

    pub fn init(self: *GpuContext) !void {
        self.ctx = try zc.Context.init(std.heap.c_allocator, .{});
        errdefer self.ctx.deinit();

        self.shad = try Shader.initBytes(&self.ctx, @embedFile("quad_fitness.spv"));
        errdefer self.shad.deinit();

        self.qg = try zc.Buffer(u32).init(&self.ctx, quadgrams_int.len, .{
            .map = true,
            .storage = true,
        });
        errdefer self.qg.deinit();

        {
            const mem = try self.qg.map();
            defer self.qg.unmap();
            std.mem.copy(u32, mem, &quadgrams_int);
        }

        self.res = try zc.Buffer(u32).init(&self.ctx, 1, .{
            .map = true,
            .storage = true,
        });
        errdefer self.res.deinit();

        self.text.len = 0;
    }

    pub fn deinit(self: GpuContext) void {
        if (self.text.len > 0) {
            self.text.deinit();
        }
        self.res.deinit();
        self.qg.deinit();
        self.shad.deinit();
        self.ctx.deinit();
    }

    pub fn quadFitness(self: *GpuContext, text: []const u8, step: u32) !u32 {
        if (self.text.len < text.len) {
            if (self.text.len > 0) {
                self.text.deinit();
            }
            self.text = try zc.Buffer(u8).init(&self.ctx, text.len, .{
                .map = true,
                .storage = true,
            });
        }

        {
            const mem = try self.text.map();
            defer self.text.unmap();
            for (text) |ch, i| {
                mem[i] = ch;
            }
        }
        {
            const mem = try self.res.map();
            defer self.res.unmap();
            mem[0] = 0;
        }

        try self.shad.exec(null, .{
            .x = @intCast(u32, text.len) - 3,
        }, .{
            .quadgrams = self.qg,
            .step = step,
            .text = self.text,
            .result = self.res,
        });
        try self.shad.wait();

        {
            const mem = try self.res.map();
            defer self.res.unmap();
            return mem[0];
        }
    }

    const Shader = zc.Shader(&.{
        zc.storageBuffer("quadgrams", 0, zc.Buffer(u32)),
        zc.pushConstant("step", 0, u32),
        zc.storageBuffer("text", 1, zc.Buffer(u8)),
        zc.storageBuffer("result", 2, zc.Buffer(u32)),
    });
};

fn quadFitnessInt(text: []const u8, step: usize) u32 {
    var fitness: u32 = 0;
    const coef = std.meta.Vector(4, u32){ 17576, 676, 26, 1 };

    var i: usize = 0;
    while (i < text.len - 3) : (i += step) {
        const qg8: std.meta.Vector(4, u8) = text[i..][0..4].*;
        const qg: std.meta.Vector(4, u32) = qg8;
        const pos = @reduce(.Add, qg * coef);
        fitness += quadgrams_int[pos];
    }
    return fitness;
}

test "gpu" {
    var rand = std.rand.DefaultPrng.init(1234456);

    var ctx: GpuContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        var text: [1000]u8 = undefined;
        for (text) |*ch| {
            ch.* = rand.random().intRangeAtMost(u8, 0, 25);
        }
        const expected = quadFitnessInt(&text, 1);
        const res = try ctx.quadFitness(&text, 1);
        if (expected != res) {
            std.debug.print("iter {}: expected {}, got {}\n", .{ i, expected, res });
            return error.TestExpectedEqual;
        }
    }
}
