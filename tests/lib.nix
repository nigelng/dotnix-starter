# Unit tests for the pure merge/resolve functions in lib/default.nix.
# Run: nix eval --impure --json --expr '(import ./tests/lib.nix { lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; }).results'
# `results` is empty when every test passes. Test names must start with "test".
{ lib }:

let
  flakeLib = import ../lib { inherit lib; };
  inherit (flakeLib)
    mergeAppConfig
    mergeFontConfig
    mergeFirefoxConfig
    mergeAndroidConfig
    resolveHostConfig
    checkHostsManifest
    ;

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;

  schemaProps =
    name: builtins.attrNames (lib.importJSON ../config/schema/${name}.schema.json).properties;
  schemaRequired = name: (lib.importJSON ../config/schema/${name}.schema.json).required;
  missingFrom = name: out: lib.subtractLists (builtins.attrNames out) (schemaProps name);

  # Minimal valid raw host for resolveHostConfig.
  rawLaptop = {
    machineType = "laptop";
  };
  rawMini = {
    machineType = "macmini";
  };

  # Sample values for every key the host schema requires.
  hostSamples = {
    description = "d";
    adminUsername = "admin";
    machineType = "laptop";
    computerName = "c";
    hostName = "h";
    screenshotFolder = "~/Pictures";
    homebrewPrefix = "/opt/homebrew";
    homebrewCleanup = "check";
    trustedUsers = [ "admin" ];
    allowedUsers = [ "admin" ];
  };
  requiredOnlyRaw = lib.genAttrs (schemaRequired "host") (k: hostSamples.${k});

  fullApps = {
    base = {
      system = [ "a" ];
      user = [ "b" ];
      taps = [ "t" ];
      brews = [ "x" ];
      casks = [ "c" ];
      trustedCasks = {
        c = true;
      };
      mas = {
        Foo = 1;
      };
    };
    host = {
      system = [ "z" ];
    };
  };

  fullFonts = {
    base = {
      pkgs = [ "p" ];
      nerd = [ "n" ];
      google = [ "g" ];
      casks = [ "c" ];
    };
    host = { };
  };

  fullFirefox = {
    base = {
      enable = true;
      profileName = "base";
      settings = {
        a = 1;
      };
      extensions = {
        nix = [ "n" ];
        manual = [ ];
      };
    };
    host = { };
  };

  fullAndroid = {
    base = {
      avdHome = "/x";
      guiSdkSymlink = false;
      avdDefaultSymlink = false;
      jdkPackage = "jdk17";
      platformVersions = [ "33" ];
      systemImageTypes = [ "default" ];
      abiVersions = [ "x86_64" ];
    };
    host = {
      enable = true;
    };
  };

  tests = {
    # ---- mergeAppConfig ----
    testAppsUnionDedupe = {
      expr =
        mergeAppConfig
          {
            system = [
              "a"
              "b"
            ];
          }
          {
            system = [
              "b"
              "c"
            ];
          };
      expected = (mergeAppConfig { } { }) // {
        system = [
          "a"
          "b"
          "c"
        ];
      };
    };
    testAppsUserTapsBrewsCasksDedupe = {
      expr =
        let
          m =
            mergeAppConfig
              {
                user = [ "u" ];
                taps = [ "t" ];
                brews = [ "b" ];
                casks = [ "c" ];
              }
              {
                user = [
                  "u"
                  "v"
                ];
                taps = [
                  "t"
                  "t2"
                ];
                brews = [
                  "b"
                  "b2"
                ];
                casks = [
                  "c"
                  "c2"
                ];
              };
        in
        [
          m.user
          m.taps
          m.brews
          m.casks
        ];
      expected = [
        [
          "u"
          "v"
        ]
        [
          "t"
          "t2"
        ]
        [
          "b"
          "b2"
        ]
        [
          "c"
          "c2"
        ]
      ];
    };
    testAppsEmptyDefaults = {
      expr = mergeAppConfig { } { };
      expected = {
        system = [ ];
        user = [ ];
        taps = [ ];
        trustedCasks = { };
        brews = [ ];
        casks = [ ];
        mas = { };
      };
    };
    testAppsTrustedCasksHostWins = {
      expr =
        (mergeAppConfig
          {
            trustedCasks = {
              a = true;
              b = true;
            };
          }
          {
            trustedCasks = {
              b = false;
              c = true;
            };
          }
        ).trustedCasks;
      expected = {
        a = true;
        b = false;
        c = true;
      };
    };
    testAppsMasHostWins = {
      expr =
        (mergeAppConfig
          {
            mas = {
              X = 1;
              Y = 2;
            };
          }
          {
            mas = {
              Y = 3;
            };
          }
        ).mas;
      expected = {
        X = 1;
        Y = 3;
      };
    };

    # ---- mergeFontConfig ----
    testFontsUnionDedupe = {
      expr =
        let
          m =
            mergeFontConfig
              {
                pkgs = [ "p" ];
                nerd = [ "n" ];
                google = [ "g" ];
                casks = [ "c" ];
              }
              {
                pkgs = [
                  "p"
                  "p2"
                ];
                nerd = [ "n2" ];
                google = [ "g" ];
                casks = [ "c2" ];
              };
        in
        m;
      expected = {
        pkgs = [
          "p"
          "p2"
        ];
        nerd = [
          "n"
          "n2"
        ];
        google = [ "g" ];
        casks = [
          "c"
          "c2"
        ];
      };
    };
    testFontsEmptyDefaults = {
      expr = mergeFontConfig { } { };
      expected = {
        pkgs = [ ];
        nerd = [ ];
        google = [ ];
        casks = [ ];
      };
    };

    # ---- mergeFirefoxConfig ----
    testFirefoxSettingsPerKeyOverride = {
      expr =
        (mergeFirefoxConfig
          {
            settings = {
              a = 1;
              b = 2;
            };
          }
          {
            settings = {
              b = 20;
              c = 3;
            };
          }
        ).settings;
      expected = {
        a = 1;
        b = 20;
        c = 3;
      };
    };
    testFirefoxExtensionsAdditiveDedupe = {
      expr =
        (mergeFirefoxConfig
          {
            extensions = {
              nix = [
                "a"
                "b"
              ];
              manual = [ { url = "https://x"; } ];
            };
          }
          {
            extensions = {
              nix = [
                "b"
                "c"
              ];
              manual = [
                { url = "https://x"; }
                { url = "https://y"; }
              ];
            };
          }
        ).extensions;
      expected = {
        nix = [
          "a"
          "b"
          "c"
        ];
        manual = [
          { url = "https://x"; }
          { url = "https://y"; }
        ];
      };
    };
    testFirefoxProfileNameHostWins = {
      expr = (mergeFirefoxConfig { profileName = "b"; } { profileName = "h"; }).profileName;
      expected = "h";
    };
    testFirefoxProfileNameBaseFallback = {
      expr = (mergeFirefoxConfig { profileName = "b"; } { }).profileName;
      expected = "b";
    };
    testFirefoxProfileNameDefault = {
      expr = (mergeFirefoxConfig { } { }).profileName;
      expected = "default";
    };
    testFirefoxEnableAbsent = {
      expr = (mergeFirefoxConfig { } { }) ? enable;
      expected = false;
    };
    testFirefoxEnableBaseOnly = {
      expr = (mergeFirefoxConfig { enable = true; } { }).enable;
      expected = true;
    };
    testFirefoxEnableHostOverridesBase = {
      expr = (mergeFirefoxConfig { enable = true; } { enable = false; }).enable;
      expected = false;
    };
    testFirefoxEnableHostOnlyFalsePresent = {
      expr = (mergeFirefoxConfig { } { enable = false; }) ? enable;
      expected = true;
    };

    # ---- mergeAndroidConfig ----
    testAndroidDefaults = {
      expr = mergeAndroidConfig { } { };
      expected = {
        enable = false;
        avdHome = null;
        guiSdkSymlink = true;
        avdDefaultSymlink = true;
        jdkPackage = "jdk";
        platformVersions = [
          "34"
          "35"
        ];
        systemImageTypes = [ "google_apis_playstore" ];
        abiVersions = [ "arm64-v8a" ];
      };
    };
    testAndroidHostListReplacesBase = {
      expr =
        (mergeAndroidConfig {
          platformVersions = [
            "33"
            "34"
          ];
        } { platformVersions = [ "35" ]; }).platformVersions;
      expected = [ "35" ];
    };
    testAndroidHostEmptyListReplacesBase = {
      expr =
        (mergeAndroidConfig { platformVersions = [ "33" ]; } { platformVersions = [ ]; }).platformVersions;
      expected = [ ];
    };
    testAndroidBaseListKeptWhenHostUnset = {
      expr = (mergeAndroidConfig { abiVersions = [ "x86_64" ]; } { }).abiVersions;
      expected = [ "x86_64" ];
    };
    testAndroidHostEnable = {
      expr = (mergeAndroidConfig { } { enable = true; }).enable;
      expected = true;
    };
    testAndroidBaseEnableThrows = {
      expr = throws (mergeAndroidConfig { enable = true; } { });
      expected = true;
    };
    testAndroidBaseEnableFalseThrows = {
      expr = throws (mergeAndroidConfig { enable = false; } { enable = true; });
      expected = true;
    };

    # ---- resolveHostConfig ----
    testHostLaptopPreset = {
      expr =
        let
          r = resolveHostConfig "h" rawLaptop;
        in
        {
          inherit (r) knownNetworkServices restartAfterPowerFailure;
        };
      expected = {
        knownNetworkServices = [
          "Wi-Fi"
          "Thunderbolt Bridge"
        ];
        restartAfterPowerFailure = false;
      };
    };
    testHostMacminiPreset = {
      expr =
        let
          r = resolveHostConfig "h" rawMini;
        in
        {
          inherit (r) knownNetworkServices restartAfterPowerFailure;
        };
      expected = {
        knownNetworkServices = [
          "Wi-Fi"
          "USB 10/100/1000 LAN"
          "Thunderbolt Ethernet Slot 1"
          "Thunderbolt Bridge"
        ];
        restartAfterPowerFailure = true;
      };
    };
    testHostOverridesKnownNetworkServices = {
      expr =
        (resolveHostConfig "h" (rawLaptop // { knownNetworkServices = [ "Eth" ]; })).knownNetworkServices;
      expected = [ "Eth" ];
    };
    testHostOverridesRestartAfterPowerFailure = {
      expr =
        (resolveHostConfig "h" (rawLaptop // { restartAfterPowerFailure = true; }))
        .restartAfterPowerFailure;
      expected = true;
    };
    testHostOverridesRestartFalseOnMacmini = {
      expr =
        (resolveHostConfig "h" (rawMini // { restartAfterPowerFailure = false; })).restartAfterPowerFailure;
      expected = false;
    };
    testHostAutoUpdatesDefaultTrue = {
      expr = (resolveHostConfig "h" rawLaptop).automaticallyInstallMacOSUpdates;
      expected = true;
    };
    testHostAutoUpdatesOverrideFalse = {
      expr =
        (resolveHostConfig "h" (rawLaptop // { automaticallyInstallMacOSUpdates = false; }))
        .automaticallyInstallMacOSUpdates;
      expected = false;
    };
    testHostClaudeKitDefaultFalse = {
      expr = (resolveHostConfig "h" rawLaptop).claudeKit;
      expected = false;
    };
    testHostClaudeKitHonorsTrue = {
      expr = (resolveHostConfig "h" (rawLaptop // { claudeKit = true; })).claudeKit;
      expected = true;
    };
    testHostExtraSessionPathsDefault = {
      expr = (resolveHostConfig "h" rawLaptop).extraSessionPaths;
      expected = [ ];
    };
    testHostExtraSessionPathsHonored = {
      expr = (resolveHostConfig "h" (rawLaptop // { extraSessionPaths = [ "/x" ]; })).extraSessionPaths;
      expected = [ "/x" ];
    };
    testHostPreservesRawKeys = {
      expr = (resolveHostConfig "h" (rawLaptop // { hostName = "foo"; })).hostName;
      expected = "foo";
    };
    testHostBadMachineTypeThrows = {
      expr = throws (resolveHostConfig "h" { machineType = "desktop"; });
      expected = true;
    };
    testHostMissingMachineTypeThrows = {
      expr = throws (resolveHostConfig "h" { });
      expected = true;
    };

    # ---- checkHostsManifest ----
    testManifestAcceptsWithoutDefaultHost = {
      expr = checkHostsManifest {
        hosts = [
          "a"
          "b"
        ];
      };
      expected = {
        hosts = [
          "a"
          "b"
        ];
      };
    };
    testManifestAcceptsWithDefaultHost = {
      expr = checkHostsManifest {
        hosts = [
          "a"
          "b"
        ];
        defaultHost = "b";
      };
      expected = {
        hosts = [
          "a"
          "b"
        ];
        defaultHost = "b";
      };
    };
    testManifestEmptyHostsThrows = {
      expr = throws (checkHostsManifest {
        hosts = [ ];
      });
      expected = true;
    };
    testManifestMissingHostsThrows = {
      expr = throws (checkHostsManifest {
        defaultHost = "a";
      });
      expected = true;
    };
    testManifestNonListHostsThrows = {
      expr = throws (checkHostsManifest {
        hosts = "a";
      });
      expected = true;
    };
    testManifestDefaultHostNotInHostsThrows = {
      expr = throws (checkHostsManifest {
        hosts = [ "a" ];
        defaultHost = "z";
      });
      expected = true;
    };
    testManifestNonStringDefaultHostThrows = {
      expr = throws (checkHostsManifest {
        hosts = [ "a" ];
        defaultHost = [ "a" ];
      });
      expected = true;
    };
    testManifestNullDefaultHostThrows = {
      expr = throws (checkHostsManifest {
        hosts = [ "a" ];
        defaultHost = null;
      });
      expected = true;
    };

    # ---- schema <-> loader drift: every documented knob must reach the loader output ----
    testDriftApps = {
      expr = missingFrom "apps" (mergeAppConfig fullApps.base fullApps.host);
      expected = [ ];
    };
    testDriftFonts = {
      expr = missingFrom "fonts" (mergeFontConfig fullFonts.base fullFonts.host);
      expected = [ ];
    };
    testDriftFirefox = {
      expr = missingFrom "firefox" (mergeFirefoxConfig fullFirefox.base fullFirefox.host);
      expected = [ ];
    };
    testDriftAndroid = {
      expr = missingFrom "android" (mergeAndroidConfig fullAndroid.base fullAndroid.host);
      expected = [ ];
    };
    # Required-only raw host: optional knobs must get loader defaults.
    testDriftHost = {
      expr = missingFrom "host" (resolveHostConfig "h" requiredOnlyRaw);
      expected = [ ];
    };
  };
in
{
  inherit tests;
  results = lib.runTests tests;
  count = builtins.length (builtins.attrNames tests);
}
