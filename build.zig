const std = @import("std");

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
                    if (err == error.AccessDenied) return;
                    std.log.warn("clean: unable to remove directory '{s}': {s}", .{ entry_name, @errorName(err) });
                };
            },
            else => {
                dir.deleteFile(entry_name) catch |err| {
                    if (err == error.AccessDenied) return;
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

fn addCleanDir(b: *std.Build, clean_step: *std.Build.Step, dir_path: []const u8) void {
    const clean_dir = CleanDirContentsStep.create(b, dir_path);
    clean_step.dependOn(&clean_dir.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sample_name = b.option([]const u8, "sample", "Sample firmware name for run/samples-run (for example: stand01 or stand01.bin)");

    const exe = b.addExecutable(.{
        .name = "ritz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run ritz");
    run_step.dependOn(&run_cmd.step);

    const samples_build_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "--build-file",
        "build.zig",
        "--summary",
        "none",
    });
    samples_build_cmd.setCwd(b.path("samples"));
    samples_build_cmd.step.dependOn(b.getInstallStep());

    const samples_build_step = b.step("samples", "Build all sample firmware in samples/");
    samples_build_step.dependOn(&samples_build_cmd.step);

    if (sample_name) |name_raw| {
        const name = if (std.mem.endsWith(u8, name_raw, ".bin")) name_raw[0 .. name_raw.len - 4] else name_raw;
        run_cmd.step.dependOn(&samples_build_cmd.step);
        run_cmd.addArgs(&.{ "-f", b.fmt("samples/zig-out/bin/{s}.bin", .{name}) });
    }

    const samples_run_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "run",
        "--build-file",
        "build.zig",
    });
    samples_run_cmd.setCwd(b.path("samples"));
    samples_run_cmd.step.dependOn(b.getInstallStep());
    if (sample_name) |name_raw| {
        const name = if (std.mem.endsWith(u8, name_raw, ".bin")) name_raw[0 .. name_raw.len - 4] else name_raw;
        samples_run_cmd.addArg(b.fmt("-Dfirmware={s}", .{name}));
    }

    const samples_run_step = b.step("samples-run", "Build and run sample firmware via compiled ritz");
    samples_run_step.dependOn(&samples_run_cmd.step);

    const tests_build_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "--summary",
        "none",
    });
    tests_build_cmd.setCwd(b.path("tests"));
    tests_build_cmd.step.dependOn(b.getInstallStep());

    const tests_step = b.step("tests", "Build tests firmware in tests/");
    tests_step.dependOn(&tests_build_cmd.step);

    const tests_run_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "run",
        "--summary",
        "none",
    });
    tests_run_cmd.setCwd(b.path("tests"));
    tests_run_cmd.step.dependOn(&tests_build_cmd.step);

    const tests_run_step = b.step("tests-run", "Build and run tests firmware via compiled ritz");
    tests_run_step.dependOn(&tests_run_cmd.step);

    const tests_clean_cmd = b.addSystemCommand(&.{
        "zig",
        "build",
        "clean",
        "--summary",
        "none",
    });
    tests_clean_cmd.setCwd(b.path("tests"));

    const tests_clean_step = b.step("tests-clean", "Clean generated tests artifacts in tests/");
    tests_clean_step.dependOn(&tests_clean_cmd.step);

    const clean_step = b.step("clean", "Delete contents of cache/output directories");
    addCleanDir(b, clean_step, ".zig-cache");
    addCleanDir(b, clean_step, "zig-out");
    addCleanDir(b, clean_step, "samples/.zig-cache");
    addCleanDir(b, clean_step, "samples/zig-out");
}
