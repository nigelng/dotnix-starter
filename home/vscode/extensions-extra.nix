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
  artdiniz.quitcontrol-vscode = mkExt {
    publisher = "artdiniz";
    name = "quitcontrol-vscode";
    version = "4.0.0";
    hash = "sha256-JB9Dvu6HjTJSxm7SKkIqAqfkjDhScsFFlRVQipV5YqQ=";
  };

  arcanis.vscode-zipfs = mkExt {
    publisher = "arcanis";
    name = "vscode-zipfs";
    version = "3.0.0";
    hash = "sha256-yNRC03kV0UvpEp1gF+NK0N3iCoqZMQ+PAqtrHLXFeXM=";
  };

  pomdtr.excalidraw-editor = mkExt {
    publisher = "pomdtr";
    name = "excalidraw-editor";
    version = "3.9.1";
    hash = "sha256-/LqC8GUBEDs+yGYCIX8RQtxDmWogTTiTiF/WJiCuEj4=";
  };

  ms-vscode.atom-keybindings = mkExt {
    publisher = "ms-vscode";
    name = "atom-keybindings";
    version = "3.3.0";
    hash = "sha256-vzOb/DUV44JMzcuQJgtDB6fOpTKzq298WSSxVKlYE4o=";
  };

  wayou.vscode-todo-highlight = mkExt {
    publisher = "wayou";
    name = "vscode-todo-highlight";
    version = "1.0.5";
    hash = "sha256-CQVtMdt/fZcNIbH/KybJixnLqCsz5iF1U0k+GfL65Ok=";
  };

  tyriar.lorem-ipsum = mkExt {
    publisher = "tyriar";
    name = "lorem-ipsum";
    version = "1.3.1";
    hash = "sha256-iBOeyrLTs5CQy/qnW9WoWMxt2Z03XHUrcJ2lyHjKmZk=";
  };

  tomoyukim.vscode-mermaid-editor = mkExt {
    publisher = "tomoyukim";
    name = "vscode-mermaid-editor";
    version = "0.19.1";
    hash = "sha256-MZkR9wPTj+TwhQP0kbH4XqlTvQwfkbiZdfzA10Q9z5A=";
  };

  npxms.hide-gitignored = mkExt {
    publisher = "npxms";
    name = "hide-gitignored";
    version = "1.1.0";
    hash = "sha256-GHDyt+dzzqQXcqJYeMuYczOGFn1lf/Gliehc5oAzSBQ=";
  };

  orta.vscode-jest = mkExt {
    publisher = "orta";
    name = "vscode-jest";
    version = "6.4.4";
    hash = "sha256-aAS52nwAtoMxrFoWD2Ow4LSKgCiBEZvAP6H2xYXMUzY=";
  };
}
