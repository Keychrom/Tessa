const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Output = types.Output;
const Server = types.Server;

const INITIAL_RESTART_MS: i32 = 500;
const MAX_RESTART_MS: i32 = 8000;
const STABLE_RUN_MS: i64 = 10_000;

fn panelBin() [*:0]const u8 {
    if (c.getenv("TESSA_PANEL_BIN")) |p| return p;
    return "tessa-panel";
}

fn disarmRestart(out: *Output) void {
    if (out.panel.restart_timer) |timer| _ = c.wl_event_source_timer_update(timer, 0);
}

fn closePidfd(out: *Output) void {
    const panel = &out.panel;
    if (panel.source) |source| {
        _ = c.wl_event_source_remove(source);
        panel.source = null;
    }
    if (panel.fd >= 0) {
        _ = c.close(panel.fd);
        panel.fd = -1;
    }
}

pub fn initOutput(out: *Output) void {
    out.panel = .{ .fd = -1 };
    const loop = c.wl_display_get_event_loop(out.server.display);
    out.panel.restart_timer = c.wl_event_loop_add_timer(loop, onRestartTimer, out);
}

fn scheduleRestart(out: *Output) void {
    const panel = &out.panel;
    var delay = INITIAL_RESTART_MS;
    var i: u32 = 0;
    while (i < panel.failures and delay < MAX_RESTART_MS) : (i += 1) {
        delay *= 2;
    }
    if (delay > MAX_RESTART_MS) delay = MAX_RESTART_MS;
    panel.restart_at_ms = core.timeNowMs() + delay;
    if (panel.restart_timer) |timer| {
        _ = c.wl_event_source_timer_update(timer, delay);
    }
    core.logInfo("panel for {s} exited; restarting in {d} ms (failure {d})", .{
        core.outputName(out),
        delay,
        panel.failures,
    });
}

fn onPanelExit(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = fd;
    _ = mask;
    const out: *Output = @ptrCast(@alignCast(data.?));
    const panel = &out.panel;
    closePidfd(out);
    const pid = panel.pid;
    panel.pid = 0;
    if (!panel.supervised) return 0;

    const now = core.timeNowMs();
    if (panel.started_ms > 0 and now - panel.started_ms >= STABLE_RUN_MS) {
        panel.failures = 0;
    } else {
        panel.failures += 1;
    }
    core.logInfo("panel process {d} for {s} exited unexpectedly", .{ pid, core.outputName(out) });
    scheduleRestart(out);
    return 0;
}

fn onRestartTimer(data: ?*anyopaque) callconv(.c) c_int {
    const out: *Output = @ptrCast(@alignCast(data.?));
    if (!out.panel.supervised or out.panel.pid > 0) return 0;
    start(out);
    return 0;
}

/// Start (or restart) the panel for one output. The pidfd is attached to the
/// Wayland event loop, so exits are noticed even though SIGCHLD is ignored for
/// the rest of the compositor's child processes.
pub fn start(out: *Output) void {
    const server = out.server;
    if (!server.config.autostart_panel) return;
    if (c.getenv("TESSA_NO_PANEL") != null) return;

    const panel = &out.panel;
    if (panel.pid > 0) return;
    panel.supervised = true;
    disarmRestart(out);

    var name_buf: [128:0]u8 = undefined;
    core.copyZ(&name_buf, core.outputName(out));
    var make_buf: [128:0]u8 = undefined;
    core.copyZ(&make_buf, core.cstr(out.wlr.make));
    var model_buf: [128:0]u8 = undefined;
    core.copyZ(&model_buf, core.cstr(out.wlr.model));
    var serial_buf: [128:0]u8 = undefined;
    core.copyZ(&serial_buf, core.cstr(out.wlr.serial));
    if (!server.panel_notify_owner_assigned) {
        panel.notify_owner = true;
        server.panel_notify_owner_assigned = true;
    }

    const bin = panelBin();
    const pid = c.fork();
    if (pid < 0) {
        panel.failures += 1;
        scheduleRestart(out);
        core.logInfo("panel for {s}: fork failed", .{core.outputName(out)});
        return;
    }
    if (pid == 0) {
        core.resetChildSignals();
        _ = c.setenv("TESSA_PANEL_OUTPUT", &name_buf, 1);
        _ = c.setenv("TESSA_PANEL_OUTPUT_MAKE", &make_buf, 1);
        _ = c.setenv("TESSA_PANEL_OUTPUT_MODEL", &model_buf, 1);
        _ = c.setenv("TESSA_PANEL_OUTPUT_SERIAL", &serial_buf, 1);
        _ = c.setenv("TESSA_PANEL_NOTIFY_OWNER", if (panel.notify_owner) "1" else "0", 1);
        _ = c.execlp(bin, bin, @as(?[*:0]const u8, null));
        c._exit(127);
    }

    panel.pid = pid;
    panel.started_ms = core.timeNowMs();
    const pidfd = c.pidfd_open(pid, 0);
    if (pidfd < 0) {
        core.logInfo("panel for {s}: pidfd_open failed; crash recovery disabled", .{core.outputName(out)});
        return;
    }
    panel.fd = pidfd;
    const loop = c.wl_display_get_event_loop(server.display);
    const source = c.wl_event_loop_add_fd(
        loop,
        pidfd,
        @intCast(c.WL_EVENT_READABLE),
        onPanelExit,
        out,
    );
    if (source == null) {
        core.logInfo("panel for {s}: event source failed; crash recovery disabled", .{core.outputName(out)});
        _ = c.close(pidfd);
        panel.fd = -1;
        return;
    }
    panel.source = source;
    core.logInfo("panel started for {s} (pid {d}, notify_owner={})", .{
        core.outputName(out),
        pid,
        panel.notify_owner,
    });
}

/// Stop supervising and terminate the panel. Called when an output disappears
/// or the compositor shuts down. A deliberate stop is never restarted.
pub fn stop(out: *Output) void {
    const panel = &out.panel;
    panel.supervised = false;
    disarmRestart(out);
    closePidfd(out);
    if (panel.pid > 0) {
        _ = c.kill(panel.pid, c.SIGTERM);
        core.logInfo("panel stopped for {s} (pid {d})", .{ core.outputName(out), panel.pid });
        panel.pid = 0;
    }
    panel.started_ms = 0;
    panel.failures = 0;
}

pub fn deinitOutput(out: *Output) void {
    stop(out);
    if (out.panel.restart_timer) |timer| {
        _ = c.wl_event_source_remove(timer);
        out.panel.restart_timer = null;
    }
}

pub fn shutdown(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| deinitOutput(out);
    }
}

/// Apply a config reload to panel supervision. Enabling the panel starts it on
/// existing outputs; disabling it stops the supervised children.
pub fn reload(server: *Server) void {
    const want = server.config.autostart_panel and c.getenv("TESSA_NO_PANEL") == null;
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        if (want) {
            if (!out.panel.supervised) start(out);
        } else if (out.panel.supervised) {
            stop(out);
        }
    }
}
