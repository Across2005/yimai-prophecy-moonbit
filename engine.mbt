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

// P1 性能：小语料（<PRUNE_MIN_TM 条 TM）走全图，不启动倒排剪枝。
// 原因：IDF 在小语料上区分度低（df 多为 1），top-3 候选可能全落在单一 TM，破坏 Top-K 完备性；
// 全图扫描在 < 1K TM 量级本就 < 1ms，倒排剪枝只对 1K+ 才有收益。
const PRUNE_MIN_TM : Int = 200

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
  mut tm_toks : Array[String]                // yimai_tokenize(text)（未去重，供 concordance 计数 + idf 重建复用）
  mut tm_ngrams : Map[String, Bool]          // char 2-gram 去重集合（P1 Map 化：fuzzy 字符 2-gram 分项零分配）
  mut tm_toks_set : Map[String, Bool]        // unique(tm_toks) 去重集合（P1 Map 化：fuzzy token 集合分项零分配）
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
  mut tm_idf_dirty : Bool                          // add_tm/剪枝/restore 后置真，fuzzy_match 惰性重算
  mut tm_count : Int                               // TM 节点数缓存（rebuild_tm_idf 顺带刷新；count_tm O(1) 读）
  // ---- P1 倒排剪枝：TM token -> mids 倒排（内部态，不进 to_json；与 tm_idf 同源）----
  mut tm_postings : Map[String, Array[String]]    // TM 倒排：token -> 含该 token 的 TM mid 列表（fuzzy_match 候选剪枝）
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
    tm_toks_set: Map([]),
    tm_ngrams: Map([]),
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
    tm_count: 0,
    tm_postings: Map::from_iter(([] : Array[(String, Array[String])]).iter()),
    term_idx: Map::from_iter(([] : Array[(String, Array[String])]).iter()),
    term_idx_dirty: false,
  }
}

fn ProphecyEngine::_new_id(self : ProphecyEngine) -> String {
  self.seq = self.seq + 1
  "m" + self.seq.to_string()
}
// ---------------------------------------------------------------------------
// 序列化（状态跨调用 / 持久化）
// ---------------------------------------------------------------------------
//
// to_json / from_json 是状态 schema 的**事实契约**——`tm_store.json` 落盘 + 跨会话恢复
// 全部依赖它们。改字段名 / 顺序会破坏 backward compat，所以这两个函数保持**显式列出**所有
// 字段（不抽 helper，不动字段名）。
//
// 评估结论（2026-08 评审）：当前 to_json 50 行 + from_json 50 行 + schema 21 字段，
// 还在可读范围，**不强拆**。拆分触发条件（任一）：
//   1) schema 字段数 > 30（每段 > 8 字段，逻辑才"自然"分组）
//   2) 字段分组出现明显语义边界（例如新增 neural 层 / multimodal OCR / 联邦 WAL 时）
//   3) to_json 或 from_json 任一行数 > 100
//
// 短期可改进方向（如果以后真拆）：
//   - to_json 拆为 to_json_core / to_json_episodes / to_json_meta / to_json_tuning 四段
//   - from_json 同构四段
//   - 加 schema_version 字段在 JSON 顶层（目前隐式 v0.1.0，无显式版本号）

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
  e.rebuild_tm_features()   // P2-2：恢复后重建 TM 特征缓存（幂等；P1 须先于 idf——rebuild 复用 tm_toks）
  e.rebuild_tm_idf()   // S1：内部态不进 to_json，恢复后重建 IDF 表（幂等；P1 复用 tm_toks 并刷新 tm_count）
  e.rebuild_term_index()   // P4-2：恢复后重建术语首字符索引（幂等）
  e
}
