extern const UART_BUF_REG_ADDR: u8;
extern const @"__global_pointer$": u8;
extern const CLINT_MTIMECMP_ADDR: u8;
extern const CLINT_MTIME_ADDR: u8;
extern const _task_exit: u8;


// It assumes CLINT mtime runs at about 10,000,000 ticks/sec (10 MHz).
const TICKER_PER_SEC = 10_000_000;
const TIMER_INTERVAL_TICKS = 20_000_000;

const StackSize = 512;

pub const TaskContext = extern struct {
    ra: u32 = 0,
    sp: u32 = 0,
    gp: u32 = 0,
    tp: u32 = 0,
    t0: u32 = 0,
    t1: u32 = 0,
    t2: u32 = 0,
    s0: u32 = 0,
    s1: u32 = 0,
    a0: u32 = 0,
    a1: u32 = 0,
    a2: u32 = 0,
    a3: u32 = 0,
    a4: u32 = 0,
    a5: u32 = 0,
    a6: u32 = 0,
    a7: u32 = 0,
    s2: u32 = 0,
    s3: u32 = 0,
    s4: u32 = 0,
    s5: u32 = 0,
    s6: u32 = 0,
    s7: u32 = 0,
    s8: u32 = 0,
    s9: u32 = 0,
    s10: u32 = 0,
    s11: u32 = 0,
    t3: u32 = 0,
    t4: u32 = 0,
    t5: u32 = 0,
    t6: u32 = 0,
    mepc: u32 = 0,
};

const machine_timer_interrupt_mcause: u32 = 0x80000007;

export var current_task_ctx: u32 = 0;
export var task1_context: TaskContext = .{};
export var task2_context: TaskContext = .{};
export var task3_context: TaskContext = .{};
export var task2_stack: [StackSize]u8 align(16) = [_]u8{0} ** StackSize;
export var task3_stack: [StackSize]u8 align(16) = [_]u8{0} ** StackSize;

fn stackTop(stack: *[StackSize]u8) u32 {
    return @as(u32, @truncate(@intFromPtr(stack) + StackSize));
}

fn putChar(ch: u8) void {
    putByte(ch);
}

fn initTaskContext(ctx: *TaskContext, entry: *const fn () callconv(.c) u32, stack: *[StackSize]u8) void {
    ctx.* = .{};
    ctx.ra = @as(u32, @truncate(@intFromPtr(&_task_exit)));
    ctx.sp = stackTop(stack);
    ctx.gp = @as(u32, @truncate(@intFromPtr(&@"__global_pointer$")));
    ctx.mepc = @as(u32, @truncate(@intFromPtr(entry)));
}

fn programTimerAfter(delta: u64) void {
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

    const mtimecmp = mtime + delta;
    clintMtimecmpHi().* = 0xFFFF_FFFF;
    clintMtimecmpLo().* = @as(u32, @truncate(mtimecmp));
    clintMtimecmpHi().* = @as(u32, @truncate(mtimecmp >> 32));
}

fn nextTask(current: *TaskContext) *TaskContext {
    if (current == &task1_context) return &task2_context;
    if (current == &task2_context) return &task3_context;
    return &task1_context;
}

export fn schedulerInit() callconv(.c) void {
    current_task_ctx = @as(u32, @truncate(@intFromPtr(&task1_context)));
    task1_context = .{};
    initTaskContext(&task2_context, main2, &task2_stack);
    initTaskContext(&task3_context, main3, &task3_stack);
}

export fn handleTrap(current_ctx: *TaskContext, mcause: u32) callconv(.c) *TaskContext {
    if (mcause == machine_timer_interrupt_mcause) {
        programTimerAfter(TIMER_INTERVAL_TICKS);
        putChar('@');
        const next = nextTask(current_ctx);
        current_task_ctx = @as(u32, @truncate(@intFromPtr(next)));
        return next;
    }

    putChar('!');
    current_task_ctx = @as(u32, @truncate(@intFromPtr(current_ctx)));
    return current_ctx;
}

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
    programTimerAfter(TIMER_INTERVAL_TICKS);
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

export fn main3() u32 {

    putStr("TASK main3\n");

    while (true) {
        putStr("TASK 3: =");
        putU64(getMtimeCsr());
        putStr("\n");
        delayMs(1300);
    }

    putStr("Going down main\n");
    return 0;
}

export fn main2() u32 {

    putStr("TASK main2\n");

    while (true) {
        putStr("TASK 2: =");
        putU64(getMtimeCsr());
        putStr("\n");
        delayMs(1100);
    }

    putStr("Going down main\n");
    return 0;
}

export fn main() u32 {

    putStr("TASK main\n");
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
