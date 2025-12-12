{
  description = "nix scanner";

  nixConfig = {
    extra-substituters = [
      "https://cache.trev.zip/nur"
    ];
    extra-trusted-public-keys = [
      "nur:70xGHUW1+1b8FqBchldaunN//pZNVo6FKuPL4U/n844="
    ];
  };

  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    trev = {
      url = "github:spotdemo4/nur";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      trev,
      ...
    }:
    trev.libs.mkFlake (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            trev.overlays.packages
            trev.overlays.libs
            trev.overlays.images
          ];
        };
      in
      rec {
        devShells = {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # bash
              jq
              pcre2

              # util
              bumper

              # lint
              shellcheck
              nixfmt
              prettier
            ];
            shellHook = pkgs.shellhook.ref;
          };

          update = pkgs.mkShell {
            packages = with pkgs; [
              renovate
            ];
          };

          vulnerable = pkgs.mkShell {
            packages = with pkgs; [
              # nix
              flake-checker

              # actions
              octoscan
            ];
          };
        };

        checks = pkgs.lib.mkChecks {
          bash = {
            src = packages.default;
            deps = with pkgs; [
              shellcheck
            ];
            script = ''
              shellcheck nix-scan.sh
            '';
          };

          action = {
            src = ./.;
            deps = with pkgs; [
              action-validator
            ];
            script = ''
              action-validator action.yaml
            '';
          };

          nix = {
            src = ./.;
            deps = with pkgs; [
              nixfmt-tree
            ];
            script = ''
              treefmt --ci
            '';
          };

          actions = {
            src = ./.;
            deps = with pkgs; [
              prettier
              action-validator
              octoscan
              renovate
            ];
            script = ''
              prettier --check "**/*.json" "**/*.yaml"
              action-validator .github/**/*.yaml
              octoscan scan .github
              renovate-config-validator .github/renovate.json
            '';
          };
        };

        apps = pkgs.lib.mkApps {
          dev.script = "./nix-scan.sh";
        };

        packages = {
          default = pkgs.stdenv.mkDerivation (finalAttrs: {
            pname = "nix-scan";
            version = "1.0.1";

            src = builtins.path {
              name = "root";
              path = ./.;
            };

            nativeBuildInputs = with pkgs; [
              makeWrapper
              shellcheck
            ];

            runtimeInputs = with pkgs; [
              jq
              ncurses
              nix
              pcre2
            ];

            unpackPhase = ''
              cp -a "$src/nix-scan.sh" nix-scan.sh
            '';

            dontBuild = true;

            configurePhase = ''
              sed -i '1c\#!${pkgs.runtimeShell}' nix-scan.sh
              sed -i '2c\export PATH="${pkgs.lib.makeBinPath finalAttrs.runtimeInputs}:$PATH"' nix-scan.sh
            '';

            doCheck = true;
            checkPhase = ''
              shellcheck nix-scan.sh
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp nix-scan.sh "$out/bin/nix-scan"
            '';

            dontFixup = true;

            meta = {
              description = "nix package scanner";
              mainProgram = "nix-scan";
              homepage = "https://github.com/spotdemo4/nix-scan";
              changelog = "https://github.com/spotdemo4/nix-scan/releases/tag/v${finalAttrs.version}";
              platforms = pkgs.lib.platforms.all;
            };
          });

          image = pkgs.dockerTools.buildLayeredImage {
            name = packages.default.pname;
            tag = packages.default.version;

            fromImage = pkgs.image.nix;
            contents = with pkgs; [
              packages.default
              dockerTools.caCertificates
            ];

            created = "now";
            meta = packages.default.meta;

            config = {
              Cmd = [ "${pkgs.lib.meta.getExe packages.default}" ];
              Env = [ "DOCKER=true" ];
            };
          };
        };

        formatter = pkgs.nixfmt-tree;
      }
    );
}
