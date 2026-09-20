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
8. **Firmware password** — not applicable on Apple Silicon; on Intel, set only via Recovery if you still use Intel Macs.

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

- The Firefox **app** comes from the Homebrew `firefox` cask only. home-manager never installs Firefox from nixpkgs (`programs.firefox.package = null` always).
- Default add-ons use enterprise `ExtensionSettings` (`force_installed`) with **pinned** AMO file URLs from `home/firefox/addons.nix` / `extensions.manual`. Firefox fetches Mozilla-signed XPIs at first launch or after policy apply (HTTPS + AMO + Mozilla signing).
- **Trust gap vs Nix store:** policy install does **not** verify sha256 at `nix switch`. Mitigations: pin file URLs in git, keep `extensions.update.enabled` / `autoUpdateDefault` false, bump catalog/manual URLs intentionally for CVE fixes.
- Do **not** duplicate starter `addonId`s in overlay `ExtensionSettings` — starter owns the force-installed list from JSON; overlays should use `extensions.nix` slugs or `manual` entries.
- `extensions.manual` accepts arbitrary URL + hash — treat host JSON as trusted input (a malicious URL compromises the profile).
- Profile-dir XPI sideload (`extensionInstallMode = "sideload"`) is an undocumented escape hatch only; official/Homebrew Firefox builds typically ignore new sideloads.
- DoH mode `2` falls back to system DNS; set `network.trr.mode` to `3` in `config/firefox/` for DoH-only.

## Editors

- VS Code / Cursor default `security.workspace.trust.untrustedFiles` is `"prompt"`.
- Some Cursor extensions install via `cursor --install-extension` at switch time (marketplace builds are not content-addressed like Nix store paths).

## CI / supply chain

- Workflows pin Actions by **commit SHA** (version in a comment). Dependabot still opens weekly bumps for `github-actions`.
- `flake.yml` uses least-privilege `permissions: contents: read`.
- Release / update-flake workflows need write permissions (or `WORKFLOW_PAT`); scope the PAT tightly and review ruleset exemptions.

See also [MACOS-27.md](MACOS-27.md) for major OS upgrade guidance.
