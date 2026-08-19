// yimai_prophecy_moonbit_quality_test.mbt
// 待办补齐能力（S4 评测 / M1 风格 / M2 回译 / M3 术语冲突 / M5 TMPlm）专项回归
// 覆盖：bleu_score / chrf_score / style_check / back_align / term_conflicts / retrieve_for_prompt / recall 角色剪枝

test "T1 BLEU：完全匹配 = 1.0" {
  let s = @lib.bleu_score("the cat is on the mat", "the cat is on the mat")
  inspect(s == 1.0, content="true")
}

test "T2 BLEU：部分匹配介于 (0,1)" {
  let s = @lib.bleu_score("the cat is on the mat", "a cat sits on a mat")
  inspect(s > 0.0 && s < 1.0, content="true")
}

test "T3 chrF++：完全匹配 = 1.0" {
  let s = @lib.chrf_score("the cat is on the mat", "the cat is on the mat")
  inspect(s == 1.0, content="true")
}

test "T4 style_check：检测重复标点" {
  let e = @lib.ProphecyEngine::make()
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
  let e = @lib.ProphecyEngine::make()
  let m1 = e.add_tm("电池包热管理", "battery pack thermal management")
  let m2 = e.add_tm("电池管理系统", "battery management system")
  let _ = e.add_tm("快充功率", "fast charging power")
  let _ = e.mark_term(m1)
  let _ = e.mark_term(m2)
  // observe 工作流节点（translation 恒空）不应计入双语统计
  let _ = e.observe("提取核心术语表并锁定", "instruction")
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
  // 拉丁词根按首个单词归并（switch/switcher 共享词根 "switch"），且输出按 root 字典序
  let e2 = @lib.ProphecyEngine::make()
  let l1 = e2.add_tm("switch mode", "开关模式")
  let l2 = e2.add_tm("switch unit", "切换单元")
  let _ = e2.mark_term(l1)
  let _ = e2.mark_term(l2)
  let r3 = e2.style_report("")
  match r3 {
    Json::Object(o) =>
      match o.get("term_variants") {
        Some(Json::Array(a)) => inspect(a.length() >= 1, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

test "T5 back_align：LCS 对齐分数合理" {
  let e = @lib.ProphecyEngine::make()
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
  let e = @lib.ProphecyEngine::make()
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
  let e = @lib.ProphecyEngine::make()
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

// ---------------------------------------------------------------------------
// T30..T33: decode_pct 单元回归（P4 路径安全加固）
//   覆盖：标准 %XX 解码 / 大小写 hex / 无 % 透传 / 非 hex % 保守保留
//   serve_static 自身是 native-only HTTP handler，wasm-gc 测试调不到；这里用
//   decode_pct 直测确保底层工具正确。
// ---------------------------------------------------------------------------

test "T30 decode_pct: %2e%2e%2f 解码为 \"../\"" {
  let out = @lib.decode_pct("%2e%2e%2f")
  inspect(out == "../", content="true")
}

test "T31 decode_pct: 大写 hex %2F 同样解码为 /" {
  let out = @lib.decode_pct("a%2Fb")
  inspect(out == "a/b", content="true")
}

test "T32 decode_pct: 无 % 序列原样透传" {
  let out = @lib.decode_pct("plain/path/with-slashes")
  inspect(out == "plain/path/with-slashes", content="true")
}

test "T33 decode_pct: 非 hex %ZZ 保守保留原样" {
  // %ZZ 不是合法 hex 序列，保守策略：透传整个 % 字节（不丢字符）
  let out = @lib.decode_pct("a%ZZb")
  inspect(out == "a%ZZb", content="true")
}

test "T34 decode_pct: %2e%2e%2fcmd 显式返回 \"..cmd\" 前缀触发 '..' 检查" {
  // 模拟 serve_static 的检查链路：解码后必含 ".."，被现有 str_contains 拦截
  let decoded = @lib.decode_pct("%2e%2e%2fcmd%2fservice%2fmcp.mbt")
  inspect(@lib.str_contains(decoded, ".."), content="true")
  inspect(@lib.str_contains(decoded, "\\"), content="false")
}

// ---------------------------------------------------------------------------
// T35..T37: MQM 严重度数值化（P4：与 AGENTS.md 声明的标准尺度 None=0/Minor=1/Major=5/Critical=10 对齐）
//   mqm_issue helper 内部用 mqm_severity_to_score 自动计算 severity_score 字段
// ---------------------------------------------------------------------------

test "T35 mqm_severity_to_score: 标准 4 档全部正确" {
  inspect(@lib.mqm_severity_to_score("none") == 0.0, content="true")
  inspect(@lib.mqm_severity_to_score("minor") == 1.0, content="true")
  inspect(@lib.mqm_severity_to_score("major") == 5.0, content="true")
  inspect(@lib.mqm_severity_to_score("critical") == 10.0, content="true")
}

test "T36 mqm_issue: 输出 4 字段 (dimension/severity/severity_score/detail)" {
  let issue = @lib.mqm_issue("terminology", "major", "术语违规")
  match issue {
    Json::Object(o) => {
      let has_dim = match o.get("dimension") { Some(Json::String("terminology")) => true; _ => false }
      let has_sev = match o.get("severity") { Some(Json::String("major")) => true; _ => false }
      let has_score = match o.get("severity_score") { Some(Json::Number(5.0, ..)) => true; _ => false }
      let has_detail = match o.get("detail") { Some(Json::String(_)) => true; _ => false }
      inspect(has_dim && has_sev && has_score && has_detail, content="true")
    }
    _ => inspect(false, content="true")
  }
}

test "T37 mqm_tags: critical 空译文 issue 带 severity_score=10.0" {
  let e = @lib.ProphecyEngine::make()
  let r = e.mqm_tags("测试源文", "", 0.0, true)
  match r {
    Json::Array(issues) => {
      let mut found = false
      for it in issues {
        match it {
          Json::Object(o) =>
            match (o.get("severity"), o.get("severity_score")) {
              (Some(Json::String("critical")), Some(Json::Number(s, ..))) => {
                if s == 10.0 { found = true }
              }
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
