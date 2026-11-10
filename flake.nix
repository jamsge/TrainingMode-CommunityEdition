{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    devkitNix.url = "github:bandithedoge/devkitNix";
    devkitNix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      devkitNix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ devkitNix.overlays.default ];
        };
      in
      {
        devShells.default = pkgs.mkShell.override { stdenv = pkgs.devkitNix.stdenvPPC; } {
          buildInputs = with pkgs; [
            xdelta
            patchelf
            file
          ];

          shellHook = ''
            # Create a local bin directory with symlinks for every name the script might look for
            mkdir -p .nix-bin
            export PATH="$PWD/.nix-bin:$PATH"

            # gc_fst (already correct in nixpkgs)
            if command -v gc_fst > /dev/null; then
              [ -e .nix-bin/gc_fst ] || ln -sf "$(command -v gc_fst)" .nix-bin/gc_fst
            fi

            # hgecko
            if command -v hgecko > /dev/null; then
              [ -e .nix-bin/hgecko ] || ln -sf "$(command -v hgecko)" .nix-bin/hgecko
            fi

            # hmex
            if command -v hmex > /dev/null; then
              [ -e .nix-bin/hmex ] || ln -sf "$(command -v hmex)" .nix-bin/hmex
            fi

            # xdelta3 from nixpkgs -> provide both xdelta and xdelta3 names
            if command -v xdelta3 > /dev/null; then
              [ -e .nix-bin/xdelta3 ] || ln -sf "$(command -v xdelta3)" .nix-bin/xdelta3
              [ -e .nix-bin/xdelta ] || ln -sf "$(command -v xdelta3)" .nix-bin/xdelta
            fi

            # Export tool variables so build.sh never sees an empty variable
            export gc_fst="$(command -v gc_fst 2>/dev/null || echo "$PWD/bin/gc_fst")"
            export hgecko="$(command -v hgecko 2>/dev/null || echo "$PWD/bin/hgecko")"
            export hmex="$(command -v hmex 2>/dev/null || echo "$PWD/bin/hmex")"
            export xdelta="$(command -v xdelta 2>/dev/null || command -v xdelta3 2>/dev/null || echo xdelta3)"

            # Patch bundled dynamically-linked binaries for NixOS
            for binary in bin/gc_fst bin/hgecko bin/hmex; do
              if [ -f "$binary" ] && file "$binary" | grep -q "dynamically linked"; then
                if ! readelf -l "$binary" 2>/dev/null | grep -q "nix-store"; then
                  echo "Patching $binary for NixOS..."
                  cp "$binary" "$binary.orig"
                  patchelf \
                    --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" \
                    --set-rpath "${pkgs.lib.makeLibraryPath [
                      pkgs.glibc
                      pkgs.zlib
                      pkgs.stdenv.cc.cc.lib
                    ]}" \
                    "$binary"
                fi
              fi
            done
          '';
        };
      }
    );
}
