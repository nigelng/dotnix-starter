# Cursor (+ optional Devin settings): extensions and user settings via home-manager.
# Install the Cursor app via apps JSON (e.g. code-cursor cask); HM manages config only.
# commonBase in ./vscode/extensions.nix is the Cursor HM extension set (and reinstate base for VS Code).
# Devin (when casked) shares the settings pipeline only — not commonBase extension installs.
# Nix IDE, Python Environments, and Pylance are CLI-pinned for Cursor (engine lags upstream).
{
  config,
  pkgs,
  lib,
  appConfig,
  mkWritableCopyActivation,
  editorTooling ? { },
  ...
}:
let
  sharedSettings = import ./vscode/shared-settings.nix { inherit lib; };
  extensionSets = import ./vscode/extensions.nix { inherit pkgs lib; };

  hasDevin = lib.elem "devin-desktop" appConfig.casks;

  applyToAllProfiles = [
    "remote.localPortHost"
    "workbench.colorTheme"
    "workbench.iconTheme"
    "workbench.sideBar.location"
    "workbench.startupEditor"
    "workbench.panel.defaultLocation"
    "workbench.panel.opensMaximized"
    "workbench.editor.showTabs"
    "workbench.editor.tabSizing"
    "workbench.editor.openSideBySideDirection"
    "workbench.statusBar.visible"
    "workbench.secondarySideBar.visible"
    "window.menuBarVisibility"
    "terminal.integrated.defaultLocation"
  ];

  nixToolPaths = {
    nix.serverPath = "${pkgs.nil}/bin/nil";
    nix.formatterPath = "${pkgs.nixfmt}/bin/nixfmt";
  };

  editorToolingHome = "${config.home.homeDirectory}/.config/editor-tooling";

  jsLintSettings = lib.optionalAttrs (editorTooling != { }) {
    eslint.useFlatConfig = true;
    eslint.options.overrideConfigFile = "${editorToolingHome}/eslint.config.js";
    eslint.nodePath = "${editorToolingHome}/node_modules";
    prettier.configPath = "${editorToolingHome}/.prettierrc.json";
    # Module root (not nixpkgs bin/prettier): resolves your prettier-config from editor-tooling node_modules.
    prettier.prettierPath = "${editorToolingHome}/node_modules/prettier";
  };

  cursorObsoleteKeyPrefixes = [
    "jnoortheen.nix-ide"
    "ms-python.vscode-python-envs"
    "ms-python.vscode-pylance"
  ];

  cursorObsoleteJqFilter =
    let
      prefixTests = lib.concatMapStringsSep " or " (p: "startswith(\"${p}\")") cursorObsoleteKeyPrefixes;
    in
    "with_entries(select((.key | ${prefixTests}) | not))";

  mkEditorSettings =
    extras: lib.recursiveUpdate sharedSettings (nixToolPaths // jsLintSettings // extras);

  # Shared settings pipeline: Cursor (active) and Devin (when cask present).
  # Future VS Code: mkEditorSettings { …vscode-only prefs… } + programs.vscode = mkEditor "vscode" …
  # with extensions = commonBase ++ [ nixIdeVscode pythonEnvsVscode pylanceVscode ] (++ optional vscodeOnly).
  devinSettings = mkEditorSettings {
    workbench.settings.applyToAllProfiles = applyToAllProfiles;
  };

  cursorSettings = mkEditorSettings {
    workbench.settings.applyToAllProfiles = applyToAllProfiles;
  };

  mkEditor = name: userSettings: {
    enable = true;
    package = null;
    profiles.default = {
      extensions = extensionSets.${name};
      inherit userSettings;
      enableUpdateCheck = false;
      enableExtensionUpdateCheck = false;
    };
  };

  # Cursor registers gallery-style installs (publisher.name-version-universal), not HM symlinks.
  cursorPinnedExtensions = [
    "jnoortheen.nix-ide"
    "ms-python.vscode-python-envs"
    "ms-python.vscode-pylance"
  ];

  # VS Code-family editors rewrite settings.json on startup; HM store symlinks are read-only.
  editorUserSettingsPaths = [
    "${config.home.homeDirectory}/Library/Application Support/Cursor/User/settings.json"
  ]
  ++ lib.optionals hasDevin [
    "${config.home.homeDirectory}/Library/Application Support/Devin/User/settings.json"
  ];

  mkWritableEditorSettingsActivation = mkWritableCopyActivation;

  installCursorPinnedExtensions = pkgs.writeShellScript "install-cursor-pinned-extensions" ''
    set -euo pipefail
    if ! command -v cursor >/dev/null 2>&1; then
      exit 0
    fi
    listed=$(cursor --list-extensions 2>/dev/null || true)
    for ext in ${lib.concatStringsSep " " cursorPinnedExtensions}; do
      if ! printf '%s\n' "$listed" | grep -qx "$ext"; then
        cursor --install-extension "$ext" --force
      fi
    done
  '';

in
{
  # VS Code HM path intentionally disabled; reinstate via mkEditor + commonBase (see extensions.nix).
  programs.cursor = mkEditor "cursor" cursorSettings;

  home.activation.editorUserSettingsWritable = mkWritableEditorSettingsActivation editorUserSettingsPaths;

  home.activation.unmarkCursorHmExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    obsolete="$HOME/.cursor/extensions/.obsolete"
    if [ -f "$obsolete" ]; then
      ${pkgs.jq}/bin/jq '${cursorObsoleteJqFilter}' "$obsolete" > "$obsolete.tmp" && mv "$obsolete.tmp" "$obsolete"
    fi
  '';

  home.activation.installCursorPinnedExtensions =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "unmarkCursorHmExtensions"
      ]
      ''
        ${installCursorPinnedExtensions}
      '';

  home.file."Library/Application Support/Devin/User/settings.json" = lib.mkIf hasDevin {
    text = builtins.toJSON devinSettings;
  };

  home.file.".cspell/custom-dictionary-user.txt".text = ''
    # Personal spell-check words (one per line).
    # Managed by home-manager; add project-specific words in workspace .cspell.json.
  '';
}
