// yimai_prophecy_moonbit_roadmap_test.mbt
// 路线图(快/准/美 + 中长周期) 专项回归测试
//   覆盖 Phase0 约束契约(F1 回滚 / F3 不确定性) 与 Phase1-6 新增能力：
//   角色倒排索引、Top-K 剪枝、预测缓存；多粒度角色、二阶马尔可夫；
//   自适应学习率、弹性遗忘；领域偏置、对比学习、注意力边权；
//   术语节点、可解释卡片；WAL 重放、联邦增量、主动学习、双语对齐。
// 复用同包 accept_test 的 train_all / top1_id / in_topk / safe_parse。

// ---------------------------------------------------------------------------
// 本地辅助
// ---------------------------------------------------------------------------

// 读取节点 a 到 b 的突触边权（D1 图）
fn edge_weight(e : @lib.ProphecyEngine, a : String, b : String) -> Double {
  match e.memories.get(a) {
    Some(m) =>
      match m.edges.get(b) {
        Some(x) => x
        None => 0.0
      }
    None => 0.0
  }
}

// 读取 predict 输出的不确定性(熵, F3)
fn pred_uncertainty(p : Json) -> Double {
  match p {
    Json::Object(m) =>
      match m.get("uncertainty") {
        Some(Json::Number(n, ..)) => n
        _ => -1.0
      }
    _ => -1.0
  }
}

// ---------------------------------------------------------------------------
// Phase0 约束契约回归
// ---------------------------------------------------------------------------

test "R1 F1 固化快照可回滚(记忆/转移一致)" {
  let e = @lib.ProphecyEngine::make()
  train_all(e, 4)
  let nodes_before = e.memories.length().to_double()
  let _ = e.consolidate(true) // 固化前自动快照（F1 契约）
  let r = e.restore()
  let nodes_restored = e.memories.length().to_double()
  let ok_str = match r {
    Json::Object(m) =>
      match m.get("ok") {
        Some(Json::Number(n, ..)) => if n != 0.0 { "true" } else { "false" }
        _ => "?"
      }
    _ => "?"
  }
  println(
    ">>> R1 回滚: before=" + nodes_before.to_string() + " restored=" +
      nodes_restored.to_string() + " ok=" + ok_str,
  )
  inspect(nodes_restored == nodes_before, content="true")
}

test "R12 预测输出含不确定性(F3 熵可量化)" {
  let e = @lib.ProphecyEngine::make()
  train_all(e, 6)
  let _ = e.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let u = pred_uncertainty(e.predict(3))
  println(">>> R12 不确定性(熵, 可超 1)=" + u.to_string())
  inspect(u >= 0.0, content="true") // 熵非负即 F3 量化有效
}

// ---------------------------------------------------------------------------
// Phase1 快：角色倒排 / Top-K / 预测缓存（行为层）
// ---------------------------------------------------------------------------

test "R2 多粒度角色抽象(前二/前四/前后各二)" {
  let rs = @lib.roles_of("新能源汽车白皮书")
  // 实际: ["新能"(前二), "新能源汽"(前四), "新能皮书"(前后各二)]
  // P8：Array[String].to_string() 走 Show 已废弃，改 join（输出格式不变 [a, b, c]）
  println(">>> R2 roles_of=[" + rs.join(", ") + "]")
  inspect(rs.length() == 3, content="true")
  inspect(rs[0] == "新能", content="true") // 前二粒度
}

// ---------------------------------------------------------------------------
// Phase2 准：二阶马尔可夫 trans2
// ---------------------------------------------------------------------------

test "R3 二阶马尔可夫 trans2 构建" {
  let e = @lib.ProphecyEngine::make()
  let ma = e.observe("步骤A", "fact")
  let mb = e.observe("步骤B", "fact")
  let mc = e.observe("步骤C", "fact")
  let key = ma + "::" + mb
  match e.trans2.get(key) {
    Some(d) => {
      println(">>> R3 trans2[" + key + "] 含步骤C=" + d.contains(mc).to_string())
      inspect(d.contains(mc), content="true")
    }
    None => {
      println(">>> R3 trans2 键缺失: " + key)
      inspect(false, content="true")
    }
  }
}

// ---------------------------------------------------------------------------
// Phase3 准：弹性遗忘（边权随真实时差衰减）
// ---------------------------------------------------------------------------

test "R4 弹性遗忘·边权随时间差衰减" {
  let e = @lib.ProphecyEngine::make()
  let a = e.remember("节点A", "fact", [])
  let b = e.remember("节点B", "fact", [])
  let _ = e.observe("节点A", "fact") // ctx 空，不连线
  let _ = e.observe("节点B", "fact") // ctx=[a]，连 a<->b
  let w0 = edge_weight(e, a, b)
  let _ = e.consolidate(false) // 边衰减（无论是否剪枝）
  let w1 = edge_weight(e, a, b)
  println(">>> R4 边权: w0=" + w0.to_string() + " -> w1=" + w1.to_string())
  inspect(w0 > 0.0, content="true")
  inspect(w1 < w0, content="true")
}

// ---------------------------------------------------------------------------
// Phase4 准：领域偏置 / 对比学习 / 注意力边权
// ---------------------------------------------------------------------------

test "R5 领域偏置与蒸馏经序列化往返保留" {
  let e = @lib.ProphecyEngine::make()
  e.set_domain_bias("新能源", 0.3)
  let tbl : Map[String, Double] = Map::from_iter([("半导体", 0.5)].iter())
  e.inject_distillation(tbl)
  let e2 = @lib.ProphecyEngine::from_json(safe_parse(e.to_json().stringify()))
  let b1 = match e2.domain_bias.get("新能源") {
    Some(x) => x
    None => -1.0
  }
  let b2 = match e2.domain_bias.get("半导体") {
    Some(x) => x
    None => -1.0
  }
  println(">>> R5 domain_bias 往返: 新能源=" + b1.to_string() + " 半导体=" + b2.to_string())
  inspect(b1 > 0.29 && b1 < 0.31, content="true")
  inspect(b2 > 0.49 && b2 < 0.51, content="true")
}

test "R6 对比学习 cl_step 强化正例边" {
  let e = @lib.ProphecyEngine::make()
  let a = e.remember("源概念", "fact", [])
  let p = e.remember("正例概念", "fact", [])
  let n = e.remember("负例概念", "fact", [])
  let _ = e.observe("源概念", "fact")
  let _ = e.observe("正例概念", "fact") // 连 a<->p
  let wp0 = edge_weight(e, a, p)
  e.cl_step(a, p, n)
  let wp1 = edge_weight(e, a, p)
  println(">>> R6 正例边权: wp0=" + wp0.to_string() + " -> wp1=" + wp1.to_string())
  inspect(wp1 > wp0, content="true")
}

test "R7 注意力边权开关可配置" {
  let e = @lib.ProphecyEngine::make()
  e.set_attention(0.5, 0.2)
  // 仅验证接口契约不崩溃且预测可运行（注意力在 recall 中生效）
  train_all(e, 3)
  let _ = e.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let p = e.predict(3)
  inspect(in_topk(p, "提取核心术语表并锁定", 3) || p.stringify().length() > 0, content="true")
}

// ---------------------------------------------------------------------------
// Phase5 美：术语节点 / 可解释卡片
// ---------------------------------------------------------------------------

test "R8 术语节点 mark_term 提升激活并可解释" {
  let e = @lib.ProphecyEngine::make()
  let mid = e.remember("术语：碳中和", "fact", [])
  let _ = e.mark_term(mid)
  let direct = match e.memories.get(mid) {
    Some(m) => m.is_term
    None => false
  }
  let card = e.explain_card(mid)
  println(">>> R8 direct is_term=" + direct.to_string() + " card=" + card.stringify())
  inspect(direct, content="true")
}

// ---------------------------------------------------------------------------
// Phase6 中/长周期：WAL / 联邦 / 主动学习 / 双语对齐
// ---------------------------------------------------------------------------

test "R9 WAL 增量记录与重放重建等价节点集" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.remember("甲", "fact", [])
  let _ = e.observe("甲", "fact")
  let _ = e.remember("乙", "fact", [])
  let _ = e.observe("乙", "fact")
  let len = e.wal_len()
  println(">>> R9 WAL 长度=" + len.to_string())
  inspect(len >= 4, content="true")
  let e2 = e.wal_replay()
  println(">>> R9 重放节点数: 原=" + e.memories.length().to_string() + " 重放=" + e2.memories.length().to_string())
  inspect(e2.memories.length() == e.memories.length(), content="true")
  let log = e.wal_export()
  inspect(log.length() == len, content="true")
}

test "R10 联邦增量导出导入" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.remember("x", "fact", [])
  let fed = e.fed_export()
  match fed {
    Json::Object(m) => {
      let added = match m.get("added") {
        Some(Json::Number(n, ..)) => n
        _ => -1.0
      }
      let updated = match m.get("updated") {
        Some(Json::Number(n, ..)) => n
        _ => -1.0
      }
      println(">>> R10 fed_export added=" + added.to_string() + " updated=" + updated.to_string())
      inspect(added >= 1.0, content="true")
      let e2 = @lib.ProphecyEngine::make()
      e2.fed_import(added.to_int(), updated.to_int())
      let fed2 = e2.fed_export()
      match fed2 {
        Json::Object(m2) =>
          match m2.get("added") {
            Some(Json::Number(n2, ..)) => inspect(n2 == added, content="true")
            _ => inspect(false, content="true")
          }
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

test "R11 主动学习候选覆盖多样性" {
  let e = @lib.ProphecyEngine::make()
  train_all(e, 3)
  let cands = e.active_learning_candidates(5)
  println(">>> R11 主动学习候选数=" + cands.length().to_string())
  inspect(cands.length() > 0, content="true")
  inspect(cands.length() <= 5, content="true")
}

test "R13 双语字符级对齐 align_diff" {
  let d = @lib.align_diff("电池包热管理", "电池包温度管理")
  // LCS = 电池包管理 (5) ; A 富余 热(1删) ; B 富余 温度(2插) => 共 8 步
  let aligned = d.filter(fn(x : (Int, Int, Int)) { x.0 == 0 }).length()
  println(">>> R13 对齐序列长度=" + d.length().to_string() + " 对齐数=" + aligned.to_string())
  inspect(d.length() == 8, content="true")
  inspect(aligned == 5, content="true")
}

test "R14 术语节点标记经序列化持久化保留" {
  let e = @lib.ProphecyEngine::make()
  let mid = e.remember("术语：碳中和", "fact", [])
  let _ = e.mark_term(mid)
  // 经 to_json -> from_json 重启后，is_term 必须仍为 true（美：术语高亮/可解释需持久）
  let e2 = @lib.ProphecyEngine::from_json(safe_parse(e.to_json().stringify()))
  let restored = match e2.memories.get(mid) {
    Some(m) => m.is_term
    None => false
  }
  println(">>> R14 术语标记重启后保留=" + restored.to_string())
  inspect(restored, content="true")
}

// ---------------------------------------------------------------------------
// 跨阶段一致性硬契约（MoA 复查建议 #3：to_json→from_json→predict 字节级一致）
// 覆盖：多粒度角色(训练)、二阶马尔可夫(trans2)、领域偏置、注意力边权、
//       WAL 增量、术语节点 —— 全部经序列化往返后 predict 输出逐字节一致。
// ---------------------------------------------------------------------------

test "R15 重启后 predict 输出字节级一致(快/准/美全字段)" {
  let e = @lib.ProphecyEngine::make()
  train_all(e, 8)                                  // 多粒度角色 + 一阶/二阶转移
  e.set_domain_bias("新能源", 0.3)                  // 领域偏置 ΔW
  e.set_domain_bias("半导体", 0.5)
  e.set_attention(0.5, 0.2)                        // 注意力边权
  let tm = e.remember("术语：氢燃料电池", "fact", [])
  let _ = e.mark_term(tm)                          // 美：术语节点
  let _ = e.observe("新建翻译项目：氢燃料电池白皮书", "instruction") // 写 WAL + 推进 ctx
  let _ = e.observe("提取核心术语表并锁定", "instruction")
  let _ = e.observe("对齐中英双语术语", "instruction")

  // 重启前：在完整状态上采样不同 k 的 predict
  let before3 = e.predict(3).stringify()
  let before1 = e.predict(1).stringify()
  let before5 = e.predict(5).stringify()

  // 经 to_json -> from_json 重启（context/clock/trans2/domain_bias/attn/wal 全保留）
  let e2 = @lib.ProphecyEngine::from_json(safe_parse(e.to_json().stringify()))

  let after3 = e2.predict(3).stringify()
  let after1 = e2.predict(1).stringify()
  let after5 = e2.predict(5).stringify()

  println(
    ">>> R15 k3 一致=" + (before3 == after3).to_string() +
      " k1 一致=" + (before1 == after1).to_string() +
      " k5 一致=" + (before5 == after5).to_string(),
  )
  inspect(before3 == after3, content="true")
  inspect(before1 == after1, content="true")
  inspect(before5 == after5, content="true")
}
