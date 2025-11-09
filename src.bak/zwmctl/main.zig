const std = @import("std");
const net = std.net;
const posix = std.posix;
const ipc = @import("shared");

const gpa = std.heap.c_allocator;

fn printUsage() void {
    std.debug.print(
        \\zwmctl - Control utility for ZWM compositor
        \\
        \\Usage: zwmctl [OPTIONS]
        \\
        \\Options:
        \\  --clients                    List all clients (human-readable)
        \\  --clients-json               List all clients (JSON format)
        \\  --active-window              Print active window title
        \\  --switch-workspace <id>      Switch to workspace (create if doesn't exist)
        \\  --get-workspaces             List all workspaces (human-readable)
        \\  --get-workspaces-json        List all workspaces (JSON format)
        \\  --help                       Show this help message
        \\
    , .{});
}

fn connectToServer() !net.Stream {
    const socket_path = try ipc.getSocketPath(gpa);
    defer gpa.free(socket_path);

    // Create Unix domain socket
    const sockfd = try posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0);
    errdefer posix.close(sockfd);

    // Connect to the Unix socket
    const addr = try std.net.Address.initUnix(socket_path);
    try posix.connect(sockfd, &addr.any, addr.getOsSockLen());

    return net.Stream{ .handle = sockfd };
}

fn sendCommand(msg_type: ipc.MessageType, payload: []const u8) !void {
    var stream = connectToServer() catch {
        std.debug.print("Error: Cannot connect to ZWM compositor\n", .{});
        std.debug.print("Make sure ZWM is running\n", .{});
        return error.ConnectionFailed;
    };
    defer stream.close();

    const writer = stream.writer();
    const reader = stream.reader();

    // Send request
    try ipc.writeMessage(writer, msg_type, payload);

    // Read response header
    const header = try ipc.readHeader(reader);

    // Read response payload
    const response = try ipc.readPayload(reader, gpa, header.payload_size);
    defer gpa.free(response);

    switch (header.msg_type) {
        .response_ok => {
            // Success with no data
        },
        .response_data => {
            // Print the data
            std.debug.print("{s}", .{response});
        },
        .response_error => {
            std.debug.print("Error: {s}\n", .{response});
            return error.ServerError;
        },
        else => {
            std.debug.print("Error: Unexpected response type\n", .{});
            return error.UnexpectedResponse;
        },
    }
}

pub fn main() !void {
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) {
        printUsage();
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "--help")) {
        printUsage();
        return;
    } else if (std.mem.eql(u8, command, "--clients")) {
        sendCommand(.get_clients, "") catch |err| {
            if (err != error.ConnectionFailed) return err;
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, command, "--clients-json")) {
        sendCommand(.get_clients_json, "") catch |err| {
            if (err != error.ConnectionFailed) return err;
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, command, "--active-window")) {
        sendCommand(.get_active_window, "") catch |err| {
            if (err != error.ConnectionFailed) return err;
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, command, "--get-workspaces")) {
        sendCommand(.get_workspaces, "") catch |err| {
            if (err != error.ConnectionFailed) return err;
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, command, "--get-workspaces-json")) {
        sendCommand(.get_workspaces_json, "") catch |err| {
            if (err != error.ConnectionFailed) return err;
            std.process.exit(1);
        };
    } else if (std.mem.eql(u8, command, "--switch-workspace")) {
        if (args.len < 3) {
            std.debug.print("Error: --switch-workspace requires a workspace ID\n", .{});
            std.process.exit(1);
        }
        const workspace_id = args[2];
        sendCommand(.switch_workspace, workspace_id) catch |err| {
            if (err != error.ConnectionFailed) return err;
            std.process.exit(1);
        };
    } else {
        std.debug.print("Error: Unknown command '{s}'\n\n", .{command});
        printUsage();
        std.process.exit(1);
    }
}
