{ pkgs, ... }:
let
  theme = import ./themes/default.nix;
in
{

  programs.neovim = {
    enable = true;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    defaultEditor = true;

    extraConfig = ''
      set termguicolors
      colorscheme ${theme.nvimColorscheme}
    '';

    plugins = with pkgs.vimPlugins; [
      catppuccin-vim
      vim-easy-align
      zoxide-vim
      fzf-vim
      vim-prettier
      editorconfig-vim
    ];
  };
}
