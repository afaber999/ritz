const std = @import("std");

const CleanPatternsStep = struct {
    step: std.Build.Step,

    fn create(b: *std.Build) *CleanPatternsStep {
        const self = b.allocator.create(CleanPatternsStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "clean test artifacts",
                .owner = b,
                .makeFn = make,
            }),
        };
        return self;
    }

    fn removeByExt(dir_path: []const u8, ext: []const u8) void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var it = dir.iterate();
        while (it.next() catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ext)) continue;
            dir.deleteFile(entry.name) catch {};
        }
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = step;
        _ = options;

        removeByExt("riscv_tests", ".o");
        removeByExt("tests/riscv_tests", ".o");
        removeByExt("firmware", ".o");
        removeByExt("firmware", ".elf");
        removeByExt("firmware", ".bin");
        removeByExt("firmware", ".lst");
        removeByExt("tests/firmware", ".o");
        removeByExt("tests/firmware", ".elf");
        removeByExt("tests/firmware", ".bin");
        removeByExt("tests/firmware", ".lst");
    }
};

fn findFirstProgram(b: *std.Build, candidates: []const []const u8, search_paths: []const []const u8) ?[]const u8 {
    for (candidates) |program_name| {
        const found = b.findProgram(&.{program_name}, search_paths) catch null;
        if (found != null) return found;
    }
    return null;
}

fn needsRv32imaZicsr(test_name: []const u8) bool {
    if (std.mem.eql(u8, test_name, "csr") or std.mem.eql(u8, test_name, "mcsr") or std.mem.eql(u8, test_name, "lrsc")) return true;
    return std.mem.startsWith(u8, test_name, "amo");
}

fn getTestTxt(test_name: []const u8) []const u8 {
    if (std.mem.eql(u8, test_name, "lrsc")) return "lrsc_w";
    return test_name;
}

pub fn build(b: *std.Build) void {
    const tests_root = b.path(".");
    const repo_root = b.path("..");
    const root_ritz_path = "..\\zig-out\\bin\\ritz.exe";
    const firmware_dir_path = "firmware";
    const firmware_start_path = "firmware/start.S";
    const firmware_linker_path = "firmware/linker.ld";
    const start_o = "firmware/start.o";
    const firmware_elf = "firmware/firmware.elf";
    const firmware_bin = "firmware/firmware.bin";

    const gcc_candidates = [_][]const u8{
        "riscv64-unknown-elf-gcc",
        "riscv32-unknown-elf-gcc",
        "riscv32-esp-elf-gcc",
    };
    const objcopy_candidates = [_][]const u8{
        "riscv64-unknown-elf-objcopy",
        "riscv32-unknown-elf-objcopy",
        "riscv32-esp-elf-objcopy",
    };
    const objdump_candidates = [_][]const u8{
        "riscv64-unknown-elf-objdump",
        "riscv32-unknown-elf-objdump",
        "riscv32-esp-elf-objdump",
    };
    const risctools_search_paths = [_][]const u8{
        "C:/msys64/mingw64/bin",
        "C:/msys64/ucrt64/bin",
        "C:/msys64/usr/bin",
        "/mingw64/bin",
        "/ucrt64/bin",
        "/usr/bin",
    };

    const gcc = findFirstProgram(b, &gcc_candidates, &risctools_search_paths) orelse {
        std.log.err("Unable to find a RISC-V GCC (riscv64-unknown-elf-gcc/riscv32-unknown-elf-gcc)", .{});
        return;
    };
    const objcopy = findFirstProgram(b, &objcopy_candidates, &risctools_search_paths) orelse {
        std.log.err("Unable to find a RISC-V objcopy", .{});
        return;
    };
    const objdump = findFirstProgram(b, &objdump_candidates, &risctools_search_paths) orelse {
        std.log.err("Unable to find a RISC-V objdump", .{});
        return;
    };

    const test_names = [_][]const u8{
        "addi", "add", "andi", "and", "auipc", "beq", "bge", "bgeu", "blt", "bltu", "bne",
        "div", "divu", "jalr", "jal", "j", "lb", "lbu", "lh", "lhu", "lui", "lw",
        "mulh", "mulhsu", "mulhu", "mul", "ori", "or", "rem", "remu", "sb", "sh", "simple",
        "slli", "sll", "slti", "sltiu", "slt", "srai", "sra", "srli", "srl", "sub", "sw",
        "xori", "xor", "csr", "mcsr", "amoadd_w", "amoand_w", "amoor_w", "amoswap_w", "amoxor_w",
        "amomax_w", "amomaxu_w", "amomin_w", "amominu_w", "lrsc",
    };

    const compile_start = b.addSystemCommand(&.{gcc});
    compile_start.setCwd(tests_root);
    compile_start.addArgs(&.{ "-c", "-mabi=ilp32", "-march=rv32im" });
    compile_start.addArg(firmware_start_path);
    compile_start.addArgs(&.{ "-o", start_o });

    const link_fw = b.addSystemCommand(&.{gcc});
    link_fw.setCwd(tests_root);
    link_fw.step.dependOn(&compile_start.step);
    link_fw.addArgs(&.{
        "-march=rv32ima_zicsr",
        "-mabi=ilp32",
        "-Os",
        "-ffreestanding",
        "-nostdlib",
        "-o",
    });
    link_fw.addArg(firmware_elf);
    link_fw.addArg(b.fmt("-Wl,-m,elf32lriscv,-Bstatic,-T,{s}", .{firmware_linker_path}));

    var object_paths = std.ArrayList([]const u8){};
    defer object_paths.deinit(b.allocator);
    object_paths.append(b.allocator, start_o) catch @panic("OOM");

    for (test_names) |test_name| {
        const obj_path = b.fmt("riscv_tests/{s}.o", .{test_name});
        const src_path = b.fmt("riscv_tests/{s}.S", .{test_name});
        const march = if (needsRv32imaZicsr(test_name)) "rv32ima_zicsr" else "rv32im";
        const test_txt = getTestTxt(test_name);

        const compile_test = b.addSystemCommand(&.{gcc});
        compile_test.setCwd(tests_root);
        compile_test.step.dependOn(&compile_start.step);
        link_fw.step.dependOn(&compile_test.step);
        compile_test.addArgs(&.{ "-c", "-mabi=ilp32" });
        compile_test.addArg(b.fmt("-march={s}", .{march}));
        compile_test.addArgs(&.{ "-o" });
        compile_test.addArg(obj_path);
        compile_test.addArg(b.fmt("-DTEST_FUNC_NAME={s}", .{test_name}));
        compile_test.addArg(b.fmt("-DTEST_FUNC_TXT=\"{s}\"", .{test_txt}));
        compile_test.addArg(b.fmt("-DTEST_FUNC_RET={s}_ret", .{test_name}));
        compile_test.addArg(src_path);

        object_paths.append(b.allocator, obj_path) catch @panic("OOM");
    }

    for (object_paths.items) |obj_path| {
        link_fw.addArg(obj_path);
    }
    link_fw.addArg("-lgcc");

    const to_bin = b.addSystemCommand(&.{objcopy});
    to_bin.setCwd(tests_root);
    to_bin.step.dependOn(&link_fw.step);
    to_bin.addArgs(&.{ "-O", "binary" });
    to_bin.addArg(firmware_elf);
    to_bin.addArg(firmware_bin);

    const dump_elf = b.addSystemCommand(&.{objdump});
    dump_elf.setCwd(tests_root);
    dump_elf.step.dependOn(&link_fw.step);
    dump_elf.addArgs(&.{ "-s", "-d" });
    dump_elf.addArg(firmware_elf);
    const firmware_lst = dump_elf.captureStdOut();
    const install_firmware_lst = b.addInstallFileWithDir(firmware_lst, .{ .custom = firmware_dir_path }, "firmware.lst");
    b.getInstallStep().dependOn(&install_firmware_lst.step);

    const dump_start = b.addSystemCommand(&.{objdump});
    dump_start.setCwd(tests_root);
    dump_start.step.dependOn(&compile_start.step);
    dump_start.addArgs(&.{ "-s", "-d" });
    dump_start.addArg(start_o);
    const start_lst = dump_start.captureStdOut();
    const install_start_lst = b.addInstallFileWithDir(start_lst, .{ .custom = firmware_dir_path }, "start.lst");
    b.getInstallStep().dependOn(&install_start_lst.step);

    const all_step = b.step("all", "Build tests firmware from riscv_tests/*.S");
    all_step.dependOn(&to_bin.step);
    all_step.dependOn(&install_firmware_lst.step);
    all_step.dependOn(&install_start_lst.step);

    const tests_step = b.step("tests", "Alias for all");
    tests_step.dependOn(all_step);

    const build_root_ritz = b.addSystemCommand(&.{ "zig", "build", "--summary", "all" });
    build_root_ritz.setCwd(repo_root);

    const run_cmd = b.addSystemCommand(&.{root_ritz_path});
    run_cmd.setCwd(tests_root);
    run_cmd.step.dependOn(&to_bin.step);
    run_cmd.step.dependOn(&build_root_ritz.step);
    run_cmd.addArgs(&.{ "-l", "0x20000", "-f", firmware_bin });

    const run_step = b.step("run", "Run ritz with generated tests firmware.bin");
    run_step.dependOn(&run_cmd.step);

    const tests_run_step = b.step("tests-run", "Alias for run");
    tests_run_step.dependOn(run_step);

    b.default_step.dependOn(all_step);

    const clean_step = b.step("clean", "Remove generated test artifacts");
    const clean_impl = CleanPatternsStep.create(b);
    clean_step.dependOn(&clean_impl.step);

    const tests_clean_step = b.step("tests-clean", "Alias for clean");
    tests_clean_step.dependOn(clean_step);
}
