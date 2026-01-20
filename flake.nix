{
  description = "nix vulnerability scanner";

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
        fs = pkgs.lib.fileset;
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
              nix-scan

              # actions
              octoscan
            ];
          };
        };

        checks = pkgs.lib.mkChecks {
          shellcheck = {
            src = fs.toSource {
              root = ./.;
              fileset = ./nix-scan.sh;
            };
            deps = with pkgs; [
              shellcheck
            ];
            script = ''
              shellcheck nix-scan.sh
            '';
          };

          nix = {
            src = fs.toSource {
              root = ./.;
              fileset = fs.fileFilter (file: file.hasExt "nix") ./.;
            };
            deps = with pkgs; [
              nixfmt-tree
            ];
            script = ''
              treefmt --ci
            '';
          };

          actions = {
            src = fs.toSource {
              root = ./.;
              fileset = fs.unions [
                ./action.yaml
                ./.github/workflows
              ];
            };
            deps = with pkgs; [
              action-validator
              octoscan
            ];
            script = ''
              action-validator **/*.yaml
              octoscan scan .
            '';
          };

          renovate = {
            src = fs.toSource {
              root = ./.github;
              fileset = ./.github/renovate.json;
            };
            deps = with pkgs; [
              renovate
            ];
            script = ''
              renovate-config-validator renovate.json
            '';
          };

          prettier = {
            src = fs.toSource {
              root = ./.;
              fileset = fs.fileFilter (file: file.hasExt "yaml" || file.hasExt "json" || file.hasExt "md") ./.;
            };
            deps = with pkgs; [
              prettier
            ];
            script = ''
              prettier --check .
            '';
          };
        };

        apps = pkgs.lib.mkApps {
          dev.script = "./nix-scan.sh";
        };

        packages = {
          default = pkgs.stdenv.mkDerivation (finalAttrs: {
            pname = "nix-scan";
            version = "1.1.2";

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
              description = "Nix vulnerability scanner";
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
              dockerTools.caCertificates
              packages.default
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
