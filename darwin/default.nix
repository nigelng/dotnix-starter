# One nix-darwin configuration per entry in config/hosts.json.
{
  lib,
  pkgs,
  hosts,
  loadHostConfig,
  loadAppConfig,
  loadFontConfig,
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
            mkWritableCopyActivation
            ;
        };
        home-manager.users.${userConfig.user} = {
          imports = [ (import ../home) ] ++ extraHomeModules;
        };
      }
    ];
  }
)
