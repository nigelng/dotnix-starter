# Drafting rules (coverage, architecture docs, tiers, waves)

Read when drafting Step 4 content or validating an update. Companion to [plan-template.md](plan-template.md). SoT for coverage, architecture-doc, tier, and wave rules — skills point here rather than restating.

## Execution scaffold (Step 4–5, required)

Every new plan **must** ship the execution scaffold from [plan-template.md](plan-template.md): YAML frontmatter `execution:` block with `status: not-started` and zeroed progress, plus an empty `## Execution log` placed **immediately after** `## Execution map` and **before** `## Files to modify/create`. Do not append it at EOF. Field meanings and update rules live in `../execute-plan/execution-status.md` (SoT); do not restate them in the plan.

## Test coverage probe (Step 3)

Default numeric target when tooling exists but the repo has no threshold: **90%** (unless the user chooses otherwise after the probe).

1. Inspect manifests/CI for coverage tooling (JS/TS `coverage`/`vitest`/`jest`/`c8`/`nyc`; Python `pytest-cov`/`.coveragerc`; Go `-cover`; Rust `llvm-cov`/`tarpaulin`; CI gates).
2. Record **Available + threshold** (command + percent), **Available, no threshold** (command; use the default above), or **Not available** (do not invent a gate; note in Verification; optional follow-up).
3. If available and the target is still unclear, ask once: repo threshold / that default / Other.

Always record the probe under **Verification**. When available: include command + numeric target; prefer map/Implementation rows that close coverage gaps. When not: say so — no fake percentage or non-existent command.

## Update documentation (architecture docs)

Every new plan **must** include Implementation step(s) **and** matching Execution-map row(s) to **update** relevant architecture docs (or **create** under `docs/architecture/` if the Step 3 scan found none and the change affects system shape), **or** an explicit **justified skip** in Scope or Implementation.

**Scan (Step 3):** `Glob` / `Grep` / `Read` for architecture documentation. Default hints: `docs/architecture/**`, `**/ARCHITECTURE*`, `**/architecture/**`, README Architecture links, and Archify artifacts under `docs/architecture/`. Record paths for Assumptions / Dependencies / a short Architecture docs note. If a canonical prose doc (e.g. `OVERVIEW`) names a diagram or path, treat that as canonical; else prefer the newest `docs/architecture/**` artifact by folder timestamp; never ground on historical folders that disagree with the canonical doc.

- **Prefer updating** `docs/architecture/OVERVIEW.md` and the **canonical** Archify / diagram path from the scan over inventing parallel docs.
- **Justified skip** — allowed only for pure chore / docs-only / formatting with **no** change to: runtime topology, config contracts, control plane, trust boundaries, or subsystem ownership. One line is enough (e.g. in Scope or the Implementation docs step).
- **Verification** must be execute-checkable (`git diff` / Files show those architecture-doc paths changed as listed, **or** the one-line skip is present). Recording scan paths in Assumptions/Dependencies alone does **not** satisfy Verification.
- **Success criteria** must say architecture docs reflect the shape change, or that the skip is recorded.

On **update**, if the change alters system shape or Scope, re-run the scan and add/adjust the docs step + map row, or the justified skip. Pure wording-only plan edits may keep the prior note if Scope/shape is unchanged.

## Tier rules (when writing the map)

Portable tiers: `haiku` | `auto` | `opus` (`low`/`mid`/`top` in [model-tiers.md](model-tiers.md)). Never write `sonnet` — use `auto`. Do not restate per-tool pins here.

- **`haiku`** — mechanical/tight: renames, boilerplate, template tests, wire existing helpers. One concern, few files.
- **`auto`** — default mid-tier: new logic, API shape, non-trivial tests, judgmentful refactors.
- **`opus`** — rare deep design during execute; prefer finishing design here so execute stays `auto`/`haiku`.

## Wave / parallel rules

- Same **Wave** number → independent (no shared write paths, no ordering dependency) → `/execute-plan` may run them **in parallel**.
- Higher wave waits on listed `Depends on` IDs.
- Split large steps until most rows are `haiku` or `auto`; avoid “do the feature” mega-steps.
- Prefer many small steps over few large ones when it does not create thrash (shared file conflicts → serial in the same wave or a later wave).
