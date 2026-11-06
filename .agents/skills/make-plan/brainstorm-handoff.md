# Brainstorm handoff parsing

Parse args for these markers:

- **Task description** — text before the first marker (`Goal:`, `Scope:`, `Constraints:`, `Target Phase 1:`, or `Brainstorm:`), not text before the first `.`
- **Goal** — text between `Goal:` and the next marker (or end)
- **Scope** — text between `Scope:` and the next marker (or end)
- **Constraints** — text between `Constraints:` and the next marker (or end)
- **Target Phase 1** — text between `Target Phase 1:` and the next marker (or end)
- **Brainstorm** — path after `Brainstorm:` (or a bare `docs/brainstorms/*.md` path in args)

If a `Brainstorm:` path (or `docs/brainstorms/*.md`) is present, `Read` that file and treat its Goal brief, Phase 1, constraints, strategy, and architecture as already answered — skip duplicate Step 2 (Requirements & scope) questions that would re-derive them.

Use the markers (and the brainstorm file when loaded) to pre-populate:

- **Purpose** — Goal (if present) + task description + Target Phase 1 as the immediate focus
- **Scope** — parsed `Scope:` text; map non-goals and deferred/deferring items into **Out of scope**
- **Assumptions / Risks** — map parsed `Constraints:` text here (not a separate Constraints section)
- **Implementation steps** — focus on the Phase 1 deliverable first; prefer strategy/architecture from the brainstorm file over re-deriving from the one-liner
