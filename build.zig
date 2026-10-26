const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    server_mod.addIncludePath(b.path("protocol"));

    const server = b.addExecutable(.{
        .name = "tessa",
        .root_module = server_mod,
    });
    server.root_module.linkSystemLibrary("wlroots-0.19", .{});
    server.root_module.linkSystemLibrary("wayland-server", .{});
    server.root_module.linkSystemLibrary("xkbcommon", .{});
    server.root_module.linkSystemLibrary("pixman-1", .{});
    server.root_module.linkSystemLibrary("m", .{ .use_pkg_config = .no });
    b.installArtifact(server);

    const panel_mod = b.createModule(.{
        .root_source_file = b.path("panel/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    panel_mod.addIncludePath(b.path("protocol"));
    panel_mod.addIncludePath(b.path("panel"));
    panel_mod.addCSourceFile(.{
        .file = b.path("protocol/layer-shell-protocol.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("protocol/xdg-shell-client-protocol.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("protocol/text-input-client-protocol.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("protocol/wlr-data-control-unstable-v1-client-protocol.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("protocol/wlr-screencopy-unstable-v1-client-protocol.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("panel/text.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    panel_mod.linkSystemLibrary("wayland-client", .{});
    panel_mod.linkSystemLibrary("cairo", .{});
    panel_mod.linkSystemLibrary("pangocairo-1.0", .{});
    panel_mod.linkSystemLibrary("xkbcommon", .{});
    panel_mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
    const panel = b.addExecutable(.{
        .name = "tessa-panel",
        .root_module = panel_mod,
    });
    b.installArtifact(panel);

    const ctl_mod = b.createModule(.{
        .root_source_file = b.path("src/ctl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const ctl = b.addExecutable(.{
        .name = "tessa-ctl",
        .root_module = ctl_mod,
    });
    b.installArtifact(ctl);

    const run_cmd = b.addRunArtifact(server);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Tessa compositor");
    run_step.dependOn(&run_cmd.step);
}
