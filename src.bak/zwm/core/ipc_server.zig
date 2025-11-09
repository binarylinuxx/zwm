const std = @import("std");
const posix = std.posix;
const net = std.net;
const wl = @import("wayland").server.wl;
const Server = @import("server.zig").Server;
const ipc_protocol = @import("../ipc/protocol.zig");

const gpa = std.heap.c_allocator;

pub fn setupIPCServer(server: *Server, _: *wl.EventLoop) !void {
    const socket_path = try ipc_protocol.getSocketPath(gpa);
    defer gpa.free(socket_path);

    // Remove old socket if it exists
    std.posix.unlink(socket_path) catch {};

    // Create Unix socket
    const address = try net.Address.initUnix(socket_path);
    const listener = try address.listen(.{
        .reuse_address = true,
    });

    server.ipc_socket = listener;
    std.log.info("IPC server listening on {s}", .{socket_path});

    // Spawn IPC server thread
    const thread = try std.Thread.spawn(.{}, ipcServerThread, .{server});
    thread.detach();
}

fn ipcServerThread(server: *Server) void {
    while (true) {
        if (server.ipc_socket) |*listener| {
            const client = listener.accept() catch |err| {
                std.log.err("Failed to accept IPC connection: {}", .{err});
                continue;
            };

            handleIPCClient(server, client.stream) catch |err| {
                std.log.err("Failed to handle IPC client: {}", .{err});
                client.stream.close();
            };
        } else {
            break;
        }
    }
}

fn handleIPCClient(server: *Server, stream: net.Stream) !void {
    defer stream.close();

    const reader = stream.reader();
    const writer = stream.writer();

    // Read request header
    const header = ipc_protocol.readHeader(reader) catch |err| {
        std.log.err("Failed to read IPC header: {}", .{err});
        return err;
    };

    // Read payload
    const payload = ipc_protocol.readPayload(reader, gpa, header.payload_size) catch |err| {
        std.log.err("Failed to read IPC payload: {}", .{err});
        return err;
    };
    defer gpa.free(payload);

    // Process command
    switch (header.msg_type) {
        .get_clients => try handleGetClients(server, writer, false),
        .get_clients_json => try handleGetClients(server, writer, true),
        .get_active_window => try handleGetActiveWindow(server, writer),
        .get_workspaces => try handleGetWorkspaces(server, writer, false),
        .get_workspaces_json => try handleGetWorkspaces(server, writer, true),
        .switch_workspace => try handleSwitchWorkspace(server, writer, payload),
        else => {
            try ipc_protocol.writeMessage(writer, .response_error, "Unknown command");
        },
    }
}

fn handleGetClients(server: *Server, writer: anytype, json: bool) !void {
    var output = std.ArrayList(u8).init(gpa);
    defer output.deinit();

    const out_writer = output.writer();

    if (json) {
        try out_writer.writeAll("[");
    }

    var first = true;
    var it = server.toplevels.iterator(.forward);
    while (it.next()) |toplevel| {
        const title = if (toplevel.xdg_toplevel.title) |t| std.mem.span(t) else "(no title)";
        const app_id = if (toplevel.xdg_toplevel.app_id) |a| std.mem.span(a) else "(no app id)";
        const geo = toplevel.xdg_toplevel.base.current.geometry;
        const workspace_id = if (toplevel.workspace) |ws| ws.id else 0;
        const is_active = (server.master_toplevel == toplevel);

        if (json) {
            if (!first) try out_writer.writeAll(",");
            try std.fmt.format(out_writer,
                \\{{"title":"{s}","app_id":"{s}","x":{d},"y":{d},"width":{d},"height":{d},"workspace_id":{d},"is_active":{}}}
            , .{ title, app_id, toplevel.x, toplevel.y, geo.width, geo.height, workspace_id, is_active });
        } else {
            try std.fmt.format(out_writer, "{s} ({s}) - {}x{} at {},{} - workspace {} {s}\n", .{
                title,
                app_id,
                geo.width,
                geo.height,
                toplevel.x,
                toplevel.y,
                workspace_id,
                if (is_active) "[ACTIVE]" else "",
            });
        }
        first = false;
    }

    if (json) {
        try out_writer.writeAll("]");
    }

    try ipc_protocol.writeMessage(writer, .response_data, output.items);
}

fn handleGetActiveWindow(server: *Server, writer: anytype) !void {
    const wlr = @import("wlroots");

    // Get the currently focused surface from the seat
    if (server.seat.keyboard_state.focused_surface) |surface| {
        // Try to get the XDG surface from the focused surface
        if (wlr.XdgSurface.tryFromWlrSurface(surface)) |xdg_surface| {
            if (xdg_surface.role_data.toplevel) |xdg_toplevel| {
                const title = if (xdg_toplevel.title) |t| std.mem.span(t) else "(no title)";
                var output = std.ArrayList(u8).init(gpa);
                defer output.deinit();
                try std.fmt.format(output.writer(), "{s}\n", .{title});
                try ipc_protocol.writeMessage(writer, .response_data, output.items);
                return;
            }
        }
    }

    // No active window
    try ipc_protocol.writeMessage(writer, .response_data, "(no active window)\n");
}

fn handleGetWorkspaces(server: *Server, writer: anytype, json: bool) !void {
    var output = std.ArrayList(u8).init(gpa);
    defer output.deinit();

    const out_writer = output.writer();

    if (json) {
        try out_writer.writeAll("[");
    }

    var first = true;
    var it = server.workspaces.iterator(.forward);
    while (it.next()) |workspace| {
        const is_active = (server.active_workspace == workspace);
        const client_count = workspace.getClientCount();

        if (json) {
            if (!first) try out_writer.writeAll(",");
            try std.fmt.format(out_writer,
                \\{{"id":{d},"name":"{s}","client_count":{d},"is_active":{}}}
            , .{ workspace.id, workspace.name, client_count, is_active });
        } else {
            try std.fmt.format(out_writer, "Workspace {d}: {s} ({d} clients) {s}\n", .{
                workspace.id,
                workspace.name,
                client_count,
                if (is_active) "[ACTIVE]" else "",
            });
        }
        first = false;
    }

    if (json) {
        try out_writer.writeAll("]");
    }

    try ipc_protocol.writeMessage(writer, .response_data, output.items);
}

fn handleSwitchWorkspace(server: *Server, writer: anytype, payload: []const u8) !void {
    const workspace_id = std.fmt.parseInt(u32, std.mem.trim(u8, payload, &std.ascii.whitespace), 10) catch {
        try ipc_protocol.writeMessage(writer, .response_error, "Invalid workspace ID");
        return;
    };

    server.switchToWorkspace(workspace_id) catch |err| {
        var error_msg = std.ArrayList(u8).init(gpa);
        defer error_msg.deinit();
        try std.fmt.format(error_msg.writer(), "Failed to switch workspace: {}", .{err});
        try ipc_protocol.writeMessage(writer, .response_error, error_msg.items);
        return;
    };

    try ipc_protocol.writeMessage(writer, .response_ok, "");
}
