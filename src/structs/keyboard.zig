const std = @import("std");

const wl = @import("wayland").server.wl;

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const gpa = std.heap.c_allocator;

const Server = @import("../core/server.zig").Server;
const Toplevel = @import("../structs/toplevel.zig").Toplevel;
const config = @import("../config.zig");

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
                std.log.info("Key symbol: {}", .{sym});
                
                // Check against configured keybinds by iterating through config
                const sym_int = @intFromEnum(sym);
                inline for (config.keys) |keybind| {
                    var match = sym_int == keybind.keysym;
                    
                    // Check if modifiers match based on our MOD constants
                    if (match) {
                        if (config.MOD.LOGO == keybind.modifiers) {
                            match = modifiers.logo and !modifiers.shift and !modifiers.ctrl and !modifiers.alt;
                        } else if (config.MOD.LOGO_SHIFT == keybind.modifiers) {
                            match = modifiers.logo and modifiers.shift and !modifiers.ctrl and !modifiers.alt;
                        } else if (config.MOD.NONE == keybind.modifiers) {
                            match = !modifiers.logo and !modifiers.shift and !modifiers.ctrl and !modifiers.alt;
                        } else if (config.MOD.SHIFT == keybind.modifiers) {
                            match = modifiers.shift and !modifiers.logo and !modifiers.ctrl and !modifiers.alt;
                        } else if (config.MOD.CTRL == keybind.modifiers) {
                            match = modifiers.ctrl and !modifiers.logo and !modifiers.shift and !modifiers.alt;
                        } else if (config.MOD.ALT == keybind.modifiers) {
                            match = modifiers.alt and !modifiers.logo and !modifiers.shift and !modifiers.ctrl;
                        } else {
                            match = false;
                        }
                    }
                    
                    if (match) {
                        // Check if this keybind has an action to execute
                        if (keybind.action != .none) {
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
    fn executeAction(keyboard: *Keyboard, action: config.Action) void {
        std.log.info("Executing action: {}", .{action});
        
        switch (action) {
            .focus_next => {
                if (keyboard.server.toplevels.length() < 2) return;
                // Focus the next window (second in list since first is current focus)
                var it = keyboard.server.toplevels.iterator(.forward);
                _ = it.next(); // Skip the currently focused window
                if (it.next()) |next_toplevel| {
                    keyboard.server.focusView(next_toplevel, next_toplevel.xdg_toplevel.base.surface, true);
                }
            },
            .focus_prev => {
                if (keyboard.server.toplevels.length() < 2) return;
                // Focus the previous window (last in list - cycles back to end)
                var prev_toplevel: ?*Toplevel = null;
                var it = keyboard.server.toplevels.iterator(.forward);
                while (it.next()) |toplevel| {
                    prev_toplevel = toplevel;
                }
                if (prev_toplevel) |toplevel| {
                    keyboard.server.focusView(toplevel, toplevel.xdg_toplevel.base.surface, true);
                }
            },
            .close_window => {
                if (keyboard.server.toplevels.length() == 0) return;
                // Close the currently focused window (first in list)
                var it = keyboard.server.toplevels.iterator(.forward);
                if (it.next()) |toplevel| {
                    toplevel.xdg_toplevel.sendClose();
                }
            },
            .increase_ratio => {
                keyboard.server.master_ratio = @min(0.9, keyboard.server.master_ratio + 0.05);
                keyboard.server.arrangeWindows();
            },
            .decrease_ratio => {
                keyboard.server.master_ratio = @max(0.1, keyboard.server.master_ratio - 0.05);
                keyboard.server.arrangeWindows();
            },
            .quit => {
                keyboard.server.wl_server.terminate();
            },
            .none => {}, // Do nothing
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
            keyboard.server.master_ratio = @max(0.1, keyboard.server.master_ratio - 0.05);
            keyboard.server.arrangeWindows();
        } else if (std.mem.eql(u8, cmd, "increase_ratio")) {
            keyboard.server.master_ratio = @min(0.9, keyboard.server.master_ratio + 0.05);
            keyboard.server.arrangeWindows();
        } else if (std.mem.eql(u8, cmd, "kitty") or 
                   std.mem.eql(u8, cmd, "terminal")) {
            // Launch external command
            keyboard.launchCommand(cmd);
        }
    }
    
    // Launch external command
    fn launchCommand(keyboard: *Keyboard, cmd: []const u8) void {
        var command_to_run: []const u8 = cmd;
        
        // Look up command in config if it's a predefined name
        for (config.commands) |command| {
            if (std.mem.eql(u8, command.name, cmd)) {
                command_to_run = command.cmd;
                break;
            }
        }
        
        std.log.info("Launching command: {s}", .{command_to_run});
        
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
