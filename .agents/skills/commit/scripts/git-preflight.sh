#!/usr/bin/env bash
# git-preflight.sh — read-only git facts for /commit and the release skills.
# Output is key=value lines. Bash 3.2. No GNU-only or BSD-only date flags
# without a fallback. Never hardcodes the default branch name.
#
#   git-preflight.sh state
#   git-preflight.sh version [<tag>]
#   git-preflight.sh bump <type> [<from>]
#   git-preflight.sh fingerprint
set -euo pipefail

usage() {
  echo "usage: git-preflight.sh state | version [<tag>] | bump <type> [<from>] | fingerprint" >&2
  exit 2
}

cd "$(git rev-parse --show-toplevel)"

kv() { printf '%s=%s\n' "$1" "$2"; }

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

default_branch() {
  local ref
  ref=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ -n "$ref" ]]; then
    printf '%s' "${ref#refs/remotes/origin/}"
    return
  fi
  printf ''
}

toml_version() {
  awk -v sect="$2" '
    index($0, "[" sect "]") == 1 { insec = 1; next }
    /^\[/ { insec = 0 }
    insec && /^version[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      gsub(/[[:space:]]/, "")
      print
      exit
    }
  ' "$1"
}

version_in() {
  case "$1" in
    package.json) jq -r '.version // empty' "$1" ;;
    pyproject.toml) toml_version "$1" project ;;
    Cargo.toml) toml_version "$1" package ;;
  esac
}

# First manifest that yields a version; empty when none does.
manifest_file() {
  local f
  for f in package.json pyproject.toml Cargo.toml; do
    if [[ -f "$f" && -n "$(version_in "$f")" ]]; then
      printf '%s' "$f"
      return
    fi
  done
}

manifest_version() {
  local f
  f=$(manifest_file)
  [[ -z "$f" ]] || version_in "$f"
}

changelog_heading() {
  [[ -f CHANGELOG.md ]] || return 0
  awk '
    /^## / {
      line = tolower($0)
      if (line ~ /unreleased/) { print $0; exit }
    }
  ' CHANGELOG.md
}

changelog_version_of() {
  local heading=$1
  if [[ "$heading" =~ \[([0-9]+\.[0-9]+\.[0-9]+)\] ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

bump_kind() {
  local type=$1
  case "$type" in
    major | breaking | breaking-change) printf 'major' ;;
    minor | feat) printf 'minor' ;;
    patch | fix) printf 'patch' ;;
    none | chore | refactor | docs | style | perf | test | build | ci | revert) printf 'none' ;;
    *!) printf 'major' ;;
    *) return 1 ;;
  esac
}

bump_version() {
  local ver=$1 kind=$2 maj min pat
  if [[ ! "$ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    return 1
  fi
  maj=${BASH_REMATCH[1]}
  min=${BASH_REMATCH[2]}
  pat=${BASH_REMATCH[3]}
  case "$kind" in
    major) maj=$((maj + 1)); min=0; pat=0 ;;
    minor) min=$((min + 1)); pat=0 ;;
    patch) pat=$((pat + 1)) ;;
    none) ;;
  esac
  printf '%s.%s.%s' "$maj" "$min" "$pat"
}

cmd_state() {
  local branch clean upstream ahead behind counts
  if git remote get-url origin >/dev/null 2>&1; then
    git fetch --quiet origin || echo "WARN: git fetch failed" >&2
  fi
  branch=$(git branch --show-current)
  if [[ -z "$(git status --porcelain)" ]]; then
    clean=yes
  else
    clean=no
  fi
  if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
    counts=$(git rev-list --left-right --count 'HEAD...@{upstream}')
    ahead=$(printf '%s\n' "$counts" | awk '{print $1}')
    behind=$(printf '%s\n' "$counts" | awk '{print $2}')
  else
    upstream=none
    ahead=0
    behind=0
  fi
  kv default "$(default_branch)"
  kv branch "$branch"
  kv clean "$clean"
  kv upstream "$upstream"
  kv ahead "$ahead"
  kv behind "$behind"
}

cmd_version() {
  local tag=${1:-} heading ver last local_tag remote_tag remote_refs mf
  mf=$(manifest_file)
  kv manifest "$([[ -z "$mf" ]] || version_in "$mf")"
  kv manifest_file "$mf"
  heading=$(changelog_heading || true)
  kv changelog_heading "$heading"
  ver=$(changelog_version_of "$heading")
  kv changelog_version "$ver"
  last=$(git describe --tags --abbrev=0 2>/dev/null || true)
  kv last_tag "$last"
  if [[ -n "$tag" ]]; then
    if git show-ref --verify --quiet "refs/tags/$tag"; then
      local_tag=yes
    else
      local_tag=no
    fi
    kv local_tag "$local_tag"
    remote_tag=no
    if git remote get-url origin >/dev/null 2>&1; then
      if remote_refs=$(git ls-remote --tags origin "refs/tags/$tag" 2>/dev/null); then
        [[ -z "$remote_refs" ]] || remote_tag=yes
      else
        remote_tag=unknown
      fi
    fi
    kv remote_tag "$remote_tag"
  fi
}

# version_ge A B: success when A >= B, both x.y.z.
version_ge() {
  local a=$1 b=$2 i
  [[ "$a" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  local -a av=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
  [[ "$b" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  local -a bv=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
  for i in 0 1 2; do
    if ((10#${av[$i]} > 10#${bv[$i]})); then
      return 0
    fi
    if ((10#${av[$i]} < 10#${bv[$i]})); then
      return 1
    fi
  done
  return 0
}

# bump <type> [<from>]: <from> (a tag ending in x.y.z, e.g. v1.2.3 or
# lifecycle-v0.13.0) is the base for `to=`; default is the manifest. `skip=yes` when the manifest is already >= to.
cmd_bump() {
  local type=${1:-} kind from to manifest skip=no
  [[ -n "$type" ]] || usage
  kind=$(bump_kind "$type") || usage
  manifest=$(manifest_version)
  from=${2:-$manifest}
  if [[ "$from" =~ (^|[^0-9.])([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    from=${BASH_REMATCH[2]}
  fi
  [[ -n "$from" ]] || { echo "git-preflight.sh: no package manifest version" >&2; exit 2; }
  to=$(bump_version "$from" "$kind") || { echo "git-preflight.sh: base version is not x.y.z" >&2; exit 2; }
  if version_ge "$manifest" "$to"; then
    skip=yes
  fi
  kv bump "$kind"
  kv from "$from"
  kv to "$to"
  kv skip "$skip"
}

path_excluded() {
  case "$1" in
    docs/plans | docs/plans/* | docs/brainstorms | docs/brainstorms/*) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_fingerprint() {
  local tmp head
  tmp=$(mktemp "${TMPDIR:-/tmp}/git-preflight.XXXXXX")
  {
    printf 'diff\n'
    git diff HEAD -- . ':(exclude)docs/plans' ':(exclude)docs/brainstorms'
    printf 'untracked\n'
    while IFS= read -r -d '' f; do
      [[ -n "$f" ]] || continue
      # Skip directories (a nested repo is listed as dir/) and other non-files.
      [[ -f "$f" ]] || continue
      if path_excluded "$f"; then
        continue
      fi
      printf 'file %s\n' "$f"
      cat "$f"
      printf '\n'
    done < <(git ls-files -z --others --exclude-standard)
  } >"$tmp"
  kv fingerprint "$(sha256_stdin <"$tmp")"
  rm -f "$tmp"
  head=$(git rev-parse HEAD)
  kv head "$head"
}

main() {
  local cmd=${1:-}
  [[ -n "$cmd" ]] || usage
  shift
  case "$cmd" in
    state)
      [[ $# -eq 0 ]] || usage
      cmd_state
      ;;
    version)
      [[ $# -le 1 ]] || usage
      cmd_version "${1:-}"
      ;;
    bump)
      [[ $# -ge 1 && $# -le 2 ]] || usage
      cmd_bump "$@"
      ;;
    fingerprint)
      [[ $# -eq 0 ]] || usage
      cmd_fingerprint
      ;;
    *) usage ;;
  esac
}

main "$@"
