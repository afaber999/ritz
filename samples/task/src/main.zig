extern const UART_BUF_REG_ADDR: u8;
extern const CLINT_BASE_ADDR: u8;
extern const CLINT_MTIMECMP_ADDR: u8;
extern const CLINT_MTIME_ADDR: u8;


// It assumes CLINT mtime runs at about 10,000,000 ticks/sec (10 MHz).
const TICKER_PER_SEC = 10_000_000;

fn clintMtimecmpLo() *volatile u32 {
    const base = @intFromPtr(&CLINT_MTIMECMP_ADDR);
    return @ptrFromInt(base + 0);
}

fn uartBufReg() *volatile u32 {
    const base = @intFromPtr(&UART_BUF_REG_ADDR);
    return @ptrFromInt(base);
}

fn clintMtimecmpHi() *volatile u32 {
    const base = @intFromPtr(&CLINT_MTIMECMP_ADDR);
    return @ptrFromInt(base + 4);
}

fn clintMtimeLo() *volatile u32 {
    const base = @intFromPtr(&CLINT_MTIME_ADDR);
    return @ptrFromInt(base + 0);
}

fn clintMtimeHi() *volatile u32 {
    const base = @intFromPtr(&CLINT_MTIME_ADDR);
    return @ptrFromInt(base + 4);
}

extern fn timervec() callconv(.c) void;

fn putByte(ch: u8) void {
    uartBufReg().* = ch;
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
        const hi1 = clintMtimeHi().*;
        const lo = clintMtimeLo().*;
        const hi2 = clintMtimeHi().*;
        if (hi1 == hi2) {
            mtime = (@as(u64, hi1) << 32) | @as(u64, lo);
            break;
        }
    }
    const mtimecmp = mtime + 20_000_000;
    // QEMU virt: program CLINT mtimecmp for hart 0 at 0x02004000.
    clintMtimecmpHi().* = 0xFFFF_FFFF;
    clintMtimecmpLo().* = @as(u32, @truncate(mtimecmp));
    clintMtimecmpHi().* = @as(u32, @truncate(mtimecmp >> 32));
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

    putStr("TASK main\n");
    // putStr("enabling timer interrupt\n");
    setupTimer();
    enableTimerInterrupt();

    while (true) {
        putStr("TASK 1: =");
        putU64(getMtimeCsr());
        putStr("\n");
        delayMs(1000);
    }

    putStr("Going down main\n");
    return 0;
}


fn delayMs(n : u32) void {
    const start = getMtimeCsr();
    const exp_time = start + ((TICKER_PER_SEC / 1000) * n);
    while (getMtimeCsr() < exp_time) {
        asm volatile ("nop");
    }
}
