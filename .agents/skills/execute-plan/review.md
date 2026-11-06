# Independent review criteria and loop

The review must be run by a **different subagent** than any that implemented. Use `subagent_type: "generalPurpose"` with an explicit **read-only** contract (do not edit files).

**Review model (per pass):** [model-tiers.md](model-tiers.md) — intermediate passes use mid (`auto`); the final pass and ≤1 escalation use top (`opus`). If the tool cannot pin the final top-tier model, stop and ask before that pass. Report each review with its tier (`auto` or `opus`) and resolved model.

## Review loop (state machine)

Hard cap: **5** review passes total (mid-tier, final, confirmation, and escalation all count).

1. Run a **mid-tier** review pass.
2. If dirty (`blocking`/`important`): fix → re-verify → go to 1 (next mid-tier pass).
3. On the **first clean** mid-tier pass: run **one** top-tier **final** pass.
   - Final **clean** → done.
   - Final **dirty** → fix → re-verify → one mid-tier confirmation → **stop** (hand remaining items to the user).
4. **Escalate once** (top-tier, **replacing** the next mid-tier pass) when the same finding(s) repeat across **two** consecutive mid-tier passes, or the reviewer Task errors twice. A **clean** escalation counts as the final pass (done). A dirty escalation follows the same dirty-final path (fix → re-verify → one mid-tier confirmation → stop).
5. After the hard cap or a confirmation stop, present remaining concerns to the user.

## Each review pass

1. Diff: `git diff HEAD` + untracked (`git ls-files --others --exclude-standard`), scoped to the Step 3 baseline.
2. Launch read-only `Task` (`generalPurpose`) at this pass’s review model. Give: that diff, full plan (incl. map), criteria below, and **do not edit/write/delete** — structured review only.

## Sub-agent review criteria

The sub-agent must review the diff against each of these and report only concrete, high-confidence findings:

1. Logic/behavior bugs, unhandled edge cases, null/undefined refs, races, security issues, resource leaks, API contract violations, and caching bugs (staleness, keys, invalidation, ineffective cache).
2. Violations of existing code patterns or conventions.
3. Code-smell indicators: god methods, cyclomatic complexity above the target, duplicated logic, weak test assertions, or missing tests for newly introduced behavior.
4. Missing or skipped per-step tests without a valid justification; behavior changed without following **test & implement → lint → verify** (or a valid docs/config skip).
5. Lint / type-check regressions introduced in the diff when the project has those tools.

## Required sub-agent output format

Each finding must include:

- **Severity**: `blocking`, `important`, or `nit`.
- **Location**: file path and approximate line(s) if possible.
- **Description**: what is wrong and why it matters.
- **Suggested fix**: concrete change or test to add.
- **Tests needed**: yes/no — whether a new or updated test should cover the issue.

If no findings, the sub-agent must explicitly state: "No high-confidence issues found."

## Handling findings — fix subagent

For each concrete, high-confidence issue:

- If severity is `nit`, record it for the final summary but **do not** auto-fix unless the user asks.
- If severity is `blocking` or `important` and the fix is clear and safe, **resume the relevant implementation subagent** (using `Task` with the `resume` parameter and that step's agent ID), or spawn a new fix Task scoped to the finding's files. Prefer **`haiku`** when the fix is mechanical; otherwise **`auto`**. Never use the review subagent to apply fixes.
- If the fix is unclear or risky, ask the user before proceeding.

After fixes are applied, re-run the full verification via a mid-tier Task, then continue the **Review loop (state machine)** above (next mid-tier pass, final, confirmation, or escalation as that machine directs).

**Done when:** full tests pass; coverage meets target **when available**; no high-confidence `blocking`/`important` findings remain.
