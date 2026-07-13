# Shared flake outputs for dotnix-starter and thin overlay repos.
{
  self,
  pkgs,
  lib,
  system,
  dotnix-starter,
  flakeRoot,
  manifest,
  primaryHost,
  darwinConfigurations,
  editorTooling ? { },
  newHostApp,
}:
let
  nixpkgsLib = pkgs.lib;

  loadAppConfig = dotnix-starter.lib.loadAppConfig flakeRoot;
  loadFontConfig = dotnix-starter.lib.loadFontConfig flakeRoot;
  loadFirefoxConfig = dotnix-starter.lib.loadFirefoxConfig flakeRoot;
  loadAndroidConfig = dotnix-starter.lib.loadAndroidConfig flakeRoot;

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
in
{
  scripts = {
    inherit switchApp checkApp changelogApp;
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
      (dotnix-starter.validateApps {
        lib = nixpkgsLib;
        pkgs = dotnix-starter.pkgsForValidation;
        hosts = manifest.hosts;
        inherit
          loadAppConfig
          loadFontConfig
          loadFirefoxConfig
          loadAndroidConfig
          ;
      }) == { };
    nixpkgsLib.genAttrs manifest.hosts (host: darwinConfigurations.${host}.system)
    // nixpkgsLib.optionalAttrs (editorTooling != { }) {
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
    new-host =
      if newHostApp ? type && newHostApp.type == "app" then
        newHostApp
      else
        {
          type = "app";
          program = "${newHostApp}/bin/darwin-new-host";
          meta = {
            description = "Scaffold config for a new host (interactive prompts)";
            mainProgram = "darwin-new-host";
          };
        };
  };
}
