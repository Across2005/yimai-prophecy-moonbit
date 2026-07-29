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
// 按 D1–D8 规范实现；差异处：用逻辑时钟(self.clock)替代 wall-clock
// 时间戳（确定性、零依赖），算法与常量完全自洽。

// ---- 算法常量（按 D1–D8 规范设定）----
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
  mut last_active : Double              // 最近一次被激活/命中（逻辑时钟），用于弹性遗忘的真实时差折扣
  mut is_term : Bool                     // 术语节点（美：高初始激活 + 命中高亮，mark_term 置位）
  translation : String                   // TM 译文 / TB 目标术语（#22 TM/TB 一等公民）
}

// 引擎状态
pub struct ProphecyEngine {
  mut memories : Map[String, MemoryNode]
  mut transitions : Map[String, Map[String, Double]]    // D3 前向模型：src -> {dst: count}（固化前快照，F1 需回滚）
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
  mut snap_trans : Option[Map[String, Map[String, Double]]]  // 固化前转移快照（约束契约·F1）
  mut snap_role : Option[Map[String, Map[String, Double]]]    // 固化前角色转移快照（约束契约·F1）
  mut role_trans : Map[String, Map[String, Double]]      // D8 角色级转移（固化前快照，F1 需回滚）
  mut role_index : Map[String, String]              // 角色 -> 代表节点 id
  // ---- 路线图拓展字段（内部态，不进入 to_json；from_json 后由 rebuild_* 重建）----
  mut role_members : Map[String, Array[String]]   // 角色 -> 成员节点倒排索引（快：大图角色限定召回加速）
  mut trans2 : Map[String, Map[String, Double]]     // 二阶马尔可夫：(w1\0w2) -> {w3: count}（准，#17 实现）
  mut domain_bias : Map[String, Double]             // 领域偏置 ΔW（LoRA 式，按角色原型）（准，#19 实现）
  mut hebb_lr : Double                             // 动态赫布学习率（#18 自适应，consolidate 中重赋值）
  mut attn_alpha : Double                           // 注意力边权系数 α（#19，默认 0=关，set_attention 开启）
  mut attn_beta : Double                            // 注意力边权系数 β（#19，角色匹配项）
  mut pred_cache : Map[String, Json]               // 预测缓存 LRU（#16 快）
  mut cache_epoch : Int                            // 引擎变更计数，失效预测缓存
  cl_buf : Array[Json]                             // 在线对比学习缓冲（#19）
  mut wal_log : Array[String]                      // 增量固化 WAL 日志（#21，事件溯源）
  mut fed_add : Int                                // 联邦增量：新增节点计数
  mut fed_upd : Int                                // 联邦增量：更新计数
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

// 转移表深拷贝（F1：固化前快照须独立副本，否则回滚会引用同一对象）
fn copy_trans(t : Map[String, Map[String, Double]]) -> Map[String, Map[String, Double]] {
  let out : Map[String, Map[String, Double]] =
    Map::from_iter(([] : Array[(String, Map[String, Double])]).iter())
  for a, d in t.iter2() {
    let inner : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
    for b, c in d.iter2() {
      inner.set(b, c)
    }
    out.set(a, inner)
  }
  out
}

// 角色倒排索引：增量维护（仅 ADD，避免误删；restore/prune 时整体重建）
fn ProphecyEngine::role_members_add(self : ProphecyEngine, role : String, mid : String) -> Unit {
  if role == "" {
    return
  }
  match self.role_members.get(role) {
    Some(arr) => {
      if !arr_contains(arr, mid) {
        arr.push(mid)
      }
    }
    None => {
      let a : Array[String] = [mid]
      self.role_members.set(role, a)
    }
  }
}

fn ProphecyEngine::rebuild_role_members(self : ProphecyEngine) -> Unit {
  self.role_members = Map::from_iter(([] : Array[(String, Array[String])]).iter())
  for mid, m in self.memories.iter2() {
    for rk in roles_of(m.text) {
      self.role_members_add(rk, mid)
    }
  }
}

// 预测缓存失效（引擎被修改时调用，保证记忆更新后预测不过期）
fn ProphecyEngine::invalidate_pred_cache(self : ProphecyEngine) -> Unit {
  self.pred_cache = Map::from_iter(([] : Array[(String, Json)]).iter())
  self.cache_epoch = self.cache_epoch + 1
}

// WAL：追加一条增量固化操作日志（#21）
fn ProphecyEngine::wal_append(self : ProphecyEngine, line : String) -> Unit {
  self.wal_log.push(line)
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
    ("last_active", num_json(m.last_active)),
    ("is_term", if m.is_term { 1.0 } else { 0.0 }),
    ("translation", str_json(m.translation)),
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
    last_active: get_num(j, "last_active"),
    is_term: get_num(j, "is_term") != 0.0,
    translation: get_str(j, "translation"),
  }
}

fn memories_to_json(m : Map[String, MemoryNode]) -> Json {
  let o : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for mid, mn in m.iter2() {
    o.set(mid, node_to_json(mn))
  }
  o.to_json()
}

// 转移表序列化（F1 修复补全：快照三元组须随状态持久化，
// 否则重载后 restore() 会回滚 memories 却不回滚 transitions/role_trans）
fn trans_map_to_json(t : Map[String, Map[String, Double]]) -> Json {
  let o : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for a, d in t.iter2() {
    o.set(a, dmap_to_json(d))
  }
  o.to_json()
}

fn json_to_trans_map(j : Json) -> Map[String, Map[String, Double]] {
  let out : Map[String, Map[String, Double]] =
    Map::from_iter(([] : Array[(String, Map[String, Double])]).iter())
  match j {
    Json::Object(m) => for a, aj in m.iter2() { out.set(a, json_to_dmap(aj)) }
    _ => ()
  }
  out
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
    snap_trans: None,
    snap_role: None,
    role_trans: Map::from_iter(([] : Array[(String, Map[String, Double])]).iter()),
    role_index: Map::from_iter(([] : Array[(String, String)]).iter()),
    role_members: Map::from_iter(([] : Array[(String, Array[String])]).iter()),
    trans2: Map::from_iter(([] : Array[(String, Map[String, Double])]).iter()),
    domain_bias: Map::from_iter(([] : Array[(String, Double)]).iter()),
    hebb_lr: HEBB_LR,
    attn_alpha: 0.0,
    attn_beta: 0.0,
    pred_cache: Map::from_iter(([] : Array[(String, Json)]).iter()),
    cache_epoch: 0,
    cl_buf: [],
    wal_log: [],
    fed_add: 0,
    fed_upd: 0,
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
    m.last_active = self.clock
    self.role_index.set(role_of(text), best)
    for rk in roles_of(text) {
      self.role_index.set(rk, best)
      self.role_members_add(rk, best)
    }
    self.memories.set(best, m)
    self._wire(best, ctx)
    self.wal_append("remember" + WAL_SEP + best + WAL_SEP + text + WAL_SEP + mtype)
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
  }
  self.role_index.set(role_of(text), mid)
  for rk in roles_of(text) {
    self.role_index.set(rk, mid)
    self.role_members_add(rk, mid)
  }
  self.wal_append("remember" + WAL_SEP + mid + WAL_SEP + text + WAL_SEP + mtype)
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
  // 快：预测缓存 LRU（相同上下文签名且引擎未变更时直接返回，跳过转移聚合）
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
        // 快：每源 Top-K(=8) 剪枝候选，大图下显著降低聚合开销（≤8 时不触发，保证小图行为不变）
        let keep : Array[String] = []
        if trans.length() > 8 {
          let allc : Array[(String, Double)] = []
          for dst, c in trans.iter2() {
            allc.push((dst, c))
          }
          sort_sd(allc)
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
  self.clock = self.clock + 1.0
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
  self.wal_append("observe" + WAL_SEP + mid + WAL_SEP + text + WAL_SEP + mtype)
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
  // 0. 约束契约：固化前对记忆/转移/角色转移做快照，支持回滚
  //    （F1：三者须一致回滚，否则记忆与转移表错位导致预测失真）
  self.snapshot = Some(copy_memories(self.memories))
  self.snap_trans = Some(copy_trans(self.transitions))
  self.snap_role = Some(copy_trans(self.role_trans))
  // 1. 边衰减 + 剪枝
  for mid, m in self.memories.iter2() {
    let new_edges : Map[String, Double] =
      Map::from_iter(([] : Array[(String, Double)]).iter())
    for nb, w in m.edges.iter2() {
      // 弹性遗忘：边随「节点真实时差」加速衰减（陈旧关联更快淡出，新鲜关联保持）
      let gap = self.clock - m.last_active
      let recency = if gap < 0.0 { 1.0 } else { @math.exp(-gap / REC_TAU) }
      let eff_decay = EDGE_DECAY * (0.5 + 0.5 * recency) // ∈ (0, EDGE_DECAY] ⊂ (0,1)
      let nw = w * eff_decay
      if nw >= MIN_EDGE && self.memories.contains(nb) {
        new_edges.set(nb, nw)
      }
    }
    // 对齐 D1–D8 规范：无论是否剪枝都写回衰减后的边权（否则 EDGE_DECAY 在干净网络上形同虚设）
    let m2 = m
    m2.edges = new_edges
    self.memories.set(mid, m2)
  }
  // 2. 转移计数衰减（对齐 D1–D8 规范：缓慢衰减，权重 < 0.5 的转移被丢弃）
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
  // 自适应学习率：近期命中率驱动（高→更快适应，低→更稳）
  let target_lr = if hr > 0.8 {
    HEBB_LR * 1.2
  } else if hr < 0.5 {
    HEBB_LR * 0.6
  } else {
    HEBB_LR
  }
  self.hebb_lr = if target_lr < 0.05 {
    0.05
  } else if target_lr > 0.95 {
    0.95
  } else {
    target_lr
  }
  self.invalidate_pred_cache()
  self.rebuild_role_members()
  self.fed_upd = self.fed_upd + 1
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
      match self.snap_trans {
        Some(st) => self.transitions = st
        None => ()
      }
      match self.snap_role {
        Some(sr) => self.role_trans = sr
        None => ()
      }
      self.snapshot = None
      self.snap_trans = None
      self.snap_role = None
      self.invalidate_pred_cache()
      self.rebuild_role_members()
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
      // 价值拆解（D4 各项）
      let u_freq = m.use_count.to_double() / (m.use_count.to_double() + 5.0)
      let dt = self.clock - m.last_used
      let u_rec = if dt < 0.0 { 1.0 } else { clamp01(@math.exp(-dt / REC_TAU)) }
      let u_fb = clamp01((m.feedback + 1.0) / 2.0)
      let u_past = 0.5 * u_freq + 0.3 * u_rec + 0.2 * u_fb
      let hr = if m.predict_count > 0 {
        m.hit_count.to_double() / m.predict_count.to_double()
      } else {
        0.0
      }
      let mut tot = 0.0
      match self.transitions.get(mid) {
        Some(tr) => for _, c in tr.iter2() { tot = tot + c }
        None => ()
      }
      let out_str = min1(tot / (tot + 10.0))
      let u_pred = 0.6 * hr + 0.4 * out_str
      let mut esum = 0.0
      for _, w in m.edges.iter2() {
        esum = esum + w
      }
      let c_graph = min1(esum / 5.0)
      obj([
        ("id", str_json(mid)),
        ("text", str_json(m.text)),
        ("is_term", m.is_term.to_json()),
        ("activation_path", arr_json(in_edges)),
        ("prediction_path", arr_json(out_preds)),
        (
          "value_breakdown",
          obj([
            ("u_freq", num_json(r4(u_freq))),
            ("u_recency", num_json(r4(u_rec))),
            ("u_feedback", num_json(r4(u_fb))),
            ("u_past", num_json(r4(u_past))),
            ("u_pred", num_json(r4(u_pred))),
            ("c_graph", num_json(r4(c_graph))),
            ("predictive_value", num_json(r4(m.predictive_value))),
          ]),
        ),
      ])
    }
    None => obj([("error", str_json("unknown id"))])
  }
}

// ---- #22 TM/TB 一等公民：翻译记忆检索 + 术语库强制对齐 ----
// 设计：TM 条目 mtype="tm"（text=源, translation=译文）；TB 术语 mtype="term"（text=源术语, translation=目标术语）。
// 二者分离：fuzzy_match/concordance 只检索 tm；enforce_terms/check_terms 只扫 term。

// 加入一条翻译记忆（源 -> 译文），复用 tokenize/tf_vector 建索引
pub fn ProphecyEngine::add_tm(self : ProphecyEngine, src : String, tgt : String) -> String {
  let mid = self._new_id()
  let vec = tf_vector(yimai_tokenize(src))
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
  }
  self.memories.set(mid, node)
  self.invalidate_pred_cache()
  self.fed_add = self.fed_add + 1
  mid
}

// TM 模糊匹配：Top-K（按匹配率降序）。匹配率 = 0.7·token余弦 + 0.3·字符级比率。
// 对齐 Trados 实践：低于 threshold（建议阈值 0.70；MoonBit 无默认参数，调用方需显式传入）视为无匹配；返回匹配率%与分项相似度。
pub fn ProphecyEngine::fuzzy_match(self : ProphecyEngine, query : String, k : Int, threshold : Double) -> Json {
  let qv = tf_vector(yimai_tokenize(query))
  let cands : Array[(String, Double, Double, Double)] = []
  for mid, m in self.memories.iter2() {
    if m.mtype != "tm" { continue }
    let sim_tok = cosine(qv, m.vec)
    let sim_ch = char_ratio(query, m.text)
    let score = 0.7 * sim_tok + 0.3 * sim_ch
    if score >= threshold {
      cands.push((mid, score, sim_tok, sim_ch))
    }
  }
  let sorted : Array[(String, Double, Double, Double)] = []
  for c in cands {
    let mut j = 0
    let mut ins = false
    while j < sorted.length() {
      if c.1 > sorted[j].1 { sorted.insert(j, c); ins = true; break }
      j = j + 1
    }
    if !ins { sorted.push(c) }
  }
  let lim = if k > sorted.length() { sorted.length() } else { k }
  let out : Array[Json] = []
  let mut i = 0
  while i < lim {
    let (mid, score, st, sc) = sorted[i]
    match self.memories.get(mid) {
      Some(m) =>
        out.push(obj([
          ("id", str_json(mid)),
          ("source", str_json(m.text)),
          ("target", str_json(m.translation)),
          ("score", num_json(r4(score))),
          ("match_pct", num_json(r4(score * 100.0))),
          ("sim_token", num_json(r4(st))),
          ("sim_char", num_json(r4(sc))),
        ]))
      None => ()
    }
    i = i + 1
  }
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
    let toks = yimai_tokenize(m.text)
    let mut hits = 0
    for t in toks {
      if t == qkey { hits = hits + 1 }
    }
    if hits == 0 && str_contains(m.text, term) { hits = 1 }
    if hits > 0 { cands.push((mid, hits)) }
  }
  let sorted : Array[(String, Int)] = []
  for c in cands {
    let mut j = 0
    let mut ins = false
    while j < sorted.length() {
      if c.1 > sorted[j].1 { sorted.insert(j, c); ins = true; break }
      j = j + 1
    }
    if !ins { sorted.push(c) }
  }
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
      }
      self.memories.set(mid, node)
      self.invalidate_pred_cache()
      count = count + 1
    }
  }
  count
}

// 术语强制对齐：扫描文本，返回所有命中已知术语的位置与译文（翻译时高亮/锁定）。
// 用 term_hit 做词边界判定，避免 log⊂logical 这类子串误报。
pub fn ProphecyEngine::enforce_terms(self : ProphecyEngine, text : String) -> Json {
  let out : Array[Json] = []
  for mid, m in self.memories.iter2() {
    if !m.is_term { continue }
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
  let violations : Array[Json] = []
  for mid, m in self.memories.iter2() {
    if !m.is_term { continue }
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

// ---- #21 中/长期：WAL 增量固化 / 主动学习 / 联邦 / 蒸馏 ----
const WAL_SEP : String = "\u0001"

// 从 WAL 重放重建引擎（事件溯源：仅重放 remember/observe 原子事件）
pub fn ProphecyEngine::wal_replay(self : ProphecyEngine) -> ProphecyEngine {
  let e = ProphecyEngine::make()
  for line in self.wal_log {
    let parts = line.split(WAL_SEP).to_array()
    // 记录格式: op␁mid␁text␁mtype（␁ = WAL_SEP）
    if parts.length() >= 4 {
      let op = parts[0].to_owned()
      let text = parts[2].to_owned()
      let mtype = parts[3].to_owned()
      if op == "observe" {
        let _ = e.observe(text, mtype)
      } else if op == "remember" {
        let _ = e.remember(text, mtype, [])
      }
    }
  }
  e
}

pub fn ProphecyEngine::wal_export(self : ProphecyEngine) -> Array[String] {
  self.wal_log
}

pub fn ProphecyEngine::wal_compact(self : ProphecyEngine, keep : Int) -> Unit {
  if self.wal_log.length() > keep {
    let start = self.wal_log.length() - keep
    let kept : Array[String] = []
    for i = start; i < self.wal_log.length(); i = i + 1 {
      kept.push(self.wal_log[i])
    }
    self.wal_log = kept
  }
}

pub fn ProphecyEngine::wal_clear(self : ProphecyEngine) -> Unit {
  self.wal_log = []
}

pub fn ProphecyEngine::wal_len(self : ProphecyEngine) -> Int {
  self.wal_log.length()
}

// 主动学习候选：高不确定(低命中/低使用) + 角色多样性
pub fn ProphecyEngine::active_learning_candidates(
  self : ProphecyEngine,
  k : Int,
) -> Array[Json] {
  self._recompute_values()
  let pairs : Array[(String, Double)] = []
  for mid, m in self.memories.iter2() {
    let hr = if m.predict_count > 0 {
      m.hit_count.to_double() / m.predict_count.to_double()
    } else {
      0.0
    }
    let unc = 1.0 - hr
    let nov = 1.0 - clamp01(m.use_count.to_double() / 5.0)
    pairs.push((mid, 0.6 * unc + 0.4 * nov))
  }
  sort_sd(pairs)
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
    ("cur_episode", arr_json(self.cur_episode.map(fn(s) { str_json(s) }))),
    ("last_pred", arr_json(self.last_pred.map(fn(s) { str_json(s) }))),
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
    ("snap_trans", match self.snap_trans { Some(t) => trans_map_to_json(t); None => obj([]) }),
    ("snap_role", match self.snap_role { Some(t) => trans_map_to_json(t); None => obj([]) }),
    ("trans2", trans_map_to_json(self.trans2)),
    ("domain_bias", dmap_to_json(self.domain_bias)),
    ("hebb_lr", num_json(self.hebb_lr)),
    ("attn_alpha", num_json(self.attn_alpha)),
    ("attn_beta", num_json(self.attn_beta)),
    ("wal_log", arr_json(self.wal_log.map(fn(s) { str_json(s) }))),
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
  e.cur_episode = get_str_arr(data, "cur_episode")
  e.last_pred = get_str_arr(data, "last_pred")
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
  let sjt = get_obj(data, "snap_trans")
  match sjt {
    Json::Object(m) =>
      if m.length() > 0 {
        e.snap_trans = Some(json_to_trans_map(sjt))
      } else {
        e.snap_trans = None
      }
    _ => e.snap_trans = None
  }
  let sjr = get_obj(data, "snap_role")
  match sjr {
    Json::Object(m) =>
      if m.length() > 0 {
        e.snap_role = Some(json_to_trans_map(sjr))
      } else {
        e.snap_role = None
      }
    _ => e.snap_role = None
  }
  match get_obj(data, "role_trans") {
    Json::Object(m) => for a, aj in m.iter2() { e.role_trans.set(a, json_to_dmap(aj)) }
    _ => ()
  }
  e.role_index = json_to_smap(get_obj(data, "role_index"))
  e.trans2 = json_to_trans_map(get_obj(data, "trans2"))
  e.domain_bias = json_to_dmap(get_obj(data, "domain_bias"))
  e.hebb_lr = get_num(data, "hebb_lr")
  e.attn_alpha = get_num(data, "attn_alpha")
  e.attn_beta = get_num(data, "attn_beta")
  e.wal_log = get_str_arr(data, "wal_log")
  e.rebuild_role_members()
  e
}
