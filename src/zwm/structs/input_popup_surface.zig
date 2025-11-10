const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

const Server = @import("../core/server.zig").Server;

pub const InputPopupSurface = struct {
    server: *Server,
    popup_surface: *wlr.InputPopupSurfaceV2,
    scene_tree: *wlr.SceneTree,

    destroy: wl.Listener(void) = .init(handleDestroy),
    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
    map: wl.Listener(void) = .init(handleMap),
    unmap: wl.Listener(void) = .init(handleUnmap),

    fn handleMap(listener: *wl.Listener(void)) void {
        const input_popup: *InputPopupSurface = @fieldParentPtr("map", listener);
        std.log.info("input popup surface mapped", .{});

        // Position the popup above other surfaces
        input_popup.scene_tree.node.raiseToTop();
        input_popup.scene_tree.node.setEnabled(true);
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const input_popup: *InputPopupSurface = @fieldParentPtr("unmap", listener);
        std.log.info("input popup surface unmapped", .{});
        input_popup.scene_tree.node.setEnabled(false);
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const input_popup: *InputPopupSurface = @fieldParentPtr("commit", listener);
        _ = input_popup;
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const input_popup: *InputPopupSurface = @fieldParentPtr("destroy", listener);

        input_popup.destroy.link.remove();
        input_popup.commit.link.remove();
        input_popup.map.link.remove();
        input_popup.unmap.link.remove();

        input_popup.scene_tree.node.destroy();

        gpa.destroy(input_popup);
        std.log.info("input popup surface destroyed", .{});
    }
};
