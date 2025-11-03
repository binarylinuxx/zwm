const std = @import("std");
const xkb = @import("xkbcommon");
const simple_kdl = @import("simple_kdl.zig");

// Helper function to convert hex color string to RGBA array
pub fn hexToRGBA(hexStr: []const u8) [4]f32 {
    var hex: u32 = 0;

    // Handle # prefix if present
    var start: usize = 0;
    if (hexStr.len > 0 and hexStr[0] == '#') {
        start = 1;
    }

    // Validate and parse hex string
    const hexLen = hexStr.len - start;
    if (hexLen < 6 or hexLen > 8) {
        // Default to white if invalid
        return [4]f32{ 1.0, 1.0, 1.0, 1.0 };
    }

    // Parse hex string to integer
    const slice = hexStr[start..];
    const parsed = std.fmt.parseInt(u32, slice, 16) catch {
        // Default to white if parsing fails
        return [4]f32{ 1.0, 1.0, 1.0, 1.0 };
    };

    // Handle different hex formats
    if (hexLen == 3) {
        const r = (parsed >> 8) & 0xF;
        const g = (parsed >> 4) & 0xF;
        const b = parsed & 0xF;
        hex = ((r << 4) | r) << 16 | (((g << 4) | g) << 8) | ((b << 4) | b);
    } else if (hexLen == 4) {
        const r = (parsed >> 12) & 0xF;
        const g = (parsed >> 8) & 0xF;
        const b = (parsed >> 4) & 0xF;
        const a = parsed & 0xF;
        hex = ((r << 4) | r) << 16 | (((g << 4) | g) << 8) | ((b << 4) | b) | (((a << 4) | a) << 24);
    } else if (hexLen == 6) {
        hex = parsed | 0xFF000000;
    } else if (hexLen == 8) {
        hex = parsed;
    }

    const r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0;
    const g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0;
    const b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0;
    const a = @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0;
    return [4]f32{ r, g, b, a };
}

// Modifier constants (using bitmasks)
pub const MOD = struct {
    pub const NONE: u32 = 0;
    pub const LOGO: u32 = 1;
    pub const SHIFT: u32 = 2;
    pub const CTRL: u32 = 4;
    pub const ALT: u32 = 8;
    pub const LOGO_SHIFT: u32 = LOGO | SHIFT;
    pub const LOGO_CTRL: u32 = LOGO | CTRL;
    pub const LOGO_ALT: u32 = LOGO | ALT;
};

// Key sym constants
pub const Keysym = struct {
    pub const Escape: c_int = 0x0000FF1B;
    pub const Return: c_int = 0x0000FF0D;
    pub const j: c_int = 0x0000006A;
    pub const k: c_int = 0x0000006B;
    pub const c: c_int = 0x00000063;
    pub const h: c_int = 0x00000068;
    pub const l: c_int = 0x0000006C;
    pub const q: c_int = 0x00000071;
    pub const F1: c_int = 0x0000FFBE;
    pub const Left: c_int = 0x0000FF51;
    pub const Right: c_int = 0x0000FF53;
    pub const Up: c_int = 0x0000FF52;
    pub const Down: c_int = 0x0000FF54;
};

// Action enum for predefined actions
pub const Action = enum {
    none,
    focus_next,
    focus_prev,
    focus_left,
    focus_right,
    close_window,
    increase_ratio,
    decrease_ratio,
    quit,
    reload_config,
    spawn,
};

// Key binding structure
pub const KeyBind = struct {
    modifiers: u32,
    keysym: c_int,
    cmd: []const u8,
    action: Action = .none,
};

// Command structure
pub const Command = struct {
    name: []const u8,
    cmd: []const u8,
};

// Blur configuration structure
pub const BlurConfig = struct {
    enabled: bool = false,
    num_passes: i32 = 2,
    radius: f32 = 5.0,
    noise: f32 = 0.02,
    brightness: f32 = 0.9,
    contrast: f32 = 0.9,
    saturation: f32 = 1.0,
};

// Configuration structure
pub const Config = struct {
    // Visual settings
    active_border: [4]f32,
    inactive_border: [4]f32,
    background: [4]f32,
    text: [4]f32,
    border_width: i32,
    corner_radius: i32,
    gap_size: i32,

    // Blur settings
    blur: BlurConfig,

    // Layout settings
    master_ratio: f32,

    // Animation settings
    animation_duration: u32,
    spring_frequency: f32,
    spring_damping_ratio: f32,

    // Keybindings and commands
    keybinds: std.ArrayList(KeyBind),
    commands: std.ArrayList(Command),

    // XKB settings
    xkb_layout: []const u8,
    xkb_options: []const u8,

    // Environment variables
    environment: std.StringHashMap([]const u8),

    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        self.keybinds.deinit();
        self.commands.deinit();
        self.environment.deinit();
    }
};

// Parse modifier string like "Mod+Shift" into bitmask
fn parseModifiers(mod_str: []const u8) u32 {
    var result: u32 = 0;
    var iter = std.mem.splitSequence(u8, mod_str, "+");

    while (iter.next()) |part| {
        if (std.mem.eql(u8, part, "Mod") or std.mem.eql(u8, part, "Logo")) {
            result |= MOD.LOGO;
        } else if (std.mem.eql(u8, part, "Shift")) {
            result |= MOD.SHIFT;
        } else if (std.mem.eql(u8, part, "Ctrl")) {
            result |= MOD.CTRL;
        } else if (std.mem.eql(u8, part, "Alt")) {
            result |= MOD.ALT;
        } else if (std.mem.eql(u8, part, "None")) {
            result = MOD.NONE;
        }
    }

    return result;
}

// Parse key string to keysym
fn parseKeysym(key_str: []const u8) !c_int {
    // Single character keys
    if (key_str.len == 1) {
        const c = key_str[0];
        if (c >= 'a' and c <= 'z') {
            return @as(c_int, c);
        }
        if (c >= '0' and c <= '9') {
            return @as(c_int, c);
        }
    }

    // Special keys
    if (std.mem.eql(u8, key_str, "Escape")) return Keysym.Escape;
    if (std.mem.eql(u8, key_str, "Return")) return Keysym.Return;
    if (std.mem.eql(u8, key_str, "Left")) return Keysym.Left;
    if (std.mem.eql(u8, key_str, "Right")) return Keysym.Right;
    if (std.mem.eql(u8, key_str, "Up")) return Keysym.Up;
    if (std.mem.eql(u8, key_str, "Down")) return Keysym.Down;
    if (std.mem.eql(u8, key_str, "F1")) return Keysym.F1;

    return error.UnknownKeysym;
}

// Parse action string
fn parseAction(action_str: []const u8) Action {
    if (std.mem.eql(u8, action_str, "focus-next") or std.mem.eql(u8, action_str, "focus_next")) return .focus_next;
    if (std.mem.eql(u8, action_str, "focus-prev") or std.mem.eql(u8, action_str, "focus_prev")) return .focus_prev;
    if (std.mem.eql(u8, action_str, "focus-left") or std.mem.eql(u8, action_str, "focus_left")) return .focus_left;
    if (std.mem.eql(u8, action_str, "focus-right") or std.mem.eql(u8, action_str, "focus_right")) return .focus_right;
    if (std.mem.eql(u8, action_str, "close-window") or std.mem.eql(u8, action_str, "close_window")) return .close_window;
    if (std.mem.eql(u8, action_str, "increase-ratio") or std.mem.eql(u8, action_str, "increase_ratio")) return .increase_ratio;
    if (std.mem.eql(u8, action_str, "decrease-ratio") or std.mem.eql(u8, action_str, "decrease_ratio")) return .decrease_ratio;
    if (std.mem.eql(u8, action_str, "quit")) return .quit;
    if (std.mem.eql(u8, action_str, "reload-config") or std.mem.eql(u8, action_str, "reload_config")) return .reload_config;
    if (std.mem.eql(u8, action_str, "spawn")) return .spawn;

    return .none;
}

// Get the config directory path (~/.config/zwm)
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "zwm" });
}

// Get the full config file path (~/.config/zwm/zwm.kdl)
pub fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);
    return std.fs.path.join(allocator, &[_][]const u8{ config_dir, "zwm.kdl" });
}

// Default config content
const DEFAULT_CONFIG =
\\// ZWM Configuration File
\\
\\// Visual settings
\\visual {
\\    colors {
\\        active-border "#ffb4a4"
\\        inactive-border "#561f13"
\\        background "#2D2D2D"
\\        text "#FFFFFF"
\\    }
\\
\\    border-width 3
\\    corner-radius 0
\\    gap-size 10
\\
\\    blur {
\\        enabled false
\\        num-passes 2
\\        radius 5.0
\\        noise 0.02
\\        brightness 0.9
\\        contrast 0.9
\\        saturation 1.0
\\    }
\\}
\\
\\// Layout, window management, and keybinds
\\layout {
\\    master-ratio 0.5
\\
\\    animation {
\\        duration 400
\\        spring-frequency 6.0
\\        spring-damping-ratio 1.0
\\    }
\\
\\    binds {
\\        // Application launchers
\\        Mod+Return {
\\            spawn "kitty"
\\        }
\\
\\        // Window focus
\\        Mod+j {
\\            focus-next
\\        }
\\        Mod+k {
\\            focus-prev
\\        }
\\
\\        // Layout adjustments
\\        Mod+h {
\\            decrease-ratio
\\        }
\\        Mod+l {
\\            increase-ratio
\\        }
\\
\\        // Window management
\\        Mod+q {
\\            close-window
\\        }
\\
\\        // System
\\        Mod+Shift+q {
\\            quit
\\        }
\\        Mod+Shift+r {
\\            reload-config
\\        }
\\        Escape {
\\            quit
\\        }
\\    }
\\}
\\
\\// Input configuration
\\input {
\\    keyboard {
\\        xkb {
\\            layout "us,ru"
\\            options "grp:alt_shift_toggle"
\\        }
\\    }
\\}
\\
\\// Environment variables
\\environment {
\\    DISPLAY ":0"
\\    QT_QPA_PLATFORM "wayland"
\\    EDITOR "emacsclient"
\\}
\\
\\// External commands
\\commands {
\\    terminal "kitty"
\\    launcher "bemenu-run"
\\    screenshot "grim"
\\    lock "swaylock"
\\}
\\
;

// Ensure config directory and file exist, create with defaults if not
pub fn ensureConfigExists(allocator: std.mem.Allocator) ![]const u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const config_path = try getConfigPath(allocator);
    errdefer allocator.free(config_path);

    // Create config directory if it doesn't exist
    std.fs.makeDirAbsolute(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.log.err("Failed to create config directory: {}", .{err});
            return err;
        }
    };

    // Check if config file exists
    const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Create default config file
            std.log.info("Config file not found, creating default at: {s}", .{config_path});
            const new_file = try std.fs.createFileAbsolute(config_path, .{});
            defer new_file.close();
            try new_file.writeAll(DEFAULT_CONFIG);
            std.log.info("Created default config file at: {s}", .{config_path});
        } else {
            return err;
        }
        return config_path;
    };
    file.close();

    return config_path;
}

pub fn loadConfig(allocator: std.mem.Allocator, config_path: []const u8) !Config {
    // Default configuration
    var config = Config{
        .active_border = hexToRGBA("#ffb4a4"),
        .inactive_border = hexToRGBA("#561f13"),
        .background = hexToRGBA("#2D2D2D"),
        .text = hexToRGBA("#FFFFFF"),
        .border_width = 3,
        .corner_radius = 0,
        .gap_size = 10,
        .blur = BlurConfig{},
        .master_ratio = 0.5,
        .animation_duration = 400,
        .spring_frequency = 6.0,
        .spring_damping_ratio = 1.0,
        .keybinds = std.ArrayList(KeyBind).init(allocator),
        .commands = std.ArrayList(Command).init(allocator),
        .xkb_layout = "us",
        .xkb_options = "",
        .environment = std.StringHashMap([]const u8).init(allocator),
        .allocator = allocator,
    };

    // Try to load config file
    const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        std.log.warn("Could not open config file '{s}': {}. Using defaults.", .{ config_path, err });
        return config;
    };
    defer file.close();

    // Read entire file
    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    // Parse with our simple KDL parser
    var parser = simple_kdl.Parser.init(allocator, content);
    var nodes = try parser.parse();
    defer simple_kdl.freeNodes(&nodes);

    // Process top-level nodes
    std.log.info("Parsed {} top-level nodes from KDL", .{nodes.items.len});
    for (nodes.items) |*node| {
        std.log.info("Top-level node: '{s}' with {} children", .{node.name, node.children.items.len});
        if (std.mem.eql(u8, node.name, "visual")) {
            try parseVisualNode(node, &config);
        } else if (std.mem.eql(u8, node.name, "layout")) {
            std.log.info("Calling parseLayoutNode", .{});
            try parseLayoutNode(node, &config, allocator);
        } else if (std.mem.eql(u8, node.name, "input")) {
            try parseInputNode(node, &config, allocator);
        } else if (std.mem.eql(u8, node.name, "environment")) {
            try parseEnvironmentNode(node, &config, allocator);
        } else if (std.mem.eql(u8, node.name, "commands")) {
            try parseCommandsNode(node, &config, allocator);
        }
    }

    std.log.info("Configuration loaded from '{s}' - {} keybinds loaded", .{config_path, config.keybinds.items.len});

    // Debug: print all keybinds
    for (config.keybinds.items, 0..) |kb, i| {
        std.log.info("Keybind {}: mod={} key={} action={} cmd='{s}'", .{i, kb.modifiers, kb.keysym, kb.action, kb.cmd});
    }

    return config;
}

// Parse visual node
fn parseVisualNode(node: *const simple_kdl.Node, config: *Config) !void {
    for (node.children.items) |*child| {
        if (std.mem.eql(u8, child.name, "colors")) {
            for (child.children.items) |*color_node| {
                if (color_node.getArg(0)) |color_str| {
                    if (std.mem.eql(u8, color_node.name, "active-border")) {
                        config.active_border = hexToRGBA(color_str);
                    } else if (std.mem.eql(u8, color_node.name, "inactive-border")) {
                        config.inactive_border = hexToRGBA(color_str);
                    } else if (std.mem.eql(u8, color_node.name, "background")) {
                        config.background = hexToRGBA(color_str);
                    } else if (std.mem.eql(u8, color_node.name, "text")) {
                        config.text = hexToRGBA(color_str);
                    }
                }
            }
        } else if (std.mem.eql(u8, child.name, "blur")) {
            for (child.children.items) |*blur_node| {
                if (blur_node.getArg(0)) |arg| {
                    if (std.mem.eql(u8, blur_node.name, "enabled")) {
                        config.blur.enabled = std.mem.eql(u8, arg, "true");
                    } else if (std.mem.eql(u8, blur_node.name, "num-passes")) {
                        config.blur.num_passes = try std.fmt.parseInt(i32, arg, 10);
                    } else if (std.mem.eql(u8, blur_node.name, "radius")) {
                        config.blur.radius = try std.fmt.parseFloat(f32, arg);
                    } else if (std.mem.eql(u8, blur_node.name, "noise")) {
                        config.blur.noise = try std.fmt.parseFloat(f32, arg);
                    } else if (std.mem.eql(u8, blur_node.name, "brightness")) {
                        config.blur.brightness = try std.fmt.parseFloat(f32, arg);
                    } else if (std.mem.eql(u8, blur_node.name, "contrast")) {
                        config.blur.contrast = try std.fmt.parseFloat(f32, arg);
                    } else if (std.mem.eql(u8, blur_node.name, "saturation")) {
                        config.blur.saturation = try std.fmt.parseFloat(f32, arg);
                    }
                }
            }
        } else if (std.mem.eql(u8, child.name, "border-width")) {
            if (child.getArg(0)) |arg| {
                config.border_width = try std.fmt.parseInt(i32, arg, 10);
            }
        } else if (std.mem.eql(u8, child.name, "corner-radius")) {
            if (child.getArg(0)) |arg| {
                config.corner_radius = try std.fmt.parseInt(i32, arg, 10);
            }
        } else if (std.mem.eql(u8, child.name, "gap-size")) {
            if (child.getArg(0)) |arg| {
                config.gap_size = try std.fmt.parseInt(i32, arg, 10);
            }
        }
    }
}

// Parse layout node
fn parseLayoutNode(node: *const simple_kdl.Node, config: *Config, allocator: std.mem.Allocator) !void {
    std.log.info("parseLayoutNode: {} children", .{node.children.items.len});
    for (node.children.items) |*child| {
        std.log.info("  Layout child: '{s}' with {} children", .{child.name, child.children.items.len});
        if (std.mem.eql(u8, child.name, "master-ratio")) {
            if (child.getArg(0)) |arg| {
                config.master_ratio = try std.fmt.parseFloat(f32, arg);
            }
        } else if (std.mem.eql(u8, child.name, "animation")) {
            for (child.children.items) |*anim_node| {
                if (anim_node.getArg(0)) |arg| {
                    if (std.mem.eql(u8, anim_node.name, "duration")) {
                        config.animation_duration = try std.fmt.parseInt(u32, arg, 10);
                    } else if (std.mem.eql(u8, anim_node.name, "spring-frequency")) {
                        config.spring_frequency = try std.fmt.parseFloat(f32, arg);
                    } else if (std.mem.eql(u8, anim_node.name, "spring-damping-ratio")) {
                        config.spring_damping_ratio = try std.fmt.parseFloat(f32, arg);
                    }
                }
            }
        } else if (std.mem.eql(u8, child.name, "binds")) {
            // Parse keybinds
            std.log.info("Found binds section with {} children", .{child.children.items.len});
            for (child.children.items) |*bind_node| {
                std.log.info("Processing bind node: {s} with {} children", .{bind_node.name, bind_node.children.items.len});
                var keybind = try parseKeyCombo(bind_node.name, allocator);

                // Parse action from children
                for (bind_node.children.items) |*action_node| {
                    std.log.info("  Action node: {s}", .{action_node.name});
                    if (std.mem.eql(u8, action_node.name, "spawn")) {
                        if (action_node.getArg(0)) |cmd| {
                            keybind.cmd = try allocator.dupe(u8, cmd);
                            keybind.action = .spawn;
                        }
                    } else {
                        keybind.action = parseAction(action_node.name);
                    }
                }

                try config.keybinds.append(keybind);
                std.log.info("Added keybind: {s} -> {}", .{bind_node.name, keybind.action});
            }
        }
    }
}

// Parse a key combo string like "Mod+Return" into modifiers and keysym
fn parseKeyCombo(combo: []const u8, allocator: std.mem.Allocator) !KeyBind {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var iter = std.mem.splitSequence(u8, combo, "+");
    while (iter.next()) |part| {
        try parts.append(part);
    }

    if (parts.items.len == 0) return error.InvalidKeyCombo;

    // Last part is the key, everything before is modifiers
    const key = parts.items[parts.items.len - 1];
    const keysym = try parseKeysym(key);

    var modifiers: u32 = 0;
    for (parts.items[0..parts.items.len - 1]) |mod| {
        modifiers |= parseModifiers(mod);
    }

    return KeyBind{
        .modifiers = modifiers,
        .keysym = keysym,
        .cmd = "",
        .action = .none,
    };
}

// Parse input node
fn parseInputNode(node: *const simple_kdl.Node, config: *Config, allocator: std.mem.Allocator) !void {
    for (node.children.items) |*child| {
        if (std.mem.eql(u8, child.name, "keyboard")) {
            for (child.children.items) |*kb_node| {
                if (std.mem.eql(u8, kb_node.name, "xkb")) {
                    for (kb_node.children.items) |*xkb_node| {
                        if (xkb_node.getArg(0)) |arg| {
                            if (std.mem.eql(u8, xkb_node.name, "layout")) {
                                config.xkb_layout = try allocator.dupe(u8, arg);
                            } else if (std.mem.eql(u8, xkb_node.name, "options")) {
                                config.xkb_options = try allocator.dupe(u8, arg);
                            }
                        }
                    }
                }
            }
        }
    }
}

// Parse environment node
fn parseEnvironmentNode(node: *const simple_kdl.Node, config: *Config, allocator: std.mem.Allocator) !void {
    for (node.children.items) |*child| {
        if (child.getArg(0)) |value| {
            const name = try allocator.dupe(u8, child.name);
            const val = try allocator.dupe(u8, value);
            try config.environment.put(name, val);
        }
    }
}

// Parse commands node
fn parseCommandsNode(node: *const simple_kdl.Node, config: *Config, allocator: std.mem.Allocator) !void {
    for (node.children.items) |*child| {
        if (child.getArg(0)) |cmd| {
            try config.commands.append(.{
                .name = try allocator.dupe(u8, child.name),
                .cmd = try allocator.dupe(u8, cmd),
            });
        }
    }
}
