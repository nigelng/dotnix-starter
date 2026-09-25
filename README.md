# dotnix-starter

[![Flake check](https://github.com/nigelng/dotnix-starter/actions/workflows/flake.yml/badge.svg)](https://github.com/nigelng/dotnix-starter/actions/workflows/flake.yml)

Nix flake template for macOS (Apple Silicon): [nix-darwin](https://github.com/LnL7/nix-darwin) for the system and [home-manager](https://github.com/nix-community/home-manager) for user config. App lists: shared packages in `config/apps/base.json`, per-host extras in `config/apps/hosts/<hostname>.json` (merged at build time). Profile settings in `config/user.json`, git in `config/git.json`; per-machine settings (including `adminUsername`) in `config/hosts/<hostname>.json`.

This template is designed to work standalone **and** as a flake overlay — a private repo can import `homeModules` and `darwinModules` from this flake and extend them with personal config (see [Using as a flake overlay](#using-as-a-flake-overlay)).

**Included:**

- **zsh** as the login shell
- **Fonts**: `config/fonts/base.json` defines `pkgs` (nixpkgs-only), `google` (via `overlays/google-fonts`), and `nerd` (starter ships `meslo-lg`); per-host extras (including optional Homebrew font `casks`) in `config/fonts/hosts/<hostname>.json`
- **Ghostty config** — Nix defaults from `home/themes/default.nix` into `~/.config/ghostty/config.d/nix.conf`; personal overrides in `~/.config/ghostty/local.conf`. Install the Ghostty app yourself (e.g. add a Homebrew cask in apps JSON)
- **[Firefox](https://www.mozilla.org/firefox/)** — backup browser via Homebrew cask with Dark Reader, 1Password, AdGuard AdBlocker, and Privacy Badger; privacy-hardened HM profile defaults; JSON-driven config in `config/firefox/` (see [Firefox (backup browser)](#firefox-backup-browser))
- **btop** with Catppuccin Mocha theme

**User-scope extras** (home-manager):

- **direnv** (with **nix-direnv**)
- **git** / **ssh** (1Password agent) / **gpg** (GPG agent for other uses; **commits sign with SSH** via 1Password — see Caveats)
- **Cursor module** (`home/vscode.nix` / `homeModules.vscode`) — manages Cursor extensions + settings (`package = null`); add `code-cursor` (or install another way) via apps JSON when you want Homebrew to manage the app. Devin (optional cask) shares the **settings** pipeline only; `commonBase` is the Cursor extension set (VS Code HM disabled but reinstate-ready)
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
| `lib/`                                 | JSON loaders (`loadSharedConfig`, `loadHostConfig`, …)                                                                                                                                    |
| `config/apps/base.json`                | Apps on every host: `system`, `user`, `taps`, `brews`, `casks`, `mas`                                                                                                                     |
| `config/apps/hosts/<name>.json`        | Per-host extras only (additive merge; lists deduplicated). Required for each host in `config/hosts.json`.                                                                                 |
| `config/fonts/base.json`               | Fonts on every host: `pkgs`, `google`, `nerd` (optional `casks` per host in `config/fonts/hosts/<name>.json`)                                                                             |
| `config/fonts/hosts/<name>.json`       | Per-host font extras only (additive merge). Required for each host in `config/hosts.json`.                                                                                                |
| `config/firefox/base.json`             | Firefox backup browser defaults: `profileName`, `settings` (about:config), `extensions.nix` (AMO slugs)                                                                                   |
| `config/firefox/hosts/<name>.json`     | Per-host Firefox overrides (additive merge for extensions, per-key override for settings). Required for each host in `config/hosts.json`.                                                 |
| `config/android/base.json`             | Shared Android SDK defaults (no `enable` key). Optional for overlays that omit Android.                                                                                                   |
| `config/android/hosts/<name>.json`     | Per-host Android opt-in (`enable`) and overrides. Required when base exists.                                                                                                              |
| `config/schema/*.schema.json`          | JSON Schema for hosts, apps, fonts, Firefox, Android (validated by `scripts/validate-host-json.sh`; override with `SCHEMA_ROOT`)                                                          |
| `config/user.json` / `config/git.json` | Shared profile (name, email, GPG) and git settings. Copy `config/user.json.example` to `config/user.json`, edit, and **git add** it (flakes only see tracked files). |
| `config/hosts.json`                    | Hostnames to build (`hosts`, `defaultHost`)                                                                                                                                               |
| `config/hosts/<name>.json`             | Per-machine settings: `adminUsername`, `machineType` (`laptop` \| `macmini`), Homebrew, nix trusted/allowed users, optional `extraSessionPaths`, `knownNetworkServices`, power / SoftwareUpdate overrides |
| `docs/MACOS-27.md`                     | Major macOS / channel upgrade checklist                                                                                                                                                   |
| `docs/SECURITY.md`                     | Trust model, post-install checklist (FileVault/Gatekeeper), secrets, Homebrew, Firefox, CI pinning                                                                                        |
| `overlays/google-fonts/`               | Nix overlay packaging fonts from [google/fonts](https://github.com/google/fonts)                                                                                                          |
| `scripts/new-host.sh`                  | Interactive scaffold for a new host (also `nix run '.#new-host'`)                                                                                                                         |
| `darwin/`                              | nix-darwin modules (`configuration.nix`, `system.nix`)                                                                                                                                    |
| `home/`                                | home-manager modules (`git.nix`, `vim.nix`, `vscode.nix`, `zsh.nix`, `firefox.nix`, `android.nix`, …)                                                                                      |

**Pinned inputs** (see `flake.lock`):

- `nixpkgs` — `nixos-26.05` (single package set for system and home-manager)
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
nix fmt              # format *.nix (uses flake formatter)
nix fmt $(git ls-files '*.nix') -- --check   # verify formatting (CI uses this)
nix run '.#check'    # runs nix flake check (may warn once if repo is dirty)
nix flake check      # direct; use after committing for quiet output
nix flake update     # bump input pins (commit flake.lock when intentional)
nix run '.#changelog'           # nix-darwin stateVersion notes (defaultHost)
nix run '.#changelog' -- example-mac  # same for a specific host
```

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

SSH and git signing use the 1Password agent / `op-ssh-sign` (see Caveats), which needs the **1Password app**, not only the CLI.

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
| `config/firefox/hosts/<name>.json`  | Per-host overrides (additive merge for extension lists, per-key override for settings). Use `{}` if none. |
| `config/schema/firefox.schema.json` | JSON Schema for the Firefox config (validated by `scripts/validate-host-json.sh`)                         |

**How extensions are installed:**

By default (`my.firefox.extensionInstallMode = "policy"`), add-ons are installed via `programs.firefox.policies.ExtensionSettings` (`force_installed` + pinned AMO **file** URLs from the catalog / `manual` entries). home-manager writes these into Darwin defaults (`org.mozilla.firefox.plist`) so Homebrew Firefox applies them. First launch (or restart after switch) needs network so Firefox can fetch the XPIs. Extension auto-update prefs stay off — bump catalog/manual URLs intentionally to change versions (see [docs/SECURITY.md](docs/SECURITY.md)).

Official Firefox builds ignore new profile-directory XPI sideloads, so the old `home.file` symlink path is not the default.

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

Consumers can add custom XPI add-ons via `my.firefox.manualExtensions` (or the JSON `extensions.manual` array). Each entry requires `name`, `addonId`, `url`, and `hash` (SRI format; `hash` is required by schema and used if you opt into sideload mode):

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
| `homeModules.vscode`             | Cursor editor module (shared `commonBase`; VS Code HM path disabled)                                                                                                      |
| `homeModules.zsh`                | Just the zsh config module                                                                                                                                                |
| `homeModules.editor`             | Editor tooling (Prettier + ESLint from flake-pinned config repos)                                                                                                         |
| `homeModules.firefox`            | Just the Firefox backup browser module (opt-in via `my.firefox.enable`)                                                                                                   |
| `homeModules.android`            | Just the Android SDK module (opt-in via `my.android.enable` / host JSON)                                                                                                  |
| `darwinModules.default`          | Combined configuration.nix + system.nix                                                                                                                                   |
| `darwinModules.configuration`    | Just the nix-darwin system config module                                                                                                                                  |
| `darwinModules.system`           | Just the macOS defaults/networking module                                                                                                                                 |
| `lib`                            | Config loaders (`loadHostsManifest`, `loadSharedConfig`, `loadUserConfig`, `loadAppConfig`, `loadHostConfig`, `loadRawHostConfig`, `loadFontConfig`, `loadFirefoxConfig`, `loadAndroidConfig`) |
| `editorTooling`                  | Built editor tooling attrset, or `{}` when inputs are absent                                                                                                              |
| `mkWritableCopyActivation`       | Helper for writable-copy activation scripts (pass into `darwinConfigurationsBuilder`)                                                                                     |
| `darwinConfigurationsBuilder`    | The `darwin/default.nix` function — call with your own config loaders and `extraHomeModules`                                                                              |
| `overlayFlakeOutputs`            | Shared `apps` / `checks` / `formatter` / `devShell` helper used by this flake                                                                                              |
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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

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

**Manual overlay example (module-level):**

For overlays that need full control over `darwinSystem` modules:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    darwin.url = "github:LnL7/nix-darwin/nix-darwin-26.05";
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

Set to **6** in code (`darwin/system.nix`). Check the changelog before bumping:

```sh
nix run '.#changelog'
```

### `home.stateVersion` (home-manager)

Should match the flake's home-manager release (currently **26.05**). Bump only when upgrading the `home-manager` input and after reading [HM release notes](https://nix-community.github.io/home-manager/release-notes.xhtml).

### Home Manager file conflicts

If activation stops because an existing file would be "clobbered", `home-manager.backupFileExtension` is set to `hm-bak` in `darwin/default.nix` so the existing file is renamed before Home Manager installs its version.

### Secrets

Do not commit API tokens, private keys, or `.env` files (see `.gitignore`). Track `config/user.json` in git — it holds public identity (name, email, GPG key id, SSH **public** signing key), not private key material. Copy from `config/user.json.example`, edit, and `git add` it; overlays fail closed if it is missing from the flake store copy. Prefer `op run --env-file=.env` for shell secrets (see [1Password secret loading](#1password-secret-loading) and [docs/SECURITY.md](docs/SECURITY.md)); do not put 1Password item ids in Nix. For encrypted repo secrets, consider [sops-nix](https://github.com/Mic92/sops-nix) or [agenix](https://github.com/ryantm/agenix).

### Periodic updates and macOS upgrades

See [docs/MACOS-27.md](docs/MACOS-27.md) for the weekly lockfile cadence, Dependabot Actions pins, and the checklist for Apple major releases / Nix channel bumps. Channel bumps are **manual** `flake.nix` ref edits — `nix flake update` alone stays on `*-26.05`.

### Pre-commit (optional)

Install [pre-commit](https://pre-commit.com/) locally for fast feedback before push:

```sh
pre-commit install
pre-commit run --all-files
```

Hooks (see `.pre-commit-config.yaml`): **`nix fmt`** (writes, then `--check`) on `*.nix`, `shellcheck` on `scripts/*.sh` and `build-darwin.sh`. Agents must also run `nix fmt` before committing Nix (see [AGENTS.md](AGENTS.md) and `.cursor/rules/nixfmt.mdc`). Not required for CI beyond the flake `fmt` job.

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

- **Evaluate flake** — verifies every host in `config/hosts.json` has matching JSON under `config/hosts/`, `config/apps/hosts/`, `config/fonts/hosts/`, and (when present) Firefox/Android hosts; validates against `config/schema/*.schema.json`; then `nix flake check --no-build` (includes app/font package name and Firefox slug validation).
- **Nix formatting** — dedicated job: `nix fmt -- --check` on all tracked `*.nix` files.
- **Per-host build** (`.github/workflows/flake.yml`) — matrix derived from `config/hosts.json`: builds `.#checks.aarch64-darwin.<host>`.
- **shellcheck** — `scripts/*.sh` and `build-darwin.sh` on Ubuntu.
- **Update flake inputs** (`.github/workflows/update-flake.yml`) — weekly (and manual) `nix flake update` with eval check and an automated PR; full host builds run on the PR via `flake.yml`.
- **Dependabot** (`.github/dependabot.yml`) — weekly GitHub Actions dependency updates (workflows pin Actions by commit SHA).

Linux runners cannot build this flake; CI must stay on macOS.

---

## Caveats

- **Apple Silicon only.** The flake hardcodes `system = "aarch64-darwin"` permanently. Intel Macs (`x86_64-darwin`) are out of scope.
- Only brews/casks listed in the merged app and font configs are installed when `homebrewCleanup` is `uninstall` or `zap`; extras are removed on switch.
- **mas** = Mac App Store apps (IDs in `config/apps/base.json` and/or `config/apps/hosts/<host>.json`). Find existing app IDs with [mas-cli](https://github.com/mas-cli/mas).
- [Trusted users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-trusted-users) are the current user plus any listed in the host JSON. Default: `[<username>]`. Never use `"*"`.
- [Allowed users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-allowed-users) are the current user plus config. Default for new hosts: `[adminUsername]`. Never use `"*"`.
- Guest login is disabled; Remote Login (`services.openssh`) is off; screensaver requires a password immediately. FileVault and Gatekeeper stay **out of band** — see [docs/SECURITY.md](docs/SECURITY.md).
- `EDITOR=nvim` and `VISUAL=cursor` are intentional (terminal vs GUI default). `VISUAL` is forced in `home.sessionVariables` so it wins over neovim `defaultEditor`.
- SSH `HashKnownHosts` is enabled in home-manager.
- Git signs commits with **SSH** via 1Password (`gpg.format = "ssh"` and `op-ssh-sign`), not classic GPG. Set `defaultSigningKey` in `config/user.json`. Adjust `home/git.nix` if you do not want signing.
- **Cursor extension pins:** Cursor's VS Code engine lags upstream. **Nix IDE**, **Python Environments**, and **Pylance** are installed for Cursor via `cursor --install-extension` on home-manager activation (HM symlinks are not enough). They will not appear in marketplace search; check **Installed** or `cursor --list-extensions | grep -E 'nix-ide|python-envs|pylance'`. If missing after switch, run manually: `cursor --install-extension jnoortheen.nix-ide --force && cursor --install-extension ms-python.vscode-python-envs --force && cursor --install-extension ms-python.vscode-pylance --force`, then reload the window.
- **Unfree:** editors/`commonBase` stay free (Git Graph removed, not installed). `nixpkgs.config.allowUnfree = true` is still required for `_1password-cli`, Android SDK, and editor/VS Code ecosystem packages overlays may need — predicate allowlists keep breaking as new unfree attrs appear.
- **CloudFormation YAML:** Prettier is the sole YAML formatter. Prefer `Fn::` long form (`Fn::Ref`, `Fn::Sub`, …). CFN short tags (`!Ref`, `!Sub`, …) are not Prettier-safe without a dedicated CFN extension (not shipped here).
- **Leaving VS Code:** this module no longer manages Code. After switching, remove leftover Nix-managed VS Code extensions under `~/.vscode/extensions` (and any unused Code app) if you still see old HM symlinks.
