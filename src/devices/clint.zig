const mip_msip_bit: u32 = (@as(u32, 1) << 3);

pub const Clint = struct {
    msip_base: u64,

    pub fn init(msip_base: u64) Clint {
        return .{ .msip_base = msip_base };
    }

    fn msipValue(_: *const Clint, csr_mip: u32) u32 {
        return if ((csr_mip & mip_msip_bit) != 0) 1 else 0;
    }

    pub fn isMsipAddr(self: *const Clint, addr: u64) bool {
        return addr >= self.msip_base and addr < self.msip_base + 4;
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
};
