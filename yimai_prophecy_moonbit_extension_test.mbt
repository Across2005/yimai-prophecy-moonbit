// yimai_prophecy_moonbit_extension_test.mbt
// #2–#7 扩展能力专项回归（E1–E16）
// 覆盖：QE+MQM / 格式保真 / 多模态对齐(OCR 外部桩) / 本地化批处理 / TMS(TMX·XLIFF) / 可观测与漂移。
// E14–E16 为审查回归：parse_tmx 跨语种建 TM 正确性、mqm_tags 跨语种误报屏蔽、同语种仍报 accuracy。

// ---- #2 QE + MQM ----
test "E1 QE 自动评测：高匹配 + 无术语违规 => 高分且 term_ok" {
  let e = ProphecyEngine::make()
  let _ = e.add_tm("电池包热管理", "Battery pack thermal management")
  let r = e.qe_auto("电池包热管理", "Battery pack thermal management", 0.95)
  match r {
    Json::Object(m) => {
      // P1：BLEU 校准 + char 缩权后，跨语种高匹配对照（zh↔en，无 token 重合）从 ~0.86 降到 ~0.74
      // （BLEU 同样因词重合度低而偏低）。分数仍 > 0.7 表明「高匹配 + 术语一致」的可信信号。
      match m.get("qe_score") {
        Some(Json::Number(s, ..)) => inspect(s > 0.7, content="true")
        _ => inspect(false, content="true")
      }
      match m.get("term_ok") {
        Some(Json::Number(b, ..)) => inspect(b == 1.0, content="true")
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

test "E2 MQM：术语违规 => 检出 terminology 维度" {
  let e = ProphecyEngine::make()
  let _ = e.load_tbx(
    "<termEntry><langSet xml:lang=\"en-US\"><ntig><term>API</term></ntig></langSet><langSet xml:lang=\"zh-CN\"><ntig><term>接口</term></ntig></langSet></termEntry>",
  )
  // 源文含 API，但译文未出现「接口」=> term_ok=false
  let tags = e.mqm_tags("调用 API 接口", "调用 接口", 0.9, false)
  match tags {
    Json::Array(a) => {
      let mut found = false
      for t in a {
        match t {
          Json::Object(o) =>
            match o.get("dimension") {
              Some(Json::String(d)) => if d == "terminology" { found = true }
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

test "E3 MQM：译文为空 => fluency critical" {
  let e = ProphecyEngine::make()
  let tags = e.mqm_tags("任何源文", "", 0.0, true)
  match tags {
    Json::Array(a) => {
      let mut found = false
      for t in a {
        match t {
          Json::Object(o) =>
            match o.get("dimension") {
              Some(Json::String(d)) => if d == "fluency" { found = true }
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

// ---- #3 格式保真 ----
test "E4 格式保真：源有标签译无 => ok=false 且 missing 非空" {
  let e = ProphecyEngine::make()
  let r = e.check_format_fidelity("点击 <b>确定</b> 提交", "点击 确定 提交")
  match r {
    Json::Object(m) => {
      match m.get("ok") {
        Some(Json::Number(b, ..)) => inspect(b == 0.0, content="true")
        _ => inspect(false, content="true")
      }
      match m.get("missing") {
        Some(Json::Array(a)) => inspect(a.length() >= 1, content="true")
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

test "E5 格式保真：protect_tags 掩码标签" {
  let e = ProphecyEngine::make()
  let masked = e.protect_tags("hello <b>world</b> {0}")
  inspect(str_contains(masked, "<b>") == false, content="true")
  inspect(str_contains(masked, "__TAG__"), content="true")
}

// ---- #4 多模态（OCR 外部桩） ----
test "E6 OCR 外部桩返回空数组" {
  let r = ocr_image("screenshot.png")
  inspect(r.length() == 0, content="true")
}

test "E7 多模态：区域文本对齐命中 TM" {
  let e = ProphecyEngine::make()
  let _ = e.add_tm("电池包", "Battery pack")
  let regions : Array[Json] = [
    obj([
      ("bbox", arr_json([0, 0, 10, 10].map(fn(x) { num_json(x.to_double()) }))),
      ("text", str_json("电池包")),
    ]),
  ]
  let r = e.align_regions(regions, 0.70)
  match r {
    Json::Array(a) => {
      inspect(a.length() == 1, content="true")
      match a[0] {
        Json::Object(m) => {
          match m.get("matched") {
            Some(Json::Number(b, ..)) => inspect(b == 1.0, content="true")
            _ => inspect(false, content="true")
          }
          match m.get("translation") {
            Some(Json::String(s)) => inspect(s == "Battery pack", content="true")
            _ => inspect(false, content="true")
          }
        }
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

// ---- #5 本地化 CI / 批处理 ----
test "E8 批处理：TM 匹配且术语一致 => pass" {
  let e = ProphecyEngine::make()
  let _ = e.add_tm("打开文件", "Open file")
  let _ = e.load_tbx(
    "<termEntry><langSet xml:lang=\"en-US\"><ntig><term>file</term></ntig></langSet><langSet xml:lang=\"zh-CN\"><ntig><term>文件</term></ntig></langSet></termEntry>",
  )
  let r = e.batch_apply(["打开文件"], 0.70)
  match r {
    Json::Object(m) =>
      match m.get("passed") {
        Some(Json::Number(p, ..)) => inspect(p == 1.0, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

test "E9 批处理：无 TM 匹配 => fail_match" {
  let e = ProphecyEngine::make()
  let r = e.batch_apply(["完全无关的句段xyz"], 0.70)
  match r {
    Json::Object(m) =>
      match m.get("failed") {
        Some(Json::Number(f, ..)) => inspect(f == 1.0, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

// ---- #6 TMS 互通 ----
test "E10 TMX 解析建 TM + 导出往返一致" {
  let e = ProphecyEngine::make()
  let tmx =
    "<?xml version=\"1.0\"?><tmx><body><tu><tuv xml:lang=\"en-US\"><seg>Open file</seg></tuv><tuv xml:lang=\"zh-CN\"><seg>打开文件</seg></tuv></tu></body></tmx>"
  let n = e.parse_tmx(tmx)
  inspect(n == 1, content="true")
  let out = e.export_tmx()
  inspect(str_contains(out, "<seg>Open file</seg>"), content="true")
  inspect(str_contains(out, "xml:lang=\"en-US\""), content="true")
}

test "E11 XLIFF 解析建 TM 且可 fuzzy 命中" {
  let e = ProphecyEngine::make()
  let xliff =
    "<xliff><file><body><trans-unit id=\"1\"><source>Open file</source><target>打开文件</target></trans-unit></body></file></xliff>"
  let n = e.parse_xliff(xliff)
  inspect(n == 1, content="true")
  let r = e.fuzzy_match("Open file", 1, 0.70)
  match r {
    Json::Array(a) => inspect(a.length() == 1, content="true")
    _ => inspect(false, content="true")
  }
}

// ---- #7 可观测 / 漂移 ----
test "E12 指标：术语覆盖率计数正确" {
  let e = ProphecyEngine::make()
  let _ = e.add_tm("API 接口文档", "API interface doc")
  let _ = e.load_tbx(
    "<termEntry><langSet xml:lang=\"en-US\"><ntig><term>API</term></ntig></langSet><langSet xml:lang=\"zh-CN\"><ntig><term>接口</term></ntig></langSet></termEntry>",
  )
  let m = e.metrics()
  match m {
    Json::Object(o) => {
      match o.get("tm_count") {
        Some(Json::Number(t, ..)) => inspect(t == 1.0, content="true")
        _ => inspect(false, content="true")
      }
      match o.get("term_count") {
        Some(Json::Number(t, ..)) => inspect(t == 1.0, content="true")
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

test "E13 漂移：新增 TM 后被检出" {
  let e0 = ProphecyEngine::make()
  let before = e0.to_json()
  let e1 = ProphecyEngine::make()
  let _ = e1.add_tm("新条目源", "新条目译")
  let after = e1.to_json()
  let d = e1.drift_report(before, after)
  match d {
    Json::Object(o) =>
      match o.get("tm_added") {
        Some(Json::Number(t, ..)) => inspect(t == 1.0, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

// E13b：P4 增量 — drift_report 新增 text_chrf_avg + text_chrf_n 字段
//   验证：1 个 TM 翻译 chrF 在 (0, 1)（"新条目源" vs "新条目译" 字符 1-gram 重合 3/4，
//   字符 2-gram 不重合，词 1-gram 不重合；综合 avg 在 (0, 1)）；n=1
test "E13b 漂移报告：text_chrf_avg 字段正确返回 chrF 平均" {
  let e0 = ProphecyEngine::make()
  let before = e0.to_json()
  let e1 = ProphecyEngine::make()
  let _ = e1.add_tm("新条目源", "新条目译")
  let after = e1.to_json()
  let d = e1.drift_report(before, after)
  match d {
    Json::Object(o) =>
      match (o.get("text_chrf_avg"), o.get("text_chrf_n")) {
        (Some(Json::Number(avg, ..)), Some(Json::Number(n, ..))) => {
          // avg 严格在 (0, 1) — 字符 1-gram 重合 3/4 (0.75) 但 2-gram/词都不重合
          inspect(avg > 0.0 && avg < 1.0, content="true")
          inspect(n == 1.0, content="true")
        }
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

// ---- 审查回归（open-code-review 发现并修复） ----

test "E14 parse_tmx 跨语种：en-US/zh-CN 双 <tuv> 正确建 TM（回归：<tu>/<tuv> 切分碰撞）" {
  let e = ProphecyEngine::make()
  let tmx =
    "<?xml version=\"1.0\"?><tmx><body>" +
    "<tu><tuv xml:lang=\"en-US\"><seg>Open file</seg></tuv><tuv xml:lang=\"zh-CN\"><seg>打开文件</seg></tuv></tu>" +
    "<tu><tuv xml:lang=\"en-US\"><seg>Call API</seg></tuv><tuv xml:lang=\"zh-CN\"><seg>调用接口</seg></tuv></tu>" +
    "</body></tmx>"
  let n = e.parse_tmx(tmx)
  inspect(n == 2, content="true")
  let r = e.fuzzy_match("Open file", 1, 0.7)
  match r {
    Json::Array(a) =>
      match a[0] {
        Json::Object(m) =>
          match m.get("target") {
            Some(Json::String(s)) => inspect(s == "打开文件", content="true")
            _ => inspect(false, content="true")
          }
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

test "E15 mqm_tags 跨语种：正确 EN→ZH 不误报 accuracy/omission（回归：跨语言启发式误报）" {
  let e = ProphecyEngine::make()
  let tags = e.mqm_tags("Open file", "打开文件", 0.95, true)
  match tags {
    Json::Array(a) => {
      let mut bad = 0
      for t in a {
        match t {
          Json::Object(o) =>
            match o.get("dimension") {
              Some(Json::String(d)) => if d == "accuracy" || d == "omission" { bad = bad + 1 }
              _ => ()
            }
          _ => ()
        }
      }
      inspect(bad == 0, content="true")
    }
    _ => inspect(false, content="true")
  }
}

test "E16 mqm_tags 同语种：低相似度仍报 accuracy（确认屏蔽仅限跨语种）" {
  let e = ProphecyEngine::make()
  let tags = e.mqm_tags("Open file", "Qmxi kpl zzz", 0.95, true)
  match tags {
    Json::Array(a) => {
      let mut hit = false
      for t in a {
        match t {
          Json::Object(o) =>
            match o.get("dimension") {
              Some(Json::String(d)) => if d == "accuracy" { hit = true }
              _ => ()
            }
          _ => ()
        }
      }
      inspect(hit, content="true")
    }
    _ => inspect(false, content="true")
  }
}

// ---- 审查回归（MoA 多模型复查发现并修复） ----

test "E17 mqm_tags 空译文：仅标 fluency/critical，不重复标 omission（回归：空 target 双标）" {
  let e = ProphecyEngine::make()
  let tags = e.mqm_tags("Open file", "", 0.95, true)
  match tags {
    Json::Array(a) => inspect(a.length() == 1, content="true")
    _ => inspect(false, content="true")
  }
}

test "E18 parse_tmx 语言代码变体：en/zh 前缀也能正确建 TM（回归 #8 语言硬编码）" {
  let e = ProphecyEngine::make()
  let tmx =
    "<?xml version=\"1.0\"?><tmx><body>" +
    "<tu><tuv xml:lang=\"en\"><seg>Open file</seg></tuv><tuv xml:lang=\"zh\"><seg>打开文件</seg></tuv></tu>" +
    "</body></tmx>"
  let n = e.parse_tmx(tmx)
  inspect(n == 1, content="true")
  let r = e.fuzzy_match("Open file", 1, 0.7)
  match r {
    Json::Array(a) =>
      match a[0] {
        Json::Object(m) =>
          match m.get("target") {
            Some(Json::String(s)) => inspect(s == "打开文件", content="true")
            _ => inspect(false, content="true")
          }
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}
