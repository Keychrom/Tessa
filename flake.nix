{
  description = "Tessa - a quiet tiled Wayland compositor and desktop shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
          (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          tessa = pkgs.callPackage ./packaging/nix/package.nix {
            zig = pkgs.zig_0_17;
          };
          tessa-plain = pkgs.callPackage ./packaging/nix/package.nix {
            zig = pkgs.zig_0_17;
            withScenefx = false;
          };
        in
        {
          inherit tessa tessa-plain;
          default = tessa;
        });

      overlays.default = final: prev: {
        tessa = final.callPackage ./packaging/nix/package.nix {
          zig = final.zig_0_17;
        };
        tessa-plain = final.callPackage ./packaging/nix/package.nix {
          zig = final.zig_0_17;
          withScenefx = false;
        };
      };

      nixosModules.default = import ./packaging/nix/module.nix;
      nixosModules.tessa = self.nixosModules.default;

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
