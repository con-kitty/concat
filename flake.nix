{
  description = "concat";

  outputs = {
    self,
    flake-utils,
    nixpkgs,
  }: let
    supportedGhcVersions = ["ghc884" "ghc8107" "ghc902" "ghc924" "ghcHEAD"];
    excludedPackages = ["concat-hardware"];
    noHaddockPackages = ["concat-examples" "concat-inline" "concat-plugin"];
    # need display, graphviz for testing. disable test for now.
    noCheckPackages = ["concat-graphics" "concat-plugin"];

    cabalPackages =
      builtins.filter
      ({name, ...}: !(builtins.elem name excludedPackages))
      (self.lib.parseCabalProject ./cabal.project);
    nixPackages = pkgs: ghcVer: let
      haskellLib = pkgs.haskell.lib;
    in
      builtins.listToAttrs
      (builtins.map
        ({
          name,
          path,
        }: {
          inherit name;
          value = let
            p = pkgs.haskell.packages.${ghcVer}.callCabal2nix name (./. + "/${path}") {};
            p1 =
              if builtins.elem name noHaddockPackages
              then haskellLib.dontHaddock p
              else p;
          in
            if builtins.elem name noCheckPackages
            then haskellLib.dontCheck p1
            else p1;
        })
        cabalPackages);
  in
    {
      overlays.default = final:
        self.lib.overlayHaskellPackages
        supportedGhcVersions
        (ghcVer: hfinal: hprev: nixPackages final ghcVer)
        final;

      ### TODO: Pull this into its own flake, for use across Haskell projects.
      lib = {
        overlayHaskellPackages = ghcVersions: haskellOverlay: final: prev: {
          haskell =
            prev.haskell
            // {
              packages =
                prev.haskell.packages
                // builtins.zipAttrsWith
                (name: values: builtins.head values)
                (builtins.map
                  (ghcVer: {
                    "${ghcVer}" = prev.haskell.packages.${ghcVer}.override (old: {
                      # see these issues and discussions:
                      # - https://github.com/NixOS/nixpkgs/issues/16394
                      # - https://github.com/NixOS/nixpkgs/issues/25887
                      # - https://github.com/NixOS/nixpkgs/issues/26561
                      # - https://discourse.nixos.org/t/nix-haskell-development-2020/6170
                      overrides =
                        final.lib.composeExtensions
                        (old.overrides or (_: _: {}))
                        (haskellOverlay ghcVer);
                    });
                  })
                  ghcVersions);
            };
        };

        parseCabalProject = import ./parse-cabal-project.nix;
      };
    }
    // flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        # NB: This uses `self.overlays.default` instead of `dependencies`
        #     because packages need to be able to find other packages in this
        #     flake as dependencies.
        overlays = [self.overlays.default];
      };

      systemPackages = nixPackages pkgs;
    in {
      # This package set is only useful for CI build test.
      # In practice, users will create a development environment composed by overlays.
      packages = let
        packagesOnGHC = ghcVer: let
          ghcPackages = systemPackages ghcVer;

          individualPackages =
            pkgs.lib.concatMapAttrs
            (name: value: {"${ghcVer}_${name}" = value;})
            ghcPackages;

          allEnv = pkgs.buildEnv {
            name = "all-packages";
            paths = [
              (pkgs.haskell.packages.${ghcVer}.ghcWithPackages
                (_: builtins.attrValues ghcPackages))
            ];
          };
        in
          individualPackages // {"${ghcVer}_all" = allEnv;};
      in
        {default = self.packages.${system}.ghc902_all;}
        // packagesOnGHC "ghc884"
        // packagesOnGHC "ghc8107"
        // packagesOnGHC "ghc902"
        // packagesOnGHC "ghc924"
        // packagesOnGHC "ghcHEAD";

      devShells = let
        mkDevShell = ghcVer:
          pkgs.haskell.packages.${ghcVer}.shellFor {
            packages = _: builtins.attrValues (systemPackages ghcVer);
            nativeBuildInputs = [
              pkgs.haskell-language-server
              pkgs.haskell.packages.${ghcVer}.cabal-install
            ];
            withHoogle = false;
          };
      in {
        default = self.devShells.${system}.ghc902;
        ghc884 = mkDevShell "ghc884";
        ghc8107 = mkDevShell "ghc8107";
        ghc902 = mkDevShell "ghc902";
        ghc924 = mkDevShell "ghc924";
        ghcHEAD = mkDevShell "ghcHEAD";
      };

      formatter = pkgs.alejandra;
    });

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    nixpkgs.url = github:NixOS/nixpkgs/nixos-22.11;
  };
}
