const std = @import("std");

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const gpa = std.heap.c_allocator;

const Server = @import("../core/server.zig").Server;
const Toplevel = @import("../structs/toplevel.zig").Toplevel;
const config_parser = @import("../config_parser.zig");
const MOD = config_parser.MOD;
const Action = config_parser.Action;

pub const Keyboard = struct {
    server: *Server,
    link: wl.list.Link = undefined,
    device: *wlr.InputDevice,

    modifiers: wl.Listener(*wlr.Keyboard) = .init(handleModifiers),
    key: wl.Listener(*wlr.Keyboard.event.Key) = .init(handleKey),
    destroy: wl.Listener(*wlr.InputDevice) = .init(handleDestroy),

    pub fn create(server: *Server, device: *wlr.InputDevice) !void {
        const keyboard = try gpa.create(Keyboard);
        errdefer gpa.destroy(keyboard);

        keyboard.* = .{
            .server = server,
            .device = device,
        };

        const context = xkb.Context.new(.no_flags) orelse return error.ContextFailed;
        defer context.unref();

        // Try to load keymap from file first, otherwise build from rules
        const keymap = blk: {
            if (server.config.xkb_file) |file_path| {
                std.log.info("Loading XKB keymap from file: {s}", .{file_path});
                const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                    std.log.err("Failed to open XKB file {s}: {}", .{file_path, err});
                    break :blk null;
                };
                defer file.close();

                const file_size = (file.stat() catch |err| {
                    std.log.err("Failed to stat XKB file: {}", .{err});
                    break :blk null;
                }).size;

                // Allocate with +1 for null terminator
                const contents = gpa.allocSentinel(u8, file_size, 0) catch |err| {
                    std.log.err("Failed to allocate memory for XKB file: {}", .{err});
                    break :blk null;
                };
                defer gpa.free(contents);

                _ = file.readAll(contents) catch |err| {
                    std.log.err("Failed to read XKB file: {}", .{err});
                    break :blk null;
                };

                break :blk xkb.Keymap.newFromString(context, contents.ptr, .text_v1, .no_flags);
            } else {
                // Build keymap from rules (layout, options, etc.)
                // Note: strings from config parser are already null-terminated since they're duped from KDL strings
                var rule_names = xkb.RuleNames{
                    .rules = if (server.config.xkb_rules) |r| @as([*:0]const u8, @ptrCast(r.ptr)) else null,
                    .model = if (server.config.xkb_model) |m| @as([*:0]const u8, @ptrCast(m.ptr)) else null,
                    .layout = if (server.config.xkb_layout) |l| @as([*:0]const u8, @ptrCast(l.ptr)) else null,
                    .variant = if (server.config.xkb_variant) |v| @as([*:0]const u8, @ptrCast(v.ptr)) else null,
                    .options = if (server.config.xkb_options) |o| @as([*:0]const u8, @ptrCast(o.ptr)) else null,
                };

                std.log.info("Creating XKB keymap with rules: layout={s}, options={s}, model={s}, variant={s}, rules={s}", .{
                    if (server.config.xkb_layout) |l| l else "default",
                    if (server.config.xkb_options) |o| o else "none",
                    if (server.config.xkb_model) |m| m else "default",
                    if (server.config.xkb_variant) |v| v else "default",
                    if (server.config.xkb_rules) |r| r else "default",
                });

                break :blk xkb.Keymap.newFromNames(context, &rule_names, .no_flags);
            }
        } orelse return error.KeymapFailed;
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
            const xkb_state = wlr_keyboard.xkb_state.?;
            
            // Get modifiers using the same approach as original code
            const modifiers = wlr_keyboard.getModifiers();
            
            // Log modifier state using the same approach as before
            std.log.info("Key pressed: keycode={}, modifiers alt={}, ctrl={}, shift={}, logo={}", .{
                keycode,
                modifiers.alt,
                modifiers.ctrl,
                modifiers.shift,
                modifiers.logo,
            });

            for (xkb_state.keyGetSyms(keycode)) |sym| {
                const sym_int = @intFromEnum(sym);
                std.log.info("Key symbol: {} (int: {})", .{sym, sym_int});

                // Check against configured keybinds by iterating through runtime config
                for (keyboard.server.config.keybinds.items) |keybind| {
                    var match = sym_int == keybind.keysym;

                    if (match) {
                        std.log.info("Found matching keysym! Checking modifiers: keybind.mod={} logo={} shift={} ctrl={} alt={}", .{keybind.modifiers, modifiers.logo, modifiers.shift, modifiers.ctrl, modifiers.alt});
                    }

                    // Check if modifiers match based on our MOD constants
                    if (match) {
                        if (MOD.LOGO == keybind.modifiers) {
                            match = modifiers.logo and !modifiers.shift and !modifiers.ctrl and !modifiers.alt;
                        } else if (MOD.LOGO_SHIFT == keybind.modifiers) {
                            match = modifiers.logo and modifiers.shift and !modifiers.ctrl and !modifiers.alt;
                        } else if (MOD.NONE == keybind.modifiers) {
                            match = !modifiers.logo and !modifiers.shift and !modifiers.ctrl and !modifiers.alt;
                        } else if (MOD.SHIFT == keybind.modifiers) {
                            match = modifiers.shift and !modifiers.logo and !modifiers.ctrl and !modifiers.alt;
                        } else if (MOD.CTRL == keybind.modifiers) {
                            match = modifiers.ctrl and !modifiers.logo and !modifiers.shift and !modifiers.alt;
                        } else if (MOD.ALT == keybind.modifiers) {
                            match = modifiers.alt and !modifiers.logo and !modifiers.shift and !modifiers.ctrl;
                        } else {
                            match = false;
                        }
                    }

                    if (match) {
                        std.log.info("MATCH! Executing action: {}", .{keybind.action});
                        // Check if this keybind has an action to execute
                        if (keybind.action == .spawn) {
                            // Spawn action needs the cmd string
                            keyboard.launchCommand(keybind.cmd);
                        } else if (keybind.action == .switch_workspace) {
                            // Switch workspace needs cmd string with workspace ID
                            keyboard.executeActionWithParam(keybind.action, keybind.cmd);
                        } else if (keybind.action != .none) {
                            keyboard.executeAction(keybind.action);
                        } else {
                            // Fall back to executing command string
                            keyboard.executeCommand(keybind.cmd);
                        }
                        handled = true;
                        break;
                    }
                }
                
                if (handled) break;
            }
        }

        if (!handled) {
            keyboard.server.seat.setKeyboard(wlr_keyboard);
            keyboard.server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
        }
    }
    
    // Execute action based on the Action enum
    fn executeAction(keyboard: *Keyboard, action: Action) void {
        std.log.info("Executing action: {}", .{action});

        switch (action) {
            .focus_next => {
                const active_workspace = keyboard.server.active_workspace orelse return;
                const toplevel_count = active_workspace.getClientCount();
                std.log.info("Focus next action triggered, total toplevels in workspace: {}", .{toplevel_count});
                if (toplevel_count < 2) {
                    std.log.info("Not enough windows to focus next", .{});
                    return;
                }
                // Focus the next window (second in list since first is current focus)
                var it = active_workspace.getToplevelIterator();
                const current_toplevel = it.next();
                std.log.info("Current focused toplevel: {*}", .{current_toplevel});
                if (current_toplevel) |_| {
                    _ = it.next(); // Skip the currently focused window
                }
                if (it.next()) |next_toplevel| {
                    std.log.info("Focusing next toplevel at {*}", .{next_toplevel});
                    keyboard.server.focusView(next_toplevel, next_toplevel.xdg_toplevel.base.surface, true);
                } else {
                    std.log.info("No next toplevel found", .{});
                }
            },
            .focus_prev => {
                const active_workspace = keyboard.server.active_workspace orelse return;
                const toplevel_count = active_workspace.getClientCount();
                std.log.info("Focus prev action triggered, total toplevels in workspace: {}", .{toplevel_count});
                if (toplevel_count < 2) {
                    std.log.info("Not enough windows to focus prev", .{});
                    return;
                }
                // Focus the previous window (last in list - cycles back to end)
                var prev_toplevel: ?*Toplevel = null;
                var it = active_workspace.getToplevelIterator();
                var count: usize = 0;
                while (it.next()) |toplevel| {
                    prev_toplevel = toplevel;
                    count += 1;
                }
                std.log.info("Found {} toplevels, focusing last one", .{count});
                if (prev_toplevel) |toplevel| {
                    std.log.info("Focusing previous toplevel at {*}", .{toplevel});
                    keyboard.server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
                } else {
                    std.log.info("No previous toplevel found", .{});
                }
            },
            .focus_left, .focus_right => {
                // TODO: Implement directional focus
                std.log.info("Directional focus not yet implemented", .{});
            },
            .close_window => {
                std.log.info("Close window action triggered", .{});
                const active_workspace = keyboard.server.active_workspace orelse return;
                if (active_workspace.getClientCount() == 0) {
                    std.log.info("No windows to close", .{});
                    return;
                }
                // Close the currently focused window (first in list)
                var it = active_workspace.getToplevelIterator();
                if (it.next()) |toplevel| {
                    std.log.info("Sending close request to toplevel at {*}, xdg_toplevel at {*}", .{ toplevel, toplevel.xdg_toplevel });
                    toplevel.xdg_toplevel.sendClose();
                } else {
                    std.log.info("No toplevel found to close", .{});
                }
            },
            .increase_ratio => {
                std.log.info("Increasing master ratio from {} to {}", .{ keyboard.server.config.master_ratio, @min(0.9, keyboard.server.config.master_ratio + 0.05) });
                keyboard.server.config.master_ratio = @min(0.9, keyboard.server.config.master_ratio + 0.05);
                keyboard.server.arrangeWindows();
            },
            .decrease_ratio => {
                std.log.info("Decreasing master ratio from {} to {}", .{ keyboard.server.config.master_ratio, @max(0.1, keyboard.server.config.master_ratio - 0.05) });
                keyboard.server.config.master_ratio = @max(0.1, keyboard.server.config.master_ratio - 0.05);
                keyboard.server.arrangeWindows();
            },
            .quit => {
                std.log.info("Quit action triggered", .{});
                keyboard.server.wl_server.terminate();
            },
            .reload_config => {
                std.log.info("Reload config action triggered", .{});
                keyboard.server.reloadConfig() catch |err| {
                    std.log.err("Failed to reload config: {}", .{err});
                };
            },
            .switch_workspace => {
                // Workspace switching is handled via cmd parameter with workspace ID
                std.log.info("Switch workspace action (requires cmd parameter)", .{});
            },
            .none, .spawn => {}, // Do nothing (spawn is handled elsewhere)
        }
    }

    // Execute action with parameter (e.g., workspace ID)
    fn executeActionWithParam(keyboard: *Keyboard, action: Action, param: []const u8) void {
        std.log.info("Executing action: {} with param: {s}", .{action, param});

        switch (action) {
            .switch_workspace => {
                // Extract workspace ID from param (e.g., "workspace-1" -> 1)
                const workspace_id = std.fmt.parseInt(u32, param, 10) catch {
                    std.log.err("Invalid workspace ID: {s}", .{param});
                    return;
                };
                std.log.info("Switching to workspace {d}", .{workspace_id});
                keyboard.server.switchToWorkspace(workspace_id) catch |err| {
                    std.log.err("Failed to switch workspace: {}", .{err});
                };
            },
            else => {
                std.log.warn("Action {} does not support parameters", .{action});
            },
        }
    }

    // Execute command based on its string identifier
    fn executeCommand(keyboard: *Keyboard, cmd: []const u8) void {
        std.log.info("Executing command: {s}", .{cmd});
        
        if (std.mem.eql(u8, cmd, "quit")) {
            keyboard.server.wl_server.terminate();
        } else if (std.mem.eql(u8, cmd, "focus_next")) {
            // Keep for backwards compatibility
            if (keyboard.server.toplevels.length() < 2) return;
            var it = keyboard.server.toplevels.iterator(.forward);
            _ = it.next(); // Skip the currently focused window
            if (it.next()) |next_toplevel| {
                keyboard.server.focusView(next_toplevel, next_toplevel.xdg_toplevel.base.surface, true);
            }
        } else if (std.mem.eql(u8, cmd, "focus_prev")) {
            // Keep for backwards compatibility
            if (keyboard.server.toplevels.length() < 2) return;
            var prev_toplevel: ?*Toplevel = null;
            var it = keyboard.server.toplevels.iterator(.forward);
            while (it.next()) |toplevel| {
                prev_toplevel = toplevel;
            }
            if (prev_toplevel) |toplevel| {
                keyboard.server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
            }
        } else if (std.mem.eql(u8, cmd, "close_window")) {
            if (keyboard.server.toplevels.length() == 0) return;
            // Close the currently focused window (first in list)
            var it = keyboard.server.toplevels.iterator(.forward);
            if (it.next()) |toplevel| {
                toplevel.xdg_toplevel.sendClose();
            }
        } else if (std.mem.eql(u8, cmd, "decrease_ratio")) {
            keyboard.server.config.master_ratio = @max(0.1, keyboard.server.config.master_ratio - 0.05);
            keyboard.server.arrangeWindows();
        } else if (std.mem.eql(u8, cmd, "increase_ratio")) {
            keyboard.server.config.master_ratio = @min(0.9, keyboard.server.config.master_ratio + 0.05);
            keyboard.server.arrangeWindows();
        } else if (std.mem.startsWith(u8, cmd, "switch_workspace_")) {
            // Extract workspace ID from command (e.g., "switch_workspace_1")
            const workspace_id_str = cmd["switch_workspace_".len..];
            const workspace_id = std.fmt.parseInt(u32, workspace_id_str, 10) catch {
                std.log.err("Invalid workspace ID: {s}", .{workspace_id_str});
                return;
            };
            std.log.info("Switching to workspace {d}", .{workspace_id});
            keyboard.server.switchToWorkspace(workspace_id) catch |err| {
                std.log.err("Failed to switch workspace: {}", .{err});
            };
        } else if (std.mem.eql(u8, cmd, "kitty") or
                   std.mem.eql(u8, cmd, "terminal")) {
            // Launch external command
            keyboard.launchCommand(cmd);
        }
    }
    
    // Launch external command
    fn launchCommand(keyboard: *Keyboard, cmd: []const u8) void {
        std.log.info("launchCommand called with: '{s}'", .{cmd});
        var command_to_run: []const u8 = cmd;

        // Look up command in config if it's a predefined name
        for (keyboard.server.config.commands.items) |command| {
            std.log.info("Checking command '{s}' == '{s}'?", .{command.name, cmd});
            if (std.mem.eql(u8, command.name, cmd)) {
                command_to_run = command.cmd;
                std.log.info("Found in config, using: '{s}'", .{command_to_run});
                break;
            }
        }

        std.log.info("About to spawn: {s}", .{command_to_run});
        
        var child = std.process.Child.init(&[_][]const u8{ command_to_run }, gpa);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        var env_map = std.process.getEnvMap(gpa) catch |err| {
            std.log.err("Failed to get environment: {}", .{err});
            return;
        };
        defer env_map.deinit();
        
        env_map.put("WAYLAND_DISPLAY", keyboard.server.wayland_display) catch |err| {
            std.log.err("Failed to set WAYLAND_DISPLAY: {}", .{err});
            return;
        };
        child.env_map = &env_map;

        child.spawn() catch |err| {
            std.log.err("Failed to spawn command {s}: {}", .{ command_to_run, err });
            return;
        };
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
