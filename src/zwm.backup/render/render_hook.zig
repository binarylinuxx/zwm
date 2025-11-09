const std = @import("std");
const wlr = @import("wlroots");
const FXRenderer = @import("fx_renderer.zig").FXRenderer;

const c = @cImport({
    @cInclude("GLES2/gl2.h");
    @cInclude("wlr/render/gles2.h");
});

/// Hook into wlroots' rendering pipeline to apply custom effects
pub const RenderHook = struct {
    fx_renderer: *FXRenderer,

    pub fn init(fx_renderer: *FXRenderer) RenderHook {
        return .{
            .fx_renderer = fx_renderer,
        };
    }

    /// Apply effects before rendering a surface
    pub fn beforeSurfaceRender(self: *RenderHook, x: i32, y: i32, width: i32, height: i32) void {
        if (self.fx_renderer.corner_radius > 0.0) {
            // Enable GL scissor test for basic clipping
            c.glEnable(c.GL_SCISSOR_TEST);
            c.glScissor(x, y, width, height);

            // Apply stencil-based rounded corner clipping
            self.fx_renderer.applyRoundedCorners(x, y, width, height);
        }
    }

    /// Clean up after rendering a surface
    pub fn afterSurfaceRender(self: *RenderHook) void {
        if (self.fx_renderer.corner_radius > 0.0) {
            self.fx_renderer.endRoundedCorners();
            c.glDisable(c.GL_SCISSOR_TEST);
        }
    }
};
