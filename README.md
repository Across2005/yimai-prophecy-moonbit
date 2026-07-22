# 译脉·先知 2.0 (MoonBit)

> 译脉·先知 2.0「预知记忆网络」引擎的 **MoonBit 零依赖转译版**，与 Python 原版逐项对齐、算法/常量/行为完全一致。

本仓库把 `yimai_prophecy.py`（译脉·先知 2.0 预知记忆网络引擎，Python 零依赖实现）完整转译为 MoonBit 语言项目，可独立编译运行，演示输出与 Python 版可逐项对照（Hit@3、冷启动泛化、固化重放、reward、restore、降级 recall 均一致）。

## 它是什么

译脉·先知是一套**带预测能力的记忆网络**：记住翻译工作流，下一次遇到同类项目时，能**预测下一步需求**并给出可解释路径（白盒）。核心算法（对应原版 D1–D8）：

| 模块 | 算法 | 说明 |
|------|------|------|
| D1 突触图谱 | Hebbian 权重 `w ← w + LR·(1−w)` | 共现即连线，权重衰减 |
| D2 激活扩散 | 多跳扩散 `a·w·decay` | 种子相似节点 → 网络激活召回 |
| D3 前向模型 | 一阶马尔可夫转移 `src→{dst:count}` | 按上下文激活权重累加预测 |
| D4 价值定价 | `V = α·U_past + β·U_pred + γ·C_graph + δ·R − ε·Cost` | β=0.45 主导，预测命中价值最高 |
| D5 情景序列 | episode 记录 | 固化重放用 |
| D6 固化重放 | 剪枝 + 约束契约快照 | 元认知调控探索度，约束契约可回滚 |
| D7 不确定性 | 分布熵 | 输出 confidence / uncertainty |
| D8 概念抽象 | 角色级转移冷启动 | 取文本前 4 字作角色键，跨主题归纳通用规律 |

**确定性设计**：MoonBit 版用 `self.clock`（每次 remember/observe +1）替代 Python 的 `time.time()` 墙钟，保证结果可复现、零依赖；因 `REC_TAU` 远大于训练步数，时效项近似恒 1，与原版行为等价。

## 目录结构

```
yimai_prophecy_moonbit/
├── moon.mod              # 包名 Across2005/yimai_prophecy_moonbit
├── moon.pkg              # lib 包声明
├── util.mbt              # 编码层：停用词 / tokenize / tf_vector / cosine / clamp / r4 + JSON 辅助
├── engine.mbt            # 引擎核心：ProphecyEngine + 全部 D1–D8 方法 + 序列化
├── cmd/
│   └── main/
│       ├── moon.pkg      # 可执行包（is-main），导入 lib + json + math
│       └── main.mbt      # 演示与验证入口（移植 Python __main__）
└── README.md
```

算法常量（权重/阈值）集中在 `engine.mbt` 顶部 `const`，与 Python 原版逐项一致。

## 构建与运行

需要 MoonBit 工具链（`moon`，v0.1.2026+）：

```bash
# 构建
moon build

# 运行演示（训练 → Hit@3 → 复盘预测 → D8 冷启动 → 固化重放 → reward → restore → 降级）
moon run cmd/main
```

预期关键输出（与 Python 版一致）：

- `hit rate ≈ 0.825`（Hit@3 预测命中率）
- 已知项目复盘：`observe 项目名` → Top-1 预测「提取核心术语表并锁定」
- 冷启动泛化：从未见过的「量子计算综述」项目名 → 仍泛化预测「提取核心术语表并锁定」，路径含 `m14(role)` 角色级补位（D8）
- 固化重放 `pruned=0`、reward 后预测价值上升、restore 回滚成功、单节点降级 recall 有结果

## 与 Python 原版对应关系

| Python | MoonBit | 备注 |
|--------|---------|------|
| `ProphecyEngine` 类 | `pub struct ProphecyEngine` | 字段同构，`clock` 替代墙钟 |
| `remember / observe / predict / recall` | 同名 `pub fn` 方法 | 行为一致 |
| `consolidate / restore / reward / explain` | 同名方法 | 一致 |
| `_role(text)` | `role_of(text)` | 取前 4 字 |
| `tf_vector / cosine / tokenize` | `util.mbt` 同名函数 | 纯函数层 |
| `time.time()` 时效 | `self.clock` 逻辑时钟 | 确定性等价 |

> 转译要点：MoonBit 结构体字段默认不可变（需 `mut`）；`const` 跨文件可见且须大写，但仅支持不可变原语类型（数组用顶层 `let`）；`Map` 的 `.set/.push` 原地修改对所有副本共享；数学用 `@math.exp/pow/ln`，`.sqrt()` 为方法；`for` 循环用 C 式或 `for x in iter`，不支持 `0..N` 区间写法；数组 `.size()` 已弃用改用 `.length()`。

## 许可证

见 `LICENSE`（与 Python 原版一致）。
