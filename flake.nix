{
  description = "Gajae Code MVP";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.rust-overlay = {
    url = "github:oxalica/rust-overlay";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, rust-overlay, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          lib = pkgs.lib;
          version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).workspace.package.version;
          rustChannel = (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml)).toolchain.channel;
          rustToolchain = pkgs.rust-bin.nightly.${lib.removePrefix "nightly-" rustChannel}.minimal;
          rustPlatform = pkgs.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };
          platform = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux";
          arch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
          variantSuffix = lib.optionalString (arch == "x64") "-baseline";
          nativeFilename = "pi_natives.${platform}-${arch}${variantSuffix}.node";

          nodeModules = pkgs.stdenvNoCC.mkDerivation {
            pname = "gajae-code-node_modules";
            inherit version;
            src = ./.;

            impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
              "GIT_PROXY_COMMAND"
              "SOCKS_SERVER"
            ];

            nativeBuildInputs = [
              pkgs.bun
              pkgs.writableTmpDirAsHomeHook
            ];

            dontConfigure = true;
            dontFixup = true;

            buildPhase = ''
              runHook preBuild
              export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
              bun install \
                --cpu="*" \
                --os="*" \
                --frozen-lockfile \
                --ignore-scripts \
                --no-progress
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              find . -type d -name node_modules -exec cp -R --parents {} $out \;
              runHook postInstall
            '';

            outputHash = "sha256-hgk936oXU4MxK4e5rifxiN6o27+VM0a0vFfDPj97Rko=";
            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
          };

          nativeAddon = rustPlatform.buildRustPackage {
            pname = "gajae-code-native-addon";
            inherit version;
            src = ./.;

            cargoHash = "sha256-R9trLBSQDkYsYCJlxGeq9oyWhwOGy6LZXR9R/zhS3H0=";
            buildType = "dist";
            cargoBuildFlags = [
              "--package"
              "pi-natives"
            ];
            cargoCheckFlags = [
              "--package"
              "pi-natives"
            ];
            RUSTFLAGS = lib.optionalString (arch == "x64") "-C target-cpu=x86-64-v2";

            nativeBuildInputs = [
              pkgs.perl
              pkgs.pkg-config
              pkgs.python3
            ];

            buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.wayland
            ];

            preCheck = ''
              export HOME="$TMPDIR"
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 \
                "target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/dist/libpi_natives${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}" \
                "$out/${nativeFilename}"
              runHook postInstall
            '';
          };
        in
        rec {
          default = gajae-code;

          gajae-code = pkgs.stdenv.mkDerivation {
            pname = "gajae-code";
            inherit version;
            __structuredAttrs = true;
            strictDeps = true;

            src = ./.;

            nativeBuildInputs = [
              pkgs.bun
              pkgs.writableTmpDirAsHomeHook
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.darwin.sigtool
            ];

            configurePhase = ''
              runHook preConfigure
              cp -R ${nodeModules}/. .
              patchShebangs node_modules packages/*/node_modules
              install -Dm755 ${nativeAddon}/${nativeFilename} packages/natives/native/${nativeFilename}
              runHook postConfigure
            '';

            buildPhase = ''
              runHook preBuild
              export TARGET_PLATFORM=${platform}
              export TARGET_ARCH=${arch}
              export EMBED_VARIANTS=${if arch == "x64" then "baseline" else "default"}
              bun --cwd=packages/coding-agent run generate-docs-index
              bun --cwd=packages/coding-agent run build
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 packages/coding-agent/dist/gjc $out/bin/gjc
              runHook postInstall
            '';

            dontStrip = true;

            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck
              export HOME=$(mktemp -d)
              export XDG_DATA_HOME=$(mktemp -d)
              mkdir -p "$XDG_DATA_HOME/gjc"
              $out/bin/gjc --version
              $out/bin/gjc --smoke-test
              runHook postInstallCheck
            '';

            meta = {
              description = "Gajae Code MVP";
              homepage = "https://github.com/Yeachan-Heo/gajae-code";
              changelog = "https://github.com/Yeachan-Heo/gajae-code/releases/tag/v${version}";
              license = lib.licenses.mit;
              maintainers = [ ];
              mainProgram = "gjc";
            };
          };
        }
      );
    };
}
