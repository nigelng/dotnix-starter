# Subagent hosts

Spawn every Task per the host (the tool running this session). Pins: [model-tiers.md](model-tiers.md).

- **claude-code:** `Task` with `model:` set to the tier's alias (`opus`, `sonnet`, `haiku`).
- **cursor:** `Task` with the resolved model slug.
- **devin:** `run_subagent` with `profile: kit-<role>`. Write: `kit-execute`, `kit-mid`, `kit-low`. Read-only (no shell: run each Task's commands here into `.claude/tmp/exec-claude-review-*`, pass paths): `kit-review-mid`, `kit-review-top`, `kit-critique` (`top-critique`). Install per the kit README. Profile not offered: stop and tell the user (`/critique plan`: fallback). The profile's `model:` is the resolved model; if it differs from `tiers.sh resolve devin <tier>` (read-only: `--role review`), warn once and log it.
- **agy:** `invoke_subagent`: `Model: inherit` for this session's tier (`execute` = `mid`), incl. its `mid` review (logged `same-family mid review`), `flash_lite` for `low`; other tier (`mid`/`execute` from `top`, `top` from Gemini) or no row matching the session model: stop.

No write top Task (devin: no write top profile; agy: no `top` alias): a `top` row with Files runs here if this session is top tier, else stop and tell the user. Never use a read-only or default profile for writes.

Any other host, or no way to pin the model: stop and tell the user before delegating (unattended: fail the row, report why).
