---
name: gh-create-pr
description: >-
  Create a feature branch if on the default branch, push commits, open a PR via
  gh CLI, and watch CI. Ask the user to run /commit first if the tree is dirty.
  Gate plan and relay files on the branch (Keep or Drop) and stop without
  deleting or committing when any are dropped. Args: none required. Use when
  the user asks to create a PR, open a pull request, push and PR, or mentions
  /gh-create-pr.
disable-model-invocation: true
---

# gh-create-pr

Create a pull request for the current changes: ensure a feature branch, push, open the PR, then watch CI. Does not commit and does not delete plan or relay files. Ask the user to run `/commit` first if the tree is dirty. If they Drop a plan or Discard a relay file, print the commands, ask them to commit, and stop.

## Preconditions

- User explicitly asked to create a PR (this skill does not push or open PRs on its own initiative).
- Use `gh` for all GitHub operations. If `gh` is not available, inform the user and stop.

## Workflow

### 1. Inspect (parallel)

Run these in parallel:

```bash
git status --short
git log -5 --oneline
git branch --show-current
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "no-upstream"
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
gh pr view --json url -q .url 2>/dev/null || echo "no-pr"
```

Use the resolved name (e.g. `main` or `master`) everywhere below as `<default>`. Do **not** hardcode `main` / `origin/main`.

If `gh pr view` returned a URL, a PR already exists for this branch — report that URL and skip create later (still may push / watch CI as needed).

Then fetch the remote default branch and compare against it (not a possibly stale local ref):

```bash
git fetch origin <default>
git log --oneline origin/<default>...HEAD
git diff origin/<default>...HEAD
```

If the working tree is clean **and** there are no commits ahead of `origin/<default>`, inform the user and stop.

### 2. Commit uncommitted work (if any)

If there are uncommitted changes, ask the user to run `/commit` to handle them first. This skill does not commit changes itself. Stop until the tree is clean (or the user confirms they will commit separately and continue with already-committed work only).

### 3. Planning-artifacts gate

Run this after step 2, before creating a branch. The skill does not commit here, does not run `git rm`, and does not run `/relay:discard`.

The diff is commits only (`origin/<default>...HEAD`). Uncommitted artifact files are outside this PR.

List added and modified artifacts:

```bash
git diff --name-status origin/<default>...HEAD -- docs/plans docs/relay docs/handoffs
```

Include a path when the status is `A` or `M`. For a rename or copy (`R` or `C`), include the new path only. Ignore deletions (`D`).

Also find **dropped plans** for the PR body (step 5). Do not prompt about them. A dropped plan was added on this branch and is absent at `HEAD`, so the command above no longer lists it. PRs here are squash-merged (`(#N)` subjects): that plan never reaches `<default>` history. GitHub keeps the pre-drop commit reachable via `refs/pull/N/head`, and the PR body holds a blob permalink to it.

```bash
git log --diff-filter=A --name-only --pretty=format: origin/<default>..HEAD -- docs/plans
```

Keep a path only when `git cat-file -e "HEAD:<path>"` fails (added, then gone). Exclude the old path of a rename (the second field of `git diff --name-status --diff-filter=R origin/<default>...HEAD -- docs/plans`): that path moved, it was not dropped. Resolve `<sha>` in this order:

1. The SHA printed the last time this session stopped for a Drop, when `git cat-file -e "<sha>:<path>"` succeeds.
2. Otherwise the newest commit on the branch that added or modified the file:

```bash
git log -1 --diff-filter=AM --format=%H origin/<default>..HEAD -- <path>
```

When any permalink is needed:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

Permalink form: `https://github.com/<owner>/<repo>/blob/<sha>/<path>` (`<path>` has no leading slash).

If the added/modified list is empty, skip the questions silently and continue to step 4. Do not announce an empty gate. Still pass any dropped-plan permalinks to step 5.

Otherwise split the list into plans (`docs/plans/**`) and relay files (`docs/relay/**` and `docs/handoffs/**`).

**Plans.** For each file, read `execution.status` from YAML frontmatter (the `execution.status` field, not the execution-log table). If it is missing, show `unknown`.

One question per file, up to four questions per `AskQuestion` call; wait for the answers before asking about the next four (otherwise ask conversationally). Options are **Keep** and **Drop**. The prompt shows the path and `execution.status`. When the status is not `completed`, include the warning "execution not finished" and the actual status. The user still decides.

**Relay files.** Same batching (one question per file, up to four per call). Resolve the current branch slug first (see item 3 below). For a file of the current branch, options are **Keep** and **Discard via `/relay:discard`**. Do not `git rm` it. A mirrored twin needs its `discarded` lock first; `/relay:discard` takes that lock, then removes the repo file.

For a relay file whose slug is not the current branch's, read its YAML frontmatter. With no `mirror:` key there is no remote twin and no lock to take: options are **Keep** and **Drop** (Drop prints a plain `git rm`, as for plans). With a `mirror:` key, options are **Keep** and **Discard later from its own branch**; there is no Drop, because removing it here would orphan the remote twin without its `discarded` lock.

**Discard later from its own branch** counts as Keep for this PR: nothing is printed and the gate does not stop; tell the user to run `/relay:discard` on that branch later, and list the path as `(kept)` in step 5.

**Any Drop, or Discard via `/relay:discard`.** Stop. Do not continue to step 4, push, or open a PR.

1. When any plan is Dropped, record the last commit that still contains it **before** printing a `git rm` command:

```bash
git rev-parse HEAD
```

Print the full SHA and each dropped plan path. The re-run uses this SHA for those permalinks. Accept only paths matching `^docs/plans/[A-Za-z0-9._-]+\.md$`; show any other as "skipped: unusual name" and do not print a `git rm` or permalink for it.

2. When any plan is Dropped, print this command and do not run it. Paths are only the dropped plans:

```bash
git rm -- docs/plans/<file> …
```

3. When any relay file is Discarded or Dropped, resolve the current branch slug the same way as `/relay:discard` Step 1 (`branch` from `git branch --show-current`; if empty, `slug=detached-<short>` from `git rev-parse --short HEAD`; else `/` → `--`, characters outside `[A-Za-z0-9._-]` → `-`). This branch’s handoff paths are `docs/relay/<slug>.md` and legacy `docs/handoffs/<slug>.md`. Split each discarded path into **current-branch** (equals one of those two) vs **other**.

   - **Current-branch** (Keep/Discard intent via `/relay:discard`): print:

   > Run `/relay:discard`. It takes the `discarded` lock when a twin exists, then removes this branch’s handoff (`docs/relay/<slug>.md` or legacy `docs/handoffs/<slug>.md`). Do not `git rm` `docs/relay/**` or `docs/handoffs/**`.

   - **Other** paths (unmirrored, Dropped): `/relay:discard` only removes this branch’s handoff, so print a plain `git rm -- <path> …` for the user to run (never run it here). Accept only paths matching `^docs/(relay|handoffs)/[A-Za-z0-9._-]+\.md$`; show any other as "skipped: unusual name". Mirrored other-branch files are never Dropped here.

4. Ask the user to run `/commit` for removals already made (plan `git rm`, other-branch relay `git rm`, plus relay files removed by `/relay:discard`). When a plan is dropped, suggest `chore: drop plan <slug>` (`<slug>` is the basename without `.md`; several slugs, space-separated, in one subject). When only relay files are discarded via `/relay:discard`, suggest `chore: discard relay <slug>`; for other-branch relay drops use `chore: drop relay <slug>`. When plans and relay files are mixed, name both the plan and relay slugs in the subject. Then stop. Kept answers are not stored: the re-run asks again for every path still added or modified. After those paths are gone and committed, re-running `/gh-create-pr` passes the gate for the dropped and discarded paths.

**All Keep (including Discard later).** Continue to step 4. Step 5 lists every kept path under `## Planning artifacts`.

### 4. Ensure feature branch

Use the current branch from step 1 (do not re-run `git branch --show-current`):

- If already on a feature branch (not `<default>`), skip branch creation.
- If on `<default>`, analyze the commits and suggest a branch name in the format `<type>/<short-description>` (e.g. `feat/add-tsconfig`, `fix/publish-workflow`). Present the suggested name for approval. On approval, run `git checkout -b <branch>`.

Never push commits directly to `<default>`.

### 5. Draft PR title and body

- **Title:** [Conventional Commits](https://www.conventionalcommits.org/) format.
  - Single commit → use its subject directly.
  - Multiple commits → primary commit's type+summary, or a combined summary of the main change.
- **Body:**
  - Start with a `## Summary` bullet list derived from the commit messages (what changed and why).
  - If step 3 kept any files or recovered any dropped-plan permalinks, add `## Planning artifacts` after the summary and before the test plan. One bullet per kept path (`<path> (kept)`), plans and relay files included. One bullet per dropped plan: the blob permalink from step 3, labelled `(dropped)`. Include only rows that exist. Omit the heading when both lists are empty.
  - Include a short `## Test plan` checklist.
  - Check for a repo PR template (`.github/PULL_REQUEST_TEMPLATE.md` or any `.md` under `.github/PULL_REQUEST_TEMPLATE/`). If found, append its content below the generated summary, separated by a blank line.

### 6. Present for review

Present the branch name (if newly created or just confirmed), PR title, and combined body to the user for review via `AskQuestion` when available (approve / revise / cancel); otherwise ask conversationally. **Do not push or create the PR until the user approves.**

If the user requests changes to the title or body, revise and re-present.

### 7. Push (sequential)

On approval:

```bash
git push -u origin HEAD
```

Use `-u` when the branch has no upstream. Do not force-push to `<default>`; warn if the user requests it.

### 8. Create PR (sequential)

If step 1 already found an existing PR for this branch, report that URL and skip create (do not call `gh pr create`). If step 3 produced planning-artifact lines, show them in that report. Do not edit the existing PR body unless the user asks.

Otherwise:

```bash
gh pr create --base <default> --title "<conventional-commit title>" --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Planning artifacts
- docs/plans/<file>.md (kept)
- https://github.com/<owner>/<repo>/blob/<sha>/docs/plans/<file>.md (dropped)

## Test plan
- [ ] <checklist item>

<optional PR template content>

EOF
)"
```

Omit `## Planning artifacts` when step 3 has nothing to list. Include only the kept and dropped rows that exist.

Share the returned PR URL. Mention any commits created and the base branch (`<default>`) used.

### 9. Watch CI status

CI checks are triggered by the push and/or PR creation. After the PR exists:

1. Run `gh pr checks <PR-number> --watch` to monitor status checks in real time.
2. If `--watch` is unsupported or times out, poll with `gh pr checks <PR-number>` every 30–60 seconds until all checks reach a terminal state (success, failure, or cancelled), **or until ~20 minutes have elapsed**.
3. If still pending after ~20 minutes, stop polling and report which checks are still pending (names + current status). Do not keep waiting indefinitely.

**If all checks pass** — report success and stop. Do not merge.

**If any check fails** — do not only report failure; investigate:

1. Run `gh run view <run-id> --log-failed` to fetch the failed job's logs.
2. Identify the failing step and extract the error message(s).
3. Cross-reference with the PR changes (caused by this PR vs pre-existing/flaky).
4. Present a summary:
   - Which check(s) failed and the job name(s)
   - Specific error message(s) and failing step(s)
   - Whether the failure is caused by the PR or appears pre-existing/flaky
   - A recommended next step (fix code, update workflow, re-run, etc.)
5. If the failure is clearly caused by the PR and the fix is obvious, offer to fix it. Do **not** fix without user approval; if approved, commit via `/commit` (a new commit, not an amend) and push normally without `--force`. This skill still does not commit.
6. If flaky or infrastructure-related (network timeout, runner issue), offer `gh run rerun <run-id> --failed`.

**If checks are skipped or none run** — tell the user no CI checks were triggered and ask whether they expected any.

### 10. Offer next steps

After the PR is open (and CI is green or the user accepted skipped checks):
- Done — stop here; user merges manually.
- After merge on `<default>`: suggest `/gh-tag-release` to tag and trigger the publish workflow, **or** `/gh-draft-release` to create a draft GitHub Release with notes (no tag/publish).

## Safety (never)

- Commit secret/credential files (`.env`, tokens, keys), update `git config`, or skip hooks (`--no-verify`) unless the user explicitly asks
- Commit, `git rm`, or `/relay:discard` from this skill. On Drop or Discard, print the commands and ask the user to run `/commit`. Never `git rm` a relay file for the current branch (use `/relay:discard`) or any relay file with `mirror:`; for an unmirrored other-branch relay file, only print the `git rm`, never run it
- `git commit --amend` after push or `git push --force` (to `<default>` or the PR branch) unless the user explicitly asks after warning
