// engine_index.mbt
// =====================================================================
// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。
// 主题: TM 文档频率/IDF/term 倒排索引（fuzzy 倒排剪枝与 enforce/check 加速依赖）

// ---- S1 检索强化：TM IDF 表（确定性重建，逻辑时钟无关）----

// 全量重建 TM 文档频率 / IDF / 倒排（幂等；add_tm/consolidate-prune/restore/from_json 后触发）。
// P1：同一遍 O(N·|Q|) 扫描顺手把 token -> mids 倒排也建好，给 fuzzy_match 候选剪枝用，
// 避免二次扫描（成本约为 N·|Q| token 遍历，本就绕不开）。
// P1：复用节点缓存的 m.tm_toks（调用前须保证特征缓存新鲜——from_json 先 features 后 idf，
//   其余写路径均在置脏前已同步 tm_toks）；顺带刷新 tm_count 供 count_tm O(1) 读。
fn ProphecyEngine::rebuild_tm_idf(self : ProphecyEngine) -> Unit {
  let df : Map[String, Int] = Map::from_iter(([] : Array[(String, Int)]).iter())
  let postings : Map[String, Array[String]] =
    Map::from_iter(([] : Array[(String, Array[String])]).iter())
  let mut n = 0
  for mid, m in self.memories.iter2() {
    if m.mtype != "tm" {
      continue
    }
    n = n + 1
    let seen : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
    for t in m.tm_toks {
      if seen.contains(t) {
        continue
      }
      seen.set(t, true)
      let v = match df.get(t) {
        Some(x) => x
        None => 0
      }
      df.set(t, v + 1)
      // P1 倒排：mid 去重后入 postings（同一 TM 含重复 token 不重复推 mid）
      match postings.get(t) {
        Some(arr) =>
          if !arr_contains(arr, mid) {
            arr.push(mid)
          }
        None => {
          let a : Array[String] = [mid]
          postings.set(t, a)
        }
      }
    }
  }
  self.tm_df = df
  let idf : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  for t, f in self.tm_df.iter2() {
    // idf = ln((N+1)/(df+1)) + 1：常见词（df 高）权重低，罕见术语（df 低）权重高；N=0 时 idf=1
    idf.set(t, @math.ln((n + 1).to_double() / (f + 1).to_double()) + 1.0)
  }
  self.tm_idf = idf
  self.tm_postings = postings
  self.tm_count = n
  self.tm_idf_dirty = false
}

fn ProphecyEngine::mark_tm_idf_dirty(self : ProphecyEngine) -> Unit {
  self.tm_idf_dirty = true
}

// 惰性重算：fuzzy_match 开头调用，仅当 dirty 时全量重建（保证每次 fuzzy_match 的 IDF/postings 表新鲜）
fn ProphecyEngine::ensure_tm_idf(self : ProphecyEngine) -> Unit {
  if self.tm_idf_dirty {
    self.rebuild_tm_idf()
  }
}

// 全量重建 TM 特征缓存（幂等；from_json 后调用，使 tm_toks/tm_ngrams 与重建的 IDF 表对齐）
fn ProphecyEngine::rebuild_tm_features(self : ProphecyEngine) -> Unit {
  for mid, m in self.memories.iter2() {
    if m.mtype != "tm" {
      continue
    }
    let m2 = m
    m2.tm_toks = yimai_tokenize(m.text)
    m2.tm_toks_set = to_set(m2.tm_toks)
    m2.tm_ngrams = char_ngram_set(m.text, 2)
    self.memories.set(mid, m2)
  }
}

// ---- P4-2 术语首字符倒排（内部态，不进 to_json；惰性重建，幂等）----

fn ProphecyEngine::mark_term_index_dirty(self : ProphecyEngine) -> Unit {
  self.term_idx_dirty = true
}

fn ProphecyEngine::ensure_term_index(self : ProphecyEngine) -> Unit {
  if self.term_idx_dirty {
    self.rebuild_term_index()
  }
}

fn ProphecyEngine::rebuild_term_index(self : ProphecyEngine) -> Unit {
  let idx : Map[String, Array[String]] = Map::from_iter(([] : Array[(String, Array[String])]).iter())
  for mid, m in self.memories.iter2() {
    if !m.is_term || m.text.length() == 0 {
      continue
    }
    // 与 term_candidates 的 text.iter() 同路径取首字符（统一按 Unicode 标量，避免切片语义差异）
    let c = match m.text.iter().next() {
      Some(ch) => ch.to_string()
      None => continue
    }
    match idx.get(c) {
      Some(arr) => arr.push(mid)
      None => {
        let a : Array[String] = [mid]
        idx.set(c, a)
      }
    }
  }
  self.term_idx = idx
  self.term_idx_dirty = false
}

// 收集 text 首字符能命中的候选 term mid 集合（按首字符索引粗筛）。
// 完备性：term_hit(text,term)=true ⟹ term[0] 必作为字符出现在 text 中（CJK 子串 / 拉丁边界均成立），
// 故候选集合是超集；终判仍用 term_hit 精确复验，保证输出与全量扫描逐项等价。
fn ProphecyEngine::term_candidates(self : ProphecyEngine, text : String) -> Map[String, Bool] {
  let cand : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
  let seen : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
  for ch in text.iter() {
    let c = ch.to_string()
    if seen.contains(c) {
      continue
    }
    seen.set(c, true)
    match self.term_idx.get(c) {
      Some(mids) =>
        for mid in mids {
          cand.set(mid, true)
        }
      None => ()
    }
  }
  cand
}

// IDF 加权集合 Dice = 2·Σ_{t∈A∩B} idf(t) / (Σ_{t∈A} idf(t) + Σ_{t∈B} idf(t))。
// fuzzy_match 主评分项：关注共有词的权重（罕见术语权重高），对 query 独有词的
// 范数惩罚比 TF-IDF 余弦更宽容，短句/中文 bigram 场景更稳。
fn idf_dice(
  qvec : Map[String, Double],
  mvec : Map[String, Double],
  idf : Map[String, Double],
) -> Double {
  if qvec.length() == 0 || mvec.length() == 0 {
    return 0.0
  }
  let mut inter_w = 0.0
  let mut qw = 0.0
  let mut mw = 0.0
  for k, _ in qvec.iter2() {
    let id = match idf.get(k) {
      Some(x) => x
      None => 1.0
    }
    qw = qw + id
    if mvec.contains(k) {
      inter_w = inter_w + id
    }
  }
  for k, _ in mvec.iter2() {
    let id = match idf.get(k) {
      Some(x) => x
      None => 1.0
    }
    mw = mw + id
  }
  if qw == 0.0 || mw == 0.0 {
    return 0.0
  }
  2.0 * inter_w / (qw + mw)
}

// TF-IDF 加权余弦：qvec/mvec 存纯 TF，计算时实时乘 IDF（零依赖，不改变节点向量存储）。
// 作为 fuzzy_match 输出的信息性分项（sim_tfidf），供调用方对比。
fn tfidf_cosine(
  qvec : Map[String, Double],
  mvec : Map[String, Double],
  idf : Map[String, Double],
) -> Double {
  if qvec.length() == 0 || mvec.length() == 0 {
    return 0.0
  }
  let mut num = 0.0
  for k, qv in qvec.iter2() {
    let id = match idf.get(k) {
      Some(x) => x
      None => 1.0
    }
    match mvec.get(k) {
      Some(mv) => num = num + (qv * id) * (mv * id)
      None => ()
    }
  }
  if num == 0.0 {
    return 0.0
  }
  let mut na2 = 0.0
  for k, v in qvec.iter2() {
    let id = match idf.get(k) {
      Some(x) => x
      None => 1.0
    }
    na2 = na2 + (v * id) * (v * id)
  }
  let mut nb2 = 0.0
  for k, v in mvec.iter2() {
    let id = match idf.get(k) {
      Some(x) => x
      None => 1.0
    }
    nb2 = nb2 + (v * id) * (v * id)
  }
  let na = na2.sqrt()
  let nb = nb2.sqrt()
  if na == 0.0 || nb == 0.0 {
    return 0.0
  }
  num / (na * nb)
}

