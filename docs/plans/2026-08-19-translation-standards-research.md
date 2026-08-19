# 前沿国际视域下的翻译/本地化标准研究报告

**项目：** yimai_prophecy_moonbit（译脉·先知 2.0）  
**日期：** 2026-08-19  
**范围：** 聚焦 0.2.0 版本需要对接的国际翻译/本地化标准，梳理最新版本、核心要求、与 yimai 现有能力的映射及下一步建议。

---

## 1. 研究方法说明

- 以 ISO、OASIS、W3C 官方发布状态为准，辅以行业文献与主流 CAT/TMS 工具实现现状。
- 对 yimai 能力的映射基于 `engine.mbt`、`AGENTS.md`、`README.md` 及现有测试用例（`tests/feature/*`）。
- 本报告不修改代码，仅在末尾给出可直接写入 `AGENTS.md` 的修订建议。

---

## 2. 各标准现状与解读

### 2.1 ISO 17100:2015 — Translation services — Requirements for translation services

| 项目 | 说明 |
|------|------|
| **最新版本** | ISO 17100:2015 + Amd 1:2017（现行）。**未发现 2024/2025 正式新版**。ISO/TC 37/SC 5 已将其置于“待修订”（stage 90.92）状态，但新版尚未发布。 |
| **核心要求** | 1. 核心流程：翻译、校审（revision）、审阅（review）分离。  <br>2. 译员能力：翻译/语言学学位+2 年经验，或等效能力评估。  <br>3. 技术资源：安全的项目管理、文件处理、存储与交换工具。  <br>4. 反馈循环：交付后客户满意度与反馈收集。  <br>5. **明确排除**“原始 MT 输出 + 译后编辑”（由 ISO 18587 覆盖）。 |
| **与 yimai 的映射** | - `observe`/`predict`/`reward` 构成交付后的反馈与学习闭环。  <br>- `consolidate`/`restore` 对应 ISO 17100 §5.5 要求的技术审阅与元认知复核。  <br>- `retrieve_prompt` 可在 LLM 翻译步骤中注入双语上下文，强化译员能力。 |
| **0.2.0 建议** | 1. 在 `AGENTS.md` 中明确：yimai 是“技术构件”，不直接认证 ISO 17100，但可为认证流程提供记忆与一致性支撑。  <br>2. 新增 `project_spec` 结构化接口，支持按 ISO 11669:2024 生成翻译项目规范（见 2.4）。 |

---

### 2.2 ISO 18587:2017 — Translation services — Post-editing of machine translation output

| 项目 | 说明 |
|------|------|
| **最新版本** | ISO 18587:2017（现行）。**未发现 2024 修订版**。中文等同采用为 GB/T 40036-2021。 |
| **核心要求** | 1. 定义完整译后编辑（full post-editing）与轻量译后编辑（light post-editing）。  <br>2. 译后编辑人员能力：语言能力、翻译经验、MT 系统理解。  <br>3. 流程要求：明确 MT 输出质量预期、后编辑深度、交付标准。  <br>4. 仅适用于经 MT 系统处理的内容。 |
| **与 yimai 的映射** | - `qe_auto`（QE + MQM 标注）在译后编辑前量化 MT 输出质量。  <br>- `bleu`/`chrf` 提供 MT 输出前后对比。  <br>- `retrieve_prompt` 可将 TM 命中注入译后编辑 LLM 步骤。  <br>- `mqm_re_annotate` 对 Critical 问题进行二次审视，降低人工评估噪音。 |
| **0.2.0 建议** | 1. 在 `qe_auto` 输出中增加 `post_editing_effort` 字段（如 Low/Medium/High），直接服务于 ISO 18587 的“后编辑深度”约定。  <br>2. 将 `mqm_re_annotate` 从仅 Critical 扩展为可选“全量二次审”（配置开关）。 |

---

### 2.3 ISO 30042:2019 TBX3 — TermBase eXchange v3

| 项目 | 说明 |
|------|------|
| **最新版本** | ISO 30042:2019（TBX3，现行），替代 ISO 30042:2008。中文修改采用为 GB/T 44227-2024（2025-02-01 实施）。 |
| **TBX3 vs TBX2 关键差异** | 1. **元模型重构**：TBX3 明确 `conceptEntry` → `langSec` → `termSec` 的元模型，TBX2 以 `<ntig>/<termGrp>/<term>` 为主。  <br>2. **DCA / DCT 两种 XML 编码方式**：数据类别可作为属性（DCA）或标签（DCT）表达，TBX2 多为 DCA。  <br>3. **方言机制**：TBX3 定义“核心方言”（TBX-Core）与行业自定义方言（如 TBX-Basic、TBX-Min），TBX2 相对单一。  <br>4. **与 ISO 16642 TMF 对齐**：TBX3 是术语标记框架（TMF）下的具体实现。 |
| **最新解释器实践** | 主流 CAT 工具（SDL Trados、memoQ、OmegaT）同时兼容 TBX2 与 TBX3；生产环境常见做法是在导入时按 `<martif>` 与 `<termEntry>` 识别版本，再分别解析 `<tig>` / `<ntig>` / `<termSec>`。 |
| **与 yimai 的映射** | - `load_tbx` 已支持 TBX2 风格 `<ntig>/<termGrp>/<term>` 与简化 `<tig>`，并做语言感知匹配。  <br>- `enforce_terms` / `check_terms` 实现术语强制对齐与一致性校验。 |
| **0.2.0 建议** | 1. 扩展 `load_tbx` 以支持 TBX3 的 `<conceptEntry>/<langSec>/<termSec>` 结构。  <br>2. 增加 `export_tbx`（当前仅有 `export_tmx`），支持 TBX3 DCA/DCT 双模式导出。  <br>3. 在 `AGENTS.md` 中把“TBX2”更正/补充为“ISO 30042:2019 / TBX3（向下兼容 TBX2）”。 |

---

### 2.4 ISO 11669:2024 — Translation projects — General guidance

| 项目 | 说明 |
|------|------|
| **最新版本** | ISO 11669:2024（正本国际标准），替代已废止的 ISO/TS 11669:2012。2024 年发布。 |
| **核心要点** | 1. 为翻译项目全生命周期提供通用指南：需求分析 → 规划 → 执行 → 交付 → 收尾。  <br>2. 强调项目规范的制定：目标受众、用途、风格、术语、文件格式、交付方式、质量预期。  <br>3. 风险评估与缓解。  <br>4. **非认证性标准**，不提供定量质量评估程序。 |
| **与 yimai 的映射** | - `predict` 可作为项目执行阶段的“下一步动作推荐器”。  <br>- `consolidate` 可用于项目收尾阶段的元认知审查。  <br>- `batch_apply` 可对接项目规范中的批量处理需求。 |
| **0.2.0 建议** | 1. 新增 `project_spec` 数据结构与 `/api/project_spec` 端点，支持按 ISO 11669:2024 字段生成项目规范 JSON。  <br>2. 在 `batch_apply` 中允许传入项目规范参数，实现“按规范执行”的 CI 流程。 |

---

### 2.5 MQM / MQM Core 2025

| 项目 | 说明 |
|------|------|
| **最新版本** | MQM Core 经过 2024–2025 年修订，形成“修订版 MQM Core + MQM Full 错误分类学、带校准的线性评分模型、流程导向评估”。严重度约定保持不变。 |
| **严重度约定** | 标准四档：**Neutral / Minor / Major / Critical**。  <br>常见罚分：0 / 1 / 5 / 10（线性/指数均可配置）。 |
| **与 yimai `severity_score` 的对应** | yimai 已实现：none=0 / minor=1 / major=5 / critical=10，与 MQM Core 主流记分卡一致。 |
| **与 yimai 的映射** | - `mqm_issue` 输出 `dimension`、`severity`、`severity_score`、`detail` 四字段。  <br>- `mqm_tags` 覆盖 terminology / accuracy / fluency / omission / numeric_consistency 等维度。  <br>- `qe_auto` 返回 `qe_score`、`term_ok`、`mqm` 三段式结果。 |
| **0.2.0 建议** | 1. 在 `AGENTS.md` 中更新为“MQM Core 2025（修订版）”，并保留 0/1/5/10 映射表。  <br>2. 增加可选的 MQM Full 二级分类（如 `addition`、`mistranslation`、`grammar` 等子类型）。  <br>3. 提供 `/api/mqm_score` 端点，按 MQM Core 2025 计算标准化质量分数。 |

---

### 2.6 MQM Re-annotation（Riley et al., Google, 2025-10-28）

| 项目 | 说明 |
|------|------|
| **最新要点** | 论文 *Improving Human Translation Evaluation with Re-annotation* 提出：单次 MQM 标注易产生评估噪音；由第二位评估员（或 LLM 评估器）复核已有标注，可新增、删除或修正错误 span，显著提升评分一致性与可靠性。研究覆盖人工标注、GEMBA-MQM（GPT-4 提示）与 AutoMQM（微调 Gemini）三类初标来源。 |
| **与 yimai 的映射** | - yimai 已在 `mqm_re_annotate` 中实现 Critical 问题的 deterministic 自重审。  <br>- 当前输出字段：`re_annotated`、`critical_count`、`re_annotations`，预留了未来多评估员模型的接口。 |
| **0.2.0 建议** | 1. 扩展 `mqm_re_annotate` 支持可选的 `rater_id` 参数，实现多评估员模型。  <br>2. 增加对 Major 问题的可选二次审（默认 Critical -only）。  <br>3. 记录“标注来源”（human / gemba-mqm / auto）到 `re_annotations` 元数据。 |

---

### 2.7 TMX 1.4b / XLIFF 2.1 / ISO 21720:2024 / SRX 2.0 互操作现状

| 标准 | 最新版本与状态 | CAT 工具对接要点 |
|------|----------------|------------------|
| **TMX** | TMX 1.4b（2005 发布，2013 年 ETSI GS LIS 002 V1.4.2 重新托管），仍为事实标准。 | 所有主流 CAT 工具支持导入/导出 TMX 1.4b；注意 `<seg>` 内 XML 转义与语言代码前缀匹配。 |
| **XLIFF** | - OASIS XLIFF 2.1（2018-02-13 发布，当前 OASIS 稳定版）。  <br>- OASIS XLIFF 2.2 Committee Specification（2025-03-13）。  <br>- **ISO 21720:2024**（第二版）为 ISO 采纳的 XLIFF 2.0，替代 ISO 21720:2017。 | XLIFF 2.x 核心为 `<unit>/<source>/<target>`；2.2 引入更原生的 ITS 2.0 支持、改进验证模块。CAT 工具对 XLIFF 2.1 支持已普及，2.2 尚在跟进。 |
| **SRX** | SRX 2.0（2008 年 OSCAR 标准），现由 GALA 维护。 | 用于记录句段切分规则，使 TMX 在不同工具间复用。规则基于 ICU 正则表达式； Crowdin、AEM Guides 等支持自定义 SRX 2.0。 |
| **互操作现状** | TMX/XLIFF/SRX 仍是 CAT 数据交换三驾马车；实际落地时需注意：1) TMX 1.4b 与 XLIFF 2.x 语言代码差异；2) 不同工具默认断句规则不同，需 SRX 保证复用性；3) 占位符/标签在 TMX/XLIFF 与本地 TM 间需保真。 | |

**与 yimai 的映射：**

- `parse_tmx` / `export_tmx`：已分别实现 TMX 1.4 导入/导出。
- `parse_xliff`：已实现 XLIFF 1.2/2.0 `<trans-unit>` / `<unit>` 导入。
- **SRX**：尚未实现；yimai 的 `concordance` / `fuzzy_match` 按内部 tokenize 规则切分，与外部 SRX 规则可能不一致。

**0.2.0 建议：**

1. 将 `parse_tmx` / `parse_xliff` / `export_tmx` 暴露为 `/api/import_tmx`、`/api/export_tmx`、`/api/import_xliff`。
2. 新增 `export_xliff`（XLIFF 2.1/ISO 21720:2024 兼容），补齐导出侧。
3. 新增最小 SRX 2.0 解析器 `parse_srx`，使 `fuzzy_match`/`concordance` 在导入 SRX 后可按项目规则切分，提升与 CAT 工具的句段对齐一致性。
4. 在 `AGENTS.md` 中将 XLIFF 状态从“ISO 21720:2017”更新为“ISO 21720:2024”。

---

### 2.8 W3C ITS 2.0 在本地 TM/TB 引擎中的可能使用点

| 数据类别 | 含义 | 在 yimai 中的使用点 |
|----------|------|---------------------|
| **Translate** | 标记元素是否应被翻译 | 导入 XML/HTML 内容时，结合 `its:translateRule` 决定是否进入 `add_tm`/`parse_xliff`。 |
| **Terminology** / **Terminology with termConfidence** | 链接术语库条目并带置信度 | 与 `load_tbx`/`enforce_terms` 联动，为术语命中附加 `termConfidence` 分数。 |
| **Domain** | 内容领域标识 | 与 yimai 的 `domain_bias` / `set_domain_bias` 对接，实现领域路由。 |
| **Locale Filter** | 指定内容适用的目标区域 | 在 `fuzzy_match` 中按目标 locale 过滤 TM 条目。 |
| **MT Confidence** | MT 系统对翻译结果的信心 | 导入时写入 `qe_score`，作为 `fuzzy_match` 排序的补充信号。 |
| **Localization Quality Issue / Localization Quality Rating** | 标注已知的质量问题 | 与 `mqm_issue` 结果双向映射，实现“预标注问题 → MQM issue”的流转。 |
| **Elements Within Text** | 标记不应打断翻译流的内联元素 | 与 `protect_tags`/`check_format_fidelity` 配合，避免 `<ph>` 类标签被误切分。 |

**0.2.0 建议：**

1. 新增 `parse_its_rules` 辅助函数，从 XML/HTML 文档中提取 ITS 2.0 规则。
2. 在 `parse_xliff` / `parse_tmx` 中识别并保留 ITS 2.0 元数据（如 `its:term`、`its:translate`）。
3. 在 `export_xliff` 中回写 ITS 2.0 标注（术语、MT confidence、质量 issue）。

---

## 3. yimai 现有能力映射总表

| 标准 | yimai 已实现 | 已暴露端点/MCP | 0.2.0 缺口 |
|------|--------------|----------------|------------|
| ISO 17100:2015 | 反馈闭环、技术审阅、双语上下文注入 | `observe`, `predict`, `reward`, `consolidate`, `retrieve_prompt` | 项目规范接口、认证声明 |
| ISO 18587:2017 | MT 质量评估、译后编辑深度暗示、二次审 | `qe_auto`, `mqm_re_annotate`, `bleu`, `chrf` | `post_editing_effort` 字段 |
| ISO 30042:2019 TBX3 | TBX2/TBX3 解析、术语对齐/校验 | `load_tbx`, `enforce_terms`, `check_terms` | TBX3 DCA/DCT 导出 |
| ISO 11669:2024 | 阶段化预测、批量处理 | `predict`, `batch_apply` | `project_spec` 结构化接口 |
| MQM Core 2025 | 0/1/5/10 严重度、核心维度标注 | `mqm_tags`, `mqm_issue`, `qe_auto` | MQM Full 二级分类、标准分端点 |
| MQM Re-annotation | Critical 自重审 | `mqm_re_annotate` | 多评估员、Major 复审 |
| TMX 1.4b | 导入/导出 | 引擎内 `parse_tmx`/`export_tmx` | `/api/*` 端点 |
| XLIFF 2.1/ISO 21720:2024 | 导入 | 引擎内 `parse_xliff` | 导出端点、ITS 2.0 元数据 |
| SRX 2.0 | 无 | — | `parse_srx` + 切分规则应用 |
| W3C ITS 2.0 | 无显式支持 | — | 规则解析、元数据保留/回写 |

---

## 4. 0.2.0 版本建议（按优先级）

1. **标准化接口补齐**：把 `parse_tmx`/`export_tmx`/`parse_xliff` 暴露为 `/api/*` 端点；新增 `export_xliff`。
2. **TBX3 导出**：实现 `export_tbx`，优先支持 DCA 编码，与 `load_tbx` 形成 TB 闭环。
3. **ISO 11669 项目规范**：新增 `project_spec` 数据结构与端点。
4. **SRX 2.0 最小支持**：`parse_srx` + 在 `fuzzy_match`/`concordance` 中按 SRX 规则切分。
5. **ITS 2.0 元数据**：在 XLIFF 导入/导出中保留 `its:*` 标注。
6. **MQM Core 2025 对齐**：在 `AGENTS.md` 中更新版本表述，并考虑增加 MQM Full 二级分类。
7. **认证声明**：在 `AGENTS.md` 中明确 yimai 是“技术构件，非认证主体”，避免用户误解为可直接获得 ISO 认证。

---

## 5. 可直接写入 AGENTS.md 的修订建议

> 以下文本可直接替换或追加到 `AGENTS.md` 的“International translation standards (alignment, not certification)”一节。

```markdown
## International translation standards (alignment, not certification)

This engine is a **technical building block**, not a translation service, so it
isn't itself certifiable — but the features map cleanly to the workflows the
following international standards describe, so adopters can wire yimai into
ISO-conformant pipelines:

| Standard | What it covers | How yimai fits |
|---|---|---|
| **ISO 17100:2015 + Amd 1:2017** (Translation services — Requirements) | Translator competence, project management, technical resources, post-delivery feedback. No 2024/2025 edition has been published; the standard is under periodic review (stage 90.92). | `observe`/`predict`/`reward` provide the post-delivery feedback loop; `consolidate`/`restore` support the technical revision step. |
| **ISO 18587:2017** (Post-editing of MT output) | MTPE workflow, post-editor competence, output quality. No 2024 edition has been published. | `qe_auto` (QE + MQM tagging) and `bleu`/`chrf` measure MT output before/after post-edit; `retrieve_prompt` injects TM hits into the post-edit step. |
| **ISO 30042:2019 / TBX3** (TermBase eXchange, v3) | TermBase XML schema for terminology exchange. TBX3 introduces a `conceptEntry`/`langSec`/`termSec` metamodel and DCA/DCT encoding; it supersedes TBX2. | `load_tbx` parses ISO 30042-compliant TBX2/TBX3 XML; `enforce_terms`/`check_terms` enforce term consistency. `export_tbx` (TBX3-DCA) is planned for 0.2.0. |
| **ISO 11669:2024** (Translation projects — General guidance) | Project lifecycle, deliverables, sign-off. Replaces the withdrawn ISO/TS 11669:2012. | `project_spec` (planned for 0.2.0) structures project requirements; `predict` recommends next actions; `consolidate` supports project-completion review. |
| **MQM Core 2025** (Multidimensional Quality Metrics) | Revised Core + Full typology with calibrated linear scoring. Severity scale: **None=0 / Minor=1 / Major=5 / Critical=10**. | `qe_auto` returns an MQM-shaped tag set; `mqm_re_annotate` performs a second pass on Critical issues. |
| **MQM Re-annotation** (Riley et al., Google, 2025-10-28) | Two-stage MQM review: a second rater reviews existing annotations (human or auto) to reduce inter-rater variance and improve reliability. | `mqm_re_annotate` currently performs deterministic self-review on Critical issues; the JSON shape is designed for future multi-rater/LLM-rater swap-in. |
| **TMX 1.4b / XLIFF 2.1 / ISO 21720:2024 / SRX 2.0** | CAT-tool interchange standards for translation memory, localization packages, and segmentation rules. | `parse_tmx`/`export_tmx` and `parse_xliff` are implemented in-engine; `/api/*` endpoints and `export_xliff` are planned for 0.2.0. SRX 2.0 segmentation support is on the roadmap. |
| **W3C ITS 2.0** (Internationalization Tag Set) | Markup-level metadata for translation, terminology, locale, MT confidence, and localization quality. | Currently consumed indirectly via host CMS/app; 0.2.0 will parse and preserve `its:*` metadata in XLIFF/TBX workflows. |

### MQM severity scale (cross-tool alignment)

yimai's `severity_score` follows the standard MQM Core scale: `None=0 / Minor=1 / Major=5 / Critical=10`.
This keeps scores comparable with MQM Core 2025 and avoids tool-specific penalty drift.
```

---

## 6. 结论与最重要的 3 条发现摘要

1. **ISO 17100:2015 与 ISO 18587:2017 均未发布 2024/2025 新版**：国际官方最新版仍为 2015+Amd 1:2017 和 2017。yimai 无需追逐新版，但应把能力映射写清楚，避免用户误以为有新版要求。
2. **ISO 21720:2024 已发布，XLIFF 2.2 已进入 Committee Specification**：yimai 当前的 `parse_xliff` 基于 XLIFF 1.2/2.0，应尽快补齐 XLIFF 2.1/2.2 导出（`export_xliff`）并把 ISO 引用从 2017 更新为 2024。
3. **MQM Re-annotation 与 ITS 2.0 是 0.2.0 提升评估可信度与互操作性的关键**：前者可通过扩展多评估员/LLM 复核提升 `mqm_re_annotate` 的实用价值；后者能打通 XLIFF/TBX 与外部 CAT 工具之间的元数据通道。
