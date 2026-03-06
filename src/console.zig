const std = @import("std");
const Output = @import("output.zig").Output;

pub const Console = struct {
    pub fn get8(_: *Console, _: u64) i8 {
        return -1;
    }

    pub fn get16(_: *Console, _: u64) i16 {
        return -1;
    }

    pub fn get32(_: *Console, _: u64) i32 {
        return -1;
    }

    pub fn get64(_: *Console, _: u64) i64 {
        return -1;
    }

    pub fn set8(_: *Console, _: *Output, _: u64, val: u8) !void {
        const ch = [1]u8{val};
        var stdout = std.fs.File.stdout();
        try stdout.writeAll(&ch);
    }

    pub fn set16(self: *Console, out: *Output, addr: u64, val: u16) !void {
        _ = self;
        _ = out;
        _ = addr;
        _ = val;
    }

    pub fn set32(self: *Console, out: *Output, addr: u64, val: u32) !void {
        _ = self;
        _ = out;
        _ = addr;
        _ = val;
    }

    pub fn set64(self: *Console, out: *Output, addr: u64, val: u64) !void {
        _ = self;
        _ = out;
        _ = addr;
        _ = val;
    }

    pub fn getBaseAddress(_: *Console) u64 {
        return 0xffff0001;
    }

    pub fn getLastAddress(_: *Console) u64 {
        return 0xffff0001;
    }

    pub fn getIdent(_: *Console) []const u8 {
        return "CON";
    }
};
