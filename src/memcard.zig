const std = @import("std");
const Output = @import("output.zig").Output;

pub const Memcard = struct {
    pub const statusRegAddr: u64 = 0xf0000214;
    pub const controlRegAddr: u64 = 0xf0000210;
    pub const addressRegAddr: u64 = 0xf0000200;
    pub const bufFirstAddr: u64 = 0xf0000000;
    pub const bufLastAddr: u64 = 0xf00001ff;

    pub const controlWriteCommand: u32 = 0x80000001;
    pub const controlReadCommand: u32 = 0x80000002;

    buf: [512 / 4]u32 = [_]u32{0} ** (512 / 4),
    status: u32 = 0,
    control: u32 = 0,
    address: u32 = 0,

    pub fn get8(_: *Memcard, _: u64) i8 {
        return -1;
    }

    pub fn get16(_: *Memcard, _: u64) i16 {
        return -1;
    }

    pub fn get32(self: *Memcard, addr: u64) i32 {
        if (addr == statusRegAddr) return @bitCast(self.status);
        if (addr == controlRegAddr) return @bitCast(self.control);
        if (addr == addressRegAddr) return @bitCast(self.address);

        return @bitCast(self.buf[(addr - bufFirstAddr) / 4]);
    }

    pub fn get64(_: *Memcard, _: u64) i64 {
        return -1;
    }

    pub fn set8(_: *Memcard, out: *Output, addr: u64, val: u8) !void {
        try out.print("WARNING: {s}-bit write to non-existent device at address: 0x{X:0>8} = 0x{X:0>8}\n", .{ "8", @as(u32, @truncate(addr)), @as(u32, val) });
    }

    pub fn set16(_: *Memcard, out: *Output, addr: u64, val: u16) !void {
        try out.print("WARNING: {s}-bit write to non-existent device at address: 0x{X:0>8} = 0x{X:0>8}\n", .{ "16", @as(u32, @truncate(addr)), @as(u32, val) });
    }

    pub fn set32(self: *Memcard, out: *Output, addr: u64, val: u32) !void {
        if (addr == statusRegAddr) {
            return;
        } else if (addr == controlRegAddr) {
            try self.writeControl(out, val);
        } else if (addr == addressRegAddr) {
            self.writeAddress(val);
        } else {
            self.writeBuf(addr, val);
        }
    }

    pub fn set64(_: *Memcard, out: *Output, addr: u64, val: u64) !void {
        try out.print("WARNING: {s}-bit write to non-existent device at address: 0x{X:0>8} = 0x{X:0>8}\n", .{ "64", @as(u32, @truncate(addr)), @as(u32, @truncate(val)) });
    }

    fn writeControl(self: *Memcard, out: *Output, val: u32) !void {
        self.control = val;
        if (self.control == controlWriteCommand) {
            try out.print("{s}: Begin write operation...\n", .{self.getIdent()});
        } else if (self.control == controlReadCommand) {
            try out.print("{s}: Begin read operation...\n", .{self.getIdent()});
        } else {
            try out.print("WARNING: {s}-bit write to address 0x{X:0>8} with illegal value 0x{X:0>8}\n", .{ "32", @as(u32, @truncate(controlRegAddr)), val });
            try out.print("Invalid command value\n", .{});
        }
    }

    fn writeAddress(self: *Memcard, val: u32) void {
        self.address = val;
    }

    fn writeBuf(self: *Memcard, addr: u64, val: u32) void {
        self.buf[(addr - bufFirstAddr) / 4] = val;
    }

    pub fn getBaseAddress(_: *Memcard) u64 {
        return 0xf0000000;
    }

    pub fn getLastAddress(_: *Memcard) u64 {
        return 0xf0000217;
    }

    pub fn getIdent(_: *Memcard) []const u8 {
        return "MEMCARD";
    }
};
