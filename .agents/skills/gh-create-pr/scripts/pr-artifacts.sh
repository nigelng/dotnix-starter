#!/usr/bin/env bash
# pr-artifacts.sh <default-branch> — read-only planning-artifact inventory.
# Prints JSON for added/modified plans (with execution.status), sibling notes
# at HEAD, relay files (current_branch and mirror), dropped plans (resolved
# SHA), and paths skipped for an unusual name. Never runs git rm.
# Bash 3.2. Run from the git repo that holds the branch.
set -euo pipefail

usage() {
  echo "usage: pr-artifacts.sh <default-branch>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
default=$1
[[ -n "$default" ]] || usage

cd "$(git rev-parse --show-toplevel)"

if [[ "$default" == */* ]]; then
  base=$default
else
  base="origin/$default"
fi
git rev-parse --verify "$base" >/dev/null 2>&1 || {
  echo "pr-artifacts.sh: cannot resolve $base" >&2
  exit 2
}

is_safe_plan() {
  [[ "$1" =~ ^docs/plans/[A-Za-z0-9._-]+\.md$ && "$1" != *.notes.md ]]
}
is_safe_notes() {
  [[ "$1" =~ ^docs/plans/[A-Za-z0-9._-]+\.notes\.md$ ]]
}
is_safe_relay() {
  [[ "$1" =~ ^docs/(relay|handoffs)/[A-Za-z0-9._-]+\.md$ ]]
}

branch_slug() {
  local branch slug short
  branch=$(git branch --show-current)
  if [[ -z "$branch" ]]; then
    short=$(git rev-parse --short HEAD)
    printf 'detached-%s' "$short"
    return
  fi
  slug=${branch//\//--}
  printf '%s' "$slug" | sed 's/[^A-Za-z0-9._-]/-/g'
}

execution_status_of_blob() {
  local path=$1 blob
  if ! blob=$(git show "HEAD:$path" 2>/dev/null); then
    printf 'unknown'
    return
  fi
  local status
  status=$(printf '%s\n' "$blob" | awk '
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
  ')
  if [[ -n "$status" ]]; then
    printf '%s' "$status"
  else
    printf 'unknown'
  fi
}

blob_has_mirror() {
  local path=$1 blob
  blob=$(git show "HEAD:$path" 2>/dev/null || true)
  printf '%s\n' "$blob" | awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm == 1 && /^---[[:space:]]*$/ { exit }
    fm == 1 && /^mirror:/ { found = 1; exit }
    END { exit found ? 0 : 1 }
  '
}

at_head() {
  git cat-file -e "HEAD:$1" 2>/dev/null
}

slug=$(branch_slug)
relay_self_a="docs/relay/${slug}.md"
relay_self_b="docs/handoffs/${slug}.md"

plans_json='[]'
notes_json='[]'
relay_json='[]'
dropped_json='[]'
skipped_json='[]'
note_seen=$'\n'
plan_seen=$'\n'

add_skip() {
  local path=$1 obj
  obj=$(jq -n -c --arg path "$path" --arg reason "unusual name" '{path:$path,reason:$reason}')
  skipped_json=$(jq -n -c --argjson arr "$skipped_json" --argjson obj "$obj" '$arr + [$obj]')
}

# Old paths of renames are moves, not drops.
rename_old=$'\n'
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  # status \t old \t new
  old=$(printf '%s' "$line" | awk -F '\t' '{print $2}')
  [[ -n "$old" ]] || continue
  rename_old+="${old}"$'\n'
done < <(git diff --name-status --find-renames --diff-filter=R "$base...HEAD" -- docs/plans || true)
# A file added and renamed only on this branch is not an R in the cumulative
# three-dot diff. Per-commit history still records the rename source.
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  old=$(printf '%s' "$line" | awk -F '\t' '{print $2}')
  [[ -n "$old" ]] || continue
  rename_old+="${old}"$'\n'
done < <(git log --diff-filter=R --name-status --pretty=format: "$base..HEAD" -- docs/plans || true)

# Added and modified artifacts. Renames and copies contribute the new path only.
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  status=${line%%$'\t'*}
  rest=${line#*$'\t'}
  case "$status" in
    A|M) path=$rest ;;
    R*|C*) path=$(printf '%s' "$rest" | awk -F '\t' '{print $2}') ;;
    *) continue ;;
  esac
  [[ -n "$path" ]] || continue
  if is_safe_notes "$path"; then
    case "$note_seen" in
      *$'\n'"$path"$'\n'*) ;;
      *)
        note_seen+="${path}"$'\n'
        sibling=${path%.notes.md}.md
        in_plans=false
        if is_safe_plan "$sibling"; then
          case "$plan_seen" in
            *$'\n'"$sibling"$'\n'*) in_plans=true ;;
          esac
        fi
        obj=$(jq -n -c --arg path "$path" --arg sibling "$sibling" --argjson sibling_in_gate "$in_plans" \
          '{path:$path,sibling:$sibling,sibling_in_gate:$sibling_in_gate,at_head:true}')
        notes_json=$(jq -n -c --argjson arr "$notes_json" --argjson obj "$obj" '$arr + [$obj]')
        ;;
    esac
  elif is_safe_plan "$path"; then
    plan_seen+="${path}"$'\n'
    est=$(execution_status_of_blob "$path")
    change=$status
    case "$status" in
      R*|C*) change=A ;;
    esac
    obj=$(jq -n -c --arg path "$path" --arg change "$change" --arg execution_status "$est" \
      '{path:$path,change:$change,execution_status:$execution_status}')
    plans_json=$(jq -n -c --argjson arr "$plans_json" --argjson obj "$obj" '$arr + [$obj]')
    sibling="${path%.md}.notes.md"
    if at_head "$sibling"; then
      case "$note_seen" in
        *$'\n'"$sibling"$'\n'*) ;;
        *)
          note_seen+="${sibling}"$'\n'
          obj=$(jq -n -c --arg path "$sibling" --arg sibling_plan "$path" \
            '{path:$path,sibling:$sibling_plan,sibling_in_gate:true,at_head:true}')
          notes_json=$(jq -n -c --argjson arr "$notes_json" --argjson obj "$obj" '$arr + [$obj]')
          ;;
      esac
    fi
  elif is_safe_relay "$path"; then
    current=false
    if [[ "$path" == "$relay_self_a" || "$path" == "$relay_self_b" ]]; then
      current=true
    fi
    mirror=false
    if blob_has_mirror "$path"; then
      mirror=true
    fi
    change=$status
    case "$status" in
      R*|C*) change=A ;;
    esac
    obj=$(jq -n -c --arg path "$path" --arg change "$change" \
      --argjson current_branch "$current" --argjson mirror "$mirror" \
      '{path:$path,change:$change,current_branch:$current_branch,mirror:$mirror}')
    relay_json=$(jq -n -c --argjson arr "$relay_json" --argjson obj "$obj" '$arr + [$obj]')
  else
    add_skip "$path"
  fi
done < <(git diff --name-status --find-renames "$base...HEAD" -- docs/plans docs/relay docs/handoffs || true)

# Notes that were recorded before their sibling plan was seen need sibling_in_gate refreshed.
notes_json=$(jq -c --argjson plans "$plans_json" '
  [ .[] | . as $note
    | .sibling_in_gate = (($plans | map(.path)) | index($note.sibling) != null) ]
' <<<"$notes_json")

# Dropped plans: added on the branch, absent at HEAD, not the old path of a rename.
while IFS= read -r path || [[ -n "$path" ]]; do
  [[ -n "$path" ]] || continue
  case "$path" in
    docs/plans/*) ;;
    *) continue ;;
  esac
  if at_head "$path"; then
    continue
  fi
  case "$rename_old" in
    *$'\n'"$path"$'\n'*) continue ;;
  esac
  if ! is_safe_plan "$path"; then
    add_skip "$path"
    continue
  fi
  sha=$(git log -1 --diff-filter=AM --format=%H "$base..HEAD" -- "$path" || true)
  obj=$(jq -n -c --arg path "$path" --arg sha "$sha" '{path:$path,sha:$sha}')
  dropped_json=$(jq -n -c --argjson arr "$dropped_json" --argjson obj "$obj" '$arr + [$obj]')
done < <(git log --diff-filter=A --name-only --pretty=format: "$base..HEAD" -- docs/plans || true)

jq -n -c \
  --argjson plans "$plans_json" \
  --argjson notes "$notes_json" \
  --argjson relay "$relay_json" \
  --argjson dropped "$dropped_json" \
  --argjson skipped "$skipped_json" \
  '{plans:$plans,notes:$notes,relay:$relay,dropped:$dropped,skipped:$skipped}'
