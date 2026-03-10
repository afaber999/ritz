const UART_BUF_REG_ADDR:usize = 0xf0000000;
const uart_buf_reg = @volatileCast(@as(*u32, @ptrFromInt(UART_BUF_REG_ADDR)));

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



export fn main() u32 {

    while (true) {
        putStr("mtime=");
        putU64(getMtimeCsr());
        putStr("\n");

        wait();
    }
    return 0;
}

fn wait() void {
    var i: u32 = 0;
    while (i < 2_000_000) : (i += 1) {
        asm volatile ("nop");
    }
}
