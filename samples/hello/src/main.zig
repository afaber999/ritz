                                 
const UART_BUF_REG_ADDR:usize = 0x10000000;
const uart_buf_reg = @volatileCast(@as(*u32, @ptrFromInt(UART_BUF_REG_ADDR)));

export fn main() u32 {
    for ("Hello world\n") |b| {
        // write each byte to the UART FIFO
        uart_buf_reg.* = b;
    }

    foo();
    return 0;
}

fn foo() void {
    for ("func foo!\n") |b| {
        uart_buf_reg.* = b;
    }
    bar();
}

fn bar() void {
    for ("func bar!\n") |b| {
        uart_buf_reg.* = b;
    }
}
