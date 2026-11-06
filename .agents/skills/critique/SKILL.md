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

## Critique policy A (session / Task tiers)

**Not all critique is Opus.** Split by mode — do not collapse these into one
mid-tier loop. Resolve models per [model-tiers.md](model-tiers.md)
(`top` / `mid` / `low`). Report each subagent with intended tier and resolved
model.

`/critique change` uses at most **2 top-tier passes** per run (≤1 escalate +
1 final closing pass); report each with its reason.

| Pass | Tier | Notes |
| --- | --- | --- |
| **`/critique plan`** | **top** (in-session) | Plan edits OK; warn once if session below top; 2-pass budget |
| Lean review (change Phase A) | **mid** | Resolve **mid** per [model-tiers.md](model-tiers.md); max **2** |
| Fix Task (change) | **mid** (**low** if mechanical) | Separate write agent; never the reviewer |
| Escalate (≤1) | **top** Task | After round-1 **Rework**, or after **2 mid** with `blocking`/unresolved `important`; then **stop**; `critique escalate` |
| **Final `/critique change`** | **top** Task | Separate read-only Task (`critique closing pass`); ≠ escalate |
| Security pass | Cursor **`security-review`** | Not a generic Opus essay; Claude / inline trust-boundary fallback if unavailable |

Never silent “Ship as-is” while `blocking` / unresolved `important` remain; never lean past 2 rounds.

Fleet multi-mode critique (not Cursor `/review` / `/review-bugbot` / `/review-security`). When security tooling runs as a sub-step here, do not also tell the user to run `/review-security`.

## When to use / skip

- **`/critique plan`** after `/make-plan` (large blast radius, migrations,
  security-sensitive scope especially): in-session top-tier review + plan edits.
  Tiny/mechanical plans still use top-tier — keep the review short.
- **`/critique change`** before commit when `/execute-plan` was **not** used, or
  for hand-written diffs (lean mid → final top closing Task when lean is clean).
- **After converged `/execute-plan` top-tier review:** Change mode → After
  execute-plan.

## Preconditions

**Requires Agent mode** for plan edits or code fixes. In Plan/Ask mode needing
writes: stop and tell the user to switch to Agent mode.

## Step 1 — Detect review context

Determine whether this is a **plan review** or a **change review**. Run `git status`, `git diff`, `git log --oneline -10`, and `Glob docs/plans/*.md` in parallel first.

Parse the user's slash-command or message args.

### Explicit mode (args start with a mode keyword)

- `critique plan [path]` → **plan mode**. If a path is given, use it; otherwise pick the most recent `docs/plans/*.md` (or ask if multiple candidates).
- `critique change [ref|range|#PR]` → **change mode**. Parse the ref per "Change mode — Resolve the diff" below.
- `critique <path-or-ref>` (no keyword) → resolve the argument:
  - If it's an existing file path ending in `.md` under `docs/plans/` (or matches a plan file) → **plan mode** with that path.
  - If it looks like a commit-ish, range (`a..b`), or PR number (`#123` / `123`) → **change mode** with that ref.
  - Otherwise → ask the user which mode they meant.

### No arguments — auto-detect

Evaluate in this order (ambiguous before uncommitted→change):

1. **Both a fresh plan and uncommitted changes exist** → ambiguous. Use `AskQuestion` when available (otherwise ask conversationally):
   - Option A: "Review the plan at `<path>`" — rationale: stress-test before execute.
   - Option B: "Review uncommitted changes (`git diff HEAD`)" — rationale: catch bugs before commit.
   - Option C: "Other".
   - **Recommendation: A** if the plan was drafted in this session, otherwise **B**.
2. **Has uncommitted changes** (staged or unstaged) → **change mode** (review `git diff HEAD`).
3. **Working tree clean, has commits** → look at `docs/plans/*.md`:
   - If the most recent plan file's timestamp is newer than the latest commit's author date → **plan mode**.
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

Plan mode has no lean mid-tier loop (in-session top-tier; pass budget in Plan mode).

### Phase A — lean mid-tier (change mode only), max 2

1. Spawn an independent **read-only** lean review Task (`generalPurpose`, mid-tier).
2. Parse findings; auto-apply only `blocking` / `important` via fix Task.
3. Stop lean loop if Ship as-is / only nits / no high-confidence issues.
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
applies, the user opts out, or that Task already ran this turn (in-session
self-review does **not** count).

If the closing pass finds `blocking` / `important`: apply clear fixes via a
fix Task (**no re-review**), list those fixes as **unverified**, and **stop**.

---

## Plan mode

Review a plan in `docs/plans/**` (or promoted `.cursor/plans/`) for residual
failure modes; apply plan-file edits. **Session is top-tier** — in-session
review + edits (not a separate Task). **Warn once** (do not block) if the
session is below top tier.

### Load the plan

`Read` the plan; review **in-session**. Second pass: **re-check only edited
sections + open findings**. After **2** passes, **stop** and present remaining
items — no third automatic plan critique.

### Review criteria (only report hits; top-tier plan pass)

1. **Unverified assumptions / missing decisions** that will cause guesswork at execute time
2. **Failure modes & unsafe half-done states**
3. **Sequencing / blast radius / irreversibility** gaps
4. **Verification gaps** — missing commands, coverage claim without tooling, Success criteria vs Verification mismatch

Also flag **security-sensitive scope** (auth, crypto, PII, network trust boundaries) so a change-mode security pass will be needed later. Do **not** run Cursor `security-review` on a plan file alone (diff-based tool).

Do **not** re-litigate Execution map tier labels or Goal wording unless wrong/unsafe.

### Suggested changes / apply

Concrete minimal plan edits tied to a finding; human decisions → questions (do
not invent answers). Main agent edits **only** the plan file; summarize fixes
in 1–2 sentences per finding. Unverifiable paths via `Glob`/`Read` → finding,
not a guess.

---

## Change mode

Review a git diff for residual bugs and gaps; apply fixes via a separate fix subagent; run a **security pass** via product tooling when available.

### Resolve the diff

Using the ref from Step 1 (or auto-detected):

- **Commit-ish** → `git show <ref>` / `git diff <ref>~1 <ref>`.
- **Range** (`a..b`) → `git diff a..b`.
- **PR number** → `gh pr diff` / `gh pr view` when `gh` is available.
- **No ref:** dirty tree → `git diff HEAD`; clean → `git show HEAD`.

Capture diff, changed files, base ref. For lean review: if the diff is huge, pass `git diff --stat` + file list and instruct the reviewer to `Read` hottest files — still require evidence before findings.

**Working tree vs commit:** Fixes always land in the working tree (never rewrite history). Tell the user when the reviewed ref was a commit but fixes are uncommitted.

### After execute-plan

If this session (or the user) just finished `/execute-plan` with a converged
**top-tier** review: **skip Phase A lean** and **skip** the closing final
`/critique change` pass by default (execute-plan review already closed the
change). Proceed to **Security pass** unless docs-only or the user opts out.
Run this skill’s closing top-tier pass only when **this skill’s own lean loop**
is what is shipping, or the user asks for another pass. In the round table, note
skipped Phase A / final closing rows with reason `after converged execute-plan`.

### Lean review criteria (only report hits)

1. **Correctness & logic**
2. **Edge cases / null safety** where the diff introduces risk
3. **API contracts / breakages**
4. **Tests missing** for new behavior

Optional catch-all: other high-confidence issues (caching, resources, conventions) only when a finding exists. Do **not** full-audit security in the lean Task when the security pass runs.

### Fix subagent contract

- Only edit files in the current diff. Minimal change. No mutating git. No installs/migrations (defer those).
- Per finding: `fixed` | `deferred` | `disputed` | `skipped` (nits).
- Verify edited regions by reading them. Main agent may run fast lint/typecheck after fixes; prefer revert + defer if a non-trivial regression appears.

### Post-round verification (main agent)

1. `git diff --stat` — revert out-of-scope files with `git checkout -- <file>` if needed.
2. Optional fast lint/typecheck/test; fix or revert+defer on failure.
3. Record round outcomes for the summary.

### Security pass (change mode)

Run **once** per `/critique change` (not per lean round). Prefer **in parallel** with the first lean review when the surface allows concurrent Tasks; otherwise after locating the diff / after skipping lean post-execute-plan.

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

Map into `blocking` / `important` / `nit`. Auto-fix via fix Task only when
concrete, in-diff, and safe; otherwise defer. No multi-round security loop.

---

## Final output (both modes)

- **Mode** and what was reviewed; **round table** (plan: top session; change:
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
