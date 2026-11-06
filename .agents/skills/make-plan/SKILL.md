---
name: make-plan
description: >-
  Prompt for a task's purpose and build a structured implementation plan,
  grounded in codebase exploration and prior plans. Args: [update]
  [optional task description or path to existing plan]. Use when the user asks
  to plan a task, draft an implementation plan, or mentions /make-plan.
disable-model-invocation: true
---

# make-plan

Build a structured implementation plan for a task. Prompt for purpose, clarify scope, explore the codebase and recent plans, then draft and persist the plan to `docs/plans/**`. Can also update an existing plan.

**References (read when needed):** [plan-template.md](plan-template.md) · [drafting-rules.md](drafting-rules.md) · [brainstorm-handoff.md](brainstorm-handoff.md) · [execution-status.md](../execute-plan/execution-status.md) (execution scaffold SoT)

Session/Task tiers: [model-tiers.md](model-tiers.md) (`top`/`mid`/`low`). `/make-plan` needs **top**; warn once and recommend switching if below top — do not silently draft a thin plan. Execution-map rows stay haiku-biased (`haiku`/`auto`/`opus`); that does not lower the planner session.

## Built-in Plan vs this skill

Prefer this skill's `docs/plans/**` artifact for `/execute-plan` / `/critique plan`. If a Cursor (`~/.cursor/plans/`) or Claude (`~/.claude/plans/`) plan already exists, **promote/copy** it into `docs/plans/` (fleet template) instead of rediscovering — never run `/execute-plan` on those raw paths. Suggest `/brainstorm` first if approaches are still open; `/make-plan` never implements.

## Step 1 — Determine intent: new plan vs. update

Parse the user's slash-command or message args:

1. **Update mode** — if args start with `update` or `revise` (case-insensitive), strip the keyword and treat the remainder as a path or slug to an existing plan file. Read that plan and skip to "Update mode" below.
2. **Existing plan path** — if args are a single argument that is an existing file path under `docs/plans/` (or resolves to one via `Glob`), ask: "Update this plan, or use it as context for a new plan?" Default to **Update**.
3. **Brainstorm handoff** — if args contain `Scope:`, `Target Phase 1:`, `Brainstorm:`, or a `docs/brainstorms/*.md` path, parse once per [brainstorm-handoff.md](brainstorm-handoff.md); Step 2 skips duplicates.
4. **New plan** — otherwise use args as the task description and proceed to Step 2.

If no arguments were given, use `AskQuestion` when available (otherwise ask conversationally):
- **What do you want to build or accomplish?** (free-text via "Other", plus 2–4 example options inferred from the current project)
- Optional follow-up: **Is this a new plan or an update to an existing plan?**

## Step 2 — Requirements & scope

After Step 1, detect whether a brainstorm artifact already answers Goal / requirements:

- **Has brainstorm handoff** (from Step 1) — `Read` the brainstorm file when a path is present; ask only remaining gaps (handoff file owns the skip list).
- **No brainstorm artifact** → before codebase exploration (Step 3), run this step as a mandatory gap-fill interview.

`AskQuestion` when available (else conversational): one call per facet, ≤4 options + "Other". Ask **only gaps** among Goal, must-haves, non-goals (→ Out of scope), constraints (→ Assumptions/Risks), in/out of scope, success criteria, assumptions. Skip answers already known from handoff, an existing plan being updated, or an obvious codebase fact.

Do **not** ask for a **coverage target** here — ask only after Step 3's probe finds tooling (see [drafting-rules.md](drafting-rules.md)).

Do **not** draft Implementation steps or the Execution map until Goal and must-haves are captured. If the user is still choosing among approaches, recommend `/brainstorm` and stop — do not force a thin plan.

## Step 3 — Explore the codebase and prior plans

Use `Read`, `Grep`, and `Glob` **in parallel** to find relevant files, trace consumers, note patterns/tests, check prior art and recent plans, and **scan architecture docs** + **probe test coverage** (full rules in [drafting-rules.md](drafting-rules.md)).

Run `git status`, `git diff`, and `git log --oneline -10`. Also `Glob docs/plans/*.md` and read the 2–3 most recent plans; note conflicts/related work. Record architecture-doc paths for the draft.

Do not over-explore. Focus on what the plan needs to be concrete and grounded.

## Step 4 — Draft the plan

`Read` [plan-template.md](plan-template.md) and write the plan in that structure. Apply [drafting-rules.md](drafting-rules.md) for coverage, architecture-doc steps, tiers (`haiku` | `auto` | `opus`; never `sonnet`), and waves.

**Execution map** is required for multi-step plans. Ground every step and file reference in exploration — verify unsure paths with `Glob` or `Read` before including them.

## Step 5 — Write or update the plan file

### New plan

Project root: `git rev-parse --show-toplevel` (else cwd). Slug: kebab-case from title; strip common stopwords. Timestamp: `date +%y%m%d%H%M`. Write `<project-root>/docs/plans/<yymmddhhmm>-<slug>.md` (create `docs/plans/` if needed).

### Update mode

1. `Read` the existing plan; present briefly; ask what to change (or apply the change description from args).
2. Clarify with `AskQuestion` if needed.
3. If the update changes system shape or Scope, re-run the architecture-doc scan and adjust the docs Implementation/map step or justified skip ([drafting-rules.md](drafting-rules.md)). Wording-only edits may keep the prior Architecture docs note.
4. Write back to the **same path**; keep the filename unless the title/slug is badly misleading.
5. Present and offer next steps (Step 6–7).

## Step 6 — Present the plan

Show the full plan in the chat and share the file path.

## Step 7 — Offer next steps

Offer: **Refine** · **Review** (`/critique plan`) · **Proceed** (`/execute-plan <path>`, Agent mode). Wait for the user's choice. Do not start implementing unless explicitly asked.

## Constraints

- Never implement — only write `docs/plans/**`; no commit/push. Ask rather than guess; keep plans minimal.
- Plans are committable; `/gh-create-pr` asks Keep/Drop for each plan on the branch (via `/commit` when the repo tracks `docs/plans/**`).
- Preserve filename on update unless the title changed drastically.
