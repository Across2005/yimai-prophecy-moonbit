# Agent 接入指南（译脉·先知 2.0 / MoonBit）

本压缩包把一个**零第三方依赖、可确定性复现**的"预知型翻译记忆引擎"
（Prophecy Memory Network, PMN）交付给其它 Agent 接入使用。

> 重要前提（MoonBit 0.1.20260713 工具链约束，已查证）：
> - 本机 **无 stdin / 无文件 I/O**；
> - `js` 目标只为 `is-main` 包生成立即执行的 IIFE，**不导出函数**给宿主语言（Node/Python）直接调用。
> 因此"接入"不是进程内函数调用，而是下面两种方式之一。

---

## 接入方式 A：构建运行（Agent 具备 MoonBit 工具链）

```bash
# 1) 安装 MoonBit 工具链：https://www.moonbitlang.com  (moon 0.1.20260713+)
# 2) 进入本目录
cd yimai_prophecy_moonbit

# 3) 验收（含真实翻译场景 + 抽象量化，全绿即代表引擎可用）
moon test --target wasm-gc

# 4) 跑 Python 原版对照演示（is-main 入口）
cd cmd/main && moon build --target wasm-gc && moon run .
```

Agent 可在自己的 MoonBit 工程中 `moon add Across2005/yimai_prophecy_moonbit`，
直接调用 `ProphecyEngine` 的 16 个公开方法（make/remember/observe/recall/predict/
consolidate/restore/reward/explain/end_episode/hit_rate/stats_view/context_texts/
last_context_id/to_json/from_json）。

## 接入方式 B：算法移植（Agent 不具备 MoonBit，但需内嵌能力）

`engine.mbt` 为**纯标准库实现、零依赖、零 I/O**，算法与 Python 原版逐项对齐，
可直接阅读后移植到 Python / TypeScript / Go 等宿主语言；
常量（HEBB_LR、EDGE_DECAY、BETA 等）与 D1–D8 模块一一对应，移植成本低。
这是当前"跨语言 Agent 装载"最可行的路径。

---

## 压缩包内容

```
yimai-prophecy-moonbit/
├── engine.mbt                      # 引擎实现（PMN，零依赖，D1–D8）
├── util.mbt                        # 向量/分词/JSON 辅助
├── yimai_prophecy_moonbit.mbt      # 包入口（占位/转发）
├── moon.pkg / moon.mod             # 包定义
├── README.md                       # 功能与使用文档（moon_elk 范式）
├── README.mbt.md                   # MoonBit 包元数据说明
├── AGENTS.md                       # Agent 协作约定
├── CODE_REVIEW.md                  # 代码审查记录
├── LICENSE                         # Apache-2.0
├── cmd/main/main.mbt               # is-main 演示（Python 原版对照）
├── yimai_prophecy_moonbit_test.mbt            # 既有黑盒测试
├── yimai_prophecy_moonbit_accept_test.mbt     # 抽象量化验收（Layer1/Layer2）
├── yimai_prophecy_moonbit_scenario_test.mbt   # 真实双语场景模拟验收
├── ACCEPTANCE_REPORT.md            # 量化验收报告
└── EVALUATION_REPORT.md            # 真实翻译内容评价报告
```
（`_build/`、`.git/`、`_archive/` 已排除在压缩包外。）

---

## 给接入 Agent 的定位建议

引擎最擅长的是**带预测能力的翻译记忆（Predictive TM）**：
- **召回（recall）**：给定新源文片段，按语义召回**具体双语术语/例句**——保持术语与风格一致的核心能力；
- **预测（predict）**：对已建模的工作流步骤精准预测下一步；对自由源文段落则回退到流程锚点（详见 EVALUATION_REPORT.md §4.2）。

建议接入时把本引擎定位为「翻译记忆 + 流程提示」组件，而非「自由文本续写」组件。
