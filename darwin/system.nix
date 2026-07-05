{
  pkgs,
  lib,
  systemConfig,
  fontConfig,
  userConfig,
  ...
}:
let
  pkgsFonts = builtins.map (app: builtins.getAttr app pkgs) fontConfig.pkgs;
  nerdFonts = builtins.map (app: builtins.getAttr app pkgs.nerd-fonts) fontConfig.nerd;
  googleFonts = builtins.map (name: pkgs.${"google-fonts-" + name}) fontConfig.google;
in
{
  system = {
    primaryUser = userConfig.user;
    # Set once at install; bump only after `darwin-rebuild changelog` (see README).
    stateVersion = 6;

    keyboard = {
      enableKeyMapping = true;
    };

    defaults = {
      NSGlobalDomain = {
        # expand the save panel by default
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;

        # Disable automatic typography options I find annoying while typing code
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;

        # enable tap-to-click (mode 1)
        "com.apple.mouse.tapBehavior" = 1;

        # sound control
        "com.apple.sound.beep.volume" = 0.4723665; # 25%
        "com.apple.trackpad.enableSecondaryClick" = true;

        # Enable full keyboard access for all controls
        # (e.g. enable Tab in modal dialogs)
        AppleKeyboardUIMode = 3;

        # Set a very fast keyboard repeat rate
        KeyRepeat = 2;
        InitialKeyRepeat = 10;

        AppleTemperatureUnit = "Celsius";
        AppleICUForce24HourTime = true;
      };

      ActivityMonitor = {
        ShowCategory = 102; # 102: My Processes
        SortColumn = "CPUUsage";
      };

      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

      finder = {
        # show full POSIX path as Finder window title
        _FXShowPosixPathInTitle = false;

        # disable the warning when changing a file extension
        FXEnableExtensionChangeWarning = false;
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        FXPreferredViewStyle = "Nlsv";
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
        TrackpadRightClick = true;
      };

      menuExtraClock = {
        Show24Hour = true;
        ShowDayOfWeek = true;
      };

      dock = {
        tilesize = 48;
        orientation = "left";
        show-process-indicators = true;

        # enable spring loading (hold a dragged file over an icon to drop/open it there)
        enable-spring-load-actions-on-all-items = true;
        # don't automatically rearrange spaces based on the most recent one
        mru-spaces = false;
      };

      screencapture = {
        location = systemConfig.screenshotFolder;
        type = "png";
      };
    };
  };

  networking = {
    computerName = systemConfig.computerName;
    hostName = systemConfig.hostName;
    knownNetworkServices = systemConfig.knownNetworkServices;

    applicationFirewall = {
      enable = true;
      enableStealthMode = true;
    };
  };

  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
    watchIdAuth = true;
  };

  power = lib.mkMerge [
    {
      restartAfterFreeze = true;
    }
    (lib.mkIf systemConfig.restartAfterPowerFailure {
      restartAfterPowerFailure = true;
    })
  ];

  # fonts
  fonts = {
    packages = pkgsFonts ++ nerdFonts ++ googleFonts;
  };
}
