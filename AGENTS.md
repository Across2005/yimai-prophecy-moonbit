# AGENTS.md — AI Agent Out-of-the-Box Guide

This file tells AI agents (Claude, Copilot, Cursor, code agents, …) how to use
this repository immediately after cloning. Read this first.

> **Multi-harness companion files** (auto-loaded by specific agents):
> - [`CLAUDE.md`](./CLAUDE.md) — Claude Code (Anthropic CLI)
> - [`GEMINI.md`](./GEMINI.md) — Gemini CLI (Google)
> - Both point back to this file for the full multi-harness guide.

## What this project is

**译脉·先知 2.0** — a deterministic memory-prediction engine written in
[MoonBit](https://www.moonbitlang.com), zero third-party dependencies
(`core/json` + `core/math` only). It remembers workflows / translation-memory
entries and predicts the next step, with white-box explanations.

Three layers, one language (no bridge code):

| Layer | Where | What |
|---|---|---|
| Layer 0 · engine | `engine.mbt` / `util.mbt` | D1-D8 memory network + #22 TM/TB + #2-#7 extensions + S1 fuzzy-match |
| Layer 2 · service | `cmd/service/` | 24 REST endpoints (`/api/*`) + `/mcp` MCP server + web workbench |
| Layer 1 · knowledge | `README.md`, `AGENTS.md`, web workbench | docs + how-to |

## Fast start (Windows, verified environment)

```powershell
# one-shot: env check -> build -> start service -> seed sample TM -> smoke test
powershell -ExecutionPolicy Bypass -File scripts/dev.ps1
```

Or step by step:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup.ps1   # detect moon/MSVC, validate cl.exe paths
powershell -ExecutionPolicy Bypass -File scripts/build.ps1   # compile cmd/service (native)
powershell -ExecutionPolicy Bypass -File scripts/run.ps1     # start http://127.0.0.1:8787
powershell -ExecutionPolicy Bypass -File scripts/seed.ps1    # load sample TM pairs (optional)
powershell -ExecutionPolicy Bypass -File scripts/smoke.ps1   # verify endpoints + MCP
```

Engine tests (no MSVC needed):

```bash
moon test --target wasm-gc        # 151/151 green (P4 + frontier corpus 后)
```

## Consuming the service

- **REST**: 24 个 `/api/*` 端点（多数 `POST` JSON 体，`/api/ping` 与 `/api/tm_count` 为 GET）。示例
  `POST /api/fuzzy_match {"query":"电池包热管理方案","k":3,"threshold":0.5}` → Top-K with
  white-box scores (`sim_token/sim_tfidf/sim_char/sim_ngram/sim_tokenset`)（详见 `README.md` → Service Layer）。
- **MCP**: `POST /mcp` speaks JSON-RPC 2.0 (spec 2025-11-25). `initialize` → `tools/list` (24 tools)
  → `tools/call {"name":"fuzzy_match","arguments":{...}}`. Standard MCP config:
  `{"mcpServers":{"yimai":{"url":"http://127.0.0.1:8787/mcp"}}}`.
- **Web workbench**: open `http://127.0.0.1:8787/` (three panels: TM search / term check / evidence chain).
- **Persistence**: writes `tm_store.json` (atomic tmp+rename) next to the service working directory;
  restart restores state automatically.

## MCP integration per harness

| Harness | Config file | Drop-in sample |
|---|---|---|
| **Claude Desktop** | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows) | `docs/harness-configs/claude-desktop.json` |
| **Claude Code** | `~/.claude/mcp.json` or via `/mcp` slash command | `docs/harness-configs/claude-code.json` ([`CLAUDE.md`](./CLAUDE.md)) |
| **Gemini CLI** | `~/.gemini/settings.json` | `docs/harness-configs/gemini-cli.json` ([`GEMINI.md`](./GEMINI.md)) |
| **Cursor** | `~/.cursor/mcp.json` | `docs/harness-configs/cursor.json` |
| **Cline** | VS Code → Cline → MCP Servers → Add → name=`yimai`, type=`http`, url=`http://127.0.0.1:8787/mcp` | `docs/harness-configs/cline.json` |
| **Continue.dev** | `~/.continue/config.json` under `"mcpServers"` (use `type: "streamable-http"`) | `docs/harness-configs/continue.json` |
| **Roo Code** | VS Code → Roo Code → MCP → Add Server (HTTP transport) | `docs/harness-configs/roo-code.json` |
| **Windsurf / Cascade** | `~/.windsurf/mcp.json` (use `serverUrl` + `type: "http"`) | `docs/harness-configs/windsurf.json` |
| **OpenAI Codex CLI** (≥ 0.21) | `~/.codex/config.toml` or `<repo>/.codex/config.toml` (≥ 0.46 needs `transport = "http"`) | `docs/harness-configs/codex.toml` |
| **Aider** (≥ 0.86) | `~/.aider.conf.yml` or `<repo>/.aider.conf.yml` | `docs/harness-configs/aider.conf.yml` |
| **Sourcegraph Cody** | Cody → Settings → MCP Servers — *deprecated 2025-08, use other harness* | `docs/harness-configs/cody.json` |
| **Zed** | `~/.config/zed/settings.json` under `context_servers` (≥ 0.150 uses `url` field) | `docs/harness-configs/zed.json` |
| **GitHub Copilot (Coding Agent)** | `.github/workflows/copilot-setup-steps.yml` (snippet, runner caveat) | `docs/harness-configs/github-copilot.yml` |

All clients use the same MCP shape. The only thing that varies is the config
file path. After `scripts/run.ps1` is up, all clients should be able to
`tools/list` and see the 24 tools.

> 📁 **Full sample set** (one file per harness + per-harness install path
> table) lives under [`docs/harness-configs/`](./docs/harness-configs/README.md).

## Windows prerequisites (native build)

- **MSVC** is mandatory for `cmd/service` native target (async `thread_pool.c` has a hard `#error`
  otherwise; mingw/gcc won't work).
- `link.native.cc` in `cmd/service/moon.pkg` and `cmd/main/moon.pkg` points at `cl.exe`. **If the
  path is machine-specific, update both files** (setup.ps1 detects a missing cl.exe and prints a hint).
- After a **MoonBit toolchain upgrade**, rebuild the core native bundle once:
  `cd ~/.moon/lib/core && moon clean --target-dir _build/native && moon bundle --target native --release`
  (otherwise `moonc` link asserts).

## Code conventions

- Engine must stay **zero-dependency** (`core/json` + `core/math` only). All I/O lives in `cmd/service`.
- Determinism is a hard contract: same input ⇒ byte-identical `to_json` output (R15).
- MoonBit gotchas:
  - async calls need **no `await`** (`await` is a reserved word).
  - no top-level `let mut` — use `@ref.Ref[T]` (see `cmd/service/main.mbt`).
  - `Json` is an FFI type: **cannot construct values** like `Json::Object`/`Json::Bool`; build them
    via `@lib.obj/str_json/num_json/arr_json` (util.mbt) or `Int.to_json()/Bool.to_json()` (builtin ToJson).
  - `Request.path` includes the full query string — strip `?` before routing (see `extract_base_path`).
  - `@fs.write_file` default `create_mode=TruncateExisting` fails when the file is absent — pass
    `create_mode=@fs.CreateMode::CreateOrTruncate` for first writes.
- `moon fmt` reformats the whole repo (2585-line diffs historically) — avoid unless asked.
- **Map ≠ HashMap** — `Map[String, T]` (MoonBit) is **ordered by insertion** and is
  load-bearing for the determinism contract (R15): `predict` scores, `fuzzy_match` ranking,
  `metrics` JSON field order all depend on iteration order. Do **not** swap in `@hashmap`
  or any `HashSet/HashMap` from a hypothetical future stdlib — that would break R15 silently.
- Keep `moon test --target wasm-gc` green on every change.

## Project layout (where new files go)

P5 仓库整理（2026-08）：所有新增文件必须落到合适目录，**禁止再散落在根目录**。

| 文件类型 | 落点 | 命名规范 |
|---|---|---|
| Lib 源文件（pub 导出） | 根目录 | `engine.mbt` / `util.mbt` / `yimai_prophecy_moonbit.mbt`（按需新建） |
| Lib 测试 (`*_test.mbt` / `*_wbtest.mbt`) | `tests/{core,corpus,feature}/` | `yimai_prophecy_moonbit_<topic>_test.mbt` |
| Sub-package moon.pkg | `tests/<sub>/moon.pkg` | 每加一个子包必须新建 |
| 跨子包共享 helper | `tests/<sub>/_test_helpers.mbt`（同子包内 `pub`） | DRY 注释：与同子包内 `_test_helpers.mbt` 同步 |
| Binary 入口 | `cmd/main/` 或 `cmd/service/` | new service 在 `cmd/<name>/` |
| 文档 | `docs/<topic>/` | 不再放 `docs/superpowers/...` 中间层 |
| 一次性 plan/notes | `docs/plans/` | 文件名带日期 `YYYY-MM-DD-<topic>.md` |
| 中文文件名 | **禁止** | 重命名为英文（仓库国际友好） |
| 散落占位文件（如 `*.mcp.json`） | 删 | 已废弃的占位不进仓 |
| 调试脚本 | **不入仓** | 用完即删；只留可复现的正式脚本进 `scripts/` |

**关键约束**：
- MoonBit 0.1.20260724 不支持 sub-package 跨包 import：每个 `tests/<sub>/` 是独立 package，**helper fn 必须 inline 在子包内**（共享 helper 写到 `_test_helpers.mbt` + 跨子包各复制一份），或者提到 `lib` 主包（污染 API，慎用）。
- 跨子包 helper 改了要在所有副本同步（已加注释提醒）。
- 根 `moon.pkg` 范围 = 根目录直系 .mbt，**不含 `tests/**`**。每个子包有自己 moon.pkg。

## International translation standards (alignment, not certification)

This engine is a **technical building block**, not a translation service, so it
isn't itself certifiable — but the features map cleanly to the workflows the
following international standards describe, so adopters can wire yimai into
ISO-conformant pipelines:

| Standard | What it covers | How yimai fits |
|---|---|---|
| **ISO 17100:2015** (Translation services — Requirements) | Translator competence, project management, technical resources, post-delivery feedback | `observe`/`predict` + `reward` give the post-delivery feedback loop; `retrieve_prompt` injects bilingual context into the LLM step; `consolidate` is the meta-cognitive review that ISO 17100 §5.5 expects for "technical revision" |
| **ISO 18587:2017** (Post-editing of machine translation output) | MTPE workflow, post-editor competence, output quality | `qe_auto` (QE + MQM tagging) and `bleu`/`chrf` measure MT output before/after post-edit; `retrieve_prompt` injects TM hits into the post-edit LLM step |
| **ISO 30042:2019 / TBX3** (TermBase eXchange, v3 dialect) | TermBase XML schema for terminology exchange (TBX3 v3.0, not TBX2 v2.0 — namespace and structure changed) | `load_tbx` parses ISO 30042-compliant `<martif>/<termEntry>` XML; `add_tm` + `check_terms` enforce term consistency (the "TB" half of TM/TB) |
| **ISO 11669:2024 (TS)** (Translation projects — General guidance) | Project lifecycle, deliverables, sign-off — **TS** (technical specification) | `predict` is the per-step next-action recommender; `consolidate` is the project-completion review |
| **MQM / MQM Core** (Lommel et al., 2014–present) | Multidimensional Quality Metrics for translation evaluation. Standard 7 dimensions (terminology / accuracy / linguistic / style / locale / audience / design); standard severity scale **None=0 / Minor=1 / Major=5 / Critical=10** | `qe_auto` returns an MQM-shaped tag set; `back_align` produces the alignment script MQM fluency/accuracy annotations are anchored to. If you add a custom MQM scorer, prefer the standard severity scale for cross-tool comparability. |
| **MQM Re-annotation** (Riley et al., Google, 2025-10-28) | Two-stage MQM review: a second rater reviews an existing annotation (human or auto), reducing inter-rater variance. The paper reports stronger rater agreement and reliability across all re-annotation scenarios, including LLM-generated annotations like GEMBA-MQM and AutoMQM. | P5 `mqm_re_annotate` walks the same path on every Critical-severity issue: it re-runs `mqm_tags` and emits `re_annotated` / `critical_count` / `re_annotations`. The current implementation is deterministic self-review (consistent = true), but the JSON shape is designed so the engine can be swapped for a multi-rater or LLM-rater implementation without changing the public contract. |

### MQM severity scale (cross-tool alignment, P5 increment)

yimai's `severity_score` follows the standard MQM Core scale: `None=0 / Minor=1 / Major=5 / Critical=10`.
Three major MQM scoring systems use different penalty weights — below is the explicit mapping so
adopters can translate yimai scores into whatever external tool they wire us into:

| Severity | yimai `severity_score` | Phrase penalty | Lokalise penalty (vs 100) |
|----------|------------------------|----------------|---------------------------|
| None     | 0                      | 0              | 0                         |
| Minor    | 1                      | 1              | 5                         |
| Major    | 5                      | 5              | 25                        |
| Critical | **10**                 | **25**         | **75**                    |

**yimai vs Phrase** — Critical penalty is `10` in yimai vs `25` in Phrase. Rationale: yimai's
`mqm_re_annotate` already auto-runs a second pass on every Critical issue, so a Critical
that survives the second pass is by construction "double-checked" and the extra penalty
weight Phrase uses as a manual-review deterrent isn't needed.

**yimai vs Lokalise** — Lokalise's score is `100 - sum(penalties)`; yimai's `qe_auto` is
a weighted blend (`0.50·match_rate + 0.25·term_ok + 0.10·char + 0.15·bleu`). They are
not numerically comparable; convert via the formula.
| **W3C ITS 2.0** (Internationalization Tag Set) | Markup-level metadata for translation, terminology, language identification | Out of scope for the engine itself; consume from the host CMS/app, push translated strings through `add_tm` |
| **Model Context Protocol `2025-11-25`** (Anthropic / OpenAI / community) | Streamable HTTP + JSON-RPC 2.0 standard for tool-calling. **Note**: 2026-07-28 RC introduced breaking changes (initialize handshake removal, `Mcp-Method`/`Mcp-Name` headers, JSON Schema 2020-12, error code `-32602`); we are on `2025-11-25` and will migrate in 0.2.0. | `POST /mcp` is the spec-compliant MCP server; see [`docs/harness-configs/`](./docs/harness-configs/README.md) for client config |

### Roadmap (not implemented in 0.1.0; declared for adopters)

| Standard | Why it matters | Status |
|---|---|---|
| **TMX 1.4b** (Translation Memory eXchange, GALA Global) | The CAT-tool lingua franca for TM export/import. A 24-tool MCP service without `parse_tmx` / `export_tmx` can't be dropped into a Trados / memoQ / OmegaT pipeline. | `parse_tmx` / `export_tmx` declared in `engine.mbt` as `pub fn` but **not yet exposed** via `/api/*` or `/mcp`. Add `/api/import_tmx` + `/api/export_tmx` for v0.2. |
| **XLIFF 2.1** (OASIS) / **ISO 21720:2024** (XLIFF 2.0) | The CAT-tool lingua franca for segment-level exchange. ISO 21720:2024 = XLIFF 2.0; OASIS 2.1 is the newer revision. | `parse_xliff` declared in `engine.mbt` as `pub fn` but **not yet exposed**. Add `/api/import_xliff` + `/api/export_xliff` for v0.2. |
| **SRX 2.0** (Segmentation Rules eXchange) | Sentence-segmentation rules that make `concordance` and TM hit windows reproducible across CAT tools. | Not yet declared; would need a `/api/import_srx` endpoint. |
| **MQM severity scale** (None/Minor/Major/Critical + 0/1/5/10) | If/when adding a strict MQM scorer, use this scale so yimai scores are comparable to the broader MQM ecosystem. | Default scale recommendation documented here; engine `qe_auto` currently emits dimension tags only (not severity). |

> **Caveat.** None of the above is a claim of certification. yimai is a
> library + local service. To actually run an ISO 17100 / 18587 pipeline you
> still need certified linguists, project management, and the surrounding
> process — yimai gives you the *memory + consistency* primitives those
> processes rely on.

## Useful entry points

## Useful entry points

| File | Purpose |
|---|---|
| `engine.mbt` | all engine methods (fuzzy_match L1503, check_terms L1702, predict, recall, …) |
| `cmd/service/routes.mbt` | REST handlers + static file serving + `/mcp` branch |
| `cmd/service/mcp.mbt` | MCP JSON-RPC layer (initialize/tools/list/tools/call) |
| `cmd/service/tm_store.mbt` | load/save persistence (atomic write) |
| `cmd/service/web/` | front-end workbench (index.html + app.js, no build step) |
| `scripts/` | setup / build / run / seed / smoke / dev |
