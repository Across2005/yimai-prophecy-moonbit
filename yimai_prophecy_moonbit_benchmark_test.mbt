// yimai_prophecy_moonbit_benchmark_test.mbt
// 严格基准测试台（可信度加固）：为 Hit@3 提供【基线对照】与【留出集泛化】证据。
//
// 动机：既有验收给出 Hit@3=0.8246，但缺两类关键证据——
//   (1) 没有基线：0.8246 相对"随机猜/频率先验"到底强多少？
//   (2) 训练即测试（in-sample）：缺少 train/test 划分下的泛化数字。
// 本文件用与 accept_test 完全相同的 6 步工作流语料（canon/topics，同包共享），
// 直接在同一数据流上跑出可复现、可审计的对照数字，回应上述两点。
//
// 复用同包常量/辅助：canon、topics、in_topk（定义于 accept_test.mbt）。

// 生成一条按 train_all 顺序展开的观察文本流（用于基线离线统计，语义与引擎在线训练一致）
fn bench_stream(reps : Int) -> Array[String] {
  let out : Array[String] = []
  for _r = 0; _r < reps; _r = _r + 1 {
    for topic in topics {
      for i = 0; i < canon.length(); i = i + 1 {
        out.push(canon[i].0.replace_all(old="%TOPIC%", new=topic))
      }
    }
  }
  out
}

// 统计每个文本出现次数
fn bench_freq(stream : Array[String]) -> Map[String, Int] {
  let c : Map[String, Int] = Map::from_iter(([] : Array[(String, Int)]).iter())
  for t in stream {
    let v = match c.get(t) { Some(x) => x; None => 0 }
    c.set(t, v + 1)
  }
  c
}

// 取频率最高的前 k 个文本（选择法，零依赖）
fn bench_topk_texts(freq : Map[String, Int], k : Int) -> Array[String] {
  let pairs : Array[(String, Int)] = []
  for t, n in freq.iter2() {
    pairs.push((t, n))
  }
  // 选择排序按计数降序
  for i = 0; i < pairs.length(); i = i + 1 {
    let mut bi = i
    for j = i + 1; j < pairs.length(); j = j + 1 {
      if pairs[j].1 > pairs[bi].1 {
        bi = j
      }
    }
    if bi != i {
      let tmp = pairs[i]
      pairs[i] = pairs[bi]
      pairs[bi] = tmp
    }
  }
  let out : Array[String] = []
  let lim = if k < pairs.length() { k } else { pairs.length() }
  for i = 0; i < lim; i = i + 1 {
    out.push(pairs[i].0)
  }
  out
}

fn bench_contains(arr : Array[String], s : String) -> Bool {
  for x in arr {
    if x == s {
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// B1. 基线对照：引擎 Hit@3  vs  频率先验（context-free 上界）  vs  随机
// ---------------------------------------------------------------------------

test "B1 基线对照：引擎显著优于频率先验与随机基线" {
  let reps = 8
  // 引擎在线 Hit@3（复现验收数字）
  let eng = ProphecyEngine::make()
  train_all(eng, reps)
  let eng_hit = eng.hit_rate()

  // 频率先验基线（context-free）：用【全量】频率取 Top-3，对整条流做命中统计。
  // 这是任何"不看上下文"预测器的性能上界，作为强基线更有说服力。
  let stream = bench_stream(reps)
  let freq = bench_freq(stream)
  let top3 = bench_topk_texts(freq, 3)
  let mut freq_hits = 0
  for t in stream {
    if bench_contains(top3, t) {
      freq_hits = freq_hits + 1
    }
  }
  let freq_rate = freq_hits.to_double() / stream.length().to_double()

  // 随机基线：均匀从全部不同节点里猜 3 个，期望命中率 = 3 / 节点数
  let distinct : Map[String, Int] = bench_freq(stream)
  let rand_rate = 3.0 / distinct.length().to_double()

  println(">>> [B1] 引擎 Hit@3      = " + eng_hit.to_string())
  println(">>> [B1] 频率先验 Hit@3  = " + freq_rate.to_string() + "  (Top-3 高频步 = " + top3.length().to_string() + " 项)")
  println(">>> [B1] 随机基线 Hit@3  = " + rand_rate.to_string() + "  (节点数 = " + distinct.length().to_string() + ")")
  let lift_vs_freq = eng_hit / freq_rate
  let lift_vs_rand = eng_hit / rand_rate
  println(">>> [B1] 相对频率先验提升 = " + lift_vs_freq.to_string() + "x")
  println(">>> [B1] 相对随机基线提升 = " + lift_vs_rand.to_string() + "x")

  // 断言：引擎显著优于两条基线（>0.8 vs 频率先验 ~0.5 vs 随机 ~0.23）
  inspect(eng_hit > freq_rate, content="true")
  inspect(eng_hit > rand_rate, content="true")
  inspect(eng_hit > 1.5 * freq_rate, content="true")
  println(">>> [B1] PASS: 引擎 Hit@3 显著高于强基线（频率先验/随机）")
}

// ---------------------------------------------------------------------------
// B2. 留出集（leave-one-out）泛化：训练时【完全不含】被测主题名，测试其冷启动预测
//     这是真正的 train/test 划分——被测主题的项目名从未在训练中出现，
//     若仍能预测出正确下一步，则证明泛化来自 D8 角色抽象而非记忆。
// ---------------------------------------------------------------------------

test "B2 留出集泛化：未见主题名的冷启动 Top-3 命中（leave-one-out）" {
  let mut success = 0
  let total = topics.length()
  for h = 0; h < total; h = h + 1 {
    let held = topics[h]
    let e = ProphecyEngine::make()
    // 仅用【其余 7 个主题】训练（held 从不进入训练）
    for _r = 0; _r < 6; _r = _r + 1 {
      for t in topics {
        if t == held {
          continue
        }
        e.end_episode()
        for i = 0; i < canon.length(); i = i + 1 {
          let text = canon[i].0.replace_all(old="%TOPIC%", new=t)
          let _ = e.predict(3)
          let _ = e.observe(text, canon[i].1)
        }
      }
    }
    // 测试：观察【未见】主题的项目名 -> 预测下一步是否命中"提取核心术语表并锁定"
    let _ = e.observe("新建翻译项目：" + held, "instruction")
    let pred = e.predict(3)
    let ok = in_topk(pred, "提取核心术语表并锁定", 3)
    if ok {
      success = success + 1
    }
    println(">>> [B2] 留出主题「" + held + "」冷启动命中 = " + ok.to_string())
  }
  let acc = success.to_double() / total.to_double()
  println(">>> [B2] 留出集泛化准确率 = " + success.to_string() + "/" + total.to_string() + " = " + acc.to_string())
  // 断言：留出集泛化准确率高（证明非记忆、真泛化）
  inspect(acc >= 0.75, content="true")
  println(">>> [B2] PASS: 未见主题名也能经 D8 角色抽象泛化出正确下一步（train/test 划分）")
}

// ---------------------------------------------------------------------------
// B3. 鲁棒性：交错噪声干扰下工作流预测不崩溃
//     在标准工作流训练后，注入一条无关噪声观察，随后复盘已知项目名，
//     引擎仍应把正确下一步保留在 Top-3（噪声不应清除已学转移规律）。
// ---------------------------------------------------------------------------

test "B3 鲁棒性：注入噪声后仍能预测正确下一步" {
  let e = ProphecyEngine::make()
  train_all(e, 6)
  // 注入无关噪声（与任何工作流步骤都不相关的句子）
  let _ = e.observe("顺便一提：今天午餐吃了牛肉面味道不错", "fact")
  let _ = e.observe("会议室临时改到五楼东侧", "fact")
  // 复盘已知项目名
  let _ = e.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let pred = e.predict(3)
  let ok = in_topk(pred, "提取核心术语表并锁定", 3)
  println(">>> [B3] 噪声注入后复盘 Top1=" + top1_text(pred) + " | 仍命中提取术语=" + ok.to_string())
  inspect(ok, content="true")
  println(">>> [B3] PASS: 噪声观察不破坏已学工作流的下一步预测（鲁棒）")
}

// ---------------------------------------------------------------------------
// B4. 召回精度（量化）：给定含某术语的新源文，Top-1 召回应是该领域相关记忆
//     用可量化断言替代"看起来相关"，为 TM 核心能力提供硬证据。
// ---------------------------------------------------------------------------

test "B4 召回精度：术语查询 Top-3 命中对应双语术语" {
  let e = ProphecyEngine::make()
  // 建一个小型双语术语库（真实内容）
  let glossary : Array[(String, String)] = [
    ("【术语】电池管理系统 → Battery Management System (BMS)", "fact"),
    ("【术语】能量密度 → energy density", "fact"),
    ("【术语】续航里程 → driving range", "fact"),
    ("【术语】生物相容性 → biocompatibility", "fact"),
    ("【术语】灭菌 → sterilization", "fact"),
    ("【例句】该车型采用液冷电池包以提升热安全性。→ The model adopts a liquid-cooled battery pack to improve thermal safety.", "fact"),
  ]
  let ctx : Array[String] = []
  for g in glossary {
    let id = e.remember(g.0, g.1, ctx)
    ctx.push(id)
  }
  // 查询"电池"，Top-3 应包含 BMS 术语或液冷电池包例句
  let hits = e.recall("电池包热管理与安全", 3)
  let mut ok = false
  for hj in hits {
    let t = match hj {
      Json::Object(m) => match m.get("text") { Some(Json::String(s)) => s; _ => "" }
      _ => ""
    }
    if t == "【术语】电池管理系统 → Battery Management System (BMS)" ||
       t == "【例句】该车型采用液冷电池包以提升热安全性。→ The model adopts a liquid-cooled battery pack to improve thermal safety." {
      ok = true
    }
  }
  println(">>> [B4] 查询'电池包热管理与安全' Top-3 命中相关双语术语/例句 = " + ok.to_string())
  inspect(ok, content="true")
  println(">>> [B4] PASS: 语义召回按内容命中对应双语术语（TM 核心能力可量化）")
}
