const mip_msip_bit: u32 = (@as(u32, 1) << 3);
const mip_mtip_bit: u32 = (@as(u32, 1) << 7);
const timermatch_offset: u64 = 0x4000;
const mtime_offset: u64 = 0xBFF8;

pub const Clint = struct {
    msip_base: u64,
    timermatchl: u32 = 0,
    timermatchh: u32 = 0,

    pub fn init(msip_base: u64) Clint {
        return .{ .msip_base = msip_base, .timermatchl = 0, .timermatchh = 0 };
    }

    pub fn reset(self: *Clint) void {
        self.timermatchl = 0;
        self.timermatchh = 0;
    }

    fn msipValue(_: *const Clint, csr_mip: u32) u32 {
        return if ((csr_mip & mip_msip_bit) != 0) 1 else 0;
    }

    pub fn isMsipAddr(self: *const Clint, addr: u64) bool {
        return addr >= self.msip_base and addr < self.msip_base + 4;
    }

    pub fn isTimermatchAddr(self: *const Clint, addr: u64) bool {
        return addr == self.msip_base + timermatch_offset or addr == self.msip_base + timermatch_offset + 4;
    }

    pub fn isMtimeAddr(self: *const Clint, addr: u64) bool {
        return addr == self.msip_base + mtime_offset or addr == self.msip_base + mtime_offset + 4;
    }

    pub fn readMsipByte(self: *const Clint, csr_mip: u32, addr: u64) u8 {
        const shift: u5 = @truncate((addr - self.msip_base) * 8);
        return @truncate((self.msipValue(csr_mip) >> shift) & 0xff);
    }

    pub fn writeMsipWord(_: *const Clint, machine: anytype, value: u32) void {
        if ((value & 1) != 0) {
            machine.csr_mip |= mip_msip_bit;
            machine.extraflags &= ~@as(u32, 4); // Wake from WFI on pending software interrupt.
        } else {
            machine.csr_mip &= ~mip_msip_bit;
        }
    }

    pub fn writeMsipByte(self: *const Clint, machine: anytype, addr: u64, value: u8) void {
        const shift: u5 = @truncate((addr - self.msip_base) * 8);
        const cur = self.msipValue(machine.csr_mip);
        const mask = ~(@as(u32, 0xff) << shift);
        const next = (cur & mask) | (@as(u32, value) << shift);
        self.writeMsipWord(machine, next);
    }

    pub fn read32(self: *const Clint, machine: anytype, addr: u64) ?u32 {
        if (addr == self.msip_base + timermatch_offset) return self.timermatchl;
        if (addr == self.msip_base + timermatch_offset + 4) return self.timermatchh;
        if (addr == self.msip_base + mtime_offset) return machine.timerl;
        if (addr == self.msip_base + mtime_offset + 4) return machine.timerh;
        return null;
    }

    pub fn write32(self: *Clint, machine: anytype, addr: u64, value: u32) bool {
        if (addr == self.msip_base) {
            self.writeMsipWord(machine, value);
            return true;
        }
        if (addr == self.msip_base + timermatch_offset) {
            self.timermatchl = value;
            return true;
        }
        if (addr == self.msip_base + timermatch_offset + 4) {
            self.timermatchh = value;
            return true;
        }
        return false;
    }

    pub fn updateTimerInterrupt(self: *const Clint, machine: anytype) void {
        if ((self.timermatchh != 0 or self.timermatchl != 0) and
            ((machine.timerh > self.timermatchh) or (machine.timerh == self.timermatchh and machine.timerl >= self.timermatchl)))
        {
            machine.extraflags &= ~@as(u32, 4); // Clear WFI
            machine.csr_mip |= mip_mtip_bit;
        } else {
            machine.csr_mip &= ~mip_mtip_bit;
        }
    }
};
