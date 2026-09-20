# Fail flake check when app/font config references unknown nixpkgs attributes
# or Firefox extension slugs missing from the curated catalog.
{
  lib,
  pkgs,
  hosts,
  loadAppConfig,
  loadFontConfig,
  loadFirefoxConfig ? null,
  loadAndroidConfig ? null,
}:
let
  missingPkgs = names: lib.filter (n: (pkgs.${n} or null) == null) names;

  missingNerdFonts = names: lib.filter (n: (pkgs.nerd-fonts.${n} or null) == null) names;

  missingGoogleFonts = names: lib.filter (n: (pkgs.${"google-fonts-" + n} or null) == null) names;

  firefoxAddons =
    if loadFirefoxConfig == null then null else import ../home/firefox/addons.nix { inherit pkgs lib; };

  validateFirefoxPackage =
    hostName:
    if loadFirefoxConfig == null then
      [ ]
    else
      let
        firefoxConfig = loadFirefoxConfig hostName;
      in
      lib.optional ((pkgs.${firefoxConfig.package} or null) == null) ''
        ${hostName}: unknown Firefox package: ${firefoxConfig.package}
      '';

  validateFirefoxExtensions =
    hostName:
    if loadFirefoxConfig == null || firefoxAddons == null then
      [ ]
    else
      let
        firefoxConfig = loadFirefoxConfig hostName;
        slugs = firefoxConfig.extensions.nix or [ ];
        unknown = lib.filter (s: !(firefoxAddons.catalog ? ${s})) slugs;
      in
      lib.optional (unknown != [ ]) ''
        ${hostName}: unknown Firefox extension slugs: ${lib.concatStringsSep ", " unknown}
        Valid slugs: ${lib.concatStringsSep ", " (builtins.attrNames firefoxAddons.catalog)}
      '';

  validateAndroidJdk =
    hostName:
    if loadAndroidConfig == null then
      [ ]
    else
      let
        androidConfig = loadAndroidConfig hostName;
        jdkPackage = androidConfig.jdkPackage or "jdk";
      in
      if !(androidConfig.enable or false) then
        [ ]
      else
        lib.optional ((pkgs.${jdkPackage} or null) == null) ''
          ${hostName}: unknown Android JDK package: ${jdkPackage}
        '';

  validateHost =
    hostName:
    let
      appConfig = loadAppConfig hostName;
      fontConfig = loadFontConfig hostName;
      errors =
        lib.optional (missingPkgs appConfig.system != [ ]) ''
          ${hostName}: unknown system packages: ${lib.concatStringsSep ", " (missingPkgs appConfig.system)}
        ''
        ++ lib.optional (missingPkgs appConfig.user != [ ]) ''
          ${hostName}: unknown user packages: ${lib.concatStringsSep ", " (missingPkgs appConfig.user)}
        ''
        ++ lib.optional (missingPkgs fontConfig.pkgs != [ ]) ''
          ${hostName}: unknown font pkgs: ${lib.concatStringsSep ", " (missingPkgs fontConfig.pkgs)}
        ''
        ++ lib.optional (missingNerdFonts fontConfig.nerd != [ ]) ''
          ${hostName}: unknown nerd fonts: ${lib.concatStringsSep ", " (missingNerdFonts fontConfig.nerd)}
        ''
        ++ lib.optional (missingGoogleFonts fontConfig.google != [ ]) ''
          ${hostName}: unknown google fonts: ${lib.concatStringsSep ", " (missingGoogleFonts fontConfig.google)}
        ''
        ++ validateFirefoxPackage hostName
        ++ validateFirefoxExtensions hostName
        ++ validateAndroidJdk hostName;
    in
    if errors == [ ] then null else lib.concatStringsSep "\n" errors;

  allErrors = lib.filter (e: e != null) (map validateHost hosts);
in
if allErrors != [ ] then
  throw ''
    App/font config validation failed:
    ${lib.concatStringsSep "\n" allErrors}
  ''
else
  { }
