#!/usr/bin/env bash
# Focused regression checks for default-install and JSON-config correctness.
#
# Usage: scripts/test-correctness.sh [apps|gc|android|git|shell|host|schema|cursor|wrapper|release|pins|all]
#   (default: all). Run from anywhere; the repo root is derived from this file.
#
# Tools (nix, jq, python3 jsonschema) are only required by the cases that use
# them, so `wrapper` also runs under the stock macOS /bin/bash 3.2. Everything is
# Bash 3.2 compatible: no mapfile, associative arrays, ${var,,} or |&.
#
# No case activates a system, escalates privileges, garbage-collects, or builds
# the Android SDK or a full darwin system: app tests use fake nix/sudo/
# darwin-rebuild executables, and the other cases only evaluate (the cursor case
# also builds one tiny writeShellScript to run it against a fake cursor).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=""
CHECKS=0
FAILURES=0

# --- reporting -------------------------------------------------------------

indent() { sed 's/^/       /'; }

pass() {
  CHECKS=$((CHECKS + 1))
  printf 'ok     %s\n' "$1"
}

# fail LABEL [DETAIL...]: record a failed assertion; each detail is indented.
fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  printf 'FAIL   %s\n' "$1" >&2
  shift
  while [ $# -gt 0 ]; do
    printf '%s\n' "$1" | indent >&2
    shift
  done
}

# die MESSAGE: harness/environment problem (not a regression); stops the run.
die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

check_eq() { # label expected actual
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1" "expected: $2" "actual:   $3"
  fi
}

check_contains() { # label haystack needle
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass "$1"
  else
    fail "$1" "missing: $3" "in: $2"
  fi
}

need_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required (run inside 'nix develop')"
  done
}

# --- temp fixtures ---------------------------------------------------------

init_tmp() {
  if [ -z "$TMP" ]; then
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotnix-correctness.XXXXXX")"
  fi
}

cleanup() {
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    # Fixtures include read-only directories (a stand-in for the Nix store).
    chmod -R u+w "$TMP" 2>/dev/null || true
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

default_host() {
  jq -r '.defaultHost // .hosts[0]' "$ROOT/config/hosts.json"
}

# row ARG...: tab-joined record, the format the fake executables log in.
row() {
  local IFS=$'\t'
  printf '%s\n' "$*"
}

# run_eval CMD...: capture stdout/stderr/status of a nix evaluation.
EVAL_OUT=""
EVAL_ERR=""
EVAL_RC=0
run_eval() {
  EVAL_RC=0
  EVAL_OUT="$("$@" 2>"$TMP/eval.err")" || EVAL_RC=$?
  EVAL_ERR="$(cat "$TMP/eval.err")"
}

# --- fake executables (apps + wrapper) ---------------------------------------
# Every fake appends one tab-separated line to $FAKE_LOG: name, then its args.

write_fake_nix() { # path
  cat >"$1" <<'FAKE'
#!/bin/sh
PATH=/usr/bin:/bin
{ printf 'nix'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$FAKE_LOG"
if [ "${FAKE_NIX_RC:-0}" != 0 ]; then
  echo "fake nix: simulated failure" >&2
  exit "$FAKE_NIX_RC"
fi
case " $* " in
  *" build "*)
    # Real `nix build` drops a ./result symlink unless --no-link is given.
    case " $* " in
      *" --no-link "*) ;;
      *) ln -s "$FAKE_SYSTEM_PATH" result || exit 1 ;;
    esac
    case " $* " in
      *" --print-out-paths "*) printf '%s\n' "$FAKE_SYSTEM_PATH" ;;
    esac
    ;;
esac
exit 0
FAKE
  chmod +x "$1"
}

write_fake_sudo() { # path; logs, then runs the command WITHOUT elevating
  cat >"$1" <<'FAKE'
#!/bin/sh
{ printf 'sudo'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$FAKE_LOG"
exec "$@"
FAKE
  chmod +x "$1"
}

write_fake_rebuild() { # path; logs "rebuild<TAB>args" (the installed darwin-rebuild)
  cat >"$1" <<'FAKE'
#!/bin/sh
{ printf 'rebuild'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$FAKE_LOG"
FAKE
  chmod +x "$1"
}

write_fake_system_rebuild() { # path; logs "sysrebuild<TAB>$0<TAB>args" (the built system's)
  cat >"$1" <<'FAKE'
#!/bin/sh
{ printf 'sysrebuild\t%s' "$0"; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$FAKE_LOG"
FAKE
  chmod +x "$1"
}

# --- case: wrapper -----------------------------------------------------------

test_wrapper() {
  local bin log
  init_tmp
  if [ -x "$ROOT/build-darwin.sh" ]; then
    pass "wrapper: build-darwin.sh is executable"
  else
    fail "wrapper: build-darwin.sh is executable" "build-darwin.sh lacks the executable bit (chmod +x build-darwin.sh)"
  fi

  bin="$TMP/wrapper/bin"
  log="$TMP/wrapper/log"
  mkdir -p "$bin"
  write_fake_nix "$bin/nix"

  # Invoke through sh so argument forwarding is checked independently of the mode.
  : >"$log"
  env -i PATH="$bin:/usr/bin:/bin" FAKE_LOG="$log" sh "$ROOT/build-darwin.sh"
  check_eq "wrapper: no host runs the default switch app" \
    "$(row nix run '.#switch')" "$(cat "$log")"

  : >"$log"
  env -i PATH="$bin:/usr/bin:/bin" FAKE_LOG="$log" sh "$ROOT/build-darwin.sh" some-host
  check_eq "wrapper: host argument is forwarded to the switch app" \
    "$(row nix run '.#switch' -- some-host)" "$(cat "$log")"
}

# --- case: apps ----------------------------------------------------------------
# The built apps `export PATH=<runtimeInputs>:$PATH` and `cd` into the read-only
# store flakeRoot. To exercise them against fakes, a copy of each built script is
# made with the PATH export removed and the cd retargeted to a read-only fixture
# directory; the rest of the script body is untouched.

APPS_DIR=""
APPS_LOG=""
APPS_FLAKE=""
APPS_CWD=""
APPS_SYS=""
APPS_HOST=""
APP_RC=0
APP_OUT=""

build_apps() {
  local out
  out="$(cd "$ROOT" && nix build --no-link --print-out-paths \
    '.#scripts.switchApp' '.#scripts.changelogApp' 2>"$TMP/build.err")" ||
    die "nix build of the switch/changelog apps failed: $(cat "$TMP/build.err")"
  SWITCH_BUILT="$(printf '%s\n' "$out" | grep -- '-darwin-switch$')/bin/darwin-switch"
  CHANGELOG_BUILT="$(printf '%s\n' "$out" | grep -- '-darwin-changelog$')/bin/darwin-changelog"
  [ -f "$SWITCH_BUILT" ] || die "built switch app not found: $SWITCH_BUILT"
  [ -f "$CHANGELOG_BUILT" ] || die "built changelog app not found: $CHANGELOG_BUILT"
}

prepare_app_script() { # built-script destination
  # shellcheck disable=SC2016  # the single-quoted $ is a literal regex anchor/char
  sed -e '/^export PATH="\/nix\/store\/.*:\$PATH"$/d' \
    -e "s|^cd \"/nix/store/.*\"\$|cd \"$APPS_FLAKE\"|" "$1" >"$2"
  chmod +x "$2"
  if grep -q '^export PATH=' "$2" || ! grep -qF "cd \"$APPS_FLAKE\"" "$2"; then
    die "could not retarget PATH/cd in $1 (writeShellApplication output changed?)"
  fi
}

setup_app_fixtures() {
  APPS_DIR="$TMP/apps"
  APPS_LOG="$APPS_DIR/log"
  APPS_FLAKE="$APPS_DIR/flake"
  APPS_CWD="$APPS_DIR/cwd"
  # A path with spaces proves the returned build output is quoted correctly.
  APPS_SYS="$APPS_DIR/out put/system"
  APPS_HOST="$(default_host)"

  mkdir -p "$APPS_DIR/bin-with" "$APPS_DIR/bin-without" "$APPS_CWD" \
    "$APPS_FLAKE" "$APPS_SYS/sw/bin"
  for variant in with without; do
    write_fake_nix "$APPS_DIR/bin-$variant/nix"
    write_fake_sudo "$APPS_DIR/bin-$variant/sudo"
  done
  write_fake_rebuild "$APPS_DIR/bin-with/darwin-rebuild"
  write_fake_system_rebuild "$APPS_SYS/sw/bin/darwin-rebuild"
  : >"$APPS_FLAKE/flake.nix"
  # Stand-in for the read-only store: any write into it fails.
  chmod -R a-w "$APPS_FLAKE"

  prepare_app_script "$SWITCH_BUILT" "$APPS_DIR/switch"
  prepare_app_script "$CHANGELOG_BUILT" "$APPS_DIR/changelog"
}

# run_app KIND VARIANT HOST_ARG HOST_ENV: empty HOST_ARG/HOST_ENV are omitted
# entirely (no argument / HOST unset). Variant "with" has an installed
# darwin-rebuild first on PATH, "without" does not. PATH is only the fake dir.
run_app() {
  : >"$APPS_LOG"
  APP_RC=0
  APP_OUT="$(cd "$APPS_CWD" && env -i PATH="$APPS_DIR/bin-$2" \
    FAKE_LOG="$APPS_LOG" FAKE_SYSTEM_PATH="$APPS_SYS" \
    FAKE_NIX_RC="${FAKE_NIX_RC:-0}" ${4:+HOST="$4"} "$APPS_DIR/$1" ${3:+"$3"} 2>&1)" || APP_RC=$?
}

nix_build_row() { # host
  row nix build --no-link --print-out-paths ".#darwinConfigurations.$1.system"
}

expected_fast_rows() { # kind host
  if [ "$1" = switch ]; then
    row sudo darwin-rebuild switch --flake ".#$2"
  fi
  row rebuild "$1" --flake ".#$2"
}

expected_fallback_rows() { # kind host
  local rebuild="$APPS_SYS/sw/bin/darwin-rebuild"
  nix_build_row "$2"
  if [ "$1" = switch ]; then
    row sudo "$rebuild" switch --flake ".#$2"
  fi
  row sysrebuild "$rebuild" "$1" --flake ".#$2"
}

check_app_untouched() { # label
  check_eq "$1: no result symlink or writes in the flake dir" \
    "flake.nix" "$(ls -A "$APPS_FLAKE")"
  check_eq "$1: no result symlink or writes in the cwd" "" "$(ls -A "$APPS_CWD")"
}

check_app_run() { # label expected-rc expected-log
  if [ "$APP_RC" != "$2" ]; then
    fail "$1: exit status" "expected: $2" "actual:   $APP_RC" "output: $APP_OUT"
  else
    pass "$1: exit status"
  fi
  check_eq "$1: calls" "$3" "$(cat "$APPS_LOG")"
  check_app_untouched "$1"
}

# app_scenario KIND VARIANT HOST_ARG HOST_ENV EXPECTED_HOST
app_scenario() {
  local kind=$1 variant=$2 expected
  if [ "$variant" = with ]; then
    expected="$(expected_fast_rows "$kind" "$5")"
  else
    expected="$(expected_fallback_rows "$kind" "$5")"
  fi
  run_app "$kind" "$variant" "$3" "$4"
  check_app_run "$kind/$variant host arg='$3' env='$4'" 0 "$expected"
}

test_app_kind() { # kind
  local kind=$1
  # Installed darwin-rebuild (fast path) vs missing (first-install fallback);
  # default, explicit, env, and explicit-over-env host selection.
  local variant
  for variant in with without; do
    app_scenario "$kind" "$variant" "" "" "$APPS_HOST"
    app_scenario "$kind" "$variant" "alpha" "" "alpha"
    app_scenario "$kind" "$variant" "" "beta" "beta"
    app_scenario "$kind" "$variant" "alpha" "beta" "alpha"
  done

  # A failing fallback build must propagate its status and never reach rebuild.
  FAKE_NIX_RC=3 run_app "$kind" without "" ""
  check_app_run "$kind/without build failure" 3 "$(nix_build_row "$APPS_HOST")"
}

test_apps() {
  need_tools nix jq
  init_tmp
  build_apps
  setup_app_fixtures
  test_app_kind switch
  test_app_kind changelog
}

# --- case: gc ------------------------------------------------------------------

test_gc() {
  need_tools nix jq
  init_tmp
  local host attr interval
  host="$(default_host)"
  attr=".#darwinConfigurations.${host}.config"

  run_eval nix eval --json "$attr.launchd.daemons.nix-gc.serviceConfig.StartCalendarInterval"
  if [ "$EVAL_RC" != 0 ]; then
    fail "gc: evaluate StartCalendarInterval" "$EVAL_ERR"
  else
    # launchd accepts an attrset or a list of attrsets; normalise to a list.
    interval="$(jq -c 'if type == "array" then . else [.] end' <<<"$EVAL_OUT")"
    check_gc_interval "$interval"
  fi

  check_gc_option "$attr" automatic "true"
  check_gc_option "$attr" options '"--delete-older-than 14d"'
  check_optimise "$attr"
}

# nix.optimise replaces auto-optimise-store; the legacy setting must not be forced on.
check_optimise() { # attr
  local interval
  run_eval nix eval --json "$1.nix.optimise.automatic"
  if [ "$EVAL_RC" != 0 ]; then
    fail "gc: evaluate nix.optimise.automatic" "$EVAL_ERR"
  else
    check_eq "gc: nix.optimise.automatic" "true" "$EVAL_OUT"
  fi

  check_auto_optimise_store_off "$1"

  run_eval nix eval --json "$1.nix.optimise.interval"
  if [ "$EVAL_RC" != 0 ]; then
    fail "gc: evaluate nix.optimise.interval" "$EVAL_ERR"
  else
    interval="$(jq -c 'if type == "array" then . else [.] end' <<<"$EVAL_OUT")"
    check_optimise_interval "$interval"
  fi
}

# Any result other than JSON true (false or null) passes.
check_auto_optimise_store_off() { # attr
  run_eval nix eval --json "$1.nix.settings.auto-optimise-store"
  if [ "$EVAL_RC" != 0 ]; then
    fail "gc: evaluate nix.settings.auto-optimise-store" "$EVAL_ERR"
  elif [ "$EVAL_OUT" = "true" ]; then
    fail "gc: nix.settings.auto-optimise-store must not be true" "use nix.optimise.automatic instead"
  else
    pass "gc: nix.settings.auto-optimise-store is not true ($EVAL_OUT)"
  fi
}

check_optimise_interval() { # normalised-json-list
  check_eq "gc: optimise one calendar entry" "1" "$(jq 'length' <<<"$1")"
  check_eq "gc: optimise Weekday is Sunday (0)" "0" "$(jq -c '.[0].Weekday' <<<"$1")"
  check_eq "gc: optimise Hour is 4" "4" "$(jq -c '.[0].Hour' <<<"$1")"
  check_eq "gc: optimise Minute is 0" "0" "$(jq -c '.[0].Minute' <<<"$1")"
}

# nix.gc is evaluated per option: the whole attrset also forces the removed `dates`.
check_gc_option() { # attr option expected-json
  run_eval nix eval --json "$1.nix.gc.$2"
  if [ "$EVAL_RC" != 0 ]; then
    fail "gc: evaluate nix.gc.$2" "$EVAL_ERR"
  else
    check_eq "gc: nix.gc.$2" "$3" "$EVAL_OUT"
  fi
}

check_gc_interval() { # normalised-json-list
  check_eq "gc: one calendar entry" "1" "$(jq 'length' <<<"$1")"
  check_eq "gc: Weekday is Sunday (0)" "0" "$(jq -c '.[0].Weekday' <<<"$1")"
  check_eq "gc: Hour is 3" "3" "$(jq -c '.[0].Hour' <<<"$1")"
  check_eq "gc: Minute is 0" "0" "$(jq -c '.[0].Minute' <<<"$1")"
  check_eq "gc: no Day-of-month restriction" "null" "$(jq -c '.[0].Day' <<<"$1")"
}

# --- case: android -------------------------------------------------------------

ANDROID_DEFAULTS='{"platformVersions":["34","35"],"systemImageTypes":["google_apis_playstore"],"abiVersions":["arm64-v8a"]}'
ANDROID_BASE_LISTS='{"platformVersions":["35"],"systemImageTypes":["google_apis"],"abiVersions":["x86_64"]}'
ANDROID_CASES=""

# The loader is called on fixture roots (plain paths, not a flake snapshot) and
# its output is fed to home/android.nix as androidConfig. With enable = false the
# module's SDK composition is never forced, so no SDK is realised. Module checking
# is off only because the module also defines undeclared home-manager options.
nix_android_expr() {
  cat <<'NIX'
let
  rootDir = builtins.getEnv "T_ROOT";
  fixDir = builtins.getEnv "T_FIX";
  lib = (builtins.getFlake "git+file://${rootDir}").inputs.nixpkgs.lib;
  starter = import "${rootDir}/lib" { inherit lib; };
  moduleOf =
    androidConfig:
    (lib.evalModules {
      modules = [
        "${rootDir}/home/android.nix"
        {
          config._module.check = false;
          config._module.args = {
            pkgs = { };
            inherit androidConfig;
          };
          options.xdg.configHome = lib.mkOption {
            type = lib.types.str;
            default = "/home/test/.config";
          };
        }
      ];
    }).config.my.android;
  run =
    name:
    let
      loader = starter.loadAndroidConfig "${fixDir}/${name}" "h";
    in
    {
      inherit loader;
      my = {
        inherit (moduleOf loader)
          enable
          avdHome
          guiSdkSymlink
          avdDefaultSymlink
          jdkPackage
          platformVersions
          systemImageTypes
          abiVersions
          ;
      };
    };
in
lib.genAttrs (lib.splitString " " (builtins.getEnv "T_CASES")) run
NIX
}

nix_android_loader_expr() {
  cat <<'NIX'
let
  rootDir = builtins.getEnv "T_ROOT";
  lib = (builtins.getFlake "git+file://${rootDir}").inputs.nixpkgs.lib;
  starter = import "${rootDir}/lib" { inherit lib; };
in
starter.loadAndroidConfig "${builtins.getEnv "T_FIX"}/${builtins.getEnv "T_CASE"}" "h"
NIX
}

# android_case NAME BASE_JSON|- HOST_JSON EXPECTED_LISTS_JSON
android_case() {
  local dir="$TMP/android/$1"
  mkdir -p "$dir/config/android/hosts"
  if [ "$2" != "-" ]; then
    printf '%s\n' "$2" >"$dir/config/android/base.json"
  fi
  printf '%s\n' "$3" >"$dir/config/android/hosts/h.json"
  printf '%s\n' "$4" >"$TMP/android/$1.expected"
  ANDROID_CASES="$ANDROID_CASES $1"
}

# host_override KEY VALUE: base sets every list, host overrides only KEY.
android_host_override_case() {
  local expected
  expected="$(jq -c --arg k "$1" --argjson v "$2" '.[$k] = $v' <<<"$ANDROID_BASE_LISTS")"
  android_case "host-overrides-$1" "$ANDROID_BASE_LISTS" \
    "$(jq -nc --arg k "$1" --argjson v "$2" '{($k): $v}')" "$expected"
}

define_android_cases() {
  local empty='{"platformVersions":[],"systemImageTypes":[],"abiVersions":[]}'
  android_case missing-base - '{"enable":true}' "$ANDROID_DEFAULTS"
  android_case empty-config '{}' '{}' "$ANDROID_DEFAULTS"
  android_case base-only "$ANDROID_BASE_LISTS" '{}' "$ANDROID_BASE_LISTS"
  android_host_override_case platformVersions '["36"]'
  android_host_override_case systemImageTypes '["google_apis","google_apis_playstore"]'
  android_host_override_case abiVersions '["arm64-v8a","x86_64"]'
  android_case host-empty-lists "$ANDROID_BASE_LISTS" "$empty" "$empty"
  android_case base-empty-lists "$empty" '{}' "$empty"
}

check_android_case() { # name results-json
  local name=$1 expected got
  expected="$(jq -cS . "$TMP/android/$name.expected")"
  got="$(jq -cS --arg n "$name" '.[$n].my | {platformVersions, systemImageTypes, abiVersions}' <<<"$2")"
  check_eq "android/$name: lists reach my.android" "$expected" "$got"
  if [ "$name" = missing-base ]; then
    check_eq "android/$name: loader returns { enable = false; }" \
      '{"enable":false}' "$(jq -cS --arg n "$name" '.[$n].loader' <<<"$2")"
  else
    got="$(jq -cS --arg n "$name" '.[$n].loader | {platformVersions, systemImageTypes, abiVersions}' <<<"$2")"
    check_eq "android/$name: loader returns the lists" "$expected" "$got"
  fi
}

test_android_scalars() { # results-json (case empty-config)
  local got
  got="$(jq -cS '."empty-config".my | {enable, avdHome: (.avdHome | endswith("/.android/avd")), guiSdkSymlink, avdDefaultSymlink, jdkPackage}' <<<"$1")"
  check_eq "android/empty-config: scalar module defaults preserved" \
    '{"avdDefaultSymlink":true,"avdHome":true,"enable":false,"guiSdkSymlink":true,"jdkPackage":"jdk"}' "$got"
}

test_android_forbidden_enable() {
  local dir="$TMP/android/forbidden-enable"
  mkdir -p "$dir/config/android/hosts"
  printf '%s\n' '{"enable":true}' >"$dir/config/android/base.json"
  printf '%s\n' '{}' >"$dir/config/android/hosts/h.json"
  export T_CASE=forbidden-enable
  run_eval nix eval --impure --json --expr "$(nix_android_loader_expr)"
  if [ "$EVAL_RC" = 0 ]; then
    fail "android/base enable is rejected" "loader accepted base.json with enable: $EVAL_OUT"
  else
    check_contains "android/base enable is rejected" "$EVAL_ERR" 'must not contain "enable"'
  fi
}

test_android_loader() {
  export T_ROOT="$ROOT" T_FIX="$TMP/android"
  define_android_cases
  export T_CASES="${ANDROID_CASES# }"
  run_eval nix eval --impure --json --expr "$(nix_android_expr)"
  if [ "$EVAL_RC" != 0 ]; then
    fail "android: evaluate loader + my.android" "$EVAL_ERR"
    return 0
  fi
  local name
  for name in $T_CASES; do
    check_android_case "$name" "$EVAL_OUT"
  done
  test_android_scalars "$EVAL_OUT"
  test_android_forbidden_enable
}

# schema_check SCHEMA LABEL valid|invalid JSON
# SCHEMA is the file stem under config/schema (android -> android.schema.json).
schema_check() {
  local schema="$1" label="$2" want="$3" doc="$4"
  local file="$TMP/schema/$((CHECKS + 1)).json" rc=0
  mkdir -p "$TMP/schema"
  printf '%s\n' "$doc" >"$file"
  python3 - "$ROOT/config/schema/$schema.schema.json" "$file" <<'PY' || rc=$?
import json
import sys

from jsonschema import Draft202012Validator

with open(sys.argv[1]) as f:
    schema = json.load(f)
with open(sys.argv[2]) as f:
    data = json.load(f)
# Exit 4 means "invalid"; any other non-zero status is a harness error.
sys.exit(4 if list(Draft202012Validator(schema).iter_errors(data)) else 0)
PY
  if [ "$rc" != 0 ] && [ "$rc" != 4 ]; then
    die "schema validation harness error (status $rc) for $schema: $doc"
  fi
  if [ "$want" = valid ] && [ "$rc" = 0 ]; then
    pass "schema: accepts $label"
  elif [ "$want" = invalid ] && [ "$rc" != 0 ]; then
    pass "schema: rejects $label"
  else
    fail "schema: should $([ "$want" = valid ] && echo accept || echo reject) $label" "document: $doc"
  fi
}

test_android_schema() {
  python3 -c 'import jsonschema' 2>/dev/null || die "python jsonschema is required (run inside 'nix develop')"
  schema_check android "lists of strings" valid "$(jq -c '. + {"enable": true}' <<<"$ANDROID_BASE_LISTS")"
  schema_check android "explicit empty lists" valid '{"platformVersions":[],"systemImageTypes":[],"abiVersions":[]}'
  schema_check android "existing scalar keys" valid \
    '{"enable":true,"avdHome":"/x","guiSdkSymlink":true,"avdDefaultSymlink":false,"jdkPackage":"jdk17"}'
  schema_check android "the shipped base.json" valid "$(cat "$ROOT/config/android/base.json")"
  schema_check android "an unknown key (typo)" invalid '{"platformVersion":["34"]}'
  schema_check android "a string where a list is expected" invalid '{"platformVersions":"34"}'
  schema_check android "an object where a list is expected" invalid '{"systemImageTypes":{"a":1}}'
  schema_check android "a number where a list is expected" invalid '{"abiVersions":5}'
  schema_check android "a non-string platformVersions element" invalid '{"platformVersions":[34]}'
  schema_check android "a null abiVersions element" invalid '{"abiVersions":["arm64-v8a",null]}'
}

test_android() {
  need_tools nix jq python3
  init_tmp
  test_android_loader
  test_android_schema
}

# --- Home Manager shape evaluation (git, shell, host, cursor) --------------------

# Shared Nix prelude (an open `let`): each case appends its own bindings and the
# `in` body. pkgsUnfree lets _1password-cli and editor extensions evaluate.
nix_hm_prelude() {
  cat <<'NIX'
let
  rootDir = builtins.getEnv "T_ROOT";
  flake = builtins.getFlake "git+file://${rootDir}";
  hm = flake.inputs.home-manager;
  inherit (flake.inputs.nixpkgs) lib;
  system = builtins.currentSystem;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
  pkgsUnfree = import flake.inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  userConfig = {
    name = "Test User";
    email = "test@example.com";
    defaultSigningKey = "ssh-ed25519 AAAA";
  };
  appConfigOf = casks: {
    inherit casks;
    system = [ ];
    user = [ ];
  };
  mkWritableOf =
    pkgs:
    import "${rootDir}/lib/mk-writable-copy-activation.nix" {
      hmLib = hm.lib;
      inherit lib pkgs;
    };
  evalHm =
    {
      pkgs,
      modules,
      args,
    }:
    (hm.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = modules ++ [
        {
          home = {
            username = "tester";
            homeDirectory = "/Users/tester";
            stateVersion = "25.11";
          };
        }
      ];
      extraSpecialArgs = args;
    }).config;
NIX
}

# eval_shapes EXPR: evaluate an attrset of independent probes as JSON. Each probe
# is wrapped in tryEval, so one that cannot evaluate yet (an option a later step
# adds, say) reports ok=false instead of hiding the others.
eval_shapes() {
  run_eval nix eval --impure --json --expr "let s = $1; in builtins.mapAttrs (_: v: let t = builtins.tryEval (builtins.deepSeq v v); in if t.success then t.value // { ok = true; } else { ok = false; }) s"
}

# err_summary: the key lines of the last evaluation's stderr (else its tail).
err_summary() {
  local keys
  keys="$(printf '%s\n' "$EVAL_ERR" | grep -E 'error:|does not exist|conflict' | head -n 3 || true)"
  if [ -n "$keys" ]; then
    printf '%s\n' "$keys"
  else
    printf '%s\n' "$EVAL_ERR" | tail -n 8
  fi
}

# shape_ok LABEL RESULTS_JSON EXPR NAME: pass-through guard for a probe; on a
# failed probe, re-evaluates it alone to surface the Nix error and returns 1.
shape_ok() {
  if [ "$(jq -r --arg n "$4" '.[$n].ok' <<<"$2")" = true ]; then
    return 0
  fi
  run_eval nix eval --impure --json --expr "let s = $3; in s.\"$4\""
  fail "$1: evaluates" "$(err_summary)"
  return 1
}

# The checks below print only the matching lines (never the whole generated
# file), since the texts they inspect are long.
check_has() { # label haystack needle
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass "$1"
  else
    fail "$1" "missing: $3"
  fi
}

check_lacks() { # label haystack needle
  if printf '%s\n' "$2" | grep -nF -- "$3" >"$TMP/match.out"; then
    fail "$1" "unexpected: $3" "$(cat "$TMP/match.out")"
  else
    pass "$1"
  fi
}

# check_no_line LABEL TEXT ERE: no line of TEXT matches the extended regex.
check_no_line() {
  if printf '%s\n' "$2" | grep -nE -- "$3" >"$TMP/match.out"; then
    fail "$1" "unexpected line matching: $3" "$(cat "$TMP/match.out")"
  else
    pass "$1"
  fi
}

# --- case: git -----------------------------------------------------------------

# Evaluates the real home/git.nix through Home Manager for the gitConfig shapes
# (no includes key, empty list, several conditional/unconditional includes) and
# the 1Password signing shapes (casks, option override, no appConfig at all,
# appConfig via _module.args).
# Only the git config file and include list are read, so nothing is built.
nix_git_expr() {
  nix_hm_prelude
  cat <<'NIX'
  evalGit =
    {
      gitConfig ? { },
      casks ? null,
      modules ? [ ],
    }:
    let
      cfg = evalHm {
        inherit pkgs;
        modules = [ "${rootDir}/home/git.nix" ] ++ modules;
        args = {
          inherit gitConfig userConfig;
        }
        // lib.optionalAttrs (casks != null) { appConfig = appConfigOf casks; };
      };
    in
    {
      includes = map (i: {
        file = baseNameOf (toString i.path);
        condition = i.condition or null;
      }) cfg.programs.git.includes;
      text = cfg.xdg.configFile."git/config".text;
    };
in
{
  missing = evalGit { casks = [ ]; };
  empty = evalGit {
    casks = [ ];
    gitConfig.includes = [ ];
  };
  multi = evalGit {
    casks = [ ];
    gitConfig.includes = [
      { path = "/fixture/user-a.gitconfig"; }
      {
        condition = "gitdir:~/work/";
        path = "/fixture/user-b.gitconfig";
      }
      { path = "/fixture/user-c.gitconfig"; }
      {
        condition = "hasconfig:remote.*.url:git@github.com:acme/**";
        path = "/fixture/user-d.gitconfig";
      }
    ];
  };
  nocask = evalGit { casks = [ "firefox" ]; };
  cask = evalGit { casks = [ "1password" ]; };
  beta = evalGit { casks = [ "1password@beta" ]; };
  clionly = evalGit { casks = [ "1password-cli" ]; };
  override = evalGit {
    casks = [ ];
    modules = [ { my.onePassword.enable = true; } ];
  };
  noappconfig = evalGit { };
  # appConfig supplied via _module.args instead of extraSpecialArgs.
  moduleargs = evalGit {
    modules = [ { _module.args.appConfig = appConfigOf [ "1password" ]; } ];
  };
}
NIX
}

expected_git_includes() { # missing|multi
  cat <<'JSON'
{"missing":[{"file":"delta-catppuccin.gitconfig","condition":null}],
 "multi":[{"file":"delta-catppuccin.gitconfig","condition":null},
  {"file":"user-a.gitconfig","condition":null},
  {"file":"user-b.gitconfig","condition":"gitdir:~/work/"},
  {"file":"user-c.gitconfig","condition":null},
  {"file":"user-d.gitconfig","condition":"hasconfig:remote.*.url:git@github.com:acme/**"}]}
JSON
}

check_git_results() { # results-json
  local sections want
  want="$(expected_git_includes)"
  check_eq "git/missing includes: only the delta theme" \
    "$(jq -cS '.missing' <<<"$want")" "$(jq -cS '.missing.includes' <<<"$1")"
  check_eq "git/empty includes: only the delta theme" \
    "$(jq -cS '.missing' <<<"$want")" "$(jq -cS '.empty.includes' <<<"$1")"
  check_eq "git/multi: delta first, then user includes in order, conditions intact" \
    "$(jq -cS '.multi' <<<"$want")" "$(jq -cS '.multi.includes' <<<"$1")"
  # Only the include sections of the generated config are compared.
  sections="$(jq -r '.multi.text' <<<"$1" | grep -A1 '^\[include' || true)"
  check_contains "git/multi: generated config has the delta theme path" "$sections" 'delta-catppuccin.gitconfig'
  check_contains "git/multi: generated config has unconditional user include" "$sections" 'path = "/fixture/user-a.gitconfig"'
  check_contains "git/multi: generated config has gitdir includeIf" "$sections" '[includeIf "gitdir:~/work/"]'
  check_contains "git/multi: generated config has hasconfig includeIf" "$sections" \
    '[includeIf "hasconfig:remote.*.url:git@github.com:acme/**"]'
  check_contains "git/multi: generated config has conditional user path" "$sections" 'path = "/fixture/user-d.gitconfig"'
}

check_git_signing_off() { # label text
  check_lacks "$1: no gpgSign" "$2" 'gpgSign'
  check_lacks "$1: no op-ssh-sign" "$2" 'op-ssh-sign'
  check_lacks "$1: no [gpg section" "$2" '[gpg'
  check_has "$1: keeps user.signingKey" "$2" 'signingKey'
}

check_git_signing_on() { # label text
  check_has "$1: op-ssh-sign program" "$2" 'op-ssh-sign'
  check_has "$1: gpgSign = true" "$2" 'gpgSign = true'
  check_has "$1: gpg format ssh" "$2" 'format = "ssh"'
}

# git_signing_shape RESULTS_JSON NAME on|off
git_signing_shape() {
  local text
  shape_ok "git/$2" "$1" "$SHAPES_EXPR" "$2" || return 0
  text="$(jq -r --arg n "$2" '.[$n].text' <<<"$1")"
  "check_git_signing_$3" "git/$2" "$text"
}

check_git_signing() { # results-json
  git_signing_shape "$1" nocask off
  git_signing_shape "$1" cask on
  git_signing_shape "$1" beta on
  git_signing_shape "$1" clionly off
  git_signing_shape "$1" override on
  git_signing_shape "$1" noappconfig off
  git_signing_shape "$1" moduleargs on
}

test_git() {
  need_tools nix jq
  init_tmp
  export T_ROOT="$ROOT"
  SHAPES_EXPR="$(nix_git_expr)"
  eval_shapes "$SHAPES_EXPR"
  if [ "$EVAL_RC" != 0 ]; then
    fail "git: evaluate home/git.nix" "$EVAL_ERR"
    return 0
  fi
  check_git_results "$EVAL_OUT"
  check_git_signing "$EVAL_OUT"
}

# --- case: shell -----------------------------------------------------------------

# Evaluates the real home/zsh.nix through Home Manager for four appConfig shapes
# (no appConfig arg, no op/fnm apps, op as a Nix app, op via _module.args). initContent, profileExtra
# and the zcompdump activation entry are read; _1password-cli is never built.
nix_shell_expr() {
  nix_hm_prelude
  cat <<'NIX'
  evalZshWith =
    modules: args:
    let
      cfg = evalHm {
        pkgs = pkgsUnfree;
        modules = [ "${rootDir}/home/zsh.nix" ] ++ modules;
        args = {
          inherit userConfig;
          systemConfig.homebrewPrefix = "/opt/homebrew";
          mkWritableCopyActivation = mkWritableOf pkgsUnfree;
        }
        // args;
      };
    in
    {
      initContent = cfg.programs.zsh.initContent;
      profileExtra = cfg.programs.zsh.profileExtra;
      zcompdump = {
        inherit (cfg.home.activation.clearStaleZcompdump) after before;
      };
    };
  evalZsh = evalZshWith [ ];
in
{
  noappconfig = evalZsh { };
  noop = evalZsh { appConfig = appConfigOf [ ]; };
  nixop = evalZsh {
    appConfig = (appConfigOf [ ]) // {
      system = [ "_1password-cli" ];
    };
  };
  # appConfig supplied via _module.args instead of extraSpecialArgs.
  moduleargs = evalZshWith [
    {
      _module.args.appConfig = (appConfigOf [ ]) // {
        system = [ "_1password-cli" ];
      };
    }
  ] { };
}
NIX
}

# zsh_syntax LABEL TEXT FILE: `zsh -n` on TEXT written under $TMP/zsh.
zsh_syntax() {
  mkdir -p "$TMP/zsh"
  printf '%s\n' "$2" >"$TMP/zsh/$3"
  if zsh -n "$TMP/zsh/$3" 2>"$TMP/zsh/err"; then
    pass "$1: zsh -n accepts $3"
  else
    fail "$1: zsh -n accepts $3" "$(cat "$TMP/zsh/err")"
  fi
}

# Checks shared by every shell shape. $2 is initContent, $3 profileExtra.
# shellcheck disable=SC2016  # $+commands[...] is literal zsh syntax
check_shell_common() { # label init profile zcompdump-json
  check_has "$1: fnm eval is guarded" "$2" '$+commands[fnm]'
  check_no_line "$1: no unguarded fnm eval" "$2" '^[[:space:]]*eval "\$\(fnm env'
  check_has "$1: brew shellenv is guarded with -x" "$3" '-x /opt/homebrew/bin/brew'
  zsh_syntax "$1" "$2" initContent.zsh
  zsh_syntax "$1" "$3" profileExtra.zsh
  check_eq "$1: clearStaleZcompdump runs after writeBoundary" \
    true "$(jq -r '.after | index("writeBoundary") != null' <<<"$4")"
  check_eq "$1: clearStaleZcompdump has no before constraint" '[]' "$(jq -c '.before' <<<"$4")"
}

# shellcheck disable=SC2016  # $+commands[...] is literal zsh syntax
check_shell_runtime_op() { # label init
  check_has "$1: op completion is guarded" "$2" '$+commands[op]'
  check_no_line "$1: no unguarded op completion" "$2" '^[[:space:]]*eval "\$\(op completion'
}

check_shell_baked_op() { # label init
  local path
  # The package's own completion file, read-guarded and sourced (no ERE backrefs).
  path="$(printf '%s\n' "$2" | grep -Eo '/nix/store/[^ /]*-1password-cli-[^ /]*/share/zsh/site-functions/_op' | head -n 1 || true)"
  if [ -n "$path" ]; then
    check_has "$1: sources the packaged op completion behind [[ -r ]]" "$2" "[[ -r $path ]] && source $path && compdef _op op"
  else
    fail "$1: sources the packaged op completion behind [[ -r ]]" \
      "missing: /nix/store/...-1password-cli-.../share/zsh/site-functions/_op"
  fi
  check_lacks "$1: no op completion runtime call" "$2" 'op completion zsh'
}

# shell_shape RESULTS_JSON NAME runtime|baked
shell_shape() {
  local init profile
  shape_ok "shell/$2" "$1" "$SHAPES_EXPR" "$2" || return 0
  init="$(jq -r --arg n "$2" '.[$n].initContent' <<<"$1")"
  profile="$(jq -r --arg n "$2" '.[$n].profileExtra' <<<"$1")"
  check_shell_common "shell/$2" "$init" "$profile" "$(jq -c --arg n "$2" '.[$n].zcompdump' <<<"$1")"
  if [ "$3" = baked ]; then
    check_shell_baked_op "shell/$2" "$init"
  else
    check_shell_runtime_op "shell/$2" "$init"
  fi
}

test_shell() {
  need_tools nix jq zsh
  init_tmp
  export T_ROOT="$ROOT"
  SHAPES_EXPR="$(nix_shell_expr)"
  eval_shapes "$SHAPES_EXPR"
  if [ "$EVAL_RC" != 0 ]; then
    fail "shell: evaluate home/zsh.nix" "$EVAL_ERR"
    return 0
  fi
  shell_shape "$EVAL_OUT" noappconfig runtime
  shell_shape "$EVAL_OUT" noop runtime
  shell_shape "$EVAL_OUT" nixop baked
  shell_shape "$EVAL_OUT" moduleargs baked
}

# --- case: host ----------------------------------------------------------------

# Evaluates darwinConfigurations.example-mac (the shipped default host) and two
# extendModules variants; nothing is built. T_USER is the host's adminUsername.
nix_host_expr() {
  cat <<'NIX'
let
  flake = builtins.getFlake "git+file://${builtins.getEnv "T_ROOT"}";
  user = builtins.getEnv "T_USER";
  host = flake.darwinConfigurations.example-mac;
  hmOf = sys: sys.config.home-manager.users.${user};
  gitText = hmCfg: hmCfg.xdg.configFile."git/config".text;
  base = hmOf host;
  withOnePassword = hmOf (
    host.extendModules {
      modules = [ { home-manager.users.${user}.my.onePassword.enable = true; } ];
    }
  );
  withVersions = host.extendModules {
    modules = [
      {
        system.stateVersion = 5;
        home-manager.users.${user}.home.stateVersion = "25.11";
      }
    ];
  };
in
{
  ssh.value = base.programs.ssh.extraConfig;
  git.value = gitText base;
  find.value = base.home.shellAliases ? find;
  # null (not false) while the option is undeclared, so the check fails red.
  option.value = base.my.onePassword.enable or null;
  on = {
    ssh = withOnePassword.programs.ssh.extraConfig;
    git = gitText withOnePassword;
  };
  versions = {
    system = withVersions.config.system.stateVersion;
    home = (hmOf withVersions).home.stateVersion;
  };
}
NIX
}

# host_value RESULTS_JSON NAME: the probe's .value rendered as raw text.
host_value() { jq -r --arg n "$2" '.[$n].value' <<<"$1"; }

# host_probe LABEL RESULTS_JSON NAME: shape_ok for the host expression.
host_probe() { shape_ok "$1" "$2" "$SHAPES_EXPR" "$3"; }

check_host_defaults() { # results-json
  if host_probe host/ssh "$1" ssh; then
    check_lacks "host: default ssh config has no 1Password agent" "$(host_value "$1" ssh)" '1password'
  fi
  if host_probe host/git "$1" git; then
    check_lacks "host: default git config has no gpgSign" "$(host_value "$1" git)" 'gpgSign'
  fi
  if host_probe host/find "$1" find; then
    check_eq "host: find alias is gone" false "$(host_value "$1" find)"
  fi
  if host_probe host/option "$1" option; then
    check_eq "host: my.onePassword.enable defaults to false" false "$(host_value "$1" option)"
  fi
}

check_host_on() { # results-json
  host_probe host/on "$1" on || return 0
  check_has "host: enabling my.onePassword restores the IdentityAgent" \
    "$(jq -r '.on.ssh' <<<"$1")" 'IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password'
  check_has "host: enabling my.onePassword restores op-ssh-sign" \
    "$(jq -r '.on.git' <<<"$1")" 'op-ssh-sign'
}

check_host_versions() { # results-json
  host_probe host/versions "$1" versions || return 0
  check_eq "host: system.stateVersion is overridable without mkForce" 5 "$(jq -c '.versions.system' <<<"$1")"
  check_eq "host: home.stateVersion is overridable without mkForce" '"25.11"' "$(jq -c '.versions.home' <<<"$1")"
}

test_host() {
  need_tools nix jq
  init_tmp
  export T_ROOT="$ROOT"
  T_USER="$(jq -r '.adminUsername' "$ROOT/config/hosts/example-mac.json")"
  export T_USER
  SHAPES_EXPR="$(nix_host_expr)"
  eval_shapes "$SHAPES_EXPR"
  if [ "$EVAL_RC" != 0 ]; then
    fail "host: evaluate darwinConfigurations.example-mac" "$EVAL_ERR"
    return 0
  fi
  check_host_defaults "$EVAL_OUT"
  check_host_on "$EVAL_OUT"
  check_host_versions "$EVAL_OUT"
}

# --- case: schema ----------------------------------------------------------------

# Config hardening: the JSON schemas (shipped files accepted, unsafe values
# rejected), scripts/validate-host-json.sh on a temp copy, and the Nix-side
# assertions that back the schemas up (final nix.settings user lists, https-only
# manual Firefox add-ons, my.firefox.enable from a loader's `enable`).

test_schema_files() {
  local example host_json
  example="$ROOT/config/hosts/$(default_host).json"
  host_json="$(jq -c . "$example")"
  schema_check host "the shipped example host" valid "$host_json"
  schema_check host "a plain user list" valid "$(jq -c '.trustedUsers = ["alice"]' <<<"$host_json")"
  schema_check host 'trustedUsers ["*"]' invalid "$(jq -c '.trustedUsers = ["*"]' <<<"$host_json")"
  schema_check host 'trustedUsers ["alice *"]' invalid "$(jq -c '.trustedUsers = ["alice *"]' <<<"$host_json")"
  schema_check host "a trustedUsers entry containing a newline" invalid \
    "$(jq -c --arg u $'a\nb' '.trustedUsers = [$u]' <<<"$host_json")"
  schema_check host 'allowedUsers ["*"]' invalid "$(jq -c '.allowedUsers = ["*"]' <<<"$host_json")"
  schema_check host 'allowedUsers ["alice *"]' invalid "$(jq -c '.allowedUsers = ["alice *"]' <<<"$host_json")"
  schema_check host "an allowedUsers entry containing a newline" invalid \
    "$(jq -c --arg u $'a\nb' '.allowedUsers = [$u]' <<<"$host_json")"
  schema_check host 'adminUsername "a *"' invalid "$(jq -c '.adminUsername = "a *"' <<<"$host_json")"
  schema_check host 'a tab in trustedUsers' invalid "$(jq -c --arg u $'a\tb' '.trustedUsers = [$u]' <<<"$host_json")"
  schema_check host 'a carriage return in allowedUsers' invalid \
    "$(jq -c --arg u $'a\rb' '.allowedUsers = [$u]' <<<"$host_json")"
  schema_check host 'an empty "" trustedUsers entry' invalid "$(jq -c '.trustedUsers = [""]' <<<"$host_json")"
  schema_check host 'an empty "" allowedUsers entry' invalid "$(jq -c '.allowedUsers = [""]' <<<"$host_json")"
  schema_check host 'an empty "" adminUsername' invalid "$(jq -c '.adminUsername = ""' <<<"$host_json")"
  schema_check host '@staff group entries' valid \
    "$(jq -c '.trustedUsers = ["@staff"] | .allowedUsers = ["@staff"]' <<<"$host_json")"

  schema_check hosts "the shipped hosts.json" valid "$(jq -c . "$ROOT/config/hosts.json")"
  schema_check hosts "an empty hosts list" invalid '{"hosts":[]}'
  schema_check hosts "duplicate hosts" invalid '{"hosts":["a","a"]}'

  local user_json
  user_json="$(jq -c . "$ROOT/config/user.json.example")"
  schema_check user "the shipped user.json.example" valid "$user_json"
  schema_check user "a user.json with an extra key" valid "$(jq -c '.extra = "x"' <<<"$user_json")"
  schema_check user "a user.json without defaultGpgKey" invalid "$(jq -c 'del(.defaultGpgKey)' <<<"$user_json")"
  schema_check user "a user.json without defaultSigningKey" invalid "$(jq -c 'del(.defaultSigningKey)' <<<"$user_json")"
  schema_check user 'an empty "" user name' invalid "$(jq -c '.name = ""' <<<"$user_json")"
  schema_check user "a non-string email" invalid "$(jq -c '.email = 5' <<<"$user_json")"

  schema_check git "the shipped git.json" valid "$(jq -c . "$ROOT/config/git.json")"
  schema_check git "an extra programs.git key" valid '{"lfs":{"enable":true}}'
  schema_check git "an include with a path and condition" valid '{"includes":[{"path":"~/.gitconfig.work","condition":"gitdir:~/work/"}]}'
  schema_check git "an include with neither path nor contents" invalid '{"includes":[{"condition":"gitdir:~/work/"}]}'
  schema_check git "includes that is not a list" invalid '{"includes":{"path":"x"}}'
  schema_check git "a non-string ignores entry" invalid '{"ignores":[5]}'
  schema_check git 'an empty "" ignores entry' invalid '{"ignores":[""]}'

  schema_check firefox "the shipped firefox base.json" valid "$(jq -c . "$ROOT/config/firefox/base.json")"
  schema_check firefox "an http:// manual add-on url" invalid "$(jq -c '.extensions.manual = [{name: "x", addonId: "x@x", url: "http://e.com/x.xpi", hash: "sha256-AAAA"}]' "$ROOT/config/firefox/base.json")"
  schema_check firefox "an https:// manual add-on url" valid "$(jq -c '.extensions.manual = [{name: "x", addonId: "x@x", url: "https://e.com/x.xpi", hash: "sha256-AAAA"}]' "$ROOT/config/firefox/base.json")"
}

# validate-host-json.sh runs on a copy of config/ and scripts/ so the real tree is
# never touched; it takes the repo root as $1.
test_schema_validator() {
  local copy="$TMP/validator"
  mkdir -p "$copy"
  cp -R "$ROOT/config" "$ROOT/scripts" "$copy/"
  run_eval bash "$copy/scripts/validate-host-json.sh" "$copy"
  check_eq "validator: accepts the shipped config" 0 "$EVAL_RC"
  jq '.defaultHost = "not-a-host"' "$ROOT/config/hosts.json" >"$copy/config/hosts.json"
  run_eval bash "$copy/scripts/validate-host-json.sh" "$copy"
  if [ "$EVAL_RC" = 0 ]; then
    fail "validator: rejects a defaultHost that is not in hosts" "exited 0"
  else
    pass "validator: rejects a defaultHost that is not in hosts"
  fi
  check_contains "validator: names the defaultHost problem" "$EVAL_ERR" "not listed in hosts"

  # An older SCHEMA_ROOT without the hosts/user/git schemas must keep working,
  # and the hosts manifest check must still run without hosts.schema.json.
  local older="$TMP/older-schemas" name
  mkdir -p "$older"
  for name in host apps fonts firefox android; do
    cp "$ROOT/config/schema/$name.schema.json" "$older/"
  done
  cp "$ROOT/config/hosts.json" "$copy/config/hosts.json"
  SCHEMA_ROOT="$older" run_eval bash "$copy/scripts/validate-host-json.sh" "$copy"
  check_eq "validator: an older SCHEMA_ROOT without hosts/user/git schemas accepts the shipped config" 0 "$EVAL_RC"
  jq '.defaultHost = "not-a-host"' "$ROOT/config/hosts.json" >"$copy/config/hosts.json"
  SCHEMA_ROOT="$older" run_eval bash "$copy/scripts/validate-host-json.sh" "$copy"
  if [ "$EVAL_RC" = 0 ]; then
    fail "validator: an older SCHEMA_ROOT still rejects a defaultHost that is not in hosts" "exited 0"
  else
    pass "validator: an older SCHEMA_ROOT still rejects a defaultHost that is not in hosts"
  fi
  check_contains "validator: an older SCHEMA_ROOT names the defaultHost problem" "$EVAL_ERR" "not listed in hosts"

  # Like checkHostsManifest, a present but null or non-string defaultHost is
  # rejected (older SCHEMA_ROOT, so the jq check alone must catch it).
  local bad label
  for bad in null "[\"$(default_host)\"]"; do
    label="validator: rejects \"defaultHost\": $bad"
    jq --argjson d "$bad" '.defaultHost = $d' "$ROOT/config/hosts.json" >"$copy/config/hosts.json"
    SCHEMA_ROOT="$older" run_eval bash "$copy/scripts/validate-host-json.sh" "$copy"
    if [ "$EVAL_RC" = 0 ]; then
      fail "$label" "exited 0"
    else
      pass "$label"
    fi
    check_contains "$label names the defaultHost problem" "$EVAL_ERR" "not listed in hosts"
  done
  cp "$ROOT/config/hosts.json" "$copy/config/hosts.json"
}

# Probes (each `{ value = ...; }`, see eval_shapes): the failing assertion
# messages of the shipped host and of extendModules variants, plus
# my.firefox.enable for the shipped host and for a builder call whose firefox
# loader sets enable = false. Nothing is built. T_HOST is the default host and
# T_USER its adminUsername.
nix_schema_expr() {
  cat <<'NIX'
let
  rootDir = builtins.getEnv "T_ROOT";
  user = builtins.getEnv "T_USER";
  flake = builtins.getFlake "git+file://${rootDir}";
  inherit (flake.inputs.nixpkgs) lib;
  flakeRoot = builtins.toString flake.outPath;
  hostName = builtins.getEnv "T_HOST";
  host = flake.darwinConfigurations.${hostName};
  sc = flake.lib.loadHostConfig flakeRoot hostName;
  failing = sys: map (a: a.message) (builtins.filter (a: !a.assertion) sys.config.assertions);
  withSystemConfig = extra: host.extendModules { specialArgs.systemConfig = sc // extra; };
  withModule = module: host.extendModules { modules = [ module ]; };
  firefoxEnable = sys: sys.config.home-manager.users.${user}.my.firefox.enable;

  # The same arguments flake.nix passes, except the firefox loader.
  builderHosts = flake.darwinConfigurationsBuilder {
    inherit lib flakeRoot;
    inherit (flake.inputs) home-manager darwin;
    # flake.nix hard-codes this system as well.
    system = "aarch64-darwin";
    gitConfig = (flake.lib.loadSharedConfig flakeRoot).gitConfig;
    inherit (flake) editorTooling mkWritableCopyActivation;
    hosts = [ hostName ];
    loadHostConfig = flake.lib.loadHostConfig flakeRoot;
    loadAppConfig = flake.lib.loadAppConfig flakeRoot;
    loadFontConfig = flake.lib.loadFontConfig flakeRoot;
    loadFirefoxConfig =
      _: flake.lib.mergeFirefoxConfig (lib.importJSON (flakeRoot + "/config/firefox/base.json")) { enable = false; };
    loadAndroidConfig = flake.lib.loadAndroidConfig flakeRoot;
    loadUserConfig = flake.lib.loadUserConfig flakeRoot { allowExample = true; };
  };
in
{
  baseline.value = failing host;
  trusted.value = failing (withSystemConfig { trustedUsers = [ "*" ]; });
  allowed.value = failing (withSystemConfig { allowedUsers = [ "*" ]; });
  newline.value = failing (withSystemConfig { trustedUsers = [ "a\nb" ]; });
  tab.value = failing (withSystemConfig { trustedUsers = [ "a\tb" ]; });
  carriageReturn.value = failing (withSystemConfig { allowedUsers = [ "a\rb" ]; });
  group.value = failing (withSystemConfig {
    trustedUsers = [ "@staff" ];
    allowedUsers = [ "@staff" ];
  });
  module.value = failing (withModule { nix.settings.trusted-users = [ "*" ]; });
  moduleExtraTrusted.value = failing (withModule { nix.settings.extra-trusted-users = [ "*" ]; });
  moduleExtraAllowed.value = failing (withModule { nix.settings.extra-allowed-users = [ "*" ]; });
  http.value = failing (withModule {
    home-manager.users.${user}.my.firefox.manualExtensions = [
      {
        name = "x";
        addonId = "x@x";
        url = "http://e.com/x.xpi";
        hash = "sha256-AAAA";
      }
    ];
  });
  firefoxDefault.value = firefoxEnable host;
  firefoxDisabled.value = firefoxEnable builderHosts.${hostName};
}
NIX
}

# check_assertion LABEL RESULTS_JSON PROBE NEEDLE: the probe has at least one
# failing assertion and its messages mention NEEDLE.
check_assertion() {
  local msgs
  shape_ok "$1" "$2" "$SHAPES_EXPR" "$3" || return 0
  msgs="$(jq -r --arg n "$3" '.[$n].value | join("\n")' <<<"$2")"
  if [ -z "$msgs" ]; then
    fail "$1" "no failing assertion"
    return 0
  fi
  check_contains "$1" "$msgs" "$4"
}

check_schema_eval() { # results-json
  if shape_ok "schema/baseline" "$1" "$SHAPES_EXPR" baseline; then
    check_eq "schema: the shipped host has no failing assertions" '[]' "$(jq -c '.baseline.value' <<<"$1")"
  fi
  check_assertion 'schema: trustedUsers ["*"] fails an assertion naming trusted-users' "$1" trusted trusted-users
  check_assertion 'schema: allowedUsers ["*"] fails an assertion naming allowed-users' "$1" allowed allowed-users
  check_assertion "schema: a newline in a user entry fails an assertion naming trusted-users" "$1" newline trusted-users
  check_assertion "schema: a tab in a user entry fails an assertion naming trusted-users" "$1" tab trusted-users
  check_assertion "schema: a carriage return in a user entry fails an assertion naming allowed-users" "$1" carriageReturn allowed-users
  if shape_ok "schema/group" "$1" "$SHAPES_EXPR" group; then
    check_eq 'schema: @staff group entries pass the user-list assertion' '[]' "$(jq -c '.group.value' <<<"$1")"
  fi
  check_assertion 'schema: nix.settings.trusted-users from a module ["*"] fails an assertion' "$1" module trusted-users
  check_assertion 'schema: nix.settings.extra-trusted-users from a module ["*"] fails an assertion' "$1" moduleExtraTrusted extra-trusted-users
  check_assertion 'schema: nix.settings.extra-allowed-users from a module ["*"] fails an assertion' "$1" moduleExtraAllowed extra-allowed-users
  check_assertion "schema: an http:// manual add-on fails an assertion naming https://" "$1" http "https://"
  if shape_ok "schema/firefoxDefault" "$1" "$SHAPES_EXPR" firefoxDefault; then
    check_eq "schema: my.firefox.enable is true for the shipped host" true "$(jq -c '.firefoxDefault.value' <<<"$1")"
  fi
  if shape_ok "schema/firefoxDisabled" "$1" "$SHAPES_EXPR" firefoxDisabled; then
    check_eq "schema: a loader's enable = false turns my.firefox.enable off" false "$(jq -c '.firefoxDisabled.value' <<<"$1")"
  fi
}

test_schema() {
  need_tools nix jq python3
  python3 -c 'import jsonschema' 2>/dev/null || die "python jsonschema is required (run inside 'nix develop')"
  init_tmp
  test_schema_files
  test_schema_validator
  export T_ROOT="$ROOT"
  T_HOST="$(default_host)"
  T_USER="$(jq -r '.adminUsername' "$ROOT/config/hosts/$T_HOST.json")"
  export T_HOST T_USER
  SHAPES_EXPR="$(nix_schema_expr)"
  eval_shapes "$SHAPES_EXPR"
  if [ "$EVAL_RC" != 0 ]; then
    fail "schema: evaluate the host assertions" "$EVAL_ERR"
    return 0
  fi
  check_schema_eval "$EVAL_OUT"
}

# --- case: cursor ----------------------------------------------------------------

CURSOR_EXTENSIONS="jnoortheen.nix-ide ms-python.vscode-python-envs ms-python.vscode-pylance"
CURSOR_DIR=""
CURSOR_RC=0
CURSOR_SCRIPT=""
CURSOR_EXTENSION_COUNT=3

# Evaluates home/vscode.nix with Cursor casked and builds only a text file holding
# the installCursorPinnedExtensions activation entry (realising the small
# writeShellScript it references). editorTooling must be passed: module arguments
# ignore `? { }` defaults.
nix_cursor_expr() {
  nix_hm_prelude
  cat <<'NIX'
  cfg = evalHm {
    pkgs = pkgsUnfree;
    modules = [ "${rootDir}/home/vscode.nix" ];
    args = {
      appConfig = appConfigOf [ "cursor" ];
      editorTooling = { };
      mkWritableCopyActivation = mkWritableOf pkgsUnfree;
    };
  };
in
pkgsUnfree.writeText "cursor-pinned-activation" cfg.home.activation.installCursorPinnedExtensions.data
NIX
}

# Fake cursor: --version ok, nothing installed, every install attempt fails.
write_fake_cursor() { # path
  cat >"$1" <<'FAKE'
#!/bin/sh
case "$1" in
  --version) echo "0.0.0" ;;
  --list-extensions) ;;
  --install-extension)
    printf 'install\t%s\n' "$2" >>"$FAKE_LOG"
    exit 1
    ;;
esac
FAKE
  chmod +x "$1"
}

# build_cursor_script: sets CURSOR_SCRIPT to the realised install script path.
build_cursor_script() {
  local built
  run_eval nix build --impure --no-link --print-out-paths --expr "$(nix_cursor_expr)"
  if [ "$EVAL_RC" != 0 ]; then
    fail "cursor: build the pinned-extension activation script" "$(err_summary)"
    return 1
  fi
  built="$(printf '%s\n' "$EVAL_OUT" | tail -n 1)"
  CURSOR_SCRIPT="$(grep -o '/nix/store/[^[:space:]]*install-cursor-pinned-extensions' "$built" | head -n 1 || true)"
  if [ -z "$CURSOR_SCRIPT" ] || [ ! -x "$CURSOR_SCRIPT" ]; then
    fail "cursor: activation entry references the install script" "activation text: $(cat "$built")"
    return 1
  fi
}

run_cursor_script() {
  CURSOR_RC=0
  env -i PATH="$CURSOR_DIR/bin:/usr/bin:/bin" HOME="$CURSOR_DIR/home" FAKE_LOG="$CURSOR_DIR/log" \
    "$CURSOR_SCRIPT" >"$CURSOR_DIR/out" 2>"$CURSOR_DIR/err" || CURSOR_RC=$?
}

check_cursor_run() {
  local ext
  check_eq "cursor: failing installs do not fail activation (exit status)" 0 "$CURSOR_RC"
  check_eq "cursor: one warning per failed extension" "$CURSOR_EXTENSION_COUNT" \
    "$(grep -c '^warning:' "$CURSOR_DIR/err" || true)"
  check_eq "cursor: every pinned extension is attempted" "$CURSOR_EXTENSION_COUNT" \
    "$(grep -c '^install' "$CURSOR_DIR/log" || true)"
  for ext in $CURSOR_EXTENSIONS; do
    check_has "cursor: install attempted for $ext" "$(cat "$CURSOR_DIR/log")" "$(row install "$ext")"
    check_has "cursor: warning names $ext" "$(cat "$CURSOR_DIR/err")" "$ext"
  done
}

test_cursor() {
  need_tools nix
  init_tmp
  export T_ROOT="$ROOT"
  CURSOR_DIR="$TMP/cursor"
  mkdir -p "$CURSOR_DIR/bin" "$CURSOR_DIR/home"
  : >"$CURSOR_DIR/log"
  write_fake_cursor "$CURSOR_DIR/bin/cursor"
  build_cursor_script || return 0
  run_cursor_script
  check_cursor_run
}

# --- case: release -----------------------------------------------------------
# scripts/release-changelog.sh --bump: pure string handling, no git-cliff needed.

check_bump() { # label expected tag type
  check_eq "release: $1" "$2" "$("$ROOT/scripts/release-changelog.sh" --bump "$3" "$4")"
}

check_bump_rejected() { # label tag type expected-stderr-fragment
  local out rc=0
  out="$("$ROOT/scripts/release-changelog.sh" --bump "$2" "$3" 2>&1 >/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "release: $1" "expected non-zero exit, got 0" "stderr: $out"
  elif [[ "$out" != *"$4"* ]]; then
    fail "release: $1" "expected stderr to contain: $4" "stderr: $out"
  else
    pass "release: $1"
  fi
}

test_release() {
  check_bump "patch bump" v1.2.4 v1.2.3 patch
  check_bump "minor bump resets patch" v1.3.0 v1.2.3 minor
  check_bump "major bump resets minor and patch" v2.0.0 v1.2.3 major
  check_bump "tag without v prefix is accepted" v1.2.4 1.2.3 patch
  check_bump_rejected "two-part version is rejected" v1.2 patch "Invalid semver"
  check_bump_rejected "pre-release suffix is rejected" v1.2.3-rc1 patch "Invalid semver"
  check_bump_rejected "shell metacharacters are rejected" 'v1.2.3;id' patch "Invalid semver"
  check_bump_rejected "empty tag is rejected by the --bump arg guard" "" patch "requires a tag"
  check_bump_rejected "unknown bump type is rejected" v1.2.3 foo "Invalid bump type"
}

# --- case: pins ----------------------------------------------------------------
# scripts/update-pins.sh against tests/fixtures/pins: synthetic sidecars (root/)
# and canned API responses (base/ = everything current, plus per-scenario
# overrides). Each scenario gets fresh copies under $TMP, UPDATE_PINS_ROOT and
# UPDATE_PINS_FIXTURES point at them, and a stub curl that records its arguments
# and fails sits first on PATH, so no scenario can touch the network or a real
# sidecar. A few scenarios instead source the script with fixtures off and a stub
# nix first on PATH (canned `got:` build output, canned prefetch JSON) to cover
# the real-nix fallbacks. The case also asserts it left the repo's tracked files alone.

PINS_FIX="$ROOT/tests/fixtures/pins"
PINS_DIR=""
PINS_RC=0
PINS_OUT=""
PINS_ERR=""

# Stub curl: log one tab-separated line per call, print `{}`, exit $PINS_CURL_RC
# (99 by default, so an unexpected network call fails loudly).
write_pins_curl() { # path
  cat >"$1" <<'FAKE'
#!/bin/sh
{ printf 'curl'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$PINS_CURL_LOG"
echo '{}'
exit "${PINS_CURL_RC:-99}"
FAKE
  chmod +x "$1"
}

# Stub nix for the fixtures-off scenarios: log one tab-separated line per call to
# <its dir>/log and answer from files beside it. `flake` prints flake.json and
# exits flake.rc (default 1: no prefetch); `build` prints build.out on stderr and
# exits build.rc (default 1, as a fake-hash build does); `store` prints
# prefetch.json and exits prefetch.rc (default 0). Anything else fails loudly.
write_pins_nix() { # path
  cat >"$1" <<'FAKE'
#!/bin/sh
d="${0%/*}"
{ printf 'nix'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "$d/log"
rc() { if [ -f "$d/$1.rc" ]; then cat "$d/$1.rc"; else echo "$2"; fi; }
case "$1" in
  flake) cat "$d/flake.json" 2>/dev/null; exit "$(rc flake 1)" ;;
  build) cat "$d/build.out" >&2; exit "$(rc build 1)" ;;
  store) cat "$d/prefetch.json"; exit "$(rc prefetch 0)" ;;
esac
echo "stub nix: unexpected call: $*" >&2
exit 98
FAKE
  chmod +x "$1"
}

pins_setup() { # name [override-dir...]
  local name="$1" dir
  shift
  PINS_DIR="$TMP/pins/$name"
  mkdir -p "$PINS_DIR/root" "$PINS_DIR/fx" "$PINS_DIR/bin" "$PINS_DIR/nixbin"
  cp -R "$PINS_FIX/root/." "$PINS_DIR/root/"
  cp -R "$PINS_FIX/base/." "$PINS_DIR/fx/"
  for dir in "$@"; do
    cp -R "$PINS_FIX/$dir/." "$PINS_DIR/fx/"
  done
  : >"$PINS_DIR/curl.log"
  : >"$PINS_DIR/summary"
  write_pins_curl "$PINS_DIR/bin/curl"
  write_pins_nix "$PINS_DIR/nixbin/nix"
  : >"$PINS_DIR/nixbin/log"
}

# pins_run ARG...: run update-pins.sh in the current scenario.
pins_run() {
  PINS_RC=0
  env -u GH_TOKEN \
    PATH="$PINS_DIR/bin:$PATH" PINS_CURL_LOG="$PINS_DIR/curl.log" \
    UPDATE_PINS_ROOT="${PINS_ENV_ROOT:-$PINS_DIR/root}" UPDATE_PINS_FIXTURES="$PINS_DIR/fx" \
    GITHUB_STEP_SUMMARY="$PINS_DIR/summary" \
    bash "$ROOT/scripts/update-pins.sh" "$@" >"$PINS_DIR/out" 2>"$PINS_DIR/err" || PINS_RC=$?
  PINS_OUT="$(cat "$PINS_DIR/out")"
  PINS_ERR="$(cat "$PINS_DIR/err")"
}

pins_get() { jq -r "$2" "$PINS_DIR/root/$1"; } # root-relative-file jq-filter

# pins_bash PROGRAM ARG...: run `bash -c PROGRAM _ update-pins.sh ARG...` with
# fixtures off, the stub nix and the stub curl first on PATH, and stdin passed
# through; sets PINS_RC, PINS_OUT and PINS_ERR like pins_run.
pins_bash() {
  PINS_RC=0
  env -u UPDATE_PINS_FIXTURES -u GH_TOKEN \
    PATH="$PINS_DIR/nixbin:$PINS_DIR/bin:$PATH" PINS_CURL_LOG="$PINS_DIR/curl.log" \
    GITHUB_STEP_SUMMARY="$PINS_DIR/summary" \
    bash -c "$1" _ "$ROOT/scripts/update-pins.sh" "${@:2}" >"$PINS_DIR/out" 2>"$PINS_DIR/err" || PINS_RC=$?
  PINS_OUT="$(cat "$PINS_DIR/out")"
  PINS_ERR="$(cat "$PINS_DIR/err")"
}

# pins_fn FUNCTION ARG...: call one function of the sourced script.
pins_fn() {
  # shellcheck disable=SC2016 # the inner script's $1/$@ expand in the child bash
  pins_bash '. "$1"; shift; "$@"' "$@"
}

pins_nix_set() { printf '%s\n' "$2" >"$PINS_DIR/nixbin/$1"; } # stub-file content
pins_nix_log() { cat "$PINS_DIR/nixbin/log"; }

# check_pins_no_commands LABEL: no output line (stdout, stderr, step summary)
# starts with `::`, the workflow-command prefix.
check_pins_no_commands() {
  check_eq "$1" 0 "$(cat "$PINS_DIR/out" "$PINS_DIR/err" "$PINS_DIR/summary" | grep -c '^::' || true)"
}

check_pins_untouched() { # label root-relative-file
  if cmp -s "$PINS_FIX/root/$2" "$PINS_DIR/root/$2"; then
    pass "$1"
  else
    fail "$1" "$2 was modified"
  fi
}

# check_pins_offline LABEL: the stub curl was never called.
check_pins_offline() {
  check_eq "$1" 0 "$(wc -l <"$PINS_DIR/curl.log" | tr -d ' ')"
}

ADDONS_PINS="home/firefox/addons-pins.json"
EXTENSIONS_PINS="home/vscode/extensions-extra.json"
BAT_PINS="home/bat-theme-pin.json"
FONTS_PINS="overlays/google-fonts/pins.json"
NPM_PINS="lib/editor-tooling-package.json"

test_pins_amo_bump() {
  pins_setup amo-bump amo-bump
  pins_run amo
  check_eq "pins: amo bump exits 0" 0 "$PINS_RC"
  check_has "pins: amo bump reports old -> new" "$PINS_OUT" \
    "pins: amo: darkreader darkreader-4.9.128.xpi -> darkreader-4.9.135.xpi"
  check_has "pins: amo current add-on reported unchanged" "$PINS_OUT" \
    "pins: amo: adguard-browser-assistant unchanged"
  check_eq "pins: amo bump rewrites the url" \
    "https://addons.mozilla.org/firefox/downloads/file/5216111/darkreader-4.9.135.xpi" \
    "$(pins_get "$ADDONS_PINS" '.darkreader.url')"
  check_eq "pins: amo bump converts the hex hash to SRI" \
    "sha256-v+1FkdbMaYV/XtM6LTy/vFgR1bksQyPQc10vF1fi3OQ=" "$(pins_get "$ADDONS_PINS" '.darkreader.hash')"
  check_eq "pins: amo bump keeps name and addonId" "darkreader addon@darkreader.org" \
    "$(pins_get "$ADDONS_PINS" '.darkreader | "\(.name) \(.addonId)"')"
  check_eq "pins: amo bump leaves the current entry byte-for-byte" \
    "$(jq -c '.["adguard-browser-assistant"]' "$PINS_FIX/root/$ADDONS_PINS")" \
    "$(pins_get "$ADDONS_PINS" '.["adguard-browser-assistant"]' | jq -c .)"
  check_has "pins: amo bump is appended to GITHUB_STEP_SUMMARY" "$(cat "$PINS_DIR/summary")" \
    "pins: amo: darkreader darkreader-4.9.128.xpi -> darkreader-4.9.135.xpi"
  check_eq "pins: amo bump leaves no temp file behind" 1 \
    "$(find "$PINS_DIR/root/home/firefox" -type f | wc -l | tr -d ' ')"
  check_pins_offline "pins: amo bump never calls curl (fixtures only)"
}

# A rejected entry fails the run and nothing in that sidecar is written, not even
# the valid bump sitting next to it.
check_pins_amo_rejected() { # scenario reason-fragment
  pins_setup "amo-$1" "$1"
  pins_run amo
  check_eq "pins: $1 exits 1" 1 "$PINS_RC"
  check_pins_untouched "pins: $1 leaves the sidecar untouched" "$ADDONS_PINS"
  check_has "pins: $1 explains the rejection" "$PINS_ERR" "$2"
  check_pins_offline "pins: $1 never calls curl"
}

test_pins_amo_rejections() {
  check_pins_amo_rejected amo-bad-guid "guid mismatch"
  check_pins_amo_rejected amo-bad-host "unexpected download url"
  check_pins_amo_rejected amo-bad-hash "unexpected hash"
  # The pattern is anchored at the end too: nothing may trail the file name.
  check_pins_amo_rejected amo-bad-url-tail "unexpected download url"
  # An embedded newline is rejected, and never reaches the output as a new line.
  check_pins_amo_rejected amo-ctrl-url "control characters"
  check_pins_no_commands "pins: amo-ctrl-url prints no line starting with ::"
}

test_pins_vscode() {
  pins_setup vscode-pre vscode-prerelease
  pins_run vscode
  check_eq "pins: vscode pre-release skip exits 0" 0 "$PINS_RC"
  check_eq "pins: vscode skips the newer pre-release for the newest stable" 0.19.2 \
    "$(pins_get "$EXTENSIONS_PINS" '.[0].version')"
  check_eq "pins: vscode hash comes from VsixSha256 as SRI" \
    "sha256-2romrRYRq8PSGhfkQhIin8ti1zYk25rhcakUVNC/S2U=" "$(pins_get "$EXTENSIONS_PINS" '.[0].hash')"
  check_eq "pins: vscode leaves the other extension alone" "1.1.32" "$(pins_get "$EXTENSIONS_PINS" '.[1].version')"
  check_has "pins: vscode reports old -> new" "$PINS_OUT" \
    "pins: vscode: tomoyukim.vscode-mermaid-editor 0.19.1 -> 0.19.2"
  check_pins_offline "pins: vscode never calls curl"

  # Engine ^1.200.0 is newer than the locked 1.119.0 (numeric, not string, compare).
  pins_setup vscode-eng vscode-engine
  pins_run vscode
  check_eq "pins: vscode engine skip exits 0" 0 "$PINS_RC"
  check_pins_untouched "pins: vscode skips a version newer than the locked engine" "$EXTENSIONS_PINS"
  check_has "pins: vscode engine skip is reported" "$PINS_OUT" "skipped"

  # The newest stable (0.19.0) is older than the pin (0.19.1): never a downgrade.
  pins_setup vscode-old vscode-older
  pins_run vscode
  check_eq "pins: vscode older stable exits 0" 0 "$PINS_RC"
  check_pins_untouched "pins: vscode never downgrades a newer pin" "$EXTENSIONS_PINS"
  check_has "pins: vscode older stable is reported as not newer" "$PINS_OUT" "0.19.0 is not newer than 0.19.1"
  check_pins_offline "pins: vscode downgrade check never calls curl"

  # A control character in the response rejects the entry and never starts a line.
  pins_setup vscode-ctrl vscode-ctrl
  pins_run vscode
  check_eq "pins: vscode control-character version exits 1" 1 "$PINS_RC"
  check_pins_untouched "pins: vscode control-character version leaves the sidecar untouched" "$EXTENSIONS_PINS"
  check_has "pins: vscode control-character version is explained" "$PINS_ERR" "control characters"
  check_pins_no_commands "pins: vscode control-character version prints no line starting with ::"
}

check_pins_failed() { check_eq "$1" 1 "$([ "$PINS_RC" -ne 0 ] && echo 1 || echo 0)"; } # label

check_pins_newer() { # label expected-status candidate current
  pins_fn version_newer "$3" "$4"
  check_eq "$1" "$2" "$PINS_RC"
}

test_pins_version_newer() {
  pins_setup version
  check_pins_newer "pins: version_newer: 1.10.0 is newer than 1.9.0 (numeric)" 0 1.10.0 1.9.0
  check_pins_newer "pins: version_newer: 1.9.0 is not newer than 1.10.0" 1 1.9.0 1.10.0
  check_pins_newer "pins: version_newer: equal is not newer" 1 0.19.1 0.19.1
  check_pins_newer "pins: version_newer: 1.2 equals 1.2.0" 1 1.2 1.2.0
  check_pins_newer "pins: version_newer: 1.2.1 is newer than 1.2" 0 1.2.1 1.2
  check_pins_newer "pins: version_newer: a suffix is undecidable" 2 1.2.3-beta 1.2.0
  check_pins_newer "pins: version_newer: non-numeric is undecidable" 2 latest 1.2.0
  check_pins_newer "pins: version_newer: empty is undecidable" 2 "" 1.2.0
  check_pins_newer "pins: version_newer: an embedded newline is undecidable" 2 $'1.2\n3' 1.0
}

# Real-nix fallbacks, offline: a stub nix answers (see write_pins_nix).
test_pins_fake_hash_build() {
  local got="sha256-2romrRYRq8PSGhfkQhIin8ti1zYk25rhcakUVNC/S2U="
  pins_setup nix-build
  pins_nix_set build.out "error: hash mismatch in fixed-output derivation '/nix/store/x-source.drv':
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    $got"
  pins_fn fake_hash_build 'pkgs.hello'
  check_eq "pins: fake_hash_build exits 0 on a hash mismatch" 0 "$PINS_RC"
  check_eq "pins: fake_hash_build prints the got: hash, not the specified one" "$got" "$PINS_OUT"
  check_has "pins: fake_hash_build builds the expression against the flake's pkgs" "$(pins_nix_log)" \
    "pkgsForValidation; in pkgs.hello"
  check_pins_offline "pins: fake_hash_build never calls curl"

  pins_nix_set build.rc 0
  pins_fn fake_hash_build 'pkgs.hello'
  check_eq "pins: fake_hash_build refuses a build that succeeds" 1 "$PINS_RC"
  check_has "pins: fake_hash_build explains the refusal" "$PINS_ERR" "build succeeded with a fake hash"
  check_eq "pins: fake_hash_build prints no hash after a refusal" "" "$PINS_OUT"

  rm "$PINS_DIR/nixbin/build.rc"
  pins_nix_set build.out "error: builder for '/nix/store/x.drv' failed"
  pins_fn fake_hash_build 'pkgs.hello'
  check_eq "pins: fake_hash_build fails when the output has no got: line" 1 "$PINS_RC"
  check_has "pins: fake_hash_build says it could not read the hash" "$PINS_ERR" "could not read the hash"
}

test_pins_prefetch_fallbacks() {
  local hash="sha256-ZGFiYTI2YWQxNjExYWJjM2QyMWExN2U0NDIxMjIyOWY="
  local rev=0123456789abcdef0123456789abcdef01234567 tab=$'\t'
  pins_setup nix-prefetch
  pins_nix_set prefetch.json "{\"hash\":\"$hash\",\"storePath\":\"/nix/store/x-file\"}"
  pins_fn prefetch_vsix pub ext 1.2.3
  check_eq "pins: prefetch_vsix exits 0" 0 "$PINS_RC"
  check_eq "pins: prefetch_vsix prints the hash from the prefetch-file JSON" "$hash" "$PINS_OUT"
  check_has "pins: prefetch_vsix prefetches the VSIX URL" "$(pins_nix_log)" \
    "store${tab}prefetch-file${tab}--json${tab}https://pub.gallery.vsassets.io/_apis/public/gallery/publisher/pub/extension/ext/1.2.3/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
  pins_nix_set prefetch.json '{"storePath":"/nix/store/x-file"}'
  pins_fn prefetch_vsix pub ext 1.2.3
  check_pins_failed "pins: prefetch_vsix fails when the JSON has no hash"
  pins_nix_set prefetch.json "{\"hash\":\"$hash\"}"
  pins_nix_set prefetch.rc 1
  pins_fn prefetch_vsix pub ext 1.2.3
  check_pins_failed "pins: prefetch_vsix fails when nix fails"
  check_pins_offline "pins: prefetch_vsix never calls curl"

  # prefetch_bat: `nix flake prefetch` first, the fake-hash build only as fallback.
  pins_setup nix-bat
  pins_nix_set flake.json "{\"hash\":\"$hash\"}"
  pins_nix_set flake.rc 0
  pins_fn prefetch_bat catppuccin bat "$rev"
  check_eq "pins: prefetch_bat uses the flake prefetch hash" "$hash" "$PINS_OUT"
  check_lacks "pins: prefetch_bat does not build when the flake prefetch works" "$(pins_nix_log)" "build"

  pins_setup nix-bat-fallback
  pins_nix_set build.out "error: hash mismatch in fixed-output derivation '/nix/store/x-source.drv':
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    $hash"
  pins_fn prefetch_bat catppuccin bat "$rev"
  check_eq "pins: prefetch_bat falls back to the fake-hash build" "$hash" "$PINS_OUT"
  check_has "pins: prefetch_bat tried the flake prefetch first" "$(pins_nix_log)" "flake${tab}prefetch${tab}--json${tab}github:catppuccin/bat/$rev"
  check_has "pins: prefetch_bat fallback builds the pinned rev" "$(pins_nix_log)" "rev = \"$rev\""
  pins_nix_set build.rc 0
  pins_fn prefetch_bat catppuccin bat "$rev"
  check_eq "pins: prefetch_bat fallback refuses a build that succeeds" 1 "$PINS_RC"
  check_pins_offline "pins: prefetch_bat never calls curl"
}

# Reporting never emits a fetched value as a line of its own.
test_pins_report_sanitized() {
  pins_setup sanitize
  pins_fn err $'bad\n::error::injected\r::x'
  check_eq "pins: err replaces newlines and carriage returns" \
    "pins: error: bad ::error::injected ::x" "$PINS_ERR"
  check_pins_no_commands "pins: err output has no line starting with ::"
  pins_fn note $'moved\n::warning::injected'
  check_eq "pins: note replaces newlines" "pins: moved ::warning::injected" "$PINS_OUT"
  check_eq "pins: the step summary stays one line per entry" 2 "$(wc -l <"$PINS_DIR/summary" | tr -d ' ')"
  check_pins_no_commands "pins: the step summary has no line starting with ::"
}

# errexit must really be on inside an updater: drive the real `main` with a fake
# source whose update_fake hits a bare `false` before it would write its sidecar.
test_pins_errexit() {
  local side
  pins_setup errexit
  side="$PINS_DIR/sidecar"
  : >"$side"
  # shellcheck disable=SC2016 # the inner script's $1/$2/$3 expand in the child bash
  pins_bash '. "$1"; need_tools() { :; }; parse_args() { ROOT=/; SELECTED=fake; }
    SIDE="$2"; eval "update_fake() { $3; }"; main' "$side" 'false; echo written >"$SIDE"'
  check_eq "pins: a failing step inside an updater fails the run" 1 "$PINS_RC"
  check_eq "pins: a failing step stops the updater before it writes" "" "$(cat "$side")"
  check_has "pins: the failed source is reported" "$PINS_ERR" "fake: update failed"

  # shellcheck disable=SC2016 # the inner script's $1/$2/$3 expand in the child bash
  pins_bash '. "$1"; need_tools() { :; }; parse_args() { ROOT=/; SELECTED=fake; }
    SIDE="$2"; eval "update_fake() { $3; }"; main' "$side" 'true; echo written >"$SIDE"'
  check_eq "pins: an updater that succeeds exits 0" 0 "$PINS_RC"
  check_eq "pins: the harness writes when nothing fails" written "$(cat "$side")"
}

test_pins_bat() {
  pins_setup bat-noop
  pins_run bat
  check_eq "pins: bat no-op exits 0" 0 "$PINS_RC"
  check_has "pins: bat no-op reports unchanged" "$PINS_OUT" "pins: bat: catppuccin/bat unchanged"
  check_pins_untouched "pins: bat no-op leaves the sidecar untouched" "$BAT_PINS"

  pins_setup bat-bump bat-bump
  pins_run bat
  check_eq "pins: bat bump exits 0" 0 "$PINS_RC"
  check_eq "pins: bat bump moves rev and hash" \
    "0123456789abcdef0123456789abcdef01234567 sha256-2romrRYRq8PSGhfkQhIin8ti1zYk25rhcakUVNC/S2U=" \
    "$(pins_get "$BAT_PINS" '"\(.rev) \(.hash)"')"
  check_has "pins: bat bump reports old -> new" "$PINS_OUT" "pins: bat: catppuccin/bat 6810349 -> 0123456"
}

test_pins_google_fonts() {
  pins_setup fonts-noop
  pins_run google-fonts
  check_eq "pins: google-fonts no-op exits 0" 0 "$PINS_RC"
  check_has "pins: google-fonts no-op reports unchanged" "$PINS_OUT" "pins: google-fonts: unchanged"
  check_pins_untouched "pins: google-fonts no-op leaves the sidecar untouched" "$FONTS_PINS"

  pins_setup fonts-bump fonts-bump
  pins_run google-fonts
  check_eq "pins: google-fonts bump exits 0" 0 "$PINS_RC"
  check_eq "pins: google-fonts bump moves rev to the default-branch HEAD" \
    fedcba9876543210fedcba9876543210fedcba98 "$(pins_get "$FONTS_PINS" '.rev')"
  check_eq "pins: google-fonts bump re-hashes every font" \
    "sha256-ZGFiYTI2YWQxNjExYWJjM2QyMWExN2U0NDIxMjIyOWY= sha256-cmVzYWx0LWludGVyLWhhc2gtZml4dHVyZS12YWx1ZTE=" \
    "$(pins_get "$FONTS_PINS" '"\(.fonts.lato.hash) \(.fonts.inter.hash)"')"

  # One font failing to hash must not leave pins.json half-updated.
  pins_setup fonts-partial fonts-bump
  rm "$PINS_DIR/fx/prefetch/font-fedcba9876543210fedcba9876543210fedcba98-ofl_inter.txt"
  pins_run google-fonts
  check_eq "pins: google-fonts partial re-hash exits 1" 1 "$PINS_RC"
  check_pins_untouched "pins: google-fonts writes pins.json only after every font hashed" "$FONTS_PINS"
}

test_pins_npm() {
  pins_setup npm-minor npm-minor
  pins_run npm
  check_eq "pins: npm minor bump exits 0" 0 "$PINS_RC"
  check_eq "pins: npm bumps to the highest plain X.Y.Z in the pinned major" \
    "10.16.0 3.10.2" "$(pins_get "$NPM_PINS" '"\(.dependencies.eslint) \(.dependencies.prettier)"')"
  check_eq "pins: npm leaves the other dependencies alone" "file:eslint-config" \
    "$(pins_get "$NPM_PINS" '.dependencies["@nigelng/eslint-config"]')"
  check_has "pins: npm reports old -> new" "$PINS_OUT" "pins: npm: prettier 3.10.1 -> 3.10.2"
  check_lacks "pins: npm same-major bump has no major warning" "$PINS_OUT" "available"

  pins_setup npm-major npm-major
  pins_run npm
  check_eq "pins: npm new-major warning exits 0" 0 "$PINS_RC"
  check_has "pins: npm warns about the newer major" "$PINS_OUT" "pins: npm: eslint 11 available"
  check_pins_untouched "pins: npm never auto-bumps across a major" "$NPM_PINS"
}

test_pins_continues_after_failure() {
  pins_setup all-continue amo-bad-guid npm-minor
  pins_run all
  check_eq "pins: all exits 1 when one updater fails" 1 "$PINS_RC"
  check_pins_untouched "pins: all leaves the failed sidecar untouched" "$ADDONS_PINS"
  check_eq "pins: all still runs the other updaters after a failure" 10.16.0 \
    "$(pins_get "$NPM_PINS" '.dependencies.eslint')"
  check_has "pins: all reports the failing source" "$PINS_ERR" "amo"
  check_pins_offline "pins: all never calls curl"
}

test_pins_fixture_seam() {
  pins_setup seam npm-minor
  rm "$PINS_DIR/fx/registry.npmjs.org_eslint.json"
  pins_run npm
  check_eq "pins: a missing fixture fails the run" 1 "$PINS_RC"
  check_has "pins: a missing fixture is named" "$PINS_ERR" "missing fixture"
  check_pins_untouched "pins: a missing fixture leaves the sidecar untouched" "$NPM_PINS"
  check_pins_offline "pins: a missing fixture does not fall through to curl"
}

test_pins_cli() {
  pins_setup cli npm-minor
  PINS_ENV_ROOT="$PINS_DIR/nonexistent" pins_run --root "$PINS_DIR/root" npm
  check_eq "pins: --root overrides UPDATE_PINS_ROOT" 10.16.0 "$(pins_get "$NPM_PINS" '.dependencies.eslint')"
  pins_run bogus
  check_eq "pins: an unknown source is a usage error" 2 "$PINS_RC"

  pins_setup cli-two npm-minor
  pins_run amo npm
  check_eq "pins: a second source is a usage error" 2 "$PINS_RC"
  check_has "pins: a second source is explained on stderr" "$PINS_ERR" "only one source"
  check_eq "pins: a rejected second source runs nothing" "" "$PINS_OUT"
  check_pins_untouched "pins: a rejected second source leaves the first sidecar alone" "$ADDONS_PINS"
  check_pins_untouched "pins: a rejected second source leaves the last sidecar alone" "$NPM_PINS"
  pins_run npm all
  check_eq "pins: a source followed by all is a usage error" 2 "$PINS_RC"
}

# GH_TOKEN scoping: source the script with fixtures off and the stub curl first
# on PATH; fetch_json must send the bearer token to https://api.github.com/ only.
pins_fetch() { # url...: fetch_json each url with GH_TOKEN=tok-secret
  # shellcheck disable=SC2016 # the inner script's $1/$u expand in the child bash
  env -u UPDATE_PINS_FIXTURES \
    PATH="$PINS_DIR/bin:$PATH" PINS_CURL_LOG="$PINS_DIR/curl.log" PINS_CURL_RC=0 \
    GH_TOKEN="${PINS_TOKEN-tok-secret}" \
    bash -c '. "$1"; shift; for u; do fetch_json "$u" -X POST -d "{}" >/dev/null; done' _ \
    "$ROOT/scripts/update-pins.sh" "$@"
}

# curl_call URL: the stub's logged line for that URL (the URL is its last field).
curl_call() { awk -F '\t' -v u="$1" '$NF == u' "$PINS_DIR/curl.log"; }

check_pins_no_auth() { # url
  local call
  call="$(curl_call "$1")"
  check_has "pins: GH_TOKEN scoping: request was made for $1" "$call" "$1"
  check_lacks "pins: GH_TOKEN scoping: no Authorization for $1" "$call" "Authorization"
}

test_pins_token_scope() {
  local gh="https://api.github.com/repos/google/fonts/commits/HEAD" call
  pins_setup token
  pins_fetch \
    "https://addons.mozilla.org/api/v5/addons/addon/x/" \
    "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
    "https://registry.npmjs.org/eslint" \
    "https://api.github.com.evil.example/repos/x" \
    "https://api.github.com@evil.example/repos/x" \
    "$gh"
  check_pins_no_auth "https://addons.mozilla.org/api/v5/addons/addon/x/"
  check_pins_no_auth "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
  check_pins_no_auth "https://registry.npmjs.org/eslint"
  check_pins_no_auth "https://api.github.com.evil.example/repos/x"
  check_pins_no_auth "https://api.github.com@evil.example/repos/x"
  call="$(curl_call "$gh")"
  check_has "pins: GH_TOKEN scoping: bearer token sent to https://api.github.com/" "$call" \
    "Authorization: Bearer tok-secret"
  check_eq "pins: GH_TOKEN scoping: the token appears in exactly one request" 1 \
    "$(grep -c -F tok-secret "$PINS_DIR/curl.log" || true)"

  pins_setup token-unset
  PINS_TOKEN="" pins_fetch "$gh"
  check_lacks "pins: GH_TOKEN scoping: no Authorization when GH_TOKEN is empty" "$(curl_call "$gh")" \
    "Authorization"
}

repo_fingerprint() { # tracked-file state: porcelain status plus a hash of the diff
  git -C "$ROOT" status --porcelain
  git -C "$ROOT" diff | git hash-object --stdin
}

test_pins() {
  local before="" after="" tracked=0
  need_tools nix jq git
  init_tmp
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tracked=1
    before="$(repo_fingerprint)"
  fi
  test_pins_amo_bump
  test_pins_amo_rejections
  test_pins_vscode
  test_pins_bat
  test_pins_google_fonts
  test_pins_npm
  test_pins_continues_after_failure
  test_pins_fixture_seam
  test_pins_cli
  test_pins_version_newer
  test_pins_fake_hash_build
  test_pins_prefetch_fallbacks
  test_pins_report_sanitized
  test_pins_errexit
  test_pins_token_scope
  if [ "$tracked" = 1 ]; then
    after="$(repo_fingerprint)"
    check_eq "pins: the case leaves the repo's tracked-file state unchanged" "$before" "$after"
  fi
}

# --- entry point ----------------------------------------------------------------

usage() {
  echo "usage: ${0##*/} [apps|gc|android|git|shell|host|schema|cursor|wrapper|release|pins|all]"
}

summary() {
  printf '\n%s checks, %s failed\n' "$CHECKS" "$FAILURES"
  [ "$FAILURES" -eq 0 ]
}

main() {
  case "${1:-all}" in
    apps) test_apps ;;
    gc) test_gc ;;
    android) test_android ;;
    git) test_git ;;
    shell) test_shell ;;
    host) test_host ;;
    schema) test_schema ;;
    cursor) test_cursor ;;
    wrapper) test_wrapper ;;
    release) test_release ;;
    pins) test_pins ;;
    all)
      test_wrapper
      test_apps
      test_gc
      test_android
      test_git
      test_shell
      test_host
      test_schema
      test_cursor
      test_release
      test_pins
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  summary
}

main "$@"
