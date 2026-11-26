# Build ~/.config/editor-tooling/node_modules from flake-pinned config repos.
# Pinned revisions: flake.lock → inputs.prettier-config / inputs.eslint-config.
# After bumping those inputs (or editing lib/editor-tooling-package.json), run
#   scripts/update-editor-tooling-lock.sh
# to regenerate lib/editor-tooling-package-lock.json and npmDepsHash below.
# The weekly update-flake workflow runs it automatically.
#
# This flake always provides editorTooling (the prettier-config and eslint-config
# inputs point at github:nigelng/prettier-config and github:nigelng/eslint-config).
# Overlay repos that don't want editor tooling can omit the inputs — home/default.nix
# skips the editor.nix import via lib.optional (editorTooling != {}).
{
  pkgs,
  lib,
  prettier-config,
  eslint-config,
}:
let
  toolingSrc = pkgs.runCommandLocal "nigelng-editor-tooling-src" { } ''
    mkdir -p $out/prettier-config $out/eslint-config
    cp -r ${prettier-config}/* $out/prettier-config/
    cp -r ${eslint-config}/* $out/eslint-config/
    cp ${../lib/editor-tooling-package.json} $out/package.json
    cp ${../lib/editor-tooling-package-lock.json} $out/package-lock.json
  '';

  editorTooling = pkgs.buildNpmPackage {
    pname = "nigelng-editor-tooling";
    version = "1.0.0";
    src = toolingSrc;
    npmDepsHash = "sha256-kjfePXwbn0tRhLwZYKxjR6XdAomg5pFYVmb7KxhF+wE=";
    npmDepsFetcherVersion = 2;
    npmFlags = [ "--legacy-peer-deps" ];
    dontNpmBuild = true;
  };

  nodeModules = "${editorTooling}/lib/node_modules/nigelng-editor-tooling/node_modules";

  eslintWrapper = pkgs.writeShellScriptBin "eslint" ''
    exec ${pkgs.nodejs}/bin/node ${nodeModules}/eslint/bin/eslint.js "$@"
  '';

  prettierWrapper = pkgs.writeShellScriptBin "prettier" ''
    exec ${pkgs.nodejs}/bin/node ${nodeModules}/prettier/bin/prettier.cjs "$@"
  '';
in
{
  inherit
    editorTooling
    nodeModules
    eslintWrapper
    prettierWrapper
    ;
}
