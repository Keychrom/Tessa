const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const scenefx = b.option(
        bool,
        "scenefx",
        "build with scenefx rounded corners and backdrop blur (requires scenefx-0.4 and GLES2)",
    ) orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "scenefx", scenefx);

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    server_mod.addIncludePath(b.path("protocol"));
    server_mod.addIncludePath(b.path("src"));
    server_mod.addOptions("build_options", build_options);
    server_mod.addCSourceFile(.{
        .file = b.path("src/regex_shim.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });

    const server = b.addExecutable(.{
        .name = "tessa",
        .root_module = server_mod,
    });
    server.pie = true;
    // Zig 0.16's self-hosted linker cannot handle the R_X86_64_PC64
    // relocations in glibc 2.43's .sframe sections (Arch/GCC 16). Use LLD
    // for every build mode, including Debug.
    server.use_llvm = true;
    server.use_lld = true;
    if (scenefx) server.root_module.linkSystemLibrary("scenefx-0.4", .{});
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
    panel_mod.addCSourceFile(.{
        .file = b.path("panel/notifications.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE", "-pthread" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("panel/media.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE", "-pthread" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("panel/tray.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE", "-pthread" },
    });
    panel_mod.addCSourceFile(.{
        .file = b.path("panel/audio.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE", "-pthread" },
    });
    panel_mod.linkSystemLibrary("wayland-client", .{});
    panel_mod.linkSystemLibrary("cairo", .{});
    panel_mod.linkSystemLibrary("pangocairo-1.0", .{});
    panel_mod.linkSystemLibrary("gio-2.0", .{});
    panel_mod.linkSystemLibrary("xkbcommon", .{});
    panel_mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
    const panel = b.addExecutable(.{
        .name = "tessa-panel",
        .root_module = panel_mod,
    });
    panel.pie = true;
    panel.use_llvm = true;
    panel.use_lld = true;
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
    ctl.pie = true;
    ctl.use_llvm = true;
    ctl.use_lld = true;
    b.installArtifact(ctl);

    const run_cmd = b.addRunArtifact(server);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Tessa compositor");
    run_step.dependOn(&run_cmd.step);
}
