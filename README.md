# zwm
[![Last Commit](https://img.shields.io/github/last-commit/binarylinuxx/zwm)](https://codeberg.org/blx/zwm)
[![GitHub Stars](https://img.shields.io/github/stars/binarylinuxx/zwm?style=social)](https://github.com/binarylinuxx/zwm)
[![Codeberg Stars](https://img.shields.io/badge/dynamic/json?color=success&label=Codeberg%20Stars&query=stars_count&url=https%3A%2F%2Fcodeberg.org%2Fapi%2Fv1%2Frepos%2Fblx%2Fzwm&logo=codeberg)](https://codeberg.org/blx/zwm)

*ziged wlroots tiling Wayland Compositor*

# Info
always seen those eye candy compositors and they always uses C/++ and im decided try how far can i push with zig. repo has [GithubMirror](https://github.com/binarylinuxx/zwm.git) but mainly accepting all pull requests on [CodebergRepo](https://codeberg.org/blx/zwm.git) all other things issues and etc on both.

**currently support:**
- Basic Master Stack tiling layout
- Smooth spring-based animations for window movements
- Window rounding with SceneFX (corner radius fully configurable)
- Backdrop blur effects with customizable parameters
- Custom FX renderer with OpenGL shader support
- Basic LayerShell, WlrScreenCopy, WlrOutput protocols
- KDL-based configuration with hot-reload support

**TO-DO:**
- [x] Config parser instead .zig file
- [x] Migration to wlroots 0.19 for custom render
- [x] Window Rounding (SceneFX integration with buffer-level corner radius)
- [x] Custom renderer for FX effects via Shaders (infrastructure ready)
- [x] Blur effect (backdrop blur on windows with scene-level parameters)
- Fix Popups at gtk apps for qt they seems work fine
- Fix Some bugs (appear to be permanent by develop progress)
- Advanced rounded corners with clipping regions for borders
- More tiling layouts (floating, monocle, etc.)

**Current project status:**
- zwm are very young expect many issues and bugs
- if you willing contribute submit pull request explain what enchanced

**Recomended Commit tags for PR(pull request):**
- New feature "FT|FEATURE: short description of your new feature"
- BugFix "BUG|BUGFIX: short description of your new Bugfix"
- Edited README "EDIT: readme updates"

# Building and testing

*requirements:*
- zig 0.14.1 you probably would get it from https://ziglang.org/download/
- pkg-config
- make or meson/ninja (choose one build system)
- wlroots 0.19
- SceneFX 0.4.1

*build with Make:*
```
git clone https://codeberg.org/blx/zwm
cd zwm
make build
sudo make install # optional if you want install zwm to path
```

*build with Meson:*
```
git clone https://codeberg.org/blx/zwm
cd zwm
meson setup build
ninja -C build
sudo ninja -C build install # optional if you want install zwm to path
```

# Config
Configuration uses KDL (KDL Document Language) format and is located at `~/.config/zwm/zwm.kdl`.
Configuration currently parsed with my little yet simple KDL parser specifically 

On first run, ZWM will automatically create the config directory and generate a default config file with sensible defaults.

**Hot Reload:** Press `Mod+Shift+r` to reload the config on the fly without restarting the compositor and also has instant reload on change if no changes seen make sure no syntax error in the config.
