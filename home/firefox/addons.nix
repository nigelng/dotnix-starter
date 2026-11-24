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

  # Curated AMO add-on catalog keyed by slug, loaded from addons-pins.json.
  # Bump URLs and hashes with scripts/update-pins.sh (queries the AMO API).
  # Policy install uses `url` as ExtensionSettings install_url (pinned file URL).
  catalog = lib.importJSON ./addons-pins.json;

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
