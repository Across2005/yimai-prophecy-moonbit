---
name: yimai-prophecy
language: MoonBit
description: >-
  译脉·先知 2.0：一个用 MoonBit 写的本地化记忆与预测引擎，帮你把「翻过的句子」和「学过的术语」变成下一次可复用的资产。
  适合译员、本地化工程师、翻译项目管理者使用。零云端依赖、零第三方依赖，同一输入始终同一输出。

  它能做什么：
  - 翻译记忆（TM）：存双语对、按白盒分数（词/词频/字符/N元/词集）检索相似句
  - 术语库（TB）：加载 TBX 术语表，守门术语不一致（支持多语言）
  - 下一步预测：记住你最近做的几个步骤，推荐下一个合理的动作，并给出证据链
  - MT 评分：内置 BLEU-4 与 chrF++，零依赖可复现
  - 风格检查与报告：检测句长/正式度偏离、术语变体、生成一致报告
  - 回译对齐：帮你看译稿是否准确，定位不匹配点
  - 主动学习：推荐高不确定性句子供你优先审核
  - MQM 二次标注：自动跑两轮 MQM 质检

  服务形态：本地 HTTP 服务（27 个 REST 接口 + /mcp 端的 MCP 服务 + 前端工作台），
  同时为 Claude Desktop、Cursor、Continue.dev、Cline、Windsurf、Roo Code、Zed、
  GitHub Copilot、Codex CLI、Gemini CLI、Aider、Cody 提供 drop-in 配置（13 种 harness）。

  只需起一次服务（scripts/dev.ps1），就能在任何 MCP 工具里直接调。

tips: >-
  触发场景：翻译记忆、TM 检索、术语校验、术语一致性、下一步预测、记忆闭环、反馈学习、
  MT 质量评测、BLEU、chrF、chrF++、风格检查、风格一致、回译对齐、术语冲突、
  把 TM 灌给 LLM、主动学习、MQM、漂移报告、翻译质量评估、严重度评分、
  二次标注、re_annotate；本地服务、MCP、http://127.0.0.1:8787。
  详细 endpoint 列表见下方 API 手册。
---

# 译脉·先知 2.0 —— 翻译记忆预测引擎

## 功能描述

- **确定性记忆网络**：D1-D8 模块（Hebbian 学习、二阶马尔可夫、角色索引、预测缓存、自适应学习率、弹性遗忘、领域偏置、对比学习、注意力边权、WAL、联邦增量、主动学习、双语对齐），零第三方依赖，同输入必同输出。
- **翻译记忆（TM）+ 术语库（TB）**：#22 模块 —— add_tm / fuzzy_match（S1 四分量白盒：token/tfidf/char/ngram/tokenset）/ concordance / load_tbx / enforce_terms / check_terms。
- **记忆闭环**：observe（记录步骤）→ predict（下一步预测+证据链）→ reward（采纳/拒绝反馈）→ consolidate（固化重放），重启不丢（tm_store.json 原子落盘）。
- **质量与扩展**：qe_auto（QE+MQM）、style_check（风格一致性）、style_report（风格一致报告）、back_align（回译 LCS 对齐）、term_conflicts（术语冲突）、bleu_score / chrf_score（MT 评测）、retrieve_for_prompt（TMPlm 三段式 prompt 上下文）。
- **多形态消费**：27 REST 端点（25 业务 + metrics/health）+ `/mcp` MCP Server（25 tools）+ 前端工作台（8 面板，含记忆图谱可视化、职业译员双栏工作台、双语对齐热力图、主动学习推荐、风格一致报告）。

## 调用条件（触发场景）

- 翻译/本地化工作流需要 **TM 记忆**（相似句检索、术语守门、质量评分）
- 需要 **预测式翻译记忆**（根据已做步骤推荐下一步，可解释）
- 需要 **MT 质量评测**（BLEU-4 / chrF++，零依赖可复现）
- 需要 **TMPlm**（把 TM 检索结果组装成 LLM prompt 上下文）
- 需要 **记忆可视化/审计**（白盒卡片、记忆图谱、术语冲突）

## 快速启动

```bash
# Windows（MSVC 已装）：一键构建→启动→灌示例→冒烟
powershell -ExecutionPolicy Bypass -File scripts/dev.ps1
# 或分步：scripts/setup.ps1 → build.ps1 → run.ps1 → seed.ps1 → smoke.ps1
```

服务地址：`http://127.0.0.1:8787`；数据持久化：`tm_store.json`（原子写，重启恢复）。

## API 手册（REST，全部 POST + JSON body；MCP 等价 tools 见 /mcp）

| 端点 | 请求 | 响应要点 |
|---|---|---|
| `/api/add_tm` | `{"src","tgt"}` | `{id,status}` 新增 TM 并落盘 |
| `/api/fuzzy_match` | `{"query","k","threshold"}` | Top-K + S1 四分量白盒（sim_token/tfidf/char/ngram/tokenset） |
| `/api/check_terms` | `{"source","target"}` | 术语违规数组（term/expected/mid），空=通过 |
| `/api/concordance` | `{"term","k"}` | 含术语 TM 段（hits 频次） |
| `/api/qe_auto` | `{"source","target","match_rate"}` | `{qe_score,term_ok,mqm}` |
| `/api/predict` | `{"k"}` | `{predictions,confidence,uncertainty}` + 路径证据 |
| `/api/observe` | `{"text","mtype"}` | `{mid,status}` 记录步骤（学习） |
| `/api/recall` | `{"query","k"}` | 激活扩散召回（via_edges） |
| `/api/explain` | `{"mid"}` | 白盒卡片（value_breakdown/activation_path） |
| `/api/reward` | `{"mid","score"}` | 采纳/拒绝反馈（闭环核心） |
| `/api/consolidate` | `{"prune"}` | 固化重放（pruned/nodes/edges） |
| `/api/tm_count` | — | `{tm_count}` 存量 |
| `/api/retrieve_prompt` | `{"query","k","threshold"}` | **TMPlm 三段**：suggestions/terms/glossary |
| `/api/bleu` · `/api/chrf` | `{"ref","hyp"}` | MT 质量评测分数 |
| `/api/style_check` | `{"text"}` | 风格问题数组（rule/level/message） |
| `/api/style_report` | `{"text"?}` | 风格一致报告：句长/正式度分布 + 术语变体族 + 新译文偏离建议 |
| `/api/back_align` | `{"source","target"}` | `{align_score,misaligns,ops}` 含字符级对齐脚本 |
| `/api/term_conflicts` | — | 一词多译/多词一译 |
| `/api/fed_export` · `/api/fed_import` | `{"added","updated"}` | 联邦增量 |
| `/api/distill_inject` | `{"table":{k:v}}` | 蒸馏偏置注入 |
| `/api/active_learning` | `{"k"}` | 主动学习推荐：待标注句 Top-K（uncertainty×0.6+novelty×0.4，角色去重） |
| `/api/mqm_re_annotate` | `{"source","target","match_rate"}` | MQM 二次标注（re_annotated / critical_count / re_annotations） |
| `/api/metrics` | — | 引擎运行指标（tm_count / term_count / total_memories / term_coverage / predict_calls / hit_rate） |
| `/api/health` | — | 健康详情（uptime_seconds / version / last_save_status / last_save_age_seconds） |
| `/api/ping` | — | 健康检查 |

## MCP 接入（Claude Desktop / 通用 MCP 客户端）

```json
{ "mcpServers": { "yimai": { "url": "http://127.0.0.1:8787/mcp" } } }
```

25 个 MCP tools 与上表端点一一对应（initialize → tools/list → tools/call）。

## 数据契约

- **tm_store.json**：`to_json()` 全量快照（memories/edges/clock/domain_bias 等），`from_json()` 恢复后重建内部索引（role_members / tm_idf）。写操作原子落盘（tmp+rename）。
- **JSON 边界**：引擎零依赖纯函数，外部能力（OCR/LLM/持久化宿主）经 JSON 注入——`ocr_image`/`retrieve_for_prompt` 均走此边界。
- **确定性**：逻辑时钟 `clock`（非 wall-clock），同输入必同输出（R15 契约）；浮点统一 `r4` 舍入。

## 已知边界

- Windows native 构建需 MSVC（`link.native.cc` 指向 cl.exe，`scripts/setup.ps1` 可检测）。
- BLEU 实现口径：Add-1 平滑 + BP（Papineni 2002 单参考），与 sacrebleu 数值可能有小幅差异。
- chrF++：字符 1-6 元 + 词 1-2 元，β=2（Popović 2017），空格不参与字符 n-gram。
- MQM 严重度采用标准尺度 None=0/Minor=1/Major=5/Critical=10；数字守门（numeric_consistency）
  不受跨语种影响。
