final: prev:

let
  inherit (prev) lib;
  buildGoogleFont = prev.callPackage ./build-font.nix { };

  # Pinned google/fonts commit; bump rev and per-font hashes when updating.
  rev = "c89741abbf4eeabce432c3ed2fd7dc28b022701e";

  fontDefs = {
    fira = {
      path = "ofl/firasans";
      hash = "sha256-2lGJ6OcOn25vLwpk4zQRqiOPVqAfu+UoR79I3QwFB20=";
      description = "Fira Sans typeface";
      homepage = "https://fonts.google.com/specimen/Fira+Sans";
    };
    fira-mono = {
      path = "ofl/firamono";
      hash = "sha256-c2AYHWfJThi90khi1NUdUlTWstitVGRJzmzM8ba8U/8=";
      description = "Fira Mono monospaced typeface";
      homepage = "https://fonts.google.com/specimen/Fira+Mono";
    };
    ibm-plex = {
      path = "ofl/ibmplexsans";
      hash = "sha256-j+PQxJozeR4heHiwIqCIw849a2kDLQ94aNO0fs1mXf0=";
      description = "IBM Plex Sans typeface";
      homepage = "https://fonts.google.com/specimen/IBM+Plex+Sans";
    };
    inter = {
      path = "ofl/inter";
      hash = "sha256-nJ35zZWRbOTcE3OWqOOTqJKY0JT4x5msm4a7O//9IP8=";
      description = "A typeface carefully crafted for computer screens";
      homepage = "https://rsms.me/inter/";
    };
    lato = {
      path = "ofl/lato";
      hash = "sha256-Y5Xpqe5ucvtDf8SYOHbnsqHGDsC9rYxLi4j9Fmf0Hpw=";
      description = "Lato sans serif typeface";
      homepage = "https://fonts.google.com/specimen/Lato";
    };
    manrope = {
      path = "ofl/manrope";
      hash = "sha256-Y9E3Otn4RIyHjGIZ0iqjmGKgL3oi1431XVg1Y7xZNAk=";
      description = "Modern geometric sans serif typeface";
      homepage = "https://fonts.google.com/specimen/Manrope";
    };
    open-sans = {
      path = "ofl/opensans";
      hash = "sha256-48y4NC0G1a5guDepQixN6jVq80KVrtC781fDPU6wZUQ=";
      description = "Open Sans typeface";
      homepage = "https://fonts.google.com/specimen/Open+Sans";
    };
    poppins = {
      path = "ofl/poppins";
      hash = "sha256-T6FTWywEmEK4botvSzcA4hzQHRtOL8MvyIZBHcTljLU=";
      description = "Poppins geometric sans serif typeface";
      homepage = "https://fonts.google.com/specimen/Poppins";
    };
  };

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
