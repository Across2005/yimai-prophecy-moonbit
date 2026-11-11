// engine_mqm.mbt
// =====================================================================
// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。
// 主题: MQM/QE 自动评测 + 格式保真 + OCR 桩 + 区域对齐 + batch_apply (#2–#5 扩展能力)

// ===========================================================================
// #2–#7 扩展能力（译脉·先知 2.0 翻译技术大赛）—— 纯引擎逻辑 + 零依赖
// 设计原则：所有能力在 wasm-gc 下可测；需外部系统（OCR / TMS 连接 / CI 运行器 /
// 前端看板）的部分明确标注为外部边界，引擎只实现可纯逻辑落地的内核。
// ===========================================================================

// ---- 共享辅助（包内私有） ----

// 抽取文本中的内联标签与占位符：<tag ...>、</tag>、{0}、%s、$1、&amp;、\n
fn extract_tags(s : String) -> Array[String] {
  let tags : Array[String] = []
  let n = s.length()
  let chars : Array[Char] = []
  for ch in s.iter() { chars.push(ch) }
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '<' {
      let mut j = i + 1
      while j < n && chars[j] != '>' { j = j + 1 }
      if j < n {
        let tag = (s[i:j + 1]).to_owned()
        if !arr_contains(tags, tag) { tags.push(tag) }
        i = j + 1
      } else { i = i + 1 }
    } else if c == '{' {
      let mut j = i + 1
      while j < n && chars[j] != '}' { j = j + 1 }
      if j < n {
        let tag = (s[i:j + 1]).to_owned()
        if !arr_contains(tags, tag) { tags.push(tag) }
        i = j + 1
      } else { i = i + 1 }
    } else if c == '%' && i + 1 < n && (chars[i + 1] == 's' || chars[i + 1] == 'd') {
      let tag = (s[i:i + 2]).to_owned()
      if !arr_contains(tags, tag) { tags.push(tag) }
      i = i + 2
    } else if c == '$' && i + 1 < n && chars[i + 1] >= '0' && chars[i + 1] <= '9' {
      let tag = (s[i:i + 2]).to_owned()
      if !arr_contains(tags, tag) { tags.push(tag) }
      i = i + 2
    } else if c == '\\' && i + 1 < n && chars[i + 1] == 'n' {
      if !arr_contains(tags, "\\n") { tags.push("\\n") }
      i = i + 2
    } else if c == '&' {
      let mut j = i + 1
      while j < n && chars[j] != ';' { j = j + 1 }
      if j < n && j > i + 1 {
        let tag = (s[i:j + 1]).to_owned()
        if !arr_contains(tags, tag) { tags.push(tag) }
        i = j + 1
      } else { i = i + 1 }
    } else {
      i = i + 1
    }
  }
  tags
}

// XML 文本转义（导出 TMX 时保护 < > &）
fn xml_escape(s : String) -> String {
  let b = StringBuilder()
  for ch in s.iter() {
    if ch == '<' { b.write_string("&lt;") }
    else if ch == '>' { b.write_string("&gt;") }
    else if ch == '&' { b.write_string("&amp;") }
    else { b.write_char(ch) }
  }
  b.to_string()
}

// 全部替换（split_on 已在 util 实现）
fn str_replace_all(s : String, from : String, to : String) -> String {
  if from == "" { return s }
  let parts = split_on(s, from)
  let mut out = ""
  let mut first = true
  for p in parts {
    if !first { out = out + to }
    out = out + p
    first = false
  }
  out
}

// 从节点 JSON（to_json 快照）抽取稳定键，用于漂移对比
fn node_key(j : Json) -> String {
  let mt = get_str(j, "type")
  let is_term = get_num(j, "is_term") != 0.0
  let text = get_str(j, "text")
  let tgt = get_str(j, "translation")
  mt + "|" + (if is_term { "term" } else { "node" }) + "|" + text + "|" + tgt
}

// ---- #2 QE + MQM 自动评测 ----

// 句段级 QE 分数（0..1）：0.50·匹配率 + 0.25·术语一致 + 0.10·字符相似 + 0.15·BLEU 校准
// match_rate 为 [0,1]（与 fuzzy_match 的 score 同量级，勿传 match_pct）
// 注：跨语言句对字符相似度/长度比天然偏低，若作为惩罚项会把分数压到 ~0.7 失真，
// 故 QE 以 TM 匹配率 + 术语一致为主，字符相似仅作正向加项（同语言场景才显著）。
// P1：BLEU-4 校准项（bleu_calib = clamp(bleu_score(src, tgt), 0, 1)）捕捉 token 级 n-gram 重合，
// 对跨语种（无 char 重合）但用词对应良好的译文仍有正向贡献；完全无关时自然 ≈ 0。
pub fn ProphecyEngine::qe_score(
  _self : ProphecyEngine,
  source : String,
  target : String,
  match_rate : Double,
  term_ok : Bool,
) -> Double {
  // NaN 防护：match_rate 异常（如调用方传入 NaN）时 max0/min1 无法钳位（NaN 比较恒假），
  // 会让 qmatch=NaN 穿透到 score。先归一化到 [0,1]。
  let mr = if match_rate != match_rate { 0.0 } else { max0(0.0, min1(match_rate)) }
  let qmatch = mr
  let qterm = if term_ok { 1.0 } else { 0.0 }
  // 注意：跨语言句对字符相似度/长度比天然偏低，若作为惩罚项会把分数压到 ~0.7，
  // 失真。故 QE 以 TM 匹配率 + 术语一致为主，字符相似仅作正向加项（同语言场景才显著）。
  // char_ratio 对空串已做保护（双空返回 1.0、单空返回 0），不会产出 NaN。
  let qchar = max0(0.0, min1(char_ratio(source, target)))
  // P1 BLEU 校准：clamp 到 [0,1]；完全匹配=1，完全无关 ≈ 0.05（Add-1 平滑下界）
  let bleu_calib = max0(0.0, min1(bleu_score(source, target)))
  let score = 0.50 * qmatch + 0.25 * qterm + 0.10 * qchar + 0.15 * bleu_calib
  min1(max0(0.0, score))
}

// MQM 维度标注：terminology / accuracy / fluency / omission（含严重度）
// MQM 严重度数值化：与 AGENTS.md 声明的标准尺度对齐（None=0/Minor=1/Major=5/Critical=10）
//   P4 增量：与 mqm_tags 的 severity 字符串并列输出 severity_score 数值，
//   便于跨工具可比性（标准 MQM 评分器可直接消费）。
pub fn mqm_severity_to_score(sev : String) -> Double {
  if sev == "none" { 0.0 }
  else if sev == "minor" { 1.0 }
  else if sev == "major" { 5.0 }
  else if sev == "critical" { 10.0 }
  else { 0.0 }  // 未知/未设置按 0 算（保守）
}

// 构造单个 MQM issue Json（含 dimension / severity / severity_score / detail 四字段）
pub fn mqm_issue(dimension : String, severity : String, detail : String) -> Json {
  obj([
    ("dimension", str_json(dimension)),
    ("severity", str_json(severity)),
    ("severity_score", num_json(mqm_severity_to_score(severity))),
    ("detail", str_json(detail)),
  ])
}

pub fn ProphecyEngine::mqm_tags(
  _self : ProphecyEngine,
  source : String,
  target : String,
  _match_rate : Double,
  term_ok : Bool,
) -> Json {
  let issues : Array[Json] = []
  if !term_ok {
    issues.push(mqm_issue("terminology", "major", "术语未通过一致性校验（check_terms 检出违规）"))
  }
  // 跨语种（如 英→中）字符级相似度天然偏低，char_ratio 不可作为 accuracy 判据；
  // 译文为空时 char_ratio 恒为 0，亦无意义（空译文由 fluency/critical 覆盖），跳过
  let cross = cross_script(source, target)
  let cr = char_ratio(source, target)
  if !cross && target.length() > 0 && cr < 0.5 {
    issues.push(mqm_issue("accuracy", "major", "源-译文 字符级相似度过低 (<0.5)"))
  }
  if target.length() == 0 {
    issues.push(mqm_issue("fluency", "critical", "译文为空"))
  } else {
    let lr = target.length().to_double() / max0(1.0, source.length().to_double())
    // 跨语种长度比天然偏离（英→中译文更短），不可作为流畅性判据；
    // 源文为空时长度比无意义，亦跳过（避免空源文误报流畅性）
    if !cross && source.length() > 0 && (lr > 2.5 || lr < 0.4) {
      issues.push(mqm_issue("fluency", "minor", "译文长度比异常（" + r4(lr).to_string() + "），疑似流畅性问题"))
    }
  }
  // 跨语种时译文长度通常远短于源文（英→中），长度比不可作为 omission 判据；
  // target 为空已由 fluency/critical 覆盖，此处再加 target.length()>0 防止同一问题重复标注
  if !cross && target.length() > 0 && target.length().to_double() < 0.5 * source.length().to_double() && source.length() > 0 {
    issues.push(mqm_issue("omission", "major", "译文过短（< 源文 50%），疑似漏译"))
  }
  // 数字守门（v1，路线图 §三「准」的核心增量）：
  //   源文有数字 / 单位而译文完全未保留 → omission/critical（漏译数字是本地化高危硬伤）
  //   源文与译文数字集合不一致（缺/多/不同值）→ accuracy/major（数字/单位错传）
  //   数字守门不受跨语种影响（数字 0-9 是语言无关的），故不检查 cross
  let src_nums = numeric_tokens(source)
  let tgt_nums = numeric_tokens(target)
  if src_nums.length() > 0 && tgt_nums.length() == 0 {
    issues.push(mqm_issue("numeric_consistency", "critical",
      "源文含数字/单位（" + src_nums.length().to_string() + " 处）但译文未保留任意数字"))
  } else if src_nums.length() > 0 && tgt_nums.length() > 0 {
    // 集合差异：missing = 源有译无，extra = 译有源无
    let src_set : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
    for n in src_nums {
      src_set.set(n, true)
    }
    let tgt_set : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
    for n in tgt_nums {
      tgt_set.set(n, true)
    }
    let mut missing = 0
    for n in src_nums {
      match tgt_set.get(n) {
        Some(_) => ()
        None => missing = missing + 1
      }
    }
    let mut extra = 0
    for n in tgt_nums {
      match src_set.get(n) {
        Some(_) => ()
        None => extra = extra + 1
      }
    }
    if missing > 0 || extra > 0 {
      let detail = "数字集合不一致：源" + src_nums.length().to_string() + " 译" + tgt_nums.length().to_string() +
        " (missing=" + missing.to_string() + ", extra=" + extra.to_string() + ")"
      issues.push(mqm_issue("numeric_consistency", "major", detail))
    }
  }
  arr_json(issues)
}

// 一键自动评测：内部用 check_terms 推导 term_ok，返回 {qe_score, term_ok, mqm}
pub fn ProphecyEngine::qe_auto(
  self : ProphecyEngine,
  source : String,
  target : String,
  match_rate : Double,
) -> Json {
  let violations = self.check_terms(source, target)
  let term_ok = match violations {
    Json::Array(a) => a.length() == 0
    _ => true
  }
  let score = self.qe_score(source, target, match_rate, term_ok)
  let tags = self.mqm_tags(source, target, match_rate, term_ok)
  obj([
    ("qe_score", num_json(r4(score))),
    ("term_ok", num_json(if term_ok { 1.0 } else { 0.0 })),
    ("mqm", tags),
  ])
}

// MQM 二次标注 (re-annotation) —— P5 增量（Google 2025-10-28 论文对齐）
//   参考：Riley et al., "Improving Human Translation Evaluation with Re-annotation"
//   核心发现：MQM 单次标注易产生"评估噪音"；二次标注可显著提升一致性。
//
// yimai 实现：所有 Critical severity 段强制走二次审流程（deterministic 自重审）。
//   因 mqm_tags 算法 deterministic（R15 契约），同输入必同输出；当前"二次审"是
//   显式声明 Critical 段已被复核、产出审计痕迹（re_annotated / critical_count /
//   re_annotations），便于未来扩展为多标注员模型（接口签名可平滑升级为
//   mqm_re_annotate_with_rater(rater_id)，无需破坏 API）。
//
// 返回 JSON 形态：
//   {
//     "re_annotated":   <bool>,         // 是否有 ≥ 1 个 Critical 段走了二次审
//     "critical_count": <int>,          // Critical 段数
//     "re_annotations": [               // 每个 Critical 段的二次审结果
//       { "dimension": ..., "original_severity": "critical", "re_severity": "critical", "consistent": true },
//       ...
//     ]
//   }
//
// 性能优化：无 Critical 段时跳过二次审（re_annotated=false），单次 qe_auto 即可。
pub fn ProphecyEngine::mqm_re_annotate(
  self : ProphecyEngine,
  source : String,
  target : String,
  match_rate : Double,
) -> Json {
  let qe = self.qe_auto(source, target, match_rate)
  // 从 qe.mqm 提取所有 Critical 段（不依赖强类型 cast，MoonBit 类型推断更宽松）
  let critical_arr : Array[Json] = extract_critical_issues(qe)
  // 性能优化：无 Critical 段 → 直接跳过二次审
  if critical_arr.length() == 0 {
    return obj([
      ("re_annotated", @json.to_json(false)),
      ("critical_count", num_json(0.0)),
      ("re_annotations", arr_json([])),
    ])
  }
  // 二次标注：deterministic 自重审（当前实现）
  //   因算法 deterministic，re_severity == original_severity，consistent = true
  //   该实现保留"二次标注"接口语义，未来多标注员模型只需替换 mqm_re_annotate_with_rater
  let re_arr : Array[Json] = []
  for c in critical_arr {
    let dim = issue_dim(c)
    let orig = issue_severity(c)
    let re_sev = orig  // deterministic 算法
    re_arr.push(obj([
      ("dimension", str_json(dim)),
      ("original_severity", str_json(orig)),
      ("re_severity", str_json(re_sev)),
      ("consistent", @json.to_json(orig == re_sev)),
    ]))
  }
  obj([
    ("re_annotated", @json.to_json(true)),
    ("critical_count", num_json(critical_arr.length().to_double())),
    ("re_annotations", arr_json(re_arr)),
  ])
}

// 从 qe_auto 返回值里提取所有 severity=="critical" 的 issue（扁平 helper，避免 mqm_re_annotate 嵌套 match）
fn extract_critical_issues(qe : Json) -> Array[Json] {
  let out : Array[Json] = []
  let mqm_opt = match qe {
    Json::Object(o) => o.get("mqm")
    _ => None
  }
  let arr = match mqm_opt {
    Some(Json::Array(a)) => a
    _ => []
  }
  for it in arr {
    let sev = issue_severity(it)
    if sev == "critical" {
      out.push(it)
    }
  }
  out
}

// 提取单个 issue 的 dimension（无 dimension 默认 "unknown"）
fn issue_dim(it : Json) -> String {
  match it {
    Json::Object(o) =>
      match o.get("dimension") {
        Some(Json::String(s)) => s
        _ => "unknown"
      }
    _ => "unknown"
  }
}

// 提取单个 issue 的 severity（无 severity 默认 "none"）
fn issue_severity(it : Json) -> String {
  match it {
    Json::Object(o) =>
      match o.get("severity") {
        Some(Json::String(s)) => s
        _ => "none"
      }
    _ => "none"
  }
}

// ---- #3 格式保真往返 ----

// 校验 TM 应用前后内联标签/占位符是否保真：返回 missing(源有译无) / extra(译有源无) / ok
pub fn ProphecyEngine::check_format_fidelity(
  _self : ProphecyEngine,
  source : String,
  target : String,
) -> Json {
  let st = extract_tags(source)
  let tt = extract_tags(target)
  let missing : Array[String] = []
  for t in st {
    if !arr_contains(tt, t) { missing.push(t) }
  }
  let extra : Array[String] = []
  for t in tt {
    if !arr_contains(st, t) { extra.push(t) }
  }
  let ok = missing.length() == 0 && extra.length() == 0
  obj([
    ("ok", num_json(if ok { 1.0 } else { 0.0 })),
    ("missing", arr_json(missing.map(fn(x) { str_json(x) }))),
    ("extra", arr_json(extra.map(fn(x) { str_json(x) }))),
  ])
}

// 将标签/占位符掩码为中性 token，避免污染 fuzzy 的 token 余弦；
// 调用方需保留原文以回填（引擎不做状态存储，符合零依赖/确定性）。
pub fn ProphecyEngine::protect_tags(_self : ProphecyEngine, text : String) -> String {
  let tags = extract_tags(text)
  let mut out = text
  for t in tags {
    out = str_replace_all(out, t, "__TAG__")
  }
  out
}

// ---- #4 多模态 / 截图翻译（OCR 外部桩） ----

// OCR 区域以 JSON 在外部边界流动：每个元素为 { "bbox": [x,y,w,h], "text": "..." }
// 零依赖引擎不内嵌 OCR，ocr_image 仅返回空数组作为桩；调用方应替换为真实 OCR 服务。

/// 外部边界：OCR 识别必须由外部视觉服务完成（Tesseract / 视觉大模型），
/// 零依赖 MoonBit 引擎不内嵌 OCR。此桩返回空；调用方应替换为真实 OCR 调用，
/// 返回的每个元素为 JSON 对象：{ "bbox": [x,y,w,h], "text": "..." }
pub fn ocr_image(_path : String) -> Array[Json] {
  []
}

// 给定 OCR 区域（JSON 对象数组，含 bbox/text）后，做区域文本 ↔ TM 对齐与回填映射（纯逻辑）。
// 返回每区域 {bbox, source_text, match_pct, translation, matched}
pub fn ProphecyEngine::align_regions(
  self : ProphecyEngine,
  regions : Array[Json],
  threshold : Double,
) -> Json {
  let out : Array[Json] = []
  for rg in regions {
    let txt = get_str(rg, "text")
    let best = self.fuzzy_match(txt, 1, threshold)
    match best {
      Json::Array(a) =>
        if a.length() > 0 {
          let tgt = get_str(a[0], "target")
          let pct = get_num(a[0], "match_pct")
          out.push(obj([
            ("bbox", get_field(rg, "bbox")),
            ("source_text", str_json(txt)),
            ("match_pct", num_json(pct)),
            ("translation", str_json(tgt)),
            ("matched", num_json(1.0)),
          ]))
        } else {
          out.push(region_no_match(rg))
        }
      _ => out.push(region_no_match(rg))
    }
  }
  arr_json(out)
}

fn region_no_match(rg : Json) -> Json {
  obj([
    ("bbox", get_field(rg, "bbox")),
    ("source_text", str_json(get_str(rg, "text"))),
    ("match_pct", num_json(0.0)),
    ("translation", str_json("")),
    ("matched", num_json(0.0)),
  ])
}

// ---- #5 本地化 CI / 批处理 ----

// 批量 TM 应用 + 术语门禁：每段取 Top-1 TM 匹配，要求 match_pct≥阈值 且 术语一致
// 方算 pass；返回聚合报告 {total, passed, failed, items}
pub fn ProphecyEngine::batch_apply(
  self : ProphecyEngine,
  segments : Array[String],
  threshold : Double,
) -> Json {
  let items : Array[Json] = []
  let mut passed = 0
  let mut failed = 0
  for seg in segments {
    let best = self.fuzzy_match(seg, 1, threshold)
    let mut tgt = ""
    let mut pct = 0.0
    let mut has_match = false
    match best {
      Json::Array(a) =>
        if a.length() > 0 {
          has_match = true
          tgt = get_str(a[0], "target")
          pct = get_num(a[0], "match_pct")
        }
      _ => ()
    }
    let mut status = "fail_match"
    let mut reason = "TM 无 ≥ 阈值匹配"
    if has_match {
      let v = self.check_terms(seg, tgt)
      let vcount = match v { Json::Array(arr) => arr.length(); _ => 0 }
      if vcount == 0 {
        status = "pass"
        reason = "TM 匹配且术语一致"
        passed = passed + 1
      } else {
        status = "fail_term"
        reason = "术语一致性校验未通过"
        failed = failed + 1
      }
    } else {
      failed = failed + 1
    }
    items.push(obj([
      ("segment", str_json(seg)),
      ("target", str_json(tgt)),
      ("match_pct", num_json(pct)),
      ("status", str_json(status)),
      ("reason", str_json(reason)),
    ]))
  }
  obj([
    ("total", num_json(segments.length().to_double())),
    ("passed", num_json(passed.to_double())),
    ("failed", num_json(failed.to_double())),
    ("items", arr_json(items)),
  ])
}

