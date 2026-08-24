// engine_learn.mbt
// =====================================================================
// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。
// 主题: remember/observe/predict/recall + value breakdown + 偏置/对比学习/attention/mark_term/reward (D1–D8 学习+预测核心)

// ---------------------------------------------------------------------------
// D1 突触图谱：写入 + 建边 + 赫布学习
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::remember(
  self : ProphecyEngine,
  text : String,
  mtype : String,
  ctx : Array[String],
) -> String {
  self.clock = self.clock + 1.0
  // P0 性能：分词一次，vec / tm_toks / tm_toks_set 共用（原版 new/merge 分支各自再分词）
  let toks = yimai_tokenize(text)
  let vec = tf_vector(toks)
  let mut best = ""
  let mut best_sim = 0.0
  for mid, m in self.memories.iter2() {
    let s = cosine(vec, m.vec)
    if s > best_sim {
      best = mid
      best_sim = s
    }
  }
  if best != "" && best_sim > DEDUP_SIM {
    let m = self.memories[best]
    m.text = text
    m.vec = vec
    // 若合并目标是 TM 节点，text 已改写，须同步重建特征缓存并刷新 IDF（P2-2）
    if m.mtype == "tm" {
      m.tm_toks = toks
      m.tm_toks_set = to_set(toks)
      m.tm_ngrams = char_ngram_set(m.text, 2)
      self.mark_tm_idf_dirty()
    }
    if m.is_term {
      self.mark_term_index_dirty()   // P4-2：术语 text 被改写，首字符索引可能失配
    }
    m.use_count = m.use_count + 1
    m.last_used = self.clock
    m.last_active = self.clock
    // role_index 增量维护：对 text 全部角色粒度 set 到合并节点（role_index 是序列化字段，
    // 保持与新建分支 L713-717 的一致，非主角色条目同样重指向 best）
    self.role_index.set(role_of(text), best)
    for rk in roles_of(text) {
      self.role_index.set(rk, best)
    }
    self.memories.set(best, m)
    // P4-1：text 已改写，role_members 全量重建（清掉旧角色残留 mid；本索引内部态不进
    // to_json，只做角色限定召回的剪枝，幂等/确定性零影响；与 consolidate/restore 同源）
    self.rebuild_role_members()
    self._wire(best, ctx)
    self.wal_append("remember" + WAL_SEP + best + WAL_SEP + wal_escape_field(text) + WAL_SEP + wal_escape_field(mtype))
    self.invalidate_pred_cache()
    self.fed_upd = self.fed_upd + 1
    return best
  }
  let mid = self._new_id()
  let node : MemoryNode = {
    id: mid,
    text,
    mtype,
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
    translation: "",
    tm_toks: if mtype == "tm" { toks } else { [] },
    tm_toks_set: if mtype == "tm" { to_set(toks) } else { Map([]) },
    tm_ngrams: if mtype == "tm" { char_ngram_set(text, 2) } else { Map([]) },
  }
  if mtype == "tm" {
    self.mark_tm_idf_dirty()
  }
  self.role_index.set(role_of(text), mid)
  for rk in roles_of(text) {
    self.role_index.set(rk, mid)
    self.role_members_add(rk, mid)
  }
  self.wal_append("remember" + WAL_SEP + mid + WAL_SEP + wal_escape_field(text) + WAL_SEP + wal_escape_field(mtype))
  self.invalidate_pred_cache()
  self.memories.set(mid, node)
  self._wire(mid, ctx)
  self.stats_remembers = self.stats_remembers + 1
  self.fed_add = self.fed_add + 1
  mid
}

// 概念抽象：角色抽取（前 4 字）
// role_of 已在 util.mbt 定义

// 共现即建边：一起出现的记忆，其突触加权（fire together, wire together）
fn ProphecyEngine::_wire(self : ProphecyEngine, mid : String, ctx : Array[String]) -> Unit {
  if ctx.length() == 0 {
    return
  }
  for a in ctx {
    if a == mid {
      continue
    }
    match self.memories.get(a) {
      None => ()
      Some(_) => {
        let m = self.memories[mid]
        let w = match m.edges.get(a) { Some(x) => x; None => 0.0 }
        m.edges.set(a, clamp01(w + self.hebb_lr * (1.0 - w)))
        self.memories.set(mid, m)
        let na = self.memories[a]
        let w2 = match na.edges.get(mid) { Some(x) => x; None => 0.0 }
        na.edges.set(mid, clamp01(w2 + self.hebb_lr * (1.0 - w2)))
        self.memories.set(a, na)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// D2 激活扩散召回
// ---------------------------------------------------------------------------

fn pack_recall(
  m : MemoryNode,
  score : Double,
  act : Double,
  via : Array[Json],
) -> Json {
  obj([
    ("id", str_json(m.id)),
    ("text", str_json(m.text)),
    ("type", str_json(m.mtype)),
    ("score", num_json(r4(score))),
    ("activation", num_json(r4(act))),
    ("via_edges", arr_json(via)),
  ])
}

pub fn ProphecyEngine::recall(
  self : ProphecyEngine,
  query : String,
  k : Int,
) -> Array[Json] {
  let qvec = tf_vector(yimai_tokenize(query))
  // 降级：网络过小则退化为 1.0 余弦 Top-K
  if self.memories.length() < MIN_GRAPH {
    let scored : Array[(String, Double)] = []
    for mid, m in self.memories.iter2() {
      scored.push((mid, cosine(qvec, m.vec)))
    }
    sort_desc_by_key(scored, fn(x){ x.1 })
    let out : Array[Json] = []
    let lim = if k < scored.length() { k } else { scored.length() }
    for i = 0; i < lim; i = i + 1 {
      let mid = scored[i].0
      match self.memories.get(mid) {
        Some(m) => out.push(pack_recall(m, 0.0, 0.0, []))
        None => ()
      }
    }
    return out
  }
  // 种子：先按角色索引（role_members）剪枝候选池（S2），空池降级全图
  let role_keys = roles_of(query)
  let pool : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
  for rk in role_keys {
    match self.role_members.get(rk) {
      Some(mids) =>
        for mid in mids {
          pool.set(mid, true)
        }
      None => ()
    }
  }
  let sims : Array[(String, Double)] = []
  if pool.length() > 0 {
    for mid, _ in pool.iter2() {
      match self.memories.get(mid) {
        Some(m) => {
          let s = cosine(qvec, m.vec)
          if s > 0.05 {
            sims.push((mid, s))
          }
        }
        None => ()
      }
    }
  } else {
    // 降级：全图扫描（角色索引为空时保持原行为）
    for mid, m in self.memories.iter2() {
      let s = cosine(qvec, m.vec)
      if s > 0.05 {
        sims.push((mid, s))
      }
    }
  }
  if sims.length() == 0 {
    let all : Array[(String, Int)] = []
    for mid, m in self.memories.iter2() {
      all.push((mid, m.use_count))
    }
    sort_desc_by_key(all, fn(x){ x.1.to_double() })
    for i = 0; i < 3 && i < all.length(); i = i + 1 {
      sims.push((all[i].0, 0.05))
    }
  }
  sort_desc_by_key(sims, fn(x){ x.1 })
  let seeds : Array[String] = []
  for i = 0; i < 3 && i < sims.length(); i = i + 1 {
    seeds.push(sims[i].0)
  }
  // 扩散
  let mut act : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  for s in seeds {
    // 术语节点高初始激活（+5.0），使其在联想召回中优先浮出（美：术语命中高亮）
    let boost = match self.memories.get(s) {
      Some(m) => if m.is_term { 5.0 } else { 1.0 }
      None => 1.0
    }
    act.set(s, boost)
  }
  for _step = 0; _step < SPREAD_STEPS; _step = _step + 1 {
    let newm : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
    for nid, a in act.iter2() {
      newm.set(nid, a)
    }
    for nid, a in act.iter2() {
      match self.memories.get(nid) {
        Some(m) =>
          for nb, w in m.edges.iter2() {
            // 注意力边权：相似度 + 角色匹配调制扩散（attn_alpha/beta=0 时退化为原行为）
            let attn = if self.attn_alpha == 0.0 && self.attn_beta == 0.0 {
              1.0
            } else {
              match self.memories.get(nb) {
                Some(nbm) => {
                  let simqn = cosine(qvec, nbm.vec)
                  let rmatch = if role_of(m.text) == role_of(nbm.text) { 1.0 } else { 0.0 }
                  @math.exp(self.attn_alpha * simqn + self.attn_beta * rmatch)
                }
                None => 1.0
              }
            }
            let contrib = a * w * SPREAD_DECAY * attn
            if contrib > 0.01 {
              let cur = match newm.get(nb) { Some(x) => x; None => 0.0 }
              newm.set(nb, if contrib > cur { contrib } else { cur })
            }
          }
        None => ()
      }
    }
    act = newm
  }
  // 排序：激活 × (0.3 + 0.7*预测价值)
  let scored : Array[(String, Double, Double, Array[Json])] = []
  for mid, a in act.iter2() {
    match self.memories.get(mid) {
      Some(m) => {
        let score = a * (0.3 + 0.7 * m.predictive_value)
        let via : Array[Json] = []
        for nb, w in m.edges.iter2() {
          if act.contains(nb) {
            via.push(obj([("to", str_json(nb)), ("w", num_json(r4(w)))]))
          }
        }
        scored.push((mid, score, a, via))
      }
      None => ()
    }
  }
  sort_desc_by_key(scored, fn(x){ x.1 })
  let out : Array[Json] = []
  let lim = if k < scored.length() { k } else { scored.length() }
  for i = 0; i < lim; i = i + 1 {
    let (mid, score, a, via) = scored[i]
    match self.memories.get(mid) {
      Some(m) => out.push(pack_recall(m, score, a, via))
      None => ()
    }
  }
  out
}

// ---------------------------------------------------------------------------
// D3 预测前向模型 + D7 不确定性
// ---------------------------------------------------------------------------

// P4 重构：把 predict 269 行拆为 3 段私有 fn
//   - collect_activations: 上下文→激活权重（最近项权重最高）
//   - aggregate_transitions: 一阶转移 + D8 角色回退聚合到 score+path
//   - rank_and_pack: 归一化 + 排名 + 熵 + pack Json（含 predict_count 积累）
//   predict 主体只做缓存、orchestrator 与缓存写；保留 R15 排序依赖（Map 插入序）

// 收集上下文激活：context 中每个 mid 获得 (1+1/n)^exp 形式的近期权重（取最大，重复 mid 不重复加权）
fn ProphecyEngine::predict_collect_activations(self : ProphecyEngine) -> Map[String, Double] {
  let act : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  let n = self.context.length()
  if n == 0 { return act }
  let exp = 2.0 - self.explore               // 元认知：探索度高时降低幂次->更广利用
  for i = 0; i < n; i = i + 1 {
    let mid = self.context[i]
    match self.memories.get(mid) {
      Some(_) => {
        let base = (i + 1).to_double() / n.to_double()
        let w = @math.pow(base, exp)
        let cur = match act.get(mid) { Some(x) => x; None => 0.0 }
        act.set(mid, if w > cur { w } else { cur })
      }
      None => ()
    }
  }
  act
}

// 一阶转移 + D8 角色回退聚合到 score + path（in-place 修改）
//   转移动作（含 Top-8 剪枝快路径）后，紧接 D8 概念抽象回退：具体转移稀疏时用
//   角色级 (role_trans × role_index) 规律补位，权重 0.5。
fn ProphecyEngine::predict_aggregate_transitions(
  self : ProphecyEngine,
  act : Map[String, Double],
  score : Map[String, Double],
  path : Map[String, Array[Json]],
) -> Unit {
  for a, aw in act.iter2() {
    let tt : Double = match self.transitions.get(a) {
      Some(trans) => {
        let mut tot = 0.0
        for _, c in trans.iter2() {
          tot = tot + c
        }
        let tt0 = if tot == 0.0 { 1.0 } else { tot }
        // 快：每源 Top-K(=8) 剪枝候选，大图下显著降低聚合开销（≤8 时不触发，保证小图行为不变）
        let keep : Array[String] = []
        if trans.length() > 8 {
          let allc : Array[(String, Double)] = []
          for dst, c in trans.iter2() {
            allc.push((dst, c))
          }
          sort_desc_by_key(allc, fn(x){ x.1 })
          let kp = if 8 < allc.length() { 8 } else { allc.length() }
          for i = 0; i < kp; i = i + 1 {
            keep.push(allc[i].0)
          }
        }
        for dst, c in trans.iter2() {
          if keep.length() > 0 && !arr_contains(keep, dst) {
            continue
          }
          let p = c / tt0
          let cur = match score.get(dst) { Some(x) => x; None => 0.0 }
          score.set(dst, cur + aw * p)
          let arr = match path.get(dst) {
            Some(x) => x
            None => {
              let na : Array[Json] = []
              path.set(dst, na)
              na
            }
          }
          arr.push(obj([("from", str_json(a)), ("p", num_json(r4(p)))]))
        }
        tt0
      }
      None => 1.0
    }
    // D8 概念抽象回退：具体转移稀疏(冷启动)时用角色级规律补位
    // 注意：无具体转移时 tt=1.0，同样进入回退（对应 D8 角色级补位的空转移兜底）
    if tt <= 1.0 {
      match self.memories.get(a) {
        Some(na) => {
          for ra in roles_of(na.text) {
            if ra == "" {
              continue
            }
            match self.role_trans.get(ra) {
              Some(rtrans) => {
                let mut rtot = 0.0
                for _, c in rtrans.iter2() {
                  rtot = rtot + c
                }
                let rtt = if rtot == 0.0 { 1.0 } else { rtot }
                for rb, c in rtrans.iter2() {
                  match self.role_index.get(rb) {
                    Some(tgt) =>
                      match self.memories.get(tgt) {
                        Some(_) => {
                          let rp = c / rtt
                          let cur = match score.get(tgt) { Some(x) => x; None => 0.0 }
                          score.set(tgt, cur + aw * rp * 0.5)
                          let arr = match path.get(tgt) {
                            Some(x) => x
                            None => {
                              let na2 : Array[Json] = []
                              path.set(tgt, na2)
                              na2
                            }
                          }
                          arr.push(obj([("from", str_json(a + "(role:" + ra + ")")), ("p", num_json(r4(rp)))]))
                        }
                        None => ()
                      }
                    None => ()
                  }
                }
              }
              None => ()
            }
          }
        }
        None => ()
      }
    }
  }
  // 二阶马尔可夫：以最近一对 (prev2, prev1) 作上下文，叠加 P(w3|w1,w2)
  let nctx = self.context.length()
  if nctx >= 2 {
    let p1 = self.context[nctx - 1]
    let p2 = self.context[nctx - 2]
    let key2 = p2 + "::" + p1
    match self.trans2.get(key2) {
      Some(t2) => {
        let mut tot2 = 0.0
        for _, c in t2.iter2() {
          tot2 = tot2 + c
        }
        let tt2 = if tot2 == 0.0 { 1.0 } else { tot2 }
        let lam = 0.4
        for w3, c in t2.iter2() {
          let p = c / tt2
          let cur = match score.get(w3) { Some(x) => x; None => 0.0 }
          score.set(w3, cur + lam * p)
          let arr = match path.get(w3) {
            Some(x) => x
            None => {
              let na3 : Array[Json] = []
              path.set(w3, na3)
              na3
            }
          }
          arr.push(obj([("from", str_json(p2 + ">" + p1 + "(2nd)")), ("p", num_json(r4(p)))]))
        }
      }
      None => ()
    }
  }
  // 领域偏置 ΔW：按目标节点多粒度角色原型注入先验（LoRA 式；初值为 0 不影响基线）
  let sbias : Array[String] = []
  for d, _ in score.iter2() {
    sbias.push(d)
  }
  for d in sbias {
    match self.memories.get(d) {
      Some(mn) => {
        let mut bias = 0.0
        for rk in roles_of(mn.text) {
          bias = bias + (match self.domain_bias.get(rk) { Some(x) => x; None => 0.0 })
        }
        if bias != 0.0 {
          let cur = match score.get(d) { Some(x) => x; None => 0.0 }
          score.set(d, cur + bias)
        }
      }
      None => ()
    }
  }
  // 归一化（in-place 修改 score）
  let mut z = 0.0
  for _, v in score.iter2() {
    z = z + v
  }
  let znorm = if z == 0.0 { 1.0 } else { z }
  let ks : Array[String] = []
  for d, _ in score.iter2() {
    ks.push(d)
  }
  for d in ks {
    let v = match score.get(d) { Some(x) => x; None => 0.0 }
    score.set(d, v / znorm)
  }
}

// 排名 + 熵 + pack Json；副作用：更新 self.stats_preds/last_pred、topk mid 的 predict_count
fn ProphecyEngine::predict_rank_and_pack(
  self : ProphecyEngine,
  score : Map[String, Double],
  path : Map[String, Array[Json]],
  k : Int,
) -> (Json, Array[String]) {
  // 排名
  let ranked : Array[(String, Double)] = []
  for d, v in score.iter2() {
    ranked.push((d, v))
  }
  sort_desc_by_key(ranked, fn(x){ x.1 })
  let topk : Array[String] = []
  let lim = if k < ranked.length() { k } else { ranked.length() }
  for i = 0; i < lim; i = i + 1 {
    topk.push(ranked[i].0)
  }
  if topk.length() > 0 {
    self.stats_preds = self.stats_preds + 1
    self.last_pred = topk
  } else {
    self.last_pred = []
  }
  // 预测效用积累
  for d in topk {
    match self.memories.get(d) {
      Some(m) => {
        m.predict_count = m.predict_count + 1
        self.memories.set(d, m)
      }
      None => ()
    }
  }
  // D7 不确定性：基于【全量归一化分布】的熵
  //    （F3：原实现仅取 Top-K，极端偏态分布下严重低估不确定性）
  let mut entropy = 0.0
  for i = 0; i < ranked.length(); i = i + 1 {
    let p = ranked[i].1
    if p > 0.0 {
      entropy = entropy - p * @math.ln(p + 0.000000001)
    }
  }
  let preds : Array[Json] = []
  for i = 0; i < lim; i = i + 1 {
    let (mid, p) = ranked[i]
    match self.memories.get(mid) {
      Some(m) =>
        preds.push(obj([
          ("id", str_json(mid)),
          ("text", str_json(m.text)),
          ("prob", num_json(r4(p))),
          ("path", arr_json(match path.get(mid) { Some(x) => x; None => [] })),
        ]))
      None => ()
    }
  }
  let out = obj([
    ("predictions", arr_json(preds)),
    ("confidence", num_json(if preds.length() > 0 { r4(ranked[0].1) } else { 0.0 })),
    ("uncertainty", num_json(r4(entropy))),
  ])
  (out, topk)
}

pub fn ProphecyEngine::predict(self : ProphecyEngine, k : Int) -> Json {
  // 快：预测缓存（相同上下文签名且引擎未变更时直接返回，跳过转移聚合；引擎变更时全量失效，非 LRU）
  let ckeyb = StringBuilder()
  for i = 0; i < self.context.length(); i = i + 1 {
    if i > 0 {
      ckeyb.write_char('|')
    }
    ckeyb.write_string(self.context[i])
  }
  let ckey = ckeyb.to_string() + "|k" + k.to_string()
  match self.pred_cache.get(ckey) {
    Some(cached) => {
      let out = get_obj(cached, "out")
      let topk = get_str_arr(cached, "topk")
      if topk.length() > 0 {
        self.stats_preds = self.stats_preds + 1
        self.last_pred = topk
      } else {
        self.last_pred = []
      }
      for d in topk {
        match self.memories.get(d) {
          Some(m) => {
            m.predict_count = m.predict_count + 1
            self.memories.set(d, m)
          }
          None => ()
        }
      }
      return out
    }
    None => ()
  }
  // 3 段编排（参见对应 fn 注释）：collect → aggregate (含 2nd-order + 偏置 + 归一化) → rank+pack
  let act = self.predict_collect_activations()
  let score : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  let path : Map[String, Array[Json]] =
    Map::from_iter(([] : Array[(String, Array[Json])]).iter())
  self.predict_aggregate_transitions(act, score, path)
  let (out, topk) = self.predict_rank_and_pack(score, path, k)
  // 容量守卫：pred_cache 超上限时清空（内部态，零确定性影响；防长跑无界增长）
  if self.pred_cache.length() >= PRED_CACHE_MAX {
    self.pred_cache = Map::from_iter(([] : Array[(String, Json)]).iter())
  }
  self.pred_cache.set(ckey, obj([("out", out), ("topk", arr_json(topk.map(fn(s) { str_json(s) })))]))
  out
}

// ---------------------------------------------------------------------------
// observe：记住真实下一步 + 更新转移 + 命中核算
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::observe(
  self : ProphecyEngine,
  text : String,
  mtype : String,
) -> String {
  // 时钟语义（P4-1 修正）：一次 observe 推进一个逻辑时刻（+1）。
  // remember 内部已自增（L652），故此处不再单独自增，避免每次 observe 竟 +2。
  let mid = self.remember(text, mtype, self.context)
  // D3 转移计数：仅由「紧邻前驱」建立一阶马尔可夫边
  if self.context.length() > 0 {
    let prev = self.context[self.context.length() - 1]
    match self.memories.get(prev) {
      Some(_) => {
        inc_trans(self.transitions, prev, mid)
        // 二阶马尔可夫：最近一对 (prev2, prev) -> mid
        if self.context.length() >= 2 {
          let prev2 = self.context[self.context.length() - 2]
          inc_trans(self.trans2, prev2 + "::" + prev, mid)
        }
        // D8 概念抽象：同时记录多粒度角色级转移
        match self.memories.get(prev) {
          Some(pn) =>
            match self.memories.get(mid) {
              Some(mn) => {
                let ras = roles_of(pn.text)
                let rbs = roles_of(mn.text)
                for ra in ras {
                  if ra == "" {
                    continue
                  }
                  for rb in rbs {
                    if rb != "" {
                      inc_trans(self.role_trans, ra, rb)
                    }
                  }
                }
              }
              None => ()
            }
          None => ()
        }
      }
      None => ()
    }
  }
  // 命中核算（元认知滚动窗口）
  if self.last_pred.length() > 0 {
    let hit = arr_contains(self.last_pred, mid)
    if hit {
      self.stats_hits = self.stats_hits + 1
        match self.memories.get(mid) {
          Some(m) => {
            m.hit_count = m.hit_count + 1
            m.last_active = self.clock
            self.memories.set(mid, m)
          }
          None => ()
        }
    }
    self.meta_hits.push(if hit { 1 } else { 0 })
    if self.meta_hits.length() > 200 {
      let _ = self.meta_hits.remove(0)
    }
    self.last_pred = []
  }
  self.cur_episode.push(mid)
  self.context.push(mid)
  if self.context.length() > CTX_WINDOW {
    let _ = self.context.remove(0)
  }
  self.wal_append("observe" + WAL_SEP + mid + WAL_SEP + wal_escape_field(text) + WAL_SEP + wal_escape_field(mtype))
  self.fed_upd = self.fed_upd + 1
  self.invalidate_pred_cache()
  mid
}

pub fn ProphecyEngine::end_episode(self : ProphecyEngine) -> Unit {
  if self.cur_episode.length() > 0 {
    self.episodes.push(self.cur_episode)
    self.cur_episode = []
  }
}

// ---------------------------------------------------------------------------
// D4 预测价值定价
// ---------------------------------------------------------------------------

// 节点命中率：predict_count>0 时取 hit/predict，否则 0（多处复用的确定性公式）
fn hit_rate_of(m : MemoryNode) -> Double {
  if m.predict_count > 0 {
    m.hit_count.to_double() / m.predict_count.to_double()
  } else {
    0.0
  }
}

// 预测价值分解（D4）。单一事实源，供 _recompute_values（写回 predictive_value）
// 与 explain_card（白盒展示）共用，消除原先两处重复的内联计算。
fn ProphecyEngine::value_breakdown(
  self : ProphecyEngine,
  m : MemoryNode,
) -> ValueBreakdown {
  let now = self.clock
  let u_freq = m.use_count.to_double() / (m.use_count.to_double() + 5.0)
  let dt = now - m.last_used
  let u_rec = if dt < 0.0 { 1.0 } else { clamp01(@math.exp(-dt / REC_TAU)) }
  let u_fb = clamp01((m.feedback + 1.0) / 2.0)
  let u_past = 0.5 * u_freq + 0.3 * u_rec + 0.2 * u_fb
  let hr = hit_rate_of(m)
  let mut tot = 0.0
  match self.transitions.get(m.id) {
    Some(trans) => for _, c in trans.iter2() { tot = tot + c }
    None => ()
  }
  let out_str = min1(tot / (tot + 10.0))
  let u_pred = 0.6 * hr + 0.4 * out_str
  let mut esum = 0.0
  for _, w in m.edges.iter2() {
    esum = esum + w
  }
  let c_graph = min1(esum / 5.0)
  {
    u_freq: u_freq,
    u_rec: u_rec,
    u_fb: u_fb,
    u_past: u_past,
    u_pred: u_pred,
    c_graph: c_graph,
  }
}

fn ProphecyEngine::_recompute_values(self : ProphecyEngine) -> Unit {
  for mid, m in self.memories.iter2() {
    let vb = self.value_breakdown(m)
    let cost = @math.ln(1.0 + self.memories.length().to_double()) / 20.0
    let vval =
      ALPHA * vb.u_past + BETA * vb.u_pred + GAMMA * vb.c_graph + DELTA * vb.u_fb - EPS * cost
    let m2 = m
    m2.predictive_value = clamp01(if vval > 0.0 { vval } else { 0.0 })
    self.memories.set(mid, m2)
  }
}

// ---------------------------------------------------------------------------
// 进化引擎·感知器：成功/失败信号进入预测价值
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::reward(
  self : ProphecyEngine,
  mid : String,
  score_in : Double,
) -> Bool {
  match self.memories.get(mid) {
    Some(m) => {
      let s = if score_in > 1.0 {
        1.0
      } else if score_in < -1.0 {
        -1.0
      } else {
        score_in
      }
      let m2 = m
      m2.feedback = 0.7 * m2.feedback + 0.3 * s
      self.memories.set(mid, m2)
      self._recompute_values()
      self.invalidate_pred_cache()
      self.fed_upd = self.fed_upd + 1
      true
    }
    None => false
  }
}

// ---------------------------------------------------------------------------
// #19 准：领域偏置 ΔW / 在线对比学习 / 注意力边权（对外接口）
// ---------------------------------------------------------------------------

// 领域偏置 ΔW：按角色原型注入先验（外部蒸馏 / 对比学习收敛后写入）
pub fn ProphecyEngine::set_domain_bias(
  self : ProphecyEngine,
  role : String,
  delta : Double,
) -> Unit {
  if role == "" {
    return
  }
  self.domain_bias.set(role, delta)
  self.invalidate_pred_cache()
}

// 在线对比学习单步：增强 (anchor,positive)，抑制 (anchor,negative)
// 调用方可据 D7 不确定性动态调节 lr；高不确定时对比信号更强
pub fn ProphecyEngine::cl_step(
  self : ProphecyEngine,
  anchor : String,
  positive : String,
  negative : String,
) -> Unit {
  match self.memories.get(anchor) {
    Some(a) => {
      let w = match a.edges.get(positive) { Some(x) => x; None => 0.0 }
      a.edges.set(positive, clamp01(w + self.hebb_lr))
      self.memories.set(anchor, a)
    }
    None => ()
  }
  match self.memories.get(positive) {
    Some(p) => {
      let w = match p.edges.get(anchor) { Some(x) => x; None => 0.0 }
      p.edges.set(anchor, clamp01(w + self.hebb_lr))
      self.memories.set(positive, p)
    }
    None => ()
  }
  match self.memories.get(anchor) {
    Some(a) => {
      let w = match a.edges.get(negative) { Some(x) => x; None => 0.0 }
      a.edges.set(negative, clamp01(w - self.hebb_lr * 0.5))
      self.memories.set(anchor, a)
    }
    None => ()
  }
  self.cl_buf.push(
    obj([("anchor", str_json(anchor)), ("pos", str_json(positive)), ("neg", str_json(negative))]),
  )
  self.invalidate_pred_cache()
}

// 注意力边权开关（默认关；ardot 工作台按场景开启以强化语义召回）
pub fn ProphecyEngine::set_attention(
  self : ProphecyEngine,
  alpha : Double,
  beta : Double,
) -> Unit {
  self.attn_alpha = alpha
  self.attn_beta = beta
}

// ---- #20 美：TermNode + 可解释推理卡片 ----

// 标记术语节点：高亮 + 高初始激活（召回优先），并刷新时效
pub fn ProphecyEngine::mark_term(self : ProphecyEngine, mid : String) -> Bool {
  match self.memories.get(mid) {
    Some(m) => {
      m.is_term = true
      m.last_active = self.clock
      self.memories.set(mid, m)
      self.invalidate_pred_cache()
      self.mark_term_index_dirty()   // P4-2：新增术语节点，索引需重建
      self.fed_upd = self.fed_upd + 1
      true
    }
    None => false
  }
}

// 可解释推理卡片：对外契约 JSON（激活路径 / 预测路径 / 价值拆解），供 CLI/前端无耦合消费
pub fn ProphecyEngine::explain_card(self : ProphecyEngine, mid : String) -> Json {
  match self.memories.get(mid) {
    Some(m) => {
      self._recompute_values()
      // 激活路径：谁连到它（入边）
      let in_edges : Array[Json] = []
      for omid, om in self.memories.iter2() {
        match om.edges.get(mid) {
          Some(w) => in_edges.push(obj([("from", str_json(omid)), ("w", num_json(r4(w)))]))
          None => ()
        }
      }
      // 预测路径：它预测什么（出边转移）
      let out_preds : Array[Json] = []
      match self.transitions.get(mid) {
        Some(t) =>
          for dst, c in t.iter2() {
            out_preds.push(obj([("to", str_json(dst)), ("count", num_json(c))]))
          }
        None => ()
      }
      // 价值拆解（D4 各项）：复用 value_breakdown 单一事实源，与 _recompute_values 完全一致
      let vb = self.value_breakdown(m)
      obj([
        ("id", str_json(mid)),
        ("text", str_json(m.text)),
        ("is_term", m.is_term.to_json()),
        ("activation_path", arr_json(in_edges)),
        ("prediction_path", arr_json(out_preds)),
        (
          "value_breakdown",
          obj([
            ("u_freq", num_json(r4(vb.u_freq))),
            ("u_recency", num_json(r4(vb.u_rec))),
            ("u_feedback", num_json(r4(vb.u_fb))),
            ("u_past", num_json(r4(vb.u_past))),
            ("u_pred", num_json(r4(vb.u_pred))),
            ("c_graph", num_json(r4(vb.c_graph))),
            ("predictive_value", num_json(r4(m.predictive_value))),
          ]),
        ),
      ])
    }
    None => obj([("error", str_json("unknown id"))])
  }
}

