const c = @import("c.zig").c;
const types = @import("types.zig");

const Server = types.Server;
const Client = types.Client;
const LayerSurface = types.LayerSurface;

pub const Origin = struct {
    x: f64,
    y: f64,
};

pub fn surfaceAt(server: *Server, lx: f64, ly: f64, sx: *f64, sy: *f64) ?*c.wlr_surface {
    const node_raw = c.wlr_scene_node_at(&server.scene.tree.node, lx, ly, sx, sy) orelse return null;
    const node: *c.wlr_scene_node = @ptrCast(@alignCast(node_raw));
    if (node.type != c.WLR_SCENE_NODE_BUFFER) return null;
    const buf = c.wlr_scene_buffer_from_node(node);
    const scene_surface_raw = c.wlr_scene_surface_try_from_buffer(buf) orelse return null;
    const scene_surface: *c.wlr_scene_surface = @ptrCast(@alignCast(scene_surface_raw));
    return @ptrCast(@alignCast(scene_surface.surface));
}

pub fn clientAt(server: *Server, lx: f64, ly: f64) ?*Client {
    var sx: f64 = 0;
    var sy: f64 = 0;
    const node = c.wlr_scene_node_at(&server.scene.tree.node, lx, ly, &sx, &sy) orelse return null;
    var cur: ?*c.wlr_scene_node = node;
    while (cur) |n| {
        if (n.data) |d| return @ptrCast(@alignCast(d));
        if (n.parent) |p| {
            const ptree: *c.wlr_scene_tree = @ptrCast(@alignCast(p));
            cur = &ptree.node;
        } else {
            cur = null;
        }
    }
    return null;
}

pub fn layerForSurface(server: *Server, surface: *c.wlr_surface) ?*LayerSurface {
    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        const layer = server.layers[i] orelse continue;
        if (layer.wlr.surface == surface) return layer;
    }
    return null;
}

const OriginContext = struct {
    target: *c.wlr_surface,
    origin: ?Origin = null,
};

fn originBuffer(buffer_raw: [*c]c.wlr_scene_buffer, sx: c_int, sy: c_int, data: ?*anyopaque) callconv(.c) void {
    const ctx: *OriginContext = @ptrCast(@alignCast(data.?));
    const buffer: *c.wlr_scene_buffer = @ptrCast(@alignCast(buffer_raw));
    const scene_surface_raw = c.wlr_scene_surface_try_from_buffer(buffer) orelse return;
    const scene_surface: *c.wlr_scene_surface = @ptrCast(@alignCast(scene_surface_raw));
    if (scene_surface.surface != ctx.target) return;
    ctx.origin = .{
        .x = @floatFromInt(sx),
        .y = @floatFromInt(sy),
    };
}

pub fn surfaceOrigin(server: *Server, surface: *c.wlr_surface) ?Origin {
    var ctx = OriginContext{ .target = surface };
    c.wlr_scene_node_for_each_buffer(&server.scene.tree.node, originBuffer, &ctx);
    return ctx.origin;
}
