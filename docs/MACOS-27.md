# macOS 27 readiness

Apple year-based releases (macOS 26 → **macOS 27**) move on a different schedule than NixOS / nix-darwin channel trains (`nixos-26.05`, then typically `26.11` / `27.05`). This template stays on **`*-26.05`** until matching release branches exist and build cleanly.

`nix flake update` only refreshes lock revisions **within** the current channel refs. A major OS / channel bump is a deliberate `flake.nix` edit.

## Before installing a macOS 27 beta

1. Set `"automaticallyInstallMacOSUpdates": false` in `config/hosts/<host>.json` (defaults to `true`). Re-switch so Software Update does not jump ahead of nix-darwin support.
2. Keep a known-good generation; test on one machine first.
3. Track [nix-darwin](https://github.com/LnL7/nix-darwin) and nixpkgs Darwin issues for the new OS.
4. Re-check network service names after upgrade:

   ```sh
   networksetup -listallnetworkservices
   ```

   Override via `knownNetworkServices` in host JSON if labels changed (`lib/host-presets.nix`).
5. Smoke-test PAM sudo (Touch ID / Apple Watch), `system.defaults`, Homebrew activation, Firefox / VS Code / Cursor paths under `~/Library/`.
6. Confirm Homebrew still lives at `homebrewPrefix` (default `/opt/homebrew`) and `brew shellenv` works in zsh.

## CI

GitHub Actions currently use **`macos-14`**. When GitHub ships a runner image that matches the new Darwin (or you use a self-hosted Mac on macOS 27), update `.github/workflows/flake.yml` and `update-flake.yml`. Keep `aarch64-darwin` until Intel support is intentionally added.

## When Nix ships a supporting channel

1. Wait for `nixos-XX.YY`, `nix-darwin-XX.YY`, and home-manager `release-XX.YY` (or temporarily track `master` / unstable for beta-only testing).
2. Update the three input URLs in `flake.nix` **and** the thin-overlay examples in this README.
3. Run `nix flake update`, then `nix flake check` and per-host builds.
4. Read nix-darwin + [home-manager release notes](https://nix-community.github.io/home-manager/release-notes.xhtml).
5. Bump `home.stateVersion` in `home/default.nix` only when required; bump `system.stateVersion` only after `nix run '.#changelog'`.
6. Re-validate Homebrew cleanup flags, PAM, defaults, Firefox add-ons, optional Android SDK.
7. Notify overlay consumers to bump `dotnix-starter` (and matching channel pins) together.
8. Cut a release with a clear conventional commit (e.g. `chore(nix): bump channels to XX.YY`) so it appears in CHANGELOG — routine `chore: update flake inputs` commits are skipped by git-cliff.

## Periodic updates (stable channel)

| Cadence | Action |
| ------- | ------ |
| Weekly | Merge `chore: update flake inputs` PRs after green CI |
| Weekly | Merge Dependabot Actions SHA bumps |
| After merge | `darwin-rebuild switch` (or `./build-darwin.sh`) on each Mac; watch Homebrew / PAM |
| Channel bump | Manual `flake.nix` ref change — not automatic |

Optional: Cachix for faster CI (see README). Optional follow-up: automate AMO / VS Code extension hash bumps.

See also [SECURITY.md](SECURITY.md).
