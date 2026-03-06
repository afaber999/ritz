const std = @import("std");
const Output = @import("output.zig").Output;
const Console = @import("console.zig").Console;
const Memcard = @import("memcard.zig").Memcard;

pub const Device = union(enum) {
    console: Console,
    memcard: Memcard,

    pub fn get8(self: *Device, addr: u64) i8 {
        return switch (self.*) {
            .console => |*d| d.get8(addr),
            .memcard => |*d| d.get8(addr),
        };
    }

    pub fn get16(self: *Device, addr: u64) i16 {
        return switch (self.*) {
            .console => |*d| d.get16(addr),
            .memcard => |*d| d.get16(addr),
        };
    }

    pub fn get32(self: *Device, addr: u64) i32 {
        return switch (self.*) {
            .console => |*d| d.get32(addr),
            .memcard => |*d| d.get32(addr),
        };
    }

    pub fn get64(self: *Device, addr: u64) i64 {
        return switch (self.*) {
            .console => |*d| d.get64(addr),
            .memcard => |*d| d.get64(addr),
        };
    }

    pub fn set8(self: *Device, out: *Output, addr: u64, val: u8) !void {
        return switch (self.*) {
            .console => |*d| d.set8(out, addr, val),
            .memcard => |*d| d.set8(out, addr, val),
        };
    }

    pub fn set16(self: *Device, out: *Output, addr: u64, val: u16) !void {
        return switch (self.*) {
            .console => |*d| d.set16(out, addr, val),
            .memcard => |*d| d.set16(out, addr, val),
        };
    }

    pub fn set32(self: *Device, out: *Output, addr: u64, val: u32) !void {
        return switch (self.*) {
            .console => |*d| d.set32(out, addr, val),
            .memcard => |*d| d.set32(out, addr, val),
        };
    }

    pub fn set64(self: *Device, out: *Output, addr: u64, val: u64) !void {
        return switch (self.*) {
            .console => |*d| d.set64(out, addr, val),
            .memcard => |*d| d.set64(out, addr, val),
        };
    }

    pub fn getBaseAddress(self: *Device) u64 {
        return switch (self.*) {
            .console => |*d| d.getBaseAddress(),
            .memcard => |*d| d.getBaseAddress(),
        };
    }

    pub fn getLastAddress(self: *Device) u64 {
        return switch (self.*) {
            .console => |*d| d.getLastAddress(),
            .memcard => |*d| d.getLastAddress(),
        };
    }
};

pub const Devices = struct {
    devs: std.ArrayList(Device),
    allocator: std.mem.Allocator,
    warnings: i32 = 1,
    out: *Output,

    pub fn init(allocator: std.mem.Allocator, out: *Output) Devices {
        return .{
            .devs = .{},
            .allocator = allocator,
            .warnings = 1,
            .out = out,
        };
    }

    pub fn deinit(self: *Devices) void {
        self.devs.deinit(self.allocator);
    }

    pub fn addConsole(self: *Devices) !void {
        try self.devs.append(self.allocator, .{ .console = .{} });
    }

    pub fn addMemcard(self: *Devices) !void {
        try self.devs.append(self.allocator, .{ .memcard = .{} });
    }

    fn findDevice(self: *Devices, addr: u64) ?*Device {
        for (self.devs.items) |*d| {
            if (d.getBaseAddress() <= addr and d.getLastAddress() >= addr) {
                return d;
            }
        }
        return null;
    }

    pub fn get8(self: *Devices, addr: u64) !i8 {
        if (self.findDevice(addr)) |d| return d.get8(addr);
        try self.errorGet("8", addr);
        return -1;
    }

    pub fn get16(self: *Devices, addr: u64) !i16 {
        if (self.findDevice(addr)) |d| return d.get16(addr);
        try self.errorGet("16", addr);
        return -1;
    }

    pub fn get32(self: *Devices, addr: u64) !i32 {
        if (self.findDevice(addr)) |d| return d.get32(addr);
        try self.errorGet("32", addr);
        return -1;
    }

    pub fn get64(self: *Devices, addr: u64) !i64 {
        if (self.findDevice(addr)) |d| return d.get64(addr);
        try self.errorGet("64", addr);
        return -1;
    }

    pub fn set8(self: *Devices, addr: u64, val: u8) !void {
        if (self.findDevice(addr)) |d| return d.set8(self.out, addr, val);
        try self.errorSet("8", addr, val);
    }

    pub fn set16(self: *Devices, addr: u64, val: u16) !void {
        if (self.findDevice(addr)) |d| return d.set16(self.out, addr, val);
        try self.errorSet("16", addr, val);
    }

    pub fn set32(self: *Devices, addr: u64, val: u32) !void {
        if (self.findDevice(addr)) |d| return d.set32(self.out, addr, val);
        try self.errorSet("32", addr, val);
    }

    pub fn set64(self: *Devices, addr: u64, val: u64) !void {
        if (self.findDevice(addr)) |d| return d.set64(self.out, addr, val);
        try self.errorSet("64", addr, val);
    }

    pub fn errorSet(self: *Devices, len: []const u8, addr: u64, val: u64) !void {
        if (self.warnings != 0) {
            try self.out.print("WARNING: {s}-bit write to non-existent device at address: 0x{X:0>8} = 0x{X:0>8}\n", .{ len, @as(u32, @truncate(addr)), @as(u32, @truncate(val)) });
        }
    }

    pub fn errorGet(self: *Devices, len: []const u8, addr: u64) !void {
        if (self.warnings != 0) {
            try self.out.print("WARNING: {s}-bit read from non-existent device at address: 0x{X:0>8}\n", .{ len, @as(u32, @truncate(addr)) });
        }
    }

    pub fn errorInvalidWrite(self: *Devices, len: []const u8, addr: u64, val: u64, msg: ?[]const u8) !void {
        try self.out.print("WARNING: {s}-bit write to address 0x{X:0>8} with illegal value 0x{X:0>8}\n", .{ len, @as(u32, @truncate(addr)), @as(u32, @truncate(val)) });
        if (msg) |m| {
            try self.out.print("{s}\n", .{m});
        }
    }
};
