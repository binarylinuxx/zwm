const std = @import("std");

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

const Server = @import("../core/server.zig").Server;

pub const Popup = struct {
    server: *Server,
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
        std.log.info("popup mapped, giving keyboard focus", .{});

        // Give keyboard focus to the popup when it opens
        // This allows keyboard navigation (arrow keys, Enter, Escape, etc.)
        const surface = popup.xdg_popup.base.surface;
        if (popup.server.seat.getKeyboard()) |wlr_keyboard| {
            popup.server.seat.keyboardNotifyEnter(
                surface,
                wlr_keyboard.keycodes[0..wlr_keyboard.num_keycodes],
                &wlr_keyboard.modifiers,
            );
        }
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

        // Inherit the parent popup's toplevel data
        if (parent_tree.node.data) |data| {
            scene_tree.node.data = data;
        }

        scene_tree.node.setEnabled(true);
        scene_tree.node.raiseToTop();

        // Create nested popup struct
        const popup = gpa.create(Popup) catch {
            std.log.err("failed to allocate nested popup", .{});
            return;
        };
        popup.* = .{
            .server = parent_popup.server,
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