# flake.nix
#   ├── config/
#   │   ├── apps/base.json, apps/hosts/<name>.json
#   │   ├── fonts/base.json, fonts/hosts/<name>.json
#   │   ├── firefox/base.json, firefox/hosts/<name>.json
#   │   ├── user.json, git.json              # shared profile / git
#   │   ├── hosts.json                       # host list + default
#   │   └── hosts/<name>.json                # per-machine settings + adminUsername
#   ├── darwin/                              # nix-darwin modules
#   ├── home/                                # home-manager modules
#   └── lib/                                 # config loaders
{
  description = "nix-darwin + home-manager template (macOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Editor-tooling inputs (Prettier/ESLint config repos).
    # This flake pins nigelng/prettier-config and nigelng/eslint-config so
    # editor tooling is built by default. These are plain source repos (not
    # Nix flakes), used as file: deps in lib/editor-tooling.nix. Overlay repos
    # can omit these inputs to disable editor tooling (home/default.nix guards
    # on editorTooling != {}).
    prettier-config = {
      url = "github:nigelng/prettier-config";
      flake = false;
    };
    eslint-config = {
      url = "github:nigelng/eslint-config";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      darwin,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      system = "aarch64-darwin";
      flakeLib = import ./lib { inherit lib; };
      flakeRoot = builtins.toString self.outPath;

      manifest = flakeLib.loadHostsManifest flakeRoot;
      shared = flakeLib.loadSharedConfig flakeRoot;
      primaryHost = if manifest ? defaultHost then manifest.defaultHost else builtins.head manifest.hosts;

      inherit (shared) gitConfig;

      pkgs = nixpkgs.legacyPackages.${system};

      # Same overlay as darwin/default.nix so google-fonts-* attrs resolve during validation.
      pkgsForValidation = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ (import ./overlays/google-fonts) ];
      };

      # Editor tooling is optional — only built when both flake inputs are present.
      # When absent, editorTooling is {} (empty attrset), and home/default.nix
      # skips the editor.nix import via lib.optional (editorTooling != {}).
      hasEditorTooling = inputs ? prettier-config && inputs ? eslint-config;

      editorTooling =
        if hasEditorTooling then
          import ./lib/editor-tooling.nix {
            inherit pkgs lib;
            prettier-config = inputs.prettier-config;
            eslint-config = inputs.eslint-config;
          }
        else
          { };

      mkWritableCopyActivation = import ./lib/mk-writable-copy-activation.nix {
        hmLib = home-manager.lib;
        inherit lib pkgs;
      };

      validateHostJsonScript = pkgs.writeShellApplication {
        name = "validate-host-json";
        runtimeInputs = [
          pkgs.jq
          (pkgs.python3.withPackages (ps: [ ps.jsonschema ]))
        ];
        text = builtins.readFile ./scripts/validate-host-json.sh;
      };

      darwinConfigurations = import ./darwin {
        inherit (nixpkgs) lib;
        inherit pkgs;
        inherit
          flakeRoot
          home-manager
          darwin
          system
          gitConfig
          editorTooling
          ;
        hosts = manifest.hosts;
        loadHostConfig = flakeLib.loadHostConfig flakeRoot;
        loadAppConfig = flakeLib.loadAppConfig flakeRoot;
        loadFontConfig = flakeLib.loadFontConfig flakeRoot;
        loadFirefoxConfig = flakeLib.loadFirefoxConfig flakeRoot;
        loadAndroidConfig = flakeLib.loadAndroidConfig flakeRoot;
        loadUserConfig = flakeLib.loadUserConfig flakeRoot;
      };

      newHostApp = pkgs.writeShellApplication {
        name = "darwin-new-host";
        runtimeInputs = [
          pkgs.jq
          pkgs.nix
          pkgs.git
        ];
        text = ''
          set -e
          # Use the caller's checkout (PWD), not flakeRoot (read-only store copy).
          exec ${./scripts/new-host.sh} "$@"
        '';
      };

      overlayOutputs = import ./lib/overlay-flake-outputs.nix {
        inherit
          self
          pkgs
          lib
          system
          flakeRoot
          manifest
          primaryHost
          darwinConfigurations
          editorTooling
          newHostApp
          ;
        dotnix-starter = self;
      };
    in
    {
      darwinConfigurations = darwinConfigurations;

      # ── Thin-overlay exports ──────────────────────────────────────────
      # These let overlay repos build darwinConfigurations using only the
      # starter's exports + their own config/ JSON, without copying lib/,
      # overlays/, scripts/, or darwin/default.nix.

      # Config loaders (loadHostsManifest, loadSharedConfig, loadUserConfig,
      # loadAppConfig, loadHostConfig, loadFontConfig, loadFirefoxConfig,
      # loadAndroidConfig).
      lib = flakeLib;

      # Built editor tooling attrset, or {} when inputs are absent.
      editorTooling = editorTooling;

      # Helper for writable-copy activation scripts (used by home/vscode.nix
      # and home/zsh.nix via extraSpecialArgs).
      mkWritableCopyActivation = mkWritableCopyActivation;

      # The darwin/default.nix function — overlays call this with their own
      # config loaders, host list, and extraHomeModules.
      darwinConfigurationsBuilder = import ./darwin;

      # Overlays needed by overlay repos for font resolution.
      overlays.google-fonts = import ./overlays/google-fonts;

      # nixpkgs with google-fonts overlay for validation in overlay checks.
      pkgsForValidation = pkgsForValidation;

      # App/font validation function for overlay checks.
      validateApps = import ./lib/validate-apps.nix;

      # Shared flake outputs helper for thin overlay repos.
      overlayFlakeOutputs = import ./lib/overlay-flake-outputs.nix;

      # Script derivations for overlay CI.
      scripts = {
        validateHostJson = validateHostJsonScript;
      }
      // overlayOutputs.scripts;

      # ── Module exports ─────────────────────────────────────────────────

      # Reusable module exports for overlay repos.
      # homeModules.default imports the full home-manager module tree.
      # homeModules.defaultWithFirefox also imports the Firefox backup browser.
      # Per-file modules let overlay repos pick individual pieces.
      homeModules = {
        default = import ./home;
        defaultWithFirefox = {
          imports = [
            (import ./home)
            (import ./home/firefox.nix)
          ];
        };
        git = import ./home/git.nix;
        vim = import ./home/vim.nix;
        vscode = import ./home/vscode.nix;
        zsh = import ./home/zsh.nix;
        editor = import ./home/editor.nix;
        firefox = import ./home/firefox.nix;
        android = import ./home/android.nix;
      };

      # darwinModules.default combines configuration.nix + system.nix.
      # Per-file modules let overlay repos customize individual concerns.
      darwinModules = {
        default = _: {
          imports = [
            ./darwin/configuration.nix
            ./darwin/system.nix
          ];
        };
        configuration = import ./darwin/configuration.nix;
        system = import ./darwin/system.nix;
      };

      formatter = overlayOutputs.formatter;

      devShells = overlayOutputs.devShells;

      checks = overlayOutputs.checks;

      apps.${system} = overlayOutputs.apps.${system} // {
        validate-host-json = {
          type = "app";
          program = "${validateHostJsonScript}/bin/validate-host-json";
          meta = {
            description = "Validate config/hosts/*.json against JSON schemas";
            mainProgram = "validate-host-json";
          };
        };
      };
    };
}
