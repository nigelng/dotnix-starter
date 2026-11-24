#!/usr/bin/env bash
# tiers.sh — resolve model tier pins from tiers.json.
# Bash 3.2: no associative arrays, no mapfile, no ${var,,}.
#
# Reads tiers.json from its own directory. When the override file
# ${NNG_KIT_TIERS:-${XDG_CONFIG_HOME:-$HOME/.config}/nng-kit/tiers.json}
# exists, it is deep-merged over the shipped file (jq '.[0] * .[1]':
# objects merge, arrays replace). KIT_TODAY overrides the date for tests;
# a row or tool is expired when today > until (string compare).
#
# authenv <tool> prints the merged authEnv names, one per line (the
# launchers validate them). runner-tool <runner> prints the tool whose
# reviewRunners lists <runner>; a runner listed by several tools resolves
# to the first in canonical order, the same order `runners` dedupes in.
#
# Exit codes: 0 ok; 2 usage error, unknown tool, unknown tier, missing jq,
# malformed JSON (shipped or override); 3 no usable pin / disabled tool /
# no tool lists the runner.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIPPED="$DIR/tiers.json"
OVERRIDE="${NNG_KIT_TIERS:-${XDG_CONFIG_HOME:-${HOME:-}/.config}/nng-kit/tiers.json}"
TODAY="${KIT_TODAY:-}" # resolve fills it; the other commands need no `date`
TIER_NAMES="top-plan top-review top-critique execute mid low"

die() {
  local rc=$1
  shift
  echo "tiers.sh: $*" >&2
  exit "$rc"
}

usage() {
  echo "usage: tiers.sh tools|host|order|delegates|runners|validate" >&2
  echo "       tiers.sh resolve <tool> <tier> [--role implement|review]" >&2
  echo "       tiers.sh authenv <tool> | runner-tool <runner>" >&2
}

command -v jq >/dev/null 2>&1 || die 2 "jq not found on PATH"
[[ -f "$SHIPPED" ]] || die 2 "registry not found: $SHIPPED"

if [[ -f "$OVERRIDE" ]]; then
  if ! REGISTRY=$(jq -s '.[0] * .[1]' "$SHIPPED" "$OVERRIDE"); then
    die 2 "malformed JSON in $SHIPPED or $OVERRIDE"
  fi
else
  if ! REGISTRY=$(jq '.' "$SHIPPED"); then
    die 2 "malformed JSON in $SHIPPED"
  fi
fi

# Canonical tool order: planningOrder first, then any other tool ids in
# document (key) order. Emitted as a jq snippet used by several commands.
TOOL_ORDER='(($r.planningOrder // []) + ((($r.tools // {}) | keys_unsorted) - ($r.planningOrder // [])))'

cmd_tools() {
  jq -r ". as \$r | ${TOOL_ORDER}[] as \$t
    | select((\$r.tools[\$t].enabled // false) == true) | \$t" <<<"$REGISTRY"
}

cmd_host() {
  jq -r '.host // empty' <<<"$REGISTRY"
}

cmd_order() {
  jq -r '. as $r | ($r.planningOrder // [])[] as $t
    | select(($r.tools[$t].enabled // false) == true) | $t' <<<"$REGISTRY"
}

cmd_delegates() {
  jq -r ". as \$r | ${TOOL_ORDER}[] as \$t
    | select((\$r.tools[\$t].delegate // false) == true) | \$t" <<<"$REGISTRY"
}

cmd_runners() {
  jq -r ". as \$r
    | [ ${TOOL_ORDER}[] as \$t | ((\$r.tools[\$t].reviewRunners // {}) | keys_unsorted[]) ]
    | reduce .[] as \$x ([]; if index(\$x) == null then . + [\$x] else . end)
    | .[] | select(. != \"session\") | \"top@\(.)\"" <<<"$REGISTRY"
}

require_tool() {
  jq -e --arg t "$1" '.tools | has($t)' <<<"$REGISTRY" >/dev/null \
    || die 2 "unknown tool: $1"
}

cmd_authenv() {
  require_tool "$1"
  jq -r --arg t "$1" '(.tools[$t].authEnv // [])[]' <<<"$REGISTRY"
}

cmd_runner_tool() {
  local tool
  tool=$(jq -r --arg x "$1" ". as \$r | [ ${TOOL_ORDER}[] as \$t
    | select((\$r.tools[\$t].reviewRunners // {}) | has(\$x)) | \$t ] | .[0] // empty" <<<"$REGISTRY")
  [[ -n "$tool" ]] || die 3 "no tool lists review runner: $1"
  printf '%s\n' "$tool"
}

# resolve_tier <tool> <tier> <role> — tool must exist. Prints the first
# usable model on stdout and returns 0; expired candidates are logged to
# stderr. execute falls through to mid --role implement, low to mid with
# the same role, each logging "fallback: <tier>→mid"; mid and top-*
# return 3 when no candidate is usable.
resolve_tier() {
  local tool=$1 tier=$2 role=$3
  local enabled tuntil texp rows status model

  enabled=$(jq -r --arg t "$tool" '.tools[$t].enabled // false' <<<"$REGISTRY")
  [[ "$enabled" == "true" ]] || return 3

  texp=false
  tuntil=$(jq -r --arg t "$tool" '.tools[$t].until // ""' <<<"$REGISTRY")
  if [[ -n "$tuntil" && "$TODAY" > "$tuntil" ]]; then
    texp=true
  fi

  if ! rows=$(jq -r \
      --arg t "$tool" --arg tier "$tier" --arg role "$role" \
      --arg today "$TODAY" --argjson texp "$texp" '
    (.tools[$t].tiers[$tier]) as $rows
    | if ($rows | type) != "array" then error("tiers[" + $tier + "] is not an array") else $rows end
    | .[]
    | select((has("role") | not) or .role == $role)
    | select($role != "review" or .model != "auto")
    | if ($texp or (((.until // "") != "") and ($today > .until)))
      then "expired\t\(.model)"
      else "pin\t\(.model)"
      end
  ' <<<"$REGISTRY"); then
    die 2 "malformed registry rows for $tool/$tier"
  fi

  while IFS=$'\t' read -r status model; do
    [[ -z "$status" ]] && continue
    if [[ "$status" == "expired" ]]; then
      echo "fallback: expired $model" >&2
      continue
    fi
    printf '%s\n' "$model"
    return 0
  done <<<"$rows"

  case "$tier" in
    execute)
      echo "fallback: execute→mid" >&2
      resolve_tier "$tool" mid implement
      ;;
    low)
      echo "fallback: low→mid" >&2
      resolve_tier "$tool" mid "$role"
      ;;
    *)
      return 3
      ;;
  esac
}

cmd_resolve() {
  local tool=$1 tier=$2
  shift 2
  local role=implement
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role)
        [[ $# -ge 2 ]] || die 2 "--role needs implement or review"
        role=$2
        shift 2
        ;;
      --role=*)
        role=${1#--role=}
        shift
        ;;
      *)
        die 2 "unknown resolve argument: $1"
        ;;
    esac
  done
  [[ "$role" == "implement" || "$role" == "review" ]] || die 2 "--role must be implement or review"
  case " $TIER_NAMES " in
    *" $tier "*) ;;
    *) die 2 "unknown tier: $tier" ;;
  esac
  require_tool "$tool"
  [[ -n "$TODAY" ]] || TODAY=$(date +%F)

  resolve_tier "$tool" "$tier" "$role"
}

cmd_validate() {
  local problems
  if ! problems=$(jq -r '
    . as $r
    | (.tools // {}) as $tools
    | ($tools | keys_unsorted) as $ids
    | ([$ids[] as $t | (($tools[$t].reviewRunners // {}) | keys_unsorted[])]) as $runnerNames
    | (
        (if (($r.host | type) != "string") or (($ids | index($r.host)) == null)
          then "host is not a known tool id: \($r.host | tojson)" else empty end),

        (($r.planningOrder // [])[] | . as $id
          | select(($ids | index($id)) == null)
          | "planningOrder id is not a tool: \($id)"),

        ($ids[] as $t | ($tools[$t]) as $tool | (
          (["top-plan","top-review","top-critique","execute","mid","low"][] as $k
            | select(($tool.tiers[$k] | type) != "array")
            | "tools.\($t).tiers.\($k): missing or not an array"),

          (if (($tool | has("until"))
               and (($tool.until | type) != "string"
                    or (($tool.until | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) | not)))
            then "tools.\($t).until: must match YYYY-MM-DD" else empty end),

          (($tool.defaultReviewRunner // null) as $d
            | if (($d != null) and (($runnerNames | index($d)) == null))
              then "tools.\($t).defaultReviewRunner is not a reviewRunner: \($d)" else empty end),

          (($tool.tiers // {}) | to_entries[]
            | select(.value | type == "array")
            | .key as $k
            | (.value | to_entries[]) | .key as $i | .value as $row
            | if ($row | type) != "object"
              then "tools.\($t).tiers.\($k)[\($i)]: row must be an object"
              else
                (if (($row.model | type) != "string")
                  then "tools.\($t).tiers.\($k)[\($i)].model: must be a string" else empty end),
                (if (($row | has("until"))
                     and (($row.until | type) != "string"
                          or (($row.until | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) | not)))
                  then "tools.\($t).tiers.\($k)[\($i)].until: must match YYYY-MM-DD" else empty end),
                (if (($row | has("role"))
                     and ((["implement","review"] | index($row.role)) == null))
                  then "tools.\($t).tiers.\($k)[\($i)].role: must be implement or review" else empty end)
              end
          )
        ))
      )
  ' <<<"$REGISTRY"); then
    die 2 "validate: could not evaluate registry"
  fi
  if [[ -n "$problems" ]]; then
    printf '%s\n' "$problems" >&2
    exit 2
  fi
}

main() {
  [[ $# -ge 1 ]] || { usage; exit 2; }
  local cmd=$1
  shift
  case "$cmd" in
    tools | host | order | delegates | runners | validate)
      [[ $# -eq 0 ]] || { usage; exit 2; }
      "cmd_$cmd"
      ;;
    resolve)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      cmd_resolve "$@"
      ;;
    authenv)
      [[ $# -eq 1 ]] || { usage; exit 2; }
      cmd_authenv "$1"
      ;;
    runner-tool)
      [[ $# -eq 1 ]] || { usage; exit 2; }
      cmd_runner_tool "$1"
      ;;
    *)
      echo "tiers.sh: unknown subcommand: $cmd" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
