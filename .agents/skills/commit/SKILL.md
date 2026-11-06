---
name: commit
description: >-
  Scan current changes, optionally bump package version and update
  CHANGELOG/README, then create a Conventional Commits message for review before
  committing. Args: none required. Use when the user asks to commit, save work,
  or mentions /commit, semantic commits, or Conventional Commits.
disable-model-invocation: true
---

# commit

Scan the current working-tree changes, update docs and version when appropriate, then create a [Conventional Commits](https://www.conventionalcommits.org/) commit after user review.

Session/Task tiers: [model-tiers.md](model-tiers.md) (`top`/`mid`/`low`). `/commit` defaults to `low` (use `mid` for large mixed trees or version + CHANGELOG judgment).

**AskQuestion:** when available, use it for approvals; otherwise ask conversationally.

## Preconditions

- User explicitly asked to commit (this skill does not commit on its own initiative).
- Do not commit files that likely contain secrets (`.env`, credentials, tokens). Warn the user if they request those.
- **Plans and brainstorms:** never stage or commit `docs/brainstorms/**` (local `/brainstorm` artifacts). Stage `docs/plans/**` only when `git check-ignore -q docs/plans/<file>` fails (path is tracked-eligible) **and** the plan belongs to this change; if `check-ignore` succeeds, leave that plan unstaged. Include eligible plans in the commit plan when they are part of the diff.

## Workflow

### 1. Inspect (parallel)

Run these in parallel:

```bash
git status --short
git diff HEAD
git diff --staged
git log -5 --oneline
```

If the working tree is clean, inform the user and stop.

### 2. Classify changes

Analyze the diff to determine the change type and scope:

- `feat:` — new feature or config
- `fix:` — bug fix or correction
- `chore:` — tooling, deps, CI, formatting
- `refactor:` — code restructuring with no behavior change
- `docs:` — documentation only
- `style:` — whitespace, formatting only
- `perf:`, `test:`, `build:`, `ci:`, `revert:` — as appropriate
- `BREAKING CHANGE` or `!:` suffix — breaking change (highest priority for version bump)

Match the repo's recent commit style from `git log`.

### 3. Split plan (if needed)

If the diff spans multiple distinct change types (e.g. `feat` + `chore` + `docs`), suggest splitting into multiple commits grouped by change type:

- Present a commit plan as a list of proposed commits, each with its type, summary, and the files it covers.
- Wait for user approval of the plan via AskQuestion.
- On approval, process each group through steps 4–9 (step 9 is the commit).
- If the user requests changes to the plan, revise and re-present.

If the diff is a single change type (or the user declines splitting), continue with one commit.

### 4. Draft commit message

Generate a conventional commit message:

```
<type>[optional scope][optional !]: <description>

[optional body — why, not what; 1-2 sentences max]
```

**Rules:**
- Description starts with a **lowercase** letter
- Imperative mood (`add`, not `added`)
- Summary ≤72 chars, no trailing period
- Focus on **why**, not a file list
- If the change spans multiple types and the user declined splitting, pick the most significant type
- No AI co-author trailers or "Generated with …" lines

**Invalid:** `Add feature`, `feat: Added thing.`, `fix: fixed the bug`

**Valid:**
```
feat(processor): add retry for transient SQS failures
fix: correct contact deduplication in batch queries
chore: bump node to 24 and update jest config
```

### 5. Propose version bump

If a `package.json` exists (or equivalent package manifest like `pyproject.toml`, `Cargo.toml`), compute **one** proposed version for the whole `/commit` session from the highest-priority commit type in the plan, using semantic versioning:

- `BREAKING CHANGE` or `!:` → major (e.g. 1.2.3 → 2.0.0)
- `feat:` → minor (e.g. 1.2.3 → 1.3.0)
- `fix:` → patch (e.g. 1.2.3 → 1.2.4)
- `chore:`, `refactor:`, `docs:`, `style:`, `perf:`, `test:`, `build:`, `ci:`, `revert:` → no version change

**Apply rules:**
1. Propose the version once for the session; apply it only on the **first** commit in a multi-commit plan.
2. If CHANGELOG has a versioned unreleased heading (`## [x.y.z] — unreleased`), skip proposing/applying only when that `x.y.z` is already at or past the proposed version (from last tag via `git describe --tags --abbrev=0`). A bare `## [Unreleased]` does **not** skip — still propose when the commit type warrants a bump. If an existing versioned heading is below the proposed bump, propose the higher version (and update the heading).
3. Skip if the package manifest version is already at or past the proposed version since the last tag (`git describe --tags --abbrev=0`).

Present the suggested version to the user for approval via AskQuestion. If the user declines, skip the version change.

### 6. Update CHANGELOG

If a `CHANGELOG.md` exists, prepend a new entry under the canonical unreleased heading (reuse an existing top unreleased heading rather than duplicating it):

- Version change applied in Step 5, **or** `CHANGELOG.md` already has `## [x.y.z] — unreleased`: use `## [x.y.z] — unreleased` (when bumping, upgrade an existing bare `## [Unreleased]` or lower versioned unreleased heading in place).
- Neither applies: use `## [Unreleased]` (prepend under an existing `## [Unreleased]` if present).

Under that heading:

- Add the commit type and summary as a bullet point.
- Group by type if multiple changes are being committed together.

If no `CHANGELOG.md` exists, skip this step — do not create one.

### 7. Update README

If the changes affect documented features, configuration options, usage examples, or any content covered in `README.md`, suggest updates to keep it in sync. Present the proposed README changes to the user for approval. If no updates are needed, skip this step.

### 8. Present for review

Present the proposed commit message, proposed version (if any), changelog diff, and README diff (if any) to the user for review via AskQuestion (approve / revise / cancel). **Do not commit until the user approves.**

If the user requests changes, revise and repeat this step.

### 9. Stage and commit (sequential)

On approval:

```bash
# Prefer path-specific adds (not `git add -A`). Stage docs/plans/<file> only when `git check-ignore -q` fails and the file is part of this change; never docs/brainstorms/**.
git add <paths-to-commit>
git commit -m "$(cat <<'EOF'
<type>[scope]: <description>

<optional body>

EOF
)"
git status
```

Stage from the repo root so approved changes are included (including any approved version/CHANGELOG/README edits). Exclude secret files if any were flagged. If a version change was applied, include it in the same commit.

### 10. Hook failure and amend

If pre-commit **rejects** the commit:

1. Fix the reported issues.
2. Create a **new** commit — never `--amend` after a rejected hook.

Use `git commit --amend` only when **all** of the following are true:

1. The user explicitly requested amend, **or** the commit succeeded and a hook auto-modified files that must be included.
2. HEAD was created by you in this conversation.
3. The commit has not been pushed.

If already pushed, never amend unless the user explicitly requests it (requires force push).

## Offer next steps

After a successful commit:
- Done — stop here (local commit only).
- **Open a PR** — suggest `/gh-create-pr` to create a branch (if needed), push, and open a PR.
- **Review the change first** — suggest `/critique change` if the diff hasn't been reviewed yet.

## Safety (never)

- Skip hooks (`--no-verify`) unless the user explicitly asks
- Update `git config`
- Push or `git push --force` (local commits only unless the user explicitly asks)
