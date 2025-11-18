{
  description = "ZWM - A Wayland compositor inspired by dwm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zwm-src = {
      url = "git+https://codeberg.org/blx/zwm.git?ref=main";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, zig-overlay, ... } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; overlays = [ zig-overlay.overlays.default ]; };
    zig = pkgs.zig;
    wlroots = pkgs.wlroots_0_19;
  in {
    packages.${system}.default = pkgs.stdenv.mkDerivation {
      pname = "zwm";
      version = "unstable-2025-11-18";

      src = zwm-src.outPath;

      nativeBuildInputs = with pkgs; [
        zig
        pkg-config
        make
        meson
        ninja
        wayland
        scenefx
        wlroots_0_19
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
        scenefx
        wlroots_0_19
      ];

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
        description = "ZWM - Zigged wlroots tilling";
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
