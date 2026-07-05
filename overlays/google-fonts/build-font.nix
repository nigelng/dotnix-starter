{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

{
  name,
  path,
  rev,
  hash,
  version ? rev,
  description,
  homepage ? "https://fonts.google.com/specimen/${
    lib.strings.toUpper (lib.strings.substring 0 1 name)
  }${lib.strings.substring 1 (-1) name}",
}:

stdenvNoCC.mkDerivation {
  pname = "google-fonts-${name}";
  inherit version;

  src = fetchFromGitHub {
    owner = "google";
    repo = "fonts";
    inherit rev hash;
    sparseCheckout = [ path ];
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype
    cp ${path}/*.ttf $out/share/fonts/truetype/ 2>/dev/null || true
    cp ${path}/*.otf $out/share/fonts/opentype/ 2>/dev/null || true

    if [ -z "$(ls -A $out/share/fonts/truetype 2>/dev/null)" ] \
      && [ -z "$(ls -A $out/share/fonts/opentype 2>/dev/null)" ]; then
      echo "No font files found in ${path}" >&2
      exit 1
    fi

    runHook postInstall
  '';

  meta = {
    inherit description homepage;
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
