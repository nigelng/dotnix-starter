---
name: gh-draft-release
description: >-
  Stash WIP, sync to the default branch, check unreleased commits, and create a
  draft GitHub Release with notes. Differs from gh-tag-release, which dates the
  changelog and pushes a tag to trigger publish CI. Args: none required. Use when
  the user asks to draft a release, create release notes, or mentions
  /gh-draft-release.
disable-model-invocation: true
---

# gh-draft-release

**User prompts:** `AskQuestion` when available; otherwise ask conversationally.

**When to use this vs `/gh-tag-release`:**
- `/gh-draft-release` (this skill) — create a **draft** GitHub Release with generated notes from unreleased commits. Does **not** push a tag or trigger publish. User publishes the draft manually.
- `/gh-tag-release` — push a git tag on `<default>` (after CI is green) to trigger the publish workflow. Does **not** create a GitHub Release draft; the publish workflow handles the release.

## Preconditions

- User explicitly asked to create a draft release (this skill does not create releases on its own initiative).
- Use `gh` for all GitHub operations. If `gh` is not available, inform the user and stop.

## Workflow

### 0. Resolve default branch

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
```

Use that name (e.g. `main` or `master`) everywhere below as `<default>`. Do **not** hardcode `main` / `origin/main`.

### 1. Handle uncommitted changes

```bash
git status --short
ORIG=$(git branch --show-current)
```

Record `<orig>` from `ORIG` (the branch to restore after the draft). Prefer **stash** on every branch (including feature branches):

```bash
git stash push -m "gh-draft-release-wip"
```

Do **not** create a WIP commit. Offer stash only. If no changes, proceed (still keep `<orig>` for restore).

### 2. Switch to default branch

```bash
git checkout <default>
```

### 3. Sync default branch

Release notes must only describe commits that the remote release target includes. Sync once:

```bash
git pull --ff-only
git status -sb
git rev-parse HEAD
git rev-parse origin/<default>
```

Require local `<default>` == `origin/<default>` (same commit).

- If local is **ahead** / has unpushed commits: stop, or user prompts whether to push first. Do not create a release whose notes describe commits the remote target does not include.
- If `git pull --ff-only` fails (diverged / non-ff): stop and inform the user; do not force-rebase unless they explicitly ask.
- If they match: proceed.

### 4. Detect unreleased changes

```bash
git describe --tags --abbrev=0
git log <latest-tag>..HEAD --oneline
```

If no tags exist, all commits are unreleased.

If there are no commits since the latest tag, inform the user "nothing to release" and stop.

### 5. Generate release notes

Prefer the **Unreleased** section of `CHANGELOG.md` (or `CHANGELOG`) when present and non-empty. Use that text as the release notes.

Otherwise, from commits since the last tag, group by conventional commit type (`feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `style`, `revert`). Present as a markdown summary with sections per type. Omit empty groups.

### 6. Suggest a release tag

- If `package.json` exists, read the `version` field and suggest `v<version>` as the tag (e.g. `v0.1.0`).
- If `package.json` is missing, user prompts for the tag (or infer from the latest tag / CHANGELOG when obvious). Do not invent a version silently.
- Present the tag and release note for approval (user prompts).

### 7. Check existing tag / release

Before creating, verify the suggested tag is free:

```bash
git rev-parse "v<version>" 2>/dev/null && echo "tag-exists" || echo "tag-free"
gh release view "v<version>" 2>/dev/null && echo "release-exists" || echo "release-free"
```

If the tag or release already exists, stop or user prompts whether to bump the version — do not overwrite or recreate.

### 8. Create draft GitHub Release

On approval of tag + notes, and after steps 3 and 7 pass, pass notes via `--notes-file` or a heredoc (never inline `--notes "..."` with a multi-line body):

```bash
gh release create <tag> --title "<tag>" --notes-file - --draft --target <default> <<'EOF'
<release-note>
EOF
```

Or write notes to a temp file and use `--notes-file <path>`.

Share the release URL with the user.

### 9. Revisions

If the user requests changes to the tag or release note, revise and repeat from step 6 (re-run steps 3 and 7 before create).

## Post-release

After the release is created (or if the workflow stops early), restore the working state:

```bash
git checkout <orig> && git stash pop
```

Skip `stash pop` if nothing was stashed. If already on `<orig>`, only `git stash pop` as needed.

## Constraints

- Always create releases in **draft** mode — the user publishes them manually.
- Do not push to `<default>` directly unless the user explicitly approves a push to sync local ahead commits (step 3).
- If already on `<default>` with no unreleased changes, inform the user and stop.
- Keep release text clean and user-authored — no AI co-author trailers.
- Use [Conventional Commits](https://www.conventionalcommits.org/) to group release notes by type when CHANGELOG Unreleased is absent.

## Safety (never)

- Update git config
- `git push --force` to `<default>` (warn if requested)
- Skip hooks (`--no-verify`) unless the user explicitly asks
- Push to `<default>` without explicit user approval
- Create a non-draft release without explicit user approval
- Create a release without user approval of the tag and notes
- Create a WIP commit (stash only)
