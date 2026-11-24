---
name: critique
description: >-
  Independent review of a plan or code changes (policy A): top-tier for
  /critique plan and final /critique change; lean mid-tier change rounds
  (≤2) with ≤1 top-tier escalate; Cursor/Claude security-review pass when
  available. Args: [plan <path> | change <ref|range|#PR> | <path-or-ref>].
  Use when the user asks to review a plan or change, or mentions /critique.
disable-model-invocation: true
---

# critique

High-confidence second opinion on a **plan** or **change**. Not a second
planning/execute loop. Prefer “Ship as-is” over inventing nits. Auto-apply only
`blocking` / `important`; leave `nit`s for the user.

> **Under /conduct:** change mode runs in full (the after-execute-plan skip is disabled) over the whole branch diff; see [../conduct/stage-overrides.md](../conduct/stage-overrides.md#critique-change). Standalone behaviour is unchanged.

## Critique policy A (session / Task tiers)

**Not all critique is top-tier.** Split by mode; don't collapse into one
mid-tier loop. Resolve models per [model-tiers.md](model-tiers.md)
(`top` / `mid` / `low`). Report each subagent with intended tier and resolved
model. Spawn every Task per [../execute-plan/hosts.md](../execute-plan/hosts.md).
On Devin, `mkdir -p .claude/tmp` before writing the
`.claude/tmp/exec-claude-review-*` files hosts.md asks for, write them fresh
for each Task, and delete them once the run ends.

`/critique change` uses at most **2 top-tier passes** per run (≤1 escalate +
1 final closing pass); report each with its reason.

| Pass | Tier | Notes |
| --- | --- | --- |
| `/critique plan` | **top-critique** Task (`top-review` if absent or unpinnable); **top-plan** session | Separate read-only Task; session applies edits (warn once below `top-plan`, never block); 2-pass budget; Devin without profiles: in-session fallback (Plan mode) |
| Lean review (change Phase A) | **mid** | Per [model-tiers.md](model-tiers.md); max **2** |
| Fix Task (change) | **mid** (**low** if mechanical) | Separate write agent; never the reviewer |
| Escalate (≤1) | **top-review** Task | After round-1 **Rework**, or after **2 mid** with `blocking`/unresolved `important`; then **stop**; `critique escalate` |
| **Final `/critique change`** | **top-review** Task | Separate read-only Task (`critique closing pass`); ≠ escalate |
| Security pass | Cursor `security-review` | Not a generic top-tier essay; Claude/inline trust-boundary fallback if absent |

Never silent “Ship as-is” while `blocking` / unresolved `important` remain; never lean past 2 rounds.

Fleet multi-mode critique (not Cursor `/review` / `/review-bugbot` / `/review-security`). When security tooling runs as a sub-step here, do not also tell the user to run `/review-security`.

## When to use / skip

- **`/critique plan`** after `/make-plan` (large blast radius, migrations,
  security-sensitive scope especially): top-tier review Task; session applies edits.
  Tiny/mechanical plans still use top-tier — keep the review short.
- **`/critique change`** before commit when `/execute-plan` was **not** used, or
  for hand-written diffs (lean mid → final top closing Task when lean is clean).
- **After a converged `/execute-plan` top-tier review, or a converged delegate PASS:** Change mode: see below.

## Preconditions

**Requires Agent mode** for plan edits or code fixes. In Plan/Ask mode needing
writes: stop and tell the user to switch to Agent mode.

## Step 1 — Detect review context

Determine whether this is a **plan review** or a **change review**. First, one parallel batch: `git status`, `git diff`, `git log --oneline -10`, `Glob docs/plans/*.md`, and `bash <skill-dir>/../execute-plan/scripts/plan-status.sh recent docs/plans; echo "exit=$?"` (newest plan; `<skill-dir>` = this `SKILL.md`'s absolute directory). Drop `*.notes.md` hits; a notes file is never a plan. `recent` printed `exit=3` (`tie`) → ask which plan; `exit=2` → no plan; `exit=0` → its stdout is the newest plan.

Parse the user's slash-command or message args.

### Explicit mode (args start with a mode keyword)

- `critique plan [path]` → **plan mode**. If a path is given, use it unless it is `*.notes.md` (ask which plan). Otherwise use the plan `recent` printed.
- `critique change [ref|range|#PR]` → **change mode**. Parse the ref per "Change mode — Resolve the diff" below.
- `critique <path-or-ref>` (no keyword) → resolve the argument:
  - If it's an existing file path ending in `.md` under `docs/plans/` (or matches a plan file) and is not `*.notes.md` → **plan mode** with that path.
  - If it looks like a commit-ish, range (`a..b`), or PR number (`#123` / `123`) → **change mode** with that ref.
  - Otherwise → ask the user which mode they meant.

### No arguments — auto-detect

Evaluate in this order (ambiguous before uncommitted→change):

1. **Both a fresh plan and uncommitted changes exist** → ambiguous. Use the question tool (`AskQuestion`/`AskUserQuestion`/`ask_user_question`) when available (otherwise ask conversationally):
   - Option A: "Review the plan at `<path>`" — rationale: stress-test before execute.
   - Option B: "Review uncommitted changes (`git diff HEAD`)" — rationale: catch bugs before commit.
   - Option C: "Other".
   - **Recommendation: A** if the plan was drafted in this session, otherwise **B**.
2. **Has uncommitted changes** (staged or unstaged) → **change mode** (review `git diff HEAD`).
3. **Working tree clean, has commits** → the plan `recent` printed. Compare its `approved_at`, then `created_at`, then the filename prefix (local time, as `recent` uses it), then mtime, to the latest commit's author date:
   - If that timestamp is newer than the commit's author date → **plan mode**.
   - Otherwise → **change mode** (review the latest commit, `git show HEAD`).
4. **No commits and no plan files** → tell the user there's nothing to review and stop.

If at any point you cannot confidently determine the mode, ask — never guess.

## Shared — lean output contract

Review Tasks must:

- Omit solid categories entirely — **no** “Solid.” padding.
- Report **only** high-confidence `blocking` / `important` / `nit` findings (nits ≤3, optional; prefer zero).
- Blind spots: only if there is a real finding; else one line: “No additional blind spots.”
- No plan/code rewrites for style. Prefer Ship as-is when unsure.
- Verdict: `"Ship as-is"` | `"Apply N suggested changes then ship"` / `"Address N findings then ship"` | `"Rework — fundamental issues"`. Count matches actionable items.

Each finding: **Severity**, **Location**, **Description**, **Suggested fix**.

If none: “No high-confidence issues found.”

---

## Shared — round budget (change mode Phase A / B + final)

Plan mode has no lean loop (one top-tier Task per pass; budget in Plan mode).

### Phase A — lean mid-tier (change mode only), max 2

1. Spawn an independent **read-only** lean review Task (`generalPurpose`, mid-tier). Round 1: launch the Security pass Task in the same message when it runs as a Task.
2. Parse findings (round 1: lean + security, merged); auto-apply only `blocking` / `important` in one fix batch.
3. Stop lean loop if Ship as-is / only nits / no high-confidence issues (round 1: lean + security merged, so an applied security fix means round 2 runs).
4. If blockers remain with clear fixes: apply, then **at most one more** lean
   review (max **2** mid-tier reviews total).

### Phase B — top-tier escalate (≤1; only if still dirty)

Run **exactly one** top-tier escalate review (reason `critique escalate`) when:

- round-1 verdict is “Rework” → escalate immediately (**skip** a second lean
  round), or
- after **2 mid-tier** rounds any `blocking` or unresolved `important` remains.

Apply clear blocking/important fixes; optional quick lint/tests verify. **No
further automatic escalate rounds.** If issues remain: **stop**, present the
remaining list, offer refine / re-run `/critique` later / accept deferred.

### Final `/critique change` — top-tier closing pass

When Phase A is clean/ship-ready **and** escalate was not required — or after
escalate fixes leave the change ship-ready — run **one** read-only **top-tier**
Task (`reason: critique closing pass`); never in-session (avoids
self-review). Distinct from Phase B escalate. **Skip** when After execute-plan
or a converged delegate PASS applies, the user opts out, or that Task already
ran this turn (in-session self-review does **not** count).

If the closing pass finds `blocking` / `important`: apply clear fixes via a
fix batch (**no re-review**), list those fixes as **unverified**, and **stop**.

---

## Plan mode

Review a plan in `docs/plans/**` (or promoted `.cursor/plans/`) for residual
failure modes. The session applies plan-file edits and stamps: warn once and
recommend switching if below the host's **top-plan** pin
(`tiers.sh resolve <host> top-plan`), never block; if the session model is
unlisted, say so in one line and continue.

### Spawn the review Task

Never review in the drafting session, except the Devin fallback below. Per
pass, run one read-only Task at `tiers.sh resolve <host> top-critique`; exit 3
(host has no such tier) or unpinnable on `<host>` → `top-review`. The Task
returns findings only. Fresh context gives independence.

**Devin without the profiles.** If `run_subagent` offers neither `kit-critique`
nor `kit-review-top` (or is absent), do not stop. Warn once: `kit-* profiles
missing: reviewing in-session, not independent. Install per the kit README.`
Then review in this session: `Read` the plan fresh from disk, run `rows --lint`
yourself, apply the criteria below, keep the 2-pass budget, and start the
verdict with `in-session review (no independent Task)`. One of the two offered
→ use it. Any other host or spawn failure still stops per hosts.md.

### Load the plan

Pass the Task the plan path and criteria; it reads the plan. On Devin, first
run `rows --lint <plan>` into a `.claude/tmp/exec-claude-review-*` file (exit 2
→ stop and show stderr) and pass its path too. Second pass:
**re-check only edited sections + open findings**. After **2** passes, **stop** and present remaining
items — no third automatic plan critique.

### Review criteria (only report hits; top-tier plan pass)

1. **Unverified assumptions / missing decisions** that will cause guesswork at execute time
2. **Failure modes & unsafe half-done states**
3. **Sequencing / blast radius / irreversibility** gaps
4. **Verification gaps** — missing commands, coverage claim without tooling, Success criteria vs Verification mismatch
5. **Map v2 rule violations** — only on a v2 map (columns in [Map v2 rules](../make-plan/drafting-rules.md); a legacy map with no Files column is not a hit). Run `rows --lint` (Devin Task: read the lint output file you were given) and cite each `REFUSE:` line. Exit 0 is not a hit. Exit 2 → stop and show stderr.

```bash
bash <skill-dir>/../execute-plan/scripts/plan-status.sh rows --lint <plan>
```

Also flag **security-sensitive scope** (auth, crypto, PII, network trust boundaries) so a change-mode security pass will be needed later. Do **not** run Cursor `security-review` on a plan file alone (diff-based tool).

Do **not** re-litigate Execution map tier labels or Goal wording unless wrong/unsafe. Criterion 5 is those rule breaks, not a preference about tier labels.

### Suggested changes / apply

Concrete minimal plan edits tied to a finding; human decisions → questions (do
not invent answers). Main agent edits **only** the plan file; summarize fixes
in 1–2 sentences per finding. Unverifiable paths via `Glob`/`Read` → finding,
not a guess.

After any edit to a plan under `docs/plans/**` (including a second pass), stamp. Do not change `created_at`. Do not hand-edit `plan_sha`. Exit 2 → stop and show stderr.

```bash
bash <skill-dir>/../execute-plan/scripts/plan-status.sh stamp <plan>
```

---

## Change mode

Review a git diff for residual bugs and gaps; apply fixes via a separate fix subagent; run a **security pass** via product tooling when available.

### Resolve the diff

Using the ref from Step 1 (or auto-detected):

- **Commit-ish** → `git show <ref>` / `git diff <ref>~1 <ref>`.
- **Range** (`a..b`) → `git diff a..b`.
- **PR number** → `gh pr diff` / `gh pr view` when `gh` is available.
- **No ref:** dirty tree → `git diff HEAD`; clean → `git show HEAD`.

Resolve the base ref and changed-file list. Pass each review Task that base ref and the criteria only. The Task runs `git diff <base>` itself (and lists untracked files when the review includes them). Do not paste the diff. If the diff is huge, the Task may start from `git diff --stat` and `Read` the hottest files — still require evidence before findings. On Devin the session runs these commands and the Task reads the files hosts.md has the session write.

**Working tree vs commit:** Fixes always land in the working tree (never rewrite history). Tell the user when the reviewed ref was a commit but fixes are uncommitted.

### After execute-plan or a converged delegate PASS

If this session (or the user) just finished `/execute-plan` with a converged
**top-tier** review, a `/delegate:execute-via-*` PASS whose last review was a
clean `top@*`, or a `/delegate:review` PASS (log `review=top@… clean`): by
default **skip Phase A lean** and the closing final pass (that review closed
the change). Note the skipped rows in the round table with reason `after
converged execute-plan` or `after converged delegate PASS`.

Either skip still proceeds to **Security pass** unless docs-only or the user
opts out. Run this skill’s closing top-tier pass only when **this skill’s own
lean loop** is what is shipping, or the user asks for another pass.

### Lean review criteria (only report hits)

1. **Correctness & logic**
2. **Edge cases / null safety** where the diff introduces risk
3. **API contracts / breakages**
4. **Tests missing** for new behavior

Optional catch-all: other high-confidence issues (caching, resources, conventions) only when a finding exists. Do **not** full-audit security in the lean Task when the security pass runs.

### Fix subagent contract

- **Fix batch:** one fix Task per disjoint file group, launched in one message; a finding that spans files keeps them in one group.
- Only edit the group's files (all in the current diff). Minimal change. No mutating git. No installs/migrations (defer those).
- Per finding: `fixed` | `deferred` | `disputed` | `skipped` (nits).
- Verify edited regions by reading them. Main agent may run fast lint/typecheck after fixes; prefer revert + defer if a non-trivial regression appears.

### Post-round verification (main agent)

1. In one parallel batch: `git diff --stat` and optional fast lint/typecheck/test, each check suffixed `; echo "exit=$?"` so a failure does not cancel its siblings.
2. Revert out-of-scope files with `git checkout -- <file>`; on a failed check, fix or revert+defer.
3. Record round outcomes for the summary.

### Security pass (change mode)

Run **once** per `/critique change` (not per lean round): alongside lean round 1 (Phase A) when it runs as a Task, else after locating the diff or skipping lean.

#### When to run

- Diff touches code (not docs-only / lockfile-only / pure markdown).
- Skip with one-line reason if docs-only / generated-only, or user opts out.

#### Cursor

If `security-review` subagent type is available, launch **exactly one**:

- `description: "Security Review"`
- `subagent_type: "security-review"`
- `run_in_background: false` unless the user asked for background

Prompt shape (do **not** pre-compute the diff for this subagent):

```text
Full Repository Path: <absolute repository path>
Diff: <uncommitted changes | branch changes>
```

Use `uncommitted changes` for working-tree / HEAD-diff reviews; `branch changes` when reviewing branch/PR scope. Add `Base Branch:` / `Custom Instructions:` only when needed (same rules as Cursor review-security).

Retry once on incorrect invocation or transient failure; then stop and report the blocker.

#### Claude Code

If a security-review skill, plugin, or subagent with the same role exists, invoke it once equivalently. Otherwise use **inline fallback**.

#### Inline fallback (tooling unavailable)

One short mid-tier read-only Task on trust-boundary issues only: injection, authz, secrets in logs, SSRF, unsafe deserialization. Cap findings; no 9-category essay.

#### Merge security findings

Map into `blocking` / `important` / `nit`. Auto-fix (in the round-1 fix batch
when it ran alongside lean) only when concrete, in-diff, and safe; otherwise
defer. No multi-round security loop.

---

## Final output (both modes)

- **Mode** and what was reviewed; **round table** (plan: top Task; change:
  lean mid rows, escalate/final top if used).
- **Security** (change): tool (`security-review` / Claude / inline / skipped +
  reason) + findings count or “no issues”.
- **Change:** `git diff --stat` after fixes; deferred/disputed/remaining by
  severity (never hide blockers).
- **Final verdict** from the last substantive review (not Ship as-is if
  blockers remain).
- **Next:** plan → `/execute-plan <path>` or refine; change → tests, deferred,
  `/commit`, `/gh-create-pr`.

## Global constraints

- Never commit or push. Mutating git only for allowed `git checkout -- <file>`
  reverts of out-of-scope / regressing change-mode edits.
- Review Tasks: `generalPurpose` read-only (except platform `security-review`).
  Fix Tasks: separate write agents — never the reviewer.
- Plan mode: only the plan file. Change fixes: only files in the current diff.
- Auto-apply only `blocking` / `important`; leave `nit`s. No speculative
  findings — ground in plan text or diff + reads. Pre-existing bugs in touched
  files: label separately; fix only if minimal and in-diff, else defer.
