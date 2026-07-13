#!/usr/bin/env bash
# Generate a Keep a Changelog section from conventional commits and optionally prepend to CHANGELOG.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${ROOT}/cliff.toml"
CHANGELOG="${ROOT}/CHANGELOG.md"
CLIFF="${GIT_CLIFF_BIN:-git-cliff}"

SKIP_PATTERNS=(
  '^Merge pull request'
  '^docs\(release\):'
  '^build\(deps\):'
  '^chore: update flake inputs$'
)

usage() {
  cat <<'EOF'
Usage: release-changelog.sh [options]

Generate a Keep a Changelog section from conventional commits since a ref.

Options:
  --print-prev-tag          Print latest v* tag, or root commit if none
  --bump TAG BUMP           Bump semver tag (patch|minor|major)
  --since REF               Start of commit range (tag or SHA)
  --version TAG             Target release tag (e.g. v1.0.1)
  --dry-run                 Print section only; fail when no releasable commits
  --prepend                 Prepend generated section to CHANGELOG.md
  --extract-section TAG     Print an existing ## [X.Y.Z] section from CHANGELOG.md
  --header-exists TAG       Exit 0 when the version header exists in CHANGELOG.md
  --tag-exists TAG          Exit 0 when the git tag exists
  --release-commit-sha TAG  Print SHA of docs(release): vX.Y.Z commit
  --orphan-headers          List v-prefixed semver changelog headers without a git tag
  --check-orphans TAG BOOL  Fail on untagged headers (BOOL: true|false for recover mode)
  -h, --help                Show this help

Examples:
  ./scripts/release-changelog.sh --since v1.0.0 --version v1.0.1 --dry-run
  ./scripts/release-changelog.sh --print-prev-tag
  ./scripts/release-changelog.sh --bump v1.0.0 patch
EOF
}

require_cliff() {
  if ! command -v "$CLIFF" >/dev/null 2>&1; then
    echo "git-cliff is required (set GIT_CLIFF_BIN or install git-cliff)" >&2
    exit 1
  fi
}

strip_v() {
  printf '%s' "${1#v}"
}

is_skipped_subject() {
  local subject="$1"
  local pattern
  for pattern in "${SKIP_PATTERNS[@]}"; do
    if [[ "$subject" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

is_conventional_subject() {
  local subject="$1"
  [[ "$subject" =~ ^(feat|fix|perf|refactor|style|docs|chore|ci|test|build|deprecate|remove|security)(\([[:alnum:]@./_-]+\))?(!)?: ]]
}

resolve_prev_tag() {
  local tag
  tag="$(git tag -l 'v*' --sort=-v:refname | head -1 || true)"
  if [[ -n "$tag" ]]; then
    printf '%s' "$tag"
    return 0
  fi
  git rev-list --max-parents=0 HEAD
}

bump_semver() {
  local current="$1"
  local bump="$2"
  local ver major minor patch

  ver="$(strip_v "$current")"
  IFS=. read -r major minor patch <<< "$ver"
  case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *)
      echo "Invalid bump type: $bump (expected patch, minor, or major)" >&2
      return 1
      ;;
  esac
  printf 'v%s.%s.%s' "$major" "$minor" "$patch"
}

count_releasable_commits() {
  local since="$1"
  local count=0
  local subject

  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    if is_skipped_subject "$subject"; then
      continue
    fi
    if ! is_conventional_subject "$subject"; then
      continue
    fi
    count=$((count + 1))
  done < <(git log --format='%s' "${since}..HEAD")

  printf '%s' "$count"
}

ensure_releasable_commits() {
  local since="$1"
  local count

  count="$(count_releasable_commits "$since")"
  if [[ "$count" -eq 0 ]]; then
    echo "No releasable commits in range ${since}..HEAD" >&2
    exit 1
  fi
}

generate_section() {
  local since="$1"
  local version="$2"

  ensure_releasable_commits "$since"
  require_cliff
  "$CLIFF" --config "$CONFIG" --tag "$version" --unreleased "${since}..HEAD"
}

header_exists() {
  local version="$1"
  local bare

  bare="$(strip_v "$version")"
  grep -qF "## [${bare}]" "$CHANGELOG"
}

tag_exists() {
  git rev-parse "$1^{commit}" >/dev/null 2>&1
}

list_semver_headers() {
  grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" \
    | sed -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/'
}

list_orphan_headers() {
  local ver

  while IFS= read -r ver; do
    [[ -z "$ver" ]] && continue
    if ! tag_exists "v${ver}"; then
      printf 'v%s\n' "$ver"
    fi
  done < <(list_semver_headers)
}

check_orphan_headers() {
  local next_tag="$1"
  local recover="$2"
  local orphans=()
  local found=false
  local o orphan_list

  while IFS= read -r o; do
    [[ -z "$o" ]] && continue
    orphans+=("$o")
  done < <(list_orphan_headers)

  if [[ ${#orphans[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ "$recover" == true ]]; then
    for o in "${orphans[@]}"; do
      if [[ "$o" == "$next_tag" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" != true ]]; then
      orphan_list=$(IFS=', '; echo "${orphans[*]}")
      echo "recover: true requires next tag ${next_tag} to match an orphan header; found: ${orphan_list}" >&2
      exit 1
    fi
    return 0
  fi

  orphan_list=$(IFS=', '; echo "${orphans[*]}")
  echo "Orphan changelog headers without tags: ${orphan_list}. Re-dispatch with recover: true for the matching version." >&2
  exit 1
}

extract_section() {
  local version="$1"
  local bare

  bare="$(strip_v "$version")"
  awk -v ver="$bare" '
    /^## \[/ {
      if (capturing && $0 !~ "^## \\[" ver "\\]") {
        exit
      }
      if ($0 ~ "^## \\[" ver "\\]") {
        capturing = 1
        print
        next
      }
    }
    capturing { print }
  ' "$CHANGELOG"
}

release_commit_sha() {
  local version="$1"
  local subject="docs(release): ${version} [skip ci]"
  local sha

  sha="$(git log -1 --fixed-strings --grep="$subject" --format=%H || true)"
  if [[ -z "$sha" ]]; then
    echo "No docs(release): ${version} commit found" >&2
    exit 1
  fi
  printf '%s' "$sha"
}

prepend_section() {
  local section_file="$1"
  local tmp

  tmp="$(mktemp)"
  awk -v section_file="$section_file" '
    BEGIN {
      while ((getline line < section_file) > 0) {
        section = section line "\n"
      }
      close(section_file)
      inserted = 0
    }
    {
      print
      if (!inserted && /^> Versions before 1\.0\.0/) {
        print ""
        printf "%s", section
        if (section !~ /\n$/) {
          print ""
        }
        inserted = 1
      } else if (!inserted && /^The format is based on \[Keep a Changelog\]/) {
        hold_format = 1
      } else if (!inserted && hold_format && /^$/) {
        print ""
        printf "%s", section
        if (section !~ /\n$/) {
          print ""
        }
        inserted = 1
        hold_format = 0
      }
    }
    END {
      if (!inserted) {
        print "Could not find CHANGELOG insertion point" > "/dev/stderr"
        exit 1
      }
    }
  ' "$CHANGELOG" > "$tmp"
  mv "$tmp" "$CHANGELOG"
}

SINCE=""
VERSION=""
BUMP_FROM=""
BUMP_TYPE=""
DRY_RUN=false
PREPEND=false
EXTRACT_TAG=""
HEADER_TAG=""
TAG_CHECK=""
RELEASE_SHA_TAG=""
ORPHAN_CHECK_TAG=""
ORPHAN_CHECK_RECOVER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-prev-tag)
      resolve_prev_tag
      exit 0
      ;;
    --bump)
      BUMP_FROM="${2:?--bump requires a tag}"
      BUMP_TYPE="${3:?--bump requires patch|minor|major}"
      bump_semver "$BUMP_FROM" "$BUMP_TYPE"
      exit 0
      ;;
    --since)
      SINCE="${2:?--since requires a ref}"
      shift 2
      ;;
    --version)
      VERSION="${2:?--version requires a tag}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --prepend)
      PREPEND=true
      shift
      ;;
    --extract-section)
      EXTRACT_TAG="${2:?--extract-section requires a tag}"
      extract_section "$EXTRACT_TAG"
      exit 0
      ;;
    --header-exists)
      HEADER_TAG="${2:?--header-exists requires a tag}"
      header_exists "$HEADER_TAG"
      exit 0
      ;;
    --tag-exists)
      TAG_CHECK="${2:?--tag-exists requires a tag}"
      tag_exists "$TAG_CHECK"
      exit 0
      ;;
    --release-commit-sha)
      RELEASE_SHA_TAG="${2:?--release-commit-sha requires a tag}"
      release_commit_sha "$RELEASE_SHA_TAG"
      exit 0
      ;;
    --orphan-headers)
      list_orphan_headers
      exit 0
      ;;
    --check-orphans)
      ORPHAN_CHECK_TAG="${2:?--check-orphans requires a tag}"
      ORPHAN_CHECK_RECOVER="${3:?--check-orphans requires true or false}"
      check_orphan_headers "$ORPHAN_CHECK_TAG" "$ORPHAN_CHECK_RECOVER"
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SINCE" || -z "$VERSION" ]]; then
  echo "--since and --version are required for generation" >&2
  usage >&2
  exit 1
fi

section_file="$(mktemp)"
trap 'rm -f "$section_file"' EXIT

generate_section "$SINCE" "$VERSION" > "$section_file"

if [[ ! -s "$section_file" ]]; then
  echo "git-cliff produced an empty changelog section" >&2
  exit 1
fi

if ! grep -qE '^- ' "$section_file"; then
  echo "No changelog bullets generated for ${SINCE}..HEAD" >&2
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  cat "$section_file"
  exit 0
fi

if [[ "$PREPEND" == true ]]; then
  if header_exists "$VERSION"; then
    echo "CHANGELOG already contains header for ${VERSION}" >&2
    exit 1
  fi
  prepend_section "$section_file"
fi

cat "$section_file"
