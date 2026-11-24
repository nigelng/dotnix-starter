# Architecture overview

How JSON under `config/` becomes a nix-darwin + home-manager system, and which checks guard each stage. Entry points: [README.md](../../README.md), [SECURITY.md](../SECURITY.md).

## Pipeline

```
config/**/*.json
   │  validated by config/schema/*.schema.json   (scripts/validate-host-json.sh, `json-schema` check)
   ▼
lib/default.nix  load* wrappers  (read files, throw on missing host files)
   │  call pure merge functions   (mergeAppConfig, mergeFontConfig, mergeFirefoxConfig,
   │                               mergeAndroidConfig, resolveHostConfig, checkHostsManifest)
   ▼
darwin/default.nix  (darwinConfigurationsBuilder; passes configs as specialArgs / extraSpecialArgs)
   ▼
darwin/*.nix and home/*.nix modules
   ▼
assertions on the final config  (nix user lists, https add-ons)
```

- **Schema** is the contract for JSON shape; the validator runs it per host. Nix does not read schemas.
- **Loaders** (`load*`) do IO only; all merge and default logic lives in the pure functions, which `tests/lib.nix` exercises with literal attrsets.
- **Assertions** run over final module values, so overlay loaders and extra modules are checked too. Each assertion covers only the keys it names (see the user-list and https entries below).

## JSON file to consumer

| JSON | Schema | Loader (pure fn) | Consumer |
| ---- | ------ | ---------------- | -------- |
| `config/hosts.json` | `hosts` | `loadHostsManifest` (`checkHostsManifest`) | `flake.nix` host list, `defaultHost` |
| `config/hosts/<host>.json` | `host` | `loadHostConfig` (`resolveHostConfig`) | `darwin/configuration.nix`, `darwin/system.nix`; `adminUsername` also via `loadUserConfig` |
| `config/user.json` (else `.example`) | `user` | `loadUserConfig` | `home/git.nix`, `home/default.nix`, `darwin/` (`userConfig.user`) |
| `config/git.json` | `git` | `loadSharedConfig` | `home/git.nix` (`gitConfig`) |
| `config/apps/base.json` + `apps/hosts/<host>.json` | `apps` | `loadAppConfig` (`mergeAppConfig`) | `darwin/configuration.nix` (packages, Homebrew) |
| `config/fonts/base.json` + `fonts/hosts/<host>.json` | `fonts` | `loadFontConfig` (`mergeFontConfig`) | `darwin/system.nix`, Homebrew font casks |
| `config/firefox/base.json` + `firefox/hosts/<host>.json` | `firefox` | `loadFirefoxConfig` (`mergeFirefoxConfig`) | `darwin/default.nix` (enable default), `home/firefox.nix` |
| `config/android/base.json` + `android/hosts/<host>.json` | `android` | `loadAndroidConfig` (`mergeAndroidConfig`) | `darwin/default.nix` (`my.android.enable`), `home/android.nix` |

Merge semantics: lists are unioned and deduplicated, maps are host-wins per key, Android lists are replaced by the host value (including `[]`).

## Knob defaults

| Knob | Default | Where defined |
| ---- | ------- | ------------- |
| `claudeKit` (host) | `false` | `resolveHostConfig`; the starter ships the flag only, behavior lives in an overlay module |
| `automaticallyInstallMacOSUpdates` (host) | `true` | `resolveHostConfig` |
| `knownNetworkServices`, `restartAfterPowerFailure` (host) | from `machineType` preset (`laptop` / `macmini`) | `lib/host-presets.nix`, overridable per host |
| `extraSessionPaths` (host) | `[]` | `resolveHostConfig` |
| `my.firefox.enable` | host/base `"enable"` if either sets it (host wins), else on when `config/firefox/base.json` exists, else off | `mergeFirefoxConfig` + `darwin/default.nix` (`lib.mkDefault`; module settings override) |
| Android `enable` | `false`; base must not set it | `mergeAndroidConfig` |
| Android `platformVersions` / `systemImageTypes` / `abiVersions` | `["34","35"]` / `["google_apis_playstore"]` / `["arm64-v8a"]` | `mergeAndroidConfig` |
| Android `jdkPackage`, `guiSdkSymlink`, `avdDefaultSymlink`, `avdHome` | `"jdk"`, `true`, `true`, `null` | `mergeAndroidConfig` |
| Firefox `profileName` | `"default"` | `mergeFirefoxConfig` |

## Trust rules

- `trustedUsers`, `allowedUsers`, `adminUsername`: no `*`, whitespace or newline. Schema (`host.schema.json`) plus an assertion on the final `nix.settings` `trusted-users`, `allowed-users`, `extra-trusted-users` and `extra-allowed-users` in `darwin/configuration.nix`. Free-form `nix.extraOptions` is not inspected. `@group` entries are still allowed.
- Firefox `extensions.manual[].url` / `my.firefox.manualExtensions`: must be `https://`. Schema (`firefox.schema.json`) plus an assertion in `home/firefox.nix`. Direct `programs.firefox.policies` settings are not inspected.
- `defaultHost` must be one of `hosts`: `checkHostsManifest` (loader) and `validate-host-json.sh`.

## Check inventory

| Check | What it covers | Where it runs |
| ----- | -------------- | ------------- |
| `lib-tests` flake check | `tests/lib.nix`: every merge function, plus drift test (schema properties reach loader output) | `nix flake check --no-build` evaluates; CI `eval` job builds |
| `fmt` flake check | `treefmt --ci` (nixfmt) on a writable copy of the source | CI `eval` job (also `nix fmt -- --ci` in the `fmt` job) |
| `shellcheck` flake check | `scripts/*.sh`, `build-darwin.sh` | CI `eval` job (also the `shellcheck` job) |
| `json-schema` flake check | all eight schemas exist, then `validate-host-json` on the tree | CI `eval` job |
| `<host>` flake check | builds the full system closure | CI per-host matrix |
| `validate-host-json.sh` | hosts/user/git (each only when schema and file exist), then per-host host/apps/fonts/firefox/android; `defaultHost` in `hosts` | CI `eval` job, `nix run '.#validate-host-json'`, overlays via `SCHEMA_ROOT` |
| `scripts/test-correctness.sh` | cases `apps`, `gc`, `android`, `git`, `shell`, `host`, `schema`, `cursor`, `wrapper`, `release`, `all` | CI `eval` job, pre-commit |

The `schema` case checks schema accept/reject (user lists, https add-ons, `hosts`), the validator's `defaultHost` rejection on a temp copy, the nix-darwin and home-manager assertions via `extendModules`, and the Firefox `enable` wiring.

## Overlay contract

An overlay repo supplies its own `config/` JSON and imports from this flake:

- **Exported:** `homeModules.*`, `darwinModules.*`, `lib` (loaders and pure merge functions), `darwinConfigurationsBuilder`, `overlayFlakeOutputs`, `validateApps`, `scripts.validateHostJson`, `packages.<system>.json-schemas`, `mkWritableCopyActivation`, `editorTooling`.
- **Overlay gets:** the modules (including the nix user-list and https assertions), loaders, the shared `apps` / `checks` (app, font and Firefox-slug validation, host builds) / `formatter` / `devShell` from `overlayFlakeOutputs`, and the validator with schemas via `SCHEMA_ROOT`. Overlays may pass custom loaders and `extraDarwinModules`; the user-list assertion still checks the final `nix.settings` values (not `nix.extraOptions`).
- **Starter only:** the `lib-tests`, `fmt`, `shellcheck` and `json-schema` checks, `tests/lib.nix` and `scripts/test-correctness.sh`. They are deliberately not in `overlayFlakeOutputs`.
- **Missing optional config:** without `config/firefox/base.json` or `config/android/base.json` the loaders return a no-op config and the modules stay disabled.
- **Intended breaks on upgrade** (unsafe user entries, Firefox host `enable: false`, `defaultHost` not in `hosts`, `user.json` without `defaultGpgKey`): see [Overlay upgrade notes](../../README.md#overlay-upgrade-notes).
