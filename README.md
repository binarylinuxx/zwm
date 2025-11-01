# zwm
*ziged wlroots tiling Wayland Compositor*

# Info
always seen those eye candy compositors and they always uses C/++ and im decided try how far can i push with zig. repo has [GithubMirror](https://github.com/binarylinuxx/zwm.git) but mainly accepting all pull requests on [CodebergRepo](https://codeberg.org/blx/zwm.git) all other things issues and etc on both.

**currently support:**
- Basic Master Stack
- animations
- Basic LayerShell,WlrScreenCopy,WlrOutput protocols

**TO-DO:**
- Fix Some bugs
- Blur
- Window Rounding
- Custom renderer for FX effects
- Migration to wlroots 0.19 for custom render
- [x] Config parser instead .zig file

**Current project status:**
- zwm are very young expect many issues and bugs
- if you willing contribute submit pull request explain what enchanced

# Building and testing

*requirements:*
- zig 0.14.1+ you probably would get it from https://ziglang.org/download/
- pkg-config
- make
- wlroots 0.18

*build:*
```
git clone https://codeberg.org/blx/zwm
cd zwm
make build
sudo make install # optional if you want install zwm to path
```

# Config
Configuration uses KDL (KDL Document Language) format and is located at `~/.config/zwm/zwm.kdl`.

On first run, ZWM will automatically create the config directory and generate a default config file with sensible defaults.

**Hot Reload:** Press `Mod+Shift+r` to reload the config on the fly without restarting the compositor!

Example keybind in `zwm.kdl`:
```kdl
layout {
    binds {
        Mod+Return {
            spawn "kitty"
        }
        Mod+Shift+r {
            reload-config
        }
    }
}
```
