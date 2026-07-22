// engine.mbt —— 译脉·先知 2.0 (MoonBit) 预知记忆网络(PMN) 引擎
// =====================================================================
// 从「记录型记忆」升级为「预知型记忆」。核心主张：只有能预测未来
// 发展的记忆，才是好记忆。
//
// 把神经网络的「逻辑」(而非重量) 搬进纯标准库实现（零第三方依赖）：
//   D1 突触图谱       -> MemoryNode + 加权关联边 + 赫布学习
//   D2 激活扩散       -> 联想召回 (spreading activation)
//   D3 预测前向模型   -> 转移计数 + 下一步需求预测
//   D4 预测价值定价   -> 价值公式以「预测效用」为主导项 (BETA)
//   D5 情景序列       -> episodic 序列学习
//   D6 固化重放       -> 离线剪枝/合并/强化 + 约束契约回滚
//   D7 不确定性&可解释 -> 置信度 + 激活/预测路径 (白盒)
//   D8 概念抽象       -> 角色级转移，支撑冷启动泛化
//
// 与 Python 版逐项对齐；差异处：用逻辑时钟(self.clock)替代 wall-clock
// 时间戳（确定性、零依赖），其余算法与常量完全一致。

// ---- 算法常量（与 Python 版逐项一致）----
const HEBB_LR : Double = 0.30      // 赫布学习率
const EDGE_DECAY : Double = 0.95   // 边权衰减（固化重放）
const MIN_EDGE : Double = 0.05     // 边权剪枝阈值
const SPREAD_DECAY : Double = 0.60 // 激活扩散衰减
const SPREAD_STEPS : Int = 2       // 扩散跳数
const DEDUP_SIM : Double = 0.90    // 语义去重相似度阈值
const CTX_WINDOW : Int = 6         // 当前上下文窗口长度
const TRANS_DECAY : Double = 0.98  // 转移计数衰减
const MIN_GRAPH : Int = 4          // 低于此节点数自动降级 1.0 余弦

// D4 价值公式权重（BETA 主导：预测效用）
const ALPHA : Double = 0.20        // 历史效用
const BETA : Double = 0.45         // 预测效用（主导项）
const GAMMA : Double = 0.20        // 网络中心性
const DELTA : Double = 0.10        // 近期奖励
const EPS : Double = 0.05          // 存储成本

const REC_TAU : Double = 604800.0  // 时效半衰期（7 天，单位=逻辑时钟步）

// 记忆节点（值类型；字段 mut 以支持原地更新后写回 Map）
pub struct MemoryNode {
  id : String
  mut text : String
  mtype : String
  mut vec : Map[String, Double]
  created : Double
  mut last_used : Double
  mut use_count : Int
  mut feedback : Double
  mut edges : Map[String, Double]        // 邻接 -> 权重 (突触)
  mut predictive_value : Double
  mut hit_count : Int
  mut predict_count : Int
}

// 引擎状态
pub struct ProphecyEngine {
  mut memories : Map[String, MemoryNode]
  transitions : Map[String, Map[String, Double]]      // D3 前向模型：src -> {dst: count}
  mut episodes : Array[Array[String]]
  mut context : Array[String]                       // 当前上下文窗口 (最近 mids)
  mut stats_preds : Int
  mut stats_hits : Int
  mut stats_remembers : Int
  mut stats_evolutions : Int
  mut seq : Int
  mut last_pred : Array[String]                     // 最近一次 predict 的 Top-K (空=无)
  mut cur_episode : Array[String]
  mut explore : Double                              // 探索度[0,1]：元认知调控
  mut meta_hits : Array[Int]                        // 近期命中(0/1)滚动窗口
  mut snapshot : Option[Map[String, MemoryNode]]    // 固化前快照（约束契约）
  role_trans : Map[String, Map[String, Double]]        // D8 角色级转移
  mut role_index : Map[String, String]              // 角色 -> 代表节点 id
  mut clock : Double                                // 逻辑时钟（替代 wall-clock）
}

// ---------------------------------------------------------------------------
// 内部辅助
// ---------------------------------------------------------------------------

fn min1(x : Double) -> Double {
  if x > 1.0 { 1.0 } else { x }
}

fn max0(a : Double, b : Double) -> Double {
  if a > b { a } else { b }
}

// 转移计数自增（一阶马尔可夫边；Map 原地修改跨副本生效）
fn inc_trans(
  trans : Map[String, Map[String, Double]],
  a : String,
  b : String,
) -> Unit {
  match trans.get(a) {
    Some(inner) => {
      let c = match inner.get(b) { Some(x) => x; None => 0.0 }
      inner.set(b, c + 1.0)
    }
    None => {
      let inner : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
      inner.set(b, 1.0)
      trans.set(a, inner)
    }
  }
}

fn copy_memories(m : Map[String, MemoryNode]) -> Map[String, MemoryNode] {
  let out : Map[String, MemoryNode] = Map::from_iter(([] : Array[(String, MemoryNode)]).iter())
  for mid, mn in m.iter2() {
    out.set(mid, mn)
  }
  out
}

fn ProphecyEngine::edges_count(self : ProphecyEngine) -> Int {
  let mut total = 0
  for _, m in self.memories.iter2() {
    total = total + m.edges.length()
  }
  total
}

// 取对象字段为 Json 数组
fn get_arr_j(j : Json, key : String) -> Array[Json] {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Array(a)) => a
        _ => []
      }
    _ => []
  }
}

// 解析 episodes：Json 数组的数组 -> Array[Array[String]]
fn parse_episodes(a : Array[Json]) -> Array[Array[String]] {
  let out : Array[Array[String]] = []
  for ep in a {
    match ep {
      Json::Array(inner) => {
        let sa : Array[String] = []
        for t in inner {
          match t {
            Json::String(s) => sa.push(s)
            _ => ()
          }
        }
        out.push(sa)
      }
      _ => ()
    }
  }
  out
}

// 排序：Array[(String, Double)] 按值降序（选择排序，零依赖）
fn sort_sd(arr : Array[(String, Double)]) -> Unit {
  for i = 0; i < arr.length(); i = i + 1 {
    let mut bi = i
    for j = i + 1; j < arr.length(); j = j + 1 {
      if arr[j].1 > arr[bi].1 {
        bi = j
      }
    }
    if bi != i {
      let t = arr[i]
      arr[i] = arr[bi]
      arr[bi] = t
    }
  }
}

// 排序：Array[(String, Int)] 按值降序
fn sort_si(arr : Array[(String, Int)]) -> Unit {
  for i = 0; i < arr.length(); i = i + 1 {
    let mut bi = i
    for j = i + 1; j < arr.length(); j = j + 1 {
      if arr[j].1 > arr[bi].1 {
        bi = j
      }
    }
    if bi != i {
      let t = arr[i]
      arr[i] = arr[bi]
      arr[bi] = t
    }
  }
}

// 排序：Array[(String, Double, Double, Array[Json])] 按第 2 项(score)降序
fn sort_scored(arr : Array[(String, Double, Double, Array[Json])]) -> Unit {
  for i = 0; i < arr.length(); i = i + 1 {
    let mut bi = i
    for j = i + 1; j < arr.length(); j = j + 1 {
      if arr[j].1 > arr[bi].1 {
        bi = j
      }
    }
    if bi != i {
      let t = arr[i]
      arr[i] = arr[bi]
      arr[bi] = t
    }
  }
}

// 节点 -> Json
fn node_to_json(m : MemoryNode) -> Json {
  obj([
    ("id", str_json(m.id)),
    ("text", str_json(m.text)),
    ("type", str_json(m.mtype)),
    ("vec", dmap_to_json(m.vec)),
    ("created", num_json(m.created)),
    ("last_used", num_json(m.last_used)),
    ("use_count", num_json(m.use_count.to_double())),
    ("feedback", num_json(m.feedback)),
    ("edges", dmap_to_json(m.edges)),
    ("predictive_value", num_json(m.predictive_value)),
    ("hit_count", num_json(m.hit_count.to_double())),
    ("predict_count", num_json(m.predict_count.to_double())),
  ])
}

// Json -> 节点
fn node_from_json(j : Json) -> MemoryNode {
  {
    id: get_str(j, "id"),
    text: get_str(j, "text"),
    mtype: get_str(j, "type"),
    vec: json_to_dmap(get_obj(j, "vec")),
    created: get_num(j, "created"),
    last_used: get_num(j, "last_used"),
    use_count: get_num(j, "use_count").to_int(),
    feedback: get_num(j, "feedback"),
    edges: json_to_dmap(get_obj(j, "edges")),
    predictive_value: get_num(j, "predictive_value"),
    hit_count: get_num(j, "hit_count").to_int(),
    predict_count: get_num(j, "predict_count").to_int(),
  }
}

fn memories_to_json(m : Map[String, MemoryNode]) -> Json {
  let o : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for mid, mn in m.iter2() {
    o.set(mid, node_to_json(mn))
  }
  o.to_json()
}

// ---------------------------------------------------------------------------
// 构造 / ID
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::make() -> ProphecyEngine {
  {
    memories: Map::from_iter(([] : Array[(String, MemoryNode)]).iter()),
    transitions: Map::from_iter(([] : Array[(String, Map[String, Double])]).iter()),
    episodes: [],
    context: [],
    stats_preds: 0,
    stats_hits: 0,
    stats_remembers: 0,
    stats_evolutions: 0,
    seq: 0,
    last_pred: [],
    cur_episode: [],
    explore: 0.0,
    meta_hits: [],
    snapshot: None,
    role_trans: Map::from_iter(([] : Array[(String, Map[String, Double])]).iter()),
    role_index: Map::from_iter(([] : Array[(String, String)]).iter()),
    clock: 0.0,
  }
}

fn ProphecyEngine::_new_id(self : ProphecyEngine) -> String {
  self.seq = self.seq + 1
  "m" + self.seq.to_string()
}

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
  let vec = tf_vector(yimai_tokenize(text))
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
    m.use_count = m.use_count + 1
    m.last_used = self.clock
    self.role_index.set(role_of(text), best)
    self.memories.set(best, m)
    self._wire(best, ctx)
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
    use_count: 1,
    feedback: 0.0,
    edges: Map::from_iter(([] : Array[(String, Double)]).iter()),
    predictive_value: 0.0,
    hit_count: 0,
    predict_count: 0,
  }
  self.role_index.set(role_of(text), mid)
  self.memories.set(mid, node)
  self._wire(mid, ctx)
  self.stats_remembers = self.stats_remembers + 1
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
        m.edges.set(a, clamp01(w + HEBB_LR * (1.0 - w)))
        self.memories.set(mid, m)
        let na = self.memories[a]
        let w2 = match na.edges.get(mid) { Some(x) => x; None => 0.0 }
        na.edges.set(mid, clamp01(w2 + HEBB_LR * (1.0 - w2)))
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
    sort_sd(scored)
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
  // 种子：与查询最相似的若干节点
  let sims : Array[(String, Double)] = []
  for mid, m in self.memories.iter2() {
    let s = cosine(qvec, m.vec)
    if s > 0.05 {
      sims.push((mid, s))
    }
  }
  if sims.length() == 0 {
    let all : Array[(String, Int)] = []
    for mid, m in self.memories.iter2() {
      all.push((mid, m.use_count))
    }
    sort_si(all)
    for i = 0; i < 3 && i < all.length(); i = i + 1 {
      sims.push((all[i].0, 0.05))
    }
  }
  sort_sd(sims)
  let seeds : Array[String] = []
  for i = 0; i < 3 && i < sims.length(); i = i + 1 {
    seeds.push(sims[i].0)
  }
  // 扩散
  let mut act : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  for s in seeds {
    act.set(s, 1.0)
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
            let contrib = a * w * SPREAD_DECAY
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
  sort_scored(scored)
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

pub fn ProphecyEngine::predict(self : ProphecyEngine, k : Int) -> Json {
  let act : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  let n = self.context.length()
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
  // 汇总：每个上下文节点的转移概率按激活权重累加
  let score : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  let path : Map[String, Array[Json]] =
    Map::from_iter(([] : Array[(String, Array[Json])]).iter())
  for a, aw in act.iter2() {
    let tt : Double = match self.transitions.get(a) {
      Some(trans) => {
        let mut tot = 0.0
        for _, c in trans.iter2() {
          tot = tot + c
        }
        let tt0 = if tot == 0.0 { 1.0 } else { tot }
        for dst, c in trans.iter2() {
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
    // 注意：无具体转移时 tt=1.0，同样进入回退（对应 Python 的 get(a, {})）
    if tt <= 1.0 {
      match self.memories.get(a) {
        Some(na) => {
          let ra = role_of(na.text)
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
                            let na : Array[Json] = []
                            path.set(tgt, na)
                            na
                          }
                        }
                        arr.push(obj([("from", str_json(a + "(role)")), ("p", num_json(r4(rp)))]))
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
        None => ()
      }
    }
  }
  // 归一化
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
  // 排名
  let ranked : Array[(String, Double)] = []
  for d, v in score.iter2() {
    ranked.push((d, v))
  }
  sort_sd(ranked)
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
  // D7 不确定性：整体分布熵
  let mut entropy = 0.0
  for i = 0; i < lim; i = i + 1 {
    let p = ranked[i].1
    entropy = entropy - p * @math.ln(p + 0.000000001)
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
  obj([
    ("predictions", arr_json(preds)),
    ("confidence", num_json(if preds.length() > 0 { r4(ranked[0].1) } else { 0.0 })),
    ("uncertainty", num_json(r4(entropy))),
  ])
}

// ---------------------------------------------------------------------------
// observe：记住真实下一步 + 更新转移 + 命中核算
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::observe(
  self : ProphecyEngine,
  text : String,
  mtype : String,
) -> String {
  self.clock = self.clock + 1.0
  let mid = self.remember(text, mtype, self.context)
  // D3 转移计数：仅由「紧邻前驱」建立一阶马尔可夫边
  if self.context.length() > 0 {
    let prev = self.context[self.context.length() - 1]
    match self.memories.get(prev) {
      Some(_) => {
        inc_trans(self.transitions, prev, mid)
        // D8 概念抽象：同时记录角色级转移
        match self.memories.get(prev) {
          Some(pn) =>
            match self.memories.get(mid) {
              Some(mn) => {
                let ra = role_of(pn.text)
                let rb = role_of(mn.text)
                if ra != "" && rb != "" {
                  inc_trans(self.role_trans, ra, rb)
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

fn ProphecyEngine::_recompute_values(self : ProphecyEngine) -> Unit {
  let mut max_uc = 1
  for _, m in self.memories.iter2() {
    if m.use_count > max_uc {
      max_uc = m.use_count
    }
  }
  let now = self.clock
  for mid, m in self.memories.iter2() {
    let u_freq = m.use_count.to_double() / (m.use_count.to_double() + 5.0)
    let dt = now - m.last_used
    let u_rec = if dt < 0.0 { 1.0 } else { clamp01(@math.exp(-dt / REC_TAU)) }
    let u_fb = clamp01((m.feedback + 1.0) / 2.0)
    let u_past = 0.5 * u_freq + 0.3 * u_rec + 0.2 * u_fb
    // U_pred（主导项）
    let hr = if m.predict_count > 0 {
      m.hit_count.to_double() / m.predict_count.to_double()
    } else {
      0.0
    }
    let mut tot = 0.0
    match self.transitions.get(mid) {
      Some(trans) => for _, c in trans.iter2() { tot = tot + c }
      None => ()
    }
    let out_str = min1(tot / (tot + 10.0))
    let u_pred = 0.6 * hr + 0.4 * out_str
    // C_graph 网络中心性
    let mut esum = 0.0
    for _, w in m.edges.iter2() {
      esum = esum + w
    }
    let c_graph = min1(esum / 5.0)
    let r = u_fb
    let cost = @math.ln(1.0 + self.memories.length().to_double()) / 20.0
    let vval = ALPHA * u_past + BETA * u_pred + GAMMA * c_graph + DELTA * r - EPS * cost
    let m2 = m
    m2.predictive_value = clamp01(if vval > 0.0 { vval } else { 0.0 })
    self.memories.set(mid, m2)
  }
}

// ---------------------------------------------------------------------------
// D6 固化重放
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::consolidate(self : ProphecyEngine, prune : Bool) -> Json {
  // 0. 约束契约：固化前对记忆做快照，支持回滚
  self.snapshot = Some(copy_memories(self.memories))
  // 1. 边衰减 + 剪枝
  for mid, m in self.memories.iter2() {
    let new_edges : Map[String, Double] =
      Map::from_iter(([] : Array[(String, Double)]).iter())
    for nb, w in m.edges.iter2() {
      let nw = w * EDGE_DECAY
      if nw >= MIN_EDGE && self.memories.contains(nb) {
        new_edges.set(nb, nw)
      }
    }
    // 对齐 Python：无论是否剪枝都写回衰减后的边权（否则 EDGE_DECAY 在干净网络上形同虚设）
    let m2 = m
    m2.edges = new_edges
    self.memories.set(mid, m2)
  }
  // 2. 转移计数衰减（对齐 Python：缓慢衰减，权重 < 0.5 的转移被丢弃）
  for a, d in self.transitions.iter2() {
    let newd : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
    for dst, c in d.iter2() {
      let nc = c * TRANS_DECAY
      if nc >= 0.5 {
        newd.set(dst, nc)
      }
    }
    self.transitions.set(a, newd)
  }
  // 3. 重算预测价值
  self._recompute_values()
  // 4. (可选) 压缩零预测价值噪声节点
  let mut removed = 0
  if prune {
    let ids : Array[String] = []
    for mid, _ in self.memories.iter2() {
      ids.push(mid)
    }
    for mid in ids {
      match self.memories.get(mid) {
        Some(m) => {
          if m.predictive_value < 0.08 && m.use_count <= 1 &&
             !arr_contains(self.context, mid) {
            for _, other in self.memories.iter2() {
              other.edges.remove(mid)
            }
            self.transitions.remove(mid)
            for _, d in self.transitions.iter2() {
              d.remove(mid)
            }
            self.memories.remove(mid)
            removed = removed + 1
          }
        }
        None => ()
      }
    }
  }
  // 5. 元认知调控：用近期命中率自适应探索/利用
  let recent : Array[Int] = []
  let start = if self.meta_hits.length() > 50 {
    self.meta_hits.length() - 50
  } else {
    0
  }
  for i = start; i < self.meta_hits.length(); i = i + 1 {
    recent.push(self.meta_hits[i])
  }
  let mut hr = 0.5
  if recent.length() > 0 {
    let mut s = 0
    for x in recent {
      s = s + x
    }
    hr = s.to_double() / recent.length().to_double()
  }
  self.explore = clamp01(max0(0.0, (0.6 - hr) * 2.0))
  self.stats_evolutions = self.stats_evolutions + 1
  obj([
    ("pruned", num_json(removed.to_double())),
    ("nodes", num_json(self.memories.length().to_double())),
    ("edges", num_json(self.edges_count().to_double())),
    ("explore", num_json(r4(self.explore))),
    ("recent_hit_rate", num_json(r4(hr))),
  ])
}

pub fn ProphecyEngine::restore(self : ProphecyEngine) -> Json {
  match self.snapshot {
    Some(s) => {
      self.memories = s
      self.snapshot = None
      obj([("ok", true.to_json()), ("nodes", num_json(self.memories.length().to_double()))])
    }
    None => obj([("ok", false.to_json()), ("reason", str_json("no snapshot"))])
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
      true
    }
    None => false
  }
}

// ---------------------------------------------------------------------------
// D7 可解释：回放某记忆的来龙去脉
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::explain(self : ProphecyEngine, mid : String) -> Json {
  match self.memories.get(mid) {
    Some(m) => {
      let hr = if m.predict_count > 0 {
        m.hit_count.to_double() / m.predict_count.to_double()
      } else {
        0.0
      }
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

// ---------------------------------------------------------------------------
// 序列化（状态跨调用 / 持久化）
// ---------------------------------------------------------------------------

pub fn ProphecyEngine::to_json(self : ProphecyEngine) -> Json {
  let mem_map : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for mid, m in self.memories.iter2() {
    mem_map.set(mid, node_to_json(m))
  }
  let trans_map : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for a, d in self.transitions.iter2() {
    trans_map.set(a, dmap_to_json(d))
  }
  let role_map : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for a, d in self.role_trans.iter2() {
    role_map.set(a, dmap_to_json(d))
  }
  obj([
    ("memories", mem_map.to_json()),
    ("transitions", trans_map.to_json()),
    (
      "episodes",
      arr_json(self.episodes.map(fn(ep) { arr_json(ep.map(fn(s) { str_json(s) })) })),
    ),
    ("context", arr_json(self.context.map(fn(s) { str_json(s) }))),
    (
      "stats",
      obj([
        ("preds", num_json(self.stats_preds.to_double())),
        ("hits", num_json(self.stats_hits.to_double())),
        ("remembers", num_json(self.stats_remembers.to_double())),
        ("evolutions", num_json(self.stats_evolutions.to_double())),
      ]),
    ),
    ("seq", num_json(self.seq.to_double())),
    ("explore", num_json(self.explore)),
    ("clock", num_json(self.clock)),
    ("meta_hits", arr_json(self.meta_hits.map(fn(x) { num_json(x.to_double()) }))),
    ("snapshot", match self.snapshot { Some(s) => memories_to_json(s); None => obj([]) }),
    ("role_trans", role_map.to_json()),
    ("role_index", smap_to_json(self.role_index)),
  ])
}

pub fn ProphecyEngine::from_json(data : Json) -> ProphecyEngine {
  let e = ProphecyEngine::make()
  match get_obj(data, "memories") {
    Json::Object(m) => for mid, mj in m.iter2() { e.memories.set(mid, node_from_json(mj)) }
    _ => ()
  }
  match get_obj(data, "transitions") {
    Json::Object(m) => for a, aj in m.iter2() { e.transitions.set(a, json_to_dmap(aj)) }
    _ => ()
  }
  e.episodes = parse_episodes(get_arr_j(data, "episodes"))
  e.context = get_str_arr(data, "context")
  match get_obj(data, "stats") {
    Json::Object(m) => {
      e.stats_preds = match m.get("preds") { Some(Json::Number(n, ..)) => n.to_int(); _ => 0 }
      e.stats_hits = match m.get("hits") { Some(Json::Number(n, ..)) => n.to_int(); _ => 0 }
      e.stats_remembers = match m.get("remembers") { Some(Json::Number(n, ..)) => n.to_int(); _ => 0 }
      e.stats_evolutions = match m.get("evolutions") { Some(Json::Number(n, ..)) => n.to_int(); _ => 0 }
    }
    _ => ()
  }
  e.seq = get_num(data, "seq").to_int()
  e.explore = get_num(data, "explore")
  e.clock = get_num(data, "clock")
  e.meta_hits = get_arr_j(data, "meta_hits").filter_map(fn(t) {
    match t {
      Json::Number(n, ..) => Some(n.to_int())
      _ => None
    }
  })
  match get_obj(data, "snapshot") {
    Json::Object(m) =>
      if m.length() > 0 {
        let snap : Map[String, MemoryNode] =
          Map::from_iter(([] : Array[(String, MemoryNode)]).iter())
        for mid, mj in m.iter2() {
          snap.set(mid, node_from_json(mj))
        }
        e.snapshot = Some(snap)
      } else {
        e.snapshot = None
      }
    _ => e.snapshot = None
  }
  match get_obj(data, "role_trans") {
    Json::Object(m) => for a, aj in m.iter2() { e.role_trans.set(a, json_to_dmap(aj)) }
    _ => ()
  }
  e.role_index = json_to_smap(get_obj(data, "role_index"))
  e
}
