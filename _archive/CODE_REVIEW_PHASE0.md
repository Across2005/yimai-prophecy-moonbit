# Code Review —— `engine.mbt`（Phase 0：F1 / F2 / F3 正确性修复）

> 审查技能：`open-code-review`（工作区模式：git diff 已暂存+未暂存 + 未跟踪文件筛选）
> 审查文件：`engine.mbt`（唯一源码变更，本次 +46 / -4，单文件 < 50 行，不触发计划阶段）
> 业务背景：译脉·先知 2.0 PMN 引擎（MoonBit，零第三方依赖）。本次变更为 P0 正确性修复：
> - **F1**：固化前须对 `memories` + `transitions` + `role_trans` 三者一致快照，`restore()` 须回滚三者；
> - **F2**：`to_json` / `from_json` 须序列化并恢复 `cur_episode` / `last_pred`；
> - **F3**：`predict` 不确定性熵须基于**全量归一化分布**（原实现仅取 Top-K）。

---

## 审查结果

**Reviewed files**: 1
**Issues found**: 0 high / 2 medium / 0 low

`make` 字段新增 `mut`（与既有 `memories` 一致）、`copy_trans` 深拷贝、`consolidate` 三快照、`restore` 三回滚、熵循环改 `ranked.length()` 并加 `p>0` 守卫——逻辑均正确，未引入编译/运行期缺陷。
**验证**：`moon build` 通过；`moon test` **56/56 全绿**（Hit@3=0.8246、确定性逐字节一致、to_json→from_json→to_json 往返一致三项硬契约均保持）。

### High Priority
无。

### Medium Priority

- **`engine.mbt` `to_json`(原 L1061) / `from_json`(原 L1099-1112) — 快照三元组跨（反）序列化不对称** *(已修复并验证)*
  原 `to_json`/`from_json` 序列化并恢复了 `snapshot`（memories 快照），但**未**序列化 `snap_trans` / `snap_role`。
  后果：若在「固化快照待回滚」状态下序列化引擎（此时 `snapshot=Some`），重载后 `restore()` 会回滚 memories 却**不**回滚 `transitions`/`role_trans` —— 重新引入 F1 同类的「部分回滚」不一致（跨会话路径）。
  > Fix applied（方案 a，保留跨会话回滚能力）：新增 `trans_map_to_json` / `json_to_trans_map` 两个辅助，`to_json` 增加 `snap_trans`/`snap_role` 字段、`from_json` 对应恢复。修复后 `moon test` 仍 56/56 绿（字节一致性与往返契约保持）。

- **`engine.mbt`（测试覆盖）— F1 / F3 缺少针对性回归测试**
  F2（`cur_episode`/`last_pred` 往返）已被现有「to_json→from_json→to_json 字节一致」测试间接覆盖；但：
  - **F1**：无断言验证 `restore()` 回滚 `transitions`+`role_trans`（现有测试只校验节点数，不校验转移表回滚）；若将来有人把 `restore` 改回「仅回滚 memories」，测试仍会绿——缺陷无法被守卫。
  - **F3**：无断言验证熵基于**全量**分布（多峰时的不确定性应高于旧 Top-K-only 实现）。
  > Recommendation（建议纳入路线图 #22 测试阶段）：
  > 1. consolidate 前深拷贝 `transitions`/`role_trans` → consolidate（使转移表衰减/剪枝）→ `restore()` → 断言二者与快照一致；
  > 2. 构造多峰分布，断言 `uncertainty` 高于旧实现 Top-K-only 给出的值。

### 分类统计
- bug: 1（Medium，一致性，已修复）· test: 1（Medium）· security: 0 · performance: 0 · maintainability: 0 · style: 0 · documentation: 0 · other: 0

---

## 结论
Phase 0 三处正确性修复逻辑正确、构建与全量测试均通过；审查发现 1 个真实一致性缺陷（快照三元组跨会话不对称），已就近补全修复并复测通过；另 1 个测试覆盖建议留作路线图测试阶段（#22）落实。无高风险/安全问题。
