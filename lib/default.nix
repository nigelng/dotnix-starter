# Shared helpers for loading JSON config and resolving hosts.
{ lib }:

let
  loadJson = path: builtins.fromJSON (builtins.readFile path);

  loadSharedConfig = root: {
    gitConfig = loadJson "${root}/config/git.json";
  };

  loadRawHostConfig = root: hostName: loadJson "${root}/config/hosts/${hostName}.json";

  # loadUserConfig root { allowExample ? false } hostName
  # Overlays must pass {} (fail closed). The starter passes allowExample = true for CI.
  loadUserConfig =
    root:
    {
      allowExample ? false,
    }:
    hostName:
    let
      userPath = "${root}/config/user.json";
      examplePath = "${root}/config/user.json.example";
      profile =
        if builtins.pathExists userPath then
          loadJson userPath
        else if allowExample && builtins.pathExists examplePath then
          builtins.trace "loadUserConfig: ${userPath} not found — using placeholder values from ${examplePath}." (
            loadJson examplePath
          )
        else
          builtins.throw ''
            loadUserConfig: ${userPath} not found.
            Flakes only see git-tracked files (self.outPath). Copy config/user.json.example
            to config/user.json, edit your identity fields, then git add config/user.json.
            Do not gitignore it — that silently excluded the file from eval.
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

  # Pure merge: lists are unioned (deduplicated), maps are host-wins per key.
  mergeAppConfig = base: host: {
    system = mergeLists base host "system";
    user = mergeLists base host "user";
    taps = mergeLists base host "taps";
    trustedCasks = objAttr base "trustedCasks" // objAttr host "trustedCasks";
    brews = mergeLists base host "brews";
    casks = mergeLists base host "casks";
    mas = objAttr base "mas" // objAttr host "mas";
  };

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
    mergeAppConfig base host;

  hostPresets = import ./host-presets.nix { inherit lib; };

  # Pure: validate machineType and fill preset defaults for one raw host attrset.
  resolveHostConfig =
    hostName: raw:
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
        # Host JSON can override the machineType preset.
        restartAfterPowerFailure =
          if raw ? restartAfterPowerFailure then
            raw.restartAfterPowerFailure
          else
            preset.restartAfterPowerFailure;
        # Defaults to true for compatibility; set false before major macOS betas
        # until nix-darwin supports the new OS (see docs/MACOS-27.md).
        automaticallyInstallMacOSUpdates =
          if raw ? automaticallyInstallMacOSUpdates then raw.automaticallyInstallMacOSUpdates else true;
        claudeKit = raw.claudeKit or false;
      };

  loadHostConfig = root: hostName: resolveHostConfig hostName (loadRawHostConfig root hostName);

  mergeFontConfig = base: host: {
    casks = mergeLists base host "casks";
    google = mergeLists base host "google";
    nerd = mergeLists base host "nerd";
    pkgs = mergeLists base host "pkgs";
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
    mergeFontConfig base host;

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

  # Pure merge. `enable` (host wins over base) is emitted only when either side
  # sets it, so downstream can tell "unset" from false via `firefoxConfig ? enable`.
  mergeFirefoxConfig =
    base: host:
    {
      # Host profileName overrides base if present.
      profileName = host.profileName or base.profileName or "default";
      settings = mergeSettings base host;
      extensions = mergeExtensions base host;
    }
    // lib.optionalAttrs (base ? enable || host ? enable) {
      enable = host.enable or base.enable;
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
      in
      mergeFirefoxConfig base host;

  # Pure merge. Throws if base sets "enable" (it is per-host only); checked
  # before `host` is forced so a bad base fails first.
  mergeAndroidConfig =
    base: host:
    if base ? enable then
      builtins.throw ''
        loadAndroidConfig: config/android/base.json must not contain "enable" (use hosts/<host>.json instead).
      ''
    else
      let
        merged = base // host;
      in
      {
        enable = merged.enable or false;
        avdHome = merged.avdHome or null;
        guiSdkSymlink = merged.guiSdkSymlink or true;
        avdDefaultSymlink = merged.avdDefaultSymlink or true;
        jdkPackage = merged.jdkPackage or "jdk";
        platformVersions =
          merged.platformVersions or [
            "34"
            "35"
          ];
        systemImageTypes = merged.systemImageTypes or [ "google_apis_playstore" ];
        abiVersions = merged.abiVersions or [ "arm64-v8a" ];
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
        host =
          if builtins.pathExists hostPath then
            loadJson hostPath
          else
            builtins.throw ''
              loadAndroidConfig: missing ${hostPath}
              Add config/android/hosts/${hostName}.json for each entry in config/hosts.json (use { "enable": false } if Android is off for this host).
            '';
      in
      mergeAndroidConfig base host;

  # Pure: hosts must be a non-empty list and defaultHost (when set) one of them.
  checkHostsManifest =
    manifest:
    let
      hosts = manifest.hosts or null;
    in
    if !(builtins.isList hosts) || hosts == [ ] then
      builtins.throw ''
        checkHostsManifest: config/hosts.json must set "hosts" to a non-empty list of host names.
      ''
    else if manifest ? defaultHost && !(builtins.isString manifest.defaultHost) then
      builtins.throw ''
        checkHostsManifest: config/hosts.json defaultHost must be a string (a host name from "hosts"), got ${builtins.typeOf manifest.defaultHost}.
      ''
    else if manifest ? defaultHost && !(builtins.elem manifest.defaultHost hosts) then
      builtins.throw ''
        checkHostsManifest: config/hosts.json defaultHost "${toString manifest.defaultHost}" must be one of hosts: ${builtins.concatStringsSep ", " (map toString hosts)}.
      ''
    else
      manifest;

  loadHostsManifest = root: checkHostsManifest (loadJson "${root}/config/hosts.json");

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
    mergeAppConfig
    mergeFontConfig
    mergeFirefoxConfig
    mergeAndroidConfig
    resolveHostConfig
    checkHostsManifest
    ;
}
