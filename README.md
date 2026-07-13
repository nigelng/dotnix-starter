# dotnix-starter

[![Flake check](https://github.com/nigelng/dotnix-starter/actions/workflows/flake.yml/badge.svg)](https://github.com/nigelng/dotnix-starter/actions/workflows/flake.yml)

Nix flake template for macOS (Apple Silicon): [nix-darwin](https://github.com/LnL7/nix-darwin) for the system and [home-manager](https://github.com/nix-community/home-manager) for user config. App lists: shared packages in `config/apps/base.json`, per-host extras in `config/apps/hosts/<hostname>.json` (merged at build time). Profile settings in `config/user.json`, git in `config/git.json`; per-machine settings (including `adminUsername`) in `config/hosts/<hostname>.json`.

This template is designed to work standalone **and** as a flake overlay — a private repo can import `homeModules` and `darwinModules` from this flake and extend them with personal config (see [Using as a flake overlay](#using-as-a-flake-overlay)).

**Included:**

- **zsh** as the login shell
- **Fonts**: `config/fonts/base.json` defines `pkgs` (nixpkgs-only, e.g. Font Awesome), `google` (e.g. Fira, Inter via `overlays/google-fonts`), and `nerd` (e.g. JetBrains Mono); per-host extras (including optional Homebrew font `casks`) in `config/fonts/hosts/<hostname>.json`
- **[Ghostty](https://ghostty.org)** — Homebrew cask (`config/apps/base.json`); terminal font via nerd-font casks or pkgs in `config/fonts/`; Nix defaults generated from `home/themes/default.nix` into `~/.config/ghostty/config.d/nix.conf`; personal overrides in `~/.config/ghostty/local.conf` (see `home/config_files/ghostty_local.conf.example`)
- **[Firefox](https://www.mozilla.org/firefox/)** — backup browser via `firefox-bin` with Dark Reader, 1Password, and AdGuard AdBlocker; privacy-hardened defaults (telemetry opt-out, DNS-over-HTTPS via Cloudflare, fingerprinting resistance); JSON-driven config in `config/firefox/` (see [Firefox (backup browser)](#firefox-backup-browser))
- **btop** with Catppuccin Mocha theme

**User-scope extras** (home-manager):

- **direnv** (with **nix-direnv**)
- **git** / **ssh** (1Password agent) / **gpg**
- **Visual Studio Code** and **Cursor** (`vscode`, `code-cursor` via nix-darwin; extensions and settings via `home/vscode.nix`)
- **[eza](https://eza.rocks)** (modern `ls` replacement)
- **[fzf](https://github.com/junegunn/fzf)** (Catppuccin Mocha colors)
- **[zoxide](https://github.com/ajeetdsouza/zoxide)**
- **[gh](https://cli.github.com)** with extensions:
  - [gh-eco](https://github.com/jrnxf/gh-eco)
  - [gh-dash](https://github.com/dlvhdr/gh-dash)
  - [gh-markdown-preview](https://github.com/yusukebe/gh-markdown-preview)

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
| `config/firefox/base.json`             | Firefox backup browser defaults: `package`, `profileName`, `settings` (about:config), `extensions.nix` (AMO slugs)                                                                        |
| `config/firefox/hosts/<name>.json`     | Per-host Firefox overrides (additive merge for extensions, per-key override for settings). Required for each host in `config/hosts.json`.                                                 |
| `config/user.json` / `config/git.json` | Shared profile (name, email, GPG) and git settings. Copy `config/user.json.example` to `config/user.json`.                                                                                |
| `config/hosts.json`                    | Hostnames to build (`hosts`, `defaultHost`)                                                                                                                                               |
| `config/hosts/<name>.json`             | Per-machine settings: `adminUsername`, `machineType` (`laptop` \| `macmini`), Homebrew, nix trusted/allowed users, optional `extraSessionPaths`, optional `knownNetworkServices` override |
| `overlays/google-fonts/`               | Nix overlay packaging fonts from [google/fonts](https://github.com/google/fonts)                                                                                                          |
| `scripts/new-host.sh`                  | Interactive scaffold for a new host (also `nix run '.#new-host'`)                                                                                                                         |
| `darwin/`                              | nix-darwin modules (`configuration.nix`, `system.nix`)                                                                                                                                    |
| `home/`                                | home-manager modules (`git.nix`, `vim.nix`, `vscode.nix`, `zsh.nix`, `firefox.nix`, …)                                                                                                    |

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

This template uses [1Password CLI](https://developer.1password.com/docs/cli) for secret management. The `op` CLI is installed as a system package (`_1password-cli` in `config/apps/base.json`).

To load a secret into an environment variable, uncomment the `load_secret` example alias in `home/zsh.nix`:

```sh
# load_secret = "export MY_TOKEN=$(op item get <op-item-id> --reveal --fields label=token)"
```

Replace `<op-item-id>` with your 1Password item ID (find it with `op item list`).

The `config/user.json.example` file also includes a `ghTokenOpItemId` field for storing a 1Password item ID that references a GitHub token — use this pattern to wire up any secret you need at switch time.

See: `home/zsh.nix` (the `load_secret` example alias), `config/user.json.example`.

### Firefox (backup browser)

[Mozilla Firefox](https://www.mozilla.org/firefox/) is installed as a backup browser via `firefox-bin` and home-manager `programs.firefox`. It ships with three AMO add-ons — **Dark Reader**, **1Password**, and **AdGuard AdBlocker** — plus a privacy-hardened profile (telemetry opt-out, DNS-over-HTTPS via Cloudflare, fingerprinting resistance, strict content blocking). The configuration is JSON-driven and extendable by both standalone users and overlay consumers.

**Add-ons installed by default:**

| Add-on            | AMO slug                         | Purpose                 |
| ----------------- | -------------------------------- | ----------------------- |
| Dark Reader       | `darkreader`                     | Dark mode for all sites |
| 1Password         | `onepassword-x-password-manager` | Password manager        |
| AdGuard AdBlocker | `adguard-adblocker`              | Ad/tracker blocking     |

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
| `config/firefox/base.json`          | Default Firefox package, profile name, `settings` (about:config prefs), and `extensions.nix` (AMO slugs)  |
| `config/firefox/hosts/<name>.json`  | Per-host overrides (additive merge for extension lists, per-key override for settings). Use `{}` if none. |
| `config/schema/firefox.schema.json` | JSON Schema for the Firefox config (validated by `scripts/validate-host-json.sh`)                         |

**How extensions are installed:**

By default (`my.firefox.useDeclarativeExtensions = false`), add-ons are installed via `home.file` symlinks (`force = true`) into the Firefox profile's `extensions/` directory. A post-switch activation re-links each XPI and prints `ls -la` of that directory so extensions are restored if Firefox removed them since the last switch. `extensions.autoDisableScopes = 0` is set when add-ons are configured so sideloaded extensions stay enabled.

To use home-manager's declarative extension path instead, set `my.firefox.useDeclarativeExtensions = true` in your overlay config. This wires `programs.firefox.profiles.<name>.extensions.packages` directly.

**Overriding in an overlay:**

The thin overlay path (`darwinConfigurationsBuilder`) includes the Firefox module but disables it by default when `config/firefox/base.json` doesn't exist. To enable Firefox in an overlay, either create `config/firefox/base.json` (which enables it automatically) or set `my.firefox.enable = true` in your `extraHomeModules`:

```nix
home-manager.users.myuser = {
  imports = [ dotnix-starter.homeModules.firefox ];
  my.firefox.enable = true;
  # Override settings (replaces JSON defaults for these keys)
  my.firefox.settings = {
    "browser.startup.homepage" = "https://example.com";
  };
  # Add extra nixpkgs/NUR extension packages
  my.firefox.nixExtensions = [ someAddonPkg ];
  # Use declarative extensions instead of home.file symlinks
  my.firefox.useDeclarativeExtensions = true;
};
```

**Adding non-AMO extensions:**

Consumers can add custom XPI add-ons via `my.firefox.manualExtensions` (or the JSON `extensions.manual` array). Each entry requires `name`, `addonId`, `url`, and `hash` (SRI format):

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

After switching, launch Firefox and open `about:addons` to confirm Dark Reader, 1Password, and AdGuard AdBlocker are installed and enabled. Open `about:config` to verify the settings from `config/firefox/base.json`.

See: `home/firefox.nix`, `home/firefox/addons.nix`, `config/firefox/base.json`.

---

## Using as a flake overlay

This template exposes `homeModules` and `darwinModules` as flake outputs so a private overlay repo can import and extend them. It also exports infrastructure (`lib`, `editorTooling`, `mkWritableCopyActivation`, `darwinConfigurationsBuilder`, `overlays.google-fonts`, `pkgsForValidation`, `validateApps`, `scripts.validateHostJson`) so overlay repos can build `darwinConfigurations` without copying any infrastructure files.

**Available exports:**

| Output                           | Description                                                                                                                                                               |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `homeModules.default`            | Full home-manager module tree (imports git, vim, vscode, zsh, editor)                                                                                                     |
| `homeModules.defaultWithFirefox` | Full home-manager module tree plus the Firefox backup browser module                                                                                                      |
| `homeModules.git`                | Just the git/gh config module                                                                                                                                             |
| `homeModules.vim`                | Just the neovim config module                                                                                                                                             |
| `homeModules.vscode`             | Just the VS Code/Cursor config module                                                                                                                                     |
| `homeModules.zsh`                | Just the zsh config module                                                                                                                                                |
| `homeModules.editor`             | Editor tooling (Prettier + ESLint from flake-pinned config repos)                                                                                                         |
| `homeModules.firefox`            | Just the Firefox backup browser module (opt-in via `my.firefox.enable`)                                                                                                   |
| `darwinModules.default`          | Combined configuration.nix + system.nix                                                                                                                                   |
| `darwinModules.configuration`    | Just the nix-darwin system config module                                                                                                                                  |
| `darwinModules.system`           | Just the macOS defaults/networking module                                                                                                                                 |
| `lib`                            | Config loaders (`loadHostsManifest`, `loadSharedConfig`, `loadUserConfig`, `loadAppConfig`, `loadHostConfig`, `loadRawHostConfig`, `loadFontConfig`, `loadFirefoxConfig`) |
| `editorTooling`                  | Built editor tooling attrset, or `{}` when inputs are absent                                                                                                              |
| `mkWritableCopyActivation`       | Helper for writable-copy activation scripts                                                                                                                               |
| `darwinConfigurationsBuilder`    | The `darwin/default.nix` function — call with your own config loaders and `extraHomeModules`                                                                              |
| `overlays.google-fonts`          | The google-fonts nixpkgs overlay                                                                                                                                          |
| `pkgsForValidation`              | nixpkgs with google-fonts overlay for app/font validation                                                                                                                 |
| `validateApps`                   | App/font validation function for overlay checks                                                                                                                           |
| `scripts.validateHostJson`       | Shell derivation for host JSON schema validation in CI                                                                                                                    |

Note: `homeModules.editor` is exported and wired to the flake-pinned `prettier-config` and `eslint-config` inputs. Overlay repos that don't provide those inputs should omit `homeModules.editor` from their imports.

**Thin overlay example (recommended):**

An overlay repo builds its `darwinConfigurations` using only the starter's exports + its own `config/` JSON and `home/personal.nix` — with zero copied infrastructure files:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    darwin.url = "github:LnL7/nix-darwin/nix-darwin-26.05";
    dotnix-starter.url = "github:nigelng/dotnix-starter";
  };

  outputs = { self, nixpkgs, home-manager, darwin, dotnix-starter, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};

      flakeLib = dotnix-starter.lib;
      flakeRoot = builtins.toString self.outPath;
      manifest = flakeLib.loadHostsManifest flakeRoot;
      shared = flakeLib.loadSharedConfig flakeRoot;
    in {
      darwinConfigurations = dotnix-starter.darwinConfigurationsBuilder {
        inherit (nixpkgs) lib pkgs;
        inherit home-manager darwin system;
        inherit (shared) gitConfig;
        editorTooling = dotnix-starter.editorTooling;
        hosts = manifest.hosts;
        loadHostConfig = flakeLib.loadHostConfig flakeRoot;
        loadAppConfig = flakeLib.loadAppConfig flakeRoot;
        loadFontConfig = flakeLib.loadFontConfig flakeRoot;
        loadFirefoxConfig = flakeLib.loadFirefoxConfig flakeRoot;
        loadUserConfig = flakeLib.loadUserConfig flakeRoot;
        extraHomeModules = [ ./home/personal.nix ];
      };

      checks.${system} =
        assert
          (dotnix-starter.validateApps {
            inherit lib;
            pkgs = dotnix-starter.pkgsForValidation;
            hosts = manifest.hosts;
            loadAppConfig = flakeLib.loadAppConfig flakeRoot;
            loadFontConfig = flakeLib.loadFontConfig flakeRoot;
            loadFirefoxConfig = flakeLib.loadFirefoxConfig flakeRoot;
          }) == { };
        lib.genAttrs manifest.hosts (host: self.darwinConfigurations.${host}.system);
    };
}
```

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

Use `check` or `none` on a shared machine if others install brews outside this flake.

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

Do not commit API tokens, private keys, or `.env` files (see `.gitignore`). Signing keys and public git metadata in `config/user.json` / `config/git.json` are fine. For encrypted repo secrets, consider [sops-nix](https://github.com/Mic92/sops-nix) or [agenix](https://github.com/ryantm/agenix). Shell tokens are loaded via 1Password (see [1Password secret loading](#1password-secret-loading)).

### Pre-commit (optional)

Install [pre-commit](https://pre-commit.com/) locally for fast feedback before push:

```sh
pre-commit install
pre-commit run --all-files
```

Hooks (see `.pre-commit-config.yaml`): `nix fmt --check` on `*.nix`, `shellcheck` on `scripts/*.sh` and `build-darwin.sh`. Not required for CI.

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

### Faster CI (optional)

To cache Nix store paths on GitHub Actions, add a [Cachix](https://www.cachix.org) cache and set `CACHIX_AUTH_TOKEN` in repo secrets, then extend `.github/workflows/flake.yml` with `cachix/cachix-action`.

---

## CI

GitHub Actions on `macos-14` (Apple Silicon):

- **Evaluate flake** — verifies every host in `config/hosts.json` has matching JSON under `config/hosts/`, `config/apps/hosts/`, `config/fonts/hosts/`, and `config/firefox/hosts/`; validates each host JSON against `config/schema/host.schema.json` and Firefox JSON against `config/schema/firefox.schema.json`; then `nix flake check --no-build` (includes app/font package name validation).
- **Nix formatting** — dedicated job: `nix fmt -- --check` on all tracked `*.nix` files.
- **Per-host build** (`.github/workflows/flake.yml`) — matrix derived from `config/hosts.json`: builds `.#checks.aarch64-darwin.<host>`.
- **shellcheck** — `scripts/*.sh` and `build-darwin.sh` on Ubuntu.
- **Update flake inputs** (`.github/workflows/update-flake.yml`) — weekly (and manual) `nix flake update` with an automated PR when the lockfile changes.
- **Dependabot** (`.github/dependabot.yml`) — weekly GitHub Actions dependency updates.

Linux runners cannot build this flake; CI must stay on macOS.

---

## Caveats

- **Apple Silicon only.** The flake hardcodes `system = "aarch64-darwin"`. Intel Macs (`x86_64-darwin`) are not supported.
- Only brews/casks listed in the merged app and font configs are installed when `homebrewCleanup` is `uninstall` or `zap`; extras are removed on switch.
- **mas** = Mac App Store apps (IDs in `config/apps/base.json` and/or `config/apps/hosts/<host>.json`). Find existing app IDs with [mas-cli](https://github.com/mas-cli/mas).
- [Trusted users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-trusted-users) are the current user plus any listed in the host JSON. Default: `[<username>]`.
- [Allowed users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-allowed-users) are the current user plus config. Default for new hosts: `[adminUsername]`.
- `EDITOR=nvim` and `VISUAL=code` in zsh are intentional (terminal vs GUI default).
- SSH `HashKnownHosts` is enabled in home-manager.
- Git is configured to [sign commits](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work) with [GPG](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key). Remove or adjust if you don't need signing.
- **Cursor extension pins:** Cursor's VS Code engine lags upstream. **Nix IDE** and **Python Environments** are installed for Cursor via `cursor --install-extension` on home-manager activation (HM symlinks are not enough). They will not appear in marketplace search; check **Installed** or `cursor --list-extensions | grep -E 'nix-ide|python-envs'`. If missing after switch, run manually: `cursor --install-extension jnoortheen.nix-ide --force && cursor --install-extension ms-python.vscode-python-envs --force`, then reload the window.
