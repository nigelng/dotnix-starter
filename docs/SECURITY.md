# Security notes

This template is a starter for personal Apple Silicon Macs. Defaults favor a working developer setup; adjust for stricter threat models.

## Nix trust

- The macOS admin (`adminUsername`) is always a **trusted-user** (plus any names in host JSON `trustedUsers`).
- Trusted users can add substituters / override trust boundaries without a password prompt.
- Prefer empty `trustedUsers` and explicit `allowedUsers`. **Never** set `"*"` in either list.
- No third-party binary caches are configured in-repo. Add substituters only when you trust the cache keys.

## Secrets

- `config/user.json` is gitignored; copy from `config/user.json.example`.
- SSH uses the 1Password agent; git commit signing uses SSH via `op-ssh-sign` (`gpg.format = "ssh"`), not a private key in the repo.
- Prefer short-lived injection with `op run` over exporting tokens into the shell environment.
- The commented `load_secret` alias in `home/zsh.nix` puts secrets in process environment if enabled — avoid for long-lived tokens.
- Install `_1password-cli` via apps JSON if you use `op` on the CLI.

## Homebrew

- `onActivation.autoUpdate = true` refreshes Homebrew indexes on switch; `upgrade = false` limits surprise upgrades.
- `homebrewCleanup: "zap"` is destructive (removes undeclared formulae/casks and zaps cask files). Prefer `"check"` or `"none"` on shared machines. The example host uses `"check"`.
- Non-official tap casks require a fully-qualified name via `trustedCasks` (per-cask trust, not whole-tap trust).

## Firefox

- Add-ons are content-addressed (`fetchFirefoxAddon` + sha256 in `home/firefox/addons.nix`). Auto-update prefs are off so CVE fixes need intentional hash bumps.
- Default install path sideloads XPIs and sets `extensions.autoDisableScopes = 0` so they stay enabled. Prefer `my.firefox.useDeclarativeExtensions = true` for a stricter trust model.
- `extensions.manual` accepts arbitrary URL + hash — treat host JSON as trusted input.
- DoH mode `2` falls back to system DNS; set `network.trr.mode` to `3` for DoH-only.

## Editors

- VS Code / Cursor default `security.workspace.trust.untrustedFiles` is `"prompt"`.
- Some Cursor extensions install via `cursor --install-extension` at switch time (marketplace builds are not content-addressed like Nix store paths).

## CI / supply chain

- Workflows pin Actions by **commit SHA** (version in a comment). Dependabot still opens weekly bumps for `github-actions`.
- `flake.yml` uses least-privilege `permissions: contents: read`.
- Release / update-flake workflows need write permissions (or `WORKFLOW_PAT`); scope the PAT tightly and review ruleset exemptions.

## System defaults

- Application firewall + stealth mode are enabled.
- Touch ID / Watch ID for sudo are enabled for convenience — disable in `darwin/system.nix` if that is too trustful for your environment.
- FileVault, Gatekeeper, and firmware password are not managed here; enable them out of band if required.

See also [MACOS-27.md](MACOS-27.md) for major OS upgrade guidance.
