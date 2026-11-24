# Drafting rules (coverage, architecture docs, tiers, waves)

Read in the Step 2 prefetch or at the start of Update mode. SoT for coverage, architecture-doc, map v2, Runner policy, and wave rules.

## Execution scaffold (Step 4–5, required)

Every new plan **must** ship the execution scaffold from [plan-template.md](plan-template.md): YAML frontmatter `execution:` block with `status: not-started` and zeroed progress, plus an empty `## Execution log` placed **immediately after** `## Execution map` and **before** `## Files to modify/create`. Field meanings and update rules live in `../execute-plan/execution-status.md` (SoT); do not restate them in the plan.

## Test coverage probe (Step 2 prefetch)

Default numeric target when tooling exists but the repo has no threshold: **90%** on files the plan changes.

1. Inspect manifests/CI for coverage tooling (JS/TS `coverage`/`vitest`/`jest`/`c8`/`nyc`; Python `pytest-cov`/`.coveragerc`; Go `-cover`; Rust `llvm-cov`/`tarpaulin`; CI gates).
2. Record **Available + threshold** (command + percent), **Available, no threshold** (command; use the default above), or **Not available** (do not invent a gate; note in Verification; optional follow-up).
3. If available and the target is still unclear, ask once in the Step 2 batch: repo threshold / that default / Other.

Always record the probe under **Verification**. When available: include command + numeric target; prefer map/Implementation rows that close coverage gaps. When not: no fake percentage or command.

## Update documentation (architecture docs)

Every new plan **must** include Implementation step(s) **and** matching Execution-map row(s) to **update** relevant architecture docs (or **create** under `docs/architecture/` if the scan found none and the change affects system shape), **or** an explicit **justified skip** in Scope or Implementation.

**Scan (`Glob` in Step 2 prefetch or Update step 4; `Read` in Step 3 or Update step 4):** architecture docs. Default hints: `docs/architecture/**`, `**/ARCHITECTURE*`, `**/architecture/**`, README Architecture links, and Archify artifacts under `docs/architecture/`. Record paths for Assumptions / Dependencies / a short Architecture docs note. Prefer a canonical prose doc (e.g. `OVERVIEW`) and any diagram/path it names; else the newest `docs/architecture/**` artifact by folder timestamp; ignore conflicting historical folders.

- **Prefer updating** `docs/architecture/OVERVIEW.md` and the **canonical** Archify / diagram path from the scan over inventing parallel docs.
- **Justified skip** — allowed only for pure chore / docs-only / formatting with **no** change to: runtime topology, config contracts, control plane, trust boundaries, or subsystem ownership. One line is enough.
- **Verification** must be execute-checkable (`git diff` / Files show those architecture-doc paths changed as listed, **or** the one-line skip is present). Recording scan paths in Assumptions/Dependencies alone does **not** satisfy Verification.
- **Success criteria** must say architecture docs reflect the shape change, or that the skip is recorded.

**Changelog:** if the repo has `CHANGELOG.md`, add a step and map row for it, or a one-line justified skip.

On **update**, if the change alters system shape or Scope, re-run the scan and add/adjust the docs step + map row, or the justified skip. Wording-only edits may keep the prior note.

## Map v2 rules (when writing the map)

Columns and generation rules for the Execution map. Do not restate per-tool pins; resolution stays in [model-tiers.md](model-tiers.md). `tiers.sh` is `bash <skill-dir>/../execute-plan/scripts/tiers.sh`.

**Tier:** `top` | `execute` | `mid` | `low`. Never write `sonnet`. Legacy labels map over: `opus` → `top`, `auto` / `sonnet` → `mid`, `haiku` → `low`.

**Detail by tier:**

- `low` — exact edits, paths and commands.
- `execute` — interface, test cases and the helpers to use.
- `mid` — judgment within a stated design.
- `top` — planning, decisions or review only.

**Runner:** `session` | `subagent` | `delegate:<id>` for any id from `tiers.sh delegates`.

- `top` rows use only `session` or `subagent`, never `delegate:*`.
- Missing Runner: `top` → `session`, anything else → `subagent`.
- Which Runner a row gets: [Runner policy](#runner-policy).

**Files:** repo-relative paths; `—` when a row writes nothing. No overlap within a wave. Escape a literal pipe in a cell as `\|`.

**Acceptance:** one runnable command; `—` allowed only on `top` rows. Escape a literal pipe in a cell as `\|`.

**Model:** empty, or `auto` only with `low` + `delegate:cursor` (recorded as `auto(router)`).

**Review:** `top@session` | any name from `tiers.sh runners` | `mid` | `none`.

- Missing Review → `mid`.
- `none` only on `low` rows with an Acceptance command.
- Rows in one (wave, runner) batch share a single `top@*` value.

**Dispatch generation:**

- Waves in ascending order. Within a wave, `session` and `subagent` rows go in one `/execute-plan <plan> <IDs>` line, and each `delegate:<b>` gets one `/delegate:execute-via-<b> <plan> <IDs>` line.
- Insert a `/commit` line before every `/delegate:execute-via-<b>` line that has any execution line before it — delegates refuse a dirty working tree.
- Then one review line per wave at the strongest Review per batch (`none` < `mid` < `top@*`).
- Batch reviews for delegate rows run inside the delegate run, at the batch's strongest Review; the per-wave review line is informational.
- **Small plans** (see Small plans below) omit the per-wave review lines entirely.
- Then one final whole-branch review line naming the final `top` | `session` review row `<ID>` (Review: `top@` + the host's `defaultReviewRunner` unless the planner names another `top@*`): `Final whole-branch review — top@<x> — /execute-plan <plan> <ID>` for `top@session` / `top@claude-task`, else `Final whole-branch review — top@<x> — /delegate:review <plan> <ID>`.

**Size budget:** keep the body (per SoT in `../execute-plan/execution-status.md`) under about 15 KB. Risk registers, decision records and long evidence go to a sibling `<plan-file>.notes.md`, which only `top` rows and reviews read.

## Small plans

A plan is **small** when all of these hold:

- The map has at most 4 non-`top` rows, all in wave 1.
- There is exactly one `top` row: the final whole-branch review.
- The planner judges it touches no trust boundary (auth, secrets, permissions, CI credentials, network exposure).

When small, record `- **Plan size:** small` under **Assumptions** (in the body, so the plan lock covers it). A missing Plan size line means normal plan behavior.

Effects:

1. Dispatch omits the per-wave review lines and keeps only the final whole-branch review line.
2. `/make-plan`'s closing offer does not recommend `/critique plan` (still offered on request).
3. `/execute-plan`'s review loop starts at the top-tier final pass — no mid passes. A dirty final follows the existing dirty-final path (fix → re-verify → one mid confirmation → stop).

The hard cap is unchanged.

## Runner policy

SoT for which Runner each map row gets. Record this line under **Assumptions**, in the body, so the [plan lock](../execute-plan/execution-status.md#plan-lock) covers it:

- **Runner policy:** <mode> [<list>]

Missing → `auto`.

List members: `subagent` or any id from `tiers.sh delegates`; write `delegate:<id>` for a delegate id. Default `round-robin` list = the delegates in `tiers.sh order`.

**Eligible** = a delegate is eligible when the host is `claude-code` and `tiers.sh resolve <id> <tier>` exits 0; `subagent` is eligible for every non-`top` row; `top` rows never go to delegates. The modes below assign non-`top` rows only.

- `auto` — the planner's choice (today).
- `pin <tool>` — every non-`top` row → `delegate:<tool>` if that delegate is eligible, else `subagent`. `pin subagent` writes `subagent` on every non-`top` row.
- `order <list>` — each non-`top` row → the first eligible member.
- `round-robin [<list>]` — the rotation advances from wave to wave. Per wave, assign that wave's non-`top` rows to the next member. A row that member can't take goes to the next eligible member in list order (walk the list from that member, wrapping). A member eligible for none of the wave's rows is skipped without consuming the turn.

Same-wave **Files** overlap rules still apply across runners. **Dispatch** generation is unchanged: one line per (wave, runner), and a `/commit` before each delegate line.

Never write a runner the policy didn't pick. If no member is eligible, use `subagent` and say why in the row's Step summary.

## Wave / parallel rules

- Same **Wave** → independent (no shared writes or ordering). Waves are barriers: wave count is the critical path.
- **Earliest wave:** 1 + highest `Depends on` Wave (1 if none). Split a step's independent part into an earlier wave.
- Same-file rows cannot share a wave (lint refuses): merge, split Files, or chain via `Depends on`.
- Split large steps until most rows are `low`, `execute`, or `mid`; no “do the feature” mega-steps, but avoid thrash.
- Docs/CHANGELOG rows depend only on rows whose output they quote; else they join implementation's wave.
- One runner per wave where policy allows, so the wave runs as one parallel batch (`/execute-plan` Tasks or delegate subagents); mixed-runner waves run serially.
