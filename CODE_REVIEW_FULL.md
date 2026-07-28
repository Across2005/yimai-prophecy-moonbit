# Code Review Results — 全量 diff（Phase 1–6 路线图「快·准·美」实现）

> 审查模式：工作区模式（全量 diff）
> 审查对象：`engine.mbt` (+719 行) · `util.mbt` (+85 行)
> 工具：open-code-review（确定性工程 × Agent 混合，复刻 alibaba/open-code-review）
> 约束：仅报告「仅凭 diff / 已读上下文即可确认为真问题」的意见；疑似项放行（高精度优先）

## 结果概览

**Files reviewed**: 2
**Issues found**: **0 high priority / 0 medium priority**

（历史 3 个 latent bug —— `role_of` 短串崩溃、WAL 分隔符与参数错位、`node_to_json` 漏持久化 `last_active`/`is_term` —— 已在 prior session 修复，并由 R1–R15 回归覆盖。）

### High Priority
（无）

### Medium Priority
（无）

### 分类统计
- bug: 0 · security: 0 · performance: 0 · maintainability: 0 · test: 0 · style: 0 · documentation: 0 · other: 0

---

## 重点核查项（逐行证伪，结论：非缺陷）

1. **二阶马尔可夫 `trans2` 是否真正接入预测（疑似死代码）**
   初看 `trans2` 仅在 `observe` 写入（`engine.mbt:919` `inc_trans(self.trans2, prev2 + "::" + prev, mid)`），易误判为未消费。经查 `predict`（`engine.mbt:774–800`）：当 `context.length() >= 2` 时以 `key2 = p2 + "::" + p1` 查 `trans2`，叠加 `lam = 0.4 · P(w3|w1,w2)` 到得分。写入键 `prev2::prev`（919）与读取键 `p2::p1`（779）**完全一致** → 端到端正确，非死代码。

2. **序列化分层是否遗漏 `predict` 依赖状态（MoA 复查质疑）**
   逐字段核对 `to_json` / `from_json`（`engine.mbt:1584–1700`）：`context` / `explore` / `memories`(含 `last_active`、`is_term`、`predict_count`) / `role_trans` / `trans2` / `domain_bias` / `attn_*` / `clock` / `meta_hits` / `wal_log` / `snapshot·snap_trans·snap_role` 三元组 **全部持久化**。
   新增回归 **R15** 实证：在「多粒度角色 + 二阶马尔可夫 + 领域偏置 + 注意力 + WAL + TermNode」全字段场景下，`to_json → from_json → predict` 于 `k=1/3/5` 输出 **逐字节一致**。
   → MoA 关于「逻辑时钟未持久化」的假设与源码不符（`clock` 已序列化，`engine.mbt:1605/1646`）。

3. **`consolidate` 弹性遗忘 + 自适应 LR 的确定性与安全性**
   时差折扣 `exp(-gap/REC_TAU)` 与命中率驱动的 `hebb_lr` 均运行于纯确定路径，不引入 RNG。剪枝仅在 `predictive_value < 0.08 && use_count <= 1 && 不在 context` 时移除节点，并通过 `ids` 快照数组遍历（避免迭代期删键）。逻辑正确，无并发/迭代风险（引擎单线程、无共享可变状态跨越调用边界）。

4. **WAL 重放等价性**
   分隔符常量 `WAL_SEP = "\u0001"` 统一 `wal_append` 与 `wal_replay` 解析；记录格式 `op␁mid␁text␁mtype` 与解析 `parts[2]=text, parts[3]=mtype` 对齐（prior session 修复项）。R9 验证重放后节点集与重放前等价。

5. **`align_diff` 字符级 LCS 编辑脚本正确性**
   标准 DP 填表 + 回溯，边界 `a[i]==b[k]` 对齐、`dp[i+1][k] >= dp[i][k+1]` 删/`else` 插，尾部补齐剩余字符。R13 验证（`电池包热管理` vs `电池包温度管理` → 长度 8、对齐 5）。无越界。

---

## Low（按 open-code-review 纪律静默丢弃，仅记录供后续演进）

- **`set_attention` 未钳制 `alpha/beta`**：极端值下 `exp(α·sim + β·rmatch)` 可能溢出 `inf/NaN`（仅影响扩散权重，命中核算不受影响，且 `NaN` 比较恒假会回退 `cur`）。属调用方责任，非缺陷。
- **`active_learning_candidates` 角色多样性条件语义略隐晦**：`seen_role.length() < k` 在角色数已达 k 后停止跳过同角色候选，最终可填满 k；功能正确，仅可读性可优化。
- **`explain_card.is_term` 序列化形态**：经 `Bool::to_json()` 落为数值（MoonBit `Json` 无原生布尔构造），消费方需按数值解读；R8 以结构体直读 `is_term` 校验，不受此影响。可在文档中注明。
- **`fed_import` 仅合并增量计数**：权重级 FedAvg 聚合由协调方完成 —— 属路线图「需外部服务」项，非引擎缺陷。

---

## 结论

Phase 1–6 全量代码审查 **无高/中危问题**。先前会话发现的 3 个 latent bug 已修复并回归覆盖。三大约束契约（**Hit@3 > 0.8** / **确定性逐字节一致** / **JSON 往返一致**）在全部 Phase 后保持；**Layer2 重启后预测一致**经 R15 进一步加固（覆盖快/准/美全字段）。

建议下一阶段独立推进「需外部系统」项：外存/CSR、ardot 译员工作台、联邦协调方、神经符号蒸馏训练管线、可视化记忆图谱（数据接口均已可消费）。
