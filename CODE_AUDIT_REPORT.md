# 译脉·先知 2.0（MoonBit）代码审计报告

> 三技能联合审查：`code-bug-analyzer`（四维风险分析） + `open-code-review`（结构化审查） + `MoA`（多模型综合）
> 审查范围：`engine.mbt` / `util.mbt` / `cmd/main/main.mbt`（核心源码，不含 `_build` 生成物）
> 审查日期：2026-07-28 ｜ 语言：MoonBit 0.1（零第三方依赖）

---

## 一、执行概要

| 维度 | 结论 |
|------|------|
| 安全漏洞 | **未发现**（纯内存引擎，JSON 解析全部字段兜底，无注入/SSRF/执行路径） |
| 高危正确性缺陷 | **3 项**（F1 回滚不完整 / F2 持久化丢集 / F3 不确定性度量失真） |
| 低危 / 技术债 | 4 项（F4 性能 / F5 时钟 / F6 重复代码） |
| MoA 多模型判定 | F1/F2/F3 升为高危、F4 降为低，与源码逐行核对**一致** |
| MoA 臆测否决 | 4 处（CJK split / clear() / softmax溢出 / from_json panic）已查证剔除 |

**核心结论**：代码库功能基本正确（56/56 测试通过、有 to_json/from_json 往返测试），但**核心不变量已破损**——`restore` 回滚与 `to_json` 持久化均不完整，且 `predict` 的不确定性度量不符合 D7 设计契约。建议按「先准（P0）→ 再快（P1）→ 后美（P2）」修复。

---

## 二、第一部分 · code-bug-analyzer 四维分析

**语言识别**：MoonBit（置信度 99%，`.mbt` 扩展名 + `pub struct`/`fn`/`@math` 语法）
**代码类型**：工程代码（内存态预测记忆引擎，含 JSON 序列化、状态机、统计指标）
**整体评价**：原生 MoonBit 实现、常量按 D1–D8 规范定义，逻辑自洽；短板集中在**状态一致性与度量正确性**。

### 四维发现

#### ① 静态 Bug 分析
| 发现 | 严重度 | 位置 | 说明 |
|------|--------|------|------|
| F1 `restore` 仅回滚 `memories` | 🔴 高 | `engine.mbt:770, 787-796, 858` | `consolidate` 会衰减/剪枝 `transitions`（第787-796行，且**与 prune 参数无关，非剪枝也会执行**），但快照只捕获 `memories`（第770行），`restore` 仅 `self.memories = s`（第858行）。回滚后转移模型仍停留在固化后状态，`predict` 行为与快照时刻不一致。 |
| F2 `to_json` 漏序列化 `cur_episode`/`last_pred` | 🔴 高 | `engine.mbt:1004-1027` | 序列化含 memories/transitions/context/clock/meta_hits 等，但**不含运行中未完成的一集 `cur_episode`**，也不含 `last_pred`。`from_json` 同样不恢复。重启后在线学习连续性中断。 |

#### ② 安全审计
| 发现 | 严重度 | 说明 |
|------|--------|------|
| 无安全漏洞 | 🟢 无 | 纯内存引擎；`from_json` 经 `get_str/get_num/get_obj` 全部字段兜底（缺省 `""` / `0.0` / 空对象），缺键不 panic；无文件/网络/SQL/exec 路径。**这是优点，如实记录。** |

#### ③ 逻辑正确性
| 发现 | 严重度 | 位置 | 说明 |
|------|--------|------|------|
| F3 不确定性仅对 top-k 求熵 | 🔴 高 | `engine.mbt:622-626` | 第618-619行已对**全部 dst** 归一化（`znorm`），但第622-626行熵只累加 `ranked[0..lim]`（top-k）。系统性低估不确定性，违反 D7「整体分布熵」契约；下游置信度判断会被误导。 |
| F5 `observe` 时钟双重自增 | 🟢 低 | `engine.mbt:657, 292` | `observe` 先 `clock+1`，再调 `remember` 又 `clock+1`，每次 observe 时钟 +2。相对顺序不变，但 `REC_TAU` 时效尺度等效减半，仅影响衰减速度。 |

#### ④ 代码质量
| 发现 | 严重度 | 位置 | 说明 |
|------|--------|------|------|
| F4 全量线性扫描 O(n²) | 🟡 低（技术债） | `engine.mbt:296-302, 384-484, 772-796` | `remember` 每次与全部记忆求余弦、`recall`/`consolidate` 线性扫描，无向量索引。规模 <10⁴ 可接受，属中期扩展债务。 |
| F6 JSON 辅助函数重复 | 🟢 低 | `engine.mbt:177-308` vs `cmd/main/main.mbt:10-41` | `engine.mbt` 的 `get_str/get_num/get_obj/obj` 与 `main.mbt` 的 `jstr/jnum/jarr` 功能重叠，可抽取为共享模块。 |

---

## 三、第二部分 · open-code-review 结构化审查

**模式**：全量扫描（scan），`.mbt` 不在语言映射表 → 套用 `default.md` 清单（Correctness / Security / Performance / Maintainability / Test Coverage）。
**过滤纪律**：每条仅保留「凭已读源码即可确证为真」的意见；无法证实的疑似项**放行不报**（高精度优先）。

### Findings（分类 / 严重度）

- **`engine.mbt:858` — restore 回滚不变量破坏** ｜ category: `bug` ｜ severity: `high`
  > 证据：`consolidate` 改写 `transitions`（衰减 + 阈值剪枝），而 `snapshot` 仅含 `memories`，`restore` 不恢复 `transitions`。回滚后预测模型与固化前不一致。
  > Recommendation：快照同时捕获 `transitions` 与 `role_trans`，`restore` 一并回写（见第四部分修复代码 F1）。

- **`engine.mbt:1004-1027` — 持久化丢失未结束的 episode** ｜ category: `bug` ｜ severity: `high`
  > 证据：`to_json` 无 `cur_episode` 字段，`from_json` 不恢复。往返一致性测试（accept_test:163-177）因该字段本就不在 JSON 中而「假通过」，无法暴露此缺陷。
  > Recommendation：补序列化 `cur_episode` 与 `last_pred`（见 F2 修复代码）。

- **`engine.mbt:622-626` — 不确定性度量与设计契约不符** ｜ category: `bug` ｜ severity: `high`
  > 证据：概率已对全量 dst 归一化，熵却只覆盖 top-k，系统性低估。
  > Recommendation：对全量归一化分布求熵（见 F3 修复代码）。

- **`engine.mbt:770,787-796` — consolidate 无 dry_run / 审计日志** ｜ category: `maintainability` ｜ severity: `low`
  > 固化（尤其 prune）为不可逆状态变更，建议增加 `dry_run` 预览与剪枝规模日志。

### 分类统计
- bug: 3（F1/F2/F3，均 high）
- security: 0
- performance: 1（F4，low）
- maintainability: 2（consolidate 日志、F6 重复代码，均 low）
- test: 1（见第四部分盲区）
- style / documentation / other: 0

---

## 四、第三部分 · MoA 多模型综合 + 查证复核

**MoA 配置**：参考模型 `deepseek-v4-flash-free` + `nemotron-3-ultra-free`，聚合 `deepseek-v4-flash-free`，单轮（`-r 1`）。运行结果：deepseek 单模型 90s 读超时（已记为 failed_reference），nemotron 成功，满足 `min-success=1`，结果落盘 `_moa_audit_result.json`。

### 4.1 采纳的 MoA 判定（与源码逐行核对一致 ✅）

| 编号 | MoA 复核严重度 | 核对结论 |
|------|----------------|----------|
| F1 | 高（原中） | ✅ 一致：`consolidate` 改 `transitions`、快照只含 `memories`、`restore` 只回 `memories` —— 源码确证。 |
| F2 | 高（原中） | ✅ 一致：`to_json` 无 `cur_episode`、`from_json` 不恢复 —— 源码确证。 |
| F3 | 高（原中） | ✅ 一致：熵仅对 top-k，归一化却覆盖全量 —— 源码确证。 |
| F4 | 低（原中低） | ✅ 合理降级：当前规模下非瓶颈，标记为技术债。 |
| F5 / F6 | 维持低 | ✅ 一致。 |

**MoA 额外盲区补充（已核实采纳）**：
- 🔸 **并发安全**：全部字段 `mut`、无锁。当前 MoonBit 单线程安全；若未来接 WASM 多线程 / FFI，必现数据竞争。→ 建议文档标注「非线程安全」+ 中期 Actor/RwLock 封装。
- 🔸 **测试覆盖盲区**：缺「回滚一致性」「对抗 JSON」「大规模性能」「分词边界」「consolidate 软/硬对比」测试。
- 🔸 **JSON 无 schema 版本字段**：格式变更时旧 JSON 会被静默误解析（这是 MoA 关于 `from_json` 的唯一有效点，其「panic」断言已否决，见下）。
- 🔸 **`predict` 空分支 `uncertainty=0.0` 语义偏差**：无预测时应为「最大不确定」而非「完全确定」。

### 4.2 ⚠️ 已查证否决的 MoA 臆测（Hallucination，必须剔除）

| MoA 声称 | 实际源码 | 裁决 |
|----------|----------|------|
| tokenize「仅 `str.split(" ")`」，CJK 退化为整句单 token | `util.mbt:53-93` `yimai_tokenize` 已做 **CJK 单字 + 相邻二元组**切分，且 `role_of` 取前 4 字做角色键 | ❌ **否决**：分词器已是 CJK 感知，不存在该缺陷 |
| `consolidate` 用 `transitions.clear()`「直接抹除转移」 | `engine.mbt:787-796` 是带 `nc >= 0.5` 阈值的**过滤**（保留衰减后仍 ≥0.5 的转移），无 `clear()` | ❌ **否决**：属模型凭空捏造 API |
| `softmax` 未减 `max_logit` 致 `exp` 溢出 | `predict` 无 softmax，归一化用 `znorm` 且已 `if z==0.0 {1.0}` 防零 | ❌ **否决**：源码无 softmax |
| `from_json` 缺键/类型不匹配时 panic | `get_str/get_num/get_obj/get_arr_j` 全部优雅兜底（缺省 `""`/`0.0`/空对象） | ❌ **否决**：解析是防御性的，不 panic |

> 教训：MoA 参考模型**未持有源码**，对未提供的实现细节会按「通用 MoonBit/Python 模板」脑补。凡涉具体 API/行号的主张，必须回源码证伪——这正是 open-code-review 的「宁可漏报、不可误报」纪律。

---

## 五、第四部分 · 整合修复路线图（按 快 / 准 / 美）

### 🔴 P0 ·「准」—— 本 Sprint 强制完成（修复 F1/F2/F3）

| 任务 | 投入 | 收益 |
|------|------|------|
| F1 完整快照 + 事务式 `restore` | ~0.5 天 | 封杀核心回滚不变量破损 |
| F2 `cur_episode`/`last_pred` 序列化补齐 | ~0.3 天 | 修复持久化「假通过」，支持可靠重启 |
| F3 全量分布熵修正 | ~0.2 天 | 不确定性度量符合 D7 契约 |
| **最高杠杆单项**：**F1 完整快照 + 事务式 restore**（一次修复覆盖回滚一致性，为检查点/灾备奠基） |

### 🟡 P1 ·「快」—— 下一里程碑
- 分词器抽象化（注入 `tokenizer` 接口，默认保留现有 CJK bigram，预留 `unicode-segmentation` 接入点）
- ANN 索引骨架（纯 MoonBit 球树/倒排，`remember`/`recall` 走索引，O(n²)→O(log n)）

### 🟢 P2 ·「美」—— 持续改进
- 提取公用 JSON 辅助函数（F6）
- 统一 `clock` 推进点（F5，observe 内只增一次）
- 并发安全封装（RwLock / Actor）
- 补回滚一致性 / 对抗 JSON / 混沌测试

---

## 六、附：可复制修复代码（P0）

> 以下为最小正确修复，建议先纳入测试再合入；**未自动修改源文件**，待你确认后应用。

### F1 — 完整快照 + 事务式 restore

在 `ProphecyEngine` 结构体中新增两个快照字段（与 `snapshot` 配套）：
```moonbit
mut snap_trans : Option[Map[String, Map[String, Double]]]   // 固化前转移模型快照
mut snap_role : Option[Map[String, Map[String, Double]]]    // 固化前角色转移快照
```
`make()` 中初始化：`snap_trans: None, snap_role: None`。

新增深拷贝辅助（与 `copy_memories` 并列）：
```moonbit
fn copy_trans(t : Map[String, Map[String, Double]]) -> Map[String, Map[String, Double]] {
  let out : Map[String, Map[String, Double]] =
    Map::from_iter(([] : Array[(String, Map[String, Double])]).iter())
  for a, inner in t.iter2() {
    let c : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
    for b, w in inner.iter2() { c.set(b, w) }
    out.set(a, c)
  }
  out
}
```

`consolidate` 第 0 步改为同时快照转移模型：
```moonbit
// 0. 约束契约：固化前对记忆 + 转移模型做快照，支持完整回滚
self.snapshot = Some(copy_memories(self.memories))
self.snap_trans = Some(copy_trans(self.transitions))
self.snap_role = Some(copy_trans(self.role_trans))
```

`restore` 改为回写全部三份状态：
```moonbit
pub fn ProphecyEngine::restore(self : ProphecyEngine) -> Json {
  match (self.snapshot, self.snap_trans, self.snap_role) {
    (Some(s), Some(st), Some(sr)) => {
      self.memories = s
      self.transitions = st
      self.role_trans = sr
      self.snapshot = None
      self.snap_trans = None
      self.snap_role = None
      obj([("ok", true.to_json()), ("nodes", num_json(self.memories.length().to_double()))])
    }
    _ => obj([("ok", false.to_json()), ("reason", str_json("no complete snapshot"))])
  }
}
```

### F2 — 补齐 `cur_episode` / `last_pred` 序列化

`to_json` 增加两项（建议放在 `"context"` 附近）：
```moonbit
("cur_episode", arr_json(self.cur_episode.map(fn(s) { str_json(s) }))),
("last_pred", arr_json(self.last_pred.map(fn(s) { str_json(s) }))),
```
`from_json` 末尾补充恢复：
```moonbit
e.cur_episode = get_str_arr(data, "cur_episode")
e.last_pred = get_str_arr(data, "last_pred")
```

### F3 — 基于全量分布求熵

将 `predict` 第 622-626 行的熵循环改为遍历**全部归一化后的 dst**（而非仅 top-k）：
```moonbit
// D7 不确定性：对全部 dst 的归一化分布求熵（符合「整体分布熵」契约）
let mut entropy = 0.0
let dkeys : Array[String] = []
for d, _ in score.iter2() { dkeys.push(d) }
for d in dkeys {
  let p = match score.get(d) { Some(x) => x; None => 0.0 }
  if p > 0.0 {
    entropy = entropy - p * @math.ln(p)
  }
}
```

---

## 七、验证建议（落修复前的回归护栏）

1. **新增回滚一致性测试**：`make → observe×N → consolidate(true) → 记录 predict 分布 → restore → 断言 predict 分布与固化前一致`（直接封杀 F1 回归）。
2. **新增持久化测试**：`to_json → from_json` 后断言 `cur_episode`/`last_pred`/`transitions` 全等（封杀 F2，并暴露原「假通过」）。
3. **新增熵契约测试**：构造已知分布，断言 `uncertainty` 等于全量熵（封杀 F3）。

---

### 附录：本次审查产物
- `_moa_audit_prompt.txt` — 送 MoA 的审计提示词
- `_moa_audit_result.json` — MoA 多模型原始综合结果（含已否决的臆测，供对照）
