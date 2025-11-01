const std = @import("std");
const mem = std.mem;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");

const gpa = std.heap.c_allocator;

const Toplevel = @import("../structs/toplevel.zig").Toplevel;
const SpringParams = @import("../utils/easing.zig").SpringParams;
const springInterpolate = @import("../utils/easing.zig").springInterpolate;

pub const Animation = struct {
    toplevel: *Toplevel,
    start_x: f32,
    start_y: f32,
    target_x: f32,
    target_y: f32,
    start_width: f32,
    start_height: f32,
    target_width: f32,
    target_height: f32,
    start_time: i64,
    duration: i64, // in microseconds
    spring_params: SpringParams,
    last_update_time: i64, // To track the time of last update for frame-rate adaptive calculations
    link: wl.list.Link = undefined,

    pub fn init(toplevel: *Toplevel, target_x: i32, target_y: i32, target_width: i32, target_height: i32, duration_ms: i64) Animation {
        const now = std.time.microTimestamp();
        
        // Convert to f32 for smoother spring animation
        return .{
            .toplevel = toplevel,
            .start_x = @floatFromInt(toplevel.x),
            .start_y = @floatFromInt(toplevel.y),
            .target_x = @floatFromInt(target_x),
            .target_y = @floatFromInt(target_y),
            .start_width = @floatFromInt(@as(i32, @intCast(toplevel.xdg_toplevel.base.current.geometry.width))),
            .start_height = @floatFromInt(@as(i32, @intCast(toplevel.xdg_toplevel.base.current.geometry.height))),
            .target_width = @floatFromInt(target_width),
            .target_height = @floatFromInt(target_height),
            .start_time = now,
            .duration = duration_ms * 1000, // convert to microseconds
            .spring_params = SpringParams{ .frequency = 8.0, .damping_ratio = 0.8 }, // Default spring parameters
            .last_update_time = now, // Initialize with current time
        };
    }

    pub fn update(self: *Animation) bool {
        const now = std.time.microTimestamp();
        const elapsed = now - self.start_time;
        
        // Convert elapsed time to seconds for physics calculations
        const elapsed_seconds = @as(f32, @floatFromInt(elapsed)) / 1_000_000.0;
        
        // Apply spring physics to calculate progress
        // We cap the time to prevent the spring from oscillating forever
        const max_time = 3.0; // Cap at 3 seconds for performance
        const spring_time = @min(elapsed_seconds * self.spring_params.frequency, max_time);
        const spring_progress = springInterpolate(spring_time, self.spring_params);

        // Calculate current values based on spring progress
        const current_x = self.start_x + spring_progress * (self.target_x - self.start_x);
        const current_y = self.start_y + spring_progress * (self.target_y - self.start_y);
        const current_width = self.start_width + spring_progress * (self.target_width - self.start_width);
        const current_height = self.start_height + spring_progress * (self.target_height - self.start_height);

        // Convert back to integers for positioning
        const int_current_x = @as(i32, @intFromFloat(current_x));
        const int_current_y = @as(i32, @intFromFloat(current_y));
        const int_current_width = @as(i32, @intFromFloat(current_width));
        const int_current_height = @as(i32, @intFromFloat(current_height));

        _ = self.toplevel.server.config.border_width;
        self.toplevel.border_container.node.setPosition(int_current_x - self.toplevel.server.config.border_width, int_current_y - self.toplevel.server.config.border_width);
        self.toplevel.scene_tree.node.setPosition(self.toplevel.server.config.border_width, self.toplevel.server.config.border_width);
        _ = self.toplevel.xdg_toplevel.setSize(int_current_width, int_current_height);

        self.toplevel.x = int_current_x;
        self.toplevel.y = int_current_y;

        // Update border
        var geometry: wlr.Box = undefined;
        self.toplevel.xdg_toplevel.base.getGeometry(&geometry);
        self.toplevel.updateBorder(int_current_x, int_current_y, int_current_width, int_current_height);

        // Animation is complete when we're close enough to the target
        const position_threshold = 1.0;
        const size_threshold = 1.0;
        const position_done = @abs(current_x - self.target_x) < position_threshold and 
                             @abs(current_y - self.target_y) < position_threshold;
        const size_done = @abs(current_width - self.target_width) < size_threshold and 
                         @abs(current_height - self.target_height) < size_threshold;
        
        return position_done and size_done;
    }
};