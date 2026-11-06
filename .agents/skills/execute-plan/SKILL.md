---
name: execute-plan
description: >-
  Execute a structured implementation plan produced by /make-plan, delegating
  implementation to a subagent and iterating with an independent review
  subagent until quality criteria are met. Args: [optional plan file path or
  plan slug]. Use when the user asks to execute a plan or mentions
  /execute-plan.
disable-model-invocation: true
---

# execute-plan

Execute a structured plan. Orchestrate: locate plan → ensure Execution map → pre-flight → **wave-delegated implement** (parallel `generalPurpose` Tasks, tier per step) → **independent** review loop (mid intermediate, **top** final) until no `blocking`/`important` remain and agreed tests pass.

**References (read when needed):** [implementer.md](implementer.md) · [review.md](review.md) · [execution-status.md](execution-status.md)

## Preconditions

**Requires Agent mode.** If you are in Plan or Ask mode, stop and tell the user to switch to Agent mode before continuing.

**Orchestrator model (top-tier).** Session/Task tiers: [model-tiers.md](model-tiers.md) (`top`/`mid`/`low`). Warn once if the session is below top-tier and recommend switching before delegating. The orchestrator does **not** edit implementation source files — only locates the plan, manages the map, dual-writes plan status/log (see Status audit), launches Tasks, and summarizes. Plan-file map and status edits remain allowed.

## Step 1 — Locate the plan

Args are a path under `docs/plans/**` or a plan slug/timestamp. Resolve slugs against `docs/plans/` only; use `Glob` for the most recent match if needed.

If no argument, list `docs/plans/*.md`, then ask the user to pick (`AskQuestion` when available).

If the user points at `.cursor/plans/`, stop and tell them to promote via `/make-plan` into `docs/plans/**` first. If missing/unreadable, stop. Do **not** execute raw `~/.claude/plans/` — require a fleet plan under `docs/plans/**`.

## Step 2 — Read and parse the plan

Extract: Purpose, Scope, Assumptions, Dependencies, Implementation steps, Execution map (IDs, tiers `haiku`/`auto`/`opus`, waves, depends-on), Files to modify/create, Verification, Success criteria, Rollback, Risks.

If a section is ambiguous or referenced files do not exist, ask a focused clarifying question before proceeding. Treat legacy tier `sonnet` as alias of `auto`.

## Step 2.5 — Refuse if blocked or incomplete

Hard stop (not a clarifying question) if any of:

- Explicit unresolved **"Blocked on"** note
- Missing **Success criteria** section
- Missing **Verification** section

State which condition triggered and the next step: resolve the blocker, or `/make-plan update <path>`, then re-invoke `/execute-plan`. Ambiguous *content* inside an existing section → clarifying question (Step 2); missing section / unresolved blocker → hard stop.

## Step 2.75 — Execution map (required before implement)

Do **not** invent silent sequential `auto` steps and proceed. An Execution map must exist and be validated before Step 4.

### Map present

1. **Validate:** every Implementation step has a map ID (or clear sub-bullet coverage); tiers only `haiku` | `auto` | `opus` (after `sonnet`→`auto`); same-wave rows do not share write paths (conflict → ask to re-wave or serialize).
2. Use the map as the schedule. Do **not** rewrite unless the user asks.
3. **Hard follow:** never collapse the map into a single whole-plan Task; never invent extra implementation steps outside the map without explicit user approval.

### Map absent

1. Draft a map biased to **smallest mechanical units**: prefer `haiku` for tightly scoped work; `auto` for judgment-heavy bulk; avoid `opus` for implement rows; prefer parallel waves when write paths do not overlap; split coarse steps into map rows (and split plan bullets if needed).
2. Present for confirmation (`AskQuestion`: approve / revise / abort).
3. **On approve:** write `## Execution map` into the **same plan file** (after Implementation steps if present), then re-read.
4. **On revise:** iterate until approved — do not start Step 3/4 until confirmed. **On abort:** stop.
5. If Implementation steps are too coarse for a safe map, offer `/make-plan update <path>`; default remains in-place map (+ split bullets as needed).

Re-run validation after confirm/persist (or when the map was already present); fix or ask before Step 4.

## Step 3 — Pre-flight checks

1. Project root: `git rev-parse --show-toplevel` (else cwd).
2. `git status --short` and `git diff HEAD` for baseline.
3. If working tree not clean, warn and ask proceed / stash / abort.
4. Determine test / build / lint / type-check tooling from manifests, Verification, and common config.
5. Build a **Quality toolkit** for every implementation Task: unit/integration commands (prefer path-scoped), lint, type-check/format-check, and **Coverage** (if Verification says available: command + target, else plan target or **90%**; if not available, do not invent a gate).
6. **Optional:** if the plan was not stress-tested via `/critique plan`, offer that first; do not block if they decline.

## Status audit (orchestrator dual-write)

`Read` [execution-status.md](execution-status.md) for schema, `%` formula, placement, and dual-write rule. Dual-write YAML frontmatter + `## Execution log` in **one edit** at:

1. **Start** — after Step 3 (and map validation) pass, before or as Step 4 begins: ensure frontmatter + log exist; `status: in-progress`; `started_at` if unset; scoped rows `pending` (leave prior `done` on resume). Confirm with the user before resetting an already-`completed` plan.
2. **After each wave** (success or wave-failure stop): update those row statuses + frontmatter `%` / `updated_at`.
3. **Terminal** — at Step 6 (or earlier abort/hard stop): set overall `status` (`completed` / `partial` / `failed` / `aborted`), `completed_at` iff `completed`, final `%`, one `### Run …` stanza with its `Run:` line, and append one `runs:` entry (fields in [execution-status.md](execution-status.md) § Run records): `backend: claude-code`; `model_requested` / `model_resolved` = the distinct implementer models in run order (resolved = what the Tasks actually ran on); `effort` = their tier efforts; `review_findings` = `blocking` + `important` findings from every review pass this run; `fix_loops` = fix rounds after review; `fallback` = `null` or the reason (for example a `haiku` row that fell back to `mid`).

## Step 4 — Delegate implementation by waves

Do **not** send the whole plan to a single subagent. Orchestrate from the validated Execution map only. For quality bar, Task prompt, and full verification details, `Read` [implementer.md](implementer.md).

### Model resolution (per map tier) — implementers

Resolve map tiers `haiku`/`auto`/`opus` via [model-tiers.md](model-tiers.md) (`low`/`mid`/`top`). Always set the model explicitly; if you can't, stop and tell the user before delegating.

### Wave schedule

1. Group map rows by **Wave** (ascending).
2. Within a wave, launch **one `Task` (`generalPurpose`) per step** with no unmet `Depends on` — typically all same-wave rows **in parallel**.
3. Wait for the wave. **Orchestrator quality gate (lint before tests):** each step report must show **lint+tests status** — (a) lint/type-check results when those tools exist, (b) tests added/updated or justified skip, (c) no failing commands in scope. On failure, **stop the wave** — do not start later waves; dual-write status (Status audit #2) then ask or resume that step. If any step reports unresolved issues, ask the user how to proceed before continuing to review.
4. Next wave only after every prior step passed the gate; dual-write status after each successful wave (Status audit #2).
5. After the **last** wave, run the full Verification suite once via a mid-tier (`auto`) Task unless the last wave already ran an equivalent full suite successfully.

Track each Task's agent ID, map tier, and resolved platform model for the final report and resume-on-fix.

## Step 5 — Review loop (independent review; final pass top-tier)

`Read` [review.md](review.md) and follow its loop.

## Step 6 — Final summary

Dual-write terminal status first (Status audit #3). Present: plan path (note if map was drafted/persisted this run); **audit** (`execution.status`, `progress_pct`, `steps_done`/`steps_total`, `last_skill`); files changed; test/coverage results; **orchestrator** model; **each implementer/fix Task** (map ID, tier, resolved model, lint+tests status); **each reviewer** (tier `auto` for intermediate passes, `opus` for the final pass or escalation; resolved model); whether the **final top-tier review converged** (`clean` or `dirty` — `/critique change` keys off this); remaining notes; clear statement that changes are **uncommitted**.

Offer: `/critique change` · `/commit` · `/gh-create-pr` (clean tree / commits first). Do not commit or push unless explicitly asked.

## Constraints

- Implementers and the review subagent must be **different agents** — never resume an implementer for review; never use the reviewer to apply fixes.
- Ask rather than guess when a fix is unclear.
