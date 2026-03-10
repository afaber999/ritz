const UART_BUF_REG_ADDR: usize = 0xf0000000;

// https://github.com/ziglang/zig/issues/21033
const PeripheralTypeU8 = struct {
    raw: struct {
        value: u8,
    },
};

var uartreg: *volatile PeripheralTypeU8 = @ptrFromInt(UART_BUF_REG_ADDR);

fn putByte(ch: u8) void {
    uartreg.raw.value = ch;
}

fn putDigit(d: i32) void {
    putByte('0' + @as(u8, @intCast(d)));
}

fn putStr(comptime s: []const u8) void {
    for (s) |ch| putByte(ch);
}

fn putU32(value: u32) void {
    var buf: [10]u8 = undefined;
    var idx: usize = 0;
    var mut = value;

    if (mut == 0) {
        putByte('0');
        return;
    }

    while (mut > 0) {
        buf[idx] = '0' + @as(u8, @intCast(mut % 10));
        idx += 1;
        mut /= 10;
    }

    while (idx > 0) {
        idx -= 1;
        putByte(buf[idx]);
    }
}

fn isPrime(n: u32) bool {
    if (n < 2) return false;
    if (n == 2) return true;
    if ((n & 1) == 0) return false;

    var d: u32 = 3;
    while (d <= n / d) : (d += 2) {
        if (n % d == 0) return false;
    }
    return true;
}

pub fn prime() void {
    const max_primes: u32 = 200;
    var count: u32 = 0;
    var candidate: u32 = 2;

    putStr("Primes:\r\n");

    while (count < max_primes) : (candidate += 1) {
        if (!isPrime(candidate)) continue;

        putU32(candidate);
        putStr("\r\n");
        count += 1;
    }

    putByte('\r');
    putByte('\n');
}

export fn main() u32 {
    prime();
    return 0;
}
