#!/usr/bin/env bash
# plan-status.sh — lock, rows, and status writes (start, batch, terminal, review).
# Bash 3.2: no associative arrays, no mapfile, no ${var,,}.
# Writers dual-write execution: and ## Execution log via one temp file + mv.
set -euo pipefail

usage() {
  echo "usage: plan-status.sh lock [--gate] <plan>" >&2
  echo "       plan-status.sh rows [--reexecute] <plan> <backend> [ID...]" >&2
  echo "       plan-status.sh rows --lint <plan>" >&2
  echo "       plan-status.sh start <plan> <last_skill> <rows-json> [--now TS] [--reexecute]" >&2
  echo "       plan-status.sh batch <plan> <last_skill> (--done ID... | --failed ID... | --skipped ID --note TEXT)... [--now TS]" >&2
  echo "       plan-status.sh terminal <plan> <last_skill> <rows-json> --outcome pass|fail|abort --backend B --model-requested S --model-resolved S --effort E --started TS --findings N --fix-loops N --fallback R|null [--usage <json>] [--done ID...] [--notes TEXT] [--now TS] [--deferred-review]" >&2
  echo "       plan-status.sh review <plan> [ID] --outcome pass|fail --runner <top@…> --findings N [--notes TEXT] [--now TS]" >&2
  echo "       plan-status.sh stamp <plan> [--now TS]" >&2
  echo "       plan-status.sh recent <dir>" >&2
  echo "       plan-status.sh approve <plan> [--now TS]" >&2
}

is_blank_dash() {
  case "$1" in
    "" | "-" | "—" | "–") return 0 ;;
    *) return 1 ;;
  esac
}

trim_ws() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_h2() {
  case "$1" in
    '###'*) return 1 ;;
    '## '*) return 0 ;;
    '##	'*) return 0 ;;
    *) return 1 ;;
  esac
}

h2_title() {
  local line=$1
  case "$line" in
    '###'*) printf '' ;;
    '## '*)
      line=${line#'## '}
      printf '%s' "$(trim_ws "$line")"
      ;;
    '##	'*)
      line=${line#'##	'}
      printf '%s' "$(trim_ws "$line")"
      ;;
    *) printf '' ;;
  esac
}

# Split a markdown table row on unescaped |. Sets global CELLS.
split_row() {
  local line=$1 buf="" i c n nxt
  line=${line%$'\r'}
  line="$(trim_ws "$line")"
  if [[ "$line" == "|"* ]]; then line=${line#"|"}; fi
  if [[ "$line" == *"|" ]]; then line=${line%"|"}; fi
  CELLS=()
  buf=""
  n=${#line}
  for ((i = 0; i < n; i++)); do
    c=${line:i:1}
    if [[ "$c" == '\' ]]; then
      nxt=${line:i+1:1}
      if [[ "$nxt" == "|" ]]; then
        buf+="|"
        i=$((i + 1))
        continue
      fi
      buf+="$c"
      continue
    fi
    if [[ "$c" == "|" ]]; then
      CELLS+=("$(trim_ws "$buf")")
      buf=""
      continue
    fi
    buf+="$c"
  done
  CELLS+=("$(trim_ws "$buf")")
}

is_separator_line() {
  local s=$1 t
  case "$s" in
    *'|'* ) ;;
    *) return 1 ;;
  esac
  t=${s//|/}
  t=${t//-/}
  t=${t//:/}
  t=${t// /}
  t=${t//$'\t'/}
  [[ -z "$t" ]]
}

cell_at() {
  local idx=$1
  if [[ "$idx" -lt 0 ]]; then
    printf ''
    return
  fi
  if [[ "$idx" -ge ${#CELLS[@]} ]]; then
    printf ''
    return
  fi
  printf '%s' "${CELLS[$idx]}"
}

lower_ascii() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Exact membership in a newline-separated list. Empty needle never matches.
in_list() {
  local needle=$1 list=$2 item
  [[ -n "$needle" ]] || return 1
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ "$item" == "$needle" ]] && return 0
  done <<<"$list"
  return 1
}

norm_tier() {
  local t
  t=$(lower_ascii "$1")
  case "$t" in
    "-" | "—" | "–") printf 'UNSCHED' ;;
    "") printf 'INVALID' ;;
    opus) printf 'top' ;;
    auto | sonnet) printf 'mid' ;;
    haiku) printf 'low' ;;
    top | execute | mid | low) printf '%s' "$t" ;;
    *) printf 'INVALID' ;;
  esac
}

norm_runner() {
  local raw=$1 tier=$2 r id
  if is_blank_dash "$raw"; then
    if [[ "$tier" == top ]]; then
      printf 'session'
    else
      printf 'subagent'
    fi
    return
  fi
  r=$(lower_ascii "$raw")
  case "$r" in
    session | subagent)
      printf '%s' "$r"
      ;;
    delegate:*)
      id=${r#delegate:}
      if in_list "$id" "$REG_DELEGATES_LC"; then
        printf '%s' "$r"
      else
        printf 'INVALID'
      fi
      ;;
    *) printf 'INVALID' ;;
  esac
}

norm_review() {
  local r
  if is_blank_dash "$1"; then
    printf 'mid'
    return
  fi
  r=$(lower_ascii "$1")
  case "$r" in
    top@session | mid | none)
      printf '%s' "$r"
      ;;
    *)
      if in_list "$r" "$REG_RUNNERS_LC"; then
        printf '%s' "$r"
      else
        printf 'INVALID'
      fi
      ;;
  esac
}

clean_text() {
  local s=$1
  s=${s//\`/}
  s=$(trim_ws "$s")
  if is_blank_dash "$s"; then
    printf ''
  else
    printf '%s' "$s"
  fi
}

has_nested_braces() {
  local s=$1 n=${#s} i c depth=0
  for ((i = 0; i < n; i++)); do
    c=${s:i:1}
    if [[ "$c" == '{' ]]; then
      if [[ $depth -ge 1 ]]; then
        return 0
      fi
      depth=1
    elif [[ "$c" == '}' ]]; then
      depth=0
    fi
  done
  return 1
}

# One non-nested brace level. Nested braces stay literal.
expand_braces() {
  local s=$1
  if has_nested_braces "$s"; then
    printf '%s\n' "$s"
    return
  fi
  local n=${#s} i c open=-1 mid pre post alt oldifs
  local -a alts=()
  for ((i = 0; i < n; i++)); do
    c=${s:i:1}
    if [[ "$c" == '{' ]]; then
      open=$i
    elif [[ "$c" == '}' && $open -ge 0 ]]; then
      mid=${s:open+1:i-open-1}
      case "$mid" in
        *,*)
          pre=${s:0:open}
          post=${s:i+1}
          oldifs=$IFS
          alts=()
          IFS=, read -r -a alts <<< "$mid" || true
          IFS=$oldifs
          for alt in ${alts[@]+"${alts[@]}"}; do
            expand_braces "${pre}${alt}${post}"
          done
          return
          ;;
      esac
      open=-1
    fi
  done
  printf '%s\n' "$s"
}

# Backticked tokens, each brace-expanded, one path per line.
extract_files() {
  local cell=$1 rest tok tick
  if is_blank_dash "$cell"; then
    return
  fi
  tick='`'
  rest=$cell
  while [[ "$rest" == *"$tick"* ]]; do
    rest=${rest#*$tick}
    [[ "$rest" == *"$tick"* ]] || break
    tok=${rest%%$tick*}
    rest=${rest#*$tick}
    [[ -n "$tok" ]] || continue
    expand_braces "$tok"
  done
}

parse_depends() {
  local cell=$1 p
  local -a parts=()
  if is_blank_dash "$cell"; then
    return
  fi
  IFS=, read -r -a parts <<< "$cell" || true
  for p in ${parts[@]+"${parts[@]}"}; do
    p=$(trim_ws "$p")
    if is_blank_dash "$p"; then
      continue
    fi
    printf '%s\n' "$p"
  done
}

lines_to_json() {
  local out='[' first=1 line enc
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    enc=$(jq -Rn --arg s "$line" '$s')
    if [[ $first -eq 1 ]]; then
      first=0
    else
      out+=','
    fi
    out+="$enc"
  done
  if [[ $first -eq 1 ]]; then
    printf '[]'
  else
    printf '%s]' "$out"
  fi
}

blob_to_json() {
  local blob=$1
  printf '%s\n' "$blob" | lines_to_json
}

refuse() {
  REFUSES+=("REFUSE: $1")
}

skip_row() {
  local id=$1 note=$2 obj
  obj=$(jq -n -c --arg id "$id" --arg note "$note" '{id:$id,note:$note}')
  SKIPPED_JSON=$(jq -n -c --argjson arr "$SKIPPED_JSON" --argjson obj "$obj" '$arr + [$obj]')
}

block_row() {
  local id=$1 on=$2 obj
  obj=$(jq -n -c --arg id "$id" --arg on "$on" '{id:$id,on:$on}')
  BLOCKED_JSON=$(jq -n -c --argjson arr "$BLOCKED_JSON" --argjson obj "$obj" '$arr + [$obj]')
  BLOCKED_SET+="${id}"$'\n'
}

is_blocked() {
  case $'\n'"$BLOCKED_SET" in
    *$'\n'"$1"$'\n'*) return 0 ;;
  esac
  return 1
}

header_index() {
  local name=$1 i h
  for ((i = 0; i < ${#CELLS[@]}; i++)); do
    h=$(lower_ascii "$(trim_ws "${CELLS[$i]}")")
    if [[ "$h" == "$name" ]]; then
      printf '%s' "$i"
      return
    fi
  done
  printf '%s' "-1"
}

parse_header() {
  NCOLS=${#CELLS[@]}
  COL_ID=$(header_index "id")
  COL_TIER=$(header_index "tier")
  COL_RUNNER=$(header_index "runner")
  COL_WAVE=$(header_index "wave")
  COL_DEP=$(header_index "depends on")
  COL_FILES=$(header_index "files")
  COL_ACC=$(header_index "acceptance")
  COL_MODEL=$(header_index "model")
  COL_REVIEW=$(header_index "review")
}

add_parsed_row() {
  local id tier_raw tier runner_raw runner wave dep_cell files_cell acc_cell model_cell review_raw
  local dep_blob files_blob
  id=$(cell_at "$COL_ID")
  id=$(trim_ws "$id")
  if [[ -z "$id" ]]; then
    id='?'
  fi
  tier_raw=$(cell_at "$COL_TIER")
  tier=$(norm_tier "$tier_raw")
  ROW_ID[$ROW_N]=$id
  ROW_BAD[$ROW_N]=0
  files_cell=$(cell_at "$COL_FILES")
  ROW_FILES_RAW[$ROW_N]=$(trim_ws "$files_cell")
  if [[ "$tier" == UNSCHED ]]; then
    ROW_UNSCHED[$ROW_N]=1
    ROW_TIER[$ROW_N]=""
    ROW_RUNNER[$ROW_N]=""
    ROW_WAVE[$ROW_N]=""
    ROW_DEP[$ROW_N]=""
    ROW_FILES[$ROW_N]=""
    ROW_ACC[$ROW_N]=""
    ROW_MODEL[$ROW_N]=""
    ROW_REVIEW[$ROW_N]=""
    ROW_N=$((ROW_N + 1))
    return
  fi
  ROW_UNSCHED[$ROW_N]=0
  if [[ "$tier" == INVALID ]]; then
    ROW_TIER[$ROW_N]=INVALID
  else
    ROW_TIER[$ROW_N]=$tier
  fi
  runner_raw=$(cell_at "$COL_RUNNER")
  if [[ "$tier" == INVALID ]]; then
    runner=$(norm_runner "$runner_raw" "execute")
  else
    runner=$(norm_runner "$runner_raw" "$tier")
  fi
  ROW_RUNNER[$ROW_N]=$runner
  wave=$(cell_at "$COL_WAVE")
  wave=$(trim_ws "$wave")
  if is_blank_dash "$wave"; then
    wave=""
  fi
  ROW_WAVE[$ROW_N]=$wave
  dep_cell=$(cell_at "$COL_DEP")
  dep_blob=$(parse_depends "$dep_cell" || true)
  ROW_DEP[$ROW_N]=$dep_blob
  files_blob=$(extract_files "$files_cell" || true)
  ROW_FILES[$ROW_N]=$files_blob
  acc_cell=$(cell_at "$COL_ACC")
  ROW_ACC[$ROW_N]=$(clean_text "$acc_cell")
  model_cell=$(cell_at "$COL_MODEL")
  ROW_MODEL[$ROW_N]=$(clean_text "$model_cell")
  review_raw=$(cell_at "$COL_REVIEW")
  ROW_REVIEW[$ROW_N]=$(norm_review "$review_raw")
  ROW_N=$((ROW_N + 1))
}

parse_map() {
  local file=$1 line title in=0 intable=0 saw=0 bad_id
  MAP_KIND=none
  in=0
  intable=0
  saw=0
  COL_ID=-1
  COL_TIER=-1
  COL_RUNNER=-1
  COL_WAVE=-1
  COL_DEP=-1
  COL_FILES=-1
  COL_ACC=-1
  COL_MODEL=-1
  COL_REVIEW=-1
  NCOLS=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ $in -eq 0 ]]; then
      if is_h2 "$line"; then
        title=$(h2_title "$line")
        if [[ "$title" == "Execution map" ]]; then
          in=1
        fi
      fi
      continue
    fi
    if is_h2 "$line"; then
      break
    fi
    if [[ $intable -eq 0 ]]; then
      case "$line" in
        '|'*) ;;
        *) continue ;;
      esac
      if is_separator_line "$line"; then
        continue
      fi
      split_row "$line"
      parse_header
      if [[ "$COL_ID" -lt 0 ]]; then
        refuse "?: malformed map (no ID column)"
        saw=1
        intable=1
        MAP_KIND=legacy
        continue
      fi
      saw=1
      intable=1
      continue
    fi
    case "$line" in
      '|'*) ;;
      *) break ;;
    esac
    if is_separator_line "$line"; then
      continue
    fi
    split_row "$line"
    if [[ ${#CELLS[@]} -ne $NCOLS ]]; then
      if [[ $COL_ID -ge 0 && $COL_ID -lt ${#CELLS[@]} ]]; then
        bad_id=$(trim_ws "${CELLS[$COL_ID]}")
      else
        bad_id='?'
      fi
      if [[ -z "$bad_id" ]]; then
        bad_id='?'
      fi
      refuse "$bad_id: malformed row (cell count)"
      continue
    fi
    add_parsed_row
  done < "$file"
  if [[ $saw -eq 0 ]]; then
    MAP_KIND=none
  elif [[ $COL_RUNNER -lt 0 ]]; then
    MAP_KIND=legacy
  else
    MAP_KIND=v2
  fi
}

parse_steps() {
  local file=$1 line title in=0 n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ $in -eq 0 ]]; then
      if is_h2 "$line"; then
        title=$(h2_title "$line")
        if [[ "$title" == "Implementation steps" ]]; then
          in=1
        fi
      fi
      continue
    fi
    if is_h2 "$line"; then
      break
    fi
    case "$line" in
      [0-9]*) ;;
      *) continue ;;
    esac
    case "$line" in
      [0-9]*.\ *) ;;
      [0-9][0-9]*.\ *) ;;
      *) continue ;;
    esac
    # Only a top-level numbered step (no leading whitespace — already true).
    n=$((n + 1))
    ROW_ID[$ROW_N]="I${n}"
    ROW_UNSCHED[$ROW_N]=0
    ROW_BAD[$ROW_N]=0
    ROW_TIER[$ROW_N]=execute
    ROW_RUNNER[$ROW_N]=subagent
    ROW_WAVE[$ROW_N]=1
    ROW_DEP[$ROW_N]=""
    ROW_FILES[$ROW_N]=""
    ROW_FILES_RAW[$ROW_N]=""
    ROW_ACC[$ROW_N]=""
    ROW_MODEL[$ROW_N]=""
    ROW_REVIEW[$ROW_N]=mid
    ROW_N=$((ROW_N + 1))
  done < "$file"
}

execution_status_of() {
  awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm == 1 && /^---[[:space:]]*$/ { exit }
    fm == 1 && /^execution:[[:space:]]*$/ { ex = 1; next }
    ex && /^[^[:space:]#]/ { exit }
    ex && /^[[:space:]]+status:[[:space:]]*/ {
      sub(/^[[:space:]]+status:[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      sub(/[[:space:]].*$/, "")
      print
      exit
    }
  ' "$1"
}

frontmatter_plan_sha() {
  frontmatter_top_key "$1" plan_sha
}

frontmatter_top_key() {
  local file=$1 key=$2
  awk -v key="$key" '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm == 1 && /^---[[:space:]]*$/ { exit }
    fm == 1 && index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      gsub(/^["'\'']|["'\'']$/, "")
      gsub(/[[:space:]]/, "")
      print
      exit
    }
  ' "$file"
}

parse_done() {
  local file=$1 line title in=0 intable=0
  local id_col=-1 st_col=-1 id st
  DONE_SET=$'\n'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ $in -eq 0 ]]; then
      if is_h2 "$line"; then
        title=$(h2_title "$line")
        if [[ "$title" == "Execution log" ]]; then
          in=1
        fi
      fi
      continue
    fi
    if is_h2 "$line"; then
      break
    fi
    if [[ $intable -eq 0 ]]; then
      case "$line" in
        '|'*) ;;
        *) continue ;;
      esac
      if is_separator_line "$line"; then
        continue
      fi
      split_row "$line"
      id_col=$(header_index "id")
      st_col=$(header_index "status")
      intable=1
      continue
    fi
    case "$line" in
      '|'*) ;;
      *) break ;;
    esac
    if is_separator_line "$line"; then
      continue
    fi
    split_row "$line"
    if [[ $id_col -lt 0 || $st_col -lt 0 ]]; then
      continue
    fi
    if [[ $id_col -ge ${#CELLS[@]} || $st_col -ge ${#CELLS[@]} ]]; then
      continue
    fi
    id=$(trim_ws "${CELLS[$id_col]}")
    st=$(trim_ws "${CELLS[$st_col]}")
    if [[ "$st" == done && -n "$id" ]]; then
      DONE_SET+="${id}"$'\n'
    fi
  done < "$file"
}

is_done() {
  case "$DONE_SET" in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

row_exists() {
  local id=$1 i
  for ((i = 0; i < ROW_N; i++)); do
    if [[ "${ROW_ID[$i]}" == "$id" ]]; then
      return 0
    fi
  done
  return 1
}

id_requested() {
  local id=$1 r
  if [[ ${#REQ[@]} -eq 0 ]]; then
    return 1
  fi
  for r in "${REQ[@]}"; do
    if [[ "$r" == "$id" ]]; then
      return 0
    fi
  done
  return 1
}

load_lock_fns() {
  local dir ref snippet
  dir=$(cd "$(dirname "$0")" && pwd)
  if [[ -f "$dir/../references/execution-status.md" ]]; then
    ref="$dir/../references/execution-status.md"
  elif [[ -f "$dir/../execution-status.md" ]]; then
    ref="$dir/../execution-status.md"
  else
    echo "usage: plan-status.sh: missing execution-status.md (looked beside $dir)" >&2
    exit 2
  fi
  snippet=$(awk '
    $0 == "<!-- plan-sha:start -->" { grab = 1; next }
    $0 == "<!-- plan-sha:end -->" { exit }
    grab && $0 !~ /^```/ { print }
  ' "$ref")
  if [[ -z "$snippet" ]]; then
    echo "usage: plan-status.sh: empty plan-sha snippet" >&2
    exit 2
  fi
  # shellcheck disable=SC2086
  eval "$snippet"
}

cmd_lock() {
  local gate=0
  if [[ "${1:-}" == "--gate" ]]; then
    gate=1
    shift
  fi
  local plan=${1:-}
  if [[ -z "$plan" || ! -f "$plan" || $# -gt 1 ]]; then
    usage
    exit 2
  fi
  load_lock_fns
  local key have want gsha gat
  key=$(frontmatter_plan_sha "$plan")
  if [[ $gate -eq 1 ]]; then
    if [[ -z "$key" ]]; then
      exit 3
    fi
    have=$(plan_sha "$plan")
    have=$(lower_ascii "$have")
    have=${have//[[:space:]]/}
    want=$(lower_ascii "$key")
    gsha=$(frontmatter_top_key "$plan" gate_b_sha)
    gat=$(frontmatter_top_key "$plan" gate_b_at)
    gsha=$(lower_ascii "$gsha")
    if [[ -n "$gsha" && "$gsha" == "$want" && "$gsha" == "$have" && -n "$gat" ]]; then
      printf '%s\n' "$gat"
      exit 0
    fi
    exit 3
  fi
  if [[ -z "$key" ]]; then
    printf '%s\n' "WARN: legacy plan (no plan_sha)" >&2
    printf '%s\n' legacy
    exit 0
  fi
  have=$(plan_sha "$plan")
  have=$(lower_ascii "$have")
  have=${have//[[:space:]]/}
  want=$(lower_ascii "$key")
  if [[ "$have" == "$want" ]]; then
    printf '%s\n' ok
    exit 0
  fi
  printf '%s\n' "plan body changed since approval; re-approve with /make-plan update $plan" >&2
  exit 3
}

check_unknown() {
  local id
  if [[ ${#REQ[@]} -eq 0 ]]; then
    return
  fi
  for id in "${REQ[@]}"; do
    if ! row_exists "$id"; then
      refuse "$id: unknown ID"
    fi
  done
}

check_review_batches() {
  local i j
  for ((i = 0; i < ROW_N; i++)); do
    [[ ${ROW_UNSCHED[$i]} -eq 1 || ${ROW_BAD[$i]} -eq 1 ]] && continue
    case ${ROW_REVIEW[$i]} in
      top@*) ;;
      *) continue ;;
    esac
    for ((j = i + 1; j < ROW_N; j++)); do
      [[ ${ROW_UNSCHED[$j]} -eq 1 || ${ROW_BAD[$j]} -eq 1 ]] && continue
      [[ ${ROW_WAVE[$i]} == "${ROW_WAVE[$j]}" ]] || continue
      [[ ${ROW_RUNNER[$i]} == "${ROW_RUNNER[$j]}" ]] || continue
      case ${ROW_REVIEW[$j]} in
        top@*) ;;
        *) continue ;;
      esac
      if [[ ${ROW_REVIEW[$i]} != "${ROW_REVIEW[$j]}" ]]; then
        refuse "${ROW_ID[$j]}: invalid Review"
        ROW_BAD[$j]=1
      fi
    done
  done
}

validate_rows() {
  local i tier runner model review acc id
  for ((i = 0; i < ROW_N; i++)); do
    [[ ${ROW_UNSCHED[$i]} -eq 1 ]] && continue
    id=${ROW_ID[$i]}
    tier=${ROW_TIER[$i]}
    runner=${ROW_RUNNER[$i]}
    model=${ROW_MODEL[$i]}
    review=${ROW_REVIEW[$i]}
    acc=${ROW_ACC[$i]}
    if [[ "$tier" == INVALID ]]; then
      refuse "$id: invalid Tier"
      ROW_BAD[$i]=1
      continue
    fi
    if [[ "$runner" == INVALID ]]; then
      refuse "$id: invalid Runner"
      ROW_BAD[$i]=1
      continue
    fi
    if [[ -n "$model" && "$model" != auto && "$model" != "auto(router)" ]]; then
      refuse "$id: invalid Model"
      ROW_BAD[$i]=1
      continue
    fi
    if [[ -n "$model" && ( "$tier" != low || "$runner" != "delegate:cursor" ) ]]; then
      refuse "$id: invalid Model"
      ROW_BAD[$i]=1
      continue
    fi
    if [[ "$review" == INVALID ]]; then
      refuse "$id: invalid Review"
      ROW_BAD[$i]=1
      continue
    fi
    if [[ "$review" == none ]]; then
      if [[ "$tier" != low || -z "$acc" ]]; then
        refuse "$id: invalid Review"
        ROW_BAD[$i]=1
        continue
      fi
    fi
    if [[ "$tier" == top && "$runner" == delegate:* ]]; then
      refuse "$id: top rows never run on a delegate"
      ROW_BAD[$i]=1
      continue
    fi
  done
  check_review_batches
}

consider_row() {
  local i=$1 id tier runner requested=0 filtered=0
  if [[ ${ROW_BAD[$i]} -eq 1 ]]; then
    return
  fi
  id=${ROW_ID[$i]}
  if [[ ${#REQ[@]} -gt 0 ]]; then
    filtered=1
    if id_requested "$id"; then
      requested=1
    fi
  fi
  if [[ ${ROW_UNSCHED[$i]} -eq 1 ]]; then
    if [[ $requested -eq 1 ]]; then
      refuse "$id: not scheduled"
    else
      skip_row "$id" "not scheduled"
    fi
    return
  fi
  if is_done "$id" && [[ $KEEP_DONE -eq 0 ]]; then
    return
  fi
  tier=${ROW_TIER[$i]}
  runner=${ROW_RUNNER[$i]}
  if [[ $filtered -eq 1 && $requested -eq 0 ]]; then
    if [[ "$tier" == top && "$runner" != delegate:* ]]; then
      skip_row "$id" "out of step-scope (top row: run in session)"
    else
      skip_row "$id" "out of step-scope"
    fi
    return
  fi
  if [[ "${BACKEND:-}" == claude-code && "$runner" == delegate:* ]]; then
    skip_row "$id" "out of step-scope (dispatch via delegate)"
    return
  fi
  if [[ "${BACKEND:-}" == claude-code ]]; then
    case "$runner" in
      session | subagent) SEL+=("$i") ;;
    esac
    return
  fi
  if [[ "$tier" == top ]]; then
    if [[ "$runner" == delegate:* || $requested -eq 1 ]]; then
      refuse "$id: top rows never run on a delegate"
    else
      skip_row "$id" "out of step-scope (top row: run in session)"
    fi
    return
  fi
  if [[ "$MAP_KIND" == v2 ]]; then
    if [[ "$runner" != "delegate:$BACKEND" ]]; then
      if [[ $requested -eq 1 ]]; then
        refuse "$id: routed to $runner"
      else
        skip_row "$id" "out of step-scope"
      fi
      return
    fi
  fi
  SEL+=("$i")
}

row_is_selected() {
  local id=$1 si
  if [[ ${#SEL[@]} -eq 0 ]]; then
    return 1
  fi
  for si in "${SEL[@]}"; do
    if [[ "${ROW_ID[$si]}" == "$id" ]]; then
      return 0
    fi
  done
  return 1
}

runner_of_id() {
  local id=$1 i
  for ((i = 0; i < ROW_N; i++)); do
    if [[ "${ROW_ID[$i]}" == "$id" ]]; then
      printf '%s' "${ROW_RUNNER[$i]}"
      return 0
    fi
  done
  return 1
}

check_deps() {
  local si id dep dep_runner changed=1
  if [[ ${#SEL[@]} -eq 0 ]]; then
    return
  fi
  for si in "${SEL[@]}"; do
    id=${ROW_ID[$si]}
    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      if row_is_selected "$dep"; then
        continue
      fi
      if is_done "$dep"; then
        continue
      fi
      if [[ "${BACKEND:-}" == claude-code ]]; then
        dep_runner=""
        if dep_runner=$(runner_of_id "$dep"); then
          case "$dep_runner" in
            delegate:*)
              block_row "$id" "$dep"
              continue
              ;;
          esac
        fi
      fi
      refuse "$id: depends on $dep (not done)"
    done <<< "${ROW_DEP[$si]}"
  done
  if [[ "${BACKEND:-}" != claude-code ]]; then
    return
  fi
  # A selected row that depends on a blocked row cannot run either (fixpoint).
  while [[ $changed -eq 1 ]]; do
    changed=0
    for si in "${SEL[@]}"; do
      id=${ROW_ID[$si]}
      if is_blocked "$id"; then
        continue
      fi
      while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        if is_blocked "$dep"; then
          block_row "$id" "$dep"
          changed=1
          break
        fi
      done <<< "${ROW_DEP[$si]}"
    done
  done
}

files_share() {
  local a=$1 b=$2 fa fb
  while IFS= read -r fa; do
    [[ -n "$fa" ]] || continue
    while IFS= read -r fb; do
      [[ -n "$fb" ]] || continue
      if [[ "$fa" == "$fb" ]]; then
        return 0
      fi
    done <<< "$b"
  done <<< "$a"
  return 1
}

check_overlap() {
  local n i j si sj
  n=${#SEL[@]}
  if [[ $n -lt 2 ]]; then
    return
  fi
  for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
      si=${SEL[$i]}
      sj=${SEL[$j]}
      if [[ ${ROW_WAVE[$si]} != "${ROW_WAVE[$sj]}" ]]; then
        continue
      fi
      if files_share "${ROW_FILES[$si]}" "${ROW_FILES[$sj]}"; then
        refuse "${ROW_ID[$sj]}: files overlap with ${ROW_ID[$si]}"
      fi
    done
  done
}

check_acceptance_lint() {
  local i
  for ((i = 0; i < ROW_N; i++)); do
    [[ ${ROW_UNSCHED[$i]} -eq 1 || ${ROW_BAD[$i]} -eq 1 ]] && continue
    if [[ ${ROW_TIER[$i]} != top && -z ${ROW_ACC[$i]} ]]; then
      refuse "${ROW_ID[$i]}: missing Acceptance"
    fi
  done
}

check_overlap_all() {
  local i j
  for ((i = 0; i < ROW_N; i++)); do
    [[ ${ROW_UNSCHED[$i]} -eq 1 || ${ROW_BAD[$i]} -eq 1 ]] && continue
    for ((j = i + 1; j < ROW_N; j++)); do
      [[ ${ROW_UNSCHED[$j]} -eq 1 || ${ROW_BAD[$j]} -eq 1 ]] && continue
      [[ ${ROW_WAVE[$i]} == "${ROW_WAVE[$j]}" ]] || continue
      if files_share "${ROW_FILES[$i]}" "${ROW_FILES[$j]}"; then
        refuse "${ROW_ID[$j]}: files overlap with ${ROW_ID[$i]}"
      fi
    done
  done
}

tier_rank() {
  case "$1" in
    low) printf '1' ;;
    execute) printf '2' ;;
    mid) printf '3' ;;
    *) printf '0' ;;
  esac
}

emit_json() {
  local si id tier wave acc model review dep_json files_json obj
  local best=0 rank name launch="" router_ok=1 file seen union_json='[]'
  if [[ ${#SEL[@]} -eq 0 ]]; then
    router_ok=0
  fi
  SELECTED_JSON='[]'
  for si in ${SEL[@]+"${SEL[@]}"}; do
    id=${ROW_ID[$si]}
    tier=${ROW_TIER[$si]}
    wave=${ROW_WAVE[$si]}
    acc=${ROW_ACC[$si]}
    model=${ROW_MODEL[$si]}
    review=${ROW_REVIEW[$si]}
    dep_json=$(blob_to_json "${ROW_DEP[$si]}")
    files_json=$(blob_to_json "${ROW_FILES[$si]}")
    obj=$(jq -n -c \
      --arg id "$id" \
      --arg tier "$tier" \
      --arg wave "$wave" \
      --argjson depends "$dep_json" \
      --argjson files "$files_json" \
      --arg acceptance "$acc" \
      --arg model "$model" \
      --arg review "$review" \
      '{id:$id,tier:$tier,wave:$wave,depends:$depends,files:$files,acceptance:$acceptance,model:$model,review:$review}')
    SELECTED_JSON=$(jq -n -c --argjson arr "$SELECTED_JSON" --argjson obj "$obj" '$arr + [$obj]')
    rank=$(tier_rank "$tier")
    if [[ "$rank" -gt $best ]]; then
      best=$rank
      launch=$tier
    fi
    if [[ "$BACKEND" != cursor || "$tier" != low ]]; then
      router_ok=0
    elif [[ "$model" != auto && "$model" != "auto(router)" ]]; then
      router_ok=0
    fi
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      seen=$'\n'"$UNION_SET"$'\n'
      case "$seen" in
        *$'\n'"$file"$'\n'*) continue ;;
      esac
      UNION_SET+="${file}"$'\n'
      union_json=$(jq -n -c --argjson arr "$union_json" --arg f "$file" '$arr + [$f]')
    done <<< "${ROW_FILES[$si]}"
  done
  if [[ $router_ok -eq 1 ]]; then
    router_json=true
  else
    router_json=false
  fi
  jq -n \
    --arg map "$MAP_KIND" \
    --arg launch_tier "$launch" \
    --argjson router "$router_json" \
    --argjson selected "$SELECTED_JSON" \
    --argjson skipped "$SKIPPED_JSON" \
    --argjson blocked "${BLOCKED_JSON:-[]}" \
    --argjson files_union "$union_json" \
    '{map:$map,launch_tier:$launch_tier,router:$router,selected:$selected,skipped:$skipped,blocked:$blocked,files_union:$files_union}'
}

print_refuses() {
  local r
  for r in ${REFUSES[@]+"${REFUSES[@]}"}; do
    printf '%s\n' "$r" >&2
  done
}

reset_row_state() {
  REFUSES=()
  SEL=()
  ROW_N=0
  ROW_ID=()
  ROW_TIER=()
  ROW_RUNNER=()
  ROW_WAVE=()
  ROW_DEP=()
  ROW_FILES=()
  ROW_FILES_RAW=()
  ROW_ACC=()
  ROW_MODEL=()
  ROW_REVIEW=()
  ROW_UNSCHED=()
  ROW_BAD=()
  SKIPPED_JSON='[]'
  BLOCKED_JSON='[]'
  BLOCKED_SET=$'\n'
  UNION_SET=""
  DONE_SET=$'\n'
}

check_selected_review_tools() {
  local si
  for si in ${SEL[@]+"${SEL[@]}"}; do
    if review_tool_disabled "${ROW_REVIEW[$si]}" >/dev/null; then
      refuse "${ROW_ID[$si]}: Review ${ROW_REVIEW[$si]} is disabled (${REVIEW_TOOL_LAST})"
    fi
  done
}

check_disabled_lint() {
  local i id runner
  for ((i = 0; i < ROW_N; i++)); do
    [[ ${ROW_UNSCHED[$i]} -eq 0 && ${ROW_BAD[$i]} -eq 0 ]] || continue
    id=${ROW_ID[$i]}
    if is_done "$id"; then
      continue
    fi
    runner=${ROW_RUNNER[$i]}
    case "$runner" in
      delegate:*)
        if ! tool_enabled "${runner#delegate:}"; then
          refuse "$id: Runner $runner is disabled"
        fi
        ;;
    esac
    if review_tool_disabled "${ROW_REVIEW[$i]}" >/dev/null; then
      refuse "$id: Review ${ROW_REVIEW[$i]} is disabled (${REVIEW_TOOL_LAST})"
    fi
  done
}

cmd_rows_lint() {
  local plan=$1
  if [[ ! -f "$plan" ]]; then
    usage
    exit 2
  fi
  reset_row_state
  parse_map "$plan"
  if [[ "$MAP_KIND" == none ]]; then
    parse_steps "$plan"
  fi
  parse_done "$plan"
  validate_rows
  if [[ "$MAP_KIND" == v2 ]]; then
    check_acceptance_lint
  fi
  check_overlap_all
  check_disabled_lint
  if [[ ${#REFUSES[@]} -gt 0 ]]; then
    print_refuses
    exit 3
  fi
  printf '%s\n' ok
}

cmd_rows() {
  local reexecute=0 lint=0 plan backend status
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reexecute) reexecute=1; shift ;;
      --lint) lint=1; shift ;;
      *) break ;;
    esac
  done
  if [[ $lint -eq 1 ]]; then
    if [[ $reexecute -eq 1 || $# -ne 1 ]]; then
      usage
      exit 2
    fi
    cmd_rows_lint "$1"
    return
  fi
  if [[ $# -lt 2 ]]; then
    usage
    exit 2
  fi
  plan=$1
  backend=$2
  shift 2
  if ! valid_backend "$backend"; then
    usage
    exit 2
  fi
  if [[ ! -f "$plan" ]]; then
    usage
    exit 2
  fi
  if [[ "$backend" != "claude-code" ]] && ! tool_enabled "$backend"; then
    printf '%s\n' "REFUSE: delegate:${backend} is disabled" >&2
    exit 3
  fi
  BACKEND=$backend
  REQ=("$@")
  reset_row_state
  parse_map "$plan"
  if [[ "$MAP_KIND" == none ]]; then
    parse_steps "$plan"
  fi
  parse_done "$plan"
  status=$(execution_status_of "$plan")
  if [[ $reexecute -eq 1 || "$status" == completed ]]; then
    KEEP_DONE=1
  else
    KEEP_DONE=0
  fi
  check_unknown
  if [[ ${#REFUSES[@]} -eq 0 ]]; then
    validate_rows
  fi
  if [[ ${#REFUSES[@]} -eq 0 ]]; then
    local i
    for ((i = 0; i < ROW_N; i++)); do
      consider_row "$i"
    done
  fi
  if [[ ${#REFUSES[@]} -eq 0 ]]; then
    check_selected_review_tools
    check_deps
    check_overlap
  fi
  if [[ ${#REFUSES[@]} -gt 0 ]]; then
    print_refuses
    exit 3
  fi
  if [[ ${#SEL[@]} -eq 0 ]]; then
    if [[ "$BACKEND" == claude-code ]]; then
      emit_json
      return
    fi
    printf '%s\n' "REFUSE: no rows routed to delegate:${BACKEND}" >&2
    exit 3
  fi
  emit_json
}

# --- writers (start / batch / terminal) ---

MODEL_RE='^[A-Za-z0-9][A-Za-z0-9 ._:/()+-]{0,63}$'
OUT_TMP=""

remove_out_tmp() {
  if [[ -n "${OUT_TMP:-}" ]]; then
    rm -f "$OUT_TMP"
    OUT_TMP=""
  fi
}
trap remove_out_tmp EXIT

die_usage() {
  usage
  exit 2
}

require_plan_file() {
  local plan=$1
  if [[ -z "$plan" || ! -f "$plan" ]]; then
    die_usage
  fi
}

require_skill() {
  local id
  case "$1" in
    execute-plan | review) ;;
    execute-via-*)
      id=${1#execute-via-}
      in_list "$id" "$REG_DELEGATES" || die_usage
      ;;
    *) die_usage ;;
  esac
}

is_iso_ts() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

require_iso_ts() {
  if ! is_iso_ts "$1"; then
    die_usage
  fi
}

now_ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

single_line() {
  local s=$1
  s=${s//$'\r'/}
  s=${s//$'\n'/ }
  printf '%s' "$s"
}

yaml_quote() {
  local s=$1
  s=${s//$'\r'/}
  s=${s//$'\n'/ }
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

escape_cell() {
  local s=$1
  s=${s//$'\r'/}
  s=${s//$'\n'/ }
  s=${s//|/\\|}
  printf '%s' "$s"
}

normalize_resolved() {
  local model=$1
  if [[ "$model" =~ $MODEL_RE && "$model" != null && -n "$model" ]]; then
    printf '%s' "$model"
  else
    printf '%s' 'auto(unresolved)'
  fi
}

slug_ok() {
  local s=$1
  [[ -n "$s" && "$s" != null && "$s" =~ $MODEL_RE ]]
}

# A single slug or a comma-separated list of slugs. Empty pieces fail.
model_list_ok() {
  local raw=$1 rest part
  rest=$raw
  [[ -n "$rest" ]] || return 1
  while [[ "$rest" == *","* ]]; do
    part=${rest%%,*}
    rest=${rest#*,}
    part=$(trim_ws "$part")
    slug_ok "$part" || return 1
  done
  part=$(trim_ws "$rest")
  slug_ok "$part"
}

note_blocks_completed() {
  case "$1" in
    "out of step-scope"*) return 0 ;;
    *) return 1 ;;
  esac
}

load_rows_json() {
  local spec=$1
  if [[ -z "$spec" ]]; then
    die_usage
  fi
  if [[ -f "$spec" ]]; then
    ROWS_JSON=$(cat "$spec")
  else
    ROWS_JSON=$spec
  fi
  if ! jq -e 'type == "object" and (.selected | type == "array") and (.skipped | type == "array")' \
    >/dev/null <<<"$ROWS_JSON"; then
    echo "usage: plan-status.sh: rows-json must be a file or a JSON object with selected and skipped" >&2
    exit 2
  fi
  SEL_IDS=()
  SKIP_IDS=()
  SKIP_NOTES=()
  BLOCKED_IDS=""
  local id obj note
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    SEL_IDS+=("$id")
  done < <(jq -r '.selected[]? | .id // empty' <<<"$ROWS_JSON")
  BLOCKED_IDS=$(jq -r '.blocked[]? | .id // empty' <<<"$ROWS_JSON")
  while IFS= read -r obj; do
    [[ -n "$obj" ]] || continue
    id=$(jq -r '.id // empty' <<<"$obj")
    [[ -n "$id" ]] || continue
    note=$(jq -r '.note // ""' <<<"$obj")
    SKIP_IDS+=("$id")
    SKIP_NOTES+=("$note")
  done < <(jq -c '.skipped[]?' <<<"$ROWS_JSON")
}

read_plan_lines() {
  local plan=$1 line
  LINES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    LINES+=("$line")
  done <"$plan"
}

# Frontmatter started_at / runs, plus the existing log's ### Run history.
extract_plan_state() {
  local i j line val title
  local n=${#LINES[@]}
  HAS_FM=0
  FM_CLOSE=-1
  EXEC_S=-1
  EXEC_E=-1
  HAS_STARTED=0
  OLD_STARTED=""
  HAS_COMPLETED=0
  OLD_COMPLETED=""
  RUNS_LINES=()
  LOG_S=-1
  LOG_E=$n
  HIST=()
  if [[ $n -gt 0 && ${LINES[0]} =~ ^---[[:space:]]*$ ]]; then
    HAS_FM=1
    for ((i = 1; i < n; i++)); do
      if [[ ${LINES[$i]} =~ ^---[[:space:]]*$ ]]; then
        FM_CLOSE=$i
        break
      fi
    done
    if [[ $FM_CLOSE -lt 0 ]]; then
      echo "usage: plan-status.sh: unclosed frontmatter" >&2
      exit 2
    fi
    for ((i = 1; i < FM_CLOSE; i++)); do
      if [[ ${LINES[$i]} =~ ^execution:[[:space:]]*(#.*)?$ ]]; then
        EXEC_S=$i
        EXEC_E=$FM_CLOSE
        for ((j = i + 1; j < FM_CLOSE; j++)); do
          if [[ ${LINES[$j]} =~ ^[^[:space:]#] ]]; then
            EXEC_E=$j
            break
          fi
        done
        break
      fi
    done
  fi
  if [[ $EXEC_S -ge 0 ]]; then
    local in_runs=0
    for ((i = EXEC_S + 1; i < EXEC_E; i++)); do
      line=${LINES[$i]}
      if [[ $in_runs -eq 0 && $line =~ ^[[:space:]]+runs: ]]; then
        in_runs=1
      fi
      if [[ $in_runs -eq 1 ]]; then
        RUNS_LINES+=("$line")
        continue
      fi
      if [[ $line =~ ^[[:space:]]+started_at:[[:space:]]*(.*)$ ]]; then
        val=$(unquote_scalar "${BASH_REMATCH[1]}")
        case "$val" in
          "" | null | "~" | "''") ;;
          *)
            HAS_STARTED=1
            OLD_STARTED=$val
            ;;
        esac
      elif [[ $line =~ ^[[:space:]]+completed_at:[[:space:]]*(.*)$ ]]; then
        val=$(unquote_scalar "${BASH_REMATCH[1]}")
        case "$val" in
          "" | null | "~" | "''") ;;
          *)
            HAS_COMPLETED=1
            OLD_COMPLETED=$val
            ;;
        esac
      fi
    done
  fi
  local body_start=0
  if [[ $HAS_FM -eq 1 ]]; then
    body_start=$((FM_CLOSE + 1))
  fi
  for ((i = body_start; i < n; i++)); do
    title=$(h2_title "${LINES[$i]}")
    if [[ "$title" == "Execution log" ]]; then
      LOG_S=$i
      LOG_E=$n
      for ((j = i + 1; j < n; j++)); do
        if is_h2 "${LINES[$j]}"; then
          LOG_E=$j
          break
        fi
      done
      break
    fi
  done
  if [[ $LOG_S -ge 0 ]]; then
    local seen=0
    for ((i = LOG_S; i < LOG_E; i++)); do
      case ${LINES[$i]} in
        "### Run"*) seen=1 ;;
      esac
      if [[ $seen -eq 1 ]]; then
        HIST+=("${LINES[$i]}")
      fi
    done
    trim_hist
  fi
}

trim_hist() {
  local i last_non=-1
  local -a kept=()
  if [[ ${#HIST[@]} -eq 0 ]]; then
    return
  fi
  for ((i = 0; i < ${#HIST[@]}; i++)); do
    if [[ -n ${HIST[$i]} ]]; then
      last_non=$i
    fi
  done
  if [[ $last_non -lt 0 ]]; then
    HIST=()
    return
  fi
  for ((i = 0; i <= last_non; i++)); do
    kept+=("${HIST[$i]}")
  done
  HIST=("${kept[@]}")
}

load_map_ids() {
  local plan=$1 i
  REFUSES=()
  ROW_N=0
  ROW_ID=()
  ROW_TIER=()
  ROW_RUNNER=()
  ROW_WAVE=()
  ROW_DEP=()
  ROW_FILES=()
  ROW_FILES_RAW=()
  ROW_ACC=()
  ROW_MODEL=()
  ROW_REVIEW=()
  ROW_UNSCHED=()
  ROW_BAD=()
  MAP_IDS=()
  parse_map "$plan"
  if [[ "$MAP_KIND" == none ]]; then
    parse_steps "$plan"
  fi
  for ((i = 0; i < ROW_N; i++)); do
    MAP_IDS+=("${ROW_ID[$i]}")
  done
}

parse_log_state() {
  local file=$1 line title in=0 intable=0
  local id_col=-1 st_col=-1 note_col=-1 id st note
  OLD_N=0
  OLD_ID=()
  OLD_ST=()
  OLD_NOTE=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ $in -eq 0 ]]; then
      if is_h2 "$line"; then
        title=$(h2_title "$line")
        if [[ "$title" == "Execution log" ]]; then
          in=1
        fi
      fi
      continue
    fi
    if is_h2 "$line"; then
      break
    fi
    if [[ $intable -eq 0 ]]; then
      case "$line" in
        '|'*) ;;
        *) continue ;;
      esac
      if is_separator_line "$line"; then
        continue
      fi
      split_row "$line"
      id_col=$(header_index "id")
      st_col=$(header_index "status")
      note_col=$(header_index "notes")
      intable=1
      continue
    fi
    case "$line" in
      '|'*) ;;
      *) break ;;
    esac
    if is_separator_line "$line"; then
      continue
    fi
    split_row "$line"
    if [[ $id_col -lt 0 || $st_col -lt 0 ]]; then
      continue
    fi
    if [[ $id_col -ge ${#CELLS[@]} || $st_col -ge ${#CELLS[@]} ]]; then
      continue
    fi
    id=$(trim_ws "${CELLS[$id_col]}")
    st=$(trim_ws "${CELLS[$st_col]}")
    note=""
    if [[ $note_col -ge 0 && $note_col -lt ${#CELLS[@]} ]]; then
      note=$(trim_ws "${CELLS[$note_col]}")
    fi
    if [[ -z "$id" ]]; then
      continue
    fi
    OLD_ID[$OLD_N]=$id
    OLD_ST[$OLD_N]=$st
    OLD_NOTE[$OLD_N]=$note
    OLD_N=$((OLD_N + 1))
  done <"$file"
}

old_status_of() {
  local id=$1 i
  for ((i = 0; i < OLD_N; i++)); do
    if [[ ${OLD_ID[$i]} == "$id" ]]; then
      printf '%s' "${OLD_ST[$i]}"
      return
    fi
  done
  printf ''
}

old_note_of() {
  local id=$1 i
  for ((i = 0; i < OLD_N; i++)); do
    if [[ ${OLD_ID[$i]} == "$id" ]]; then
      printf '%s' "${OLD_NOTE[$i]}"
      return
    fi
  done
  printf ''
}

map_has() {
  local id=$1 i
  for ((i = 0; i < ${#MAP_IDS[@]}; i++)); do
    if [[ ${MAP_IDS[$i]} == "$id" ]]; then
      return 0
    fi
  done
  return 1
}

require_known() {
  local id
  for id in "$@"; do
    if ! map_has "$id"; then
      echo "usage: plan-status.sh: unknown ID $id" >&2
      exit 2
    fi
  done
}

unquote_scalar() {
  local val
  val=$(trim_ws "$1")
  val=${val%%[[:space:]]#*}
  val=$(trim_ws "$val")
  if [[ $val == \"*\" ]]; then
    val=${val#\"}
    val=${val%\"}
  elif [[ $val == \'*\' ]]; then
    val=${val#\'}
    val=${val%\'}
  fi
  printf '%s' "$val"
}

init_new_from_old() {
  local i oldst oldnote
  NEW_ST=()
  NEW_NOTE=()
  for ((i = 0; i < ${#MAP_IDS[@]}; i++)); do
    oldst=$(old_status_of "${MAP_IDS[$i]}")
    oldnote=$(old_note_of "${MAP_IDS[$i]}")
    if [[ -z "$oldst" ]]; then
      oldst=pending
      oldnote=""
    fi
    NEW_ST+=("$oldst")
    NEW_NOTE+=("$oldnote")
  done
}

row_index() {
  local id=$1 i
  for ((i = 0; i < ${#MAP_IDS[@]}; i++)); do
    if [[ ${MAP_IDS[$i]} == "$id" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

set_row_status() {
  local id=$1 st=$2 clear_note=$3 idx
  idx=$(row_index "$id") || return 1
  NEW_ST[$idx]=$st
  if [[ "$clear_note" -eq 1 ]]; then
    NEW_NOTE[$idx]=""
  fi
}

id_in_sel() {
  local id=$1 s
  if [[ ${#SEL_IDS[@]} -eq 0 ]]; then
    return 1
  fi
  for s in "${SEL_IDS[@]}"; do
    if [[ "$s" == "$id" ]]; then
      return 0
    fi
  done
  return 1
}

skip_note_for() {
  local id=$1 i
  for ((i = 0; i < ${#SKIP_IDS[@]}; i++)); do
    if [[ ${SKIP_IDS[$i]} == "$id" ]]; then
      printf '%s' "${SKIP_NOTES[$i]}"
      return 0
    fi
  done
  return 1
}

recalc_progress() {
  local i
  STEPS_TOTAL=${#MAP_IDS[@]}
  STEPS_DONE=0
  for ((i = 0; i < STEPS_TOTAL; i++)); do
    case ${NEW_ST[$i]} in
      done | skipped) STEPS_DONE=$((STEPS_DONE + 1)) ;;
    esac
  done
  if [[ "$STEPS_TOTAL" -eq 0 ]]; then
    PROG=0
  else
    PROG=$(( (100 * STEPS_DONE + STEPS_TOTAL / 2) / STEPS_TOTAL ))
  fi
}

rows_satisfy_completed() {
  local i
  if [[ "$STEPS_TOTAL" -eq 0 ]]; then
    return 1
  fi
  for ((i = 0; i < STEPS_TOTAL; i++)); do
    case ${NEW_ST[$i]} in
      done) ;;
      skipped)
        if note_blocks_completed "${NEW_NOTE[$i]}"; then
          return 1
        fi
        ;;
      *) return 1 ;;
    esac
  done
  return 0
}

selected_any_done() {
  local s idx
  if [[ ${#SEL_IDS[@]} -eq 0 ]]; then
    return 1
  fi
  for s in "${SEL_IDS[@]}"; do
    idx=$(row_index "$s") || continue
    if [[ ${NEW_ST[$idx]} == done ]]; then
      return 0
    fi
  done
  return 1
}

apply_start_rows() {
  local reexecute=$1 i id note oldst
  for ((i = 0; i < ${#MAP_IDS[@]}; i++)); do
    id=${MAP_IDS[$i]}
    oldst=${NEW_ST[$i]}
    if id_in_sel "$id"; then
      if [[ "$reexecute" -eq 0 && "$oldst" == done ]]; then
        continue
      fi
      NEW_ST[$i]=pending
      NEW_NOTE[$i]=""
      continue
    fi
    if note=$(skip_note_for "$id"); then
      if [[ "$oldst" == done ]]; then
        continue
      fi
      NEW_ST[$i]=skipped
      NEW_NOTE[$i]=$note
    fi
  done
}

apply_done_ids() {
  local id
  if [[ $# -eq 0 ]]; then
    return
  fi
  for id in "$@"; do
    set_row_status "$id" done 0
  done
}

apply_failed_ids() {
  local id
  if [[ $# -eq 0 ]]; then
    return
  fi
  for id in "$@"; do
    set_row_status "$id" failed 0
  done
}

mark_selected_done() {
  local s idx
  if [[ ${#SEL_IDS[@]} -eq 0 ]]; then
    return
  fi
  for s in "${SEL_IDS[@]}"; do
    idx=$(row_index "$s") || continue
    case $'\n'"$BLOCKED_IDS"$'\n' in
      *$'\n'"$s"$'\n'*) continue ;;
    esac
    if [[ ${NEW_ST[$idx]} != skipped ]]; then
      set_row_status "$s" done 0
    fi
  done
}

mark_selected_failed_unless_done() {
  local s idx
  if [[ ${#SEL_IDS[@]} -eq 0 ]]; then
    return
  fi
  for s in "${SEL_IDS[@]}"; do
    idx=$(row_index "$s") || continue
    case $'\n'"$BLOCKED_IDS"$'\n' in
      *$'\n'"$s"$'\n'*) continue ;;
    esac
    if [[ ${NEW_ST[$idx]} != done && ${NEW_ST[$idx]} != skipped ]]; then
      NEW_ST[$idx]=failed
    fi
  done
}

emit_line() {
  printf '%s\n' "$1" >>"$OUT_TMP"
}

emit_exec_block() {
  local status=$1 pct=$2 done_n=$3 total=$4 skill=$5 started=$6 updated=$7 completed=$8 append_run=$9
  emit_line "execution:"
  emit_line "  status: $status"
  emit_line "  progress_pct: $pct"
  emit_line "  steps_done: $done_n"
  emit_line "  steps_total: $total"
  emit_line "  last_skill: $skill"
  emit_line "  started_at: $(yaml_quote "$started")"
  emit_line "  updated_at: $(yaml_quote "$updated")"
  if [[ -n "$completed" ]]; then
    emit_line "  completed_at: $(yaml_quote "$completed")"
  else
    emit_line "  completed_at: null"
  fi
  local i have_runs=0 placeholder=0
  if [[ ${#RUNS_LINES[@]} -gt 0 ]]; then
    have_runs=1
    if [[ ${#RUNS_LINES[@]} -eq 1 ]]; then
      case ${RUNS_LINES[0]} in
        "  runs:" | "  runs: []" | "  runs: null") placeholder=1 ;;
      esac
    fi
  fi
  if [[ "$append_run" -ne 1 ]]; then
    if [[ $have_runs -eq 1 ]]; then
      for ((i = 0; i < ${#RUNS_LINES[@]}; i++)); do
        emit_line "${RUNS_LINES[$i]}"
      done
    fi
    return
  fi
  if [[ $have_runs -eq 0 || $placeholder -eq 1 ]]; then
    emit_line "  runs:"
  else
    for ((i = 0; i < ${#RUNS_LINES[@]}; i++)); do
      emit_line "${RUNS_LINES[$i]}"
    done
  fi
  emit_line "    - skill: $RUN_SKILL"
  emit_line "      backend: $RUN_BACKEND"
  emit_line "      model_requested: $(yaml_quote "$RUN_REQUESTED")"
  emit_line "      model_resolved: $(yaml_quote "$RUN_RESOLVED")"
  emit_line "      effort: $(yaml_quote "$RUN_EFFORT")"
  emit_line "      started_at: $(yaml_quote "$RUN_STARTED")"
  emit_line "      ended_at: $(yaml_quote "$updated")"
  emit_line "      tokens_in: $RUN_TOKENS_IN"
  emit_line "      tokens_cached: $RUN_TOKENS_CACHED"
  emit_line "      tokens_out: $RUN_TOKENS_OUT"
  emit_line "      review_findings: $RUN_FINDINGS"
  emit_line "      fix_loops: $RUN_LOOPS"
  if [[ "$RUN_FALLBACK" == null ]]; then
    emit_line "      fallback: null"
  else
    emit_line "      fallback: $(yaml_quote "$RUN_FALLBACK")"
  fi
  emit_line "      outcome: $RUN_OUTCOME"
}

emit_run_md() {
  local fb=$RUN_FALLBACK
  if [[ "$fb" == null ]]; then
    fb=none
  fi
  emit_line "### Run ${NOW_TS} (${RUN_SKILL})"
  emit_line "- Outcome: ${RUN_OUTCOME}"
  emit_line "- Run: backend=${RUN_BACKEND} model=${RUN_REQUESTED}→${RUN_RESOLVED} effort=${RUN_EFFORT} findings=${RUN_FINDINGS} fix_loops=${RUN_LOOPS} fallback=${fb} tokens_in=${RUN_TOKENS_IN} tokens_cached=${RUN_TOKENS_CACHED} tokens_out=${RUN_TOKENS_OUT} (${RUN_STARTED}→${NOW_TS})"
  if [[ -n "$RUN_NOTES" ]]; then
    emit_line "- Notes: ${RUN_NOTES}"
  else
    emit_line "- Notes:"
  fi
}

emit_review_md() {
  emit_line "### Run ${NOW_TS} (review)"
  emit_line "- Outcome: ${RUN_OUTCOME}"
  emit_line "- Run: runner=${RUN_RUNNER} findings=${RUN_FINDINGS}"
  if [[ -n "$RUN_NOTES" ]]; then
    emit_line "- Notes: ${RUN_NOTES}"
  else
    emit_line "- Notes:"
  fi
}

emit_log_section() {
  local i note append_run=$1
  emit_line "## Execution log"
  emit_line ""
  emit_line "- **Overall:** ${NEW_STATUS} — ${PROG}% (${STEPS_DONE}/${STEPS_TOTAL})"
  emit_line "- **Last skill:** ${SKILL}"
  emit_line "- **Updated:** ${NOW_TS}"
  emit_line ""
  emit_line "| ID | Status | Notes |"
  emit_line "| --- | --- | --- |"
  for ((i = 0; i < ${#MAP_IDS[@]}; i++)); do
    note=$(escape_cell "${NEW_NOTE[$i]}")
    if [[ -n "$note" ]]; then
      printf '| %s | %s | %s |\n' "${MAP_IDS[$i]}" "${NEW_ST[$i]}" "$note" >>"$OUT_TMP"
    else
      printf '| %s | %s | |\n' "${MAP_IDS[$i]}" "${NEW_ST[$i]}" >>"$OUT_TMP"
    fi
  done
  if [[ ${#HIST[@]} -gt 0 ]]; then
    emit_line ""
    for ((i = 0; i < ${#HIST[@]}; i++)); do
      emit_line "${HIST[$i]}"
    done
  fi
  if [[ "$append_run" -eq 1 ]]; then
    emit_line ""
    emit_run_md
  elif [[ "$append_run" -eq 2 ]]; then
    emit_line ""
    emit_review_md
  fi
  emit_line ""
}

# mktemp is 0600. Copy the plan's mode onto the temp before mv, or a tracked
# plan flips 0644 → 0600 (core.filemode). 0600 is kept only when the source is.
apply_source_mode() {
  local src=$1 dest=$2 mode=""
  if mode=$(stat -c %a "$src" 2>/dev/null); then
    :
  elif mode=$(stat -f %OLp "$src" 2>/dev/null); then
    :
  else
    echo "plan-status.sh: cannot read mode of $src" >&2
    exit 2
  fi
  case "$mode" in
    [0-7][0-7][0-7] | [0-7][0-7][0-7][0-7]) ;;
    *)
      echo "plan-status.sh: cannot read mode of $src" >&2
      exit 2
      ;;
  esac
  chmod "$mode" "$dest"
}

# One temp file, then mv. Non-execution frontmatter lines are copied unchanged.
commit_write() {
  local plan=$1 status=$2 skill=$3 now=$4 started=$5 completed=$6 append_run=$7
  local i k title anchor insert_k
  local -a keep=()
  NEW_STATUS=$status
  SKILL=$skill
  NOW_TS=$now
  remove_out_tmp
  OUT_TMP=$(mktemp "$(dirname "$plan")/.plan-status.XXXXXX")
  local body_start=0
  if [[ $HAS_FM -eq 1 ]]; then
    local end_pre=$FM_CLOSE
    if [[ $EXEC_S -ge 0 ]]; then
      end_pre=$EXEC_S
    fi
    for ((i = 0; i < end_pre; i++)); do
      emit_line "${LINES[$i]}"
    done
    emit_exec_block "$status" "$PROG" "$STEPS_DONE" "$STEPS_TOTAL" "$skill" "$started" "$now" "$completed" "$append_run"
    local rest=$FM_CLOSE
    if [[ $EXEC_S -ge 0 ]]; then
      rest=$EXEC_E
    fi
    for ((i = rest; i <= FM_CLOSE; i++)); do
      emit_line "${LINES[$i]}"
    done
    body_start=$((FM_CLOSE + 1))
  else
    emit_line "---"
    emit_exec_block "$status" "$PROG" "$STEPS_DONE" "$STEPS_TOTAL" "$skill" "$started" "$now" "$completed" "$append_run"
    emit_line "---"
    body_start=0
  fi
  for ((i = body_start; i < ${#LINES[@]}; i++)); do
    if [[ $LOG_S -ge 0 && $i -ge $LOG_S && $i -lt $LOG_E ]]; then
      continue
    fi
    keep+=("$i")
  done
  anchor=-1
  for ((k = 0; k < ${#keep[@]}; k++)); do
    title=$(h2_title "${LINES[${keep[$k]}]}")
    if [[ "$title" == "Execution map" ]]; then
      anchor=$k
      break
    fi
  done
  if [[ $anchor -lt 0 ]]; then
    for ((k = 0; k < ${#keep[@]}; k++)); do
      title=$(h2_title "${LINES[${keep[$k]}]}")
      if [[ "$title" == "Implementation steps" ]]; then
        anchor=$k
        break
      fi
    done
  fi
  insert_k=${#keep[@]}
  if [[ $anchor -ge 0 ]]; then
    for ((k = anchor + 1; k < ${#keep[@]}; k++)); do
      if is_h2 "${LINES[${keep[$k]}]}"; then
        insert_k=$k
        break
      fi
    done
  fi
  for ((k = 0; k < ${#keep[@]}; k++)); do
    if [[ $k -eq $insert_k ]]; then
      emit_log_section "$append_run"
    fi
    emit_line "${LINES[${keep[$k]}]}"
  done
  if [[ $insert_k -eq ${#keep[@]} ]]; then
    emit_log_section "$append_run"
  fi
  apply_source_mode "$plan" "$OUT_TMP"
  mv "$OUT_TMP" "$plan"
  OUT_TMP=""
}

prepare_write() {
  local plan=$1
  read_plan_lines "$plan"
  extract_plan_state
  load_map_ids "$plan"
  parse_log_state "$plan"
  init_new_from_old
}

check_sel_and_skip_known() {
  if [[ ${#SEL_IDS[@]} -gt 0 ]]; then
    require_known "${SEL_IDS[@]}"
  fi
  if [[ ${#SKIP_IDS[@]} -gt 0 ]]; then
    require_known "${SKIP_IDS[@]}"
  fi
}

started_or_now() {
  local now=$1
  if [[ $HAS_STARTED -eq 1 ]]; then
    printf '%s' "$OLD_STARTED"
  else
    printf '%s' "$now"
  fi
}

cmd_start() {
  local plan skill rows now="" reexecute=0 started
  if [[ $# -lt 3 ]]; then
    die_usage
  fi
  plan=$1
  skill=$2
  rows=$3
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reexecute) reexecute=1; shift ;;
      --now)
        [[ $# -ge 2 ]] || die_usage
        now=$2
        shift 2
        ;;
      *) die_usage ;;
    esac
  done
  require_plan_file "$plan"
  require_skill "$skill"
  if [[ -n "$now" ]]; then
    require_iso_ts "$now"
  else
    now=$(now_ts)
  fi
  load_rows_json "$rows"
  local status
  status=$(execution_status_of "$plan")
  if [[ "$reexecute" -eq 0 && "$status" == completed ]]; then
    echo "plan already completed; confirm re-execute" >&2
    exit 4
  fi
  prepare_write "$plan"
  check_sel_and_skip_known
  apply_start_rows "$reexecute"
  recalc_progress
  started=$(started_or_now "$now")
  commit_write "$plan" "in-progress" "$skill" "$now" "$started" "" 0
}

cmd_batch() {
  local plan skill now="" sid snote i idx
  local -a done_ids=() failed_ids=() skip_ids=() skip_notes=()
  if [[ $# -lt 2 ]]; then
    die_usage
  fi
  plan=$1
  skill=$2
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --now)
        [[ $# -ge 2 ]] || die_usage
        now=$2
        shift 2
        ;;
      --done)
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          done_ids+=("$1")
          shift
        done
        ;;
      --failed)
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          failed_ids+=("$1")
          shift
        done
        ;;
      --skipped)
        [[ $# -ge 4 ]] || die_usage
        shift
        sid=$1
        shift
        [[ "${1:-}" == "--note" ]] || die_usage
        shift
        snote=$1
        shift
        skip_ids+=("$sid")
        skip_notes+=("$snote")
        ;;
      *) die_usage ;;
    esac
  done
  require_plan_file "$plan"
  require_skill "$skill"
  if [[ -n "$now" ]]; then
    require_iso_ts "$now"
  else
    now=$(now_ts)
  fi
  if [[ ${#done_ids[@]} -eq 0 && ${#failed_ids[@]} -eq 0 && ${#skip_ids[@]} -eq 0 ]]; then
    die_usage
  fi
  prepare_write "$plan"
  if [[ ${#done_ids[@]} -gt 0 ]]; then
    require_known "${done_ids[@]}"
  fi
  if [[ ${#failed_ids[@]} -gt 0 ]]; then
    require_known "${failed_ids[@]}"
  fi
  if [[ ${#skip_ids[@]} -gt 0 ]]; then
    require_known "${skip_ids[@]}"
  fi
  if [[ ${#failed_ids[@]} -gt 0 ]]; then
    apply_failed_ids "${failed_ids[@]}"
  fi
  if [[ ${#done_ids[@]} -gt 0 ]]; then
    apply_done_ids "${done_ids[@]}"
  fi
  for ((i = 0; i < ${#skip_ids[@]}; i++)); do
    idx=$(row_index "${skip_ids[$i]}")
    if [[ ${NEW_ST[$idx]} == done ]]; then
      continue
    fi
    NEW_ST[$idx]=skipped
    NEW_NOTE[$idx]=${skip_notes[$i]}
  done
  recalc_progress
  local status started
  status=$(execution_status_of "$plan")
  case "$status" in
    in-progress | partial | failed | aborted | completed) ;;
    *) status=in-progress ;;
  esac
  started=$(started_or_now "$now")
  local completed=""
  if [[ "$status" == completed ]]; then
    if [[ $HAS_COMPLETED -eq 1 ]]; then
      completed=$OLD_COMPLETED
    else
      completed=$now
    fi
  fi
  commit_write "$plan" "$status" "$skill" "$now" "$started" "$completed" 0
}

require_count() {
  [[ "$1" =~ ^[0-9]+$ ]] || die_usage
}

cmd_terminal() {
  local plan skill rows now="" outcome="" backend="" requested="" resolved_raw="" effort=""
  local started_run="" findings="" loops="" fallback="" notes="" usage_json=""
  local tokens_in=null tokens_cached=null tokens_out=null
  local -a done_ids=()
  local saw_fallback=0 saw_outcome=0 saw_backend=0 saw_requested=0 saw_resolved=0
  local saw_effort=0 saw_started=0 saw_findings=0 saw_loops=0 deferred=0
  if [[ $# -lt 3 ]]; then
    die_usage
  fi
  plan=$1
  skill=$2
  rows=$3
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --now)
        [[ $# -ge 2 ]] || die_usage
        now=$2
        shift 2
        ;;
      --outcome)
        [[ $# -ge 2 ]] || die_usage
        outcome=$2
        saw_outcome=1
        shift 2
        ;;
      --backend)
        [[ $# -ge 2 ]] || die_usage
        backend=$2
        saw_backend=1
        shift 2
        ;;
      --model-requested)
        [[ $# -ge 2 ]] || die_usage
        requested=$2
        saw_requested=1
        shift 2
        ;;
      --model-resolved)
        [[ $# -ge 2 ]] || die_usage
        resolved_raw=$2
        saw_resolved=1
        shift 2
        ;;
      --effort)
        [[ $# -ge 2 ]] || die_usage
        effort=$2
        saw_effort=1
        shift 2
        ;;
      --started)
        [[ $# -ge 2 ]] || die_usage
        started_run=$2
        saw_started=1
        shift 2
        ;;
      --findings)
        [[ $# -ge 2 ]] || die_usage
        findings=$2
        saw_findings=1
        shift 2
        ;;
      --fix-loops)
        [[ $# -ge 2 ]] || die_usage
        loops=$2
        saw_loops=1
        shift 2
        ;;
      --fallback)
        [[ $# -ge 2 ]] || die_usage
        fallback=$2
        saw_fallback=1
        shift 2
        ;;
      --usage)
        [[ $# -ge 2 ]] || die_usage
        usage_json=$2
        shift 2
        ;;
      --notes)
        [[ $# -ge 2 ]] || die_usage
        notes=$2
        shift 2
        ;;
      --done)
        shift
        while [[ $# -gt 0 && "$1" != --* ]]; do
          done_ids+=("$1")
          shift
        done
        ;;
      --deferred-review)
        deferred=1
        shift
        ;;
      *) die_usage ;;
    esac
  done
  require_plan_file "$plan"
  require_skill "$skill"
  if [[ $saw_outcome -eq 0 || $saw_backend -eq 0 || $saw_requested -eq 0 || $saw_resolved -eq 0 \
    || $saw_effort -eq 0 || $saw_started -eq 0 || $saw_findings -eq 0 || $saw_loops -eq 0 \
    || $saw_fallback -eq 0 ]]; then
    die_usage
  fi
  case "$outcome" in
    pass | fail | abort) ;;
    *) die_usage ;;
  esac
  if ! valid_backend "$backend"; then
    die_usage
  fi
  require_iso_ts "$started_run"
  require_count "$findings"
  require_count "$loops"
  if [[ -n "$usage_json" ]]; then
    if ! jq -e '
      type == "object"
      and has("tokens_in") and has("tokens_cached") and has("tokens_out")
      and ((.tokens_in == null) or (.tokens_in | type == "number" and . >= 0 and . == floor))
      and ((.tokens_cached == null) or (.tokens_cached | type == "number" and . >= 0 and . == floor))
      and ((.tokens_out == null) or (.tokens_out | type == "number" and . >= 0 and . == floor))
    ' <<<"$usage_json" >/dev/null 2>&1; then
      die_usage
    fi
    tokens_in=$(jq -r '.tokens_in' <<<"$usage_json")
    tokens_cached=$(jq -r '.tokens_cached' <<<"$usage_json")
    tokens_out=$(jq -r '.tokens_out' <<<"$usage_json")
  fi
  if [[ -n "$now" ]]; then
    require_iso_ts "$now"
  else
    now=$(now_ts)
  fi
  load_rows_json "$rows"
  prepare_write "$plan"
  check_sel_and_skip_known
  if [[ ${#done_ids[@]} -gt 0 ]]; then
    require_known "${done_ids[@]}"
    apply_done_ids "${done_ids[@]}"
  fi
  case "$outcome" in
    pass)
      if [[ ${#done_ids[@]} -eq 0 && $deferred -eq 0 ]]; then
        mark_selected_done
      fi
      ;;
    fail)
      mark_selected_failed_unless_done
      ;;
  esac
  recalc_progress
  local status completed=""
  case "$outcome" in
    pass)
      if [[ $deferred -eq 1 ]]; then
        status=partial
      elif rows_satisfy_completed; then
        status=completed
      else
        status=partial
      fi
      ;;
    fail)
      status=failed
      ;;
    abort)
      if selected_any_done; then
        status=partial
      else
        status=aborted
      fi
      ;;
  esac
  if [[ "$status" == completed ]]; then
    completed=$now
  fi
  local started
  started=$(started_or_now "$started_run")
  # When the plan has never recorded started_at, this run's --started is that stamp.
  if [[ $HAS_STARTED -eq 0 ]]; then
    started=$started_run
  fi
  RUN_SKILL=$skill
  RUN_BACKEND=$backend
  if [[ "$backend" == claude-code ]]; then
    # `none` = no implementer Task ran (delegate stop, early abort, session-only rows).
    [[ "$requested" == none ]] || model_list_ok "$requested" || die_usage
    [[ "$resolved_raw" == none ]] || model_list_ok "$resolved_raw" || die_usage
    RUN_REQUESTED=$(single_line "$requested")
    RUN_RESOLVED=$(single_line "$resolved_raw")
  else
    RUN_REQUESTED=$(single_line "$requested")
    RUN_RESOLVED=$(normalize_resolved "$resolved_raw")
  fi
  RUN_EFFORT=$(single_line "$effort")
  RUN_STARTED=$started_run
  RUN_FINDINGS=$findings
  RUN_LOOPS=$loops
  RUN_FALLBACK=$(single_line "$fallback")
  RUN_TOKENS_IN=$tokens_in
  RUN_TOKENS_CACHED=$tokens_cached
  RUN_TOKENS_OUT=$tokens_out
  RUN_OUTCOME=$status
  RUN_NOTES=$(single_line "$notes")
  commit_write "$plan" "$status" "$skill" "$now" "$started" "$completed" 1
}

review_refuse_reason() {
  local idx=$1 tier runner review files
  tier=${ROW_TIER[$idx]}
  runner=${ROW_RUNNER[$idx]}
  review=${ROW_REVIEW[$idx]}
  files=${ROW_FILES_RAW[$idx]-}
  if [[ "$tier" != top ]]; then
    printf 'Tier is not top'
    return 1
  fi
  if [[ "$runner" != session ]]; then
    printf 'Runner is not session'
    return 1
  fi
  if ! is_blank_dash "$files"; then
    printf 'Files is not —'
    return 1
  fi
  case "$review" in
    top@*) ;;
    *)
      printf 'Review is not top@*'
      return 1
      ;;
  esac
  return 0
}

cmd_review() {
  local plan id="" now="" outcome="" runner="" findings="" notes=""
  local saw_outcome=0 saw_runner=0 saw_findings=0 saw_notes=0
  local idx reason status started completed row_note
  if [[ $# -lt 1 ]]; then
    die_usage
  fi
  plan=$1
  shift
  if [[ $# -gt 0 && "$1" != --* ]]; then
    id=$1
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --outcome)
        [[ $# -ge 2 ]] || die_usage
        outcome=$2
        saw_outcome=1
        shift 2
        ;;
      --runner)
        [[ $# -ge 2 ]] || die_usage
        runner=$2
        saw_runner=1
        shift 2
        ;;
      --findings)
        [[ $# -ge 2 ]] || die_usage
        findings=$2
        saw_findings=1
        shift 2
        ;;
      --notes)
        [[ $# -ge 2 ]] || die_usage
        notes=$2
        saw_notes=1
        shift 2
        ;;
      --now)
        [[ $# -ge 2 ]] || die_usage
        now=$2
        shift 2
        ;;
      *) die_usage ;;
    esac
  done
  require_plan_file "$plan"
  require_skill review
  if [[ $saw_outcome -eq 0 || $saw_runner -eq 0 || $saw_findings -eq 0 ]]; then
    die_usage
  fi
  case "$outcome" in
    pass | fail) ;;
    *) die_usage ;;
  esac
  if [[ ! "$runner" =~ ^top@[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
    die_usage
  fi
  require_count "$findings"
  if [[ -n "$now" ]]; then
    require_iso_ts "$now"
  else
    now=$(now_ts)
  fi
  if [[ "$outcome" == pass ]]; then
    row_note="review=${runner} clean"
  else
    row_note="review=${runner} findings=${findings}"
  fi
  if [[ $saw_notes -eq 0 ]]; then
    notes=$row_note
  fi
  prepare_write "$plan"
  if [[ -n "$id" ]]; then
    if ! idx=$(row_index "$id"); then
      printf 'REFUSE: %s: unknown ID\n' "$id" >&2
      exit 3
    fi
    if ! reason=$(review_refuse_reason "$idx"); then
      printf 'REFUSE: %s: %s\n' "$id" "$reason" >&2
      exit 3
    fi
    if [[ "$outcome" == pass ]]; then
      NEW_ST[$idx]=done
    else
      NEW_ST[$idx]=failed
    fi
    NEW_NOTE[$idx]=$row_note
  fi
  recalc_progress
  if [[ "$outcome" == pass ]] && rows_satisfy_completed; then
    status=completed
  else
    status=partial
  fi
  if [[ "$status" == completed ]]; then
    completed=$now
  else
    completed=""
  fi
  started=$(started_or_now "$now")
  RUN_OUTCOME=$status
  RUN_RUNNER=$runner
  RUN_FINDINGS=$findings
  RUN_NOTES=$(single_line "$notes")
  commit_write "$plan" "$status" review "$now" "$started" "$completed" 2
}

# Replace or insert top-level frontmatter keys. Never creates or changes created_at.
# Other lines, including the execution: block, are copied verbatim.
upsert_top_keys() {
  local plan=$1
  shift
  local tmp spec
  tmp=$(mktemp "$(dirname "$plan")/.plan-status.XXXXXX")
  spec=$(mktemp "${TMPDIR:-/tmp}/plan-status-keys.XXXXXX")
  while [[ $# -ge 2 ]]; do
    printf '%s\t%s\n' "$1" "$2" >>"$spec"
    shift 2
  done
  awk -F '\t' '
    BEGIN { n = 0 }
    NR == FNR { key[n] = $1; val[n] = $2; n++; next }
    FNR == 1 && $0 !~ /^---[[:space:]]*$/ {
      print "---"
      for (i = 0; i < n; i++) printf "%s: \"%s\"\n", key[i], val[i]
      print "---"
      print
      next
    }
    FNR == 1 { fm = 1; print; next }
    fm == 1 && $0 ~ /^execution:[[:space:]]*$/ {
      for (i = 0; i < n; i++) if (!(key[i] in done)) printf "%s: \"%s\"\n", key[i], val[i]
      for (i = 0; i < n; i++) done[key[i]] = 1
      print
      next
    }
    fm == 1 && $0 ~ /^---[[:space:]]*$/ {
      for (i = 0; i < n; i++) if (!(key[i] in done)) printf "%s: \"%s\"\n", key[i], val[i]
      fm = 2
      print
      next
    }
    fm == 1 {
      replaced = 0
      for (i = 0; i < n; i++) {
        if (index($0, key[i] ":") == 1) {
          printf "%s: \"%s\"\n", key[i], val[i]
          done[key[i]] = 1
          replaced = 1
          break
        }
      }
      if (!replaced) print
      next
    }
    { print }
  ' "$spec" "$plan" >"$tmp"
  rm -f "$spec"
  apply_source_mode "$plan" "$tmp"
  mv "$tmp" "$plan"
}

take_now() {
  local now=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --now)
        [[ $# -ge 2 ]] || die_usage
        now=$2
        shift 2
        ;;
      *) die_usage ;;
    esac
  done
  if [[ -n "$now" ]]; then
    require_iso_ts "$now"
  else
    now=$(now_ts)
  fi
  printf '%s' "$now"
}

cmd_stamp() {
  local plan now bytes sha
  [[ $# -ge 1 ]] || die_usage
  plan=$1
  shift
  require_plan_file "$plan"
  now=$(take_now "$@")
  load_lock_fns
  bytes=$(plan_body "$plan" | wc -c | tr -d '[:space:]')
  sha=$(plan_sha "$plan")
  sha=$(lower_ascii "$sha")
  sha=${sha//[[:space:]]/}
  upsert_top_keys "$plan" plan_sha "$sha" approved_at "$now"
  printf '%s\n' "$bytes"
  if [[ "$bytes" -gt 15000 ]]; then
    printf 'WARN: plan body is %s bytes (over 15000)\n' "$bytes" >&2
  fi
}

local_to_utc() {
  local spec=$1 epoch
  # GNU date: parse the wall time in the local zone, then print UTC.
  # `date -u -d` would treat the string as already UTC.
  if epoch=$(date -d "$spec" +%s 2>/dev/null); then
    date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ
    return
  fi
  epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$spec" "+%s")
  date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
}

recency_ts() {
  local f=$1 base created yy year
  base=$(basename "$f")
  created=$(frontmatter_top_key "$f" created_at)
  if [[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    printf '%s' "$created"
    return
  fi
  if [[ "$base" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})- ]]; then
    local_to_utc "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} 00:00:00"
    return
  fi
  if [[ "$base" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})- ]]; then
    yy=$((10#${BASH_REMATCH[1]}))
    year=$((2000 + yy))
    local_to_utc "$(printf '%04d-%s-%s %s:%s:00' "$year" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}")"
    return
  fi
  date -u -r "$f" +%Y-%m-%dT%H:%M:%SZ
}

cmd_recent() {
  local dir=${1:-} f base ts best_ts="" best_path="" tie=0
  [[ -n "$dir" && -d "$dir" ]] || die_usage
  shopt -s nullglob
  for f in "$dir"/*.md; do
    base=$(basename "$f")
    case "$base" in
      *.notes.md) continue ;;
    esac
    [[ -f "$f" ]] || continue
    ts=$(recency_ts "$f")
    if [[ -z "$best_ts" || "$ts" > "$best_ts" ]]; then
      best_ts=$ts
      best_path=$f
      tie=0
    elif [[ "$ts" == "$best_ts" ]]; then
      tie=1
    fi
  done
  shopt -u nullglob
  if [[ -z "$best_path" ]]; then
    echo "usage: plan-status.sh: no plans in $dir" >&2
    exit 2
  fi
  if [[ $tie -eq 1 ]]; then
    echo "tie" >&2
    exit 3
  fi
  printf '%s\n' "$best_path"
}

cmd_approve() {
  local plan now key have want
  [[ $# -ge 1 ]] || die_usage
  plan=$1
  shift
  require_plan_file "$plan"
  now=$(take_now "$@")
  load_lock_fns
  key=$(frontmatter_plan_sha "$plan")
  if [[ -z "$key" ]]; then
    exit 3
  fi
  have=$(plan_sha "$plan")
  have=$(lower_ascii "$have")
  have=${have//[[:space:]]/}
  want=$(lower_ascii "$key")
  if [[ "$have" != "$want" ]]; then
    printf '%s\n' "plan body changed since approval; re-approve with /make-plan update $plan" >&2
    exit 3
  fi
  upsert_top_keys "$plan" gate_b_sha "$want" gate_b_at "$now"
}

# claude-code is the in-process host name. Any other backend must be a
# registry delegate id (enabled or not).
valid_backend() {
  case "$1" in
    claude-code) return 0 ;;
  esac
  in_list "$1" "$REG_DELEGATES"
}

tool_enabled() {
  in_list "$(lower_ascii "$1")" "$REG_ENABLED_LC"
}

# Resolve bare review runner name to owning tool id via tiers.sh, caching
# hits in parallel indexed arrays (Bash 3.2). Sets REVIEW_TOOL_LAST.
lookup_review_tool() {
  local bare=$1 i n=${#REVIEW_TOOL_CACHE_K[@]} tool="" line orig_bare=$1
  for ((i = 0; i < n; i++)); do
    if [[ "${REVIEW_TOOL_CACHE_K[$i]}" == "$bare" ]]; then
      REVIEW_TOOL_LAST=${REVIEW_TOOL_CACHE_V[$i]}
      return 0
    fi
  done
  while IFS= read -r line; do
    if [[ "$(lower_ascii "$line")" == "top@$bare" ]]; then
      orig_bare=${line#top@}
      break
    fi
  done <<<"$REG_RUNNERS"
  tool=$(bash "$REG_TIERS" runner-tool "$orig_bare") || registry_unavailable "$REG_TIERS"
  REVIEW_TOOL_CACHE_K+=("$bare")
  REVIEW_TOOL_CACHE_V+=("$tool")
  REVIEW_TOOL_LAST=$tool
}

# For top@<x> other than top@session, print the owning tool id (and set
# REVIEW_TOOL_LAST) and return 0 when that tool is disabled; else return 1.
review_tool_disabled() {
  local review=$1 bare=""
  REVIEW_TOOL_LAST=""
  case "$review" in
    top@session) return 1 ;;
    top@*) bare=${review#top@} ;;
    *) return 1 ;;
  esac
  lookup_review_tool "$bare" || return 1
  if ! tool_enabled "$REVIEW_TOOL_LAST"; then
    printf '%s' "$REVIEW_TOOL_LAST"
    return 0
  fi
  return 1
}

# Read delegate ids, review runners, and enabled tools once, in this shell,
# from tiers.sh beside this script. Later $(...) subshells inherit the lists.
# A missing or failing resolver is an environment error (exit 2, not the exit 3
# plan-body refusal); there is no built-in list.
registry_unavailable() {
  echo "plan-status.sh: tier registry unavailable: $1" >&2
  exit 2
}

load_registry() {
  local dir tiers
  dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  tiers="$dir/tiers.sh"
  [[ -f "$tiers" ]] || registry_unavailable "$tiers"
  REG_TIERS="$tiers"
  REG_DELEGATES=$(bash "$tiers" delegates) || registry_unavailable "$tiers"
  REG_RUNNERS=$(bash "$tiers" runners) || registry_unavailable "$tiers"
  REG_ENABLED=$(bash "$tiers" tools) || registry_unavailable "$tiers"
  REG_DELEGATES_LC=$(printf '%s\n' "$REG_DELEGATES" | tr '[:upper:]' '[:lower:]')
  REG_RUNNERS_LC=$(printf '%s\n' "$REG_RUNNERS" | tr '[:upper:]' '[:lower:]')
  REG_ENABLED_LC=$(printf '%s\n' "$REG_ENABLED" | tr '[:upper:]' '[:lower:]')
  REVIEW_TOOL_CACHE_K=()
  REVIEW_TOOL_CACHE_V=()
  REVIEW_TOOL_LAST=""
}

main() {
  local cmd=${1:-}
  if [[ -z "$cmd" ]]; then
    usage
    exit 2
  fi
  shift
  case "$cmd" in
    rows | start | batch | terminal | review)
      load_registry
      ;;
    lock | stamp | recent | approve) ;;
    *)
      usage
      exit 2
      ;;
  esac
  case "$cmd" in
    lock) cmd_lock "$@" ;;
    rows) cmd_rows "$@" ;;
    start) cmd_start "$@" ;;
    batch) cmd_batch "$@" ;;
    terminal) cmd_terminal "$@" ;;
    review) cmd_review "$@" ;;
    stamp) cmd_stamp "$@" ;;
    recent) cmd_recent "$@" ;;
    approve) cmd_approve "$@" ;;
  esac
}

main "$@"
