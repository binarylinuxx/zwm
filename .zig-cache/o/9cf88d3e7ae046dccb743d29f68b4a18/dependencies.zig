pub const packages = struct {
    pub const @"pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX" = struct {
        pub const build_root = "/home/blx/.cache/zig/p/pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX";
        pub const build_zig = @import("pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"wayland-0.3.0-lQa1kjPIAQDmhGYpY-zxiRzQJFHQ2VqhJkQLbKKdt5wl" = struct {
        pub const build_root = "/home/blx/.cache/zig/p/wayland-0.3.0-lQa1kjPIAQDmhGYpY-zxiRzQJFHQ2VqhJkQLbKKdt5wl";
        pub const build_zig = @import("wayland-0.3.0-lQa1kjPIAQDmhGYpY-zxiRzQJFHQ2VqhJkQLbKKdt5wl");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"wlroots-0.18.2-jmOlchnIAwBq45_cxU1V3OWErxxJjQZlc9PyJfR-l3uk" = struct {
        pub const build_root = "/home/blx/.cache/zig/p/wlroots-0.18.2-jmOlchnIAwBq45_cxU1V3OWErxxJjQZlc9PyJfR-l3uk";
        pub const build_zig = @import("wlroots-0.18.2-jmOlchnIAwBq45_cxU1V3OWErxxJjQZlc9PyJfR-l3uk");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "pixman", "pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX" },
            .{ "wayland", "wayland-0.3.0-lQa1kjPIAQDmhGYpY-zxiRzQJFHQ2VqhJkQLbKKdt5wl" },
            .{ "xkbcommon", "xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr" },
        };
    };
    pub const @"xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr" = struct {
        pub const build_root = "/home/blx/.cache/zig/p/xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr";
        pub const build_zig = @import("xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "pixman", "pixman-0.3.0-LClMnz2VAAAs7QSCGwLimV5VUYx0JFnX5xWU6HwtMuDX" },
    .{ "wayland", "wayland-0.3.0-lQa1kjPIAQDmhGYpY-zxiRzQJFHQ2VqhJkQLbKKdt5wl" },
    .{ "wlroots", "wlroots-0.18.2-jmOlchnIAwBq45_cxU1V3OWErxxJjQZlc9PyJfR-l3uk" },
    .{ "xkbcommon", "xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr" },
};
