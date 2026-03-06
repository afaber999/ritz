const std = @import("std");
const Target = @import("std").Target;
const Feature = @import("std").Target.Cpu.Feature;

pub fn build(b: *std.Build) void {
    const features = Target.riscv.Feature;
    var disabled_features = Feature.Set.empty;
    var enabled_features = Feature.Set.empty;

    // disable all CPU extensions
    disabled_features.addFeature(@intFromEnum(features.a));
    disabled_features.addFeature(@intFromEnum(features.c));
    disabled_features.addFeature(@intFromEnum(features.d));
    disabled_features.addFeature(@intFromEnum(features.e));
    disabled_features.addFeature(@intFromEnum(features.f));
    // except multiply
    enabled_features.addFeature(@intFromEnum(features.m));

    const objdump_candidates = [_][]const u8{
        "riscv64-unknown-elf-objdump",
        "riscv32-unknown-elf-objdump",
        "riscv32-esp-elf-objdump",
        "objdump",
    };
    const objcopy_candidates = [_][]const u8{
        "riscv64-unknown-elf-objcopy",
        "riscv32-unknown-elf-objcopy",
        "riscv32-esp-elf-objcopy",
        "objcopy",
    };

    const risctools_search_paths = [_][]const u8{
        "C:/msys64/mingw64/bin",
        "C:/msys64/ucrt64/bin",
        "C:/msys64/usr/bin",
        "/mingw64/bin",
        "/ucrt64/bin",
        "/usr/bin",
    };

    var gnu_objdump: ?[]const u8 = null;
    for (objdump_candidates) |program_name| {
        gnu_objdump = b.findProgram(&.{program_name}, &risctools_search_paths) catch null;
        if (gnu_objdump != null) break;
    }

    var gnu_objcopy: ?[]const u8 = null;
    for (objcopy_candidates) |program_name| {
        gnu_objcopy = b.findProgram(&.{program_name}, &risctools_search_paths) catch null;
        if (gnu_objcopy != null) break;
    }

    const target = b.resolveTargetQuery(.{ .cpu_arch = Target.Cpu.Arch.riscv32, .os_tag = Target.Os.Tag.freestanding, .abi = Target.Abi.none, .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 }, .cpu_features_sub = disabled_features, .cpu_features_add = enabled_features });

    const firmware = b.addExecutable(.{
        .name = "test01",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
        .strip = false,
    });

    firmware.setLinkerScript(b.path("src/linker.ld"));

    var warned_objcopy_missing = false;
    var copy_bin_step: ?*std.Build.Step = null;

    if (gnu_objcopy) |objcopy_path| {
        const bin_filename = b.fmt("{s}.bin", .{"test01"});
        const objcopy_run = b.addSystemCommand(&.{objcopy_path});
        objcopy_run.step.dependOn(&firmware.step);
        objcopy_run.addArgs(&.{ "-O", "binary" });
        objcopy_run.addFileArg(firmware.getEmittedBin());
        const bin_output = objcopy_run.addOutputFileArg(bin_filename);

        const install_bin = b.addInstallFileWithDir(
            bin_output,
            .{ .custom = "bin" },
            bin_filename,
        );
        b.getInstallStep().dependOn(&install_bin.step);
        install_bin.step.dependOn(&objcopy_run.step);
        copy_bin_step = &install_bin.step;
    } else if (!warned_objcopy_missing) {
        std.log.warn("GNU objcopy not found (tried: riscv64-unknown-elf-objcopy, riscv32-unknown-elf-objcopy, riscv32-esp-elf-objcopy, objcopy); skipping .bin generation", .{});
        warned_objcopy_missing = true;
    }

    var warned_objdump_missing = false;
    var copy_lst_step: ?*std.Build.Step = null;

    // Use GNU objdump to create an ELF listing file (.lst)
    if (gnu_objdump) |objdump_path| {
        const lst_filename = b.fmt("{s}.lst", .{"test01"});
        const objdump_run = b.addSystemCommand(&.{objdump_path});
        objdump_run.step.dependOn(&firmware.step);
        objdump_run.addArgs(&.{ "-dr", "-t", "-Mnumeric,no-aliases" });
        objdump_run.addFileArg(firmware.getEmittedBin());
        const lst_output = objdump_run.captureStdOut();

        const install_lst = b.addInstallFileWithDir(
            lst_output,
            .{ .custom = "bin" },
            lst_filename,
        );
        b.getInstallStep().dependOn(&install_lst.step);
        install_lst.step.dependOn(&objdump_run.step);
        copy_lst_step = &install_lst.step;
    } else if (!warned_objdump_missing) {
        std.log.warn("GNU objdump not found (tried: riscv64-unknown-elf-objdump, riscv32-unknown-elf-objdump, riscv32-esp-elf-objdump, objdump); skipping .lst generation", .{});
        warned_objdump_missing = true;
    }

    const rvddt = b.addSystemCommand(&.{
        "..\\rvddt.exe",
        "-l0x2000",
        "-f",
        ".\\zig-out\\bin\\test01.bin",
    });
    if (copy_bin_step) |step| {
        rvddt.step.dependOn(step);
    } else {
        rvddt.step.dependOn(&firmware.step);
    }

    const run_step = b.step("run", "Run rvddt with the generated test01.bin");
    run_step.dependOn(&rvddt.step);

    const lst_step = b.step("lst", "Generate test01.lst from firmware ELF using GNU objdump");
    if (copy_lst_step) |step| {
        lst_step.dependOn(step);
    } else {
        lst_step.dependOn(&firmware.step);
    }
}
