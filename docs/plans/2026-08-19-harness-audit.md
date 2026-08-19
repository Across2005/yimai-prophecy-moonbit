# MCP/Harness Compatibility Audit 2026-08-19

> 审计范围：译脉·先知 2.0（yimai_prophecy_moonbit）MoonBit 项目的 MCP Server、JSON-RPC 层、13 个 harness config 及其验证脚本。
> 审计文件：cmd/service/mcp.mbt、cmd/service/routes.mbt、cmd/service/main.mbt、yimai_prophecy_moonbit.mbt、docs/harness-configs/*、scripts/validate-harness-configs.ps1、AGENTS.md、README.md。

---

## 1. MCP 2025-11-25 协议实现

### 1.1 发现：tools/call 缺少 -32602 参数校验
- **位置**：cmd/service/mcp.mbt（`handle_tools_call`，L343–377）
- **严重程度**：高
- **描述**：
  - 当前 `tools/call` 对缺失或类型错误的参数一律使用默认值（例如 `arg_int(args, "k", 3)`），不会返回 JSON-RPC `-32602 Invalid params`。
  - 这意味着客户端传错参数时服务静默容错，违反 JSON-RPC 2.0 / MCP 2025-11-25 对参数级错误的处理要求。
  - 例如 `{"name":"fuzzy_match","arguments":{}}` 会返回空查询的结果，而不是提示缺少 `query`。
- **修复/改进建议**：
  - 在 `invoke_tool` 前增加 required 参数校验，缺失必填参数时返回 `rpc_error(id, -32602, "Invalid params: missing 'query'")`。
  - 或利用 `tool_def` 中已有的 `required` 数组做统一校验，保持 schema 与运行时一致。

### 1.2 发现：未知工具错误码使用 -32601 而非 -32602
- **位置**：cmd/service/mcp.mbt（L353–355）
- **严重程度**：中
- **描述**：
  - 当 `tools/call` 收到不存在的 `name` 时，返回 `-32601 Method not found`。
  - 严格按 JSON-RPC 2.0 语义，method 是 `tools/call`，tool name 是参数；参数错误应返回 `-32602 Invalid params`。
  - 代码注释承认这是“业界惯例”，但仍构成与严格规范的偏离。
- **修复/改进建议**：
  - 立即修复：改为 `-32602` 并附带具体工具名。  - 或在文档中显式声明“yimai 将未知工具视为 method not found”作为有意偏离，但会减弱跨客户端兼容性。

### 1.3 发现：initialize 未协商 protocolVersion
- **位置**：cmd/service/mcp.mbt（`handle_initialize`，L328–337）
- **严重程度**：低
- **描述**：
  - `initialize` 直接返回 `protocolVersion: "2025-11-25"`，不读取客户端请求的 `protocolVersion`。
  - 当前 MCP 2025-11-25 是单版本，所以不会出错；但 0.2.0 迁移到 2026-07-28 RC 时，需要协商逻辑。
- **修复/改进建议**：
  - 0.2.0 阶段实现协议版本协商，优先返回客户端请求且服务端支持的版本。

### 1.4 发现：缺少 batch JSON-RPC 请求支持
- **位置**：cmd/service/routes.mbt（`handle_mcp`，L406–432）
- **严重程度**：中
- **描述**：
  - `/mcp` 端点只接受单个 JSON 对象，JSON-RPC 2.0 允许的数组 batch 请求会被当作解析失败或 method 为空。
  - MCP Streamable HTTP 规范允许 batch，某些客户端可能在重连或批量调用时使用。
- **修复/改进建议**：
  - 0.2.0 增加 batch 支持；当前应在文档或代码中显式声明“本实现不支持 batch”。

### 1.5 发现：tools/list 数量与文档不一致
- **位置**：cmd/service/mcp.mbt（`all_tools` L122–211；`known_tool_names` L217–222）
- **严重程度**：中
- **描述**：
  - 当前实际注册了 25 个 MCP tools（P5 新增 `mqm_re_annotate`）。
  - 但代码注释、README、AGENTS.md 多处仍写“24 tools”，README 的端点矩阵也遗漏了 `mqm_re_annotate` 以及 `/api/metrics`、`/api/health`。
- **修复/改进建议**：
  - 立即统一文档与代码为 25 tools / 27 个 REST 端点（含 metrics/health）。
  - 在 README 端点矩阵中补充 `/api/mqm_re_annotate`、`/api/metrics`、`/api/health`。

---

## 2. JSON-RPC 错误对象

### 2.1 发现：错误对象缺少 `data` 字段（可选，但建议）
- **位置**：cmd/service/mcp.mbt（`rpc_error`，L11–17）
- **严重程度**：低
- **描述**：
  - `rpc_error` 仅返回 `code` 和 `message`，未包含 `data`。
  - JSON-RPC 2.0 中 `data` 是可选字段，不是强制要求。
- **修复/改进建议**：
  - 在 `-32602` 等参数错误中补充 `data: { "field": "..." }`，方便客户端定位。

### 2.2 发现：id 处理符合规范
- **位置**：cmd/service/mcp.mbt（`extract_id`，L20–29）
- **严重程度**：信息
- **描述**：
  - `id` 为 String/Number 时原样回写；缺失 id 时按 JSON-RPC notification 处理，不回包（返回 202）。
  - 实现正确。

### 2.3 发现：解析错误使用 -32700 正确
- **位置**：cmd/service/mcp.mbt（L430）
- **严重程度**：信息
- **描述**：
  - 非法 JSON body 返回 `-32700 Parse error`，符合 JSON-RPC 2.0。

---

## 3. 13 个 harness config 的 schema

### 3.1 发现：全部 13 个 config URL 正确且一致
- **位置**：docs/harness-configs/*
- **严重程度**：信息
- **描述**：
  - 13 个 harness 配置（10 JSON + 1 TOML + 2 YAML）均指向 `http://127.0.0.1:8787/mcp`。
  - 字段名与 harness_manifest.json 中声明的 `top_key` / `url_path` 一致。

### 3.2 发现：Codex TOML 使用 transport="http" 而非 "streamable-http"
- **位置**：docs/harness-configs/codex.toml、docs/harness-configs/harness_manifest.json（codex 条目）
- **严重程度**：低
- **描述**：
  - codex.toml 使用 `transport = "http"`，而 harness_manifest.json 的 service.transport 声明为 `streamable-http`。
  - 这是为了兼容 Codex CLI ≥ 0.46 的强制要求，已在 manifest 的 `note` 中说明。
- **修复/改进建议**：
  - 保持现状，但在 README/AGENTS.md 中更醒目地说明 Codex 需要 `transport="http"`。

### 3.3 发现：Roo Code 使用 transport 字段而非 type
- **位置**：docs/harness-configs/roo-code.json
- **严重程度**：低
- **描述**：
  - roo-code.json 使用 `"transport": "http"`，与其他 JSON harness（type:"http"）不同。
  - manifest 的 `note` 已说明“Roo Code 用 transport="http"（不是 type）”。
- **修复/改进建议**：
  - 保持现状，因为不同客户端 schema 不同；但应在 harness_manifest.json 的 `required_fields` 中显式包含 transport。

### 3.4 发现：Windsurf 使用 serverUrl 字段
- **位置**：docs/harness-configs/windsurf.json
- **严重程度**：低
- **描述**：
  - Windsurf 使用 `serverUrl` 而非 `url`，manifest 中 `url_path` 已正确配置为 `["yimai", "serverUrl"]`。
- **修复/改进建议**：
  - 信息记录，无需修改。

---

## 4. harness_manifest.json 与 config 文件一致性

### 4.1 发现：harness_manifest.json 与 13 个 config 文件一致
- **位置**：docs/harness-configs/harness_manifest.json
- **严重程度**：信息
- **描述**：
  - 13 个 harness 条目、config_file 名称、top_key/url_path 均与实际文件一致。
  - cody 标记为 deprecated，github-copilot 标记为 doc-only，说明清晰。

### 4.2 发现：manifest 缺少对 config schema 字段的完整约束
- **位置**：docs/harness-configs/harness_manifest.json
- **严重程度**：低
- **描述**：
  - 虽然每个 harness 都有 `required_fields` 数组，但 manifest 没有声明字段类型、枚举值等 schema 约束。
  - 例如 `type` 应为 `"http"` 或 `"streamable-http"`，`transport` 应为 `"http"` 等。
- **修复/改进建议**：
  - 0.2.0 在 harness_manifest.json 中增加 `schema` 或 `allowed_values` 段，供验证脚本使用。

---

## 5. validate-harness-configs.ps1 覆盖性

### 5.1 发现：脚本覆盖全部 13 个 harness
- **位置**：scripts/validate-harness-configs.ps1（L88–188）
- **严重程度**：信息
- **描述**：
  - 脚本读取 harness_manifest.json 并遍历所有 harness 条目，覆盖 13/13。
  - 对 JSON 校验 URL，对 TOML 校验 url+transport，对 YAML 分 config 型和 doc-only 处理，逻辑正确。

### 5.2 发现：脚本未校验 JSON harness 的 type/transport 值
- **位置**：scripts/validate-harness-configs.ps1（L106–128）
- **严重程度**：中
- **描述**：
  - JSON 分支仅校验 URL 是否等于 service.url，不校验 `type` 或 `transport` 字段的值。
  - 若某 JSON harness 的 `type` 被错写为 `stdio` 或完全缺失，脚本不会报错。
- **修复/改进建议**：
  - 在 JSON 分支增加 `type`/`transport` 值校验：允许的值为 `"http"`、`"streamable-http"`、或 `"transport": "http"`。

### 5.3 发现：脚本未校验 required_fields 是否真实存在
- **位置**：scripts/validate-harness-configs.ps1
- **严重程度**：低
- **描述**：
  - `required_fields` 数组目前只是元数据，脚本没有用它做断言。
- **修复/改进建议**：
  - 让脚本根据 `required_fields` 自动检查 config 文件中对应字段是否存在。

---

## 6. 与 MCP 2026-07-28 RC 的差异

### 6.1 发现：2026-07-28 RC 差异已在文档中声明
- **位置**：docs/harness-configs/README.md（L72–76）、AGENTS.md（L175）、README.md（L913）
- **严重程度**：信息
- **描述**：
  - 文档明确说明：当前实现为 MCP 2025-11-25，2026-07-28 RC 的 breaking changes（移除 initialize 握手、`Mcp-Method`/`Mcp-Name` 头、`Mcp-Session-Id`、JSON Schema 2020-12 完整支持、错误码 `-32602` 等）将延后到 0.2.0。
  - 文档说明充分，当前状态合理。

### 6.2 发现：当前实现已部分涉及 2026-07-28 RC 要求但未完全对齐
- **位置**：cmd/service/mcp.mbt
- **严重程度**：中
- **描述**：
  - 2026-07-28 RC 要求 `tools/call` 对参数错误返回 `-32602`，当前实现未做到（见 1.1）。
  - RC 要求 `Mcp-Method`/`Mcp-Name` 头（用于 SSE/Streamable HTTP 路由），当前未实现。
  - RC 移除了 `initialize` 握手，当前仍保留；这是 2025-11-25 合规，但与未来 RC 不兼容。
- **修复/改进建议**：
  - 立即修复项：补上 `-32602` 参数错误处理。
  - 0.2.0 规划项：移除 initialize 握手、增加 `Mcp-Method`/`Mcp-Name`/`Mcp-Session-Id` 头支持、完整 JSON Schema 2020-12 校验。

---

## 7. /api/* 端点与 MCP tools 对应关系

### 7.1 发现：/api/* 端点与 MCP tools 基本一一对应
- **位置**：yimai_prophecy_moonbit.mbt（routes_meta）、cmd/service/mcp.mbt（all_tools）
- **严重程度**：信息
- **描述**：
  - 25 个 MCP tools 与 24 个数据端点（再加 `/api/mqm_re_annotate`）一一对应。
  - `/api/ping` 对应 MCP tool `ping`，`/api/tm_count` 对应 `tm_count`，等等。

### 7.2 发现：/api/health 和 /api/metrics 未暴露为 MCP tools
- **位置**：cmd/service/mcp.mbt（`all_tools`）
- **严重程度**：低
- **描述**：
  - `/api/health` 和 `/api/metrics` 仅作为 REST 端点存在，不在 `tools/list` 中。
  - 对于纯 MCP 消费的 harness，无法通过 MCP 获取健康度与 metrics。
- **修复/改进建议**：
  - 考虑新增 MCP tools：`health`、`metrics`，保持 REST/MCP 能力一致。
  - 或至少通过 MCP `ping` tool 提供基础健康信息。

### 7.3 发现：README 端点矩阵遗漏 mqm_re_annotate、metrics、health
- **位置**：README.md（Service Layer 端点矩阵）
- **严重程度**：低
- **描述**：
  - 端点矩阵标题为“24 个”，但实际 routes_meta 有 27 个条目，矩阵缺少 `/api/mqm_re_annotate`、`/api/metrics`、`/api/health`。
- **修复/改进建议**：
  - 立即更新 README 端点矩阵，补齐上述 3 个端点，并将标题改为 27 个 REST 端点。

---

## 8. 健康检查、metrics 端点可用于 harness 心跳检测

### 8.1 发现：/api/health 可暴露服务健康状态
- **位置**：cmd/service/routes.mbt（L712–732）
- **严重程度**：信息
- **描述**：
  - `/api/health` 返回 `status`、`tm_count`、`uptime_seconds`、`last_save_status`、`last_save_age_seconds`、`version`。
  - 可用于 harness 心跳检测。

### 8.2 发现：/api/metrics 可暴露引擎指标
- **位置**：cmd/service/routes.mbt（L690–706）
- **严重程度**：信息
- **描述**：
  - `/api/metrics` 返回 `tm_count`、`term_count`、`total_memories`、`term_coverage`、`predict_calls`、`avg_predictive_value`、`hit_rate`。
  - 适合 harness 做性能/容量监控。

### 8.3 发现：MCP 层未提供等效心跳 tool
- **位置**：cmd/service/mcp.mbt
- **严重程度**：低
- **描述**：
  - MCP 层仅有 `ping` tool（返回 `{"status":"ok"}`），没有 `health`/`metrics` tool。
  - 依赖 MCP 的 harness 若只能访问 `/mcp`，则无法通过 tools/call 拿到详细健康/指标信息。
- **修复/改进建议**：
  - 新增 `health` 和 `metrics` MCP tools，返回与 `/api/health`、`/api/metrics` 相同的数据。

---

## 9. 其他发现

### 9.1 发现：缺少 MCP 协议的自动化单元测试
- **位置**：tests/ 目录
- **严重程度**：低
- **描述**：
  - 现有测试集中在引擎 wasm-gc 测试，未见针对 `initialize`、`tools/list`、`tools/call`、错误码等的单元测试。
  - `scripts/smoke.ps1` 可能有端到端覆盖，但不可作为持续集成中的协议回归。
- **修复/改进建议**：
  - 0.2.0 增加 MCP JSON-RPC 协议测试，覆盖正常路径、错误码、notification、batch 等。

---

## 汇总：立即修复项 vs 0.2.0 规划项

### 立即修复项（可在 0.1.x 完成）

1. **tools/call 增加 -32602 参数错误处理**（高）：对缺失/类型错误的必填参数返回 `-32602 Invalid params`。
2. **统一文档中的 tools/端点数量**（中）：将“24 tools / 24 端点”更新为“25 MCP tools / 27 REST 端点”。
3. **更新 README 端点矩阵**（中）：补充 `/api/mqm_re_annotate`、`/api/metrics`、`/api/health`。
4. **validate-harness-configs.ps1 增加 type/transport 校验**（中）：防止 JSON harness 的 transport 字段错误。
5. **处理未知工具错误码**（中）：建议改为 `-32602`，或在文档中显式声明为 `-32601` 偏离。

### 0.2.0 规划项

1. **迁移 MCP 协议到 2026-07-28 RC**：移除 initialize 握手、支持 `Mcp-Method`/`Mcp-Name`/`Mcp-Session-Id` 头、完整 JSON Schema 2020-12 校验。
2. **新增 MCP health/metrics tools**：让纯 MCP 消费的 harness 也能做心跳与监控。
3. **增加 batch JSON-RPC 请求支持**：提升与更复杂 MCP 客户端的兼容性。
4. **实现 protocolVersion 协商**：为未来多版本 MCP 做准备。
5. **新增 MCP 协议自动化测试**：覆盖 initialize、tools/list、tools/call、错误码、notification、batch 等路径。

---

## 关键问题数量

- 高严重度：**1** 项
- 中严重度：**5** 项
- 低严重度：**8** 项
- 信息：**5** 项

合计：**19** 项发现，其中 **6** 项建议立即修复，**5** 项建议纳入 0.2.0 规划。

---

## 最优先修复的 3 个兼容性问题

1. **tools/call 缺少 -32602 参数校验**
   - 影响：违反 JSON-RPC 2.0 / MCP 规范，参数错误静默容错，会导致客户端难以调试。
   - 位置：cmd/service/mcp.mbt `handle_tools_call`
   - 修复：在调用 `invoke_tool` 前，根据 tool schema 的 `required` 数组校验参数，缺失时返回 `rpc_error(id, -32602, ...)`。

2. **未知工具错误码使用 -32601 而非 -32602**
   - 影响：与 JSON-RPC 2.0 语义不一致，可能被严格 MCP client 视为 method 不存在而不是参数错误。
   - 位置：cmd/service/mcp.mbt L353–355
   - 修复：将未知工具错误码从 `-32601` 改为 `-32602`，或至少将当前行为作为已知偏离写入文档。

3. **文档与代码的 tools/端点数量不一致**
   - 影响：README、AGENTS.md、代码注释多处写“24 tools/24 端点”，但代码实际为 25 tools/27 端点，导致新用户和维护者困惑。
   - 位置：README.md、AGENTS.md、cmd/service/mcp.mbt 注释
   - 修复：全面更新文档和注释，统一为 25 MCP tools / 27 REST 端点，并补齐 README 端点矩阵。
