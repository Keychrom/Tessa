const c = @import("c.zig").c;
const types = @import("types.zig");
const layout_helper = @import("layout_helper.zig");
const gestures = @import("gestures.zig");
const touch = @import("touch.zig");
const tablet = @import("tablet.zig");
const constraints = @import("constraints.zig");
const xim = @import("xim.zig");

const Server = types.Server;

/// Remove global and per-device listeners before wl_display_destroy().
/// wlroots asserts that its signal listener lists are empty when its globals
/// are destroyed; client-owned listeners are already gone by this point.
pub fn cleanupGlobals(server: *Server) void {
    layout_helper.deinit(server);
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        c.wl_list_remove(&out.frame.link);
        c.wl_list_remove(&out.request_state.link);
        c.wl_list_remove(&out.destroy.link);
    }
    c.wl_list_remove(&server.new_output.link);
    c.wl_list_remove(&server.new_layer_surface.link);
    if (server.output_manager != null) {
        c.wl_list_remove(&server.output_apply.link);
        c.wl_list_remove(&server.output_test.link);
    }

    i = 0;
    while (i < server.keyboards.len) : (i += 1) {
        const kb = server.keyboards[i] orelse continue;
        c.wl_list_remove(&kb.modifiers.link);
        c.wl_list_remove(&kb.key.link);
        c.wl_list_remove(&kb.keymap.link);
        c.wl_list_remove(&kb.destroy.link);
    }
    c.wl_list_remove(&server.new_input.link);
    c.wl_list_remove(&server.cursor_motion.link);
    c.wl_list_remove(&server.cursor_motion_absolute.link);
    c.wl_list_remove(&server.cursor_button.link);
    c.wl_list_remove(&server.cursor_axis.link);
    c.wl_list_remove(&server.cursor_frame.link);
    c.wl_list_remove(&server.request_cursor.link);
    c.wl_list_remove(&server.request_set_selection.link);
    c.wl_list_remove(&server.request_set_primary_selection.link);
    if (server.virtual_keyboard_manager != null) {
        c.wl_list_remove(&server.new_virtual_keyboard.link);
    }
    if (server.virtual_pointer_manager != null) {
        c.wl_list_remove(&server.new_virtual_pointer.link);
    }
    if (server.cursor_shape_manager != null) {
        c.wl_list_remove(&server.request_set_shape.link);
    }

    c.wl_list_remove(&server.new_xdg_toplevel.link);
    c.wl_list_remove(&server.new_xdg_popup.link);
    if (server.xdg_decoration_manager != null) {
        c.wl_list_remove(&server.new_toplevel_decoration.link);
    }
    if (server.xdg_activation != null) {
        c.wl_list_remove(&server.request_activate.link);
    }

    if (server.text_input_manager != null) {
        c.wl_list_remove(&server.new_text_input.link);
    }
    if (server.input_method_manager != null) {
        c.wl_list_remove(&server.new_input_method.link);
    }
    if (server.input_method != null) {
        c.wl_list_remove(&server.im_commit.link);
        c.wl_list_remove(&server.im_grab_keyboard.link);
        c.wl_list_remove(&server.im_destroy.link);
        c.wl_list_remove(&server.im_new_popup.link);
        if (server.im_grab != null) {
            c.wl_list_remove(&server.im_grab_destroy.link);
            server.im_grab = null;
        }
        server.input_method = null;
    }

    if (server.session_lock_manager != null) {
        c.wl_list_remove(&server.new_session_lock.link);
    }
    if (server.session_lock != null) {
        c.wl_list_remove(&server.new_lock_surface.link);
        c.wl_list_remove(&server.lock_unlock.link);
        c.wl_list_remove(&server.lock_destroy.link);
        server.session_lock = null;
    }

    if (server.idle_inhibit_manager != null) {
        c.wl_list_remove(&server.new_idle_inhibitor.link);
    }
    if (server.output_power_manager != null) {
        c.wl_list_remove(&server.output_power_set_mode.link);
    }

    gestures.cleanup(server);
    touch.cleanup(server);
    var ti: usize = 0;
    while (ti < server.touch_device_count) : (ti += 1) {
        const td = server.touch_devices[ti] orelse continue;
        c.wl_list_remove(&td.destroy.link);
        c.free(td);
        server.touch_devices[ti] = null;
    }
    server.touch_device_count = 0;
    tablet.cleanup(server);
    constraints.cleanup(server);
    xim.cleanup(server);

    if (server.sigint) |src| {
        _ = c.wl_event_source_remove(src);
        server.sigint = null;
    }
    if (server.sigterm) |src| {
        _ = c.wl_event_source_remove(src);
        server.sigterm = null;
    }
}
