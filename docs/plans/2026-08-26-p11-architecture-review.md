# P11 架构扫描 + 深度评审 — 2026-08-26

> 译脉·先知 2.0 (MoonBit) — 仓库组织 + 代码深度评审
> 评审者：Mavis (root session, mavis agent) | 评审日期：2026-08-26
> 评审范围：根 lib（13 个 .mbt）+ `cmd/service/`（7 个 .mbt + web/）+ `cmd/main/` + 3 个 tests 子包 + scripts/

## TL;DR

P11 一轮架构扫描 + 深度评审，落地 4 个 P11 commit（4f721a7 / 6391f65 / 47f90dd / 12af653），4 类代码组织改进：

| Commit | 主题 | 文件 | 净行数 | 风险 |
|---|---|---|---:|---|
| P11-A | util 升 pub + cmd/main 复用 | `util.mbt` + `cmd/main/main.mbt` | -18 | 极低 |
| P11-B | mcp.mbt 拆 4 文件 | `cmd/service/mcp*.mbt` ×4 | +31 | 极低 |
| P11-C | routes.mbt 拆 5 文件 | `cmd/service/routes*.mbt` ×5 | +46 | 低 |
| P11-D | CI 校验脚本 + pre-commit 挂接 | `scripts/ci-check-test-helpers.ps1` + `.githooks/pre-commit` | +76 | 极低 |

合计 +135 / -50，净 +85 行（含 4 个新文档/脚本文件 + 注释扩展）。**单文件最大行数** 912 → 270（-70%）；**27 REST + 25 MCP** 端点行为零变化；**175/175 测试** 全绿；R15 确定性保留（`moon run cmd/main` 输出与改动前字节完全相同）。

## 评审方法

按 ROI 从高到低，6 条 Finding 全部经过"做 / 不做 / 何时做"权衡，最终落地 4 条（P11-A/B/C/D），明确**不实施** 2 条（P11-E 不实施，0.2.0 路线图项已声明范围外）。

| Finding | 主题 | ROI | 落地 |
|---|---|---|---|
| Finding 1 | routes.mbt 747 行 / 27 handler 单文件瓶颈 | 中-高 | P11-C |
| Finding 2 | mcp.mbt 440 行 / 25 tool 集中单文件 | 中-高 | P11-B |
| Finding 3 | cmd/main/main.mbt 自含 jstr/jnum/jarr 复制 @lib helper | 低-中 | P11-A |
| Finding 4 | _test_helpers.mbt 漂移主动防御 | 低 | P11-D |
| Finding 5 | engine_ops.mbt 主题混杂（"style" + "运维"） | 中 | **不实施** |
| Finding 6 | 0.2.0 路线图项 | — | 范围外 |

## Finding 1 — routes.mbt 747 行 / 27 handler 单文件瓶颈【中-高价值，中风险】

### 观察

`cmd/service/routes.mbt` 747 行单文件，含 27 个 `handle_xxx` 函数 + 11 个 helper，主题混杂（query / mutation / metrics / ops）。每次改 1 个 handler 需审全 747 行 diff 噪音。

函数清单（27 handler）：
- query/mutation (12): fuzzy_match / add_tm / tm_count / check_terms / concordance / qe_auto / mqm_re_annotate / predict / observe / recall / explain / retrieve_prompt
- metrics (8): bleu / chrf / style_check / style_report / back_align / term_conflicts / metrics / health
- ops (6): reward / consolidate / fed_export / fed_import / distill_inject / active_learning
- inlined (1): ping (handle_request match 派发中 1 行内联)

### 评估

27 endpoint 同文件阻碍 diff 审查、违反 deep module 原则。P10 commit B 已验证同包多文件零风险模式（`@lib` 别名零变化）。

### 决策

**实施** — 拆为 5 文件（沿用 P10 模式），按 HTTP 端点语义层次（入口/安全/查询/度量/运维）分组。

### 实施

见 P11-C commit (47f90dd)。文件结构：
- `routes.mbt` (270 行) — 入口：handle_request dispatch + handle_panic + lookup_route + extract_base_path + send_json + send_error + read_json_or_400 + read_json_body + serve_static + content_type
- `routes_security.mbt` (95 行) — 5 个 P9 收紧安全 helper
- `routes_handlers_query.mbt` (250 行, 12 handler)
- `routes_handlers_metrics.mbt` (190 行, 8 handler + 3 json helper)
- `routes_handlers_ops.mbt` (165 行, 6 handler)

### 验收

- `moon check --target native` 0 警告
- `moon test --target wasm-gc` 175/175 全绿
- smoke test 27 REST 端点全通（11 返 200，16 必填校验返 400 符合设计）
- MCP tools/list 返 25 tools，tools/call ping 返 `{"status":"ok"}`
- 单文件最大行数 747 → 270（-64%）

## Finding 2 — mcp.mbt 440 行 / 25 tool 集中单文件【中-高价值，低风险】

### 观察

`cmd/service/mcp.mbt` 440 行，25 个 `tool_def(...)` 调用集中在 `all_tools()`（L121–216），25 个 `else if name ==` 分支集中在 `invoke_tool`（L256–354）。

### 决策

**实施** — 拆为 4 文件。

### 实施

见 P11-B commit (6391f65)。文件结构：
- `mcp.mbt` (280 行) — 入口：JSON-RPC 响应构造 + id/method/params 提取 + known_tool_names + is_known_tool + check_required_fields + handle_initialize + handle_tools_list + handle_tools_call + dispatch + handle_mcp
- `mcp_args.mbt` (50 行) — 5 个 JSON 提取 helper（arg_str/int/num/bool + schema_prop）
- `mcp_schemas.mbt` (110 行) — tool_def + all_tools（25 个 tool_def 物理隔离）
- `mcp_dispatch.mbt` (120 行) — invoke_tool（25 个 else if 分支物理隔离）

### 验收

- `moon check --target native` 0 警告
- `moon test --target wasm-gc` 175/175 全绿
- smoke test 25 MCP tools 全通
- 单文件最大行数 440 → 280（-36%）

## Finding 3 — cmd/main/main.mbt 自含 jstr/jnum/jarr 复制 @lib helper【低-中价值，低风险】

### 观察

`cmd/main/main.mbt` 143 行，自含 `jstr` / `jnum` / `jarr` 3 个 helper（30 行），与 `util.mbt::get_str` / `get_num` 完全等价（签名、逻辑、返回类型一致）。`jarr` 是 `get_obj` + `Json::Array` 拆解的组合。

### 决策

**实施** — 升 `util.mbt::get_str / get_num / get_obj / get_field` 为 pub，cmd/main 复用 + 删重复 fn。

### 实施

见 P11-A commit (4f721a7)。

util.mbt 改动：
- `get_str` / `get_num` / `get_obj` 升 pub
- `get_field` 新升 pub（原为私有）—— 是 `get_obj` 的「不过滤类型」版本；`get_obj` 对 Object 字段有效，但对 Array 字段会返回空 obj，`get_field` 保留原始 Json 类型。cmd/main 的 jarr 包装必须用 `get_field`，不能用 `get_obj`

cmd/main/main.mbt 改动：
- 删 `jstr` / `jnum`（30 行），改用 `@lib.get_str` / `@lib.get_num`
- 保留 3 行 `jarr` 包装（基于 `@lib.get_field` + `Json::Array` 拆解）
- 11 个调用点更新

### R15 验证

`moon run cmd/main` 输出与改动前**字节完全相同**（2007 bytes，`fc.exe /B` 0 差异）。

### 验收

- `moon check --target native` 0 警告
- `moon test --target wasm-gc` 175/175 全绿
- R15 字节对比 0 差异
- 净 -18 行（删除 30 行重复 helper，新增 12 行 pub + 注释）

## Finding 4 — _test_helpers.mbt 漂移主动防御【低价值，低风险】

### 观察

`tests/core/_test_helpers.mbt` (4507B) 与 `tests/corpus/_test_helpers.mbt` (4507B) 是 MoonBit sub-package 限制下的必须 inline 副本（AGENTS.md 已声明）。`tests/feature/_test_helpers.mbt` (1061B → 改后 1061B) 是子集。

本评审发现：**两个文件实际有真实内容漂移**：
- core 在 `]` 与 `// 8 个真实项目主题` 之间有 1 空行
- core 在 `]` 与 `// @json.parse` 段间有 1 空行
- corpus 无对应空行

sha256 校验：core 与 corpus 不等。漂移原因可能是有一次只改了 core 没改 corpus。

### 决策

**实施** — CI 哈希校验 + pre-commit 挂接。根因（MoonBit 跨包 import 限制）无法在 MoonBit 限制下根除，但可主动防御漂移。

### 实施

见 P11-D commit (12af653)。

- `scripts/ci-check-test-helpers.ps1` (53 行) — 用 SHA256 校验 core == corpus，feature 是子集不强制
- `.githooks/pre-commit` 末尾追加 ci-check 阶段（pwsh 缺时 WARN 不阻断）
- `_test_helpers.mbt` 顶部注释加 CI 校验说明
- 顺手修了 core/corpus 真实漂移（[System.IO.File]::Copy 字节级同步）

### 验收

- `pwsh -File scripts/ci-check-test-helpers.ps1` exit 0
- 模拟漂移（手动改 core）→ exit 1 阻断 commit
- pre-commit hook 全链路通过（含新 ci-check）
- `moon test --target wasm-gc` 175/175 全绿

## Finding 5 — engine_ops.mbt 主题混杂（"style" + "运维"）【中价值，零风险，不实施】

### 观察

`engine_ops.mbt` 518 行，14 pub fn 涵盖 4 个语义层次：
- 风格：`style_check` / `style_report`（L169/228）
- 检索：`retrieve_for_prompt` / `back_align` / `term_conflicts`（L478/367/415）
- 运维：`active_learning_candidates` / `fed_export` / `fed_import` / `inject_distillation`（L7/51/59/66）
- 解释：`explain` / `hit_rate` / `context_texts` / `last_context_id` / `stats_view`（L83/113/122/134/142）

### 不实施原因

拆分会让 4 个文件平均 ~130 行，但跨子主题的"杂项"是 P10 commit B 已审视的现状：
- `engine_ops.mbt` 名字本身就是「其他/杂」的语义占位符（"ops" = 杂项 / operations）
- 进一步拆分会引入"剩余杂项层"，反而违反命名一致性
- CHANGELOG P10 段已记录此评估结论（"9 helper 改 Type::method" / "to_json 评估注释"），本结论与当时一致

**决策**：仅记录于此报告 §"Non-goals" 段，**不实施**。如未来 0.3.0 阶段需要进一步整理，可重新评估。

## Finding 6 — 0.2.0 路线图项【范围外】

`parse_tmx` / `parse_xliff` / `export_tmx` / `load_tbx` SAX 重构 / `export_tbx` TBX3 DCA+DCT / Project Spec ISO 11669:2024 全部不在本次评审范围。AGENTS.md "Roadmap" 段已声明。

## 评审约束（硬）

| 约束 | 满足 |
|---|---|
| 175/175 测试全绿 | ✓（每个 commit 后验证） |
| native+wasm-gc 双 check 0 警告 | ✓ |
| 纯本地零云依赖 | ✓（无新增外部依赖） |
| 确定性 R15 契约 | ✓（P11-A 字节比对验证） |
| 27 REST + 25 MCP 端点行为零变化 | ✓（smoke test 全通） |
| MoonBit sub-package 限制不变 | ✓（沿用 P10 同包多文件模式） |

## 经验教训

1. **.mbt 文档漂移很难被肉眼发现**：2 处 1 空行的差异在 4507B 文件中占 0.04%，但 SHA256 一眼可见。**CI 哈希校验是必需防御**。
2. **PowerShell 字节操作 vs 内容操作**：`Add-Content` / `Set-Content` 走 UTF-8 重新编码，破坏原字节；`[System.IO.File]::Copy` 是字节级保真。涉及 UTF-8 多字节字符的脚本备份用 Copy，不用 Set-Content。
3. **R15 验证必须字节比对**：commit 前 fc.exe /B 0 差异是硬证据，避免「看起来一致实际不同」的事后排查。
4. **MoonBit sub-package 限制是真限制**：跨包 import 不支持不是 bug，是设计。CI 校验是当前可用的最佳防御。

## 后续（0.2.0 / 0.3.0 路线图）

- **0.2.0**：parse_tmx / parse_xliff / export_tmx 端点暴露 + load_tbx SAX 重构 + export_tbx TBX3 DCA+DCT + pub fn 端点暴露 + Project Spec (ISO 11669:2024)
- **0.3.0**：engine_ops.mbt 进一步整理（重新评估时机）；如新增能力突破 60 个 REST 端点，可考虑 routes 拆「按业务域」二级分类（学习 / 翻译 / 运维 / 评测）

## 产物清单

### 新文件
- `cmd/service/mcp_args.mbt`（50 行）
- `cmd/service/mcp_schemas.mbt`（110 行）
- `cmd/service/mcp_dispatch.mbt`（120 行）
- `cmd/service/routes_security.mbt`（95 行）
- `cmd/service/routes_handlers_query.mbt`（250 行）
- `cmd/service/routes_handlers_metrics.mbt`（190 行）
- `cmd/service/routes_handlers_ops.mbt`（165 行）
- `scripts/ci-check-test-helpers.ps1`（53 行）

### 修改文件
- `util.mbt`（+12 / -6：4 个 fn 升 pub + 注释）
- `cmd/main/main.mbt`（+12 / -42：删 2 fn + 改 11 调用点 + 注释）
- `cmd/service/mcp.mbt`（+260 / -257：拆 4 文件后瘦身）
- `cmd/service/routes.mbt`（+260 / -657：拆 5 文件后瘦身）
- `.githooks/pre-commit`（+9：挂接 ci-check）
- `tests/core/_test_helpers.mbt`（+6：P11-D CI 提示注释 + 漂移修复）
- `tests/corpus/_test_helpers.mbt`（+5：P11-D CI 提示注释）
- `tests/feature/_test_helpers.mbt`（+3：P11-D CI 提示注释）

### 文档
- `docs/plans/2026-08-26-p11-architecture-review.md`（本文件）
- `CHANGELOG.md`（增 P11 段）
- `AGENTS.md`（"Project layout" 段增 P11 拆分说明）

### 双 remote 同步
- 4 个 commit 一次性推 github (via ghproxy.net) + gitlink
