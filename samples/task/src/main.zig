const UART_BUF_REG_ADDR:usize = 0x10000000;
const uart_buf_reg = @volatileCast(@as(*u32, @ptrFromInt(UART_BUF_REG_ADDR)));

const CLINT_MTIMECMP_ADDR: usize = 0x02004000;
const CLINT_MTIME_ADDR: usize = 0x0200BFF8;
const clint_mtimecmp_lo = @volatileCast(@as(*u32, @ptrFromInt(CLINT_MTIMECMP_ADDR + 0)));
const clint_mtimecmp_hi = @volatileCast(@as(*u32, @ptrFromInt(CLINT_MTIMECMP_ADDR + 4)));
const clint_mtime_lo = @volatileCast(@as(*u32, @ptrFromInt(CLINT_MTIME_ADDR + 0)));
const clint_mtime_hi = @volatileCast(@as(*u32, @ptrFromInt(CLINT_MTIME_ADDR + 4)));

extern fn timervec() callconv(.c) void;

fn putByte(ch: u8) void {
    uart_buf_reg.* = ch;
}

fn putStr(comptime s: []const u8) void {
    for (s) |b| {
        putByte(b);
    }
}

fn putU64(value: u64) void {
    var v = value;
    var buf: [20]u8 = undefined;
    var idx: usize = 0;

    if (v == 0) {
        putByte('0');
        return;
    }

    while (v > 0) {
        buf[idx] = '0' + @as(u8, @intCast(v % 10));
        idx += 1;
        v /= 10;
    }

    while (idx > 0) {
        idx -= 1;
        putByte(buf[idx]);
    }
}

fn getTimeLow() u32 {
    return asm volatile (
        "csrr %[out], 0xC01"
        : [out] "=r" (-> u32),
    );
}

fn getTimeHigh() u32 {
    return asm volatile (
        "csrr %[out], 0xC81"
        : [out] "=r" (-> u32),
    );
}

fn getMtimeCsr() u64 {
    // Read hi/lo/hi to avoid rollover between reads.
    while (true) {
        const hi1 = getTimeHigh();
        const lo = getTimeLow();
        const hi2 = getTimeHigh();
        if (hi1 == hi2) {
            return (@as(u64, hi1) << 32) | @as(u64, lo);
        }
    }
}


fn setupTimer() void {
    // Program next timer compare event using CLINT mtime/mtimecmp.
    var mtime: u64 = 0;
    while (true) {
        const hi1 = clint_mtime_hi.*;
        const lo = clint_mtime_lo.*;
        const hi2 = clint_mtime_hi.*;
        if (hi1 == hi2) {
            mtime = (@as(u64, hi1) << 32) | @as(u64, lo);
            break;
        }
    }
    const mtimecmp = mtime + 20_000_000;
    // QEMU virt: program CLINT mtimecmp for hart 0 at 0x02004000.
    clint_mtimecmp_hi.* = 0xFFFF_FFFF;
    clint_mtimecmp_lo.* = @as(u32, @truncate(mtimecmp));
    clint_mtimecmp_hi.* = @as(u32, @truncate(mtimecmp >> 32));
}

fn enableTimerInterrupt() void {
    const mtvec_addr: u32 = @truncate(@intFromPtr(&timervec));
    const mtie_mask: u32 = 1 << 7;
    const mie_mask: u32 = 1 << 3;
    asm volatile (
        "csrw 0x305, %[mtvec]\n" ++ // mtvec
        "csrrs x0, 0x304, %[mtie]\n" ++ // mie.MTIE
        "csrrs x0, 0x300, %[mie]\n"     // mstatus.MIE
        :
        : [mtvec] "r" (mtvec_addr), [mtie] "r" (mtie_mask), [mie] "r" (mie_mask)
    );
}

export fn main() u32 {
    putStr("enabling timer interrupt\n");
    enableTimerInterrupt();
    setupTimer();

    while (true) {
        putStr("mtime=");
        putU64(getMtimeCsr());
        putStr("\n");

        delayMs(1000);
    }
    return 0;
}

fn delayMs(n : u32) void {
    var i: u32 = 0;
    while (i < 18_000_000 * n) : (i += 1) {
        asm volatile ("nop");
    }
}
