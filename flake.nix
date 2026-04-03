{
  description = "nix vulnerability scanner";

  nixConfig = {
    extra-substituters = [
      "https://nix.trev.zip"
    ];
    extra-trusted-public-keys = [
      "trev:I39N/EsnHkvfmsbx8RUW+ia5dOzojTQNCTzKYij1chU="
    ];
  };

  inputs = {
    systems.url = "github:spotdemo4/systems";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    trev = {
      url = "github:spotdemo4/nur";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      trev,
      ...
    }:
    trev.libs.mkFlake (
      system: pkgs: {
        devShells = {
          default = pkgs.mkShell {
            shellHook = pkgs.shellhook.ref;
            packages = with pkgs; [
              # bash
              jq
              pcre2

              # lint
              shellcheck

              # format
              nixfmt
              prettier

              # util
              bumper
            ];
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

        checks = pkgs.mkChecks {
          shellcheck = {
            root = ./.;
            fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "sh") ./.;
            deps = with pkgs; [
              shellcheck
            ];
            forEach = ''
              shellcheck "$file"
            '';
          };

          actions = {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./action.yaml
              ./.github/workflows
            ];
            deps = with pkgs; [
              action-validator
              octoscan
            ];
            forEach = ''
              action-validator "$file"
              octoscan scan "$file"
            '';
          };

          renovate = {
            root = ./.github;
            fileset = ./.github/renovate.json;
            deps = with pkgs; [
              renovate
            ];
            script = ''
              renovate-config-validator renovate.json
            '';
          };

          nix = {
            root = ./.;
            filter = file: file.hasExt "nix";
            deps = with pkgs; [
              nixfmt
            ];
            forEach = ''
              nixfmt --check "$file"
            '';
          };

          prettier = {
            root = ./.;
            filter = file: file.hasExt "yaml" || file.hasExt "json" || file.hasExt "md";
            deps = with pkgs; [
              prettier
            ];
            forEach = ''
              prettier --check "$file"
            '';
          };
        };

        apps = pkgs.mkApps {
          dev = "./nix-scan.sh";
        };

        packages = with pkgs.lib; {
          default = pkgs.stdenv.mkDerivation (finalAttrs: {
            pname = "nix-scan";
            version = "1.1.2";

            src = builtins.path {
              name = "root";
              path = ./.;
            };

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
              sed -i '2c\export PATH="${makeBinPath finalAttrs.runtimeInputs}:$PATH"' nix-scan.sh
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp nix-scan.sh "$out/bin/nix-scan"
            '';

            dontFixup = true;

            meta = {
              mainProgram = "nix-scan";
              description = "Nix vulnerability scanner";
              license = licenses.mit;
              platforms = platforms.all;
              homepage = "https://github.com/spotdemo4/nix-scan";
              changelog = "https://github.com/spotdemo4/nix-scan/releases/tag/v${finalAttrs.version}";
            };
          });
        };

        images = {
          default = pkgs.mkImage self.packages.${system}.default {
            fromImage = pkgs.image.nix;
            contents = with pkgs; [ dockerTools.caCertificates ];
          };
        };

        formatter = pkgs.nixfmt-tree;
        schemas = trev.schemas;
      }
    );
}
