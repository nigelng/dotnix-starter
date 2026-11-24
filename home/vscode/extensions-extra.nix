# Marketplace extensions not (yet) packaged under pkgs.vscode-extensions.
# Pins live in extensions-extra.json; bump them with scripts/update-pins.sh.
{ pkgs }:
let
  inherit (pkgs) lib;
  inherit (pkgs.vscode-utils) buildVscodeMarketplaceExtension;

  mkExt =
    {
      publisher,
      name,
      version,
      hash,
      license ? "mit",
    }:
    buildVscodeMarketplaceExtension {
      mktplcRef = {
        inherit
          publisher
          name
          version
          hash
          ;
      };
      meta.license = lib.licenses.${license};
    };

  # Rebuild the `<publisher>.<name>` attrset consumed by extensions.nix.
  mkExtAttr = acc: pin: lib.recursiveUpdate acc { ${pin.publisher}.${pin.name} = mkExt pin; };
in
lib.foldl' mkExtAttr { } (lib.importJSON ./extensions-extra.json)
