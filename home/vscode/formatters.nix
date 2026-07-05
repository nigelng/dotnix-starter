# Default formatters and on-save behavior for Prettier, ESLint, and EditorConfig.
{ lib }:
let
  prettierExt = "esbenp.prettier-vscode";

  mkPrettierLang = lang: {
    "[${lang}]" = {
      editor.defaultFormatter = prettierExt;
      editor.formatOnSave = true;
    };
  };

  # https://prettier.io/docs/en/index.html — languages Prettier formats
  prettierLanguages = [
    "css"
    "graphql"
    "html"
    "javascript"
    "javascriptreact"
    "json"
    "jsonc"
    "less"
    "markdown"
    "scss"
    "typescript"
    "typescriptreact"
    "vue"
    "yaml"
  ];

  prettierLangSettings = lib.foldl' lib.recursiveUpdate { } (map mkPrettierLang prettierLanguages);

in
{
  inherit prettierLangSettings;

  # Prettier formats; ESLint fixes lint issues on save (not "explicit").
  eslintSettings = {
    editor.codeActionsOnSave = {
      "source.fixAll.eslint" = "always";
    };
    eslint.format.enable = false;
  };

  # Indent/eol/charset from ~/.editorconfig on file open; Prettier reads it via useEditorConfig.
  editorconfigSettings = {
    editorconfig.autoSave = "off";
  };
}
