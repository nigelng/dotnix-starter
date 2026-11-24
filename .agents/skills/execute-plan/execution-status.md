# Plan execution status contract

Single source of truth for durable completion state on fleet plans under `docs/plans/**`, and for plan metadata, the plan lock, and plan recency. Execute skills **dual-write** YAML frontmatter + `## Execution log` in one edit. Skills link here; do not restate the full schema in SKILL bodies.

## Frontmatter schema

`created_at`, `plan_sha`, `approved_at`, `gate_b_sha`, and `gate_b_at` are top-level keys placed **above** `execution:` (see Plan metadata). The `execution:` block is required once any execute skill has touched the plan:

```yaml
---
created_at: <ISO-8601Z>   # set once when the file is created; see Plan metadata
plan_sha: <64 hex chars>  # see Plan lock
approved_at: <ISO-8601Z>  # see Plan metadata
gate_b_sha: <64 hex | absent>
gate_b_at: <ISO-8601Z | absent>
execution:
  status: not-started | in-progress | completed | partial | failed | aborted
  progress_pct: 0-100
  steps_done: <int>
  steps_total: <int>
  last_skill: execute-plan | execute-via-cursor | execute-via-agy | execute-via-devin | review
  started_at: <ISO-8601Z>   # first run that moved status off not-started
  updated_at: <ISO-8601Z>   # every write
  completed_at: <ISO-8601Z | null>  # only when status == completed
  runs:                     # optional; one entry appended per terminal outcome, oldest first
    - skill: <last_skill value for this run>
      backend: cursor | agy | devin | claude-code
      model_requested: <slug>
      model_resolved: <model the CLI reported | auto(router) | auto(unresolved)>
      effort: low | medium | high | xhigh | max | default | unknown
      started_at: <ISO-8601Z>   # this run's Start write
      ended_at: <ISO-8601Z>     # this run's terminal write
      tokens_in: <int | null>   # uncached input tokens
      tokens_cached: <int | null>  # cache-read tokens
      tokens_out: <int | null>  # output tokens as reported
      review_findings: <int>
      fix_loops: <int>
      fallback: <null | reason>
      outcome: completed | partial | failed | aborted
---
```

Timestamps: ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`).

## Plan metadata

These top-level frontmatter keys are placed **above** `execution:`:

- `created_at` — ISO-8601Z. Set once when the file is created; never rewrite it.
- `plan_sha` — 64 hex characters. Hash of the locked body (see Plan lock). `plan-status.sh stamp` writes it. Never hand-edit it.
- `approved_at` — ISO-8601Z. Written with `plan_sha` by `stamp`.
- `gate_b_sha` — the `plan_sha` at Gate B. Written only by `plan-status.sh approve`, called only by `/conduct` at Gate B Approve.
- `gate_b_at` — ISO-8601Z written with `gate_b_sha`. No other skill writes `gate_b_sha` or `gate_b_at`.

`/make-plan` and `/critique plan` call `stamp` only. Execute and delegate skills never set, change, or remove `created_at`, `plan_sha`, or `approved_at`.

## Plan lock

The locked body is the file minus its leading frontmatter, minus the `## Execution log` section, with CRLF normalized to LF. That section runs from its heading through the line before the next line that begins with `## ` (a `### Run` subsection stays inside the log), or through EOF when the log is the last section. Run the lock with `plan-status.sh lock <plan>`. Do not reimplement the hash. The snippet below is the definition `lock` loads.

<!-- plan-sha:start -->
```bash
plan_body() {
  awk '{ sub(/\r$/, "") }
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm == 1 { if (/^---[[:space:]]*$/) fm = 2; next }
    /^## Execution log[[:space:]]*$/ { skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }' "$1"
}
plan_sha() {
  if command -v sha256sum >/dev/null 2>&1; then plan_body "$1" | sha256sum
  else plan_body "$1" | shasum -a 256; fi | cut -d' ' -f1
}
```
<!-- plan-sha:end -->

- No `plan_sha` → stderr `WARN: legacy plan (no plan_sha)`, stdout `legacy`; continue.
- Mismatch → exit 3; stderr `plan body changed since approval; re-approve with /make-plan update <path>`.
- `stamp` prints body bytes and warns when over 15000.

## Plan recency

To pick the most recent plan:

- Ignore `*.notes.md`. A notes file is never a plan.
- Give each remaining file one timestamp. The newest timestamp wins.
  - Use `created_at` when it is present.
  - Otherwise use the filename prefix, read in the machine's local time zone and converted to UTC before comparing: `YYYY-MM-DD-` is local 00:00 that day, and `yymmddhhmm-` is local `20yy-mm-dd hh:mm`.
  - Otherwise use mtime.
- Never sort raw filenames.

## Run records (`runs:`)

One entry per run, appended in the **Terminal** write (never rewritten later; earlier entries stay as they are). Plans written before this field existed simply have no `runs:` key.

Reviews are not runs: `/delegate:review` (`last_skill: review`) appends a `### Run <ISO-8601Z> (review)` stanza (`Outcome:`, `Run: runner=<top@…> findings=<N>`, `Notes:`) and **no** `runs:` entry. Batch reviews inside a delegate run are counted in that run's `review_findings`.

| Field | Meaning |
| --- | --- |
| `skill` | The `last_skill` value this run wrote. |
| `backend` | `cursor`, `agy`, `devin`, or `claude-code` (in-process `/execute-plan`). |
| `model_requested` | The slug passed to the CLI: the user's `model=` or the tier pin from `model-tiers.md`. May be `auto` for a router row (map `Model: auto` on a `delegate:cursor` batch) or when the user explicitly requested a router / fallback to Auto. For `claude-code`, the distinct implementer models used, in run order, comma-separated (for example `claude-sonnet-5-5,claude-haiku-5-5`). |
| `model_resolved` | The CLI-reported model: Cursor `init.model`, agy `init.model`, Devin export step `model_name`; `claude-code` uses the Task models. A Cursor `delegate:cursor` batch with map `Model: auto` writes `auto(router)`, not a CLI display label (`fallback: null`, `effort: unknown`). Any other value must match `^[A-Za-z0-9][A-Za-z0-9 ._:/()+-]{0,63}$` or be `auto(unresolved)`. YAML-quote it in `runs:` and put that same value on the `Run:` line. No CLI value → `auto(unresolved)`. Never copy `model_requested`. |
| `effort` | The effort suffix of the requested slug (`grok-4.7-high` → `high`); `default` when the slug has none (`composer-2.5`); the tier effort from `model-tiers.md` for `claude-code` (comma-separated, matching `model_requested`); `unknown` for a router. |
| `started_at` / `ended_at` | This run's Start write and Terminal write. |
| `tokens_in` / `tokens_cached` / `tokens_out` | Integers, or `null` when unknown. Delegate runs write `delegate-usage.sh` totals over every implement and FIX launch (uncached input, cache reads, output as reported; do not add reasoning). External reviewer launches and in-process `/execute-plan` (`claude-code`) write `null`. A missing run file or usage block makes the affected fields `null`, never an undercount. |
| `review_findings` | Count of `blocking` + `important` findings raised by Claude's reviews during this run (all rounds summed; `0` when every review was clean). Nits are not counted. |
| `fix_loops` | FIX rounds used (delegate skills: 0–2; `/execute-plan`: fix Task rounds after review). |
| `fallback` | `null`, or why a non-pinned model ran: `expired <slug>`, `pin missing`, `quota`, `model=auto`, `model mismatch <requested>→<resolved>`, or `auto(unresolved)` when resolved is unknown. Compare resolved to requested on Devin only (exact slugs; a mismatch is already FAIL). Cursor's display label and agy's value are not compared: set `fallback` only from `expired <slug>`, `pin missing`, `quota`, `model=auto`, or `auto(unresolved)`; a resolved value equal to `auto` (case-insensitive) is a router fallback. |
| `outcome` | Same value as the `### Run` stanza `Outcome:` line. |

## Overall `status` meanings

| Value | Meaning |
| --- | --- |
| `not-started` | Scaffold only; no execute run yet. |
| `in-progress` | At least one row `in-progress` or `done`, and not terminal. |
| `completed` | Every row is `done` **or** `skipped` for a reason **other than** a Note that begins with `out of step-scope` (including `out of step-scope (dispatch via delegate)`), **and** the skill’s success path finished (execute-plan review clean / execute-via-cursor, execute-via-agy, or execute-via-devin PASS / `/delegate:review` PASS on the last open row). Rows whose Notes begin with `out of step-scope` do **not** satisfy this. |
| `partial` | Run stopped without meeting `completed`: user abort mid-wave; scoped PASS (out-of-scope skips and/or unfinished in-scope rows); or any row still `pending`/`in-progress`/`failed` after a non-failed stop. Scoped PASS is never `completed`. |
| `failed` | Terminal failure (execute-via-cursor, execute-via-agy, or execute-via-devin FAIL after FIX budget; execute-plan hard stop after failed wave/review stop conditions without a clean finish). |
| `aborted` | User aborted before any row reached `done` this run; preflight refusals write nothing. |

## Row statuses

Table column values: `pending` | `in-progress` | `done` | `skipped` | `failed`.

`plan-status.sh` computes progress, placement, the log template and update timing.

## Out-of-scope / step-scope (locked)

Out-of-scope rows (not in current `step-scope` / execute-plan subset) → **`skipped`** + Notes **`out of step-scope`**, only if not already `done` (never leave `pending`; never downgrade prior `done`). Notes that begin with `out of step-scope` (including `out of step-scope (dispatch via delegate)`) never count toward `completed` (see `partial`).

## Who writes

| Skill | Writer |
| --- | --- |
| `/execute-plan` | **Orchestrator** via `plan-status.sh` (`lock`, `rows`, `start`, `batch`, `terminal`). |
| `/delegate:execute-via-cursor`, `/delegate:execute-via-agy`, `/delegate:execute-via-devin` | **Claude** via `scripts/plan-status.sh` (`start` / `batch` / `terminal`) after each meaningful phase (post-implement before/after review as needed; always on terminal verdict). **Never** the implementer tool (`agent` / `agy` / `devin`). |
| `/delegate:review` | **Claude** via `scripts/plan-status.sh review` (marks the final `top` review row `done`/`failed`, appends a `### Run … (review)` stanza; no `runs:` entry). **Never** the reviewer CLI. |

## Fallback when no Execution map

Treat numbered **Implementation steps** as the row set for progress. Use IDs `I1`…`In` or the plan’s existing step numbers. Same row statuses and out-of-scope rule.

## Idempotency / re-execute

Re-running on an already **`completed`** plan: **confirm with the user** before resetting row statuses (or only add a new Run stanza if the user confirms re-execute).

Default recommendation when user confirms re-execute: reset non-`skipped` rows in scope to `pending` and set overall `in-progress`.

## Dual-write rule

Every status update is **one edit** that updates frontmatter **and** `## Execution log` together. Prefer replace-the-summary-table over conflicting formats. Never write one without the other. A status edit may change `execution:` only. Leave `created_at`, `plan_sha`, `approved_at`, `gate_b_sha`, and `gate_b_at` unchanged.
