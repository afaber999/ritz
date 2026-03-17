extern const @"__global_pointer$": u8;
extern const _task_exit: u8;

const platform = @import("platform.zig");

const TIMER_INTERVAL_TICKS = 20_000_000;
const StackSize = 2048;
const StackGuardSize = 64;
const StackGuardByte: u8 = 0xA5;
const machine_timer_interrupt_mcause: u32 = 0x80000007;

const TaskEntry = *const fn () callconv(.c) u32;
const WorkerTaskSpec = struct {
    entry: TaskEntry,
};

const worker_task_specs = [_]WorkerTaskSpec{
    .{ .entry = main2 },
    .{ .entry = main3 },
    .{ .entry = main4 },
};

const WorkerTaskCount = worker_task_specs.len;
const TaskCount = 1 + WorkerTaskCount;

pub const putByte = platform.putByte;
pub const putStr = platform.putStr;
pub const putU64 = platform.putU64;
pub const getMtimeCsr = platform.getMtimeCsr;
pub const delayMs = platform.delayMs;


// needs to be in line with offsets in start.S
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
export var current_task_index: u32 = 0;

var task_contexts: [TaskCount]TaskContext = [_]TaskContext{.{}} ** TaskCount;
var worker_task_stacks: [WorkerTaskCount][StackSize]u8 align(16) = [_][StackSize]u8{[_]u8{0} ** StackSize} ** WorkerTaskCount;

fn fillStackGuard(stack: *[StackSize]u8) void {
    @memset(stack[0..StackGuardSize], StackGuardByte);
}

fn stackGuardIntact(stack: *const [StackSize]u8) bool {
    for (stack[0..StackGuardSize]) |byte| {
        if (byte != StackGuardByte) return false;
    }
    return true;
}

fn workerTaskIndexFromContext(ctx: *TaskContext) ?usize {
    for (worker_task_specs, 0..) |_, idx| {
        if (&task_contexts[idx + 1] == ctx) return idx;
    }
    return null;
}

fn putHexDigit(nibble: u4) void {
    const digit: u8 = if (nibble < 10)
        @as(u8, '0') + @as(u8, nibble)
    else
        @as(u8, 'A') + (@as(u8, nibble) - 10);
    putByte(digit);
}

fn putHex32(value: u32) void {
    var shift: u5 = 28;
    while (true) {
        putHexDigit(@as(u4, @truncate(value >> shift)));
        if (shift == 0) break;
        shift -= 4;
    }
}

fn reportTrap(current_ctx: *TaskContext, mcause: u32, mtval: u32) void {
    putStr("\nTRAP mcause=0x");
    putHex32(mcause);
    putStr(" mepc=0x");
    putHex32(current_ctx.mepc);
    putStr(" mtval=0x");
    putHex32(mtval);

    if ((mcause & 0x8000_0000) == 0) {
        putStr(" exception");
    } else {
        putStr(" interrupt");
    }

    if (mcause == 2) {
        putStr(" illegal-instruction");
    }

    putStr("\n");
}

fn checkCurrentStackGuard(current_ctx: *TaskContext) void {
    const worker_idx = workerTaskIndexFromContext(current_ctx) orelse return;
    if (stackGuardIntact(&worker_task_stacks[worker_idx])) return;

    putStr("\nSTACK OVERFLOW task=");
    putU64(worker_idx + 2);
    putStr(" sp=0x");
    putHex32(current_ctx.sp);
    putStr(" mepc=0x");
    putHex32(current_ctx.mepc);
    putStr("\n");
}

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

fn nextTask() *TaskContext {
    current_task_index = (current_task_index + 1) % TaskCount;
    return &task_contexts[current_task_index];
}

fn syncCurrentTaskIndex(current_ctx: *TaskContext) void {
    for (&task_contexts, 0..) |*ctx, idx| {
        if (ctx == current_ctx) {
            current_task_index = @as(u32, @intCast(idx));
            return;
        }
    }
}

pub fn setupTimer() void {
    platform.programTimerAfter(TIMER_INTERVAL_TICKS);
}

export fn schedulerInit() callconv(.c) void {
    current_task_index = 0;
    for (&task_contexts) |*ctx| ctx.* = .{};

    for (worker_task_specs, 0..) |spec, idx| {
        fillStackGuard(&worker_task_stacks[idx]);
        initTaskContext(&task_contexts[idx + 1], spec.entry, &worker_task_stacks[idx]);
    }

    current_task_ctx = @as(u32, @truncate(@intFromPtr(&task_contexts[0])));
}

export fn handleTrap(current_ctx: *TaskContext, mcause: u32, mtval: u32) callconv(.c) *TaskContext {
    syncCurrentTaskIndex(current_ctx);
    checkCurrentStackGuard(current_ctx);

    if (mcause == machine_timer_interrupt_mcause) {
        platform.programTimerAfter(TIMER_INTERVAL_TICKS);
        platform.putByte('@');
        const next = nextTask();
        current_task_ctx = @as(u32, @truncate(@intFromPtr(next)));
        return next;
    }

    reportTrap(current_ctx, mcause, mtval);
    current_task_ctx = @as(u32, @truncate(@intFromPtr(current_ctx)));
    return current_ctx;
}

pub fn runTaskLoop(comptime banner: []const u8, comptime tick_prefix: []const u8, delay_ms: u32) noreturn {
    putStr(banner);

    while (true) {
        putStr(tick_prefix);
        putU64(getMtimeCsr());
        putStr("\n");
        delayMs(delay_ms);
    }
}

export fn main2() u32 {
    runTaskLoop("START TASK main2\n", "LOOP TASK 2: =", 200);
}

export fn main3() u32 {
    runTaskLoop("START TASK main3\n", "LOOP TASK 3: =", 400);
}

export fn main4() u32 {
    runTaskLoop("START TASK main4\n", "LOOP TASK 4: =", 18200);
}