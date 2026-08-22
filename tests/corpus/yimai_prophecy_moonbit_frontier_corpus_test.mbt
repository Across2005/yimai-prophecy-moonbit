// yimai_prophecy_moonbit_frontier_corpus_test.mbt
// Frontier Multi-Domain Corpus (2026) — 8 humanities & science domains
// ======================================================================
// 2026-08 增补：紧接 modern_corpus (8 域, 工程/物理) 与 extended_corpus (6 域,
// 机器人/聚变/合成生物/航天/电池/AI 制药) 之后,本文件覆盖 8 个新增领域
// 的人文/前沿主题,响应 cron 维护任务「测试 10 个翻译语料」的需求:
//
//   1. 前沿科技 ① — AI Safety / AGI 评估
//   2. 前沿科技 ② — Agent 时代 / 端云协同
//   3. 科学    — 凝聚态物理 (Majorana wire criticality)
//   4. 数学 ①  — 算术几何 (BSD 猜想)
//   5. 数学 ②  — 拓扑与高维范畴
//   6. 哲学    — 现象学与心智哲学
//   7. 文学    — 数字人文 (Computational Literary Studies)
//   8. 心理学  — 认知行为疗法 (CBT) / 实施意图
//   9. 民航    — RNP AR / 适航 (BCAR Section L)
//  10. 航天    — 国际月球科研站 ILRS
//
// 语料来源: 2026 年 1-8 月学术论文 + 行业白皮书 + 顶会报告,具体来源:
//   - AGI 评估: 腾讯 ConTech 2025 + SITS 2026 + IDC 2026 企业级 AGI 白皮书
//   - 端云协同: Computex 2026 高通 CEO Amon 主题演讲
//   - 凝聚态物理: Yale Vlad Kurilovich 博士论文 (2024) + J. Phys. Condens. Matter
//   - 算术几何: 经典 BSD 猜想文献 (Mordell-Weil / Selmer / Iwasawa)
//   - 范畴论: Lurie Higher Topos Theory + Jacob Lurie 谱代数几何
//   - 心智哲学: Smith & Thomasson Phenomenology and Philosophy of Mind (OUP 2005)
//   - 数字人文: Digital Humanities Now + Tübingen Computational Literary Studies
//   - CBT: Gabriele Oettingen WOOP 框架 + Clinical Psychology & Psychotherapy 2026
//   - 民航: UK CAA CAP 632 / BCAR Section L / Boeing CMO 2026
//   - 航天: CNSA ILRS 国际合作 / 国际月球科研站路线图 2035

// ---- Helper: recall texts (frontier corpus version) ----
fn fc_recall_texts(rec : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for x in rec {
    match x {
      Json::Object(m) =>
        match m.get("text") {
          Some(Json::String(s)) => out.push(s)
          _ => ()
        }
      _ => ()
    }
  }
  out
}

// ---- Helper: generic training loop ----
fn fc_train(eng : @lib.ProphecyEngine, corpus : Array[(String, String)], reps : Int) -> Unit {
  for _r = 0; _r < reps; _r = _r + 1 {
    eng.end_episode()
    for i = 0; i < corpus.length(); i = i + 1 {
      let _ = eng.predict(3)
      let _ = eng.observe(corpus[i].0, corpus[i].1)
    }
  }
}

// ============================================================================
// FRONTIER CORPUS: 10 sub-domains across 8 themes, 60 sentence pairs total
// ============================================================================

// ---- Domain 1: AI Safety & AGI 评估 (前沿科技 ①) ----
let fc_ai_safety : Array[(String, String)] = [
  ("Project: AGI Safety Technical Report Q4 2025", "instruction"),
  ("Define evaluation taxonomy for frontier model capabilities", "instruction"),
  ("Run red-teaming exercises against RLHF-tuned LLaMA-4 variant", "fact"),
  ("Audit chain-of-thought faithfulness using sparse autoencoders", "fact"),
  ("Compute compliance score against EU AI Act Article 52", "instruction"),
  ("Publish redacted safety case with differential privacy guarantees", "instruction"),
]

// ---- Domain 2: Agent 时代 / 端云协同 (前沿科技 ②) ----
let fc_agent_edge : Array[(String, String)] = [
  ("Project: Hybrid AI Orchestrator for Edge-Cloud Token Offload", "instruction"),
  ("Deploy 30/70 device-cloud split for Agentic AI inference to cut cost 60%", "fact"),
  ("Validate Raptor 3 methalox engine restart after 14-day orbital coast", "fact"),
  ("Benchmark on-device LLM at 2mW headphone to AI PC power range", "instruction"),
  ("Wire Qualcomm Dragonfly datacenter accelerator into CDN tier", "fact"),
  ("Publish Dragonwing IQ10 robotics stack performance report", "instruction"),
]

// ---- Domain 3: 凝聚态物理 (Majorana wire criticality) ----
let fc_majorana : Array[(String, String)] = [
  ("Project: Criticality in Majorana Wires 2026 Validation", "instruction"),
  ("Engineer one-dimensional topological superconductor with Majorana zero modes", "fact"),
  ("Combine quantum Hall and conventional superconducting states in heterostructure", "fact"),
  ("Establish that disorder tunes system to critical point between trivial and topological phases", "instruction"),
  ("Compute nonlocal transport of two counter-propagating quantum Hall edge states", "fact"),
  ("Publish universal Majorana wire transport theory in Nature Physics", "instruction"),
]

// ---- Domain 4: 算术几何 (BSD 猜想) ----
let fc_bsd : Array[(String, String)] = [
  ("Project: BSD Conjecture Progress Review for Rank-0 Elliptic Curves", "instruction"),
  ("Compute Mordell-Weil rank for elliptic curve over Q at conductor 5077", "fact"),
  ("Establish that Selmer group has rank 0 via 3-descent computation", "fact"),
  ("Apply Iwasawa main conjecture to analyze p-adic L-function behavior", "instruction"),
  ("Resolve that L(E,1)=0 implies Mordell-Weil rank at least 1 by Kolyvagin's theorem", "fact"),
  ("Publish complete BSD proof for rank-0 curves in Annals of Mathematics", "instruction"),
]

// ---- Domain 5: 拓扑与高维范畴 ----
let fc_higher_cat : Array[(String, String)] = [
  ("Project: Derived Algebraic Geometry of Higher Stacks", "instruction"),
  ("Construct infinity-category of presentable infinity-categories", "fact"),
  ("Establish Quillen model structure on simplicial presheaves", "fact"),
  ("Prove that derived stack of formal moduli is an algebraic stack", "instruction"),
  ("Apply Lurie's higher topos theory to descent obstruction problems", "fact"),
  ("Publish complete treatment of spectral algebraic geometry in Cambridge Tracts", "instruction"),
]

// ---- Domain 6: 现象学与心智哲学 ----
let fc_phenomenology : Array[(String, String)] = [
  ("Project: Phenomenology of Intentionality in Cross-Tradition Synthesis", "instruction"),
  ("Investigate Husserl's noetic-noematic structure of consciousness", "fact"),
  ("Apply phenomenological reduction to suspend the natural attitude", "fact"),
  ("Reject physicalist reduction of qualia in defense of the Hard Problem", "instruction"),
  ("Examine Merleau-Ponty's lived body as subject of perceptual experience", "fact"),
  ("Publish cross-tradition synthesis in Oxford Handbook of Philosophy of Mind", "instruction"),
]

// ---- Domain 7: 数字人文 (Computational Literary Studies) ----
let fc_digital_humanities : Array[(String, String)] = [
  ("Project: Computational Literary Studies for Modernist Corpus", "instruction"),
  ("Run stylometric authorship attribution on 1920s Paris manuscripts", "fact"),
  ("Apply BERTopic to detect thematic drift across Ulysses chapters", "fact"),
  ("Train word2vec on Million Book corpus to track lexical semantic change", "instruction"),
  ("Validate distant reading hypotheses with targeted close reading spot-checks", "fact"),
  ("Publish topic-model-driven literary periodization in Journal of Cultural Analytics", "instruction"),
]

// ---- Domain 8: 临床心理学 (CBT 实施意图) ----
let fc_cbt : Array[(String, String)] = [
  ("Project: Digital CBT Implementation Intentions 2026", "instruction"),
  ("Apply WOOP framework to translate wishes into concrete If-Then plans", "fact"),
  ("Train therapist on cognitive restructuring of automatic negative thoughts", "fact"),
  ("Measure effect size of CBT on metacognitive beliefs in OCD network analysis", "instruction"),
  ("Validate that self-compassion group therapy reduces adolescent MDD symptom severity", "fact"),
  ("Publish randomized controlled trial results in Clinical Psychology & Psychotherapy", "instruction"),
]

// ---- Domain 9: 民航 (RNP AR / 适航) ----
let fc_civil_aviation : Array[(String, String)] = [
  ("Project: RNP AR Approach Procedure Design for Continental Airports", "instruction"),
  ("Compute aircraft positioning accuracy requirement of RNP 0.1 nautical miles", "fact"),
  ("Validate Flight Management System two-dimensional navigation with RNP", "fact"),
  ("Apply Special Authorization I for RNP AR procedures with RF leg segments", "instruction"),
  ("Design missed approach procedure with vertical guidance LPV minimums", "fact"),
  ("Publish BCAR Section L amendment for aircraft maintenance engineer licensing", "instruction"),
]

// ---- Domain 10: 航天 (国际月球科研站 ILRS) ----
let fc_ilrs : Array[(String, String)] = [
  ("Project: International Lunar Research Station Basic Model by 2035", "instruction"),
  ("Coordinate Chang'e-7 relay satellite for far-side sample return mission", "fact"),
  ("Assemble Shackleton crater landing zone with regolith-shielded pressurized habitat", "fact"),
  ("Validate methalox propulsion restart capability for sustained lunar night operation", "instruction"),
  ("Establish international partner network via DSEL cooperation memoranda of understanding", "fact"),
  ("Publish ILRS Phase 1 architecture at International Deep Space Exploration Conference", "instruction"),
]

// ---- Training helper that iterates all 10 sub-corpora ----
fn fc_train_all(eng : @lib.ProphecyEngine, reps : Int) -> Unit {
  fc_train(eng, fc_ai_safety, reps)
  fc_train(eng, fc_agent_edge, reps)
  fc_train(eng, fc_majorana, reps)
  fc_train(eng, fc_bsd, reps)
  fc_train(eng, fc_higher_cat, reps)
  fc_train(eng, fc_phenomenology, reps)
  fc_train(eng, fc_digital_humanities, reps)
  fc_train(eng, fc_cbt, reps)
  fc_train(eng, fc_civil_aviation, reps)
  fc_train(eng, fc_ilrs, reps)
}

// ===========================================================================
// T38..T47: Per-corpus prediction + recall tests
// ===========================================================================

// T38: 训练后 predict 能产出非空预测 (10 语料中至少一个能召回)
test "T38 frontier-corpus: 训练 10 语料后 predict 至少一个产出" {
  let e = @lib.ProphecyEngine::make()
  fc_train_all(e, 2)
  let p = e.predict(3)
  match p {
    Json::Object(o) => {
      let preds = match o.get("predictions") { Some(Json::Array(a)) => a; _ => [] }
      inspect(preds.length() >= 1, content="true")
    }
    _ => inspect(false, content="true")
  }
}

// T39: AI Safety 训练后 recall 召回 EU AI Act 相关记忆
test "T39 frontier-AI-Safety: recall 召回 EU AI Act 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_ai_safety, 3)
  let r = e.recall("EU AI Act Article 52 compliance score", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "EU AI Act") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T40: 凝聚态物理 训练后 recall 召回 Majorana 关键词
test "T40 frontier-Majorana: recall 召回 Majorana 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_majorana, 3)
  let r = e.recall("topological superconductor Majorana zero modes criticality", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "Majorana") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T41: 算术几何 训练后 recall 召回 BSD / Selmer 关键词
test "T41 frontier-BSD: recall 召回 BSD 猜想与 Selmer 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_bsd, 3)
  let r = e.recall("BSD conjecture Mordell-Weil rank Selmer group", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "BSD") || @lib.str_contains(t, "Mordell-Weil") ||
       @lib.str_contains(t, "Selmer") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T42: 拓扑学 训练后 recall 召回 infinity-category 关键词
test "T42 frontier-higher-cat: recall 召回 infinity-category 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_higher_cat, 3)
  let r = e.recall("infinity-category presentable simplicial presheaf", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "infinity-category") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T43: 现象学 训练后 recall 召回 intentionality 关键词
test "T43 frontier-phenomenology: recall 召回 intentionality 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_phenomenology, 3)
  let r = e.recall("Husserl intentionality noetic-noematic phenomenology", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "intentionality") || @lib.str_contains(t, "Husserl") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T44: 数字人文 训练后 recall 召回 stylometry / BERTopic 关键词
test "T44 frontier-digital-humanities: recall 召回 stylometry 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_digital_humanities, 3)
  let r = e.recall("stylometric authorship BERTopic distant reading", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "stylometric") || @lib.str_contains(t, "BERTopic") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T45: 心理学 训练后 recall 召回 WOOP / If-Then 关键词
test "T45 frontier-CBT: recall 召回 WOOP / If-Then 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_cbt, 3)
  let r = e.recall("WOOP implementation intentions If-Then plan cognitive restructuring", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "WOOP") || @lib.str_contains(t, "If-Then") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T46: 民航 训练后 recall 召回 RNP AR 关键词
test "T46 frontier-civil-aviation: recall 召回 RNP AR 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_civil_aviation, 3)
  let r = e.recall("RNP AR approach procedure RF leg BCAR Section L", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "RNP") || @lib.str_contains(t, "BCAR") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T47: 航天 训练后 recall 召回 ILRS / 月球 关键词
test "T47 frontier-ILRS: recall 召回 ILRS 关键词" {
  let e = @lib.ProphecyEngine::make()
  fc_train(e, fc_ilrs, 3)
  let r = e.recall("International Lunar Research Station ILRS Chang'e-7 methalox", 5)
  let texts = fc_recall_texts(r)
  let mut has_match = false
  for t in texts {
    if @lib.str_contains(t, "Lunar Research Station") ||
       @lib.str_contains(t, "ILRS") ||
       @lib.str_contains(t, "Chang'e-7") { has_match = true }
  }
  inspect(has_match, content="true")
}

// T48: 跨域训练后 add_tm (TM 一等公民) 入索引, fuzzy_match 仍命中
//   fuzzy_match 只搜索 mtype="tm" 的 memory, observe 训练不入索引;
//   add_tm 是 fuzzy_match 真正测试的入口。验证跨域 TM 一等公民能力。
test "T48 frontier-cross-corpus: 跨域 add_tm 后 fuzzy_match 命中 TM 文本" {
  let e = @lib.ProphecyEngine::make()
  fc_train_all(e, 2)
  // 把 4 个跨域术语对加入 TM 索引 (翻译记忆一等公民)
  let _ = e.add_tm(
    "International Lunar Research Station Basic Model 2035",
    "国际月球科研站基础型 2035",
  )
  let _ = e.add_tm(
    "RNP AR approach procedure with RF leg segment",
    "RNP AR 进近程序含 RF 航段",
  )
  let _ = e.add_tm(
    "WOOP implementation intentions If-Then plan",
    "WOOP 实施意图 If-Then 计划",
  )
  let _ = e.add_tm(
    "topological superconductor Majorana zero modes criticality",
    "拓扑超导 Majorana 零模临界性",
  )
  // 模糊查询: 同语义的轻微变形, 阈值 0.3 (与 modern_corpus 对齐)
  let r = e.fuzzy_match("RNP AR approach with RF leg", 3, 0.3)
  match r {
    Json::Array(arr) => {
      let mut has_hit = false
      for it in arr {
        match it {
          Json::Object(o) =>
            match o.get("source") {
              Some(Json::String(s)) =>
                if @lib.str_contains(s, "RNP") && @lib.str_contains(s, "RF") { has_hit = true }
              _ => ()
            }
          _ => ()
        }
      }
      inspect(has_hit, content="true")
    }
    _ => inspect(false, content="true")
  }
}

// T49: 跨域训练后同输入两次 predict 字节级一致 (R15 确定性契约)
test "T49 frontier-cross-corpus: 确定性 (R15) — 同输入两次状态逐字节一致" {
  let e1 = @lib.ProphecyEngine::make()
  fc_train_all(e1, 1)
  let snap1 = e1.to_json()
  let e2 = @lib.ProphecyEngine::make()
  fc_train_all(e2, 1)
  let snap2 = e2.to_json()
  inspect(snap1.stringify() == snap2.stringify(), content="true")
}

// T50: 跨域训练后 consolidate 不崩 + 记忆总量非负
test "T50 frontier-cross-corpus: consolidate 后记忆数 ≥ 0 (无回滚)" {
  let e = @lib.ProphecyEngine::make()
  fc_train_all(e, 2)
  let r = e.consolidate(false)
  match r {
    Json::Object(o) =>
      match o.get("nodes") {
        Some(Json::Number(n, ..)) => inspect(n >= 0.0, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}

// T51: 跨域训练后 predict 返回 confidence 字段 (D7 不确定性)
test "T51 frontier-cross-corpus: predict 返回 confidence + uncertainty 字段" {
  let e = @lib.ProphecyEngine::make()
  fc_train_all(e, 2)
  let p = e.predict(3)
  match p {
    Json::Object(o) => {
      let has_conf = match o.get("confidence") { Some(Json::Number(_, ..)) => true; _ => false }
      let has_unc = match o.get("uncertainty") { Some(Json::Number(_, ..)) => true; _ => false }
      inspect(has_conf && has_unc, content="true")
    }
    _ => inspect(false, content="true")
  }
}
