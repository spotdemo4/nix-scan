# nix package scanner

![check](https://github.com/spotdemo4/nix-scan/actions/workflows/check.yaml/badge.svg?branch=main)
![vulnerable](https://github.com/spotdemo4/nix-scan/actions/workflows/vulnerable.yaml/badge.svg?branch=main)

Scans a nix package for CVEs. Like [vulnix](https://github.com/nix-community/vulnix) but with way less false positives and more false negatives.

## Usage

```elm
nix-scan [packages...]
```

## Install

### Action

```yaml
- name: Scan
  uses: spotdemo4/nix-scan@v1.1.1
```

### Nix

```elm
nix run github:spotdemo4/nix-scan
```

#### Flake

```nix
inputs = {
    scan = {
        url = "github:spotdemo4/nix-scan";
        inputs.nixpkgs.follows = "nixpkgs";
    };
};

outputs = { scan, ... }: {
    devShells."${system}".default = pkgs.mkShell {
        packages = [
            scan."${system}".default
        ];
    };
}
```

also available from the [nix user repository](https://nur.nix-community.org/repos/trev) as `nur.repos.trev.nix-scan`

### Docker

```elm
docker run -it --rm \
  -v "$(pwd):/app" \
  -w /app \
  -e GITHUB_TOKEN=... \
  ghcr.io/spotdemo4/nix-scan:1.1.1
```

### Downloads

#### [nix-scan.sh](/src/nix-scan.sh) - bash script

requires [jq](https://jqlang.org/) and [pcre2grep](https://github.com/PCRE2Project/pcre2)

```elm
git clone https://github.com/spotdemo4/nix-scan &&
./nix-scan/nix-scan.sh
```

#### [nix-scan-1.1.1.tar.xz](https://github.com/spotdemo4/nix-scan/releases/download/v1.1.1/nix-scan-1.1.1.tar.xz) - bundle

contains all dependencies, only use if necessary

```elm
wget https://github.com/spotdemo4/nix-scan/releases/download/v1.1.1/nix-scan-1.1.1.tar.xz &&
tar xf nix-scan-1.1.1.tar.xz &&
./release
```
