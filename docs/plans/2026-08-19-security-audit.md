 Security Audit 2026-08-19

审计范围：MoonBit 项目 `d:/Agent work/buddy/yimai_prophecy_moonbit`
必审文件：engine.mbt、util.mbt、yimai_prophecy_moonbit.mbt、cmd/service/routes.mbt、cmd/service/mcp.mbt、cmd/service/tm_store.mbt、cmd/service/main.mbt

---

## 1. 关键发现

### 1.1 REST /api/* 请求体在大小检查前完整读取（Critical）

- **位置**：`cmd/service/routes.mbt` 第 197–208 行（`read_json_body`）
- **风险等级**：Critical
- **描述**：`read_json_body` 先调用 `body.read_all()` 把整个请求体读到内存，再 `data.text()` 转字符串，最后才判断 `s.length() > MAX_BODY_BYTES`。攻击者在检查触发前即可上传超大 payload 撑爆内存。
- **影响**：远程单请求即可造成 OOM，导致服务不可用（DoS）。
- **修复建议**：使用带长度上限的读取方式；或在 `read_all()` 前基于 `Content-Length` 等头部预拒绝；也可改用流式 JSON 解析器，确保内存占用与检查前已读字节数解耦。

### 1.2 /mcp 端点缺失请求体大小限制（Critical）

- **位置**：`cmd/service/mcp.mbt` 第 406–432 行（`handle_mcp`）
- **风险等级**：Critical
- **描述**：`/mcp` 分支直接调用 `read_json_body(body)`，没有调用 `read_json_or_400`，因此不享有 `MAX_BODY_BYTES` 保护，超大 JSON-RPC 请求会导致与 REST 端点同样的 OOM 问题。
- **影响**：针对 MCP 端点的远程 OOM / DoS。
- **修复建议**：在 `handle_mcp` 中复用 `read_json_or_400` 或单独做大小校验；同时建议对 JSON-RPC `params` 做深度/字段数限制。

### 1.3 静态文件服务路径穿越防御不完整（High）

- **位置**：`cmd/service/routes.mbt` 第 162–188 行（`serve_static`）
- **风险等级**：High
- **描述**：`serve_static` 对解码后的路径仅检查 `..` 与 `\`，未拒绝绝对路径、前导 `/`、空字节、点号变体（如 `....` 在某些文件系统上的等价处理）以及 Unicode 规范化差异。虽然 `cmd/service/web/` 前缀能阻止部分经典穿越，但防御面不足。
- **影响**：存在越权读取 web 目录外文件或敏感文件的风险（风险程度依赖于底层文件系统路径解析行为）。
- **修复建议**：
  1. 拒绝任何包含空字节、前导 `/` 或绝对路径的 `rel`；
  2. 使用 realpath/canonical 化后确认文件位于 `cmd/service/web/` 之下；
  3. 对 `rel` 做白名单字符校验，仅允许 `[A-Za-z0-9._-]` 等安全字符；
  4. 将 `cmd/service/web/` 提升为常量并统一引用。

### 1.4 WAL 分隔符注入导致状态损坏（High）

- **位置**：`engine.mbt` 第 714、747、2881–2893 行（`wal_append`、`wal_replay`）
- **风险等级**：High
- **描述**：`wal_append` 将用户可控的 `text`/`mtype` 用 `WAL_SEP`（`\u0001`）拼接成日志行；`wal_replay` 再用 `WAL_SEP` 切分。如果 `text` 或 `mtype` 包含 `\u0001`，重放时字段错位，会把恶意文本当作 `op`/`mid`/`mtype` 处理。
- **影响**：持久化状态可被污染，加载 `tm_store.json` 后引擎行为异常，甚至丢失/伪造记忆节点。
- **修复建议**：转义 `WAL_SEP` 或改用结构化格式（如 JSON 数组/对象）存储 WAL 条目；加载时做字段数与 op 白名单校验。

### 1.5 回译对齐/最长公共子序列无输入长度上限（High）

- **位置**：`util.mbt` 第 377–432 行（`align_diff`）；`engine.mbt` 第 3417–3463 行（`back_align`）
- **风险等级**：High
- **描述**：`align_diff` 采用 O(n×m) 动态规划，一次性分配 `(n+1)×(m+1)` 的二维数组。`back_align` 直接对用户传入的 `source`/`target` 调用 `align_diff`，未限制长度。
- **影响**：攻击者发送极长的 `source`/`target`（如各数兆字符）可瞬间耗尽内存，造成 DoS。
- **修复建议**：对 `source`/`target` 总长度或乘积设上限，超过时拒绝或降级为贪心/分块对齐；也可改用滚动数组降低内存，但仍需 CPU 上限。

### 1.6 请求体大小限制按字符数而非字节数（Medium）

- **位置**：`cmd/service/routes.mbt` 第 13–16、203 行（`MAX_BODY_BYTES`、`read_json_body`）
- **风险等级**：Medium
- **描述**：代码注释已承认 `MAX_BODY_BYTES` 实际是字符数。UTF-8 下 CJK 字符约 3 字节，导致实际可接收约 3 MiB 数据，与预期 1 MiB 有偏差。
- **影响**：内存占用高于设计预期，放大 DoS 窗口。
- **修复建议**：在 `read_all()` 之前按字节长度拒绝，或把 `MAX_BODY_BYTES` 下调至约 349K 字符，使字节上限接近 1 MiB；更优方案是 MoonBit 提供字节级 `read`/`take`。

### 1.7 引擎反序列化缺少模式与版本校验（Medium）

- **位置**：`engine.mbt` 第 3136–3217 行（`ProphecyEngine::from_json`）
- **风险等级**：Medium
- **描述**：`from_json` 对任意 JSON 做宽容解析，缺失字段静默使用默认值（0/""）。没有版本号、没有必填字段校验、没有未知字段告警。加载被篡改或跨版本的 `tm_store.json` 后引擎状态可能不一致。
- **影响**：持久化状态损坏、逻辑错误、预测结果异常。
- **修复建议**：在序列化输出中加入 `version` 字段；`from_json` 校验必填字段类型与范围，拒绝未知 top-level 字段；对关键字段（如 `seq`、`clock`）做非负/合理性校验。

### 1.8 启动加载 `tm_store.json` 未限制文件大小（Medium）

- **位置**：`cmd/service/tm_store.mbt` 第 35–50 行（`load_store`）
- **风险等级**：Medium
- **描述**：启动时直接读取并解析整个 `tm_store.json`。若本地存在被恶意放大的文件，会在 `read_file`/`text()`/`json.parse` 阶段耗尽内存。
- **影响**：本地文件可触发启动即 OOM，导致服务无法启动。
- **修复建议**：读取前检查文件大小上限；对 JSON 解析做 try/catch 并降级到空引擎；必要时使用流式解析。

### 1.9 XML/TMX/XLIFF 解析为手写字符串切分，无 schema 校验（Low）

- **位置**：`engine.mbt` 第 2077–2731 行（`load_tbx`、`parse_tmx`、`parse_xliff`）
- **风险等级**：Low
- **描述**：上述函数使用 `split_on`、`first_tag_text`、`lang_attr` 等手写字符串操作解析 XML，未做 schema 校验、实体展开限制和命名空间处理。
- **影响**：恶意 XML 可能导致解析结果异常或 Billion Laughs 类资源消耗（依赖底层字符串重复展开）。
- **修复建议**：限制输入大小；对实体展开和嵌套深度做限制；如有可能迁移到正规 XML 解析库。

### 1.10 `observe`/`remember` 的 `mtype` 可任意赋值（Low）

- **位置**：`engine.mbt` 第 670–753 行（`remember`）、第 1265–1339 行（`observe`）
- **风险等级**：Low
- **描述**：`mtype` 从用户输入透传，未做白名单校验。虽然当前仅作为字符串字段使用，但引擎内部有 `"tm"`/`"term"` 等类型语义，错误类型可能导致统计、索引、持久化行为偏离预期。
- **影响**：状态统计/索引不一致。
- **修复建议**：对 `mtype` 做白名单校验，拒绝未知类型。

---

## 2. 已检查并通过的项

| 检查项 | 结论 | 说明 |
|---|---|---|
| SQL 注入 | 通过 | 无数据库访问，纯内存 Map 结构。 |
| 命令注入 | 通过 | 无 `system`、`exec`、shell 调用。 |
| `unsafe`/原始指针 | 通过 | 未在 `.mbt` 代码中使用 `unsafe` 块或原始指针。 |
| 显式 `panic`/`abort` | 通过 | 生产代码无显式 `panic`/`abort`，仅依赖顶层 try/catch 兜底。 |
| JSON 构造方式 | 通过 | 路由与 MCP 主要使用 `@lib.obj`/`str_json` 等安全 JSON 构造，未使用字符串拼接生成 JSON。 |
| 顶层异常兜底 | 通过 | `handle_request` 与 `handle_mcp` 均有 try/catch，未捕获异常统一返回 500，避免连接悬挂。 |
| 持久化原子写 | 通过 | `save_store` 采用临时文件 + `rename` 实现原子写。 |
| URL 百分号解码前置 | 通过 | `serve_static` 在路径穿越检查前调用 `decode_pct`，可防御 `%2e%2e` 绕过。 |
| 分词器长度兜底 | 通过 | `util.mbt` 中 `yimai_tokenize` 使用 `MAX_TOKENS` 截断。 |
| 上下文窗口 | 通过 | `CTX_WINDOW` 固定为 6，不会无界增长。 |
| 预测缓存上限 | 通过 | `pred_cache` 超过 512 条会清空，避免长跑无界增长。 |
| WAL 自动压缩 | 通过 | `wal_log` 超过 4096 条自动裁剪到 2048 条。 |

---

## 3. 汇总

- **报告文件路径**：`d:/Agent work/buddy/yimai_prophecy_moonbit/docs/plans/2026-08-19-security-audit.md`
- **风险统计**：
  - Critical：2 项
  - High：3 项
  - Medium：3 项
  - Low：2 项
- **已检查并通过**：12 项

### 最需要优先修复的 3 个问题

1. **REST /api/* 请求体在大小检查前完整读取（Critical）**：这是最容易被远程利用的 OOM/DoS 入口，所有 POST 端点均受影响。应在读取前或读取过程中实施字节级上限。
2. **`/mcp` 端点缺失请求体大小限制（Critical）**：MCP 暴露了一个不受大小限制的新入口，攻击者可直接绕过 REST 的大小保护发起超大请求。需要与 REST 统一大小校验。
3. **WAL 分隔符注入导致状态损坏（High）**：持久化数据 integrity 问题，一旦被污染会在重启后持续影响引擎行为；修复成本相对低（转义或结构化 WAL），收益高。
