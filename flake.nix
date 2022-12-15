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
      lib = import ./nix/lib.nix {inherit nixpkgs;};
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
