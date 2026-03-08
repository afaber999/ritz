const std = @import("std");
const Memory = @import("memory.zig").Memory;
const Output = @import("output.zig").Output;

pub const RV32 = struct {
    reg: [32]i32 = [_]i32{0} ** 32,
    pc: u32 = 0,
    trace: i32 = 1,
    regNamesABI: i32 = 0,
    reservation_valid: bool = false,
    reservation_addr: u32 = 0,
    csr_mstatus: u32 = 0,
    csr_misa: u32 = (@as(u32, 1) << 30) | (@as(u32, 1) << 8) | (@as(u32, 1) << 12), // RV32 + I + M
    csr_mtvec: u32 = 0,
    csr_mcounteren: u32 = 0,
    csr_mscratch: u32 = 0,
    csr_mepc: u32 = 0,
    csr_mcause: u32 = 0,
    csr_scounteren: u32 = 0,
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
        self.reservation_valid = false;
        self.reservation_addr = 0;
        self.csr_mstatus = 0;
        self.csr_mtvec = 0;
        self.csr_mcounteren = 0;
        self.csr_mscratch = 0;
        self.csr_mepc = 0;
        self.csr_mcause = 0;
        self.csr_scounteren = 0;
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

    fn regU32(self: *RV32, r: u8) u32 {
        return @as(u32, @bitCast(self.getReg(r)));
    }

    fn advancePc(self: *RV32) void {
        self.pc +%= 4;
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
            0b0001111 => if (funct3 == 0b000) try self.execFence(insn) else return self.illegal(),
            0b0100011 => switch (funct3) {
                0b000 => try self.execSb(insn),
                0b001 => try self.execSh(insn),
                0b010 => try self.execSw(insn),
                else => return self.illegal(),
            },
            0b0101111 => if (funct3 == 0b010) try self.execAtomicW(insn) else return self.illegal(),
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
                    0b0000001 => try self.execMul(insn),
                    else => return self.illegal(),
                },
                0b001 => switch (funct7) {
                    0b0000000 => try self.execSll(insn),
                    0b0000001 => try self.execMulh(insn),
                    else => return self.illegal(),
                },
                0b010 => switch (funct7) {
                    0b0000000 => try self.execSlt(insn),
                    0b0000001 => try self.execMulhsu(insn),
                    else => return self.illegal(),
                },
                0b011 => switch (funct7) {
                    0b0000000 => try self.execSltu(insn),
                    0b0000001 => try self.execMulhu(insn),
                    else => return self.illegal(),
                },
                0b100 => switch (funct7) {
                    0b0000000 => try self.execXor(insn),
                    0b0000001 => try self.execDiv(insn),
                    else => return self.illegal(),
                },
                0b101 => switch (funct7) {
                    0b0000000 => try self.execSrl(insn),
                    0b0100000 => try self.execSra(insn),
                    0b0000001 => try self.execDivu(insn),
                    else => return self.illegal(),
                },
                0b110 => switch (funct7) {
                    0b0000000 => try self.execOr(insn),
                    0b0000001 => try self.execRem(insn),
                    else => return self.illegal(),
                },
                0b111 => switch (funct7) {
                    0b0000000 => try self.execAnd(insn),
                    0b0000001 => try self.execRemu(insn),
                    else => return self.illegal(),
                },
                else => return self.illegal(),
            },
            0b1110011 => switch (funct3) {
                0b001 => try self.execCsrrw(insn),
                0b010 => try self.execCsrrs(insn),
                0b011 => try self.execCsrrc(insn),
                0b101 => try self.execCsrrwi(insn),
                0b110 => try self.execCsrrsi(insn),
                0b111 => try self.execCsrrci(insn),
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
        self.advancePc();
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
        self.advancePc();
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
        const immop = self.getIImmCtx(insn);
        const target = (self.getReg(immop.rs1) +% immop.imm) & ~@as(i32, 1);
        try self.traceInsnComment(
            "{x:0>8} jalr   {s}, {d}({s})",
            .{ insn, self.getRegName(immop.rd), immop.imm, self.getRegName(immop.rs1) },
            "{s} = 0x{x:0>8}, pc = 0x{x:0>8} = {d}(0x{x:0>8})&~1",
            .{ self.getRegName(immop.rd), self.pc +% 4, @as(u32, @bitCast(target)), immop.imm, self.regU32(immop.rs1) },
        );
        self.setReg(immop.rd, @bitCast(self.pc +% 4));
        self.setPc(target);
    }

    const BranchCtx = struct {
        rs1: u8,
        rs2: u8,
        taken_target: i32,
        fallthrough_target: i32,
    };

    fn getBranchCtx(self: *RV32, insn: u32) BranchCtx {
        const imm = self.getInsnImmB(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        const pc_i32 = @as(i32, @bitCast(self.pc));
        return .{
            .rs1 = rs1,
            .rs2 = rs2,
            .taken_target = pc_i32 +% imm,
            .fallthrough_target = pc_i32 +% 4,
        };
    }

    const ILoadCtx = struct {
        imm: i32,
        rs1: u8,
        rd: u8,
        addr: u32,
    };

    fn getILoadCtx(self: *RV32, insn: u32) ILoadCtx {
        const imm = self.getInsnImmI(insn);
        const rs1 = self.getInsnRs1(insn);
        const rd = self.getInsnRd(insn);
        return .{
            .imm = imm,
            .rs1 = rs1,
            .rd = rd,
            .addr = @as(u32, @bitCast(self.getReg(rs1) +% imm)),
        };
    }

    const IImmCtx = struct {
        imm: i32,
        rs1: u8,
        rd: u8,
    };

    fn getIImmCtx(self: *RV32, insn: u32) IImmCtx {
        return .{
            .imm = self.getInsnImmI(insn),
            .rs1 = self.getInsnRs1(insn),
            .rd = self.getInsnRd(insn),
        };
    }

    const IShiftCtx = struct {
        rs1: u8,
        rd: u8,
        shamt: u5,
    };

    fn getIShiftCtx(self: *RV32, insn: u32) IShiftCtx {
        return .{
            .rs1 = self.getInsnRs1(insn),
            .rd = self.getInsnRd(insn),
            .shamt = @truncate(self.getInsnRs2(insn)),
        };
    }

    const SStoreCtx = struct {
        imm: i32,
        rs1: u8,
        rs2: u8,
        addr: u32,
    };

    fn getSStoreCtx(self: *RV32, insn: u32) SStoreCtx {
        const imm = self.getInsnImmS(insn);
        const rs1 = self.getInsnRs1(insn);
        const rs2 = self.getInsnRs2(insn);
        return .{
            .imm = imm,
            .rs1 = rs1,
            .rs2 = rs2,
            .addr = @as(u32, @bitCast(self.getReg(rs1) +% imm)),
        };
    }

    const RTypeCtx = struct {
        rs1: u8,
        rs2: u8,
        rd: u8,
    };

    fn getRTypeCtx(self: *RV32, insn: u32) RTypeCtx {
        return .{
            .rs1 = self.getInsnRs1(insn),
            .rs2 = self.getInsnRs2(insn),
            .rd = self.getInsnRd(insn),
        };
    }

    const RShiftCtx = struct {
        rs1: u8,
        rd: u8,
        shamt: u5,
    };

    fn getRShiftCtx(self: *RV32, insn: u32) RShiftCtx {
        const r = self.getRTypeCtx(insn);
        return .{
            .rs1 = r.rs1,
            .rd = r.rd,
            .shamt = @truncate(self.regU32(r.rs2) & 0x1f),
        };
    }

    fn execBeq(self: *RV32, insn: u32) !void {
        const branch = self.getBranchCtx(insn);
        try self.traceInsnComment(
            "{x:0>8} beq    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(branch.rs1), self.getRegName(branch.rs2), @as(u32, @bitCast(branch.taken_target)) },
            "pc = (0x{x} == 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(branch.rs1))), @as(u32, @bitCast(self.getReg(branch.rs2))), @as(u32, @bitCast(branch.taken_target)), @as(u32, @bitCast(branch.fallthrough_target)) },
        );
        if (self.getReg(branch.rs1) == self.getReg(branch.rs2)) self.setPc(branch.taken_target) else self.setPc(branch.fallthrough_target);
    }

    fn execBne(self: *RV32, insn: u32) !void {
        const branch = self.getBranchCtx(insn);
        try self.traceInsnComment(
            "{x:0>8} bne    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(branch.rs1), self.getRegName(branch.rs2), @as(u32, @bitCast(branch.taken_target)) },
            "pc = (0x{x} != 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(branch.rs1))), @as(u32, @bitCast(self.getReg(branch.rs2))), @as(u32, @bitCast(branch.taken_target)), @as(u32, @bitCast(branch.fallthrough_target)) },
        );
        if (self.getReg(branch.rs1) != self.getReg(branch.rs2)) self.setPc(branch.taken_target) else self.setPc(branch.fallthrough_target);
    }

    fn execBlt(self: *RV32, insn: u32) !void {
        const branch = self.getBranchCtx(insn);
        try self.traceInsnComment(
            "{x:0>8} blt    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(branch.rs1), self.getRegName(branch.rs2), @as(u32, @bitCast(branch.taken_target)) },
            "pc = (0x{x} < 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(branch.rs1))), @as(u32, @bitCast(self.getReg(branch.rs2))), @as(u32, @bitCast(branch.taken_target)), @as(u32, @bitCast(branch.fallthrough_target)) },
        );
        if (self.getReg(branch.rs1) < self.getReg(branch.rs2)) self.setPc(branch.taken_target) else self.setPc(branch.fallthrough_target);
    }

    fn execBge(self: *RV32, insn: u32) !void {
        const branch = self.getBranchCtx(insn);
        try self.traceInsnComment(
            "{x:0>8} bge    {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(branch.rs1), self.getRegName(branch.rs2), @as(u32, @bitCast(branch.taken_target)) },
            "pc = (0x{x} >= 0x{x}) ? 0x{x} : 0x{x}",
            .{ @as(u32, @bitCast(self.getReg(branch.rs1))), @as(u32, @bitCast(self.getReg(branch.rs2))), @as(u32, @bitCast(branch.taken_target)), @as(u32, @bitCast(branch.fallthrough_target)) },
        );
        if (self.getReg(branch.rs1) >= self.getReg(branch.rs2)) self.setPc(branch.taken_target) else self.setPc(branch.fallthrough_target);
    }

    fn execBltu(self: *RV32, insn: u32) !void {
        const branch = self.getBranchCtx(insn);
        try self.traceInsnComment(
            "{x:0>8} bltu   {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(branch.rs1), self.getRegName(branch.rs2), @as(u32, @bitCast(branch.taken_target)) },
            "pc = (0x{x} < 0x{x}) ? 0x{x} : 0x{x}",
            .{ self.regU32(branch.rs1), self.regU32(branch.rs2), @as(u32, @bitCast(branch.taken_target)), @as(u32, @bitCast(branch.fallthrough_target)) },
        );
        if (self.regU32(branch.rs1) < self.regU32(branch.rs2)) self.setPc(branch.taken_target) else self.setPc(branch.fallthrough_target);
    }

    fn execBgeu(self: *RV32, insn: u32) !void {
        const branch = self.getBranchCtx(insn);
        try self.traceInsnComment(
            "{x:0>8} bgeu   {s}, {s}, 0x{x}",
            .{ insn, self.getRegName(branch.rs1), self.getRegName(branch.rs2), @as(u32, @bitCast(branch.taken_target)) },
            "pc = (0x{x} >= 0x{x}) ? 0x{x} : 0x{x}",
            .{ self.regU32(branch.rs1), self.regU32(branch.rs2), @as(u32, @bitCast(branch.taken_target)), @as(u32, @bitCast(branch.fallthrough_target)) },
        );
        if (self.regU32(branch.rs1) >= self.regU32(branch.rs2)) self.setPc(branch.taken_target) else self.setPc(branch.fallthrough_target);
    }

    fn execLb(self: *RV32, insn: u32) !void {
        const load = self.getILoadCtx(insn);
        const m8 = try self.mem.get8(load.addr);
        try self.traceInsnComment(
            "{x:0>8} lb     {s}, {d}({s})",
            .{ insn, self.getRegName(load.rd), load.imm, self.getRegName(load.rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(load.rd), @as(u32, @bitCast(@as(i32, m8))), load.imm, @as(u32, @bitCast(self.getReg(load.rs1))) },
        );
        self.setReg(load.rd, m8);
        self.advancePc();
    }

    fn execLh(self: *RV32, insn: u32) !void {
        const load = self.getILoadCtx(insn);
        const m16 = try self.mem.get16(load.addr);
        try self.traceInsnComment(
            "{x:0>8} lh     {s}, {d}({s})",
            .{ insn, self.getRegName(load.rd), load.imm, self.getRegName(load.rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(load.rd), @as(u32, @bitCast(@as(i32, m16))), load.imm, @as(u32, @bitCast(self.getReg(load.rs1))) },
        );
        self.setReg(load.rd, m16);
        self.advancePc();
    }

    fn execLw(self: *RV32, insn: u32) !void {
        const load = self.getILoadCtx(insn);
        const m32 = try self.mem.get32(load.addr);
        try self.traceInsnComment(
            "{x:0>8} lw     {s}, {d}({s})",
            .{ insn, self.getRegName(load.rd), load.imm, self.getRegName(load.rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(load.rd), @as(u32, @bitCast(m32)), load.imm, @as(u32, @bitCast(self.getReg(load.rs1))) },
        );
        self.setReg(load.rd, m32);
        self.advancePc();
    }

    fn execLbu(self: *RV32, insn: u32) !void {
        const load = self.getILoadCtx(insn);
        const m = @as(i32, @as(u8, @bitCast(try self.mem.get8(load.addr))));
        try self.traceInsnComment(
            "{x:0>8} lbu    {s}, {d}({s})",
            .{ insn, self.getRegName(load.rd), load.imm, self.getRegName(load.rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(load.rd), @as(u32, @bitCast(m)), load.imm, @as(u32, @bitCast(self.getReg(load.rs1))) },
        );
        self.setReg(load.rd, m);
        self.advancePc();
    }

    fn execLhu(self: *RV32, insn: u32) !void {
        const load = self.getILoadCtx(insn);
        const m = @as(i32, @as(u16, @bitCast(try self.mem.get16(load.addr))));
        try self.traceInsnComment(
            "{x:0>8} lhu    {s}, {d}({s})",
            .{ insn, self.getRegName(load.rd), load.imm, self.getRegName(load.rs1) },
            "{s} = 0x{x:0>8} = {d}(0x{x:0>8})",
            .{ self.getRegName(load.rd), @as(u32, @bitCast(m)), load.imm, @as(u32, @bitCast(self.getReg(load.rs1))) },
        );
        self.setReg(load.rd, m);
        self.advancePc();
    }

    fn execSb(self: *RV32, insn: u32) !void {
        const store = self.getSStoreCtx(insn);
        const src = @as(u8, @truncate(@as(u32, @bitCast(self.getReg(store.rs2)))));
        try self.traceInsnComment(
            "{x:0>8} sb     {s}, {d}({s})",
            .{ insn, self.getRegName(store.rs2), store.imm, self.getRegName(store.rs1) },
            "{d}(0x{x:0>8}) = 0x{x:0>8}",
            .{ store.imm, @as(u32, @bitCast(self.getReg(store.rs1))), @as(u32, src) },
        );
        try self.mem.set8(store.addr, src);
        self.reservation_valid = false;
        self.advancePc();
    }

    fn execSh(self: *RV32, insn: u32) !void {
        const store = self.getSStoreCtx(insn);
        const src = @as(u16, @truncate(@as(u32, @bitCast(self.getReg(store.rs2)))));
        try self.traceInsnComment(
            "{x:0>8} sh     {s}, {d}({s})",
            .{ insn, self.getRegName(store.rs2), store.imm, self.getRegName(store.rs1) },
            "{d}(0x{x:0>8}) = 0x{x:0>8}",
            .{ store.imm, @as(u32, @bitCast(self.getReg(store.rs1))), @as(u32, src) },
        );
        try self.mem.set16(store.addr, src);
        self.reservation_valid = false;
        self.advancePc();
    }

    fn execSw(self: *RV32, insn: u32) !void {
        const store = self.getSStoreCtx(insn);
        const src: u32 = @bitCast(self.getReg(store.rs2));
        try self.traceInsnComment(
            "{x:0>8} sw     {s}, {d}({s})",
            .{ insn, self.getRegName(store.rs2), store.imm, self.getRegName(store.rs1) },
            "{d}(0x{x:0>8}) = 0x{x:0>8}",
            .{ store.imm, @as(u32, @bitCast(self.getReg(store.rs1))), src },
        );
        try self.mem.set32(store.addr, src);
        self.reservation_valid = false;
        self.advancePc();
    }

    fn execFence(self: *RV32, insn: u32) !void {
        try self.traceInsn("{X:0>8} fence", .{insn});
        self.advancePc();
    }

    fn getInsnAmoFunct5(_: *RV32, insn: u32) u5 {
        return @truncate((insn >> 27) & 0x1f);
    }

    fn execAtomicW(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const addr = self.regU32(r.rs1);
        const funct5 = self.getInsnAmoFunct5(insn);

        switch (funct5) {
            0b00010 => try self.execLrW(insn, r, addr),
            0b00011 => try self.execScW(insn, r, addr),
            0b00000 => try self.execAmoBinaryW(insn, r, addr, "amoadd.w", .add),
            0b00100 => try self.execAmoBinaryW(insn, r, addr, "amoxor.w", .xor),
            0b01100 => try self.execAmoBinaryW(insn, r, addr, "amoand.w", .and_op),
            0b01000 => try self.execAmoBinaryW(insn, r, addr, "amoor.w", .or_op),
            0b00001 => try self.execAmoBinaryW(insn, r, addr, "amoswap.w", .swap),
            0b10000 => try self.execAmoBinaryW(insn, r, addr, "amomin.w", .min),
            0b10100 => try self.execAmoBinaryW(insn, r, addr, "amomax.w", .max),
            0b11000 => try self.execAmoBinaryW(insn, r, addr, "amominu.w", .minu),
            0b11100 => try self.execAmoBinaryW(insn, r, addr, "amomaxu.w", .maxu),
            else => _ = self.illegal(),
        }
    }

    const AmoOp = enum {
        add,
        xor,
        and_op,
        or_op,
        swap,
        min,
        max,
        minu,
        maxu,
    };

    fn execAmoBinaryW(self: *RV32, insn: u32, r: RTypeCtx, addr: u32, mnemonic: []const u8, op: AmoOp) !void {
        const old = try self.mem.get32(addr);
        const src = self.getReg(r.rs2);

        const result: i32 = switch (op) {
            .add => old +% src,
            .xor => old ^ src,
            .and_op => old & src,
            .or_op => old | src,
            .swap => src,
            .min => if (old < src) old else src,
            .max => if (old > src) old else src,
            .minu => blk: {
                const old_u: u32 = @bitCast(old);
                const src_u: u32 = @bitCast(src);
                break :blk if (old_u < src_u) old else src;
            },
            .maxu => blk: {
                const old_u: u32 = @bitCast(old);
                const src_u: u32 = @bitCast(src);
                break :blk if (old_u > src_u) old else src;
            },
        };

        try self.traceInsnComment(
            "{X:0>8} {s: <8}{s}, ({s})",
            .{ insn, mnemonic, self.getRegName(r.rd), self.getRegName(r.rs1) },
            "{s}=0x{X:0>8}, mem[0x{X:0>8}]=0x{X:0>8}",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(old)), addr, @as(u32, @bitCast(result)) },
        );

        try self.mem.set32(addr, @bitCast(result));
        self.setReg(r.rd, old);
        self.reservation_valid = false;
        self.advancePc();
    }

    fn execLrW(self: *RV32, insn: u32, r: RTypeCtx, addr: u32) !void {
        if (r.rs2 != 0) {
            _ = self.illegal();
            return;
        }
        const old = try self.mem.get32(addr);
        try self.traceInsnComment(
            "{X:0>8} lr.w   {s}, ({s})",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1) },
            "{s}=0x{X:0>8}, reserve[0x{X:0>8}]",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(old)), addr },
        );
        self.setReg(r.rd, old);
        self.reservation_valid = true;
        self.reservation_addr = addr;
        self.advancePc();
    }

    fn execScW(self: *RV32, insn: u32, r: RTypeCtx, addr: u32) !void {
        const can_store = self.reservation_valid and self.reservation_addr == addr;
        if (can_store) {
            try self.mem.set32(addr, @bitCast(self.getReg(r.rs2)));
            self.setReg(r.rd, 0);
        } else {
            self.setReg(r.rd, 1);
        }
        try self.traceInsnComment(
            "{X:0>8} sc.w   {s}, {s}, ({s})",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs2), self.getRegName(r.rs1) },
            "{s}=0x{X:0>8}",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(self.getReg(r.rd))) },
        );
        self.reservation_valid = false;
        self.advancePc();
    }

    fn execAddi(self: *RV32, insn: u32) !void {
        const immop = self.getIImmCtx(insn);
        const sum = self.getReg(immop.rs1) +% immop.imm;
        try self.traceInsnComment(
            "{X:0>8} addi   {s}, {s}, {d}",
            .{ insn, self.getRegName(immop.rd), self.getRegName(immop.rs1), immop.imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} + 0x{X:0>8}",
            .{ self.getRegName(immop.rd), @as(u32, @bitCast(sum)), @as(u32, @bitCast(self.getReg(immop.rs1))), @as(u32, @bitCast(immop.imm)) },
        );
        self.setReg(immop.rd, sum);
        self.advancePc();
    }

    fn execSlti(self: *RV32, insn: u32) !void {
        const immop = self.getIImmCtx(insn);
        const cond: i32 = if (self.getReg(immop.rs1) < immop.imm) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} slti   {s}, {s}, {d}",
            .{ insn, self.getRegName(immop.rd), self.getRegName(immop.rs1), immop.imm },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(immop.rd), @as(u32, @bitCast(cond)), @as(u32, @bitCast(self.getReg(immop.rs1))), @as(u32, @bitCast(immop.imm)) },
        );
        self.setReg(immop.rd, cond);
        self.advancePc();
    }

    fn execSltiu(self: *RV32, insn: u32) !void {
        const immop = self.getIImmCtx(insn);
        const cond: i32 = if (@as(u32, @bitCast(self.getReg(immop.rs1))) < @as(u32, @bitCast(immop.imm))) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} sltiu  {s}, {s}, {d}",
            .{ insn, self.getRegName(immop.rd), self.getRegName(immop.rs1), immop.imm },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(immop.rd), @as(u32, @bitCast(cond)), @as(u32, @bitCast(self.getReg(immop.rs1))), @as(u32, @bitCast(immop.imm)) },
        );
        self.setReg(immop.rd, cond);
        self.advancePc();
    }

    fn execXori(self: *RV32, insn: u32) !void {
        const immop = self.getIImmCtx(insn);
        const result = self.getReg(immop.rs1) ^ immop.imm;
        try self.traceInsnComment(
            "{X:0>8} xori   {s}, {s}, {d}",
            .{ insn, self.getRegName(immop.rd), self.getRegName(immop.rs1), immop.imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} ^ 0x{X:0>8}",
            .{ self.getRegName(immop.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(immop.rs1))), @as(u32, @bitCast(immop.imm)) },
        );
        self.setReg(immop.rd, result);
        self.advancePc();
    }

    fn execOri(self: *RV32, insn: u32) !void {
        const immop = self.getIImmCtx(insn);
        const result = self.getReg(immop.rs1) | immop.imm;
        try self.traceInsnComment(
            "{X:0>8} ori    {s}, {s}, {d}",
            .{ insn, self.getRegName(immop.rd), self.getRegName(immop.rs1), immop.imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} | 0x{X:0>8}",
            .{ self.getRegName(immop.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(immop.rs1))), @as(u32, @bitCast(immop.imm)) },
        );
        self.setReg(immop.rd, result);
        self.advancePc();
    }

    fn execAndi(self: *RV32, insn: u32) !void {
        const immop = self.getIImmCtx(insn);
        const result = self.getReg(immop.rs1) & immop.imm;
        try self.traceInsnComment(
            "{X:0>8} andi   {s}, {s}, {d}",
            .{ insn, self.getRegName(immop.rd), self.getRegName(immop.rs1), immop.imm },
            "{s} = 0x{X:0>8} = 0x{X:0>8} & 0x{X:0>8}",
            .{ self.getRegName(immop.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(immop.rs1))), @as(u32, @bitCast(immop.imm)) },
        );
        self.setReg(immop.rd, result);
        self.advancePc();
    }

    fn execSlli(self: *RV32, insn: u32) !void {
        const shift = self.getIShiftCtx(insn);
        const result = self.getReg(shift.rs1) << shift.shamt;
        try self.traceInsnComment(
            "{X:0>8} slli   {s}, {s}, {d}",
            .{ insn, self.getRegName(shift.rd), self.getRegName(shift.rs1), shift.shamt },
            "{s} = 0x{X:0>8} = 0x{X:0>8} << {d}",
            .{ self.getRegName(shift.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(shift.rs1))), shift.shamt },
        );
        self.setReg(shift.rd, result);
        self.advancePc();
    }

    fn execSrli(self: *RV32, insn: u32) !void {
        const shift = self.getIShiftCtx(insn);
        const result: i32 = @bitCast(@as(u32, @bitCast(self.getReg(shift.rs1))) >> shift.shamt);
        try self.traceInsnComment(
            "{X:0>8} srli   {s}, {s}, {d}",
            .{ insn, self.getRegName(shift.rd), self.getRegName(shift.rs1), shift.shamt },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(shift.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(shift.rs1))), shift.shamt },
        );
        self.setReg(shift.rd, result);
        self.advancePc();
    }

    fn execSrai(self: *RV32, insn: u32) !void {
        const shift = self.getIShiftCtx(insn);
        const result = self.getReg(shift.rs1) >> shift.shamt;
        try self.traceInsnComment(
            "{X:0>8} srai   {s}, {s}, {d}",
            .{ insn, self.getRegName(shift.rd), self.getRegName(shift.rs1), shift.shamt },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(shift.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(shift.rs1))), shift.shamt },
        );
        self.setReg(shift.rd, result);
        self.advancePc();
    }

    fn execAdd(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result = self.getReg(r.rs1) +% self.getReg(r.rs2);
        try self.traceInsnComment(
            "{X:0>8} add    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} + 0x{X:0>8}",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(r.rs1))), @as(u32, @bitCast(self.getReg(r.rs2))) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execSub(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result = self.getReg(r.rs1) -% self.getReg(r.rs2);
        try self.traceInsnComment(
            "{X:0>8} sub    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} - 0x{X:0>8}",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(r.rs1))), @as(u32, @bitCast(self.getReg(r.rs2))) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execMul(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result: i32 = @bitCast(self.regU32(r.rs1) *% self.regU32(r.rs2));
        try self.traceInsnComment(
            "{X:0>8} mul    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = low32(0x{X:0>8} * 0x{X:0>8})",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execMulh(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const prod: i64 = @as(i64, self.getReg(r.rs1)) * @as(i64, self.getReg(r.rs2));
        const hi_u32: u32 = @truncate(@as(u64, @bitCast(prod)) >> 32);
        const result: i32 = @bitCast(hi_u32);
        try self.traceInsnComment(
            "{X:0>8} mulh   {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = high32(signed(0x{X:0>8}) * signed(0x{X:0>8}))",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execMulhsu(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const prod: i64 = @as(i64, self.getReg(r.rs1)) * @as(i64, self.regU32(r.rs2));
        const hi_u32: u32 = @truncate(@as(u64, @bitCast(prod)) >> 32);
        const result: i32 = @bitCast(hi_u32);
        try self.traceInsnComment(
            "{X:0>8} mulhsu {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = high32(signed(0x{X:0>8}) * unsigned(0x{X:0>8}))",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execMulhu(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const prod: u64 = @as(u64, self.regU32(r.rs1)) * @as(u64, self.regU32(r.rs2));
        const hi_u32: u32 = @truncate(prod >> 32);
        const result: i32 = @bitCast(hi_u32);
        try self.traceInsnComment(
            "{X:0>8} mulhu  {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = high32(unsigned(0x{X:0>8}) * unsigned(0x{X:0>8}))",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execDiv(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const dividend = self.getReg(r.rs1);
        const divisor = self.getReg(r.rs2);

        const result: i32 = if (divisor == 0)
            -1
        else if (dividend == std.math.minInt(i32) and divisor == -1)
            std.math.minInt(i32)
        else
            @divTrunc(dividend, divisor);

        try self.traceInsnComment(
            "{X:0>8} div    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = signed(0x{X:0>8}) / signed(0x{X:0>8})",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execDivu(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const dividend = self.regU32(r.rs1);
        const divisor = self.regU32(r.rs2);

        const result_u32: u32 = if (divisor == 0) 0xffffffff else @divTrunc(dividend, divisor);
        const result: i32 = @bitCast(result_u32);

        try self.traceInsnComment(
            "{X:0>8} divu   {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = unsigned(0x{X:0>8}) / unsigned(0x{X:0>8})",
            .{ self.getRegName(r.rd), result_u32, self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execRem(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const dividend = self.getReg(r.rs1);
        const divisor = self.getReg(r.rs2);

        const result: i32 = if (divisor == 0)
            dividend
        else if (dividend == std.math.minInt(i32) and divisor == -1)
            0
        else
            @rem(dividend, divisor);

        try self.traceInsnComment(
            "{X:0>8} rem    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = signed(0x{X:0>8}) % signed(0x{X:0>8})",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execRemu(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const dividend = self.regU32(r.rs1);
        const divisor = self.regU32(r.rs2);

        const result_u32: u32 = if (divisor == 0) dividend else @rem(dividend, divisor);
        const result: i32 = @bitCast(result_u32);

        try self.traceInsnComment(
            "{X:0>8} remu   {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = unsigned(0x{X:0>8}) % unsigned(0x{X:0>8})",
            .{ self.getRegName(r.rd), result_u32, self.regU32(r.rs1), self.regU32(r.rs2) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execSll(self: *RV32, insn: u32) !void {
        const shift = self.getRShiftCtx(insn);
        const result = self.getReg(shift.rs1) << shift.shamt;
        try self.traceInsnComment(
            "{X:0>8} sll    {s}, {s}, {s}",
            .{ insn, self.getRegName(shift.rd), self.getRegName(shift.rs1), self.getRegName(self.getInsnRs2(insn)) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} << {d}",
            .{ self.getRegName(shift.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(shift.rs1))), shift.shamt },
        );
        self.setReg(shift.rd, result);
        self.advancePc();
    }

    fn execSlt(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result: i32 = if (self.getReg(r.rs1) < self.getReg(r.rs2)) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} slt    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(r.rs1))), @as(u32, @bitCast(self.getReg(r.rs2))) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execSltu(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result: i32 = if (@as(u32, @bitCast(self.getReg(r.rs1))) < @as(u32, @bitCast(self.getReg(r.rs2)))) 1 else 0;
        try self.traceInsnComment(
            "{X:0>8} sltu   {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = (0x{X:0>8} < 0x{X:0>8}) ? 1 : 0",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(r.rs1))), @as(u32, @bitCast(self.getReg(r.rs2))) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execXor(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result = self.getReg(r.rs1) ^ self.getReg(r.rs2);
        try self.traceInsnComment(
            "{X:0>8} xor    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} ^ 0x{X:0>8}",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(r.rs1))), @as(u32, @bitCast(self.getReg(r.rs2))) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execSrl(self: *RV32, insn: u32) !void {
        const shift = self.getRShiftCtx(insn);
        const result: i32 = @bitCast(@as(u32, @bitCast(self.getReg(shift.rs1))) >> shift.shamt);
        try self.traceInsnComment(
            "{X:0>8} srl    {s}, {s}, {s}",
            .{ insn, self.getRegName(shift.rd), self.getRegName(shift.rs1), self.getRegName(self.getInsnRs2(insn)) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(shift.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(shift.rs1))), shift.shamt },
        );
        self.setReg(shift.rd, result);
        self.advancePc();
    }

    fn execSra(self: *RV32, insn: u32) !void {
        const shift = self.getRShiftCtx(insn);
        const result = self.getReg(shift.rs1) >> shift.shamt;
        try self.traceInsnComment(
            "{X:0>8} sra    {s}, {s}, {s}",
            .{ insn, self.getRegName(shift.rd), self.getRegName(shift.rs1), self.getRegName(self.getInsnRs2(insn)) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} >> {d}",
            .{ self.getRegName(shift.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(shift.rs1))), shift.shamt },
        );
        self.setReg(shift.rd, result);
        self.advancePc();
    }

    fn execOr(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result = self.getReg(r.rs1) | self.getReg(r.rs2);
        try self.traceInsnComment(
            "{X:0>8} or     {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} | 0x{X:0>8}",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(r.rs1))), @as(u32, @bitCast(self.getReg(r.rs2))) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execAnd(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const result = self.getReg(r.rs1) & self.getReg(r.rs2);
        try self.traceInsnComment(
            "{X:0>8} and    {s}, {s}, {s}",
            .{ insn, self.getRegName(r.rd), self.getRegName(r.rs1), self.getRegName(r.rs2) },
            "{s} = 0x{X:0>8} = 0x{X:0>8} & 0x{X:0>8}",
            .{ self.getRegName(r.rd), @as(u32, @bitCast(result)), @as(u32, @bitCast(self.getReg(r.rs1))), @as(u32, @bitCast(self.getReg(r.rs2))) },
        );
        self.setReg(r.rd, result);
        self.advancePc();
    }

    fn execCsrrw(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const csr = self.getInsnCsr(insn);
        const old = self.csrRead(csr) orelse {
            _ = self.illegal();
            return;
        };
        if (!self.csrWrite(csr, self.regU32(r.rs1))) {
            _ = self.illegal();
            return;
        }
        try self.traceInsnComment(
            "{X:0>8} csrrw  {s}, 0x{X:0>3}, {s}",
            .{ insn, self.getRegName(r.rd), csr, self.getRegName(r.rs1) },
            "{s} = 0x{X:0>8}, csr[0x{X:0>3}] = 0x{X:0>8}",
            .{ self.getRegName(r.rd), old, csr, self.regU32(r.rs1) },
        );
        self.setReg(r.rd, @bitCast(old));
        self.advancePc();
    }

    fn execCsrrs(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const csr = self.getInsnCsr(insn);
        const old = self.csrRead(csr) orelse {
            _ = self.illegal();
            return;
        };
        if (r.rs1 != 0) {
            if (!self.csrWrite(csr, old | self.regU32(r.rs1))) {
                _ = self.illegal();
                return;
            }
        }
        try self.traceInsnComment(
            "{X:0>8} csrrs  {s}, 0x{X:0>3}, {s}",
            .{ insn, self.getRegName(r.rd), csr, self.getRegName(r.rs1) },
            "{s} = 0x{X:0>8}",
            .{ self.getRegName(r.rd), old },
        );
        self.setReg(r.rd, @bitCast(old));
        self.advancePc();
    }

    fn execCsrrc(self: *RV32, insn: u32) !void {
        const r = self.getRTypeCtx(insn);
        const csr = self.getInsnCsr(insn);
        const old = self.csrRead(csr) orelse {
            _ = self.illegal();
            return;
        };
        if (r.rs1 != 0) {
            if (!self.csrWrite(csr, old & ~self.regU32(r.rs1))) {
                _ = self.illegal();
                return;
            }
        }
        try self.traceInsnComment(
            "{X:0>8} csrrc  {s}, 0x{X:0>3}, {s}",
            .{ insn, self.getRegName(r.rd), csr, self.getRegName(r.rs1) },
            "{s} = 0x{X:0>8}",
            .{ self.getRegName(r.rd), old },
        );
        self.setReg(r.rd, @bitCast(old));
        self.advancePc();
    }

    fn execCsrrwi(self: *RV32, insn: u32) !void {
        const rd = self.getInsnRd(insn);
        const zimm = self.getInsnRs1(insn);
        const csr = self.getInsnCsr(insn);
        const old = self.csrRead(csr) orelse {
            _ = self.illegal();
            return;
        };
        if (!self.csrWrite(csr, zimm)) {
            _ = self.illegal();
            return;
        }
        try self.traceInsnComment(
            "{X:0>8} csrrwi {s}, 0x{X:0>3}, {d}",
            .{ insn, self.getRegName(rd), csr, zimm },
            "{s} = 0x{X:0>8}, csr[0x{X:0>3}] = 0x{X:0>8}",
            .{ self.getRegName(rd), old, csr, zimm },
        );
        self.setReg(rd, @bitCast(old));
        self.advancePc();
    }

    fn execCsrrsi(self: *RV32, insn: u32) !void {
        const rd = self.getInsnRd(insn);
        const zimm = self.getInsnRs1(insn);
        const csr = self.getInsnCsr(insn);
        const old = self.csrRead(csr) orelse {
            _ = self.illegal();
            return;
        };
        if (zimm != 0) {
            if (!self.csrWrite(csr, old | zimm)) {
                _ = self.illegal();
                return;
            }
        }
        try self.traceInsnComment(
            "{X:0>8} csrrsi {s}, 0x{X:0>3}, {d}",
            .{ insn, self.getRegName(rd), csr, zimm },
            "{s} = 0x{X:0>8}",
            .{ self.getRegName(rd), old },
        );
        self.setReg(rd, @bitCast(old));
        self.advancePc();
    }

    fn execCsrrci(self: *RV32, insn: u32) !void {
        const rd = self.getInsnRd(insn);
        const zimm = self.getInsnRs1(insn);
        const csr = self.getInsnCsr(insn);
        const old = self.csrRead(csr) orelse {
            _ = self.illegal();
            return;
        };
        if (zimm != 0) {
            if (!self.csrWrite(csr, old & ~zimm)) {
                _ = self.illegal();
                return;
            }
        }
        try self.traceInsnComment(
            "{X:0>8} csrrci {s}, 0x{X:0>3}, {d}",
            .{ insn, self.getRegName(rd), csr, zimm },
            "{s} = 0x{X:0>8}",
            .{ self.getRegName(rd), old },
        );
        self.setReg(rd, @bitCast(old));
        self.advancePc();
    }

    fn csrRead(self: *RV32, csr: u12) ?u32 {
        return switch (csr) {
            0x300 => self.csr_mstatus,
            0x301 => self.csr_misa,
            0x305 => self.csr_mtvec,
            0x306 => self.csr_mcounteren,
            0x340 => self.csr_mscratch,
            0x341 => self.csr_mepc,
            0x342 => self.csr_mcause,
            0x106 => self.csr_scounteren,
            0xC00 => 0, // cycle
            0xF11 => 0, // mvendorid
            0xF12 => 0, // marchid
            0xF13 => 0, // mimpid
            0xF14 => 0, // mhartid
            else => null,
        };
    }

    fn csrWrite(self: *RV32, csr: u12, value: u32) bool {
        switch (csr) {
            0x300 => self.csr_mstatus = value,
            0x305 => self.csr_mtvec = value,
            0x306 => self.csr_mcounteren = value,
            0x340 => self.csr_mscratch = value,
            0x341 => self.csr_mepc = value,
            0x342 => self.csr_mcause = value,
            0x106 => self.csr_scounteren = value,
            0xC00, 0x301, 0xF11, 0xF12, 0xF13, 0xF14 => return false,
            else => return false,
        }
        return true;
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

    pub fn getInsnCsr(_: *RV32, insn: u32) u12 {
        return @truncate((insn >> 20) & 0x0fff);
    }
};
