{nixpkgs}: {
  # Produces a devShell for each supported GHC version.
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

  # Produces a set of packages for each supported GHC version.
  #
  # <ghcVer>_<package> = A package with only the one Cabal package
  # <ghcVer>_all = A package containing GHC will all Cabal packages installed
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

  # Creates an overlay with `haskellOverlay` installed in
  # `haskell.packages.<ghcVer>` for each supported GHC version.
  #
  # `haskellOverlay` should be a function:
  #
  #     ghcVer: finalHaskPkgs: prevHaskPkgs: AttrSet
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

  # Reads the set of local packages from a cabal.project provided at the call
  # site.
  #
  # Ideally, parsing cabal.project should be done via official tools
  # Related discussion at NixOS/cabal2nix#286
  parseCabalProject =
    cabalProject: let
      content = builtins.readFile cabalProject;
      lines = nixpkgs.lib.splitString "\n" content;
      matches =
        builtins.map
          (builtins.match "[[:space:]]*[.]/(.*)/(.*)[.]cabal$")
          lines;
      projects = builtins.concatMap (match:
        if builtins.isList match && builtins.length match == 2
        then [
          {
            name = builtins.elemAt match 1;
            path = builtins.elemAt match 0;
          }
        ]
        else [])
        matches;
    in
      projects;
}
