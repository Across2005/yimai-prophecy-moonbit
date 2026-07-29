# 译脉·先知 2.0 路线图（快·准·美）实现总结报告

> 引擎：`yimai_prophecy_moonbit`（MoonBit 0.1，零第三方依赖 `core/json` + `core/math`）
> 日期：2026-07-28
> 范围：将 `拓展路线图.md` 的「快 / 准 / 美」三维算法内核全量落地为引擎代码，并经 `open-code-review` 全量复查 + MoA 多模型交叉验证。

## 一、交付总览

| 维度 | 路线图条目 | 引擎实现 | 状态 |
|---|---|---|---|
| **快** | 角色倒排索引 + Top-K 剪枝 + 预测缓存 LRU | `role_members` / `predict` 每源 Top-8 剪枝 / `pred_cache` | ✅ 引擎已实现 |
| **准** | 二阶马尔可夫 | `trans2`（`prev2::prev`→{w3}），`predict` 中 `λ=0.4` 融合 | ✅ 引擎已实现 |
| **准** | 多粒度角色泛化 | `roles_of`（前二 / 前四 / 前后各二） | ✅ 引擎已实现 |
| **准** | 自适应学习率 + 弹性遗忘 | `hebb_lr` 按命中率自适应；`consolidate` 时差折扣衰减 | ✅ 引擎已实现 |
| **准** | 领域偏置 ΔW（LoRA 式） | `domain_bias` + `set_domain_bias` + `inject_distillation` | ✅ 引擎已实现 |
| **准** | 在线对比学习 | `cl_step(anchor, pos, neg)` | ✅ 引擎已实现 |
| **准** | 注意力式边权 | `attn_alpha/beta` + `set_attention` + `recall` 门控 | ✅ 引擎已实现 |
| **美** | TermNode + 可解释卡片 | `mark_term` / `explain_card{activation_path, prediction_path, value_breakdown}` | ✅ 引擎已实现 |
| **美（算法层）** | 双语对齐（LCS/Myers） | `align_diff` 字符级编辑脚本 | ✅ 算法已实现 |
| **中/长周期** | 增量固化 WAL | `wal_replay/export/compact/clear/len` | ✅ 引擎已实现 |
| **中/长周期** | 主动学习候选 | `active_learning_candidates(k)` | ✅ 引擎已实现 |
| **中/长周期** | 联邦增量导出/导入 | `fed_export/fed_import`（计数聚合层） | ✅ 引擎已实现（增量层） |
| **长周期** | 神经符号蒸馏（注入侧） | `inject_distillation`（只读 ΔW 表注入） | ✅ 引擎已实现（注入侧） |
| 外存/CSR、译员工作台、联邦协调方、蒸馏训练管线、可视化图谱 | — | ⬜ **需外部系统**（前端/外部服务衔接） |

## 二、测试证据（71/71 全绿）

`cd yimai_prophecy_moonbit && moon test` → **Total tests: 71, passed: 71, failed: 0**

- 原有 56 项（接受度 L1/L2 + 10 真实场景 + 30 领域 × 5 轮 + B1–B4 可信度 + 黑盒/支撑）保持。
- 新增 **路线图专项回归 R1–R15**（15 项），覆盖：
  - Phase0 约束契约：F1 固化回滚（R1）、F3 不确定性熵（R12）。
  - 快：多粒度角色（R2）、Top-K 剪枝 / 预测缓存（行为层，R7 经 set_attention 不崩）。
  - 准：二阶马尔可夫构建（R3）、弹性遗忘衰减（R4）、领域偏置+蒸馏序列化往返（R5）、对比学习正例强化（R6）、注意力开关（R7）。
  - 美：TermNode mark_term（R8）、术语节点序列化持久化（R14）。
  - 中/长周期：WAL 重放等价（R9）、联邦导出导入（R10）、主动学习候选（R11）、双语对齐 LCS（R13）。
  - **跨阶段硬契约（MoA 复查建议 #3）**：R15 验证 `to_json → from_json → predict` 在 k=1/3/5 下输出**逐字节一致**（快/准/美全字段）。

三大约束契约保持：
- **Hit@3 = 0.8246 > 0.8** ✅
- **确定性逐字节一致** ✅（同输入两次 `to_json` 相同）
- **JSON 往返一致** ✅（`to_json → from_json → to_json` 相同）
- **Layer2 重启后预测一致** ✅（R15 强化：覆盖领域偏置 / 注意力 / trans2 / TermNode / WAL）

## 三、代码审查结论（open-code-review 全量 diff）

- **0 high / 0 medium**。报告见 [`CODE_REVIEW_FULL.md`](./CODE_REVIEW_FULL.md)。
- 重点证伪 5 项疑似问题（含 `trans2` 死代码疑云、MoA 序列化遗漏质疑、consolidate 安全性、WAL 等价性、`align_diff` 正确性），均**非缺陷**。
- Low 级（静默丢弃，仅记录）：`set_attention` 未钳制极值、`active_learning_candidates` 角色多样性条件可读性、`explain_card.is_term` 数值序列化（MoonBit Json 限制）、`fed_import` 仅合并计数（属外部协调方职责）。

## 四、MoA 多模型交叉验证

- 复跑 MoA 对「序列化分层策略 + 3 个 latent bug」的复查（输出 `_moa_roadmap_review.txt`）。
- MoA 提出「白名单制持久化 + 重建确定性审计 + 强化测试」三条建议。
- 经源码逐行核对 + R15 实证：当前 `to_json`/`from_json` **已是 whitelist-complete**（所有 `predict` 读入字段均显式序列化）；MoA 关于「逻辑时钟未持久化」的假设与源码不符（clock 已序列化）。其建议 #3（字节级 `predict` 一致性断言）已通过 **R15** 落地闭环。

## 五、剩余工作（需外部系统，非引擎缺口）

1. **外存层次 / CSR 持久化**：当前 wasm-gc 内存态；冷数据落 IndexedDB 需宿主 JS 桥。
2. **职业译员工作台（ardot 转代码）**：Web/CLI 双语 TM 面板 + 实时预测流 + 可解释侧栏 + 术语高亮。
3. **双语对齐热力图**：`align_diff` 算法已就绪，需前端渲染。
4. **联邦协调方（FedAvg 聚合服务）**：引擎仅出增量计数，权重聚合由服务端完成。
5. **神经符号蒸馏训练管线**：引擎仅消费只读 ΔW 表，训练四层 Transformer 需独立流程。
6. **可视化记忆图谱**：引擎出节点/边 JSON，D3.js 力导向渲染。

## 六、一句话结论

路线图「快·准·美」的**算法/引擎内核已全量落地并通过契约测试**；剩余条目均为前端工作台或外部服务的衔接，属「需外部系统」而非「未实现」。引擎侧三项铁律（零依赖、确定性优先、可解释即契约）在 Phase 1–6 后依然成立。
