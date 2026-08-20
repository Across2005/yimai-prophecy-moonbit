# Changelog

All notable changes to **译脉·先知 2.0 (MoonBit)** are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
since `0.1.0`.

> **Pure local, zero cloud dependency** — every change below is verifiable
> on `127.0.0.1` with `scripts/dev.ps1` and `moon test --target wasm-gc`.

> **Note on `[Unreleased]` multiplicity**: this repo's development style
> runs multiple parallel "P" increments (P3 / P4 / P5 / P6) against the same
> unreleased trunk. Per Keep a Changelog 1.1.0 "SHOULD" recommendation, we
> keep **one canonical `[Unreleased]` at the top** (containing the *latest*
> active increment) and let earlier parallel increments remain tagged with
> their own dated headers below. Future 0.2.0 release will fold them into a
> single dated version.

## [Unreleased] — P6 hardening, multi-harness compat & repo tidy

### Fixed
- **`cmd/service/routes.mbt` `MAX_BODY_BYTES` → `MAX_BODY_CHARS`** — renamed and clarified char-count limit; added `Content-Length` pre-check for non-MCP POST requests and hardened JSON body error handling.
- **`cmd/service/mcp.mbt` `/mcp` body size protection** — added `Content-Length` pre-rejection and JSON-RPC `-32700` error response for oversized bodies; switched unknown tool error from `-32601` to `-32602`.
- **`cmd/service/mcp.mbt` `tools/call` required-field validation** — added `check_required_fields` for all tools with required args, returning `-32602 Invalid params` on missing fields.
- **`cmd/service/routes.mbt` `serve_static`** — hardened path traversal defense: reject absolute paths, leading slashes, drive colons, and null bytes; extracted `WEB_ROOT` constant and `is_safe_static_path` helper.
- **`engine.mbt` WAL separator injection** — `text`/`mtype` fields are now escaped with `wal_escape_field` on append and unescaped on replay; unknown `op` values are skipped during `wal_replay`.
- **`util.mbt` `align_diff` DoS** — added `MAX_ALIGN_CHARS` / `MAX_ALIGN_CELLS` limits to prevent OOM from maliciously long `source`/`target` inputs.
- **`cmd/service/tm_store.mbt` `load_store`** — added `MAX_STORE_CHARS` soft cap and warning on oversized `tm_store.json`.
- **Deprecated API cleanup** — replaced `.size()` → `.length()`, `not(...)` → `!...`, `Map::new()` → `Map([])`, `StringView.to_string()` → `to_owned()` in engine/util; added `moonbitlang/core/json` imports in `tests/core/moon.pkg` and `tests/corpus/moon.pkg`.
- **Documentation count sync** — README.md/AGENTS.md/CLAUDE.md/GEMINI.md/docs/skill/SKILL.md/docs/harness-configs/README.md/scripts now consistently state 27 REST endpoints and 25 MCP tools (was 24/24).
- **`AGENTS.md` standards table** — ISO 11669:2024 is now a full standard (replaced ISO/TS 11669:2012); ISO 21720:2024 noted as second edition; XLIFF 2.2 in Committee Specification as of 2025-03.
- **`scripts/smoke.ps1` portability** — removed UTF-8 BOM and replaced Chinese string literals/check names with ASCII to keep `powershell -File` reliable across OEM code pages.
- **`scripts/validate-harness-configs.ps1` robustness** — extracted `Test-ValidEnumField` helper to DRY up type/transport whitelist validation; cast values to string before comparison.
- **`moon.mod`** — corrected `readme` from deleted `README.mbt.md` to `README.md`.

### Added
- **`docs/plans/2026-08-19-full-audit-and-hardening.md`** — plan marker and baseline record for the P6 audit.
- **`docs/plans/2026-08-19-security-audit.md`** — security audit report (Critical/High/Medium/Low findings).
- **`docs/plans/2026-08-19-quality-audit.md`** — code quality audit report.
- **`docs/plans/2026-08-19-harness-audit.md`** — MCP/harness compatibility audit report.
- **`docs/plans/2026-08-19-translation-standards-research.md`** — frontier international translation standards research report.

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

## [Unreleased] — P4 hardening, refactor, quality & docs (2026-08-17)

7 commits (a3df919 + 0a1ded0 + e15142a + bb4b389 + 931c011 + 8857bc2 + 09edae8);
test count 137 → 151 → 159 (+22). All changes pass `moon test --target wasm-gc`.

### Security
- `decode_pct` URL decode in `util.mbt` — defends path traversal
  (`serve_static` detects `..` and `\\` before percent-decode).
- MCP `notifications/*` wildcard in `cmd/service/mcp.mbt` dispatch —
  JSON-RPC 2.0 spec compliant; supports `notifications/initialized`.
- `/api/health` version sync — uses `@lib.api_version` single source.

### Added
- `distill_inject` `ignored` field — surfaces schema errors for debugging.
- `drift_report.text_chrf_avg` / `_n` — translation quality drift metric
  (pure local, zero dependency).
- MQM severity numeric scoring — None=0 / Minor=1 / Major=5 / Critical=10.
- `routes_test.mbt` derived — `build_known_handlers` from `routes_meta`.
- `README.md` "International Standards & Compliance" section (ISO 5060:2024,
  EU AI Act, GDPR, MQM Council, MCP integration).
- `yimai_prophecy_moonbit_frontier_corpus_test.mbt` — 10 frontier domains
  (AI Safety×2, Science, Math×2, Philosophy, Digital Humanities, CBT,
  Aviation, Space), 60 sentence pairs, 14 tests (T38–T51).
- Regression tests T30–T37 (quality/security) and T38–T51 (frontier corpus).

### Changed
- `fuzzy_match` / `fuzzy_match_full` shared helpers — `fuzzy_score_one` /
  `fuzzy_pack_top` remove 99% duplication; R15 sort contract preserved.
- `is_known_tool` uses `Array::contains` — eliminates 25 hardcoded strings.
- `routes_meta` single source — `lookup_route` uses `@lib.routes_meta`
  (no 27 hardcoded entries).
- `predict` split into 3 — `predict_collect_activations` /
  `predict_aggregate_transitions` / `predict_rank_and_pack`; main function
  drops 269 → 41 lines.
- `consolidate` split into 4 — `consolidate_edge_decay` / `_trans_decay` /
  `_prune_nodes` / `_meta_cognition`; main drops 112 → 28 lines.
- `save_store` depth guard — `MAX_SAVE_DEPTH=3` (added in P4; removed in
  a later cleanup phase as dead defense).
- Test counts synced 89/101 → 137 → 151 → 159 across badges / gate sections /
  roadmap / AGENTS.md.
- `docs/skill/SKILL.md` frontmatter — P4 summary + trigger words (MQM /
  drift_report / severity_score).

### Stats
| Indicator | Value |
|---|---|
| Commits | 7 |
| Files | 21 modified |
| Code change | +561 / -238 lines |
| New tests | 22 (T30–T37 quality/security + T38–T51 frontier) |
| Test total | 137 → 151 → 159 |
| Pass rate | 159/159 (100%) |

## [Unreleased] — P5 I18n-Hardening & Multi-Harness Connectivity (2026-08-19)

### Added (5 commits)
- **`docs/harness-configs/harness_manifest.json`** — 13 harness schema 单一源清单
  (form / top_key / required_fields / client_reads / notes)；将 13 个 drop-in config
  的契约从 13 个散落文件收敛为 1 个 JSON，便于自动化校验和 adopter 集成。
- **`scripts/validate-harness-configs.ps1`** — 自动化 schema 校验脚本（Windows PS 5.1
  兼容，UTF-8 BOM 编码）：JSON 走 `ConvertFrom-Json`、TOML 手写 mini-parser、YAML
  降级文本搜索；13/13 PASS，退出码 0/1。
- **`POST /api/mqm_re_annotate`** + `cmd/service/mcp.mbt` `mqm_re_annotate` tool —
  MQM 二次标注（Google 2025-10-28 论文对齐）：所有 Critical severity 段强制走二次审，
  显式产出 `re_annotated` / `critical_count` / `re_annotations` 三段式 JSON；当前是
  deterministic 自重审（consistent=true），接口设计保留未来多标注员模型扩展空间。
- **`yimai_prophecy_moonbit_business_corpus_test.mbt`** — 商务领域 8 句语料
  (合同 / 商务信函 / 招投标 / 议价 / 付款条件 / 装运 / 索赔 / 仲裁)，
  对齐 ISO 11669:2024 + GB/T 30539-2025 中国商务领域语言服务国家标准。
- **README / AGENTS.md / SKILL.md** — MQM 严重度三方对齐文档化（yimai vs Phrase vs
  Lokalise），含 severity_score 转换公式与设计差异说明。

### Tests
- 测试数量：151 → 159（T38–T41 mqm_re_annotate × 4 + T42–T44 商务语料 × 3 + 1 集合）
- 16/16 P5 增量测试全绿；pre-commit 门禁保持绿色
- `routes_meta`：26 → 27（加 mqm_re_annotate）；`L19` 测试同步
- MCP `known_tool_names`：24 → 25（加 mqm_re_annotate）
- 13 harness configs 全部通过 `validate-harness-configs.ps1` 自动校验

### Documentation alignment
- README MQM 段：新增三方对齐表（yimai severity_score / Phrase penalty / Lokalise vs 100）
- AGENTS.md 标准对齐表：新增"MQM Re-annotation"行（Riley et al. 2025-10-28）
- AGENTS.md 新增"### MQM severity scale (cross-tool alignment, P5 increment)"子段
- SKILL.md frontmatter tips：新增 severity_scale / Phrase / Lokalise / ISO 11669 /
  GB/T 30539 / 商务领域 / re_annotate / 二次标注 关键词

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
