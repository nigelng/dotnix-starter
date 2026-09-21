# Curated AMO add-on catalog and helpers.
# Policy mode (default) uses metadata only — pinned install_url, no store fetch.
# Sideload escape hatch still builds fetchFirefoxAddon packages via mkAddon.
{
  pkgs,
  lib,
}:
let
  inherit (pkgs) fetchFirefoxAddon;

  # Build a fetchFirefoxAddon package (sideload escape hatch only).
  # fixedExtid sets passthru.extid to the AMO GUID for profile extensions/*.xpi.
  mkAddon =
    {
      name,
      addonId,
      url,
      hash,
    }:
    fetchFirefoxAddon {
      inherit name url hash;
      fixedExtid = addonId;
    };

  # Curated AMO add-on catalog keyed by slug.
  # Update URLs and hashes when bumping versions (query the AMO API).
  # Policy install uses `url` as ExtensionSettings install_url (pinned file URL).
  catalog = {
    darkreader = {
      name = "darkreader";
      addonId = "addon@darkreader.org";
      url = "https://addons.mozilla.org/firefox/downloads/file/4859299/darkreader-4.9.128.xpi";
      hash = "sha256-Mb5p5eeD4w3CVe41fypyM0hvgBy6BhVg8aRN65YDKW8";
    };
    "onepassword-x-password-manager" = {
      name = "onepassword-x-password-manager";
      addonId = "{d634138d-c276-4fc8-924b-40a0ea21d284}";
      url = "https://addons.mozilla.org/firefox/downloads/file/4853670/1password_x_password_manager-8.12.24.34.xpi";
      hash = "sha256-Rqs4wTzm1HJ5S9uG7h4Q7CfrZO4xdXq4ph/ni4JrO9s";
    };
    "adguard-adblocker" = {
      name = "adguard-adblocker";
      addonId = "adguardadblocker@adguard.com";
      url = "https://addons.mozilla.org/firefox/downloads/file/4805625/adguard_adblocker-5.4.3.1.xpi";
      hash = "sha256-NKAzwTSD1Pif/0RP67xMNNdCqcUR6vscfthcwBhGF+c";
    };
    "privacy-badger17" = {
      name = "privacy-badger17";
      addonId = "jid1-MnnxcxisBPnSXQ@jetpack";
      url = "https://addons.mozilla.org/firefox/downloads/file/5032646/privacy_badger17-2026.9.15.xpi";
      hash = "sha256-l82JEeNIbaNKUyp8fygGzW0M+hF6H75eh0cEKpRELWI=";
    };
  };

  lookupSlug =
    slug:
    if catalog ? ${slug} then
      catalog.${slug}
    else
      builtins.throw "Unknown Firefox add-on slug: ${slug}. Valid slugs: ${lib.concatStringsSep ", " (builtins.attrNames catalog)}";

  # Resolve slugs to catalog metadata without fetching XPIs into the Nix store.
  resolveSlugEntries = slugs: map lookupSlug slugs;

  # Map one catalog/manual entry to an ExtensionSettings attribute set.
  toExtensionSetting =
    {
      addonId,
      url,
      ...
    }:
    {
      ${addonId} = {
        installation_mode = "force_installed";
        install_url = url;
      };
    };

  # Merge entries into a single ExtensionSettings attrset.
  toExtensionSettings = entries: lib.foldl' (acc: entry: acc // toExtensionSetting entry) { } entries;
in
{
  inherit
    catalog
    mkAddon
    lookupSlug
    resolveSlugEntries
    toExtensionSetting
    toExtensionSettings
    ;
}
