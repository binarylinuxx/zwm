const std = @import("std");
const wlr = @import("wlroots");

/// SceneFX C bindings for rounded corners and blur effects
pub const c = @cImport({
    @cDefine("WLR_USE_UNSTABLE", "1");
    @cInclude("scenefx/types/wlr_scene.h");
    @cInclude("scenefx/types/fx/corner_location.h");
    @cInclude("scenefx/types/fx/clipped_region.h");
    @cInclude("scenefx/render/fx_renderer/fx_renderer.h");
});

/// Corner location flags
pub const CornerLocation = enum(c_uint) {
    none = 0,
    top_left = 1,
    top_right = 2,
    bottom_right = 4,
    bottom_left = 8,
    all = 15, // All corners
};

/// Clipped region for masking parts of scene rectangles
pub const ClippedRegion = struct {
    area: wlr.Box,
    corner_radius: i32,
    corners: CornerLocation,

    /// Convert to C struct for FFI
    fn toC(self: ClippedRegion) c.struct_clipped_region {
        return c.struct_clipped_region{
            .area = c.struct_wlr_box{
                .x = self.area.x,
                .y = self.area.y,
                .width = self.area.width,
                .height = self.area.height,
            },
            .corner_radius = self.corner_radius,
            .corners = @intFromEnum(self.corners),
        };
    }
};

/// Set corner radius for a scene rectangle (borders)
pub fn setRectCornerRadius(rect: anytype, radius: i32, corners: CornerLocation) void {
    const c_rect: [*c]c.struct_wlr_scene_rect = @ptrCast(rect);
    c.wlr_scene_rect_set_corner_radius(c_rect, radius, @intFromEnum(corners));
}

/// Set corner radius for a scene buffer (window surface)
pub fn setBufferCornerRadius(buffer: anytype, radius: i32, corners: CornerLocation) void {
    const c_buffer: [*c]c.struct_wlr_scene_buffer = @ptrCast(buffer);
    c.wlr_scene_buffer_set_corner_radius(c_buffer, radius, @intFromEnum(corners));
}

/// Set global blur radius for the scene
pub fn setSceneBlurRadius(scene: anytype, radius: i32) void {
    c.wlr_scene_set_blur_radius(scene, radius);
}

/// Set all blur parameters for the scene at once
pub fn setSceneBlurData(scene: anytype, num_passes: i32, radius: i32, noise: f32, brightness: f32, contrast: f32, saturation: f32) void {
    const c_scene: [*c]c.struct_wlr_scene = @ptrCast(scene);
    c.wlr_scene_set_blur_data(c_scene, num_passes, radius, noise, brightness, contrast, saturation);
}

/// Enable backdrop blur for a scene buffer (window)
pub fn setBufferBackdropBlur(buffer: anytype, enabled: bool) void {
    const c_buffer: [*c]c.struct_wlr_scene_buffer = @ptrCast(buffer);
    c.wlr_scene_buffer_set_backdrop_blur(c_buffer, enabled);
}

/// Enable optimized backdrop blur for a scene buffer
pub fn setBufferBackdropBlurOptimized(buffer: anytype, enabled: bool) void {
    const c_buffer: [*c]c.struct_wlr_scene_buffer = @ptrCast(buffer);
    c.wlr_scene_buffer_set_backdrop_blur_optimized(c_buffer, enabled);
}

/// Set whether to ignore transparent pixels in backdrop blur
pub fn setBufferBackdropBlurIgnoreTransparent(buffer: anytype, enabled: bool) void {
    const c_buffer: [*c]c.struct_wlr_scene_buffer = @ptrCast(buffer);
    c.wlr_scene_buffer_set_backdrop_blur_ignore_transparent(c_buffer, enabled);
}

/// Callback type for iterating scene buffers
pub const SceneBufferIterator = *const fn (buffer: *c.struct_wlr_scene_buffer, sx: c_int, sy: c_int, user_data: ?*anyopaque) callconv(.C) void;

/// Iterate through all buffers in a scene node
pub fn sceneNodeForEachBuffer(node: anytype, iterator: SceneBufferIterator, user_data: ?*anyopaque) void {
    const c_node: [*c]c.struct_wlr_scene_node = @ptrCast(node);
    c.wlr_scene_node_for_each_buffer(c_node, iterator, user_data);
}

/// Create FX renderer instead of regular wlroots renderer
pub fn createFXRenderer(backend: *wlr.Backend) !*wlr.Renderer {
    const c_renderer = c.fx_renderer_create(@ptrCast(backend));
    if (c_renderer == null) {
        return error.FXRendererCreationFailed;
    }
    return @ptrCast(c_renderer);
}

/// Set subsurface tree clipping with optional rounded corners
pub fn setSubsurfaceTreeClip(node: anytype, clip_box: ?*const wlr.Box) void {
    const c_node: [*c]c.struct_wlr_scene_node = @ptrCast(node);
    const c_box: ?*const c.struct_wlr_box = if (clip_box) |box| @ptrCast(box) else null;
    c.wlr_scene_subsurface_tree_set_clip(c_node, c_box);
}

/// Set clipped region for a scene rectangle to create hollow/masked effects
/// This is perfect for creating border-only rectangles by clipping out the inner area
pub fn setRectClippedRegion(rect: anytype, clipped_region: ClippedRegion) void {
    const c_rect: [*c]c.struct_wlr_scene_rect = @ptrCast(rect);
    const c_region = clipped_region.toC();
    c.wlr_scene_rect_set_clipped_region(c_rect, c_region);
}
