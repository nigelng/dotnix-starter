#!/usr/bin/env bash
# Validate config/hosts/<host>.json against config/schema/host.schema.json.
# Run from the repo root, or pass the repo root as $1.
set -euo pipefail

ROOT="${1:-$PWD}"
cd "$ROOT"

schema="config/schema/host.schema.json"
manifest="config/hosts.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
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

validate_firefox() {
  firefox_schema="config/schema/firefox.schema.json"
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
  android_schema="config/schema/android.schema.json"
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
  validate_with_python "$schema" "$host_json"
  validate_firefox "$host"
  validate_android "$host"
done

echo "Host JSON schema validation passed."
