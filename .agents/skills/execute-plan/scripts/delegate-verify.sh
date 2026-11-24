#!/usr/bin/env bash
# delegate-verify.sh — run Verification commands and report PASS/FAIL.
# Bash 3.2: no associative arrays, no mapfile, no ${var,,}.
#
# Usage: delegate-verify.sh <repo-root> <commands-file>
#
# commands-file holds one command per line; blank lines and lines whose
# first non-space character is '#' are skipped. Each remaining line runs
# whole (pipelines included) via `bash -c "$line"` from repo-root with
# stdin </dev/null; stdout+stderr go to a temp file. Per-command timeout is
# DELEGATE_VERIFY_TIMEOUT seconds (default 900) via timeout/gtimeout when on
# PATH, else no timeout.
#
# Output: per command `$ <command>` then `exit: <n>`; on non-zero exit the
# last 20 output lines follow, each prefixed with two spaces. Then exactly
# one final line: PASS, FAIL, FAIL (tree changed), or PASS (no commands).
# git status --porcelain is snapshotted before the first and after the last
# command; a change prints the before/after diff lines (prefixed two
# spaces) above `FAIL (tree changed)`, which wins over PASS/FAIL.
#
# Exit codes: 0 pass, 1 command failure, 3 tree changed, 2 usage error.
set -euo pipefail

usage() {
  echo "usage: delegate-verify.sh <repo-root> <commands-file>" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

root=$1
commands_file=$2

case "$root" in
  /*) ;;
  *)
    usage
    exit 2
    ;;
esac

phys=$(cd "$root" 2>/dev/null && pwd -P) || { usage; exit 2; }
git_top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || { usage; exit 2; }
git_phys=$(cd "$git_top" 2>/dev/null && pwd -P) || { usage; exit 2; }
if [[ "$phys" != "$git_phys" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$commands_file" ]]; then
  usage
  exit 2
fi

verify_timeout=${DELEGATE_VERIFY_TIMEOUT:-900}
if [[ ! "$verify_timeout" =~ ^[0-9]+$ ]]; then
  usage
  exit 2
fi

timeout_bin=""
if command -v timeout >/dev/null 2>&1; then
  timeout_bin=$(command -v timeout)
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_bin=$(command -v gtimeout)
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/delegate-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT

cmd_out="$work/cmd.out"
snap_before="$work/porcelain-before"
snap_after="$work/porcelain-after"

cd "$phys"
git status --porcelain >"$snap_before"

n_commands=0
failed=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%$'\r'}
  if [[ -z "${line//[[:space:]]/}" ]]; then
    continue
  fi
  trimmed=${line#"${line%%[![:space:]]*}"}
  if [[ "$trimmed" == \#* ]]; then
    continue
  fi
  n_commands=$((n_commands + 1))
  printf '$ %s\n' "$line"
  rc=0
  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" "$verify_timeout" bash -c "$line" </dev/null >"$cmd_out" 2>&1 || rc=$?
  else
    bash -c "$line" </dev/null >"$cmd_out" 2>&1 || rc=$?
  fi
  printf 'exit: %s\n' "$rc"
  if [[ "$rc" -ne 0 ]]; then
    failed=1
    tail -n 20 "$cmd_out" | sed 's/^/  /'
  fi
done <"$commands_file"

git status --porcelain >"$snap_after"

if ! cmp -s "$snap_before" "$snap_after"; then
  diff -u "$snap_before" "$snap_after" 2>/dev/null | tail -n +3 | sed 's/^/  /' || true
  printf 'FAIL (tree changed)\n'
  exit 3
fi

if [[ "$n_commands" -eq 0 ]]; then
  printf 'PASS (no commands)\n'
  exit 0
fi

if [[ "$failed" -ne 0 ]]; then
  printf 'FAIL\n'
  exit 1
fi

printf 'PASS\n'
exit 0
