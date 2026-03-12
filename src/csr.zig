const std = @import("std");
const riscv = @import("machine.zig").Machine;

// Privilege level. Only Machine mode is mandatory (riscv-privileged-20211203.pdf Ch 1.2)
// and shall be the mode set after reset (riscv-privileged-20211203.pdf Ch 3).
pub const PrivilegeMode = enum(u3) {
  USER = 0x00,
  SUPERVISOR = 0x01,
  HYPERVISOR = 0x02,
  MACHINE = 0x03,
};

pub const Flags = enum(u7) {
  DEBUG = 0x10,
  READ = 0x20,
  WRITE = 0x40,
};

pub const ModeMask = 0x03;

const URW = @intFromEnum(PrivilegeMode.USER)        | @intFromEnum(Flags.READ) | @intFromEnum(Flags.WRITE);
const URO = @intFromEnum(PrivilegeMode.USER)        | @intFromEnum(Flags.READ)                          ;
const SRW = @intFromEnum(PrivilegeMode.SUPERVISOR)  | @intFromEnum(Flags.READ) | @intFromEnum(Flags.WRITE);
const HRW = @intFromEnum(PrivilegeMode.HYPERVISOR)  | @intFromEnum(Flags.READ) | @intFromEnum(Flags.WRITE);
const HRO = @intFromEnum(PrivilegeMode.HYPERVISOR)  | @intFromEnum(Flags.READ)                          ;
const MRW = @intFromEnum(PrivilegeMode.MACHINE)     | @intFromEnum(Flags.READ) | @intFromEnum(Flags.WRITE);
const MRO = @intFromEnum(PrivilegeMode.MACHINE)     | @intFromEnum(Flags.READ)                          ;
const DRW = @intFromEnum(Flags.DEBUG)               | @intFromEnum(Flags.READ) | @intFromEnum(Flags.WRITE);

pub const CSR = struct {
  const Self = @This();

  name: []const u8,
  index: u12,
  flags: u7,
  setter: *const fn(self: Self, cpu: *riscv.RiscVCPU(u32), value: u32) void,
  getter: *const fn(self: Self, cpu: riscv.RiscVCPU(u32)) u32,
  description: []const u8,

  pub fn set(self: Self, cpu: *riscv.RiscVCPU(u32), value: u32) void {
    self.setter(self, cpu, value);
  }

  pub fn get(self: Self, cpu: riscv.RiscVCPU(u32)) u32 {
    return self.getter(self, cpu);
  }
};

// Volume II: RISC-V Privileged Architectures V20211203 Ch. 2.2 CSR Listing
const CSRSet = [_]CSR{
// Unprivileged Floating-Point CSRs
  .{ .name = "fflags",         .index = 0x001, .flags = URW, .setter = setCSR,      .getter = getCSR, .description = "Floating-Point Accrued Exceptions" },
  .{ .name = "frm",            .index = 0x002, .flags = URW, .setter = setCSR,      .getter = getCSR, .description = "Floating-Point Dynamic Rounding Mode" },
  .{ .name = "fcsr",           .index = 0x003, .flags = URW, .setter = setCSR,      .getter = getCSR, .description = "Floating-Point Control and Status Register (frm + fflags)" },
// Unprivileged Counter/Timers
  .{ .name = "cycle",          .index = 0xC00, .flags = URO, .setter = setNop,      .getter = getMCycle, .description = "Cycle counter for RDCYCLE instruction" },
  .{ .name = "time",           .index = 0xC01, .flags = URO, .setter = setNop,      .getter = getTime,.description = "Timer for RDTIME instruction" },
  .{ .name = "instret",        .index = 0xC02, .flags = URO, .setter = setNop,      .getter = getMInstreth, .description = "Instructions-retired counter for RDINSTRET instruction" },
  .{ .name = "hpmcounter3",    .index = 0xC03, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter4",    .index = 0xC04, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter5",    .index = 0xC05, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter6",    .index = 0xC06, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter7",    .index = 0xC07, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter8",    .index = 0xC08, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter9",    .index = 0xC09, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter10",   .index = 0xC0A, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter11",   .index = 0xC0B, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter12",   .index = 0xC0C, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter13",   .index = 0xC0D, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter14",   .index = 0xC0E, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter15",   .index = 0xC0F, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter16",   .index = 0xC10, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter17",   .index = 0xC11, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter18",   .index = 0xC12, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter19",   .index = 0xC13, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter20",   .index = 0xC14, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter21",   .index = 0xC15, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter22",   .index = 0xC16, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter23",   .index = 0xC17, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter24",   .index = 0xC18, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter25",   .index = 0xC19, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter26",   .index = 0xC1A, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter27",   .index = 0xC1B, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter28",   .index = 0xC1C, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter29",   .index = 0xC1D, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter30",   .index = 0xC1E, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "hpmcounter31",   .index = 0xC1F, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Performance-monitoring counter" },
  .{ .name = "cycleh",         .index = 0xC80, .flags = URO, .setter = setNop,      .getter = getMCycleh, .description = "Upper 32 bits of cycle, RV32 only" },
  .{ .name = "timeh",          .index = 0xC81, .flags = URO, .setter = setNop,      .getter = getTimeh, .description = "Upper 32 bits of time, RV32 only" },
  .{ .name = "instreth",       .index = 0xC82, .flags = URO, .setter = setNop,      .getter = getMInstreth, .description = "Upper 32 bits of instret, RV32 only" },
  .{ .name = "hpmcounter3h",   .index = 0xC83, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter3, RV32 only" },
  .{ .name = "hpmcounter4h",   .index = 0xC84, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter4, RV32 only" },
  .{ .name = "hpmcounter5h",   .index = 0xC85, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter5, RV32 only" },
  .{ .name = "hpmcounter6h",   .index = 0xC86, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter6, RV32 only" },
  .{ .name = "hpmcounter7h",   .index = 0xC87, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter7, RV32 only" },
  .{ .name = "hpmcounter8h",   .index = 0xC88, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter8, RV32 only" },
  .{ .name = "hpmcounter9h",   .index = 0xC89, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter9, RV32 only" },
  .{ .name = "hpmcounter10h",  .index = 0xC8A, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter10, RV32 only" },
  .{ .name = "hpmcounter11h",  .index = 0xC8B, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter11, RV32 only" },
  .{ .name = "hpmcounter12h",  .index = 0xC8C, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter12, RV32 only" },
  .{ .name = "hpmcounter13h",  .index = 0xC8D, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter13, RV32 only" },
  .{ .name = "hpmcounter14h",  .index = 0xC8E, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter14, RV32 only" },
  .{ .name = "hpmcounter15h",  .index = 0xC8F, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter15, RV32 only" },
  .{ .name = "hpmcounter16h",  .index = 0xC90, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter16, RV32 only" },
  .{ .name = "hpmcounter17h",  .index = 0xC91, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter17, RV32 only" },
  .{ .name = "hpmcounter18h",  .index = 0xC92, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter18, RV32 only" },
  .{ .name = "hpmcounter19h",  .index = 0xC93, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter19, RV32 only" },
  .{ .name = "hpmcounter20h",  .index = 0xC94, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter20, RV32 only" },
  .{ .name = "hpmcounter21h",  .index = 0xC95, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter21, RV32 only" },
  .{ .name = "hpmcounter22h",  .index = 0xC96, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter22, RV32 only" },
  .{ .name = "hpmcounter23h",  .index = 0xC97, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter23, RV32 only" },
  .{ .name = "hpmcounter24h",  .index = 0xC98, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter24, RV32 only" },
  .{ .name = "hpmcounter25h",  .index = 0xC99, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter25, RV32 only" },
  .{ .name = "hpmcounter26h",  .index = 0xC9A, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter26, RV32 only" },
  .{ .name = "hpmcounter27h",  .index = 0xC9B, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter27, RV32 only" },
  .{ .name = "hpmcounter28h",  .index = 0xC9C, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter28, RV32 only" },
  .{ .name = "hpmcounter29h",  .index = 0xC9D, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter29, RV32 only" },
  .{ .name = "hpmcounter30h",  .index = 0xC9E, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter30, RV32 only" },
  .{ .name = "hpmcounter31h",  .index = 0xC9F, .flags = URO, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of hpmcounter31, RV32 only" },
// Supervisor Trap Setup
  .{ .name = "sstatus",        .index = 0x100, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor status register" },
  .{ .name = "sie",            .index = 0x104, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor interrupt-enable register" },
  .{ .name = "stvec",          .index = 0x105, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor trap handler base address" },
  .{ .name = "scounteren",     .index = 0x106, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor counter enable" },
// Supervisor Configuration
  .{ .name = "senvcfg",        .index = 0x10A, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor environment configuration register" },
// Supervisor Trap Handling
  .{ .name = "sscratch",       .index = 0x140, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Scratch register for supervisor trap handlers" },
  .{ .name = "sepc",           .index = 0x141, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor exception program counter" },
  .{ .name = "scause",         .index = 0x142, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor trap cause" },
  .{ .name = "stval",          .index = 0x143, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor bad address or instruction" },
  .{ .name = "sip",            .index = 0x144, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor interrupt pending" },
// Supervisor Protection and Translation
  .{ .name = "satp",           .index = 0x180, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor address translation and protection" },
// Debug/Trace Registers
  .{ .name = "scontext",       .index = 0x5A8, .flags = SRW, .setter = setCSR,      .getter = getCSR, .description = "Supervisor-mode context register" },
// Hypervisor Trap Setup
  .{ .name = "hstatus",        .index = 0x600, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor status register" },
  .{ .name = "hedeleg",        .index = 0x602, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor exception delegation register" },
  .{ .name = "hideleg",        .index = 0x603, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor interrupt delegation register" },
  .{ .name = "hie",            .index = 0x604, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor interrupt-enable register" },
  .{ .name = "hcounteren",     .index = 0x606, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor counter enable" },
  .{ .name = "hgeie",          .index = 0x607, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor guest external interrupt-enable register" },
// Hypervisor Trap Handling
  .{ .name = "htval",          .index = 0x643, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor bad guest physical address" },
  .{ .name = "hip",            .index = 0x644, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor interrupt pending" },
  .{ .name = "hvip",           .index = 0x645, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor virtual interrupt pending" },
  .{ .name = "htinst",         .index = 0x64A, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor trap instruction (transformed)" },
  .{ .name = "hgeip",          .index = 0xE12, .flags = HRO, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor guest external interrupt pending" },
// Hypervisor Configuration
  .{ .name = "henvcfg",        .index = 0x60A, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor environment configuration register" },
  .{ .name = "henvcfgh",       .index = 0x61A, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Additional hypervisor env. conf. register, RV32 only" },
// Hypervisor Protection and Translation
  .{ .name = "hgatp",          .index = 0x680, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor guest address translation and protection" },
// Debug/Trace Registers
  .{ .name = "hcontext",       .index = 0x6A8, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Hypervisor-mode context register" },
// Hypervisor Counter/Timer Virtualization Registers
  .{ .name = "htimedelta",     .index = 0x605, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Delta for VS/VU-mode timer" },
  .{ .name = "htimedeltah",    .index = 0x615, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of htimedelta, HSXLEN=32 only" },
// Virtual Supervisor Registers
  .{ .name = "vsstatus",       .index = 0x200, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor status register" },
  .{ .name = "vsie",           .index = 0x204, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor interrupt-enable register" },
  .{ .name = "vstvec",         .index = 0x205, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor trap handler base address" },
  .{ .name = "vsscratch",      .index = 0x240, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor scratch register" },
  .{ .name = "vsepc",          .index = 0x241, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor exception program counter" },
  .{ .name = "vscause",        .index = 0x242, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor trap cause" },
  .{ .name = "vstval",         .index = 0x243, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor bad address or instruction" },
  .{ .name = "vsip",           .index = 0x244, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor interrupt pending" },
  .{ .name = "vsatp",          .index = 0x280, .flags = HRW, .setter = setCSR,      .getter = getCSR, .description = "Virtual supervisor address translation and protection" },
// Machine Information Registers
  .{ .name = "mvendorid",      .index = 0xF11, .flags = MRO, .setter = setNop,      .getter = getCSR, .description = "Vendor ID" },
  .{ .name = "marchid",        .index = 0xF12, .flags = MRO, .setter = setNop,      .getter = getCSR, .description = "Architecture ID" },
  .{ .name = "mimpid",         .index = 0xF13, .flags = MRO, .setter = setCSR,      .getter = getCSR, .description = "Implementation ID" },
  .{ .name = "mhartid",        .index = 0xF14, .flags = MRO, .setter = setCSR,      .getter = getCSR, .description = "Hardware thread ID" },
  .{ .name = "mconfigptr",     .index = 0xF15, .flags = MRO, .setter = setCSR,      .getter = getCSR, .description = "Pointer to configuration data structure" },
// Machine Trap Setup
  .{ .name = "mstatus",        .index = 0x300, .flags = MRW, .setter = setMStatus,  .getter = getCSR, .description = "Machine status register" },
  .{ .name = "misa",           .index = 0x301, .flags = MRW, .setter = setNop,      .getter = getMisa,.description = "ISA and extension" },
  .{ .name = "medeleg",        .index = 0x302, .flags = MRW, .setter = setCSR,      .getter = getNop, .description = "Machine exception delegation register" },
  .{ .name = "mideleg",        .index = 0x303, .flags = MRW, .setter = setMideleg,  .getter = getNop, .description = "Machine interrupt delegation register" },
  .{ .name = "mie",            .index = 0x304, .flags = MRW, .setter = setMie,      .getter = getCSR, .description = "Machine interrupt-enable register" },
  .{ .name = "mtvec",          .index = 0x305, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine trap-handler base address" },
  .{ .name = "mcounteren",     .index = 0x306, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine counter enable" },
  .{ .name = "mstatush",       .index = 0x310, .flags = MRW, .setter = setCSR,      .getter = getNop, .description = "Additional machine status register, RV32 only" },
// Machine Trap Handling
  .{ .name = "mscratch",       .index = 0x340, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Scratch register for machine trap handlers" },
  .{ .name = "mepc",           .index = 0x341, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine exception program counter" },
  .{ .name = "mcause",         .index = 0x342, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine trap cause" },
  .{ .name = "mtval",          .index = 0x343, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine bad address or instruction" },
  .{ .name = "mip",            .index = 0x344, .flags = MRW, .setter = setMip,      .getter = getCSR, .description = "Machine interrupt pending" },
  .{ .name = "mtinst",         .index = 0x34A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine trap instruction (transformed)" },
  .{ .name = "mtval2",         .index = 0x34B, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine bad guest physical address" },
// Machine Configuration
  .{ .name = "menvcfg",        .index = 0x30A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine environment configuration register" },
  .{ .name = "menvcfgh",       .index = 0x31A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Additional machine env. conf. register, RV32 only" },
  .{ .name = "mseccfg",        .index = 0x747, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine security configuration register" },
  .{ .name = "mseccfgh",       .index = 0x757, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Additional machine security conf. register, RV32 only" },
// Machine Memory Protection
  .{ .name = "pmpcfg0",        .index = 0x3A0, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration" },
  .{ .name = "pmpcfg1",        .index = 0x3A1, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg2",        .index = 0x3A2, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration" },
  .{ .name = "pmpcfg3",        .index = 0x3A3, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg4",        .index = 0x3A4, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg5",        .index = 0x3A5, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg6",        .index = 0x3A6, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg7",        .index = 0x3A7, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg8",        .index = 0x3A8, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg9",        .index = 0x3A9, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg10",       .index = 0x3AA, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg11",       .index = 0x3AB, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg12",       .index = 0x3AC, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg13",       .index = 0x3AD, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpcfg14",       .index = 0x3AE, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration" },
  .{ .name = "pmpcfg15",       .index = 0x3AF, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection configuration, RV32 only" },
  .{ .name = "pmpaddr0",       .index = 0x3B0, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection address register" },
  .{ .name = "pmpaddr1",       .index = 0x3B1, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection address register" },
// TODO: Complete the physical memory protection address registers.
  .{ .name = "pmpaddr63",      .index = 0x3EF, .flags = MRW, .setter = setNop,      .getter = getCSR, .description = "Physical memory protection address register" },
  .{ .name = "mcycle",         .index = 0xB00, .flags = MRW, .setter = setNop,      .getter = getMCycle, .description = "Machine cycle counter" },
  .{ .name = "minstret",       .index = 0xB02, .flags = MRW, .setter = setNop,      .getter = getMInstret, .description = "Machine instructions-retired counter" },
  .{ .name = "mhpmcounter3",   .index = 0xB03, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter4",   .index = 0xB04, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter5",   .index = 0xB05, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter6",   .index = 0xB06, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter7",   .index = 0xB07, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter8",   .index = 0xB08, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter9",   .index = 0xB09, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter10",  .index = 0xB0A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter11",  .index = 0xB0B, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter12",  .index = 0xB0C, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter13",  .index = 0xB0D, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter14",  .index = 0xB0E, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter15",  .index = 0xB0F, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter16",  .index = 0xB10, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter17",  .index = 0xB11, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter18",  .index = 0xB12, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter19",  .index = 0xB13, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter20",  .index = 0xB14, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter21",  .index = 0xB15, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter22",  .index = 0xB16, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter23",  .index = 0xB17, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter24",  .index = 0xB18, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter25",  .index = 0xB19, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter26",  .index = 0xB1A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter27",  .index = 0xB1B, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter28",  .index = 0xB1C, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter29",  .index = 0xB1D, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter30",  .index = 0xB1E, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mhpmcounter31",  .index = 0xB1F, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring counter" },
  .{ .name = "mcycleh",        .index = 0xB80, .flags = MRW, .setter = setNop,      .getter = getMCycleh, .description = "Upper 32 bits of mcycle, RV32 only" },
  .{ .name = "minstreth",      .index = 0xB82, .flags = MRW, .setter = setNop,      .getter = getMInstreth, .description = "Upper 32 bits of minstret, RV32 only" },
  .{ .name = "mhpmcounter3h",  .index = 0xB83, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter3, RV32 only" },
  .{ .name = "mhpmcounter4h",  .index = 0xB84, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter4, RV32 only" },
  .{ .name = "mhpmcounter5h",  .index = 0xB85, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter5, RV32 only" },
  .{ .name = "mhpmcounter6h",  .index = 0xB86, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter6, RV32 only" },
  .{ .name = "mhpmcounter7h",  .index = 0xB87, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter7, RV32 only" },
  .{ .name = "mhpmcounter8h",  .index = 0xB88, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter8, RV32 only" },
  .{ .name = "mhpmcounter9h",  .index = 0xB89, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter9, RV32 only" },
  .{ .name = "mhpmcounter10h", .index = 0xB8A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter10, RV32 only" },
  .{ .name = "mhpmcounter11h", .index = 0xB8B, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter11, RV32 only" },
  .{ .name = "mhpmcounter12h", .index = 0xB8C, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter12, RV32 only" },
  .{ .name = "mhpmcounter13h", .index = 0xB8D, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter13, RV32 only" },
  .{ .name = "mhpmcounter14h", .index = 0xB8E, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter14, RV32 only" },
  .{ .name = "mhpmcounter15h", .index = 0xB8F, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter15, RV32 only" },
  .{ .name = "mhpmcounter16h", .index = 0xB90, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter16, RV32 only" },
  .{ .name = "mhpmcounter17h", .index = 0xB91, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter17, RV32 only" },
  .{ .name = "mhpmcounter18h", .index = 0xB92, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter18, RV32 only" },
  .{ .name = "mhpmcounter19h", .index = 0xB93, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter19, RV32 only" },
  .{ .name = "mhpmcounter20h", .index = 0xB94, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter20, RV32 only" },
  .{ .name = "mhpmcounter21h", .index = 0xB95, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter21, RV32 only" },
  .{ .name = "mhpmcounter22h", .index = 0xB96, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter22, RV32 only" },
  .{ .name = "mhpmcounter23h", .index = 0xB97, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter23, RV32 only" },
  .{ .name = "mhpmcounter24h", .index = 0xB98, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter24, RV32 only" },
  .{ .name = "mhpmcounter25h", .index = 0xB99, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter25, RV32 only" },
  .{ .name = "mhpmcounter26h", .index = 0xB9A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter26, RV32 only" },
  .{ .name = "mhpmcounter27h", .index = 0xB9B, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter27, RV32 only" },
  .{ .name = "mhpmcounter28h", .index = 0xB9C, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter28, RV32 only" },
  .{ .name = "mhpmcounter29h", .index = 0xB9D, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter29, RV32 only" },
  .{ .name = "mhpmcounter30h", .index = 0xB9E, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter30, RV32 only" },
  .{ .name = "mhpmcounter31h", .index = 0xB9F, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Upper 32 bits of mhpmcounter31, RV32 only" },
// Machine Counter Setup
  .{ .name = "mcountinhibit",  .index = 0x320, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine counter-inhibit register" },
  .{ .name = "mhpmevent3",     .index = 0x323, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent4",     .index = 0x324, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent5",     .index = 0x325, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent6",     .index = 0x326, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent7",     .index = 0x327, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent8",     .index = 0x328, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent9",     .index = 0x329, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent10",    .index = 0x32A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent11",    .index = 0x32B, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent12",    .index = 0x32C, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent13",    .index = 0x32D, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent14",    .index = 0x32E, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent15",    .index = 0x32F, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent16",    .index = 0x330, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent17",    .index = 0x331, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent18",    .index = 0x332, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent19",    .index = 0x333, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent20",    .index = 0x334, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent21",    .index = 0x335, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent22",    .index = 0x336, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent23",    .index = 0x337, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent24",    .index = 0x338, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent25",    .index = 0x339, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent26",    .index = 0x33A, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent27",    .index = 0x33B, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent28",    .index = 0x33C, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent29",    .index = 0x33D, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent30",    .index = 0x33E, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
  .{ .name = "mhpmevent31",    .index = 0x33F, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine performance-monitoring event selector" },
// Debug/Trace Registers (shared with Debug Mode)
  .{ .name = "tselect",        .index = 0x7A0, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Debug/Trace trigger register select" },
  .{ .name = "tdata1",         .index = 0x7A1, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "First Debug/Trace trigger data register" },
  .{ .name = "tdata2",         .index = 0x7A2, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Second Debug/Trace trigger data register" },
  .{ .name = "tdata3",         .index = 0x7A3, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Third Debug/Trace trigger data register" },
  .{ .name = "mcontext",       .index = 0x7A8, .flags = MRW, .setter = setCSR,      .getter = getCSR, .description = "Machine-mode context register" },
// Debug Mode Registers
  .{ .name = "dcsr",           .index = 0x7B0, .flags = DRW, .setter = setCSR,      .getter = getCSR, .description = "Debug control and status register" },
  .{ .name = "dpc",            .index = 0x7B1, .flags = DRW, .setter = setCSR,      .getter = getCSR, .description = "Debug PC" },
  .{ .name = "dscratch0",      .index = 0x7B2, .flags = DRW, .setter = setCSR,      .getter = getCSR, .description = "Debug scratch register 0" },
  .{ .name = "dscratch1",      .index = 0x7B3, .flags = DRW, .setter = setCSR,      .getter = getCSR, .description = "Debug scratch register 1" },
};

pub const fflags: u12 = 0x001;
pub const frm: u12 = 0x002;
pub const fcsr: u12 = 0x003;
pub const cycle: u12 = 0xC00;
pub const time: u12 = 0xC01;
pub const instret: u12 = 0xC02;
pub const hpmcounter3: u12 = 0xC03;
pub const hpmcounter4: u12 = 0xC04;
pub const hpmcounter5: u12 = 0xC05;
pub const hpmcounter6: u12 = 0xC06;
pub const hpmcounter7: u12 = 0xC07;
pub const hpmcounter8: u12 = 0xC08;
pub const hpmcounter9: u12 = 0xC09;
pub const hpmcounter10: u12 = 0xC0A;
pub const hpmcounter11: u12 = 0xC0B;
pub const hpmcounter12: u12 = 0xC0C;
pub const hpmcounter13: u12 = 0xC0D;
pub const hpmcounter14: u12 = 0xC0E;
pub const hpmcounter15: u12 = 0xC0F;
pub const hpmcounter16: u12 = 0xC10;
pub const hpmcounter17: u12 = 0xC11;
pub const hpmcounter18: u12 = 0xC12;
pub const hpmcounter19: u12 = 0xC13;
pub const hpmcounter20: u12 = 0xC14;
pub const hpmcounter21: u12 = 0xC15;
pub const hpmcounter22: u12 = 0xC16;
pub const hpmcounter23: u12 = 0xC17;
pub const hpmcounter24: u12 = 0xC18;
pub const hpmcounter25: u12 = 0xC19;
pub const hpmcounter26: u12 = 0xC1A;
pub const hpmcounter27: u12 = 0xC1B;
pub const hpmcounter28: u12 = 0xC1C;
pub const hpmcounter29: u12 = 0xC1D;
pub const hpmcounter30: u12 = 0xC1E;
pub const hpmcounter31: u12 = 0xC1F;
pub const cycleh: u12 = 0xC80;
pub const timeh: u12 = 0xC81;
pub const instreth: u12 = 0xC82;
pub const hpmcounter3h: u12 = 0xC83;
pub const hpmcounter4h: u12 = 0xC84;
pub const hpmcounter5h: u12 = 0xC85;
pub const hpmcounter6h: u12 = 0xC86;
pub const hpmcounter7h: u12 = 0xC87;
pub const hpmcounter8h: u12 = 0xC88;
pub const hpmcounter9h: u12 = 0xC89;
pub const hpmcounter10h: u12 = 0xC8A;
pub const hpmcounter11h: u12 = 0xC8B;
pub const hpmcounter12h: u12 = 0xC8C;
pub const hpmcounter13h: u12 = 0xC8D;
pub const hpmcounter14h: u12 = 0xC8E;
pub const hpmcounter15h: u12 = 0xC8F;
pub const hpmcounter16h: u12 = 0xC90;
pub const hpmcounter17h: u12 = 0xC91;
pub const hpmcounter18h: u12 = 0xC92;
pub const hpmcounter19h: u12 = 0xC93;
pub const hpmcounter20h: u12 = 0xC94;
pub const hpmcounter21h: u12 = 0xC95;
pub const hpmcounter22h: u12 = 0xC96;
pub const hpmcounter23h: u12 = 0xC97;
pub const hpmcounter24h: u12 = 0xC98;
pub const hpmcounter25h: u12 = 0xC99;
pub const hpmcounter26h: u12 = 0xC9A;
pub const hpmcounter27h: u12 = 0xC9B;
pub const hpmcounter28h: u12 = 0xC9C;
pub const hpmcounter29h: u12 = 0xC9D;
pub const hpmcounter30h: u12 = 0xC9E;
pub const hpmcounter31h: u12 = 0xC9F;
pub const sstatus: u12 = 0x100;
pub const sie: u12 = 0x104;
pub const stvec: u12 = 0x105;
pub const scounteren: u12 = 0x106;
pub const senvcfg: u12 = 0x10A;
pub const sscratch: u12 = 0x140;
pub const sepc: u12 = 0x141;
pub const scause: u12 = 0x142;
pub const stval: u12 = 0x143;
pub const sip: u12 = 0x144;
pub const satp: u12 = 0x180;
pub const scontext: u12 = 0x5A8;
pub const hstatus: u12 = 0x600;
pub const hedeleg: u12 = 0x602;
pub const hideleg: u12 = 0x603;
pub const hie: u12 = 0x604;
pub const hcounteren: u12 = 0x606;
pub const hgeie: u12 = 0x607;
pub const htval: u12 = 0x643;
pub const hip: u12 = 0x644;
pub const hvip: u12 = 0x645;
pub const htinst: u12 = 0x64A;
pub const hgeip: u12 = 0xE12;
pub const henvcfg: u12 = 0x60A;
pub const henvcfgh: u12 = 0x61A;
pub const hgatp: u12 = 0x680;
pub const hcontext: u12 = 0x6A8;
pub const htimedelta: u12 = 0x605;
pub const htimedeltah: u12 = 0x615;
pub const vsstatus: u12 = 0x200;
pub const vsie: u12 = 0x204;
pub const vstvec: u12 = 0x205;
pub const vsscratch: u12 = 0x240;
pub const vsepc: u12 = 0x241;
pub const vscause: u12 = 0x242;
pub const vstval: u12 = 0x243;
pub const vsip: u12 = 0x244;
pub const vsatp: u12 = 0x280;
pub const mvendorid: u12 = 0xF11;
pub const marchid: u12 = 0xF12;
pub const mimpid: u12 = 0xF13;
pub const mhartid: u12 = 0xF14;
pub const mconfigptr: u12 = 0xF15;
pub const mstatus: u12 = 0x300;
pub const misa: u12 = 0x301;
pub const medeleg: u12 = 0x302;
pub const mideleg: u12 = 0x303;
pub const mie: u12 = 0x304;
pub const mtvec: u12 = 0x305;
pub const mcounteren: u12 = 0x306;
pub const mstatush: u12 = 0x310;
pub const mscratch: u12 = 0x340;
pub const mepc: u12 = 0x341;
pub const mcause: u12 = 0x342;
pub const mtval: u12 = 0x343;
pub const mip: u12 = 0x344;
pub const mtinst: u12 = 0x34A;
pub const mtval2: u12 = 0x34B;
pub const menvcfg: u12 = 0x30A;
pub const menvcfgh: u12 = 0x31A;
pub const mseccfg: u12 = 0x747;
pub const mseccfgh: u12 = 0x757;
pub const pmpcfg0: u12 = 0x3A0;
pub const pmpcfg1: u12 = 0x3A1;
pub const pmpcfg2: u12 = 0x3A2;
pub const pmpcfg3: u12 = 0x3A3;
pub const pmpcfg4: u12 = 0x3A4;
pub const pmpcfg5: u12 = 0x3A5;
pub const pmpcfg6: u12 = 0x3A6;
pub const pmpcfg7: u12 = 0x3A7;
pub const pmpcfg8: u12 = 0x3A8;
pub const pmpcfg9: u12 = 0x3A9;
pub const pmpcfg10: u12 = 0x3AA;
pub const pmpcfg11: u12 = 0x3AB;
pub const pmpcfg12: u12 = 0x3AC;
pub const pmpcfg13: u12 = 0x3AD;
pub const pmpcfg14: u12 = 0x3AE;
pub const pmpcfg15: u12 = 0x3AF;
pub const pmpaddr0: u12 = 0x3B0;
pub const pmpaddr1: u12 = 0x3B1;
pub const pmpaddr63: u12 = 0x3EF;
pub const mcycle: u12 = 0xB00;
pub const minstret: u12 = 0xB02;
pub const mhpmcounter3: u12 = 0xB03;
pub const mhpmcounter4: u12 = 0xB04;
pub const mhpmcounter5: u12 = 0xB05;
pub const mhpmcounter6: u12 = 0xB06;
pub const mhpmcounter7: u12 = 0xB07;
pub const mhpmcounter8: u12 = 0xB08;
pub const mhpmcounter9: u12 = 0xB09;
pub const mhpmcounter10: u12 = 0xB0A;
pub const mhpmcounter11: u12 = 0xB0B;
pub const mhpmcounter12: u12 = 0xB0C;
pub const mhpmcounter13: u12 = 0xB0D;
pub const mhpmcounter14: u12 = 0xB0E;
pub const mhpmcounter15: u12 = 0xB0F;
pub const mhpmcounter16: u12 = 0xB10;
pub const mhpmcounter17: u12 = 0xB11;
pub const mhpmcounter18: u12 = 0xB12;
pub const mhpmcounter19: u12 = 0xB13;
pub const mhpmcounter20: u12 = 0xB14;
pub const mhpmcounter21: u12 = 0xB15;
pub const mhpmcounter22: u12 = 0xB16;
pub const mhpmcounter23: u12 = 0xB17;
pub const mhpmcounter24: u12 = 0xB18;
pub const mhpmcounter25: u12 = 0xB19;
pub const mhpmcounter26: u12 = 0xB1A;
pub const mhpmcounter27: u12 = 0xB1B;
pub const mhpmcounter28: u12 = 0xB1C;
pub const mhpmcounter29: u12 = 0xB1D;
pub const mhpmcounter30: u12 = 0xB1E;
pub const mhpmcounter31: u12 = 0xB1F;
pub const mcycleh: u12 = 0xB80;
pub const minstreth: u12 = 0xB82;
pub const mhpmcounter3h: u12 = 0xB83;
pub const mhpmcounter4h: u12 = 0xB84;
pub const mhpmcounter5h: u12 = 0xB85;
pub const mhpmcounter6h: u12 = 0xB86;
pub const mhpmcounter7h: u12 = 0xB87;
pub const mhpmcounter8h: u12 = 0xB88;
pub const mhpmcounter9h: u12 = 0xB89;
pub const mhpmcounter10h: u12 = 0xB8A;
pub const mhpmcounter11h: u12 = 0xB8B;
pub const mhpmcounter12h: u12 = 0xB8C;
pub const mhpmcounter13h: u12 = 0xB8D;
pub const mhpmcounter14h: u12 = 0xB8E;
pub const mhpmcounter15h: u12 = 0xB8F;
pub const mhpmcounter16h: u12 = 0xB90;
pub const mhpmcounter17h: u12 = 0xB91;
pub const mhpmcounter18h: u12 = 0xB92;
pub const mhpmcounter19h: u12 = 0xB93;
pub const mhpmcounter20h: u12 = 0xB94;
pub const mhpmcounter21h: u12 = 0xB95;
pub const mhpmcounter22h: u12 = 0xB96;
pub const mhpmcounter23h: u12 = 0xB97;
pub const mhpmcounter24h: u12 = 0xB98;
pub const mhpmcounter25h: u12 = 0xB99;
pub const mhpmcounter26h: u12 = 0xB9A;
pub const mhpmcounter27h: u12 = 0xB9B;
pub const mhpmcounter28h: u12 = 0xB9C;
pub const mhpmcounter29h: u12 = 0xB9D;
pub const mhpmcounter30h: u12 = 0xB9E;
pub const mhpmcounter31h: u12 = 0xB9F;
pub const mcountinhibit: u12 = 0x320;
pub const mhpmevent3: u12 = 0x323;
pub const mhpmevent4: u12 = 0x324;
pub const mhpmevent5: u12 = 0x325;
pub const mhpmevent6: u12 = 0x326;
pub const mhpmevent7: u12 = 0x327;
pub const mhpmevent8: u12 = 0x328;
pub const mhpmevent9: u12 = 0x329;
pub const mhpmevent10: u12 = 0x32A;
pub const mhpmevent11: u12 = 0x32B;
pub const mhpmevent12: u12 = 0x32C;
pub const mhpmevent13: u12 = 0x32D;
pub const mhpmevent14: u12 = 0x32E;
pub const mhpmevent15: u12 = 0x32F;
pub const mhpmevent16: u12 = 0x330;
pub const mhpmevent17: u12 = 0x331;
pub const mhpmevent18: u12 = 0x332;
pub const mhpmevent19: u12 = 0x333;
pub const mhpmevent20: u12 = 0x334;
pub const mhpmevent21: u12 = 0x335;
pub const mhpmevent22: u12 = 0x336;
pub const mhpmevent23: u12 = 0x337;
pub const mhpmevent24: u12 = 0x338;
pub const mhpmevent25: u12 = 0x339;
pub const mhpmevent26: u12 = 0x33A;
pub const mhpmevent27: u12 = 0x33B;
pub const mhpmevent28: u12 = 0x33C;
pub const mhpmevent29: u12 = 0x33D;
pub const mhpmevent30: u12 = 0x33E;
pub const mhpmevent31: u12 = 0x33F;
pub const tselect: u12 = 0x7A0;
pub const tdata1: u12 = 0x7A1;
pub const tdata2: u12 = 0x7A2;
pub const tdata3: u12 = 0x7A3;
pub const mcontext: u12 = 0x7A8;
pub const dcsr: u12 = 0x7B0;
pub const dpc: u12 = 0x7B1;
pub const dscratch0: u12 = 0x7B2;
pub const dscratch1: u12 = 0x7B3;

fn generateCSRRegistry() [4096]CSR {
  var tmp = [_]CSR{ .{ .name = "", .index = 0, .flags = URO, .setter = setCSR, .getter = getCSR, .description = "Not initialized" } } ** 4096;
  for (CSRSet) |csr| {
    tmp[csr.index] = csr;
  }
  return tmp;
}

// Static array of all the CSR set at the correct index as built from the
// CSR set description.
pub const csrRegistry = generateCSRRegistry();

// Default CSR setter
fn setCSR(self: CSR, cpu: *riscv.RiscVCPU(u32), value: u32) void {
  cpu.csr[self.index] = value;
}

// Default CSR getter
fn getCSR(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  return cpu.csr[self.index];
}

fn setNop(self: CSR, cpu: *riscv.RiscVCPU(u32), value: u32) void {
  _ = self;
  _ = cpu;
  _ = value;
  // Noop
}

fn getNop(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  _ = cpu;
  return 0;
}

pub const MstatusBits = struct {
  pub const MIE: u32 = 1 <<  3; // riscv-privileged-20211203.pdf Ch. 3.1.6.1
  pub const MPRV:u32 = 1 << 17; // riscv-privileged-20211203.pdf Ch. 3.1.6.3
  pub const SUM: u32 = 1 << 18; // riscv-privileged-20211203.pdf Ch. 3.1.6.3
  pub const MXR: u32 = 1 << 19; // riscv-privileged-20211203.pdf Ch. 3.1.6.3
  pub const TVM: u32 = 1 << 20; // riscv-privileged-20211203.pdf Ch. 3.1.6.5
  pub const TW: u32  = 1 << 21; // riscv-privileged-20211203.pdf Ch. 3.1.6.5
  pub const FS: u32  = 3 << 13; // riscv-privileged-20211203.pdf Ch. 3.1.6.6
  pub const VS: u32  = 3 <<  9; // riscv-privileged-20211203.pdf Ch. 3.1.6.6
  pub const XS: u32  = 3 << 15; // riscv-privileged-20211203.pdf Ch. 3.1.6.6
  pub const SD: u32  = 1 << 31; // riscv-privileged-20211203.pdf Ch. 3.1.6.6
};
// From here some specific CSR getter and setter
fn setMStatus(self: CSR, cpu: *riscv.RiscVCPU(u32), value: u32) void {
  std.log.debug("set mstatus from 0x{x:0>8} to 0x{x:0>8} MIE {s}", .{
    cpu.csr[self.index], value, if ((value & MstatusBits.MIE) != 0) "enabled" else "disabled" });
  cpu.csr[self.index] = value | 0x00001800; // Force MBB to Machine Mode (0b11) for now.
  cpu.csr[self.index] = cpu.csr[self.index] & ~MstatusBits.TVM & ~MstatusBits.TW &
    ~MstatusBits.MPRV & ~MstatusBits.SUM & ~MstatusBits.MXR & ~MstatusBits.FS &
    ~MstatusBits.VS & ~MstatusBits.XS & ~MstatusBits.SD; // Force those flags to 0.

  // TODO: Documentation indicates that some field of the mstatus CSR must be
  // preserved, but mini-riscv32 force the value to 0. Probably wrong but while
  // investigating panic issue, let's reduce differences with a working
  // implementation.
  // cpu.csr[self.index] = value;

  riscv.checkForInterrupt(cpu); // riscv-privileged-20211203.pdf Ch. 3.1.9
}

fn setMideleg(self: CSR, cpu: *riscv.RiscVCPU(u32), value: u32) void {
  _ = self;
  _ = value;
  riscv.checkForInterrupt(cpu); // riscv-privileged-20211203.pdf Ch. 3.1.9
}

// riscv-privileged-20211203.pdf Ch. 3.1.9
pub const MieBits = struct {
  const SSIE: u32 = 1 <<  1;
  const MSIE: u32 = 1 <<  3;
  const STIE: u32 = 1 <<  5;
  const MTIE: u32 = 1 <<  7;
  const SEIE: u32 = 1 <<  9;
  const MEIE: u32 = 1 << 11;
};
fn setMie(self: CSR, cpu: *riscv.RiscVCPU(u32), value: u32) void {
  cpu.csr[self.index] = value;
  cpu.csr[self.index] = cpu.csr[self.index] & ~MieBits.SSIE & ~MieBits.STIE & ~MieBits.SEIE;
  riscv.checkForInterrupt(cpu); // riscv-privileged-20211203.pdf Ch. 3.1.9
}

// riscv-privileged-20211203.pdf Ch. 3.1.9
pub const MipBits = struct {
  const SSIP: u32 = 1 <<  1;
  const MSIP: u32 = 1 <<  3;
  const STIP: u32 = 1 <<  5;
  const MTIP: u32 = 1 <<  7;
  const SEIP: u32 = 1 <<  9;
  const MEIP: u32 = 1 << 11;
};
fn setMip(self: CSR, cpu: *riscv.RiscVCPU(u32), value: u32) void {
  cpu.csr[self.index] = value;
  cpu.csr[self.index] = cpu.csr[self.index] & ~MipBits.SSIP & ~MipBits.STIP & ~MipBits.SEIP;
  riscv.checkForInterrupt(cpu); // riscv-privileged-20211203.pdf Ch. 3.1.9
}

fn getMCycle(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  // @breakpoint();
  // Do not use self here, this can be called by other xcycle registers, see
  // riscv-privileged-20211203.pdf Ch. 3.1.11.
  return cpu.csr[mcycle];
}

fn getMCycleh(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  // @breakpoint();
  // Do not use self here, this can be called by other xcycle registers, see
  // riscv-privileged-20211203.pdf Ch. 3.1.11.
  return cpu.csr[mcycleh];
}

fn getMInstret(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  // @breakpoint();
  // Do not use self here, this can be called by other xcycle registers, see
  // riscv-privileged-20211203.pdf Ch. 3.1.11.
  return cpu.csr[minstret];
}

fn getMInstreth(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  // @breakpoint();
  // Do not use self here, this can be called by other xcycle registers, see
  // riscv-privileged-20211203.pdf Ch. 3.1.11.
  return cpu.csr[minstreth];
}

fn getTime(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  _ = cpu;
  // @breakpoint();
  return 0;
}

fn getTimeh(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  _ = cpu;
  // @breakpoint();
  return 0;
}

fn getMisa(self: CSR, cpu: riscv.RiscVCPU(u32)) u32 {
  _ = self;
  // @breakpoint();
  return cpu.csr[misa];
}

// These are the initial values for the CSR registry file.
// All the other CSRs must be set to 0.
pub const rv32_initial_csr_values = [_]std.meta.Tuple(&.{ usize, u32 }) {
  .{ 0xF14, 0x00000000 }, // // riscv-privileged-20211203.pdf Ch. 3.1.5 Hart ID Register (mhardid)
  // This is set to 32 bits with I, A and M extension.
  .{ 0x301, 0x40401101 }, // riscv-privileged-20211203.pdf Ch. 3.1.1 Machine ISA Register (misa)
// 0x40001101
  // MIE (Machine Interrupt Enabled) and MPIE (Machine Previous Interrupt Enabled) are set to true.
  // MPP (Machine Previous Privilege) is set to 11 for Machine mode.
  .{ 0x300, 0x00001888 }, // riscv-privileged-20211203.pdf Ch. 3.1.6 Machine Status Register (mstatus)
};

// Initialize an array with 0 and fill up the provided initial values.
pub fn init_csr(comptime T: type, values: []const std.meta.Tuple(&.{ usize, u32 })) [4096]T {
  var tmp = [_]T{ 0 } ** 4096;
  for (values) |value| {
    tmp[value[0]] = value[1];
  }
  return tmp;
}

pub const MCauseInterruptCode = enum(u32) {
  SupervisorSoftwareInterrupt = 1,
  MachineSoftwareInterrupt = 3,
  SupervisorTimerInterrupt = 5,
  MachineTimerInterrupt = 7,
  SupervisorExternalInterrupt = 9,
  MachineExternalInterrupt = 11,
};

pub const MCauseExceptionCode = enum(u32) {
  InstructionAddressMisaligned = 0x00000000,
  IllegalInstruction = 2,
  Breakpoint = 3,
  LoadAccessFault = 5,
  StoreAccessFault = 7,
  MachineModeEnvCall = 11,
};
