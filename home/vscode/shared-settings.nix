# Shared VS Code / Cursor user settings (Nix attribute set → settings.json).
{ lib }:
let
  formatters = import ./formatters.nix { inherit lib; };
  theme = import ../themes/default.nix;

  baseSettings = {
    cSpell.autoFormatConfigFile = true;
    # Australian English (dictionary extension in commonBase).
    cSpell.language = "en-AU";
    cSpell.customDictionaries.custom = {
      addWords = true;
      name = "user";
      path = "~/.cspell/custom-dictionary-user.txt";
    };

    debug.console.fontSize = 14;
    editor.codeLensFontFamily = "\"${theme.uiFont}\"";
    editor.fontFamily = "\"${theme.uiFont}\", Monaco, 'Courier New', monospace";
    editor.fontLigatures = true;
    editor.fontSize = 14;
    editor.fontVariations = false;
    editor.fontWeight = "normal";
    editor.formatOnSave = true;
    editor.formatOnSaveExclude = {
      "**/.vscode/settings.json" = true;
      "**/User/settings.json" = true;
    };
    editor.formatOnType = true;
    editor.lineHeight = 1.5;
    editor.renderWhitespace = "none";

    "[nix]" = {
      editor.defaultFormatter = "jnoortheen.nix-ide";
      editor.formatOnSave = true;
    };

    eslint.validate = [
      "javascript"
      "javascriptreact"
      "typescript"
      "typescriptreact"
    ];

    files.associations = {
      "*.nix" = "nix";
      "flake.nix" = "nix";
    };
    files.trimTrailingWhitespace = true;

    git.autofetch = true;

    # User overrides replace VS Code defaults; include builtins plus extension schema hosts.
    json.schemaDownload.trustedDomains = {
      "https://schemastore.azurewebsites.net/" = true;
      "https://raw.githubusercontent.com/microsoft/vscode/" = true;
      "https://raw.githubusercontent.com/devcontainers/spec/" = true;
      "https://www.schemastore.org/" = true;
      "https://json.schemastore.org/" = true;
      "https://json-schema.org/" = true;
      "https://developer.microsoft.com/json-schemas/" = true;
      "https://raw.githubusercontent.com/catppuccin/vscode/" = true;
    };

    nix.enableLanguageServer = true;
    nix.formatterPath = "nixfmt";
    nix.serverPath = "nil";
    nix.serverSettings.nil.formatting.command = [ "nixfmt" ];

    prettier.useEditorConfig = true;

    scm.inputFontSize = 14;
    security.workspace.trust.untrustedFiles = "prompt";

    telemetry.telemetryLevel = "off";
    telemetry.enableTelemetry = false;
    telemetry.enableCrashReporter = false;

    terminal.integrated.fontSize = 15;
    terminal.integrated.lineHeight = 1.25;
    terminal.integrated.enableKittyKeyboardProtocol = false;

    tailwindCSS.emmetCompletions = true;

    workbench.colorTheme = theme.vscodeTheme;
    workbench.iconTheme = theme.iconTheme;
    workbench.sideBar.location = "left";
    workbench.startupEditor = "none";

    # Layout — shared across Cursor and Devin-desktop.
    workbench.panel.defaultLocation = "bottom";
    workbench.panel.opensMaximized = "never";
    workbench.editor.showTabs = "multiple";
    workbench.editor.tabSizing = "shrink";
    workbench.editor.openSideBySideDirection = "left";
    workbench.statusBar.visible = true;
    workbench.secondarySideBar.visible = true;
    window.menuBarVisibility = "compact";
    terminal.integrated.defaultLocation = "view";
  };
in
lib.foldl' lib.recursiveUpdate baseSettings [
  formatters.prettierLangSettings
  formatters.eslintSettings
  formatters.editorconfigSettings
]
