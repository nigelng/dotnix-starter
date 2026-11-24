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

`<skill-dir>` is the absolute directory of this `SKILL.md`. Run:

```bash
bash <skill-dir>/../commit/scripts/git-preflight.sh state
git log -5 --oneline
gh pr view --json url -q .url 2>/dev/null || echo "no-pr"
```

Use `default=` as `<default>` everywhere below. Do **not** hardcode `main` / `origin/main`. If `default=` is empty, stop and ask — do not guess. `state` fetched `origin`; on stderr `WARN: git fetch failed`, stop (stale `origin`). `clean=`, `branch=`, `upstream=`, `ahead=`, and `behind=` are against that upstream.

If `gh pr view` returned a URL, a PR already exists for this branch — report that URL and skip create later (still may push / watch CI as needed).

Compare against the remote default (not a possibly stale local ref):

```bash
git log --oneline origin/<default>...HEAD
git diff origin/<default>...HEAD
```

If `clean=yes` **and** that log is empty, inform the user and stop.

### 2. Commit uncommitted work (if any)

If `clean=no`, ask the user to run `/commit` to handle uncommitted changes first. Stop until the tree is clean (or the user confirms they will commit separately and continue with already-committed work only).

### 3. Planning-artifacts gate

After step 2, before creating a branch. Do not commit, do not run `git rm`, and do not run `/relay:discard`. Uncommitted artifact files are outside this PR. Call the script once:

```bash
bash <skill-dir>/scripts/pr-artifacts.sh <default>
```

Read that JSON: `plans` (`path`, `execution_status`), `notes` (`path`, `sibling`, `sibling_in_gate`), `relay` (`path`, `current_branch`, `mirror`), `dropped` (`path`, `sha`), `skipped` (unusual name). Show each skipped path as "skipped: unusual name" and do not print a `git rm` or permalink for it.

If `plans`, `notes`, and `relay` are all empty, skip the questions and continue to step 4. Do not announce an empty gate. Still pass dropped-plan permalinks to step 5.

**Plans.** One **Keep** / **Drop** question per `plans` entry. The prompt shows the path and `execution_status`. When that status is not `completed`, include "execution not finished" and the actual status. The user still decides.

**Notes.** `sibling_in_gate` true follows that plan's Keep or Drop — do not ask. `sibling_in_gate` false gets its own Keep / Drop question (path only; `*.notes.md` is not a plan).

**Relay.** One question per file. `current_branch` true: **Keep** or **Discard via `/relay:discard`** (do not `git rm`; `/relay:discard` takes the `discarded` lock when a twin exists). `current_branch` false and `mirror` false: **Keep** or **Drop**. `current_branch` false and `mirror` true: **Keep** or **Discard later from its own branch** (no Drop — removing it here would orphan the twin). **Discard later** counts as Keep: nothing is printed, the gate does not stop, tell the user to run `/relay:discard` on that branch later, and list the path as `(kept)` in step 5.

Up to four questions per call of the question tool (`AskQuestion`/`AskUserQuestion`/`ask_user_question`); wait before the next four (otherwise ask conversationally).

**Any Drop, or Discard via `/relay:discard`.** Stop. Do not continue to step 4, push, or open a PR.

1. When any plan is Dropped, run `git rev-parse HEAD` before printing `git rm`. Print that full SHA and each dropped plan path. The re-run uses this SHA for those permalinks when `git cat-file -e "<sha>:<path>"` succeeds; otherwise use the JSON `sha`. Name each dropped plan and its sibling note when `notes` lists that plan as `sibling`.

2. When any plan is Dropped, print this and do not run it. Paths are each dropped plan plus each `notes` path whose `sibling` is that plan:

```bash
git rm -- docs/plans/<file> docs/plans/<slug>.notes.md …
```

2b. When a note with `sibling_in_gate` false is Dropped, print `git rm -- <path> …` for those notes paths only and do not run it. No dropped-plan permalink.

3. When any relay file is Discarded or Dropped:
   - `current_branch` true: print: Run `/relay:discard`. It takes the `discarded` lock when a twin exists, then removes this branch’s handoff (`docs/relay/<slug>.md` or legacy `docs/handoffs/<slug>.md`). Do not `git rm` `docs/relay/**` or `docs/handoffs/**`.
   - `current_branch` false and `mirror` false: print `git rm -- <path> …` and do not run it. Mirrored other-branch files are never Dropped here.

4. Ask the user to run `/commit` for removals already made (plan `git rm`, other-branch relay `git rm`, plus relay files removed by `/relay:discard`). When a plan is dropped, suggest `chore: drop plan <slug>` (`<slug>` is the basename without `.md`; several slugs, space-separated, in one subject). When only current-branch relay files are discarded, suggest `chore: discard relay <slug>`; for other-branch relay drops use `chore: drop relay <slug>`. When plans and relay files are mixed, name both. Then stop. Kept answers are not stored: the re-run asks again. After those paths are gone and committed, re-running `/gh-create-pr` passes the gate.

**All Keep (including Discard later).** Continue to step 4. Step 5 lists every kept path under `## Planning artifacts`, including a kept plan's sibling note when `notes` lists it, and each note kept via its own question.

Permalink for each `dropped` entry: `https://github.com/<owner>/<repo>/blob/<sha>/<path>` (`gh repo view --json nameWithOwner -q .nameWithOwner`; `<path>` has no leading slash).

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
  - If step 3 kept any files or recovered any dropped-plan permalinks, add `## Planning artifacts` after the summary and before the test plan. One bullet per kept path (`<path> (kept)`), plans and relay files included; for each kept plan, also bullet the sibling path `notes` lists for it (`(kept)`). One bullet per dropped plan: the blob permalink from step 3, labelled `(dropped)` (notes siblings are removed via `git rm` with the plan, not separate permalinks). Include only rows that exist. Omit the heading when both lists are empty.
  - Include a short `## Test plan` checklist.
  - Check for a repo PR template (`.github/PULL_REQUEST_TEMPLATE.md` or any `.md` under `.github/PULL_REQUEST_TEMPLATE/`). If found, append its content below the generated summary, separated by a blank line.

### 6. Present for review

Present the branch name (if newly created or just confirmed), PR title, and combined body for review via the question tool when available (approve / revise / cancel); otherwise ask conversationally. **Do not push or create the PR until the user approves.**

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
- docs/plans/<slug>.notes.md (kept)
- https://github.com/<owner>/<repo>/blob/<sha>/docs/plans/<file>.md (dropped)

## Test plan
- [ ] <checklist item>

<optional PR template content>

EOF
)"
```

Include only the kept and dropped rows that exist.

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
5. If the failure is clearly caused by the PR and the fix is obvious, offer to fix it. Do **not** fix without user approval; if approved, commit via `/commit` (a new commit, not an amend) and push normally without `--force`.
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
