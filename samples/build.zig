const std = @import("std");
const Target = @import("std").Target;
const Feature = @import("std").Target.Cpu.Feature;

const CleanDirContentsStep = struct {
    step: std.Build.Step,
    dir_path: []const u8,

    fn create(b: *std.Build, dir_path: []const u8) *CleanDirContentsStep {
        const self = b.allocator.create(CleanDirContentsStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = b.fmt("clean {s}", .{dir_path}),
                .owner = b,
                .makeFn = make,
            }),
            .dir_path = dir_path,
        };
        return self;
    }

    fn deleteEntry(dir: *std.fs.Dir, entry_name: []const u8, entry_kind: std.fs.Dir.Entry.Kind) void {
        switch (entry_kind) {
            .directory => {
                dir.deleteTree(entry_name) catch |err| {
                    std.log.warn("clean: unable to remove directory '{s}': {s}", .{ entry_name, @errorName(err) });
                };
            },
            else => {
                dir.deleteFile(entry_name) catch |err| {
                    std.log.warn("clean: unable to remove file '{s}': {s}", .{ entry_name, @errorName(err) });
                };
            },
        }
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        const self: *CleanDirContentsStep = @fieldParentPtr("step", step);

        var dir = std.fs.cwd().openDir(self.dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            deleteEntry(&dir, entry.name, entry.kind);
        }
    }
};

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn findFirstProgram(
    b: *std.Build,
    candidates: []const []const u8,
    search_paths: []const []const u8,
) ?[]const u8 {
    for (candidates) |program_name| {
        const found = b.findProgram(&.{program_name}, search_paths) catch null;
        if (found != null) return found;
    }
    return null;
}

fn addCleanDir(
    b: *std.Build,
    clean_step: *std.Build.Step,
    dir_path: []const u8,
) void {
    const clean_dir = CleanDirContentsStep.create(b, dir_path);
    clean_step.dependOn(&clean_dir.step);
}

fn addFirmware(
    b: *std.Build,
    firmware_name: []const u8,
    has_main_zig: bool,
    has_start_asm: bool,
    target: std.Build.ResolvedTarget,
    gnu_objcopy: ?[]const u8,
    gnu_objdump: ?[]const u8,
    run_selection: ?[]const u8,
    run_all_step: *std.Build.Step,
    lst_all_step: *std.Build.Step,
) bool {
    const root_source_path = b.fmt("{s}/src/main.zig", .{firmware_name});
    const start_asm_path = b.fmt("{s}/src/start.S", .{firmware_name});
    const linker_script_path = b.fmt("{s}/src/linker.ld", .{firmware_name});
    const module_root_source_path = if (has_main_zig) root_source_path else "empty.zig";

    const firmware = b.addExecutable(.{
        .name = firmware_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(module_root_source_path),
            .target = target,
            .optimize = .ReleaseSmall,
        }),
    });
    if (has_start_asm) {
        firmware.addAssemblyFile(b.path(start_asm_path));
    }
    firmware.setLinkerScript(b.path(linker_script_path));

    var copy_bin_step: ?*std.Build.Step = null;
    if (gnu_objcopy) |objcopy_path| {
        const bin_filename = b.fmt("{s}.bin", .{firmware_name});
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
    }

    var copy_lst_step: ?*std.Build.Step = null;
    if (gnu_objdump) |objdump_path| {
        const lst_filename = b.fmt("{s}.lst", .{firmware_name});
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
    }

    const ritz_exe = b.addSystemCommand(&.{
        "..\\zig-out\\bin\\ritz.exe",
        "-l",
        "0x2000",
        "-f",
        b.fmt(".\\zig-out\\bin\\{s}.bin", .{firmware_name}),
    });
    if (copy_bin_step) |step| {
        ritz_exe.step.dependOn(step);
    } else {
        ritz_exe.step.dependOn(&firmware.step);
    }

    const run_step_name = b.fmt("run-{s}", .{firmware_name});
    const run_step_desc = b.fmt("Run ritz with the generated {s}.bin", .{firmware_name});
    const run_step = b.step(run_step_name, run_step_desc);
    run_step.dependOn(&ritz_exe.step);

    const selected_for_run = if (run_selection) |selected_name|
        std.mem.eql(u8, selected_name, firmware_name)
    else
        true;
    if (selected_for_run) {
        run_all_step.dependOn(&ritz_exe.step);
    }

    const lst_step_name = b.fmt("lst-{s}", .{firmware_name});
    const lst_step_desc = b.fmt("Generate {s}.lst from firmware ELF using GNU objdump", .{firmware_name});
    const lst_step = b.step(lst_step_name, lst_step_desc);
    if (copy_lst_step) |step| {
        lst_step.dependOn(step);
        lst_all_step.dependOn(step);
    } else {
        lst_step.dependOn(&firmware.step);
        lst_all_step.dependOn(&firmware.step);
    }

    return selected_for_run;
}

pub fn build(b: *std.Build) void {
    const features = Target.riscv.Feature;
    var disabled_features = Feature.Set.empty;
    var enabled_features = Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(features.a));
    disabled_features.addFeature(@intFromEnum(features.c));
    disabled_features.addFeature(@intFromEnum(features.d));
    disabled_features.addFeature(@intFromEnum(features.e));
    disabled_features.addFeature(@intFromEnum(features.f));
    enabled_features.addFeature(@intFromEnum(features.m));

    const target = b.resolveTargetQuery(.{
        .cpu_arch = Target.Cpu.Arch.riscv32,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    });

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

    const gnu_objdump = findFirstProgram(b, &objdump_candidates, &risctools_search_paths);
    const gnu_objcopy = findFirstProgram(b, &objcopy_candidates, &risctools_search_paths);
    const run_selection = b.option([]const u8, "firmware", "Firmware name to run with `zig build run` (e.g. stand01)");

    if (gnu_objcopy == null) {
        std.log.warn("GNU objcopy not found; .bin generation and run steps will not have binary artifacts", .{});
    }
    if (gnu_objdump == null) {
        std.log.warn("GNU objdump not found; .lst generation steps will be skipped", .{});
    }

    const run_all_step = b.step("run", "Run ritz_exe for all firmware bins");
    const lst_all_step = b.step("lst", "Generate .lst files for all firmware ELFs");
    const clean_step = b.step("clean", "Delete all .zig-cache and zig-out directories");

    addCleanDir(b, clean_step, ".zig-cache");
    addCleanDir(b, clean_step, "zig-out");

    var firmware_count: usize = 0;
    var selected_firmware_found = false;

    var dir = std.fs.cwd().openDir(".", .{ .iterate = true }) catch |err| {
        std.log.err("failed to open workspace root for firmware discovery: {s}", .{@errorName(err)});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "stand")) continue;

        addCleanDir(b, clean_step, b.fmt("{s}/.zig-cache", .{entry.name}));
        addCleanDir(b, clean_step, b.fmt("{s}/zig-out", .{entry.name}));

        const root_source_path = b.fmt("{s}/src/main.zig", .{entry.name});
        const start_asm_path = b.fmt("{s}/src/start.S", .{entry.name});
        const linker_script_path = b.fmt("{s}/src/linker.ld", .{entry.name});
        const has_main_zig = fileExists(root_source_path);
        const has_start_asm = fileExists(start_asm_path);
        if (!fileExists(linker_script_path) or (!has_main_zig and !has_start_asm)) continue;

        const selected_match = addFirmware(
            b,
            entry.name,
            has_main_zig,
            has_start_asm,
            target,
            gnu_objcopy,
            gnu_objdump,
            run_selection,
            run_all_step,
            lst_all_step,
        );
        selected_firmware_found = selected_firmware_found or selected_match;
        firmware_count += 1;
    }

    if (firmware_count == 0) {
        std.log.warn("no firmware folders discovered (expected stand*/src/linker.ld + one of src/main.zig or src/start.S)", .{});
    }

    if (run_selection) |selected_name| {
        if (!selected_firmware_found) {
            std.log.err("-Dfirmware={s} did not match any discovered firmware", .{selected_name});
            std.process.exit(1);
        }
    }
}
