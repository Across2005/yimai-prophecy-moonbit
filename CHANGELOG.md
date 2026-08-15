# Changelog

All notable changes to **译脉·先知 2.0 (MoonBit)** are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
since `0.1.0`.

> **Pure local, zero cloud dependency** — every change below is verifiable
> on `127.0.0.1` with `scripts/dev.ps1` and `moon test --target wasm-gc`.

## [Unreleased] — P2 multi-harness & international standards

### Added
- **`docs/harness-configs/`** — drop-in MCP config samples for 12+ AI coding
  harnesses: Claude Desktop / Claude Code / Gemini CLI / Cursor / Cline /
  Continue.dev / Roo Code / Windsurf / **OpenAI Codex CLI (≥ 0.21)** /
  **Aider (≥ 0.86)** / Sourcegraph Cody / Zed / GitHub Copilot Coding Agent.
  Every sample points at the same `http://127.0.0.1:8787/mcp` Streamable HTTP
  endpoint (MCP spec 2025-11-25).
- **International translation standards section** in `AGENTS.md` mapping
  engine features to **ISO 17100:2015**, **ISO 18587:2017** (MTPE),
  **ISO 30042:2019** (TBX), **ISO 11669:2024**, **MQM Core**, and
  **W3C ITS 2.0**. (Library alignment, not certification claim.)
- `.gitignore` entry for the legacy `AGENTS.md.mcp.json` placeholder.

### Changed
- `AGENTS.md` MCP integration table now points each harness to its dedicated
  drop-in file under `docs/harness-configs/`, and links the README index.

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
