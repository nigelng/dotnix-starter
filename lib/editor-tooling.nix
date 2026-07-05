# Build ~/.config/editor-tooling/node_modules from flake-pinned config repos.
# Pinned revisions: flake.lock → inputs.prettier-config / inputs.eslint-config.
# After bumping those inputs, regenerate lib/editor-tooling-package-lock.json
# (npm install --package-lock-only with file: deps at the locked source paths).
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
    cat > $out/package.json <<'EOF'
    {
      "name": "nigelng-editor-tooling",
      "version": "1.0.0",
      "private": true,
      "dependencies": {
        "@nigelng/prettier-config": "file:prettier-config",
        "@nigelng/eslint-config": "file:eslint-config",
        "eslint": "10.6.0",
        "prettier": "3.9.4"
      }
    }
    EOF
    cp ${../lib/editor-tooling-package-lock.json} $out/package-lock.json
  '';

  editorTooling = pkgs.buildNpmPackage {
    pname = "nigelng-editor-tooling";
    version = "1.0.0";
    src = toolingSrc;
    npmDepsHash = "sha256-FkLEBwmtuxYBpa+v524yXhr7h9x1NjzxOlsjZzuyQ7g=";
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
