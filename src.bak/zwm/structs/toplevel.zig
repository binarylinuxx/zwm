const std = @import("std");

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

const Server = @import("../core/server.zig").Server;
const scenefx = @import("../render/scenefx.zig");

pub const Toplevel = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    workspace_link: wl.list.Link = undefined,
    xdg_toplevel: *wlr.XdgToplevel,
    scene_tree: *wlr.SceneTree,

    // Border-related fields
    border_container: *wlr.SceneTree,
    border_nodes: [4]*wlr.SceneRect = undefined, // top, right, bottom, left borders
    corner_nodes: [4]*wlr.SceneRect = undefined, // top-left, top-right, bottom-right, bottom-left corners

    x: i32 = 0,
    y: i32 = 0,
    workspace: ?*@import("workspace.zig").Workspace = null,

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
            _ = toplevel.xdg_toplevel.base.scheduleConfigure();
        }

        // Update border when window geometry changes
        const geometry = toplevel.xdg_toplevel.base.current.geometry;
        toplevel.updateBorder(toplevel.x, toplevel.y, geometry.width, geometry.height);

        // Apply corner radius to window buffers on each commit
        // This ensures subsurfaces and new buffers get rounded corners too
        toplevel.applyWindowCornerRadius();
    }

    pub fn updateBorder(toplevel: *Toplevel, x: i32, y: i32, width: i32, height: i32) void {
        const border_width = toplevel.server.config.border_width;
        const radius = toplevel.server.config.corner_radius;

        // Update border container position to match the toplevel
        toplevel.border_container.node.setPosition(x - border_width, y - border_width);

        // Create a single border frame rectangle that encompasses the full border area
        // Size: window size + 2*border_width in each dimension
        _ = toplevel.border_nodes[0].setSize(@intCast(width + 2 * border_width), @intCast(height + 2 * border_width));
        toplevel.border_nodes[0].node.setPosition(0, 0);

        // Apply corner radius to outer border frame
        if (radius > 0) {
            scenefx.setRectCornerRadius(toplevel.border_nodes[0], radius, .all);
        }

        // Clip out the inner window area to create a hollow border effect
        // The clipped region defines what area to REMOVE from the rectangle
        const clipped_region = scenefx.ClippedRegion{
            .area = wlr.Box{
                .x = border_width,  // Offset from border rect's origin
                .y = border_width,
                .width = width,     // Inner window dimensions
                .height = height,
            },
            .corner_radius = if (radius > 0) radius else 0,  // Match outer corners
            .corners = .all,
        };
        scenefx.setRectClippedRegion(toplevel.border_nodes[0], clipped_region);

        // The other border nodes can be set to zero size as placeholders since we're using single rectangle
        _ = toplevel.border_nodes[1].setSize(0, 0);
        toplevel.border_nodes[1].node.setPosition(0, 0);

        _ = toplevel.border_nodes[2].setSize(0, 0);
        toplevel.border_nodes[2].node.setPosition(0, 0);

        _ = toplevel.border_nodes[3].setSize(0, 0);
        toplevel.border_nodes[3].node.setPosition(0, 0);

        // The corner nodes are also not needed with single rectangle approach, set to zero
        _ = toplevel.corner_nodes[0].setSize(0, 0);
        toplevel.corner_nodes[0].node.setPosition(0, 0);

        _ = toplevel.corner_nodes[1].setSize(0, 0);
        toplevel.corner_nodes[1].node.setPosition(0, 0);

        _ = toplevel.corner_nodes[2].setSize(0, 0);
        toplevel.corner_nodes[2].node.setPosition(0, 0);

        _ = toplevel.corner_nodes[3].setSize(0, 0);
        toplevel.corner_nodes[3].node.setPosition(0, 0);
    }


    fn handleMap(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("map", listener);
        std.log.info("handleMap called for toplevel at {*}, xdg_toplevel at {*}", .{toplevel, toplevel.xdg_toplevel});

        // Make sure the border container is positioned correctly when the window is mapped
        const border_width = toplevel.server.config.border_width;
        toplevel.border_container.node.setPosition(toplevel.x - border_width, toplevel.y - border_width);

        // Apply corner radius to the window surface
        toplevel.applyWindowCornerRadius();

        // Apply blur to the window surface if enabled
        if (toplevel.server.config.blur.enabled) {
            toplevel.applyWindowBlur();
        }

        // Only add to list if not already present (defensive programming)
        if (!isToplevelInList(toplevel.server, toplevel)) {
            std.log.info("Adding new toplevel to server list", .{});
            toplevel.server.toplevels.prepend(toplevel);

            // Add to active workspace
            if (toplevel.server.active_workspace) |workspace| {
                workspace.addToplevel(toplevel);
                std.log.info("Added toplevel to workspace {d}", .{workspace.id});
            }
        } else {
            std.log.info("Toplevel already in server list, not adding again", .{});
        }

        std.log.info("Calling focusView for mapped toplevel", .{});
        toplevel.server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
        // Rearrange windows when a new one is mapped
        toplevel.server.arrangeWindows();
        std.log.info("handleMap completed for toplevel at {*}", .{toplevel});
    }
    
    // Helper function to check if toplevel is already in the server's list
    fn isToplevelInList(server: *Server, toplevel: *Toplevel) bool {
        var it = server.toplevels.iterator(.forward);
        while (it.next()) |list_toplevel| {
            if (list_toplevel == toplevel) {
                return true;
            }
        }
        return false;
    }

    fn applyWindowCornerRadius(toplevel: *Toplevel) void {
        const radius = toplevel.server.config.corner_radius;
        if (radius <= 0) return;

        // Use wlr_scene_node_for_each_buffer to find all buffers
        const Context = struct {
            radius: i32,
        };
        var ctx = Context{ .radius = radius };

        const callback = struct {
            fn apply(buffer: [*c]scenefx.c.struct_wlr_scene_buffer, _: i32, _: i32, data: ?*anyopaque) callconv(.C) void {
                const context: *Context = @ptrCast(@alignCast(data));
                scenefx.setBufferCornerRadius(buffer, context.radius, .all);
                std.log.info("Applied corner radius {} to buffer via for_each_buffer", .{context.radius});
            }
        }.apply;

        // This C function will call our callback for each buffer in the scene tree
        const c_node: [*c]scenefx.c.struct_wlr_scene_node = @ptrCast(&toplevel.scene_tree.node);
        scenefx.c.wlr_scene_node_for_each_buffer(c_node, callback, &ctx);
    }

    fn applyWindowBlur(toplevel: *Toplevel) void {
        const callback = struct {
            fn apply(buffer: [*c]scenefx.c.struct_wlr_scene_buffer, _: i32, _: i32, _: ?*anyopaque) callconv(.C) void {
                // Enable backdrop blur for this buffer
                scenefx.setBufferBackdropBlur(buffer, true);
                scenefx.setBufferBackdropBlurOptimized(buffer, true);
                scenefx.setBufferBackdropBlurIgnoreTransparent(buffer, true);
                std.log.info("Applied backdrop blur to buffer", .{});
            }
        }.apply;

        // Iterate through all buffers in the scene tree and apply blur
        const c_node: [*c]scenefx.c.struct_wlr_scene_node = @ptrCast(&toplevel.scene_tree.node);
        scenefx.c.wlr_scene_node_for_each_buffer(c_node, callback, null);
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("unmap", listener);
        std.log.info("handleUnmap called for toplevel at {*}, xdg_toplevel at {*}", .{ toplevel, toplevel.xdg_toplevel });

        // If this is the master window, clear the master reference
        if (toplevel.server.master_toplevel != null and toplevel.server.master_toplevel.? == toplevel) {
            std.log.info("Clearing master toplevel reference", .{});
            toplevel.server.master_toplevel = null;
        }

        // Remove from workspace
        if (toplevel.workspace) |workspace| {
            workspace.removeToplevel(toplevel);
            std.log.info("Removed toplevel from workspace {d}", .{workspace.id});
        }

        // Only remove from list if currently in the list (defensive programming)
        if (isToplevelInList(toplevel.server, toplevel)) {
            std.log.info("Removing toplevel from server list", .{});
            toplevel.link.remove();
        } else {
            std.log.info("Toplevel was not in server list, skipping removal", .{});
        }

        // Remove the xdg_toplevel specific listeners here (before destroy)
        // This prevents the assertion failure in wlroots destroy_xdg_toplevel
        std.log.info("Removing xdg_toplevel event listeners", .{});
        toplevel.request_move.link.remove();
        toplevel.request_resize.link.remove();

        // Rearrange remaining windows
        toplevel.server.arrangeWindows();
        std.log.info("handleUnmap completed for toplevel at {*}", .{ toplevel });
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("destroy", listener);
        std.log.info("handleDestroy called for toplevel at {*}, xdg_toplevel at {*}", .{ toplevel, toplevel.xdg_toplevel });

        // If this is the master window, clear the master reference so a new one can be selected
        if (toplevel.server.master_toplevel != null and toplevel.server.master_toplevel.? == toplevel) {
            std.log.info("Clearing master toplevel reference during destroy", .{});
            toplevel.server.master_toplevel = null;
        }

        // Cancel any ongoing animation for this toplevel
        var it = toplevel.server.animations.iterator(.forward);
        while (it.next()) |animation| {
            if (animation.toplevel == toplevel) {
                std.log.info("Removing animation for toplevel {*}", .{ toplevel });
                animation.link.remove();
                gpa.destroy(animation);
                break;
            }
        }

        std.log.info("Removing remaining event listeners for toplevel {*}", .{ toplevel });

        // Remove the listener objects from their respective signal lists
        // Note: request_move and request_resize are already removed in handleUnmap
        toplevel.commit.link.remove();
        toplevel.map.link.remove();
        toplevel.unmap.link.remove();
        toplevel.destroy.link.remove();

        // Null out the scene tree data to prevent use-after-free when cursor hovers over destroyed window
        std.log.info("Nulling scene tree data for toplevel {*}", .{ toplevel });
        toplevel.scene_tree.node.data = null;

        // Destroy border container to clean up ghost borders
        std.log.info("Destroying border container for toplevel {*}", .{ toplevel });
        toplevel.border_container.node.destroy();

        std.log.info("Destroying toplevel struct at {*}", .{ toplevel });
        gpa.destroy(toplevel);
        std.log.info("handleDestroy completed for toplevel", .{});
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

        const box = toplevel.xdg_toplevel.base.current.geometry;

        const border_x = toplevel.x + box.x + if (event.edges.right) box.width else 0;
        const border_y = toplevel.y + box.y + if (event.edges.bottom) box.height else 0;
        server.grab_x = server.cursor.x - @as(f64, @floatFromInt(border_x));
        server.grab_y = server.cursor.y - @as(f64, @floatFromInt(border_y));

        server.grab_box = box;
        server.grab_box.x += toplevel.x;
        server.grab_box.y += toplevel.y;
    }
};