# Declarative extension sets for VS Code and Cursor.
{
  pkgs,
  lib ? pkgs.lib,
  hasFlutter ? false,
}:
let
  inherit (pkgs) vscode-extensions;
  extra = import ./extensions-extra.nix { inherit pkgs; };

  flutterDev = lib.optionals hasFlutter (
    with vscode-extensions.dart-code;
    [
      dart-code
      flutter
    ]
  );

  commonBase =
    with vscode-extensions;
    [
      esbenp.prettier-vscode
      editorconfig.editorconfig
      catppuccin.catppuccin-vsc
      catppuccin.catppuccin-vsc-icons
      streetsidesoftware.code-spell-checker
      redhat.vscode-yaml
      mhutchie.git-graph
      github.vscode-pull-request-github
      github.vscode-github-actions
      ms-python.python
      ms-python.debugpy
      ms-azuretools.vscode-containers
      aaron-bond.better-comments
      davidanson.vscode-markdownlint
      bierner.markdown-preview-github-styles
      naumovs.color-highlight
      arrterian.nix-env-selector
      dbaeumer.vscode-eslint
      yoavbls.pretty-ts-errors
      bradlc.vscode-tailwindcss
    ]
    ++ (with extra; [
      artdiniz.quitcontrol-vscode
      arcanis.vscode-zipfs
      pomdtr.excalidraw-editor
      ms-vscode.atom-keybindings
      orta.vscode-jest
      tomoyukim.vscode-mermaid-editor
      wayou.vscode-todo-highlight
      tyriar.lorem-ipsum
    ])
    ++ flutterDev;

  nixIdeVscode = vscode-extensions.jnoortheen.nix-ide;

  pythonEnvsVscode = vscode-extensions.ms-python.vscode-python-envs;

  vscodeOnly =
    with vscode-extensions;
    [
      anthropic.claude-code
      github.copilot-chat
      ms-python.vscode-pylance
    ]
    ++ [
      extra.npxms.hide-gitignored
    ];

in
{
  inherit
    commonBase
    vscodeOnly
    nixIdeVscode
    pythonEnvsVscode
    ;
  vscode = lib.unique (
    commonBase
    ++ [
      nixIdeVscode
      pythonEnvsVscode
    ]
    ++ vscodeOnly
  );
  # Nix IDE + Python Environments are installed for Cursor via CLI in home/vscode.nix
  # (HM symlinks alone are not picked up by Cursor's extension host).
  cursor = lib.unique commonBase;
}
