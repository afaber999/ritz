const std = @import("std");

pub const base: u64 = 0x10000000;
const lsr_addr: u64 = base + 0x05;
const lsr_thre: u8 = 0x20;

pub fn read8(addr: u64) ?u8 {
    if (addr == lsr_addr) return lsr_thre;
    return null;
}

pub fn write8(addr: u64, value: u8) bool {
    if (addr != base) return false;
    std.debug.print("{c}", .{value});
    return true;
}
