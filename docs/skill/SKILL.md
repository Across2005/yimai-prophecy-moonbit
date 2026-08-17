---
name: yimai-prophecy
agent_created: true
description: >-
  译脉·先知 2.0 翻译记忆预测引擎（确定性记忆网络 + TM/术语库 + 下一步预测）。当用户需要翻译记忆检索、
  术语一致性校验、下一步预测、记忆闭环反馈、MT 质量评测（BLEU/chrF++）、风格检查、风格一致报告、回译对齐、术语冲突检测，
  或把翻译记忆注入 LLM prompt（TMPlm）时使用。服务形态：本地 HTTP 服务（24 REST 端点 + 2 ops（metrics/health）
  + /mcp MCP Server spec 2025-11-25 + 前端工作台；纯本地、零云端依赖；13 个 harness 已有 drop-in 配置）。
  P4 增量（2026-08）：decode_pct 路径安全加固 + MCP notifications/* 通配 + fuzzy_match 抽公共 helper
  + drift_report.text_chrf_avg 翻译质量漂移指标 + MQM 严重度数值化（None=0/Minor=1/Major=5/Critical=10）
  + predict/consolidate 拆 5/4 段 fn + routes_meta 单一源化。
tips: >-
  触发词：翻译记忆、TM 检索、术语校验、check_terms、下一步预测、predict、记忆闭环、reward、consolidate、
  BLEU 评测、chrF 评测、风格检查、回译验证、术语冲突、TMPlm、retrieve_prompt、MQM、drift_report、
  漂移报告、翻译质量、严重度、severity_score、Claude Code、Cursor、Gemini CLI、MCP。
  先用 scripts/dev.ps1 起服务（或确认 127.0.0.1:8787 已运行），再按「API 手册」调用端点；
  读结果时优先看白盒分数（sim_* 分量）与证据链。
---

# 译脉·先知 2.0 —— 翻译记忆预测引擎

## 功能描述

- **确定性记忆网络**：D1-D8 模块（Hebbian 学习、二阶马尔可夫、角色索引、预测缓存、自适应学习率、弹性遗忘、领域偏置、对比学习、注意力边权、WAL、联邦增量、主动学习、双语对齐），零第三方依赖，同输入必同输出。
- **翻译记忆（TM）+ 术语库（TB）**：#22 模块 —— add_tm / fuzzy_match（S1 四分量白盒：token/tfidf/char/ngram/tokenset）/ concordance / load_tbx / enforce_terms / check_terms。
- **记忆闭环**：observe（记录步骤）→ predict（下一步预测+证据链）→ reward（采纳/拒绝反馈）→ consolidate（固化重放），重启不丢（tm_store.json 原子落盘）。
- **质量与扩展**：qe_auto（QE+MQM）、style_check（风格一致性）、style_report（风格一致报告）、back_align（回译 LCS 对齐）、term_conflicts（术语冲突）、bleu_score / chrf_score（MT 评测）、retrieve_for_prompt（TMPlm 三段式 prompt 上下文）。
- **多形态消费**：13 REST 端点 + 11 补充端点（共 24；含 metrics/health 共 26）+ `/mcp` MCP Server（24 tools）+ 前端工作台（8 面板，含记忆图谱可视化、职业译员双栏工作台、双语对齐热力图、主动学习推荐、风格一致报告）。

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
| `/api/ping` | — | 健康检查 |

## MCP 接入（Claude Desktop / 通用 MCP 客户端）

```json
{ "mcpServers": { "yimai": { "url": "http://127.0.0.1:8787/mcp" } } }
```

24 个 MCP tools 与上表端点一一对应（initialize → tools/list → tools/call）。

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
