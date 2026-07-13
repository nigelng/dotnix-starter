# Shared helpers for loading JSON config and resolving hosts.
{ lib }:

let
  loadJson = path: builtins.fromJSON (builtins.readFile path);

  loadSharedConfig = root: {
    gitConfig = loadJson "${root}/config/git.json";
  };

  loadRawHostConfig = root: hostName: loadJson "${root}/config/hosts/${hostName}.json";

  loadUserConfig =
    root: hostName:
    let
      userPath = "${root}/config/user.json";
      examplePath = "${root}/config/user.json.example";
      profile =
        if builtins.pathExists userPath then
          loadJson userPath
        else if builtins.pathExists examplePath then
          builtins.trace "loadUserConfig: ${userPath} not found — using placeholder values from ${examplePath}." (
            loadJson examplePath
          )
        else
          builtins.throw ''
            loadUserConfig: neither ${userPath} nor ${examplePath} found.
            Copy config/user.json.example to config/user.json and edit with your details.
          '';
      host = loadRawHostConfig root hostName;
    in
    if host ? adminUsername then
      profile // { user = host.adminUsername; }
    else
      builtins.throw ''
        loadUserConfig: config/hosts/${hostName}.json must set "adminUsername" (macOS admin username).
      '';

  listAttr = attrs: name: if attrs ? ${name} then attrs.${name} else [ ];

  objAttr = attrs: name: if attrs ? ${name} then attrs.${name} else { };

  mergeLists =
    base: host: name:
    lib.unique (listAttr base name ++ listAttr host name);

  loadAppConfig =
    root: hostName:
    let
      hostPath = "${root}/config/apps/hosts/${hostName}.json";
      base = loadJson "${root}/config/apps/base.json";
      host =
        if builtins.pathExists hostPath then
          loadJson hostPath
        else
          builtins.throw ''
            loadAppConfig: missing ${hostPath}
            Add config/apps/hosts/${hostName}.json for each entry in config/hosts.json (use {} if there are no host-only apps).
          '';
    in
    {
      system = mergeLists base host "system";
      user = mergeLists base host "user";
      taps = mergeLists base host "taps";
      trustedCasks = objAttr base "trustedCasks" // objAttr host "trustedCasks";
      brews = mergeLists base host "brews";
      casks = mergeLists base host "casks";
      mas = objAttr base "mas" // objAttr host "mas";
    };

  hostPresets = import ./host-presets.nix { inherit lib; };

  loadHostConfig =
    root: hostName:
    let
      raw = loadRawHostConfig root hostName;
    in
    if !(raw ? machineType) then
      builtins.throw ''
        loadHostConfig: config/hosts/${hostName}.json must set "machineType" ("laptop" or "macmini").
      ''
    else if !(raw.machineType == "laptop" || raw.machineType == "macmini") then
      builtins.throw ''
        loadHostConfig: config/hosts/${hostName}.json machineType must be "laptop" or "macmini", got "${raw.machineType}".
      ''
    else
      let
        preset = hostPresets.${raw.machineType};
      in
      raw
      // {
        extraSessionPaths = listAttr raw "extraSessionPaths";
        knownNetworkServices =
          if raw ? knownNetworkServices then raw.knownNetworkServices else preset.knownNetworkServices;
        restartAfterPowerFailure = preset.restartAfterPowerFailure;
      };

  loadFontConfig =
    root: hostName:
    let
      hostPath = "${root}/config/fonts/hosts/${hostName}.json";
      base = loadJson "${root}/config/fonts/base.json";
      host =
        if builtins.pathExists hostPath then
          loadJson hostPath
        else
          builtins.throw ''
            loadFontConfig: missing ${hostPath}
            Add config/fonts/hosts/${hostName}.json for each entry in config/hosts.json (use {} if there are no host-only fonts).
          '';
    in
    {
      casks = mergeLists base host "casks";
      google = mergeLists base host "google";
      nerd = mergeLists base host "nerd";
      pkgs = mergeLists base host "pkgs";
    };

  # Merge a base settings attrset with a host settings attrset (host wins per-key).
  mergeSettings =
    base: host:
    let
      baseSettings = objAttr base "settings";
      hostSettings = objAttr host "settings";
    in
    baseSettings // hostSettings;

  # Merge extensions: nix slugs and manual entries are additive (deduplicated).
  mergeExtensions =
    base: host:
    let
      baseExt = objAttr base "extensions";
      hostExt = objAttr host "extensions";
    in
    {
      nix = mergeLists baseExt hostExt "nix";
      manual = mergeLists baseExt hostExt "manual";
    };

  loadFirefoxConfig =
    root: hostName:
    let
      basePath = "${root}/config/firefox/base.json";
    in
    if !builtins.pathExists basePath then
      # Overlay repos without Firefox get a no-op config.
      # home/firefox.nix accepts firefoxConfig ? { } and my.firefox.enable
      # defaults to false in overlays, so Firefox won't activate.
      {
        package = "firefox-bin";
        profileName = "default";
        settings = { };
        extensions = {
          nix = [ ];
          manual = [ ];
        };
      }
    else
      let
        hostPath = "${root}/config/firefox/hosts/${hostName}.json";
        base = loadJson basePath;
        host =
          if builtins.pathExists hostPath then
            loadJson hostPath
          else
            builtins.throw ''
              loadFirefoxConfig: missing ${hostPath}
              Add config/firefox/hosts/${hostName}.json for each entry in config/hosts.json (use {} if there are no host-only Firefox overrides).
            '';
        # Host package/profileName override base if present.
        package = if host ? package then host.package else base.package or "firefox-bin";
        profileName = if host ? profileName then host.profileName else base.profileName or "default";
      in
      {
        inherit package profileName;
        settings = mergeSettings base host;
        extensions = mergeExtensions base host;
      };

  loadAndroidConfig =
    root: hostName:
    let
      basePath = "${root}/config/android/base.json";
    in
    if !builtins.pathExists basePath then
      # Overlay repos without Android get a no-op config.
      # home/android.nix applies module defaults for avdHome etc.
      {
        enable = false;
      }
    else
      let
        hostPath = "${root}/config/android/hosts/${hostName}.json";
        base = loadJson basePath;
      in
      if base ? enable then
        builtins.throw ''
          loadAndroidConfig: config/android/base.json must not contain "enable" (use hosts/<host>.json instead).
        ''
      else
        let
          host =
            if builtins.pathExists hostPath then
              loadJson hostPath
            else
              builtins.throw ''
                loadAndroidConfig: missing ${hostPath}
                Add config/android/hosts/${hostName}.json for each entry in config/hosts.json (use { "enable": false } if Android is off for this host).
              '';
          merged = base // host;
        in
        {
          enable = merged.enable or false;
          avdHome = merged.avdHome or null;
          guiSdkSymlink = merged.guiSdkSymlink or true;
          avdDefaultSymlink = merged.avdDefaultSymlink or true;
          jdkPackage = merged.jdkPackage or "jdk";
        };

  loadHostsManifest = root: loadJson "${root}/config/hosts.json";

in
{
  inherit
    loadJson
    loadRawHostConfig
    loadSharedConfig
    loadUserConfig
    loadAppConfig
    loadHostConfig
    loadFontConfig
    loadFirefoxConfig
    loadAndroidConfig
    loadHostsManifest
    ;
}
