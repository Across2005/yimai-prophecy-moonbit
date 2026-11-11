# AGENTS.md — AI Agent Out-of-the-Box Guide

This file tells AI agents (Claude, Copilot, Cursor, code agents, …) how to use
this repository immediately after cloning. Read this first.

> **Multi-harness companion files** (auto-loaded by specific agents):
> - [`CLAUDE.md`](./CLAUDE.md) — Claude Code (Anthropic CLI)
> - [`GEMINI.md`](./GEMINI.md) — Gemini CLI (Google)
> - Both point back to this file for the full multi-harness guide.
>
> 📜 **变更历史**：[`CHANGELOG.md`](./CHANGELOG.md) — 每次 P 增量的完整 commit 列表与影响范围。本仓库约定：**所有 P 增量详情只入 CHANGELOG，README / AGENTS.md / CLAUDE.md / GEMINI.md 只描述当前状态**（避免历史段在多处腐烂）。

## What this project is

**译脉·先知 2.0** — a deterministic memory-prediction engine written in
[MoonBit](https://www.moonbitlang.com), zero third-party dependencies
(`core/json` + `core/math` only). It remembers workflows / translation-memory
entries and predicts the next step, with white-box explanations.

Three layers, one language (no bridge code):

| Layer | Where | What |
|---|---|---|
| Layer 0 · engine | `engine.mbt` / `util.mbt` | D1-D8 memory network + #22 TM/TB + #2-#7 extensions + S1 fuzzy-match |
| Layer 1 · service | `cmd/service/` | 27 REST endpoints (`/api/*`) + `/mcp` MCP server + web workbench |
| Layer 2 · knowledge | `README.md`, `AGENTS.md`, web workbench | docs + how-to |

> 注：原表格把 service 编为 Layer 2、knowledge 编为 Layer 1 是 P5 之前的命名反直觉；
>   2026-08 重构为 0/1/2 顺序（engine → service → knowledge），与 README 第 422 行的
>   "cmd/service 是 Layer 2" 旧表述不一致——README 的"Layer 2" 实指测试层编号（E-Layer0~10），
>   与本架构层无关；如读者混淆，请以本表为准。

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
moon test --target wasm-gc        # 175/175 green
```

> **Toolchain floor** — `moon` ≥ `0.1.20261104`, `moonc` ≥ `v0.10.20`.
> 当前版本的实测数字见 `CHANGELOG.md` → 最新 `[Unreleased]` 段的 Verified 表。

## Consuming the service

- **REST**: 27 个 `/api/*` 端点（多数 `POST` JSON 体，`/api/ping` 与 `/api/tm_count` 为 GET）。示例
  `POST /api/fuzzy_match {"query":"电池包热管理方案","k":3,"threshold":0.5}` → Top-K with
  white-box scores (`sim_token/sim_tfidf/sim_char/sim_ngram/sim_tokenset`)（详见 `README.md` → Service Layer）。
- **MCP**: `POST /mcp` speaks JSON-RPC 2.0 (spec 2025-11-25). `initialize` → `tools/list` (25 tools)
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
| **Aider** (≥ 0.86) | `~/.aider.conf.yml` or `<repo>/.aider.conf.yml` | `docs/harness-configs/aider.conf.yml` (aspirational — see footnote) |
| **Sourcegraph Cody** | Cody → Settings → MCP Servers — *deprecated 2025-08, use other harness* | `docs/harness-configs/cody.json` |
| **Zed** | `~/.config/zed/settings.json` under `context_servers` (≥ 0.150 uses `url` field) | `docs/harness-configs/zed.json` |
| **GitHub Copilot (Coding Agent)** | `.github/workflows/copilot-setup-steps.yml` (snippet, runner caveat) | `docs/harness-configs/github-copilot.yml` |

All clients use the same MCP shape. The only thing that varies is the config
file path. After `scripts/run.ps1` is up, all clients should be able to
`tools/list` and see the 25 tools.

> **Aider 现实注脚（2026-06 复核）**：`docs/harness-configs/aider.conf.yml` 仍按 `mcp_servers` 块保留配置以**追踪 Aider 官方 MCP 提案**。Aider 0.86.x 官方 config reference **未列 MCP 选项**（MCP PRs 已 closed unmerged，per WeAreWarp 2026-06 audit）；社区 `@poai/mcpm-aider` 桥接可用但属 third-party / experimental。当前 yimai 对 Aider 用户的最稳路径是 **aider `--run 'curl ... /mcp'`**（直调 + JSON-RPC）或等待 Aider 合并原生支持。配置保留作 forward-compat；Aider 合并后只需把 `aider.conf.yml` 的 `mcp_servers` 块调整为 Aider 实际接受的 schema 即可。

> 📁 **Full sample set** (one file per harness + per-harness install path
> table) lives under [`docs/harness-configs/`](./docs/harness-configs/README.md).

### Project-level auto-discovery (zero-copy)

This repo ships **in-repo MCP configs** so agents see the 25 tools immediately
after `scripts/run.ps1` — no manual copy to `~/.config/…` needed:

| File | Agent |
|---|---|
| `.mcp.json` | Claude Code, Gemini CLI, generic MCP clients |
| `.cursor/mcp.json` | Cursor (per-project) |
| `.cline/mcp.json` | Cline (per-project, ≥ 3.x) |
| `.roo/mcp.json` | Roo Code (per-project) |
| `.windsurf/mcp.json` | Windsurf / Cascade (per-project) |
| `.codex/config.toml` | OpenAI Codex CLI (≥ 0.21, per-project) |

All point at `http://127.0.0.1:8787/mcp`. Start the service first
(`scripts/dev.ps1` or `scripts/run.ps1`), then restart the agent — it will
auto-discover the 25 tools via `tools/list`.

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
    via `@lib.obj/str_json/num_json/arr_json` (util.mbt).
  - **从 moon 0.1.20261104 起** `Json` / `ToJson` 由 prelude 统一导出，方法式 `x.to_json()`
    不再解析；统一用包级函数 `@json.to_json(x)`（`@lib` 内部同理）。
  - `Request.path` includes the full query string — strip `?` before routing (see `extract_base_path`).
  - `@fs.write_file` default `create_mode=TruncateExisting` fails when the file is absent — pass
    `create_mode=@fs.CreateMode::CreateOrTruncate` for first writes.
- `moon fmt` reformats the whole repo (2585-line diffs historically) — avoid unless asked.
- **Map ≠ HashMap** — `Map[String, T]` (MoonBit) is **ordered by insertion** and is
  load-bearing for the determinism contract (R15): `predict` scores, `fuzzy_match` ranking,
  `metrics` JSON field order all depend on iteration order. Do **not** swap in `@hashmap`
  or any `HashSet/HashMap` from a hypothetical future stdlib — that would break R15 silently.
- Keep `moon test --target wasm-gc` green on every change.

### Local-server security (P9)

The service binds **only `127.0.0.1:8787`** (never `0.0.0.0`) and is **pure local, zero cloud
dependency** — there are no outbound network calls anywhere in the codebase. Two hardening
rules apply:

- **Origin validation (DNS-rebinding protection)**: every HTTP/MCP request passes
  `is_safe_origin` (`cmd/service/routes.mbt`). Non-loopback Origins (e.g. `https://evil.com`)
  are rejected with `403 Forbidden`. This is mandated by the MCP 2025-11-25 Streamable HTTP
  security warning and shields a local server from cross-site requests via DNS rebinding.
- **Startup resilience**: `load_store` wraps `ProphecyEngine::from_json` in a guard — a corrupt
  `tm_store.json` degrades to an empty engine with a warning instead of panic-crashing startup.

## Project layout (where new files go)

P5 仓库整理（2026-08）：所有新增文件必须落到合适目录，**禁止再散落在根目录**。

> **Root 大文件为何留在根目录（MoonBit 限制）** — `engine.mbt` / `util.mbt` /
> `yimai_prophecy_moonbit.mbt` 是**根 package（lib）**的源文件。MoonBit 的 `moon.pkg`
> 把所在目录声明为一个 package，根目录的 `moon.pkg` 即根 package，`@lib` 别名指向它；
> 全代码库的 `@lib.X` 调用点与 wasm-gc 测试均依赖此别名。若把这些文件挪进 `src/` 子目录，
> 它们会变成独立 sub-package，跨包 import 受 MoonBit 限制（sub-package 间不能互相 import
> 主包符号），需改动每一个调用点与测试 import，风险高、收益低。
> **因此：根 lib package 有意保留在根目录；新功能优先落到 sub-package**
> （`cmd/<name>/`、`tests/<sub>/`、以及按领域新建的功能 sub-package），而非继续往根目录堆文件。
> 这正是「尽量以代码打包进文件夹的形式编程」在 MoonBit 下的正确落地方式。

> **P10 引擎文件按主题拆分**（同包多文件，MoonBit 0.1.20260724 起支持，@lib 别名零变化）—
> P10 把原 3619 行 `engine.mbt` 按 D1–D8 + #22 TM/TB + #21 WAL 主题拆为 8 个根 `.mbt` 文件：
>
> | 文件 | 行数 | 主题 |
> |---|---:|---|
> | `engine.mbt` | 590 | 常量 + struct + JSON I/O + make + to_json/from_json (schema 契约根) |
> | `engine_index.mbt` | 226 | TM TF-IDF + term 倒排索引 |
> | `engine_learn.mbt` | 912 | remember/observe/predict/recall + value + 偏置/对比学习/attention/reward |
> | `engine_consolidate.mbt` | 237 | consolidate 4 段 + restore + WAL 增量日志 |
> | `engine_tm.mbt` | 456 | add_tm + fuzzy 家族 + concordance + load_tbx + enforce/check |
> | `engine_mqm.mbt` | 501 | MQM/QE + 格式保真 + OCR 桩 + 区域对齐 + batch_apply |
> | `engine_io.mbt` | 212 | TMX/XLIFF 解析导出 + metrics + drift_report |
> | `engine_ops.mbt` | 518 | style/back_align/term_conflicts/retrieve_for_prompt + 主动学习/联邦/蒸馏/可观测 |
>
> 主题分组降低单文件体积（最大 912 行 vs 原 3619），调用点零修改；to_json/from_json
> 留在 `engine.mbt` 是因为它是状态 schema 事实契约，跨会话恢复依赖单一事实源。
> 复现脚本 `scripts/split_engine.py` 一次性使用，已加 CHANGELOG 引用。

> **P11 cmd/service 同包多文件拆分**（同模式，验证 27 REST + 25 MCP 行为零变化）—
> P11 把 `cmd/service/mcp.mbt` (440) 与 `cmd/service/routes.mbt` (747) 拆为多文件：
>
> | 文件 | 行数 | 主题 |
> |---|---:|---|
> | `cmd/service/mcp.mbt` | ~280 | 入口：JSON-RPC 构造 + id/method/params + known_tool_names + 5 个 method 处理 + handle_mcp |
> | `cmd/service/mcp_args.mbt` | ~50 | JSON 字段提取（arg_str/int/num/bool）+ schema_prop |
> | `cmd/service/mcp_schemas.mbt` | ~110 | 25 个 tool_def 物理隔离 + all_tools |
> | `cmd/service/mcp_dispatch.mbt` | ~120 | 25 个 invoke_tool 派发物理隔离 |
> | `cmd/service/routes.mbt` | ~270 | 入口：handle_request dispatch + handle_panic + lookup_route + send_json/error + read_json_or_400/body + serve_static + content_type |
> | `cmd/service/routes_security.mbt` | ~95 | 5 个 P9 收紧安全 helper（is_safe_origin / is_loopback_hostport / is_safe_static_path / parse_nonnegative_int / content_length_too_large） |
> | `cmd/service/routes_handlers_query.mbt` | ~250 | 12 个查询/记忆类 handler（fuzzy_match / add_tm / tm_count / check_terms / concordance / qe_auto / mqm_re_annotate / predict / observe / recall / explain / retrieve_prompt） |
> | `cmd/service/routes_handlers_metrics.mbt` | ~190 | 8 个度量/风格/对齐类 handler（bleu / chrf / style_check / style_report / back_align / term_conflicts / metrics / health）+ 3 json helper |
> | `cmd/service/routes_handlers_ops.mbt` | ~165 | 6 个运维类 handler（reward / consolidate / fed_export / fed_import / distill_inject / active_learning） |
>
> 单文件最大行数从 747 → 270（-64%）；按 REST 端点语义层次（query / mutation / metrics / ops）拆，让 diff 范围最小（加 1 个端点改 query/metrics/ops 中一处，不影响入口）。
> 评审报告：`docs/plans/2026-08-26-p11-architecture-review.md`。

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
- MoonBit 限制：sub-package 不支持跨包 import（每个 `tests/<sub>/` 是独立 package），**helper fn 必须 inline 在子包内**（共享 helper 写到 `_test_helpers.mbt` + 跨子包各复制一份），或者提到 `lib` 主包（污染 API，慎用）。
- 跨子包 helper 改了要在所有副本同步（已加注释提醒）。
- 根 `moon.pkg` 范围 = 根目录直系 .mbt，**不含 `tests/**`**。每个子包有自己 moon.pkg。

## International translation standards (alignment, not certification)

This engine is a **technical building block**, not a translation service, so it
isn't itself certifiable — but the features map cleanly to the workflows the
following international standards describe, so adopters can wire yimai into
ISO-conformant pipelines:

| Standard | What it covers | How yimai fits |
|---|---|---|
| **ISO 17100:2015** (Translation services — Requirements) | Translator competence, project management, technical resources, post-delivery feedback. **Under revision**: `ISO/AWI 17100` entered TC/SC work programme at **stage 20.00 on 2025-07-22** (new project approved); expected topics include MT/AI integration, second-pair-of-eyes scope, and possible merger with ISO 18587. yimai maps to the 2015 version's structure today and will be re-evaluated when the new edition publishes. | `observe`/`predict` + `reward` give the post-delivery feedback loop; `retrieve_prompt` injects bilingual context into the LLM step; `consolidate` is the meta-cognitive review that ISO 17100 §5.5 expects for "technical revision" |
| **ISO 18587:2017** (Post-editing of machine translation output) | MTPE workflow, post-editor competence, output quality | `qe_auto` (QE + MQM tagging) and `bleu`/`chrf` measure MT output before/after post-edit; `retrieve_prompt` injects TM hits into the post-edit LLM step |
| **ISO 30042:2019 / TBX3** (TermBase eXchange, v3 dialect) | TermBase XML schema for terminology exchange (TBX3 v3.0, not TBX2 v2.0 — namespace and structure changed) | `load_tbx` parses ISO 30042-compliant `<martif>/<termEntry>` XML; `add_tm` + `check_terms` enforce term consistency (the "TB" half of TM/TB) |
| **ISO 11669:2024** (Translation projects — General guidance) | Project lifecycle, deliverables, sign-off — full standard (replaced ISO/TS 11669:2012) | `predict` is the per-step next-action recommender; `consolidate` is the project-completion review |
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
| **Model Context Protocol `2025-11-25`** (Anthropic / OpenAI / community) | Streamable HTTP + JSON-RPC 2.0 standard for tool-calling. **Note**: spec 演进见下方「2025–2026 前沿更新」；我们停留在 `2025-11-25`（纯本地、无鉴权、广 harness 兼容），迁移 0.2.0 再议。 | `POST /mcp` is the spec-compliant MCP server; see [`docs/harness-configs/`](./docs/harness-configs/README.md) for client config |

### 2025–2026 前沿更新（联网核查，2026-08 增补；P10 2026-08-24 增订 ISO 17100 修订立项 + EU AI Act Guidelines 编号 + MQM RFC-1 + Aider MCP 复核）

> 下列为 2025–2026 年国际翻译/协议生态的关键演进，已据此校准 yimai 的对齐姿态。
> yimai 仍是技术构建块（library + local service），以下为「adopter 集成指南」而非认证声明。

- **MQM 评分模型正式化（2025）** — MQM Council 于 **2025-04** 发布 **Linear Calibrated Scoring Model** 与 **Non-Linear Scoring Model**（此前仅公布原始评分模型）；**2025-06**《Multi-Range Theory of Translation Quality Measurement》提出跨三档样本量（含单句级）的通用测量法，并主张极小样本用 **Statistical Quality Control**。MQM Core 现含 **39 种 error type**（MQM Full 更多）。yimai 的 `severity_score`（None=0/Minor=1/Major=5/Critical=10）保持与 MQM Core 一致；adopter 若需接入上述新评分模型，建议在 `qe_auto` 外层做分数换算。
- **EU AI Act Article 50 机器翻译标注（2026-08-02 生效）** — 法规要求对 AI 生成内容作来源标注；**Commission Guidelines C(2026) 5054 final（2026-07-20）** 在「standard editing 豁免清单」中**明文列入**「AI-generated translations of text」——机器翻译输出**通常不触发** Article 50(2) 的 provider 端机器可读标注义务。但 Article 50(4) 的 deployer 端披露义务在「公利益文本」场景独立成立（除非有实质性 human review / editorial responsibility）；译文不自动继承源文编辑清关。罚则上限：EUR 15 M 或全球年营业额 3%（取高）。yimai 作为本地引擎不代行标注，但 adopter 在欧盟公利益场景部署时应自行补标注层。**MQM Council 同步发布 *MQM RFC-1-20260802*（DOI 10.5281/zenodo.21765333）**给出详细解读，与 Commission 指南一致。
- **MCP `2026-07-28` 稳定版（2026-07-28 发布）** — 史上最大重构：**无状态核心**，`initialize` 握手 + `Mcp-Session-Id` **移除**，改每请求 `_meta` 自描述；新增 `server/discover`；`Mcp-Method`/`Mcp-Name` 头成为路由强制项；`tools/list` 等结果可缓存（`ttlMs`+`cacheScope`）；Authorization 向 OAuth 2.1 靠拢（RFC 9207 issuer 校验，弃用 DCR）；Roots/Sampling/Logging 进入 **Deprecated**（≥12 个月窗口，最早 ~2027-07-28 才可考虑移除）。
  - **yimai 决策：停留在 `2025-11-25`**。理由：① 纯本地、绑定 `127.0.0.1`、无鉴权，stateless/多实例横向扩容诉求不成立；② 当前 13 个 harness（Claude Desktop / Cursor / Codex / Cline / 等）均基于 `2025-11-25` 的 `initialize` 握手消费，贸然切 `2026-07-28` 会断开现有客户端；③ 规范明确「仅本机 stdio / 无远程扩容 / 无复杂网关」场景可暂不升级。迁移将在 0.2.0 视 adopter 需求评估（dual-era 兼容优先）。
  - **但已落实 `2025-11-25` 的本地安全要求**：`cmd/service` 全链路（REST + `/mcp`）新增 **Origin 头校验（DNS 重绑定防护）**——拒绝非回环 Origin（如 `https://evil.com`），放行无 Origin（curl/CLI）、`null`、以及 `127.0.0.1`/`localhost`/`[::1]`。详见「Code conventions → Local-server security」。

### Roadmap (not implemented in 0.1.0; declared for adopters)

| Standard | Why it matters | Status |
|---|---|---|
| **TMX 1.4b** (Translation Memory eXchange, GALA Global) | The CAT-tool lingua franca for TM export/import. A 25-tool MCP service without `parse_tmx` / `export_tmx` can't be dropped into a Trados / memoQ / OmegaT pipeline. | `parse_tmx` / `export_tmx` declared in `engine.mbt` as `pub fn` but **not yet exposed** via `/api/*` or `/mcp`. Add `/api/import_tmx` + `/api/export_tmx` for v0.2. |
| **XLIFF 2.1** (OASIS) / **ISO 21720:2024** (XLIFF 2.0) | The CAT-tool lingua franca for segment-level exchange. ISO 21720:2024 = XLIFF 2.0 (second edition, updated from 2017); OASIS XLIFF 2.2 is in Committee Specification as of 2025-03. | `parse_xliff` declared in `engine.mbt` as `pub fn` but **not yet exposed**. Add `/api/import_xliff` + `/api/export_xliff` for v0.2. |
| **SRX 2.0** (Segmentation Rules eXchange) | Sentence-segmentation rules that make `concordance` and TM hit windows reproducible across CAT tools. | Not yet declared; would need a `/api/import_srx` endpoint. |
| **MQM severity scale** (None/Minor/Major/Critical + 0/1/5/10) | If/when adding a strict MQM scorer, use this scale so yimai scores are comparable to the broader MQM ecosystem. | Default scale recommendation documented here; engine `qe_auto` currently emits dimension tags only (not severity). |

> **Caveat.** None of the above is a claim of certification. yimai is a
> library + local service. To actually run an ISO 17100 / 18587 pipeline you
> still need certified linguists, project management, and the surrounding
> process — yimai gives you the *memory + consistency* primitives those
> processes rely on.

## Useful entry points

| File | Purpose |
|---|---|
| `engine.mbt` (root lib) | constants + struct + JSON I/O + make + to_json/from_json; 8 个 engine*.mbt 各负责一个主题（见上方"Project layout"） |
| `engine_index.mbt` | TM TF-IDF + term 倒排（fuzzy 倒排剪枝与 enforce/check 加速） |
| `engine_learn.mbt` | remember/observe/predict/recall + value + 偏置/对比学习/attention/reward (D1–D8) |
| `engine_consolidate.mbt` | consolidate 4 段 + restore + WAL (D6 + #21) |
| `engine_tm.mbt` | add_tm + fuzzy 家族 + concordance + load_tbx + enforce/check (#22) |
| `engine_mqm.mbt` | MQM/QE + 格式保真 + OCR + 区域对齐 + batch_apply (#2-#5) |
| `engine_io.mbt` | TMX/XLIFF 解析导出 + metrics + drift (#6-#7) |
| `engine_ops.mbt` | style + back_align + term_conflicts + retrieve_for_prompt + 主动学习/联邦/蒸馏/可观测 |
| `cmd/service/routes.mbt` | REST 入口 + dispatch + I/O helper + 静态文件服务（27 endpoint 派发） |
| `cmd/service/routes_security.mbt` | 5 个 P9 收紧安全 helper（is_safe_origin / is_loopback_hostport / ...） |
| `cmd/service/routes_handlers_query.mbt` | 12 个查询/记忆类 REST handler |
| `cmd/service/routes_handlers_metrics.mbt` | 8 个度量/风格/对齐类 REST handler |
| `cmd/service/routes_handlers_ops.mbt` | 6 个运维类 REST handler |
| `cmd/service/mcp.mbt` | MCP JSON-RPC 入口（initialize/tools/list/tools/call/dispatch） |
| `cmd/service/mcp_args.mbt` | JSON 字段提取 + schema_prop |
| `cmd/service/mcp_schemas.mbt` | 25 个 tool_def + all_tools |
| `cmd/service/mcp_dispatch.mbt` | 25 个 invoke_tool 派发 |
| `cmd/service/tm_store.mbt` | load/save persistence (atomic write) |
| `cmd/service/web/` | front-end workbench (index.html + app.js, no build step) |
| `scripts/` | setup / build / run / seed / smoke / dev |
