// engine_io.mbt
// =====================================================================
// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。
// 主题: TMX/XLIFF 解析导出 + 引擎健康 metrics + 双快照 drift_report (#6–#7 互操作与可观测)

// ---- #6 TMS 互通（XLIFF / TMX 解析侧） ----

// 解析 TMX(1.4/2.0)：每个 <tu> 取 src/tgt 的 <tuv xml:lang>/<seg> 建 TM。返回加载条数。
// 注意：必须以单元「闭合标签」</tu> 切分，而非 <tu> 开端标签——
// 因为 split_on(xml,"<tu") 会同时命中 <tuv（<tuv 以 <tu 开头），
// 把每个 <tu> 内的两个 <tuv> 拆到不同片段，导致译文落空/丢弃。
// 而 </tu> 不是 </tuv> 的子串，按闭合标签切分可保证一个单元的全部 <tuv> 落在同一片段。
pub fn ProphecyEngine::parse_tmx(self : ProphecyEngine, xml : String) -> Int {
  let mut count = 0
  let tus = split_on(xml, "</tu>")
  for tu in tus {
    let tuvs = split_on(tu, "<tuv")
    let mut src = ""
    let mut tgt = ""
    let mut fallback = ""
    for tuv in tuvs {
      let lang = lang_attr(tuv)
      let seg = first_tag_text(tuv, "seg")
      if seg == "" { continue }
      // 前缀匹配以兼容语言代码变体：en-US/en/zh-CN/zh/zh-Hans 等
      if starts_with(lang, "en") { src = seg }
      else if starts_with(lang, "zh") { tgt = seg }
      else if fallback == "" { fallback = seg }
    }
    if tgt == "" { tgt = fallback }
    // 仅入库完整双语对，避免空译文污染翻译记忆（数据完整性）
    if src != "" && tgt != "" {
      let _ = self.add_tm(src, tgt)
      count = count + 1
    }
  }
  count
}

// 解析 XLIFF(1.2/2.0)：<trans-unit>/<unit> 内的 <source>/<target> 建 TM。返回加载条数。
// 注意：split_on 返回的 segs[0] 是首个标签之前的前缀（不含 source/target），
// 必须从 index=1 起遍历，否则无匹配时会把整段 XML 误当作一个单元重复建 TM。
pub fn ProphecyEngine::parse_xliff(self : ProphecyEngine, xml : String) -> Int {
  let mut count = 0
  // XLIFF 1.2: <trans-unit id=...> ; XLIFF 2.0: <unit id=...>
  let segs1 = split_on(xml, "<trans-unit")
  for i = 1; i < segs1.length(); i = i + 1 {
    let u = segs1[i]
    let src = first_tag_text(u, "source")
    let tgt = first_tag_text(u, "target")
    // 仅入库完整双语对，避免空译文污染翻译记忆
    if src != "" && tgt != "" {
      let _ = self.add_tm(src, tgt)
      count = count + 1
    }
  }
  let segs2 = split_on(xml, "<unit")
  for i = 1; i < segs2.length(); i = i + 1 {
    let u = segs2[i]
    // 跳过 1.2 的 <trans-unit>（已由 segs1 处理），仅处理真正的 <unit>（2.0）
    if str_contains(u, "trans-unit") { continue }
    let src = first_tag_text(u, "source")
    let tgt = first_tag_text(u, "target")
    if src != "" && tgt != "" {
      let _ = self.add_tm(src, tgt)
      count = count + 1
    }
  }
  count
}

// 导出 TMX(1.4)：将所有 mtype=="tm" 节点序列化为标准 TMX 片段（XML 转义已做）
pub fn ProphecyEngine::export_tmx(
  self : ProphecyEngine,
  src_lang~ : String = "en-US",
  tgt_lang~ : String = "zh-CN",
) -> String {
  let b = StringBuilder()
  b.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<tmx version=\"1.4\">\n<body>\n")
  for _, m in self.memories.iter2() {
    if m.mtype != "tm" { continue }
    b.write_string("<tu>\n<tuv xml:lang=\"")
    b.write_string(src_lang)
    b.write_string("\"><seg>")
    b.write_string(xml_escape(m.text))
    b.write_string("</seg></tuv>\n<tuv xml:lang=\"")
    b.write_string(tgt_lang)
    b.write_string("\"><seg>")
    b.write_string(xml_escape(m.translation))
    b.write_string("</seg></tuv>\n</tu>\n")
  }
  b.write_string("</body>\n</tmx>")
  b.to_string()
}

// ---- #7 可观测 / 漂移监控 ----

// 引擎健康指标：TM 数 / 术语数 / 总记忆数 / 术语覆盖率（术语出现在任一 TM 源或译文的比例）
pub fn ProphecyEngine::metrics(self : ProphecyEngine) -> Json {
  let mut tm_count = 0
  let mut term_count = 0
  let mut term_used = 0
  let mut total_mem = 0
  let tm_texts : Array[String] = []
  for _, m in self.memories.iter2() {
    total_mem = total_mem + 1
    if m.mtype == "tm" {
      tm_count = tm_count + 1
      tm_texts.push(m.text)
      tm_texts.push(m.translation)
    } else if m.is_term {
      term_count = term_count + 1
      let covered = arr_contains(tm_texts, m.text) || arr_contains(tm_texts, m.translation)
      if covered { term_used = term_used + 1 }
    }
  }
  let coverage = if term_count == 0 { 0.0 } else { term_used.to_double() / term_count.to_double() }
  obj([
    ("tm_count", num_json(tm_count.to_double())),
    ("term_count", num_json(term_count.to_double())),
    ("total_memories", num_json(total_mem.to_double())),
    ("term_coverage", num_json(r4(coverage))),
  ])
}

// 两快照（to_json 输出）对比的漂移报告：按 (type|is_term|text|translation) 键算 TM/术语 增删
// P4 增强：在 after snapshot 上加 text_chrf_avg 字段，算所有 TM (text, translation) 的 chrF 平均
//   作为「记忆库整体翻译质量」指标；纯本地 (chrf_score 零依赖)，无云端。
pub fn ProphecyEngine::drift_report(
  _self : ProphecyEngine,
  before : Json,
  after : Json,
) -> Json {
  let b_mem = get_obj(before, "memories")
  let a_mem = get_obj(after, "memories")
  let b_keys : Array[String] = []
  let a_keys : Array[String] = []
  match b_mem {
    Json::Object(m) => for _, mn in m.iter2() { b_keys.push(node_key(mn)) }
    _ => ()
  }
  match a_mem {
    Json::Object(m) => for _, mn in m.iter2() { a_keys.push(node_key(mn)) }
    _ => ()
  }
  let mut tm_added = 0
  let mut tm_removed = 0
  let mut term_added = 0
  let mut term_removed = 0
  for k in a_keys {
    if !arr_contains(b_keys, k) {
      if str_contains(k, "tm|") { tm_added = tm_added + 1 } else { term_added = term_added + 1 }
    }
  }
  for k in b_keys {
    if !arr_contains(a_keys, k) {
      if str_contains(k, "tm|") { tm_removed = tm_removed + 1 } else { term_removed = term_removed + 1 }
    }
  }
  let mut b_tm = 0
  let mut b_term = 0
  for k in b_keys {
    if str_contains(k, "tm|") { b_tm = b_tm + 1 } else { b_term = b_term + 1 }
  }
  let mut a_tm = 0
  let mut a_term = 0
  for k in a_keys {
    if str_contains(k, "tm|") { a_tm = a_tm + 1 } else { a_term = a_term + 1 }
  }
  // P4：after snapshot 所有 TM (text, translation) chrF 平均 — 翻译质量漂移指标
  //   注：to_json 字段名是 "type" 不是 "mtype"（见 node_key L2195）
  let mut chrf_sum = 0.0
  let mut chrf_n = 0
  match a_mem {
    Json::Object(m) =>
      for _, mn in m.iter2() {
        match mn {
          Json::Object(nobj) => {
            let is_tm = match nobj.get("type") {
              Some(Json::String(s)) => s == "tm"
              _ => false
            }
            if is_tm {
              let text = get_str(mn, "text")
              let trans = get_str(mn, "translation")
              if text != "" && trans != "" {
                chrf_sum = chrf_sum + chrf_score(text, trans)
                chrf_n = chrf_n + 1
              }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  let chrf_avg = if chrf_n > 0 { r4(chrf_sum / chrf_n.to_double()) } else { 0.0 }
  obj([
    ("before_tm", num_json(b_tm.to_double())),
    ("after_tm", num_json(a_tm.to_double())),
    ("before_term", num_json(b_term.to_double())),
    ("after_term", num_json(a_term.to_double())),
    ("tm_added", num_json(tm_added.to_double())),
    ("tm_removed", num_json(tm_removed.to_double())),
    ("term_added", num_json(term_added.to_double())),
    ("term_removed", num_json(term_removed.to_double())),
    // P4 新增：after snapshot 翻译质量漂移指标（chrF 平均，0..1）
    ("text_chrf_avg", num_json(chrf_avg)),
    ("text_chrf_n", num_json(chrf_n.to_double())),
  ])
}

