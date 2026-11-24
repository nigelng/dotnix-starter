# dotnix-starter

[![Flake check](https://github.com/nigelng/dotnix-starter/actions/workflows/flake.yml/badge.svg)](https://github.com/nigelng/dotnix-starter/actions/workflows/flake.yml)

Nix flake template for macOS (Apple Silicon): [nix-darwin](https://github.com/nix-darwin/nix-darwin) for the system and [home-manager](https://github.com/nix-community/home-manager) for user config. App lists: shared packages in `config/apps/base.json`, per-host extras in `config/apps/hosts/<hostname>.json` (merged at build time). Profile settings in `config/user.json`, git in `config/git.json`; per-machine settings (including `adminUsername`) in `config/hosts/<hostname>.json`.

This template is designed to work standalone **and** as a flake overlay — a private repo can import `homeModules` and `darwinModules` from this flake and extend them with personal config (see [Using as a flake overlay](#using-as-a-flake-overlay)).

**Included:**

- **zsh** as the login shell
- **Fonts**: `config/fonts/base.json` defines `pkgs` (nixpkgs-only), `google` (via `overlays/google-fonts`), and `nerd` (starter ships `jetbrains-mono`; UI font `JetBrainsMono Nerd Font Mono`); per-host extras (including optional Homebrew font `casks`) in `config/fonts/hosts/<hostname>.json`
- **Ghostty config** — Nix defaults from `home/themes/default.nix` into `~/.config/ghostty/config.d/nix.conf`; personal overrides in `~/.config/ghostty/local.conf`. Install the Ghostty app yourself (e.g. add a Homebrew cask in apps JSON)
- **[Firefox](https://www.mozilla.org/firefox/)** — backup browser via Homebrew cask with Dark Reader, 1Password, AdGuard AdBlocker, and Privacy Badger; privacy-hardened HM profile defaults; JSON-driven config in `config/firefox/` (see [Firefox (backup browser)](#firefox-backup-browser))
- **btop** with Catppuccin Mocha theme
- **Themed CLI tools** — Catppuccin Mocha (mauve accent): p10k palette, eza, vivid `LS_COLORS`, gh-dash, bat, git delta

**User-scope extras** (home-manager):

- **direnv** (with **nix-direnv**)
- **git** / **ssh** / **gpg** (GPG agent for other uses). With the 1Password app (`1password` / `1password@beta` cask, or `my.onePassword.enable = true`), SSH uses the 1Password agent and **commits sign with SSH** via 1Password; otherwise commits are unsigned — see [1Password secret loading](#1password-secret-loading) and Caveats
- **Editor modules** (`home/vscode.nix` / `homeModules.vscode`) — manage Cursor and VS Code extensions + settings (`package = null`). Cursor turns on only when a `cursor`/`code-cursor` cask is listed in apps JSON; VS Code only when `visual-studio-code` is listed. If you install either another way, set `programs.cursor.enable = true` / `programs.vscode.enable = true`. Both share `commonBase`; VS Code also HM-installs Nix IDE, Python Environments and Pylance. Devin (optional cask) shares the **settings** pipeline only
- **[eza](https://eza.rocks)** (modern `ls` replacement)
- **[fzf](https://github.com/junegunn/fzf)** (Catppuccin Mocha colors)
- **[zoxide](https://github.com/ajeetdsouza/zoxide)**
- **[gh](https://cli.github.com)** with extensions:
  - [gh-eco](https://github.com/jrnxf/gh-eco)
  - [gh-dash](https://github.com/dlvhdr/gh-dash)
  - [gh-markdown-preview](https://github.com/yusukebe/gh-markdown-preview)

**Optional (JSON-driven):**

- **Android SDK** — disabled by default (`config/android/`); enable per host (see [Android SDK](#android-sdk))
- Homebrew casks / extra nixpkgs apps (Ghostty, editors, `_1password-cli`, …) via `config/apps/`

**Zsh** is the default shell (in addition to system shells):

- Managed via [zimfw](https://zimfw.sh) (`pkgs.zimfw`) with modules: `environment`, `completion`, `git`, `input`, `termtitle`, `utility`, `archive`
- **eza**, **fzf**, and **zoxide** integrations are via home-manager (`programs.*`), not zimfw modules (avoids duplicate aliases/keybindings)
- **[Powerlevel10k](https://github.com/romkatv/powerlevel10k)** prompt via `pkgs.zsh-powerlevel10k` and vendored `home/config_files/p10k.zsh` (`POWERLEVEL9K_MODE=nerdfont-v3`)

### Powerlevel10k setup

Config lives in `home/config_files/p10k.zsh` and is installed to `~/.p10k.zsh` (made writable on each switch so the wizard can save). Run `p10k configure` in zsh or from any shell via the `p10k` command on PATH. The wizard should skip `.zshrc` edits (home-manager owns `~/.config/zsh/.zshrc`); if it still asks, choose **(n) No**. When you are happy with the result, copy `~/.p10k.zsh` into `home/config_files/p10k.zsh` and re-switch to persist it declaratively.

Instant-prompt cache files live in `~/.cache/p10k-instant-prompt-*` (not managed by Nix).

### Git aliases (zimfw `git` module)

Uppercase `G*` shortcuts come from zimfw's `git` module (`zmodule git` in `home/zsh.nix`), not from home-manager `shellAliases`. Run `G?` in a shell to look up aliases.

---

## Flake layout

| Path                                   | Role                                                                                                                                                                                      |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flake.nix`                            | Inputs, `darwinConfigurations`, `homeModules`, `darwinModules`, `formatter`, `devShell`, `checks`, `apps`                                                                                 |
| `lib/`                                 | JSON loaders (`loadSharedConfig`, `loadHostConfig`, …) wrapping pure merge functions (`mergeAppConfig`, `resolveHostConfig`, …); see [docs/architecture/OVERVIEW.md](docs/architecture/OVERVIEW.md) |
| `tests/lib.nix`                        | `lib.runTests` unit tests for the pure merge functions plus a schema-to-loader drift test (run by the `lib-tests` flake check)                                                            |
| `config/apps/base.json`                | Apps on every host: `system`, `user`, `taps`, `brews`, `casks`, `mas`                                                                                                                     |
| `config/apps/hosts/<name>.json`        | Per-host extras only (additive merge; lists deduplicated). Required for each host in `config/hosts.json`.                                                                                 |
| `config/fonts/base.json`               | Fonts on every host: `pkgs`, `google`, `nerd` (optional `casks` per host in `config/fonts/hosts/<name>.json`)                                                                             |
| `config/fonts/hosts/<name>.json`       | Per-host font extras only (additive merge). Required for each host in `config/hosts.json`.                                                                                                |
| `config/firefox/base.json`             | Firefox backup browser defaults: `profileName`, `settings` (about:config), `extensions.nix` (AMO slugs)                                                                                   |
| `config/firefox/hosts/<name>.json`     | Per-host Firefox overrides (additive merge for extensions, per-key override for settings). Required for each host in `config/hosts.json`.                                                 |
| `config/android/base.json`             | Shared Android SDK defaults (no `enable` key). Optional for overlays that omit Android.                                                                                                   |
| `config/android/hosts/<name>.json`     | Per-host Android opt-in (`enable`) and overrides. Required when base exists.                                                                                                              |
| `config/schema/*.schema.json`          | JSON Schema for `host`, `hosts`, `user`, `git`, `apps`, `fonts`, `firefox`, `android` (8 schemas; validated by `scripts/validate-host-json.sh`; override with `SCHEMA_ROOT`)               |
| `config/user.json` / `config/git.json` | Shared profile (name, email, GPG) and git settings. Copy `config/user.json.example` to `config/user.json`, edit, and **git add** it (flakes only see tracked files). |
| `config/hosts.json`                    | Hostnames to build (`hosts`, `defaultHost`)                                                                                                                                               |
| `config/hosts/<name>.json`             | Per-machine settings: `adminUsername`, `machineType` (`laptop` \| `macmini`), Homebrew, nix trusted/allowed users, optional `extraSessionPaths`, `knownNetworkServices`, power / SoftwareUpdate overrides |
| `docs/MACOS-27.md`                     | Major macOS / channel upgrade checklist                                                                                                                                                   |
| `docs/architecture/OVERVIEW.md`        | Config pipeline (JSON → schema → loader → modules → assertions), knob defaults, check inventory, overlay contract                                                                         |
| `docs/SECURITY.md`                     | Trust model, post-install checklist (FileVault/Gatekeeper), secrets, Homebrew, Firefox, CI pinning                                                                                        |
| `overlays/google-fonts/`               | Nix overlay packaging fonts from [google/fonts](https://github.com/google/fonts)                                                                                                          |
| `scripts/new-host.sh`                  | Interactive scaffold for a new host (also `nix run '.#new-host'`)                                                                                                                         |
| `darwin/`                              | nix-darwin modules (`configuration.nix`, `system.nix`)                                                                                                                                    |
| `home/`                                | home-manager modules (`git.nix`, `vim.nix`, `vscode.nix`, `zsh.nix`, `firefox.nix`, `android.nix`, …)                                                                                      |

**Pinned inputs** (see `flake.lock`):

- `nixpkgs` — `nixpkgs-26.05-darwin` (single package set for system and home-manager; this Darwin branch only advances once its Darwin Hydra jobs pass, so it is gated on Darwin builds)
- `darwin` — `nix-darwin-26.05`
- `home-manager` — `release-26.05`

`nix-command` and `flakes` are enabled via `nix.settings` in `darwin/configuration.nix` after the first switch.

**zsh:** Quote flake refs that contain `#` (e.g. `nix run '.#check'`), or zsh will try to glob and fail with `no matches found`.

---

## Install requirements

1. Install [Homebrew](https://brew.sh):

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Install Nix (multi-user) with [nix-installer](https://github.com/DeterminateSystems/nix-installer):

   ```sh
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

3. Clone this repo (e.g. to `~/.nix`):

   ```sh
   git clone https://github.com/nigelng/dotnix-starter ~/.nix && cd ~/.nix
   ```

4. Copy the user config example and edit with your details:

   ```sh
   cp config/user.json.example config/user.json
   # Edit config/user.json: name, email, GPG key, signing key
   git add config/user.json   # flakes only see tracked files
   ```

5. Edit `config/hosts/example-mac.json` with your macOS username and machine settings.

**Notes:**

- If `/etc/nix/nix.conf` already exists, move it to `~/.config/nix/nix.conf`.
- If `/etc/shells` or similar already exists, back it up and remove as needed for Nix-managed shells.
- If you see: `ln: failed to create symbolic link '/run': Read-only file system`:

  ```sh
  sudo /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
  ```

---

## Running the setup

Each Mac uses the hostname that matches `hostName` in `config/hosts/<hostname>.json`. The flake attribute is `darwinConfigurations.<hostName>`. Hosts are listed in `config/hosts.json`.

On a given machine, pass that host id to switch:

```sh
nix run '.#switch' -- example-mac
```

If you omit the argument, `defaultHost` from `config/hosts.json` is used.

### Adding another Mac

1. Run `nix run '.#new-host'` (or copy an existing host with `--copy-from`) to scaffold JSON under `config/hosts/`, `config/apps/hosts/`, `config/fonts/hosts/`, and `config/firefox/hosts/`, and append the id to `config/hosts.json`.
2. Edit the new host JSON files (`adminUsername`, `homebrewPrefix`, `homebrewCleanup`, host-only apps/fonts, Firefox overrides).
3. `git add` the new paths (Nix only sees tracked files), then `nix run '.#check'`.
4. On that machine: `nix run '.#switch' -- <new-host>`.

CI builds every host in `config/hosts.json` automatically; no workflow edit is required when adding a host.

### First build

From the flake directory (e.g. `~/.nix`):

```sh
# Optional: verify the closure builds
nix run '.#check'

# First install (builds nix-darwin, then activates)
nix run '.#switch'
# or: ./build-darwin.sh
```

Until `darwin-rebuild` is installed, the `switch` app builds the system with `nix build --no-link --print-out-paths` and runs `darwin-rebuild` from the returned store path. No `./result` symlink is created in the flake directory (which is read-only when run from the store).

### Later updates

After the first install, `darwin-rebuild` is on your `PATH`:

```sh
darwin-rebuild switch --flake ~/.nix#example-mac
# or from the repo:
darwin-rebuild switch --flake .
```

### Working on the flake

```sh
nix develop          # shell with nixfmt, jq, shellcheck, nodejs, jsonschema (host JSON validation)
nix fmt              # format *.nix (flake formatter = nixfmt-tree / treefmt)
nix fmt -- --ci      # verify formatting (CI uses this; treefmt CI mode)
nix run '.#check'    # runs nix flake check (may warn once if repo is dirty)
nix flake check      # direct; use after committing for quiet output
nix build --no-link '.#checks.aarch64-darwin.lib-tests'  # also: fmt, shellcheck, json-schema, pinned-sources (see CI)
bash scripts/test-correctness.sh schema   # schema/assertion regressions (also part of `all`)
nix flake update     # bump input pins (commit flake.lock when intentional)
nix run '.#changelog'           # nix-darwin stateVersion notes (defaultHost)
nix run '.#changelog' -- example-mac  # same for a specific host
```

When `darwin-rebuild` is not installed yet, `switch` and `changelog` use the same `--no-link --print-out-paths` store-path fallback as [First build](#first-build).

---

## Optional integrations

### Editor tooling (Prettier + ESLint)

This template wires Prettier and ESLint from flake-pinned config repos by default. The `prettier-config` and `eslint-config` inputs point at `github:nigelng/prettier-config` and `github:nigelng/eslint-config`, so editor tooling is always built for this flake.

The committed files that make this work:

- `lib/editor-tooling.nix` — builds `~/.config/editor-tooling/node_modules` from the flake-pinned config repos via `buildNpmPackage`.
- `home/editor.nix` — home-manager module that symlinks `.prettierrc.json`, `eslint.config.js`, and `node_modules` into `~/.config/editor-tooling/`.
- `home/config_files/editor-tooling/.prettierrc.json` — references `@nigelng/prettier-config`.
- `home/config_files/editor-tooling/eslint.config.js` — re-exports `@nigelng/eslint-config`.
- `lib/editor-tooling-package-lock.json` — pinned lockfile for reproducible `npmDepsHash`.

The flake automatically detects the `prettier-config` and `eslint-config` inputs and builds the editor tooling. `home/default.nix` imports `home/editor.nix` only when `editorTooling` is non-empty.

Overlay repos that don't want editor tooling can disable it by not passing the `prettier-config` and `eslint-config` inputs — `home/default.nix` skips the `editor.nix` import via `lib.optional (editorTooling != { })`.

See: `lib/editor-tooling.nix`, `home/editor.nix`.

### Granted / assume

[Granted](https://github.com/common-fate/granted) manages AWS CLI profiles via the `assume` command. To enable:

1. Add `granted` to `config/apps/hosts/<host>.json` in the `user` array:

   ```json
   { "user": ["granted"] }
   ```

2. The `assume()` function in `home/zsh.nix` is gated behind `programs.granted.enable` and wraps the `assume` binary so it works correctly in zsh.

3. To auto-assume a profile on shell startup, uncomment the example in `home/zsh.nix`:
   ```sh
   # assume your-profile-name &>/dev/null
   ```

See: `home/zsh.nix` (the `assume()` function and auto-call example).

### 1Password secret loading

This template integrates with [1Password CLI](https://developer.1password.com/docs/cli) when `op` is on PATH. Add `_1password-cli` to `config/apps` (system or user) if you want Nix to install it.

Prefer short-lived injection:

```sh
op run --env-file=.env -- your-command
```

An optional shell alias pattern is commented in `home/zsh.nix` (`load_secret`). Prefer `op run` over exporting long-lived tokens into the shell environment.

SSH and git signing use the 1Password agent / `op-ssh-sign` (see Caveats), which needs the **1Password app**, not only the CLI. They are gated by the home-manager option `my.onePassword.enable` (declared in `home/git.nix`):

- **Default:** `true` when the merged apps casks contain `1password` or `1password@beta`; `1password-cli` alone does **not** count. The default example host has neither, so it gets no `IdentityAgent` and unsigned commits and tags (`user.signingKey` stays set).
- **On:** SSH `IdentityAgent` points at the 1Password agent, and git sets `commit.gpgSign`, `tag.gpgSign`, `gpg.format = "ssh"` and `gpg.ssh.program` to `op-ssh-sign`.
- **Override:** if you install 1Password another way (Mac App Store, manual download), set `my.onePassword.enable = true` in `extraHomeModules`.
- **Shell:** `op` completion and `fnm env` run only when the binary is on PATH. When `_1password-cli` is a Nix app (apps `system`/`user`), the `op` completion is generated at build time, so shell startup never calls `op`.

See: `home/zsh.nix`, [docs/SECURITY.md](docs/SECURITY.md).

### Firefox (backup browser)

[Mozilla Firefox](https://www.mozilla.org/firefox/) is installed as a backup browser via the Homebrew `firefox` cask (`config/apps/base.json`). home-manager `programs.firefox` manages the profile, settings, and extensions only (`package = null` always — same pattern as Cursor; **no nixpkgs Firefox**). It ships with four AMO add-ons — **Dark Reader**, **1Password**, **AdGuard AdBlocker**, and **Privacy Badger** — plus a privacy-hardened profile (telemetry opt-out, DNS-over-HTTPS via Cloudflare, fingerprinting resistance, strict content blocking). The configuration is JSON-driven and extendable by both standalone users and overlay consumers.

**Add-ons installed by default:**

| Add-on            | AMO slug                         | Purpose                 |
| ----------------- | -------------------------------- | ----------------------- |
| Dark Reader       | `darkreader`                     | Dark mode for all sites |
| 1Password         | `onepassword-x-password-manager` | Password manager        |
| AdGuard AdBlocker | `adguard-adblocker`              | Ad/tracker blocking     |
| Privacy Badger    | `privacy-badger17`               | Tracker blocking        |

**Also in the curated catalog** (`home/firefox/addons.nix`; not in default `extensions.nix` — overlays may opt in via JSON slugs):

| Add-on                    | AMO slug                     | Purpose                                                              |
| ------------------------- | ---------------------------- | -------------------------------------------------------------------- |
| AdGuard Browser Assistant | `adguard-browser-assistant`  | Companion for the AdGuard desktop app (use instead of AdBlocker then) |

**Privacy/telemetry settings (in `config/firefox/base.json`):**

| Category            | Key prefs                                                                                             | Effect                                                                                            |
| ------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Telemetry opt-out   | `datareporting.*`, `toolkit.telemetry.*`, `app.shield.*`, `app.normandy.*`, `browser.crashReports.*`  | Disables all telemetry, health reports, Shield studies, auto crash submission                     |
| DNS-over-HTTPS      | `network.trr.mode: 2`, `network.trr.uri: cloudflare-dns.com`, `network.trr.bootstrapAddress: 1.1.1.1` | DoH via Cloudflare (mode 2 = DoH first, fall back to system DNS; set `3` for DoH-only)            |
| Fingerprinting      | `privacy.resistFingerprinting: true`, `media.peerconnection.ice.default_address_only: true`           | RFP spoofs common fingerprinting vectors; WebRTC uses default route only (prevents local IP leak) |
| Content blocking    | `browser.contentblocking.category: strict`, `privacy.trackingprotection.enabled: true`                | Strict tracking protection (social media trackers, fingerprinters)                                |
| Cookies & referrers | `network.cookie.cookieBehavior: 1` (block 3rd-party), `network.http.referer.XOriginPolicy: 2`         | Blocks third-party cookies; strips referrer to origin for cross-origin requests                   |
| Other privacy       | `privacy.donottrackheader.enabled`, `privacy.query_stripping.enabled`, `network.dns.disablePrefetch`  | DNT header, tracking query param stripping, no DNS prefetch leaking                               |
| Safe browsing       | `browser.safebrowsing.malware.enabled`, `browser.safebrowsing.phishing.enabled`                       | Keeps Google Safe Browsing malware/phishing protection on                                         |
| Misc                | `extensions.pocket.enabled: false`, `browser.urlbar.speculativeConnect.enabled: false`                | Disables Pocket (removes built-in service that phones home); no speculative URL bar connections   |

All settings are consumer-overridable via `my.firefox.settings` (Nix) or per-host JSON. See `config/firefox/base.json` for the full list.

**JSON file layout:**

| Path                                | Role                                                                                                      |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `config/firefox/base.json`          | Default profile name, `settings` (about:config prefs), and `extensions.nix` (AMO slugs)                   |
| `config/firefox/hosts/<name>.json`  | Per-host overrides (additive merge for extension lists, per-key override for settings; optional `"enable"`, see below). Use `{}` if none. |
| `config/schema/firefox.schema.json` | JSON Schema for the Firefox config (validated by `scripts/validate-host-json.sh`)                         |

**How extensions are installed:**

By default (`my.firefox.extensionInstallMode = "policy"`), add-ons are installed via `programs.firefox.policies.ExtensionSettings` (`force_installed` + pinned AMO **file** URLs from the catalog / `manual` entries). home-manager writes these into Darwin defaults (`org.mozilla.firefox.plist`) so Homebrew Firefox applies them. First launch (or restart after switch) needs network so Firefox can fetch the XPIs. Extension auto-update prefs stay off. Catalog pins (`home/firefox/addons-pins.json`) are refreshed by `scripts/update-pins.sh` in the weekly update PR; `manual` URLs stay hand-bumped (see [docs/SECURITY.md](docs/SECURITY.md)).

Official Firefox builds ignore new profile-directory XPI sideloads, so the old `home.file` symlink path is not the default.

**Enabling per host:**

A host's `"enable"` in `config/firefox/hosts/<host>.json` (or in `base.json`; the host wins) sets the `my.firefox.enable` default (`lib.mkDefault`), so `"enable": false` turns home-manager Firefox off for that host and `"enable": true` turns it on. When neither file sets `enable`, Firefox defaults on if `config/firefox/base.json` exists. An explicit `my.firefox.enable` in a module still overrides the default.

**Overriding in an overlay:**

The thin overlay path (`darwinConfigurationsBuilder`) includes the Firefox module but disables it by default when `config/firefox/base.json` doesn't exist. To enable Firefox in an overlay:

1. Add `"firefox"` to your apps `casks` (e.g. `config/apps/base.json`), same as Cursor / Ghostty.
2. Either create `config/firefox/base.json` (which enables HM Firefox automatically) or set `my.firefox.enable = true` in your `extraHomeModules`.

Default add-ons from starter JSON install via policies automatically after you bump this flake — no hand-written `ExtensionSettings` required. If an overlay previously duplicated `programs.firefox.policies.ExtensionSettings` as a brew workaround, **remove** that and keep/restore JSON `extensions.nix` slugs (or `manual`) so starter owns the policy list.

```nix
home-manager.users.myuser = {
  imports = [ dotnix-starter.homeModules.firefox ];
  my.firefox.enable = true;
  # Override settings (replaces JSON defaults for these keys)
  my.firefox.settings = {
    "browser.startup.homepage" = "https://example.com";
  };
};
```

**Adding non-AMO extensions:**

Consumers can add custom XPI add-ons via `my.firefox.manualExtensions` (or the JSON `extensions.manual` array). Each entry requires `name`, `addonId`, `url`, and `hash` (SRI format; `hash` is required by schema and used if you opt into sideload mode). `url` must be `https://`: `config/schema/firefox.schema.json` rejects other schemes and `home/firefox.nix` asserts the same for `my.firefox.manualExtensions` set from Nix. The rule covers only `extensions.manual` / `my.firefox.manualExtensions`; direct `programs.firefox.policies` settings (e.g. `ExtensionSettings.<id>.install_url`) and profile extensions set from other modules are not inspected. Example:

```nix
my.firefox.manualExtensions = [
  {
    name = "my-custom-addon";
    addonId = "my-addon@example.com";
    url = "https://example.com/my-addon.xpi";
    hash = "sha256-AAAA...";
  }
];
```

**Existing Firefox profile migration:**

Home-manager will back up any existing files in `~/Library/Application Support/Firefox/Profiles/` to `.hm-bak` on the first switch (via `home-manager.backupFileExtension`). The first switch uses a fresh Nix-managed profile. To keep your existing profile data:

1. Before switching: back up your profile manually (e.g. `cp -r ~/Library/Application\ Support/Firefox/Profiles ~/firefox-profile-backup`).
2. After the first switch: copy bookmarks, saved logins, and other profile data from your backup into the new Nix-managed profile directory.
3. Firefox Sync / Firefox Account is not configured by this template — sign in manually if you use Sync.

**Verifying add-ons:**

After switching, **quit and relaunch Firefox**, then open `about:policies` (ExtensionSettings should list the force-installed add-ons) and `about:addons` to confirm Dark Reader, 1Password, AdGuard AdBlocker, and Privacy Badger are installed and enabled. Optionally check Darwin defaults include enterprise policies, e.g. `defaults read org.mozilla.firefox`. Open `about:config` to verify the settings from `config/firefox/base.json`.

See: `home/firefox.nix`, `home/firefox/addons.nix`, `config/firefox/base.json`.

### Android SDK

Optional Nix-managed Android SDK via `home/android.nix` and `homeModules.android`.

| Path | Role |
| ---- | ---- |
| `config/android/base.json` | Shared defaults (`jdkPackage`, symlink flags). **Must not** contain `enable`. |
| `config/android/hosts/<name>.json` | Per-host `"enable": true \| false` and overrides. |
| `config/schema/android.schema.json` | JSON Schema (validated when base exists). |

This starter ships `enable: false` for `example-mac` so loaders and CI exercise the path without installing the SDK. To enable on a host:

```json
{ "enable": true }
```

List settings (JSON, in `config/android/base.json` or `config/android/hosts/<host>.json`) default to:

| Key                | Default                       |
| ------------------ | ----------------------------- |
| `platformVersions` | `["34", "35"]`                |
| `systemImageTypes` | `["google_apis_playstore"]`   |
| `abiVersions`      | `["arm64-v8a"]`               |

A host list replaces the base list (shallow merge), including an explicit `[]`. `config/schema/android.schema.json` sets `additionalProperties: false`, so unknown keys fail validation.

Then `darwin-rebuild switch`. Overlay repos without `config/android/` get a no-op (`enable = false`). Thin overlays should pass `loadAndroidConfig` into `darwinConfigurationsBuilder` (see below).

See: `home/android.nix`, `lib/default.nix` (`loadAndroidConfig`).

---

## Using as a flake overlay

This template exposes `homeModules` and `darwinModules` as flake outputs so a private overlay repo can import and extend them. It also exports infrastructure (`lib`, `editorTooling`, `mkWritableCopyActivation`, `darwinConfigurationsBuilder`, `overlayFlakeOutputs`, `overlays.google-fonts`, `pkgsForValidation`, `validateApps`, `scripts.validateHostJson`, `packages.<system>.json-schemas`) so overlay repos can build `darwinConfigurations` without copying any infrastructure files.

**Available exports:**

| Output                           | Description                                                                                                                                                               |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `homeModules.default`            | Full home-manager module tree (imports git, vim, vscode, zsh, editor)                                                                                                     |
| `homeModules.defaultWithFirefox` | Full home-manager module tree plus the Firefox backup browser module                                                                                                      |
| `homeModules.git`                | Just the git/gh config module                                                                                                                                             |
| `homeModules.vim`                | Just the neovim config module                                                                                                                                             |
| `homeModules.vscode`             | Cursor and VS Code editor modules (shared `commonBase`; each gated on its cask)                                                                                           |
| `homeModules.zsh`                | Just the zsh config module                                                                                                                                                |
| `homeModules.editor`             | Editor tooling (Prettier + ESLint from flake-pinned config repos)                                                                                                         |
| `homeModules.firefox`            | Just the Firefox backup browser module (opt-in via `my.firefox.enable`)                                                                                                   |
| `homeModules.android`            | Just the Android SDK module (opt-in via `my.android.enable` / host JSON)                                                                                                  |
| `darwinModules.default`          | Combined configuration.nix + system.nix                                                                                                                                   |
| `darwinModules.configuration`    | Just the nix-darwin system config module                                                                                                                                  |
| `darwinModules.system`           | Just the macOS defaults/networking module                                                                                                                                 |
| `lib`                            | Config loaders (`loadHostsManifest`, `loadSharedConfig`, `loadUserConfig`, `loadAppConfig`, `loadHostConfig`, `loadRawHostConfig`, `loadFontConfig`, `loadFirefoxConfig`, `loadAndroidConfig`) and pure merge functions (`mergeAppConfig`, `mergeFontConfig`, `mergeFirefoxConfig`, `mergeAndroidConfig`, `resolveHostConfig`, `checkHostsManifest`) |
| `editorTooling`                  | Built editor tooling attrset, or `{}` when inputs are absent                                                                                                              |
| `mkWritableCopyActivation`       | Helper for writable-copy activation scripts (pass into `darwinConfigurationsBuilder`)                                                                                     |
| `darwinConfigurationsBuilder`    | The `darwin/default.nix` function — call with your own config loaders, `extraHomeModules`, and `extraDarwinModules` (extra nix-darwin modules spliced into every host's `modules`; default `[ ]`) |
| `overlayFlakeOutputs`            | Shared `apps` / `checks` / `formatter` / `devShell` helper used by this flake (the starter-only checks `lib-tests`, `fmt`, `shellcheck`, `json-schema`, `pinned-sources` are not included)    |
| `overlays.google-fonts`          | The google-fonts nixpkgs overlay                                                                                                                                          |
| `pkgsForValidation`              | nixpkgs with google-fonts overlay for app/font validation (`allowUnfree = true`, matching darwin)                                                                         |
| `validateApps`                   | App/font/Firefox-slug/Android JDK validation for overlay checks                                                                                                           |
| `scripts.validateHostJson`       | Shell derivation for host JSON schema validation in CI                                                                                                                    |
| `packages.<system>.json-schemas` | Store copy of `config/schema`; set `SCHEMA_ROOT` to this path in overlay CI instead of copying schemas                                                                    |

Note: `homeModules.editor` is exported and wired to the flake-pinned `prettier-config` and `eslint-config` inputs. Overlay repos that don't provide those inputs should omit `homeModules.editor` from their imports.

**Thin overlay example (recommended):**

An overlay repo builds its `darwinConfigurations` using only the starter's exports + its own `config/` JSON and `home/personal.nix` — with zero copied infrastructure files. Prefer `follows` so darwin/HM track the starter, and `overlayFlakeOutputs` for the same `apps` / `checks` / `formatter` / `devShell` wiring:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    home-manager.follows = "dotnix-starter/home-manager";
    darwin.follows = "dotnix-starter/darwin";

    dotnix-starter = {
      url = "github:nigelng/dotnix-starter"; # pin a release tag in real overlays
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      darwin,
      dotnix-starter,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      system = "aarch64-darwin";
      flakeLib = dotnix-starter.lib;
      editorTooling = dotnix-starter.editorTooling;
      flakeRoot = builtins.toString self.outPath;

      manifest = flakeLib.loadHostsManifest flakeRoot;
      shared = flakeLib.loadSharedConfig flakeRoot;
      primaryHost = if manifest ? defaultHost then manifest.defaultHost else builtins.head manifest.hosts;

      inherit (shared) gitConfig;

      pkgs = nixpkgs.legacyPackages.${system};

      darwinConfigurations = dotnix-starter.darwinConfigurationsBuilder {
        inherit (nixpkgs) lib;
        inherit
          flakeRoot
          home-manager
          darwin
          system
          gitConfig
          editorTooling
          ;
        inherit (dotnix-starter) mkWritableCopyActivation;
        hosts = manifest.hosts;
        loadHostConfig = flakeLib.loadHostConfig flakeRoot;
        loadAppConfig = flakeLib.loadAppConfig flakeRoot;
        loadFontConfig = flakeLib.loadFontConfig flakeRoot;
        loadFirefoxConfig = flakeLib.loadFirefoxConfig flakeRoot;
        loadAndroidConfig = flakeLib.loadAndroidConfig flakeRoot;
        loadUserConfig = flakeLib.loadUserConfig flakeRoot { };
        extraHomeModules = [ ./home/personal.nix ];
        # extraDarwinModules = [ ./darwin/my-module.nix ]; # optional, default [ ]
      };

      overlayOutputs = dotnix-starter.overlayFlakeOutputs {
        inherit
          self
          pkgs
          lib
          system
          dotnix-starter
          flakeRoot
          manifest
          primaryHost
          darwinConfigurations
          editorTooling
          ;
        newHostApp = dotnix-starter.apps.${system}.new-host;
      };
    in
    {
      darwinConfigurations = darwinConfigurations;

      formatter = overlayOutputs.formatter;
      devShells = overlayOutputs.devShells;
      checks = overlayOutputs.checks;
      apps.${system} = overlayOutputs.apps.${system};
    };
}
```

For schema validation without copying `config/schema/`, point `SCHEMA_ROOT` at the starter package:

```sh
SCHEMA_ROOT="$(nix build --print-out-paths --no-link '.#json-schemas')" \
  nix run github:nigelng/dotnix-starter#validate-host-json
# or, from an overlay that wraps the starter app against its own flake root:
# SCHEMA_ROOT="$(nix build --print-out-paths --no-link github:nigelng/dotnix-starter#json-schemas)" \
#   nix run .#validate-host-json
```

(When the flake root *is* this template, the default `SCHEMA_ROOT=$PWD/config/schema` is enough.)

The validator checks `config/hosts.json` (against `hosts.schema.json` when present; `defaultHost`, when set, must be listed in `hosts` regardless), `config/user.json` (falling back to `config/user.json.example`; `user.schema.json`) and `config/git.json` (`git.schema.json`), then each host's `hosts/`, `apps/`, `fonts/`, `firefox/` and `android/` files. The `hosts`, `user` and `git` checks run only when that schema exists in `SCHEMA_ROOT` and the file exists, so an overlay pointing at an older schema directory keeps passing.

**Manual overlay example (module-level):**

For overlays that need full control over `darwinSystem` modules:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    dotnix-starter.url = "github:nigelng/dotnix-starter";
    prettier-config = {
      url = "github:nigelng/prettier-config";
      flake = false;
    };
    eslint-config = {
      url = "github:nigelng/eslint-config";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, darwin, dotnix-starter, ... }@inputs:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      flakeRoot = builtins.toString self.outPath;
    in {
      darwinConfigurations.my-mac = darwin.lib.darwinSystem {
        inherit system;
        modules = [
          dotnix-starter.darwinModules.default
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              editorTooling = dotnix-starter.editorTooling;
              mkWritableCopyActivation = dotnix-starter.mkWritableCopyActivation;
              firefoxConfig = dotnix-starter.lib.loadFirefoxConfig flakeRoot;
            };
            home-manager.users.myuser = dotnix-starter.homeModules.default;
          }
        ];
      };
    };
}
```

### Overlay upgrade notes

Intended behaviour changes for overlays that upgrade to this release:

- **Unsafe user-list entries fail eval.** An entry in `trustedUsers`, `allowedUsers` or `adminUsername` containing `*`, whitespace or a newline is rejected by the schema and by a nix-darwin assertion on the final `nix.settings` `trusted-users`, `allowed-users`, `extra-trusted-users` and `extra-allowed-users`, including values from custom loaders or `extraDarwinModules`. Free-form `nix.extraOptions` is not inspected. `@group` entries (for example `@staff`) are still allowed.
- **Firefox host `"enable": false` now takes effect.** It sets the `my.firefox.enable` default to `false`; previously the key was dropped by the loader.
- **`defaultHost` must be one of `hosts`.** Otherwise `loadHostsManifest` throws and `scripts/validate-host-json.sh` fails.
- **`config/user.json` needs `defaultGpgKey`** (alongside `name`, `email`, `defaultSigningKey`) to pass the exported validator; the modules already read these keys unguarded.
- **`manual` Firefox add-on URLs must be `https://`** (schema and home-manager assertion on `my.firefox.manualExtensions` only; direct `programs.firefox.policies` settings are not inspected).
- **New:** `claudeKit` is always defined (default `false`), and the pure merge functions are exported under `lib`.

---

## Maintenance

### Homebrew cleanup (`homebrewCleanup` in host JSON)

Controls what happens to brews/casks **not** listed in your merged config on each `darwin-rebuild switch`.

| Value       | Behavior                                                      |
| ----------- | ------------------------------------------------------------- |
| `none`      | Leave extra packages installed (nix-darwin default)           |
| `check`     | Fail activation if extras exist (good for catching drift)     |
| `uninstall` | Remove unlisted packages                                      |
| `zap`       | Remove unlisted packages and zap cask files (most aggressive) |

Use `check` or `none` on a shared machine if others install brews outside this flake. Prefer `check` over `zap` unless you intentionally want destructive cleanup (see [docs/SECURITY.md](docs/SECURITY.md)).

### Host JSON overrides

Optional keys in `config/hosts/<name>.json`:

| Key | Default | Notes |
| --- | ------- | ----- |
| `restartAfterPowerFailure` | From `machineType` preset | Override laptop/macmini preset |
| `automaticallyInstallMacOSUpdates` | `true` | Set `false` before major macOS betas ([docs/MACOS-27.md](docs/MACOS-27.md)) |
| `knownNetworkServices` | From preset | Override interface display names |
| `extraSessionPaths` | `[]` | Extra PATH entries for the user session |
| `claudeKit` | `false` | Enables the Claude/Cursor MCP + skills kit; starter ships the flag only — behavior lives in an overlay module. Defined by the loader (`resolveHostConfig`), so overlay modules can read `systemConfig.claudeKit` without a fallback |

`trustedUsers`, `allowedUsers` and `adminUsername` must not contain `*`, whitespace or a newline. The host schema rejects them, and `darwin/configuration.nix` asserts the same on the final `nix.settings` `trusted-users`, `allowed-users`, `extra-trusted-users` and `extra-allowed-users` (including values from overlay loaders and `extraDarwinModules`). Free-form `nix.extraOptions` is not inspected, so do not set user lists there. `@group` entries remain allowed. Firefox `extensions.manual[].url` / `my.firefox.manualExtensions` URLs must be `https://` (schema plus a home-manager assertion); direct `programs.firefox.policies` settings are not inspected.

### `machineType` (host presets)

Each host JSON must set `machineType` to `laptop` or `macmini`. This drives networking and power defaults in `darwin/system.nix` via `lib/host-presets.nix`:

| `machineType` | `knownNetworkServices` (default)                                            | `restartAfterPowerFailure`                         |
| ------------- | --------------------------------------------------------------------------- | -------------------------------------------------- |
| `laptop`      | Wi-Fi, Thunderbolt Bridge                                                   | omitted (macOS does not support this on portables) |
| `macmini`     | Wi-Fi, USB 10/100/1000 LAN, Thunderbolt Ethernet Slot 1, Thunderbolt Bridge | `true`                                             |

Override interface names per host by adding `knownNetworkServices` to that host's JSON. Verify labels on the machine with:

```sh
networksetup -listallnetworkservices
```

### `system.stateVersion` (nix-darwin)

Set to **6** in code (`darwin/system.nix`) with `lib.mkDefault`, so overlays can set `system.stateVersion` plainly (no `mkForce`). Check the changelog before bumping:

```sh
nix run '.#changelog'
```

### `home.stateVersion` (home-manager)

Defaults to the flake's home-manager release (currently **26.05**) via `lib.mkDefault`, so overlays can set `home.stateVersion` plainly (no `mkForce`). Bump only when upgrading the `home-manager` input and after reading [HM release notes](https://nix-community.github.io/home-manager/release-notes.xhtml).

### Home Manager file conflicts

If activation stops because an existing file would be "clobbered", `home-manager.backupFileExtension` is set to `hm-bak` in `darwin/default.nix` so the existing file is renamed before Home Manager installs its version.

### Secrets

Do not commit API tokens, private keys, or `.env` files (see `.gitignore`). Track `config/user.json` in git — it holds public identity (name, email, GPG key id, SSH **public** signing key), not private key material. Copy from `config/user.json.example`, edit, and `git add` it; overlays fail closed if it is missing from the flake store copy. Prefer `op run --env-file=.env` for shell secrets (see [1Password secret loading](#1password-secret-loading) and [docs/SECURITY.md](docs/SECURITY.md)); do not put 1Password item ids in Nix. For encrypted repo secrets, consider [sops-nix](https://github.com/Mic92/sops-nix) or [agenix](https://github.com/ryantm/agenix).

### Periodic updates and macOS upgrades

See [docs/MACOS-27.md](docs/MACOS-27.md) for the weekly lockfile cadence, Dependabot Actions pins, and the checklist for Apple major releases / Nix channel bumps. Channel bumps are **manual** `flake.nix` ref edits — `nix flake update` alone stays on `*-26.05`.

### Nix garbage collection

Automatic GC is enabled via a launchd job that runs weekly on Sunday at 03:00 local time, with `--delete-older-than 14d`. Set in `darwin/configuration.nix`.

### Pre-commit (optional)

[pre-commit](https://pre-commit.com/) and `shellcheck` are installed as user packages via `config/apps/base.json`, so after a rebuild you can enable the hooks for fast feedback before push:

```sh
pre-commit install
pre-commit run --all-files
```

Hooks (see `.pre-commit-config.yaml`): **`nix fmt`** (writes, then `nix fmt -- --ci`) on `*.nix`, `shellcheck` on `scripts/*.sh` and `build-darwin.sh`, and `scripts/test-correctness.sh all` when `lib/`, `darwin/`, `home/`, `config/`, `flake.nix`/`flake.lock`, `build-darwin.sh` or the harness changes. Agents must also run `nix fmt` before committing Nix (see [AGENTS.md](AGENTS.md) and `.cursor/rules/nixfmt.mdc`). Not required for CI beyond the flake `fmt` job.

### Releasing

Publish a semver release from **Actions → Release → Run workflow** on `main`. Choose `patch`, `minor`, or `major` and leave **recover** as `no`. The workflow generates a Keep a Changelog section from conventional commits since the latest `v*` tag, opens a short-lived PR (`automation/release-vX.Y.Z`), squash-merges it (required because `main` forbids direct pushes), creates the semver tag, and publishes a GitHub Release whose body is only the new section.

**Preconditions:**

- `main` should already be green — changelog-only release PRs skip the macOS flake CI (`paths-ignore` for `CHANGELOG.md` on both `push` and `pull_request`).
- Allow GitHub Actions to create/merge PRs (Settings → Actions → General), or set a `WORKFLOW_PAT` secret with `contents` + `pull-requests` write (same as `update-flake`).
- Keep **branch commit messages** conventional (`feat:`, `fix:`, etc.). `fix-pr-title.yml` enforces PR titles only; git-cliff reads the commits on the branch.
- Auto-generated bullets are commit-derived drafts and may be noisier than hand-curated entries. Edit `CHANGELOG.md` before dispatching if you need polished notes (optional `notes` workflow input is a possible future enhancement).
- The first release after merging the release workflow (`v1.0.1`) will include those workflow commits — expected.

**Preview locally** (requires [git-cliff](https://git-cliff.org)):

```sh
git fetch --tags
./scripts/release-changelog.sh --since v1.0.0 --version v1.0.1 --dry-run
```

**Orphan recovery:** If a changelog header was committed but tag/release creation failed, re-dispatch with **recover: yes** (same bump type as the partial release). Use **recover: no** for all normal releases.

### Faster CI (Cachix)

Optional free public [Cachix](https://www.cachix.org) cache named **`dotnix-starter`**. `.github/workflows/flake.yml` runs SHA-pinned `cachix/cachix-action` after the Nix installer on eval/fmt/check jobs (`authToken` from `CACHIX_AUTH_TOKEN`). Until the public cache and secret exist, the Cachix step may show as failed — it uses `continue-on-error: true`, so fmt/eval/check still run and the job can pass.

To enable caching:

1. Create a free OSS cache named `dotnix-starter` at [cachix.org](https://www.cachix.org).
2. Add repo secret `CACHIX_AUTH_TOKEN` (write access to that cache).
3. Subsequent CI runs pull from and push to the cache.

Do not create a private/paid cache for this template — macos overlays should reuse the same free public cache.

---

## CI

GitHub Actions on `macos-14` (Apple Silicon; update the runner image when validating newer macOS — see [docs/MACOS-27.md](docs/MACOS-27.md)):

- **Evaluate flake** — verifies every host in `config/hosts.json` has matching JSON under `config/hosts/`, `config/apps/hosts/`, `config/fonts/hosts/`, and (when present) Firefox/Android hosts; validates against `config/schema/*.schema.json`; then `nix flake check --no-build` (includes app/font package name and Firefox slug validation); then `nix build` of the starter-only checks `lib-tests`, `fmt`, `shellcheck`, `json-schema` and `pinned-sources`; then `scripts/test-correctness.sh all` (app fallbacks, GC schedule, Android lists/schema, Git includes and the 1Password signing gate, zsh init guards and baked `op` completion, `example-mac` host defaults, the `schema` case (schema accept/reject, user-list and https assertions, Firefox `enable` wiring, validator `defaultHost` check), Cursor pinned-extension installer, install wrapper).
- **Nix formatting** — dedicated job: `nix fmt -- --ci` (flake formatter is `pkgs.nixfmt-tree` / treefmt).
- **Starter flake checks** (`flake.nix`, `checks.aarch64-darwin`; starter only, not part of `overlayFlakeOutputs`): `lib-tests` (`tests/lib.nix` merge-function tests and the schema-to-loader drift test), `fmt` (`treefmt --ci`), `shellcheck` (`scripts/*.sh`, `build-darwin.sh`), `json-schema` (all eight schemas present, then `validate-host-json` on the tree) and `pinned-sources` (builds every pinned fetch: google-fonts, VSIX, AMO add-ons, bat theme). `nix flake check --no-build` evaluates them; the CI `eval` job builds them explicitly. Run one locally with `nix build --no-link '.#checks.aarch64-darwin.lib-tests'`.
- **Per-host build** (`.github/workflows/flake.yml`) — matrix derived from `config/hosts.json`: builds `.#checks.aarch64-darwin.<host>`.
- **shellcheck** — `scripts/*.sh` and `build-darwin.sh` on Ubuntu.
- **Update flake inputs** (`.github/workflows/update-flake.yml`) — weekly (and manual) `nix flake update`, `scripts/update-pins.sh all` (pins sidecars), and the editor-tooling lock refresh, with eval check and an in-workflow build of `example-mac` and `pinned-sources`; the result opens as an automated PR. Full host builds also run on the PR via `flake.yml`.
- **Dependabot** (`.github/dependabot.yml`) — weekly GitHub Actions dependency updates (workflows pin Actions by commit SHA).

Linux runners cannot build this flake; CI must stay on macOS.

---

## Caveats

- **Apple Silicon only.** The flake hardcodes `system = "aarch64-darwin"` permanently. Intel Macs (`x86_64-darwin`) are out of scope.
- Only brews/casks listed in the merged app and font configs are installed when `homebrewCleanup` is `uninstall` or `zap`; extras are removed on switch.
- **mas** = Mac App Store apps (IDs in `config/apps/base.json` and/or `config/apps/hosts/<host>.json`). Find existing app IDs with [mas-cli](https://github.com/mas-cli/mas).
- [Trusted users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-trusted-users) are the current user plus any listed in the host JSON. Default: `[<username>]`. Never use `"*"`; `*` and whitespace entries are rejected by the schema and a nix-darwin assertion.
- [Allowed users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-allowed-users) are the current user plus config. Default for new hosts: `[adminUsername]`. Never use `"*"` (same enforcement).
- Guest login is disabled; Remote Login (`services.openssh`) is off; screensaver requires a password immediately. FileVault and Gatekeeper stay **out of band** — see [docs/SECURITY.md](docs/SECURITY.md).
- `EDITOR=nvim` is the terminal default; `VISUAL` is `cursor` when `programs.cursor.enable`, else `code` when `programs.vscode.enable`, else `nvim`. `VISUAL` is forced in `home.sessionVariables` so it wins over neovim `defaultEditor`.
- SSH `HashKnownHosts` is enabled in home-manager.
- Git signs commits and tags with **SSH** via 1Password (`gpg.format = "ssh"` and `op-ssh-sign`), not classic GPG, **only when `my.onePassword.enable` is true** (default: the `1password` / `1password@beta` cask is listed; see [1Password secret loading](#1password-secret-loading)). Otherwise commits and tags are unsigned and SSH has no `IdentityAgent`; `user.signingKey` (`defaultSigningKey` in `config/user.json`) stays set so you can opt back in.
- **Shell init guards:** `op` completion and `fnm env` run only when those binaries are on PATH, and `brew shellenv` only when `<homebrewPrefix>/bin/brew` exists, so a fresh host without them starts zsh with no errors. If `_1password-cli` is a Nix app, `op` completion is baked at build time instead.
- **`homeModules.git` / `homeModules.zsh`:** `appConfig` is optional for these modules; without it the 1Password integration is off and shell init uses the runtime guards.
- The `find` alias (for `fd`) was removed; `fd` is still installed.
- **Cursor extension pins:** Cursor's VS Code engine lags upstream. **Nix IDE**, **Python Environments**, and **Pylance** are installed for Cursor via `cursor --install-extension` on home-manager activation (HM symlinks are not enough). They will not appear in marketplace search; check **Installed** or `cursor --list-extensions | grep -E 'nix-ide|python-envs|pylance'`. The installer runs only when the module is on and a real Cursor IDE answers `cursor --version` (a `cursor-cli` shim alone is not enough). A failed install prints a `warning:` and activation continues. If missing after switch, run manually: `cursor --install-extension jnoortheen.nix-ide --force && cursor --install-extension ms-python.vscode-python-envs --force && cursor --install-extension ms-python.vscode-pylance --force`, then reload the window.
- **Unfree:** `commonBase` stays free (Git Graph removed, not installed); the VS Code set adds Pylance (unfree). `nixpkgs.config.allowUnfree = true` is still required for `_1password-cli`, Android SDK, and editor/VS Code ecosystem packages overlays may need — predicate allowlists keep breaking as new unfree attrs appear.
- **CloudFormation YAML:** Prettier is the sole YAML formatter. Prefer `Fn::` long form (`Fn::Ref`, `Fn::Sub`, …). CFN short tags (`!Ref`, `!Sub`, …) are not Prettier-safe without a dedicated CFN extension (not shipped here).
- **Git `includes`:** entries in `config/git.json` `includes` are appended after the built-in delta theme include, in their original order, with their conditions preserved.
- **Leaving VS Code:** drop the `visual-studio-code` cask; the module turns off. After switching, remove leftover extensions under `~/.vscode/extensions` if you still see old HM symlinks.
