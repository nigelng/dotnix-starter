# Security notes

This template is a starter for personal Apple Silicon Macs. Defaults favor a working developer setup; adjust for stricter threat models.

## Post-install checklist (out of band)

nix-darwin does **not** manage disk encryption or Gatekeeper assessment policy. Do these once per Mac (or via MDM):

1. **FileVault** — System Settings → Privacy & Security → FileVault → Turn On. Store the recovery key in 1Password (or your org’s escrow). Confirm with `fdesetup status`.
2. **Gatekeeper** — leave at the macOS default (App Store and identified developers). Do not run `spctl --master-disable`. Avoid managing Gatekeeper from this flake.
3. **Startup Security** (Apple Silicon) — Recovery → Startup Security Utility: Full Security when possible.
4. **Sharing** — System Settings → General → Sharing: leave Remote Login / Screen Sharing / File Sharing **off** unless you need them. This flake sets `services.openssh.enable = false` so Remote Login stays off on switch.
5. **Login** — disable automatic login in System Settings if it was ever enabled (nix-darwin cannot reliably clear an existing auto-login). Guest account is disabled declaratively (`loginwindow.GuestEnabled = false`).
6. **Lock screen** — confirm password is required immediately after sleep/screensaver (flake sets screensaver prefs; verify in System Settings if behavior drifts).
7. **SIP / Lockdown Mode** — leave SIP enabled; enable Lockdown Mode only if your threat model needs it (per Apple Account, not via this flake).
8. **Firmware password** — not applicable on Apple Silicon (this template targets Apple Silicon only).

## Declarative defaults (this flake)

| Control | Setting | Notes |
| ------- | ------- | ----- |
| Application firewall | on + stealth | `allowSigned` / `allowSignedApp` set explicitly |
| Guest login | off | `system.defaults.loginwindow.GuestEnabled = false` |
| Screensaver password | on, delay 0 | Verify after major macOS upgrades |
| Remote Login (sshd) | off | `services.openssh.enable = false`; set `true` in an overlay if needed |
| Touch ID / Watch ID sudo | on | Disable in `darwin/system.nix` for a stricter local threat model |
| Auto macOS updates | host JSON | Prefer `automaticallyInstallMacOSUpdates: false` before major OS betas ([MACOS-27.md](MACOS-27.md)) |

**Not managed here (by design):** FileVault, Gatekeeper/`spctl`, SIP, Lockdown Mode, firmware password, custom `pf` rules, full Software Update MDM/DDM policy.

## Nix trust

- The macOS admin (`adminUsername`) is always a **trusted-user** (plus any names in host JSON `trustedUsers`).
- Trusted users can add substituters / override trust boundaries without a password prompt.
- Prefer empty `trustedUsers` and explicit `allowedUsers`. **Never** set `"*"` in either list.
- **User-list rule:** no entry in `trustedUsers`, `allowedUsers` or `adminUsername` may contain `*`, whitespace or a newline (these are rendered unescaped into `nix.conf`, so a space or newline would inject extra users or settings). It is enforced twice: `config/schema/host.schema.json` rejects the entry in CI/`validate-host-json`, and `darwin/configuration.nix` asserts it over the **final** `nix.settings` `trusted-users`, `allowed-users`, `extra-trusted-users` and `extra-allowed-users` (including values set by overlay loaders or `extraDarwinModules`). Free-form `nix.extraOptions` is not inspected, so do not set user lists there.
- `@group` entries (for example `@staff`) are still permitted and grant trust to every member of that group; list them deliberately.
- CI uses the free public **`dotnix-starter`** [Cachix](https://www.cachix.org) substituter (see README). Add other substituters only when you trust the cache keys.

## Secrets

- Track `config/user.json` in git (name, email, GPG key id, SSH public signing key). Copy from `config/user.json.example`, edit, and `git add` — flakes only see tracked files. Overlays fail closed if it is missing; the starter may pass `allowExample = true` for CI.
- Do not put API tokens, private keys, or 1Password item ids in Nix or in `user.json`.
- SSH uses the 1Password agent, and git commit/tag signing uses SSH via `op-ssh-sign` (`gpg.format = "ssh"`), only when `my.onePassword.enable` is true (default: the `1password` or `1password@beta` cask is listed). Otherwise there is no `IdentityAgent` and commits are unsigned. Either way, no private key is in the repo.
- Prefer short-lived injection with `op run --env-file=.env` over exporting tokens into the shell environment.
- The commented `load_secret` alias in `home/zsh.nix` puts secrets in process environment if enabled — avoid for long-lived tokens.
- Install `_1password-cli` via apps JSON if you use `op` on the CLI. The CLI alone does not enable the agent or signing; set `my.onePassword.enable = true` if the 1Password app is installed outside the casks list.

## Homebrew

- `onActivation.autoUpdate = true` refreshes Homebrew indexes on switch; `upgrade = false` limits surprise upgrades.
- `homebrewCleanup: "zap"` is destructive (removes undeclared formulae/casks and zaps cask files). Prefer `"check"` or `"none"` on shared machines. The example host uses `"check"`.
- Non-official tap casks require a fully-qualified name via `trustedCasks` (per-cask trust, not whole-tap trust).

## Firefox

- The Firefox **app** comes from the Homebrew `firefox` cask only. home-manager never installs Firefox from nixpkgs (`programs.firefox.package = null` always).
- Default add-ons use enterprise `ExtensionSettings` (`force_installed`) with **pinned** AMO file URLs from the catalog (`home/firefox/addons-pins.json`, read by `home/firefox/addons.nix`) and `extensions.manual`. Firefox fetches Mozilla-signed XPIs at first launch or after policy apply (HTTPS + AMO + Mozilla signing).
- The curated catalog may include optional AMO slugs beyond the default `extensions.nix` set (e.g. `adguard-browser-assistant` for AdGuard desktop users). Same pin/bump rules apply; overlays opt in via JSON slugs — do not ship conflicting AdGuard AdBlocker + Browser Assistant together.
- **Trust gap vs Nix store:** policy install does **not** verify sha256 at `nix switch`. Mitigations: pin file URLs in git, keep `extensions.update.enabled` / `autoUpdateDefault` false, refresh catalog pins through the weekly reviewed PR (see [Weekly pin refresh](#weekly-pin-refresh)), and bump `manual` URLs intentionally for CVE fixes.
- Do **not** duplicate starter `addonId`s in overlay `ExtensionSettings` — starter owns the force-installed list from JSON; overlays should use `extensions.nix` slugs or `manual` entries.
- `extensions.manual` accepts an arbitrary URL + hash — treat host JSON as trusted input (a malicious URL compromises the profile). URLs must be `https://`: `config/schema/firefox.schema.json` rejects other schemes and `home/firefox.nix` asserts the same for `my.firefox.manualExtensions` set from Nix. The rule covers only `extensions.manual` / `my.firefox.manualExtensions`. Direct `programs.firefox.policies` settings (e.g. `ExtensionSettings.<id>.install_url`) and profile extensions set from other modules are not inspected. Don't add add-ons that way, or keep their URLs `https://` yourself.
- Profile-dir XPI sideload (`extensionInstallMode = "sideload"`) is an undocumented escape hatch only; official/Homebrew Firefox builds typically ignore new sideloads.
- DoH mode `2` falls back to system DNS; set `network.trr.mode` to `3` in `config/firefox/` for DoH-only.

## Editors

- Cursor (and optional Devin) default `security.workspace.trust.untrustedFiles` is `"prompt"`.
- Shared extension set is `commonBase` in `home/vscode/extensions.nix`, used by both Cursor HM and VS Code HM. VS Code HM is enabled when the `visual-studio-code` cask is listed or `programs.vscode.enable = true`. Devin optionally shares the **settings** pipeline only, not extension installs.
- `commonBase` is free (Git Graph removed and not installed). `nixpkgs.config.allowUnfree = true` remains required for `_1password-cli`, Google Android SDK (`androidenv`), and editor/VS Code ecosystem packages that overlays or VS Code HM may pull in. Predicate allowlists proved too brittle as new unfree attrs appear.
- Some Cursor extensions (nix-ide, python-envs, pylance) install via `cursor --install-extension` at switch time (marketplace builds are not content-addressed like Nix store paths).

## Weekly pin refresh

`update-flake.yml` (Mondays, and on demand) runs `nix flake update` and `scripts/update-pins.sh all`, then opens a PR. The script rewrites four pin sidecars: `home/firefox/addons-pins.json` (AMO), `home/vscode/extensions-extra.json` (Marketplace), `home/bat-theme-pin.json` (catppuccin/bat HEAD) and `overlays/google-fonts/pins.json` (google/fonts commit and hashes). It also updates the same-major npm `eslint` / `prettier` pins in `lib/editor-tooling-package.json` and refreshes the editor-tooling lock.

- **Atomic, all-or-nothing per file.** A sidecar is rewritten only when every entry in it passes its guards; a failed updater leaves its file untouched.
- **AMO guards.** The response must report the expected `guid`, a download URL under `https://addons.mozilla.org/firefox/downloads/file/<id>/`, and a `sha256:` hash. Anything else is rejected.
- **No pre-releases.** Marketplace versions flagged as pre-release are skipped, as are versions whose engine is newer than the locked VS Code. npm moves only within the pinned major; a newer major is reported, not applied.
- **In-workflow verification.** The `update` job builds `example-mac` and `pinned-sources` before the PR is opened. A failed build is recorded and the run goes red, but the PR still opens. The build step has its own 60-minute timeout, so a slow cold-cache build counts as a failed build rather than cancelling the job. This step uses no token, so it does not depend on `WORKFLOW_PAT`.
- **Token scope.** `GH_TOKEN` is sent only to `https://api.github.com/*`, and redirects are not followed.
- **Two-job split.** The `update` job runs Nix and repo scripts with a `contents: read` token. Only the Nix-free `pr` job holds `contents: write` and `pull-requests: write`. It accepts only regular files at allowlisted paths and refuses symlink destinations before it copies anything into the PR branch.
- **PR review.** Reviewers check the `flake.lock` diff, the AMO and VSIX URLs in the sidecars, and any `pins: npm: <pkg> <major> available` warnings. Cursor engine drift is an accepted risk covered by this review.

## CI / supply chain

- All workflows pin Actions by **commit SHA** (version in a comment), including the nng-kit `vendor-check` composite action. Dependabot still opens weekly bumps for `github-actions`.
- `flake.yml` uses least-privilege `permissions: contents: read`.
- Release tooling (git-cliff) comes from the flake devShell pinned by `flake.lock`, not a release-asset download.
- Shellcheck in CI runs from the flake devShell.
- No workflow expands `${{ }}` inline in a `run:` block. Inputs, step outputs and matrix values reach scripts through `env:` (or the runner's default variables such as `GITHUB_REPOSITORY`), which avoids template injection.
- `flake.yml`, `update-flake.yml` and `vendor-check.yml` checkouts set `persist-credentials: false` (`update-flake.yml` pushes via `create-pull-request`'s own `token:` input); `release.yml` keeps the token because it pushes the changelog branch with `git push`.
- Every job in every workflow sets `timeout-minutes`.
- Starter-only flake checks (`lib-tests`, `fmt`, `shellcheck`, `json-schema`, `pinned-sources`) run in CI so schema and trust-rule regressions fail closed; see [architecture/OVERVIEW.md](architecture/OVERVIEW.md).
- Eval/fmt/check jobs set up the free public **`dotnix-starter`** Cachix cache after nix-installer (`CACHIX_AUTH_TOKEN`). The step uses `continue-on-error` so missing cache/token soft-fails and jobs still proceed.
- `release.yml` needs write permissions. `update-flake.yml` needs them only in its `pr` job (or a `WORKFLOW_PAT` to open PRs); scope the PAT tightly and review ruleset exemptions.

See also [MACOS-27.md](MACOS-27.md) for major OS upgrade guidance.
