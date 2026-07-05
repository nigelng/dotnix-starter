# dotnix-starter

Nix flake template for macOS (Apple Silicon): [nix-darwin](https://github.com/LnL7/nix-darwin) for the system and [home-manager](https://github.com/nix-community/home-manager) for user config. App lists: shared packages in `config/apps/base.json`, per-host extras in `config/apps/hosts/<hostname>.json` (merged at build time). Profile settings in `config/user.json`, git in `config/git.json`; per-machine settings (including `adminUsername`) in `config/hosts/<hostname>.json`.

This template is designed to work standalone **and** as a flake overlay — a private repo can import `homeModules` and `darwinModules` from this flake and extend them with personal config (see [Using as a flake overlay](#using-as-a-flake-overlay)).

**Included:**

- **zsh** as the login shell
- **Fonts**: `config/fonts/base.json` defines `pkgs` (nixpkgs-only, e.g. Font Awesome), `google` (e.g. Fira, Inter via `overlays/google-fonts`), and `nerd` (e.g. JetBrains Mono); per-host extras (including optional Homebrew font `casks`) in `config/fonts/hosts/<hostname>.json`
- **[Ghostty](https://ghostty.org)** — Homebrew cask (`config/apps/base.json`); terminal font via nerd-font casks or pkgs in `config/fonts/`; Nix defaults generated from `home/themes/default.nix` into `~/.config/ghostty/config.d/nix.conf`; personal overrides in `~/.config/ghostty/local.conf` (see `home/config_files/ghostty_local.conf.example`)
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
| `config/user.json` / `config/git.json` | Shared profile (name, email, GPG) and git settings. Copy `config/user.json.example` to `config/user.json`.                                                                                |
| `config/hosts.json`                    | Hostnames to build (`hosts`, `defaultHost`)                                                                                                                                               |
| `config/hosts/<name>.json`             | Per-machine settings: `adminUsername`, `machineType` (`laptop` \| `macmini`), Homebrew, nix trusted/allowed users, optional `extraSessionPaths`, optional `knownNetworkServices` override |
| `overlays/google-fonts/`               | Nix overlay packaging fonts from [google/fonts](https://github.com/google/fonts)                                                                                                          |
| `scripts/new-host.sh`                  | Interactive scaffold for a new host (also `nix run '.#new-host'`)                                                                                                                         |
| `darwin/`                              | nix-darwin modules (`configuration.nix`, `system.nix`)                                                                                                                                    |
| `home/`                                | home-manager modules (`git.nix`, `vim.nix`, `vscode.nix`, `zsh.nix`, …)                                                                                                                   |

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

1. Run `nix run '.#new-host'` (or copy an existing host with `--copy-from`) to scaffold JSON under `config/hosts/`, `config/apps/hosts/`, and `config/fonts/hosts/`, and append the id to `config/hosts.json`.
2. Edit the new host JSON files (`adminUsername`, `homebrewPrefix`, `homebrewCleanup`, host-only apps/fonts).
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

---

## Using as a flake overlay

This template exposes `homeModules` and `darwinModules` as flake outputs so a private overlay repo can import and extend them.

**Available modules:**

| Output                        | Description                                                           |
| ----------------------------- | --------------------------------------------------------------------- |
| `homeModules.default`         | Full home-manager module tree (imports git, vim, vscode, zsh, editor) |
| `homeModules.git`             | Just the git/gh config module                                         |
| `homeModules.vim`             | Just the neovim config module                                         |
| `homeModules.vscode`          | Just the VS Code/Cursor config module                                 |
| `homeModules.zsh`             | Just the zsh config module                                            |
| `homeModules.editor`          | Editor tooling (Prettier + ESLint from flake-pinned config repos)     |
| `darwinModules.default`       | Combined configuration.nix + system.nix                               |
| `darwinModules.configuration` | Just the nix-darwin system config module                              |
| `darwinModules.system`        | Just the macOS defaults/networking module                             |

Note: `homeModules.editor` is exported and wired to the flake-pinned `prettier-config` and `eslint-config` inputs. Overlay repos that don't provide those inputs should omit `homeModules.editor` from their imports.

**Example overlay flake:**

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

      editorTooling = import ./lib/editor-tooling.nix {
        inherit pkgs lib;
        prettier-config = inputs.prettier-config;
        eslint-config = inputs.eslint-config;
      };
    in {
      darwinConfigurations.my-mac = darwin.lib.darwinSystem {
        inherit system;
        modules = [
          dotnix-starter.darwinModules.default
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit editorTooling; };
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

### Faster CI (optional)

To cache Nix store paths on GitHub Actions, add a [Cachix](https://www.cachix.org) cache and set `CACHIX_AUTH_TOKEN` in repo secrets, then extend `.github/workflows/flake.yml` with `cachix/cachix-action`.

---

## CI

GitHub Actions on `macos-14` (Apple Silicon):

- **Evaluate flake** — verifies every host in `config/hosts.json` has matching JSON under `config/hosts/`, `config/apps/hosts/`, and `config/fonts/hosts/`; validates each host JSON against `config/schema/host.schema.json`; then `nix flake check --no-build` (includes app/font package name validation).
- **Nix formatting** — dedicated job: `nix fmt -- --check` on all tracked `*.nix` files.
- **Per-host build** (`.github/workflows/flake.yml`) — matrix derived from `config/hosts.json`: builds `.#checks.aarch64-darwin.<host>`.
- **shellcheck** — `scripts/*.sh` and `build-darwin.sh` on Ubuntu.
- **Update flake inputs** (`.github/workflows/update-flake.yml`) — weekly (and manual) `nix flake update` with an automated PR when the lockfile changes.
- **Dependabot** (`.github/dependabot.yml`) — weekly GitHub Actions dependency updates.

Linux runners cannot build this flake; CI must stay on macOS.

---

## Caveats

- Only brews/casks listed in the merged app and font configs are installed when `homebrewCleanup` is `uninstall` or `zap`; extras are removed on switch.
- **mas** = Mac App Store apps (IDs in `config/apps/base.json` and/or `config/apps/hosts/<host>.json`). Find existing app IDs with [mas-cli](https://github.com/mas-cli/mas).
- [Trusted users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-trusted-users) are the current user plus any listed in the host JSON. Default: `[<username>]`.
- [Allowed users](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-allowed-users) are the current user plus config. Default for new hosts: `[adminUsername]`.
- `EDITOR=nvim` and `VISUAL=code` in zsh are intentional (terminal vs GUI default).
- SSH `HashKnownHosts` is enabled in home-manager.
- Git is configured to [sign commits](https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work) with [GPG](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key). Remove or adjust if you don't need signing.
- **Cursor extension pins:** Cursor's VS Code engine lags upstream. **Nix IDE** and **Python Environments** are installed for Cursor via `cursor --install-extension` on home-manager activation (HM symlinks are not enough). They will not appear in marketplace search; check **Installed** or `cursor --list-extensions | grep -E 'nix-ide|python-envs'`. If missing after switch, run manually: `cursor --install-extension jnoortheen.nix-ide --force && cursor --install-extension ms-python.vscode-python-envs --force`, then reload the window.
