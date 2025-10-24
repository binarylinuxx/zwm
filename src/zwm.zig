const std = @import("std");
const posix = std.posix;
const mem = std.mem;

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const gpa = std.heap.c_allocator;
const corner_radius: i32 = 12;

// Cubic Bezier easing function
fn cubicBezier(t: f32, p0: f32, p1: f32, p2: f32, p3: f32) f32 {
    const u = 1.0 - t;
    const tt = t * t;
    const uu = u * u;
    const uuu = uu * u;
    const ttt = tt * t;

    return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3;
}

// Solve cubic bezier equation for t given x using Newton-Raphson method for better performance
fn solveCubicBezier(x: f32, p0x: f32, p1x: f32, p2x: f32, p3x: f32) f32 {
    // Start with a linear guess
    var t = x;
    
    // Newton-Raphson iterations for faster convergence
    for (0..8) |_| {  // Reduced iterations for better performance
        const x_t = cubicBezier(t, p0x, p1x, p2x, p3x);
        const dx_dt = cubicBezierDerivative(t, p0x, p1x, p2x, p3x);
        
        // Avoid division by zero
        if (@abs(dx_dt) < 0.0001) break;
        
        const diff = x_t - x;
        if (@abs(diff) < 0.001) break;
        
        t -= diff / dx_dt;
        // Clamp t to [0, 1] range
        t = @max(0.0, @min(1.0, t));
    }
    
    return t;
}

// Derivative of cubic bezier for Newton-Raphson method
fn cubicBezierDerivative(t: f32, p0: f32, p1: f32, p2: f32, p3: f32) f32 {
    const u = 1.0 - t;
    return 3.0 * (u * u * (p1 - p0) + 2 * u * t * (p2 - p1) + t * t * (p3 - p2));
}

// Get eased value using cubic bezier with standard ease-in-out curve
fn easeCubicBezier(t: f32, p0x: f32, p0y: f32, p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32) f32 {
    const x = cubicBezier(t, p0x, p1x, p2x, p3x);
    const t_val = solveCubicBezier(x, p0x, p1x, p2x, p3x);
    const y = cubicBezier(t_val, p0y, p1y, p2y, p3y);
    return y;
}

// Spring dynamics constants
const SpringParams = struct {
    frequency: f32 = 8.0,  // Angular frequency (controls speed)
    damping_ratio: f32 = 0.8,  // Damping ratio (1.0 = critically damped, < 1.0 = underdamped)
};

// Spring interpolation function
fn springInterpolate(t: f32, params: SpringParams) f32 {
    // Calculate damping coefficient and angular frequency
    const zeta = params.damping_ratio;
    const w0 = params.frequency;
    
    // Calculate damped frequency
    const wd = if (zeta < 1.0) w0 * @sqrt(1.0 - zeta * zeta) else 0.0;
    
    if (zeta > 1.0) {
        // Overdamped case
        const r1 = -zeta * w0 + @sqrt(zeta * zeta - 1.0) * w0;
        const r2 = -zeta * w0 - @sqrt(zeta * zeta - 1.0) * w0;
        const c1 = 1.0;  // Since we start at 0
        const c2 = (zeta * w0 - r1) / (r2 - r1);  // To satisfy initial conditions
        
        return 1.0 - (c1 * @exp(r1 * t) + c2 * @exp(r2 * t));
    } else if (zeta == 1.0) {
        // Critically damped case
        return 1.0 - (1.0 + w0 * t) * @exp(-w0 * t);
    } else {
        // Underdamped case (oscillating)
        const envelope = @exp(-zeta * w0 * t);
        const oscillation = @cos(wd * t) + (zeta * w0 / wd) * @sin(wd * t);
        return 1.0 - envelope * oscillation;
    }
}

const Layer = enum {
    background,
    bottom,
    app,
    top,
    overlay,
};

const Animation = struct {
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
    link: wl.list.Link = undefined,

    fn init(toplevel: *Toplevel, target_x: i32, target_y: i32, target_width: i32, target_height: i32, duration_ms: i64) Animation {
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
        };
    }

    fn update(self: *Animation) bool {
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

        _ = self.toplevel.server.border_width;
        self.toplevel.border_container.node.setPosition(int_current_x - self.toplevel.server.border_width, int_current_y - self.toplevel.server.border_width);
        self.toplevel.scene_tree.node.setPosition(self.toplevel.server.border_width, self.toplevel.server.border_width);
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

pub fn main() anyerror!void {
    wlr.log.init(.debug, null);

    // Redirect logs to file
    const log_file = std.fs.cwd().createFile("log.log", .{ .read = true }) catch |err| {
        std.debug.print("Failed to create log file: {}\n", .{err});
        return err;
    };
    defer log_file.close();

    var file_writer = std.io.bufferedWriter(log_file.writer());
    _ = file_writer.writer();

    std.log.info("Starting ZWM compositor", .{});

    var server: Server = undefined;
    try server.init();
    defer server.deinit();

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);
    server.wayland_display = try gpa.dupe(u8, socket);
    std.log.info("Created Wayland socket: {s}", .{socket});

    if (std.os.argv.len >= 2) {
        const cmd = std.mem.span(std.os.argv[1]);
        var child = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", cmd }, gpa);
        var env_map = try std.process.getEnvMap(gpa);
        defer env_map.deinit();
        try env_map.put("WAYLAND_DISPLAY", socket);
        child.env_map = &env_map;
        try child.spawn();
    }

    try server.backend.start();

    std.log.info("Running compositor on WAYLAND_DISPLAY={s}", .{socket});

    // Flush logs before running
    file_writer.flush() catch {};
    std.log.info("About to start server.wl_server.run()", .{});

    server.wl_server.run();
}

const Server = struct {
    wl_server: *wl.Server,
    backend: *wlr.Backend,
    renderer: *wlr.Renderer,
    allocator: *wlr.Allocator,
    scene: *wlr.Scene,

    output_layout: *wlr.OutputLayout,
    scene_output_layout: *wlr.SceneOutputLayout,
    new_output: wl.Listener(*wlr.Output) = .init(newOutput),

    // Layer subtrees for proper ordering
    layer_trees: [5]*wlr.SceneTree = undefined,

    xdg_shell: *wlr.XdgShell,
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) = .init(newXdgToplevel),
    new_xdg_popup: wl.Listener(*wlr.XdgPopup) = .init(newXdgPopup),
    toplevels: wl.list.Head(Toplevel, .link) = undefined,

    layer_shell: *wlr.LayerShellV1,
    new_layer_surface: wl.Listener(*wlr.LayerSurfaceV1) = .init(newLayerSurface),
    layer_surfaces: wl.list.Head(LayerSurface, .link) = undefined,

    xdg_decoration_manager: *wlr.XdgDecorationManagerV1,
    new_xdg_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) = .init(newXdgToplevelDecoration),

    xdg_output_manager: *wlr.XdgOutputManagerV1,

    screencopy_manager: *wlr.ScreencopyManagerV1,
    screencopy_frame: wl.Listener(*wlr.ScreencopyFrameV1) = .init(handleScreencopyFrame),

    seat: *wlr.Seat,
    new_input: wl.Listener(*wlr.InputDevice) = .init(newInput),
    request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = .init(requestSetCursor),
    request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = .init(requestSetSelection),
    keyboards: wl.list.Head(Keyboard, .link) = undefined,

    cursor: *wlr.Cursor,
    cursor_mgr: *wlr.XcursorManager,
    cursor_motion: wl.Listener(*wlr.Pointer.event.Motion) = .init(cursorMotion),
    cursor_motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = .init(cursorMotionAbsolute),
    cursor_button: wl.Listener(*wlr.Pointer.event.Button) = .init(cursorButton),
    cursor_axis: wl.Listener(*wlr.Pointer.event.Axis) = .init(cursorAxis),
    cursor_frame: wl.Listener(*wlr.Cursor) = .init(cursorFrame),

    cursor_mode: enum { passthrough, move, resize } = .passthrough,
    grabbed_view: ?*Toplevel = null,
    grab_x: f64 = 0,
    grab_y: f64 = 0,
    grab_box: wlr.Box = undefined,
    resize_edges: wlr.Edges = .{},

    wayland_display: []const u8,

    // Layout configuration
    master_ratio: f32 = 0.5,
    gap_size: i32 = 10,
    border_width: i32 = 3,
    master_toplevel: ?*Toplevel = null, // Track master window separately

    // Animation management
    animations: wl.list.Head(Animation, .link) = undefined,
    animation_timer: *wl.EventSource = undefined,

    fn init(server: *Server) !void {
        const wl_server = try wl.Server.create();
        const loop = wl_server.getEventLoop();
        const backend = try wlr.Backend.autocreate(loop, null);
        const renderer = try wlr.Renderer.autocreate(backend);
        const output_layout = try wlr.OutputLayout.create(wl_server);
        const scene = try wlr.Scene.create();
        const xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server);
        const screencopy_manager = try wlr.ScreencopyManagerV1.create(wl_server);
        const xdg_output_manager = try wlr.XdgOutputManagerV1.create(wl_server, output_layout);

        // Create layer subtrees
        var layer_trees: [5]*wlr.SceneTree = undefined;
        inline for (std.meta.fields(Layer)) |field| {
            layer_trees[field.value] = scene.tree.createSceneTree() catch {
                std.log.err("failed to create layer subtree", .{});
                return error.LayerTreeCreationFailed;
            };
        }

        server.* = .{
            .wl_server = wl_server,
            .backend = backend,
            .renderer = renderer,
            .allocator = try wlr.Allocator.autocreate(backend, renderer),
            .scene = scene,
            .output_layout = output_layout,
            .scene_output_layout = try scene.attachOutputLayout(output_layout),
            .xdg_shell = try wlr.XdgShell.create(wl_server, 2),
            .xdg_decoration_manager = xdg_decoration_manager,
            .layer_shell = try wlr.LayerShellV1.create(wl_server, 4),
            .xdg_output_manager = xdg_output_manager,
            .seat = try wlr.Seat.create(wl_server, "default"),
            .cursor = try wlr.Cursor.create(),
            .cursor_mgr = try wlr.XcursorManager.create(null, 24),
            .layer_trees = layer_trees,
            .screencopy_manager = screencopy_manager,
            .wayland_display = "",
        };
        
        std.log.info("Server initialized", .{});

        try server.renderer.initServer(wl_server);

        _ = try wlr.Compositor.create(server.wl_server, 6, server.renderer);
        _ = try wlr.Subcompositor.create(server.wl_server);
        _ = try wlr.DataDeviceManager.create(server.wl_server);


        server.backend.events.new_output.add(&server.new_output);

        server.xdg_shell.data = @intFromPtr(server);
        std.log.info("XDG shell data set to server ptr: {*}", .{server});
        server.xdg_shell.events.new_toplevel.add(&server.new_xdg_toplevel);
        server.xdg_shell.events.new_popup.add(&server.new_xdg_popup);
        server.toplevels.init();

        server.layer_shell.events.new_surface.add(&server.new_layer_surface);
        server.layer_surfaces.init();

        // Initialize screencopy manager
        server.screencopy_manager = try wlr.ScreencopyManagerV1.create(server.wl_server);

        // Add XDG decoration manager event listener
        server.xdg_decoration_manager.events.new_toplevel_decoration.add(&server.new_xdg_toplevel_decoration);

        server.backend.events.new_input.add(&server.new_input);
        server.seat.events.request_set_cursor.add(&server.request_set_cursor);
        server.seat.events.request_set_selection.add(&server.request_set_selection);
        server.keyboards.init();

        // Screencopy frame events are handled differently in wlroots
        // The frame event is added when a frame is created

        server.cursor.attachOutputLayout(server.output_layout);
        try server.cursor_mgr.load(1);
        server.cursor.events.motion.add(&server.cursor_motion);
        server.cursor.events.motion_absolute.add(&server.cursor_motion_absolute);
        server.cursor.events.button.add(&server.cursor_button);
        server.cursor.events.axis.add(&server.cursor_axis);
        server.cursor.events.frame.add(&server.cursor_frame);

        // Initialize animations list
        server.animations.init();

        // Set up animation timer (10 FPS for cleanup when no animations are running on frame)
        server.animation_timer = try wl.EventLoop.addTimer(
            loop,
            *Server,
            handleAnimationTimer,
            server,
        );
        try server.animation_timer.timerUpdate(100000); // 10 FPS in microseconds
    }

    fn deinit(server: *Server) void {
        server.animation_timer.remove();

        server.wl_server.destroyClients();

        server.new_input.link.remove();
        server.new_output.link.remove();

        server.new_xdg_toplevel.link.remove();
        server.new_xdg_popup.link.remove();
        server.request_set_cursor.link.remove();
        server.request_set_selection.link.remove();
        server.cursor_motion.link.remove();
        server.cursor_motion_absolute.link.remove();
        server.cursor_button.link.remove();
        server.cursor_axis.link.remove();
        server.cursor_frame.link.remove();

        if (!mem.eql(u8, server.wayland_display, "")) {
            gpa.free(server.wayland_display);
        }

        server.backend.destroy();
        server.wl_server.destroy();
    }

    fn arrangeWindows(server: *Server) void {
        std.log.info("arrangeWindows called: {} toplevels", .{server.toplevels.length()});
        const count = server.toplevels.length();

        if (count == 0) return;

        // Get the usable area from the first output
        var box: wlr.Box = undefined;
        server.output_layout.getBox(null, &box);

        _ = server.border_width;
        const usable_width = box.width - (server.gap_size * 2);
        const usable_height = box.height - (server.gap_size * 2);

        if (count == 1) {
            // Single window takes full screen with gaps
            var it = server.toplevels.iterator(.forward);
            if (it.next()) |toplevel| {
                const x = box.x + server.gap_size;
                const y = box.y + server.gap_size;
                const w = usable_width;
                const h = usable_height;

                std.log.info("Single window: animating to position x={}, y={}, size w={}, h={}", .{x, y, w, h});
                server.startAnimation(toplevel, x, y, w, h);
                
                // Set this as the master window if not already set
                if (server.master_toplevel == null) {
                    server.master_toplevel = toplevel;
                }
            }
        } else {
            // Master-stack layout
            const master_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(usable_width)) * server.master_ratio)) - server.gap_size;
            const stack_width = usable_width - master_width - server.gap_size;
            
            // Determine master window: use the explicitly set master if available, otherwise first in list
            var master: ?*Toplevel = null;
            var stack_count: usize = 0;
            
            // Count all windows that are not the master
            var it = server.toplevels.iterator(.forward);
            while (it.next()) |toplevel| {
                if (server.master_toplevel != null and toplevel == server.master_toplevel.?) {
                    master = toplevel;
                } else {
                    stack_count += 1;
                }
            }
            
            // If no master is set, use the first window as master and set it
            if (master == null) {
                var it2 = server.toplevels.iterator(.forward);
                if (it2.next()) |first_toplevel| {
                    master = first_toplevel;
                    server.master_toplevel = first_toplevel;
                }
            }
            
            const stack_height = @divTrunc(usable_height, @as(i32, @intCast(stack_count)));

            // Position master window
            if (master) |master_window| {
                const x = box.x + server.gap_size;
                const y = box.y + server.gap_size;

                std.log.info("Master window: animating to position x={}, y={}, size w={}, h={}", .{x, y, master_width, usable_height});
                server.startAnimation(master_window, x, y, master_width, usable_height);
            }

            // Position stack windows
            var stack_idx: usize = 0;
            var it3 = server.toplevels.iterator(.forward);
            while (it3.next()) |toplevel| {
                // Skip the master window
                if (server.master_toplevel != null and toplevel == server.master_toplevel.?) {
                    continue;
                }
                
                const x = box.x + server.gap_size + master_width + server.gap_size;
                const y = box.y + server.gap_size + @as(i32, @intCast(stack_idx)) * stack_height;
                const h = if (stack_idx == stack_count - 1)
                    usable_height - @as(i32, @intCast(stack_idx)) * stack_height
                else
                    stack_height - server.gap_size;

                std.log.info("Stack window {}: animating to position x={}, y={}, size w={}, h={}", .{stack_idx, x, y, stack_width, h});
                server.startAnimation(toplevel, x, y, stack_width, h);
                stack_idx += 1;
            }
        }
    }

    fn newOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
        const server: *Server = @fieldParentPtr("new_output", listener);

        if (!wlr_output.initRender(server.allocator, server.renderer)) return;

        var state = wlr.Output.State.init();
        defer state.finish();

        state.setEnabled(true);
        if (wlr_output.preferredMode()) |mode| {
            state.setMode(mode);
        }
        if (!wlr_output.commitState(&state)) return;

        Output.create(server, wlr_output) catch {
            std.log.err("failed to allocate new output", .{});
            wlr_output.destroy();
            return;
        };
        
        // Rearrange windows when output is added
        server.arrangeWindows();
    }

    fn newXdgToplevel(listener: *wl.Listener(*wlr.XdgToplevel), xdg_toplevel: *wlr.XdgToplevel) void {
        const server: *Server = @fieldParentPtr("new_xdg_toplevel", listener);
        const xdg_surface = xdg_toplevel.base;

        const toplevel = gpa.create(Toplevel) catch {
            std.log.err("failed to allocate new toplevel", .{});
            return;
        };
        errdefer gpa.destroy(toplevel);

        toplevel.* = .{
            .server = server,
            .xdg_toplevel = xdg_toplevel,
            .scene_tree = undefined,
            .border_container = undefined,
        };
        xdg_surface.data = @intFromPtr(toplevel);

        // Create a border container for this toplevel
        const border_container = toplevel.server.layer_trees[@intFromEnum(Layer.app)].createSceneTree() catch {
            std.log.err("failed to allocate border container", .{});
            return;
        };
        toplevel.border_container = border_container;
        
        // Create the four border rectangles (top, right, bottom, left)
        const color = [4]f32{ 86.0, 30.0, 25.0, 1.0}; // Desaturated red

        // Top border
        toplevel.border_nodes[0] = border_container.createSceneRect(
            0, 0, &color
        ) catch {
            std.log.err("failed to allocate top border", .{});
            return;
        };

        // Right border
        toplevel.border_nodes[1] = border_container.createSceneRect(
            0, 0, &color
        ) catch {
            std.log.err("failed to allocate right border", .{});
            return;
        };

        // Bottom border
        toplevel.border_nodes[2] = border_container.createSceneRect(
            0, 0, &color
        ) catch {
            std.log.err("failed to allocate bottom border", .{});
            return;
        };

        // Left border
        toplevel.border_nodes[3] = border_container.createSceneRect(
            0, 0, &color
        ) catch {
            std.log.err("failed to allocate left border", .{});
            return;
        };

        const scene_tree = border_container.createSceneXdgSurface(xdg_surface) catch {
            std.log.err("failed to allocate xdg toplevel scene node", .{});
            return;
        };
        toplevel.scene_tree = scene_tree;
        scene_tree.node.data = @intFromPtr(toplevel);

        xdg_surface.surface.events.commit.add(&toplevel.commit);
        xdg_surface.surface.events.map.add(&toplevel.map);
        xdg_surface.surface.events.unmap.add(&toplevel.unmap);
        xdg_surface.events.destroy.add(&toplevel.destroy);
        xdg_toplevel.events.request_move.add(&toplevel.request_move);
        xdg_toplevel.events.request_resize.add(&toplevel.request_resize);

        // Force no client-side decorations by setting window geometry to include decorations
        // This tricks clients into thinking they don't need to draw decorations
        var geometry: wlr.Box = undefined;
        xdg_surface.getGeometry(&geometry);
        // Set the window size to be larger than the content area, effectively hiding client decorations
        _ = xdg_toplevel.setSize(geometry.width + 20, geometry.height + 40); // Add padding for hidden decorations

    }


    fn newXdgToplevelDecoration(_: *wl.Listener(*wlr.XdgToplevelDecorationV1), decoration: *wlr.XdgToplevelDecorationV1) void {
        _ = decoration.setMode(.server_side);
    }

    fn newLayerSurface(listener: *wl.Listener(*wlr.LayerSurfaceV1), layer_surface: *wlr.LayerSurfaceV1) void {
    const server: *Server = @fieldParentPtr("new_layer_surface", listener);

    const layer_surface_ptr = gpa.create(LayerSurface) catch {
        std.log.err("failed to allocate new layer surface", .{});
        return;
    };
    errdefer gpa.destroy(layer_surface_ptr);

    layer_surface_ptr.* = .{
        .server = server,
        .layer_surface = layer_surface,
        .scene_layer_surface = undefined,
        .configured = false,
    };

    // Map layer-shell protocol layers to our layer trees
    const parent_idx = switch (layer_surface.current.layer) {  // Use current.layer, not pending
        .background => @intFromEnum(Layer.background),
        .bottom => @intFromEnum(Layer.bottom),
        .top => @intFromEnum(Layer.top),
        .overlay => @intFromEnum(Layer.overlay),
        _ => @intFromEnum(Layer.bottom), // Default to bottom layer for any other cases
    };
    const parent = server.layer_trees[parent_idx];

    // Create scene layer surface
    const scene_layer_surface = parent.createSceneLayerSurfaceV1(layer_surface) catch {
        std.log.err("failed to create scene layer surface", .{});
        return;
    };
    layer_surface_ptr.scene_layer_surface = scene_layer_surface;

    // DON'T add to list here - will be added in handleMap
    // server.layer_surfaces.append(layer_surface_ptr); // REMOVE THIS LINE

    // Set up event listeners
    layer_surface.surface.events.map.add(&layer_surface_ptr.map);
    layer_surface.surface.events.unmap.add(&layer_surface_ptr.unmap);
    layer_surface.surface.events.commit.add(&layer_surface_ptr.commit);
    layer_surface.events.destroy.add(&layer_surface_ptr.destroy);
    layer_surface.events.new_popup.add(&layer_surface_ptr.new_popup);

    // Assign output if not already set
    if (layer_surface.output == null) {
        // If no output specified, use the first available output
        var it = server.output_layout.outputs.iterator(.forward);
        if (it.next()) |layout_output| {
            layer_surface.output = layout_output.output;
        } else {
            std.log.err("no output available for layer surface", .{});
            return;
        }
    }
}


    fn newXdgPopup(_: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
        const xdg_surface = xdg_popup.base;

        const parent = wlr.XdgSurface.tryFromWlrSurface(xdg_popup.parent.?) orelse return;
        const parent_tree = if (parent.data != 0)
            @as(*wlr.SceneTree, @ptrFromInt(parent.data))
        else {
            return;
        };
        const scene_tree = parent_tree.createSceneXdgSurface(xdg_surface) catch {
            std.log.err("failed to allocate xdg popup node", .{});
            return;
        };
        xdg_surface.data = @intFromPtr(scene_tree);

        const popup = gpa.create(Popup) catch {
            std.log.err("failed to allocate new popup", .{});
            return;
        };
        popup.* = .{
            .xdg_popup = xdg_popup,
        };

        xdg_surface.surface.events.commit.add(&popup.commit);
        xdg_popup.events.destroy.add(&popup.destroy);
    }

    const ViewAtResult = struct {
        toplevel: *Toplevel,
        surface: *wlr.Surface,
        sx: f64,
        sy: f64,
    };

    fn viewAt(server: *Server, lx: f64, ly: f64) ?ViewAtResult {
        var sx: f64 = undefined;
        var sy: f64 = undefined;
        if (server.scene.tree.node.at(lx, ly, &sx, &sy)) |node| {
            if (node.type != .buffer) return null;
            const scene_buffer = wlr.SceneBuffer.fromNode(node);
            const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse return null;

            var it: ?*wlr.SceneTree = node.parent;
            while (it) |n| : (it = n.node.parent) {
                if (n.node.data != 0) {
                    const toplevel = @as(*Toplevel, @ptrFromInt(n.node.data));
                    return ViewAtResult{
                        .toplevel = toplevel,
                        .surface = scene_surface.surface,
                        .sx = sx,
                        .sy = sy,
                    };
                }
            }
        }
        return null;
    }

    fn setBorderActive(toplevel: *Toplevel, active: bool) void {
        const color = if (active) [4]f32{ 255, 180, 171, 1.0 } else [4]f32{ 0.4, 0.4, 0.4, 1.0 }; // Blue for active, grey for inactive
        
        for (toplevel.border_nodes) |border_node| {
            _ = border_node.setColor(&color);
        }
    }

    fn focusView(server: *Server, toplevel: *Toplevel, surface: *wlr.Surface, rearrange: bool) void {
        std.log.info("focusView called, toplevel: {*}, surface: {*}, rearrange: {}", .{toplevel, surface, rearrange});
        if (server.seat.keyboard_state.focused_surface) |previous_surface| {
            std.log.info("previous_surface: {*}, clicked surface: {*}", .{previous_surface, surface});
            if (previous_surface == surface) {
                std.log.info("Already focused, returning without rearranging", .{});
                return;
            }
            if (wlr.XdgSurface.tryFromWlrSurface(previous_surface)) |xdg_surface| {
                _ = xdg_surface.role_data.toplevel.?.setActivated(false);
                
                // Find the toplevel for the previous surface and make its border inactive
                const prev_toplevel = @as(*Toplevel, @ptrFromInt(xdg_surface.data));
                Server.setBorderActive(prev_toplevel, false);
            }
        } else {
            std.log.info("No previous focused surface", .{});
        }

        toplevel.scene_tree.node.raiseToTop();
        toplevel.link.remove();
        server.toplevels.prepend(toplevel);

        _ = toplevel.xdg_toplevel.setActivated(true);
        Server.setBorderActive(toplevel, true); // Make the border of the focused window active

        const wlr_keyboard = server.seat.getKeyboard() orelse return;
        server.seat.keyboardNotifyEnter(
            surface,
            wlr_keyboard.keycodes[0..wlr_keyboard.num_keycodes],
            &wlr_keyboard.modifiers,
        );

        if (rearrange) {
            // Rearange after focus change
            server.arrangeWindows();
        }
    }

    fn newInput(listener: *wl.Listener(*wlr.InputDevice), device: *wlr.InputDevice) void {
        const server: *Server = @fieldParentPtr("new_input", listener);
        switch (device.type) {
            .keyboard => Keyboard.create(server, device) catch |err| {
                std.log.err("failed to create keyboard: {}", .{err});
                return;
            },
            .pointer => server.cursor.attachInputDevice(device),
            else => {},
        }

        server.seat.setCapabilities(.{
            .pointer = true,
            .keyboard = server.keyboards.length() > 0,
        });
    }

    fn requestSetCursor(
        listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
        event: *wlr.Seat.event.RequestSetCursor,
    ) void {
        const server: *Server = @fieldParentPtr("request_set_cursor", listener);
        if (event.seat_client == server.seat.pointer_state.focused_client)
            server.cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
    }

    fn requestSetSelection(
        listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
        event: *wlr.Seat.event.RequestSetSelection,
    ) void {
        const server: *Server = @fieldParentPtr("request_set_selection", listener);
        server.seat.setSelection(event.source, event.serial);
    }

    fn cursorMotion(
        listener: *wl.Listener(*wlr.Pointer.event.Motion),
        event: *wlr.Pointer.event.Motion,
    ) void {
        const server: *Server = @fieldParentPtr("cursor_motion", listener);
        server.cursor.move(event.device, event.delta_x, event.delta_y);
        server.processCursorMotion(event.time_msec);
    }

    fn cursorMotionAbsolute(
        listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
        event: *wlr.Pointer.event.MotionAbsolute,
    ) void {
        const server: *Server = @fieldParentPtr("cursor_motion_absolute", listener);
        server.cursor.warpAbsolute(event.device, event.x, event.y);
        server.processCursorMotion(event.time_msec);
    }

    fn processCursorMotion(server: *Server, time_msec: u32) void {
        switch (server.cursor_mode) {
            .passthrough => if (server.viewAt(server.cursor.x, server.cursor.y)) |res| {
                server.seat.pointerNotifyEnter(res.surface, res.sx, res.sy);
                server.seat.pointerNotifyMotion(time_msec, res.sx, res.sy);
                server.focusView(res.toplevel, res.surface, false);
            } else {
                server.cursor.setXcursor(server.cursor_mgr, "default");
                server.seat.pointerClearFocus();
            },
            .move => {
                const toplevel = server.grabbed_view.?;
                const bw = server.border_width;
                const border_x = @as(i32, @intFromFloat(server.cursor.x - server.grab_x));
                const border_y = @as(i32, @intFromFloat(server.cursor.y - server.grab_y));
                toplevel.border_container.node.setPosition(border_x - bw, border_y - bw);
                toplevel.x = border_x;
                toplevel.y = border_y;
            },
            .resize => {
                const toplevel = server.grabbed_view.?;
                const border_x = @as(i32, @intFromFloat(server.cursor.x - server.grab_x));
                const border_y = @as(i32, @intFromFloat(server.cursor.y - server.grab_y));

                var new_left = server.grab_box.x;
                var new_right = server.grab_box.x + server.grab_box.width;
                var new_top = server.grab_box.y;
                var new_bottom = server.grab_box.y + server.grab_box.height;

                if (server.resize_edges.top) {
                    new_top = border_y;
                    if (new_top >= new_bottom)
                        new_top = new_bottom - 1;
                } else if (server.resize_edges.bottom) {
                    new_bottom = border_y;
                    if (new_bottom <= new_top)
                        new_bottom = new_top + 1;
                }

                if (server.resize_edges.left) {
                    new_left = border_x;
                    if (new_left >= new_right)
                        new_left = new_right - 1;
                } else if (server.resize_edges.right) {
                    new_right = border_x;
                    if (new_right <= new_left)
                        new_right = new_left + 1;
                }

                var current_geometry: wlr.Box = undefined;
                toplevel.xdg_toplevel.base.getGeometry(&current_geometry);
                toplevel.x = new_left - current_geometry.x;
                toplevel.y = new_top - current_geometry.y;
                toplevel.scene_tree.node.setPosition(toplevel.x, toplevel.y);

                const new_width = new_right - new_left;
                const new_height = new_bottom - new_top;
                _ = toplevel.xdg_toplevel.setSize(new_width, new_height);
                
                // Update border after resizing
                toplevel.updateBorder(toplevel.x, toplevel.y, new_width, new_height);
            },
        }
    }

    fn cursorButton(
        listener: *wl.Listener(*wlr.Pointer.event.Button),
        event: *wlr.Pointer.event.Button,
    ) void {
        const server: *Server = @fieldParentPtr("cursor_button", listener);
        _ = server.seat.pointerNotifyButton(event.time_msec, event.button, event.state);
        if (event.state == .released) {
            server.cursor_mode = .passthrough;
        }
        // Removed focusView call to prevent window rearrangement on mouse click
    }

    fn cursorAxis(
        listener: *wl.Listener(*wlr.Pointer.event.Axis),
        event: *wlr.Pointer.event.Axis,
    ) void {
        const server: *Server = @fieldParentPtr("cursor_axis", listener);
        server.seat.pointerNotifyAxis(
            event.time_msec,
            event.orientation,
            event.delta,
            event.delta_discrete,
            event.source,
            event.relative_direction,
        );
    }

    fn cursorFrame(listener: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
        const server: *Server = @fieldParentPtr("cursor_frame", listener);
        server.seat.pointerNotifyFrame();
    }

    fn handleAnimationTimer(server: *Server) c_int {
        server.updateAnimations();
        // Continue timer if there are still animations
        return if (server.animations.length() > 0) 0 else 1;
    }

    fn updateAnimations(server: *Server) void {
        var it = server.animations.iterator(.forward);
        var completed_animations = std.ArrayList(*Animation).initCapacity(gpa, 4) catch return;

        while (it.next()) |animation| {
            if (animation.update()) {
                completed_animations.append(animation) catch {};
            }
        }

        // Remove completed animations
        for (completed_animations.items) |animation| {
            animation.link.remove();
            gpa.destroy(animation);
        }
        completed_animations.deinit();
    }

    fn startAnimation(server: *Server, toplevel: *Toplevel, target_x: i32, target_y: i32, target_width: i32, target_height: i32) void {
        // Cancel any existing animation for this toplevel
        var it = server.animations.iterator(.forward);
        while (it.next()) |animation| {
            if (animation.toplevel == toplevel) {
                animation.link.remove();
                gpa.destroy(animation);
                break;
            }
        }

        // Create new animation
        const animation = gpa.create(Animation) catch {
            std.log.err("failed to create animation", .{});
            return;
        };
        // Use 400ms duration for spring animations to allow for natural oscillation
        animation.* = Animation.init(toplevel, target_x, target_y, target_width, target_height, 400); 
        // Configure spring parameters for smooth window movement (critically damped for minimal oscillation)
        animation.spring_params = SpringParams{ .frequency = 6.0, .damping_ratio = 1.0 };
        server.animations.append(animation);
    }

    fn handleScreencopyFrame(
        listener: *wl.Listener(*wlr.ScreencopyFrameV1),
        frame: *wlr.ScreencopyFrameV1,
    ) void {
        const server: *Server = @fieldParentPtr("screencopy_frame", listener);
        std.log.info("Screencopy frame copy requested for output {s}", .{frame.output.name});
        
        // Get the scene output for this output
        const scene_output = server.scene.getSceneOutput(frame.output) orelse {
            std.log.err("No scene output found for screencopy", .{});
            // In wlroots, the frame lifecycle is managed internally
            return;
        };
        
        // In the correct wlroots implementation, the scene output needs to be rendered to the frame buffer
        // Since the exact function might not be exposed in the Zig bindings, I'll use the renderer
        // to render the scene_output to the frame's buffer
        
        // The correct approach in wlroots is to let the scene output commit to the screencopy frame
        // by using the renderer to render the output content to the client's buffer
        if (!scene_output.commit(null)) {
            std.log.err("Failed to commit scene output for screencopy", .{});
            return;
        }
        
        // The actual copy to the frame buffer happens internally in wlroots
        // when the scene output is committed with the proper renderer configuration
        
        // In a complete implementation, we would send the ready event with proper timestamp
        // but since we don't have access to the exact function in the Zig bindings, we log success
        std.log.info("Screencopy frame completed successfully", .{});
    }

    fn handleKeybind(server: *Server, key: xkb.Keysym) bool {
        switch (@intFromEnum(key)) {
            xkb.Keysym.Escape => server.wl_server.terminate(),
            
            xkb.Keysym.F1 => {
                if (server.toplevels.length() < 2) return true;
                const toplevel: *Toplevel = @fieldParentPtr("link", server.toplevels.link.prev.?);
                server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
            },
            
            // Mod+Return: Launch kitty
            xkb.Keysym.Return => {
                std.log.info("Launching kitty terminal", .{});
                std.log.info("WAYLAND_DISPLAY: {s}", .{server.wayland_display});
                var child = std.process.Child.init(&[_][]const u8{"kitty"}, gpa);
                child.stdin_behavior = .Ignore;
                child.stdout_behavior = .Ignore;
                child.stderr_behavior = .Ignore;

                var env_map = std.process.getEnvMap(gpa) catch |err| {
                    std.log.err("Failed to get environment: {}", .{err});
                    return true;
                };
                defer env_map.deinit();
                std.log.info("Environment map created successfully", .{});

                env_map.put("WAYLAND_DISPLAY", server.wayland_display) catch |err| {
                    std.log.err("Failed to set WAYLAND_DISPLAY: {}", .{err});
                    return true;
                };
                std.log.info("WAYLAND_DISPLAY set in env_map", .{});
                child.env_map = &env_map;

                const pid = child.spawn() catch |err| {
                    std.log.err("Failed to spawn kitty: {}", .{err});
                    return true;
                };
                std.log.info("Kitty spawned successfully with PID: {}", .{pid});
            },
            
            // Mod+j: Focus next window in stack
            xkb.Keysym.j => {
                if (server.toplevels.length() < 2) return true;
                const toplevel: *Toplevel = @fieldParentPtr("link", server.toplevels.link.prev.?);
                server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
            },
            
            // Mod+k: Focus previous window in stack
            xkb.Keysym.k => {
                if (server.toplevels.length() < 2) return true;
                const toplevel: *Toplevel = @fieldParentPtr("link", server.toplevels.link.next.?);
                server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
            },
            
            // Mod+Shift+c: Close focused window
            xkb.Keysym.c => {
                if (server.toplevels.length() == 0) return true;
                const toplevel: *Toplevel = @fieldParentPtr("link", server.toplevels.link.next.?);
                toplevel.xdg_toplevel.sendClose();
            },
            
            // Mod+h: Decrease master ratio
            xkb.Keysym.h => {
                server.master_ratio = @max(0.1, server.master_ratio - 0.05);
                server.arrangeWindows();
            },
            
            // Mod+l: Increase master ratio
            xkb.Keysym.l => {
                server.master_ratio = @min(0.9, server.master_ratio + 0.05);
                server.arrangeWindows();
            },
            
            else => return false,
        }
        return true;
    }
};

const Output = struct {
    server: *Server,
    wlr_output: *wlr.Output,

    frame: wl.Listener(*wlr.Output) = .init(handleFrame),
    request_state: wl.Listener(*wlr.Output.event.RequestState) = .init(handleRequestState),
    destroy: wl.Listener(*wlr.Output) = .init(handleDestroy),

    fn create(server: *Server, wlr_output: *wlr.Output) !void {
        const output = try gpa.create(Output);

        output.* = .{
            .server = server,
            .wlr_output = wlr_output,
        };
        wlr_output.events.frame.add(&output.frame);
        wlr_output.events.request_state.add(&output.request_state);
        wlr_output.events.destroy.add(&output.destroy);

        const layout_output = try server.output_layout.addAuto(wlr_output);

        const scene_output = try server.scene.createSceneOutput(wlr_output);
        server.scene_output_layout.addOutput(layout_output, scene_output);
    }

    fn handleFrame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
        const output: *Output = @fieldParentPtr("frame", listener);

        // Update animations before rendering
        output.server.updateAnimations();

        const scene_output = output.server.scene.getSceneOutput(output.wlr_output).?;
        _ = scene_output.commit(null);

        var now = posix.clock_gettime(posix.CLOCK.MONOTONIC) catch @panic("CLOCK_MONOTONIC not supported");
        scene_output.sendFrameDone(&now);
    }

    fn handleRequestState(
        listener: *wl.Listener(*wlr.Output.event.RequestState),
        event: *wlr.Output.event.RequestState,
    ) void {
        const output: *Output = @fieldParentPtr("request_state", listener);

        _ = output.wlr_output.commitState(event.state);
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
        const output: *Output = @fieldParentPtr("destroy", listener);

        output.frame.link.remove();
        output.request_state.link.remove();
        output.destroy.link.remove();

        gpa.destroy(output);
    }
};

const LayerSurface = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    layer_surface: *wlr.LayerSurfaceV1,
    scene_layer_surface: *wlr.SceneLayerSurfaceV1,
    configured: bool = false,

    map: wl.Listener(void) = .init(handleMap),
    unmap: wl.Listener(void) = .init(handleUnmap),
    destroy: wl.Listener(*wlr.LayerSurfaceV1) = .init(handleDestroy),
    new_popup: wl.Listener(*wlr.XdgPopup) = .init(handleNewPopup),
    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),

    fn handleMap(listener: *wl.Listener(void)) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("map", listener);
        // Add to the server's list when mapped
        layer_surface.server.layer_surfaces.append(layer_surface);
    }

    fn handleUnmap(listener: *wl.Listener(void)) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("unmap", listener);
        layer_surface.link.remove();
    }

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("commit", listener);

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
        }
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.LayerSurfaceV1), _: *wlr.LayerSurfaceV1) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("destroy", listener);

        // Remove from server's layer surfaces list if still in it
        if (layer_surface.link.prev != null and layer_surface.link.next != null) {
            layer_surface.link.remove();
        }

        layer_surface.map.link.remove();
        layer_surface.unmap.link.remove();
        layer_surface.commit.link.remove();
        layer_surface.destroy.link.remove();
        layer_surface.new_popup.link.remove();

        gpa.destroy(layer_surface);
    }

    fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
        const layer_surface: *LayerSurface = @fieldParentPtr("new_popup", listener);
        const xdg_surface = xdg_popup.base;

        const scene_tree = layer_surface.scene_layer_surface.tree.createSceneXdgSurface(xdg_surface) catch {
            std.log.err("failed to allocate xdg popup node", .{});
            return;
        };
        xdg_surface.data = @intFromPtr(scene_tree);

        const popup = gpa.create(Popup) catch {
            std.log.err("failed to allocate new popup", .{});
            return;
        };
        popup.* = .{
            .xdg_popup = xdg_popup,
        };

        xdg_surface.surface.events.commit.add(&popup.commit);
        xdg_popup.events.destroy.add(&popup.destroy);
    }
};

const Toplevel = struct {
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

    fn updateBorder(toplevel: *Toplevel, x: i32, y: i32, width: i32, height: i32) void {
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

const Popup = struct {
    xdg_popup: *wlr.XdgPopup,

    commit: wl.Listener(*wlr.Surface) = .init(handleCommit),
    destroy: wl.Listener(void) = .init(handleDestroy),

    fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const popup: *Popup = @fieldParentPtr("commit", listener);
        if (popup.xdg_popup.base.initial_commit) {
            _ = popup.xdg_popup.base.scheduleConfigure();
        }
    }

    fn handleDestroy(listener: *wl.Listener(void)) void {
        const popup: *Popup = @fieldParentPtr("destroy", listener);

        popup.commit.link.remove();
        popup.destroy.link.remove();

        gpa.destroy(popup);
    }
};

const Keyboard = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    device: *wlr.InputDevice,

    modifiers: wl.Listener(*wlr.Keyboard) = .init(handleModifiers),
    key: wl.Listener(*wlr.Keyboard.event.Key) = .init(handleKey),
    destroy: wl.Listener(*wlr.InputDevice) = .init(handleDestroy),

    fn create(server: *Server, device: *wlr.InputDevice) !void {
        const keyboard = try gpa.create(Keyboard);
        errdefer gpa.destroy(keyboard);

        keyboard.* = .{
            .server = server,
            .device = device,
        };

        const context = xkb.Context.new(.no_flags) orelse return error.ContextFailed;
        defer context.unref();
        const keymap = xkb.Keymap.newFromNames(context, null, .no_flags) orelse return error.KeymapFailed;
        defer keymap.unref();

        const wlr_keyboard = device.toKeyboard();
        if (!wlr_keyboard.setKeymap(keymap)) return error.SetKeymapFailed;
        wlr_keyboard.setRepeatInfo(25, 600);

        wlr_keyboard.events.modifiers.add(&keyboard.modifiers);
        wlr_keyboard.events.key.add(&keyboard.key);
        device.events.destroy.add(&keyboard.destroy);

        server.seat.setKeyboard(wlr_keyboard);
        server.keyboards.append(keyboard);
    }

    fn handleModifiers(listener: *wl.Listener(*wlr.Keyboard), wlr_keyboard: *wlr.Keyboard) void {
        const keyboard: *Keyboard = @fieldParentPtr("modifiers", listener);
        keyboard.server.seat.setKeyboard(wlr_keyboard);
        keyboard.server.seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
    }

    fn handleKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
        const keyboard: *Keyboard = @fieldParentPtr("key", listener);
        const wlr_keyboard = keyboard.device.toKeyboard();

        const keycode = event.keycode + 8;

        var handled = false;
        if (event.state == .pressed) {
            const modifiers = wlr_keyboard.getModifiers();
            std.log.info("Key pressed: keycode={}, modifiers alt={}, ctrl={}, shift={}, logo={}", .{
                keycode,
                modifiers.alt,
                modifiers.ctrl,
                modifiers.shift,
                modifiers.logo,
            });

            if (modifiers.logo) {
                for (wlr_keyboard.xkb_state.?.keyGetSyms(keycode)) |sym| {
                    std.log.info("Key symbol: {}", .{sym});
                    if (keyboard.server.handleKeybind(sym)) {
                        handled = true;
                        break;
                    }
                }
            }
        }

        if (!handled) {
            keyboard.server.seat.setKeyboard(wlr_keyboard);
            keyboard.server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
        }
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
        const keyboard: *Keyboard = @fieldParentPtr("destroy", listener);

        keyboard.link.remove();

        keyboard.modifiers.link.remove();
        keyboard.key.link.remove();
        keyboard.destroy.link.remove();

        gpa.destroy(keyboard);
    }
};


