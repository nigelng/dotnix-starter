---
name: make-plan
description: >-
  Prompt for a task's purpose and build a structured implementation plan,
  grounded in codebase exploration and prior plans. Args: [update]
  [runner=<policy>] [optional task description or path to existing plan].
  Use when the user asks to plan a task, draft an implementation plan, or
  mentions /make-plan.
disable-model-invocation: true
---

# make-plan

Build a structured implementation plan for a task. Prompt for purpose, clarify scope, explore the codebase and recent plans, then draft and persist the plan to `docs/plans/**`. Can also update an existing plan.

> **Under /conduct:** Step 7 is replaced by the conductor; see [../conduct/stage-overrides.md](../conduct/stage-overrides.md#make-plan). Standalone behaviour is unchanged.

**References (read when needed):** [plan-template.md](plan-template.md) · [drafting-rules.md](drafting-rules.md) · [brainstorm-handoff.md](brainstorm-handoff.md) · [execution-status.md](../execute-plan/execution-status.md)

Warn once and recommend switching if below the host's **top-plan** pin (`tiers.sh resolve <host> top-plan`), unless the host's rules allow a `mid` + advisor run for a plan the user declared small (Claude Code overlay); if the session model is unlisted, say so in one line, continue (see [model-tiers.md](model-tiers.md)). Map rows use v2 tiers (`top`/`execute`/`mid`/`low`) without lowering the planner session.

## Built-in Plan vs this skill

Prefer this skill's `docs/plans/**` artifact for `/execute-plan` / `/critique plan`. If a Cursor (`~/.cursor/plans/`) or Claude (`~/.claude/plans/`) plan already exists, **promote/copy** it into `docs/plans/` (fleet template) instead of rediscovering — never run `/execute-plan` on those raw paths. Suggest `/brainstorm` first if approaches are still open; `/make-plan` never implements.

## Step 1 — Determine intent: new plan vs. update

Parse the user's slash-command or message args. If they include `runner=<policy>`, take that as the Runner policy and strip it before the cases below. It is not a task description or a plan path. `<policy>` is `auto`, `pin <tool>`, `order <list>`, or `round-robin [<list>]` (comma-separated).

1. **Update mode** — if args start with `update` or `revise` (case-insensitive), strip the keyword and treat the remainder as a path or slug to an existing plan file. Skip to "Update mode" below (its step 1 reads the plan).
2. **Existing plan path** — if args are one existing file path under `docs/plans/` (or resolve to one via `Glob`), ask: "Update this plan, or use it as context for a new plan?" Default to **Update**.
3. **Brainstorm handoff** — if args contain `Scope:`, `Target:`, `Target Phase 1:`, `Brainstorm:`, or a `docs/brainstorms/*.md` path, parse once per [brainstorm-handoff.md](brainstorm-handoff.md); Step 2 skips duplicates.
4. **New plan** — otherwise use args as the task description and proceed to Step 2.

If no arguments were given, use the question tool (`AskQuestion`/`AskUserQuestion`/`ask_user_question`) when available (otherwise ask conversationally):
- **What do you want to build or accomplish?** (free-text via "Other", plus 2–4 example options inferred from the current project)
- Optional follow-up: **Is this a new plan or an update to an existing plan?**

## Step 2 — Requirements & scope

**Prefetch** — right after Step 1, one parallel batch (none of it needs the user's answers): `git status`, `git diff`, `git log --oneline -10`; `bash <skill-dir>/../execute-plan/scripts/plan-status.sh recent docs/plans; echo "exit=$?"` (`<skill-dir>` = this `SKILL.md`'s absolute directory); the architecture-doc `Glob`s and coverage probe; `Read` of [plan-template.md](plan-template.md), [drafting-rules.md](drafting-rules.md) and any brainstorm file. Skip questions these answer; never re-run them.

Then detect whether a brainstorm artifact already answers Goal / requirements:

- **Has brainstorm handoff** (from Step 1) — ask only remaining gaps (handoff file owns the skip list).
- **No brainstorm artifact** → before codebase exploration (Step 3), run this step as a mandatory gap-fill interview.

The question tool when available (else conversational): batch up to 4 independent questions per call, each with 2–4 options plus "Other". Split only questions that depend on an earlier answer. Ask **only gaps** among Goal, must-haves, non-goals (→ Out of scope), constraints (→ Assumptions/Risks), in/out of scope, success criteria, assumptions. Skip answers already known from handoff, an existing plan being updated, or an obvious codebase fact.

**Runner policy.** If `runner=<policy>` was given, or the user already stated routing, record that policy and do not ask. Otherwise ask once (the question tool when available, else conversational; it may share a batch with the gaps above): **Runner policy**, options `auto` / `pin <tool>` (suggest `pin subagent`) / `order <list>` / `round-robin [<list>]`. Delegate runners need a Claude Code host. Record the answer under Assumptions per [Runner policy](drafting-rules.md#runner-policy).

**Coverage target** — only if the probe found tooling and the target is unclear; same batch as the gaps.

Do **not** draft Implementation steps or the Execution map until Goal and must-haves are captured. If the user is still choosing among approaches, recommend `/brainstorm` and stop — do not force a thin plan.

## Step 3 — Explore the codebase and prior plans

One parallel batch of `Read`/`Grep`/`Glob`: relevant files, consumers, patterns/tests, prior art, scanned architecture docs, prior plans (prefetch `recent` printed `exit=3` `tie` → ask; `exit=2` → none; `exit=0` → its plan plus up to two older non-notes plans; do not sort raw filenames). Batch follow-ups too. Note conflicts and architecture-doc paths.

Do not over-explore. Focus on what the plan needs to be concrete and grounded.

## Step 4 — Draft the plan

Write the plan in the [plan-template.md](plan-template.md) structure. Apply [drafting-rules.md](drafting-rules.md) for coverage, architecture-doc steps, map v2 (tiers `top` | `execute` | `mid` | `low`; never `sonnet`), **Runner policy**, **Dispatch**, and waves (earliest its dependencies allow).

**Execution map** (v2) and **Dispatch** are required for multi-step plans. Ground every step and file reference in exploration — verify unsure paths with `Glob` or `Read` before including them.

## Step 5 — Write or update the plan file

### New plan

Project root: `git rev-parse --show-toplevel` (else cwd). Slug: kebab-case from the title; strip common stopwords. When a brainstorm handoff names a brainstorm file, reuse that file's slug with its date or timestamp prefix removed ([brainstorm-handoff.md](brainstorm-handoff.md)). Write `<project-root>/docs/plans/$(date +%Y-%m-%d)-<slug>.md` (create `docs/plans/` if needed). If that path exists, append `-2`, then `-3`, and so on, before `.md` until the name is free.

Set `created_at` once, ISO-8601Z (`date -u +%Y-%m-%dT%H:%M:%SZ`), when the file is created. Never rewrite it. Keys and placement: [Plan metadata](../execute-plan/execution-status.md#plan-metadata).

Before presenting: `bash <skill-dir>/../execute-plan/scripts/plan-status.sh rows --lint <plan>`. Exit 3 → quote each `REFUSE:` line; fix when clear and lint again; if it needs a decision, report it and do not present the plan as ready. Exit 2 → stop and show stderr. Then `bash <skill-dir>/../execute-plan/scripts/plan-status.sh stamp <plan>` (again after a lint fix). A warning over 15000 → move long evidence to `<plan-file>.notes.md`. `stamp` writes `plan_sha` and `approved_at`, never `created_at`. Do not hand-edit `plan_sha`.

### Update mode

1. `Read` the existing plan, [plan-template.md](plan-template.md) and [drafting-rules.md](drafting-rules.md) in one batch; present briefly; ask what to change (or apply the change from args).
2. Clarify with the question tool if needed (same batching as Step 2).
3. If `runner=<policy>` was given, or the user asks to re-route: re-apply [Runner policy](drafting-rules.md#runner-policy) to Execution-map rows that are not `done` (no log status counts as not `done`), regenerate **Dispatch**, and update the Assumptions **Runner policy** line. Leave `done` rows unchanged.
4. Re-check architecture docs per [drafting-rules.md](drafting-rules.md) § Update documentation.
5. Write back to the **same path**. Keep `created_at` and the filename. Lint, fix, and stamp the same way as a new plan. A re-route is part of that body, so stamp it.
6. Present and offer next steps (Step 6–7).

## Step 6 — Present the plan

Show a summary (Purpose, Scope, Execution map table, remaining items) and the plan path, not the full plan.

## Step 7 — Offer next steps

Offer: **Refine** · **Review** (`/critique plan`) · **Proceed** (`/execute-plan <path>`, Agent mode). Wait for the user's choice. Do not start implementing unless explicitly asked. For small plans (see Small plans in drafting-rules.md) the offer is **Refine** · **Proceed** — Review only if asked.

## Constraints

- Never implement — only write `docs/plans/**`; no commit/push. Ask rather than guess; keep plans minimal.
- Plans are committable; `/gh-create-pr` asks Keep/Drop for each plan on the branch (via `/commit` when the repo tracks `docs/plans/**`).
- On update, keep the filename and `created_at`; stamp after the body is final.
