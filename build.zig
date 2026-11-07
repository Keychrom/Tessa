const std = @import("std");
const Translator = @import("translate_c").Translator;

fn pkgConfigExists(b: *std.Build, name: []const u8) bool {
    var exit_code: u8 = 1;
    _ = b.runAllowFail(&.{ "pkg-config", "--exists", name }, &exit_code, .ignore) catch return false;
    return exit_code == 0;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const scenefx = b.option(
        bool,
        "scenefx",
        "build with scenefx 0.5 rounded corners and backdrop blur (default: true; set false for the plain wlroots scene)",
    ) orelse true;
    const gpu = b.option(
        bool,
        "gpu",
        "build the opt-in EGL/GLES2 panel background renderer (default: true; set false for no EGL/GLES dependency)",
    ) orelse true;
    const shaders = b.option(
        bool,
        "shaders",
        "build opt-in per-window GLES2 shader effects (default: true; set false for no EGL/GLES dependency in the compositor)",
    ) orelse true;
    const with_panel = b.option(
        bool,
        "panel",
        "build and install tessa-panel, the Tessa shell panel (default: true; set false for a compositor-only build)",
    ) orelse true;

    const build_options = b.addOptions();
    build_options.addOption(bool, "scenefx", scenefx);
    build_options.addOption(bool, "gpu", gpu);
    build_options.addOption(bool, "shaders", shaders);
    build_options.addOption(bool, "panel", with_panel);

    const translate_c = b.dependency("translate_c", .{});

    // Zig 0.17 removed @cImport. Declare each C API surface as a header and
    // let the external translate-c package generate a Zig module for it.
    const server_libs: []const Translator.LinkSystemLib = if (scenefx) &.{
        .{ .name = "scenefx-0.5" },
        .{ .name = "wlroots-0.20" },
        .{ .name = "libinput" },
        .{ .name = "libdrm" },
        .{ .name = "wayland-server" },
        .{ .name = "xkbcommon" },
        .{ .name = "pixman-1" },
    } else &.{
        .{ .name = "wlroots-0.20" },
        .{ .name = "libinput" },
        .{ .name = "libdrm" },
        .{ .name = "wayland-server" },
        .{ .name = "xkbcommon" },
        .{ .name = "pixman-1" },
    };

    const server_c = Translator.init(translate_c, .{
        .name = "tessa_c",
        .c_source_file = b.path("src/c_import.h"),
        .target = target,
        .optimize = optimize,
        .link_system_libs = server_libs,
        .extra_args = if (scenefx) &.{"-DTESSA_SCENEFX=1"} else &.{"-DTESSA_SCENEFX=0"},
    });
    server_c.addIncludePath(b.path("protocol"));
    server_c.addIncludePath(b.path("src"));

    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    server_mod.addIncludePath(b.path("protocol"));
    server_mod.addIncludePath(b.path("src"));
    server_mod.addImport("c_translated", server_c.mod);
    server_mod.addOptions("build_options", build_options);
    if (scenefx) server_mod.linkSystemLibrary("scenefx-0.5", .{});
    server_mod.linkSystemLibrary("wlroots-0.20", .{});
    server_mod.linkSystemLibrary("libinput", .{});
    server_mod.linkSystemLibrary("drm", .{});
    server_mod.linkSystemLibrary("wayland-server", .{});
    server_mod.linkSystemLibrary("xkbcommon", .{});
    server_mod.linkSystemLibrary("pixman-1", .{});
    server_mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
    server_mod.addCSourceFile(.{
        .file = b.path("src/regex_shim.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    server_mod.addCSourceFile(.{
        .file = b.path("src/preview_source.c"),
        .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
    });
    if (shaders) {
        server_mod.addCSourceFile(.{
            .file = b.path("src/window_shader.c"),
            .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
        });
        server_mod.linkSystemLibrary("egl", .{});
        server_mod.linkSystemLibrary("glesv2", .{});
    }

    const server = b.addExecutable(.{
        .name = "tessa",
        .root_module = server_mod,
    });
    server.pie = true;
    // Zig's self-hosted linker cannot handle the R_X86_64_PC64 relocations
    // in glibc 2.43's .sframe sections (Arch/GCC 16). Use LLD for every
    // build mode, including Debug.
    server.use_llvm = true;
    server.use_lld = true;
    const server_install = b.addInstallArtifact(server, .{});
    b.getInstallStep().dependOn(&server_install.step);
    const compositor_step = b.step("compositor", "Build and install the Tessa compositor only");
    compositor_step.dependOn(&server_install.step);

    if (with_panel) {
        // Pango 1.58 renamed pangocairo-1.0.pc to pangocairo.pc. Keep the old
        // name for older distributions while accepting the new one.
        const pangocairo = if (pkgConfigExists(b, "pangocairo-1.0")) "pangocairo-1.0" else "pangocairo";
        const panel_libs: []const Translator.LinkSystemLib = &.{
            .{ .name = "wayland-client" },
            .{ .name = "cairo" },
            .{ .name = pangocairo },
            .{ .name = "gio-2.0" },
            .{ .name = "gdk-pixbuf-2.0" },
            .{ .name = "xkbcommon" },
        };
        const panel_c = Translator.init(translate_c, .{
            .name = "tessa_panel_c",
            .c_source_file = b.path("panel/c_import.h"),
            .target = target,
            .optimize = optimize,
            .link_system_libs = panel_libs,
        });
        panel_c.addIncludePath(b.path("protocol"));
        panel_c.addIncludePath(b.path("panel"));

        const panel_mod = b.createModule(.{
            .root_source_file = b.path("panel/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        panel_mod.addImport("c_translated", panel_c.mod);
        panel_mod.addIncludePath(b.path("protocol"));
        panel_mod.addIncludePath(b.path("panel"));
        panel_mod.addOptions("build_options", build_options);
        panel_mod.linkSystemLibrary("wayland-client", .{});
        panel_mod.linkSystemLibrary("cairo", .{});
        panel_mod.linkSystemLibrary(pangocairo, .{});
        panel_mod.linkSystemLibrary("gio-2.0", .{});
        panel_mod.linkSystemLibrary("gdk-pixbuf-2.0", .{});
        panel_mod.linkSystemLibrary("xkbcommon", .{});
        if (gpu) {
            panel_mod.linkSystemLibrary("egl", .{});
            panel_mod.linkSystemLibrary("glesv2", .{});
            panel_mod.linkSystemLibrary("wayland-egl", .{});
        }
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
            .file = b.path("protocol/ext-foreign-toplevel-list-v1-protocol.c"),
            .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
        });
        panel_mod.addCSourceFile(.{
            .file = b.path("protocol/ext-image-capture-source-v1-protocol.c"),
            .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
        });
        panel_mod.addCSourceFile(.{
            .file = b.path("protocol/ext-image-copy-capture-v1-protocol.c"),
            .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
        });
        panel_mod.addCSourceFile(.{
            .file = b.path("panel/preview.c"),
            .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
        });
        panel_mod.addCSourceFile(.{
            .file = b.path("panel/text.c"),
            .flags = &.{ "-std=c99", "-D_GNU_SOURCE" },
        });
        panel_mod.addCSourceFile(.{
            .file = b.path(if (gpu) "panel/gpu.c" else "panel/gpu_stub.c"),
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
        panel_mod.addCSourceFile(.{
            .file = b.path("panel/system.c"),
            .flags = &.{ "-std=c99", "-D_GNU_SOURCE", "-pthread" },
        });
        panel_mod.linkSystemLibrary("m", .{ .use_pkg_config = .no });
        const panel = b.addExecutable(.{
            .name = "tessa-panel",
            .root_module = panel_mod,
        });
        panel.pie = true;
        panel.use_llvm = true;
        panel.use_lld = true;
        const panel_install = b.addInstallArtifact(panel, .{});
        b.getInstallStep().dependOn(&panel_install.step);
        const panel_step = b.step("panel", "Build and install tessa-panel only");
        panel_step.dependOn(&panel_install.step);
    }

    const ctl_c = Translator.init(translate_c, .{
        .name = "tessa_ctl_c",
        .c_source_file = b.path("src/ctl_c_import.h"),
        .target = target,
        .optimize = optimize,
    });
    const ctl_mod = b.createModule(.{
        .root_source_file = b.path("src/ctl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    ctl_mod.addImport("c_translated", ctl_c.mod);
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
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the Tessa compositor");
    run_step.dependOn(&run_cmd.step);
}
