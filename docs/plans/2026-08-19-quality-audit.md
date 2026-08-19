# Quality Audit 2026-08-19

## 1. 审计范围与方法

- **审计时间**：2026-08-19
- **项目路径**：`d:/Agent work/buddy/yimai_prophecy_moonbit`
- **检查文件**：根目录 `.mbt`（`engine.mbt`、`util.mbt`、`yimai_prophecy_moonbit.mbt`）、`cmd/main/*.mbt`、`cmd/service/*.mbt`、`tests/core/*.mbt`、`tests/corpus/*.mbt`、`tests/feature/*.mbt`、`scripts/*.ps1`、`docs/harness-configs/*`、`AGENTS.md`、`README.md`。
- **使用工具**：
  - `moon check --target wasm-gc`
  - `moon test --target wasm-gc`
  - `scripts/validate-harness-configs.ps1`
  - 人工代码走查 + 函数长度统计
- **关键结果**：
  - `moon check --target wasm-gc`：**29 条 warning，0 条 error**
  - `moon test --target wasm-gc`：**159 / 159 全部通过**
  - `validate-harness-configs.ps1`：**13 / 13 全部通过**

---

## 2. 关键结论

- **核心引擎稳定**：全部 159 个测试通过，wasm-gc 契约回归保持绿色。
- **主要风险集中在**：
  1. 脚本/文档中的端点/工具数量未随 P5 新增的 `mqm_re_annotate` 同步，导致 `smoke.ps1` 断言会失败。
  2. `cmd/service` 为 native-only，`moon check --target wasm-gc` 不会检查其中大量弃用 API（`Map::new()`、`.size()`、`StringView.to_string()` 等）。
  3. `engine.mbt` 文件体积过大（3 569 行 / ≈129 KB），且多个核心函数超过 80 行，违反单一职责。
- **R15 确定性契约**：`AGENTS.md` 已充分注释 `Map[String, T]` 的顺序依赖，代码中未发现 `HashMap`/`@hashmap` 误用，确定性回归测试通过。

---

## 3. 问题清单

### Critical Issues（严重，需优先修复）

#### 1. MCP `tools/list` 数量与 `smoke.ps1` 断言不一致，文档数字陈旧
- **位置**：
  - `cmd/service/mcp.mbt:217-222`（`known_tool_names` 25 项）
  - `cmd/service/mcp.mbt:122-210`（`all_tools()` 25 个 tool_def）
  - `scripts/smoke.ps1:53`：`Check "MCP tools/list = 24"` 仍断言 24
  - `README.md`、`AGENTS.md` 中仍多处写“24 tools”
- **严重程度**：严重
- **描述**：P5 新增 `mqm_re_annotate` MCP tool 后，`known_tool_names` 与 `all_tools()` 已包含 25 个工具，但 `smoke.ps1` 仍断言 `tools.Count -eq 24`。实际运行 smoke 时该断言会失败。同时 README/AGENTS 仍写 24 tools，文档与实现不一致。
- **改进建议**：
  1. 将 `smoke.ps1:53` 的 24 改为 25，或改为与 `known_tool_names.length()` 一致。
  2. 统一更新 README.md、AGENTS.md 中“24 tools”的表述为 25，并建立从 `known_tool_names.length()` 派生的单一来源。

#### 2. 服务层（`cmd/service`）存在大量弃用 API，且未被门禁覆盖
- **位置**：
  - `cmd/service/mcp.mbt:290`：`Map::new()`
  - `cmd/service/mcp.mbt:312`：`table.size()`
  - `cmd/service/routes.mbt:645`：`Map::new()`
  - `cmd/service/routes.mbt:662`：`table.size()`
  - `cmd/service/routes.mbt:33`：`parts[0].to_string()` 作用于 `StringView`
  - `util.mbt:909,973`：`Map::new()`
  - `engine.mbt:841`：`pool.size()`
  - `engine.mbt:3223`：`x.to_string()` 作用于 `StringView`
  - `util.mbt:997,998`：`x.to_string()` 作用于 `StringView`
- **严重程度**：严重
- **描述**：`moon check --target wasm-gc` 只检查 wasm-gc 目标，`cmd/service` 是 native target，因此服务层大量弃用调用（`Map::new()`、`.size()`、`StringView.to_string()`）未被门禁捕获。这些 API 未来可能被移除，会导致 native build 失败。
- **改进建议**：
  1. `Map::new()` → `Map::from_iter(([] : Array[(K, V)]).iter())` 或 `Map([])`；`.size()` → `.length()`；`StringView.to_string()` → `to_owned()`。
  2. 在 `scripts/dev.ps1` 与 `.githooks/pre-commit` 中加入 native target 检查（如环境允许），或在 CI 中单独跑 `moon build cmd/service --target native`。
#### 3. `engine.mbt` 文件过大，多个核心函数超长
- **位置**：`engine.mbt`（3 569 行 / ≈129 KB）
- **严重程度**：严重
- **描述**：`engine.mbt` 已接近 3 600 行，远超健康阈值。关键函数超长：
  - `recall`：`engine.mbt:804-960`（156 行）
  - `predict_aggregate_transitions`：`engine.mbt:984-1148`（164 行）
  - `style_report`：`engine.mbt:3280-3386`（106 行）
  - `remember`：`engine.mbt:670-759`（89 行）
  - `drift_report`：`engine.mbt:2790-2874`（84 行）
  - `from_json`：`engine.mbt:3136-3220`（84 行）
  - `observe`：`engine.mbt:1265-1340`（75 行）
  - `mqm_tags`：`engine.mbt:2317-2392`（75 行）
  违反单一职责，增加维护、审查和测试难度。
- **改进建议**：
  1. 按子系统拆分 `engine.mbt`：例如 `engine_predict.mbt`、`engine_recall.mbt`、`engine_tm.mbt`、`engine_value.mbt`。
  2. 将超长函数进一步拆分为职责单一的小函数，建议每个函数不超过 40-50 行。

---

### Warnings（警告，建议尽快修复）

#### 4. `tests/core/_test_helpers.mbt` 与 `tests/corpus/_test_helpers.mbt` 完全重复，同步注释误导
- **位置**：
  - `tests/core/_test_helpers.mbt`
  - `tests/corpus/_test_helpers.mbt`
- **严重程度**：警告
- **描述**：两个文件共 158 行逐字节相同。注释写“与 `tests/core/yimai_prophecy_moonbit_accept_test.mbt` 顶层 helper 同步修改”，并未指明与另一个子包的副本同步，容易在后续修改时遗漏。
- **改进建议**：
  1. 在文件顶部注释中明确两个副本的镜像关系，并声明“任何修改必须同时同步两个文件”。
  2. 增加 CI 或 pre-commit 钩子，校验两个 `_test_helpers.mbt` 的 MD5/SHA 一致；或写一个生成脚本减少人工同步。

#### 5. `moon check` 29 条 warning 未清理
- **位置**：详见“附录 A：moon check 告警汇总”
- **严重程度**：警告
- **描述**：`moon check --target wasm-gc` 报告 29 条 warning，包括弃用语法、未使用值、缺失 import、未使用函数/变量。这些告警污染构建输出，会掩盖未来新增的问题。
- **改进建议**：
  1. 将旧方法语法 `fn meth(self : Type, ...)` 批量改为 `fn Type::meth(self : Type, ...)`。
  2. 在 `tests/core/moon.pkg` 和 `tests/corpus/moon.pkg` 中显式 import `moonbitlang/core/json`。
  3. 删除未使用的函数/变量，或为它们补充测试断言。
  4. 将 `Map::new()` 和 `.size()` 替换为新 API；`to_string()` debug 调用改用 `Debug`/`Show`。

#### 6. 文档/脚本中端点/工具数量表述不一致
- **位置**：
  - `README.md`：多处写“24 个 `/api/*` 端点 / 24 tools”
  - `AGENTS.md`：“24 个 `/api/*` 端点（多数 POST…）”、“24 tools”
  - `scripts/run.ps1:4` 写 24 REST endpoints，但 `run.ps1:14-16` 只列出 13 个
  - `scripts/dev.ps1:45` 写“REST API: 13 endpoints under /api/*”
  - `scripts/smoke.ps1:3` 写“24 REST endpoints + MCP”
  - `cmd/service/routes.mbt:18` 注释写“26 项同步”
  - `yimai_prophecy_moonbit.mbt:18` 注释写“两者都为 26 项”
- **严重程度**：警告
- **描述**：当前 `routes_meta` 实际为 27 项（24 baseline + metrics + health + mqm_re_annotate），MCP tools 25 项。脚本与文档仍停留在 24/26/13，会造成新成员误解，并且 `smoke.ps1` 断言将失败。
- **改进建议**：
  1. 统一以 `routes_meta.length()`、`known_tool_names.length()` 为单一来源。
  2. 全面扫描脚本、注释、README、AGENTS，更新为准确数字，或改为动态描述（例如“当前 routes_meta 包含的所有端点”）。

#### 7. `util.mbt` 存在死代码 `hex_nibble`
- **位置**：`util.mbt:87-93`
- **严重程度**：警告
- **描述**：`fn hex_nibble(b : Byte)` 未被任何代码引用，`decode_pct` 使用的是 `hex_nibble_char(c : Char)`。这是典型死代码。
- **改进建议**：删除 `hex_nibble` 函数，或在确认需求后补充使用它的代码和测试。

#### 8. `tests/corpus/` 测试文件存在未使用辅助函数/变量
- **位置**：
  - `tests/corpus/yimai_prophecy_moonbit_extended_corpus_test.mbt:16`：`fn r4_e`
  - `tests/corpus/yimai_prophecy_moonbit_extended_corpus_test.mbt:21`：`fn er_recall_texts`
  - `tests/corpus/yimai_prophecy_moonbit_frontier_corpus_test.mbt:32`：`fn r4f`
  - `tests/corpus/yimai_prophecy_moonbit_frontier_corpus_test.mbt:182`：`let fc_all_corpora`
  - `tests/corpus/yimai_prophecy_moonbit_frontier_corpus_test.mbt:188`：`let fc_corpus_names`
- **严重程度**：警告
- **描述**：这些函数/变量被定义但未被使用，可能是重构遗留或测试覆盖缺口。
- **改进建议**：要么删除，要么补充对应的测试断言；若保留用于未来扩展，请加 `// TODO` 说明。
#### 9. `engine.mbt` 仍使用旧方法语法（deprecated syntax）
- **位置**：
  - `engine.mbt:961`：`fn predict_collect_activations(self : ProphecyEngine, ...)`
  - `engine.mbt:984`：`fn predict_aggregate_transitions(self : ProphecyEngine, ...)`
  - `engine.mbt:1149`：`fn predict_rank_and_pack(self : ProphecyEngine, ...)`
  - `engine.mbt:1420`：`fn consolidate_edge_decay(self : ProphecyEngine)`
  - `engine.mbt:1442`：`fn consolidate_trans_decay(self : ProphecyEngine)`
  - `engine.mbt:1456`：`fn consolidate_prune_nodes(self : ProphecyEngine)`
  - `engine.mbt:1485`：`fn consolidate_meta_cognition(self : ProphecyEngine)`
  - `engine.mbt:1806`：`fn fuzzy_score_one(self : ProphecyEngine, ...)`
  - `engine.mbt:1832`：`fn fuzzy_pack_top(self : ProphecyEngine, ...)`
- **严重程度**：警告
- **描述**：这些函数使用 `fn meth(self : Type, ...)` 旧语法，已被 MoonBit 编译器标记为 deprecated。未来 toolchain 升级可能强制要求 `fn Type::meth(...)` 形式。
- **改进建议**：批量重构为 `fn ProphecyEngine::predict_collect_activations(...)` 等新语法。

#### 10. `cmd/service/routes.mbt` 路由表注释数字陈旧
- **位置**：`cmd/service/routes.mbt:18`、`cmd/service/routes.mbt:86`
- **严重程度**：警告
- **描述**：注释仍写“与根模块 routes_meta 保持 26 项同步”“在路由表里线性查找（26 项规模）”。实际 `routes_meta` 已有 27 项。
- **改进建议**：将 26 改为 27；或直接写“与 `routes_meta.length()` 一致”。

#### 11. `tests/feature/moon.pkg` 触发 `unused_package` / `unused_package alias` 告警
- **位置**：`tests/feature/moon.pkg:2`
- **严重程度**：警告
- **描述**：`moon check` 报告该 import 的包和别名 `@lib` 未被使用，但 feature 测试文件显然通过 `@lib.routes_meta` 等引用它。可能是当前 MoonBit 版本的误报，但告警会混淆门禁。
- **改进建议**：确认 `tests/feature/moon.pkg` 的 import 语法是否最优；若确认为误报，在 `AGENTS.md` 中记录并跟踪，待 MoonBit 升级后重试；如非误报，补充/修正引用。

---

### Suggestions（建议，可优化）

#### 12. `AGENTS.md` 存在重复标题
- **位置**：`AGENTS.md:192`、`AGENTS.md:194`
- **严重程度**：建议
- **描述**：连续出现两个 `## Useful entry points` 二级标题，影响文档观感，疑似编辑残留。
- **改进建议**：删除重复标题或合并下方表格。

#### 13. `MAX_BODY_BYTES` 命名与实现不符
- **位置**：`cmd/service/routes.mbt:13-16`
- **严重程度**：建议
- **描述**：常量名为 `MAX_BODY_BYTES`，但实际按字符数（char count）而非字节数限制请求体大小。虽然注释已说明，但命名仍具误导性。
- **改进建议**：重命名为 `MAX_BODY_CHARS`；若需真正按字节限制，应使用字节长度校验。

#### 14. `README.md` 国际标准表格列数异常
- **位置**：`README.md` 中国际标准表格的 `W3C ITS 2.0` 行
- **严重程度**：建议
- **描述**：该表格为 3 列表头，但 `W3C ITS 2.0` 所在行只有 2 列数据，Markdown 渲染可能错位。
- **改进建议**：补齐第三列说明，或将该行移出表格单独说明。


---

## 4. R15 确定性契约评估

R15 契约遵守良好。未发现 HashMap / @hashmap 使用；AGENTS.md 已注释 Map 插入序；routes_test 覆盖 to_json 字节回归。

## 5. 测试覆盖评估

159 / 159 测试通过。新增 mqm_re_annotate 功能有 feature 测试。主要缺口：cmd/service 为 native-only，当前 CI 未覆盖弃用 API。

## 6. Code Conventions 遵媪情况

函数长度过大；moon check 存在 29 / 51 条 warning。命名与注释一致。

---

## 附录 A：moon check 告警汇总

wasm-gc target：29 条 warning，0 error。native target：51 条 warning，0 error。主要类别：deprecated API、deprecated syntax、unused_value、unused_package、core_package_not_imported。

## 附录 B：engine.mbt 超长函数统计

| 函数 | 起始行 | 结束行 | 行数 |
| --- | --- | --- | --- |
| predict_aggregate_transitions | 984 | 1148 | 164 |
| recall | 804 | 960 | 156 |
| style_report | 3280 | 3386 | 106 |
| remember | 670 | 759 | 89 |
| drift_report | 2790 | 2874 | 84 |
| from_json | 3136 | 3220 | 84 |
| observe | 1265 | 1340 | 75 |
| mqm_tags | 2317 | 2392 | 75 |

## 附录 C：文件体积统计

| 文件 | 行数 | 大小 |
| --- | --- | --- |
| engine.mbt | 3569 | ~129 KB |
| util.mbt | ~1050 | ~38 KB |
| cmd/service/routes.mbt | ~720 | ~25 KB |
| cmd/service/mcp.mbt | ~450 | ~17 KB |

---

## 7. 优先修复清单

### P0 立即修复
- 1. MCP `tools/list` 数量与 `smoke.ps1` 断言不一致，文档数字陈旧
- 2. 服务层（`cmd/service`）存在大量弃用 API，且未被门禁覆盖
- 3. `engine.mbt` 文件过大，多个核心函数超长

### P1 短期修复
- 4. `tests/core/_test_helpers.mbt` 与 `tests/corpus/_test_helpers.mbt` 完全重复，同步注释误导
- 5. `moon check` 29 条 warning 未清理
- 6. 文档/脚本中端点/工具数量表述不一致
- 7. `util.mbt` 存在死代码 `hex_nibble`
- 8. `tests/corpus/` 测试文件存在未使用辅助函数/变量
- 9. `engine.mbt` 仍使用旧方法语法（deprecated syntax）
- 10. `cmd/service/routes.mbt` 路由表注释数字陈旧
- 11. `tests/feature/moon.pkg` 触发 `unused_package` / `unused_package alias` 告警

### P2 中期优化
- 12. `AGENTS.md` 存在重复标题
- 13. `MAX_BODY_BYTES` 命名与实现不符
- 14. `README.md` 国际标准表格列数异常
