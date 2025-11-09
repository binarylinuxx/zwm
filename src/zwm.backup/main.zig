const std = @import("std");
const posix = std.posix;
const mem = std.mem;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");

const xkb = @import("xkbcommon");

const gpa = std.heap.c_allocator;

const Server = @import("core/server.zig").Server;
const config_parser = @import("config_parser.zig");

pub fn main() anyerror!void {
    wlr.log.init(.debug, null);

    // Redirect logs to file
    const log_file = std.fs.cwd().createFile("log.log", .{ .read = true }) catch |err| {
        std.debug.print("Failed to create log file: {}\n", .{err});
        return err;
    };
    defer log_file.close();

    var file_writer = std.io.bufferedWriter(log_file.writer());
    _ = file_writer.writer();

    std.log.info("Starting ZWM compositor", .{});

    // Ensure config exists and get path
    const config_path = try config_parser.ensureConfigExists(gpa);
    defer gpa.free(config_path);

    // Load configuration
    const config = try config_parser.loadConfig(gpa, config_path);
    std.log.info("Loaded configuration from {s}", .{config_path});

    var server: Server = undefined;
    try server.init(config);
    defer server.deinit();

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);
    server.wayland_display = try gpa.dupe(u8, socket);
    std.log.info("Created Wayland socket: {s}", .{socket});

    if (std.os.argv.len >= 2) {
        const cmd = std.mem.span(std.os.argv[1]);
        var child = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", cmd }, gpa);
        var env_map = try std.process.getEnvMap(gpa);
        defer env_map.deinit();
        try env_map.put("WAYLAND_DISPLAY", socket);
        // Force server-side decorations for GTK apps
        try env_map.put("GTK_CSD", "0");
        // Enable Wayland for Firefox/Mozilla apps
        try env_map.put("MOZ_ENABLE_WAYLAND", "1");
        // Disable Firefox drawing its own titlebar (this forces it to use compositor decorations)
        try env_map.put("MOZ_DISABLE_WAYLAND_PROXY", "1");
        // Additional Firefox Wayland environment variables to enforce server-side decorations
        try env_map.put("MOZ_USE_XINPUT2", "1");
        // Force Firefox to request server-side decorations from compositor
        // Valid values: "client" (force CSD), "system" (request SSD from compositor)
        try env_map.put("MOZ_GTK_TITLEBAR_DECORATION", "system");
        // Additional Firefox environment variables for Wayland
        try env_map.put("MOZ_DBUS_REMOTE_CONTENT_ENABLED", "1");
        // Force server-side decorations for Qt apps
        try env_map.put("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
        try env_map.put("QT_QPA_PLATFORM", "wayland");
        child.env_map = &env_map;
        try child.spawn();
    }

    try server.backend.start();

    std.log.info("Running compositor on WAYLAND_DISPLAY={s}", .{socket});

    // Flush logs before running
    file_writer.flush() catch {};
    std.log.info("About to start server.wl_server.run()", .{});

    server.wl_server.run();
}