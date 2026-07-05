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

validate_with_python() {
  python3 - "$schema" "$1" <<'PY'
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

for host in $(jq -r '.hosts[]' "$manifest"); do
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
  validate_with_python "$host_json"
done

echo "Host JSON schema validation passed."
