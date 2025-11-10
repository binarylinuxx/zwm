project('zwm', 'c',
  version: '0.1.0',
  license: 'MIT',
  meson_version: '>=0.60.0',
  default_options: [
    'c_std=c11',
    'warning_level=2',
    'werror=false',
  ],
)

# Find required dependencies
wayland_server = dependency('wayland-server')
wlroots = dependency('wlroots-0.19')
xkbcommon = dependency('xkbcommon')
pixman = dependency('pixman-1')
egl = dependency('egl')
glesv2 = dependency('glesv2')
scenefx = dependency('scenefx-0.4')

# Wayland protocol scanner
wayland_scanner = dependency('wayland-scanner', native: true)
wayland_scanner_prog = find_program(
  wayland_scanner.get_variable(pkgconfig: 'wayland_scanner'),
  native: true,
)

wayland_protocols = dependency('wayland-protocols')
wl_protocol_dir = wayland_protocols.get_variable(pkgconfig: 'pkgdatadir')

# Protocol generation would be handled by the Zig build system
# Meson will invoke zig build which handles protocol generation

# Get zig compiler
zig = find_program('zig', required: true)

# Custom target to build with Zig
zwm_build = custom_target(
  'zwm-build',
  output: ['zwm', 'zwmctl'],
  command: [
    zig, 'build',
    '-Doptimize=ReleaseFast',
    '--prefix', meson.current_build_dir(),
  ],
  build_by_default: true,
  install: false,
)

# Extract binaries from zig-out
zwm_exe = custom_target(
  'zwm-exe',
  output: 'zwm',
  command: [
    'cp',
    join_paths(meson.current_build_dir(), 'bin', 'zwm'),
    '@OUTPUT@'
  ],
  depends: zwm_build,
  build_by_default: true,
  install: true,
  install_dir: get_option('bindir'),
)

zwmctl_exe = custom_target(
  'zwmctl-exe',
  output: 'zwmctl',
  command: [
    'cp',
    join_paths(meson.current_build_dir(), 'bin', 'zwmctl'),
    '@OUTPUT@'
  ],
  depends: zwm_build,
  build_by_default: true,
  install: true,
  install_dir: get_option('bindir'),
)

# Summary
summary({
  'prefix': get_option('prefix'),
  'bindir': get_option('bindir'),
}, section: 'Directories')

summary({
  'wayland-server': wayland_server.version(),
  'wlroots': wlroots.version(),
  'xkbcommon': xkbcommon.version(),
  'pixman-1': pixman.version(),
  'scenefx': scenefx.version(),
}, section: 'Dependencies')
