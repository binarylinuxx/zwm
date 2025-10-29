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
- Config parser instead .zig file

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
config use simplyfied zig syntax and exposed at src 
