moduleArgs@{
  pkgs,
  lib,
  config,
  gitConfig,
  userConfig,
  ...
}:
let
  # Optional: overlays import homeModules.git à la carte without appConfig.
  # specialArgs (extraSpecialArgs) first, then _module.args (unnamed args never resolve it).
  appConfig = moduleArgs.appConfig or config._module.args.appConfig or { };
  cfg = config.my.onePassword;
  theme = import ./themes/default.nix;
in
{
  options.my.onePassword.enable = lib.mkOption {
    type = lib.types.bool;
    default = lib.any (c: lib.elem c (appConfig.casks or [ ])) [
      "1password"
      "1password@beta"
    ];
    defaultText = lib.literalExpression ''
      lib.any (c: lib.elem c (appConfig.casks or [ ])) [ "1password" "1password@beta" ]
    '';
    description = "1Password app integration: SSH agent (IdentityAgent) and op-ssh-sign git signing.";
  };

  config.programs = {
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

      includes = [
        {
          path = ./themes/delta-catppuccin.gitconfig;
        }
      ]
      ++ (gitConfig.includes or [ ]);

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
        commit = lib.mkIf cfg.enable {
          gpgSign = true;
        };
        tag = lib.mkIf cfg.enable {
          gpgSign = true;
        };
        gpg = lib.mkIf cfg.enable {
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

    # Top-level module (HM renamed away from programs.git.delta).
    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        line-numbers = true;
        features = theme.deltaFeatures;
      };
    };
  };
}
