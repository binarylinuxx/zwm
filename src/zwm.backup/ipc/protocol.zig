const std = @import("std");

/// IPC message types for communication between zwm and zwmctl
pub const MessageType = enum(u32) {
    // Queries
    get_clients,
    get_clients_json,
    get_active_window,
    get_workspaces,
    get_workspaces_json,

    // Commands
    switch_workspace,

    // Responses
    response_ok,
    response_error,
    response_data,

    // Events (for event stream socket)
    event_workspace,
    event_activewindow,
    event_openwindow,
    event_closewindow,
    event_movewindow,
    event_focusedmon,
};

/// Maximum message size (64KB)
pub const MAX_MESSAGE_SIZE = 65536;

/// IPC message header
pub const MessageHeader = packed struct {
    msg_type: MessageType,
    payload_size: u32,
};

/// Client information for IPC response
pub const ClientInfo = struct {
    title: []const u8,
    app_id: []const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    workspace_id: u32,
    is_active: bool,
};

/// Workspace information for IPC response
pub const WorkspaceInfo = struct {
    id: u32,
    name: []const u8,
    client_count: u32,
    is_active: bool,
};

/// Get the IPC socket path for zwm (command socket)
pub fn getSocketPath(allocator: std.mem.Allocator) ![]const u8 {
    const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";
    return std.fmt.allocPrint(allocator, "{s}/zwm-ipc.sock", .{runtime_dir});
}

/// Get the event stream socket path for zwm
pub fn getEventSocketPath(allocator: std.mem.Allocator) ![]const u8 {
    const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";
    return std.fmt.allocPrint(allocator, "{s}/zwm-events.sock", .{runtime_dir});
}

/// Write a message header to a stream
pub fn writeHeader(writer: anytype, msg_type: MessageType, payload_size: u32) !void {
    const header = MessageHeader{
        .msg_type = msg_type,
        .payload_size = payload_size,
    };
    try writer.writeInt(u32, @intFromEnum(header.msg_type), .little);
    try writer.writeInt(u32, header.payload_size, .little);
}

/// Read a message header from a stream
pub fn readHeader(reader: anytype) !MessageHeader {
    const msg_type_int = try reader.readInt(u32, .little);
    const payload_size = try reader.readInt(u32, .little);
    return MessageHeader{
        .msg_type = @enumFromInt(msg_type_int),
        .payload_size = payload_size,
    };
}

/// Write a string-based message
pub fn writeMessage(writer: anytype, msg_type: MessageType, payload: []const u8) !void {
    try writeHeader(writer, msg_type, @intCast(payload.len));
    try writer.writeAll(payload);
}

/// Read message payload
pub fn readPayload(reader: anytype, allocator: std.mem.Allocator, size: u32) ![]u8 {
    if (size > MAX_MESSAGE_SIZE) return error.MessageTooLarge;
    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);
    try reader.readNoEof(buffer);
    return buffer;
}
