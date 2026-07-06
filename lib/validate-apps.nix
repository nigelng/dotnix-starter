# Fail flake check when app/font config references unknown nixpkgs attributes.
{
  lib,
  pkgs,
  hosts,
  loadAppConfig,
  loadFontConfig,
  loadFirefoxConfig ? null,
}:
let
  missingPkgs = names: lib.filter (n: (pkgs.${n} or null) == null) names;

  missingNerdFonts = names: lib.filter (n: (pkgs.nerd-fonts.${n} or null) == null) names;

  missingGoogleFonts = names: lib.filter (n: (pkgs.${"google-fonts-" + n} or null) == null) names;

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
        ++ validateFirefoxPackage hostName;
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
