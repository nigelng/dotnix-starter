# Firefox backup browser via home-manager programs.firefox.
#
# Install the Firefox app via Homebrew cask (config/apps casks: "firefox").
# This module manages profile, settings, and extensions only — package is
# always null (no nixpkgs Firefox). Default add-on install uses enterprise
# ExtensionSettings with pinned AMO file URLs (works with Homebrew Firefox).
# Optional extensionInstallMode = "sideload" keeps the old profile XPI path.
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

  nixEntries = addons.resolveSlugEntries (firefoxConfig.extensions.nix or [ ]);
  manualEntries = cfg.manualExtensions;
  allEntries = nixEntries ++ manualEntries;

  extensionSettings = addons.toExtensionSettings allEntries;

  # Sideload escape hatch only — fetches XPIs into the store.
  allAddonPkgs =
    if cfg.extensionInstallMode == "sideload" then (map addons.mkAddon allEntries) else [ ];

  firefoxExtensionsDir = "Library/Application Support/Firefox/Profiles/${cfg.profileName}/extensions";

  isPolicy = cfg.extensionInstallMode == "policy";
  isSideload = cfg.extensionInstallMode == "sideload";
in
{
  options.my.firefox = {
    enable = lib.mkEnableOption "Firefox backup browser";

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

    manualExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = firefoxConfig.extensions.manual or [ ];
      description = "Manually-specified XPI add-ons ({ name, addonId, url, hash }).";
    };

    extensionInstallMode = lib.mkOption {
      type = lib.types.enum [
        "policy"
        "sideload"
      ];
      default = "policy";
      description = ''
        How to install add-ons. "policy" (default) uses programs.firefox.policies
        ExtensionSettings with pinned install URLs — required for Homebrew Firefox.
        "sideload" symlinks store XPIs into the profile extensions/ directory
        (escape hatch; not recommended with official/Homebrew Firefox builds).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      # Always null: Firefox.app comes from the Homebrew cask, never nixpkgs.
      package = null;
      policies = lib.mkIf (isPolicy && allEntries != [ ]) {
        ExtensionSettings = extensionSettings;
      };
      profiles.${cfg.profileName} = {
        id = 0;
        path = cfg.profileName;
        isDefault = true;
        settings =
          cfg.settings
          // lib.optionalAttrs (isSideload && allAddonPkgs != [ ]) {
            # Needed so Firefox does not leave profile-dir sideloads disabled.
            "extensions.autoDisableScopes" = 0;
          };
      };
    };

    home.file = lib.mkIf isSideload (
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

    home.activation.ensureFirefoxExtensions = lib.mkIf (isSideload && allAddonPkgs != [ ]) (
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
