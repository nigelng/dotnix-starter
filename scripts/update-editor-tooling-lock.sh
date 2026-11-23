#!/usr/bin/env bash
# Regenerate lib/editor-tooling-package-lock.json and the npmDepsHash in
# lib/editor-tooling.nix from the prettier-config / eslint-config revisions
# pinned in flake.lock and the deps in lib/editor-tooling-package.json.
#
# Run from the flake root after `nix flake update` (the weekly update-flake
# workflow does this automatically). Idempotent: no diff when nothing changed.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

lock="lib/editor-tooling-package-lock.json"
nixfile="lib/editor-tooling.nix"
fake_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Store paths of the locked config inputs.
archive="$(nix flake archive --json)"
prettier_src="$(jq -er '.inputs["prettier-config"].path' <<<"$archive")"
eslint_src="$(jq -er '.inputs["eslint-config"].path' <<<"$archive")"

# Mirror the source layout built by toolingSrc in lib/editor-tooling.nix.
mkdir -p "$work/prettier-config" "$work/eslint-config"
cp -r "$prettier_src"/* "$work/prettier-config/"
cp -r "$eslint_src"/* "$work/eslint-config/"
chmod -R u+w "$work"
cp lib/editor-tooling-package.json "$work/package.json"

echo "Regenerating $lock ..."
# nodejs from the flake's locked nixpkgs, so the lock matches the build's npm.
node_bin="$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#nodejs)/bin"
(
  cd "$work"
  PATH="$node_bin:$PATH" npm install --package-lock-only --legacy-peer-deps \
    --ignore-scripts --no-audit --no-fund
)
cp "$work/package-lock.json" "$lock"

echo "Computing npmDepsHash ..."
old_hash="$(sed -nE 's/^ *npmDepsHash = "([^"]+)";/\1/p' "$nixfile")"
sed -i.bak -E "s|npmDepsHash = \"[^\"]+\";|npmDepsHash = \"$fake_hash\";|" "$nixfile"
rm -f "$nixfile.bak"

if out="$(nix build --no-link .#editorTooling.editorTooling 2>&1)"; then
  echo "error: build succeeded with a fake hash; refusing to guess" >&2
  sed -i.bak -E "s|npmDepsHash = \"[^\"]+\";|npmDepsHash = \"$old_hash\";|" "$nixfile"
  rm -f "$nixfile.bak"
  exit 1
fi

new_hash="$(sed -nE 's/^ *got: *(sha256-[A-Za-z0-9+/=]+).*/\1/p' <<<"$out" | head -n1)"
if [[ -z "$new_hash" ]]; then
  echo "$out" >&2
  echo "error: could not determine npmDepsHash (see build output above)" >&2
  sed -i.bak -E "s|npmDepsHash = \"[^\"]+\";|npmDepsHash = \"$old_hash\";|" "$nixfile"
  rm -f "$nixfile.bak"
  exit 1
fi

sed -i.bak -E "s|npmDepsHash = \"[^\"]+\";|npmDepsHash = \"$new_hash\";|" "$nixfile"
rm -f "$nixfile.bak"
echo "npmDepsHash: $old_hash -> $new_hash"

echo "Verifying build ..."
nix build --no-link .#editorTooling.editorTooling
