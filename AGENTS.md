# Agent notes (dotnix-starter)

Instructions for Cursor and other coding agents working in this repo.

## nixfmt (required)

Always run the flake Nix formatter before committing any `*.nix` changes:

```sh
nix fmt
git ls-files -z '*.nix' | xargs -0 nix fmt -- --check
```

CI job `Flake check / fmt` fails the PR if this is skipped. See also `.cursor/rules/nixfmt.mdc`.

## Conventional commits

PR titles and commits use Conventional Commits. See `.cursor/rules/semantic-commits.mdc`.

## Local hooks

```sh
pre-commit install
pre-commit run --all-files
```
