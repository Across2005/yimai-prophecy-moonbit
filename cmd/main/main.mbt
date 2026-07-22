// main.mbt —— 译脉·先知 2.0 (MoonBit) 演示与验证入口
// 移植原 Python 版 __main__：重复翻译工作流训练 -> Hit@3 验证 ->
// 复盘预测 -> D8 冷启动泛化 -> 固化重放 -> reward -> restore -> 降级。
// 与 Python 版输出可逐项对照。

// ---------------------------------------------------------------------------
// 演示本地 JSON 访问辅助（仅读取引擎返回的 Json）
// ---------------------------------------------------------------------------

fn jstr(j : Json, key : String) -> String {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

fn jnum(j : Json, key : String) -> Double {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
}

fn jarr(j : Json, key : String) -> Array[Json] {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Array(a)) => a
        _ => []
      }
    _ => []
  }
}

fn join_texts(arr : Array[String]) -> String {
  let b = StringBuilder()
  for i = 0; i < arr.length(); i = i + 1 {
    if i > 0 {
      b.write_string(" / ")
    }
    b.write_string(arr[i])
  }
  b.to_string()
}

fn paths_text(arr : Array[Json]) -> String {
  let b = StringBuilder()
  for i = 0; i < arr.length(); i = i + 1 {
    if i > 0 {
      b.write_string(", ")
    }
    b.write_string(jstr(arr[i], "from"))
    b.write_string("(p=" + jnum(arr[i], "p").to_string() + ")")
  }
  b.to_string()
}

fn print_preds(p : Json) -> Unit {
  println("  confidence=" + jnum(p, "confidence").to_string() + "  uncertainty=" + jnum(p, "uncertainty").to_string())
  for x in jarr(p, "predictions") {
    println("  - prob=" + jnum(x, "prob").to_string() + "  " + jstr(x, "text") + "  | path: " + paths_text(jarr(x, "path")))
  }
}

fn print_recalls(arr : Array[Json]) -> Unit {
  for x in arr {
    println("  - " + jstr(x, "text") + "  (type=" + jstr(x, "type") + ", score=" + jnum(x, "score").to_string() + ", activation=" + jnum(x, "activation").to_string() + ")")
  }
}

// ---------------------------------------------------------------------------
// 训练数据：翻译项目重复工作流（6 步，第 1 步随主题变化）
// ---------------------------------------------------------------------------

let generic : Array[(String, String)] = [
  ("新建翻译项目：%TOPIC%", "instruction"),
  ("提取核心术语表并锁定", "fact"),
  ("对齐术语风格：正式技术中性", "preference"),
  ("按章节分段翻译", "fact"),
  ("质检术语与风格一致性", "instruction"),
  ("导出中英双语交付物", "instruction"),
]

let topics : Array[String] = [
  "新能源汽车白皮书",
  "医疗器械说明书",
  "金融科技年报",
  "工业软件手册",
  "生物医药指南",
  "半导体技术文档",
  "储能系统规范",
  "智能驾驶标准",
]

fn main {
  let eng = @lib.ProphecyEngine::make()

  // 构造重复工作流，让转移规律稳定；步骤 2-6 跨项目共享（去重为共享节点）
  for _r = 0; _r < 8; _r = _r + 1 {
    for topic in topics {
      eng.end_episode()
      for i = 0; i < generic.length(); i = i + 1 {
        let tpl = generic[i].0
        let tp = generic[i].1
        let text = tpl.replace_all(old="%TOPIC%", new=topic)
        let _ = eng.predict(3)     // 先预测「下一步」
        let _ = eng.observe(text, tp) // 再揭示当前步并做命中核算
      }
    }
  }

  println("=== 预测命中率 (Hit@3)：预测项在随后被实际观察到的比例 ===")
  println("predict calls : " + jnum(eng.stats_view(), "predict_calls").to_string())
  println("hit rate      : " + eng.hit_rate().to_string())
  println("\n=== 固化重放前 stats ===")
  println(eng.stats_view().stringify(indent=2))

  // 复盘一个已训练项目，验证「observe 项目名 -> 预测下一步=提取术语」
  println("\n=== 已知项目复盘：observe 项目名后预测下一步 ===")
  let _ = eng.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let p = eng.predict(3)
  println("当前上下文: " + join_texts(eng.context_texts()))
  print_preds(p)

  // D8 概念抽象·冷启动：从未出现过的全新主题，也应泛化预测出「提取术语」
  println("\n=== 概念抽象·冷启动：全新主题项目名 -> 泛化预测 ===")
  let _ = eng.observe("新建翻译项目：量子计算综述", "instruction")
  let p2 = eng.predict(3)
  print_preds(p2)

  // 固化重放（含元认知调控 + 约束契约快照）
  let cons = eng.consolidate(true)
  println("\n=== 固化重放 (prune) ===")
  println(cons.stringify(indent=2))
  println("explore (探索度, 元认知自调) 见上 recent_hit_rate 对应值")

  // 进化引擎·感知器：对一条记忆给正反馈，验证其预测价值上升
  println("\n=== reward 反馈机制验证 ===")
  let target = eng.last_context_id()
  let before = jnum(eng.explain(target), "predictive_value")
  let _ = eng.reward(target, 1.0)
  let after = jnum(eng.explain(target), "predictive_value")
  println("反馈前预测价值: " + before.to_string() + " -> 反馈+1.0后: " + after.to_string() + (if after >= before { " | 上升" } else { " | 下降" }))

  // 约束契约·回滚验证
  println("\n=== restore 回滚验证 ===")
  println(eng.restore().stringify(indent=2))

  // 降级验证：单节点也应出结果（复杂场景异常兜底）
  let e2 = @lib.ProphecyEngine::make()
  let _ = e2.remember("孤立记忆：会议室在3楼", "fact", ([] : Array[String]))
  println("\n=== 降级 (小网络) recall ===")
  print_recalls(e2.recall("会议室在哪", 3))

  println("\n=== 译脉·先知 2.0 (MoonBit) 验证完成 ===")
}
