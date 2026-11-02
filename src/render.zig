const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const window_effects = @import("window_effects.zig");

const Server = types.Server;
const Output = types.Output;
const Client = types.Client;
const LayerSurface = types.LayerSurface;

fn tBase(xdg: *c.wlr_xdg_toplevel) *c.wlr_xdg_surface {
    return @ptrCast(@alignCast(xdg.base));
}

fn tSurface(xdg: *c.wlr_xdg_toplevel) *c.wlr_surface {
    return @ptrCast(@alignCast(tBase(xdg).surface));
}

fn layerTree(ls: *LayerSurface) *c.wlr_scene_tree {
    return @ptrCast(@alignCast(ls.scene_layer.tree));
}

pub fn init(server: *Server) void {
    server.tearing_manager = null;
    server.explicit_sync_manager = null;
    server.explicit_sync_active = false;
    server.renderer_timeline = server.renderer.features.timeline;
    server.backend_timeline = server.backend.features.timeline;
    server.renderer_output_color_transform = server.renderer.features.output_color_transform;
    server.renderer_drm_fd = c.wlr_renderer_get_drm_fd(server.renderer);
    server.backend_drm_fd = c.wlr_backend_get_drm_fd(server.backend);

    if (c.wlr_tearing_control_manager_v1_create(server.display, 1)) |manager| {
        server.tearing_manager = @ptrCast(@alignCast(manager));
    } else {
        core.logInfo("tearing-control-v1: manager creation failed", .{});
    }

    if (!server.config.explicit_sync) {
        core.logInfo("explicit sync: disabled by config", .{});
    } else if (!server.renderer_timeline or !server.backend_timeline) {
        core.logInfo("explicit sync: unavailable (renderer timeline={} backend timeline={})", .{
            server.renderer_timeline,
            server.backend_timeline,
        });
    } else if (server.backend_drm_fd < 0) {
        core.logInfo("explicit sync: unavailable (not a DRM backend)", .{});
    } else {
        const sync_fd = if (server.renderer_drm_fd >= 0)
            server.renderer_drm_fd
        else
            server.backend_drm_fd;
        const manager = c.wlr_linux_drm_syncobj_manager_v1_create(
            server.display,
            1,
            sync_fd,
        );
        if (manager) |raw| {
            server.explicit_sync_manager = @ptrCast(@alignCast(raw));
            server.explicit_sync_active = true;
            core.logInfo("explicit sync: linux-drm-syncobj-v1 enabled", .{});
        } else {
            core.logInfo("explicit sync: manager creation failed", .{});
        }
    }

    core.logInfo("rendering: direct_scanout={} tearing={s} color_transform={}", .{
        server.config.direct_scanout,
        @tagName(server.config.tearing),
        server.renderer_output_color_transform,
    });
}

fn coversOutput(client: *Client, out: *Output) bool {
    return client.x == out.full.x and
        client.y == out.full.y and
        client.w == out.full.width and
        client.h == out.full.height;
}

fn hasContentBuffer(client: *Client) bool {
    const scene_buffer = client.content_buffer orelse return false;
    return scene_buffer.buffer != null;
}

fn canScanout(client: *Client, out: *Output) bool {
    if (!client.mapped or client.fullscreen == false) return false;
    if (!types.clientVisible(client, out)) return false;
    if (client.animating or client.anim_off_x != 0 or client.anim_off_y != 0) return false;
    if (types.effectiveClientOpacity(client) < 0.999) return false;
    if (!coversOutput(client, out)) return false;
    // wlr_buffer_is_opaque() is a false negative for many DMA-BUFs. The
    // scene's scanout check validates the actual plane format; requiring a
    // buffer here just avoids hiding the background before the first commit.
    return hasContentBuffer(client);
}

/// The last child of tree_fullscreen is the topmost fullscreen frame.
fn topmostFullscreen(server: *Server, out: *Output) ?*Client {
    var found: ?*Client = null;
    const tree = server.tree_fullscreen;
    var link: ?*c.wl_list = @ptrCast(tree.children.next);
    while (link) |lp| {
        if (@intFromPtr(lp) == @intFromPtr(&tree.children)) break;
        const node: *c.wlr_scene_node = @fieldParentPtr("link", lp);
        const next: ?*c.wl_list = @ptrCast(node.link.next);
        if (node.type == c.WLR_SCENE_NODE_TREE and node.enabled) {
            if (node.data) |raw| {
                const client: *Client = @ptrCast(@alignCast(raw));
                if (client.output == out and canScanout(client, out)) found = client;
            }
        }
        link = next;
    }
    return found;
}

fn disableLayerTree(ls: *LayerSurface) void {
    c.wlr_scene_node_set_enabled(&layerTree(ls).node, false);
}

fn enableLayerTree(ls: *LayerSurface) void {
    c.wlr_scene_node_set_enabled(&layerTree(ls).node, true);
}

fn hideScanoutBlockers(out: *Output, candidate: *Client) void {
    const server = out.server;
    c.wlr_scene_node_set_enabled(&out.bg_rect.node, false);

    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        const ls = server.layers[i] orelse continue;
        if (ls.output != out or !ls.mapped) continue;
        const layer_n: u32 = @intCast(ls.wlr.current.layer);
        if (layer_n < 3) disableLayerTree(ls);
    }

    i = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl == candidate or cl.output != out) continue;
        if (!types.clientVisible(cl, out)) continue;
        c.wlr_scene_node_set_enabled(&cl.frame.node, false);
    }

    if (candidate.blur_node) |node| {
        c.wlr_scene_node_set_enabled(node, false);
    }
}

fn enterScanout(out: *Output, candidate: *Client) void {
    hideScanoutBlockers(out, candidate);

    out.scanout_active = true;
    out.scanout_client = candidate;
    core.logInfo("direct scanout: {s} client '{s}'", .{
        core.outputName(out),
        candidate.app_id[0..candidate.app_id_len],
    });
}

fn exitScanout(out: *Output) void {
    if (!out.scanout_active) return;
    const server = out.server;
    const candidate = out.scanout_client;

    c.wlr_scene_node_set_enabled(&out.bg_rect.node, true);

    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        const ls = server.layers[i] orelse continue;
        if (ls.output != out or !ls.mapped) continue;
        const layer_n: u32 = @intCast(ls.wlr.current.layer);
        if (layer_n < 3) enableLayerTree(ls);
    }

    i = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.output != out) continue;
        c.wlr_scene_node_set_enabled(&cl.frame.node, types.clientVisible(cl, out));
    }

    if (candidate) |cl| {
        // Recompute blur visibility for the window that was on screen.
        if (cl.mapped) window_effects.applyClient(cl, false);
    }

    out.scanout_active = false;
    out.scanout_client = null;
    core.logInfo("direct scanout: {s} ended", .{core.outputName(out)});
}

pub fn refreshScanout(out: *Output) void {
    if (!out.server.config.direct_scanout) {
        exitScanout(out);
        return;
    }

    const candidate = topmostFullscreen(out.server, out);
    if (candidate == out.scanout_client) {
        // A layer or another client may have mapped since the last frame.
        // Re-hide the artifacts that would break the single-entry scanout.
        if (candidate) |cl| hideScanoutBlockers(out, cl);
        return;
    }
    exitScanout(out);
    if (candidate) |cl| enterScanout(out, cl);
}

fn tearingHint(client: *Client) bool {
    const manager = client.server.tearing_manager orelse return false;
    const hint = c.wlr_tearing_control_manager_v1_surface_hint_from_surface(
        manager,
        tSurface(client.xdg),
    );
    return hint == c.WP_TEARING_CONTROL_V1_PRESENTATION_HINT_ASYNC;
}

fn tearingCandidate(out: *Output) ?*Client {
    const server = out.server;
    if (server.config.tearing == .force) {
        const focused = server.focused orelse return topmostFullscreen(server, out);
        if (focused.output == out and types.clientVisible(focused, out)) return focused;
    }
    return topmostFullscreen(server, out);
}

fn tearingEligible(out: *Output) bool {
    const cfg = &out.server.config;
    const client = tearingCandidate(out) orelse return false;
    const rule = client.tearing;
    if (rule == .off) return false;
    // A per-window rule can opt in while the global default stays off.
    if (cfg.tearing == .off and rule != .on) return false;
    if (cfg.tearing != .force and !client.fullscreen) return false;
    return tearingHint(client);
}

fn hasBuffer(state: *const c.wlr_output_state) bool {
    return (state.committed & c.WLR_OUTPUT_STATE_BUFFER) != 0;
}

pub fn commitOutput(out: *Output) bool {
    const so = c.wlr_scene_get_scene_output(out.server.scene, out.wlr) orelse return false;
    var state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&state);
    defer c.wlr_output_state_finish(&state);

    if (!c.wlr_scene_output_build_state(so, &state, null)) return false;
    if (!hasBuffer(&state)) {
        return c.wlr_output_commit_state(out.wlr, &state);
    }

    var tearing = tearingEligible(out);
    if (tearing) {
        state.tearing_page_flip = true;
        if (!c.wlr_output_test_state(out.wlr, &state)) {
            state.tearing_page_flip = false;
            tearing = false;
            out.perf.tearing_failures += 1;
            if (out.perf.tearing_failures <= 3) {
                core.logInfo("tearing: async page flip unsupported on {s}; using normal flip", .{
                    core.outputName(out),
                });
            }
        }
    }

    if (tearing) out.perf.tearing_requests += 1;
    const ok = c.wlr_output_commit_state(out.wlr, &state);
    if (!ok and tearing) {
        out.perf.tearing_failures += 1;
        core.logInfo("tearing: page flip failed on {s}", .{core.outputName(out)});
    }
    return ok;
}

fn outputForScene(server: *Server, scene_output: *c.wlr_scene_output) ?*Output {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        if (out.scene_output == scene_output) return out;
    }
    return null;
}

fn onOutputSample(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const client: *Client = @fieldParentPtr("sample", listener.?);
    const event: *c.wlr_scene_output_sample_event = @ptrCast(@alignCast(data.?));
    if (!event.direct_scanout) return;
    if (outputForScene(client.server, event.output)) |out| {
        out.perf.scanout_frames += 1;
    }
}

pub fn trackClientBuffer(client: *Client) void {
    if (client.sample_linked) return;
    const scene_buffer = client.content_buffer orelse return;
    client.sample.notify = onOutputSample;
    c.wl_signal_add(&scene_buffer.events.output_sample, &client.sample);
    client.sample_linked = true;
}

pub fn untrackClientBuffer(client: *Client) void {
    if (!client.sample_linked) return;
    c.wl_list_remove(&client.sample.link);
    client.sample_linked = false;
}

pub fn onOutputPresent(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const out: *Output = @fieldParentPtr("present", listener.?);
    const event: *c.wlr_output_event_present = @ptrCast(@alignCast(data.?));
    if (!event.presented) return;
    out.perf.presented += 1;
    if ((event.flags & c.WLR_OUTPUT_PRESENT_ZERO_COPY) != 0) out.perf.zero_copy += 1;
    if ((event.flags & c.WLR_OUTPUT_PRESENT_VSYNC) != 0) out.perf.vsync += 1;
    const seq: u64 = @intCast(event.seq);
    if (out.perf.has_present_seq and seq > out.perf.last_seq + 1) {
        out.perf.missed += seq - out.perf.last_seq - 1;
    }
    out.perf.last_seq = seq;
    out.perf.has_present_seq = true;
}

pub fn clientDestroying(client: *Client) void {
    const out = client.output;
    if (out.scanout_client == client) exitScanout(out);
}

pub fn clientUnmapped(client: *Client) void {
    const out = client.output;
    if (out.scanout_client == client) exitScanout(out);
}

pub fn resetPerf(server: *Server) void {
    server.perf.reset();
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| out.perf.reset();
    }
}

pub fn tearHintName(client: *Client) []const u8 {
    return if (tearingHint(client)) "async" else "vsync";
}
