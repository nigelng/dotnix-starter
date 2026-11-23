#!/usr/bin/env sh
# Apply the darwin configuration from this flake.
# Usage: ./build-darwin.sh [hostname]
#   hostname defaults to defaultHost in config/hosts.json
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -n "${1:-}" ]; then
  exec nix run '.#switch' -- "$1"
fi

exec nix run '.#switch'
