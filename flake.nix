{
  description = "Hackworth Ltd .github repo.";

  inputs = {
    hacknix.url = github:hackworthltd/hacknix;
    nixpkgs.follows = "hacknix/nixpkgs";

    flake-utils.url = github:numtide/flake-utils;

    flake-compat.url = github:edolstra/flake-compat;
    flake-compat.flake = false;

    pre-commit-hooks-nix.url = github:cachix/pre-commit-hooks.nix;
    pre-commit-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
    # Fixes aarch64-darwin support.
    pre-commit-hooks-nix.inputs.flake-utils.follows = "flake-utils";
  };

  outputs =
    { self
    , nixpkgs
    , hacknix
    , flake-utils
    , pre-commit-hooks-nix
    , ...
    }@inputs:
    let
      forAllSupportedSystems = flake-utils.lib.eachSystem [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllTestSystems = flake-utils.lib.eachSystem [
        "x86_64-linux"
        "aarch64-linux"
      ];

      overlay = hacknix.lib.overlays.combine [
        hacknix.overlay
        (final: prev:
          let
          in
          { }
        )
      ];

      pkgsFor = system: import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowBroken = true;
        };
        overlays = [
          overlay
        ];
      };
    in
    {
      # Note: `overlay` is not per-system like most other flake attributes.
      inherit overlay;
    }

    // forAllSupportedSystems
      (system:
      let
        pkgs = pkgsFor system;

        pre-commit-hooks =
          let
          in
          pre-commit-hooks-nix.lib.${system}.run {
            src = ./.;
            hooks = {
              nixpkgs-fmt.enable = true;

              prettier = {
                enable = true;
                excludes = [ ".github/" ];
              };

              actionlint = {
                enable = true;
                name = "actionlint";
                entry = "${pkgs.actionlint}/bin/actionlint";
                language = "system";
                files = "^.github/workflows/";
              };
            };

            tools = {
              inherit (pkgs) nixpkgs-fmt;
              inherit (pkgs.nodePackages) prettier;
            };

            excludes = [
              "CODE_OF_CONDUCT.md"
              "LICENSE"
              ".mergify.yml"
              ".buildkite/"
            ];

          };
      in
      {
        checks = {
          source-code-checks = pre-commit-hooks;
        };

        devShell = pkgs.mkShell {
          buildInputs = (with pkgs; [
            actionlint
            nodePackages.prettier
            nixpkgs-fmt
            rnix-lsp
          ]);
        };
      })

    // {
      hydraJobs = {
        inherit (self) checks;

        required =
          let
            pkgs = pkgsFor "x86_64-linux";
          in
          pkgs.releaseTools.aggregate {
            name = "required-nix-ci";
            constituents = builtins.map builtins.attrValues (with self.hydraJobs; [
              checks.x86_64-linux
              checks.aarch64-linux
              checks.aarch64-darwin
            ]);
            meta.description = "Required Nix CI builds";
          };
      };

      ciJobs = hacknix.lib.flakes.recurseIntoHydraJobs self.hydraJobs;
    };
}
