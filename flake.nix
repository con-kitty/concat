{
  description = "Compiling to categories";

  nixConfig = {
    ## https://github.com/NixOS/rfcs/blob/master/rfcs/0045-deprecate-url-syntax.md
    extra-experimental-features = ["no-url-literals"];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
    extra-trusted-substituters = ["https://cache.garnix.io"];
    ## Prevent the Nix GC from removing current dependencies from the store.
    keep-failed = true;
    keep-outputs = true;
    ## Isolate the build.
    registries = false;
    sandbox = true;
  };

  outputs = inputs: let
    pname = "concat";

    availableGhcVersions = ["ghc884" "ghc8107" "ghc902" "ghc924" "ghc942" "ghcHEAD"];
    excludedPackages = ["concat-graphics" "concat-hardware" "concat-plugin"];
    noHaddockPackages = ["concat-examples" "concat-inline" "concat-plugin"];
    # need display, graphviz for testing. disable test for now.
    noCheckPackages = ["concat-graphics" "concat-plugin"];

    cabalPackages = pkgs: ghcVer:
      inputs.nixpkgs.lib.concatMapAttrs
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
      (inputs.self.lib.cabalProject2nix ./cabal.project pkgs ghcVer);
  in
    {
      overlays = {
        default =
          inputs.self.lib.overlayHaskellPackages
          availableGhcVersions
          inputs.self.overlays.haskell;

        haskell = inputs.self.lib.haskellOverlay cabalPackages;
      };

      homeConfigurations =
        builtins.listToAttrs
        (builtins.map
          (system: {
            name = "${system}-example";
            value = inputs.home-manager.lib.homeManagerConfiguration {
              pkgs = import inputs.nixpkgs {
                inherit system;
                overlays = [inputs.self.overlays.default];
              };

              modules = [
                ({pkgs, ...}: {
                  home.packages = [
                    (pkgs.haskellPackages.ghcWithPackages (hpkgs: [
                      hpkgs.concat-examples
                    ]))
                  ];

                  ## These attributes are simply required by home-manager.
                  home = {
                    homeDirectory = /tmp/${pname}-example;
                    stateVersion = "22.11";
                    username = "${pname}-example-user";
                  };
                })
              ];
            };
          })
          inputs.flake-utils.lib.defaultSystems);

      ## TODO: Pull this into its own flake, for use across Haskell projects.
      lib = import ./nix/lib.nix {inherit (inputs) bash-strict-mode nixpkgs;};
    }
    // inputs.flake-utils.lib.eachSystem inputs.flake-utils.lib.allSystems (system: let
      pkgs = import inputs.nixpkgs {
        inherit system;
        ## NB: This uses `inputs.self.overlays.default` because packages need to
        ##     be able to find other packages in this flake as dependencies.
        overlays = [inputs.self.overlays.default];
      };

      supportedGhcVersions =
        if system == inputs.flake-utils.lib.system.aarch64-darwin
        then inputs.nixpkgs.lib.remove "ghc884" availableGhcVersions
        else availableGhcVersions;
    in {
      packages =
        {default = inputs.self.packages.${system}.ghc902_all;}
        // inputs.self.lib.mkPackages pkgs supportedGhcVersions cabalPackages;

      devShells =
        {default = inputs.self.devShells.${system}.ghc902;}
        // inputs.self.lib.mkDevShells pkgs supportedGhcVersions cabalPackages;

      checks = {
        nix-fmt =
          inputs.bash-strict-mode.lib.checkedDrv pkgs
          (pkgs.stdenv.mkDerivation {
            src = pkgs.lib.cleanSource ./.;

            name = "nix fmt";

            nativeBuildInputs = [inputs.self.formatter.${system}];

            buildPhase = ''
              runHook preBuild
              alejandra --check .
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              runHook preInstall
            '';
          });
      };

      # Nix code formatter, https://github.com/kamadorueda/alejandra#readme
      formatter = pkgs.alejandra;
    });

  inputs = {
    bash-strict-mode = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:sellout/bash-strict-mode";
    };

    flake-utils.url = "github:numtide/flake-utils";

    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager/release-22.11";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/release-22.11";
  };
}
