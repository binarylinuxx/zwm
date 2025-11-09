const std = @import("std");
const wl = @import("wayland").server.wl;
const Toplevel = @import("toplevel.zig").Toplevel;

pub const Workspace = struct {
    id: u32,
    name: []const u8,
    master_toplevel: ?*Toplevel = null,
    link: wl.list.Link = undefined,
    server: *@import("../core/server.zig").Server,

    pub fn init(allocator: std.mem.Allocator, server: *@import("../core/server.zig").Server, id: u32, name: ?[]const u8) !*Workspace {
        const ws = try allocator.create(Workspace);
        ws.* = .{
            .id = id,
            .name = if (name) |n| try allocator.dupe(u8, n) else try std.fmt.allocPrint(allocator, "Workspace {d}", .{id}),
            .server = server,
        };
        return ws;
    }

    pub fn deinit(self: *Workspace, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.destroy(self);
    }

    pub fn getClientCount(self: *Workspace) u32 {
        var count: u32 = 0;
        var it = self.server.toplevels.iterator(.forward);
        while (it.next()) |toplevel| {
            if (toplevel.workspace == self) {
                count += 1;
            }
        }
        return count;
    }

    pub fn getToplevelIterator(self: *Workspace) ToplevelIterator {
        return ToplevelIterator{
            .workspace = self,
            .server_iter = self.server.toplevels.iterator(.forward),
        };
    }

    pub fn addToplevel(self: *Workspace, toplevel: *Toplevel) void {
        toplevel.workspace = self;
    }

    pub fn removeToplevel(self: *Workspace, toplevel: *Toplevel) void {
        if (self.master_toplevel == toplevel) {
            self.master_toplevel = null;
        }
        toplevel.workspace = null;
    }
};

pub const ToplevelIterator = struct {
    workspace: *Workspace,
    server_iter: wl.list.Head(Toplevel, .link).Iterator(.forward),

    pub fn next(self: *ToplevelIterator) ?*Toplevel {
        while (self.server_iter.next()) |toplevel| {
            if (toplevel.workspace == self.workspace) {
                return toplevel;
            }
        }
        return null;
    }
};
