#!/usr/bin/env bash
# Focused regression checks for default-install and JSON-config correctness.
#
# Usage: scripts/test-correctness.sh [apps|gc|android|git|wrapper|all]
#   (default: all). Run from anywhere; the repo root is derived from this file.
#
# Tools (nix, jq, python3 jsonschema) are only required by the cases that use
# them, so `wrapper` also runs under the stock macOS /bin/bash 3.2. Everything is
# Bash 3.2 compatible: no mapfile, associative arrays, ${var,,} or |&.
#
# No case activates a system, escalates privileges, garbage-collects, or builds
# the Android SDK or a full darwin system: app tests use fake nix/sudo/
# darwin-rebuild executables, and the other cases only evaluate.
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

# schema_check LABEL valid|invalid JSON
schema_check() {
  local file="$TMP/schema/$((CHECKS + 1)).json" rc=0
  mkdir -p "$TMP/schema"
  printf '%s\n' "$3" >"$file"
  python3 - "$ROOT/config/schema/android.schema.json" "$file" <<'PY' || rc=$?
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
    die "schema validation harness error (status $rc) for: $3"
  fi
  if [ "$2" = valid ] && [ "$rc" = 0 ]; then
    pass "schema: accepts $1"
  elif [ "$2" = invalid ] && [ "$rc" != 0 ]; then
    pass "schema: rejects $1"
  else
    fail "schema: should $([ "$2" = valid ] && echo accept || echo reject) $1" "document: $3"
  fi
}

test_android_schema() {
  python3 -c 'import jsonschema' 2>/dev/null || die "python jsonschema is required (run inside 'nix develop')"
  schema_check "lists of strings" valid "$(jq -c '. + {"enable": true}' <<<"$ANDROID_BASE_LISTS")"
  schema_check "explicit empty lists" valid '{"platformVersions":[],"systemImageTypes":[],"abiVersions":[]}'
  schema_check "existing scalar keys" valid \
    '{"enable":true,"avdHome":"/x","guiSdkSymlink":true,"avdDefaultSymlink":false,"jdkPackage":"jdk17"}'
  schema_check "the shipped base.json" valid "$(cat "$ROOT/config/android/base.json")"
  schema_check "an unknown key (typo)" invalid '{"platformVersion":["34"]}'
  schema_check "a string where a list is expected" invalid '{"platformVersions":"34"}'
  schema_check "an object where a list is expected" invalid '{"systemImageTypes":{"a":1}}'
  schema_check "a number where a list is expected" invalid '{"abiVersions":5}'
  schema_check "a non-string platformVersions element" invalid '{"platformVersions":[34]}'
  schema_check "a null abiVersions element" invalid '{"abiVersions":["arm64-v8a",null]}'
}

test_android() {
  need_tools nix jq python3
  init_tmp
  test_android_loader
  test_android_schema
}

# --- case: git -----------------------------------------------------------------

# Evaluates the real home/git.nix through Home Manager for three gitConfig shapes
# (no includes key, empty list, several conditional/unconditional includes). Only
# the git config file and include list are read, so nothing is built.
nix_git_expr() {
  cat <<'NIX'
let
  rootDir = builtins.getEnv "T_ROOT";
  flake = builtins.getFlake "git+file://${rootDir}";
  hm = flake.inputs.home-manager;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  evalGit =
    gitConfig:
    let
      cfg =
        (hm.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            "${rootDir}/home/git.nix"
            {
              home = {
                username = "tester";
                homeDirectory = "/Users/tester";
                stateVersion = "25.11";
              };
            }
          ];
          extraSpecialArgs = {
            inherit gitConfig;
            userConfig = {
              name = "Test User";
              email = "test@example.com";
              defaultSigningKey = "ssh-ed25519 AAAA";
            };
          };
        }).config;
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
  missing = evalGit { };
  empty = evalGit { includes = [ ]; };
  multi = evalGit {
    includes = [
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

test_git() {
  need_tools nix jq
  init_tmp
  export T_ROOT="$ROOT"
  run_eval nix eval --impure --json --expr "$(nix_git_expr)"
  if [ "$EVAL_RC" != 0 ]; then
    fail "git: evaluate home/git.nix" "$EVAL_ERR"
  else
    check_git_results "$EVAL_OUT"
  fi
}

# --- entry point ----------------------------------------------------------------

usage() {
  echo "usage: ${0##*/} [apps|gc|android|git|wrapper|all]"
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
    wrapper) test_wrapper ;;
    all)
      test_wrapper
      test_apps
      test_gc
      test_android
      test_git
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
