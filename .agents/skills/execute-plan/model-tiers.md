# Model tiers

Canonical ordered preference lists (`provider-model-version-effort`, left-to-right). Execution-map aliases: `opus` = `top`, `auto` = `mid`, `haiku` = `low`. Delegate default role: `execute` (per-backend implement pin when `model=` is omitted). Per-tool rows carry optional `status: active|parked` (default `active`) and `until: YYYY-MM-DD`.

## Master chains

- **top (`opus`)**: `claude-opus-5-5-medium (claude-code | cursor | agy, status: parked)` → `gemini-4-carbon-high (agy, status: parked)` → `gemini-4-argon-high (agy, status: parked)` → `gpt-6-astra-medium (devin)` → `grok-4-7-high (cursor)`
- **execute**: `grok-4-7-high (cursor)` → `swe-2-high (devin, until 2026-11-30)` → `gpt-6-1-terra-high (devin)` → `gemini-4-argon-medium (agy, status: parked)` → `claude-sonnet-5-5-high (agy, status: parked)` *(+ `auto` logged fallback on `cursor`)*
- **mid (`auto`)**: `gpt-6-1-sol-high (devin)` → `gemini-4-argon-medium (devin, until 2026-12-01 | agy, status: parked)` → `claude-sonnet-5-5-high (claude-code | agy, status: parked)` *(Cursor mid: none — escalate to `claude-code`)*
- **low (`haiku`)**: `gpt-6-1-terra-high (devin)` → `claude-haiku-5-5-high (claude-code | cursor)` → `composer-2-5 (cursor)` → `gemini-3-8-flash-high (agy, status: parked)`

## Fallback

Filter the tier’s chain to the active tool; first available uncapped model wins.
- **Expired rows (`until: YYYY-MM-DD`):** skip any row whose `until:` date has passed (`today > until`, local date) and log `fallback: expired <slug>`.
- **Parked rows (`status: parked`):** skip parked rows unless that backend’s enable flag is set (`AGY_ENABLED=1` makes the `agy` rows resolve again).
- **Routers (`auto` on Cursor, `adaptive` on Devin):** never run review-loop work except as a logged fallback. Cursor’s `auto` fallback fires only on: (1) the pin missing from `agent models`, (2) a run failing with a usage/quota error, or (3) an explicit `model=auto`. Record each trigger as `fallback: <reason>`.
- **Tier exhaustion:** if `low` is exhausted → fall back to `mid` (never stall a wave; on Cursor, where `mid` is none, escalate to `claude-code`). If `top` is exhausted → stop and ask.
- **Cursor model rule:** never GPT models on Cursor; Haiku 5.5 (`claude-haiku-5-5-high`) is allowed on Cursor; Sonnet only by manual `model=` override.

## Per-tool resolution

- **claude-code** (`status: active`):
  - `top` = `claude-opus-5-5` effort `medium` (`Task(model: "opus")`); `mid` = `claude-sonnet-5-5` effort `high` (`Task(model: "sonnet")`); `low` = `claude-haiku-5-5` effort `high` (`Task(model: "haiku")`). No `execute` row (in-process `/execute-plan` uses the map tiers). Always set `model:` explicitly on spawns.
- **cursor** (`status: active`; CLI uses dots in `4.7` / `2.5`; never GPT on Cursor; Haiku 5.5 is allowed on Cursor; Sonnet only by manual `model=` override):
  - `top` (`status: active`) = `claude-opus-5-5-medium` → `grok-4.7-high`
  - `execute` (`status: active`) = `grok-4.7-high` → `auto` (logged fallback when the pool runs low)
  - `mid` (`status: active`) = none (escalate to `claude-code` mid)
  - `low` (`status: active`) = `claude-haiku-5-5-high` → `composer-2.5`
- **devin** (`status: active`; pinned only — never `adaptive` or `fusion-*` for delegate; Devin CLI strips the `cognition-` prefix on `swe-2-*`):
  - `top` (`status: active`) = `gpt-6-astra-medium`
  - `execute` (`status: active`) = `swe-2-high` (`until: 2026-11-30`) → `gpt-6-1-terra-high`
  - `mid` (`status: active`) = `gpt-6-1-sol-high` → `gemini-4-argon-medium` (`until: 2026-12-01`)
  - `low` (`status: active`) = `gpt-6-1-terra-high`
  - **Standalone Devin tasks** (guidance, not a resolver row): Fusion lead `gpt-6-1-sol-high` with sidekick `swe-2-medium` (`fusion-gpt-6-1-sol-high-sidekick-swe-2-medium`, `until: 2026-11-30`), then `gpt-6-1-terra-high` (`fusion-gpt-6-1-sol-high-sidekick-gpt-6-1-terra-high`); Adaptive (`adaptive`) only for ad-hoc interactive use.
- **agy** (Antigravity; `status: parked (agy-ai-pro)`):
  - `top` (`status: parked (agy-ai-pro)`) = `claude-opus-5-5-medium` → `gemini-4-carbon-high` → `gemini-4-argon-high` (subagent `Model: "inherit"` when parent session is top, else `"pro"`)
  - `execute` (`status: parked (agy-ai-pro)`) = `gemini-4-argon-medium` → `claude-sonnet-5-5-high`
  - `mid` (`status: parked (agy-ai-pro)`) = `gemini-4-argon-medium` → `claude-sonnet-5-5-high` (subagent `Model: "inherit"` when parent session is mid, else `"flash"`)
  - `low` (`status: parked (agy-ai-pro)`) = `gemini-3.8-flash-high` (subagent `Model: "flash_lite"`)

<!-- tiers:summary:start -->
top(opus): claude-opus-5-5-medium→gpt-6-astra-medium→grok-4-7-high
execute: grok-4-7-high→swe-2-high(until 2026-11-30)→gpt-6-1-terra-high
mid(auto): gpt-6-1-sol-high→gemini-4-argon-medium(until 2026-12-01)→claude-sonnet-5-5-high
low(haiku): gpt-6-1-terra-high→claude-haiku-5-5-high→composer-2-5
<!-- tiers:summary:end -->

**Edit:** change this file, then run `bash scripts/sync-model-tiers.sh`.
