<!-- Generated from nng-kit/plugins/lifecycle/model-tiers.md. Do not edit. -->

## Fallback

Resolve with `tiers.sh resolve <tool> <tier>` (`tiers.sh` = `bash <skill-dir>/../execute-plan/scripts/tiers.sh` in lifecycle skills, `bash <skill-dir>/../../scripts/tiers.sh` in delegate skills; `<host>` in skill preconditions is the registry id of the tool running the session, not `tiers.sh host`, which is only the default); the rows below are generated from the registry and follow these rules.
Spawn Tasks per the host: `<skill-dir>/../execute-plan/hosts.md`.
- **Expired rows (`until: YYYY-MM-DD`):** skip any row whose `until:` date has passed (`today > until`, local date) and log `fallback: expired <slug>`. A tool-level `until` (shown in the tool's header) applies to every row of that tool.
- **Planning fallback order:** per `tiers.sh order` (registry `planningOrder`), handing off via `/relay:save` + `/relay:pickup`.
- **Routers:** Cursor `auto` (Cost mode, included pool) only (1) as the logged fallback for Cursor `execute`, `mid`, and `low` (existing triggers: the pin missing from `agent models`, a usage/quota error, or an explicit `model=auto`; record `fallback: <reason>`), or (2) on a map row with `Model: auto` + `Tier: low` + `Runner: delegate:cursor`, recorded `auto(router)`. Never on top or review work. Devin `adaptive` never: it costs more than the pins and has no pool advantage.
- **Tier exhaustion:** if `low` is exhausted → fall back to `mid` (never stall a wave). `top-plan` → next tool in the planning fallback order. `top-review` → `top@devin-fusion` when Devin is enabled and not the host, logged `fallback: top-review exhausted`; otherwise stop and ask.
- **Review family:** a mid review pass prefers an allowed model from a different family than the implementer's; if the host has none at mid, proceed and log `same-family mid review` in the run notes. On Cursor the second family is `claude-sonnet-5-5-high` (third-party pool; the one exception to Cursor-models-only for `mid`); on Devin it is `gpt-6-1-sol-high` against the SWE-2 implementer; when the Devin implementer fell back to GPT, keep that reviewer and log `same-family mid review`. agy: the reviewer inherits the session model; log `same-family mid review`. Top-review is unaffected.
- **Cursor model rule:** on Cursor, `execute`/`mid`/`low` use Cursor models only (Grok for `execute`/`mid` pins, Composer 2.5, Auto), except `mid` review passes, which use `claude-sonnet-5-5-high`. Other Claude models only for `top-plan`/`top-review`, or by a manual `model=` override. Never GPT.

## Per-tool resolution

<!-- tiers:generated:per-tool:start -->
- **claude-code** (Claude Code; cli `claude`; default review runner `top@claude-task`):
  - `top-plan` = `claude-opus-5-5` (effort high (xhigh for large/risky plans); Task(model: "opus"))
  - `top-review` = `claude-opus-5-5` (effort medium; Task(model: "opus"))
  - `execute` = none (resolves to `mid`)
  - `mid` = `claude-sonnet-5-5` (effort high; Task(model: "sonnet"))
  - `low` = `claude-haiku-5-5` (effort high; Task(model: "haiku"))
- **cursor** (Cursor; cli `agent`; delegate; default review runner `top@claude-headless`):
  - `top-plan` = `claude-opus-5-5-high`
  - `top-review` = `claude-opus-5-5-medium` (--mode=ask)
  - `execute` = `grok-4.7-high` → `auto` (logged fallback)
  - `mid` = implement: `grok-4.7-high` → `auto` (logged fallback); review passes: `claude-sonnet-5-5-high` (Cursor third-party pool)
  - `low` = `composer-2.5` → `auto` (logged fallback)
- **devin** (Devin; cli `devin`; delegate; default review runner `top@claude-headless`):
  - `top-plan` = `claude-opus-5-5-high` (plain Opus, no Fusion: planning exploration stays on the lead)
  - `top-review` = `fusion-claude-opus-5-5-medium-sidekick-swe-2-medium` (provisional until the Fusion-vs-plain-Opus review test)
  - `top-critique` = `gpt-6-1-sol-high` → `gpt-6-1-terra-high`
  - `execute` = `swe-2-high` → `swe-2-medium` → `gpt-6-1-terra-high`
  - `mid` = implement: `swe-2-high` → `swe-2-medium` → `gpt-6-1-terra-high`; review passes: `gpt-6-1-sol-high` → `claude-sonnet-5-5-high` → `kimi-k3-1-pro-high`
  - `low` = `swe-2-medium` → `claude-haiku-5-5-high`
- **agy** (Antigravity; cli `agy`; delegate; default review runner `top@claude-headless`):
  - `top-plan` = `claude-opus-5-5-high` (subagent Model: "inherit" when parent session is top, else stop)
  - `top-review` = `claude-opus-5-5-medium` (--mode plan; subagent Model: "inherit" when parent session is top, else stop)
  - `top-critique` = `gemini-4-argon-high`
  - `execute` = `gemini-4-hydrogen-high` → `gemini-4-argon-medium`
  - `mid` = implement: `gemini-4-hydrogen-high` (subagent Model: "inherit"; skip unless session is this model) → `gemini-4-argon-medium` (subagent Model: "inherit"; skip unless session is this model); review passes: `gemini-4-argon-medium` (subagent Model: "inherit"; skip unless session is this model; logged "same-family mid review") → `gemini-4-hydrogen-high` (subagent Model: "inherit"; skip unless session is this model; logged "same-family mid review")
  - `low` = `gemini-4-hydrogen-medium` (subagent Model: "flash_lite" = gemini-3.5-flash-lite)
<!-- tiers:generated:per-tool:end -->

<!-- tiers:tool-notes:start -->
- **claude-code:** Always set `model:` explicitly on spawns.
- **devin:** never `adaptive` or `fusion-*` for `execute`/`mid`/`low`; Fusion only for `top-review`; Devin CLI strips the `cognition-` prefix on `swe-2-*`.
  - **Standalone Devin tasks** (guidance, not a resolver row): Fusion lead `gpt-6-1-sol-high` with sidekick `swe-2-medium` (`fusion-gpt-6-1-sol-high-sidekick-swe-2-medium`), then `gpt-6-1-terra-high` (`fusion-gpt-6-1-sol-high-sidekick-gpt-6-1-terra-high`); Adaptive (`adaptive`) only for ad-hoc interactive use.
- **agy:** pools: Generic (largest) `execute`, `mid` implement, `low`; Argon `top-critique`, overflow, Argon-session `mid` review; Claude + GPT only `top-plan`/`top-review`.
<!-- tiers:tool-notes:end -->

## Review runners

- `top@session` = the host session at `top-review` (a `mid` `/execute-plan` orchestrator uses the host's `defaultReviewRunner`)
<!-- tiers:generated:review-runners:start -->
- `top@claude-task` = Claude Code `top-review` pin, mode `task`
- `top@claude-headless` = Claude Code `top-review` pin, mode `headless`
- `top@cursor-ask` = Cursor `top-review` pin, mode `ask`
- `top@devin-fusion` = Devin `top-review` pin, mode `auto`
- `top@agy-plan` = Antigravity `top-review` pin, mode `plan`
<!-- tiers:generated:review-runners:end -->

External runners (every runner except `top@session` and `top@claude-task`) run through the delegate plugin's review launcher. They read the host's verify-script summary and never run Verification themselves, and they run under a git guard that reverts any reviewer edit. A reviewer failure (launch error, quota, timeout, guard trip, missing or inconsistent verdict) → stop and ask: retry, the host's `defaultReviewRunner`, or abort.
