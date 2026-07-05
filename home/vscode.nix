# VS Code and Cursor: extensions + user settings via home-manager.
# Editors are installed as system packages (config/apps/base.json); HM manages config only.
# Cursor pins older extensions (VS Code engine ~1.105); VS Code uses current nixpkgs versions.
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
  hasFlutter = lib.elem "flutter" appConfig.user;
  extensionSets = import ./vscode/extensions.nix { inherit pkgs lib hasFlutter; };

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

  flutterSettings = lib.optionalAttrs hasFlutter {
    "dart.flutterSdkPath" = "${pkgs.flutter}";
    "dart.sdkPath" = "${pkgs.flutter}/bin/cache/dart-sdk";
  };

  cursorObsoleteKeyPrefixes = [
    "jnoortheen.nix-ide"
    "ms-python.vscode-python-envs"
  ]
  ++ lib.optionals hasFlutter [
    "Dart-Code.dart-code"
    "Dart-Code.flutter"
  ];

  cursorObsoleteJqFilter =
    let
      prefixTests = lib.concatMapStringsSep " or " (p: "startswith(\"${p}\")") cursorObsoleteKeyPrefixes;
    in
    "with_entries(select((.key | ${prefixTests}) | not))";

  mkEditorSettings =
    extras:
    lib.recursiveUpdate sharedSettings (nixToolPaths // jsLintSettings // flutterSettings // extras);

  vscodeSettings = mkEditorSettings {
    chat.editor.fontFamily = sharedSettings.editor.fontFamily;
    chat.editor.fontSize = 14;
    chat.mcp.gallery.enabled = true;
    githubPullRequests.pullBranch = "never";
    terminal.external.osxExec = "ghostty.app";
    workbench.settings.applyToAllProfiles = applyToAllProfiles;
  };

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
  ]
  ++ lib.optionals hasFlutter [
    "Dart-Code.dart-code"
    "Dart-Code.flutter"
  ];

  devinPinnedExtensions = lib.optionals (hasFlutter && hasDevin) [
    {
      id = "Dart-Code.dart-code";
      path = "${pkgs.vscode-extensions.dart-code.dart-code}";
    }
    {
      id = "Dart-Code.flutter";
      path = "${pkgs.vscode-extensions.dart-code.flutter}";
    }
  ];

  # VS Code-family editors rewrite settings.json on startup; HM store symlinks are read-only.
  editorUserSettingsPaths = [
    "${config.home.homeDirectory}/Library/Application Support/Code/User/settings.json"
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

  installDevinPinnedExtensions = pkgs.writeShellScript "install-devin-pinned-extensions" ''
    set -euo pipefail
    if ! command -v devin-desktop >/dev/null 2>&1; then
      exit 0
    fi
    listed=$(devin-desktop --list-extensions 2>/dev/null || true)
    ${lib.concatMapStrings (
      { id, path }:
      let
        escapedPath = lib.escapeShellArg path;
      in
      ''
        if ! printf '%s\n' "$listed" | grep -qx "${id}"; then
          devin-desktop --install-extension ${escapedPath} --force
        fi
      ''
    ) devinPinnedExtensions}
  '';

in
{
  programs.vscode = mkEditor "vscode" vscodeSettings;
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

  home.activation.installDevinPinnedExtensions = lib.mkIf (hasFlutter && hasDevin) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${installDevinPinnedExtensions}
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
