{
  pkgs,
  appConfig,
  config,
  fontConfig,
  systemConfig,
  userConfig,
  lib,
  ...
}:
let
  inherit ((import ../lib/resolve-pkg.nix { inherit lib; })) resolvePkg;

  systemApps = map (resolvePkg pkgs "system package") appConfig.system;
  homebrewCleanup = systemConfig.homebrewCleanup or "check";

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
      # adminUsername is always trusted; trustedUsers adds extras. Never add "*".
      # The assertions below reject unsafe entries in the final merged lists.
      trusted-users = [ userConfig.user ] ++ systemConfig.trustedUsers;
      allowed-users = [ userConfig.user ] ++ systemConfig.allowedUsers;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    gc = {
      # Garbage collection
      automatic = true;
      # Sunday 03:00 local time (launchd StartCalendarInterval; Weekday 0 = Sunday)
      interval = {
        Weekday = 0;
        Hour = 3;
        Minute = 0;
      };
      options = "--delete-older-than 14d";
    };

    optimise = {
      # Replaces auto-optimise-store (inline dedup on every build); a weekly pass is safer on macOS
      automatic = true;
      # Sunday 04:00 local time, an hour after gc (launchd StartCalendarInterval; Weekday 0 = Sunday)
      interval = {
        Weekday = 0;
        Hour = 4;
        Minute = 0;
      };
    };
  };

  # Checks the final nix.settings trusted-users, allowed-users, extra-trusted-users and extra-allowed-users,
  # so values from overlay loaders and extra darwin modules are included. Free-form nix.extraOptions is not inspected.
  assertions =
    let
      unsafe =
        u:
        lib.any (c: lib.hasInfix c u) [
          "*"
          " "
          "\t"
          "\n"
          "\r"
        ];
      check = name: users: {
        assertion = !(lib.any unsafe users);
        message = "nix.settings.${name} contains unsafe entries ${builtins.toJSON (lib.filter unsafe users)}: entries must not contain \"*\" or whitespace (check trustedUsers/allowedUsers/adminUsername in config/hosts/<host>.json and any extra darwin modules).";
      };
    in
    [
      (check "trusted-users" config.nix.settings.trusted-users)
      (check "allowed-users" config.nix.settings.allowed-users)
      # Nix also honours the extra-* variants (freeform nix.settings); a bare string is wrapped and is unsafe if it holds "*" or whitespace.
      (check "extra-trusted-users" (lib.toList (config.nix.settings.extra-trusted-users or [ ])))
      (check "extra-allowed-users" (lib.toList (config.nix.settings.extra-allowed-users or [ ])))
    ];

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
