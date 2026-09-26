{
  pkgs,
  gitConfig,
  userConfig,
  ...
}:
let
  theme = import ./themes/default.nix;
in
{
  programs = {
    gh = {
      enable = true;
      settings = {
        prompt = "enabled";
        editor = "nvim";
        git_protocol = "https";
      };
      gitCredentialHelper.enable = true;
      extensions = with pkgs; [
        gh-eco
        gh-dash
        gh-markdown-preview
      ];
    };

    git = gitConfig // {
      enable = true;

      delta = {
        enable = true;
        options = {
          navigate = true;
          line-numbers = true;
          features = theme.deltaFeatures;
        };
      };

      includes = [
        {
          path = ./themes/delta-catppuccin.gitconfig;
        }
      ];

      lfs = {
        enable = true;
        skipSmudge = true;
      };

      settings = {
        user = {
          name = userConfig.name;
          email = userConfig.email;
          "useConfigOnly" = true;
          signingKey = userConfig.defaultSigningKey;
        };
        commit = {
          gpgSign = true;
        };
        tag = {
          gpgSign = true;
        };
        gpg = {
          format = "ssh";
          ssh = {
            program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
          };
        };
        init = {
          "defaultBranch" = "main";
        };
        merge = {
          "conflictstyle" = "diff3";
        };
        push = {
          "autoSetupRemote" = true;
        };
        core = {
          preloadindex = true;
          editor = "nvim";
        };
        color = {
          ui = true;
          status = "always";
        };
      };
    };
  };
}
