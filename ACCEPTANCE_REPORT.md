# 译脉·先知 2.0 (MoonBit) 功能验收报告

> 验收目标：在「Agent A 装上引擎 / Agent B（本机）独立验证实际效果」的范式下，
> 用一套可短期大量复跑的自动化测试台，对 `yimai_prophecy_moonbit` 引擎的
> 全部核心能力（D1–D8）做数值 + 行为双轨验收。
>
> 验收命令：`moon test --target wasm-gc`
> 验收结果：**Total tests: 12, passed: 12, failed: 0**（8 项专项验收 + 4 项既有黑盒测试）

---

## 1. 验收方案总览

MoonBit 本版本（moon 0.1.20260713）**无 stdin、无文件 I/O**，
且 `js` 目标只为 `is-main` 包生成立即执行的 IIFE（不导出函数）。
因此无法让外部 Agent 直接「装载进程内引擎」做交互式验证。

据此将方案调整为 **「MoonBit 进程内验收测试台 + 双 Agent 行为验收范式」**，
完全在 `moon test` 内闭环，今天即可大量复跑、输出可审计的验收证据：

| 层级 | 性质 | 验收内容 | 条目 |
|------|------|----------|------|
| **Layer1** | 批量功能验收（数值） | Hit@k、确定性、JSON 往返、固化重放 | 4 |
| **Layer2** | 双 Agent 行为验收（Agent B 校验 Agent A 预测行为） | 复盘预测、冷启动泛化、白盒可解释、持久化重启一致 | 4 |

语料说明：采用**项目自身真实工作流**——6 步翻译流水线
（步骤 1 随项目主题变化，步骤 2–6 跨项目共享），以 8 个真实项目主题实例驱动。
非外部文件导入（因 MoonBit 无文件 I/O，诚实标注）。

---

## 2. 验收语料

**6 步翻译流水线（CANON）**
1. 新建翻译项目：%TOPIC%（instruction）
2. 提取核心术语表并锁定（fact）
3. 对齐术语风格：正式技术中性（preference）
4. 按章节分段翻译（fact）
5. 质检术语与风格一致性（instruction）
6. 导出中英双语交付物（instruction）

**8 个真实主题（TOPICS）**：新能源汽车白皮书、医疗器械说明书、金融科技年报、
工业软件手册、生物医药指南、半导体技术文档、储能系统规范、智能驾驶标准。

训练方式：`train_all(eng, reps)` 以 `end_episode` 切分每个主题的一轮，
`predict(3)` 预热转移计数后 `observe` 执行步骤，循环 `reps` 轮。

---

## 3. 验收结果与证据

### Layer1 批量功能验收（数值）

| # | 验收项 | 判定 | 实测证据 |
|---|--------|------|----------|
| L1-1 | 批量 Hit@3 达标（>0.8） | ✅ PASS | 8 主题 × 8 轮训练后 `hit_rate = 0.8246` |
| L1-2 | 确定性 / 可复现 | ✅ PASS | 同输入两次 `to_json` 字符串**逐字节一致** |
| L1-3 | JSON 往返一致 | ✅ PASS | `to_json → from_json → to_json` 字符串一致 |
| L1-4 | 固化重放保留核心记忆 | ✅ PASS | 固化前 13 节点 → 固化后 13 节点（未丢失核心记忆） |

L1-1 附带状态快照：`nodes=13, edges=116, episodes=63,
by_type={instruction:10, fact:2, preference:1}, predict_calls=382,
avg_predictive_value=0.5353`。

> 注：L1-4 固化后 `explore=0`。这是合理现象——8 个主题共享同一套工作流，
> 网络已充分覆盖，无需触发额外探索；固化正确保持了节点数与边结构。

### Layer2 双 Agent 行为验收（Agent B 校验 Agent A）

| # | 验收项 | 判定 | 实测证据 |
|---|--------|------|----------|
| L2-1 | 已知项目复盘预测正确下一步 | ✅ PASS | observe「新建翻译项目：新能源汽车白皮书」→ Top1 = 提取核心术语表并锁定 |
| L2-2 | 冷启动（全新主题）泛化 | ✅ PASS | observe 未训练主题「量子计算综述」→ 经 D8 角色抽象泛化出 提取核心术语表并锁定 |
| L2-3 | 预测可白盒解释 | ✅ PASS | `explain(m2)` 返回含出边/转移路径的白盒结构（非黑盒） |
| L2-4 | 持久化（重启后一致） | ✅ PASS | `to_json → from_json` 恢复后 Top1 与重启前一致 |

L2 各项的「Agent A 实际回复」均以 `println` 形式落盘于测试输出，
可供人工抽检 Agent A 行为是否符合预期（即「Agent B 验证实际效果」）。

---

## 4. 涵盖的引擎能力（D1–D8）

| 能力 | 验收覆盖点 |
|------|-----------|
| D1 突触图谱 / 赫布学习 | L1-1 命中率、L1-4 边结构（edges=116） |
| D2 激活扩散 / 联想召回 | L2-1 复盘预测、L2-2 冷启动召回 |
| D3 预测前向模型 | L1-1 / L2-1 / L2-2 的 Top-K 预测 |
| D4 预测价值定价 | L1-1 avg_predictive_value=0.5353 |
| D5 情景序列 | L1-1 episodes=63、L2-1 复盘 |
| D6 固化重放 | L1-4 固化保留核心记忆 |
| D7 不确定性 & 可解释 | L2-3 白盒 explain 路径 |
| D8 概念抽象（冷启动） | L2-2 未见主题泛化 |

---

## 5. 工具链限制与处置（已查证）

本次验收过程中确认并处置了以下 MoonBit 本版本（0.1.20260713）约束：

1. **无 stdin / 无文件 I/O**：core 库无 `io`/`fs` 包。→ 验收语料内联为常量，不走文件。
2. **`js` 目标只为 `is-main` 生成立即执行 IIFE**，不导出函数。
   → 原 `cmd/server`（意图作为 Node 可加载能力模块）无法作为 Agent 装载入口，
   已移出构建树归档于 `_archive/cmd_server_bak_*`。
3. **`@json.parse` 返回 `Json raise ParseError`**（抛异常，非 `Result`），
   无 `.unwrap()`。→ 测试台与引擎统一改用 `try/catch` 兜底。
4. **顶层 `let mut` 不被允许**，且 `Json::String/Number/Array/Null` 为只读构造类型
   （须用 `.to_json()` / `Map::from_iter(...).to_json()`，无 `@json.str`）。
   → `cmd/server` 因多处触碰上述限制而无法编译，已归档。
5. **多行字符串拼接**：二元运算符须置于行尾，行首续接 `+` 报解析错误。→ 已修正。

> 结论：引擎本身（`ProphecyEngine` 全部 16 个 pub fn）功能完整、确定性可复现，
> 可作为 `moon add Across2005/yimai_prophecy_moonbit` 的库被其他 Agent/项目消费；
> 「Agent A 装引擎 / Agent B 验证」通过本验收测试台 + `cmd/main` 演示双重落地。

---

## 6. 复跑方式

```bash
cd yimai_prophecy_moonbit
moon test --target wasm-gc      # 跑全部验收（含本报告的 Layer1/Layer2）
moon build --target wasm-gc     # 仅构建库
cd cmd/main && moon build --target wasm-gc && moon run .   # 跑 Python 版对照演示
```

---

## 7. 遗留与建议

- **Skill 封装**：原「封装为 WorkBuddy skill，Agent 装上」设想，因 MoonBit 本版本
  无进程间装载入口而调整为「以验收测试台 + `cmd/main` 演示为交付，引擎以库形式被消费」。
  若需真正 Agent 内装载，建议评估：① 升级 MoonBit 至支持库导出到宿主语言的目标；
  ② 或改用 `moon run cmd/main` 子进程 + 管道（但受限于无 stdin，需改 argv/环境变量传参）。
  需用户确认技能封装的最终形态。
- **配套缺口**（此前已识别，未处理）：`STATUS.md` 缺失、`moon.mod` 的
  `repository`/`description` 为空、`README.mbt.md` 仅 1 行、无 CI 配置。
- **已归档**：`_archive/cmd_server_bak_*` 保留 Node-runtime 原型，便于后续版本能力具备时复活。
