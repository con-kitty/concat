{
  description = "concat";
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.11"; };
  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      haskellOverlay = self: super: {
        "concat-inline" = pkgs.haskell.lib.dontHaddock
          (self.callCabal2nix "concat-inline" ./inline { });
        "concat-plugin" = self.callCabal2nix "concat-plugin" ./plugin { };
        "concat-classes" = self.callCabal2nix "concat-classes" ./classes { };
        "concat-satisfy" = self.callCabal2nix "concat-satisfy" ./satisfy { };
        "concat-known" = self.callCabal2nix "concat-known" ./known { };
        #"concat-hardware" = self.callCabal2nix "concat-hardware" ./hardware { };
        "concat-graphics" = self.callCabal2nix "concat-graphics" ./graphics { };
        "concat-examples" = self.callCabal2nix "concat-examples" ./examples { };
      };

      newHaskellPackages =
        pkgs.haskellPackages.override { overrides = haskellOverlay; };

    in {
      packages.x86_64-linux = {
        inherit (newHaskellPackages)
          concat-inline concat-plugin concat-classes concat-satisfy concat-known
          #concat-hardware
          concat-graphics concat-examples;
      };

      # see these issues and discussions:
      # - https://github.com/NixOS/nixpkgs/issues/16394
      # - https://github.com/NixOS/nixpkgs/issues/25887
      # - https://github.com/NixOS/nixpkgs/issues/26561
      # - https://discourse.nixos.org/t/nix-haskell-development-2020/6170
      overlay = final: prev: {
        haskellPackages = prev.haskellPackages.override (old: {
          overrides = final.lib.composeExtensions (old.overrides or (_: _: { }))
            haskellOverlay;
        });
      };

      devShell.x86_64-linux = let
        hsenv = pkgs.haskellPackages.ghcWithPackages (p: [ p.cabal-install ]);
      in pkgs.mkShell { buildInputs = [ hsenv ]; };
    };
}
