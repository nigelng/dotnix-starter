# Plan file template

Write new/updated plans in this structure. Every multi-step plan needs an **Execution map**; a single trivial step may use one `low` (or `mid`) wave with one row. Every map ID must match a numbered Implementation step (or a clear sub-bullet). The v2 header is `ID | Step summary | Tier | Runner | Wave | Depends on | Files | Acceptance | Review`, with an optional `Model` column immediately before `Review`. An optional `**Notes:** <plan-file>.notes.md` line (same basename with `.notes.md` in place of `.md`) may sit under Purpose. Both legacy 6-column maps and v2 are valid.

```markdown
---
created_at: "<ISO-8601Z>"
plan_sha: "<64 hex chars>"
approved_at: "<ISO-8601Z>"
execution:
  status: not-started
  progress_pct: 0
  steps_done: 0
  steps_total: 0
  last_skill: null
  started_at: null
  updated_at: null
  completed_at: null
---

# Plan: <task title>

## Purpose
<1-2 sentences: what and why>

**Notes:** <plan-file>.notes.md

## Scope
**In scope:**
- <item>
**Out of scope:**
- <item>

## Assumptions
- <assumption; mark `[verified]` or `[unverified]`>
- **Architecture docs (from scan):** <paths / canonical, or "none found"; note if create-under-`docs/architecture/` needed>
- **Runner policy:** <auto | pin <tool> | order <list> | round-robin [<list>]>
- **Plan size:** small  (optional — only when the plan qualifies under Small plans in drafting-rules.md; omit for a normal plan)

## Dependencies
- <other plans, PRs, external API approvals, or infra that must be in place first; link if known>

## Implementation steps
1. <step> — <file(s) affected>
2. <step> — <file(s) affected>
3. **Update documentation** — <arch paths / create / one-line justified skip>
4. **Update CHANGELOG** — <entry, or justified skip; only if the repo has `CHANGELOG.md`>
...

## Execution map

| ID | Step summary | Tier | Runner | Wave | Depends on | Files | Acceptance | Review |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | … | execute | subagent | 1 | — | `<path-a>` | `<command>` | mid |
| S2 | … | execute | subagent | 1 | — | `<path-b>` | `<command>` | mid |
| S3 | … | low | delegate:cursor | 1 | — | `<path-c>` | `<command>` | top@cursor-ask |
| S4 | … | top | session | 2 | S1,S2,S3 | — | — | mid |
| S5 | Update architecture docs (or justified skip) | low | subagent | 3 | S4 | `docs/architecture/OVERVIEW.md` | `<command>` | mid |

## Execution log

- **Overall:** not-started — 0% (0/0)
- **Last skill:** —
- **Updated:** —

| ID | Status | Notes |
| --- | --- | --- |

<!-- Scaffold: execute/delegate skills dual-write; do not hand-edit. -->

## Dispatch

1. Wave 1 · subagent — `/execute-plan <plan> S1 S2`
2. `/commit` (delegates need a clean tree)
3. Wave 1 · delegate:cursor — `/delegate:execute-via-cursor <plan> S3`
4. Review wave 1 — mid (S1, S2) · top@cursor-ask (S3)
…
N. Final whole-branch review — top@<host defaultReviewRunner> — `/execute-plan <plan> S<N>`

## Files to modify/create
- `<path>` — <brief description of the change>
- `<path>` — <brief description of the change>

## Verification
- <test / lint / type-check / build commands — concrete and copy-pastable>
- **Coverage:** <available | not available>
  - If available: command `<exact coverage command>`; **target: <N>%** (repo threshold if present, else **90%** unless user overrode); scope: files the plan changes
  - If not available: state that explicitly
- **Architecture docs:** `git diff` / Files prove listed arch-doc changes, **or** one-line justified skip present

## Success criteria
- <what good looks like — distinct from Verification>
- If coverage available: meeting the stated **coverage target**
- Architecture docs reflect the shape change, **or** justified skip recorded

## Rollback / reversibility
- <what can be undone cleanly and how; what's NOT reversible>
- If a step force-pushes, rewrites history, or deletes a branch/tag on a remote: check **both** classic branch protection (`gh api repos/<owner>/<repo>/branches/<branch>/protection`; 404 = none) **and** repository rulesets (`gh api repos/<owner>/<repo>/rulesets`, then `gh api repos/<owner>/<repo>/rules/branches/<branch>` for the rules in effect). Rulesets can block force-push (`non_fast_forward`), require signed commits (`required_signatures`), or block deletion, even when branch protection returns 404. Record the result and the bypass path (bypass actor, or a temporary disable and re-enable) in the step.

## Risks & considerations
- <edge case, tradeoff, backwards-compat, or "None identified">
- If coverage unavailable but high-risk: note the gap
```

Implementation steps stay human-readable; the map is the machine-oriented schedule for `/execute-plan`.
