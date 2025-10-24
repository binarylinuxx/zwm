const std = @import("std");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addCustomProtocol(b.path("protocols/wlr-layer-shell-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocols/wlr-screencopy-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocols/xdg-output-unstable-v1.xml"));

    // Some of these versions may be out of date with what wlroots implements.
    // This is not a problem in practice though as long as zwm successfully compiles.
    // These versions control Zig code generation and have no effect on anything internal
    // to wlroots. Therefore, the only thing that can happen due to a version being too
    // old is that zwm fails to compile.
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);
    scanner.generate("xdg_wm_base", 2);
    scanner.generate("zxdg_decoration_manager_v1", 1);
    scanner.generate("zwp_tablet_manager_v2", 1);
    scanner.generate("zwlr_layer_shell_v1", 4);
    scanner.generate("zwlr_screencopy_manager_v1", 3);
    scanner.generate("zxdg_output_manager_v1", 3);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });
    const xkbcommon = b.dependency("xkbcommon", .{}).module("xkbcommon");
    const pixman = b.dependency("pixman", .{}).module("pixman");
    const wlroots = b.dependency("wlroots", .{}).module("wlroots");

    wlroots.addImport("wayland", wayland);
    wlroots.addImport("xkbcommon", xkbcommon);
    wlroots.addImport("pixman", pixman);

    // We need to ensure the wlroots include path obtained from pkg-config is
    // exposed to the wlroots module for @cImport() to work. This seems to be
    // the best way to do so with the current std.Build API.
    wlroots.resolved_target = target;
    wlroots.linkSystemLibrary("wlroots-0.18", .{});

    const zwm = b.addExecutable(.{
        .name = "zwm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zwm.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    zwm.linkLibC();

    zwm.root_module.addImport("wayland", wayland);
    zwm.root_module.addImport("xkbcommon", xkbcommon);
    zwm.root_module.addImport("wlroots", wlroots);
    zwm.linkSystemLibrary("glesv2");

    zwm.linkSystemLibrary("wayland-server");
    zwm.linkSystemLibrary("xkbcommon");
    zwm.linkSystemLibrary("pixman-1");
    zwm.linkSystemLibrary("egl");
    zwm.linkSystemLibrary("glesv2");

    b.installArtifact(zwm);
}
