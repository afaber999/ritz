const std = @import("std");
const Machine = @import("machine.zig").Machine;
const RV32CoreType = @import("rv32core.zig").RV32CoreType;
const Devices = @import("devices.zig").Devices;
const Output = @import("output.zig").Output;

pub const RV32SOC = RV32CoreType(Machine);


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

fn run(soc: *RV32SOC, count: u64) !void {
    const saved = soc.setTrace(0);
    var c = count;
    var num_instructions: u64 = 0;

    if ( c == 0) {
        while (!(try soc.exec())) {num_instructions += 1;}
    } else {
        while (c > 0) : (c -= 1) {
            if (try soc.exec()) break;
            num_instructions += 1;
        }
    }
    std.debug.print("g executed {d} instructions\n", .{num_instructions});

    _ = soc.setTrace(saved);
}

fn cli_g(soc: *RV32SOC, pc: ?u64, count: u64) !void {
    if (pc) |p| soc.setPc(@bitCast(@as(u32, @truncate(p))));
    try run(soc, count  );
}

fn cli_t(soc: *RV32SOC, pc: ?u64, count: u64, regs: bool) !void {
    if (pc) |p| soc.setPc(@bitCast(@as(u32, @truncate(p))));
    var c = count;
    while (c > 0) : (c -= 1) {
        if (regs) try soc.dump();
        if (try soc.exec()) break;
    }
}

fn cli_r(soc: *RV32SOC) !void {
    try soc.dump();
}

fn cli_d(machine: *Machine, start: u64, len: u64) !void {
    try machine.dump(start, len);
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

fn cli(soc: *RV32SOC, machine: *Machine, out: *Output, allocator: std.mem.Allocator) !void {
    var stdin_file = std.fs.File.stdin();
    const in = stdin_file.deprecatedReader();

    var running = true;
    var buf: [2048]u8 = [_]u8{0} ** 2048;
    var last: [2048]u8 = [_]u8{0} ** 2048;
    var d_next: u64 = machine.start;
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
            try cli_r(soc);
        } else if (std.mem.eql(u8, cmd, "t") or std.mem.eql(u8, cmd, "ti")) {
            var tok = std.mem.tokenizeAny(u8, args, " \t");
            const a = tok.next();
            const b = tok.next();
            const regs = std.mem.eql(u8, cmd, "t");
            if (a != null and b != null) {
                try cli_t(soc, try parseIntAuto(a.?), try parseIntAuto(b.?), regs);
            } else if (a != null) {
                try cli_t(soc, null, try parseIntAuto(a.?), regs);
            } else {
                try cli_t(soc, null, 1, regs);
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
                try cli_g(soc, try parseIntAuto(a.?), try parseIntAuto(b.?));
            } else if (a != null) {
                try cli_g(soc, null, try parseIntAuto(a.?));
            } else {
                try cli_g(soc, null, 0);
            }

            // if (a != null and b != null)  {
            // } else {
            //     try cli_g(soc, null);
            // }
            @memcpy(last[0..line.len], line);
        } else if (std.mem.eql(u8, cmd, "d")) {
            const mw = machine.memoryWarnings;
            machine.memoryWarnings = 0;

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
            try cli_d(machine, addr, count);
            d_next = addr + count;
            machine.memoryWarnings = mw;
            @memcpy(last[0..1], "d");
        } else if (std.mem.eql(u8, cmd, "b")) {
            machine.memoryWarnings = 0;

            var addr = d_next;
            var tok = std.mem.tokenizeAny(u8, args, " \t");
            const a = tok.next();
            if (a != null) {
                addr = try parseIntAuto(a.?);
            } else if (a != null) {
                addr = 0x0000;
            }
            soc.breakpoint = @bitCast(@as(u32, @truncate(addr)));
            @memcpy(last[0..1], "b");
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
            soc.regNamesABI = if (soc.regNamesABI == 0) 1 else 0;
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

fn csrFlagsByAddress(csr: u12) []const u8 {
    const access: u2 = @intCast((csr >> 10) & 0b11);
    const priv: u2 = @intCast((csr >> 8) & 0b11);

    // Per CSR address mapping conventions, csr[11:10] bit1 indicates RO vs RW,
    // and csr[9:8] encode the lowest privilege level.
    const is_ro = (access & 0b10) != 0;
    return switch (priv) {
        0b00 => if (is_ro) "URO" else "URW",
        0b01 => if (is_ro) "SRO" else "SRW",
        0b10 => if (is_ro) "HRO" else "HRW",
        0b11 => if (is_ro) "MRO" else "MRW",
    };
}

pub fn csrNameFromNumber(csr: u12) ![]const u8 {
    inline for (std.meta.fields(Csr)) |field| {
        if (field.value == csr) {
            return field.name;
        }
    }
    return error.UnknownCsr;
}

fn CsrDump() !void {
    inline for (std.meta.fields(Csr)) |field| {
        const value: u12 = @intCast(field.value);
        std.debug.print("{s} 0x{X:0>3} {s}\n", .{ field.name, value, csrFlagsByAddress(value) });
    }
}

pub fn main() !u8 {
    //try CsrDump();

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
        if (std.mem.eql    (u8, arg, "-s")) {
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

    var machine = try Machine.init(
        allocator,
        memstart,
        memlen,
        &dev,
        &out,
        0x02000000,
        0x10000000,
    );
    defer machine.deinit();


    var soc = RV32SOC.init(&machine, &out);

    const start: u32 = @truncate(memstart);
    soc.setPc(@bitCast(start));

    const stackTop: u32 = @truncate(memstart + memlen);
    soc.setReg(2, @bitCast(stackTop));

    try out.print("sp initialized to top of memory: 0x{X:0>8}\n", .{@as(u32, @bitCast(soc.getReg(2)))});

    if (loadfile) |lf| {
        try out.print("Loading '{s}' to 0x{x}\n", .{ lf, start });
        try machine.readRaw(lf, start);
    }

    try cli(&soc, &machine, &out, allocator);
    return 0;
}






pub const Csr = enum(u12) {
    fflags = 0x001,
    frm = 0x002,
    fcsr = 0x003,
    cycle = 0xC00,
    time = 0xC01,
    instret = 0xC02,
    hpmcounter3 = 0xC03,
    hpmcounter4 = 0xC04,
    hpmcounter5 = 0xC05,
    hpmcounter6 = 0xC06,
    hpmcounter7 = 0xC07,
    hpmcounter8 = 0xC08,
    hpmcounter9 = 0xC09,
    hpmcounter10 = 0xC0A,
    hpmcounter11 = 0xC0B,
    hpmcounter12 = 0xC0C,
    hpmcounter13 = 0xC0D,
    hpmcounter14 = 0xC0E,
    hpmcounter15 = 0xC0F,
    hpmcounter16 = 0xC10,
    hpmcounter17 = 0xC11,
    hpmcounter18 = 0xC12,
    hpmcounter19 = 0xC13,
    hpmcounter20 = 0xC14,
    hpmcounter21 = 0xC15,
    hpmcounter22 = 0xC16,
    hpmcounter23 = 0xC17,
    hpmcounter24 = 0xC18,
    hpmcounter25 = 0xC19,
    hpmcounter26 = 0xC1A,
    hpmcounter27 = 0xC1B,
    hpmcounter28 = 0xC1C,
    hpmcounter29 = 0xC1D,
    hpmcounter30 = 0xC1E,
    hpmcounter31 = 0xC1F,
    cycleh = 0xC80,
    timeh = 0xC81,
    instreth = 0xC82,
    hpmcounter3h = 0xC83,
    hpmcounter4h = 0xC84,
    hpmcounter5h = 0xC85,
    hpmcounter6h = 0xC86,
    hpmcounter7h = 0xC87,
    hpmcounter8h = 0xC88,
    hpmcounter9h = 0xC89,
    hpmcounter10h = 0xC8A,
    hpmcounter11h = 0xC8B,
    hpmcounter12h = 0xC8C,
    hpmcounter13h = 0xC8D,
    hpmcounter14h = 0xC8E,
    hpmcounter15h = 0xC8F,
    hpmcounter16h = 0xC90,
    hpmcounter17h = 0xC91,
    hpmcounter18h = 0xC92,
    hpmcounter19h = 0xC93,
    hpmcounter20h = 0xC94,
    hpmcounter21h = 0xC95,
    hpmcounter22h = 0xC96,
    hpmcounter23h = 0xC97,
    hpmcounter24h = 0xC98,
    hpmcounter25h = 0xC99,
    hpmcounter26h = 0xC9A,
    hpmcounter27h = 0xC9B,
    hpmcounter28h = 0xC9C,
    hpmcounter29h = 0xC9D,
    hpmcounter30h = 0xC9E,
    hpmcounter31h = 0xC9F,
    sstatus = 0x100,
    sie = 0x104,
    stvec = 0x105,
    scounteren = 0x106,
    senvcfg = 0x10A,
    sscratch = 0x140,
    sepc = 0x141,
    scause = 0x142,
    stval = 0x143,
    sip = 0x144,
    satp = 0x180,
    scontext = 0x5A8,
    hstatus = 0x600,
    hedeleg = 0x602,
    hideleg = 0x603,
    hie = 0x604,
    hcounteren = 0x606,
    hgeie = 0x607,
    htval = 0x643,
    hip = 0x644,
    hvip = 0x645,
    htinst = 0x64A,
    hgeip = 0xE12,
    henvcfg = 0x60A,
    henvcfgh = 0x61A,
    hgatp = 0x680,
    hcontext = 0x6A8,
    htimedelta = 0x605,
    htimedeltah = 0x615,
    vsstatus = 0x200,
    vsie = 0x204,
    vstvec = 0x205,
    vsscratch = 0x240,
    vsepc = 0x241,
    vscause = 0x242,
    vstval = 0x243,
    vsip = 0x244,
    vsatp = 0x280,
    mvendorid = 0xF11,
    marchid = 0xF12,
    mimpid = 0xF13,
    mhartid = 0xF14,
    mconfigptr = 0xF15,
    mstatus = 0x300,
    misa = 0x301,
    medeleg = 0x302,
    mideleg = 0x303,
    mie = 0x304,
    mtvec = 0x305,
    mcounteren = 0x306,
    mstatush = 0x310,
    mscratch = 0x340,
    mepc = 0x341,
    mcause = 0x342,
    mtval = 0x343,
    mip = 0x344,
    mtinst = 0x34A,
    mtval2 = 0x34B,
    menvcfg = 0x30A,
    menvcfgh = 0x31A,
    mseccfg = 0x747,
    mseccfgh = 0x757,
    pmpcfg0 = 0x3A0,
    pmpcfg1 = 0x3A1,
    pmpcfg2 = 0x3A2,
    pmpcfg3 = 0x3A3,
    pmpcfg4 = 0x3A4,
    pmpcfg5 = 0x3A5,
    pmpcfg6 = 0x3A6,
    pmpcfg7 = 0x3A7,
    pmpcfg8 = 0x3A8,
    pmpcfg9 = 0x3A9,
    pmpcfg10 = 0x3AA,
    pmpcfg11 = 0x3AB,
    pmpcfg12 = 0x3AC,
    pmpcfg13 = 0x3AD,
    pmpcfg14 = 0x3AE,
    pmpcfg15 = 0x3AF,
    pmpaddr0 = 0x3B0,
    pmpaddr1 = 0x3B1,
    pmpaddr63 = 0x3EF,
    mcycle = 0xB00,
    minstret = 0xB02,
    mhpmcounter3 = 0xB03,
    mhpmcounter4 = 0xB04,
    mhpmcounter5 = 0xB05,
    mhpmcounter6 = 0xB06,
    mhpmcounter7 = 0xB07,
    mhpmcounter8 = 0xB08,
    mhpmcounter9 = 0xB09,
    mhpmcounter10 = 0xB0A,
    mhpmcounter11 = 0xB0B,
    mhpmcounter12 = 0xB0C,
    mhpmcounter13 = 0xB0D,
    mhpmcounter14 = 0xB0E,
    mhpmcounter15 = 0xB0F,
    mhpmcounter16 = 0xB10,
    mhpmcounter17 = 0xB11,
    mhpmcounter18 = 0xB12,
    mhpmcounter19 = 0xB13,
    mhpmcounter20 = 0xB14,
    mhpmcounter21 = 0xB15,
    mhpmcounter22 = 0xB16,
    mhpmcounter23 = 0xB17,
    mhpmcounter24 = 0xB18,
    mhpmcounter25 = 0xB19,
    mhpmcounter26 = 0xB1A,
    mhpmcounter27 = 0xB1B,
    mhpmcounter28 = 0xB1C,
    mhpmcounter29 = 0xB1D,
    mhpmcounter30 = 0xB1E,
    mhpmcounter31 = 0xB1F,
    mcycleh = 0xB80,
    minstreth = 0xB82,
    mhpmcounter3h = 0xB83,
    mhpmcounter4h = 0xB84,
    mhpmcounter5h = 0xB85,
    mhpmcounter6h = 0xB86,
    mhpmcounter7h = 0xB87,
    mhpmcounter8h = 0xB88,
    mhpmcounter9h = 0xB89,
    mhpmcounter10h = 0xB8A,
    mhpmcounter11h = 0xB8B,
    mhpmcounter12h = 0xB8C,
    mhpmcounter13h = 0xB8D,
    mhpmcounter14h = 0xB8E,
    mhpmcounter15h = 0xB8F,
    mhpmcounter16h = 0xB90,
    mhpmcounter17h = 0xB91,
    mhpmcounter18h = 0xB92,
    mhpmcounter19h = 0xB93,
    mhpmcounter20h = 0xB94,
    mhpmcounter21h = 0xB95,
    mhpmcounter22h = 0xB96,
    mhpmcounter23h = 0xB97,
    mhpmcounter24h = 0xB98,
    mhpmcounter25h = 0xB99,
    mhpmcounter26h = 0xB9A,
    mhpmcounter27h = 0xB9B,
    mhpmcounter28h = 0xB9C,
    mhpmcounter29h = 0xB9D,
    mhpmcounter30h = 0xB9E,
    mhpmcounter31h = 0xB9F,
    mcountinhibit = 0x320,
    mhpmevent3 = 0x323,
    mhpmevent4 = 0x324,
    mhpmevent5 = 0x325,
    mhpmevent6 = 0x326,
    mhpmevent7 = 0x327,
    mhpmevent8 = 0x328,
    mhpmevent9 = 0x329,
    mhpmevent10 = 0x32A,
    mhpmevent11 = 0x32B,
    mhpmevent12 = 0x32C,
    mhpmevent13 = 0x32D,
    mhpmevent14 = 0x32E,
    mhpmevent15 = 0x32F,
    mhpmevent16 = 0x330,
    mhpmevent17 = 0x331,
    mhpmevent18 = 0x332,
    mhpmevent19 = 0x333,
    mhpmevent20 = 0x334,
    mhpmevent21 = 0x335,
    mhpmevent22 = 0x336,
    mhpmevent23 = 0x337,
    mhpmevent24 = 0x338,
    mhpmevent25 = 0x339,
    mhpmevent26 = 0x33A,
    mhpmevent27 = 0x33B,
    mhpmevent28 = 0x33C,
    mhpmevent29 = 0x33D,
    mhpmevent30 = 0x33E,
    mhpmevent31 = 0x33F,
    tselect = 0x7A0,
    tdata1 = 0x7A1,
    tdata2 = 0x7A2,
    tdata3 = 0x7A3,
    mcontext = 0x7A8,
    dcsr = 0x7B0,
    dpc = 0x7B1,
    dscratch0 = 0x7B2,
    dscratch1 = 0x7B3,
};
