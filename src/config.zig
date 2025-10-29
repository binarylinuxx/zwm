const std = @import("std");
const xkb = @import("xkbcommon");

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
    
    // Handle different hex formats:
    // #RGB -> #RRGGBB
    if (hexLen == 3) {
        const r = (parsed >> 8) & 0xF;
        const g = (parsed >> 4) & 0xF;
        const b = parsed & 0xF;
        hex = ((r << 4) | r) << 16 | (((g << 4) | g) << 8) | ((b << 4) | b);
    }
    // #RGBA -> #RRGGBBAA
    else if (hexLen == 4) {
        const r = (parsed >> 12) & 0xF;
        const g = (parsed >> 8) & 0xF;
        const b = (parsed >> 4) & 0xF;
        const a = parsed & 0xF;
        hex = ((r << 4) | r) << 16 | (((g << 4) | g) << 8) | ((b << 4) | b) | (((a << 4) | a) << 24);
    }
    // #RRGGBB -> #RRGGBBAA (default alpha to FF)
    else if (hexLen == 6) {
        hex = parsed | 0xFF000000;
    }
    // #RRGGBBAA
    else if (hexLen == 8) {
        hex = parsed;
    }
    
    const r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0;
    const g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0;
    const b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0;
    const a = @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0;
    return [4]f32{ r, g, b, a };
}

// Color constants using hex strings
pub const colors = struct {
    pub const active_border = hexToRGBA("#ffb4a4"); // light purple for active border
    pub const inactive_border = hexToRGBA("#561f13"); // dark purple for inactive border
    pub const background = hexToRGBA("#2D2D2D"); // dark gray background
    pub const text = hexToRGBA("#FFFFFF"); // white text
};

// Layout configuration
pub const layout = struct {
    pub const master_ratio: f32 = 0.5;
    pub const gap_size: i32 = 10;
    pub const border_width: i32 = 3;
};

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

// Key sym constants - these need to match xkb.Keysym values
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
};

// Action enum for predefined actions
pub const Action = enum {
    none,
    focus_next,
    focus_prev,
    close_window,
    increase_ratio,
    decrease_ratio,
    quit,
};

// Key binding structure
pub const KeyBind = struct {
    modifiers: u32,      // bitmask of modifiers
    keysym: c_int,       // keysym value
    cmd: []const u8,     // Command to run (for external programs)
    action: Action = .none, // Predefined action
};

// Command structure for launching external programs
pub const Command = struct {
    name: []const u8,
    cmd: []const u8,
};

// Key bindings configuration
pub const keys = [_]KeyBind{
    // Mod+Return: Launch terminal
    KeyBind{
        .modifiers = MOD.LOGO,
        .keysym = Keysym.Return,
        .cmd = "kitty",
        .action = .none,
    },
    
    // Mod+j: Focus next window
    KeyBind{
        .modifiers = MOD.LOGO,
        .keysym = Keysym.j,
        .cmd = "",
        .action = .focus_next,
    },
    
    // Mod+k: Focus previous window
    KeyBind{
        .modifiers = MOD.LOGO,
        .keysym = Keysym.k,
        .cmd = "",
        .action = .focus_prev,
    },
    
    // Mod+Shift+c: Close focused window
    KeyBind{
        .modifiers = MOD.LOGO,
        .keysym = Keysym.q,
        .cmd = "",
        .action = .close_window,
    },
    
    // Mod+h: Decrease master ratio
    KeyBind{
        .modifiers = MOD.LOGO,
        .keysym = Keysym.h,
        .cmd = "",
        .action = .decrease_ratio,
    },
    
    // Mod+l: Increase master ratio
    KeyBind{
        .modifiers = MOD.LOGO,
        .keysym = Keysym.l,
        .cmd = "",
        .action = .increase_ratio,
    },
    
    // Mod+Shift+q: Quit
    KeyBind{
        .modifiers = MOD.LOGO_SHIFT,
        .keysym = Keysym.q,
        .cmd = "",
        .action = .quit,
    },
    
    // Escape: Quit (for debug purposes)
    KeyBind{
        .modifiers = MOD.NONE,
        .keysym = Keysym.Escape,
        .cmd = "",
        .action = .quit,
    },
};

// Commands configuration
pub const commands = [_]Command{
	Command{ .name = "close_window", .cmd = "kill" },
    Command{ .name = "terminal", .cmd = "kitty" },
    Command{ .name = "launcher", .cmd = "bemenu-run" },
    Command{ .name = "screenshot", .cmd = "grim" },
    Command{ .name = "lock", .cmd = "swaylock" },
};
