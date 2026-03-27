const tasks = @import("tasks.zig");

export fn main() u32 {
    tasks.taskStartScheduler();
}
