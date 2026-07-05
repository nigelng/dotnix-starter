{ pkgs, ... }:
{

  programs.neovim = {
    enable = true;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    defaultEditor = true;

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
