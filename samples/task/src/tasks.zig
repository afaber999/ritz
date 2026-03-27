extern const @"__global_pointer$": u8;
extern const _task_exit: u8;
extern fn timervec() callconv(.c) void;
extern fn startFirstTask() callconv(.c) noreturn;

const platform = @import("platform.zig");

const TIMER_INTERVAL_TICKS = 100_000;
const StackSize = 2048;
const StackGuardSize = 64;
const StackGuardByte: u8 = 0xA5;
const machine_timer_interrupt_mcause: u32 = 0x80000007;
const MaxTasks = 8;

const TaskEntry = *const fn () callconv(.c) u32;

pub const putByte = platform.putByte;
pub const putStr = platform.putStr;
pub const putU64 = platform.putU64;
pub const putHex32 = platform.putHex32;
pub const getMtimeCsr = platform.getMtimeCsr;
pub const delayMs = platform.delayMs;


var taskCriticalNesting : u32 = 0;

pub fn enterCritical() void {
    taskCriticalNesting += 1;
    if (taskCriticalNesting == 1) {
        platform.disableInterrupts();
    }
}

pub fn exitCritical() void {
    if (taskCriticalNesting == 0) {
        // This should not happen; maybe log an error or panic
        return;
    }
    taskCriticalNesting -= 1;
    if (taskCriticalNesting == 0) {
        platform.enableInterrupts();
    }
}

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

var task_contexts: [MaxTasks]TaskContext = [_]TaskContext{.{}} ** MaxTasks;
var task_stacks: [MaxTasks][StackSize]u8 align(16) = [_][StackSize]u8{[_]u8{0} ** StackSize} ** MaxTasks;
var task_entries: [MaxTasks]TaskEntry = undefined;
var task_count: u32 = 0;



fn fillStackGuard(stack: *[StackSize]u8) void {
    @memset(stack[0..StackGuardSize], StackGuardByte);
}

fn stackGuardIntact(stack: *const [StackSize]u8) bool {
    for (stack[0..StackGuardSize]) |byte| {
        if (byte != StackGuardByte) return false;
    }
    return true;
}

fn taskIndexFromContext(ctx: *TaskContext) ?usize {
    const count: usize = @intCast(task_count);
    for (0..count) |idx| {
        const c = &task_contexts[idx];
        if (c == ctx) return idx;
    }
    return null;
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
    const task_idx = taskIndexFromContext(current_ctx) orelse return;
    if (stackGuardIntact(&task_stacks[task_idx])) return;

    putStr("\nSTACK OVERFLOW task=");
    putU64(task_idx + 1);
    putStr(" sp=0x");
    putHex32(current_ctx.sp);
    putStr(" mepc=0x");
    putHex32(current_ctx.mepc);
    putStr("\n");
}

fn stackTop(stack: *[StackSize]u8) u32 {
    return @as(u32, @truncate(@intFromPtr(stack) + StackSize));
}

fn fillAllStackGuards() void {
    for (&task_stacks) |*stack| {
        fillStackGuard(stack);
    }
}

fn initTaskContext(ctx: *TaskContext, entry: *const fn () callconv(.c) u32, stack: *[StackSize]u8) void {
    ctx.* = .{};
    ctx.ra = @as(u32, @truncate(@intFromPtr(&_task_exit)));
    ctx.sp = stackTop(stack);
    ctx.gp = @as(u32, @truncate(@intFromPtr(&@"__global_pointer$")));
    ctx.mepc = @as(u32, @truncate(@intFromPtr(entry)));
}

fn nextTask() *TaskContext {
    current_task_index = (current_task_index + 1) % task_count;
    return &task_contexts[current_task_index];
}

fn syncCurrentTaskIndex(current_ctx: *TaskContext) void {
    const count: usize = @intCast(task_count);
    for (0..count) |idx| {
        const ctx = &task_contexts[idx];
        if (ctx == current_ctx) {
            current_task_index = @as(u32, @intCast(idx));
            return;
        }
    }
}


export fn handleTrap(current_ctx: *TaskContext, mcause: u32, mtval: u32) callconv(.c) *TaskContext {
    syncCurrentTaskIndex(current_ctx);
    checkCurrentStackGuard(current_ctx);

    if (mcause == machine_timer_interrupt_mcause) {
        platform.programTimerAfter(TIMER_INTERVAL_TICKS);
        //platform.putByte('@');
        const next = nextTask();
        current_task_ctx = @as(u32, @truncate(@intFromPtr(next)));
        return next;
    }

    reportTrap(current_ctx, mcause, mtval);
    current_task_ctx = @as(u32, @truncate(@intFromPtr(current_ctx)));
    return current_ctx;
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

pub fn createTask(entry: TaskEntry) bool {
    if (task_count >= MaxTasks) return false;
    const idx: usize = @intCast(task_count);
    task_entries[idx] = entry;
    task_count += 1;
    return true;
}

fn schedulerInit() void {
    current_task_index = 0;
    if (task_count == 0) {
        putStr("\nNo tasks registered. Call createTask() before taskStartScheduler()\n");
        while (true) {
            asm volatile ("wfi");
        }
    }

    const count: usize = @intCast(task_count);
    for (0..count) |idx| task_contexts[idx] = .{};

    fillAllStackGuards();
    for (0..count) |idx| {
        initTaskContext(&task_contexts[idx], task_entries[idx], &task_stacks[idx]);
    }

    current_task_ctx = @as(u32, @truncate(@intFromPtr(&task_contexts[0])));
}

pub fn startScheduler() noreturn {
    schedulerInit();
    platform.programTimerAfter(TIMER_INTERVAL_TICKS);
    enableTimerInterrupt();
    startFirstTask();
}
