{
  pkgs,
  appConfig,
  fontConfig,
  systemConfig,
  userConfig,
  lib,
  ...
}:
let
  # Flake check validates names first; throws here catch anything at switch time.
  resolvePkg =
    name:
    if !lib.hasAttr name pkgs then
      throw "Unknown system package in app config: ${name}"
    else
      pkgs.${name};

  systemApps = map resolvePkg appConfig.system;
  homebrewCleanup = systemConfig.homebrewCleanup or "zap";

  # Non-official tap casks need a fully-qualified name and trusted: true (not whole-tap trust).
  homebrewCask =
    name:
    let
      tap = appConfig.trustedCasks.${name} or null;
    in
    if tap == null then
      name
    else
      {
        name = "${tap}/${name}";
        trusted = true;
      };

  homebrewCasks = lib.unique (map homebrewCask (appConfig.casks ++ fontConfig.casks));
in
{
  nix = {
    enable = true;
    package = pkgs.nix;

    settings = {
      trusted-users = [ userConfig.user ] ++ systemConfig.trustedUsers;
      allowed-users = [ userConfig.user ] ++ systemConfig.allowedUsers;
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    gc = {
      # Garbage collection
      automatic = true;
      interval.Day = 7;
      options = "--delete-older-than 7d";
    };
  };

  environment = {
    systemPackages = systemApps;

    shells = with pkgs; [
      zsh
      "/etc/profiles/per-user/${userConfig.user}/bin/zsh"
    ];

    variables = { };
  };

  programs = {
    zsh = {
      enable = true;
      # zimfw completion module calls compinit in ~/.config/zsh/.zshrc.
      enableGlobalCompInit = false;
      enableBashCompletion = false;
    };
    gnupg.agent.enable = true;
  };

  homebrew = {
    enable = true;
    taps = appConfig.taps;
    brews = appConfig.brews;
    casks = homebrewCasks;
    prefix = systemConfig.homebrewPrefix;
    global = {
      brewfile = true;
    };
    onActivation = {
      # Per-host: none | check | uninstall | zap (see config/hosts/<host>.json)
      cleanup = homebrewCleanup;
      autoUpdate = true;
      upgrade = false;
      # Homebrew 5.x requires --force-cleanup (or HOMEBREW_ASK) with --cleanup on bundle install.
      extraFlags = lib.optionals (homebrewCleanup == "uninstall" || homebrewCleanup == "zap") [
        "--force-cleanup"
      ];
    };
    masApps = appConfig.mas;
  };

  users.users."${userConfig.user}" = {
    home = "/Users/${userConfig.user}";
  };
}
