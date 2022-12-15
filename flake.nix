{
  description = "concat";

  outputs = {
    self,
    flake-utils,
    nixpkgs,
  }: let
    availableGhcVersions = ["ghc884" "ghc8107" "ghc902" "ghc924" "ghcHEAD"];
    excludedPackages = ["concat-hardware"];
    noHaddockPackages = ["concat-examples" "concat-inline" "concat-plugin"];
    # need display, graphviz for testing. disable test for now.
    noCheckPackages = ["concat-graphics" "concat-plugin"];

    cabalPackages = pkgs: ghcVer:
      nixpkgs.lib.concatMapAttrs
      (name: value:
        if builtins.elem name excludedPackages
        then {}
        else let
          v1 =
            if builtins.elem name noHaddockPackages
            then pkgs.haskell.lib.dontHaddock value
            else value;
          v2 =
            if builtins.elem name noCheckPackages
            then pkgs.haskell.lib.dontCheck v1
            else v1;
        in {"${name}" = v2;})
      (self.lib.cabalProject2nix ./cabal.project pkgs ghcVer);
  in
    {
      overlays = {
        default =
          self.lib.overlayHaskellPackages
          availableGhcVersions
          self.overlays.haskell;

        haskell = self.lib.haskellOverlay cabalPackages;
      };

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

      supportedGhcVersions =
        if system == flake-utils.lib.system.aarch64-darwin
        then nixpkgs.lib.remove "ghc884" availableGhcVersions
        else availableGhcVersions;
    in {
      # This package set is only useful for CI build test. In practice, users
      # will create a development environment composed by overlays.
      packages =
        {default = self.packages.${system}.ghc902_all;}
        // self.lib.mkPackages pkgs supportedGhcVersions cabalPackages;

      devShells =
        {default = self.devShells.${system}.ghc902;}
        // self.lib.mkDevShells pkgs supportedGhcVersions cabalPackages;

      formatter = pkgs.alejandra;
    });

  nixConfig = {
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
    extra-trusted-substituters = ["https://cache.garnix.io"];
    # Prevent the Nix GC from removing current dependencies from the store.
    keep-failed = true;
    keep-outputs = true;
    # Isolate the build.
    sandbox = true;
  };

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    nixpkgs.url = github:NixOS/nixpkgs/nixos-22.11;
  };
}
