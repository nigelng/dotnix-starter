# Independent review criteria and loop

A **different subagent** than any implementer must review. Use `subagent_type: "generalPurpose"` with an explicit **read-only** contract.

**Review model (per pass):** [model-tiers.md](model-tiers.md) — intermediate passes use **mid**; the final pass and ≤1 escalation use **top-review**. Apply **Review family** from model-tiers.md to mid passes. If the final **top-review** model cannot be pinned, stop and ask before that pass. Report each review's tier (`mid`/`top`) and resolved model.

## Review loop (state machine)

Hard cap: **5** review passes total (mid-tier, final, confirmation, and escalation all count).

0. If the plan records `Plan size: small` (see [Small plans](../make-plan/drafting-rules.md#small-plans)), skip steps 1–2 and start at step 3's top-tier final pass; a dirty final follows its dirty-final path.
1. Run a **mid-tier** review pass.
2. If dirty (`blocking`/`important`): fix → re-verify → go to 1 (next mid-tier pass).
3. On the **first clean** mid-tier pass: run **one** top-tier **final** pass.
   - Final **clean** → done.
   - Final **dirty** → fix → re-verify → one mid-tier confirmation → **stop** (remaining items go to the user).
4. **Escalate once** (top-tier, **replacing** the next mid-tier pass) when the same finding(s) repeat across **two** consecutive mid-tier passes, or the reviewer Task errors twice. A **clean** escalation counts as the final pass (done). A dirty escalation follows the same dirty-final path (fix → re-verify → one mid-tier confirmation → stop).
5. After the hard cap or a confirmation stop, present remaining concerns to the user.

## Each review pass

1. `<base>` is the Step 3 baseline SHA. For the final top pass and any escalation use `git merge-base origin/<default> HEAD` instead, so a multi-run plan is reviewed whole. `<default>` is the `default=` line of `<skill-dir>/../commit/scripts/git-preflight.sh state`. If `origin/<default>` is missing or merge-base fails, keep the Step 3 SHA. Report the base used.
2. Launch a read-only `Task` at this pass’s review model, as [hosts.md](hosts.md) says. Pass `<base>`, the plan path and the criteria below only. The reviewer (Devin: the session) runs `git diff <base>` and `git ls-files --others --exclude-standard`. Do not paste a diff.

## Sub-agent review criteria

The sub-agent must review the diff against each of these and report only concrete, high-confidence findings:

1. Logic/behavior bugs, unhandled edge cases, null/undefined refs, races, security issues, resource leaks, API contract violations, and caching bugs (staleness, keys, invalidation, ineffective cache).
2. Violations of existing code patterns or conventions.
3. Code-smell indicators: god methods, cyclomatic complexity above the target, duplicated logic, weak test assertions, or missing tests for newly introduced behavior.
4. Missing or skipped per-step tests without valid justification; behavior changed without **test & implement → lint → verify** (or a valid docs/config skip).
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

- `nit`: record for the final summary; do **not** auto-fix unless the user asks.
- If severity is `blocking` or `important` and the fix is clear and safe, **resume the relevant implementation subagent** (using `Task` with the `resume` parameter and that step's agent ID), or spawn a fix Task scoped to the finding's files. Use **`low`** for mechanical fixes, else **`mid`**. Never let the reviewer apply fixes.
- Unclear or risky fix, or a finding outside the plan's Files: ask the user first.

After fixes, rebuild the commands file and re-run `delegate-verify.sh` as [implementer.md](implementer.md) § Full verification describes. Exit 1 → fix Task, then re-run. Exit 3 (tree changed) → stop and ask. Exit 2 → stop and show stderr. Then continue the **Review loop (state machine)** above (next mid-tier pass, final, confirmation, or escalation as that machine directs).

**Done when:** full tests pass; coverage meets target **when available**; no `blocking`/`important` findings remain.
