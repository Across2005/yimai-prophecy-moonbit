# Changelog

All notable changes to **译脉·先知 2.0 (MoonBit)** are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
since `0.1.0`.

> **Pure local, zero cloud dependency** — every change below is verifiable
> on `127.0.0.1` with `scripts/dev.ps1` and `moon test --target wasm-gc`.

## [Unreleased] — P3 hardening & multi-harness schema correction

### Fixed
- **`docs/harness-configs/zed.json`** — replaced non-functional `command: curl -X POST`
  shim with the proper `url` field (Zed ≥ 0.150 `context_servers` schema). The curl
  shim would exit on EOF after one request, breaking the long-lived JSON-RPC session
  MCP requires.
- **`docs/harness-configs/windsurf.json`** — corrected field name `url` → `serverUrl`
  (Windsurf schema) and added required `type: "http"`.
- **`docs/harness-configs/codex.toml`** — added required `transport = "http"`
  (Codex ≥ 0.46 refuses `url` without explicit `transport`).
- **`docs/harness-configs/continue.json`** — added `type: "streamable-http"`
  (Continue distinguishes stdio / sse / streamable-http by this field).
- **`docs/harness-configs/{cursor,claude-desktop,claude-code,gemini-cli}.json`** —
  added defensive `type: "http"` to all 4 (interoperable with current and next-gen
  client schema versions).
- **`cmd/service/routes.mbt` `send_error`** — finally replaced the last string
  concatenation (`"{\"error\":\"" + ... + "\",\"code\":\"" + ... + "\"}"`) with
  `@lib.obj` to keep the CHANGELOG 0.1.0 "JSON 注入" claim intact for the
  unified-error exit. Static-message calls had no real injection window, but
  the fix future-proofs against any caller passing dynamic `message`.
- **`cmd/service/routes.mbt` `handle_bleu` / `handle_chrf`** — renamed local
  variable `ref` to `ref_str` to avoid the (currently non-reserved) keyword
  and improve readability.
- **`cmd/service/routes.mbt`** — fixed 3 over-indented `if !saved { println(...) }`
  continuations in `consolidate` / `fed_import` / `distill_inject` (8-space
  hanging indent → 6-space, matching the 3 sibling handlers).
- **`cmd/service/mcp.mbt` `handle_initialize`** — `serverInfo.version` now
  reads from `@lib.api_version` (was hardcoded `"2.0.0"`; now `"0.1.0"`
  consistent with `moon.mod` and `/api/health`).
- **`yimai_prophecy_moonbit.mbt` `error_codes`** — table expanded from 3 to
  **6 codes**, matching all 7 `send_error` call sites. The 3 missing codes
  (`unknown_mid` / `internal_error` / `align_failed`) were emitted but not
  registered. The `L22` test in `yimai_prophecy_moonbit_routes_test.mbt`
  was updated in lockstep.
- **`yimai_prophecy_moonbit_*_test.mbt`** — replaced 5 deprecated
  `Json.to_string()` calls with `.stringify()` in the R15 determinism
  assertions (warnings down from 19 → 12; remaining are unrelated
  upstream deprecations and `Array.to_string` in `roadmap_test.mbt:79`
  which is debug output not a stable comparison).
- **`docs/harness-configs/cody.json`** — stripped 6 noise `cody.*` settings
  that would have overwritten user config; added deprecation banner
  (Sourcegraph sunset Cody 2025-08; AI mainline → Amp).
- **`docs/harness-configs/github-copilot.yml`** — corrected: Copilot Coding
  Agent runs on GitHub-hosted `ubuntu-latest` runners, which can't reach
  `127.0.0.1:8787` on the local dev machine. File is no longer advertised
  as a drop-in; the snippet now points to the actual integration path
  (`.github/workflows/copilot-setup-steps.yml`).
- **`docs/harness-configs/README.md`** — fixed the `HTTP (stdio)` line
  (Continue / Aider rows), added a "form" column, added 2026-08 spec
  status note, added the `Accept: application/json, text/event-stream`
  header to the verifying curl.

### Added
- **`AGENTS.md` "Map ≠ HashMap" gotcha** — `Map[String, T]` is **ordered by
  insertion** and is load-bearing for the R15 determinism contract. This
  was a hidden gotcha; the audit (0.1.0 review) flagged it as a silent
  regression risk.
- **`AGENTS.md` TBX3 dialect clarification** — `ISO 30042:2019` = **TBX3**
  (v3.0), not TBX2 (v2.0). The two dialects differ in XML namespace and
  structure; `load_tbx` must conform to TBX3 to be spec-valid.
- **`AGENTS.md` "Roadmap (not implemented in 0.1.0)"** — declared
  **TMX 1.4b** and **XLIFF 2.1 / ISO 21720:2024** as v0.2 candidates
  (engine already has `parse_tmx` / `parse_xliff` as `pub fn` but no
  endpoint yet). Documented why (CAT-tool interoperability).
- **`AGENTS.md` MQM severity scale** — added standard `None=0 / Minor=1 /
  Major=5 / Critical=10` recommendation for any future MQM scorer.
- **`AGENTS.md` ISO 11669 TS disclaimer** — clarified that ISO 11669:2024
  is a **Technical Specification**, not a full IS.
- **`AGENTS.md` MCP `2026-07-28` RC note** — documented the upcoming
  breaking change (initialize handshake removal, `Mcp-Method`/`Mcp-Name`
  headers, JSON Schema 2020-12, error code `-32602`); not in this release
  — deferred to 0.2.0 to keep 0.1.x clients stable.

### Changed
- `AGENTS.md` MCP integration table: corrected Claude Desktop macOS
  path (`~/Library/Application Support/Claude/claude_desktop_config.json`,
  was `~/.config/claude-desktop/mcp.json`); added schema-specific notes
  per harness (`transport = "http"` for Codex ≥ 0.46, `serverUrl` for
  Windsurf, `type: "streamable-http"` for Continue, `url` for Zed ≥ 0.150).

## [0.1.0] — 2026-08-15 — P1 hardening

### Added
- `tools/call` returns `isError: true` when engine reports an `error` field
  (MCP spec 2025-11-25).
- `/mcp` parse error returns proper JSON-RPC `-32700` instead of a bare string.
- `/mcp` unknown-method error returns proper JSON-RPC `-32601` (was `-32600`).
- `tool_def` declares `additionalProperties: false` on every tool's
  `inputSchema` (JSON Schema 2020-12; mcp-lint / OpenAI Agents SDK strict mode).
- `routes_meta` synced to 26 REST endpoints; routes table is single-sourced.
- `send_error` / `read_json_or_400` helpers consolidate the 4xx responses;
  every handler routes invalid JSON to a uniform 400 with stable `code`.
- `/api/health` reports `degraded` when the last `save_store` failed, and
  `uptime_seconds` from a one-shot `start_time_ms` (avoids drift on each call).
- `docs/skill/SKILL.md` frontmatter for agent skill registries.

### Fixed
- JSON injection: replaced string-concatenated responses in `/api/add_tm`,
  `/api/ping`, panic handler with `@lib.obj` builders.
- CJK comment with reversed direction note (`最大字节数 1 MiB`) corrected
  (`char-count` is in fact looser; defence-in-depth guard still retained).
- Top-level `try/catch` around every handler so an uncaught panic returns
  500 instead of hanging the connection.

## [0.1.0] — 2026-08-15 — P1 hardening

### Added
- `tools/call` returns `isError: true` when engine reports an `error` field
  (MCP spec 2025-11-25).
- `/mcp` parse error returns proper JSON-RPC `-32700` instead of a bare string.
- `/mcp` unknown-method error returns proper JSON-RPC `-32601` (was `-32600`).
- `tool_def` declares `additionalProperties: false` on every tool's
  `inputSchema` (JSON Schema 2020-12; mcp-lint / OpenAI Agents SDK strict mode).
- `routes_meta` synced to 26 REST endpoints; routes table is single-sourced.
- `send_error` / `read_json_or_400` helpers consolidate the 4xx responses;
  every handler routes invalid JSON to a uniform 400 with stable `code`.
- `/api/health` reports `degraded` when the last `save_store` failed, and
  `uptime_seconds` from a one-shot `start_time_ms` (avoids drift on each call).
- `docs/skill/SKILL.md` frontmatter for agent skill registries.

### Fixed
- JSON injection: replaced string-concatenated responses in `/api/add_tm`,
  `/api/ping`, panic handler with `@lib.obj` builders.
- CJK comment with reversed direction note (`最大字节数 1 MiB`) corrected
  (`char-count` is in fact looser; defence-in-depth guard still retained).
- Top-level `try/catch` around every handler so an uncaught panic returns
  500 instead of hanging the connection.

## [0.0.x] — initial public drops

- D1–D8 prediction engine (`engine.mbt` 121 KB, ~3.3 K LOC) + deterministic
  memory network with Hebbian learning, second-order Markov, role-index
  cold-start, adaptive LR, elastic forgetting, attention edge weights, WAL.
- #22 TM/TB: `add_tm` / `fuzzy_match` (S1 4-component white-box scoring) /
  `concordance` / `load_tbx` (ISO 30042) / `enforce_terms` / `check_terms`.
- REST: 13 base endpoints + 11 supplementary = 24 `/api/*` + `/mcp` MCP
  Server (24 tools) + web workbench (3-panel UI).
- Persistence: `tm_store.json` atomic write (tmp+rename); survives restart.
- One-shot `scripts/dev.ps1` (env-check → build → start → seed → smoke).
- `moon test --target wasm-gc` green: 101/101 (101 contracts).
- Hit@3 = 0.8246 on 8-domain modern corpus (2025–2026).
- `.githooks/pre-commit` gates every commit on `moon check && moon test`.
