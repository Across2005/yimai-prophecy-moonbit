// yimai_prophecy_moonbit_mqm_reannotation_test.mbt —— P5 MQM re-annotation 流程测试
// 覆盖：T38 (Critical 触发) / T39 (determinism) / T40 (skip when no Critical) / T41 (consistent)
//
// P5 增量背景：Google 2025-10-28 论文 "Improving Human Translation Evaluation with
// Re-annotation"（Riley et al.）指出 MQM 二次标注可显著提升评估一致性。
// yimai 实现：mqm_re_annotate 对所有 Critical severity 段强制走二次审流程（自重审），
// 显式产出 re_annotated / critical_count / re_annotations 三段式 JSON。
// 当前是 deterministic 自重审（同输入必同输出），未来可扩 mqm_tags_with_rater(rater_id)
// 走多标注员模型。
//
// 关联：engine.mbt::mqm_re_annotate + cmd/service/routes.mbt::handle_mqm_re_annotate
//       + cmd/service/mcp.mbt::mqm_re_annotate tool + yimai_prophecy_moonbit.mbt::routes_meta

// ---------------------------------------------------------------------------
// T38: Critical severity 触发 re-annotation
//   构造"negation flip + 数字漏译"类高危段，预期 mqm_tags 至少产出 1 个 Critical 段，
//   mqm_re_annotate 据此走二次审并 re_annotated=true。
// ---------------------------------------------------------------------------
test "T38 mqm_re_annotate_flags_critical" {
  let eng = @lib.ProphecyEngine::make()
  let result = eng.mqm_re_annotate(
    "The device must not be pressurized at 30 psi.",
    "应当对该装置加压。",
    0.30,  // 极低 match_rate
  )
  let s = result.stringify()
  // 至少 1 个 Critical 段触发
  inspect(s.contains("\"re_annotated\":true"), content="true")
  // re_annotations 内每个 critical 段都有 original_severity=="critical"
  inspect(s.contains("\"original_severity\":\"critical\""), content="true")
  // critical_count 字段必须存在
  inspect(s.contains("\"critical_count\":1"), content="true")
}

// ---------------------------------------------------------------------------
// T39: 确定性 — 同一段两次调用返回完全相同（re-annotation 也是 deterministic）
// ---------------------------------------------------------------------------
test "T39 mqm_re_annotate_deterministic" {
  let eng = @lib.ProphecyEngine::make()
  let a = eng.mqm_re_annotate(
    "The device must not be pressurized at 30 psi.",
    "应当对该装置加压。",
    0.30,
  )
  let b = eng.mqm_re_annotate(
    "The device must not be pressurized at 30 psi.",
    "应当对该装置加压。",
    0.30,
  )
  inspect(a.stringify() == b.stringify(), content="true")
}

// ---------------------------------------------------------------------------
// T40: 非 Critical 段跳过二次审（re_annotated=false，性能优化）
//   高 match_rate + 译文长度正常 + 无数字丢失 → 不会触发 Critical
// ---------------------------------------------------------------------------
test "T40 mqm_re_annotate_skips_minor" {
  let eng = @lib.ProphecyEngine::make()
  let result = eng.mqm_re_annotate(
    "Use a pressure valve to activate the device.",
    "使用压力阀激活装置。",
    0.85,  // 高 match_rate，不触发 Critical
  )
  let s = result.stringify()
  // 无 Critical 段，re_annotated 应为 false，critical_count=0
  inspect(s.contains("\"re_annotated\":false"), content="true")
  inspect(s.contains("\"critical_count\":0"), content="true")
}

// ---------------------------------------------------------------------------
// T40b: re_annotations 段在 critical_count=0 时为空数组
// ---------------------------------------------------------------------------
test "T40b mqm_re_annotate_empty_array_when_no_critical" {
  let eng = @lib.ProphecyEngine::make()
  let result = eng.mqm_re_annotate(
    "Hello world",
    "你好世界",
    0.95,
  )
  // re_annotations 字段必须存在且为空数组
  inspect(result.stringify().contains("\"re_annotations\":[]"), content="true")
}

// ---------------------------------------------------------------------------
// T41: consistent 字段在 deterministic 自重审下恒为 true
//   这是当前实现的核心保证：算法 deterministic ⇒ 二次审结果与原审一致。
//   未来走多标注员模型时此断言不再恒真，需更新测试。
// ---------------------------------------------------------------------------
test "T41 mqm_re_annotate_consistent_under_deterministic_self_review" {
  let eng = @lib.ProphecyEngine::make()
  let result = eng.mqm_re_annotate(
    "The device must not be pressurized at 30 psi.",
    "应当对该装置加压。",
    0.30,
  )
  // 所有 critical 段的 consistent 字段应为 true
  inspect(result.stringify().contains("\"consistent\":true"), content="true")
}
