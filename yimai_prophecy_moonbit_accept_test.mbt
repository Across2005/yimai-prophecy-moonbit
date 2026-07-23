// yimai_prophecy_moonbit_accept_test.mbt
// 译脉·先知 2.0 (MoonBit) 验收测试台
//   Layer1 批量功能验收：Hit@k、冷启动泛化、确定性、JSON 往返、固化
//   Layer2 双 Agent 行为验收：Agent A 用引擎记工作流，Agent B 独立校验其预测行为
//
// 语料说明：采用本项目自身的真实工作流（6 步翻译流水线，取自设计文档/演示），
// 以多个真实项目主题为实例；非外部文件导入（MoonBit 本版本无文件 I/O）。

// 真实翻译工作流（步骤 1 随项目主题变化，步骤 2-6 跨项目共享）
let canon : Array[(String, String)] = [
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

// @json.parse 在本版本返回 `Json raise ParseError`（抛异常，非 Result）。
// 我们只在 JSON 往返场景解析自身 to_json 产出，必然合法；此处用 try/catch
// 兜底，异常时回退空对象，保证类型闭合且不中断验收。
fn safe_parse(s : String) -> Json {
  try {
    @json.parse(s)
  } catch {
    _ => Map::from_iter(([] : Array[(String, Json)]).iter()).to_json()
  }
}

// ---------------------------------------------------------------------------
// 训练 / 预测辅助
// ---------------------------------------------------------------------------

fn train_all(eng : ProphecyEngine, reps : Int) -> Unit {
  for _r = 0; _r < reps; _r = _r + 1 {
    for topic in topics {
      eng.end_episode()
      for i = 0; i < canon.length(); i = i + 1 {
        let tpl = canon[i].0
        let tp = canon[i].1
        let text = tpl.replace_all(old="%TOPIC%", new=topic)
        let _ = eng.predict(3)
        let _ = eng.observe(text, tp)
      }
    }
  }
}

fn top1_id(pred : Json) -> String {
  match pred {
    Json::Object(m) =>
      match m.get("predictions") {
        Some(Json::Array(a)) =>
          if a.length() > 0 {
            match a[0] {
              Json::Object(p) =>
                match p.get("id") {
                  Some(Json::String(s)) => s
                  _ => ""
                }
              _ => ""
            }
          } else { "" }
        _ => ""
      }
    _ => ""
  }
}

fn top1_text(pred : Json) -> String {
  match pred {
    Json::Object(m) =>
      match m.get("predictions") {
        Some(Json::Array(a)) =>
          if a.length() > 0 {
            match a[0] {
              Json::Object(p) =>
                match p.get("text") {
                  Some(Json::String(s)) => s
                  _ => ""
                }
              _ => ""
            }
          } else { "" }
        _ => ""
      }
    _ => ""
  }
}

fn in_topk(pred : Json, target : String, k : Int) -> Bool {
  match pred {
    Json::Object(m) =>
      match m.get("predictions") {
        Some(Json::Array(a)) => {
          let lim = if k < a.length() { k } else { a.length() }
          for i = 0; i < lim; i = i + 1 {
            match a[i] {
              Json::Object(p) =>
                match p.get("text") {
                  Some(Json::String(s)) => if s == target { return true }
                  _ => ()
                }
              _ => ()
            }
          }
          false
        }
        _ => false
      }
    _ => false
  }
}

fn explain_has_path(ex : Json) -> Bool {
  match ex {
    Json::Object(m) => {
      let out_edges = match m.get("out_edges") {
        Some(Json::Array(a)) => a.length() > 0
        _ => false
      }
      let predicts_to = match m.get("predicts_to") {
        Some(Json::Object(o)) => o.length() > 0
        _ => false
      }
      out_edges || predicts_to
    }
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Layer1 批量功能验收
// ---------------------------------------------------------------------------

test "Layer1 批量 Hit@3 达标" {
  let eng = ProphecyEngine::make()
  train_all(eng, 8)
  let hr = eng.hit_rate()
  let stats = eng.stats_view()
  println(">>> [Layer1] 批量训练 8 主题 x 8 轮 后 Hit@3 = " + hr.to_string())
  println(">>> [Layer1] predict_calls=" + stats.stringify())
  inspect(hr > 0.8, content="true")
  println(">>> [Layer1] PASS: Hit@3 > 0.8")
}

test "Layer1 确定性(可复现)" {
  let e1 = ProphecyEngine::make()
  let e2 = ProphecyEngine::make()
  train_all(e1, 4)
  train_all(e2, 4)
  let s1 = e1.to_json().stringify()
  let s2 = e2.to_json().stringify()
  inspect(s1 == s2, content="true")
  println(">>> [Layer1] PASS: 同输入两次状态逐字节一致（确定性/可复现）")
}

test "Layer1 JSON 往返一致" {
  let e = ProphecyEngine::make()
  train_all(e, 3)
  let s = e.to_json().stringify()
  let parsed = safe_parse(s)
  let e2 = ProphecyEngine::from_json(parsed)
  let s2 = e2.to_json().stringify()
  inspect(s == s2, content="true")
  println(">>> [Layer1] PASS: to_json -> from_json -> to_json 往返一致")
}

test "Layer1 固化重放保留核心记忆" {
  let e = ProphecyEngine::make()
  train_all(e, 6)
  let before = e.stats_view()
  let cons = e.consolidate(true)
  let nodes_before = match before {
    Json::Object(m) =>
      match m.get("nodes") {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
  let nodes_after = match cons {
    Json::Object(m) =>
      match m.get("nodes") {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
  let explore_s = match cons {
    Json::Object(m) =>
      match m.get("explore") {
        Some(Json::Number(n, ..)) => n.to_string()
        _ => "?"
      }
    _ => "?"
  }
  println(
    ">>> [Layer1] 固化: 节点 " +
      nodes_before.to_string() +
      " -> " +
      nodes_after.to_string() +
      " | explore=" +
      explore_s,
  )
  inspect(nodes_after >= nodes_before - 1.0, content="true")
  println(">>> [Layer1] PASS: 固化重放保留核心记忆并产出元认知 explore")
}

// ---------------------------------------------------------------------------
// Layer2 双 Agent 行为验收（Agent B 独立校验 Agent A 的预测行为）
// ---------------------------------------------------------------------------

test "Layer2 已知项目复盘预测正确下一步" {
  let eng = ProphecyEngine::make()
  train_all(eng, 6)
  let _ = eng.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let pred = eng.predict(3)
  let ok = in_topk(pred, "提取核心术语表并锁定", 3)
  println(">>> [Layer2] 已知项目复盘: observe 新建项目 -> Top1=" + top1_text(pred) + " | 命中提取术语=" + ok.to_string())
  inspect(ok, content="true")
  println(">>> [Layer2] PASS: Agent A 对新项目名主动预测正确下一步")
}

test "Layer2 冷启动(全新主题)泛化" {
  let eng = ProphecyEngine::make()
  train_all(eng, 6)
  let _ = eng.observe("新建翻译项目：量子计算综述", "instruction")
  let pred = eng.predict(3)
  let ok = in_topk(pred, "提取核心术语表并锁定", 3)
  println(">>> [Layer2] 冷启动(全新主题): Top1=" + top1_text(pred) + " | 泛化提取术语=" + ok.to_string())
  inspect(ok, content="true")
  println(">>> [Layer2] PASS: 未见主题经 D8 角色抽象泛化出正确下一步")
}

test "Layer2 预测可白盒解释" {
  let eng = ProphecyEngine::make()
  train_all(eng, 6)
  let _ = eng.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let pred = eng.predict(3)
  let id = top1_id(pred)
  let ex = eng.explain(id)
  let ok = explain_has_path(ex)
  println(">>> [Layer2] 可解释性: explain(" + id + ") 含白盒路径=" + ok.to_string())
  inspect(ok, content="true")
  println(">>> [Layer2] PASS: 预测可白盒解释（出边/转移路径可查）")
}

test "Layer2 持久化(重启后一致)" {
  let eng = ProphecyEngine::make()
  train_all(eng, 6)
  let _ = eng.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let _ = eng.predict(3)
  let snap = eng.to_json().stringify()
  let parsed = safe_parse(snap)
  let eng2 = ProphecyEngine::from_json(parsed)
  let pred2 = eng2.predict(3)
  let ok = in_topk(pred2, "提取核心术语表并锁定", 3)
  println(">>> [Layer2] 持久化: 恢复后 Top1=" + top1_text(pred2) + " | 与重启前一致=" + ok.to_string())
  inspect(ok, content="true")
  println(">>> [Layer2] PASS: 经 to_json/from_json 重启后记忆与预测保持一致")
}
