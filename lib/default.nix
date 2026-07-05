# Shared helpers for loading JSON config and resolving hosts.
{ lib }:

let
  loadJson = path: builtins.fromJSON (builtins.readFile path);

  loadSharedConfig = root: {
    gitConfig = loadJson "${root}/config/git.json";
  };

  loadUserConfig =
    root: hostName:
    let
      userPath = "${root}/config/user.json";
      profile =
        if builtins.pathExists userPath then
          loadJson userPath
        else
          builtins.throw ''
            loadUserConfig: ${userPath} not found.
            Copy config/user.json.example to config/user.json and edit with your details.
          '';
      host = loadHostConfig root hostName;
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
      raw = loadJson "${root}/config/hosts/${hostName}.json";
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

  loadHostsManifest = root: loadJson "${root}/config/hosts.json";

in
{
  inherit
    loadJson
    loadSharedConfig
    loadUserConfig
    loadAppConfig
    loadHostConfig
    loadFontConfig
    loadHostsManifest
    ;
}
