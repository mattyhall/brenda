{
  description = "An experiment in terminal multiplexing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = inputs:
    let
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs {
        inherit system;
      };
      zig = pkgs.stdenv.mkDerivation {
        name = "zig";
        src = fetchTarball {
          url = "https://ziglang.org/builds/zig-linux-x86_64-0.10.0-dev.4197+9a2f17f9f.tar.xz";
          sha256 = "sha256:0286bjfsppwrg69vrh6nvywf9v39c03byznrhxs4c5v8dy0283ig";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          mv ./lib $out/
          mkdir -p $out/bin
          mv ./zig $out/bin
        '';
      };
    in
      {
         devShell.${system} = pkgs.mkShell {
           nativeBuildInputs = [ zig ] ++ (with pkgs; [
             bashInteractive
             zls
             gdb
           ]);
         };
      };
}
