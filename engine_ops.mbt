// engine_ops.mbt
// =====================================================================
// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。
// 主题: style/back_align/term_conflicts/retrieve_for_prompt + 主动学习/联邦/蒸馏/可观测 (#21+ 长期能力)

// 主动学习候选：高不确定(低命中/低使用) + 角色多样性
pub fn ProphecyEngine::active_learning_candidates(
  self : ProphecyEngine,
  k : Int,
) -> Array[Json] {
  self._recompute_values()
  let pairs : Array[(String, Double)] = []
  for mid, m in self.memories.iter2() {
    let hr = hit_rate_of(m)
    let unc = 1.0 - hr
    let nov = 1.0 - clamp01(m.use_count.to_double() / 5.0)
    pairs.push((mid, 0.6 * unc + 0.4 * nov))
  }
  sort_desc_by_key(pairs, fn(x){ x.1 })
  let seen_role : Map[String, Int] = Map::from_iter(([] : Array[(String, Int)]).iter())
  let out : Array[Json] = []
  for i = 0; i < pairs.length(); i = i + 1 {
    if out.length() >= k {
      break
    }
    let mid = pairs[i].0
    match self.memories.get(mid) {
      Some(m) => {
        let rk = role_of(m.text)
        // 角色多样性：已覆盖角色延后选取，优先保证覆盖面
        if seen_role.contains(rk) && out.length() < k && seen_role.length() < k {
          continue
        }
        seen_role.set(rk, 1)
        out.push(
          obj([
            ("id", str_json(mid)),
            ("text", str_json(m.text)),
            ("uncertainty", num_json(r4(pairs[i].1))),
            ("role", str_json(rk)),
          ]),
        )
      }
      None => ()
    }
  }
  out
}

// 联邦：增量导出（供 FedAvg 聚合的对端差异计数）
pub fn ProphecyEngine::fed_export(self : ProphecyEngine) -> Json {
  obj([
    ("added", num_json(self.fed_add.to_double())),
    ("updated", num_json(self.fed_upd.to_double())),
  ])
}

// 联邦：增量导入（合并对端聚合后的计数；权重合并由协调方完成）
pub fn ProphecyEngine::fed_import(self : ProphecyEngine, added : Int, updated : Int) -> Unit {
  self.fed_add = self.fed_add + added
  self.fed_upd = self.fed_upd + updated
  self.invalidate_pred_cache()
}

// 蒸馏：注入只读领域偏置表（LoRA ΔW），供 predict 先验增强
pub fn ProphecyEngine::inject_distillation(
  self : ProphecyEngine,
  table : Map[String, Double],
) -> Unit {
  for rk, dv in table.iter2() {
    if rk != "" {
      let cur = match self.domain_bias.get(rk) { Some(x) => x; None => 0.0 }
      self.domain_bias.set(rk, cur + dv)
    }
  }
  self.invalidate_pred_cache()
}

// ---------------------------------------------------------------------------
// D7 可解释：回放某记忆的来龙去脉
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::explain(self : ProphecyEngine, mid : String) -> Json {
  match self.memories.get(mid) {
    Some(m) => {
      let hr = hit_rate_of(m)
      let via : Array[Json] = []
      for nb, w in m.edges.iter2() {
        via.push(obj([("to", str_json(nb)), ("w", num_json(r4(w)))]))
      }
      let predicts_to = match self.transitions.get(mid) {
        Some(d) => dmap_to_json(d)
        None => obj([])
      }
      obj([
        ("id", str_json(mid)),
        ("text", str_json(m.text)),
        ("type", str_json(m.mtype)),
        ("predictive_value", num_json(r4(m.predictive_value))),
        ("hit_rate", num_json(r4(hr))),
        ("out_edges", arr_json(via)),
        ("predicts_to", predicts_to),
      ])
    }
    None => obj([("error", str_json("unknown id"))])
  }
}

// ---------------------------------------------------------------------------
// 指标
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::hit_rate(self : ProphecyEngine) -> Double {
  if self.stats_preds > 0 {
    self.stats_hits.to_double() / self.stats_preds.to_double()
  } else {
    0.0
  }
}

// 当前上下文窗口的记忆文本（供演示/审计查看）
pub fn ProphecyEngine::context_texts(self : ProphecyEngine) -> Array[String] {
  let out : Array[String] = []
  for mid in self.context {
    match self.memories.get(mid) {
      Some(m) => out.push(m.text)
      None => out.push("")
    }
  }
  out
}

// 当前上下文最后一个节点 id（演示中取反馈对象用）
pub fn ProphecyEngine::last_context_id(self : ProphecyEngine) -> String {
  if self.context.length() == 0 {
    ""
  } else {
    self.context[self.context.length() - 1]
  }
}

pub fn ProphecyEngine::stats_view(self : ProphecyEngine) -> Json {
  self._recompute_values()
  let mut avg_v = 0.0
  for _, m in self.memories.iter2() {
    avg_v = avg_v + m.predictive_value
  }
  if self.memories.length() > 0 {
    avg_v = avg_v / self.memories.length().to_double()
  }
  let by_type : Map[String, Int] = Map::from_iter(([] : Array[(String, Int)]).iter())
  for _, m in self.memories.iter2() {
    let c = match by_type.get(m.mtype) { Some(x) => x; None => 0 }
    by_type.set(m.mtype, c + 1)
  }
  obj([
    ("nodes", num_json(self.memories.length().to_double())),
    ("edges", num_json(self.edges_count().to_double())),
    ("episodes", num_json(self.episodes.length().to_double())),
    ("by_type", imap_to_json(by_type)),
    ("predict_hit_rate", num_json(r4(self.hit_rate()))),
    ("predict_calls", num_json(self.stats_preds.to_double())),
    ("avg_predictive_value", num_json(r4(avg_v))),
    ("remembers", num_json(self.stats_remembers.to_double())),
  ])
}

// ===== M1 风格一致性检查（启发式，确定性）=====
pub fn ProphecyEngine::style_check(self : ProphecyEngine, text : String) -> Json {
  let issues : Array[Json] = []
  let sentences = text.split("。").to_array().map(fn(x) { x.to_owned() })
  // 1. 句长（>80 字符提示）
  for s in sentences {
    if s.length() > 80 {
      issues.push(obj([
        ("rule", str_json("sentence_length")),
        ("level", str_json("info")),
        ("message", str_json("句子过长（" + s.length().to_string() + " 字符），建议拆分。")),
      ]))
    }
  }
  // 2. 重复标点 / 连续空格
  if str_contains(text, "  ") {
    issues.push(obj([
      ("rule", str_json("double_space")),
      ("level", str_json("warning")),
      ("message", str_json("存在连续空格。")),
    ]))
  }
  if str_contains(text, "..") || str_contains(text, "。。") {
    issues.push(obj([
      ("rule", str_json("repeated_punct")),
      ("level", str_json("warning")),
      ("message", str_json("存在重复标点。")),
    ]))
  }
  // 3. 全角/半角括号混用
  let has_full = str_contains(text, "（") || str_contains(text, "）")
  let has_half = str_contains(text, "(") || str_contains(text, ")")
  if has_full && has_half {
    issues.push(obj([
      ("rule", str_json("bracket_mix")),
      ("level", str_json("info")),
      ("message", str_json("全角/半角括号混用，建议统一。")),
    ]))
  }
  // 4. 术语命中提示（术语库中出现的词）
  let term_hits = self.enforce_terms(text)
  let hit_count = match term_hits {
    Json::Array(a) => a.length()
    _ => 0
  }
  if hit_count > 0 {
    issues.push(obj([
      ("rule", str_json("term_hits")),
      ("level", str_json("info")),
      ("message", str_json("命中 " + hit_count.to_string() + " 个库内术语，注意按术语库译文统一。")),
    ]))
  }
  arr_json(issues)
}

// ===== 风格一致报告（路线图 §四 长期「美」）：记忆库分布统计 + 新译文偏离建议 =====
// 输入 text 可为空串（仅报告记忆库分布）或待检译文（追加偏离建议）。
// 统计口径：双语句对（tm 或带译文的 term，即 translation!=""）；句长=字符数。
// formal_score：库中通过 style_check 无格式问题的句对占比（格式达标率，非语言正式度）。
// 确定性：遍历 memories 顺序固定（iter2 按插入序），变体族按 root 排序输出，无随机。
pub fn ProphecyEngine::style_report(self : ProphecyEngine, text : String) -> Json {
  let mut sent_n = 0
  let mut sum_src = 0.0
  let mut sum_tgt = 0.0
  let mut formal_ok = 0
  let mut term_n = 0
  let term_variants : Map[String, Int] = Map::from_iter(([] : Array[(String, Int)]).iter())
  // 句长分布桶（字符）：<20 / 20-39 / 40-79 / >=80
  let mut b0 = 0
  let mut b1 = 0
  let mut b2 = 0
  let mut b3 = 0
  for _, m in self.memories.iter2() {
    // 仅统计双语节点（tm / 带译文的 term），排除 observe 工作流/指令节点（translation 恒空）
    if m.text.length() == 0 || m.translation == "" {
      continue
    }
    sent_n = sent_n + 1
    let s = m.text.length().to_double()
    let t = m.translation.length().to_double()
    sum_src = sum_src + s
    sum_tgt = sum_tgt + t
    let is_formal = match self.style_check(m.text) {
      Json::Array(a) => a.length() == 0
      _ => false
    }
    if is_formal {
      formal_ok = formal_ok + 1
    }
    if m.is_term {
      term_n = term_n + 1
      let root = term_root(m.text)
      if root != "" {
        let cur = match term_variants.get(root) { Some(v) => v; None => 0 }
        term_variants.set(root, cur + 1)
      }
    }
    if s >= 80.0 {
      b3 = b3 + 1
    } else if s >= 40.0 {
      b2 = b2 + 1
    } else if s >= 20.0 {
      b1 = b1 + 1
    } else {
      b0 = b0 + 1
    }
  }
  let n = sent_n.to_double()
  let avg_src = if n > 0.0 { r4(sum_src / n) } else { 0.0 }
  let avg_tgt = if n > 0.0 { r4(sum_tgt / n) } else { 0.0 }
  let formal_score = if n > 0.0 { r4(formal_ok.to_double() / n) } else { 0.0 }
  // 术语变体：按词根分组计数，>1 为潜在变体族；按 root 字典序输出保证确定性
  let vlist : Array[(String, Int)] = []
  for root, cnt in term_variants.iter2() {
    if cnt > 1 {
      vlist.push((root, cnt))
    }
  }
  vlist.sort_by(fn(a, b) { a.0.compare(b.0) })
  let variants_arr : Array[Json] = []
  for item in vlist {
    let (root, cnt) = item
    variants_arr.push(obj([("root", str_json(root)), ("count", num_json(cnt.to_double()))]))
  }
  // 新译文偏离建议：长度偏离记忆库均值 ±50% 或含重复标点
  let tips : Array[Json] = []
  if text.length() > 0 {
    let tl = text.length().to_double()
    if n > 0.0 && avg_tgt > 0.0 {
      let ratio = tl / avg_tgt
      if ratio > 1.5 {
        tips.push(obj([
          ("rule", str_json("length_deviation")),
          ("level", str_json("warning")),
          ("message", str_json("译文长度 " + text.length().to_string() + " 字，为库均值 " + avg_tgt.to_string() + " 的 " + r4(ratio).to_string() + "×（>1.5×），建议精简。")),
        ]))
      } else if ratio < 0.5 {
        tips.push(obj([
          ("rule", str_json("length_deviation")),
          ("level", str_json("warning")),
          ("message", str_json("译文长度 " + text.length().to_string() + " 字，为库均值 " + avg_tgt.to_string() + " 的 " + r4(ratio).to_string() + "×（<0.5×），疑似漏译。")),
        ]))
      }
    }
    let style_issues = self.style_check(text)
    match style_issues {
      Json::Array(a) => {
        for i in a {
          tips.push(i)
        }
      }
      _ => ()
    }
  }
  obj([
    ("sentence_count", num_json(sent_n.to_double())),
    ("term_count", num_json(term_n.to_double())),
    ("avg_src_len", num_json(avg_src)),
    ("avg_tgt_len", num_json(avg_tgt)),
    ("formal_score", num_json(formal_score)),
    ("distribution", arr_json([num_json(b0.to_double()), num_json(b1.to_double()), num_json(b2.to_double()), num_json(b3.to_double())])),
    ("term_variants", arr_json(variants_arr)),
    ("tips", arr_json(tips)),
  ])
}

// 词根提取：中文取前 2 个汉字，拉丁词取首个空格分隔的单词；用于归并变体族（如 电池/电池组/电池包、switch/switcher）
fn term_root(t : String) -> String {
  // 判断首字符是否为 ASCII 字母（拉丁）
  let is_latin = match t.iter().next() {
    Some(c) => (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
    None => false
  }
  if is_latin {
    // 拉丁：取首个空格分隔的单词
    let parts = t.split(" ").to_array()
    return if parts.length() > 0 { parts[0].to_owned() } else { "" }
  }
  // 中文/其他：取前 2 个非空格字符
  let chars : Array[String] = []
  for i = 0; i < t.length(); i = i + 1 {
    match t[i].to_char() {
      Some(ch) => {
        let c = ch.to_string()
        if c != " " {
          chars.push(c)
        }
        if chars.length() >= 2 {
          break
        }
      }
      None => ()
    }
  }
  chars.join("")
}

// ===== M2 回译验证（LCS 对齐质量）=====
//   P8：纯函数不读引擎状态；receiver 改 `_self` 消 unused 告警（保持 dot 调用语法不变）
pub fn ProphecyEngine::back_align(_self : ProphecyEngine, source : String, target : String) -> Json {
  let ops = align_diff(source, target)
  let mut match_n = 0
  let mis : Array[Json] = []
  let mut cur_a = ""
  let mut cur_b = ""
  for op in ops {
    match op {
      (0, _, _) => {
        if cur_a != "" {
          mis.push(obj([("side", str_json("a")), ("frag", str_json(cur_a))]))
          cur_a = ""
        }
        if cur_b != "" {
          mis.push(obj([("side", str_json("b")), ("frag", str_json(cur_b))]))
          cur_b = ""
        }
        match_n = match_n + 1
      }
      (1, i, _) => {
        if i < source.length() {
          cur_a = cur_a + (match source[i].to_char() { Some(ch) => ch.to_string(); None => "" })
        }
      }
      (2, _, j) => {
        if j < target.length() {
          cur_b = cur_b + (match target[j].to_char() { Some(ch) => ch.to_string(); None => "" })
        }
      }
      _ => ()
    }
  }
  if cur_a != "" {
    mis.push(obj([("side", str_json("a")), ("frag", str_json(cur_a))]))
  }
  if cur_b != "" {
    mis.push(obj([("side", str_json("b")), ("frag", str_json(cur_b))]))
  }
  let denom = if source.length() > target.length() { source.length() } else { target.length() }
  let score = if denom > 0 { r4(match_n.to_double() / denom.to_double()) } else { 1.0 }
  obj([
    ("align_score", num_json(score)),
    ("match_chars", num_json(match_n.to_double())),
    ("misaligns", arr_json(mis)),
  ])
}

// ===== M3 术语冲突检测（一词多译 / 多词一译）=====
pub fn ProphecyEngine::term_conflicts(self : ProphecyEngine) -> Json {
  // 收集术语节点：text -> translation
  let by_src : Map[String, Array[String]] = Map::from_iter(([] : Array[(String, Array[String])]).iter())
  let by_tgt : Map[String, Array[String]] = Map::from_iter(([] : Array[(String, Array[String])]).iter())
  for _, m in self.memories.iter2() {
    if m.is_term && m.translation != "" {
      let s1 = match by_src.get(m.text) {
        Some(v) => v
        None => []
      }
      let s2 = s1
      let mut dup_src = false
      for t in s2 {
        if t == m.translation { dup_src = true }
      }
      if !dup_src {
        s2.push(m.translation)
        by_src.set(m.text, s2)
      }
      let t1 = match by_tgt.get(m.translation) {
        Some(v) => v
        None => []
      }
      let t2 = t1
      let mut dup_tgt = false
      for s in t2 {
        if s == m.text { dup_tgt = true }
      }
      if !dup_tgt {
        t2.push(m.text)
        by_tgt.set(m.translation, t2)
      }
    }
  }
  let conflicts : Array[Json] = []
  // 一词多译
  for src, tgts in by_src.iter2() {
    if tgts.length() > 1 {
      let ts : Array[Json] = Array::map(tgts, fn(t) { str_json(t) })
      conflicts.push(obj([
        ("kind", str_json("one_to_many")),
        ("term", str_json(src)),
        ("translations", arr_json(ts)),
      ]))
    }
  }
  // 多词一译
  for tgt, srcs in by_tgt.iter2() {
    if srcs.length() > 1 {
      let ss : Array[Json] = Array::map(srcs, fn(s) { str_json(s) })
      conflicts.push(obj([
        ("kind", str_json("many_to_one")),
        ("translation", str_json(tgt)),
        ("terms", arr_json(ss)),
      ]))
    }
  }
  arr_json(conflicts)
}

// ===== M1 风格一致性检查（启发式，确定性）=====
// ===== M5 TMPlm：为 LLM prompt 组装检索上下文（三段式，全复用既有能力）=====
// 返回 {"suggestions": TM 相似句, "terms": 术语命中, "glossary": 术语上下文}
pub fn ProphecyEngine::retrieve_for_prompt(
  self : ProphecyEngine,
  query : String,
  k : Int,
  threshold : Double,
) -> Json {
  let suggestions = self.fuzzy_match(query, k, threshold)
  let term_hits = self.enforce_terms(query)
  // glossary：术语 → concordance 上下文（按 id 去重）
  let gloss : Array[Json] = []
  let seen : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
  match term_hits {
    Json::Array(items) =>
      for item in items {
        let term = get_str(item, "term")
        if term != "" {
          let ctx = self.concordance(term, 3)
          match ctx {
            Json::Array(arr) =>
              for c in arr {
                let cid = get_str(c, "id")
                if cid != "" && !seen.contains(cid) {
                  seen.set(cid, true)
                  gloss.push(c)
                }
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  obj([
    ("suggestions", suggestions),
    ("terms", term_hits),
    ("glossary", arr_json(gloss)),
  ])
}

// ===== M5 TMPlm：为 LLM prompt 组装检索上下文（三段式，全复用既有能力）=====
// 返回 {"suggestions": TM 相似句, "terms": 术语命中, "glossary": 术语上下文}