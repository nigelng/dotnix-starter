# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

> Versions before 1.0.0 used date-only headers (no semver tag).

## [1.0.1] - 2026-07-14

### Fixed

- Set `nixpkgs.config.android_sdk.accept_license` to a plain boolean (not `lib.mkIf`) so nixpkgs Android builds evaluate when Android is enabled
- Fail hard in `validate-host-json` when `config/hosts.json` is missing, invalid, or lists no hosts

### Added

- Semver release workflow (`workflow_dispatch`): git-cliff changelog, PR-based merge onto `main`, tag, and GitHub Release
- `cliff.toml` and `scripts/release-changelog.sh` for local dry-runs and CI generation

### Changed

- Skip Flake check on changelog-only pushes and PRs (`paths-ignore: CHANGELOG.md`)

## [1.0.0] - 2026-07-14

### Fixed

- Add missing `config/firefox/base.json` so default AMO add-ons and privacy prefs apply
- Re-link Firefox extension XPI symlinks on every home-manager switch (`force` + activation)

### Added

- `my.android` home-manager module with JSON-driven `loadAndroidConfig`, schema validation, and `new-host` scaffolding
- `overlayFlakeOutputs` helper for thin overlay repos (switch/check/changelog apps, checks, formatter, devShell)
- `validate-host-json` flake app wrapping `scripts.validateHostJson`
- `homeModules.android` export
- CI badge in README (Flake check workflow)

### Changed

- `flake.nix` refactored to use `overlayFlakeOutputs` internally
- Silence `DIRENV_LOG_FORMAT` when direnv is enabled (fixes p10k instant-prompt noise)
- `update-flake` workflow: `WORKFLOW_PAT` fallback and clearer failure message when Actions cannot open PRs

## [2026-07-06]

### Added

- Firefox backup browser (`my.firefox`) with JSON config, AMO add-ons, and privacy-hardened defaults

### Fixed

- Add missing `home/firefox/addons.nix` catalog

## [2026-07-05]

### Added

- Thin-overlay flake exports (`darwinConfigurationsBuilder`, `homeModules`, `lib` loaders, `validateApps`, script helpers)

### Fixed

- Fall back to `config/user.json.example` when `config/user.json` is missing

## [2026-07-04]

### Added

- Initial nix-darwin + home-manager macOS template with editor tooling (Prettier/ESLint)
