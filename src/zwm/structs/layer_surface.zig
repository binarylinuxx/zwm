const std = @import("std");
const mem = std.mem;

const wl = @import("wayland").server.wl;
const zwlr = @import("wayland").server.zwlr;

const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

const Server = @import("../core/server.zig").Server;

pub const ExclusiveZone = struct {
    zone: i32 = 0,
    anchor: u32 = 0,
    margin_top: i32 = 0,
    margin_right: i32 = 0,
    margin_bottom: i32 = 0,
    margin_left: i32 = 0,

    pub fn hasExclusiveZone(self: ExclusiveZone) bool {
        return self.zone > 0;
    }

    pub fn getEffectiveZone(self: ExclusiveZone) i32 {
        return self.zone;
    }
};

pub const LayerSurface = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    layer_surface: *wlr.LayerSurfaceV1,
    scene_layer_surface: *wlr.SceneLayerSurfaceV1,
    popup_tree: *wlr.SceneTree,  // Separate tree for popups from layer surfaces
    configured: bool = false,
    exclusive_zone: ExclusiveZone = ExclusiveZone{},

    map: wl.Listener(void) = .init(handleMap),
    unmap: wl.Listener(void) = .init(handleUnmap),
    destroy: wl.Listener(*wlr.LayerSurfaceV1) = .init(handleDestroy),
    new_popup: wl.Listener(*wlr.XdgPopup) = .init(handleNewPopup),
    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),

    fn handleMap(listener: *wl.Listener(void)) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("map", listener);
        // Add to the server's list when mapped
        layer_surface.server.layer_surfaces.append(layer_surface);
        
        // Arrange windows if this layer surface has an exclusive zone
        if (layer_surface.exclusive_zone.hasExclusiveZone()) {
            layer_surface.server.arrangeWindows();
        }
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("unmap", listener);
        layer_surface.link.remove();
        
        // Arrange windows to reclaim space if this layer surface had an exclusive zone
        if (layer_surface.exclusive_zone.hasExclusiveZone()) {
            layer_surface.server.arrangeWindows();
        }
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("commit", listener);

        // Update exclusive zone information from pending state
        const pending = layer_surface.layer_surface.pending;
        layer_surface.exclusive_zone.zone = pending.exclusive_zone;

        // Construct anchor value from individual flags with correct bit positions
        layer_surface.exclusive_zone.anchor =
            (@as(u32, if (pending.anchor.top) 1 else 0)) |
            (@as(u32, if (pending.anchor.bottom) 2 else 0)) |
            (@as(u32, if (pending.anchor.left) 4 else 0)) |
            (@as(u32, if (pending.anchor.right) 8 else 0));

        layer_surface.exclusive_zone.margin_top = pending.margin.top;
        layer_surface.exclusive_zone.margin_right = pending.margin.right;
        layer_surface.exclusive_zone.margin_bottom = pending.margin.bottom;
        layer_surface.exclusive_zone.margin_left = pending.margin.left;

        // Only configure if not yet configured or if the surface needs reconfiguration
        if (!layer_surface.configured) {
            const output = layer_surface.layer_surface.output orelse {
                std.log.err("layer surface has no output on commit", .{});
                return;
            };

            // Get output dimensions
            var box: wlr.Box = undefined;
            layer_surface.server.output_layout.getBox(output, &box);

            // Use current (not pending) width/height if specified, otherwise use output size
            const current = layer_surface.layer_surface.current;
            const width = if (current.desired_width > 0) current.desired_width else @as(u32, @intCast(box.width));
            const height = if (current.desired_height > 0) current.desired_height else @as(u32, @intCast(box.height));

            // Ensure valid dimensions
            if (width == 0 or height == 0) {
                std.log.err("invalid layer surface dimensions: {}x{}", .{width, height});
                return;
            }

            // Configure with the determined size
            _ = layer_surface.layer_surface.configure(width, height);
            layer_surface.configured = true;
            
            // After configuration, we need to arrange windows if this layer surface has an exclusive zone
            if (layer_surface.exclusive_zone.hasExclusiveZone()) {
                layer_surface.server.arrangeWindows();
            }
        } else if (layer_surface.configured) {
            // If already configured and exclusive zone changed, rearrange windows
            layer_surface.server.arrangeWindows();
        }
        
        // Ensure the layer surface gets properly positioned according to its anchors
        // The scene layer surface should handle positioning automatically based on the layer surface's anchor settings,
        // but we need to make sure it's updated after changes
        _ = layer_surface.scene_layer_surface;
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.LayerSurfaceV1), _: *wlr.LayerSurfaceV1) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("destroy", listener);

        // Arrange windows to reclaim space if this layer surface had an exclusive zone
        if (layer_surface.exclusive_zone.hasExclusiveZone()) {
            layer_surface.server.arrangeWindows();
        }

        // Remove from server's layer surfaces list if still in it
        if (layer_surface.link.prev != null and layer_surface.link.next != null) {
            layer_surface.link.remove();
        }

        layer_surface.map.link.remove();
        layer_surface.unmap.link.remove();
        layer_surface.commit.link.remove();
        layer_surface.destroy.link.remove();
        layer_surface.new_popup.link.remove();

        // Destroy popup tree
        layer_surface.popup_tree.node.destroy();

        gpa.destroy(layer_surface);
    }

    fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("new_popup", listener);
        const xdg_surface = xdg_popup.base;

        // Use the separate popup_tree instead of layer surface's tree
        const scene_tree = layer_surface.popup_tree.createSceneXdgSurface(xdg_surface) catch {
            std.log.err("failed to allocate xdg popup node", .{});
            return;
        };
        xdg_surface.data = scene_tree;
        scene_tree.node.data = @ptrFromInt(@intFromPtr(layer_surface));
        std.log.info("Created popup {*} for layer surface {*} using popup_tree {*}", .{scene_tree, layer_surface, layer_surface.popup_tree});

        const popup = gpa.create(@import("../structs/popup.zig").Popup) catch {
            std.log.err("failed to allocate new popup", .{});
            return;
        };
        popup.* = .{
            .server = layer_surface.server,
            .xdg_popup = xdg_popup,
        };

        xdg_surface.surface.events.commit.add(&popup.commit);
        xdg_surface.surface.events.map.add(&popup.map);
        xdg_surface.surface.events.unmap.add(&popup.unmap);
        xdg_popup.events.destroy.add(&popup.destroy);
        xdg_popup.events.reposition.add(&popup.reposition);
        xdg_popup.base.events.new_popup.add(&popup.new_popup);
    }
};