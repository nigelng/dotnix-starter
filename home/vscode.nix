# Cursor and VS Code (+ optional Devin settings): extensions and user settings via home-manager.
# Each editor module is on only when its cask is listed in apps JSON (`cursor`/`code-cursor`,
# `visual-studio-code`) or the user sets programs.<cursor|vscode>.enable = true; HM manages
# config only, never the app. commonBase in ./vscode/extensions.nix is the shared extension set.
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

  cursorCask = lib.any (c: lib.elem c appConfig.casks) [
    "cursor"
    "code-cursor"
  ];
  cursorEnabled = config.programs.cursor.enable;

  vscodeCask = lib.elem "visual-studio-code" appConfig.casks;
  vscodeEnabled = config.programs.vscode.enable;

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

  # Editors/nil format a single buffer via the nixfmt binary; flake `nix fmt` uses nixfmt-tree.
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

  # Shared settings pipeline: Cursor, VS Code and Devin (each when enabled / casked).
  devinSettings = mkEditorSettings {
    workbench.settings.applyToAllProfiles = applyToAllProfiles;
  };

  cursorSettings = mkEditorSettings {
    workbench.settings.applyToAllProfiles = applyToAllProfiles;
  };

  vscodeSettings = mkEditorSettings {
    workbench.settings.applyToAllProfiles = applyToAllProfiles;
  };

  mkEditor = name: userSettings: {
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
  editorUserSettingsPaths =
    lib.optionals cursorEnabled [
      "${config.home.homeDirectory}/Library/Application Support/Cursor/User/settings.json"
    ]
    ++ lib.optionals vscodeEnabled [
      "${config.home.homeDirectory}/Library/Application Support/Code/User/settings.json"
    ]
    ++ lib.optionals hasDevin [
      "${config.home.homeDirectory}/Library/Application Support/Devin/User/settings.json"
    ];

  mkWritableEditorSettingsActivation = mkWritableCopyActivation;

  installCursorPinnedExtensions = pkgs.writeShellScript "install-cursor-pinned-extensions" ''
    set -euo pipefail
    cursor --version >/dev/null 2>&1 || exit 0
    listed=$(cursor --list-extensions 2>/dev/null || true)
    for ext in ${lib.concatStringsSep " " cursorPinnedExtensions}; do
      if ! printf '%s\n' "$listed" | grep -qx "$ext"; then
        cursor --install-extension "$ext" --force
      fi
    done
  '';

in
{
  programs.cursor = mkEditor "cursor" cursorSettings // {
    enable = lib.mkDefault cursorCask;
  };

  programs.vscode = mkEditor "vscode" vscodeSettings // {
    enable = lib.mkDefault vscodeCask;
  };

  home.activation.editorUserSettingsWritable = mkWritableEditorSettingsActivation editorUserSettingsPaths;

  home.activation.unmarkCursorHmExtensions = lib.mkIf cursorEnabled (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      obsolete="$HOME/.cursor/extensions/.obsolete"
      if [ -f "$obsolete" ]; then
        ${pkgs.jq}/bin/jq '${cursorObsoleteJqFilter}' "$obsolete" > "$obsolete.tmp" && mv "$obsolete.tmp" "$obsolete"
      fi
    ''
  );

  home.activation.installCursorPinnedExtensions = lib.mkIf cursorEnabled (
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "unmarkCursorHmExtensions"
      ]
      ''
        ${installCursorPinnedExtensions}
      ''
  );

  home.file."Library/Application Support/Devin/User/settings.json" = lib.mkIf hasDevin {
    text = builtins.toJSON devinSettings;
  };

  home.file.".cspell/custom-dictionary-user.txt".text = ''
    # Personal spell-check words (one per line).
    # Managed by home-manager; add project-specific words in workspace .cspell.json.
  '';
}
