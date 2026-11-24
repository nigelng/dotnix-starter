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

**User prompts:** the question tool (`AskQuestion`/`AskUserQuestion`/`ask_user_question`) when available; otherwise ask conversationally.

**When to use this vs `/gh-tag-release`:**
- `/gh-draft-release` (this skill) — create a **draft** GitHub Release with generated notes from unreleased commits. Does **not** push a tag or trigger publish. User publishes the draft manually.
- `/gh-tag-release` — push a git tag on `<default>` (after CI is green) to trigger the publish workflow. Does **not** create a GitHub Release draft; the publish workflow handles the release.

## Preconditions

- User explicitly asked to create a draft release (this skill does not create releases on its own initiative).
- Use `gh` for all GitHub operations. If `gh` is not available, inform the user and stop.

## Workflow

### 0. Resolve default branch

`<skill-dir>` is the absolute directory of this `SKILL.md`.

```bash
bash <skill-dir>/../commit/scripts/git-preflight.sh state
```

Use `default=` as `<default>`. If it is empty, stop and ask. Do **not** hardcode `main` / `origin/main`.

### 1. Handle uncommitted changes

`<orig>` is `branch=` from step 0 (restored after the draft). `clean=no` → offer stash only. `clean=yes` → proceed (still keep `<orig>`). Prefer **stash** on every branch (including feature branches):

```bash
git stash push -m "gh-draft-release-wip"
```

Do **not** create a WIP commit. If no changes, proceed.

From here, every stop after this step runs **Restore** first.

### 2. Switch to default branch

```bash
git checkout <default>
```

### 3. Sync default branch

Release notes must only describe commits the remote release target includes. Sync once:

```bash
git pull --ff-only
bash <skill-dir>/../commit/scripts/git-preflight.sh state
```

Require `branch=<default>`, `upstream=origin/<default>`, `ahead=0`, and `behind=0`.

- `ahead` greater than 0: stop, or ask whether to push first.
- `git pull --ff-only` fails, or `behind` greater than 0: stop; do not force-rebase unless they explicitly ask.
- Those four hold: proceed.

### 4. Detect unreleased changes

```bash
bash <skill-dir>/../commit/scripts/git-preflight.sh version
git log <last_tag>..HEAD --oneline
```

Empty `last_tag=` → all commits are unreleased. No commits since `last_tag` → "nothing to release" and stop.

### 5. Generate release notes

Prefer the **Unreleased** section of `CHANGELOG.md` (or `CHANGELOG`) when present and non-empty. Use that text as the release notes.

Otherwise, from commits since the last tag, group by conventional commit type (`feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `style`, `revert`). Present as a markdown summary with sections per type. Omit empty groups.

### 6. Suggest a release tag

Use `manifest=` from step 4's `version` output (re-run `version` if skipped). Non-empty → suggest `v<manifest>`. Empty → ask for the tag (or infer from `last_tag` / CHANGELOG when obvious). Do not invent a version silently. Present the tag and notes for approval.

### 7. Check existing tag / release

Before creating, verify the suggested tag is free:

```bash
bash <skill-dir>/../commit/scripts/git-preflight.sh version v<version>
gh release view "v<version>" 2>/dev/null && echo "release-exists" || echo "release-free"
```

`local_tag=yes`, `remote_tag=yes`, or release-exists → stop or ask whether to bump. `remote_tag=unknown` (cannot verify) → stop and report. Do not overwrite or recreate.

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

On requested changes, revise and repeat from step 6 (re-run steps 3 and 7 before create).

## Restore

Run on success and on every stop after step 1:

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
