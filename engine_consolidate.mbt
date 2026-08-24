// engine_consolidate.mbt
// =====================================================================
// P10: 从 engine.mbt 拆出 — 同包（@lib）多文件，调用点零修改。
// 主题: consolidate 4 段 + restore + WAL 增量日志 (D6 固化 + #21 WAL 事件溯源)

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

// ---------------------------------------------------------------------------
// D6 固化重放
// ---------------------------------------------------------------------------

// P4 重构：consolidate 112 行拆为 4 段私有 fn
//   - consolidate_edge_decay: 边权按 recency 弹性衰减，< MIN_EDGE 或目标不存在则丢弃
//   - consolidate_trans_decay: 转移计数乘 TRANS_DECAY，< 0.5 丢弃
//   - consolidate_prune_nodes: (可选) 压 predictive_value<0.08 & use_count<=1 & 不在 context 的节点
//   - consolidate_meta_cognition: 近期 50 步命中率 → explore 参数自适应
//   快照/重算价值仍留在主 fn（属于编排不变量，F1 约束）

// 段 1：边权弹性衰减 + 边剪枝（始终执行；不依赖 prune flag）
fn ProphecyEngine::consolidate_edge_decay(self : ProphecyEngine) -> Unit {
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
}

// 段 2：转移计数衰减（对齐 D1–D8 规范：缓慢衰减，权重 < 0.5 的转移被丢弃）
fn ProphecyEngine::consolidate_trans_decay(self : ProphecyEngine) -> Unit {
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
}

// 段 3：(可选) 压缩零预测价值噪声节点；返回剪枝数
fn ProphecyEngine::consolidate_prune_nodes(self : ProphecyEngine) -> Int {
  let mut removed = 0
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
  removed
}

// 段 4：元认知调控 — 近期 50 步命中率 → explore 参数自适应；返回 hr 给主 fn 算 target_lr
fn ProphecyEngine::consolidate_meta_cognition(self : ProphecyEngine) -> Double {
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
  hr
}

pub fn ProphecyEngine::consolidate(self : ProphecyEngine, prune : Bool) -> Json {
  // 0. 约束契约：固化前对记忆/转移/角色转移做快照，支持回滚
  //    （F1：三者须一致回滚，否则记忆与转移表错位导致预测失真）
  self.snapshot = Some(copy_memories(self.memories))
  self.snap_trans = Some(copy_trans(self.transitions))
  self.snap_role = Some(copy_trans(self.role_trans))
  // 1-2. 衰减（始终执行）
  self.consolidate_edge_decay()
  self.consolidate_trans_decay()
  // 3. 重算预测价值
  self._recompute_values()
  // 4. (可选) 剪枝
  let removed = if prune { self.consolidate_prune_nodes() } else { 0 }
  // 5. 元认知（同时返回 hr 给 target_lr 用）
  let hr = self.consolidate_meta_cognition()
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
      // P1：restore 可能回滚掉 snapshot 之后的 TM 增删；若期间发生过 rebuild（脏标记已清），
      // IDF/postings/tm_count 仍是回滚前口径 → 置脏强制下次 fuzzy_match 重建（幂等，输出确定性不变）
      self.mark_tm_idf_dirty()
      obj([("ok", true.to_json()), ("nodes", num_json(self.memories.length().to_double()))])
    }
    None => obj([("ok", false.to_json()), ("reason", str_json("no snapshot"))])
  }
}

// ---- #21 中/长期：WAL 增量固化 / 主动学习 / 联邦 / 蒸馏 ----
const WAL_SEP : String = "\u0001"

// 从 WAL 重放重建引擎（事件溯源：仅重放 remember/observe 原子事件）
pub fn ProphecyEngine::wal_replay(self : ProphecyEngine) -> ProphecyEngine {
  let e = ProphecyEngine::make()
  for line in self.wal_log {
    let parts = line.split(WAL_SEP).to_array()
    // 记录格式: op␁mid␁text␁mtype（␁ = WAL_SEP）；text/mtype 已做 wal_escape_field 转义
    if parts.length() >= 4 {
      let op = parts[0].to_owned()
      let text = wal_unescape_field(parts[2].to_owned())
      let mtype = wal_unescape_field(parts[3].to_owned())
      // P6 加固：只接受已知的 op，未知 op 直接跳过，防止被污染 WAL 破坏状态
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

