# Implementer quality bar and Task prompt

Each map-row Task must meet the quality bar below before reporting success. Give each implementation Task:

- The **plan sections** it needs (Purpose, Scope, Assumptions, its Implementation step text, related Files to modify/create, Verification relevant to its files, Success criteria, Risks).
- Its **map row** (ID, tier, Runner, wave, depends-on), its **Files**, and its **Acceptance**. Implement **only that step**.
- **Files:** edit only those paths. `—` means edit nothing. A legacy row with no Files column uses the paths named in its Implementation step.
- **Acceptance:** when the row has a command, it must pass, and the report includes the command and its output. `—` means there is no acceptance command. A legacy row with no Acceptance column has none.
- The **project root** path.
- The Step 3 **Quality toolkit** (test / lint / type-check / coverage commands and coverage target when available).
- The following instructions:

> Implement only your assigned step. Meet the **per-step quality bar** before reporting success:
>
> 1. **Test & implement → lint → verify** for behavior-changing work:
>    - Write the scoped test assertions (against the plan's expected behavior, not your implementation quirks) and implement the step's files together; do not run an intentionally incomplete stub test first.
>    - Prefer small, readable functions and methods. Keep cyclomatic complexity around **6 or lower**.
>    - Avoid god methods.
>    - Prefer readable code over clever code.
>    - Follow existing project conventions, naming, and patterns.
>    - Do not invent file paths — verify with `Glob` or `Read` before writing.
>    - Edit only the row's **Files**. Do not edit any other path. If a change outside those files is required, report and stop.
>    - **Acceptance:** when the command is not `—`, run it after lint and tests. It must pass. A failing Acceptance command fails the step. `—`, or a legacy row with no Acceptance column, means there is no acceptance command.
>    - **Lint first:** when the Quality toolkit lists lint, format-check, or type-check, run them on files you touched (path-scoped when possible) before the test suite. Treat lint/type errors as step failures and fix them, including complexity findings. If the toolkit has none, skip to verify and report "not available in toolkit". Do not disable lint rules unless the plan allows it.
>    - **Verify second:** run scoped tests on the lint-clean code (or chain `lint && test` in one command). If a fix changes code, re-run lint and tests so the final bytes on disk pass both static checks and runtime assertions.
> 2. **Justified skip** — pure docs, comment-only, formatting-only, or config/skill wording with no runtime behavior: skip unit tests, state why in the report, and run validate/portable/nix (or plan Verification) checks instead. Also allowed when the step only prepares fixtures or scaffolding that a later mapped test step explicitly covers (cite that map ID).
> 3. **Do not commit or push.**
>
> Report back with:
> - Map step ID and tier.
> - Files changed (created, modified, deleted).
> - **Lint / type-check:** command(s) run, pass/fail — or "not available in toolkit".
> - **Tests:** paths added/updated, command(s) run, pass/fail — or justified skip (+ validate/portable/nix if used).
> - **Acceptance:** the command and its output, pass/fail — or `—` / no Acceptance column.
> - Issues you could not resolve.

## Full verification (after all waves)

Write `.claude/tmp/exec-claude-verify.txt` (not a tracked path; do not commit it). One command per line, as delegate `execute-via-core.md` Step 7.1 does: in-scope Acceptance, then copy-pastable Verification commands. A pipeline is one line. Skip empty acceptance and prose. Step 4 of `SKILL.md` chooses full suite or partial scope. Docs-only: validate/portable/nix commands, not a unit suite. `<skill-dir>` is the absolute directory of `execute-plan/SKILL.md`. From the repo root:

```bash
bash <skill-dir>/scripts/delegate-verify.sh /absolute/repo/root .claude/tmp/exec-claude-verify.txt
```

Exit 1 → fix Task (resume a wave agent when possible; `mid`, or `low` when mechanical), then re-run. Exit 3 (tree changed) → stop and ask. Exit 2 → stop and show stderr. Do not re-run the commands. From the output, check prose Verification bullets and coverage of the files the plan changed against the target: extend tests if below when available; never delete tests unless the replacement is equal or better. No coverage gate when Verification says unavailable.
