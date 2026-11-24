#!/usr/bin/env bash
# Refresh the manual pins that `nix flake update` does not touch.
#
# Usage: scripts/update-pins.sh [--root <dir>] [amo|google-fonts|bat|vscode|npm|all]
#
#   amo           home/firefox/addons-pins.json        (AMO API; URL + hash)
#   vscode        home/vscode/extensions-extra.json    (Marketplace API; version + hash)
#   bat           home/bat-theme-pin.json              (GitHub default-branch HEAD; rev + hash)
#   google-fonts  overlays/google-fonts/pins.json      (GitHub commits per font; rev + hashes)
#   npm           lib/editor-tooling-package.json      (npm registry; same-major eslint/prettier)
#
# Every updater runs even if an earlier one fails. Each sidecar is rewritten at
# most once, atomically (jq -> temp file beside it -> mv), and only when every
# entry in it passed its guards; a failed updater leaves its sidecar untouched.
# Output is `pins: <source>: <subject> <old> -> <new>` or `... unchanged`, also
# appended to $GITHUB_STEP_SUMMARY when set. Exit 1 if any updater failed.
#
# Environment:
#   UPDATE_PINS_ROOT      sidecar root (default: this repo); --root overrides.
#   UPDATE_PINS_FIXTURES  read every network/nix lookup from this directory
#                         instead (offline tests); a missing fixture is an error.
#   GH_TOKEN              sent as a bearer token to https://api.github.com/ only.
#
# Sourceable: nothing runs unless executed directly (tests source it).
# Needs jq, nix, and curl (curl only without UPDATE_PINS_FIXTURES).
# jq programs reference jq variables ($s, $p, ...) inside single quotes on purpose;
# SC2016 is disabled per function for those, not file-wide.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=""
SOURCES="amo vscode bat google-fonts npm"

GITHUB_API="https://api.github.com/"
AMO_API="https://addons.mozilla.org/api/v5/addons/addon"
MARKETPLACE_API="https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
NPM_REGISTRY="https://registry.npmjs.org"
NPM_PACKAGES="eslint prettier"

CURL_OPTS=(--fail --silent --show-error --max-time 60 --retry 2 --proto '=https')

# --- reporting ---------------------------------------------------------------

# clean TEXT: control characters (newlines, carriage returns, ...) become spaces,
# so a fetched value can never start a line of its own, e.g. `::error::...`, the
# workflow-command syntax, or Markdown in the step summary.
clean() { printf '%s' "$*" | tr '[:cntrl:]' ' '; }

summary_append() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf -- '- %s\n' "$(clean "$1")" >>"$GITHUB_STEP_SUMMARY" || true
  fi
}

# note TEXT: a result line on stdout (and the step summary).
note() {
  local msg
  msg="$(clean "$*")"
  printf 'pins: %s\n' "$msg"
  summary_append "pins: $msg"
}

# err TEXT: a problem line on stderr (and the step summary).
err() {
  local msg
  msg="$(clean "$*")"
  printf 'pins: error: %s\n' "$msg" >&2
  summary_append "pins: error: $msg"
}

usage() {
  echo "usage: ${0##*/} [--root <dir>] [amo|google-fonts|bat|vscode|npm|all]"
}

# --- network and nix seam ------------------------------------------------------

use_fixtures() { [[ -n "${UPDATE_PINS_FIXTURES:-}" ]]; }

# fixture_name URL [KEY]: flat file name for a URL (scheme dropped, other
# characters outside [A-Za-z0-9._-] become `_`); KEY tells apart requests that
# share one URL (the Marketplace POST).
fixture_name() {
  local name="${1#https://}"
  if [[ -n "${2:-}" ]]; then name="$name--$2"; fi
  printf '%s.json' "$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
}

# fixture_read RELATIVE-PATH: print a fixture; fail closed when it is absent
# (never fall through to the network or a real nix lookup).
fixture_read() {
  local file="$UPDATE_PINS_FIXTURES/$1"
  if [[ ! -f "$file" ]]; then
    err "missing fixture: $1"
    return 1
  fi
  cat "$file"
}

# fetch_json URL [CURL-ARGS...]: GET (or whatever the args say) and print the
# body. The bearer token goes to https://api.github.com/ and nowhere else, and
# redirects are not followed, so it cannot be forwarded.
fetch_json() {
  local url="$1"
  shift
  if use_fixtures; then
    fixture_read "$(fixture_name "$url" "${FIXTURE_KEY:-}")"
  elif [[ -n "${GH_TOKEN:-}" && "$url" == "$GITHUB_API"* ]]; then
    curl "${CURL_OPTS[@]}" -H "Authorization: Bearer $GH_TOKEN" "$@" "$url"
  else
    curl "${CURL_OPTS[@]}" "$@" "$url"
  fi
}

# fake_hash_build EXPR: realise a fixed-output fetch whose hash is lib.fakeHash
# and print the hash Nix reports. EXPR may use `pkgs` (the flake's pkgsForValidation).
fake_hash_build() {
  local out got
  if out="$(nix build --no-link --impure --expr \
    "let pkgs = (builtins.getFlake \"$REPO_ROOT\").pkgsForValidation; in $1" 2>&1)"; then
    err "build succeeded with a fake hash; refusing to guess"
    return 1
  fi
  got="$(printf '%s\n' "$out" | sed -nE 's/^ *got: *(sha256-[A-Za-z0-9+/=]+).*/\1/p' | head -n 1)"
  if [[ -z "$got" ]]; then
    err "could not read the hash from the build output"
    return 1
  fi
  printf '%s\n' "$got"
}

# prefetch_vsix PUBLISHER NAME VERSION: SRI hash of the VSIX (the URL
# buildVscodeMarketplaceExtension fetches).
prefetch_vsix() {
  if use_fixtures; then
    fixture_read "prefetch/vsix-$1.$2-$3.txt"
    return
  fi
  nix store prefetch-file --json \
    "https://$1.gallery.vsassets.io/_apis/public/gallery/publisher/$1/extension/$2/$3/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage" |
    jq -er '.hash'
}

# prefetch_bat OWNER REPO REV: SRI hash of the fetchFromGitHub source.
prefetch_bat() {
  local hash
  if use_fixtures; then
    fixture_read "prefetch/bat-$3.txt"
    return
  fi
  if hash="$(nix flake prefetch --json "github:$1/$2/$3" 2>/dev/null | jq -er '.hash')"; then
    printf '%s\n' "$hash"
    return 0
  fi
  fake_hash_build "pkgs.fetchFromGitHub { owner = \"$1\"; repo = \"$2\"; rev = \"$3\"; hash = pkgs.lib.fakeHash; }"
}

# prefetch_font REV PATH: SRI hash of the sparse google/fonts checkout.
prefetch_font() {
  if use_fixtures; then
    fixture_read "prefetch/font-$1-${2//\//_}.txt"
    return
  fi
  fake_hash_build "pkgs.fetchFromGitHub { owner = \"google\"; repo = \"fonts\"; rev = \"$1\"; hash = pkgs.lib.fakeHash; sparseCheckout = [ \"$2\" ]; }"
}

# locked_vscode_version: pkgs.vscode.version from the repo's own flake.
locked_vscode_version() {
  if use_fixtures; then
    fixture_read "vscode-version.txt"
    return
  fi
  nix eval --raw "$REPO_ROOT#pkgsForValidation.vscode.version"
}

# --- hashes and sidecars -------------------------------------------------------

hex_to_sri() { nix hash convert --hash-algo sha256 --to sri "$1"; }

# same_sri A B: equal ignoring base64 `=` padding (the pins mix both styles).
same_sri() { [[ "${1%%=*}" == "${2%%=*}" ]]; }

# write_doc FILE JSON: replace FILE atomically (temp file beside it, mode kept).
write_doc() {
  local tmp
  tmp="$(mktemp "$1.XXXXXX")" || return 1
  if cp -p "$1" "$tmp" && jq . <<<"$2" >"$tmp" && mv "$tmp" "$1"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# An updater edits one in-memory sidecar and writes it once, on success only.
SIDECAR_DOC=""
SIDECAR_CHANGED=0
SIDECAR_FAILED=0

sidecar_open() { # file
  SIDECAR_CHANGED=0
  SIDECAR_FAILED=0
  jq -e . "$1" >/dev/null || return 1
  SIDECAR_DOC="$(cat "$1")"
}

sidecar_get() { jq -r "$@" <<<"$SIDECAR_DOC"; } # jq-args... filter

sidecar_apply() { # jq-args... filter: edit the in-memory doc
  local next
  next="$(jq "$@" <<<"$SIDECAR_DOC")" || return 1
  SIDECAR_DOC="$next"
  SIDECAR_CHANGED=$((SIDECAR_CHANGED + 1))
}

sidecar_fail() { # what: remember a failed entry; the sidecar is then not written
  SIDECAR_FAILED=1
  err "$1 failed; its sidecar is left untouched"
}

sidecar_close() { # file
  if [[ "$SIDECAR_FAILED" -ne 0 ]]; then return 1; fi
  if [[ "$SIDECAR_CHANGED" -gt 0 ]]; then write_doc "$1" "$SIDECAR_DOC"; fi
}

# --- amo -----------------------------------------------------------------------

AMO_URL=""
AMO_HASH=""

# amo_verdict ADDON-ID < response: "ok", or why the response is rejected. Anything
# unexpected (including a jq error) is not "ok", so the guard fails closed. The
# patterns use \A and \z: in jq, `$` also matches before a trailing newline.
amo_verdict() {
  jq -r --arg id "$1" '
    .current_version.file as $f
    | if ([.guid, $f.url, $f.hash] | map(tostring | test("[[:cntrl:]]")) | any)
        then "control characters in the response"
      elif .guid != $id then "guid mismatch (got \(.guid))"
      elif (($f.url // "") | test("\\Ahttps://addons\\.mozilla\\.org/firefox/downloads/file/[0-9]+/[^/[:space:]]+\\.xpi\\z") | not)
        then "unexpected download url \($f.url)"
      elif (($f.hash // "") | test("\\Asha256:[0-9a-f]{64}\\z") | not)
        then "unexpected hash \($f.hash)"
      else "ok" end'
}

# amo_lookup ADDON-ID: sets AMO_URL and AMO_HASH (hex) from a guarded response.
amo_lookup() {
  local id="$1" enc doc verdict
  enc="$(jq -rn --arg v "$id" '$v | @uri')" || return 1
  doc="$(fetch_json "$AMO_API/$enc/")" || return 1
  verdict="$(amo_verdict "$id" <<<"$doc" 2>/dev/null)" || verdict="unparseable response"
  if [[ "$verdict" != "ok" ]]; then
    err "amo: $id: $verdict"
    return 1
  fi
  AMO_URL="$(jq -r '.current_version.file.url' <<<"$doc")" || return 1
  AMO_HASH="$(jq -r '.current_version.file.hash | ltrimstr("sha256:")' <<<"$doc")" || return 1
}

# shellcheck disable=SC2016 # jq variables, not shell expansions
amo_refresh() { # slug
  local slug="$1" id old_url old_hash sri
  id="$(sidecar_get --arg s "$slug" '.[$s].addonId')" || return 1
  old_url="$(sidecar_get --arg s "$slug" '.[$s].url')" || return 1
  old_hash="$(sidecar_get --arg s "$slug" '.[$s].hash')" || return 1
  amo_lookup "$id" || return 1
  sri="$(hex_to_sri "$AMO_HASH")" || return 1
  if [[ "$AMO_URL" == "$old_url" ]] && same_sri "$sri" "$old_hash"; then
    note "amo: $slug unchanged"
    return 0
  fi
  sidecar_apply --arg s "$slug" --arg u "$AMO_URL" --arg h "$sri" \
    '.[$s].url = $u | .[$s].hash = $h' || return 1
  note "amo: $slug ${old_url##*/} -> ${AMO_URL##*/}"
}

update_amo() {
  local file="$ROOT/home/firefox/addons-pins.json" slugs slug
  sidecar_open "$file" || return 1
  slugs="$(sidecar_get 'keys_unsorted[]')" || return 1
  for slug in $slugs; do
    amo_refresh "$slug" || sidecar_fail "amo: $slug"
  done
  sidecar_close "$file"
}

# --- vscode --------------------------------------------------------------------

vscode_query() { # publisher name: print the extensionquery response
  local body
  body="$(jq -cn --arg id "$1.$2" \
    '{filters: [{criteria: [{filterType: 7, value: $id}]}], flags: 19}')" || return 1
  FIXTURE_KEY="$1.$2" fetch_json "$MARKETPLACE_API" -X POST \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json;api-version=7.1-preview.1' -d "$body"
}

# vscode_pick < response: `version|engine|vsix-sha256` of the newest universal
# version that is not a pre-release (the API lists newest first).
vscode_pick() {
  jq -r '
    [ .results[0].extensions[0].versions[]?
      | select(.targetPlatform == null)
      | ([.properties[]? | {(.key): .value}] | add // {}) as $p
      | select(($p["Microsoft.VisualStudio.Code.PreRelease"] // "") != "true")
      | [.version, ($p["Microsoft.VisualStudio.Code.Engine"] // ""),
         ($p["Microsoft.VisualStudio.Services.VsixSha256"] // "")]
        | join("|") ]
    | first // empty'
}

# engine_exceeds ENGINE LOCKED: the engine range's minimum is newer than LOCKED.
# Numeric, not string, comparison (1.119.0 is newer than 1.75.0). Anything jq
# cannot decide counts as exceeding, so the bump is skipped rather than guessed.
engine_exceeds() {
  local rc=0
  jq -en --arg e "$1" --arg l "$2" '
    def ver: capture("(?<v>[0-9]+(\\.[0-9]+)*)").v | split(".") | map(tonumber) | . + [0, 0, 0] | .[0:3];
    ($e | test("[0-9]")) and (($e | ver) > ($l | ver))' >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 1 ]]
}

# version_newer CANDIDATE CURRENT: 0 when CANDIDATE is strictly newer, 1 when it is
# equal or older, 2 when either is not a plain dotted-number version. Numeric
# comparison padded to equal length (1.10.0 > 1.9.0; 1.2 equals 1.2.0).
version_newer() {
  local rc=0
  jq -en --arg c "$1" --arg l "$2" '
    def ver: capture("\\A(?<v>[0-9]+(\\.[0-9]+)*)\\z").v | split(".") | map(tonumber) | . + [0, 0, 0, 0, 0, 0] | .[0:6];
    ($c | ver) > ($l | ver)' >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0 | 1) return "$rc" ;;
    *) return 2 ;;
  esac
}

vsix_hash() { # publisher name version hex-or-empty
  if [[ "$4" =~ ^[0-9a-f]{64}$ ]]; then
    hex_to_sri "$4"
  else
    prefetch_vsix "$1" "$2" "$3"
  fi
}

# vscode_gate LABEL OLD VER ENGINE LOCKED: 0 to bump, 10 when the pin stays (the
# reason is reported), 1 on a problem. Only a strictly newer version whose engine
# the locked vscode satisfies is bumped: never a downgrade.
vscode_gate() {
  local rc=0
  version_newer "$3" "$2" || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    err "vscode: $1: cannot compare version '$3' with pinned '$2'"
    return 1
  elif [[ "$rc" -eq 1 ]]; then
    note "vscode: $1 unchanged ($3 is not newer than $2)"
    return 10
  elif engine_exceeds "$4" "$5"; then
    note "vscode: $1 $3 skipped (needs engine $4, locked vscode is $5)"
    return 10
  fi
}

# shellcheck disable=SC2016 # jq variables, not shell expansions
vscode_refresh() { # index locked-vscode-version
  local i="$1" pub name old pick ver engine hex hash rc=0
  pub="$(sidecar_get --argjson i "$i" '.[$i].publisher')" || return 1
  name="$(sidecar_get --argjson i "$i" '.[$i].name')" || return 1
  old="$(sidecar_get --argjson i "$i" '.[$i].version')" || return 1
  pick="$(vscode_query "$pub" "$name" | vscode_pick)" || return 1
  if [[ -z "$pick" ]]; then
    err "vscode: $pub.$name: no stable version in the response"
    return 1
  elif [[ "$pick" == *[[:cntrl:]]* ]]; then
    err "vscode: $pub.$name: control characters in the response"
    return 1
  fi
  IFS='|' read -r ver engine hex <<<"$pick"
  if [[ "$ver" == "$old" ]]; then
    note "vscode: $pub.$name unchanged"
    return 0
  fi
  vscode_gate "$pub.$name" "$old" "$ver" "$engine" "$2" || rc=$?
  if [[ "$rc" -eq 10 ]]; then return 0; elif [[ "$rc" -ne 0 ]]; then return 1; fi
  hash="$(vsix_hash "$pub" "$name" "$ver" "$hex")" || return 1
  sidecar_apply --argjson i "$i" --arg v "$ver" --arg h "$hash" \
    '.[$i].version = $v | .[$i].hash = $h' || return 1
  note "vscode: $pub.$name $old -> $ver"
}

update_vscode() {
  local file="$ROOT/home/vscode/extensions-extra.json" locked count i
  sidecar_open "$file" || return 1
  locked="$(locked_vscode_version)" || return 1
  if [[ ! "$locked" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    err "vscode: unusable locked vscode version '$locked'"
    return 1
  fi
  count="$(sidecar_get 'length')" || return 1
  for ((i = 0; i < count; i++)); do
    vscode_refresh "$i" "$locked" || sidecar_fail "vscode: entry $i"
  done
  sidecar_close "$file"
}

# --- bat -----------------------------------------------------------------------

# github_head_sha OWNER/REPO: SHA of the default branch HEAD.
github_head_sha() {
  fetch_json "${GITHUB_API}repos/$1/commits/HEAD" |
    jq -er 'select((.sha // "") | test("^[0-9a-f]{40}$")) | .sha'
}

# shellcheck disable=SC2016 # jq variables, not shell expansions
update_bat() {
  local file="$ROOT/home/bat-theme-pin.json" owner repo rev head hash
  sidecar_open "$file" || return 1
  owner="$(sidecar_get '.owner')" || return 1
  repo="$(sidecar_get '.repo')" || return 1
  rev="$(sidecar_get '.rev')" || return 1
  head="$(github_head_sha "$owner/$repo")" || return 1
  if [[ "$head" == "$rev" ]]; then
    note "bat: $owner/$repo unchanged"
  else
    hash="$(prefetch_bat "$owner" "$repo" "$head")" || return 1
    sidecar_apply --arg r "$head" --arg h "$hash" '.rev = $r | .hash = $h' || return 1
    note "bat: $owner/$repo ${rev:0:7} -> ${head:0:7}"
  fi
  sidecar_close "$file"
}

# --- google-fonts --------------------------------------------------------------

# font_changed_at PATH: date of the newest commit touching PATH.
font_changed_at() {
  fetch_json "${GITHUB_API}repos/google/fonts/commits?path=$1&per_page=1" |
    jq -er '.[0].commit.committer.date | select(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))'
}

# fonts_moved_since DATE: 0 when any pinned font changed after DATE, 1 when none
# did, 2 when a lookup failed. ISO-8601 UTC timestamps compare as strings.
fonts_moved_since() {
  local paths path changed moved=1
  paths="$(sidecar_get '.fonts[].path')" || return 2
  for path in $paths; do
    if ! changed="$(font_changed_at "$path")"; then
      err "google-fonts: no usable commit date for $path"
      return 2
    fi
    if [[ "$changed" > "$1" ]]; then moved=0; fi
  done
  return "$moved"
}

# rehash_fonts REV: set .rev and re-hash every font (root files in the sparse
# checkout can change a hash, so each font is rebuilt even if its path did not move).
# shellcheck disable=SC2016 # jq variables, not shell expansions
rehash_fonts() {
  local rev="$1" names name path hash
  names="$(sidecar_get '.fonts | keys_unsorted[]')" || return 1
  for name in $names; do
    path="$(sidecar_get --arg n "$name" '.fonts[$n].path')" || return 1
    hash="$(prefetch_font "$rev" "$path")" || return 1
    sidecar_apply --arg n "$name" --arg h "$hash" '.fonts[$n].hash = $h' || return 1
  done
  sidecar_apply --arg r "$rev" '.rev = $r'
}

update_google_fonts() {
  local file="$ROOT/overlays/google-fonts/pins.json" rev base head rc=0
  sidecar_open "$file" || return 1
  rev="$(sidecar_get '.rev')" || return 1
  base="$(fetch_json "${GITHUB_API}repos/google/fonts/commits/$rev" |
    jq -er '.commit.committer.date')" || return 1
  fonts_moved_since "$base" || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    note "google-fonts: unchanged"
    return 0
  elif [[ "$rc" -ne 0 ]]; then
    return 1
  fi
  head="$(github_head_sha google/fonts)" || return 1
  rehash_fonts "$head" || return 1
  sidecar_close "$file" || return 1
  note "google-fonts: ${rev:0:7} -> ${head:0:7}"
}

# --- npm -----------------------------------------------------------------------

# npm_highest PINNED < packument: highest plain X.Y.Z in PINNED's major (never
# lower than PINNED). Numeric tuple comparison: 3.10.0 is newer than 3.9.9.
npm_highest() {
  jq -r --arg p "$1" '
    ($p | split(".") | map(tonumber)) as $pin
    | [ .versions | keys[] | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
        | split(".") | map(tonumber) | select(.[0] == $pin[0]) ] + [$pin]
    | max | map(tostring) | join(".")'
}

# npm_latest_major < packument: major of dist-tags.latest.
npm_latest_major() {
  jq -er '.["dist-tags"].latest | select(test("^[0-9]+\\.")) | split(".")[0]'
}

# shellcheck disable=SC2016 # jq variables, not shell expansions
npm_refresh() { # package
  local pkg="$1" pinned doc best major latest
  pinned="$(sidecar_get --arg p "$pkg" '.dependencies[$p]')" || return 1
  if [[ ! "$pinned" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    err "npm: $pkg: pinned version '$pinned' is not a plain X.Y.Z"
    return 1
  fi
  doc="$(fetch_json "$NPM_REGISTRY/$pkg" -H 'Accept: application/vnd.npm.install-v1+json')" || return 1
  best="$(npm_highest "$pinned" <<<"$doc")" || return 1
  latest="$(npm_latest_major <<<"$doc")" || return 1
  major="${pinned%%.*}"
  if [[ "$best" == "$pinned" ]]; then
    note "npm: $pkg unchanged"
  else
    sidecar_apply --arg p "$pkg" --arg v "$best" '.dependencies[$p] = $v' || return 1
    note "npm: $pkg $pinned -> $best"
  fi
  if [[ "$latest" -gt "$major" ]]; then note "npm: $pkg $latest available"; fi
}

update_npm() {
  local file="$ROOT/lib/editor-tooling-package.json" pkg
  sidecar_open "$file" || return 1
  for pkg in $NPM_PACKAGES; do
    npm_refresh "$pkg" || sidecar_fail "npm: $pkg"
  done
  sidecar_close "$file" || return 1
  if [[ "$SIDECAR_CHANGED" -gt 0 ]]; then
    note "npm: run scripts/update-editor-tooling-lock.sh to refresh the lock"
  fi
}

# --- entry point -----------------------------------------------------------------

# run_updater SOURCE: one updater in a subshell with errexit on. bash ignores
# errexit anywhere inside a command used as an `if`/`while`/`&&`/`||` condition, so
# the caller must run this as a plain statement and read $? (see main): a failed
# mid-function step then stops the updater instead of falling through to its write.
run_updater() {
  (
    set -e
    "update_${1//-/_}"
  )
}

need_tools() {
  local tool
  for tool in jq nix; do
    command -v "$tool" >/dev/null 2>&1 || { err "$tool is required (run inside 'nix develop')"; return 1; }
  done
  if ! use_fixtures; then
    command -v curl >/dev/null 2>&1 || { err "curl is required"; return 1; }
  fi
}

# parse_args ARGS...: sets ROOT and SELECTED (one source at most).
SELECTED="all"
SOURCE_GIVEN=0
select_source() { # source: a second source is a usage error, never "last wins"
  if [[ "$SOURCE_GIVEN" -ne 0 ]]; then
    err "only one source may be given (got '$SELECTED' and '$1')"
    usage >&2
    exit 2
  fi
  SOURCE_GIVEN=1
  SELECTED="$1"
}

parse_args() {
  ROOT="${UPDATE_PINS_ROOT:-$REPO_ROOT}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)
        [[ $# -ge 2 ]] || { usage >&2; exit 2; }
        ROOT="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      amo | google-fonts | bat | vscode | npm | all)
        select_source "$1"
        shift
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
  done
  [[ -d "$ROOT" ]] || { err "root is not a directory: $ROOT"; exit 2; }
  ROOT="$(cd "$ROOT" && pwd)"
}

main() {
  local source rc failed=0
  parse_args "$@"
  need_tools || return 1
  if [[ "$SELECTED" == "all" ]]; then
    SELECTED="$SOURCES"
  fi
  for source in $SELECTED; do
    rc=0
    set +e # not `if ! run_updater`: that would make bash ignore errexit inside it
    run_updater "$source"
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
      err "$source: update failed"
      failed=1
    fi
  done
  return "$failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
