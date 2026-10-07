{
  description = "Claude Desktop (Linux beta) packaged for Nix, with a NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "claude-desktop";
        }));
    in
    {
      packages = forAllSystems (pkgs: rec {
        claude-desktop = pkgs.callPackage ./package.nix { };
        default = claude-desktop;
      });

      overlays.default = final: _prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      nixosModules.claude-desktop = ./module.nix;
      nixosModules.default = ./module.nix;

      checks = forAllSystems (pkgs: {
        module = (nixpkgs.lib.nixosSystem {
          inherit (pkgs.stdenv.hostPlatform) system;
          modules = [
            self.nixosModules.default
            {
              nixpkgs.config.allowUnfree = true;
              boot.isContainer = true;
              system.stateVersion = "26.05";
              users.users.alice.isNormalUser = true;
              programs.claude-desktop = { enable = true; cowork.users = [ "alice" ]; };
            }
          ];
        }).config.system.build.toplevel;

        vm = import ./test.nix { inherit pkgs; module = self.nixosModules.default; };
      });
    };
}
