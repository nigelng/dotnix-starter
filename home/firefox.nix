# Firefox backup browser via home-manager programs.firefox.
#
# JSON defaults (config/firefox/base.json) seed the my.firefox option defaults.
# Overlay consumers can override any option (settings, extensions, package).
# Extensions are installed via home.file symlinks into the profile's extensions/
# directory (useDeclarativeExtensions = false, the default), with force = true and
# a post-switch activation that re-links and lists the directory.
{
  config,
  pkgs,
  lib,
  firefoxConfig ? { },
  ...
}:
let
  cfg = config.my.firefox;

  addons = import ./firefox/addons.nix { inherit pkgs lib; };

  # Resolve JSON nix-extension slugs to fetchFirefoxAddon packages.
  nixAddonPkgs = addons.resolveSlugs (firefoxConfig.extensions.nix or [ ]);

  # Resolve manual extension entries from the option (seeded by JSON defaults).
  manualAddonPkgs = map addons.mkAddon cfg.manualExtensions;

  allAddonPkgs = nixAddonPkgs ++ manualAddonPkgs ++ cfg.nixExtensions;

  # Firefox profile extensions directory under macOS.
  firefoxExtensionsDir = "Library/Application Support/Firefox/Profiles/${cfg.profileName}/extensions";
in
{
  options.my.firefox = {
    enable = lib.mkEnableOption "Firefox backup browser";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.${firefoxConfig.package or "firefox-bin"};
      description = "Firefox package to install.";
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = firefoxConfig.profileName or "default";
      description = "home-manager Firefox profile name.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = firefoxConfig.settings or { };
      description = "Firefox about:config preferences keyed by preference name.";
    };

    nixExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional Firefox add-on packages to install (merged with JSON nix extensions).";
    };

    manualExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = firefoxConfig.extensions.manual or [ ];
      description = "Manually-specified XPI add-ons ({ name, addonId, url, hash }).";
    };

    useDeclarativeExtensions = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use programs.firefox declarative extensions instead of home.file symlinks.
        May not work reliably with firefox-bin on macOS; disabled by default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      package = cfg.package;
      profiles.${cfg.profileName} = {
        id = 0;
        path = cfg.profileName;
        isDefault = true;
        settings =
          cfg.settings
          // lib.optionalAttrs (allAddonPkgs != [ ]) {
            # home-manager documents this pref for store/XPI-installed extensions;
            # without it Firefox may leave sideloaded add-ons disabled.
            "extensions.autoDisableScopes" = 0;
          };
      }
      // lib.optionalAttrs cfg.useDeclarativeExtensions {
        extensions.packages = allAddonPkgs;
      };
    };

    # Default path: symlink each XPI into the profile's extensions/ directory
    # via home.file. force = true re-applies symlinks if Firefox removed or
    # replaced them since the last switch.
    home.file = lib.mkIf (!cfg.useDeclarativeExtensions) (
      builtins.listToAttrs (
        map (pkg: {
          name = "${firefoxExtensionsDir}/${pkg.passthru.extid}.xpi";
          value = {
            source = "${pkg}/${pkg.passthru.extid}.xpi";
            force = true;
          };
        }) allAddonPkgs
      )
    );

    # After home.file runs, re-link and list extensions so every switch repairs
    # sideloaded XPIs and prints the profile extensions directory.
    home.activation.ensureFirefoxExtensions =
      lib.mkIf (!cfg.useDeclarativeExtensions && allAddonPkgs != [ ])
        (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            extensionsDir="$HOME/${firefoxExtensionsDir}"
            mkdir -p "$extensionsDir"
            ${lib.concatMapStrings (
              pkg:
              let
                xpi = "${pkg}/${pkg.passthru.extid}.xpi";
              in
              ''
                ln -sfn ${lib.escapeShellArg xpi} "$extensionsDir/${pkg.passthru.extid}.xpi"
              ''
            ) allAddonPkgs}
            echo "Firefox extensions in $extensionsDir:"
            ${pkgs.coreutils}/bin/ls -la "$extensionsDir"
          ''
        );
  };
}
