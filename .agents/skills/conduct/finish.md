# conduct finish

Run this guide only at `/conduct` Stage 6, except **Branch**, which runs at Stage 4 entry (including resume). Finish modes are `push` (branch, commit, push), `pr` (push plus PR and CI watch), and `none` (leave work uncommitted, with no branch creation, commit, push or PR). Foreign paths are defined in [SKILL.md](SKILL.md) Step 0.6; apply that file's **Downgrade rule** before finishing and whenever a condition arises below. A downgrade sets `finish=none`, stops before commit and reports why.

## Branch

At Stage 4 entry, when `finish` is `push` or `pr`, `<skill-dir>` is the absolute directory of [SKILL.md](SKILL.md):

```bash
bash <skill-dir>/../commit/scripts/git-preflight.sh state
```

1. `branch=` is the current branch. Use the default branch resolved in Step 0.6; never hardcode its name. `default=` from `state` may be empty and does not replace it. Do not treat `clean=`, `ahead=`, or `behind=` as the Step 0.6 foreign-path list or the ahead-of-`origin/<default>` count.
2. If `branch=` is already a non-default branch, reuse it. The Step 0.6 preflight owns approval to ship any existing commits.
3. On the default branch, derive `<type>/<plan-slug>`: use `feat` unless the plan's Purpose is clearly `fix`, `docs`, `chore` or `refactor`. The slug is the plan basename without `.md` and its date prefix.
4. Check the candidate against local branches and branch names on `origin`, including remote heads not fetched locally. If it exists in either place, try `-2`, then `-3`, and so on until free.
5. Run `git switch -c <type>/<plan-slug>` with the chosen free name. If creation fails, stop and report; do not implement on the default branch.

Do not defer branch creation until Stage 6. If Stage 6 finds the current branch is the default branch, apply the downgrade rule rather than creating a branch to bypass it.

## Commit

For `finish=push` or `finish=pr`, first apply the downgrade rule in [SKILL.md](SKILL.md). Re-run the **Branch** `state` command immediately before committing; if `branch=` equals the Step 0.6 default, downgrade and stop. The up-front finish choice authorizes the commit when `confirm=no`; it never overrides the safety checks.

Read [../commit/SKILL.md](../commit/SKILL.md) and follow these steps with the overrides below:

- Step 1 **Inspect (parallel)** and Step 2 **Classify changes**: inspect the working tree, index and recent history, then classify the eligible change.
- Step 4 **Draft commit message**: follow its message rules, including Conventional Commits, lowercase imperative description, maximum 72-character summary, no trailing period, and no AI attribution or trailers.
- Step 9 **Stage and commit (sequential)**: use the explicit eligible paths below, then create one commit and inspect status.

Skip Step 3 **Split plan (if needed)**: make a single commit using the most significant change type. Skip Step 5 **Propose version bump**, Step 6 **Update CHANGELOG**, and Step 7 **Update README**: finishing never adds version or documentation edits.

Replace Step 8 **Present for review** with no prompt when `confirm=no`. When `confirm=yes`, ask one approve / revise / cancel question showing the branch, draft message and exact proposed staged paths. Revise updates the proposal and returns to this approval gate; cancel sets `finish=none` and stops before commit.

Build the staging set from every changed path, tracked or untracked, in `git status --porcelain --untracked-files=all`, including deletions and both sides of renames. Apply these exclusions:

- Never stage foreign paths from Step 0.6, even if the user allowed implementation to continue with them present.
- Never stage `docs/brainstorms/**` or likely secrets (`.env`, credentials, tokens), per the commit skill's **Preconditions**.
- Never stage `.claude/tmp/**` (`/execute-plan` run files), tracked or untracked.
- Include `docs/plans/**` only for `plan=keep`, only when the file belongs to this change, and only when `git check-ignore -q <path>` returns 1 (not ignored). Apply the same choice and ignore check to the plan's sibling `.notes.md` file (replace `.md` with `.notes.md`).
- For `plan=drop`, leave the plan and its notes uncommitted; do not delete them or create a removal commit.

Use path-specific adds from the repo root, not `git add -A` or `git add .`. Check the staged-path list before commit so excluded content cannot ride along in the index. If excluded paths are already staged, downgrade and report rather than committing or silently unstaging someone else's work. If no eligible changes remain, do not create an empty commit. Continue to **Push** only when Step 0.6 approved reusing a branch with commits ahead of `origin/<default>`; otherwise report that there is nothing to commit and stop (no push, no PR).

A rejecting hook overrides Step 10 **Hook failure and amend**: do not fix and retry, amend, or use `--no-verify`. Downgrade, report the hook output, and do not push or open a PR.

## Push

Only for `finish=push` or `finish=pr`, after the commit step creates a commit, or when a Step 0.6-approved reused branch has commits to ship, re-run the **Branch** `state` command. Refuse to push if `branch=` equals the Step 0.6 default; stop and report.

```bash
git push -u origin HEAD
```

If the push is rejected or otherwise fails, stop and report the error. Do not pull, rebase, retry with force, or proceed to PR creation. Never force-push, amend, or bypass hooks. For `finish=push`, report the branch, commit SHA and push result, then finish.

## Pull request

Only for `finish=pr`, after a successful push, read [../gh-create-pr/SKILL.md](../gh-create-pr/SKILL.md) and follow:

- Step 1 **Inspect (parallel)**: resolve the base, inspect the branch diff and discover any existing PR.
- Step 5 **Draft PR title and body**: use its title, summary, test-plan and repository-template rules. List kept plans and their notes under planning artifacts only when committed at `HEAD`. A plan excluded by `plan=drop` was never committed: do not invent a dropped-plan blob permalink.
- Step 8 **Create PR (sequential)**: create against the resolved default branch, or report the existing PR URL without creating a duplicate or editing its body.
- Step 9 **Watch CI status**: watch within its time limit, then report the PR URL and CI state.

Skip Step 2 **Commit uncommitted work (if any)**: deliberately excluded artifacts may leave the tree dirty; they are outside this PR. Skip Step 3 **Planning-artifacts gate**: Keep/Drop was already decided up front, and a dropped plan was never committed. Skip Step 4 **Ensure feature branch**: Stage 4 already ensured it. Skip Step 7 **Push (sequential)**: the push above already succeeded.

Skip Step 6 **Present for review** when `confirm=no`; the up-front `finish=pr` choice authorizes PR creation. When `confirm=yes`, follow its approve / revise / cancel gate for the branch, title and body; cancellation stops PR creation but does not undo the commit or push.

For Step 9 **Watch CI status**, investigate failures using failed-job logs and report the failing checks, errors, likely cause and recommended next step. Never auto-fix CI, create follow-up commits, push again or rerun jobs during this finish stage. Report pending, skipped or absent checks without claiming success. Do not merge.
