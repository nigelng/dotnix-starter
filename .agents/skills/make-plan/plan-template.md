# Plan file template

Write new/updated plans in this structure. Every multi-step plan needs an **Execution map**; a single trivial step may use one `auto` wave with one row. Every map ID must match a numbered Implementation step (or a clear sub-bullet).

```markdown
---
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

## Scope
**In scope:**
- <item>
**Out of scope:**
- <item>

## Assumptions
- <assumption; mark `[verified]` or `[unverified]`>
- **Architecture docs (from scan):** <paths / canonical, or "none found"; note if create-under-`docs/architecture/` needed>

## Dependencies
- <other plans, PRs, external API approvals, or infra that must be in place first; link if known>

## Implementation steps
1. <step> — <file(s) affected>
2. <step> — <file(s) affected>
3. **Update documentation** — <arch paths / create / one-line justified skip>
...

## Execution map

| ID | Step summary | Tier | Wave | Depends on | Notes |
| --- | --- | --- | --- | --- | --- |
| S1 | … | haiku | 1 | — | mechanical rename / boilerplate |
| S2 | … | auto | 1 | — | parallel with S1 (no shared files); mid-tier |
| S3 | … | auto | 2 | S1,S2 | integration after wave 1 |
| S4 | Update architecture docs (or justified skip) | haiku | 3 | S3 | OVERVIEW / canonical Archify — or skip |

## Execution log

- **Overall:** not-started — 0% (0/0)
- **Last skill:** —
- **Updated:** —

| ID | Status | Notes |
| --- | --- | --- |

<!-- Scaffold: execute/delegate skills dual-write; do not hand-edit. -->

## Files to modify/create
- `<path>` — <brief description of the change>
- `<path>` — <brief description of the change>

## Verification
- <test / lint / type-check / build commands — concrete and copy-pastable>
- **Coverage:** <available | not available>
  - If available: command `<exact coverage command>`; **target: <N>%** (repo threshold if present, else **90%** unless user overrode); scope if known
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
