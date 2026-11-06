---
name: gh-tag-release
description: >-
  Date the changelog and push a release tag to trigger publish CI. Differs from
  gh-draft-release, which drafts a GitHub Release with notes. Args: none
  required. Use when the user asks to tag a release, publish a version, or
  mentions /gh-tag-release.
disable-model-invocation: true
---

# gh-tag-release

Date the changelog and **push a release tag** to trigger publish CI. This is not
`gh-draft-release`: that skill drafts a GitHub Release with notes via `gh`; this
skill only dates the changelog and pushes a git tag (the publish workflow
handles the release).

## Preconditions

- User explicitly asked to tag a release (this skill does not push or tag on its own initiative).
- Resolve the default branch with git only (see step 0). Use `gh` for CI wait and workflow-run listing. If `gh` is not available, **stop** at the CI wait step — do not skip it and tag anyway (that would contradict "do not tag until CI passes").

## Workflow

### 0. Resolve default branch and confirm a clean tree

Resolve `<default>` **without** `gh`:

```bash
git symbolic-ref refs/remotes/origin/HEAD
```

Use the branch name after `refs/remotes/origin/` (e.g. `main` or `master`) everywhere below as `<default>`. Do **not** hardcode `main` / `origin/main`. If `symbolic-ref` fails (no `origin/HEAD`), stop and ask the user to set upstream tracking or name the default branch — do not guess.

Confirm the current branch:

```bash
git branch --show-current
```

- If already on `<default>`, proceed.
- If not on `<default>`: abort, **or** ask for approval to `git checkout <default>` before any push/tag. Do not push or tag from a non-default branch.

Before any edit, confirm a clean working tree:

```bash
git status --short
```

If there are uncommitted changes, inform the user: "There are uncommitted changes. Commit or stash them first." and stop.

If the working tree is clean, proceed.

### 1. Propose the tag version

- Read the `version` field from `package.json` (e.g. `3.0.0`).
- Read the latest unreleased section header in `CHANGELOG.md`. Common variants include:
  - `## [3.0.0] — unreleased` / `## [3.0.0] - unreleased` (em-dash or hyphen)
  - `## [Unreleased]` / `## Unreleased`
  - Other fuzzy matches of an unreleased heading (case-insensitive `unreleased`)
- Extract the version from that heading when present (e.g. from `## [3.0.0] — unreleased`). If the heading is only `Unreleased` / `[Unreleased]` with no version, use the `package.json` version.
- If the `package.json` version and the CHANGELOG header version **match**, propose `v<version>` as the tag.
- If they **differ**, present both versions and propose a reconciliation:
  - Use `AskQuestion` when available (otherwise ask conversationally) which version to use, or suggest bumping `package.json` to match the CHANGELOG (or vice versa).
  - On approval, plan to update the mismatched file(s) so both agree — apply those edits in step 4 together with the changelog dating (do not edit yet).
- Present the proposed tag to the user for approval. If the user requests a different tag, revise.

If no `package.json` exists, ask the user for the version directly.

Tag-free pre-check (local and remote) once `<version>` is agreed:

```bash
git rev-parse -q --verify "v<version>"
git ls-remote --tags origin "v<version>"
```

If either command shows the tag already exists, inform the user and stop (do not retag or overwrite).

### 2. Push default branch to remote (if local is ahead)

```bash
git fetch origin
git log origin/<default>..<default> --oneline
```

If local `<default>` is **ahead** of `origin/<default>` (there are unpushed commits):

- Ask the user for approval to push: `git push origin <default>`.
- On approval, push. On denial, stop.

If local `<default>` is **behind** `origin/<default>`: inform the user "local `<default>` is behind origin/`<default>` — pull or rebase first" and stop.

If local `<default>` is **up to date** with `origin/<default>`: proceed to step 3.

### 3. Wait for CI to pass on the default branch

Requires `gh`. If `gh` is not available, stop here with a note — do not skip this step and continue to tag.

```bash
gh run list --branch <default> --limit 5
```

Identify the latest run for the verify workflow (the one triggered by the push to `<default>`, or the most recent run if already up to date).

- If the latest run is still in progress, watch it: `gh run watch <run-id> --exit-status`.
- If the run **fails**, inform the user: "CI failed on `<default>`. Fix the issues before releasing." and stop.
- If the run **succeeds**, proceed to step 4.
- If no verify workflow exists for this repo, skip this step with a note to the user.

### 4. Update the CHANGELOG for release

If no `CHANGELOG.md` exists, skip this step with a note (still apply any approved `package.json` reconciliation below if needed).

Otherwise:

- Find the latest unreleased heading (see variants in step 1). Date it for release:
  - Versioned unreleased (e.g. `## [3.0.0] — unreleased` / `- unreleased`) → `## [<version>] — <today's-date>` (ISO: `YYYY-MM-DD`), preserving the repo's heading style where practical.
  - Bare `## [Unreleased]` / `## Unreleased` → replace with a dated versioned heading such as `## [<version>] — <today's-date>` (or the repo's established pattern).
- Apply any approved `package.json` version reconciliation from step 1.
- Present the changelog (and package.json, if changed) to the user for approval.
- On approval, apply the edit(s) and commit, staging **both** files together when both changed (always include each file that was edited):

```bash
git add package.json CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs: date <version> release in changelog

EOF
)"
```

(If only one of the two was edited, `git add` only that file; keep the same commit message style when the change is changelog dating.)

- Push the commit: ask the user for approval to `git push origin <default>`, then push.

**Post-CI commit policy:** this dating commit is **docs-only** (changelog markdown; `package.json` version string alignment only). Tagging without waiting for another CI cycle on this commit is acceptable. Alternatively, tag first on the already-green tip and verify publish/CI after — do not leave a behaviour-changing commit untagged between green CI and the release tag.

### 5. Tag and push the tag

```bash
git tag v<version>
```

Ask the user for approval to push the tag: `git push origin v<version>`.

On approval, push the tag. This triggers the publish workflow.

Share the workflow run URL with the user:

```bash
gh run list --workflow=publish.yml --limit 1
```

(Use the appropriate workflow name if not `publish.yml`.)

### 6. Revisions

If the user requests changes to the tag or version, revise and repeat from step 1.

## Safety (never)

- Update git config
- `git push --force` to `<default>` (warn if requested)
- Skip hooks (`--no-verify`) unless the user explicitly asks
- Tag or push without explicit user approval
