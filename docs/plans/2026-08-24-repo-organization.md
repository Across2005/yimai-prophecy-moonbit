# 仓库根目录组织说明 (P10 后状态)

> 适用：P10 commit B (796741c) 之后的根目录布局。  
> 关联：AGENTS.md "Project layout" 段、`docs/plans/2026-08-24-p10-round.md`

## 1. 设计原则

**yimai 仓库的根目录布局由三层约束共同决定**：

1. **MoonBit 包模型** — 根 `moon.pkg` 即 `@lib` 包；跨包 import 受限
2. **harness auto-discovery** — IDE 按固定路径扫描 MCP 配置
3. **纯本地零云依赖** — 任何"自动写入根目录"的工具链产物须在 `.gitignore`

## 2. 根目录清单与「留 / 挪 / 屏蔽」决策

### 2.1 源码 (根 lib package — 留)

| 路径 | 状态 | 行数 / 备注 |
|---|---|---:|
| `engine.mbt` | 留 | 590 (P10 后, 原 3619) |
| `engine_index.mbt` | 留 | 226 (P10 新增) |
| `engine_learn.mbt` | 留 | 912 (P10 新增, 单文件最大) |
| `engine_consolidate.mbt` | 留 | 237 (P10 新增) |
| `engine_tm.mbt` | 留 | 456 (P10 新增) |
| `engine_mqm.mbt` | 留 | 501 (P10 新增) |
| `engine_io.mbt` | 留 | 212 (P10 新增) |
| `engine_ops.mbt` | 留 | 518 (P10 新增) |
| `util.mbt` | 留 | 共享 helpers (编码/TF-IDF/对齐/URL 解码) |
| `yimai_prophecy_moonbit.mbt` | 留 | Lib 主入口 |
| `pkg.generated.mbti` | gitignore | `*.mbti` 通配规则 |
| `moon.mod` / `moon.pkg` | 留 | MoonBit 包元数据 |

**为什么不挪到 `src/lib/`** — MoonBit 0.1.20260724 sub-package 互不 import 主包符号;
`@lib.X` 跨测试/服务/main 大量调用, 挪子目录会触发全仓库 import 重写。  
P10 拆分到 8 个文件是 MoonBit 限制下"主题内聚"最优解。

### 2.2 Harness auto-discovery 配置 (留, 必需)

| 路径 | 用途 |
|---|---|
| `.mcp.json` | Claude Code / Gemini CLI / 通用 MCP 客户端扫描 |
| `.cursor/mcp.json` | Cursor (per-project) |
| `.cline/mcp.json` | Cline (per-project, ≥ 3.x) |
| `.roo/mcp.json` | Roo Code (per-project) |
| `.windsurf/mcp.json` | Windsurf / Cascade (per-project) |
| `.codex/config.toml` | OpenAI Codex CLI (≥ 0.21, per-project) |
| `.github/workflows/ci.yml` | GitHub Actions CI (GitHub 自身扫描) |
| `.githooks/pre-commit` | 本地 git hooks (通过 `git config core.hooksPath .githooks` 接入) |
| `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` | harness 入口文件 (各 harness 主动读取) |

**为什么不挪到 `harness-configs/`** — 各 IDE 按仓库根固定路径扫描
(`.cursor/mcp.json` 不能写成 `docs/...`), 挪了就断 auto-discovery。  
13 个 harness 共 6 个项目级配置 (1 文件/目录), 是 MoonBit 限制下另一层不可避免的根目录噪音。

### 2.3 工具链产物 (gitignore 屏蔽)

| 路径 | 屏蔽规则 |
|---|---|
| `_build/` | `moon build` 产物 (gitignore 顶层) |
| `*.mbti` | `moon info` 自动生成 (gitignore 通配) |
| `tm_store.json` | 服务运行时写入 (P1 启动韧性保护) |
| `.moonagent/` / `.mooncakes/` | MoonBit 包管理 (gitignore 顶层) |
| `.qoder/` / `.qoder-cn/` | Qoder IDE 本地工作树 (gitignore) |
| `.mimosa/` | Mimosa 安全扫描本地状态 (gitignore) |
| `target/` | Rust 工具链 (gitignore, 当前未用) |
| `.DS_Store` | macOS Finder (gitignore 顶层) |
| `.git-credentials` | 推送凭据 (gitignore, 推 GitHub 用 Git Credential Manager) |
| `.cleanup-staging/` | mavis-trash 临时目录 (gitignore) |
| `gitlink_root*.png` | gitlink 平台根截图 (gitignore) |
| `AGENTS.md.mcp.json` | 旧版 Codex MCP 占位 (gitignore, 已迁 docs/harness-configs) |
| `ocr-moonbit-rule.json` | qoder 内部规则 (gitignore) |

### 2.4 文档/脚本/测试 (子目录, 已就位)

| 路径 | 内容 |
|---|---|
| `cmd/main/` | demo 二进制 (训练 → Hit@3 → replay → ...) |
| `cmd/service/` | REST + `/mcp` 服务 + web workbench |
| `tests/core/` `tests/corpus/` `tests/feature/` | 3 个 wasm-gc 测试子包 (175 tests) |
| `docs/harness-configs/` | 13 harness 配置样本 + 校验脚本 |
| `docs/plans/` | 项目级 plan / 审计 doc (P6-P10) |
| `docs/roadmap.md` | 路线图 (英文) |
| `docs/skill/SKILL.md` | WorkBuddy 技能编排手册 |
| `scripts/` | setup / build / run / seed / smoke / dev / push / validate |

## 3. P10 前 vs P10 后根目录噪音对比

| 指标 | P9 前 | P10 后 | 变化 |
|---|---:|---:|---|
| `engine.mbt` 行数 | 3619 | 590 | **-84%** |
| 单文件最大行数 | 3619 (engine.mbt) | 912 (engine_learn.mbt) | **-75%** |
| 根目录 `.mbt` 文件数 | 3 (engine/util/ym) | 10 (8 engine*.mbt + util + ym) | +7 (按主题) |
| 根目录总 `*.mbt` 行数 | ~5000 | ~3700 | -26% |
| 根目录 IDE 配置目录 | 7 (.cursor/.cline/...) | 7 (不变, 必需) | 0 |
| 根目录其他文件 | 11 (文档/配置) | 11 (不变) | 0 |

**根目录代码臃肿**主要被 P10 引擎拆分解决 (engine.mbt 84% 缩减);
IDE 配置目录是 harness auto-discovery 的硬约束, **必须保留**。

## 4. 未来可优化方向 (≥ 0.2.0)

1. **`engine_learn.mbt` (912 行) 进一步拆**:
   - `engine_learn_value.mbt` (~150 行) — value_breakdown / _recompute_values
   - `engine_learn_attention.mbt` (~200 行) — set_domain_bias / cl_step / set_attention / mark_term
   - 仍受 MoonBit 同包多文件限制, 拆完后总行数不变, 主题内聚度上升

2. **TMX/XLIFF 暴露到 `/api/*`**: 0.2.0 路线图项, 见 AGENTS.md
3. **TBX3 完整 DCA/DCT 编码支持**: 0.2.0 路线图项
4. **Project Spec 端点 (ISO 11669:2024)**: 0.2.0 路线图项

## 5. 决策记录 (CR)

| 决策 | 原因 | 替代方案 |
|---|---|---|
| 根 lib 留根目录 | MoonBit 0.1.20260724 sub-package 互不 import | 改用其他包模型 (无) |
| IDE 配置目录留根 | 各 IDE 按固定路径扫描 | 文档化安装步骤让用户手动 cp (放弃 zero-copy) |
| `.gitignore` 屏蔽 `*.mbti` | moon info 自动生成, 不入仓 | 入仓但每次 build 跳过 (脏) |
| `tm_store.json` gitignore | 服务运行时写, 用户态无意义 | 强制入仓 (用户协作时冲突) |
| P10 拆 8 个 engine*.mbt (而非 3-4 个) | 单职责, 主题内聚; 最大 912 行, 仍可读 | 拆 3-4 个 (每个 1500+ 行, 失拆分意义) |
