extern const @"__global_pointer$": u8;
extern const _task_exit: u8;

const platform = @import("platform.zig");

const TIMER_INTERVAL_TICKS = 20_000_000;
const StackSize = 512;
const machine_timer_interrupt_mcause: u32 = 0x80000007;

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

export var current_task_ctx: u32 = 0;
export var task1_context: TaskContext = .{};
export var task2_context: TaskContext = .{};
export var task3_context: TaskContext = .{};
export var task2_stack: [StackSize]u8 align(16) = [_]u8{0} ** StackSize;
export var task3_stack: [StackSize]u8 align(16) = [_]u8{0} ** StackSize;

fn stackTop(stack: *[StackSize]u8) u32 {
    return @as(u32, @truncate(@intFromPtr(stack) + StackSize));
}

fn initTaskContext(ctx: *TaskContext, entry: *const fn () callconv(.c) u32, stack: *[StackSize]u8) void {
    ctx.* = .{};
    ctx.ra = @as(u32, @truncate(@intFromPtr(&_task_exit)));
    ctx.sp = stackTop(stack);
    ctx.gp = @as(u32, @truncate(@intFromPtr(&@"__global_pointer$")));
    ctx.mepc = @as(u32, @truncate(@intFromPtr(entry)));
}

fn nextTask(current: *TaskContext) *TaskContext {
    if (current == &task1_context) return &task2_context;
    if (current == &task2_context) return &task3_context;
    return &task1_context;
}

pub fn putByte(ch: u8) void {
    platform.putByte(ch);
}

pub fn putStr(comptime s: []const u8) void {
    platform.putStr(s);
}

pub fn putU64(value: u64) void {
    platform.putU64(value);
}

pub fn getMtimeCsr() u64 {
    return platform.getMtimeCsr();
}

pub fn delayMs(n: u32) void {
    platform.delayMs(n);
}

pub fn setupTimer() void {
    platform.programTimerAfter(TIMER_INTERVAL_TICKS);
}

export fn schedulerInit() callconv(.c) void {
    current_task_ctx = @as(u32, @truncate(@intFromPtr(&task1_context)));
    task1_context = .{};
    initTaskContext(&task2_context, main2, &task2_stack);
    initTaskContext(&task3_context, main3, &task3_stack);
}

export fn handleTrap(current_ctx: *TaskContext, mcause: u32) callconv(.c) *TaskContext {
    if (mcause == machine_timer_interrupt_mcause) {
        platform.programTimerAfter(TIMER_INTERVAL_TICKS);
        platform.putByte('@');
        const next = nextTask(current_ctx);
        current_task_ctx = @as(u32, @truncate(@intFromPtr(next)));
        return next;
    }

    platform.putByte('!');
    current_task_ctx = @as(u32, @truncate(@intFromPtr(current_ctx)));
    return current_ctx;
}

export fn main2() u32 {
    putStr("TASK main2\n");

    while (true) {
        putStr("TASK 2: =");
        putU64(getMtimeCsr());
        putStr("\n");
        delayMs(1100);
    }

    return 0;
}

export fn main3() u32 {
    putStr("TASK main3\n");

    while (true) {
        putStr("TASK 3: =");
        putU64(getMtimeCsr());
        putStr("\n");
        delayMs(1300);
    }

    return 0;
}