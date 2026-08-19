// _test_helpers.mbt
// ---------------------------------------------------------------
// 共享测试辅助（inline 副本）。
//
// P5 仓库整理：原本散落在 accept_test.mbt 顶层（私有），
// 同根 moon.pkg 范围内所有 _test.mbt 互相可见。
// 改用 sub-package 后跨子包不可见，MoonBit 0.1.20260724 不支持
// sub-package 跨包 import，故每个需要的子包 inline 一份。
//
// DRY 缺口：与 tests/core/yimai_prophecy_moonbit_accept_test.mbt
// 顶层 helper 同步修改。已加注释提醒。
// ---------------------------------------------------------------


// 真实翻译工作流（步骤 1 随项目主题变化，步骤 2-6 跨项目共享）
pub let canon : Array[(String, String)] = [
  ("新建翻译项目：%TOPIC%", "instruction"),
  ("提取核心术语表并锁定", "fact"),
  ("对齐术语风格：正式技术中性", "preference"),
  ("按章节分段翻译", "fact"),
  ("质检术语与风格一致性", "instruction"),
  ("导出中英双语交付物", "instruction"),
]
// 8 个真实项目主题（用于批量训练 / 冷启动泛化）
pub let topics : Array[String] = [
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
pub fn safe_parse(s : String) -> Json {
  try {
    @json.parse(s)
  } catch {
    _ => Map::from_iter(([] : Array[(String, Json)]).iter()).to_json()
  }
}

// ---------------------------------------------------------------------------
// 训练 / 预测辅助
// ---------------------------------------------------------------------------


pub fn train_all(eng : @lib.ProphecyEngine, reps : Int) -> Unit {
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


pub fn top1_id(pred : Json) -> String {
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


pub fn top1_text(pred : Json) -> String {
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


pub fn in_topk(pred : Json, target : String, k : Int) -> Bool {
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


pub fn explain_has_path(ex : Json) -> Bool {
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
