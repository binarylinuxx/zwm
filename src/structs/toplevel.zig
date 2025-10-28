const std = @import("std");

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

const Server = @import("../core/server.zig").Server;

pub const Toplevel = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    xdg_toplevel: *wlr.XdgToplevel,
    scene_tree: *wlr.SceneTree,

    // Border-related fields
    border_container: *wlr.SceneTree,
    border_nodes: [4]*wlr.SceneRect = undefined, // top, right, bottom, left borders

    x: i32 = 0,
    y: i32 = 0,

    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
    map: wl.Listener(void) = .init(handleMap),
    unmap: wl.Listener(void) = .init(handleUnmap),
    destroy: wl.Listener(void) = .init(handleDestroy),
    request_move: wl.Listener(*wlr.XdgToplevel.event.Move) = .init(handleRequestMove),
    request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) = .init(handleRequestResize),

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const toplevel: *Toplevel = @fieldParentPtr("commit", listener);
        if (toplevel.xdg_toplevel.base.initial_commit) {
            _ = toplevel.xdg_toplevel.setSize(0, 0);
        }

        // Update border when window geometry changes
        var geometry: wlr.Box = undefined;
        toplevel.xdg_toplevel.base.getGeometry(&geometry);
        toplevel.updateBorder(toplevel.x, toplevel.y, geometry.width, geometry.height);
    }

    pub fn updateBorder(toplevel: *Toplevel, x: i32, y: i32, width: i32, height: i32) void {
        const border_width = toplevel.server.border_width;

        // Update border container position to match the toplevel
        toplevel.border_container.node.setPosition(x - border_width, y - border_width);

        // Update each border rectangle
        // Top border: spans width, height is border_width
        _ = toplevel.border_nodes[0].setSize(@as(c_int, @intCast(width + 2 * border_width)), @as(c_int, @intCast(border_width)));
        toplevel.border_nodes[0].node.setPosition(0, 0);

        // Right border: x is width, spans height, width is border_width
        _ = toplevel.border_nodes[1].setSize(@as(c_int, @intCast(border_width)), @as(c_int, @intCast(height + border_width))); // + border_width to cover corner
        toplevel.border_nodes[1].node.setPosition(@as(i32, @intCast(width + border_width)), border_width);

        // Bottom border: spans width, y is height, height is border_width
        _ = toplevel.border_nodes[2].setSize(@as(c_int, @intCast(width + 2 * border_width)), @as(c_int, @intCast(border_width)));
        toplevel.border_nodes[2].node.setPosition(0, @as(i32, @intCast(height + border_width)));

        // Left border: spans height, width is border_width
        _ = toplevel.border_nodes[3].setSize(@as(c_int, @intCast(border_width)), @as(c_int, @intCast(height + border_width))); // + border_width to cover corner
        toplevel.border_nodes[3].node.setPosition(0, border_width);
    }

    fn handleMap(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("map", listener);
        toplevel.server.toplevels.prepend(toplevel);
        toplevel.server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
        // Rearrange windows when a new one is mapped
        toplevel.server.arrangeWindows();
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("unmap", listener);
        
        // If this is the master window, clear the master reference
        if (toplevel.server.master_toplevel != null and toplevel.server.master_toplevel.? == toplevel) {
            toplevel.server.master_toplevel = null;
        }
        
        toplevel.link.remove();
        // Rearrange remaining windows
        toplevel.server.arrangeWindows();
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("destroy", listener);

        // If this is the master window, clear the master reference so a new one can be selected
        if (toplevel.server.master_toplevel != null and toplevel.server.master_toplevel.? == toplevel) {
            toplevel.server.master_toplevel = null;
        }

        // Cancel any ongoing animation for this toplevel
        var it = toplevel.server.animations.iterator(.forward);
        while (it.next()) |animation| {
            if (animation.toplevel == toplevel) {
                animation.link.remove();
                gpa.destroy(animation);
                break;
            }
        }

        toplevel.commit.link.remove();
        toplevel.map.link.remove();
        toplevel.unmap.link.remove();
        toplevel.destroy.link.remove();
        toplevel.request_move.link.remove();
        toplevel.request_resize.link.remove();

        // Destroy border container to clean up ghost borders
        toplevel.border_container.node.destroy();

        gpa.destroy(toplevel);
    }

    fn handleRequestMove(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
        _: *wlr.XdgToplevel.event.Move,
    ) void {
        const toplevel: *Toplevel = @fieldParentPtr("request_move", listener);
        const server = toplevel.server;
        server.grabbed_view = toplevel;
        server.cursor_mode = .move;
        server.grab_x = server.cursor.x - @as(f64, @floatFromInt(toplevel.x));
        server.grab_y = server.cursor.y - @as(f64, @floatFromInt(toplevel.y));
    }

    fn handleRequestResize(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
        event: *wlr.XdgToplevel.event.Resize,
    ) void {
        const toplevel: *Toplevel = @fieldParentPtr("request_resize", listener);
        const server = toplevel.server;

        server.grabbed_view = toplevel;
        server.cursor_mode = .resize;
        server.resize_edges = event.edges;

        var box: wlr.Box = undefined;
        toplevel.xdg_toplevel.base.getGeometry(&box);

        const border_x = toplevel.x + box.x + if (event.edges.right) box.width else 0;
        const border_y = toplevel.y + box.y + if (event.edges.bottom) box.height else 0;
        server.grab_x = server.cursor.x - @as(f64, @floatFromInt(border_x));
        server.grab_y = server.cursor.y - @as(f64, @floatFromInt(border_y));

        server.grab_box = box;
        server.grab_box.x += toplevel.x;
        server.grab_box.y += toplevel.y;
    }
};