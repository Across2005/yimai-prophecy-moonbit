# 译脉·先知 2.0 (MoonBit)

> 一套**带预测能力的记忆网络**——让本地智能体记住工作流，并在遇到同类任务时**预测下一步需求**、给出可白盒解释的路径。这是「译脉·先知 2.0 预知记忆网络」引擎的 MoonBit 零依赖实现。

[![Tests](https://img.shields.io/badge/tests-16%2F16%20passing-brightgreen)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![Hit@3](https://img.shields.io/badge/Hit%403-0.8246-brightgreen)](https://github.com/Across2005/yimai_prophecy_moonbit)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.2026-9cf)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](./LICENSE)

---

## Table of Contents

- [Features](#features)
- [How it works (D1–D8)](#how-it-works-d1d8)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Real-world scenario: predictive translation memory](#real-world-scenario-predictive-translation-memory)
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

**Summary: `Total tests: 16, passed: 16, failed: 0`** (4 quantitative acceptance + 4 real-world scenarios + 4 pre-existing black-box + 4 supporting).

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

Detailed evidence:
- Quantitative acceptance (Layer1/Layer2): [`ACCEPTANCE_REPORT.md`](./ACCEPTANCE_REPORT.md)
- Concrete translation-content evaluation (4 scenarios): [`EVALUATION_REPORT.md`](./EVALUATION_REPORT.md)

Reproduce:

```bash
cd yimai_prophecy_moonbit
moon test --target wasm-gc      # all 16 tests, includes real-world scenarios
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
├── README.md
├── ACCEPTANCE_REPORT.md  # quantitative acceptance evidence
├── EVALUATION_REPORT.md  # concrete translation-content evaluation
├── AGENT_INTEGRATION.md  # how another agent plugs this in
├── LICENSE               # Apache-2.0
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

Apache-2.0 — see [`LICENSE`](./LICENSE).

---

## Acknowledgements

- Built on the [MoonBit](https://www.moonbitlang.com) language and its `core` (`json`, `math`) packages.
- README structure follows conventions of high-star open-source projects (e.g. `sharkdp/bat`, `BurntSushi/ripgrep`) and the idiomatic MoonBit library style of [`moonbit-community/moon_elk`](https://github.com/moonbit-community/moon_elk).
