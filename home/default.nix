{
  lib,
  pkgs,
  config,
  appConfig,
  userConfig,
  systemConfig,
  hostName,
  editorTooling ? { },
  ...
}:
let
  theme = import ./themes/default.nix;

  # Flake check validates names first; throws here catch anything at switch time.
  resolvePkg =
    name:
    if !lib.hasAttr name pkgs then
      throw "Unknown user package in app config: ${name}"
    else
      pkgs.${name};

  # granted is installed via programs.granted (package + zsh assume integration).
  userAppNames = lib.filter (a: a != "granted") appConfig.user;
  userApps = map resolvePkg userAppNames;
in
{
  imports = [
    ./git.nix
    ./vim.nix
    ./vscode.nix
    ./zsh.nix
  ]
  # editor.nix is only imported when editorTooling is non-empty. This flake
  # always provides editorTooling (prettier-config + eslint-config inputs);
  # the guard remains for overlay repos that don't pass editorTooling.
  ++ lib.optional (editorTooling != { }) ./editor.nix;

  xdg = {
    enable = true;
  };

  programs = {
    home-manager.enable = true;
    dircolors.enable = true;
    man.enable = true;

    btop = {
      enable = true;
      settings = {
        color_theme = theme.btopTheme;
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    eza = {
      enable = true;
      git = true;
      icons = "auto";
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };

    granted = lib.mkIf (lib.elem "granted" appConfig.user) {
      enable = true;
      # assume() wrapper lives in home/zsh.nix (exports GRANTED_ALIAS_CONFIGURED before source).
      enableZshIntegration = false;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      colors = theme.fzfColors;
    };

    gpg = {
      enable = true;
      settings = {
        default-key = userConfig.defaultGpgKey;
        keyserver-options = "include-revoked";
      };
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = true;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "auto";
        ControlPath = "~/.ssh/ssh-control-%r@%h:%p";
        ControlPersist = "5m";
      };

      # Quoted path required (spaces); settings.* does not add quotes for IdentityAgent.
      extraConfig = ''
        IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      '';
    };

    uv = {
      enable = true;
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };
  };

  home = {
    # Silence direnv loading/unloading lines so Powerlevel10k instant prompt
    # does not warn about console I/O during zsh initialization.
    sessionVariables = lib.optionalAttrs config.programs.direnv.enable {
      DIRENV_LOG_FORMAT = "";
    };

    file.".config/btop/themes/catppuccin_mocha.theme".source = ./themes/btop_catppuccin_mocha;

    # Ghostty: Nix defaults + optional user-editable local.conf (see ghostty_local.conf.example).
    file.".config/ghostty/config".text = ''
      config-file = ${config.xdg.configHome}/ghostty/config.d/nix.conf
      config-file = ?${config.xdg.configHome}/ghostty/local.conf
    '';
    file.".config/ghostty/config.d/nix.conf".text = ''
      font-family = ${theme.uiFont}
      font-size = 14
      theme = ${theme.ghosttyTheme}
    '';

    file.".p10k.zsh".source = lib.mkDefault ./config_files/p10k.zsh;

    stateVersion = "26.05";
    sessionPath = systemConfig.extraSessionPaths;
    packages =
      userApps
      ++ lib.optionals (lib.elem "podman" appConfig.system) [
        (pkgs.writeShellScriptBin "docker" ''exec podman "$@"'')
        (pkgs.writeShellScriptBin "docker-compose" ''exec podman-compose "$@"'')
      ]
      ++ lib.optionals (lib.elem "cursor-cli" appConfig.system) [
        (pkgs.writeShellScriptBin "agent" ''exec cursor-agent "$@"'')
      ];

    shellAliases = {
      # Set all shell aliases programatically
      # Aliases for commonly used tools
      find = "fd";
      cls = "clear";
      wo = "cd ~/Workspaces";
      Gcg = "git gc";

      # Nix garbage collection
      collect-garbage = "nix-collect-garbage -d && brew cleanup --prune=all";
    };
  };
}
