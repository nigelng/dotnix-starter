{
  lib,
  pkgs,
  config,
  systemConfig,
  userConfig,
  mkWritableCopyActivation,
  ...
}:
{
  home.packages = [
    pkgs.zimfw
    pkgs.zsh-powerlevel10k
    # `p10k` is a zsh function; wrapper loads an interactive login shell so `p10k configure` works from any shell.
    (pkgs.writeShellScriptBin "p10k" ''
      exec ${pkgs.zsh}/bin/zsh -lic '
        export POWERLEVEL9K_CONFIG_FILE="''${HOME}/.p10k.zsh"
        p10k "$@"
      ' _ "$@"
    '')
  ];

  # HM symlinks ~/.p10k.zsh from the store (read-only); p10k configure must write the file.
  home.activation.p10kConfigWritable = mkWritableCopyActivation [
    "${config.home.homeDirectory}/.p10k.zsh"
  ];
  home.activation.clearStaleZcompdump = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    rm -f "${config.home.homeDirectory}/.config/zsh/.zcompdump" \
          "${config.home.homeDirectory}/.config/zsh/.zcompdump.dat" \
          "${config.home.homeDirectory}/.config/zsh/.zcompdump.zwc"
  '';

  home.file.".config/zsh/.zim/zimfw.zsh".source = "${pkgs.zimfw}/zimfw.zsh";

  home.file.".config/zsh/.zimrc".text = ''
    ## Managed by home-manager (see home/zsh.nix). Run `zimfw` after edits.

    zmodule environment
    zmodule completion
    zmodule git
    zmodule input
    zmodule termtitle
    zmodule utility
    zmodule archive
  '';

  programs.zsh = {
    enable = true;
    autocd = true;
    dotDir = "${config.xdg.configHome}/zsh";

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    # zimfw initializes completion; avoid compinit running twice.
    completionInit = "";

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "code";
    }
    // lib.optionalAttrs config.programs.granted.enable {
      # Skip Granted's interactive ~/.zshenv alias installer (we manage assume below).
      GRANTED_ALIAS_CONFIGURED = "true";
    };

    shellAliases = {
      # Example: load a secret from 1Password into an environment variable.
      # Uncomment and replace <op-item-id> with your 1Password item ID.
      # load_secret = "export MY_TOKEN=$(${pkgs._1password-cli}/bin/op item get <op-item-id> --reveal --fields label=token)";
    };

    history = {
      extended = true;
      share = true;
    };

    historySubstringSearch.enable = true;

    initContent = lib.mkMerge [
      (lib.mkBefore ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      (
        (lib.optionalString config.programs.granted.enable ''
          # bin/assume is /bin/sh; it cannot see zsh aliases and only skips the setup
          # wizard when GRANTED_ALIAS_CONFIGURED=true before assumego runs.
          assume() {
            export GRANTED_ALIAS_CONFIGURED=true
            source ${config.programs.granted.package}/bin/assume "$@"
          }

        '')
        + (lib.optionalString config.programs.granted.enable ''
          # Tab completion for assume profiles (created on first Granted use).
          if [[ -d ''${HOME}/.granted/zsh_autocomplete ]]; then
            fpath=(''${HOME}/.granted/zsh_autocomplete ''${fpath})
          fi

        '')
        + ''
          bindkey -e

          ZIM_HOME=''${ZDOTDIR}/.zim

          if [[ ! ''${ZIM_HOME}/init.zsh -nt ''${ZDOTDIR}/.zimrc ]]; then
            source ''${ZIM_HOME}/zimfw.zsh init -q
          fi

          source ''${ZIM_HOME}/init.zsh

          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
          # Config lives at ~/.p10k.zsh (not under ZDOTDIR); pattern matches p10k configure integration check.
          [[ ! -f ''${HOME}/.p10k.zsh ]] || source ''${HOME}/.p10k.zsh

          autoload -Uz bashcompinit && bashcompinit

          bindkey '^A' beginning-of-line
          bindkey '^E' end-of-line
          bindkey '^B' backward-word
          bindkey '^F' forward-word

          # Suppress stderr: op can print "[ERROR] account is not signed in" when
          # 1Password CLI isn't authenticated at shell startup, which leaks past
          # the p10k instant prompt preamble and triggers its verbose warning.
          eval "$(op completion zsh 2>/dev/null)"; compdef _op op
          eval "$(fnm env --use-on-cd --shell zsh)"
        ''
        + (lib.optionalString config.programs.granted.enable ''
          if [[ -o interactive ]]; then
            # Auto-assume a profile on shell startup. Uncomment and replace
            # with your Granted profile name. Granted prints a status message
            # to stdout on assume; redirect to avoid the p10k instant prompt warning.
            # assume your-profile-name &>/dev/null
          fi
        '')
      )
    ];

    profileExtra = ''
      eval "$(${systemConfig.homebrewPrefix}/bin/brew shellenv)"
    '';
  };
}
