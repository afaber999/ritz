extern const @"__global_pointer$": u8;
extern const _task_exit: u8;
extern fn timervec() callconv(.c) void;
extern fn startFirstTask() callconv(.c) noreturn;

const root = @import("root");
const platform = @import("platform.zig");

const default_timer_interval_ticks = 100_000;
const TIMER_INTERVAL_TICKS = if (@hasDecl(root, "task_config") and @hasDecl(root.task_config, "timer_interval_ticks"))
    root.task_config.timer_interval_ticks
else
    default_timer_interval_ticks;
const default_stack_size = 2048;
const StackSize = if (@hasDecl(root, "task_config") and @hasDecl(root.task_config, "stack_size"))
    root.task_config.stack_size
else
    default_stack_size;
const StackGuardSize = 64;
const StackGuardByte: u8 = 0xA5;
const machine_timer_interrupt_mcause: u32 = 0x80000007;
const default_max_tasks = 8;
const MaxTasks = if (@hasDecl(root, "task_config"))
    root.task_config.max_tasks
else
    default_max_tasks;

comptime {
    if (TIMER_INTERVAL_TICKS == 0) {
        @compileError("task_config.timer_interval_ticks must be greater than zero");
    }
    if (StackSize <= StackGuardSize) {
        @compileError("task_config.stack_size must be greater than StackGuardSize");
    }
    if (MaxTasks == 0) {
        @compileError("task_config.max_tasks must be greater than zero");
    }
}

const TaskEntry = *const fn () u32;
const TaskState = enum(u8) {
    ready,
    blocked,
};

pub const Mutex = struct {
    state: u32 = 0,

    pub fn tryLock(self: *Mutex) bool {
        const irq = platform.irqSaveDisable();
        defer platform.irqRestore(irq);

        if (self.state != 0) return false;
        self.state = 1;
        return true;
    }

    pub fn lock(self: *Mutex) void {
        while (!self.tryLock()) {
            asm volatile ("nop");
        }
    }

    pub fn unlock(self: *Mutex) void {
        const irq = platform.irqSaveDisable();
        defer platform.irqRestore(irq);
        self.state = 0;
    }
};

pub const putByte = platform.putByte;
pub const putStr = platform.putStr;
pub const putU64 = platform.putU64;
pub const putHex32 = platform.putHex32;
pub const getMtimeCsr = platform.getMtimeCsr;

pub fn delayMs(n: u32) void {
    if (n == 0) return;
    if (task_count <= 1) {
        platform.delayMs(n);
        return;
    }

    const ticks_per_ms: u64 = platform.TICKER_PER_SEC / 1000;
    const wakeup_tick = getMtimeCsr() + (ticks_per_ms * @as(u64, n));

    var self_idx: usize = 0;
    {
        const irq = platform.irqSaveDisable();
        defer platform.irqRestore(irq);

        self_idx = @as(usize, @intCast(current_task_index));
        task_states[self_idx] = .blocked;
        task_wakeup_ticks[self_idx] = wakeup_tick;

        // Trigger a scheduling decision now, rather than waiting for the next periodic tick.
        platform.programTimerAfter(0);
    }

    while (true) {
        asm volatile ("wfi");

        const irq = platform.irqSaveDisable();
        defer platform.irqRestore(irq);
        // can fall through if another task woke us up early, 
        // but that's fine since we check the tick count in the loop condition
        if (task_states[self_idx] == .ready and getMtimeCsr() >= wakeup_tick) {
            task_wakeup_ticks[self_idx] = 0;
            break;
        }
    }
}


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
var total_context_switches: u64 = 0;

var task_contexts: [MaxTasks]TaskContext = [_]TaskContext{.{}} ** MaxTasks;
var task_stacks: [MaxTasks][StackSize]u8 align(16) = [_][StackSize]u8{[_]u8{0} ** StackSize} ** MaxTasks;
var task_entries: [MaxTasks]TaskEntry = undefined;
var task_states: [MaxTasks]TaskState = [_]TaskState{.ready} ** MaxTasks;
var task_wakeup_ticks: [MaxTasks]u64 = [_]u64{0} ** MaxTasks;
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

fn initTaskContext(ctx: *TaskContext, entry: *const fn () u32, stack: *[StackSize]u8) void {
    ctx.* = .{};
    ctx.ra = @as(u32, @truncate(@intFromPtr(&_task_exit)));
    ctx.sp = stackTop(stack);
    ctx.gp = @as(u32, @truncate(@intFromPtr(&@"__global_pointer$")));
    ctx.mepc = @as(u32, @truncate(@intFromPtr(entry)));
}

fn wakeBlockedTasks(now: u64) void {
    const count: usize = @intCast(task_count);
    for (0..count) |idx| {
        if (task_states[idx] != .blocked) continue;
        if (now < task_wakeup_ticks[idx]) continue;
        task_states[idx] = .ready;
        task_wakeup_ticks[idx] = 0;
    }
}

fn hasReadyTaskExcept(excluded_idx: usize) bool {
    const count: usize = @intCast(task_count);
    for (0..count) |idx| {
        if (idx == excluded_idx) continue;
        if (task_states[idx] == .ready) return true;
    }
    return false;
}

fn nextTask() *TaskContext {
    const count: usize = @intCast(task_count);
    var idx: usize = @intCast(current_task_index);

    var attempt: usize = 0;
    while (attempt < count) : (attempt += 1) {
        idx = (idx + 1) % count;
        if (task_states[idx] == .ready) {
            current_task_index = @as(u32, @intCast(idx));
            return &task_contexts[idx];
        }
    }

    // No READY task found; continue current context.
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
        wakeBlockedTasks(getMtimeCsr());
        platform.programTimerAfter(TIMER_INTERVAL_TICKS);
        //platform.putByte('@');
        const next = nextTask();
        if (next != current_ctx) {
            total_context_switches += 1;
        }
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
    task_states[idx] = .ready;
    task_wakeup_ticks[idx] = 0;
    task_count += 1;
    return true;
}

pub fn getContextSwitchCount() u64 {
    const irq = platform.irqSaveDisable();
    defer platform.irqRestore(irq);
    return total_context_switches;
}

pub fn taskYield() void {
    if (task_count <= 1) return;

    var baseline_switches: u64 = 0;
    {
        const irq = platform.irqSaveDisable();
        defer platform.irqRestore(irq);
        const self_idx: usize = @intCast(current_task_index);
        if (!hasReadyTaskExcept(self_idx)) return;
        baseline_switches = total_context_switches;
        // Ask CLINT for an immediate timer interrupt so the trap handler picks the next task.
        platform.programTimerAfter(0);
    }

    while (true) {
        asm volatile ("wfi");

        const irq = platform.irqSaveDisable();
        defer platform.irqRestore(irq);
        if (total_context_switches != baseline_switches) break;
    }
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

    total_context_switches = 0;
    for (0..count) |idx| {
        task_states[idx] = .ready;
        task_wakeup_ticks[idx] = 0;
    }
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
