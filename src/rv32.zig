const std = @import("std");
const Memory = @import("memory.zig").Memory;
const Output = @import("output.zig").Output;

pub const RV32 = struct {
    reg: [32]i32 = [_]i32{0} ** 32,
    pc: u32 = 0,
    trace: i32 = 1,
    regNamesABI: i32 = 0,
    mem: *Memory,
    out: *Output,

    const regNames = [2][32][]const u8{
        .{ "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23", "x24", "x25", "x26", "x27", "x28", "x29", "x30", "x31" },
        .{ "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6" },
    };

    pub fn init(mem: *Memory, out: *Output) RV32 {
        var cpu = RV32{ .mem = mem, .out = out };
        cpu.reset();
        return cpu;
    }

    pub fn reset(self: *RV32) void {
        self.pc = 0;
        for (1..self.reg.len) |i| self.reg[i] = @bitCast(@as(u32, 0xf0f0f0f0));
        self.reg[0] = 0;
        self.trace = 1;
        self.regNamesABI = 0;
    }

    pub fn dump(self: *RV32) !void {
        if (self.regNamesABI != 0) {
            for (0..self.reg.len) |i| {
                if (i % 4 == 0) try self.out.print("{s}", .{if (i == 0) "" else "\n"});
                try self.out.print("{s: >5} {s}{s} {X:0>8}", .{ self.getRegName(@intCast(i)), if (i < 10) " " else "", regNames[0][i], @as(u32, @bitCast(self.getReg(@intCast(i)))) });
            }
            try self.out.print("\n       pc {X:0>8}\n", .{self.pc});
        } else {
            for (0..self.reg.len) |i| {
                if (i % 8 == 0) try self.out.print("{s}  {s}x{d}", .{ if (i == 0) "" else "\n", if (i < 10) " " else "", i });
                try self.out.print("{s}{X:0>8}", .{ if (i % 8 != 0 and i % 4 == 0) "  " else " ", @as(u32, @bitCast(self.getReg(@intCast(i)))) });
            }
            try self.out.print("\n   pc {X:0>8}\n", .{self.pc});
        }
    }

    pub fn getReg(self: *RV32, r: u8) i32 {
        std.debug.assert(r < 32);
        return self.reg[r];
    }

    pub fn getPc(self: *RV32) i32 {
        return @bitCast(self.pc);
    }

    pub fn setReg(self: *RV32, r: u8, val: i32) void {
        std.debug.assert(r < 32);
        if (r > 0) self.reg[r] = val;
    }

    pub fn setPc(self: *RV32, val: i32) void {
        self.pc = @bitCast(val);
    }

    pub fn setTrace(self: *RV32, i: i32) i32 {
        const old = self.trace;
        self.trace = i;
        return old;
    }

    pub fn getRegName(self: *RV32, r: u8) []const u8 {
        std.debug.assert(r < 32);
        return regNames[@intCast(self.regNamesABI)][r];
    }

    pub fn exec(self: *RV32) !bool {
        if (self.pc % 4 != 0) {
            try self.out.print("ERROR: The program counter (0x{X:0>8}) is not a multiple of 4\n", .{self.pc});
            return true;
        }

        const insn_i32 = try self.mem.get32(self.pc);
        const insn: u32 = @bitCast(insn_i32);

        if (insn == 0x00100073) {
            try self.out.print("{X:0>8}: 00100073 ebreak\n", .{self.pc});
            return true;
        }
        if (insn == 0x00000073) {
            try self.out.print("{X:0>8}: 00000073 ecall (unimplemented)\n", .{self.pc});
            return true;
        }

        return self.execInsn(insn);
    }

    fn execInsn(self: *RV32, insn: u32) !bool {
        const opcode = self.getInsnOpcode(insn);
        const funct3 = self.getInsnFunct3(insn);
        const funct7 = self.getInsnFunct7(insn);

        if (self.trace != 0) {
            try self.out.print("{X:0>8}: ", .{self.pc});
        }

        switch (opcode) {
            0b0110111 => try self.execLui(insn),
            0b0010111 => try self.execAuipc(insn),
            0b1101111 => try self.execJal(insn),
            0b1100111 => if (funct3 == 0b000) try self.execJalr(insn) else return self.illegal(),
            0b1100011 => switch (funct3) {
                0b000 => try self.execBeq(insn),
                0b001 => try self.execBne(insn),
                0b100 => try self.execBlt(insn),
                0b101 => try self.execBge(insn),
                0b110 => try self.execBltu(insn),
                0b111 => try self.execBgeu(insn),
                else => return self.illegal(),
            },
            0b0000011 => switch (funct3) {
                0b000 => try self.execLb(insn),
                0b001 => try self.execLh(insn),
                0b010 => try self.execLw(insn),
                0b100 => try self.execLbu(insn),
                0b101 => try self.execLhu(insn),
                else => return self.illegal(),
            },
            0b0100011 => switch (funct3) {
                0b000 => try self.execSb(insn),
                0b001 => try self.execSh(insn),
                0b010 => try self.execSw(insn),
                else => return self.illegal(),
            },
            0b0010011 => switch (funct3) {
                0b000 => try self.execAddi(insn),
                0b010 => try self.execSlti(insn),
                0b011 => try self.execSltiu(insn),
                0b100 => try self.execXori(insn),
                0b110 => try self.execOri(insn),
                0b111 => try self.execAndi(insn),
                0b001 => if (funct7 == 0b0000000) try self.execSlli(insn) else return self.illegal(),
                0b101 => switch (funct7) {
                    0b0000000 => try self.execSrli(insn),
                    0b0100000 => try self.execSrai(insn),
                    else => return self.illegal(),
                },
                else => return self.illegal(),
            },
            0b0110011 => switch (funct3) {
                0b000 => switch (funct7) {
                    0b0000000 => try self.execAdd(insn),
                    0b0100000 => try self.execSub(insn),
                    else => return self.illegal(),
                },
                0b001 => if (funct7 == 0b0000000) try self.execSll(insn) else return self.illegal(),
                0b010 => if (funct7 == 0b0000000) try self.execSlt(insn) else return self.illegal(),
                0b011 => if (funct7 == 0b0000000) try self.execSltu(insn) else return self.illegal(),
                0b100 => if (funct7 == 0b0000000) try self.execXor(insn) else return self.illegal(),
                0b101 => switch (funct7) {
                    0b0000000 => try self.execSrl(insn),
                    0b0100000 => try self.execSra(insn),
                    else => return self.illegal(),
                },
                0b110 => if (funct7 == 0b0000000) try self.execOr(insn) else return self.illegal(),
                0b111 => if (funct7 == 0b0000000) try self.execAnd(insn) else return self.illegal(),
                else => return self.illegal(),
            },
            else => return self.illegal(),
        }

        if (self.trace != 0) try self.out.print("\n", .{});
        return false;
    }

    fn illegal(self: *RV32) bool {
        self.out.print("(illegal)\n", .{}) catch {};
        return true;
    }

    fn traceInsn(self: *RV32, comptime fmt: []const u8, args: anytype) !void {
        if (self.trace != 0) try self.out.print(fmt, args);
    }

    fn traceInsnComment(self: *RV32, comptime insn_fmt: []const u8, insn_args: anytype, comptime comment_fmt: []const u8, comment_args: anytype) !void {
        if (self.trace == 0) return;

        const COMMENT_OFFSET: usize = 34;
        var ibuf: [256]u8 = undefined;
        const istr = try std.fmt.bufPrint(&ibuf, insn_fmt, insn_args);
        try self.out.print("{s}", .{istr});

        if (istr.len < COMMENT_OFFSET) {
            for (0..(COMMENT_OFFSET - istr.len)) |_| {
                try self.out.print(" ", .{});
            }
        } else {
            try self.out.print(" ", .{});
        }

        try self.out.print("# ", .{});
        try self.out.print(comment_fmt, comment_args);
    }

    fn execLui(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmU(insn);
        const rd = self.getInsnRd(insn);
        try self.traceInsnComment(
            "{x:0>8} lui    {s}, 0x{x}",
            .{ insn, self.getRegName(rd), @as(u32, @bitCast(imm)) >> 12 },
            "{s} = 0x{x:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, imm);
        self.pc +%= 4;
    }

    fn execAuipc(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmU(insn);
        const rd = self.getInsnRd(insn);
        const target = @as(i32, @bitCast(self.pc)) +% imm;
        try self.traceInsnComment(
            "{x:0>8} auipc  {s}, 0x{x}",
            .{ insn, self.getRegName(rd), @as(u32, @bitCast(imm)) >> 12 },
            "{s} = 0x{x:0>8} = 0x{x:0>8} + 0x{x:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(target)), self.pc, @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, target);
        self.pc +%= 4;
    }

    fn execJal(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmJ(insn);
        const rd = self.getInsnRd(insn);
        const target = @as(i32, @bitCast(self.pc)) +% imm;
        try self.traceInsnComment(
            "{x:0>8} jal    {s}, 0x{x}",
            .{ insn, self.getRegName(rd), @as(u32, @bitCast(target)) },
            "pc = 0x{x:0>8} = 0x{x:0>8} + 0x{x:0>8}",
            .{ @as(u32, @bitCast(target)), self.pc, @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, @bitCast(self.pc +% 4));
        self.setPc(target);
    }

    fn execJalr(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rd = self.getInsnRd(insn);
        const rs1 = self.getInsnRs1(insn);
        const target = (self.getReg(rs1) +% imm) & ~@as(i32, 1);
        try self.traceInsnComment(
            "{x:0>8} jalr   {s}, {d}({s})",
            .{ insn, self.getRegName(rd), imm, self.getRegName(rs1) },
            "{s} = 0x{x:0>8}, pc = 0x{x:0>8} = {d}(0x{x:0>8})&~1",
            .{ self.getRegName(rd), self.pc +% 4, @as(u32, @bitCast(target)), imm, @as(u32, @bitCast(self.getReg(rs1))) },
        );
        self.setReg(rd, @bitCast(self.pc +% 4));
        self.setPc(target);
    }

    fn execBeq(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmB(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const ttarget = @as(i32, @bitCast(self.pc)) +% imm;
        const ftarget = @as(i32, @bitCast(self.pc)) +% 4;
        try self.traceInsnComment(
            "{x:0>8} beq    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(rs1), self.getRegName(rs2), @as(u32, @bitCast(ttarget)) },
            "pc = (0x{x} == 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))), @as(u32, @bitCast(ttarget)), @as(u32, @bitCast(ftarget)) },
        );
        if (self.getReg(rs1) == self.getReg(rs2)) self.setPc(ttarget) else self.setPc(ftarget);
    }

    fn execBne(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmB(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const ttarget = @as(i32, @bitCast(self.pc)) +% imm;
        const ftarget = @as(i32, @bitCast(self.pc)) +% 4;
        try self.traceInsnComment(
            "{x:0>8} bne    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(rs1), self.getRegName(rs2), @as(u32, @bitCast(ttarget)) },
            "pc = (0x{x} != 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))), @as(u32, @bitCast(ttarget)), @as(u32, @bitCast(ftarget)) },
        );
        if (self.getReg(rs1) != self.getReg(rs2)) self.setPc(ttarget) else self.setPc(ftarget);
    }

    fn execBlt(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmB(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const ttarget = @as(i32, @bitCast(self.pc)) +% imm;
        const ftarget = @as(i32, @bitCast(self.pc)) +% 4;
        try self.traceInsnComment(
            "{x:0>8} blt    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(rs1), self.getRegName(rs2), @as(u32, @bitCast(ttarget)) },
            "pc = (0x{x} < 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))), @as(u32, @bitCast(ttarget)), @as(u32, @bitCast(ftarget)) },
        );
        if (self.getReg(rs1) < self.getReg(rs2)) self.setPc(ttarget) else self.setPc(ftarget);
    }

    fn execBge(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmB(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const ttarget = @as(i32, @bitCast(self.pc)) +% imm;
        const ftarget = @as(i32, @bitCast(self.pc)) +% 4;
        try self.traceInsnComment(
            "{x:0>8} bge    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(rs1), self.getRegName(rs2), @as(u32, @bitCast(ttarget)) },
            "pc = (0x{x} >= 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))), @as(u32, @bitCast(ttarget)), @as(u32, @bitCast(ftarget)) },
        );
        if (self.getReg(rs1) >= self.getReg(rs2)) self.setPc(ttarget) else self.setPc(ftarget);
    }

    fn execBltu(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmB(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const ttarget = @as(i32, @bitCast(self.pc)) +% imm;
        const ftarget = @as(i32, @bitCast(self.pc)) +% 4;
        try self.traceInsnComment(
            "{x:0>8} bltu   {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(rs1), self.getRegName(rs2), @as(u32, @bitCast(ttarget)) },
            "pc = (0x{x} < 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))), @as(u32, @bitCast(ttarget)), @as(u32, @bitCast(ftarget)) },
        );
        if (@as(u32, @bitCast(self.getReg(rs1))) < @as(u32, @bitCast(self.getReg(rs2)))) self.setPc(ttarget) else self.setPc(ftarget);
    }

    fn execBgeu(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmB(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const ttarget = @as(i32, @bitCast(self.pc)) +% imm;
        const ftarget = @as(i32, @bitCast(self.pc)) +% 4;
        try self.traceInsnComment(
            "{x:0>8} bgeu   {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(rs1), self.getRegName(rs2), @as(u32, @bitCast(ttarget)) },
            "pc = (0x{x} => 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))), @as(u32, @bitCast(ttarget)), @as(u32, @bitCast(ftarget)) },
        );
        if (@as(u32, @bitCast(self.getReg(rs1))) >= @as(u32, @bitCast(self.getReg(rs2)))) self.setPc(ttarget) else self.setPc(ftarget);
    }

    fn execLb(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const m8 = try self.mem.get8(addr);
        try self.traceInsnComment(
            "{x:0>8} lb     {s}, {d}({s})",
            .{ insn, self.getRegName(rd), imm, self.getRegName(rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(rd), @as(u32, @bitCast(@as(i32, m8))), imm, @as(u32, @bitCast(self.getReg(rs1))) },
        );
        self.setReg(rd, m8);
        self.pc +%= 4;
    }

    fn execLh(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const m16 = try self.mem.get16(addr);
        try self.traceInsnComment(
            "{x:0>8} lh     {s}, {d}({s})",
            .{ insn, self.getRegName(rd), imm, self.getRegName(rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(rd), @as(u32, @bitCast(@as(i32, m16))), imm, @as(u32, @bitCast(self.getReg(rs1))) },
        );
        self.setReg(rd, m16);
        self.pc +%= 4;
    }

    fn execLw(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const m32 = try self.mem.get32(addr);
        try self.traceInsnComment(
            "{x:0>8} lw     {s}, {d}({s})",
            .{ insn, self.getRegName(rd), imm, self.getRegName(rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(rd), @as(u32, @bitCast(m32)), imm, @as(u32, @bitCast(self.getReg(rs1))) },
        );
        self.setReg(rd, m32);
        self.pc +%= 4;
    }

    fn execLbu(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const m = @as(i32, @as(u8, @bitCast(try self.mem.get8(addr))));
        try self.traceInsnComment(
            "{x:0>8} lbu    {s}, {d}({s})",
            .{ insn, self.getRegName(rd), imm, self.getRegName(rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(rd), @as(u32, @bitCast(m)), imm, @as(u32, @bitCast(self.getReg(rs1))) },
        );
        self.setReg(rd, m);
        self.pc +%= 4;
    }

    fn execLhu(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const m = @as(i32, @as(u16, @bitCast(try self.mem.get16(addr))));
        try self.traceInsnComment(
            "{x:0>8} lhu    {s}, {d}({s})",
            .{ insn, self.getRegName(rd), imm, self.getRegName(rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(rd), @as(u32, @bitCast(m)), imm, @as(u32, @bitCast(self.getReg(rs1))) },
        );
        self.setReg(rd, m);
        self.pc +%= 4;
    }

    fn execSb(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmS(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const src = @as(u8, @truncate(@as(u32, @bitCast(self.getReg(rs2)))));
        try self.traceInsnComment(
            "{x:0>8} sb     {s}, {d}({s})",
            .{ insn, self.getRegName(rs2), imm, self.getRegName(rs1) },
            "{d}(0x{x:0>8}) = 0x{x:0>8}",
            .{ imm, @as(u32, @bitCast(self.getReg(rs1))), @as(u32, src) },
        );
        try self.mem.set8(addr, src);
        self.pc +%= 4;
    }

    fn execSh(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmS(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const src = @as(u16, @truncate(@as(u32, @bitCast(self.getReg(rs2)))));
        try self.traceInsnComment(
            "{x:0>8} sh     {s}, {d}({s})",
            .{ insn, self.getRegName(rs2), imm, self.getRegName(rs1) },
            "{d}(0x{x:0>8}) = 0x{x:0>8}",
            .{ imm, @as(u32, @bitCast(self.getReg(rs1))), @as(u32, src) },
        );
        try self.mem.set16(addr, src);
        self.pc +%= 4;
    }

    fn execSw(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmS(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const addr = @as(u32, @bitCast(self.getReg(rs1) +% imm));
        const src: u32 = @bitCast(self.getReg(rs2));
        try self.traceInsnComment(
            "{x:0>8} sw     {s}, {d}({s})",
            .{ insn, self.getRegName(rs2), imm, self.getRegName(rs1) },
            "{d}(0x{x:0>8}) = 0x{x:0>8}",
            .{ imm, @as(u32, @bitCast(self.getReg(rs1))), src },
        );
        try self.mem.set32(addr, src);
        self.pc +%= 4;
    }

    fn execAddi(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const sum = self.getReg(rs1) +% imm;
        try self.traceInsnComment(
            "{X:0>8} addi   {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} + 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(sum)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, sum);
        self.pc +%= 4;
    }

    fn execSlti(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const cond: i32 = if (self.getReg(rs1) < imm) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} slti   {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), imm },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(rd), @as(u32, @bitCast(cond)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, cond);
        self.pc +%= 4;
    }

    fn execSltiu(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const cond: i32 = if (@as(u32, @bitCast(self.getReg(rs1))) < @as(u32, @bitCast(imm))) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} sltiu  {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), imm },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(rd), @as(u32, @bitCast(cond)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, cond);
        self.pc +%= 4;
    }

    fn execXori(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) ^ imm;
        try self.traceInsnComment(
            "{X:0>8} xori   {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} ^ 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execOri(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) | imm;
        try self.traceInsnComment(
            "{X:0>8} ori    {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} | 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execAndi(self: *RV32, insn: u32) !void {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) & imm;
        try self.traceInsnComment(
            "{X:0>8} andi   {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} & 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(imm)) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSlli(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const shamt: u5 = @truncate(self.getInsnRs2(insn));
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) << shamt;
        try self.traceInsnComment(
            "{X:0>8} slli   {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), shamt },
            "{s} = 0x{X:0>8} = 0x{X:0>8} << {d}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), shamt },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSrli(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const shamt: u5 = @truncate(self.getInsnRs2(insn));
        const rd = self.getInsnRd(insn);
        const result: i32 = @bitCast(@as(u32, @bitCast(self.getReg(rs1))) >> shamt);
        try self.traceInsnComment(
            "{X:0>8} srli   {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), shamt },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), shamt },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSrai(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const shamt: u5 = @truncate(self.getInsnRs2(insn));
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) >> shamt;
        try self.traceInsnComment(
            "{X:0>8} srai   {s}, {s}, {d}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), shamt },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), shamt },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execAdd(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) +% self.getReg(rs2);
        try self.traceInsnComment(
            "{X:0>8} add    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} + 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSub(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) -% self.getReg(rs2);
        try self.traceInsnComment(
            "{X:0>8} sub    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} - 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSll(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const shamt: u5 = @truncate(@as(u32, @bitCast(self.getReg(rs2))) & 0x1f);
        const result = self.getReg(rs1) << shamt;
        try self.traceInsnComment(
            "{X:0>8} sll    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} << {d}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), shamt },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSlt(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const result: i32 = if (self.getReg(rs1) < self.getReg(rs2)) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} slt    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSltu(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const result: i32 = if (@as(u32, @bitCast(self.getReg(rs1))) < @as(u32, @bitCast(self.getReg(rs2)))) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} sltu   {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execXor(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) ^ self.getReg(rs2);
        try self.traceInsnComment(
            "{X:0>8} xor    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} ^ 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSrl(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const shamt: u5 = @truncate(@as(u32, @bitCast(self.getReg(rs2))) & 0x1f);
        const result: i32 = @bitCast(@as(u32, @bitCast(self.getReg(rs1))) >> shamt);
        try self.traceInsnComment(
            "{X:0>8} srl    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), shamt },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execSra(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const shamt: u5 = @truncate(@as(u32, @bitCast(self.getReg(rs2))) & 0x1f);
        const result = self.getReg(rs1) >> shamt;
        try self.traceInsnComment(
            "{X:0>8} sra    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), shamt },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execOr(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) | self.getReg(rs2);
        try self.traceInsnComment(
            "{X:0>8} or     {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} | 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    fn execAnd(self: *RV32, insn: u32) !void {
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const rd = self.getInsnRd(insn);
        const result = self.getReg(rs1) & self.getReg(rs2);
        try self.traceInsnComment(
            "{X:0>8} and    {s}, {s}, {s}",
            .{ insn, self.getRegName(rd), self.getRegName(rs1), self.getRegName(rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} & 0x{X:0>8}",
            .{ self.getRegName(rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(rs1))), @as(u32, @bitCast(self.getReg(rs2))) },
        );
        self.setReg(rd, result);
        self.pc +%= 4;
    }

    pub fn getInsnImmI(_: *RV32, insn: u32) i32 {
        return @bitCast(@as(i32, @bitCast(insn)) >> 20);
    }

    pub fn getInsnImmS(_: *RV32, insn: u32) i32 {
        return (((@as(i32, @bitCast(insn)) >> 20) & @as(i32, @bitCast(@as(u32, 0xffffffe0)))) | @as(i32, @intCast((insn >> 7) & 0x1f)));
    }

    pub fn getInsnImmB(_: *RV32, insn: u32) i32 {
        return @bitCast(((insn & 0x00000f00) >> 7) |
            ((insn & 0x00000080) << 4) |
            ((insn & 0x7e000000) >> 20) |
            ((insn & 0x80000000) >> 19) |
            (if ((insn & 0x80000000) != 0) @as(u32, 0xfffff000) else 0));
    }

    pub fn getInsnImmU(_: *RV32, insn: u32) i32 {
        return @bitCast(insn & 0xfffff000);
    }

    pub fn getInsnImmJ(_: *RV32, insn: u32) i32 {
        return @bitCast(((insn & 0x7fe00000) >> 20) |
            ((insn & 0x00100000) >> 9) |
            (insn & 0x000ff000) |
            ((insn & 0x80000000) >> 11) |
            (if ((insn & 0x80000000) != 0) @as(u32, 0xfff00000) else 0));
    }

    pub fn getInsnRd(_: *RV32, insn: u32) u8 {
        return @truncate((insn & 0x00000f80) >> 7);
    }

    pub fn getInsnRs1(_: *RV32, insn: u32) u8 {
        return @truncate((insn & 0x000f8000) >> 15);
    }

    pub fn getInsnRs2(_: *RV32, insn: u32) u8 {
        return @truncate((insn & 0x01f00000) >> 20);
    }

    pub fn getInsnOpcode(_: *RV32, insn: u32) u8 {
        return @truncate(insn & 0x7f);
    }

    pub fn getInsnFunct3(_: *RV32, insn: u32) u8 {
        return @truncate((insn & 0x00007000) >> 12);
    }

    pub fn getInsnFunct7(_: *RV32, insn: u32) u8 {
        return @truncate((insn & 0xfe000000) >> 25);
    }
};
