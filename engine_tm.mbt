// engine_tm.mbt
// =====================================================================
// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。
// 主题: add_tm + fuzzy_match 家族 + concordance + load_tbx + enforce/check_terms (#22 TM/TB 一等公民)

// ---- #22 TM/TB 一等公民：翻译记忆检索 + 术语库强制对齐 ----
// 设计：TM 条目 mtype="tm"（text=源, translation=译文）；TB 术语 mtype="term"（text=源术语, translation=目标术语）。
// 二者分离：fuzzy_match/concordance 只检索 tm；enforce_terms/check_terms 只扫 term。

// 加入一条翻译记忆（源 -> 译文），复用 tokenize/tf_vector 建索引
pub fn ProphecyEngine::add_tm(self : ProphecyEngine, src : String, tgt : String) -> String {
  let mid = self._new_id()
  // P0 性能：分词一次，vec / tm_toks / tm_toks_set 共用（原版 vec 与 tm_toks 各分词一次）
  let toks = yimai_tokenize(src)
  let vec = tf_vector(toks)
  let node : MemoryNode = {
    id: mid,
    text: src,
    mtype: "tm",
    vec,
    created: self.clock,
    last_used: self.clock,
    last_active: self.clock,
    use_count: 1,
    feedback: 0.0,
    edges: Map::from_iter(([] : Array[(String, Double)]).iter()),
    predictive_value: 0.0,
    hit_count: 0,
    predict_count: 0,
    is_term: false,
    translation: tgt,
    tm_toks: toks,
    tm_toks_set: to_set(toks),
    tm_ngrams: char_ngram_set(src, 2),
  }
  self.memories.set(mid, node)
  self.invalidate_pred_cache()
  self.fed_add = self.fed_add + 1
  self.mark_tm_idf_dirty()
  mid
}

// TM 模糊匹配：Top-K（按匹配率降序）。升级版评分（S1，对标 XTM Weighted Token Levenshtein 思路）：
//   score = 0.55·idf_dice（IDF 加权共有词权重，罕见术语占优）
//         + 0.20·char_2gram_dice（字符 2-gram，捕捉形态变体，中文 bigram 与分词器一致）
//         + 0.15·token_set_dice（词序容忍：去重集合 Dice，重排场景不惩罚）
//         + 0.10·position（首锚 token 命中，句首对齐权重）
// 低于 threshold（建议阈值 0.70）视为无匹配；返回匹配率%与分项相似度。
// 旧公式保留为 fuzzy_match_legacy（0.7·token-cosine + 0.3·char-ratio）供 A/B 对照。
//
// P1 性能：先按 query 高频 token（IDF 排序 top-3）反查候选 TM（用 tm_postings），
// 仅在候选集上跑四分量；候选集为空（极冷启动：query 词都不在 TM 中）时退回全图。
// 候选集是「高 IDF 词命中」的超集——任何与 query 真匹配的 TM 至少与其中一个高频词有交集
// （否则无法构成 idf_dice 正值），所以 Top-K 完备性保留；不等性来自排序稳定性（同分顺序由 cands 顺序继承），
// 实际中无可见差异。
//
// P1 准确性：weights 可参数化（默认 0.55/0.20/0.15/0.10），配合 ardot 工作台做 A/B 调参。

// 计数 TM 节点（只用于 fuzzy_match 决定是否走剪枝，1K+ 才需要）
// P1 性能：折入 tm_idf 脏标记生命周期——rebuild_tm_idf 重建时顺带刷新缓存，此处 O(1) 读；
//   dirty 时 ensure 触发重建后读（最坏与原 O(N) 扫描同级，稳态零扫描）。
//   所有 TM 集变更点（add_tm/remember/consolidate-prune/restore/from_json）均置脏或全量重建，缓存不失真。
fn ProphecyEngine::count_tm(self : ProphecyEngine) -> Int {
  self.ensure_tm_idf()
  self.tm_count
}

// P4 重构：抽出 fuzzy_match / fuzzy_match_full 公共打分+pack 逻辑到私有 helper
//   - score_one_tm: 算单个 TM 的 sim_tok/sim_ng/sim_ts/sim_pos 加权和; 低于 threshold 返 None
//   - pack_fuzzy_top: 对已排序 cands 抽 Top-K 并 pack JSON（带 sim_tfidf/sim_char 重算）
//   两个 public fn (fuzzy_match / fuzzy_match_full) 只差「是否走 IDF 倒排剪枝」
//   核心打分+pack 共享，确保 R15 排序与 score 分量一致。

// 单 TM 打分：低于 threshold 返 None，否则返 (mid, score, sim_tok, sim_ng, sim_ts)
// P1：q2m/qtokm 为调用方预建的查询侧集合（每 query 一次），节点侧 tm_ngrams/tm_toks_set
//   已是 Map 缓存 → dice_mm 全程零 Map 分配。
fn ProphecyEngine::fuzzy_score_one(
  self : ProphecyEngine,
  mid : String,
  m : MemoryNode,
  qv : Map[String, Double],
  q2m : Map[String, Bool],
  qtokm : Map[String, Bool],
  anchor : String,
  weights : (Double, Double, Double, Double),
  threshold : Double,
) -> Option[(String, Double, Double, Double, Double)] {
  if m.mtype != "tm" { return None }
  let (w_tok, w_ng, w_ts, w_pos) = weights
  let sim_tok = idf_dice(qv, m.vec, self.tm_idf)
  let sim_ng = dice_mm(q2m, m.tm_ngrams)
  let sim_ts = dice_mm(qtokm, m.tm_toks_set)
  let sim_pos = if anchor != "" && term_hit(m.text, anchor) { 1.0 } else { 0.0 }
  let score = w_tok * sim_tok + w_ng * sim_ng + w_ts * sim_ts + w_pos * sim_pos
  if score >= threshold {
    Some((mid, score, sim_tok, sim_ng, sim_ts))
  } else {
    None
  }
}

// 对排序后的 cands 抽 Top-K 并 pack JSON（白盒四分量）
fn ProphecyEngine::fuzzy_pack_top(
  self : ProphecyEngine,
  cands : Array[(String, Double, Double, Double, Double)],
  k : Int,
  query : String,
  qv : Map[String, Double],
) -> Array[Json] {
  pack_topk_json(cands, k, fn(c) {
    let (mid, score, st, sng, sts) = c
    match self.memories.get(mid) {
      Some(m) =>
        Some(obj([
          ("id", str_json(mid)),
          ("source", str_json(m.text)),
          ("target", str_json(m.translation)),
          ("score", num_json(r4(score))),
          ("match_pct", num_json(r4(score * 100.0))),
          ("sim_token", num_json(r4(st))),
          ("sim_tfidf", num_json(r4(tfidf_cosine(qv, m.vec, self.tm_idf)))),
          ("sim_char", num_json(r4(char_ratio(query, m.text)))),
          ("sim_ngram", num_json(r4(sng))),
          ("sim_tokenset", num_json(r4(sts))),
        ]))
      None => None
    }
  })
}

pub fn ProphecyEngine::fuzzy_match(
  self : ProphecyEngine,
  query : String,
  k : Int,
  threshold : Double,
  weights? : (Double, Double, Double, Double) = (0.55, 0.20, 0.15, 0.10),
) -> Json {
  self.ensure_tm_idf()
  // P0 性能：query 只分词一次（原版 tf_vector / unique / first_anchor 各分词一次，共 3 次）
  // P1 性能：查询侧集合（q2m/qtokm）预建一次，打分循环内 dice_mm 零分配
  let qtoks = yimai_tokenize(query)
  let qv = tf_vector(qtoks)
  let q2m = char_ngram_set(query, 2)
  let qtokm = to_set(qtoks)
  let anchor = first_anchor(qtoks)
  let cands : Array[(String, Double, Double, Double, Double)] = []
  // P1 倒排剪枝策略：
  //   1) TM 总量 < PRUNE_MIN_TM：直接全图（IDF 在小语料上区分度低，top-K 容易把全图缩成一个 TM）
  //   2) 候选集为空（qtok 为空 / 无 token 在 postings 中）：退回全图
  //   3) 正常：取 query 唯一 tokens 中 IDF top-3，反查 postings 并集得到候选集
  let tm_total = self.count_tm()
  let use_prune = tm_total >= PRUNE_MIN_TM
  let cand_set = if use_prune {
    fuzzy_candidate_set(self, qtokm, self.tm_idf, 3)
  } else {
    Map::from_iter(([] : Array[(String, Bool)]).iter())
  }
  let pool = if use_prune && cand_set.length() > 0 {
    Some(cand_set)
  } else {
    None
  }
  match pool {
    Some(set) =>
      for mid, _ in set.iter2() {
        match self.memories.get(mid) {
          Some(m) =>
            match self.fuzzy_score_one(mid, m, qv, q2m, qtokm, anchor, weights, threshold) {
              Some(c) => cands.push(c)
              None => ()
            }
          None => ()
        }
      }
    None =>
      for mid, m in self.memories.iter2() {
        match self.fuzzy_score_one(mid, m, qv, q2m, qtokm, anchor, weights, threshold) {
          Some(c) => cands.push(c)
          None => ()
        }
      }
  }
  sort_desc_by_key(cands, fn(c) { c.1 })
  arr_json(self.fuzzy_pack_top(cands, k, query, qv))
}

// P1：全图 fuzzy_match（不剪枝），作为倒排剪枝的「对照基线」，供 A/B 与回归测试用。
// P4 重构：改调公共 helper fuzzy_score_one + fuzzy_pack_top；与 fuzzy_match 共享打分+pack 逻辑，
// 唯一差异是不走 IDF 倒排剪枝路径。
pub fn ProphecyEngine::fuzzy_match_full(self : ProphecyEngine, query : String, k : Int, threshold : Double) -> Json {
  self.ensure_tm_idf()
  // P0 性能：query 只分词一次（原版 tf_vector / unique / first_anchor 各分词一次，共 3 次）
  // P1 性能：查询侧集合（q2m/qtokm）预建一次，打分循环内 dice_mm 零分配
  let qtoks = yimai_tokenize(query)
  let qv = tf_vector(qtoks)
  let q2m = char_ngram_set(query, 2)
  let qtokm = to_set(qtoks)
  let anchor = first_anchor(qtoks)
  let cands : Array[(String, Double, Double, Double, Double)] = []
  for mid, m in self.memories.iter2() {
    match self.fuzzy_score_one(mid, m, qv, q2m, qtokm, anchor, (0.55, 0.20, 0.15, 0.10), threshold) {
      Some(c) => cands.push(c)
      None => ()
    }
  }
  sort_desc_by_key(cands, fn(c) { c.1 })
  arr_json(self.fuzzy_pack_top(cands, k, query, qv))
}

// P1 候选集构造：取 query 唯一 token 按 IDF 降序的前 top_k 个，合并其 postings 得候选 mid 集合。
// 返回 Map[mid, true] 形式，便于 O(1) 查；去重由 map 自然完成。
// 退化路径：qtok 为空 / 所有 IDF 缺失 / postings 全空 → 返回空 Map（caller 检测后走全图）。
// P1：qtok 改传 Map 集合（Map 插入序 = 首现序，与原 unique 数组序一致，选择结果逐位等价）。
fn fuzzy_candidate_set(
  e : ProphecyEngine,
  qtok : Map[String, Bool],
  idf : Map[String, Double],
  top_k : Int,
) -> Map[String, Bool] {
  if qtok.length() == 0 {
    return Map::from_iter(([] : Array[(String, Bool)]).iter())
  }
  // 取 IDF top-k（部分选择法；k 远小于 |qtok|，O(n·k) 已足）
  let picked : Array[String] = []
  for t, _ in qtok.iter2() {
    // 仅考虑 postings 中存在的 token（无 postings 的 token 投出去也无效）
    if e.tm_postings.contains(t) {
      let id = match idf.get(t) {
        Some(x) => x
        None => 1.0
      }
      // 选择：插入 picked 使其按 idf 降序
      let mut inserted = false
      let mut i = 0
      while i < picked.length() {
        let pid = match idf.get(picked[i]) {
          Some(x) => x
          None => 1.0
        }
        if id > pid {
          // 在 i 位置插入
          let mut j = picked.length()
          picked.push("")
          while j > i {
            picked[j] = picked[j - 1]
            j = j - 1
          }
          picked[i] = t
          inserted = true
          break
        }
        i = i + 1
      }
      if !inserted && picked.length() < top_k {
        picked.push(t)
      }
      // 维护 picked 长度 ≤ top_k
      while picked.length() > top_k {
        let _ = picked.pop()
      }
    }
  }
  // 合并 postings
  let cand : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
  for t in picked {
    match e.tm_postings.get(t) {
      Some(mids) =>
        for mid in mids {
          cand.set(mid, true)
        }
      None => ()
    }
  }
  cand
}

// 旧版模糊匹配（S1 之前的公式）：0.7·token-cosine + 0.3·char-ratio。
//
// ⚠️ **A/B 对照基线，长期保留不删除**（2026-08 决策）：
//   - 新代码请用 `fuzzy_match`（P1 增量：S1 公式 + IDF 倒排剪枝）
//   - 本函数保留理由：
//     1) fuzzy_match_full（无剪枝）和 fuzzy_match_legacy（无 IDF 但有剪枝-前一版公式）的回归基线
//     2) 历史 TM/TB 测试集 (R1-R25 部分) 仍引用它作 expected score 对照
//     3) 删除会破坏 4 个引用点（engine.mbt + tests/core/{tm,api_coverage} + README）的平滑迁移
//   - 移除窗口：仅在 fuzzy_match / fuzzy_match_full 完全替代且引用点全部迁移后（≥0.3.0）讨论
pub fn ProphecyEngine::fuzzy_match_legacy(self : ProphecyEngine, query : String, k : Int, threshold : Double) -> Json {
  let qv = tf_vector(yimai_tokenize(query))
  let cands : Array[(String, Double, Double, Double)] = []
  for mid, m in self.memories.iter2() {
    if m.mtype != "tm" {
      continue
    }
    let sim_tok = cosine(qv, m.vec)
    let sim_ch = char_ratio(query, m.text)
    let score = 0.7 * sim_tok + 0.3 * sim_ch
    if score >= threshold {
      cands.push((mid, score, sim_tok, sim_ch))
    }
  }
  sort_desc_by_key(cands, fn(c){ c.1 })
  let out = pack_topk_json(cands, k, fn(c) {
    let (mid, score, st, sc) = c
    match self.memories.get(mid) {
      Some(m) =>
        Some(obj([
          ("id", str_json(mid)),
          ("source", str_json(m.text)),
          ("target", str_json(m.translation)),
          ("score", num_json(r4(score))),
          ("match_pct", num_json(r4(score * 100.0))),
          ("sim_token", num_json(r4(st))),
          ("sim_char", num_json(r4(sc))),
        ]))
      None => None
    }
  })
  arr_json(out)
}

// Concordance 检索：返回含查询词的所有 TM 句段（按词/串出现次数打分）。
// 注意：concordance 的命中度是"词出现度"，与 fuzzy_match 的相似度算法不同（见调研结论）。
pub fn ProphecyEngine::concordance(self : ProphecyEngine, term : String, k : Int) -> Json {
  let q = yimai_tokenize(term)
  let qkey = if q.length() > 0 { q[0] } else { term }
  let cands : Array[(String, Int)] = []
  for mid, m in self.memories.iter2() {
    if m.mtype != "tm" { continue }
    let toks = m.tm_toks
    let mut hits = 0
    for t in toks {
      if t == qkey { hits = hits + 1 }
    }
    if hits == 0 && str_contains(m.text, term) { hits = 1 }
    if hits > 0 { cands.push((mid, hits)) }
  }
  sort_desc_by_key(cands, fn(c){ c.1.to_double() })
  let sorted = cands
  let lim = if k > sorted.length() { sorted.length() } else { k }
  let out : Array[Json] = []
  let mut i = 0
  while i < lim {
    let (mid, hits) = sorted[i]
    match self.memories.get(mid) {
      Some(m) =>
        out.push(obj([
          ("id", str_json(mid)),
          ("source", str_json(m.text)),
          ("target", str_json(m.translation)),
          ("hits", num_json(hits.to_double())),
        ]))
      None => ()
    }
    i = i + 1
  }
  arr_json(out)
}

// 解析 TBX(ISO 30042) 术语库，建立术语节点（text=源术语, translation=目标术语）。
// 支持 TBX 2.0 <ntig><termGrp><term> 与简化 <tig><term>。
// 语言感知：按各 langSet 的 xml:lang 取值（默认源=en-US、目标=zh-CN）；
// 无 xml:lang 时按文档顺序兜底（首 langSet 为源，次为译文）。返回加载的概念条目数。
pub fn ProphecyEngine::load_tbx(
  self : ProphecyEngine,
  xml : String,
  src_lang~ : String = "en-US",
  tgt_lang~ : String = "zh-CN"
) -> Int {
  let mut count = 0
  let entries = split_on(xml, "<termEntry")
  for e in entries {
    let langs = split_on(e, "<langSet")
    let mut src_term = ""
    let mut tgt_term = ""
    let mut fallback_tgt = ""
    for ls in langs {
      let lang = lang_attr(ls)
      let term = first_tag_text(ls, "term")
      if term == "" { continue }
      if lang == src_lang { src_term = term }
      else if lang == tgt_lang { tgt_term = term }
      else if fallback_tgt == "" { fallback_tgt = term }
    }
    if tgt_term == "" { tgt_term = fallback_tgt }
    if src_term != "" {
      let mid = self._new_id()
      let node : MemoryNode = {
        id: mid,
        text: src_term,
        mtype: "term",
        vec: tf_vector(yimai_tokenize(src_term)),
        created: self.clock,
        last_used: self.clock,
        last_active: self.clock,
        use_count: 1,
        feedback: 0.0,
        edges: Map::from_iter(([] : Array[(String, Double)]).iter()),
        predictive_value: 0.0,
        hit_count: 0,
        predict_count: 0,
        is_term: true,
        translation: tgt_term,
        tm_toks: [],
        tm_toks_set: Map([]),
        tm_ngrams: Map([]),
      }
      self.memories.set(mid, node)
      self.invalidate_pred_cache()
      self.mark_term_index_dirty()   // P4-2：新增术语节点，索引需重建
      count = count + 1
    }
  }
  count
}

// 术语强制对齐：扫描文本，返回所有命中已知术语的位置与译文（翻译时高亮/锁定）。
// 用 term_hit 做词边界判定，避免 log⊂logical 这类子串误报。
pub fn ProphecyEngine::enforce_terms(self : ProphecyEngine, text : String) -> Json {
  self.ensure_term_index()
  let cand = self.term_candidates(text)
  let out : Array[Json] = []
  for mid, m in self.memories.iter2() {
    if !m.is_term { continue }
    if !cand.contains(mid) { continue }
    if term_hit(text, m.text) {
      out.push(obj([
        ("term", str_json(m.text)),
        ("translation", str_json(m.translation)),
        ("mid", str_json(mid)),
      ]))
    }
  }
  arr_json(out)
}

// 术语一致性校验：源文识别到的术语，其译文是否出现在译文中；返回违规项。
// 源/译文均用 term_hit 做边界判定，保证拉丁文术语不会因子串包含而误判。
pub fn ProphecyEngine::check_terms(self : ProphecyEngine, source : String, target : String) -> Json {
  self.ensure_term_index()
  let cand = self.term_candidates(source)
  let violations : Array[Json] = []
  for mid, m in self.memories.iter2() {
    if !m.is_term { continue }
    if !cand.contains(mid) { continue }
    if term_hit(source, m.text) && m.translation != "" {
      if !term_hit(target, m.translation) {
        violations.push(obj([
          ("term", str_json(m.text)),
          ("expected", str_json(m.translation)),
          ("mid", str_json(mid)),
        ]))
      }
    }
  }
  arr_json(violations)
}

