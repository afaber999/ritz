const UART_BUF_REG_ADDR:usize = 0xf0000000;
const uart_buf_reg = @volatileCast(@as(*u32, @ptrFromInt(UART_BUF_REG_ADDR)));

// https://github.com/ziglang/zig/issues/21033
const PeripheralTypeU8 = struct {
    raw: struct {
        value: u8
    },
};
const PeripheralTypeU32 = struct {
    raw: struct {
        value: u32
    },
};

var uartreg: *volatile PeripheralTypeU8 = @ptrFromInt(UART_BUF_REG_ADDR);

export fn main() u32 {
    const xmin: i32 = -8601;
    const xmax: i32 = 2867;
    const ymin: i32 = -4915;
    const ymax: i32 = 4915;

    const maxiter: usize = 32;

    const dx: i32 = @divTrunc((xmax - xmin), 79);
    const dy: i32 = @divTrunc((ymax - ymin), 24);

    var cy = ymin;

    while (cy <= ymax) {
        var cx = xmin;
        while (cx <= xmax) {
            var x: i32 = 0;
            var y: i32 = 0;
            var x2: i32 = 0;
            var y2: i32 = 0;
            var iter: usize = 0;
            while (iter < maxiter) : (iter += 1) {
                if (x2 + y2 > 16384) break;
                y = ((x * y) >> 11) + cy;
                x = x2 - y2 + cx;
                x2 = (x * x) >> 12;
                y2 = (y * y) >> 12;
            }
            uartreg.raw.value = ' ' + @as(u8, @intCast(iter));
            cx += dx;
        }
        uartreg.raw.value = '\r';
        uartreg.raw.value = '\n';
        cy += dy;

    }
    return 0;
}
