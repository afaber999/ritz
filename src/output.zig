const std = @import("std");

pub const Output = struct {
    file: ?std.fs.File = null,

    pub fn deinit(self: *Output) void {
        if (self.file) |*f| {
            f.close();
            self.file = null;
        }
    }

    pub fn print(self: *Output, comptime fmt: []const u8, args: anytype) !void {
        var buf: [8192]u8 = undefined;
        const rendered = try std.fmt.bufPrint(&buf, fmt, args);
        if (self.file) |*f| {
            try f.writeAll(rendered);
        } else {
            var stdout = std.fs.File.stdout();
            try stdout.writeAll(rendered);
        }
    }

    pub fn redirect(self: *Output, fname: ?[]const u8) !void {
        if (self.file) |*f| {
            f.close();
            self.file = null;
        }

        if (fname) |name| {
            const cwd = std.fs.cwd();
            var file = cwd.openFile(name, .{ .mode = .read_write }) catch |err| switch (err) {
                error.FileNotFound => try cwd.createFile(name, .{ .read = true, .truncate = false }),
                else => return err,
            };
            try file.seekFromEnd(0);
            self.file = file;
        }
    }
};
