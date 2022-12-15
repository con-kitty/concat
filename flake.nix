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
        mkDevShells = pkgs: ghcVersions: packages:
          builtins.listToAttrs
          (builtins.map
            (ghcVer: {
              name = ghcVer;
              value = pkgs.haskell.packages.${ghcVer}.shellFor {
                packages = _: builtins.attrValues (packages ghcVer);
                nativeBuildInputs = [
                  pkgs.haskell-language-server
                  pkgs.haskell.packages.${ghcVer}.cabal-install
                ];
                withHoogle = false;
              };
            })
            ghcVersions);

        mkPackages = pkgs: ghcVersions: packages:
          nixpkgs.lib.foldr
          (a: b: a // b)
          {}
          (builtins.map
            (ghcVer: let
              ghcPackages = packages ghcVer;

              individualPackages =
                nixpkgs.lib.concatMapAttrs
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
              individualPackages // {"${ghcVer}_all" = allEnv;})
            ghcVersions);

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
                        nixpkgs.lib.composeExtensions
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
        # NB: This uses `self.overlays.default` because packages need to be able
        #     to find other packages in this flake as dependencies.
        overlays = [self.overlays.default];
      };

      systemPackages = nixPackages pkgs;
    in {
      # This package set is only useful for CI build test.
      # In practice, users will create a development environment composed by overlays.
      packages =
        {default = self.packages.${system}.ghc902_all;}
        // self.lib.mkPackages pkgs supportedGhcVersions systemPackages;

      devShells =
        {default = self.devShells.${system}.ghc902;}
        // self.lib.mkDevShells pkgs supportedGhcVersions systemPackages;

      formatter = pkgs.alejandra;
    });

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    nixpkgs.url = github:NixOS/nixpkgs/nixos-22.11;
  };
}
