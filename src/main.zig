const std = @import("std");
const Memory = @import("memory.zig").Memory;
const RV32 = @import("rv32.zig").RV32;
const Devices = @import("devices.zig").Devices;
const Output = @import("output.zig").Output;

fn usage() void {
    std.debug.print("Usage: ritz [-s <memstart>] [-l <memlen>] [-f memimage]\n", .{});
}

fn parseIntAuto(text: []const u8) !u64 {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len >= 2 and t[0] == '0' and (t[1] == 'x' or t[1] == 'X')) {
        return std.fmt.parseUnsigned(u64, t[2..], 16);
    }
    return std.fmt.parseUnsigned(u64, t, 10);
}

fn run(cpu: *RV32, count: u64) !void {
    const saved = cpu.setTrace(0);
    var c = count;
    var num_instructions: u64 = 0;

    if ( c == 0) {
        while (!(try cpu.exec())) {num_instructions += 1;}
    } else {
        while (c > 0) : (c -= 1) {
            if (try cpu.exec()) break;
            num_instructions += 1;
        }
    }
    std.debug.print("g executed {d} instructions\n", .{num_instructions});

    _ = cpu.setTrace(saved);
}

fn cli_g(cpu: *RV32, pc: ?u64, count: u64) !void {
    if (pc) |p| cpu.setPc(@bitCast(@as(u32, @truncate(p))));
    try run(cpu, count  );
}

fn cli_t(cpu: *RV32, pc: ?u64, count: u64, regs: bool) !void {
    if (pc) |p| cpu.setPc(@bitCast(@as(u32, @truncate(p))));
    var c = count;
    while (c > 0) : (c -= 1) {
        if (regs) try cpu.dump();
        if (try cpu.exec()) break;
    }
}

fn cli_r(cpu: *RV32) !void {
    try cpu.dump();
}

fn cli_d(mem: *Memory, start: u64, len: u64) !void {
    try mem.dump(start, len);
}

fn parseCmdAndArgs(buf: []const u8, cmd_out: []u8) struct { cmd: []const u8, args: []const u8 } {
    var i: usize = 0;
    while (i < buf.len and (std.ascii.isAlphabetic(buf[i]) or buf[i] == '?' or buf[i] == '>')) : (i += 1) {
        cmd_out[i] = buf[i];
    }
    const cmd = cmd_out[0..i];
    const args = buf[i..];
    return .{ .cmd = cmd, .args = args };
}

fn cli(cpu: *RV32, mem: *Memory, out: *Output, allocator: std.mem.Allocator) !void {
    var stdin_file = std.fs.File.stdin();
    const in = stdin_file.deprecatedReader();

    var running = true;
    var buf: [2048]u8 = [_]u8{0} ** 2048;
    var last: [2048]u8 = [_]u8{0} ** 2048;
    var d_next: u64 = 0;
    const echo = !stdin_file.isTty();

    _ = allocator;

    try out.print("This is ritz.  Enter ? for help.\n", .{});
    while (running) {
        try out.print("ritz> ", .{});

        const line_opt = try in.readUntilDelimiterOrEof(buf[0..], '\n');
        var line: []u8 = undefined;
        if (line_opt) |l| {
            line = l;
        } else {
            line = buf[0..1];
            line[0] = 'x';
        }

        var line_end = line.len;
        while (line_end > 0 and std.ascii.isWhitespace(line[line_end - 1])) : (line_end -= 1) {}
        line = line[0..line_end];

        if (line.len == 0) {
            const ll = std.mem.indexOfScalar(u8, last[0..], 0) orelse last.len;
            line = buf[0..ll];
            @memcpy(line, last[0..ll]);
        }

        @memset(last[0..], 0);

        if (echo and line.len > 0) {
            try out.print("{s}\n", .{line});
        }

        var cmd_buf: [2048]u8 = [_]u8{0} ** 2048;
        const parts = parseCmdAndArgs(line, cmd_buf[0..]);
        const cmd = parts.cmd;
        const args = std.mem.trimLeft(u8, parts.args, " \t");

        if (cmd.len == 0) {
            continue;
        } else if (std.mem.eql(u8, cmd, "x")) {
            running = false;
        } else if (std.mem.eql(u8, cmd, "r")) {
            try cli_r(cpu);
        } else if (std.mem.eql(u8, cmd, "t") or std.mem.eql(u8, cmd, "ti")) {
            var tok = std.mem.tokenizeAny(u8, args, " \t");
            const a = tok.next();
            const b = tok.next();
            const regs = std.mem.eql(u8, cmd, "t");
            if (a != null and b != null) {
                try cli_t(cpu, try parseIntAuto(a.?), try parseIntAuto(b.?), regs);
            } else if (a != null) {
                try cli_t(cpu, null, try parseIntAuto(a.?), regs);
            } else {
                try cli_t(cpu, null, 1, regs);
            }
            if (regs) {
                @memcpy(last[0..1], "t");
            } else {
                @memcpy(last[0..2], "ti");
            }
        } else if (std.mem.eql(u8, cmd, "g")) {
            var tok = std.mem.tokenizeAny(u8, args, " \t");
            const a = tok.next();
            const b = tok.next();
            if (a != null and b != null) {
                try cli_g(cpu, try parseIntAuto(a.?), try parseIntAuto(b.?));
            } else if (a != null) {
                try cli_g(cpu, null, try parseIntAuto(a.?));
            } else {
                try cli_g(cpu, null, 0);
            }

            // if (a != null and b != null)  {
            // } else {
            //     try cli_g(cpu, null);
            // }
            @memcpy(last[0..line.len], line);
        } else if (std.mem.eql(u8, cmd, "d")) {
            const mw = mem.memoryWarnings;
            mem.memoryWarnings = 0;

            var addr = d_next;
            var count: u64 = 0x100;
            var tok = std.mem.tokenizeAny(u8, args, " \t");
            const a = tok.next();
            const b = tok.next();
            if (a != null and b != null) {
                addr = try parseIntAuto(a.?);
                count = try parseIntAuto(b.?);
            } else if (a != null) {
                addr = try parseIntAuto(a.?);
            }
            try cli_d(mem, addr, count);
            d_next = addr + count;
            mem.memoryWarnings = mw;
            @memcpy(last[0..1], "d");
        } else if (std.mem.eql(u8, cmd, ">")) {
            var tok = std.mem.tokenizeAny(u8, args, " \t");
            const a = tok.next();
            if (a == null) {
                try out.print("Invalid redirect (missing filename?)\n", .{});
                break;
            }
            if (std.mem.eql(u8, a.?, "-")) {
                try out.redirect(null);
            } else {
                try out.redirect(a.?);
            }
        } else if (std.mem.eql(u8, cmd, "a")) {
            cpu.regNamesABI = if (cpu.regNamesABI == 0) 1 else 0;
        } else if (std.mem.eql(u8, cmd, "?")) {
            try out.print(
                "commands:\n" ++
                    "   a                 toggle the display of register ABI and x-names\n" ++
                    "   d [addr [len]]    dump memory starting at addr for len bytes\n" ++
                    "   g [[addr] qty]    set pc=addr and silently execute qty instructions\n" ++
                    "   r                 dump the contents of the CPU regs\n" ++
                    "   t [[addr] qty]    set pc=addr and trace qty instructions\n" ++
                    "   ti [[addr] qty]   set pc=addr and trace qty instructions w/o reg dumps\n" ++
                    "   x                 exit\n" ++
                    "   > filename        redirect output to 'filename' (use - for stdout)\n",
                .{},
            );
        } else {
            try out.print("Illegal command.  Press ? for help.\n", .{});
        }
    }
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memstart: u64 = 0;
    var memlen: u64 = 0x10000;
    var loadfile: ?[]const u8 = null;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-s")) {
            const v = args.next() orelse {
                usage();
                return 1;
            };
            memstart = try parseIntAuto(v);
        } else if (std.mem.eql(u8, arg, "-l")) {
            const v = args.next() orelse {
                usage();
                return 1;
            };
            memlen = try parseIntAuto(v);
        } else if (std.mem.eql(u8, arg, "-f")) {
            loadfile = args.next() orelse {
                usage();
                return 1;
            };
        } else {
            usage();
            return 1;
        }
    }

    var out = Output{};
    defer out.deinit();

    var dev = Devices.init(allocator, &out);
    defer dev.deinit();
    try dev.addConsole();
    try dev.addMemcard();

    var mem = try Memory.init(allocator, memstart, memlen, &dev, &out);
    defer mem.deinit();

    var cpu = RV32.init(&mem, &out);

    const start: u32 = @truncate(memstart);
    cpu.setPc(@bitCast(start));

    const stackTop: u32 = @truncate(memstart + memlen);
    cpu.setReg(2, @bitCast(stackTop));

    try out.print("sp initialized to top of memory: 0x{X:0>8}\n", .{@as(u32, @bitCast(cpu.getReg(2)))});

    if (loadfile) |lf| {
        try out.print("Loading '{s}' to 0x{x}\n", .{ lf, start });
        try mem.readRaw(lf, start);
    }

    try cli(&cpu, &mem, &out, allocator);
    return 0;
}
