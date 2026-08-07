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
  // ---- TM 特征缓存（内部派生态，不进 to_json；add_tm 构建 / from_json 后重建）----
  mut tm_toks : Array[String]           // yimai_tokenize(text)（未去重，供 fuzzy token 集合 + concordance 计数）
  mut tm_ngrams : Array[String]         // char_ngrams(text, 2)（供 fuzzy 字符 2-gram 分项）
}

// 预测价值分解（D4）的命名返回值：供 _recompute_values 与 explain_card 共用，避免 8 元组位置歧义
priv struct ValueBreakdown {
  u_freq : Double
  u_rec : Double
  u_fb : Double
  u_past : Double
  u_pred : Double
  c_graph : Double
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
  mut pred_cache : Map[String, Json]               // 预测缓存（#16 快）：引擎变更时全量失效（非 LRU 淘汰）
  mut cache_epoch : Int                            // 引擎变更计数，失效预测缓存
  cl_buf : Array[Json]                             // 在线对比学习缓冲（#19）
  mut wal_log : Array[String]                      // 增量固化 WAL 日志（#21，事件溯源）
  mut fed_add : Int                                // 联邦增量：新增节点计数
  mut fed_upd : Int                                // 联邦增量：更新计数
  mut clock : Double                                // 逻辑时钟（替代 wall-clock）
  // ---- S1 检索强化：TM IDF 表（内部态，不进 to_json；from_json 后重建）----
  mut tm_df : Map[String, Int]                     // TM 文档频率：token -> 含该 token 的 TM 数
  mut tm_idf : Map[String, Double]                 // 预计算 IDF：ln((N+1)/(df+1)) + 1
  mut tm_idf_dirty : Bool                          // add_tm/剪枝后置真，fuzzy_match 惰性重算
  // ---- P4-2 术语首字符倒排（内部态，不进 to_json；from_json 后重建）----
  mut term_idx : Map[String, Array[String]]        // term 首字符 -> term 节点 mid 列表（enforce/check 候选剪枝加速）
  mut term_idx_dirty : Bool                        // load_tbx/mark_term/剪枝后置真，惰性重建
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

// pred_cache 容量上限：超过后清空整表（预测缓存是内部态，仅影响下一次是否命中，
// 不改变预测结果本身，故对确定性输出零影响；清空比 LRU 更简单且无损正确性）
const PRED_CACHE_MAX : Int = 512

// WAL：追加一条增量固化操作日志（#21）
const WAL_AUTO_LIMIT : Int = 4096   // P3-1：超过此条数自动压缩（防服务长跑 WAL 无界增长）
const WAL_AUTO_KEEP : Int = 2048    // P3-1：压缩后保留的最近条数（确定性阈值，同输入同压缩点）
fn ProphecyEngine::wal_append(self : ProphecyEngine, line : String) -> Unit {
  self.wal_log.push(line)
  // 自动压缩：仅当超过上限时裁剪到最近 WAL_AUTO_KEEP 条（幂等、确定性；对 ≤ 上限的既有行为零影响）。
  // 注意：压缩后 WAL 仅保证最近 WAL_AUTO_KEEP 条（近段增量），wal_replay 不再保证完整事件溯源；
  // 完整持久化/恢复请走 to_json/from_json（memories 全量序列化），勿依赖 wal_replay 作为唯一容灾来源。
  if self.wal_log.length() >= WAL_AUTO_LIMIT {
    self.wal_compact(WAL_AUTO_KEEP)
  }
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

// 泛型降序排序（稳定自底向上归并，零依赖）：按 key 抽取的数值字段对 arr 做原地降序重排。
// 统一取代原 sort_sd / sort_si / sort_scored 三份近重复的选型排序，
// 以及 fuzzy_match / concordance 内联的插入排序。
// P2-1：将原 O(n²) 选择排序替换为 O(n log n)，且为稳定归并（相等 key 保持原相对顺序，
// 与原选择排序逐位一致，故对确定性输出零影响）。
fn[T] sort_desc_by_key(arr : Array[T], key : (T) -> Double) -> Unit {
  let n = arr.length()
  if n <= 1 {
    return
  }
  // 辅助数组（长度与源一致），自底向上归并
  let aux : Array[T] = []
  for i = 0; i < n; i = i + 1 {
    aux.push(arr[i])
  }
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = if lo + width < n { lo + width } else { n }
      let hi = if lo + 2 * width < n { lo + 2 * width } else { n }
      // 合并 arr[lo:mid] 与 arr[mid:hi] 到 aux[lo:hi]：取左优先 ⇒ 稳定
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while k < hi {
        if j >= hi || (i < mid && key(arr[i]) >= key(arr[j])) {
          aux[k] = arr[i]
          i = i + 1
        } else {
          aux[k] = arr[j]
          j = j + 1
        }
        k = k + 1
      }
      lo = lo + 2 * width
    }
    // 一趟结束：aux 写回 arr，供下一轮读取
    for k = 0; k < n; k = k + 1 {
      arr[k] = aux[k]
    }
    width = width * 2
  }
}

// 泛型 Top-K 打包（P2-3）：对已按 score 降序的候选数组取前 k 个，经 pack 映射为 Json。
// 与 fuzzy_match / fuzzy_match_legacy 原内联 while 循环逐位等价（None 跳过、None 不压缩索引）。
fn[T] pack_topk_json(scored : Array[T], k : Int, pack : (T) -> Option[Json]) -> Array[Json] {
  let out : Array[Json] = []
  let lim = if k > scored.length() { scored.length() } else { k }
  let mut i = 0
  while i < lim {
    match pack(scored[i]) {
      Some(j) => out.push(j)
      None => ()
    }
    i = i + 1
  }
  out
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
    tm_toks: [],
    tm_ngrams: [],
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
    tm_df: Map::from_iter(([] : Array[(String, Int)]).iter()),
    tm_idf: Map::from_iter(([] : Array[(String, Double)]).iter()),
    tm_idf_dirty: false,
    term_idx: Map::from_iter(([] : Array[(String, Array[String])]).iter()),
    term_idx_dirty: false,
  }
}

fn ProphecyEngine::_new_id(self : ProphecyEngine) -> String {
  self.seq = self.seq + 1
  "m" + self.seq.to_string()
}

// ---- S1 检索强化：TM IDF 表（确定性重建，逻辑时钟无关）----

// 全量重建 TM 文档频率与 IDF 表（幂等；add_tm/consolidate-prune/from_json 后调用）
fn ProphecyEngine::rebuild_tm_idf(self : ProphecyEngine) -> Unit {
  let df : Map[String, Int] = Map::from_iter(([] : Array[(String, Int)]).iter())
  let mut n = 0
  for _, m in self.memories.iter2() {
    if m.mtype != "tm" {
      continue
    }
    n = n + 1
    let seen : Map[String, Bool] = Map::from_iter(([] : Array[(String, Bool)]).iter())
    for t in yimai_tokenize(m.text) {
      if seen.contains(t) {
        continue
      }
      seen.set(t, true)
      let v = match df.get(t) {
        Some(x) => x
        None => 0
      }
      df.set(t, v + 1)
    }
  }
  self.tm_df = df
  let idf : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  for t, f in self.tm_df.iter2() {
    // idf = ln((N+1)/(df+1)) + 1：常见词（df 高）权重低，罕见术语（df 低）权重高；N=0 时 idf=1
    idf.set(t, @math.ln((n + 1).to_double() / (f + 1).to_double()) + 1.0)
  }
  self.tm_idf = idf
  self.tm_idf_dirty = false
}

fn ProphecyEngine::mark_tm_idf_dirty(self : ProphecyEngine) -> Unit {
  self.tm_idf_dirty = true
}

// 惰性重算：fuzzy_match 开头调用，仅当 dirty 时全量重建（保证每次 fuzzy_match 的 IDF 表新鲜）
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
    m2.tm_ngrams = char_ngrams(m.text, 2)
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
    // 若合并目标是 TM 节点，text 已改写，须同步重建特征缓存并刷新 IDF（P2-2）
    if m.mtype == "tm" {
      m.tm_toks = yimai_tokenize(m.text)
      m.tm_ngrams = char_ngrams(m.text, 2)
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
    tm_toks: if mtype == "tm" { yimai_tokenize(text) } else { [] },
    tm_ngrams: if mtype == "tm" { char_ngrams(text, 2) } else { [] },
  }
  if mtype == "tm" {
    self.mark_tm_idf_dirty()
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
  if pool.size() > 0 {
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
  self.mark_tm_idf_dirty()   // S1：剪枝可能删 TM 节点，IDF 表需重算（fuzzy_match 惰性触发）
  self.mark_term_index_dirty()   // P4-2：剪枝可能删术语节点，索引需重建
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
      self.rebuild_tm_features()
      self.rebuild_term_index()   // P4-2：回滚后重建术语首字符索引（幂等）
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
    tm_toks: yimai_tokenize(src),
    tm_ngrams: char_ngrams(src, 2),
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
pub fn ProphecyEngine::fuzzy_match(self : ProphecyEngine, query : String, k : Int, threshold : Double) -> Json {
  self.ensure_tm_idf()
  let qv = tf_vector(yimai_tokenize(query))
  let q2 = char_ngrams(query, 2)
  let qtok = unique(yimai_tokenize(query))
  let anchor = first_anchor(query)
  let cands : Array[(String, Double, Double, Double, Double)] = []
  for mid, m in self.memories.iter2() {
    if m.mtype != "tm" {
      continue
    }
    let sim_tok = idf_dice(qv, m.vec, self.tm_idf)
    let sim_ng = dice_coeff(q2, m.tm_ngrams)
    let sim_ts = dice_coeff(qtok, unique(m.tm_toks))
    let sim_pos = if anchor != "" && term_hit(m.text, anchor) { 1.0 } else { 0.0 }
    let score = 0.55 * sim_tok + 0.20 * sim_ng + 0.15 * sim_ts + 0.10 * sim_pos
    if score >= threshold {
      cands.push((mid, score, sim_tok, sim_ng, sim_ts))
    }
  }
  sort_desc_by_key(cands, fn(c){ c.1 })
  let out = pack_topk_json(cands, k, fn(c) {
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
  arr_json(out)
}

// 旧版模糊匹配（S1 之前的公式）：0.7·token-cosine + 0.3·char-ratio。
// 保留用于 A/B 对照与平滑迁移（新公式验证通过后可在下个版本移除）。
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
        tm_ngrams: [],
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

// 句段级 QE 分数（0..1）：0.55·匹配率 + 0.30·术语一致 + 0.15·字符相似
// match_rate 为 [0,1]（与 fuzzy_match 的 score 同量级，勿传 match_pct）
// 注：跨语言句对字符相似度/长度比天然偏低，若作为惩罚项会把分数压到 ~0.7 失真，
// 故 QE 以 TM 匹配率 + 术语一致为主，字符相似仅作正向加项（同语言场景才显著）。
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
  let score = 0.55 * qmatch + 0.30 * qterm + 0.15 * qchar
  min1(max0(0.0, score))
}

// MQM 维度标注：terminology / accuracy / fluency / omission（含严重度）
pub fn ProphecyEngine::mqm_tags(
  _self : ProphecyEngine,
  source : String,
  target : String,
  _match_rate : Double,
  term_ok : Bool,
) -> Json {
  let issues : Array[Json] = []
  if !term_ok {
    issues.push(obj([
      ("dimension", str_json("terminology")),
      ("severity", str_json("major")),
      ("detail", str_json("术语未通过一致性校验（check_terms 检出违规）")),
    ]))
  }
  // 跨语种（如 英→中）字符级相似度天然偏低，char_ratio 不可作为 accuracy 判据；
  // 译文为空时 char_ratio 恒为 0，亦无意义（空译文由 fluency/critical 覆盖），跳过
  let cross = cross_script(source, target)
  let cr = char_ratio(source, target)
  if !cross && target.length() > 0 && cr < 0.5 {
    issues.push(obj([
      ("dimension", str_json("accuracy")),
      ("severity", str_json("major")),
      ("detail", str_json("源-译文 字符级相似度过低 (<0.5)")),
    ]))
  }
  if target.length() == 0 {
    issues.push(obj([
      ("dimension", str_json("fluency")),
      ("severity", str_json("critical")),
      ("detail", str_json("译文为空")),
    ]))
  } else {
    let lr = target.length().to_double() / max0(1.0, source.length().to_double())
    // 跨语种长度比天然偏离（英→中译文更短），不可作为流畅性判据；
    // 源文为空时长度比无意义，亦跳过（避免空源文误报流畅性）
    if !cross && source.length() > 0 && (lr > 2.5 || lr < 0.4) {
      issues.push(obj([
        ("dimension", str_json("fluency")),
        ("severity", str_json("minor")),
        ("detail", str_json("译文长度比异常（" + r4(lr).to_string() + "），疑似流畅性问题")),
      ]))
    }
  }
  // 跨语种时译文长度通常远短于源文（英→中），长度比不可作为 omission 判据；
  // target 为空已由 fluency/critical 覆盖，此处再加 target.length()>0 防止同一问题重复标注
  if !cross && target.length() > 0 && target.length().to_double() < 0.5 * source.length().to_double() && source.length() > 0 {
    issues.push(obj([
      ("dimension", str_json("omission")),
      ("severity", str_json("major")),
      ("detail", str_json("译文过短（< 源文 50%），疑似漏译")),
    ]))
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
  obj([
    ("before_tm", num_json(b_tm.to_double())),
    ("after_tm", num_json(a_tm.to_double())),
    ("before_term", num_json(b_term.to_double())),
    ("after_term", num_json(a_term.to_double())),
    ("tm_added", num_json(tm_added.to_double())),
    ("tm_removed", num_json(tm_removed.to_double())),
    ("term_added", num_json(term_added.to_double())),
    ("term_removed", num_json(term_removed.to_double())),
  ])
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
  e.rebuild_tm_idf()   // S1：内部态不进 to_json，恢复后重建 IDF 表（幂等）
  e.rebuild_tm_features()   // P2-2：恢复后重建 TM 特征缓存（幂等）
  e.rebuild_term_index()   // P4-2：恢复后重建术语首字符索引（幂等）
  e
}

// ===== M1 风格一致性检查（启发式，确定性）=====
pub fn ProphecyEngine::style_check(self : ProphecyEngine, text : String) -> Json {
  let issues : Array[Json] = []
  let sentences = text.split("。").to_array().map(fn(x) { x.to_string() })
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

// ===== M2 回译验证（LCS 对齐质量）=====
pub fn ProphecyEngine::back_align(self : ProphecyEngine, source : String, target : String) -> Json {
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
  for mid, m in self.memories.iter2() {
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
                if cid != "" && not(seen.contains(cid)) {
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