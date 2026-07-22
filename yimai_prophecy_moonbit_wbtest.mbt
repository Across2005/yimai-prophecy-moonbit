// Whitebox tests: validate internal invariants fixed by code review (H1/H2).
// Run `moon test`.

// H1：边权衰减在「无剪枝」时也必须生效（对齐 Python 无条件写回）。
// 回归点：旧代码用 `if new_edges.length() != m.edges.length()` 拦截写回，
// 干净网络上所有边都 >= MIN_EDGE 导致长度相等 -> EDGE_DECAY 形同虚设。
test "H1 edge decay applies without prune" {
  let e = ProphecyEngine::make()
  let a = e.remember("术语表锁定", "fact", [])
  let b = e.remember("风格对齐正式中性", "preference", [a])
  let before = match e.memories.get(a) {
    Some(m) => match m.edges.get(b) { Some(w) => w; None => 0.0 }
    None => 0.0
  }
  let _ = e.consolidate(false)
  let after = match e.memories.get(a) {
    Some(m) => match m.edges.get(b) { Some(w) => w; None => 0.0 }
    None => 0.0
  }
  // 初始边权 > 0
  inspect(before > 0.0, content="true")
  // 衰减后边权严格变小（EDGE_DECAY=0.95 生效）
  inspect(after < before, content="true")
  // 且边仍存在（>= MIN_EDGE，未因长度相等被跳过写回）
  inspect(after > 0.0, content="true")
}

// H2：逻辑时钟 clock 必须随状态序列化往返，否则恢复后 dt<0 令时效项失真。
// 回归点：旧 to_json/from_json 未包含 clock。
test "H2 logical clock persists across to_json/from_json" {
  let e = ProphecyEngine::make()
  let _ = e.remember("新建翻译项目：量子计算综述", "instruction", [])
  let _ = e.remember("提取核心术语表并锁定", "fact", [])
  let c1 = e.clock
  let j = e.to_json()
  let e2 = ProphecyEngine::from_json(j)
  // 恢复后 clock 与保存时一致
  inspect(e2.clock == c1, content="true")
  // 恢复后 dt 必须非负：clock >= 每个记忆的 last_used（u_rec 路径有效）
  for _, m in e2.memories.iter2() {
    inspect(e2.clock - m.last_used >= 0.0, content="true")
  }
}

// M1b：转移计数衰减后 < 0.5 必须被丢弃（对齐 Python consolidate 的 `if nc >= 0.5`）。
// 回归点：此前 MoonBit 的 M1 修复对转移「无条件保留」，使转移图成为 Python 的超集（只增不减）。
test "M1b transition below 0.5 is pruned" {
  let e = ProphecyEngine::make()
  // 直接植入一条单计数转移 a->b（count=1.0）
  let inner : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  inner.set("b", 1.0)
  e.transitions.set("a", inner)
  // 连续 consolidate 40 次：1.0 * 0.98^40 ≈ 0.446 < 0.5
  for _i = 0; _i < 40; _i = _i + 1 {
    let _ = e.consolidate(false)
  }
  match e.transitions.get("a") {
    Some(d) => inspect(d.length() == 0, content="true")   // 已被清空（对齐 Python 空字典）
    None => inspect(true, content="true")
  }
}
