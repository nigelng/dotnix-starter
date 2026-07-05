# Editor tooling wiring (Prettier + ESLint from flake-pinned config repos).
#
# This flake always provides editorTooling (the prettier-config and eslint-config
# inputs point at github:nigelng/prettier-config and github:nigelng/eslint-config).
# Overlay repos that don't want editor tooling can omit the inputs — home/default.nix
# skips this import via lib.optional (editorTooling != {}).
#
# The editorTooling attrset is passed via home-manager extraSpecialArgs
# from darwin/default.nix. It must contain:
#   - editorTooling: the buildNpmPackage derivation
#   - nodeModules: path to the built node_modules
#   - eslintWrapper: pkgs.writeShellScriptBin "eslint" wrapper
#   - prettierWrapper: pkgs.writeShellScriptBin "prettier" wrapper
{
  config,
  editorTooling,
  ...
}:
let
  inherit (editorTooling) nodeModules eslintWrapper prettierWrapper;
  toolingHome = "${config.home.homeDirectory}/.config/editor-tooling";
in
{
  # ~/.editorconfig — used by EditorConfig-aware editors and Prettier (useEditorConfig).
  home.file.".editorconfig".source = ./config_files/editorconfig;

  # @nigelng/prettier-config + @nigelng/eslint-config (flake inputs).
  home.file.".config/editor-tooling/.prettierrc.json".source =
    ./config_files/editor-tooling/.prettierrc.json;
  home.file.".config/editor-tooling/eslint.config.js".source =
    ./config_files/editor-tooling/eslint.config.js;
  # Store path is symlinked (not copied) to keep activation fast.
  home.file.".config/editor-tooling/node_modules".source = nodeModules;

  home.packages = [
    editorTooling.editorTooling
    eslintWrapper
    prettierWrapper
  ];

  home.sessionVariables = {
    PRETTIER_CONFIG_PATH = "${toolingHome}/.prettierrc.json";
    ESLINT_USE_FLAT_CONFIG = "true";
  };
}
