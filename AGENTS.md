# Agent notes (dotnix-starter)

Instructions for coding agents (Cursor, Claude Code, Devin, …) working in this repo.

## nixfmt (required)

The flake `formatter` is `pkgs.nixfmt-tree` (treefmt + nixfmt). Prefer bare `nix fmt` at the flake root — it formats tracked `*.nix` without nixfmt’s deprecated directory-recursion warning.

Always format before committing any `*.nix` changes:

```sh
nix fmt
nix fmt -- --ci
```

CI job `Flake check / fmt` runs `nix fmt -- --ci`.

Editors (nil / VS Code Nix IDE) still use the `nixfmt` binary for single-buffer format; keep that separate from the flake tree formatter.

## Conventional commits

PR titles and commits use [Conventional Commits](https://www.conventionalcommits.org/).

### Format

```
<type>[optional scope][optional !]: <description>
```

### Allowed types

`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

### Rules

- Description starts with a lowercase letter
- Imperative mood (e.g. "add schema", not "adds" or "Added")
- No trailing period
- PR titles must match the same pattern (enforced by `.github/workflows/fix-pr-title.yml`)

### Examples

```
feat(android): configurable platformVersions
fix(fonts): create opentype dir for OTF installs
docs: add macOS 27 readiness checklist
chore: update flake inputs
```

## Local hooks

```sh
pre-commit install
pre-commit run --all-files
```
