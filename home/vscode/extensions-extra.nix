# Marketplace extensions not (yet) packaged under pkgs.vscode-extensions.
{ pkgs }:
let
  inherit (pkgs.vscode-utils) buildVscodeMarketplaceExtension;

  mkExt =
    {
      publisher,
      name,
      version,
      hash,
      license ? pkgs.lib.licenses.mit,
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
      meta = {
        inherit license;
      };
    };
in
{
  tomoyukim.vscode-mermaid-editor = mkExt {
    publisher = "tomoyukim";
    name = "vscode-mermaid-editor";
    version = "0.19.1";
    hash = "sha256-MZkR9wPTj+TwhQP0kbH4XqlTvQwfkbiZdfzA10Q9z5A=";
  };

  streetsidesoftware.code-spell-checker-australian-english = mkExt {
    publisher = "streetsidesoftware";
    name = "code-spell-checker-australian-english";
    version = "1.1.32";
    hash = "sha256-zn/DIzrF5sJ/jMGbc6IOQz6pTNZOBhimqMvpuuYal0k=";
  };
}
