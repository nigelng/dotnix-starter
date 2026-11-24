#!/usr/bin/env bash
# Validate hosts/user/git (once) and per-host host/apps/fonts/firefox/android JSON
# against SCHEMA_ROOT/*.schema.json. The hosts, user and git schemas are optional
# so overlays pointing SCHEMA_ROOT at an older json-schemas store path still pass.
# SCHEMA_ROOT defaults to $ROOT/config/schema (overlay repos can point at the
# starter packages.<system>.json-schemas store path instead of copying schemas).
# Run from the repo root, or pass the repo root as $1.
set -euo pipefail

ROOT="${1:-$PWD}"
cd "$ROOT"

SCHEMA_ROOT="${SCHEMA_ROOT:-$ROOT/config/schema}"

host_schema="$SCHEMA_ROOT/host.schema.json"
apps_schema="$SCHEMA_ROOT/apps.schema.json"
fonts_schema="$SCHEMA_ROOT/fonts.schema.json"
manifest="config/hosts.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [[ ! -d "$SCHEMA_ROOT" ]]; then
  echo "Missing schema directory: $SCHEMA_ROOT (set SCHEMA_ROOT or use config/schema)" >&2
  exit 1
fi

if [[ ! -f "$manifest" ]]; then
  echo "Missing required host manifest: $manifest" >&2
  exit 1
fi

if ! jq -e . "$manifest" >/dev/null; then
  echo "Unreadable or invalid JSON: $manifest" >&2
  exit 1
fi

mapfile -t hosts < <(jq -r '.hosts[]?' "$manifest")
if [[ ${#hosts[@]} -eq 0 ]]; then
  echo "No hosts listed in $manifest" >&2
  exit 1
fi

validate_with_python() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

schema_path, data_path = sys.argv[1:3]
with open(schema_path) as f:
    schema = json.load(f)
with open(data_path) as f:
    data = json.load(f)

try:
    from jsonschema import Draft202012Validator
except ImportError:
    print("python jsonschema module is required (see flake devShell)", file=sys.stderr)
    sys.exit(1)

validator = Draft202012Validator(schema)
errors = sorted(validator.iter_errors(data), key=lambda e: list(e.path))
if errors:
    for err in errors:
        path = ".".join(str(p) for p in err.path) or "(root)"
        print(f"{data_path}: {path}: {err.message}", file=sys.stderr)
    sys.exit(1)
PY
}

validate_apps() {
  for path in \
    "config/apps/base.json" \
    "config/apps/hosts/${1}.json"; do
    if [[ ! -f "$path" ]]; then
      echo "Missing required apps config: $path" >&2
      exit 1
    fi
    jq -e . "$path" >/dev/null
    validate_with_python "$apps_schema" "$path"
  done
}

validate_fonts() {
  for path in \
    "config/fonts/base.json" \
    "config/fonts/hosts/${1}.json"; do
    if [[ ! -f "$path" ]]; then
      echo "Missing required fonts config: $path" >&2
      exit 1
    fi
    jq -e . "$path" >/dev/null
    validate_with_python "$fonts_schema" "$path"
  done
}

validate_firefox() {
  firefox_schema="$SCHEMA_ROOT/firefox.schema.json"
  # Skip Firefox validation entirely if the base config doesn't exist
  # (overlay repos may not use Firefox).
  if [[ ! -f "config/firefox/base.json" ]]; then
    return 0
  fi
  for path in \
    "config/firefox/base.json" \
    "config/firefox/hosts/${1}.json"; do
    if [[ ! -f "$path" ]]; then
      echo "Missing required Firefox config: $path" >&2
      exit 1
    fi
    jq -e . "$path" >/dev/null
    validate_with_python "$firefox_schema" "$path"
  done
}

validate_android() {
  android_schema="$SCHEMA_ROOT/android.schema.json"
  # Skip Android validation entirely if the base config doesn't exist
  # (overlay repos may not use Android).
  if [[ ! -f "config/android/base.json" ]]; then
    return 0
  fi
  if jq -e 'has("enable")' "config/android/base.json" >/dev/null; then
    echo "config/android/base.json must not contain \"enable\" (use hosts/<host>.json instead)" >&2
    exit 1
  fi
  for path in \
    "config/android/base.json" \
    "config/android/hosts/${1}.json"; do
    if [[ ! -f "$path" ]]; then
      echo "Missing required Android config: $path" >&2
      exit 1
    fi
    jq -e . "$path" >/dev/null
    validate_with_python "$android_schema" "$path"
  done
}

# Mirrors the Nix loader check (checkHostsManifest); runs even without hosts.schema.json.
# A present defaultHost (including null) must be a string listed in hosts.
if ! jq -e '(has("defaultHost") | not) or (.defaultHost as $d | ($d | type) == "string" and any(.hosts[]?; . == $d))' "$manifest" >/dev/null; then
  echo "$manifest: defaultHost $(jq -c '.defaultHost' "$manifest") is not listed in hosts (must be a host name string)" >&2
  exit 1
fi

if [[ -f "$SCHEMA_ROOT/hosts.schema.json" ]]; then
  validate_with_python "$SCHEMA_ROOT/hosts.schema.json" "$manifest"
fi

if [[ -f "$SCHEMA_ROOT/user.schema.json" ]]; then
  for user_json in "config/user.json" "config/user.json.example"; do
    if [[ -f "$user_json" ]]; then
      jq -e . "$user_json" >/dev/null
      validate_with_python "$SCHEMA_ROOT/user.schema.json" "$user_json"
      break
    fi
  done
fi

if [[ -f "$SCHEMA_ROOT/git.schema.json" && -f "config/git.json" ]]; then
  jq -e . "config/git.json" >/dev/null
  validate_with_python "$SCHEMA_ROOT/git.schema.json" "config/git.json"
fi

for host in "${hosts[@]}"; do
  for path in \
    "config/hosts/${host}.json" \
    "config/apps/hosts/${host}.json" \
    "config/fonts/hosts/${host}.json"; do
    if [[ ! -f "$path" ]]; then
      echo "Missing required host config: $path" >&2
      exit 1
    fi
  done
  host_json="config/hosts/${host}.json"
  jq -e . "$host_json" >/dev/null
  validate_with_python "$host_schema" "$host_json"
  validate_apps "$host"
  validate_fonts "$host"
  validate_firefox "$host"
  validate_android "$host"
done

echo "Host JSON schema validation passed."
