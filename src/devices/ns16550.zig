const std = @import("std");

pub const Ns16550 = struct {
    base: u64,

    pub fn init(base: u64) Ns16550 {
        return .{ .base = base };
    }

    pub fn read8(self: *const Ns16550, addr: u64) ?u8 {
        const lsr_addr = self.base + 0x05;
        const lsr_thre: u8 = 0x20;
        if (addr == lsr_addr) return lsr_thre;
        return null;
    }

    pub fn write8(self: *const Ns16550, addr: u64, value: u8) bool {
        if (addr != self.base) return false;
        std.debug.print("{c}", .{value});
        return true;
    }

    pub fn write32(self: *const Ns16550, addr: u64, value: u32) bool {
        if (addr != self.base) return false;
        std.debug.print("{c}", .{@as(u8, @truncate(value))});
        return true;
    }

};
