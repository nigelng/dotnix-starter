#!/usr/bin/env bash
# Interactive scaffold for a new nix-darwin host (config/hosts + config/apps/hosts + hosts.json).
set -euo pipefail

resolve_flake_root() {
  if [[ -n "${FLAKE_ROOT:-}" ]] && [[ -f "${FLAKE_ROOT}/flake.nix" ]]; then
    printf '%s' "$FLAKE_ROOT"
    return 0
  fi
  if root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -f "$root/flake.nix" ]]; then
    printf '%s' "$root"
    return 0
  fi
  local script_root
  script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -f "$script_root/flake.nix" ]]; then
    printf '%s' "$script_root"
    return 0
  fi
  echo "Could not find flake root. Run from the repo checkout or set FLAKE_ROOT." >&2
  return 1
}

ROOT="$(resolve_flake_root)"
cd "$ROOT"

if [[ ! -w "config" ]]; then
  echo "Cannot write to $ROOT/config (permission denied)." >&2
  echo "Run from your git checkout, e.g. cd ~/.nix && nix run '.#new-host'" >&2
  echo "Do not rely on a read-only nix store copy of this flake." >&2
  exit 1
fi

COPY_FROM=""
NONINTERACTIVE=false

usage() {
  cat <<'EOF'
Usage: new-host.sh [options]

Creates:
  config/hosts/<id>.json
  config/apps/hosts/<id>.json
  config/fonts/hosts/<id>.json
  config/firefox/hosts/<id>.json
  config/android/hosts/<id>.json   (when config/android/base.json exists)
  updates config/hosts.json

Options:
  -c, --copy-from HOST   Clone host + apps JSON from an existing host
  -y, --yes              Accept defaults (still requires HOST_ID via arg or prompt)
  -h, --help             Show this help

Also runnable via: nix run '.#new-host'
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c | --copy-from)
      COPY_FROM="${2:?--copy-from requires a host id}"
      shift 2
      ;;
    -y | --yes)
      NONINTERACTIVE=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      HOST_ARG="$1"
      shift
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install jq or run: nix run '.#new-host'" >&2
  exit 1
fi

prompt() {
  local var_name="$1"
  local text="$2"
  local default="${3-}"
  local value=""
  if [[ "$NONINTERACTIVE" == true ]]; then
    value="${default}"
  else
    if [[ -n "$default" ]]; then
      read -r -p "$text [$default]: " value
      value="${value:-$default}"
    else
      read -r -p "$text: " value
    fi
  fi
  printf -v "$var_name" '%s' "$value"
}

prompt_choice() {
  local var_name="$1"
  local text="$2"
  shift 2
  local options=("$@")
  local default="${options[0]}"
  local i choice

  if [[ "$NONINTERACTIVE" == true ]]; then
    printf -v "$var_name" '%s' "$default"
    return
  fi

  echo "$text"
  for i in "${!options[@]}"; do
    echo "  $((i + 1))) ${options[$i]}"
  done
  read -r -p "Choice [${default}]: " choice
  choice="${choice:-$default}"
  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
    printf -v "$var_name" '%s' "${options[$((choice - 1))]}"
  else
    printf -v "$var_name" '%s' "$choice"
  fi
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_host_id() {
  local id="$1"
  if [[ ! "$id" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "Host id must start with a letter and use lowercase letters, digits, and hyphens only." >&2
    return 1
  fi
}

host_exists() {
  jq -e --arg h "$1" '.hosts | index($h) != null' config/hosts.json >/dev/null 2>&1
}

if [[ -n "${COPY_FROM:-}" ]]; then
  if ! host_exists "$COPY_FROM"; then
    echo "Unknown host in config/hosts.json: $COPY_FROM" >&2
    exit 1
  fi
  if [[ ! -f "config/hosts/${COPY_FROM}.json" ]]; then
    echo "Missing config/hosts/${COPY_FROM}.json" >&2
    exit 1
  fi
fi

echo "==> New nix-darwin host"
echo "    Flake root: $ROOT"
echo

if [[ -n "${HOST_ARG:-}" ]]; then
  HOST_ID="$HOST_ARG"
else
  prompt HOST_ID "Host id (flake name, e.g. work-macbook)"
fi

validate_host_id "$HOST_ID"

if host_exists "$HOST_ID"; then
  echo "Host already exists in config/hosts.json: $HOST_ID" >&2
  exit 1
fi

if [[ -f "config/hosts/${HOST_ID}.json" ]] || [[ -f "config/apps/hosts/${HOST_ID}.json" ]]; then
  echo "Host files already exist for: $HOST_ID" >&2
  exit 1
fi

if [[ -n "$COPY_FROM" ]]; then
  DESCRIPTION="$(jq -r '.description' "config/hosts/${COPY_FROM}.json")"
  prompt DESCRIPTION "Description" "$DESCRIPTION (copy)"
  HOST_CONFIG="$(jq --arg id "$HOST_ID" --arg desc "$DESCRIPTION" \
    '.description = $desc | .computerName = $id | .hostName = $id' \
    "config/hosts/${COPY_FROM}.json")"
  if [[ -f "config/apps/hosts/${COPY_FROM}.json" ]]; then
    APPS_CONFIG="$(jq '.' "config/apps/hosts/${COPY_FROM}.json")"
  else
    APPS_CONFIG='{}'
  fi
  if [[ -f "config/fonts/hosts/${COPY_FROM}.json" ]]; then
    FONTS_HOST_CONFIG="$(jq '.' "config/fonts/hosts/${COPY_FROM}.json")"
  else
    FONTS_HOST_CONFIG='{}'
  fi
  if [[ -f "config/firefox/hosts/${COPY_FROM}.json" ]]; then
    FIREFOX_HOST_CONFIG="$(jq '.' "config/firefox/hosts/${COPY_FROM}.json")"
  else
    FIREFOX_HOST_CONFIG='{}'
  fi
  if [[ -f "config/android/base.json" ]]; then
    if [[ -f "config/android/hosts/${COPY_FROM}.json" ]]; then
      ANDROID_HOST_CONFIG="$(jq '.' "config/android/hosts/${COPY_FROM}.json")"
    else
      ANDROID_HOST_CONFIG='{"enable":false}'
    fi
  fi
else
  prompt DESCRIPTION "Description" "${HOST_ID} configuration"
  prompt ADMIN_USER "adminUsername (macOS admin username)" "$(whoami)"
  prompt COMPUTER_NAME "computerName" "$HOST_ID"
  prompt HOST_NAME "hostName" "$HOST_ID"
  prompt_choice MACHINE_TYPE "machineType" laptop macmini
  # shellcheck disable=SC2088
  prompt SCREENSHOT_FOLDER "screenshotFolder" "~/Downloads"
  prompt HOMEBREW_PREFIX "homebrewPrefix (Apple Silicon)" "/opt/homebrew"
  prompt_choice HOMEBREW_CLEANUP "homebrewCleanup" none check uninstall zap
  prompt SET_DEFAULT "Add to hosts.json as defaultHost? (y/N)" "N"

  HOST_CONFIG="$(jq -n \
    --arg description "$DESCRIPTION" \
    --arg adminUsername "$ADMIN_USER" \
    --arg machineType "$MACHINE_TYPE" \
    --arg computerName "$COMPUTER_NAME" \
    --arg hostName "$HOST_NAME" \
    --arg screenshotFolder "$SCREENSHOT_FOLDER" \
    --arg homebrewPrefix "$HOMEBREW_PREFIX" \
    --arg homebrewCleanup "$HOMEBREW_CLEANUP" \
    '{
      description: $description,
      adminUsername: $adminUsername,
      machineType: $machineType,
      computerName: $computerName,
      hostName: $hostName,
      screenshotFolder: $screenshotFolder,
      homebrewPrefix: $homebrewPrefix,
      homebrewCleanup: $homebrewCleanup,
      trustedUsers: [],
      allowedUsers: [$adminUsername]
    }')"
  APPS_CONFIG='{}'
  FONTS_HOST_CONFIG='{}'
  FIREFOX_HOST_CONFIG='{}'
  if [[ -f "config/android/base.json" ]]; then
    ANDROID_HOST_CONFIG='{"enable":false}'
  fi
fi

if [[ -z "${SET_DEFAULT:-}" ]]; then
  prompt SET_DEFAULT "Add to hosts.json as defaultHost? (y/N)" "N"
fi

mkdir -p config/hosts config/apps/hosts config/fonts/hosts config/firefox/hosts
if [[ -f "config/android/base.json" ]]; then
  mkdir -p config/android/hosts
fi

HOST_FILE="config/hosts/${HOST_ID}.json"
APPS_FILE="config/apps/hosts/${HOST_ID}.json"
FONTS_FILE="config/fonts/hosts/${HOST_ID}.json"
FIREFOX_FILE="config/firefox/hosts/${HOST_ID}.json"
ANDROID_FILE="config/android/hosts/${HOST_ID}.json"
MANIFEST_FILE="config/hosts.json"

echo "$HOST_CONFIG" | jq '.' >"$HOST_FILE"
echo "$APPS_CONFIG" | jq '.' >"$APPS_FILE"
echo "$FONTS_HOST_CONFIG" | jq '.' >"$FONTS_FILE"
echo "$FIREFOX_HOST_CONFIG" | jq '.' >"$FIREFOX_FILE"
if [[ -f "config/android/base.json" ]]; then
  echo "$ANDROID_HOST_CONFIG" | jq '.' >"$ANDROID_FILE"
fi

if [[ "$(lower "${SET_DEFAULT:-}")" == y* ]]; then
  jq --arg h "$HOST_ID" '.defaultHost = $h | .hosts += [$h] | .hosts |= unique' \
    "$MANIFEST_FILE" >"${MANIFEST_FILE}.tmp"
else
  jq --arg h "$HOST_ID" '.hosts += [$h] | .hosts |= unique' \
    "$MANIFEST_FILE" >"${MANIFEST_FILE}.tmp"
fi
mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"

echo
echo "Created:"
echo "  $HOST_FILE"
echo "  $APPS_FILE"
echo "  $FONTS_FILE"
echo "  $FIREFOX_FILE"
if [[ -f "config/android/base.json" ]]; then
  echo "  $ANDROID_FILE"
fi
echo "  updated $MANIFEST_FILE"
echo
echo "Next steps:"
echo "  1. Edit $HOST_FILE for machine settings (adminUsername, machineType, homebrewCleanup, extraSessionPaths, …)."
echo "  2. Edit $APPS_FILE for host-only apps (system, casks, mas, …)."
echo "  3. Edit $FONTS_FILE for host-only fonts (pkgs, google, nerd, casks)."
echo "  4. Edit $FIREFOX_FILE for host-only Firefox overrides (use {} if none)."
if [[ -f "config/android/base.json" ]]; then
  echo "  5. Edit $ANDROID_FILE for Android enable/disable (use { \"enable\": false } if off)."
  echo "  6. git add config/hosts/${HOST_ID}.json config/apps/hosts/${HOST_ID}.json config/fonts/hosts/${HOST_ID}.json config/firefox/hosts/${HOST_ID}.json config/android/hosts/${HOST_ID}.json config/hosts.json"
  echo "  7. nix run '.#check'   # CI matrix is derived from config/hosts.json automatically"
  echo "  8. nix run '.#switch' -- ${HOST_ID}"
else
  echo "  5. git add config/hosts/${HOST_ID}.json config/apps/hosts/${HOST_ID}.json config/fonts/hosts/${HOST_ID}.json config/firefox/hosts/${HOST_ID}.json config/hosts.json"
  echo "  6. nix run '.#check'   # CI matrix is derived from config/hosts.json automatically"
  echo "  7. nix run '.#switch' -- ${HOST_ID}"
fi
