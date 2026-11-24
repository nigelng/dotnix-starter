final: prev:

let
  inherit (prev) lib;
  buildGoogleFont = prev.callPackage ./build-font.nix { };

  # Pinned google/fonts commit and per-font hashes live in pins.json;
  # bump them with scripts/update-pins.sh.
  pins = lib.importJSON ./pins.json;
  inherit (pins) rev;

  fontMeta = {
    fira = {
      description = "Fira Sans typeface";
      homepage = "https://fonts.google.com/specimen/Fira+Sans";
    };
    fira-mono = {
      description = "Fira Mono monospaced typeface";
      homepage = "https://fonts.google.com/specimen/Fira+Mono";
    };
    ibm-plex = {
      description = "IBM Plex Sans typeface";
      homepage = "https://fonts.google.com/specimen/IBM+Plex+Sans";
    };
    inter = {
      description = "A typeface carefully crafted for computer screens";
      homepage = "https://rsms.me/inter/";
    };
    lato = {
      description = "Lato sans serif typeface";
      homepage = "https://fonts.google.com/specimen/Lato";
    };
    manrope = {
      description = "Modern geometric sans serif typeface";
      homepage = "https://fonts.google.com/specimen/Manrope";
    };
    open-sans = {
      description = "Open Sans typeface";
      homepage = "https://fonts.google.com/specimen/Open+Sans";
    };
    poppins = {
      description = "Poppins geometric sans serif typeface";
      homepage = "https://fonts.google.com/specimen/Poppins";
    };
  };

  fontDefs = lib.mapAttrs (name: pin: pin // fontMeta.${name}) pins.fonts;

  mkFont =
    name: attrs:
    buildGoogleFont (
      {
        inherit name rev;
        hash = attrs.hash;
      }
      // attrs
    );

in
lib.mapAttrs' (name: attrs: {
  name = "google-fonts-${name}";
  value = mkFont name attrs;
}) fontDefs
