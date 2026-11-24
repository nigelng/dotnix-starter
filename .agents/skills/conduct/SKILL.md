---
name: conduct
description: >-
  Conduct an idea through brainstorm, make-plan, critique plan, execute-plan,
  and critique change, then branch, commit, push, or open a PR per the chosen
  finish mode. Args: [idea | docs/brainstorms/<f>.md | docs/plans/<f>.md]
  [finish=push|pr|none] [plan=keep|drop] [confirm=yes|no] [runner=<policy>].
  Use when the user asks for the whole lifecycle chain or mentions /conduct.
disable-model-invocation: true
---

# conduct

Take an idea to a reviewed change through the sibling skills, with two human gates and an up-front finish mode. Thin conductor: read each sibling skill and follow it in-session, with only the linked overrides. The siblings disable model invocation; do not invoke them as slash commands.

**References (read when needed):** [stage-overrides.md](stage-overrides.md) | [finish.md](finish.md) | [model-tiers.md](../make-plan/model-tiers.md)

`<skill-dir>` is this file's absolute directory. Sibling `model-tiers.md` and `execution-status.md` copies are identical; read each once.

## Preconditions

**Requires Agent mode.** In Plan or Ask mode, stop and tell the user to switch.

**Session needs top-plan.** Warn once and recommend switching if below the host's **top-plan** pin (`tiers.sh resolve <host> top-plan`); unknown session model → say so in one line, continue. A top-plan session meets **top-review** for the execute orchestrator. Preserve each sibling's independent-review requirements (with `/critique plan`'s Devin in-session fallback) and explicit Task-model requirements; report intended tier and resolved model, never an invented resolution.

Work in the project root (`git rev-parse --show-toplevel`). The up-front `finish=push` or `finish=pr` choice is the user's explicit request to commit/push under this skill, subject to Gate B, safety checks, and the downgrade rule, and never permission to bypass a failed gate.

## Step 0 - Router

Parse and remove `finish=`, `plan=`, `confirm=`, and `runner=` before routing the remaining argument. Keep the runner policy for Stage 2. Resolve paths with `Read`/`Glob`; never guess a file. A `*.notes.md` file is not a plan. Missing, ambiguous, or unsupported artifact status: ask first.

| Argument / artifact | Start at |
| --- | --- |
| `docs/plans/*.md`, `execution.status: not-started` | Stage 3, unless **Fresh Gate B** below passes |
| `docs/plans/*.md`, `execution.status: in-progress`, `partial`, or `failed` | Stage 4, resuming the existing plan |
| `docs/plans/*.md`, `execution.status: completed` | Stage 5 |
| `docs/brainstorms/*.md` | Stage 2, using the file's saved `/make-plan` prompt as arguments |
| Free text or no argument | Stage 1 |

Read `execution.status` from YAML frontmatter, not the execution-log table. When routing an existing plan, read its Purpose, Scope, Assumptions, Execution map, Verification, Success criteria, and Risks before continuing.

**Fresh Gate B (`not-started` only),** before Step 0.6: `bash <skill-dir>/../execute-plan/scripts/plan-status.sh lock --gate <plan>`. Pass only on exit 0 **and** an ISO-8601Z stdout (`YYYY-MM-DDTHH:MM:SSZ`): print it as `gate_b_at` and start at Stage 4. Anything else (mismatch, missing `gate_b_sha`, no `plan_sha`, exit 2, other stdout) stays at Stage 3 and still requires Gate B. Show stderr when present. This is not the resume hard stop. Do not hand-edit `plan_sha` or `gate_b_sha`.

**Resume approval** for `in-progress`, `partial`, `failed`, or `completed`, before Step 0.6 uses the **Files** column and before any stage: `bash <skill-dir>/../execute-plan/scripts/plan-status.sh lock <plan>`. Stdout `ok`: Gate B already passed; do not re-run ideation or re-approve unchanged executed work. Exit 0, stdout `legacy` (stderr WARN is not a stop): present Gate B before the routed stage. Exit 3: hard stop; quote stderr (`plan body changed since approval; re-approve with /make-plan update <path>`); no stage runs and nothing is committed. Exit 2: stop and show stderr. No argument bypasses Gate B.

## Step 0.5 - Up-front choices

Before any stage runs, ask all unanswered choices in **one batch** with the question tool (`AskQuestion`/`AskUserQuestion`/`ask_user_question`) when available, otherwise conversationally. Skip only choices already supplied by arguments:

- **Finish:** `push` (default: feature branch + commit + push), `pr` (push + PR + CI watch), or `none` (stop ready-to-PR, uncommitted).
- **Plan file:** `keep` (default: include eligible plan files in the commit) or `drop` (leave them uncommitted; do not delete them).
- **Confirm before commit:** `no` (default: no further commit approval) or `yes` (show the proposed commit and ask once before committing).

State defaults and their effects, especially commit/push authority. Choices live **in chat only**: never write them into the plan body, which would break the plan lock. A resumed invocation asks again for choices not given in its arguments; do not infer finish permission from a saved plan.

## Step 0.6 - Preflight + baseline

Complete all checks before running any stage, including on resume:

1. **Default branch and access.** Resolve the default with `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; fall back to `git symbolic-ref --short refs/remotes/origin/HEAD` and strip `origin/`. Do not assume `main` or `master`. For `finish` other than `none`, `git remote get-url origin` must succeed; for `finish=pr`, `gh auth status` must also succeed. If the default cannot be established or required access is unavailable, tell the user **now** and set `finish=none`.
2. **Baseline and ownership.** Record the HEAD SHA (`git rev-parse HEAD`), current branch, and `git status --porcelain`, including staged and untracked paths. **Conductor-owned paths** are `docs/brainstorms/**`, `docs/plans/**`, and, when resume `lock` printed `ok`, every path in that plan's Execution-map **Files** column. Every other dirty path is **foreign**. Show those paths and ask **stash / continue with `finish=none` / abort**. Stash only on explicit selection and preserve the stash; continue means preserve the files, never stage them; abort stops the run. Retain the baseline foreign-path list for execution and finishing. Later work must not retroactively authorize foreign changes.
3. **Existing branch history.** With `origin` and a known default, run `git fetch origin <default>` before comparing. If on a non-default branch with commits ahead of `origin/<default>`, count them and ask once: **reuse `<branch>` (its N existing commits ship too) / continue with `finish=none` / abort**. Do not silently publish those commits. If the comparison fails, report it and use `finish=none`.

Ownership is permission to continue, not a staging allowlist: brainstorms, secrets, foreign files, and ineligible/dropped plans remain excluded at finish. Keep baseline evidence in chat, not the locked plan body.

## Stage 1 - Brainstorm

`Read` [../brainstorm/SKILL.md](../brainstorm/SKILL.md) and follow it with [stage-overrides.md](stage-overrides.md#brainstorm) section **Brainstorm**.

Pass the idea as arguments, or let the sibling gather it when absent. Preserve the Goal brief, roadmap, saved artifact, and verbatim handoff prompt. If its **When NOT to brainstorm** decision selects planning, continue to Stage 2 with the one-line prompt under the override; do not offer built-in Plan.

### Gate A

After the brainstorm is persisted, replace the sibling's next-step offer with:

- **Refine** - return to brainstorming; preserve and update the same artifact.
- **Continue to plan** - pass the saved `/make-plan` prompt to Stage 2.
- **Stop** - stop with the saved artifact and final summary; nothing to finish.

Wait for the choice. Skip this gate only when routing directly to a later stage or taking the sibling's explicit planning path; report why.

## Stage 2 - Make-plan

`Read` [../make-plan/SKILL.md](../make-plan/SKILL.md) and follow it with [stage-overrides.md](stage-overrides.md#make-plan) section **Make-plan**.

Arguments are the brainstorm handoff prompt (including when resumed from its saved file), or the user's text on the direct planning path. Forward `runner=<policy>` when given. Capture the plan path, keep its lock metadata intact, and go to Stage 3 instead of offering standalone next steps.

## Stage 3 - Critique plan

`Read` [../critique/SKILL.md](../critique/SKILL.md) and follow it in **plan mode** on the plan path with [stage-overrides.md](stage-overrides.md#critique-plan) section **Critique plan**.

Skip the critique only when the plan records `Plan size: small`; record that reason. Any plan edits follow the sibling's re-stamping rules. Show the critique verdict and remaining items at Gate B; a Rework verdict recommends **Refine**, not silent execution.

### Gate B

**Hard approval gate, never skipped by arguments.** Present a short summary, not the full plan: Purpose, Scope, the Execution map table, the critique verdict and remaining items (or the small-plan skip), and the current finish choices, plus the plan path. Ask:

- **Approve** - `not-started`: run `approve`, then offer the continue choice. Resumed `legacy`: skip `approve` (its record is for `not-started` only); go to the routed stage.
- **Refine** - follow Stage 2 in make-plan **update** mode on the same path, then return to Stage 3 and this gate.
- **Abort** - stop; no implementation, commit, push, or other finish action.

Wait for explicit approval. An approval stamp alone is not this gate. Already passed only when resume `lock` printed `ok`, or **Fresh Gate B** printed `gate_b_at`.

`bash <skill-dir>/../execute-plan/scripts/plan-status.sh approve <plan>`. Exit 0 writes `gate_b_sha` and `gate_b_at`; do not hand-edit them or `plan_sha`. Exit 3 writes nothing: quote stderr if any (`plan body changed since approval; re-approve with /make-plan update <path>`). No `plan_sha` is also exit 3: **Refine** so `stamp` runs, then return here. Exit 2: stop and show stderr. After exit 0:

- **Continue here** - the routed stage (Stage 4 after `approve`) in this session.
- **Continue in a fresh session** - recommended unless `Plan size: small`; on a v2 map that passes `plan-status.sh rows --lint`, a `mid` session suffices for Stage 4. Print `/conduct <path> finish=<finish> plan=<keep|drop> confirm=<confirm>` and stop. That session starts at Stage 4 only when `lock --gate` passes.

## Stage 4 - Execute-plan

**On entry, before execution**, from **Continue here**, a passing `lock --gate`, or the resume router: if `finish` is not `none`, follow [finish.md](finish.md#branch) **Branch**. If `finish=none`, do not create a branch.

`Read` [../execute-plan/SKILL.md](../execute-plan/SKILL.md) and follow it with [stage-overrides.md](stage-overrides.md#execute-plan). Do not implement in the conductor.

On a clean final review (`clean`, including the in-host loop when the strongest Review is `mid` or `none`) with `execution.status` `completed`, record in chat, not the plan: `bash <skill-dir>/../commit/scripts/git-preflight.sh fingerprint` (`fingerprint=` and `head=`). On `dirty`, `partial`, or `failed`, record nothing and stop before Stage 5.

## Stage 5 - Critique change

`Read` [../critique/SKILL.md](../critique/SKILL.md) and follow it in **change mode** with [stage-overrides.md](stage-overrides.md#critique-change).

`state` fetches `origin` when a remote URL exists. Stderr `WARN: git fetch failed`, or a failed `git merge-base origin/<default> HEAD`, stops this stage and triggers the downgrade rule. Never use a stale or narrower diff. `<default>` is the Step 0.6 branch; `default=` from `state` may be empty and does not replace it. The review base is that merge-base SHA. With no `origin`, the base is the HEAD SHA recorded at Step 0.6. Pass the base ref to each review Task. The Task (Devin: the session, per hosts.md) runs `git diff <base>` and lists untracked files from `git ls-files --others --exclude-standard`. Do not paste the diff. Exclude `docs/brainstorms/**` and `docs/plans/**` from the tracked diff and from the untracked input. `fingerprint=` and `head=` are the Stage 5 comparison against the fingerprint Stage 4 recorded.

Skip **Phase A** only when all three hold: this session recorded Stage 4's `fingerprint=` and `head=`; a new `fingerprint` run prints the same values; and `head=` equals that review base. Otherwise run **Phase A** (at most two mid-tier reviews) and **Phase B** (at most one top-tier escalation, only when triggered). A skipped Phase A counts as ship-ready, so Phase B is not triggered. When Phase A is skipped and Stage 4's final review was a clean `top@*`, skip the closing top pass and run only the security pass. Keep the closing top pass when Stage 4's strongest review was `mid` or `none`. The security pass always runs.

## Stage 6 - Finish

Apply the downgrade checks **before staging or committing**. For a Stage 5 resume, inspect the saved execution/review evidence too; do not infer clean review from `completed` alone.

- `finish=none`: stop ready-to-PR if checks are clean, leaving changes uncommitted. Report unfinished work, never as ready.
- `finish=push`: follow [finish.md](finish.md#commit) **Commit**, then [finish.md](finish.md#push) **Push**, sequentially.
- `finish=pr`: follow **Commit**, then **Push**, then [finish.md](finish.md#pull-request) **Pull request**, including CI watch.

## Downgrade rule

Set **`finish=none`**, stop before commit, preserve the working tree, and report why if any condition holds:

- Execute-plan's terminal status is not `completed`.
- The final execution review is `dirty`, or status is `partial` after `terminal --deferred-review` (a printed `/delegate:review` line).
- Critique change leaves any `blocking` or unresolved `important` finding.
- The plan's Verification fails after critique fixes.
- Stage 5 cannot resolve its review base (failed `git fetch` or `git merge-base`), so the whole branch was not reviewed.
- A commit hook rejects the commit: no retry, amend, or hook bypass.
- The current branch is the default branch at Stage 6.

Do not treat missing review evidence as a clean result. A downgrade never converts failure into success or authorizes a partial commit. If a failure occurs after a commit/push already succeeded, report the actual state; do not imply it was undone.

## Final summary

On completion, stop, or downgrade, report concisely:

- Stages run and skipped, with reasons; brainstorm/plan artifact paths.
- Model per stage and per subagent: intended tier plus resolved model.
- Execution status, review verdicts, remaining findings, and Verification results.
- Branch, commit SHA (or not committed), push result (or not pushed).
- PR URL and CI state when applicable; no merge.
- Downgrade reason, any Dispatch lines, and the next safe action if unfinished.

## Safety (never)

- Commit or push to the default branch.
- Force-push, use `--no-verify`, or amend.
- Commit `docs/brainstorms/**` or secret/credential files.
- Stage foreign paths identified in Step 0.6, or include pre-staged foreign content in the conductor's commit.
- Bypass plan approval/lock, independent review (`/critique plan`'s Devin fallback is not a bypass), failed verification, or a downgrade to satisfy the requested finish mode.
- Delete dropped plans, discard foreign work, auto-fix CI, or merge a PR.
