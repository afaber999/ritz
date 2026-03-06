const std = @import("std");
const Devices = @import("devices.zig").Devices;
const Output = @import("output.zig").Output;

pub const devBaseAddress: u32 = 0xf0000000;

pub const Memory = struct {
    data: []u8,
    start: u64,
    len: u64,
    memoryWarnings: i32 = 1,
    dev: *Devices,
    out: *Output,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, start: u64, length: u64, dev: *Devices, out: *Output) !Memory {
        const data = try allocator.alloc(u8, length);
        @memset(data, 0xa5);
        return .{
            .data = data,
            .start = start,
            .len = length,
            .memoryWarnings = 1,
            .dev = dev,
            .out = out,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Memory) void {
        self.allocator.free(self.data);
    }

    pub fn get8(self: *Memory, addr: u64) !i8 {
        if (addr >= devBaseAddress) {
            return self.dev.get8(addr);
        }

        if (addr < self.start or addr >= self.start + self.len) {
            if (self.memoryWarnings != 0) {
                try self.out.print("WARNING: accessing non-existent memory at address: 0x{X:0>8}\n", .{@as(u32, @truncate(addr))});
            }
            return @bitCast(@as(u8, 0xff));
        }

        return @bitCast(self.data[addr - self.start]);
    }

    pub fn get16(self: *Memory, addr: u64) !i16 {
        if (addr >= devBaseAddress) {
            return self.dev.get16(addr);
        }

        const b0: u16 = @as(u16, @as(u8, @bitCast(try self.get8(addr))));
        const b1: u16 = @as(u16, @as(u8, @bitCast(try self.get8(addr + 1))));
        return @bitCast(b0 | (b1 << 8));
    }

    pub fn get32(self: *Memory, addr: u64) !i32 {
        if (addr >= devBaseAddress) {
            return self.dev.get32(addr);
        }

        const l: u32 = @as(u32, @as(u16, @bitCast(try self.get16(addr))));
        const h: u32 = @as(u32, @as(u16, @bitCast(try self.get16(addr + 2))));
        return @bitCast(l | (h << 16));
    }

    pub fn get64(self: *Memory, addr: u64) !i64 {
        if (addr >= devBaseAddress) {
            return self.dev.get64(addr);
        }

        const l: u64 = @as(u64, @as(u32, @bitCast(try self.get32(addr))));
        const h: u64 = @as(u64, @as(u32, @bitCast(try self.get32(addr + 4))));
        return @bitCast(l | (h << 32));
    }

    pub fn set8(self: *Memory, addr: u64, val: u8) !void {
        if (addr >= devBaseAddress) {
            return self.dev.set8(addr, val);
        }

        if (addr < self.start or addr >= self.start + self.len) {
            if (self.memoryWarnings != 0) {
                try self.out.print("WARNING: accessing non-existent memory at address: 0x{X:0>8}\n", .{@as(u32, @truncate(addr))});
            }
            return;
        }

        self.data[addr - self.start] = val;
    }

    pub fn set16(self: *Memory, addr: u64, val: u16) !void {
        if (addr >= devBaseAddress) {
            return self.dev.set16(addr, val);
        }

        try self.set8(addr, @as(u8, @truncate(val & 0x00ff)));
        try self.set8(addr + 1, @as(u8, @truncate((val >> 8) & 0x00ff)));
    }

    pub fn set32(self: *Memory, addr: u64, val: u32) !void {
        if (addr >= devBaseAddress) {
            return self.dev.set32(addr, val);
        }

        try self.set16(addr, @as(u16, @truncate(val & 0x0000ffff)));
        try self.set16(addr + 2, @as(u16, @truncate((val >> 16) & 0x0000ffff)));
    }

    pub fn set64(self: *Memory, addr: u64, val: u64) !void {
        if (addr >= devBaseAddress) {
            return self.dev.set32(addr, @as(u32, @truncate(val)));
        }

        try self.set32(addr, @as(u32, @truncate(val & 0x0000_0000_ffff_ffff)));
        try self.set32(addr + 4, @as(u32, @truncate((val >> 32) & 0x0000_0000_ffff_ffff)));
    }

    pub fn readRaw(self: *Memory, filename: []const u8, addr: u64) !void {
        const cwd = std.fs.cwd();
        var file = cwd.openFile(filename, .{}) catch |err| {
            std.debug.print("Failed to open file '{s}', Reason: {s}\n", .{ filename, @errorName(err) });
            return;
        };
        defer file.close();

        const offset = addr - self.start;
        if (offset >= self.len) return;

        _ = try file.readAll(self.data[offset..]);
    }

    pub fn dump(self: *Memory, addr: u64, length: u64) !void {
        if (length == 0) return;

        var i: usize = 0;
        var j: u64 = addr;
        var ascii: [20]u8 = [_]u8{0} ** 20;

        var startingoffset = @as(usize, @intCast(addr % 16));
        if (startingoffset != 0) {
            try self.out.print(" {X:0>8}:{s}", .{ @as(u32, @truncate(addr & ~@as(u64, 0x0f))), if (startingoffset > 8) " " else "" });
            for (0..startingoffset) |_| {
                try self.out.print("   ", .{});
            }
        }

        while (j < addr + length) : (j += 1) {
            const ch_i8 = try self.get8(j);
            const ch: u8 = @bitCast(ch_i8);
            if ((j % 16) == 0) {
                if (j > addr) {
                    ascii[i] = 0;
                    try self.out.print(" ", .{});
                    for (0..startingoffset) |_| {
                        try self.out.print(" ", .{});
                    }
                    try self.out.print("*{s}*\n", .{std.mem.sliceTo(ascii[0..], 0)});
                    startingoffset = 0;
                }
                try self.out.print(" {X:0>8}:", .{@as(u32, @truncate(j))});
                i = 0;
            }

            try self.out.print("{s}{X:0>2}", .{ if (j % 8 == 0 and j % 16 != 0) "  " else " ", ch });

            ascii[i] = if (std.ascii.isPrint(ch)) ch else '.';
            i += 1;
        }

        if (j % 16 != 0 and j % 16 < 9) {
            try self.out.print(" ", .{});
        }
        while (j % 16 != 0) : (j += 1) {
            try self.out.print("   ", .{});
        }
        ascii[i] = 0;
        try self.out.print(" *{s}*\n", .{std.mem.sliceTo(ascii[0..], 0)});
    }
};
