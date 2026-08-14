# 译脉·先知 2.0 (MoonBit)

> 一套**带预测能力的记忆网络**——让本地智能体记住工作流，并在遇到同类任务时**预测下一步需求**、给出可白盒解释的路径。这是「译脉·先知 2.0 预知记忆网络」引擎的 MoonBit **零依赖**实现（仅 `core/json` + `core/math`）。
>
> 在「预测记忆」内核之外，已落地 **#22 翻译记忆（TM）/ 术语库（TB）一等公民**：真正的 fuzzy match（含匹配率%）、concordance 检索、TBX 术语库强制对齐与一致性校验——让引擎从「只预测」走向「预测 + 检索 + 术语守门」。

[![Tests](https://img.shields.io/badge/tests-101%2F101%20passing-brightgreen)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![Hit@3](https://img.shields.io/badge/Hit%403-0.8246-brightgreen)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![Modern Corpus](https://img.shields.io/badge/modern_corpus-22%2F22%20passing-brightgreen)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![Service API](https://img.shields.io/badge/HTTP%20API-24%20endpoints%20%2B%20MCP-9cf)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.2026-9cf)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

---

## Table of Contents

- [Features](#features)
- [How it works (D1–D8)](#how-it-works-d1d8)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Modern Corpus Evaluation (2025–2026)](#modern-corpus-evaluation-20252026)
- [Service Layer — 纯 MoonBit HTTP API (cmd/service)](#service-layer--纯-moonbit-http-api-cmdservice)
- [API Reference](#api-reference)
- [#22 TM/TB — Translation Memory & TermBase](#22-tmtb--translation-memory--termbase)
- [Data Formats](#data-formats)
- [Evaluation & Test Results](#evaluation--test-results)
- [Roadmap & Extension Status](#roadmap--extension-status)
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
- **Fast inference (快)** — role inverted-index (`role_members`) + per-source Top-8 pruning keep the hot path off full-graph scans; a `pred_cache` (fully invalidated on any engine change, not LRU) short-circuits repeated `(context, k)` queries.
- **Accurate (准)** — second-order Markov (`trans2`, `P(w3|w1,w2)` blended at `λ=0.4`), multi-granularity role keys (前二/前四/前后各二), elastic forgetting (recency-aware edge decay), adaptive Hebbian LR, per-domain bias `ΔW` (LoRA-style), online contrastive learning (`cl_step`), and attention-gated edge weights in recall.
- **Explainable & bilingual (美)** — `TermNode` (`mark_term`) boosts terminology recall with a +5.0 activation and a "term hit" flag; `explain_card` returns a white-box `activation_path` / `prediction_path` / `value_breakdown` JSON; `align_diff` gives a character-level LCS edit script for bilingual alignment.
- **TM / TermBase (检索 + 守门)** — `#22` 新增 `add_tm` / `fuzzy_match` / `concordance` / `load_tbx` / `enforce_terms` / `check_terms`：真正的 fuzzy match（匹配率 %）、concordance 检索、`TBX(ISO 30042)` 术语库解析、术语强制对齐与一致性校验（见 [§#22](#22-tmtb--translation-memory--termbase)）。
- **Incremental & collaborative (中/长周期)** — Write-Ahead Log (`wal_*`) for event-sourced replay, active-learning candidates by uncertainty + diversity, and federated increment export/import (`fed_*`) for cross-agent coordination.
- **Pure-MoonBit service layer (纯 MoonBit 全栈)** — `cmd/service` 起本地 HTTP server（`127.0.0.1:8787`），**24 个 `/api/*` 端点 + `/mcp` MCP Server**（13 基础 + retrieve_prompt / bleu / chrf / style_check / style_report / back_align / term_conflicts / fed_export / fed_import / distill_inject / active_learning）全部实测通过，含 BLEU/chrF++ 评测、风格检查、回译对齐、术语冲突、TMPlm、联邦/蒸馏注入、主动学习推荐；TM 状态经 fs **原子写持久化**（tmp+rename），重启恢复闭环——**引擎到服务零桥接语言**。

---

## How it works (D1–D8)

The engine is a neuro-inspired memory network. Eight modules map directly to constants in `engine.mbt`:

| Module | Algorithm | What it does |
|--------|-----------|--------------|
| **D1 Synaptic graph** | Hebbian `w ← w + LR·(1−w)` | Co-occurrence creates edges; weights decay over time. |
| **D2 Activation spread** | Multi-hop `a·w·decay` | Seed node → activate similar nodes → recall by spreading. |
| **D3 Forward model** | 1st-order + 2nd-order Markov `src→{dst}` / `(w1,w2)→{w3}` | Predict next step by blending context-weighted 1st-order transitions with `λ·P(w3\|w1,w2)` (second-order). |
| **D4 Value pricing** | `V = α·U_past + β·U_pred + γ·C_graph + δ·R − ε·Cost` | β=0.45 dominates — predicted-hit value ranks highest. |
| **D5 Episode sequence** | episode log | Records sequences for consolidation replay. |
| **D6 Consolidation** | prune + constraint-contract snapshot | Meta-cognitive `explore` control; contract roll-back via `restore`. |
| **D7 Uncertainty** | distribution entropy | Emits `confidence` / `uncertainty`. |
| **D8 Concept abstraction** | multi-granularity role transitions (cold-start) | 前二 / 前四 / 前后各二 role keys induce cross-topic rules. |

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

### Out-of-the-box setup (Windows, AI agents welcome)

Clone the repo, then run the one-shot dev workflow (checks env → builds the native
service → starts it on `127.0.0.1:8787` → seeds sample TM pairs → smoke-tests
all 13 endpoints + MCP):

```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev.ps1
```

Or step by step: `scripts/setup.ps1` (env check) → `build.ps1` (compile, needs MSVC) →
`run.ps1` (start) → `seed.ps1` (sample data) → `smoke.ps1` (verify).

> **确定性回归门禁（纯本地，零云端依赖）**: `scripts/dev.ps1` 在构建前自动运行
> `moon test --target wasm-gc`（101/101 契约回归），任何一项失败即中止。
> 此外，仓库自带本地 `pre-commit` hook（`.githooks/pre-commit`，`moon check` +
> `moon test --target wasm-gc`），已通过 `git config core.hooksPath .githooks`
> 接入本仓库——每个 commit 前自动挡住破坏确定性契约的改动。

> **Windows native prerequisites**: `cmd/service` requires **MSVC** (`link.native.cc`
> in `cmd/service/moon.pkg` and `cmd/main/moon.pkg` points at `cl.exe` — update both if
> the path differs on your machine); after a MoonBit toolchain upgrade, rebuild the core
> native bundle once (`cd ~/.moon/lib/core && moon clean --target-dir _build/native &&
> moon bundle --target native --release`). AI agents: see [`AGENTS.md`](./AGENTS.md) for
> the full out-of-the-box guide.

---

## Quick Start

A copy-paste minimal example: train a short workflow, then predict the next need — and (with `#22`) manage a translation memory + termbase.

```moonbit
pub fn quickstart() -> Unit {
  let mut eng = @lib.ProphecyEngine::make()

  // 1) observe() records real steps in order; the engine maintains a
  //    context window and a 1st/2nd-order Markov transition model internally.
  let _ = eng.observe("解析源文件结构", "step")
  let _ = eng.observe("提取核心术语表并锁定", "step")
  let _ = eng.observe("生成双语对照草稿", "step")

  // 2) predict Top-3 most likely next steps from current context.
  let pred = eng.predict(3)
  println(@json.stringify(pred))

  // 3) recall: given a query, return related memories (with activation + path).
  let hits = eng.recall("术语", 5)
  println(@json.stringify(hits))

  // 4) persist & restore.
  let snap = eng.to_json()
  let eng2 = @lib.ProphecyEngine::from_json(snap)
  let _ = eng2

  // 5) #22 — TM / TermBase: add memory, load a TBX glossary, align & verify.
  let _ = eng.add_tm("电池包热管理策略", "Battery pack thermal management strategy")
  let tbx =
    "<martif><text><body>" +
    "<termEntry id=\"1\"><langSet xml:lang=\"en-US\"><ntig><termGrp><term>sensor</term></termGrp></ntig></langSet>" +
    "<langSet xml:lang=\"zh-CN\"><ntig><termGrp><term>传感器</term></termGrp></ntig></langSet></termEntry>" +
    "</body></text></martif>"
  let _ = eng.load_tbx(tbx)
  let tmx = eng.fuzzy_match("电池包热管理", 3, 0.70)   // Top-K with match_pct
  let v  = eng.check_terms("install the sensor", "安装设备")  // 1 violation (漏译 传感器)
  println(@json.stringify(tmx))
  println(@json.stringify(v))
}
```

> `observe(text, mtype)` builds edges/transitions from the current context window and advances the logical clock. To control co-occurrence manually, call `remember(text, mtype, ctx)` with an explicit `ctx` array.

Build & run the bundled demo:

```bash
moon build
moon run cmd/main     # training → Hit@3 → replay prediction → D8 cold-start → consolidate → reward → restore
```

### Start the HTTP service (pure MoonBit, `cmd/service`)

```bash
moon build cmd/service --target native && moon run cmd/service --target native
# 译脉引擎服务: http://127.0.0.1:8787
```

Then smoke-test the API (Windows native build requires MSVC — see [Service Layer](#service-layer--纯-moonbit-http-api-cmdservice)):

```bash
curl -X POST localhost:8787/api/add_tm        -d '{"src":"电池包热管理策略","tgt":"Battery pack thermal management strategy"}'
curl -X POST localhost:8787/api/fuzzy_match   -d '{"query":"电池包热管理方案","k":3,"threshold":0.5}'
curl -X POST localhost:8787/api/check_terms   -d '{"source":"install the sensor","target":"安装设备"}'
curl -X POST localhost:8787/api/qe_auto       -d '{"source":"a","target":"b","match_rate":0.8}'
curl -X POST localhost:8787/api/predict       -d '{"k":3}'
```

---

## Modern Corpus Evaluation (2025–2026)

The engine is evaluated end-to-end on a **cutting-edge, purely English corpus** spanning **8 modern domains** sourced from real 2025–2026 research trends. All transcripts are fully reproducible via `moon test --target wasm-gc --filter Layer*` (`yimai_prophecy_moonbit_modern_corpus_test.mbt`).

### Corpus domains

| # | Domain | Sample training content |
|---|--------|------------------------|
| 1 | **AI Safety & Alignment** | RLHF reward hacking audits, red-teaming frontier models against CBRN knowledge, mechanistic interpretability of superposition in SAE features |
| 2 | **Climate Modeling & Carbon Capture** | CMIP7 AR7 scenario SSP5-8.5 projection, direct air capture with solid amine sorbents, enhanced weathering of olivine for ocean alkalinity enhancement |
| 3 | **Quantum Computing & Error Correction** | Surface code logical error rates at 10⁻⁶ physical error threshold, cat qubit bias-preserving gates with autonomous stabilization, LDPC code benchmarks on IBM ibm_sherbrooke vs Google Willow |
| 4 | **CRISPR & Gene Therapy** | CRISPR-Cas12a multiplexed genome editing with AI-designed gRNA libraries, PCSK9 base editing for durable LDL cholesterol reduction, AAV9 capsid engineering for blood-brain barrier crossing |
| 5 | **Cybersecurity & Zero Trust** | NIST SP 800-207 Zero Trust Architecture deployment, post-quantum TLS 1.3 hybrid key exchange with Kyber-1024 + X25519, AI-driven SOC automation with graph neural network anomaly detection |
| 6 | **Neuroscience & Brain-Computer Interfaces** | High-density 1024-channel ECoG grid for speech decoding, latent diffusion models reconstructing perceived natural images from 7T fMRI BOLD signals |
| 7 | **Distributed Systems & Cloud Native** | Multi-region Spanner-style TrueTime with bounded clock uncertainty, service mesh mTLS with SPIFFE identities, disaggregated memory pooling over CXL 3.0 fabrics |
| 8 | **NLP & Large Language Models** | Llama-4-Maverick MOE routing with 128 experts + top-8 gating, RLAIF vs RLHF head-to-head on MT-Bench and AlpacaEval 2.0, retrieval-augmented generation with late interaction ColBERTv2 |

### Evaluation results — 11 tests, all passing

**Layer 0: Workflow prediction (8 domains × 6 steps × 5 rounds = 240 observations)**

| Domain | Predicted Project | Hit@3 |
|--------|------------------|-------|
| AI Safety | Project: AI Safety Technical Report Q4 2025 | ✅ |
| Climate Modeling | Project: Global Carbon Budget Analysis 2026 | ✅ |
| Quantum Computing | Project: Surface Code Error Correction Benchmark | ✅ |
| CRISPR & Gene Therapy | Project: CRISPR-Cas12a Off-Target Analysis Pipeline | ✅ |
| Cybersecurity | Project: Zero Trust Architecture Security Audit | ✅ |
| Neuroscience & BCI | Project: High-Density ECoG Neural Decoding Pipeline | ✅ |
| Distributed Systems | Project: Multi-Region Eventual Consistency Benchmark | ✅ |
| NLP & LLMs | Project: Multilingual LLM Evaluation Suite v3 | ✅ |

> **Engine-wide Hit@3 = 0.7773**. All 8/8 domains produce valid, domain-specific workflow predictions.

**Layer 1: TM fuzzy match (multi-granularity white-box scoring)**

Cross-domain TM recall consistently activates relevant memories:
- `fuzzy_match("RAG chunking vector store optimization")` → hits AI/NLP entries with sim_token / sim_tfidf / sim_char / sim_ngram / sim_tokenset breakdowns
- `fuzzy_match("CRISPR knockout of PCSK9 gene")` → hits CRISPR domain entries
- `fuzzy_match("neural decoding of brain signals")` → hits neuroscience content via semantic overlap (threshold 0.15)

**Layer 2: Term enforcement & TBX glossary**

Loads 8 bilingual term entries from TBX format (`en-US` ↔ `zh-CN`), enforces term consistency on input text, and checks source-target alignment — covering retrieval-augmented generation, low-rank adaptation, surface code, enhanced weathering, guide RNA, zero trust, ECoG, and linearizability.

**Layer 3: Cross-domain semantic recall**

Multi-domain recall activates the *correct* domains for mixed queries:
- `"LLM safety benchmarking"` → activates AI Safety + NLP domains
- `"gene editing + neural decoding"` → activates CRISPR + Neuroscience domains
- `"quantum + distributed consensus"` → activates Quantum Computing + Distributed Systems domains

**Layer 4: Cold-start generalization**

Unseen domains like *Zero-Day Threat Intelligence Report* and *Perovskite Solar Cell Efficiency Roadmap* correctly trigger D8 role abstraction to predict a sensible next step — confirming the engine generalizes beyond its training distribution.

**Layer 5: Deep fuzzy match with white-box scoring**

Cross-domain queries receive multi-granularity similarity breakdowns (token / TF-IDF / char / n-gram / token-set), while orthogonal queries (e.g., "Aristotle" against a technical corpus) correctly return zero results.

**Layer 6: Deterministic serialization & JSON round-trip**

Two independent engine instances with identical training produce byte-identical `to_json()` output; `to_json → from_json → to_json` round-trips are verified; prediction consistency across serialization boundaries is confirmed.

**Layer 7: Consolidation, metrics & WAL event sourcing**

Post-consolidation state is verified: nodes / edges pruning works correctly, WAL log and replay clone produce valid entries, and metrics report memories count and Hit@3 with expected values.

**Layer 8: White-box explainability**

`explain_card` returns rich JSON with `activation_path` (source→target node chain), `prediction_path` (step-to-step transitions), and `value_breakdown` (α·U + β·U_pred + γ·C_graph + δ·R − ε·Cost decomposition).

**Layer 9: Attention-gated recall & domain bias modulation**

Attention gating (α=0.3, β=0.2) + domain bias (+0.15 on quantum role) shifts recall ranking toward the preferred domain while preserving cross-domain awareness.

**Layer 10: Active learning, federated export/import & distillation**

Active learning candidates ranked by uncertainty + diversity; federated export produces increment diff; domain bias distilled at +0.25 for targeted roles; federated import merges external memory increments.

### Summary

| Metric | Value |
|--------|-------|
| Total modern corpus tests | 11/11 passing |
| Domains covered | 8 (AI safety, climate, quantum, CRISPR, cybersecurity, neuroscience, distributed systems, NLP) |
| Training observations | 240 |
| Engine Hit@3 | 0.7773 |
| Post-consolidation nodes/edges | 48/534 |
| Cold-start generalization | ✅ Unseen domains produce valid predictions |
| Determinism | ✅ Byte-identical serialization, round-trip verified |
| White-box explainability | ✅ activation_path + prediction_path + value_breakdown |
| WAL event sourcing | ✅ Replay integrity confirmed |

---

## Extended Corpus Evaluation — 6 New Frontier Domains

Beyond the 8 original domains, the engine is additionally validated on **6 emerging research domains** sourced from 2025–2026 breakthroughs. All transcripts in `yimai_prophecy_moonbit_extended_corpus_test.mbt`.

### Additional domains

| # | Domain | Sample training content |
|---|--------|------------------------|
| 1 | **Robotics & Embodied AI** | Diffusion policy for dexterous manipulation with visuotactile feedback, sim-to-real transfer of quadruped locomotion via domain randomization |
| 2 | **Fusion Energy & Plasma Physics** | SPARC tokamak Q>1 breakeven experiments, stellarator coil optimization with adjoint methods |
| 3 | **Synthetic Biology & Metabolic Engineering** | Cell-free biosynthesis of taxol precursors, CRISPRi logic gates for genetic circuit design |
| 4 | **Protein Design & Drug Discovery** | RFdiffusion backbone generation + ProteinMPNN sequence design, PROTAC ternary complex prediction with AlphaFold3 |
| 5 | **Battery Technology & Solid-State Electrolytes** | LLZO garnet-type solid electrolyte ionic conductivity tuning, lithium metal anode dendrite suppression with ALD coatings |
| 6 | **Space Tech & Satellite Constellations** | Starlink V2 laser inter-satellite link mesh routing, lunar surface habitat construction with regolith 3D printing |

### Evaluation results — 11 tests, all passing

Tests span the same Layer 0–10 framework, covering workflow prediction, TM fuzzy match across robotics and fusion pairs, extended TBX glossary enforcement (6 new terms), cross-domain recall, cold-start generalization, deterministic serialization, consolidation/WAL, explainability, attention-gated recall, and active learning/federated export/distillation.

---

## Service Layer — 纯 MoonBit HTTP API (cmd/service)

`cmd/service` 是**纯 MoonBit 双层架构的 Layer 2**：用 `moonbitlang/async`（http / fs / socket）起本地 HTTP server，把引擎能力以 REST API 暴露给前端工作台 / Agent / LLM 宿主。**引擎到服务零桥接语言**——同一门 MoonBit 完成全部。

### 架构演进：旧架构 vs 新架构

本项目从「纯库」演进为「三层架构」。差异如下：

| 维度 | 旧架构（v1） | 新架构（v2，当前） |
|---|---|---|
| **总体形态** | 单一纯库（零依赖内核）+ `cmd/main` demo | **三层**：Layer0 零依赖内核 / Layer2 纯 MoonBit 服务层 / Layer1 知识层（文档 + 前端工作台已实现） |
| **I/O 能力** | 无 stdin / 无文件 I/O（wasm-gc 内存态） | `async/fs` **原子写持久化**（`tm_store.json`，tmp+rename）+ 重启恢复闭环 |
| **对外接口** | 仅 MoonBit 函数调用（`moon add` 后进程内调用） | **24 个 HTTP REST 端点**，前端 / Agent / LLM 宿主可直接消费 |
| **集成路径** | 2 条：库引用、算法移植 | **4 条**：A 构建运行 / B wasm-gc exports / **C HTTP 服务（新增，已实测）** / D 算法移植 |
| **运行形态** | wasm-gc 内存态（测试友好） | native（Windows 需 MSVC）本地常驻服务，`127.0.0.1:8787` |
| **语言栈** | 单一 MoonBit（仅库） | 单一 MoonBit（库 + HTTP 服务 + 文件 I/O）——**引擎到服务零桥接语言** |
| **状态持有** | 调用方自管引擎实例 | `Ref[ProphecyEngine]` 服务内单例 + JSON 边界透出 |

> **演进动机**：旧架构的引擎能力只能被「会 MoonBit 的程序」消费；新架构让任何会 HTTP 的宿主（浏览器前端、Agent 工具调用、LLM 函数调用）都能用上确定性记忆引擎——**内核零依赖铁律不变**，只是多了一层纯 MoonBit 的 I/O 壳。

### 端点矩阵（24 个，全部 curl 实测通过）

| 端点 | 方法 | 请求体 | 响应 | 说明 |
|---|---|---|---|---|
| `/api/ping` | GET | — | `{"status":"ok"}` | 健康检查 |
| `/api/add_tm` | POST | `{"src","tgt"}` | `{"id","status"}` | 新增 TM，原子落盘 |
| `/api/fuzzy_match` | POST | `{"query","k","threshold"}` | Top-K（S1 四分量白盒） | TM 模糊检索 |
| `/api/check_terms` | POST | `{"source","target"}` | 违规数组 | 术语一致性校验 |
| `/api/concordance` | POST | `{"term","k"}` | 含术语 TM 段 | 术语上下文检索 |
| `/api/qe_auto` | POST | `{"source","target","match_rate"}` | `{"qe_score","term_ok","mqm"}` | 自动 QE 评分 |
| `/api/predict` | POST | `{"k"}` | `{"predictions","confidence","uncertainty"}` | 下一步预测 + 白盒 |
| `/api/observe` | POST | `{"text","mtype"}` | `{"mid","status"}` | 记录真实步骤（学习/转移）→ 落盘 |
| `/api/recall` | POST | `{"query","k"}` | `Array[{id,text,score,via_edges}]` | 激活扩散语义召回 |
| `/api/explain` | POST | `{"mid"}` | 白盒卡片 | `value_breakdown` / `activation_path` 证据链 |
| `/api/reward` | POST | `{"mid","score"}` | `{"ok"}` | **采纳/拒绝反馈 → predictive_value（闭环核心）** |
| `/api/consolidate` | POST | `{"prune"}` | `{pruned,nodes,edges,...}` | 固化重放（价值重算 + 剪枝） |
| `/api/retrieve_prompt` | POST | `{"query","k","threshold"}` | 三段式 | **TMPlm**：suggestions/terms/glossary 供 LLM prompt 注入 |
| `/api/bleu` / `/api/chrf` | POST | `{"ref","hyp"}` | `{bleu}` / `{chrf}` | MT 质量评测（零依赖自实现） |
| `/api/style_check` | POST | `{"text"}` | 问题数组 | 风格一致性（句长/标点/括号/术语命中） |
| `/api/style_report` | POST | `{"text"?}` | `{sentence_count,avg_src_len,avg_tgt_len,formal_score,distribution,term_variants,tips}` | **风格一致报告**（记忆库分布 + 术语变体族 + 新译文偏离建议） |
| `/api/back_align` | POST | `{"source","target"}` | `{align_score,misaligns,ops}` | 回译 LCS 对齐（含字符级 ops 供热力图） |
| `/api/term_conflicts` | POST | — | 冲突数组 | 一词多译 / 多词一译 |
| `/api/fed_export` / `/api/fed_import` | POST | `{"added","updated"}` | `{status}` | 联邦增量导出/导入（FedAvg 端点层） |
| `/api/distill_inject` | POST | `{"table":{k:v}}` | `{status,keys}` | 蒸馏偏置表注入 |
| `/api/active_learning` | POST | `{"k"}` | `Array[{id,text,uncertainty,role}]` | **主动学习推荐**（uncertainty+diversity 待标注句） |
| `/api/tm_count` | GET | — | `{"tm_count"}` | 存量统计 |

**实测**（中文 query，白盒分项全透出）：

```json
POST /api/fuzzy_match  {"query":"电池包热管理方案","k":3,"threshold":0.5}
→ [{"id":"m3","source":"电池包温度管理方案","target":"Battery pack temperature management plan",
    "score":0.7377,"match_pct":73.7723,"sim_token":0.7125,"sim_tfidf":0.6796,
    "sim_char":0.7778,"sim_ngram":0.6667,"sim_tokenset":0.75}, ...]
```

### 三层关联与记忆闭环

24 个端点不是孤立的——它们把三层连成**记忆闭环**（完整映射表见架构方案 §11）：

```
前端操作 ──HTTP──▶ Layer2 服务端点 ──调用──▶ Layer0 引擎方法
   ▲                                              │
   │                                              ▼
   └─── JSON 响应（白盒分数/证据链）◀── save_store() 原子落盘 ◀┘
                                │
                                ▼
                  重启 load_store() → from_json() → 记忆不丢
```

两个闭环（实测）：
- **采纳闭环**：前端「采纳译文」→ `/api/reward{mid,+1}` → `predictive_value` 提升 → 下次 `/api/predict` 排序更优；
- **学习闭环**：前端「记录步骤」→ `/api/observe{text}` → 转移计数 → 落盘 → 重启恢复 → 预测更准（实测：observe 两步 → predict Top1 prob=1.0）。

### MCP Server（/mcp 端点）—— 供 Claude Desktop / 通用 MCP 客户端消费

`cmd/service` 同时暴露 **MCP（Model Context Protocol）Server 变体**（spec **2025-11-25**，Streamable HTTP）：挂 `/mcp` 端点，POST 单 JSON-RPC 消息、`application/json` 响应（无需 SSE）。**24 个引擎能力直接映射为 MCP tools**：

| MCP tool | 参数 | 说明 |
|---|---|---|
| `fuzzy_match` | query / k / threshold | TM 模糊检索（S1 四分量白盒） |
| `add_tm` | src / tgt | 新增 TM 并落盘 |
| `check_terms` | source / target | 术语一致性校验 |
| `concordance` | term / k | 术语上下文检索 |
| `qe_auto` | source / target / match_rate | 自动 QE 评分 |
| `predict` | k | 下一步预测 + 白盒路径 |
| `observe` | text / mtype | 记录步骤（学习）并落盘 |
| `recall` | query / k | 语义召回 |
| `explain` | mid | 白盒卡片 |
| `reward` | mid / score | 采纳/拒绝反馈 |
| `consolidate` | prune | 固化重放 |
| `tm_count` / `ping` | — | 存量 / 健康检查 |
| `retrieve_prompt` | query / k / threshold | TMPlm：为 LLM prompt 组装三段式检索上下文（suggestions/terms/glossary） |
| `bleu` / `chrf` | ref / hyp | MT 质量评测（零依赖自实现） |
| `style_check` | text | 风格一致性（句长/标点/括号/术语命中） |
| `style_report` | text? | **风格一致报告**：记忆库句长/正式度分布 + 术语变体族 + 新译文偏离建议 |
| `back_align` | source / target | 回译 LCS 对齐验证 |
| `term_conflicts` | — | 术语冲突检测（一词多译/多词一译） |
| `fed_export` / `fed_import` | added / updated | 联邦增量导出/导入 |
| `distill_inject` | table | 蒸馏偏置表注入 |
| `active_learning` | k | **主动学习推荐**：uncertainty×0.6+novelty×0.4，角色去重，待标注句 |

```bash
# MCP 握手（curl 模拟客户端）
curl -X POST localhost:8787/mcp -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
curl -X POST localhost:8787/mcp -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
curl -X POST localhost:8787/mcp -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fuzzy_match","arguments":{"query":"电池","k":2}}}'
```

> 协议：`initialize`（protocolVersion 2025-11-25 + capabilities.tools）/ `notifications/initialized`（202）/ `tools/list`（24 tools，inputSchema JSON Schema 2020-12）/ `tools/call`（未知工具 `-32602`，引擎异常 `isError:true`）；GET /mcp 回 405。实现为自建轻量 JSON-RPC 2.0 层（`cmd/service/mcp.mbt`，MoonBit 无现成 MCP 库），全程复用引擎 `@lib.obj/str_json/num_json` 构造（Json 为 FFI 类型）。

### 持久化

- 引擎状态经 `to_json()` → `@fs.write_file(tmp, create_mode=CreateOrTruncate)` → `rename` **原子落盘**到 `tm_store.json`；
- 重启时 `load_store()` → `from_json()` 完整恢复（实测 tm_count 持久化后重启一致）；
- 单例持有：`engine_ref : @ref.Ref[@lib.ProphecyEngine]`（MoonBit 顶层无全局可变变量，`Ref` 是标准方案）。

### 平台要求（Windows）

- async 的 native 后端**硬性要求 MSVC**（`thread_pool.c: #error "Currently only MSVC is supported on Windows"`），mingw gcc 不可用；wasm/js 后端暂不支持 socket server；
- 构建需 MSVC 环境（INCLUDE/LIB）+ `moon.pkg` 配置 `link.native.cc` 指向 `cl.exe`；
- 工具链升级后需重建 core native bundle（`cd ~/.moon/lib/core && moon clean --target-dir _build/native && moon bundle --target native --release`）。

---

## API Reference

All public interfaces are methods of `ProphecyEngine` (encoding helpers in `util.mbt` are package-private).

### Core (D1–D8, persistence, feedback)

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

### Learning & explanation (准·美)

| Method | Signature | Description |
|--------|-----------|-------------|
| `set_domain_bias` | `(role, delta : Double) -> Unit` | Inject/accumulate per-domain bias `ΔW` (LoRA-style). |
| `inject_distillation` | `(table : Map[String, Double]) -> Unit` | Inject read-only distilled bias table (neural-symbolic distillation, consume-side). |
| `cl_step` | `(anchor, positive, negative : String) -> Unit` | Online contrastive learning: strengthen (anchor,pos), suppress (anchor,neg). |
| `set_attention` | `(alpha, beta : Double) -> Unit` | Toggle attention-gated edge weights in recall (default off). |
| `mark_term` | `(mid : String) -> Bool` | Mark a node as terminology (TermNode): boost recall + flag for explain card. |
| `explain_card` | `(mid : String) -> Json` | White-box explainable card: activation/prediction paths + value breakdown. |

### Incremental & collaborative (中/长周期)

| Method | Signature | Description |
|--------|-----------|-------------|
| `active_learning_candidates` | `(k : Int) -> Array[Json]` | Top-K uncertain + role-diverse nodes for human labeling. |
| `wal_replay` | `() -> ProphecyEngine` | Rebuild engine from the Write-Ahead Log (event sourcing). |
| `wal_export` / `wal_compact` / `wal_clear` / `wal_len` | `(…) -> Array[String] / Unit / Int` | WAL inspection & maintenance. |
| `fed_export` / `fed_import` | `() -> Json` / `(added, updated : Int) -> Unit` | Federated increment counter export/import (coordinator merges weights). |

### #22 TM/TB (检索 + 术语守门)

| Method | Signature | Description |
|--------|-----------|-------------|
| `add_tm` | `(src, tgt : String) -> String` | Add a translation-memory entry (source→target), build the TF index, return the node id. |
| `fuzzy_match` | `(query : String, k : Int, threshold : Double) -> Json` | TM fuzzy match Top-K. **S1 升级评分** = `0.55·idf_dice + 0.20·char-2gram-dice + 0.15·token-set-dice + 0.10·position`（IDF 加权让罕见术语优先、2-gram 捕捉形态变体、token-set Dice 容忍词序重排）；returns `match_pct` / `sim_token` / `sim_tfidf` / `sim_char` / `sim_ngram` / `sim_tokenset`. (建议阈值 `threshold = 0.70`；MoonBit 无默认参数，调用方需显式传入。) |
| `fuzzy_match_legacy` | `(query : String, k : Int, threshold : Double) -> Json` | 旧公式保留（`0.7·token-cosine + 0.3·char-ratio`），供 A/B 对照与平滑迁移（S1 前行为）。 |
| `concordance` | `(term : String, k : Int) -> Json` | Concordance search: returns all TM segments containing the query term, scored by term occurrence count (distinct from the `fuzzy_match` similarity score). |
| `load_tbx` | `(xml : String, src_lang~ : String = "en-US", tgt_lang~ : String = "zh-CN") -> Int` | Parse a TBX (ISO 30042) termbase. Resolves source/target by each `langSet`'s `xml:lang` (default en-US→zh-CN; falls back to document order when absent). Returns the number of concept entries loaded. |
| `enforce_terms` | `(text : String) -> Json` | Term enforcement: scan text for known terms (Latin terms require word boundaries, so `log` won't false-match `logical`), return hits with translation. |
| `check_terms` | `(source, target : String) -> Json` | Term-consistency check: for each source term whose translation is missing from the target, return a violation. |

---

## #22 TM/TB — Translation Memory & TermBase

This extension makes translation memory and terminology **first-class citizens** alongside the predictive core. It reuses the existing `yimai_tokenize` / `tf_vector` / `cosine` / `align_diff` / `clamp01` primitives — no new dependencies, no re-invented wheel.

- **`add_tm(src, tgt)`** builds a `MemoryNode` of `mtype="tm"` carrying `text=source`, `translation=target` (and maintains the TM document-frequency index for IDF).
- **`fuzzy_match`** (S1 upgrade) scores `0.55·idf_dice + 0.20·char-2gram-dice + 0.15·token-set-dice + 0.10·position` over `mtype=="tm"` nodes only. The IDF table (`ln((N+1)/(df+1))+1`) down-weights frequent words so rare domain terms dominate (R23); char 2-gram catches morphological variants; token-set Dice tolerates word reordering — a Chinese reordered query scores 0.91 with the new formula while the legacy one misses it entirely (R24). The old `0.7·token-cosine + 0.3·char-ratio` formula remains as `fuzzy_match_legacy` for A/B comparison.
- **`concordance`** counts query-term occurrences per TM segment — *concordance % is term occurrence, distinct from the fuzzy similarity score* (per the research baseline).
- **`load_tbx`** parses `TBX 2.0` (`<ntig><termGrp><term>` or simplified `<tig><term>`), language-aware via `xml:lang`, into `mtype="term"` nodes with `is_term=true`.
- **`enforce_terms` / `check_terms`** provide terminology lock-in and missed-term detection, with word-boundary-aware matching for Latin terms.

All six methods are covered by regression tests **R16–R22** (see [Evaluation](#evaluation--test-results)).

---

## Data Formats

### Engine persistence (`to_json` / `from_json`)

```json
{
  "memories": {
    "m1": { "id":"m1","text":"解析源文件结构","type":"step",
            "vec":{"解析":1,"源":1},"created":1,"last_used":3,
            "use_count":2,"feedback":0,"edges":{"m2":0.30},
            "predictive_value":0.42,"hit_count":1,"predict_count":1,
            "is_term":false,"translation":"" }
  },
  "transitions": { "m1": {"m2":1.0} },
  "episodes": [["m1","m2","m3"]],
  "context": ["m1","m2","m3"],
  "stats": { "preds":1, "hits":1, "remembers":3, "evolutions":0 },
  "seq": 3, "explore": 0.0, "clock": 3, "meta_hits": [1],
  "snapshot": {}, "role_trans": {}, "role_index": {}
}
```

> **TM / TermBase nodes** add two fields: a TM node carries `"type":"tm","translation":"<target>"`; a terminology node carries `"type":"term","is_term":true,"translation":"<target term>"`. Both are round-trip preserved through `to_json`/`from_json` (covered by R20).

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

### `#22` — TM / TermBase outputs

**`fuzzy_match(query, k, threshold)`** (array, Top-K by `score`):

```json
[
  { "id":"m7", "source":"电池包热管理策略", "target":"Battery pack thermal management strategy",
    "score":0.91, "match_pct":91.0, "sim_token":0.90, "sim_tfidf":0.88,
    "sim_char":0.95, "sim_ngram":0.86, "sim_tokenset":0.93 }
]
```

**`concordance(term, k)`** (array):

```json
[
  { "id":"m11", "source":"打开设置菜单选择网络", "target":"Open Settings menu, choose Network", "hits":1 }
]
```

**`load_tbx` input (TBX 2.0 fragment):**

```xml
<martif><text><body>
  <termEntry id="1">
    <langSet xml:lang="en-US"><ntig><termGrp><term>network logon</term></termGrp></ntig></langSet>
    <langSet xml:lang="zh-CN"><ntig><termGrp><term>网络登录</term></termGrp></ntig></langSet>
  </termEntry>
</body></text></martif>
```

**`enforce_terms(text)`** (array — word-boundary matched):

```json
[
  { "term":"network logon", "translation":"网络登录", "mid":"m20" }
]
```

**`check_terms(source, target)`** (array — violations only):

```json
[
  { "term":"sensor", "expected":"传感器", "mid":"m21" }
]
```

---

## Evaluation & Test Results

All numbers below are produced by `moon test --target wasm-gc` and are reproducible.

**Summary: `Total tests: 89, passed: 89, failed: 0`**
(4 quantitative acceptance + 2 corpus evaluation files (modern + extended) [Layer 0–10: 22 tests] + 25 roadmap regression [R1–R25] + 18 extension-capability regression [E1–E18]).

| Layer | Check | Result | Evidence |
|-------|-------|--------|----------|
| L1 | Batch Hit@3 > 0.8 | ✅ | `hit_rate = 0.8246` over 8 topics × 8 rounds |
| L1 | Determinism / reproducibility | ✅ | Two `to_json` calls are **byte-identical** |
| L1 | JSON round-trip | ✅ | `to_json → from_json → to_json` identical |
| L1 | Consolidation keeps core memory | ✅ | 13 nodes → 13 nodes after consolidate |
| L2 | Known-project replay predicts correct next | ✅ | observe project → Top1 `提取核心术语表并锁定` |
| L2 | Cold-start generalization | ✅ | unseen topic via D8 role-abstraction yields correct next step |
| L2 | White-box explainable | ✅ | `explain_card` returns concrete activation_path / prediction_path / value_breakdown |
| L2 | Persistence after restart | ✅ | `to_json → from_json` Top1 unchanged |
| **MC** | Modern Corpus: 8 domains × 5 rounds | ✅ | 11/11 tests passing; Hit@3=0.7773; see [Modern Corpus Evaluation](#modern-corpus-evaluation-20252026) |
| **MC** | Cold-start on unseen domains | ✅ | Zero-Day Threat Intelligence / Perovskite Solar Cell → valid predictions |
| **MC** | Cross-domain semantic recall | ✅ | Multi-domain queries activate correct domain clusters |
| **MC** | Deep fuzzy match (S1 upgrade) | ✅ | sim_token / sim_tfidf / sim_char / sim_ngram / sim_tokenset |
| **MC** | Attention-gated recall + domain bias | ✅ | α=0.3, β=0.2 + ΔW=0.15 shifts ranking correctly |
| **MC** | WAL event sourcing replay | ✅ | 384 entries → replay clone produces 576 entries |
| **MC** | Fed export/import + distillation | ✅ | Increment diff export → merge → distilled bias confirmed |

### Credibility hardening

The engine's Hit@3 is verified across multiple independent evaluation surfaces:

- **Classic acceptance suite** (4 tests): Layer1 batch training → Hit@3=0.8246, determinism, JSON round-trip, consolidation.
- **Modern corpus suite** (11 tests): 8 cutting-edge English domains, 240 training observations, Hit@3=0.7773, cold-start generalization on unseen domains, cross-domain semantic recall, deep fuzzy match, attention-gated recall, WAL event sourcing, federated export/import, and distillation.
- **Regression suite** (R1–R25): TM/TB fuzzy match % (S1 IDF + 2-gram + word-order), concordance, TBX load+enforce+check, word-boundary (`log`≠`logical`), 3-language `xml:lang`, IDF discrimination, word-order tolerance, empty/short-query boundary.
- **Extension suite** (E1–E18): QE+MQM, format-fidelity, multimodal-OCR-stub, batch-CI, TMS XLIFF/TMX, observability/drift.

Reproduce:

```bash
cd yimai_prophecy_moonbit
moon test --target wasm-gc      # all 89 tests
moon test --target wasm-gc --filter Layer*   # modern corpus only
moon build --target wasm-gc     # library only
cd cmd/main && moon build --target wasm-gc && moon run .
```

---

## Extension API (#2–#7)

All seven user-scoped extension capabilities are implemented in `engine.mbt` and regression-tested by `yimai_prophecy_moonbit_extension_test.mbt` (E1–E18). They are **zero-dependency** and **deterministic** — same input ⇒ same output.

| # | Capability | Key methods | Notes |
|---|-----------|-------------|-------|
| 2 | Quality estimation + MQM | `qe_score`, `mqm_tags`, `qe_auto` | `qe_score = 0.55·match_rate + 0.30·term_ok + 0.15·char_ratio` (cross-language length penalty dropped — it dragged scores to ~0.7 and distorted QE). `mqm_tags` emits `terminology / accuracy / fluency / omission` with `major / critical / minor` severity. |
| 3 | Format-fidelity round-trip | `check_format_fidelity`, `protect_tags` | Detects `missing` (source tag absent in target) / `extra` (target-only) inline tags & placeholders; `protect_tags` masks them to `__TAG__` so fuzzy token-cosine isn't polluted. |
| 4 | Multimodal / screenshot | `ocr_image` (stub), `align_regions` | `ocr_image` is an **external boundary stub** (real OCR = Tesseract / vision-LLM, injected by host). Regions flow as JSON `{bbox, text}`; the engine does region ↔ TM alignment purely. |
| 5 | Localization CI / batch | `batch_apply` | Top-1 TM match + term-gate per segment, threshold-driven → `{total, passed, failed, items}`. Drop-in for a CI localization gate. |
| 6 | TMS interoperability | `parse_tmx`, `parse_xliff`, `export_tmx` | XLIFF 1.2 `<trans-unit>` and 2.0 `<unit>` both parsed; TMX 1.4 exported with XML escaping. Round-trip verified (E10). |
| 7 | Observability & drift | `metrics`, `drift_report` | `metrics` = tm/term counts + term-coverage; `drift_report(before, after)` diffs two `to_json` snapshots by `(type\|is_term\|text\|translation)` key to surface TM/term add/remove. |

> **Boundary principle.** Capabilities #4 (OCR) and any host persistence stay *outside* the zero-dependency engine. The engine speaks JSON at these boundaries, so the host (Node/Python/Agent) supplies OCR, files, and I/O — the MoonBit core stays 100% pure-stdlib and `wasm-gc`-testable.

---

## Roadmap & Extension Status

### Engine implementation status (内核「快·准·美」)

The "fast / accurate / beautiful" algorithm kernel is **fully landed** and contract-tested. Remaining items are front-end workbenches (ardot hand-off) or external services, not engine gaps.

| Roadmap entry | Engine implementation | Status |
|---|---|---|
| Role inverted-index + Top-K pruning + LRU pred cache | `role_members` / predict Top-K / `pred_cache` | ✅ |
| 2nd-order Markov | `trans2` | ✅ |
| Multi-granularity roles | `roles_of` | ✅ |
| Adaptive LR + elastic forgetting | `hebb_lr` / `consolidate` | ✅ |
| Domain bias ΔW (LoRA-style) | `domain_bias` / `set_domain_bias` / `inject_distillation` | ✅ |
| Online contrastive learning | `cl_step` | ✅ |
| Attention edge weights | `attn_alpha/beta` / `set_attention` | ✅ |
| TermNode + explainable card | `mark_term` / `explain_card` | ✅ |
| Incremental WAL | `wal_*` | ✅ |
| Bilingual alignment (Myers/LCS) | `align_diff` | ✅ |
| Active-learning candidates | `active_learning_candidates` | ✅ |
| Federated increment | `fed_export` / `fed_import` | ✅ |
| Neural-symbolic distillation (consume side) | `inject_distillation` | ✅ |
| **#22 TM / TermBase** | `add_tm` / `fuzzy_match` / `concordance` / `load_tbx` / `enforce_terms` / `check_terms` | ✅ (new) |
| **S1 fuzzy-match upgrade** | `fuzzy_match`（IDF + 2-gram + word-order）/ `fuzzy_match_legacy` | ✅ |
| **Pure-MoonBit HTTP service** | `cmd/service`：24 端点 + 记忆闭环 + 原子写持久化 + 重启恢复 | ✅ (new) |
| **MCP Server (/mcp)** | `cmd/service/mcp.mbt`：24 引擎能力 → MCP tools（spec 2025-11-25） | ✅ (new) |
| **TMPlm 桥接 (M5)** | `retrieve_for_prompt` + `/api/retrieve_prompt`（三段式） | ✅ (new) |
| **SKILL.md 编排壳** | `docs/skill/SKILL.md`（agent_created，安装见 For Agents） | ✅ (new) |
| Translator workbench (web front-end) | `cmd/service/web`（四面板 + 记忆图谱） | ✅ (new，阶段 C 已交付) |
| **Visual memory graph** | web 第 4 面板（recall 节点 + via_edges 边 → SVG 确定性环布局） | ✅ (new) |
| **S4 评测 / M1 风格 / M2 回译 / M3 冲突** | `bleu_score`/`chrf_score`/`style_check`/`back_align`/`term_conflicts` + 端点 | ✅ (new) |
| **风格一致报告 (风格一致)** | `style_report`（记忆库句长/正式度分布 + 术语变体族 + 偏离建议）+ `/api/style_report` + MCP + web ⑧ 面板 | ✅ (new) |
| **FedAvg / 蒸馏注入端点** | `/api/fed_export` `/api/fed_import` `/api/distill_inject` | 🔶 端点已落地，外部协调器/独立训练流仍缺 |

### Seven extension capabilities (user-scoped)

From the "translation-born skill" brainstorm — what's built vs. pending:

| # | Capability | Status | Notes |
|---|-----------|--------|-------|
| 1 | **TM / TermBase first-class** (fuzzy match %, concordance, TBX enforcement) | ✅ Done | `moon test` 101/101; reviewed + hardened (word-boundary, `xml:lang`); S1 fuzzy-match upgrade (IDF + 2-gram + word-order, R23–R25); open-code-review + MoA fixes for `parse_tmx` cross-language/`</tu>` split + `mqm_tags` cross-language false positives + empty-target/language-variant robustness; P0 长文 + 数字守门加固（MAX_TOKENS 截断 / numeric_consistency MQM 维度 / fuzzy_match 长 query 不崩 / L1–L12 长文回归）。 |
| 2 | **Quality estimation + MQM auto-eval** | ✅ Done | `qe_score` (0.55·match + 0.30·term + 0.15·char) + `mqm_tags` (terminology/accuracy/fluency/omission w/ severity). Tested E1–E3. |
| 3 | **Format-fidelity round-trip** | ✅ Done | `check_format_fidelity` (missing/extra tag detection) + `protect_tags` (mask tags to `__TAG__`). Tested E4–E5. |
| 4 | **Multimodal / screenshot translation** | ✅ Done (OCR external stub) | `ocr_image` (external boundary) + `align_regions` (region ↔ TM align). Zero-dep engine speaks JSON at the OCR boundary; real OCR injected by host. Tested E6–E7. |
| 5 | **Localization CI / batch pipeline** | ✅ Done | `batch_apply` (Top-1 TM + term-gate, threshold-driven) → `{total, passed, failed, items}`. Tested E8–E9. |
| 6 | **TMS interoperability** | ✅ Done | `parse_tmx` / `parse_xliff` (XLIFF 1.2 `<trans-unit>` & 2.0 `<unit>`) + `export_tmx` (round-trip). Tested E10–E11; cross-language TMX correctness regression added as E14 (open-code-review fix). |
| 7 | **Observability & drift monitoring** | ✅ Done | `metrics` (tm/term counts + coverage) + `drift_report` (before/after snapshot diff). Tested E12–E13. |

> This project is **not** packaged as a WorkBuddy skill yet. The dev loop for these is: **research (Deep Research / WebSearch) → review (open-code-review) → verify (browser automation + `moon test`)**. MoA is intentionally *not* embedded inside the skill (kept as an external advisor).

---

## For Agents / Integration

This package delivers a **zero-dependency, deterministic** "Prophecy Memory Network" to other agents. Integration options (2026-08 更新，修正此前「无 I/O / 仅 IIFE」的过时声明):

> **AI agent 拆箱即用**：克隆后先读 [`AGENTS.md`](./AGENTS.md)（项目结构、构建/运行/消费指南、Windows 前置、MoonBit 坑），再跑 `scripts/dev.ps1` 一键起服务——无需人工配置。

> **安装为 WorkBuddy skill（可选）**：仓库内 [`docs/skill/SKILL.md`](./docs/skill/SKILL.md) 是编排手册（frontmatter 含 `agent_created: true`，触发词 + 24 端点 API 手册 + MCP 接入 + 数据契约）。复制到 `~/.workbuddy/skills/yimai-prophecy/` 并重启 WorkBuddy 后即成为可用技能。

**Path A — build & run (agent has the MoonBit toolchain):**

```bash
cd yimai_prophecy_moonbit
moon test --target wasm-gc        # green ⇒ engine is usable
cd cmd/main && moon build --target wasm-gc && moon run .
```

Then `moon add Across2005/yimai_prophecy_moonbit` and call any of the `ProphecyEngine` methods.

**Path B — wasm-gc exports (engine as a callable module):** 新工具链（moonc v0.10.4+）支持在 `moon.pkg.json` 配置 `link.wasm-gc.exports` + `use-js-builtin-string: true`，让 JS 宿主直接调用 `ProphecyEngine` 方法（String 与 JS String 互通）；JS 后端亦支持 `format: esm/cjs`（不再只有 IIFE）。详见 [Package Configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html)。

**Path C — service layer (纯 MoonBit HTTP server, `cmd/service`):** ✅ **已实测落地**。`moonbitlang/async` 提供 `http` / `fs` / `socket`，起本地服务并托管前端工作台；**24 个 `/api/*` 端点**（13 基础 + retrieve_prompt / bleu / chrf / style_check / style_report / back_align / term_conflicts / fed_export / fed_import / distill_inject / active_learning）全部 curl 通过，含**记忆闭环**（observe 学习 → predict 预测 → reward 反馈 → consolidate 固化）与原子写持久化 + 重启恢复（详见 [Service Layer](#service-layer--纯-moonbit-http-api-cmdservice)）。注意：Windows 上 async 的 native 后端**仅支持 MSVC 编译**（`thread_pool.c: #error "Currently only MSVC is supported on Windows"`）；wasm/js 后端暂不支持 socket server（`socket/unimplemented.mbt`）。

**Path D — algorithm port (agent has no MoonBit but needs the capability in-process):**

`engine.mbt` is pure-stdlib, zero-I/O, with constants (`HEBB_LR`, `EDGE_DECAY`, `BETA`, …) that map 1:1 to D1–D8. It can be reimplemented in Python / TypeScript / Go by reading the source — the most portable route for cross-language agent loading.

**Path E — MCP client (Claude Desktop / any MCP host):** ✅ 已实测。`cmd/service` 暴露 `/mcp` 端点（MCP spec 2025-11-25 Streamable HTTP），24 个引擎能力映射为 MCP tools（fuzzy_match / add_tm / check_terms / concordance / qe_auto / predict / observe / recall / explain / reward / consolidate / tm_count / ping / retrieve_prompt / bleu / chrf / style_check / style_report / back_align / term_conflicts / fed_export / fed_import / distill_inject / active_learning）。Claude Desktop 配置：

```json
{ "mcpServers": { "yimai": { "url": "http://127.0.0.1:8787/mcp" } } }
```

先 `moon run cmd/service --target native` 起服务，MCP 客户端即可经 initialize → tools/list → tools/call 消费全部引擎能力（详见 [MCP Server](#mcp-servermcp-端点--供-claude-desktop--通用-mcp-客户端消费)）。

---

## Contributing

Issues and pull requests are welcome. The repo ships multiple test suites — please keep `moon test --target wasm-gc` green when you submit a change. For behavioural/evaluation changes, extend `yimai_prophecy_moonbit_modern_corpus_test.mbt` with real modern corpus so the evaluation stays honest.

---

## License

MIT — see [`LICENSE`](./LICENSE).

---

## Acknowledgements

- Built on the [MoonBit](https://www.moonbitlang.com) language and its `core` (`json`, `math`) packages.
- README structure follows conventions of high-star open-source projects (e.g. `sharkdp/bat`, `BurntSushi/ripgrep`) and the idiomatic MoonBit library style of [`moonbit-community/moon_elk`](https://github.com/moonbit-community/moon_elk).
- 完整架构方案（评审叙事 + 工程附录 13 章）：`译脉·先知2.0_完整架构方案.md`（黑客松定位、三层架构、确定性/零依赖/白盒三大卖点、S1 实证、增强路线图 S/M/L → 端点映射）。
