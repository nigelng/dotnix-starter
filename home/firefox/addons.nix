# Maps AMO add-on slugs to fetchFirefoxAddon derivations.
# Each entry fetches the signed XPI from addons.mozilla.org at build time.
# The extension ID is set via fixedExtid so it appears in passthru.extid,
# which home.file and home-manager's extensions.packages both use.
{
  pkgs,
  lib,
}:
let
  inherit (pkgs) fetchFirefoxAddon;

  # Build a fetchFirefoxAddon package. The fixedExtid parameter sets
  # passthru.extid to the real AMO extension GUID, which home.file
  # uses to locate the XPI file in the Nix store output.
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
  };

  # Resolve a list of slugs to addon packages.
  resolveSlugs =
    slugs:
    map (
      slug:
      if catalog ? ${slug} then
        mkAddon catalog.${slug}
      else
        builtins.throw "Unknown Firefox add-on slug: ${slug}. Valid slugs: ${lib.concatStringsSep ", " (builtins.attrNames catalog)}"
    ) slugs;
in
{
  inherit catalog mkAddon resolveSlugs;
}
