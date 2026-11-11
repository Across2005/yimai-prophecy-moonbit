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

## [Unreleased] — 工具链同步至 moon 0.1.20261104

### Changed
- **MoonBit 工具链升级到 `0.1.20261104` / `moonc v0.10.20+65efd5b93`** — 新版把 `Json` / `ToJson`
  统一收进 prelude 导出，`Map[String, Json]` / `Bool` / `Int` / `Double` / `Array[Json]` 上的
  `.to_json()` 方法式调用全部失效（根包 18 处 + `cmd/service` 23 处编译错误）。统一改为包级函数
  `@json.to_json(x)`，覆盖 `engine.mbt` / `engine_consolidate.mbt` / `engine_learn.mbt` /
  `engine_mqm.mbt` / `util.mbt` / `cmd/service/*.mbt` / `tests/{core,corpus}/_test_helpers.mbt`。
- **`moon.pkg` 依赖清理** — 移除 `cmd/main/moon.pkg` 未使用的 `core/json` + `core/math`，
  `cmd/service/moon.pkg` 未使用的 `core/strconv` + `core/encoding/utf8`；`@ref.new(x)` →
  `Ref(x)`（新 API，`@ref.Ref[T]` 注解保持不变）。
- **测试包告警策略** — `tests/{core,corpus,feature}/moon.pkg` 增加
  `warnings = "-test_unqualified_package"`，与 `core/prelude` 的官方做法一致
  （`_test.mbt` 黑盒测试直呼同包 helper 是刻意设计，非隐患）。

- **`scripts/push.ps1` 改为直连 GitHub** — 原配置走 `ghproxy.net` 代理 URL；本机 ghproxy 证书
  2026-08 已过期、全局 `insteadOf` rewrite 也已移除，改为 `https://github.com/...` 直连。
  注意：若其他机器仍保留全局 `url.*.insteadOf` 重写，该直连地址会被再次改写。

### Fixed
- **`scripts/ci-check-test-helpers.ps1` 在本机 PowerShell 5.1 下解析崩溃** — 脚本是无 BOM 的
  UTF-8 且含中文/长破折号，Windows PowerShell 5.1 按 OEM 码页（936）读取时字符串终止符被吞，
  报 `UnexpectedToken`，会让 pre-commit 门禁误判失败。改为纯 ASCII（与 `smoke.ps1` 既有约定一致），
  并去掉脚本内的版本号措辞（该限制与版本无关）。`powershell 5.1` 与 `pwsh 7` 均实测通过。
- **`/api/style_report` 空文本被误拒（P1 回归）** — handler 注释声明 `text` 可选，但
  `validate_text_field` 强制非空，令 `{"text":""}`（"只出记忆库分布报告"的合法用法）返回
  400 `field_empty`。新增 `validate_optional_text_field` / `validate_optional_text_field_or_send`：
  仅对字符串做 `MAX_TEXT_CHARS` 上限校验，空串与"缺省/非字符串"一律按 `""` 放行（与原 handler
  行为一致，非字符串不会被新校验拒掉）。`handle_style_report` 同时改用 `with_json_object`。
  回归覆盖由 `scripts/smoke.ps1` 的 `style_report memory distribution` 用例提供（24/25 → 25/25）。

### Verified (2026-11-11, 该工具链实测)
| 门禁 | 结果 |
|---|---|
| `moon check`（全包 · wasm-gc） | 0 error / 0 warning |
| `moon check`（全包 · native） | 0 error / 0 warning |
| `moon test --target wasm-gc` | 175 / 175 passed |
| `moon build cmd/service --target native` | 成功产出 `service.exe` |
| `scripts/smoke.ps1` | 25 / 25 passed |
| 关键指标（未漂移） | Hit@3 = 0.8246；Modern Corpus Hit@3 = 0.7773；BENCH 5K/10K `pruned_acc = full_acc = 1600` |

> 说明：上表 "0 warning" 是在按上游惯例抑制 `test_unqualified_package`（纯风格诊断，见 Changed
> 第 3 条）之后的结果；`warnings` 是包级设置，未来 `tests/**` 新增文件同样被抑制。

## [2026-08-26] — P11 架构扫描 + 深度评审 + cmd/service 多文件拆分

### Changed
- **cmd/service/mcp.mbt 拆 4 文件**（P11-B commit B）— 440 行单文件按
  JSON-RPC 入口 / JSON 提取 / 25 tool schema / 25 tool 派发 4 个职责分离：
  - `cmd/service/mcp.mbt` (280 行) — 入口：JSON-RPC 构造 + id/method/params
    提取 + known_tool_names + is_known_tool + check_required_fields + 5 个
    method 处理（handle_initialize / handle_tools_list / handle_tools_call
    / dispatch / handle_mcp）
  - `cmd/service/mcp_args.mbt` (50 行) — 5 个 JSON 提取 helper（arg_str /
    arg_int / arg_num / arg_bool / schema_prop）
  - `cmd/service/mcp_schemas.mbt` (110 行) — tool_def + all_tools（25 个
    `tool_def(...)` 调用物理隔离）
  - `cmd/service/mcp_dispatch.mbt` (120 行) — invoke_tool（25 个
    `else if name ==` 分支物理隔离）
  - 单文件最大行数 440 → 280（-36%），未来加 tool 改 mcp_schemas.mbt 一处
  - 同包 cmd/service 零 import 改动，沿用 P10 同包多文件模式
- **cmd/service/routes.mbt 拆 5 文件**（P11-C commit C）— 747 行单文件按
  HTTP 入口 / 安全 / 12 查询 handler / 8 度量 handler / 6 运维 handler 5
  个职责分离：
  - `cmd/service/routes.mbt` (270 行) — 入口：handle_request dispatch
    + handle_panic + lookup_route + extract_base_path + send_json +
    send_error + read_json_or_400 + read_json_body + serve_static +
    content_type
  - `cmd/service/routes_security.mbt` (95 行) — 5 个 P9 收紧安全 helper
    （is_safe_origin + is_loopback_hostport + is_safe_static_path +
    parse_nonnegative_int + content_length_too_large）
  - `cmd/service/routes_handlers_query.mbt` (250 行, 12 handler) —
    fuzzy_match / add_tm / tm_count / check_terms / concordance /
    qe_auto / mqm_re_annotate / predict / observe / recall / explain /
    retrieve_prompt
  - `cmd/service/routes_handlers_metrics.mbt` (190 行, 8 handler + 3
    json helper) — bleu / chrf / style_check / style_report /
    back_align / term_conflicts / metrics / health + json_str / json_int
    / json_num
  - `cmd/service/routes_handlers_ops.mbt` (165 行, 6 handler) — reward /
    consolidate / fed_export / fed_import / distill_inject /
    active_learning
  - 单文件最大行数 747 → 270（-64%），按 REST 端点语义层次（query /
    mutation / metrics / ops）拆，让 diff 范围最小
  - 27 REST 端点 + 25 MCP tools 行为零变化（smoke test 全通验证）
- **util.mbt 4 个 helper 升 pub**（P11-A commit A）— `get_str` / `get_num`
  / `get_obj` / `get_field` 从 fn 升为 pub fn。`get_field` 是新升 pub
  （原为私有），是 `get_obj` 的「不过滤类型」版本——`get_obj` 只对 Object
  字段有效，对 Array 字段会返回空 obj，`get_field` 保留原始 Json 类型
- **cmd/main/main.mbt 复用 @lib helper**（P11-A commit A）— 删 jstr /
  jnum（与 @lib.get_str / @lib.get_num 完全等价），保留 3 行 jarr
  包装（基于 @lib.get_field + Json::Array 拆解）。共改 11 个调用点
- **_test_helpers.mbt 漂移主动防御**（P11-D commit D）—
  - `scripts/ci-check-test-helpers.ps1` (53 行) — 用 SHA256 校验
    `tests/core/_test_helpers.mbt == tests/corpus/_test_helpers.mbt`
    强制相等；feature 是子集不强制但提示手动验证
  - `.githooks/pre-commit` 末尾追加 ci-check 阶段（pwsh 缺时 WARN
    不阻断 commit，提示安装 PowerShell）
  - `_test_helpers.mbt` 顶部注释加 CI 校验说明
  - 顺手修了 core/corpus 真实漂移（2 处 1 空行差异）

### Added
- **P11 评审报告** `docs/plans/2026-08-26-p11-architecture-review.md` — 6 条
  Finding（4 实施 / 1 不实施 / 1 范围外）+ 4 个 P11 commit 落地细节 + 经验
  教训 + 0.2.0/0.3.0 路线图
- **R15 字节验证方法**（P11-A）— `cmd_main.before.txt` 与 `cmd_main.after.txt`
  字节对比验证 `moon run cmd/main` 输出与改动前**完全相同**（2007 bytes,
  `fc.exe /B` 0 差异）

### Non-goals（评审中明确不实施）
- **engine_ops.mbt 主题混杂**（"style" + "运维" 4 个语义层次）— P10 commit B
  已审视，`engine_ops.mbt` 名字本身是「其他/杂」占位符；进一步拆分引入
  「剩余杂项层」违反命名一致性。CHANGELOG P10 段已记录，0.3.0 重新评估
- **0.2.0 路线图项**（parse_tmx / parse_xliff / export_tmx 端点暴露 +
  load_tbx SAX 重构 + export_tbx TBX3 DCA+DCT + Project Spec ISO
  11669:2024）— 全部在范围外，AGENTS.md "Roadmap" 段已声明

### Docs
- AGENTS.md "Project layout" 段增 P11 cmd/service 多文件拆分表
  （mcp 4 文件 + routes 5 文件）
- AGENTS.md "Useful entry points" 表增 7 个新文件行
- CHANGELOG.md（本段）记录 P11 全部 commit
- `docs/plans/2026-08-26-p11-architecture-review.md` 完整评审报告

### Test & Build
- `moon check --target native` 0 警告
- `moon check --target wasm-gc` 0 警告
- `moon test --target wasm-gc` 维持 **175/175** 全绿
- `moon test --target native` 175/175（含 `cmd/service` 服务测试）
- `pwsh -File scripts/ci-check-test-helpers.ps1` exit 0
- 27 REST 端点 smoke test 全通（11 返 200，16 必填校验返 400 符合设计）
- 25 MCP tools `tools/list` + `tools/call ping` 验证通过
- `validate-harness-configs.ps1` 维持 **13/13** PASS

## [Unreleased] — P10 引擎拆分 + 安全兼容性修复 + 文档精修

### Added
- **引擎按主题拆分为 8 个根 `.mbt` 文件**（P10 commit B）— 原 3619 行 `engine.mbt`
  按 D1–D8 + #22 TM/TB + #21 WAL 主题拆为 8 个根 `.mbt` 文件，同 `@lib` 包，调用点
  零修改：

  | 文件 | 行数 | 主题 |
  |---|---:|---|
  | `engine.mbt` | 590 | 常量 + struct + JSON I/O + make + to_json/from_json (schema 契约根) |
  | `engine_index.mbt` | 226 | TM TF-IDF + term 倒排索引 |
  | `engine_learn.mbt` | 912 | remember/observe/predict/recall + value + reward (D1–D8) |
  | `engine_consolidate.mbt` | 237 | consolidate + restore + WAL (D6 + #21) |
  | `engine_tm.mbt` | 456 | add_tm + fuzzy + concordance + TBX (#22) |
  | `engine_mqm.mbt` | 501 | MQM/QE + 格式保真 + OCR + batch (#2-#5) |
  | `engine_io.mbt` | 212 | TMX/XLIFF + metrics + drift (#6-#7) |
  | `engine_ops.mbt` | 518 | style/back_align + 主动学习/联邦/蒸馏/可观测 |

  复现脚本 `scripts/split_engine.py`（一次性，不入正式 `scripts/`）。
  AGENTS.md "Project layout" 段加 P10 拆分说明。

- **`is_loopback_hostport` 提取**（P10 commit B）— `cmd/service/routes.mbt` 抽出
  单独函数显式处理 IPv6 `[host]:port` 形式（P9 隐藏 bug 修复，见下 Fixed）。

- **P10 审计 doc** — `docs/plans/2026-08-24-p10-round.md` 含安全/质量/harness/翻译标准
  5 维审计 + 验证矩阵。

### Fixed
- **`is_safe_origin` IPv6 解析 bug（P9 隐藏）** — P9 加的 `host.has_prefix("[::1]")`
  对 `http://[::1]:8787` 实际永远 false（`host` 经 `split(":")` 后是 `"["`），IPv6 环路
  origin **被误拒**。P10 抽 `is_loopback_hostport` 显式拆 `[…]:port` 形式，当前
  `127.0.0.1` 绑定不受影响（请求到不了），但若未来绑 `0.0.0.0` 或启用 IPv6 双栈，
  本地 `[::1]` 浏览器客户端会工作。属"提高兼容性"修复。

### Changed
- **`load_store` 删 P9 过防御 try/catch**（P10 commit A）— MoonBit 0.1.20260724 的
  `from_json` 走字段缺失默认路径不抛错，原 P9 加的 `try { Some(from_json(j)) } catch`
  在 native target 触发 `unused_try` 警告。改直调，损坏 JSON 走缺省字段得空壳引擎
  （同 P9 韧性目标，行为等价）。

- **AGENTS.md 文档精修**（P10 commit A）：
  - ISO 17100 行加 `ISO/AWI 17100` 2025-07-22 stage 20.00 修订立项注脚
  - EU AI Act Art 50(2) 段补 **Commission Guidelines C(2026) 5054 final** (2026-07-20)
    引用 + MQM Council **RFC-1-20260802** (DOI 10.5281/zenodo.21765333) — 机器翻译
    明确列入 standard-editing 豁免清单
  - Aider harness 行加 2026-06 复核现实注脚（Aider 0.86.x 仍**无原生 MCP**；
    MCP PRs closed unmerged，配置文件 forward-compat 保留）

### Docs
- AGENTS.md "Project layout" 段加 P10 引擎拆分 8 文件表
- AGENTS.md "Useful entry points" 表重写为按 engine*.mbt 主题列
- `docs/plans/2026-08-24-p10-round.md` P10 增量审计 doc

### Test & Build
- `moon check --target native` 0 警告 0 错误
- `moon check --target wasm-gc` 0 警告
- `moon test --target wasm-gc` 维持 **175/175** 全绿
- `moon test --target native` 175/175（含 `cmd/service` 服务测试）
- `validate-harness-configs.ps1` 维持 **13/13** PASS

## [Unreleased] — P9 安全硬化（DNS 重绑定防护 + 启动韧性）

## [Unreleased] — P9 安全硬化（DNS 重绑定防护 + 启动韧性）

### Added
- **Origin 头校验（DNS 重绑定防护）** — `cmd/service/routes.mbt` 新增 `is_safe_origin`，在
  `handle_request` 入口对所有请求（REST + `/mcp`）校验 `Origin`：放行无 Origin（curl/CLI/
  PowerShell `Invoke-RestMethod`）、`null`、以及回环 host（`127.0.0.1` / `localhost` / `[::1]`），
  其余（如 `https://evil.com`）一律 `403 Forbidden`。对齐 MCP 2025-11-25 Streamable HTTP 安全
  强制要求（本地 server 必须防 DNS 重绑定）。

### Changed
- **`load_store` 启动韧性** — `tm_store.json` 结构损坏时 `ProphecyEngine::from_json` 不再
  panic 崩溃启动，降级为空引擎并告警（包裹 try/catch）。

### Security
- 纯本地、零云依赖不变；服务仍仅绑定 `127.0.0.1:8787`。

### Docs
- AGENTS.md / README 增补 **2025–2026 前沿更新**：MQM 2025 评分模型（Linear Calibrated +
  Non-Linear，2025-04；Multi-Range Theory，2025-06）、EU AI Act Article 50 机器翻译标注
  （2026-08-02 生效）、MCP `2026-07-28` 稳定版与「停留 2025-11-25」决策；新增
  Local-server security 小节；澄清根 lib package 因 MoonBit 限制有意保留于根目录。

### Test & Build
- `moon check --target native` 0 警告 0 错误；`moon test --target wasm-gc` 维持 **175/175** 全绿。

## [Unreleased] — P8 告警清零（moon check 双 target 0 警告）

### Changed
- **deprecated 51 条全清（cmd/service + tests）** — `not(expr)` → `!expr`（routes.mbt 38 处 + mcp.mbt 1 处）；`Json::as_bool()` → `is True` / `is False` 判别（本版本 Json 的 Bool 构造器已拆为 True/False 单例，`mcp.mbt arg_bool` / `routes.mbt consolidate prune` 语义不变）；`Map::new()` → `Map([])`；`.size()` → `.length()`；`.starts_with()` → `.has_prefix()`；StringView `.to_string()` → `.to_owned()`；`path.substring(start=1, end=len)` → `path[1:].to_owned()`；测试里集合 `to_string()`（Show）→ `join(", ")`。
- **reserved_keyword 11 条全清** — `dispatch(method : String, ...)` 参数改名 `meth`（与 `@http.Request.meth` 命名一致；JSON-RPC 线上 `"method"` 字段名不受影响）。
- **missing_pattern_arguments 1 条修复** — distill_inject 循环 `Json::Number(n)` 补齐为 `Json::Number(n, ..)`（与其余 12 处调用点一致）。
- **unused_value 10 条全清** — engine `back_align` receiver 改 `_self`（纯函数不读引擎状态，dot 调用语法不变）、`term_conflicts` 迭代改 `for _, m`；`handle_term_conflicts`/`handle_fed_export` 未用 body 参数改 `_body`；`Err(panic_msg)` 改 `Err(_)`（脱敏注释保留）；删除 corpus 测试死代码：`r4_e` / `er_recall_texts` / `r4f` / `fc_all_corpora` / `fc_corpus_names`。
- **unused_package 2 条结构性消除** — 新增 `tests/feature/_test_helpers.mbt`（pub 的 `build_known_handlers` / `known_handlers` 自 routes_test 上移）。feature 包此前只有 `*_test.mbt`（黑盒），lib 构建目标为空导致 moon.pkg 的 @lib import 被判未使用；corpus/core 两包正是靠各自的 `_test_helpers.mbt` 规避同类告警，本次补齐同款结构。

### Test & Build
- `moon check --target native` **0 警告 0 错误**（原 75）；`moon check --target wasm-gc` **0 警告**（原 11）；`moon test --target wasm-gc` 维持 **175/175** 全绿。

## [Unreleased] — P0/P1 性能硬化（fuzzy_match 热路径）

### Changed
- **`util.mbt` 分词/集合算子 Map 化** — `is_stop` 由数组线性扫描改为 `stop_map` O(1) 查找；`unique` 由 O(n²) `arr_contains` 去重改为 `to_set`（Map 去重）；`char_ngrams` 数组版改为 `char_ngram_set`（直接产出 Map）；`dice_coeff` 由每候选×每分项各建 2 个 Map 改为 `dice_mm`（双 Map 直传，打分循环内零分配）。
- **`engine.mbt` fuzzy_match 打分热路径去分配** — `MemoryNode` 新增 `tm_toks_set`（unique token 去重集合）与 `tm_ngrams`（char 2-gram 去重集合）字段，`add_tm`/`remember`/`restore` 时随节点预建缓存；`fuzzy_score_one` 改为消费调用方预建的查询侧集合（`q2m`/`qtokm`），打分循环内 `dice_mm` 零 Map 分配。
- **`engine.mbt` `count_tm` O(1) 化** — 新增 `tm_count` 缓存字段，折入 `tm_idf_dirty` 生命周期：`rebuild_tm_idf` 重建时顺带刷新；`count_tm` 由 O(N) 扫描改为 O(1) 读缓存。所有 TM 集变更点（`add_tm`/`remember`/`consolidate` 剪枝/`restore`/`from_json`）均置脏或全量重建，缓存不失真。
- **R15 确定性零影响** — 所有新算子仅做 `contains` / `length` 查询，不依赖 Map 迭代顺序；`pruned_acc == full_acc == 1600` 证明剪枝结果与全量一致（幂等）。

### Performance
- `fuzzy_match` 基准（wasm-gc，tests/core/yimai_prophecy_moonbit_bench_p1.mbt）由基线 **9.04s → 4.63s（-48%）**，结果正确性不变（acc=1600）。

### Test & Build
- `moon test --target wasm-gc` 维持 **175/175** 全绿；`moon check --target native` 0 错误。

## [Unreleased] — P6 hardening, multi-harness compat & repo tidy

### Fixed
- **`cmd/service/mcp.mbt` `/mcp` JSON-RPC body parse** — `read_json_body` returns `Result[Json, BodyError]`; replaced stale `Some`/`None` pattern (Option) with `Ok`/`Err(TooLarge)`/`Err(InvalidJson)` (Result). Removed reference to deleted `last_body_oversize` global ref. Oversized requests now correctly return HTTP 413 (was incorrectly lumped into 400).
- **`cmd/service/routes.mbt` NaN/Inf guard** — `@math.is_nan(n)` / `@math.is_inf(n)` replaced with `n.is_nan()` / `n.is_inf()` (Double built-in methods; `core/math` package-level functions don't exist). Removed invalid `core/math` import from `cmd/service/moon.pkg`.
- **`cmd/service/validate.mbt` package visibility** — moved from `cmd/service/util/` (orphan sub-directory without `moon.pkg`) to `cmd/service/` same-package, making `validate_*_field_or_send` functions visible to `routes.mbt`.
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
- **`cmd/service/validate.mbt` `with_json_object`** — higher-order helper eliminating `read_json_or_400 + match Object` boilerplate across POST handlers; 3 handlers refactored as proof-of-concept (`fuzzy_match`, `add_tm`, `bleu`).
- **`.github/workflows/ci.yml`** — GitHub Actions CI: `moon check` + `moon test --target wasm-gc` with 175/175 count gate on push/PR to `main`.
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
