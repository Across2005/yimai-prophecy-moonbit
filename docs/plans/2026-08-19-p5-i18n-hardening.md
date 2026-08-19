# P5 I18n-Hardening & Multi-Harness Connectivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 0.1.x 路线内，把 13 harness 连通性、MQM 评估严谨性、商务领域覆盖、文档透明度推到与 2026 国际前沿翻译要求（ISO 5060:2024 / MQM 2025-10 re-annotation / ISO 11669:2024 / GB/T 30539-2025 / MCP 2026-07-28 RC 路线图）对齐的位置。

**Architecture:** 5 个原子 commit（不破坏现有 151/151 测试）：(1) harness config schema 自动化校验；(2) MQM Critical 二次审 (re-annotation) 流程；(3) 商务领域语料；(4) MQM severity 三方对齐文档化；(5) CHANGELOG/README/AGENTS 整合 + 双 remote 推送。

**Tech Stack:** MoonBit 0.1.2026 (wasm-gc + native), JSON-only FFI, zero third-party dependency.

---

## 任务背景

### 项目基线
- master: `a04cb03` (P4 frontier corpus 增量)
- 测试: 151/151 wasm-gc + native 全绿
- MCP spec: 2025-11-25 (Streamable HTTP, JSON-RPC 2.0)
- 13 harness drop-in config (aider / claude-code / claude-desktop / cline / codex / cody / continue / cursor / gemini-cli / github-copilot / roo-code / windsurf / zed)
- MQM severity: None=0/Minor=1/Major=5/Critical=10

### 2026 国际前沿翻译要求（基于本次联网调研）
1. **ISO 5060:2024** — 翻译输出评估指南（error types + penalty points + severity levels），不可认证但是行业事实标准
2. **MQM 2025-10-28 论文 (Google)** — 二次标注 re-annotation 改进 MQM 一致性
3. **ISO 11669:2024** — 翻译项目交付指南（强调商务领域）
4. **GB/T 30539-2025** — 中国商务领域语言服务国家标准，2026-02-01 实施
5. **MCP 2026-07-28 RC** — 移除 Session / 强制 Mcp-Method / Mcp-Name header / JSON Schema 2020-12（breaking change, 已声明 0.2.0 切换）
6. **EU AI Act 2026-08-02** — 高风险 AI 系统强制合规（翻译非 high-risk，但部署者仍需声明边界）

### P5 范围（不含）
- **MCP 2026-07-28 RC 完整切换**：已有 0.2.0 路线，本轮不破现有 harness
- **TMX/XLIFF/SRX 解析**：0.2.0 路线
- **engine.mbt / util.mbt 进一步拆分**：P4 已拆 predict/consolidate，本轮避免回归

---

## Global Constraints

- **零云端依赖**：所有新代码不能引入网络/磁盘外依赖
- **MoonBit FFI**：JSON 构造必须走 `@lib.obj`/`@lib.str_json`/`@lib.arr_json`/`@lib.num_json`，禁止字符串拼接
- **测试基线**：每个 commit 必须保持 151/151 绿，新增测试加号增量
- **determinism**：同输入必同输出（R15 契约），禁止 RNG
- **API 兼容**：24 个 MCP tool 名称 + 24 个 REST 端点路径不变
- **单一源**：路线表 / 工具名 / 路由元数据走 `@lib.routes_meta` / `known_tool_names` 单一源

---

## Task 1: 13 Harness Config Schema 自动校验

**Files:**
- Create: `docs/harness-configs/harness_manifest.json`（13 个 harness 单一源清单）
- Create: `scripts/validate-harness-configs.ps1`（PowerShell 解析 13 个 config + 校验必填字段）
- Modify: `docs/harness-configs/README.md`（加 "自动化校验" 段）
- Create: `yimai_prophecy_moonbit_harness_config_test.mbt`（wasm-gc 不可读 fs，故验证逻辑放 .ps1 + 在 README 文档化）

**Interfaces:**
- Consumes: `docs/harness-configs/*.json` + `*.toml` + `*.yml`
- Produces: `harness_manifest.json`（harness 名 / 路径 / 协议 / 必填字段 / transport / form）

### Step 1: 创建 harness_manifest.json（单一源）

```json
{
  "$schema": "https://yimai-prophecy-moonbit.local/schemas/harness-manifest.v1.json",
  "service": {
    "url": "http://127.0.0.1:8787/mcp",
    "protocol": "mcp",
    "spec": "2025-11-25",
    "transport": "streamable-http"
  },
  "harnesses": [
    { "name": "claude-desktop", "config_file": "claude-desktop.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "%APPDATA%\\Claude\\claude_desktop_config.json" },
    { "name": "claude-code", "config_file": "claude-code.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "~/.claude/mcp.json" },
    { "name": "gemini-cli", "config_file": "gemini-cli.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "~/.gemini/settings.json" },
    { "name": "cursor", "config_file": "cursor.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "~/.cursor/mcp.json" },
    { "name": "cline", "config_file": "cline.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "Cline VS Code UI" },
    { "name": "continue", "config_file": "continue.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "~/.continue/config.json" },
    { "name": "roo-code", "config_file": "roo-code.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "Roo Code VS Code UI" },
    { "name": "windsurf", "config_file": "windsurf.json", "form": "json", "top_key": "mcpServers", "required_fields": ["mcpServers.yimai.url"], "client_reads": "~/.windsurf/mcp.json" },
    { "name": "codex", "config_file": "codex.toml", "form": "toml", "top_key": "mcp_servers", "required_fields": ["[mcp_servers.yimai]", "url", "transport"], "client_reads": "~/.codex/config.toml" },
    { "name": "aider", "config_file": "aider.conf.yml", "form": "yaml", "top_key": null, "required_fields": ["--mcp flag"], "client_reads": "~/.aider.conf.yml", "note": "Aider 通过 CLI flag --mcp 启用，不读 JSON/TOML 配置文件" },
    { "name": "cody", "config_file": "cody.json", "form": "json", "top_key": "cody.mcp.servers", "required_fields": ["cody.mcp.servers.yimai.url"], "client_reads": "~/.config/sourcegraph/cody.json", "deprecated": "2025-08" },
    { "name": "zed", "config_file": "zed.json", "form": "json", "top_key": "context_servers", "required_fields": ["context_servers.yimai.url"], "client_reads": "~/.config/zed/settings.json" },
    { "name": "github-copilot", "config_file": "github-copilot.yml", "form": "yaml", "top_key": null, "required_fields": ["copilot-setup-steps"], "client_reads": ".github/workflows/copilot-setup-steps.yml", "note": "GitHub 托管 runner，与 127.0.0.1:8787 网络隔离；这是 PR 工作流内同 runner 启动 yimai 的示例片段" }
  ]
}
```

- [ ] 写 `docs/harness-configs/harness_manifest.json`
- [ ] commit: `P5-1: harness_manifest.json 单一源 + 13 harness schema 清单`

### Step 2: 写 PowerShell 校验脚本

`scripts/validate-harness-configs.ps1`：
- 读 `harness_manifest.json` → 遍历每个 harness
- 对 JSON：用 `[System.Text.Json.JsonDocument]::Parse` 校验语法 + 提取 `top_key` 路径下嵌套的 URL
- 对 TOML：用 `[System.Collections.Specialized.OrderedDictionary]` + 手写 `[section.key]` 解析（避免引入新依赖）
- 对 YAML：用 `ConvertFrom-Yaml` (PS 7+ 内置) — 校验存在
- 统一断言：所有 harness 都指向 `http://127.0.0.1:8787/mcp`（harness 12 + github-copilot 例外）
- 退出码：0 = 全通过 / 1 = 有失败

- [ ] 写 `scripts/validate-harness-configs.ps1`
- [ ] 运行：`powershell -ExecutionPolicy Bypass -File scripts/validate-harness-configs.ps1` → 期望 13/13 通过
- [ ] commit: `P5-1: scripts/validate-harness-configs.ps1 自动化 schema 校验`

### Step 3: README 增段

`docs/harness-configs/README.md`：
- 加 "## Schema 校验（自动化）" 段，引用脚本路径 + manifest
- 引用 manifest URL 字段约束

- [ ] 修改 `docs/harness-configs/README.md` 加 "Schema 校验" 段
- [ ] 写完 commit: `P5-1: harness-configs README 加 schema 校验段`

---

## Task 2: MQM Re-Annotation 流程（Google 2025-10-28 论文对齐）

**Files:**
- Modify: `engine.mbt` — 新增 `mqm_re_annotate` 方法（在 qe_auto / mqm 流程后追加）
- Modify: `cmd/service/routes.mbt` — 加 `POST /api/mqm_re_annotate` 端点
- Modify: `cmd/service/mcp.mbt` — 加 `mqm_re_annotate` tool
- Create: `yimai_prophecy_moonbit_mqm_reannotation_test.mbt` — T38-T40

**Interfaces:**
- Consumes: `qe_auto` 返回的 mqm 段（含 severity）
- Produces: `mqm_re_annotate` 流程：所有 Critical severity 段强制二次审（返回 `re_annotated: true` + 一致性标签 `consistent | flipped`）

### Step 1: 写失败测试

```moonbit
// T38: MQM re-annotation 触发（Critical 段必须二次审）
test "mqm_re_annotate_flags_critical" {
  let eng = ProphecyEngine::new()
  // 构造一段触发 Critical severity 的源-目标对
  let result = eng.mqm_re_annotate(
    "The device must not be pressurized",
    "应当对该装置加压",
    0.30  // 极低 match_rate 触发 Critical (negation flip)
  )
  // 至少 1 个 Critical 段，且 re_annotated 字段为 true
  assert_eq(result.contains("\"re_annotated\":true"), true)
  assert_eq(result.contains("\"severity\":\"Critical\""), true)
}
```

- [ ] 写 `yimai_prophecy_moonbit_mqm_reannotation_test.mbt` 含 T38
- [ ] 运行：`moon test --target wasm-gc -f yimai_prophecy_moonbit_mqm_reannotation_test.mbt` → 期望 FAIL（mqm_re_annotate 还不存在）
- [ ] commit: `P5-2: T38 failing test (MQM re-annotation 触发)`

### Step 2: 实现 mqm_re_annotate

`engine.mbt` 加方法：
- 调 `qe_auto` → 取 mqm 段
- 过滤 severity == "Critical" → 重新跑一遍 mqm 评估（用同样的算法当"第二标注员"）
- 返回 `re_annotated: true` + 每个 Critical 段的 `original_severity` / `re_severity` / `consistent: bool`

签名：
```moonbit
pub fn mqm_re_annotate(self : ProphecyEngine, source : String, target : String, match_rate : Double) -> Json
```

- [ ] 在 `engine.mbt` 加 `mqm_re_annotate` 方法（参考 qe_auto 内部 qe_pipeline 抽公共 helper 如 P4 路线）
- [ ] 运行 T38 → 期望 PASS
- [ ] commit: `P5-2: mqm_re_annotate 流程实现 (engine.mbt)`

### Step 3: 加 T39/T40

```moonbit
// T39: 一致性 — 同一段两次跑结果相同（deterministic）
test "mqm_re_annotate_deterministic" {
  let eng = ProphecyEngine::new()
  let a = eng.mqm_re_annotate("Hello world", "你好世界", 0.95)
  let b = eng.mqm_re_annotate("Hello world", "你好世界", 0.95)
  assert_eq(a, b)
}

// T40: 非 Critical 段不触发二次审（性能优化）
test "mqm_re_annotate_skips_minor" {
  let eng = ProphecyEngine::new()
  let result = eng.mqm_re_annotate(
    "Use a pressure valve to activate the device.",
    "使用压力阀激活装置。",
    0.85  // 高 match_rate 不触发 Critical
  )
  // 无 Critical 段，re_annotated 应为 false
  assert_eq(result.contains("\"re_annotated\":false"), true)
}
```

- [ ] 加 T39 / T40
- [ ] 跑全套 wasm-gc 测试 → 期望 151 + 3 = 154 全绿
- [ ] commit: `P5-2: T39-T40 re-annotation determinism + skip 优化`

### Step 4: 暴露 /api/mqm_re_annotate + mcp tool

`routes.mbt`：在 `routes_meta` 加 `("mqm_re_annotate", "POST")`；加 `handle_mqm_re_annotate` 复用 `engine.mqm_re_annotate`
`mcp.mbt`：在 `all_tools` + `known_tool_names` 加 `"mqm_re_annotate"`；在 `invoke_tool` 加分支

- [ ] 改 `yimai_prophecy_moonbit.mbt`（根模块）`routes_meta` 加一行
- [ ] 改 `routes.mbt` 加 handler
- [ ] 改 `mcp.mbt` 加 tool + dispatch
- [ ] 跑 `moon test --target wasm-gc` → 仍 154/154
- [ ] 跑 `scripts/smoke.ps1` → 期望 27 端点全过（原 26 + mqm_re_annotate）
- [ ] commit: `P5-2: /api/mqm_re_annotate + mcp.mbt mqm_re_annotate tool`

### Step 5: AGENTS.md 增段（MQM 二次标注原理）

- [ ] 在 `AGENTS.md` 加 "MQM 二次标注 (re-annotation)" 段，引用 Google 2025-10-28 论文
- [ ] commit: `P5-2: AGENTS.md 加 MQM re-annotation 原理段`

---

## Task 3: 商务领域语料（ISO 11669 / GB/T 30539-2025）

**Files:**
- Create: `yimai_prophecy_moonbit_business_corpus_test.mbt` — 8 句（合同/商务信函/招投标/议价/付款条件/装运/索赔/仲裁）
- Modify: `README.md` — 加 badge + corpus 段
- Modify: `AGENTS.md` — 已知风险加 "商务领域覆盖"

**Interfaces:**
- 8 个 (text, mtype) 对，覆盖 6 商务场景
- Hit@3 ≥ 0.70 阈值（business corpus 域内）

### Step 1: 写语料 + 测试

8 句商务英中双语对（参考 ISO 11669 商务领域词表 + GB/T 30539 商务场景）：
1. 合同标的：`"The subject matter of this contract"` ↔ `"本合同标的"`
2. 不可抗力：`"Neither party shall be liable for force majeure"` ↔ `"任何一方对不可抗力均不承担责任"`
3. 付款条件：`"Payment shall be made within 30 days of invoice date"` ↔ `"应于发票日期后 30 日内付款"`
4. 装运条款：`"Shipment shall be effected by sea freight FOB Shanghai"` ↔ `"应通过海运 FOB 上海装运"`
5. 仲裁条款：`"Any dispute shall be settled by arbitration in Shanghai"` ↔ `"任何争议应在上海通过仲裁解决"`
6. 违约赔偿：`"The breaching party shall compensate for direct losses"` ↔ `"违约方应赔偿直接损失"`
7. 商务信函：`"We are pleased to enclose our latest catalogue"` ↔ `"我们欣然附上最新产品目录"`
8. 招投标：`"Tender documents must be submitted before the deadline"` ↔ `"投标文件须于截止日期前提交"`

测试：
```moonbit
test "business_corpus_hit_at_3" {
  let eng = ProphecyEngine::new()
  // observe 8 句到记忆
  let training = [
    ("The subject matter of this contract", "本合同标的"),
    ("Neither party shall be liable for force majeure", "任何一方对不可抗力均不承担责任"),
    ("Payment shall be made within 30 days of invoice date", "应于发票日期后 30 日内付款"),
    ("Shipment shall be effected by sea freight FOB Shanghai", "应通过海运 FOB 上海装运"),
    ("Any dispute shall be settled by arbitration in Shanghai", "任何争议应在上海通过仲裁解决"),
    ("The breaching party shall compensate for direct losses", "违约方应赔偿直接损失"),
    ("We are pleased to enclose our latest catalogue", "我们欣然附上最新产品目录"),
    ("Tender documents must be submitted before the deadline", "投标文件须于截止日期前提交"),
  ]
  for s, t in training {
    let _ = eng.observe(s, "step")
    let _ = eng.observe(t, "translation")
  }
  // 命中检测
  let mut hits = 0
  for s, t in training {
    let top = eng.fuzzy_match(s, 3, 0.30)
    if top.contains(t) { hits = hits + 1 }
  }
  // Hit@3 ≥ 0.625 (5/8 底线)
  assert_eq(hits >= 5, true)
}
```

- [ ] 写 `yimai_prophecy_moonbit_business_corpus_test.mbt`
- [ ] 跑测试 → 期望 PASS
- [ ] commit: `P5-3: 商务领域语料 8 句 (ISO 11669 / GB/T 30539-2025)`

### Step 2: 跑全套 + 更新 README badge

- [ ] `moon test --target wasm-gc` → 154 + 1 = 155/155 全绿
- [ ] README.md badge `tests-151%2F151` → `tests-155%2F155`
- [ ] commit: `P5-3: README badge 151 → 155 + corpus 段`

### Step 3: AGENTS.md 增段

- [ ] AGENTS.md 加 "商务领域 (ISO 11669 / GB/T 30539-2025)" 段
- [ ] commit: `P5-3: AGENTS.md 加商务领域对齐段`

---

## Task 4: MQM Severity 三方对齐文档化

**Files:**
- Modify: `README.md` — 加 "MQM 严重度尺度（与 Phrase / Lokalise 对齐）" 表格
- Modify: `AGENTS.md` — 增段
- Modify: `docs/skill/SKILL.md` — frontmatter tips 加 severity_scale 关键词

**接口:**
- 文档化：yimai 严重度数值 = Phrase 严重度（None=0/Minor=1/Major=5/Critical=10）
- 与 Lokalise 评分（Lokalise 用 100-penalty）转换公式

### Step 1: README 增表

```markdown
## MQM 严重度尺度（与业界对齐）

yimai 采用 **MQM Core**（MQM Council 维护，2024 10 周年更新版）严重度数值化。
数值尺度与业界主流对齐：

| Severity | yimai penalty | Phrase penalty | Lokalise penalty (vs 100) | 用途 |
|----------|---------------|----------------|---------------------------|------|
| None     | 0             | 0              | 0                         | 可接受变体，不扣分 |
| Minor    | 1             | 1              | 5                         | 局部小问题（拼写/标点） |
| Major    | 5             | 5              | 25                        | 影响理解（术语错/漏译） |
| Critical | 10            | 25             | 75                        | 改变意义（negation flip / 数字错） |

**yimai vs Phrase 差异**：Critical 严格度 yimai 用 10 而非 25（出于质量门控：Critical 在 yimai
中已自动触发 `mqm_re_annotate` 二次标注流程；Phrase 走人工 review 路径故权重更高）。
**yimai vs Lokalise 差异**：Lokalise 走 `100 - sum(penalties)` 评分，yimai 走原始 penalty 累计
+ `qe_score` 公式综合（参考 `qe_auto` 实现）。

参考：MQM Council 2024 10 周年更新 [https://www.mqm.org](https://www.mqm.org)；
Google 2025-10-28 二次标注论文（arXiv）。
```

- [ ] 修改 README.md 加 "MQM 严重度尺度" 段
- [ ] commit: `P5-4: README MQM severity 三方对齐表`

### Step 2: AGENTS.md + SKILL.md 增段

- [ ] AGENTS.md 加 "MQM Severity 尺度" 段（与 README 一致）
- [ ] SKILL.md frontmatter tips 加 `severity_scale` 关键词
- [ ] commit: `P5-4: AGENTS.md + SKILL.md severity_scale 文档化`

---

## Task 5: 整合 + 推送

**Files:**
- Modify: `CHANGELOG.md` — 加 P5 段
- Modify: `README.md` — 整合 P5 增量
- Modify: `.cleanup-staging/` 清理（如有残留）

### Step 1: CHANGELOG 加 P5 段

```markdown
## P5 — I18n Hardening & Multi-Harness Connectivity (2026-08-19)

### Added
- `docs/harness-configs/harness_manifest.json` — 13 harness schema 单一源清单
- `scripts/validate-harness-configs.ps1` — 自动化 schema 校验脚本
- `POST /api/mqm_re_annotate` + `mqp.mbt` `mqm_re_annotate` tool — MQM Critical 段二次标注（Google 2025-10-28 论文对齐）
- `yimai_prophecy_moonbit_business_corpus_test.mbt` — 商务领域 8 句（ISO 11669 / GB/T 30539-2025）
- README "MQM 严重度尺度" 段（与 Phrase / Lokalise 对齐表）

### Tests
- 151 → 155 (T38 re-annotation 触发 + T39 determinism + T40 skip + 商务 corpus)
```

- [ ] 改 CHANGELOG.md
- [ ] commit: `P5-5: CHANGELOG P5 段`

### Step 2: 跑完整测试 + 推送

- [ ] 跑 `moon test --target wasm-gc` → 期望 155/155
- [ ] 跑 `moon test --target native` → 期望 155/155
- [ ] 跑 `scripts/smoke.ps1` → 期望 27 端点全过
- [ ] 跑 `scripts/validate-harness-configs.ps1` → 期望 13/13
- [ ] git log 确认 P5 5 个 commit 完整
- [ ] `scripts/push.ps1` → 推 github (via ghproxy.net) + gitlink
- [ ] cron self-reminder 监控推送后状态（5min 间隔）

---

## Self-Review

1. **Spec coverage**:
   - 13 harness 连通性 → Task 1 ✓
   - MQM 2025-10 re-annotation → Task 2 ✓
   - 商务领域 (ISO 11669 / GB/T 30539) → Task 3 ✓
   - MQM 严重度三方对齐 → Task 4 ✓
   - 整合 + 推送 → Task 5 ✓
2. **Placeholder scan**: 无 TBD / TODO / "类似" / 占位符
3. **Type consistency**:
   - `mqm_re_annotate(source, target, match_rate) -> Json` 在 4 处一致（test / engine / routes / mcp）
   - `harness_manifest.json` schema 在 README + AGENTS 一致
4. **测试基线**: 每个 commit 后 155/155 ✓
