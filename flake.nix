{
  description = "Hackworth Ltd .github repo.";

  inputs = {
    hacknix.url = "github:hackworthltd/hacknix";
    nixpkgs.follows = "hacknix/nixpkgs";

    systems.url = "github:nix-systems/default";

    flake-utils.url = "github:numtide/flake-utils";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;

    pre-commit-hooks-nix.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    let
      allOverlays = [
        inputs.hacknix.overlays.default
      ];
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      debug = true;

      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
      ];

      systems = [ "x86_64-linux" "aarch64-darwin" ];

      perSystem = { config, pkgs, system, ... }:
        let
        in
        {
          # We need a `pkgs` that includes our own overlays within
          # `perSystem`. This isn't done by default, so we do this
          # workaround. See:
          #
          # https://github.com/hercules-ci/flake-parts/issues/106#issuecomment-1399041045
          _module.args.pkgs = import inputs.nixpkgs
            {
              inherit system;
              config = {
                allowUnfree = true;
                allowBroken = true;
              };
              overlays = allOverlays;
            };

          treefmt.config =
            {
              projectRootFile = "flake.nix";
              programs = {
                prettier.enable = true;
                nixpkgs-fmt.enable = true;
              };
            };

          pre-commit = {
            check.enable = true;
            settings = {
              src = ".";
              hooks = {
                treefmt.enable = true;
                actionlint.enable = true;
                actionlint.files = "^.github/workflows/";
              };
            };
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = [
              config.treefmt.build.devShell
              config.pre-commit.devShell
            ];
            buildInputs = (with pkgs;
              [
                actionlint
                nixd
              ]);
          };
        };

      flake =
        let
          # See above, we need to use our own `pkgs` within the flake.
          pkgs = import inputs.nixpkgs
            {
              system = "x86_64-linux";
              config = {
                allowUnfree = true;
                allowBroken = true;
              };
              overlays = allOverlays;
            };
        in
        {
          hydraJobs = {
            inherit (inputs.self) checks;
            inherit (inputs.self) devShells;

            required = pkgs.releaseTools.aggregate {
              name = "required-nix-ci";
              constituents = builtins.map builtins.attrValues (with inputs.self.hydraJobs; [
                checks.x86_64-linux
                checks.aarch64-darwin
              ]);
              meta.description = "Required Nix CI builds";
            };
          };

          ciJobs = pkgs.lib.flakes.recurseIntoHydraJobs inputs.self.hydraJobs;
        };
    };
}
