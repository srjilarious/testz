const std = @import("std");
const builtin = @import("builtin");

// POSIX pipe/dup/dup2 is available on Linux and other POSIX-like systems.
// Windows requires a different approach (CreatePipe + SetStdHandle) — not yet implemented.
// Note: std.posix.pipe/dup/dup2/close were removed in Zig 0.16; use std.os.linux directly.
const is_posix = switch (builtin.os.tag) {
    .linux => true,
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
    const linux = std.os.linux;

    /// The capture in progress, if any, so a panic handler can put the real
    /// stdout/stderr back before printing the panic message.
    var active: ?Self = null;

    fn sysPipe() ![2]std.posix.fd_t {
        var fds: [2]i32 = undefined;
        const rc = linux.pipe(&fds);
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
        return .{ @intCast(fds[0]), @intCast(fds[1]) };
    }

    fn sysDup(fd: std.posix.fd_t) !std.posix.fd_t {
        const rc = linux.dup(@intCast(fd));
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
        return @intCast(rc);
    }

    fn sysDup2(old: std.posix.fd_t, new: std.posix.fd_t) !void {
        const rc = linux.dup2(@intCast(old), @intCast(new));
        if (linux.errno(rc) != .SUCCESS) return error.Unexpected;
    }

    fn sysClose(fd: std.posix.fd_t) void {
        _ = linux.close(@intCast(fd));
    }

    pub fn begin() !Self {
        const stdout_pipe = try sysPipe();
        errdefer {
            sysClose(stdout_pipe[0]);
            sysClose(stdout_pipe[1]);
        }

        const stderr_pipe = try sysPipe();
        errdefer {
            sysClose(stderr_pipe[0]);
            sysClose(stderr_pipe[1]);
        }

        const saved_stdout = try sysDup(std.posix.STDOUT_FILENO);
        errdefer sysClose(saved_stdout);

        const saved_stderr = try sysDup(std.posix.STDERR_FILENO);
        errdefer sysClose(saved_stderr);

        // Redirect fd 1 → stdout pipe write end, fd 2 → stderr pipe write end.
        try sysDup2(stdout_pipe[1], std.posix.STDOUT_FILENO);
        errdefer sysDup2(saved_stdout, std.posix.STDOUT_FILENO) catch {};

        try sysDup2(stderr_pipe[1], std.posix.STDERR_FILENO);

        // Close the original write-end fds; fd 1/2 now point to them via dup2.
        sysClose(stdout_pipe[1]);
        sysClose(stderr_pipe[1]);

        const self: Self = .{
            .saved_stdout = saved_stdout,
            .saved_stderr = saved_stderr,
            .stdout_read = stdout_pipe[0],
            .stderr_read = stderr_pipe[0],
        };
        active = self;
        return self;
    }

    pub fn end(self: *Self, alloc: std.mem.Allocator) !CapturedOutput {
        active = null;

        // Always close the read ends when we return, even on error.
        defer sysClose(self.stdout_read);
        defer sysClose(self.stderr_read);

        // Restoring fd 1/2 implicitly closes the pipe write ends that dup2
        // placed there, signalling EOF to the read ends.
        try sysDup2(self.saved_stdout, std.posix.STDOUT_FILENO);
        try sysDup2(self.saved_stderr, std.posix.STDERR_FILENO);
        sysClose(self.saved_stdout);
        sysClose(self.saved_stderr);

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
        var list: std.ArrayListUnmanaged(u8) = .empty;
        errdefer list.deinit(alloc);
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = try std.posix.read(fd, &buf);
            if (n == 0) break;
            try list.appendSlice(alloc, buf[0..n]);
        }
        return list.toOwnedSlice(alloc);
    }

    /// Called from a panic handler: if a capture is in progress, points fd 1/2
    /// back at the real stdout/stderr and forwards whatever the test wrote so
    /// far.  Without this the panic message goes into the capture pipe and is
    /// lost when the process aborts.  Doesn't allocate, since the allocator
    /// may be what panicked.  Returns true if a capture was in progress.
    pub fn restoreForPanic() bool {
        const fds = active orelse return false;
        active = null;

        // Restoring fd 1/2 closes the pipe write ends, so the drains below
        // hit EOF instead of blocking.
        _ = linux.dup2(@intCast(fds.saved_stdout), std.posix.STDOUT_FILENO);
        _ = linux.dup2(@intCast(fds.saved_stderr), std.posix.STDERR_FILENO);

        forwardPipe(fds.stdout_read, std.posix.STDOUT_FILENO);
        forwardPipe(fds.stderr_read, std.posix.STDERR_FILENO);
        return true;
    }

    fn forwardPipe(read_fd: std.posix.fd_t, out_fd: std.posix.fd_t) void {
        var buf: [4096]u8 = undefined;
        while (true) {
            const rc = linux.read(@intCast(read_fd), &buf, buf.len);
            if (linux.errno(rc) != .SUCCESS or rc == 0) return;
            writeAllFd(out_fd, buf[0..rc]);
        }
    }

    fn writeAllFd(fd: std.posix.fd_t, bytes: []const u8) void {
        var rest = bytes;
        while (rest.len > 0) {
            const rc = linux.write(@intCast(fd), rest.ptr, rest.len);
            if (linux.errno(rc) != .SUCCESS or rc == 0) return;
            rest = rest[rc..];
        }
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

    pub fn restoreForPanic() bool {
        return false;
    }
};
