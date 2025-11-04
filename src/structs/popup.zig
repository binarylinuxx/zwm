const std = @import("std");

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

pub const Popup = struct {
    xdg_popup: *wlr.XdgPopup,

    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
    map: wl.Listener(void) = .init(handleMap),
    unmap: wl.Listener(void) = .init(handleUnmap),
    destroy: wl.Listener(void) = .init(handleDestroy),
    new_popup: wl.Listener(*wlr.XdgPopup) = .init(handleNewPopup),

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const popup: *Popup = @fieldParentPtr("commit", listener);
        if (popup.xdg_popup.base.initial_commit) {
            _ = popup.xdg_popup.base.scheduleConfigure();
        }
    }

    fn handleMap(listener: *wl.Listener(void)) void {
        const popup: *Popup = @fieldParentPtr("map", listener);
        std.log.info("popup mapped", .{});

        // Ensure popup is visible and properly positioned
        // The scene graph already handles positioning based on xdg_popup geometry
        _ = popup;
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const popup: *Popup = @fieldParentPtr("unmap", listener);
        std.log.info("popup unmapped", .{});
        _ = popup;
    }

    fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
        const parent_popup: *Popup = @fieldParentPtr("new_popup", listener);
        const xdg_surface = xdg_popup.base;

        // Get parent's scene tree
        const parent_tree = @as(*wlr.SceneTree, @ptrCast(@alignCast(parent_popup.xdg_popup.base.data.?)));

        // Create nested popup scene tree
        const scene_tree = parent_tree.createSceneXdgSurface(xdg_surface) catch {
            std.log.err("failed to allocate nested xdg popup node", .{});
            return;
        };
        xdg_surface.data = scene_tree;

        // Create nested popup struct
        const popup = gpa.create(Popup) catch {
            std.log.err("failed to allocate nested popup", .{});
            return;
        };
        popup.* = .{
            .xdg_popup = xdg_popup,
        };

        xdg_surface.surface.events.commit.add(&popup.commit);
        xdg_surface.surface.events.map.add(&popup.map);
        xdg_surface.surface.events.unmap.add(&popup.unmap);
        xdg_popup.events.destroy.add(&popup.destroy);
        xdg_popup.base.events.new_popup.add(&popup.new_popup);

        std.log.info("created nested popup successfully", .{});
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const popup: *Popup = @fieldParentPtr("destroy", listener);

        popup.commit.link.remove();
        popup.map.link.remove();
        popup.unmap.link.remove();
        popup.destroy.link.remove();
        popup.new_popup.link.remove();

        gpa.destroy(popup);
        std.log.info("popup destroyed", .{});
    }
};