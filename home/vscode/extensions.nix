# Shared extension sets for Cursor (active) and future VS Code reinstatement.
# commonBase is the Cursor HM foundation — do not dissolve into an anonymous list.
# Devin shares the settings pipeline in home/vscode.nix only (not this extension list).
# nix-ide, python-envs, and pylance are CLI-pinned for Cursor (not listed in commonBase).
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  inherit (pkgs) vscode-extensions;
  extra = import ./extensions-extra.nix { inherit pkgs; };

  commonBase =
    with vscode-extensions;
    [
      esbenp.prettier-vscode
      editorconfig.editorconfig
      catppuccin.catppuccin-vsc
      catppuccin.catppuccin-vsc-icons
      streetsidesoftware.code-spell-checker
      mhutchie.git-graph
      github.vscode-github-actions
      ms-python.python
      ms-python.debugpy
      ms-azuretools.vscode-containers
      aaron-bond.better-comments
      davidanson.vscode-markdownlint
      dbaeumer.vscode-eslint
      yoavbls.pretty-ts-errors
      bradlc.vscode-tailwindcss
    ]
    ++ (with extra; [
      tomoyukim.vscode-mermaid-editor
      streetsidesoftware.code-spell-checker-australian-english
    ]);

  # Kept as separate attrs so VS Code can HM-install them again on reinstatement.
  # Cursor installs these via CLI in home/vscode.nix (HM symlinks alone are not enough).
  nixIdeVscode = vscode-extensions.jnoortheen.nix-ide;
  pythonEnvsVscode = vscode-extensions.ms-python.vscode-python-envs;
  pylanceVscode = vscode-extensions.ms-python.vscode-pylance;

  # Future VS Code reinstate example:
  # vscodeOnly = [ anthropic.claude-code github.copilot-chat … ];
  # vscode = lib.unique (commonBase ++ [ nixIdeVscode pythonEnvsVscode pylanceVscode ] ++ vscodeOnly);
in
{
  inherit
    commonBase
    nixIdeVscode
    pythonEnvsVscode
    pylanceVscode
    ;
  cursor = lib.unique commonBase;
}
