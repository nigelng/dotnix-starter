# Nix-managed Android SDK via home-manager my.android options.
#
# JSON defaults (config/android/base.json + hosts/<host>.json) seed option
# defaults. Android is opt-in per host via "enable": true in host JSON.
{
  config,
  pkgs,
  lib,
  androidConfig ? { },
  ...
}:
let
  cfg = config.my.android;

  inherit (pkgs.androidenv.androidPkgs) androidsdk;
  jdk = pkgs.${cfg.jdkPackage};
  sdkRoot = "${androidsdk}/libexec/android-sdk";
  # nixpkgs cmdline-tools layout can change across versions; pick the latest.
  cmdlineToolsVersion = lib.last (
    lib.sort lib.strings.compareVersions (lib.attrNames (builtins.readDir "${sdkRoot}/cmdline-tools"))
  );
  androidToolPaths = [
    "${sdkRoot}/emulator"
    "${sdkRoot}/platform-tools"
    "${sdkRoot}/cmdline-tools/${cmdlineToolsVersion}/bin"
  ];
in
{
  options.my.android = {
    enable = lib.mkEnableOption "Nix-managed Android SDK";

    avdHome = lib.mkOption {
      type = lib.types.str;
      default =
        if androidConfig ? avdHome && androidConfig.avdHome != null then
          androidConfig.avdHome
        else
          "${config.xdg.configHome}/.android/avd";
      description = "Directory for Android Virtual Devices (ANDROID_AVD_HOME).";
    };

    guiSdkSymlink = lib.mkOption {
      type = lib.types.bool;
      default = androidConfig.guiSdkSymlink or true;
      description = ''
        Symlink ~/Library/Android/sdk to the Nix-managed SDK root.
        GUI apps (Android Studio, Gradle) may not inherit session variables.
      '';
    };

    avdDefaultSymlink = lib.mkOption {
      type = lib.types.bool;
      default = androidConfig.avdDefaultSymlink or true;
      description = ''
        Symlink ~/.android/avd to avdHome.
        Emulator and Expo look here when ANDROID_AVD_HOME is unset.
      '';
    };

    jdkPackage = lib.mkOption {
      type = lib.types.str;
      default = androidConfig.jdkPackage or "jdk";
      description = "nixpkgs attribute name for the JDK package (e.g. jdk, jdk17).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      androidsdk
      jdk
    ];

    home.sessionPath = androidToolPaths;

    home.sessionVariables = {
      ANDROID_SDK_ROOT = sdkRoot;
      ANDROID_HOME = sdkRoot;
      ANDROID_AVD_HOME = cfg.avdHome;
      JAVA_HOME = jdk.home;
    };

    home.file = lib.optionalAttrs cfg.guiSdkSymlink {
      "Library/Android/sdk".source = sdkRoot;
    };

    home.activation.androidAvdHomeSymlink = lib.mkIf cfg.avdDefaultSymlink (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.android"
        if [ -e "$HOME/.android/avd" ] && [ ! -L "$HOME/.android/avd" ]; then
          echo "refusing to replace existing ~/.android/avd directory" >&2
          exit 1
        fi
        ln -sfn "${cfg.avdHome}" "$HOME/.android/avd"
      ''
    );
  };
}
