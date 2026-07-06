# One nix-darwin configuration per entry in config/hosts.json.
{
  lib,
  pkgs,
  hosts,
  flakeRoot,
  loadHostConfig,
  loadAppConfig,
  loadFontConfig,
  loadFirefoxConfig,
  loadUserConfig,
  home-manager,
  darwin,
  system,
  gitConfig,
  editorTooling,
  extraHomeModules ? [ ],
  ...
}:

lib.genAttrs hosts (
  hostName:
  let
    systemConfig = loadHostConfig hostName;
    appConfig = loadAppConfig hostName;
    fontConfig = loadFontConfig hostName;
    firefoxConfig = loadFirefoxConfig hostName;
    userConfig = loadUserConfig hostName;
    mkWritableCopyActivation = import ../lib/mk-writable-copy-activation.nix {
      hmLib = home-manager.lib;
      inherit lib pkgs;
    };
  in
  darwin.lib.darwinSystem {
    inherit system;
    specialArgs = {
      inherit
        hostName
        systemConfig
        appConfig
        fontConfig
        firefoxConfig
        userConfig
        ;
    };
    modules = [
      {
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [
          (import ../overlays/google-fonts)
        ];
      }
      ./configuration.nix
      ./system.nix

      home-manager.darwinModules.home-manager
      {
        # Back up existing files (e.g. VS Code settings.json) instead of failing on first switch.
        home-manager.backupFileExtension = "hm-bak";
        # Editor settings.json is copied writable each switch; allow replacing stale .hm-bak backups.
        home-manager.overwriteBackup = true;

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          inherit
            hostName
            systemConfig
            appConfig
            userConfig
            gitConfig
            editorTooling
            firefoxConfig
            mkWritableCopyActivation
            ;
        };
        home-manager.users.${userConfig.user} = {
          # The home module tree always includes firefox.nix so the module
          # options are available. Firefox is only enabled by default when the
          # standalone flake has config/firefox/base.json. Overlay repos without
          # Firefox config get the mkEnableOption default (false) and can opt in
          # by setting my.firefox.enable = true in extraHomeModules.
          imports = [
            (import ../home)
            (import ../home/firefox.nix)
          ]
          ++ extraHomeModules;
          my.firefox.enable = lib.mkIf (builtins.pathExists "${flakeRoot}/config/firefox/base.json") (
            lib.mkDefault true
          );
        };
      }
    ];
  }
)
