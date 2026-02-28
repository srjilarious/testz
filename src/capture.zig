const std = @import("std");
const builtin = @import("builtin");

// POSIX pipe/dup/dup2 is available on Linux, macOS, and other POSIX-like systems.
// Windows requires a different approach (CreatePipe + SetStdHandle) — not yet implemented.
const is_posix = switch (builtin.os.tag) {
    .linux, .macos, .ios, .tvos, .watchos, .freebsd, .openbsd, .netbsd, .dragonfly, .solaris, .illumos, .haiku => true,
    else => false,
};

/// The stdout and stderr content captured from a single test run.
/// Caller must call deinit() when done.
pub const CapturedOutput = struct {
    stdout: []u8,
    stderr: []u8,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *CapturedOutput) void {
        self.alloc.free(self.stdout);
        self.alloc.free(self.stderr);
    }
};

/// Captures all output written to file descriptors 1 (stdout) and 2 (stderr)
/// between begin() and end() at the OS level.  Works for any output path:
/// Zig writers, C library calls, subprocess output piped through the process, etc.
///
/// Usage:
///   var cap = try OutputCapture.begin();
///   runCodeThatPrintsStuff();
///   var out = try cap.end(alloc);
///   defer out.deinit();
///
/// Limitation: if the captured code writes more than the OS pipe buffer (~64 KB
/// on Linux) without returning, the write will block and deadlock because we
/// are single-threaded and the reader runs after the function returns.
/// For typical test diagnostic output this is not a concern.
///
/// On unsupported platforms (e.g. Windows) begin()/end() are no-ops that
/// return empty slices.
pub const OutputCapture = if (is_posix) struct {
    saved_stdout: std.posix.fd_t,
    saved_stderr: std.posix.fd_t,
    stdout_read: std.posix.fd_t,
    stderr_read: std.posix.fd_t,

    const Self = @This();

    pub fn begin() !Self {
        const posix = std.posix;

        const stdout_pipe = try posix.pipe();
        errdefer {
            posix.close(stdout_pipe[0]);
            posix.close(stdout_pipe[1]);
        }

        const stderr_pipe = try posix.pipe();
        errdefer {
            posix.close(stderr_pipe[0]);
            posix.close(stderr_pipe[1]);
        }

        const saved_stdout = try posix.dup(posix.STDOUT_FILENO);
        errdefer posix.close(saved_stdout);

        const saved_stderr = try posix.dup(posix.STDERR_FILENO);
        errdefer posix.close(saved_stderr);

        // Redirect fd 1 → stdout pipe write end, fd 2 → stderr pipe write end.
        try posix.dup2(stdout_pipe[1], posix.STDOUT_FILENO);
        errdefer posix.dup2(saved_stdout, posix.STDOUT_FILENO) catch {};

        try posix.dup2(stderr_pipe[1], posix.STDERR_FILENO);

        // Close the original write-end fds; fd 1/2 now point to them via dup2.
        posix.close(stdout_pipe[1]);
        posix.close(stderr_pipe[1]);

        return .{
            .saved_stdout = saved_stdout,
            .saved_stderr = saved_stderr,
            .stdout_read = stdout_pipe[0],
            .stderr_read = stderr_pipe[0],
        };
    }

    pub fn end(self: *Self, alloc: std.mem.Allocator) !CapturedOutput {
        const posix = std.posix;

        // Always close the read ends when we return, even on error.
        defer posix.close(self.stdout_read);
        defer posix.close(self.stderr_read);

        // Restoring fd 1/2 implicitly closes the pipe write ends that dup2
        // placed there, signalling EOF to the read ends.
        try posix.dup2(self.saved_stdout, posix.STDOUT_FILENO);
        try posix.dup2(self.saved_stderr, posix.STDERR_FILENO);
        posix.close(self.saved_stdout);
        posix.close(self.saved_stderr);

        const stdout_data = try drainPipe(self.stdout_read, alloc);
        errdefer alloc.free(stdout_data);

        const stderr_data = try drainPipe(self.stderr_read, alloc);

        return .{
            .stdout = stdout_data,
            .stderr = stderr_data,
            .alloc = alloc,
        };
    }

    fn drainPipe(fd: std.posix.fd_t, alloc: std.mem.Allocator) ![]u8 {
        var list: std.ArrayListUnmanaged(u8) = .{};
        errdefer list.deinit(alloc);
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = try std.posix.read(fd, &buf);
            if (n == 0) break;
            try list.appendSlice(alloc, buf[0..n]);
        }
        return list.toOwnedSlice(alloc);
    }
} else struct {
    const Self = @This();

    // No-op on unsupported platforms (Windows, WASM, …).
    pub fn begin() !Self {
        return .{};
    }

    pub fn end(self: *Self, alloc: std.mem.Allocator) !CapturedOutput {
        _ = self;
        return .{
            .stdout = try alloc.dupe(u8, ""),
            .stderr = try alloc.dupe(u8, ""),
            .alloc = alloc,
        };
    }
};
