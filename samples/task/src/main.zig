const tasks = @import("tasks.zig");

pub const task_config = struct {
    pub const max_tasks = 4;
    pub const timer_interval_ticks = 100_000;
    pub const stack_size = 2048;
};

var output_mutex: tasks.Mutex = .{};

fn runTaskLoop(comptime banner: []const u8, comptime tick_prefix: []const u8, delay_ms: u32) noreturn {
    tasks.putStr(banner);

    while (true) {
        {
            output_mutex.lock();
            defer output_mutex.unlock();

            tasks.putStr(tick_prefix);
            tasks.delayMs(100);
            tasks.putU64(tasks.getMtimeCsr());
            tasks.delayMs(100);
            tasks.putStr("\n");
            tasks.delayMs(100);
        }
        tasks.delayMs(delay_ms);
    }
}

fn main1() u32 {
    runTaskLoop("START TASK main1\n", "LOOP TASK 1: =", 1000);
}

fn main2() u32 {
    runTaskLoop("START TASK main2\n", "LOOP TASK 2: =", 200);
}

fn main3() u32 {
    runTaskLoop("START TASK main3\n", "LOOP TASK 3: =", 400);
}

fn main4() u32 {
    runTaskLoop("START TASK main4\n", "LOOP TASK 4: =", 4000);
}


export fn main() u32 {
    _ = tasks.createTask(main1);
    _ = tasks.createTask(main2);
    _ = tasks.createTask(main3);
    _ = tasks.createTask(main4);
    tasks.startScheduler();
}

