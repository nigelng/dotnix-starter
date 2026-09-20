# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).



## [1.0.5] - 2026-09-20


### Added

- firefox: install via Homebrew cask and add Privacy Badger (#22)


### Changed

- update flake inputs (#19)

- update flake inputs (#23)


## [Unreleased]

### Added

- Firefox default add-on: Privacy Badger (`privacy-badger17`)

### Fixed

- Install Firefox add-ons via `ExtensionSettings` policies (pinned AMO file URLs) so Homebrew Firefox actually registers them (profile XPI sideloads were ignored)

### Changed

- Install Firefox via the Homebrew `firefox` cask only; home-manager manages profile, settings, and extensions with `package = null` always (no nixpkgs Firefox)
- Remove `my.firefox.package`, `nixExtensions`, and `useDeclarativeExtensions`; default `extensionInstallMode = "policy"`
- Drop sideload-only prefs (`extensions.autoDisableScopes` / `enabledScopes`) from unconditional Firefox base settings
- Update flake inputs (nixpkgs)

## [1.0.4] - 2026-09-20

### Added

- `docs/SECURITY.md` trust model and post-install checklist; `docs/MACOS-27.md` readiness notes
- JSON Schema for apps and fonts; host schema fields for power / Software Update overrides
- Shared `resolvePkg` helper; Android disabled fixture (`config/android/base.json`)
- Agent nixfmt gate (`AGENTS.md`, `.cursor/rules/nixfmt.mdc`, pre-commit format+check)

### Fixed

- Google Fonts OTF install path
- Host JSON validation coverage (schemas, Android fixture, safer failure modes)

### Changed

- Harden declarative defaults: disable guest login and Remote Login, require screensaver password
- Safer VS Code workspace trust and Homebrew defaults
- Pin GitHub Actions by commit SHA; document firewall / FileVault / Gatekeeper out-of-band steps

## [1.0.3] - 2026-07-23

### Added

- `platformVersions`, `systemImageTypes`, and `abiVersions` options on `my.android` — replaces the default full SDK with `composeAndroidPackages` so overlay configs can pin specific API levels, image types, and ABIs (e.g. API 35 `google_apis_playstore` `arm64-v8a` only, ~4 GB vs ~63 GB)

### Changed

- Update flake inputs (#16)
- Bump `softprops/action-gh-release` from 2 to 3 (#15)

## [1.0.2] - 2026-07-15

### Fixed

- ci: indent multiline string in release workflow YAML (#12)
- fonts: use MesloLGMDZ Nerd Font Mono and install meslo-lg (#13)

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

> Versions before 1.0.0 used date-only headers (no semver tag).

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
