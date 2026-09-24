# Nix-managed Android SDK via home-manager my.android options.
#
# JSON defaults (config/android/base.json + hosts/<host>.json) seed option
# defaults. Android is opt-in per host via "enable": true in host JSON.
#
# SDK composition lives inside mkIf so hosts with enable=false do not force
# unfree androidenv packages (nixpkgs.config.allowUnfree = true in darwin/default.nix).
{
  config,
  pkgs,
  lib,
  androidConfig ? { },
  ...
}:
let
  cfg = config.my.android;
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

    platformVersions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        androidConfig.platformVersions or [
          "34"
          "35"
        ];
      description = "Android API levels to include (e.g. [ \"35\" ]).";
    };

    systemImageTypes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = androidConfig.systemImageTypes or [ "google_apis_playstore" ];
      description = "System image types to include (google_apis or google_apis_playstore).";
    };

    abiVersions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = androidConfig.abiVersions or [ "arm64-v8a" ];
      description = "ABIs to include. arm64-v8a is sufficient for Apple Silicon.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      sdk = pkgs.androidenv.composeAndroidPackages {
        platformVersions = cfg.platformVersions;
        systemImageTypes = cfg.systemImageTypes;
        abiVersions = cfg.abiVersions;
        includeEmulator = true;
        includeNDK = true;
        includeSystemImages = true;
      };
      androidsdk = sdk.androidsdk;
      jdk = pkgs.${cfg.jdkPackage};
      sdkRoot = "${androidsdk}/libexec/android-sdk";
      # Use androidenv's package path from repo.json (eval-time). Do NOT
      # builtins.readDir the SDK store path — that is IFD and breaks
      # `nix flake check --no-build` on Android-enabled hosts.
      cmdlineToolsBin = "${sdkRoot}/${sdk.cmdline-tools-package.path}/bin";
      androidToolPaths = [
        "${sdkRoot}/emulator"
        "${sdkRoot}/platform-tools"
        cmdlineToolsBin
      ];
    in
    {
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
    }
  );
}
