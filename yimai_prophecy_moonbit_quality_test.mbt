// yimai_prophecy_moonbit_quality_test.mbt
// 待办补齐能力（S4 评测 / M1 风格 / M2 回译 / M3 术语冲突 / M5 TMPlm）专项回归
// 覆盖：bleu_score / chrf_score / style_check / back_align / term_conflicts / retrieve_for_prompt / recall 角色剪枝

test "T1 BLEU：完全匹配 = 1.0" {
  let s = bleu_score("the cat is on the mat", "the cat is on the mat")
  inspect(s == 1.0, content="true")
}

test "T2 BLEU：部分匹配介于 (0,1)" {
  let s = bleu_score("the cat is on the mat", "a cat sits on a mat")
  inspect(s > 0.0 && s < 1.0, content="true")
}

test "T3 chrF++：完全匹配 = 1.0" {
  let s = chrf_score("the cat is on the mat", "the cat is on the mat")
  inspect(s == 1.0, content="true")
}

test "T4 style_check：检测重复标点" {
  let e = ProphecyEngine::make()
  let r = e.style_check("这是测试。这是第二句。。")
  match r {
    Json::Array(a) => {
      let mut found = false
      for item in a {
        match item {
          Json::Object(o) =>
            match o.get("rule") {
              Some(Json::String(rule)) => if rule == "repeated_punct" { found = true }
              _ => ()
            }
          _ => ()
        }
      }
      inspect(found, content="true")
    }
    _ => inspect(false, content="true")
  }
}

test "T4b style_report：记忆库分布 + 术语变体 + 偏离建议" {
  let e = ProphecyEngine::make()
  let m1 = e.add_tm("电池包热管理", "battery pack thermal management")
  let m2 = e.add_tm("电池管理系统", "battery management system")
  let _ = e.add_tm("快充功率", "fast charging power")
  let _ = e.mark_term(m1)
  let _ = e.mark_term(m2)
  let r = e.style_report("")
  match r {
    Json::Object(o) =>
      match o.get("sentence_count") {
        Some(Json::Number(n, ..)) => inspect(n == 3.0, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
  // 术语变体族「电池」（2 词同根、均标为术语）应被检出
  let r2 = e.style_report("")
  match r2 {
    Json::Object(o) =>
      match o.get("term_variants") {
        Some(Json::Array(a)) => inspect(a.length() >= 1, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

test "T5 back_align：LCS 对齐分数合理" {
  let e = ProphecyEngine::make()
  let r = e.back_align("install sensor", "install the sensor")
  match r {
    Json::Object(o) =>
      match o.get("align_score") {
        Some(Json::Number(n, ..)) => inspect(n > 0.5 && n <= 1.0, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

test "T6 term_conflicts：一词多译检出" {
  let e = ProphecyEngine::make()
  let _ = e.load_tbx(
    "<termEntry><langSet xml:lang=\"en-US\"><ntig><term>API</term></ntig></langSet><langSet xml:lang=\"zh-CN\"><ntig><term>接口</term></ntig></langSet></termEntry>" +
      "<termEntry><langSet xml:lang=\"en-US\"><ntig><term>API</term></ntig></langSet><langSet xml:lang=\"zh-CN\"><ntig><term>应用程序接口</term></ntig></langSet></termEntry>",
  )
  let r = e.term_conflicts()
  match r {
    Json::Array(a) => {
      let mut found = false
      for item in a {
        match item {
          Json::Object(o) =>
            match o.get("kind") {
              Some(Json::String(k)) => if k == "one_to_many" { found = true }
              _ => ()
            }
          _ => ()
        }
      }
      inspect(found, content="true")
    }
    _ => inspect(false, content="true")
  }
}

test "T7 retrieve_for_prompt：三段式结构" {
  let e = ProphecyEngine::make()
  let _ = e.add_tm("电池包热管理策略", "Battery pack thermal management strategy")
  let r = e.retrieve_for_prompt("电池包热管理", 2, 0.3)
  match r {
    Json::Object(o) => {
      let has_s = match o.get("suggestions") { Some(Json::Array(a)) => a.length() > 0; _ => false }
      let has_t = match o.get("terms") { Some(Json::Array(_)) => true; _ => false }
      let has_g = match o.get("glossary") { Some(Json::Array(_)) => true; _ => false }
      inspect(has_s && has_t && has_g, content="true")
    }
    _ => inspect(false, content="true")
  }
}
