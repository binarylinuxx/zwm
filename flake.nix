{
  description = "ZWM - A Wayland compositor inspired by dwm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, zig-overlay, ... } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; overlays = [ zig-overlay.overlays.default ]; };
    zig = pkgs.zig_0_14;
    wlroots = pkgs.wlroots_0_19;
  in {
    packages.${system}.default = pkgs.stdenv.mkDerivation {
      pname = "zwm";
      version = "unstable-2025-11-18";

      src = inputs.self;

      nativeBuildInputs = with pkgs; [
        zig
        pkg-config
        make
        meson
        ninja
        wayland
      ];

      buildInputs = with pkgs; [
        wlroots
        libxkbcommon
        wayland
        wayland-protocols
        pixman
        libinput
        libdrm
        mesa
        # SceneFX is a Zig package, will be handled by Zig build system
      ];

      # Assuming a meson.build or Makefile exists that uses pkg-config for wlroots
      # and other deps. For SceneFX, assuming it's a git dependency in build.zig.zon
      # User may need to adjust build.zig.zon to use absolute path if needed:
      # .dependencies sceneFX = .{
      #   .url = "git+https://github.com/Scene-Framework/sceneFX#0.4.1";
      # };

      mesonFlags = [ "-Dbuildtype=release" ];

      dontUseMesonConfigure = false;  # Enable meson

      configurePhase = ''
        meson setup build --prefix=$out
      '';

      buildPhase = ''
        ninja -C build
      '';

      installPhase = ''
        ninja -C build install
      '';

      meta = with pkgs.lib; {
        description = "ZWM - A Wayland compositor inspired by dwm";
        homepage = "https://codeberg.org/blx/zwm";
        license = licenses.mit;  # Adjust based on actual license
        maintainers = [ ];
        platforms = platforms.linux;
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      nativeBuildInputs = self.packages.${system}.default.nativeBuildInputs;
      buildInputs = self.packages.${system}.default.buildInputs;
      shellHook = ''
        export ZIG=${zig}/bin/zig
      '';
    };
  };
}
