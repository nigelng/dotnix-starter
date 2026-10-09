# Agent notes (dotnix-starter)

Instructions for Cursor and other coding agents working in this repo.

## nixfmt (required)

The flake `formatter` is `pkgs.nixfmt-tree` (treefmt + nixfmt). Prefer bare `nix fmt` at the flake root — it formats tracked `*.nix` without nixfmt’s deprecated directory-recursion warning.

Always format before committing any `*.nix` changes:

```sh
nix fmt
nix fmt -- --ci
```

CI job `Flake check / fmt` runs `nix fmt -- --ci`. See also `.cursor/rules/nixfmt.mdc`.

Editors (nil / VS Code Nix IDE) still use the `nixfmt` binary for single-buffer format; keep that separate from the flake tree formatter.

## Conventional commits

PR titles and commits use Conventional Commits. See `.cursor/rules/semantic-commits.mdc`.

## Local hooks

```sh
pre-commit install
pre-commit run --all-files
```
