# 译脉·先知 2.0 (MoonBit)

> 一套**带预测能力的记忆网络**——让本地智能体记住工作流，并在遇到同类任务时**预测下一步需求**、给出可白盒解释的路径。这是「译脉·先知 2.0 预知记忆网络」引擎的 MoonBit 零依赖实现。

[![Tests](https://img.shields.io/badge/tests-26%2F26%20passing-brightgreen)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![Hit@3](https://img.shields.io/badge/Hit%403-0.8246-brightgreen)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.2026-9cf)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

---

## Table of Contents

- [Features](#features)
- [How it works (D1–D8)](#how-it-works-d1d8)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Real-world scenario: predictive translation memory](#real-world-scenario-predictive-translation-memory)
- [Domain usage cases (10 domains × 5 rounds, verified)](#domain-usage-cases-10-domains--5-rounds-verified)
- [API Reference](#api-reference)
- [Data Formats](#data-formats)
- [Evaluation & Test Results](#evaluation--test-results)
- [Semantic notes & known limitations](#semantic-notes--known-limitations)
- [Project structure](#project-structure)
- [For Agents / Integration](#for-agents--integration)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgements](#acknowledgements)

---

## Features

- **Predictive memory network** — remembers workflows and predicts the most likely next step before the user asks.
- **White-box explainability** — every prediction/explain returns the concrete node/edge/transition path, never a black box.
- **Semantic recall** — given a new source sentence, activates a spreading network to recall the *exact* bilingual terms/sentences that keep terminology consistent.
- **Cold-start generalization** — role-level abstraction (D8) induces domain-independent process skeletons, so an unseen project still gets a sensible next step.
- **Deterministic & reproducible** — a logical clock replaces wall-clock time; identical call sequences yield byte-identical `to_json` output (no RNG).
- **Zero third-party dependencies** — pure MoonBit core (`json` + `math` only); nothing to install beyond the `moon` toolchain.
- **Serializable** — full engine state exports/imports as JSON for persistence and cross-session restore.

---

## How it works (D1–D8)

The engine is a neuro-inspired memory network. Eight modules map directly to constants in `engine.mbt`:

| Module | Algorithm | What it does |
|--------|-----------|--------------|
| **D1 Synaptic graph** | Hebbian `w ← w + LR·(1−w)` | Co-occurrence creates edges; weights decay over time. |
| **D2 Activation spread** | Multi-hop `a·w·decay` | Seed node → activate similar nodes → recall by spreading. |
| **D3 Forward model** | 1st-order Markov `src→{dst:count}` | Predict next step by accumulating context-weighted transitions. |
| **D4 Value pricing** | `V = α·U_past + β·U_pred + γ·C_graph + δ·R − ε·Cost` | β=0.45 dominates — predicted-hit value ranks highest. |
| **D5 Episode sequence** | episode log | Records sequences for consolidation replay. |
| **D6 Consolidation** | prune + constraint-contract snapshot | Meta-cognitive `explore` control; contract roll-back via `restore`. |
| **D7 Uncertainty** | distribution entropy | Emits `confidence` / `uncertainty`. |
| **D8 Concept abstraction** | role-level transitions (cold-start) | First-4-chars role key induces cross-topic rules. |

**Why deterministic:** a `self.clock` (incremented on every `remember`/`observe`) substitutes wall-clock time, so results are reproducible and dependency-free. Because `REC_TAU` ≫ training steps, the recency term is ≈ 1.

---

## Installation

As a MoonBit library, add the dependency:

```bash
moon add Across2005/yimai_prophecy_moonbit
```

Then declare the import in your package's `moon.pkg` (recommended alias `@lib`):

```moonbit
import {
  "Across2005/yimai_prophecy_moonbit" @lib,
  "moonbitlang/core/json" @json,
}
```

> Requires the MoonBit toolchain (`moon`, v0.1.2026+).

---

## Quick Start

A copy-paste minimal example: train a short workflow, then predict the next need.

```moonbit
pub fn quickstart() -> Unit {
  let mut eng = @lib.ProphecyEngine::make()

  // 1) observe() records real steps in order; the engine maintains a
  //    context window and a 1st-order Markov transition model internally.
  let _ = eng.observe("解析源文件结构", "step")
  let _ = eng.observe("提取核心术语表并锁定", "step")
  let _ = eng.observe("生成双语对照草稿", "step")

  // 2) predict Top-3 most likely next steps from current context.
  let pred = eng.predict(3)
  println(@json.stringify(pred))
  // => {"predictions":[{"id":"m4","text":"...","prob":0.6x,"path":[...]}],
  //      "confidence":0.6x,"uncertainty":0.4x}

  // 3) recall: given a query, return related memories (with activation + path).
  let hits = eng.recall("术语", 5)
  println(@json.stringify(hits))

  // 4) persist & restore.
  let snap = eng.to_json()
  let eng2 = @lib.ProphecyEngine::from_json(snap)
  let _ = eng2
}
```

> `observe(text, mtype)` builds edges/transitions from the current context window and advances the logical clock. To control co-occurrence manually, call `remember(text, mtype, ctx)` with an explicit `ctx` array.

Build & run the bundled demo:

```bash
moon build
moon run cmd/main     # training → Hit@3 → replay prediction → D8 cold-start → consolidate → reward → restore
```

---

## Real-world scenario: predictive translation memory

The engine is designed as a **Predictive Translation Memory (Predictive TM)**. Below is a verbatim transcript from `yimai_prophecy_moonbit_scenario_test.mbt` (real bilingual corpus — new-energy-vehicle whitepaper + medical-device manual), so you can see the *actual translated content* the engine handles.

**Scenario 1 — new source sentence arrives (recall of exact bilingual terms):**

```
================ 真实场景模拟 · 新能源汽车白皮书 ================
● 新到来源文(待译): 请翻译：该车的快充功率可达 150 kW，支持 800 V 高压平台。
● 引擎预测下一步 Top1: 【项目】新建翻译项目：新能源汽车白皮书
● 引擎召回的相关历史翻译记忆(前 3 条):
    1. 【接收】请翻译：该车的快充功率可达 150 kW，支持 800 V 高压平台。
    2. 【术语】电池管理系统 → Battery Management System (BMS)
    3. 【例句】该车型采用液冷电池包以提升热安全性。→ The model adopts a liquid-cooled battery pack to improve thermal safety.
● 预测可白盒解释(含真实关联路径): true
```

**Scenario 4 — second domain, independent corpus (medical device):**

```
========== 第二领域 · 医疗器械说明书 ==========
● 新到来源文(待译): 请翻译：导管需在灭菌后密封，并标注生物相容性等级。
● 引擎预测下一步 Top1: 【项目】新建翻译项目：医疗器械说明书
● 引擎召回(前 3 条):
    1. 【接收】请翻译：导管需在灭菌后密封，并标注生物相容性等级。
    2. 【术语】生物相容性 → biocompatibility
    3. 【术语】灭菌 → sterilization
```

The full four-scenario transcript (incl. term-consistency and cross-domain cold-start) lives in [`EVALUATION_REPORT.md`](./EVALUATION_REPORT.md).

### What it's good at — and what to manage expectations on

| Behavior | Reality |
|----------|---------|
| **Recall** of exact bilingual terms/sentences | ✅ Excellent. This is the core TM value. |
| **Prediction** of a *modelled workflow step* | ✅ Accurate (see replay test in Evaluation). |
| **Prediction** on a *free-form new source paragraph* | ⚠️ Falls back to the highest-value "project anchor" node. Engine is a workflow predictor, **not** a free-text continuation model. |
| **Explainability** | ✅ White-box paths on every `explain`. |
| **Cross-domain generalization** | ✅ Role abstraction (D8) induces the domain-independent skeleton. |

> **Positioning:** integrate it as a *"translation memory + next-step hint"* component, not as a *"free-text writer"*.

---

## Domain usage cases (10 domains × 5 rounds, verified)

Beyond the two everyday corpora above, the engine was driven through **ten domains** — five frontier hard-tech fields plus five humanities & life-science fields — each trained for **5 rounds** on a real bilingual glossary + example corpus, then probed for recall / next-step prediction / cold-start / white-box explanation. All transcripts below are verbatim output of `moon test --target wasm-gc` (`yimai_prophecy_moonbit_domain_demo_test.mbt`) and are fully reproducible.

The ten domains and their sourced terminology (Chinese ⇄ English):

| # | Domain | Sample terms (verified bilingual) |
|---|--------|-----------------------------------|
| 1 | **AI large models** | 大语言模型 → large language model (LLM); 推理 → inference; 智能体 → AI agent |
| 2 | **Quantum technology** | 量子比特 → qubit; 量子纠缠 → quantum entanglement; 量子密钥分发 → quantum key distribution (QKD) |
| 3 | **New energy & storage** | 固态电池 → solid-state battery; 长时储能 → long-duration energy storage (LDES) |
| 4 | **Biopharma & gene tech** | 信使RNA疫苗 → mRNA vaccine; 腺相关病毒 → adeno-associated virus (AAV) |
| 5 | **Deep-space & aerospace** | 深空光通信 → deep space optical communication (DSOC); 星间链路 → inter-satellite link (ISL); 航天器测控 → spacecraft tracking, telemetry and control (TT&C) |
| 6 | **Literary theory** | 叙事学 → narratology; 意识流 → stream of consciousness; 自由间接引语 → free indirect discourse; 陌生化 → defamiliarization |
| 7 | **Philosophy** | 现象学 → phenomenology; 认识论 → epistemology; 本体论 → ontology; 目的论 → teleology |
| 8 | **Medicine** | 循证医学 → evidence-based medicine (EBM); 发病机制 → pathogenesis; 预后 → prognosis; 随机对照试验 → randomized controlled trial (RCT) |
| 9 | **Psychology** | 认知失调 → cognitive dissonance; 工作记忆 → working memory; 大五人格特质 → Big Five personality traits; 正念 → mindfulness |
| 10 | **Neuroscience** | 神经可塑性 → neuroplasticity; 突触 → synapse; 神经递质 → neurotransmitter; 默认模式网络 → default mode network (DMN) |

> Terminology cross-checked against authoritative sources — ISO/IEC 4879 quantum vocabulary, NIST PQC, CCSDS TT&C, NASA DSOC (hard-tech); Genette/Shklovsky narratology, Husserl phenomenology, evidence-based-medicine clinical usage, Festinger/APA/DSM-5 psychology, Britannica/Hebbian neuroscience (humanities & life-science) — not invented.

**Every domain converges to the same deterministic metrics after 5 rounds** — `节点(nodes)=18  边(edges)=222  Hit@3=0.7867` — confirming the engine's behaviour is corpus-shape-driven and reproducible across all ten subjects, independent of subject matter (hard-tech or humanities).

**Domain 1 — AI large models (verbatim):**

```
===== DOMAIN DEMO: 人工智能大模型 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】文中需统一大语言模型的推理与对齐表述
· score=0.3 | 【术语】大语言模型 → large language model (LLM)
· score=0.3 | 【术语】推理 → inference
● 预测下一步(复盘已知项目: 大语言模型安全白皮书):
· p=0.4386 | 【项目】大语言模型安全白皮书 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】智能体 → AI agent | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：大语言模型安全白皮书 | path=[['m15', 0]]
● 冷启动预测(未见项目: 多模态智能体编排规范):
· p=0.4073 | 【项目】多模态智能体编排规范 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】智能体 → AI agent | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】大语言模型安全白皮书 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 2 — Quantum technology (verbatim):**

```
===== DOMAIN DEMO: 量子科技 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】段落需说明量子比特的纠缠与退相干
· score=0.3 | 【术语】量子比特 → qubit
· score=0.3 | 【术语】量子纠缠 → quantum entanglement
● 预测下一步(复盘已知项目: 量子优越性验证报告):
· p=0.4386 | 【项目】量子优越性验证报告 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】量子密钥分发 → quantum key distribution (QKD) | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：量子优越性验证报告 | path=[['m15', 0]]
● 冷启动预测(未见项目: 量子密钥分发网络白皮书):
· p=0.4073 | 【项目】量子密钥分发网络白皮书 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】量子密钥分发 → quantum key distribution (QKD) | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】量子优越性验证报告 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 3 — New energy & storage (verbatim):**

```
===== DOMAIN DEMO: 新能源与储能 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】文中需统一固态电池与长时储能的表述
· score=0.3 | 【术语】固态电池 → solid-state battery
· score=0.3 | 【例句】全固态电池以固态电解质替代液态电解质。→ The all-solid-state battery replaces liquid electrolyte with a solid electrolyte.
● 预测下一步(复盘已知项目: 全固态电池技术白皮书):
· p=0.4386 | 【项目】全固态电池技术白皮书 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】长时储能 → long-duration energy storage (LDES) | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：全固态电池技术白皮书 | path=[['m15', 0]]
● 冷启动预测(未见项目: 钠离子电池储能电站可研报告):
· p=0.4073 | 【项目】钠离子电池储能电站可研报告 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】长时储能 → long-duration energy storage (LDES) | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】全固态电池技术白皮书 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 4 — Biopharma & gene tech (verbatim):**

```
===== DOMAIN DEMO: 生物医药与基因技术 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】段落需说明 mRNA 疫苗与脂质纳米颗粒递送
· score=0.3 | 【例句】该 mRNA 疫苗由脂质纳米颗粒递送。→ The mRNA vaccine is delivered by a lipid nanoparticle.
· score=0.3 | 【术语】信使RNA疫苗 → mRNA vaccine
● 预测下一步(复盘已知项目: mRNA 疫苗技术审评报告):
· p=0.4386 | 【项目】mRNA 疫苗技术审评报告 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】腺相关病毒 → adeno-associated virus (AAV) | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：mRNA 疫苗技术审评报告 | path=[['m15', 0]]
● 冷启动预测(未见项目: AAV 基因治疗临床方案):
· p=0.4073 | 【项目】AAV 基因治疗临床方案 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】腺相关病毒 → adeno-associated virus (AAV) | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】mRNA 疫苗技术审评报告 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 5 — Deep-space & aerospace (verbatim):**

```
===== DOMAIN DEMO: 深空探测与航天 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】文中需统一深空光通信与星间链路的表述
· score=0.3 | 【术语】深空光通信 → deep space optical communication (DSOC)
· score=0.3 | 【术语】星间链路 → inter-satellite link (ISL)
● 预测下一步(复盘已知项目: 深空光通信工程总体设计):
· p=0.4386 | 【项目】深空光通信工程总体设计 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】航天器测控 → spacecraft tracking, telemetry and control (TT&C) | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：深空光通信工程总体设计 | path=[['m15', 0]]
● 冷启动预测(未见项目: 可重复使用火箭回收手册):
· p=0.4073 | 【项目】可重复使用火箭回收手册 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】航天器测控 → spacecraft tracking, telemetry and control (TT&C) | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】深空光通信工程总体设计 | path=[['m16', 0]]
● 白盒解释(术语节点 m3): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 6 — Literary theory (verbatim):**

```
===== DOMAIN DEMO: 文学理论 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】文中需统一意识流与自由间接引语的译法
· score=0.3 | 【术语】自由间接引语 → free indirect discourse
· score=0.3 | 【术语】意识流 → stream of consciousness
● 预测下一步(复盘已知项目: 西方叙事学导论):
· p=0.4386 | 【项目】西方叙事学导论 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】自由间接引语 → free indirect discourse | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：西方叙事学导论 | path=[['m15', 0]]
● 冷启动预测(未见项目: 后现代元小说研究文集):
· p=0.4073 | 【项目】后现代元小说研究文集 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】自由间接引语 → free indirect discourse | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】西方叙事学导论 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 7 — Philosophy (verbatim):**

```
===== DOMAIN DEMO: 哲学 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】段落需统一现象学与认识论的表述
· score=0.3 | 【术语】现象学 → phenomenology
· score=0.3 | 【术语】认识论 → epistemology
● 预测下一步(复盘已知项目: 现象学基本问题):
· p=0.4386 | 【项目】现象学基本问题 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】目的论 → teleology | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：现象学基本问题 | path=[['m15', 0]]
● 冷启动预测(未见项目: 分析哲学中的心灵与意识):
· p=0.4073 | 【项目】分析哲学中的心灵与意识 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】目的论 → teleology | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】现象学基本问题 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 8 — Medicine (verbatim):**

```
===== DOMAIN DEMO: 医学 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】文中需统一循证医学与随机对照试验的译法
· score=0.3 | 【术语】随机对照试验 → randomized controlled trial (RCT)
· score=0.3 | 【例句】该结论基于多项随机对照试验的证据。→ The conclusion is based on evidence from multiple randomized controlled trials.
● 预测下一步(复盘已知项目: 循证医学临床指南):
· p=0.4386 | 【项目】循证医学临床指南 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】随机对照试验 → randomized controlled trial (RCT) | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：循证医学临床指南 | path=[['m15', 0]]
● 冷启动预测(未见项目: 罕见病诊疗专家共识):
· p=0.4073 | 【项目】罕见病诊疗专家共识 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】随机对照试验 → randomized controlled trial (RCT) | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】循证医学临床指南 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 9 — Psychology (verbatim):**

```
===== DOMAIN DEMO: 心理学 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】段落需统一认知失调与工作记忆的译法
· score=0.3 | 【术语】认知失调 → cognitive dissonance
· score=0.3 | 【术语】工作记忆 → working memory
● 预测下一步(复盘已知项目: 认知心理学导论):
· p=0.4386 | 【项目】认知心理学导论 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】正念 → mindfulness | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：认知心理学导论 | path=[['m15', 0]]
● 冷启动预测(未见项目: 积极心理学与幸福感研究):
· p=0.4073 | 【项目】积极心理学与幸福感研究 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】正念 → mindfulness | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】认知心理学导论 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Domain 10 — Neuroscience (verbatim):**

```
===== DOMAIN DEMO: 神经科学 (5 rounds) =====
● 召回(前沿术语, top-3):
· score=0.3 | 【接收】文中需统一神经可塑性与突触的译法
· score=0.3 | 【术语】神经可塑性 → neuroplasticity
· score=0.3 | 【例句】神经可塑性使大脑能重组突触连接。→ Neuroplasticity enables the brain to reorganize its synaptic connections.
● 预测下一步(复盘已知项目: 神经可塑性研究综述):
· p=0.4386 | 【项目】神经可塑性研究综述 | path=[['m16', 0], ['m16(role)', 0]]
· p=0.2105 | 【术语】默认模式网络 → default mode network (DMN) | path=[['m17(role)', 0]]
· p=0.1497 | 【项目】新建翻译项目：神经可塑性研究综述 | path=[['m15', 0]]
● 冷启动预测(未见项目: 脑机接口与神经解码手册):
· p=0.4073 | 【项目】脑机接口与神经解码手册 | path=[['m16(role)', 0], ['m17', 0], ['m17(role)', 0], ['m18(role)', 0]]
· p=0.2718 | 【术语】默认模式网络 → default mode network (DMN) | path=[['m17(role)', 0], ['m18(role)', 0]]
· p=0.1711 | 【项目】神经可塑性研究综述 | path=[['m16', 0]]
● 白盒解释(术语节点 m2): 预测价值=0 命中率=0.2667 出边数=15
● 收敛: 节点=18 边=222 Hit@3=0.7867
```

**Reading the transcript:**

- **召回 (recall)** — given a new source sentence, the engine spreads activation and returns the *exact* bilingual terms/examples it has stored, keeping terminology consistent across the domain.
- **预测下一步 (next-step prediction)** — replaying a *known* project name, the engine predicts the highest-value next workflow step with a white-box `path`.
- **冷启动 (cold-start)** — for an *unseen* project in the same domain, D8 role-abstraction still induces the domain-independent skeleton and a sensible next step.
- **白盒解释 (explain)** — a glossary node's predictive value / hit-rate / out-edge count is queryable; glossary terms are *recall facts* (hit-rate 0.2667) rather than *next-step drivers*, which is expected and honest.

Reproduce:

```bash
cd yimai_prophecy_moonbit
moon test --target wasm-gc      # runs the 10-domain demo among all 26 tests
```

---

## API Reference

All public interfaces are methods of `ProphecyEngine` (encoding helpers in `util.mbt` are package-private).

| Method | Signature | Description |
|--------|-----------|-------------|
| `make` | `() -> ProphecyEngine` | Create an empty engine. |
| `remember` | `(text, mtype, ctx : Array[String]) -> String` | Write/dedupe a memory node, build co-occurrence synapse, return node id. |
| `observe` | `(text, mtype) -> String` | Record a real next step: remember + update transition + hit accounting + advance context. |
| `predict` | `(k : Int) -> Json` | Predict Top-K next steps from context window; returns prob/path/confidence/uncertainty. |
| `recall` | `(query : String, k : Int) -> Array[Json]` | Activation-spread associative recall; returns memory + activation + path. |
| `consolidate` | `(prune : Bool) -> Json` | Consolidation replay: decay, recompute value, optional prune, meta-cognitive `explore`. |
| `restore` | `() -> Json` | Roll back to the pre-consolidation snapshot (constraint contract). |
| `reward` | `(mid, score : Double) -> Bool` | Success/failure feedback into predictive value. |
| `explain` | `(mid : String) -> Json` | White-box explanation of a node's edges/transitions/hit-rate. |
| `end_episode` | `() -> Unit` | End the current episode sequence. |
| `hit_rate` | `() -> Double` | Cumulative prediction hit rate. |
| `stats_view` | `() -> Json` | Node/edge/episode counts, type distribution, avg predictive value. |
| `context_texts` | `() -> Array[String]` | Texts in the current context window. |
| `last_context_id` | `() -> String` | Last node id in the context window. |
| `to_json` | `() -> Json` | Export full engine state (persistence). |
| `from_json` | `(data : Json) -> ProphecyEngine` | Restore engine state from JSON. |

---

## Data Formats

### Engine persistence (`to_json` / `from_json`)

```json
{
  "memories": {
    "m1": { "id":"m1","text":"解析源文件结构","type":"step",
            "vec":{"解析":1,"源":1},"created":1,"last_used":3,
            "use_count":2,"feedback":0,"edges":{"m2":0.30},
            "predictive_value":0.42,"hit_count":1,"predict_count":1 }
  },
  "transitions": { "m1": {"m2":1.0} },
  "episodes": [["m1","m2","m3"]],
  "context": ["m1","m2","m3"],
  "stats": { "preds":1, "hits":1, "remembers":3, "evolutions":0 },
  "seq": 3, "explore": 0.0, "clock": 3, "meta_hits": [1],
  "snapshot": {}, "role_trans": {}, "role_index": {}
}
```

### `predict(k)` returns

```json
{
  "predictions": [
    { "id":"m4", "text":"生成双语对照草稿", "prob":0.62,
      "path": [ { "from":"m3", "p":0.55 } ] }
  ],
  "confidence": 0.62,
  "uncertainty": 0.41
}
```

### `recall(query, k)` returns (array)

```json
[
  { "id":"m2", "text":"提取核心术语表并锁定", "type":"step",
    "score":0.71, "activation":1.0, "via_edges": [ { "to":"m1", "w":0.30 } ] }
]
```

### `consolidate(prune)` returns

```json
{ "pruned": 0, "nodes": 3, "edges": 2, "explore": 0.0, "recent_hit_rate": 0.5 }
```

---

## Evaluation & Test Results

All numbers below are produced by `moon test --target wasm-gc` and are reproducible.

**Summary: `Total tests: 26, passed: 26, failed: 0`** (4 quantitative acceptance + 4 real-world scenarios + 10 domain demos + 4 pre-existing black-box + 4 supporting).

| Layer | Check | Result | Evidence |
|-------|-------|--------|----------|
| L1 | Batch Hit@3 > 0.8 | ✅ | `hit_rate = 0.8246` over 8 topics × 8 rounds |
| L1 | Determinism / reproducibility | ✅ | Two `to_json` calls are **byte-identical** |
| L1 | JSON round-trip | ✅ | `to_json → from_json → to_json` identical |
| L1 | Consolidation keeps core memory | ✅ | 13 nodes → 13 nodes after consolidate |
| L2 | Known-project replay predicts correct next | ✅ | observe `新建翻译项目：新能源汽车白皮书` → Top1 `提取核心术语表并锁定` |
| L2 | Cold-start generalization | ✅ | unseen topic `量子计算综述` → D8 role-abstraction yields `提取核心术语表并锁定` |
| L2 | White-box explainable | ✅ | `explain(m2)` returns concrete edge/transition paths |
| L2 | Persistence after restart | ✅ | `to_json → from_json` Top1 unchanged |
| RW | Exact bilingual recall on real corpus | ✅ | see [Real-world scenario](#real-world-scenario-predictive-translation-memory) |
| RW | Cross-domain (medical) generalization | ✅ | precise recall of `biocompatibility` / `sterilization` |
| DD | 10 domains × 5 rounds converge identically | ✅ | each domain → `nodes=18 edges=222 Hit@3=0.7867` (see [Domain usage cases](#domain-usage-cases-10-domains--5-rounds-verified)) |

Detailed evidence:
- Quantitative acceptance (Layer1/Layer2): [`ACCEPTANCE_REPORT.md`](./ACCEPTANCE_REPORT.md)
- Concrete translation-content evaluation (4 scenarios): [`EVALUATION_REPORT.md`](./EVALUATION_REPORT.md)

Reproduce:

```bash
cd yimai_prophecy_moonbit
moon test --target wasm-gc      # all 26 tests, incl. real-world scenarios + 10 domain demos
moon build --target wasm-gc     # library only
cd cmd/main && moon build --target wasm-gc && moon run .
```

---

## Semantic notes & known limitations

- **Logical clock:** `self.clock` increments on each `remember`/`observe` (not wall-clock). The `clock` field in exported JSON is a logical step count — same call sequence ⇒ same result.
- **Recency ≈ 1:** `REC_TAU = 604800` ≫ normal training steps, so `exp(-dt/TAU)` ≈ 1; freshness barely decays at typical scale.
- **Recall degradation:** when memory nodes `< MIN_GRAPH(4)`, `recall` falls back to pure cosine Top-K (no spreading network).
- **Prediction depends on the context window:** `predict` sums transitions over the last `CTX_WINDOW(6)` node ids. Cold-start (empty context / no specific transition) is back-filled by D8 role-level rules.
- **State accumulates:** engine state changes continuously with `remember`/`observe`. For a clean start, call `make()` again or `restore()` from a snapshot.
- **Predict fallback on free-form text:** as noted above, a brand-new source paragraph (no matching modelled step) makes `predict` return the highest-value anchor node. This is by design, not a defect — see [Real-world scenario](#real-world-scenario-predictive-translation-memory).

---

## Project structure

```
yimai_prophecy_moonbit/
├── moon.mod              # package name Across2005/yimai_prophecy_moonbit
├── moon.pkg              # lib package declaration
├── util.mbt              # encoding layer: stopwords / tokenize / tf_vector / cosine / clamp / r4 + JSON helpers (internal)
├── engine.mbt            # engine core: ProphecyEngine + D1–D8 + serialization
├── yimai_prophecy_moonbit.mbt  # package entry (placeholder)
├── cmd/
│   └── main/
│       ├── moon.pkg      # executable (is-main); imports lib + json + math
│       └── main.mbt      # demo & verification entry
├── yimai_prophecy_moonbit_test.mbt          # pre-existing black-box tests
├── yimai_prophecy_moonbit_accept_test.mbt   # quantitative acceptance (Layer1/Layer2)
├── yimai_prophecy_moonbit_scenario_test.mbt # real bilingual scenario tests
├── yimai_prophecy_moonbit_domain_demo_test.mbt # 10-domain × 5-round demos
├── README.md
├── ACCEPTANCE_REPORT.md  # quantitative acceptance evidence
├── EVALUATION_REPORT.md  # concrete translation-content evaluation
├── AGENT_INTEGRATION.md  # how another agent plugs this in
├── LICENSE               # MIT
└── AGENTS.md
```

Algorithm constants (weights/thresholds) live in the `const` block at the top of `engine.mbt`.

---

## For Agents / Integration

This package delivers a **zero-dependency, deterministic** "Prophecy Memory Network" to other agents. Because the current MoonBit toolchain (v0.1.2026) has **no stdin / no file I/O** and the `js` target emits only an immediately-invoked IIFE for `is-main` (it does not export functions to a host language), "integration" is one of two paths:

**Path A — build & run (agent has the MoonBit toolchain):**

```bash
cd yimai_prophecy_moonbit
moon test --target wasm-gc        # green ⇒ engine is usable
cd cmd/main && moon build --target wasm-gc && moon run .
```

Then `moon add Across2005/yimai_prophecy_moonbit` and call any of the 16 `ProphecyEngine` methods.

**Path B — algorithm port (agent has no MoonBit but needs the capability in-process):**

`engine.mbt` is pure-stdlib, zero-I/O, with constants (`HEBB_LR`, `EDGE_DECAY`, `BETA`, …) that map 1:1 to D1–D8. It ports cheaply to Python / TypeScript / Go by reading the source. This is currently the most practical route for cross-language agent loading.

Full guidance: [`AGENT_INTEGRATION.md`](./AGENT_INTEGRATION.md).

---

## Contributing

Issues and pull requests are welcome. The repo ships three test suites — please keep `moon test --target wasm-gc` green when you submit a change. For behavioural/evaluation changes, extend `yimai_prophecy_moonbit_scenario_test.mbt` with real bilingual corpus so the concrete-content evaluation stays honest.

---

## License

MIT — see [`LICENSE`](./LICENSE).

---

## Acknowledgements

- Built on the [MoonBit](https://www.moonbitlang.com) language and its `core` (`json`, `math`) packages.
- README structure follows conventions of high-star open-source projects (e.g. `sharkdp/bat`, `BurntSushi/ripgrep`) and the idiomatic MoonBit library style of [`moonbit-community/moon_elk`](https://github.com/moonbit-community/moon_elk).
