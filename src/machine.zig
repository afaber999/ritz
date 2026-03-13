const std = @import("std");
const Devices = @import("devices.zig").Devices;
const Output = @import("output.zig").Output;

fn intCastCompat(comptime T: type, value: anytype) T {
    return @as(T, @intCast(value));
}

pub const devBaseAddress: u32 = 0xf0000000;
pub const CSR_MSTATUS: u12 = 0x300;
pub const CSR_MISA: u12 = 0x301;
pub const CSR_MIE: u12 = 0x304;
pub const CSR_MTVEC: u12 = 0x305;
pub const CSR_MCOUNTEREN: u12 = 0x306;
pub const CSR_MIP: u12 = 0x344;
pub const CSR_MSCRATCH: u12 = 0x340;
pub const CSR_MEPC: u12 = 0x341;
pub const CSR_MCAUSE: u12 = 0x342;
pub const CSR_SCOUNTEREN: u12 = 0x106;
pub const CSR_CYCLE: u12 = 0xC00;
pub const CSR_CYCLEH: u12 = 0xC80;
pub const CSR_TIME: u12 = 0xC01;
pub const CSR_TIMEH: u12 = 0xC81;
pub const CSR_MVENDORID: u12 = 0xF11;
pub const CSR_MARCHID: u12 = 0xF12;
pub const CSR_MIMPID: u12 = 0xF13;
pub const CSR_MHARTID: u12 = 0xF14;
const CLINT_MSIP_BASE: u64 = 0x02000000;
const MIP_MSIP_BIT: u32 = (@as(u32, 1) << 3);
const DEFAULT_MISA: u32 = (@as(u32, 1) << 30) | (@as(u32, 1) << 8) | (@as(u32, 1) << 12);

pub const Machine = struct {
    data: []u8,
    start: u64,
    len: u64,
    memoryWarnings: i32 = 1,
    dev: *Devices,
    out: *Output,
    allocator: std.mem.Allocator,
    csr_mstatus: u32 = 0,
    csr_misa: u32 = DEFAULT_MISA, // RV32 + I + M
    csr_mie: u32 = 0,
    csr_mtvec: u32 = 0,
    csr_mcounteren: u32 = 0,
    csr_mip: u32 = 0,
    csr_mscratch: u32 = 0,
    csr_mepc: u32 = 0,
    csr_mcause: u32 = 0,
    csr_scounteren: u32 = 0,
    csr_cycle: u64 = 0,
    timerh: u32 = 0,
    timerl: u32 = 0,
    timermatchh: u32 = 0,
    timermatchl: u32 = 0,

	// Note: only a few bits are used.  (Machine = 3, User = 0)
    // Bits 0..1 = privilege.
    // Bit 2 = WFI (Wait for interrupt)
    // Bit 3 = halt request
    extraflags: u32 = 3,


    pub fn init(allocator: std.mem.Allocator, start: u64, length: u64, dev: *Devices, out: *Output) !Machine {
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

    pub fn deinit(self: *Machine) void {
        self.allocator.free(self.data);
    }

    pub fn resetSystemState(self: *Machine) void {
        self.csr_mstatus = 0;
        self.csr_misa = DEFAULT_MISA;
        self.csr_mie = 0;
        self.csr_mtvec = 0;
        self.csr_mcounteren = 0;
        self.csr_mip = 0;
        self.csr_mscratch = 0;
        self.csr_mepc = 0;
        self.csr_mcause = 0;
        self.csr_scounteren = 0;
        self.csr_cycle = 0;
        self.timerh = 0;
        self.timerl = 0;
        self.extraflags = 3;
    }

    pub fn next_cycle(self: *Machine) void {
        self.csr_cycle +%= 1;
        const t: i64 = std.time.microTimestamp();
        self.timerl = intCastCompat(u32, intCastCompat(u64, t) & 0xFFFF_FFFF);
        self.timerh = intCastCompat(u32, intCastCompat(u64, t) >> 32);

        // Handle timer interrupt (MTIP bit in mip).
        if ((self.timermatchh != 0 or self.timermatchl != 0) and
            ((self.timerh > self.timermatchh) or (self.timerh == self.timermatchh and self.timerl > self.timermatchl)))
        {
            self.extraflags &= ~@as(u32, 4); // Clear WFI
            self.csr_mip |= (@as(u32, 1) << 7);
        } else {
            self.csr_mip &= ~(@as(u32, 1) << 7);
        }
    }

    pub fn csrRead(self: *Machine, csr: u12) ?u32 {
        return switch (csr) {
            CSR_MSTATUS => self.csr_mstatus,
            CSR_MISA => self.csr_misa,
            CSR_MIE => self.csr_mie,
            CSR_MTVEC => self.csr_mtvec,
            CSR_MCOUNTEREN => self.csr_mcounteren,
            CSR_MIP => self.csr_mip,
            CSR_MSCRATCH => self.csr_mscratch,
            CSR_MEPC => self.csr_mepc,
            CSR_MCAUSE => self.csr_mcause,
            CSR_SCOUNTEREN => self.csr_scounteren,
            CSR_CYCLE => @truncate(self.csr_cycle),
            CSR_CYCLEH => @truncate(self.csr_cycle >> 32),
            CSR_TIME => @truncate(self.timerl),
            CSR_TIMEH => @truncate(self.timerh),
            CSR_MVENDORID => 0,
            CSR_MARCHID => 0,
            CSR_MIMPID => 0,
            CSR_MHARTID => 0,
            else => null,
        };
    }

    pub fn csrWrite(self: *Machine, csr: u12, value: u32) bool {
        switch (csr) {
            CSR_MSTATUS => self.csr_mstatus = value,
            CSR_MIE => self.csr_mie = value,
            CSR_MTVEC => self.csr_mtvec = value,
            CSR_MCOUNTEREN => self.csr_mcounteren = value,
            CSR_MIP => self.csr_mip = value,
            CSR_MSCRATCH => self.csr_mscratch = value,
            CSR_MEPC => self.csr_mepc = value,
            CSR_MCAUSE => self.csr_mcause = value,
            CSR_SCOUNTEREN => self.csr_scounteren = value,
            CSR_TIME => self.timermatchl = value,
            CSR_TIMEH => self.timermatchh = value,
            CSR_CYCLE, CSR_CYCLEH, CSR_MISA, CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID => return false,
            else => return false,
        }
        return true;
    }

    fn isClintMsipAddr(_: *Machine, addr: u64) bool {
        return addr >= CLINT_MSIP_BASE and addr < CLINT_MSIP_BASE + 4;
    }

    fn clintMsipValue(self: *Machine) u32 {
        return if ((self.csr_mip & MIP_MSIP_BIT) != 0) 1 else 0;
    }

    fn clintWriteMsip(self: *Machine, value: u32) void {
        if ((value & 1) != 0) {
            self.csr_mip |= MIP_MSIP_BIT;
            self.extraflags &= ~@as(u32, 4); // Wake from WFI on pending software interrupt.
        } else {
            self.csr_mip &= ~MIP_MSIP_BIT;
        }
    }

    pub fn get8(self: *Machine, addr: u64) !i8 {

        if (self.isClintMsipAddr(addr)) {
            const shift: u5 = @truncate((addr - CLINT_MSIP_BASE) * 8);
            const b: u8 = @truncate((self.clintMsipValue() >> shift) & 0xff);
            return @bitCast(b);
        }

        if (addr == 0x10000005) {
            return 0x20;
        }

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

    pub fn get16(self: *Machine, addr: u64) !i16 {
        if (addr >= devBaseAddress) {
            return self.dev.get16(addr);
        }

        const b0: u16 = @as(u16, @as(u8, @bitCast(try self.get8(addr))));
        const b1: u16 = @as(u16, @as(u8, @bitCast(try self.get8(addr + 1))));
        return @bitCast(b0 | (b1 << 8));
    }

    pub fn get32(self: *Machine, addr: u64) !i32 {
        if (addr >= devBaseAddress) {
            return self.dev.get32(addr);
        }

        const l: u32 = @as(u32, @as(u16, @bitCast(try self.get16(addr))));
        const h: u32 = @as(u32, @as(u16, @bitCast(try self.get16(addr + 2))));
        return @bitCast(l | (h << 16));
    }

    pub fn get64(self: *Machine, addr: u64) !i64 {
        if (addr >= devBaseAddress) {
            return self.dev.get64(addr);
        }

        const l: u64 = @as(u64, @as(u32, @bitCast(try self.get32(addr))));
        const h: u64 = @as(u64, @as(u32, @bitCast(try self.get32(addr + 4))));
        return @bitCast(l | (h << 32));
    }

    pub fn set8(self: *Machine, addr: u64, val: u8) !void {

        if (self.isClintMsipAddr(addr)) {
            const shift: u5 = @truncate((addr - CLINT_MSIP_BASE) * 8);
            const cur = self.clintMsipValue();
            const mask = ~(@as(u32, 0xff) << shift);
            const next = (cur & mask) | (@as(u32, val) << shift);
            self.clintWriteMsip(next);
            return;
        }

        if (addr == 0x10000000) {
            std.debug.print("{c}", .{val});
            return;
        }

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

    pub fn set16(self: *Machine, addr: u64, val: u16) !void {
        if (addr == 0x10000000) {
            std.debug.print("{c}", .{@as(u8, @truncate(val))});
            return;
        }

        if (addr >= devBaseAddress) {
            return self.dev.set16(addr, val);
        }

        try self.set8(addr, @as(u8, @truncate(val & 0x00ff)));
        try self.set8(addr + 1, @as(u8, @truncate((val >> 8) & 0x00ff)));
    }

    pub fn set32(self: *Machine, addr: u64, val: u32) !void {

        if (addr == CLINT_MSIP_BASE) {
            self.clintWriteMsip(val);
            return;
        }

        if (addr == 0x10000000) {
            std.debug.print("{c}", .{@as(u8, @truncate(val))});
            return;
        }

        if (addr >= devBaseAddress) {
            return self.dev.set32(addr, val);
        }

        try self.set16(addr, @as(u16, @truncate(val & 0x0000ffff)));
        try self.set16(addr + 2, @as(u16, @truncate((val >> 16) & 0x0000ffff)));
    }

    pub fn set64(self: *Machine, addr: u64, val: u64) !void {
        if (addr >= devBaseAddress) {
            return self.dev.set32(addr, @as(u32, @truncate(val)));
        }

        try self.set32(addr, @as(u32, @truncate(val & 0x0000_0000_ffff_ffff)));
        try self.set32(addr + 4, @as(u32, @truncate((val >> 32) & 0x0000_0000_ffff_ffff)));
    }

    pub fn readRaw(self: *Machine, filename: []const u8, addr: u64) !void {
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

    pub fn dump(self: *Machine, addr: u64, length: u64) !void {
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

pub const Memory = Machine;
