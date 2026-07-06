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
          pkgs.python3Packages.jsonschema
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
        loadUserConfig = flakeLib.loadUserConfig flakeRoot;
      };

      switchApp = pkgs.writeShellApplication {
        name = "darwin-switch";
        runtimeInputs = [ pkgs.nix ];
        text = ''
          set -e
          cd "${flakeRoot}"
          HOST="''${1:-''${HOST:-${primaryHost}}}"
          if command -v darwin-rebuild >/dev/null 2>&1; then
            exec sudo darwin-rebuild switch --flake ".#''${HOST}"
          fi
          echo "First install: building system, then switching…"
          nix build ".#darwinConfigurations.''${HOST}.system"
          exec sudo ./result/sw/bin/darwin-rebuild switch --flake ".#''${HOST}"
        '';
      };

      checkApp = pkgs.writeShellApplication {
        name = "darwin-check";
        runtimeInputs = [ pkgs.nix ];
        text = ''
          set -e
          cd "${flakeRoot}"
          exec nix --option warn-dirty false flake check
        '';
      };

      changelogApp = pkgs.writeShellApplication {
        name = "darwin-changelog";
        runtimeInputs = [ pkgs.nix ];
        text = ''
          set -e
          cd "${flakeRoot}"
          HOST="''${1:-''${HOST:-${primaryHost}}}"
          if command -v darwin-rebuild >/dev/null 2>&1; then
            exec darwin-rebuild changelog --flake ".#''${HOST}"
          fi
          echo "darwin-rebuild not found. Building system, then showing changelog…"
          nix build ".#darwinConfigurations.''${HOST}.system"
          exec ./result/sw/bin/darwin-rebuild changelog --flake ".#''${HOST}"
        '';
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
    in
    {
      darwinConfigurations = darwinConfigurations;

      # ── Thin-overlay exports ──────────────────────────────────────────
      # These let overlay repos build darwinConfigurations using only the
      # starter's exports + their own config/ JSON, without copying lib/,
      # overlays/, scripts/, or darwin/default.nix.

      # Config loaders (loadHostsManifest, loadSharedConfig, loadUserConfig,
      # loadAppConfig, loadHostConfig, loadFontConfig, loadFirefoxConfig).
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

      # Script derivations for overlay CI.
      scripts.validateHostJson = validateHostJsonScript;

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

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.jq
          pkgs.nix
          pkgs.nixfmt
          pkgs.nodejs
          pkgs.python3Packages.jsonschema
          pkgs.shellcheck
        ];
      };

      checks.${system} =
        assert
          (import ./lib/validate-apps.nix {
            inherit lib;
            pkgs = pkgsForValidation;
            hosts = manifest.hosts;
            loadAppConfig = flakeLib.loadAppConfig flakeRoot;
            loadFontConfig = flakeLib.loadFontConfig flakeRoot;
            loadFirefoxConfig = flakeLib.loadFirefoxConfig flakeRoot;
          }) == { };
        lib.genAttrs manifest.hosts (host: darwinConfigurations.${host}.system)
        // lib.optionalAttrs (editorTooling != { }) {
          editor-tooling = editorTooling.editorTooling;
        };

      apps.${system} = {
        switch = {
          type = "app";
          program = "${switchApp}/bin/darwin-switch";
          meta = {
            description = "Build and activate the nix-darwin system from this flake";
            mainProgram = "darwin-switch";
          };
        };
        check = {
          type = "app";
          program = "${checkApp}/bin/darwin-check";
          meta = {
            description = "Run nix flake check for this flake";
            mainProgram = "darwin-check";
          };
        };
        changelog = {
          type = "app";
          program = "${changelogApp}/bin/darwin-changelog";
          meta = {
            description = "Show nix-darwin stateVersion changelog before bumping system.stateVersion";
            mainProgram = "darwin-changelog";
          };
        };
        new-host = {
          type = "app";
          program = "${newHostApp}/bin/darwin-new-host";
          meta = {
            description = "Scaffold config for a new host (interactive prompts)";
            mainProgram = "darwin-new-host";
          };
        };
      };
    };
}
