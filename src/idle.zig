const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;

const Inhibitor = struct {
    server: *Server,
    destroy: c.wl_listener,
};

pub fn init(server: *Server) void {
    server.idle_notifier = c.wlr_idle_notifier_v1_create(server.display);
    server.idle_inhibit_manager = c.wlr_idle_inhibit_v1_create(server.display);

    if (server.idle_inhibit_manager) |mgr| {
        server.new_idle_inhibitor.notify = onNewInhibitor;
        c.wl_signal_add(&mgr.events.new_inhibitor, &server.new_idle_inhibitor);
    }

    const power_raw = c.wlr_output_power_manager_v1_create(server.display);
    if (power_raw != null) {
        const power: *c.wlr_output_power_manager_v1 = @ptrCast(@alignCast(power_raw));
        server.output_power_manager = power;
        server.output_power_set_mode.notify = onPowerMode;
        c.wl_signal_add(&power.events.set_mode, &server.output_power_set_mode);
    }
}

fn onPowerMode(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event: *c.wlr_output_power_v1_set_mode_event = @ptrCast(@alignCast(data.?));
    var state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&state);
    defer c.wlr_output_state_finish(&state);
    c.wlr_output_state_set_enabled(&state, event.mode == c.ZWLR_OUTPUT_POWER_V1_MODE_ON);
    if (!c.wlr_output_commit_state(event.output, &state)) {
        core.logInfo("failed to apply output power mode", .{});
    }
}

pub fn notifyActivity(server: *Server) void {
    if (server.idle_notifier) |notifier| {
        c.wlr_idle_notifier_v1_notify_activity(notifier, server.seat);
    }
}

pub fn updateInhibit(server: *Server) void {
    if (server.idle_notifier) |notifier| {
        c.wlr_idle_notifier_v1_set_inhibited(notifier, server.locked or server.idle_inhibitor_count > 0);
    }
}

fn onDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const inhibitor: *Inhibitor = @fieldParentPtr("destroy", listener.?);
    const server = inhibitor.server;
    c.wl_list_remove(&inhibitor.destroy.link);
    if (server.idle_inhibitor_count > 0) server.idle_inhibitor_count -= 1;
    updateInhibit(server);
    c.free(inhibitor);
}

fn onNewInhibitor(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_idle_inhibitor", listener.?);

    const inhibitor = @as(*Inhibitor, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Inhibitor)).?)));
    inhibitor.server = server;
    const wlr_inhibitor: *c.wlr_idle_inhibitor_v1 = @ptrCast(@alignCast(data.?));
    inhibitor.destroy.notify = onDestroy;
    c.wl_signal_add(&wlr_inhibitor.events.destroy, &inhibitor.destroy);

    server.idle_inhibitor_count += 1;
    updateInhibit(server);
    core.logInfo("idle inhibitor added ({d} active)", .{server.idle_inhibitor_count});
}
