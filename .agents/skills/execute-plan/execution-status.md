# Plan execution status contract

Single source of truth for durable completion state on fleet plans under `docs/plans/**`. Execute skills **dual-write** YAML frontmatter + `## Execution log` in one edit. Skills link here; do not restate the full schema in SKILL bodies.

## Frontmatter schema

Required once any execute skill has touched the plan:

```yaml
---
execution:
  status: not-started | in-progress | completed | partial | failed | aborted
  progress_pct: 0-100
  steps_done: <int>
  steps_total: <int>
  last_skill: execute-plan | execute-via-cursor | execute-via-agy | execute-via-devin
  started_at: <ISO-8601Z>   # first run that moved status off not-started
  updated_at: <ISO-8601Z>   # every write
  completed_at: <ISO-8601Z | null>  # only when status == completed
  runs:                     # optional; one entry appended per terminal outcome, oldest first
    - skill: <last_skill value for this run>
      backend: cursor | agy | devin | claude-code
      model_requested: <slug>
      model_resolved: <model the CLI reported | auto(unresolved)>
      effort: low | medium | high | xhigh | max | default | unknown
      started_at: <ISO-8601Z>   # this run's Start write
      ended_at: <ISO-8601Z>     # this run's terminal write
      review_findings: <int>
      fix_loops: <int>
      fallback: <null | reason>
      outcome: completed | partial | failed | aborted
---
```

Timestamps: ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`).

## Run records (`runs:`)

One entry per run, appended in the **Terminal** write (never rewritten later; earlier entries stay as they are). Plans written before this field existed simply have no `runs:` key. Purpose: compare models by review findings per run and spot silent fallbacks to a router.

| Field | Meaning |
| --- | --- |
| `skill` | The `last_skill` value this run wrote. |
| `backend` | `cursor`, `agy`, `devin`, or `claude-code` (in-process `/execute-plan`). |
| `model_requested` | The slug passed to the CLI: the user's `model=` or the tier pin from `model-tiers.md`. `auto` only when a router was explicitly requested. For `claude-code`, the distinct implementer models used, in run order, comma-separated (for example `claude-sonnet-5-5,claude-haiku-5-5`). |
| `model_resolved` | The model the CLI reported for the run (Cursor `init.model`, agy `init.model`, Devin export step `model_name`; for `claude-code`, the models the Tasks ran on). CLI output is untrusted: it must match `^[A-Za-z0-9][A-Za-z0-9 ._:/()+-]{0,63}$`, otherwise write `auto(unresolved)`. Write it YAML-quoted in `runs:` (for example `model_resolved: "Grok 4.7 256K High"`) and use the same validated value in the `Run:` line. If the CLI reports none, write `auto(unresolved)`; never copy `model_requested` into it. |
| `effort` | The effort suffix of the requested slug (`grok-4.7-high` → `high`); `default` when the slug has none (`composer-2.5`); the tier effort from `model-tiers.md` for `claude-code` (comma-separated, matching `model_requested`); `unknown` for a router. |
| `started_at` / `ended_at` | This run's Start write and Terminal write. |
| `review_findings` | Count of `blocking` + `important` findings raised by Claude's reviews during this run (all rounds summed; `0` when every review was clean). Nits are not counted. |
| `fix_loops` | FIX rounds used (delegate skills: 0–2; `/execute-plan`: fix Task rounds after review). |
| `fallback` | `null`, or the reason a non-pinned model ran: `expired <slug>`, `pin missing`, `quota`, `model=auto`, `model mismatch <requested>→<resolved>`, or `auto(unresolved)` when the resolved model is unknown. The resolved-vs-requested comparison applies to Devin only (exact slugs; a mismatch is already a FAIL there). Cursor reports a display label and agy's value is not compared, so for Cursor and agy `fallback` is set only from `expired <slug>`, `pin missing`, `quota`, `model=auto`, or `auto(unresolved)`; additionally a resolved value equal to `auto` (case-insensitive) is a router fallback. |
| `outcome` | Same value as the `### Run` stanza `Outcome:` line. |

## Overall `status` meanings

| Value | Meaning |
| --- | --- |
| `not-started` | Scaffold only; no execute run yet. |
| `in-progress` | At least one row `in-progress` or `done`, and not terminal. |
| `completed` | Every row is `done` **or** `skipped` for a reason **other than** solely `out of step-scope`, **and** the skill’s success path finished (execute-plan review clean / execute-via-cursor, execute-via-agy, or execute-via-devin PASS). Rows skipped only as out-of-scope do **not** satisfy this. |
| `partial` | Run stopped without meeting `completed`: user abort mid-wave; scoped PASS (out-of-scope skips and/or unfinished in-scope rows); or any row still `pending`/`in-progress`/`failed` after a non-failed stop. Scoped PASS is never `completed`. |
| `failed` | Terminal failure (execute-via-cursor, execute-via-agy, or execute-via-devin FAIL after FIX budget; execute-plan hard stop after failed wave/review stop conditions without a clean finish). |
| `aborted` | User aborted before any row reached `done` this run; preflight refusals write nothing. |

## Row statuses

Table column values: `pending` | `in-progress` | `done` | `skipped` | `failed`.

## Progress formula

- **`steps_total`** = number of Execution-map rows (preferred), or Implementation-step fallback rows when no map.
- **`steps_done`** = count of rows with status `done` **or** `skipped` (skipped counts as resolved for progress).
- **`progress_pct`** = `round(100 * steps_done / steps_total)`.
- If **`steps_total == 0`**: set `progress_pct` to `0` and **never** claim `completed`.

## Out-of-scope / step-scope (locked)

Out-of-scope rows (not in current `step-scope` / execute-plan subset) → **`skipped`** + Notes **`out of step-scope`**, only if not already `done` (never leave `pending`; never downgrade prior `done`). Out-of-scope skips alone never yield overall `completed` (see `partial`).

## Placement (locked)

`## Execution log` goes **immediately after** `## Execution map` and **before** `## Files to modify/create`.

If the plan has **no** Execution map: place immediately after `## Implementation steps` and before Files.

Writers must **create or move** the section to that slot — do **not** append at EOF; do **not** leave a duplicate mid-file.

## Markdown log template

```markdown
## Execution log

- **Overall:** <status> — <progress_pct>% (<steps_done>/<steps_total>)
- **Last skill:** <execute-plan|execute-via-cursor|execute-via-agy|execute-via-devin>
- **Updated:** <ISO-8601Z>

| ID | Status | Notes |
| --- | --- | --- |
| S1 | done | … |
| S2 | skipped | out of step-scope |
| S3 | pending | |

### Run <ISO-8601Z> (<skill>)
- Outcome: <completed|partial|failed|aborted|in-progress>
- Run: backend=<backend> model=<model_requested>→<model_resolved> effort=<effort> findings=<review_findings> fix_loops=<fix_loops> fallback=<fallback or none> (<started_at>→<ended_at>)
- Notes: <one short paragraph or bullet list>
```

The `Run:` line mirrors the matching `runs:` entry so a human sees the same record the frontmatter holds.

Keep history short: replace/update the summary table on each write; add one `### Run …` stanza per terminal (or meaningful) outcome rather than unbounded append noise.

## Update timing (locked)

1. **Start of execute** (after preflight/validation passes): ensure frontmatter + empty/updated log exist; set `status: in-progress`, `started_at` if unset, mark scoped rows `pending` (or leave prior `done` on resume).
2. **After each wave / scoped batch** succeeds or fails: update those row statuses + frontmatter `%` / `updated_at`.
3. **Terminal outcome** (final summary / PASS / FAIL / abort): set overall `status`, `completed_at` iff `completed`, final `%`, one `### Run …` stanza with its `Run:` line, and append the matching `runs:` entry.

## Who writes

| Skill | Writer |
| --- | --- |
| `/execute-plan` | **Orchestrator** (same agent that persists the Execution map). |
| `/delegate:execute-via-cursor`, `/delegate:execute-via-agy`, `/delegate:execute-via-devin` | **Claude** after each meaningful phase (post-implement before/after review as needed; always on terminal verdict). **Never** the implementer tool (`agent` / `agy` / `devin`). |

## Fallback when no Execution map

Treat numbered **Implementation steps** as the row set for progress. Use IDs `I1`…`In` or the plan’s existing step numbers. Same row statuses, formula, out-of-scope rule, and log template.

## Idempotency / re-execute

Re-running on an already **`completed`** plan: **confirm with the user** before resetting row statuses (or only add a new Run stanza if the user confirms re-execute).

Default recommendation when user confirms re-execute: reset non-`skipped` rows in scope to `pending` and set overall `in-progress`.

## Dual-write rule

Every status update is **one edit** that updates frontmatter **and** `## Execution log` together. Prefer replace-the-summary-table over conflicting formats. Never write one without the other.
