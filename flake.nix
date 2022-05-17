{
  description = "concat";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.11";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem flake-utils.lib.allSystems (system:
      let
        haskellLib = (import nixpkgs { inherit system; }).haskell.lib;

        parseCabalProject = import ./parse-cabal-project.nix;
        concatPackages = let
          excluded = [ "concat-hardware" ];
          parsed = parseCabalProject ./cabal.project;
        in builtins.filter ({ name, ... }: !(builtins.elem name excluded))
        parsed;
        concatPackageNames = builtins.map ({ name, ... }: name) concatPackages;
        haskellOverlay = self: super:
          builtins.listToAttrs (builtins.map ({ name, path }: {
            inherit name;
            value = self.callCabal2nix name (./. + "/${path}") { };
          }) concatPackages);

        # see these issues and discussions:
        # - https://github.com/NixOS/nixpkgs/issues/16394
        # - https://github.com/NixOS/nixpkgs/issues/25887
        # - https://github.com/NixOS/nixpkgs/issues/26561
        # - https://discourse.nixos.org/t/nix-haskell-development-2020/6170
        fullOverlay = final: prev: {
          haskellPackages = prev.haskellPackages.override (old: {
            overrides =
              final.lib.composeExtensions (old.overrides or (_: _: { }))
              haskellOverlay;
          });
        };
      in {
        overlay = fullOverlay;

        devShells = let
          mkDevShell = ghcVer:
            let
              overlayGHC = final: prev: {
                haskellPackages = prev.haskell.packages.${ghcVer};
              };

              newPkgs = import nixpkgs {
                # Here we use the full overlays from this flake, but the categorifier-*
                # packages will not be provided in the shell. The overlay is only used
                # to extract dependencies.
                overlays = [ overlayGHC fullOverlay ];
                inherit system;
              };

            in newPkgs.haskellPackages.shellFor {
              packages = ps: builtins.map (name: ps.${name}) concatPackageNames;
              buildInputs = [ newPkgs.haskellPackages.cabal-install ] ++
                # haskell-language-server on GHC 9.2.1 is broken yet.
                newPkgs.lib.optional (ghcVer != "ghc921")
                [ newPkgs.haskell-language-server ];
              withHoogle = false;
            };
        in {
          "ghc8107" = mkDevShell "ghc8107";
          "ghc921" = mkDevShell "ghc921";
        };
      });
}
