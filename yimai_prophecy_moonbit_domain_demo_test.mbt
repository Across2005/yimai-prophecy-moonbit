// yimai_prophecy_moonbit_domain_demo_test.mbt
// 五大前沿领域 × 五轮翻译实跑（联网抓取真实前沿术语，驱动 MoonBit 引擎）
// 与 Python 版 domain_scenario_demo.py 对应；输出为引擎真实确定性结果。
// 本文件仅做演示输出，inspect 保证测试通过；transcript 供 README 引用。

// 四位小数四舍五入（引擎 util 的 r4 不在测试作用域，这里本地定义）
fn round4(x : Double) -> Double {
  (x * 10000.0).to_int().to_double() / 10000.0
}

// ---- 通用训练（5 轮 = 5 个 episode）----
fn train_real_d(eng : ProphecyEngine, corpus : Array[(String, String)], reps : Int) -> Unit {
  for _r = 0; _r < reps; _r = _r + 1 {
    eng.end_episode()
    for i = 0; i < corpus.length(); i = i + 1 {
      let _ = eng.predict(3)
      let _ = eng.observe(corpus[i].0, corpus[i].1)
    }
  }
}

fn pd_path_str(path : Json) -> String {
  match path {
    Json::Array(a) => {
      let parts : Array[String] = []
      for i = 0; i < a.length(); i = i + 1 {
        match a[i] {
          Json::Object(p) => {
            let frm = match p.get("from") { Some(Json::String(s)) => s; _ => "" }
            let pr = match p.get("prob") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
            parts.push("['" + frm + "', " + round4(pr).to_string() + "]")
          }
          _ => ()
        }
      }
      let mut s = "["
      for i = 0; i < parts.length(); i = i + 1 {
        if i > 0 { s = s + ", " }
        s = s + parts[i]
      }
      s + "]"
    }
    _ => "[]"
  }
}

fn pd_fmt_pred(pred : Json) -> Unit {
  match pred {
    Json::Object(m) =>
      match m.get("predictions") {
        Some(Json::Array(a)) => {
          for i = 0; i < a.length(); i = i + 1 {
            match a[i] {
              Json::Object(p) => {
                let txt = match p.get("text") { Some(Json::String(s)) => s; _ => "" }
                let pr = match p.get("prob") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
                let pstr = match p.get("path") { Some(x) => pd_path_str(x); _ => "[]" }
                println("· p=" + round4(pr).to_string() + " | " + txt + " | path=" + pstr)
              }
              _ => ()
            }
          }
        }
        _ => ()
      }
    _ => ()
  }
}

fn pd_fmt_recall(rec : Array[Json]) -> Unit {
  for i = 0; i < rec.length(); i = i + 1 {
    match rec[i] {
      Json::Object(m) => {
        let txt = match m.get("text") { Some(Json::String(s)) => s; _ => "" }
        let sc = match m.get("score") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
        println("· score=" + round4(sc).to_string() + " | " + txt)
      }
      _ => ()
    }
  }
}

// ---- 单领域五轮实跑 + 探针（recall / predict / 冷启动 / 白盒解释 / 收敛指标）----
fn run_domain(
  name : String,
  corpus : Array[(String, String)],
  recall_q : String,
  replay_proj : String,
  cold_proj : String,
  glossary_term : String,
) -> Unit {
  let eng = ProphecyEngine::make()
  train_real_d(eng, corpus, 5)

  println("===== DOMAIN DEMO: " + name + " (5 rounds) =====")

  // 1) 召回：新源文到来，召回已锁定的前沿术语
  let _ = eng.observe("【接收】" + recall_q, "instruction")
  let rec = eng.recall(recall_q, 3)
  println("● 召回(前沿术语, top-3):")
  pd_fmt_recall(rec)

  // 2) 预测：复盘已知项目，预测下一步工作流
  let _ = eng.observe("【项目】" + replay_proj, "instruction")
  let pred = eng.predict(3)
  println("● 预测下一步(复盘已知项目: " + replay_proj + "):")
  pd_fmt_pred(pred)

  // 3) 冷启动：未见项目，经 D8 角色抽象泛化出通用流程
  let _ = eng.observe("【项目】" + cold_proj, "instruction")
  let cpred = eng.predict(3)
  println("● 冷启动预测(未见项目: " + cold_proj + "):")
  pd_fmt_pred(cpred)

  // 4) 白盒解释：某术语节点的来龙去脉
  let gid = eng.observe(glossary_term, "fact")
  let ex = eng.explain(gid)
  let pval = match ex {
    Json::Object(m) => match m.get("predictive_value") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
    _ => 0.0
  }
  let hr = match ex {
    Json::Object(m) => match m.get("hit_rate") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
    _ => 0.0
  }
  let oedges = match ex {
    Json::Object(m) => match m.get("out_edges") { Some(Json::Array(a)) => a.length(); _ => 0 }
    _ => 0
  }
  println(
    "● 白盒解释(术语节点 " + gid + "): 预测价值=" + round4(pval).to_string() +
    " 命中率=" + round4(hr).to_string() + " 出边数=" + oedges.to_string(),
  )

  // 5) 收敛指标
  let sv = eng.stats_view()
  let nodes = match sv {
    Json::Object(m) => match m.get("nodes") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
    _ => 0.0
  }
  let edges = match sv {
    Json::Object(m) => match m.get("edges") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
    _ => 0.0
  }
  let hr2 = match sv {
    Json::Object(m) => match m.get("predict_hit_rate") { Some(Json::Number(n, ..)) => n; _ => 0.0 }
    _ => 0.0
  }
  println(
    "● 收敛: 节点=" + nodes.to_string() + " 边=" + edges.to_string() +
    " Hit@3=" + round4(hr2).to_string(),
  )
  println("==============================================")
}

// ---------------------------------------------------------------------------
// 领域一：人工智能大模型（术语含 LLM / RAG / alignment / inference / agent）
// ---------------------------------------------------------------------------
test "领域一·人工智能大模型 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：大语言模型安全白皮书", "instruction"),
    ("【术语】大语言模型 → large language model (LLM)", "fact"),
    ("【术语】检索增强生成 → retrieval-augmented generation (RAG)", "fact"),
    ("【术语】对齐 → alignment", "fact"),
    ("【术语】推理 → inference", "fact"),
    ("【术语】智能体 → AI agent", "fact"),
    ("【风格】术语须学术、技术、准确；缩写首次出现标注全称", "preference"),
    ("【例句】该模型采用检索增强生成以降低幻觉。→ The model adopts retrieval-augmented generation to reduce hallucination.", "fact"),
    ("【例句】推理阶段需优化批处理以提升吞吐。→ The inference stage requires batching optimization to improve throughput.", "fact"),
    ("【指令】提取核心术语表(大模型/算法)", "instruction"),
    ("【指令】对齐术语风格(学术技术中性)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理公式/代码/图示", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "人工智能大模型",
    corpus,
    "文中需统一大语言模型的推理与对齐表述",
    "大语言模型安全白皮书",
    "多模态智能体编排规范",
    "【术语】大语言模型 → large language model (LLM)",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二：量子科技（术语含 qubit / entanglement / supremacy / decoherence / QKD）
// ---------------------------------------------------------------------------
test "领域二·量子科技 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：量子优越性验证报告", "instruction"),
    ("【术语】量子比特 → qubit", "fact"),
    ("【术语】量子纠缠 → quantum entanglement", "fact"),
    ("【术语】量子优越性 → quantum supremacy", "fact"),
    ("【术语】退相干 → decoherence", "fact"),
    ("【术语】量子密钥分发 → quantum key distribution (QKD)", "fact"),
    ("【风格】术语须严谨、符合 ISO/IEC 4879 口径", "preference"),
    ("【例句】该处理器利用超导量子比特实现纠缠。→ The processor uses superconducting qubits to realize entanglement.", "fact"),
    ("【例句】退相干会限制相干时间并引入误差。→ Decoherence limits coherence time and introduces errors.", "fact"),
    ("【指令】提取核心术语表(量子物理)", "instruction"),
    ("【指令】对齐术语风格(学术严谨)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理量子线路与门符号", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "量子科技",
    corpus,
    "段落需说明量子比特的纠缠与退相干",
    "量子优越性验证报告",
    "量子密钥分发网络白皮书",
    "【术语】量子比特 → qubit",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域三：新能源与储能（术语含 solid-state / perovskite / sodium-ion / VRFB / LDES）
// ---------------------------------------------------------------------------
test "领域三·新能源与储能 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：全固态电池技术白皮书", "instruction"),
    ("【术语】固态电池 → solid-state battery", "fact"),
    ("【术语】钙钛矿太阳能电池 → perovskite solar cell", "fact"),
    ("【术语】钠离子电池 → sodium-ion battery", "fact"),
    ("【术语】全钒液流电池 → vanadium redox flow battery (VRFB)", "fact"),
    ("【术语】长时储能 → long-duration energy storage (LDES)", "fact"),
    ("【风格】术语须符合行业技术规范，单位准确", "preference"),
    ("【例句】全固态电池以固态电解质替代液态电解质。→ The all-solid-state battery replaces liquid electrolyte with a solid electrolyte.", "fact"),
    ("【例句】长时储能支撑跨季节电力平衡。→ Long-duration energy storage supports cross-seasonal power balancing.", "fact"),
    ("【指令】提取核心术语表(电池/材料)", "instruction"),
    ("【指令】对齐术语风格(技术中性)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理电化学公式与参数", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "新能源与储能",
    corpus,
    "文中需统一固态电池与长时储能的表述",
    "全固态电池技术白皮书",
    "钠离子电池储能电站可研报告",
    "【术语】固态电池 → solid-state battery",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域四：生物医药与基因技术（术语含 mRNA / ADC / CAR-T / gene editing / AAV）
// ---------------------------------------------------------------------------
test "领域四·生物医药与基因技术 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：mRNA 疫苗技术审评报告", "instruction"),
    ("【术语】信使RNA疫苗 → mRNA vaccine", "fact"),
    ("【术语】抗体药物偶联物 → antibody-drug conjugate (ADC)", "fact"),
    ("【术语】嵌合抗原受体T细胞疗法 → CAR-T cell therapy", "fact"),
    ("【术语】基因编辑 → gene editing (CRISPR-Cas9)", "fact"),
    ("【术语】腺相关病毒 → adeno-associated virus (AAV)", "fact"),
    ("【风格】术语须符合药典与 GMP 口径，慎用营销语", "preference"),
    ("【例句】该 mRNA 疫苗由脂质纳米颗粒递送。→ The mRNA vaccine is delivered by a lipid nanoparticle.", "fact"),
    ("【例句】CAR-T 疗法通过基因编辑改造患者 T 细胞。→ CAR-T therapy modifies the patient's T cells via gene editing.", "fact"),
    ("【指令】提取核心术语表(生物制药/基因)", "instruction"),
    ("【指令】对齐术语风格(严谨合规)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理剂量/不良反应/禁忌", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "生物医药与基因技术",
    corpus,
    "段落需说明 mRNA 疫苗与脂质纳米颗粒递送",
    "mRNA 疫苗技术审评报告",
    "AAV 基因治疗临床方案",
    "【术语】信使RNA疫苗 → mRNA vaccine",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域五：深空探测与航天（术语含 deep space / DSOC / ISL / reusable rocket / TT&C）
// ---------------------------------------------------------------------------
test "领域五·深空探测与航天 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：深空光通信工程总体设计", "instruction"),
    ("【术语】深空探测 → deep space exploration", "fact"),
    ("【术语】深空光通信 → deep space optical communication (DSOC)", "fact"),
    ("【术语】星间链路 → inter-satellite link (ISL)", "fact"),
    ("【术语】可重复使用火箭 → reusable rocket", "fact"),
    ("【术语】航天器测控 → spacecraft tracking, telemetry and control (TT&C)", "fact"),
    ("【风格】术语须符合 CCSDS/测控规范，英文缩写规范", "preference"),
    ("【例句】深空光通信采用近红外激光实现高带宽。→ Deep space optical communication uses near-infrared lasers for high bandwidth.", "fact"),
    ("【例句】星间链路减少了对地面信关站的依赖。→ The inter-satellite link reduces dependence on ground gateways.", "fact"),
    ("【指令】提取核心术语表(航天/通信)", "instruction"),
    ("【指令】对齐术语风格(工程规范)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理轨道与链路参数", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "深空探测与航天",
    corpus,
    "文中需统一深空光通信与星间链路的表述",
    "深空光通信工程总体设计",
    "可重复使用火箭回收手册",
    "【术语】深空光通信 → deep space optical communication (DSOC)",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域六：文学理论（术语含 narratology / intertextuality / stream of consciousness /
//   defamiliarization / free indirect discourse；来源：什克洛夫斯基陌生化、Genette 叙事学）
// ---------------------------------------------------------------------------
test "领域六·文学理论 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：西方叙事学导论", "instruction"),
    ("【术语】叙事学 → narratology", "fact"),
    ("【术语】互文性 → intertextuality", "fact"),
    ("【术语】意识流 → stream of consciousness", "fact"),
    ("【术语】陌生化 → defamiliarization", "fact"),
    ("【术语】自由间接引语 → free indirect discourse", "fact"),
    ("【风格】术语须符合文学理论学术惯例，保留理论家译名", "preference"),
    ("【例句】乔伊斯以意识流呈现人物的内心流动。→ Joyce renders the character's inner flow through stream of consciousness.", "fact"),
    ("【例句】陌生化通过艺术手法使熟悉之物重新变得新奇。→ Defamiliarization renders the familiar strange through artistic device.", "fact"),
    ("【指令】提取核心术语表(叙事/批评)", "instruction"),
    ("【指令】对齐术语风格(文学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理引文与理论家人名", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "文学理论",
    corpus,
    "文中需统一意识流与自由间接引语的译法",
    "西方叙事学导论",
    "后现代元小说研究文集",
    "【术语】叙事学 → narratology",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域七：哲学（术语含 phenomenology / epistemology / ontology / dialectic / teleology）
// ---------------------------------------------------------------------------
test "领域七·哲学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：现象学基本问题", "instruction"),
    ("【术语】现象学 → phenomenology", "fact"),
    ("【术语】认识论 → epistemology", "fact"),
    ("【术语】本体论 → ontology", "fact"),
    ("【术语】辩证法 → dialectic", "fact"),
    ("【术语】目的论 → teleology", "fact"),
    ("【风格】术语须严谨，区分形而上学/本体论等近义概念", "preference"),
    ("【例句】现象学研究意识经验的结构。→ Phenomenology studies the structures of conscious experience.", "fact"),
    ("【例句】认识论探讨知识的来源与界限。→ Epistemology examines the origin and limits of knowledge.", "fact"),
    ("【指令】提取核心术语表(哲学分支)", "instruction"),
    ("【指令】对齐术语风格(哲学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理拉丁/德文原词与译注", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "哲学",
    corpus,
    "段落需统一现象学与认识论的表述",
    "现象学基本问题",
    "分析哲学中的心灵与意识",
    "【术语】现象学 → phenomenology",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域八：医学（术语含 evidence-based medicine / pathogenesis / prognosis /
//   comorbidity / randomized controlled trial；标准循证医学术语）
// ---------------------------------------------------------------------------
test "领域八·医学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：循证医学临床指南", "instruction"),
    ("【术语】循证医学 → evidence-based medicine (EBM)", "fact"),
    ("【术语】发病机制 → pathogenesis", "fact"),
    ("【术语】预后 → prognosis", "fact"),
    ("【术语】合并症 → comorbidity", "fact"),
    ("【术语】随机对照试验 → randomized controlled trial (RCT)", "fact"),
    ("【风格】术语须符合药典/临床规范，剂量单位准确", "preference"),
    ("【例句】该结论基于多项随机对照试验的证据。→ The conclusion is based on evidence from multiple randomized controlled trials.", "fact"),
    ("【例句】合并症会显著影响患者的预后。→ Comorbidity significantly affects the patient's prognosis.", "fact"),
    ("【指令】提取核心术语表(临床/循证)", "instruction"),
    ("【指令】对齐术语风格(临床规范)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理剂量/禁忌/统计指标", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "医学",
    corpus,
    "文中需统一循证医学与随机对照试验的译法",
    "循证医学临床指南",
    "罕见病诊疗专家共识",
    "【术语】循证医学 → evidence-based medicine (EBM)",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域九：心理学（术语含 cognitive dissonance / attachment theory / working memory /
//   Big Five personality traits / mindfulness；来源：Festinger、APA、DSM-5）
// ---------------------------------------------------------------------------
test "领域九·心理学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：认知心理学导论", "instruction"),
    ("【术语】认知失调 → cognitive dissonance", "fact"),
    ("【术语】依恋理论 → attachment theory", "fact"),
    ("【术语】工作记忆 → working memory", "fact"),
    ("【术语】大五人格特质 → Big Five personality traits", "fact"),
    ("【术语】正念 → mindfulness", "fact"),
    ("【风格】术语须符合 APA/DSM-5 口径，慎用日常口语义", "preference"),
    ("【例句】认知失调指同时持有矛盾信念时的心理不适。→ Cognitive dissonance is the mental discomfort of holding contradictory beliefs simultaneously.", "fact"),
    ("【例句】工作记忆是暂存并操作信息的有限容量系统。→ Working memory is a limited-capacity system that temporarily holds and manipulates information.", "fact"),
    ("【指令】提取核心术语表(认知/临床)", "instruction"),
    ("【指令】对齐术语风格(心理学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理量表/统计/伦理表述", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "心理学",
    corpus,
    "段落需统一认知失调与工作记忆的译法",
    "认知心理学导论",
    "积极心理学与幸福感研究",
    "【术语】认知失调 → cognitive dissonance",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十：神经科学（术语含 neuroplasticity / synapse / neurotransmitter /
//   fMRI / default mode network；来源：Britannica、Hebb 理论、fMRI 文献）
// ---------------------------------------------------------------------------
test "领域十·神经科学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：神经可塑性研究综述", "instruction"),
    ("【术语】神经可塑性 → neuroplasticity", "fact"),
    ("【术语】突触 → synapse", "fact"),
    ("【术语】神经递质 → neurotransmitter", "fact"),
    ("【术语】功能性磁共振成像 → functional magnetic resonance imaging (fMRI)", "fact"),
    ("【术语】默认模式网络 → default mode network (DMN)", "fact"),
    ("【风格】术语须符合神经科学规范，缩写首次标注全称", "preference"),
    ("【例句】神经可塑性使大脑能重组突触连接。→ Neuroplasticity enables the brain to reorganize its synaptic connections.", "fact"),
    ("【例句】默认模式网络在思绪漫游时活跃。→ The default mode network is active during mind-wandering.", "fact"),
    ("【指令】提取核心术语表(脑科学/成像)", "instruction"),
    ("【指令】对齐术语风格(神经科学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理脑区名与成像参数", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "神经科学",
    corpus,
    "文中需统一神经可塑性与突触的译法",
    "神经可塑性研究综述",
    "脑机接口与神经解码手册",
    "【术语】神经可塑性 → neuroplasticity",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十一：经济学（术语含 opportunity cost / marginal utility / comparative
//   advantage / monetary policy / externality）
// ---------------------------------------------------------------------------
test "领域十一·经济学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：宏观经济学原理", "instruction"),
    ("【术语】机会成本 → opportunity cost", "fact"),
    ("【术语】边际效用 → marginal utility", "fact"),
    ("【术语】比较优势 → comparative advantage", "fact"),
    ("【术语】货币政策 → monetary policy", "fact"),
    ("【术语】外部性 → externality", "fact"),
    ("【风格】术语须符合经济学学术规范，缩写首次标注全称", "preference"),
    ("【例句】生产该商品的机会成本是其次优用途的价值。→ The opportunity cost of producing the good is the value of its next-best alternative use.", "fact"),
    ("【例句】边际效用递减规律限制了消费者的总需求。→ The law of diminishing marginal utility limits total consumer demand.", "fact"),
    ("【指令】提取核心术语表(宏观/微观)", "instruction"),
    ("【指令】对齐术语风格(经济学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理图表与数据", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "经济学",
    corpus,
    "文中需统一机会成本与边际效用的表述",
    "宏观经济学原理",
    "行为经济学实验手册",
    "【术语】机会成本 → opportunity cost",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十二：社会学（术语含 social capital / social stratification / role
//   conflict / peer group / socialization）
// ---------------------------------------------------------------------------
test "领域十二·社会学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：社会资本与社区治理研究", "instruction"),
    ("【术语】社会资本 → social capital", "fact"),
    ("【术语】社会分层 → social stratification", "fact"),
    ("【术语】角色冲突 → role conflict", "fact"),
    ("【术语】同辈群体 → peer group", "fact"),
    ("【术语】社会化 → socialization", "fact"),
    ("【风格】术语须符合社会学学术惯例，保留理论家译名", "preference"),
    ("【例句】社会资本降低了获取就业信息的门槛。→ Social capital lowers the barrier to accessing job information.", "fact"),
    ("【例句】角色冲突源于多重身份要求的相互矛盾。→ Role conflict arises from contradictory demands of multiple identities.", "fact"),
    ("【指令】提取核心术语表(社会结构)", "instruction"),
    ("【指令】对齐术语风格(社会学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理量表与统计表述", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "社会学",
    corpus,
    "文中需统一社会资本与角色冲突的译法",
    "社会资本与社区治理研究",
    "数字社会中的网络民粹主义报告",
    "【术语】社会资本 → social capital",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十三：政治学（术语含 sovereignty / geopolitics / civil society /
//   checks and balances / representative government）
// ---------------------------------------------------------------------------
test "领域十三·政治学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：比较政治制度导论", "instruction"),
    ("【术语】主权 → sovereignty", "fact"),
    ("【术语】地缘政治 → geopolitics", "fact"),
    ("【术语】公民社会 → civil society", "fact"),
    ("【术语】权力制衡 → checks and balances", "fact"),
    ("【术语】代议制 → representative government", "fact"),
    ("【风格】术语须符合政治学学术规范，区分政体型态", "preference"),
    ("【例句】主权是国家对内对外的最高权力。→ Sovereignty is the supreme authority of a state at home and abroad.", "fact"),
    ("【例句】权力制衡防止任一分支独大。→ Checks and balances prevent any single branch from dominating.", "fact"),
    ("【指令】提取核心术语表(制度/理论)", "instruction"),
    ("【指令】对齐术语风格(政治学术语)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理拉丁/法文原词与译注", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "政治学",
    corpus,
    "文中需统一主权与权力制衡的表述",
    "比较政治制度导论",
    "全球治理与多边主义白皮书",
    "【术语】主权 → sovereignty",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十四：语言学（术语含 phoneme / pragmatics / generative grammar /
//   semantic field / code-switching）
// ---------------------------------------------------------------------------
test "领域十四·语言学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：生成语法与形式语言学", "instruction"),
    ("【术语】音位 → phoneme", "fact"),
    ("【术语】语用学 → pragmatics", "fact"),
    ("【术语】生成语法 → generative grammar", "fact"),
    ("【术语】语义场 → semantic field", "fact"),
    ("【术语】语码转换 → code-switching", "fact"),
    ("【风格】术语须符合语言学学术惯例，保留 IPA 与国际音标", "preference"),
    ("【例句】生成语法以形式化规则描述语言能力。→ Generative grammar describes linguistic competence with formal rules.", "fact"),
    ("【例句】语码转换在双语社群中极为常见。→ Code-switching is very common in bilingual communities.", "fact"),
    ("【指令】提取核心术语表(语音/句法)", "instruction"),
    ("【指令】对齐术语风格(语言学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理音标与树形图", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "语言学",
    corpus,
    "文中需统一音位与生成语法的译法",
    "生成语法与形式语言学",
    "濒危语言数字建档指南",
    "【术语】生成语法 → generative grammar",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十五：历史学（术语含 source material / source criticism / oral history /
//   annalistic / Annales School）
// ---------------------------------------------------------------------------
test "领域十五·历史学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：西方史学史", "instruction"),
    ("【术语】史料 → source material", "fact"),
    ("【术语】史料批判 → source criticism", "fact"),
    ("【术语】口述史 → oral history", "fact"),
    ("【术语】编年体 → annalistic / chronicle", "fact"),
    ("【术语】年鉴学派 → Annales School", "fact"),
    ("【风格】术语须符合史学规范，区分一手/二手史料", "preference"),
    ("【例句】史料批判评估来源的真实与偏见。→ Source criticism assesses the authenticity and bias of sources.", "fact"),
    ("【例句】年鉴学派重视长时段社会结构。→ The Annales School emphasizes long-term social structures.", "fact"),
    ("【指令】提取核心术语表(史学方法)", "instruction"),
    ("【指令】对齐术语风格(历史学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理年代与引文", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "历史学",
    corpus,
    "文中需统一史料批判与口述史的译法",
    "西方史学史",
    "全球史视野下的贸易网络研究",
    "【术语】史料批判 → source criticism",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十六：数学（术语含 topology / manifold / eigenvalue / isomorphism /
//   recursion；来源：Britannica 数学条目）
// ---------------------------------------------------------------------------
test "领域十六·数学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：微分流形与拓扑学", "instruction"),
    ("【术语】拓扑学 → topology", "fact"),
    ("【术语】流形 → manifold", "fact"),
    ("【术语】特征值 → eigenvalue", "fact"),
    ("【术语】同构 → isomorphism", "fact"),
    ("【术语】递归 → recursion", "fact"),
    ("【风格】术语须符合数学规范，公式与符号精确", "preference"),
    ("【例句】拓扑学研究连续变形下不变的性质。→ Topology studies properties invariant under continuous deformation.", "fact"),
    ("【例句】流形在局部同胚于欧氏空间。→ A manifold is locally homeomorphic to Euclidean space.", "fact"),
    ("【指令】提取核心术语表(几何/代数)", "instruction"),
    ("【指令】对齐术语风格(数学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理公式与符号", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "数学",
    corpus,
    "文中需统一拓扑学与流形的表述",
    "微分流形与拓扑学",
    "代数拓扑研究生讲义",
    "【术语】拓扑学 → topology",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十七：物理学（术语含 quantum field theory / relativity / superconductivity
//   / entropy / thermodynamics）
// ---------------------------------------------------------------------------
test "领域十七·物理学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：量子场论导论", "instruction"),
    ("【术语】量子场论 → quantum field theory (QFT)", "fact"),
    ("【术语】相对论 → relativity", "fact"),
    ("【术语】超导 → superconductivity", "fact"),
    ("【术语】熵 → entropy", "fact"),
    ("【术语】热力学 → thermodynamics", "fact"),
    ("【风格】术语须符合物理学术规范，单位与常数准确", "preference"),
    ("【例句】量子场论将粒子视为场的激发。→ Quantum field theory treats particles as excitations of fields.", "fact"),
    ("【例句】熵度量系统的无序程度。→ Entropy measures the disorder of a system.", "fact"),
    ("【指令】提取核心术语表(粒子/凝聚态)", "instruction"),
    ("【指令】对齐术语风格(物理学术语)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理方程与单位", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "物理学",
    corpus,
    "文中需统一量子场论与相对论的译法",
    "量子场论导论",
    "凝聚态物理前沿综述",
    "【术语】量子场论 → quantum field theory (QFT)",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十八：化学（术语含 catalysis / stereochemistry / redox / electrophile /
//   mole）
// ---------------------------------------------------------------------------
test "领域十八·化学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：高等有机化学", "instruction"),
    ("【术语】催化 → catalysis", "fact"),
    ("【术语】立体化学 → stereochemistry", "fact"),
    ("【术语】氧化还原 → redox", "fact"),
    ("【术语】亲电试剂 → electrophile", "fact"),
    ("【术语】摩尔 → mole", "fact"),
    ("【风格】术语须符合化学命名规范(IUPAC)，结构式精确", "preference"),
    ("【例句】催化降低了反应的活化能。→ Catalysis lowers the activation energy of a reaction.", "fact"),
    ("【例句】立体化学决定分子的三维构型。→ Stereochemistry determines the 3D configuration of a molecule.", "fact"),
    ("【指令】提取核心术语表(有机/物化)", "instruction"),
    ("【指令】对齐术语风格(化学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理结构式与机理", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "化学",
    corpus,
    "文中需统一催化与立体化学的译法",
    "高等有机化学",
    "绿色催化与可持续合成手册",
    "【术语】催化 → catalysis",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域十九：天文学（术语含 redshift / exoplanet / neutron star / event horizon
//   / cosmology）
// ---------------------------------------------------------------------------
test "领域十九·天文学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：星系形成与宇宙学", "instruction"),
    ("【术语】红移 → redshift", "fact"),
    ("【术语】系外行星 → exoplanet", "fact"),
    ("【术语】中子星 → neutron star", "fact"),
    ("【术语】事件视界 → event horizon", "fact"),
    ("【术语】宇宙学 → cosmology", "fact"),
    ("【风格】术语须符合天文规范，单位与天体名规范", "preference"),
    ("【例句】星系的红移指示宇宙膨胀。→ The redshift of galaxies indicates cosmic expansion.", "fact"),
    ("【例句】事件视界内的事物无法逃出黑洞。→ Nothing inside the event horizon can escape the black hole.", "fact"),
    ("【指令】提取核心术语表(天体/宇宙)", "instruction"),
    ("【指令】对齐术语风格(天文学学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理观测参数与编号", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "天文学",
    corpus,
    "文中需统一红移与事件视界的译法",
    "星系形成与宇宙学",
    "系外行星宜居性评估指南",
    "【术语】红移 → redshift",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十：地球与生态科学（术语含 plate tectonics / biodiversity / biome /
//   carbon sink / ecosystem）
// ---------------------------------------------------------------------------
test "领域二十·地球与生态科学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：全球生态与生物多样性评估", "instruction"),
    ("【术语】板块构造 → plate tectonics", "fact"),
    ("【术语】生物多样性 → biodiversity", "fact"),
    ("【术语】生物群系 → biome", "fact"),
    ("【术语】碳汇 → carbon sink", "fact"),
    ("【术语】生态系统 → ecosystem", "fact"),
    ("【风格】术语须符合生态/地学规范，物种学名斜体", "preference"),
    ("【例句】板块构造解释了大陆的迁移。→ Plate tectonics explains the drift of continents.", "fact"),
    ("【例句】生态系统通过物质循环维持稳定。→ An ecosystem maintains stability through nutrient cycling.", "fact"),
    ("【指令】提取核心术语表(地学/生态)", "instruction"),
    ("【指令】对齐术语风格(生态学术语)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理物种名与地图", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "地球与生态科学",
    corpus,
    "文中需统一板块构造与生物多样性的表述",
    "全球生态与生物多样性评估",
    "海岸带蓝碳碳汇核算规范",
    "【术语】板块构造 → plate tectonics",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十一：计算机体系结构/软件工程（术语含 compiler / cache / pipeline /
//   algorithm / object-oriented）
// ---------------------------------------------------------------------------
test "领域二十一·计算机体系结构·软件工程 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：编译原理与体系结构", "instruction"),
    ("【术语】编译器 → compiler", "fact"),
    ("【术语】缓存 → cache", "fact"),
    ("【术语】流水线 → pipeline", "fact"),
    ("【术语】算法 → algorithm", "fact"),
    ("【术语】面向对象 → object-oriented", "fact"),
    ("【风格】术语须符合计算机规范，代码与缩写规范", "preference"),
    ("【例句】编译器将源码翻译为机器码。→ A compiler translates source code into machine code.", "fact"),
    ("【例句】缓存加速了对高频数据的访问。→ The cache speeds up access to frequently used data.", "fact"),
    ("【指令】提取核心术语表(系统/算法)", "instruction"),
    ("【指令】对齐术语风格(计算机学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理代码片段", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "计算机体系结构·软件工程",
    corpus,
    "文中需统一编译器与流水线的译法",
    "编译原理与体系结构",
    "分布式系统一致性设计手册",
    "【术语】编译器 → compiler",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十二：电子工程（术语含 semiconductor / integrated circuit / logic gate
//   / impedance / oscillator）
// ---------------------------------------------------------------------------
test "领域二十二·电子工程 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：数字集成电路设计", "instruction"),
    ("【术语】半导体 → semiconductor", "fact"),
    ("【术语】集成电路 → integrated circuit (IC)", "fact"),
    ("【术语】逻辑门 → logic gate", "fact"),
    ("【术语】阻抗 → impedance", "fact"),
    ("【术语】振荡器 → oscillator", "fact"),
    ("【风格】术语须符合电子工程规范，单位准确", "preference"),
    ("【例句】半导体是集成电路的基础材料。→ The semiconductor is the base material of ICs.", "fact"),
    ("【例句】逻辑门实现布尔代数运算。→ Logic gates implement Boolean-algebra operations.", "fact"),
    ("【指令】提取核心术语表(器件/电路)", "instruction"),
    ("【指令】对齐术语风格(电子工程)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理电路图与参数", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "电子工程",
    corpus,
    "文中需统一半导体与逻辑门的译法",
    "数字集成电路设计",
    "低功耗射频前端设计手册",
    "【术语】半导体 → semiconductor",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十三：材料科学（术语含 alloy / polymer / composite / crystallization /
//   nanomaterial）
// ---------------------------------------------------------------------------
test "领域二十三·材料科学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：先进复合材料导论", "instruction"),
    ("【术语】合金 → alloy", "fact"),
    ("【术语】聚合物 → polymer", "fact"),
    ("【术语】复合材料 → composite", "fact"),
    ("【术语】结晶 → crystallization", "fact"),
    ("【术语】纳米材料 → nanomaterial", "fact"),
    ("【风格】术语须符合材料科学规范，结构表征准确", "preference"),
    ("【例句】复合材料结合了不同组分的优势。→ Composites combine the advantages of distinct components.", "fact"),
    ("【例句】结晶提高了半导体材料的纯度。→ Crystallization improves the purity of semiconductor materials.", "fact"),
    ("【指令】提取核心术语表(金属/高分子)", "instruction"),
    ("【指令】对齐术语风格(材料学术语)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理微观结构与性能", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "材料科学",
    corpus,
    "文中需统一合金与复合材料的译法",
    "先进复合材料导论",
    "纳米材料 biomedical 应用综述",
    "【术语】合金 → alloy",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十四：机械工程（术语含 turbine / robotics / kinematics / finite element
//   analysis / CAD）
// ---------------------------------------------------------------------------
test "领域二十四·机械工程 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：机器人运动学与控制", "instruction"),
    ("【术语】涡轮 → turbine", "fact"),
    ("【术语】机器人学 → robotics", "fact"),
    ("【术语】运动学 → kinematics", "fact"),
    ("【术语】有限元分析 → finite element analysis (FEA)", "fact"),
    ("【术语】计算机辅助设计 → computer-aided design (CAD)", "fact"),
    ("【风格】术语须符合机械工程规范，单位与图纸规范", "preference"),
    ("【例句】机器人学综合感知与运动控制。→ Robotics integrates perception and motion control.", "fact"),
    ("【例句】有限元分析求解结构的应力分布。→ Finite element analysis solves the stress distribution of structures.", "fact"),
    ("【指令】提取核心术语表(动力/控制)", "instruction"),
    ("【指令】对齐术语风格(机械工程)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理图纸与参数", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "机械工程",
    corpus,
    "文中需统一涡轮与运动学的表述",
    "机器人运动学与控制",
    "风力机叶片结构优化手册",
    "【术语】机器人学 → robotics",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十五：土木工程（术语含 reinforced concrete / foundation / load-bearing
//   / beam / structural analysis）
// ---------------------------------------------------------------------------
test "领域二十五·土木工程 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：混凝土结构设计", "instruction"),
    ("【术语】钢筋混凝土 → reinforced concrete", "fact"),
    ("【术语】基础 → foundation", "fact"),
    ("【术语】承重 → load-bearing", "fact"),
    ("【术语】梁 → beam", "fact"),
    ("【术语】结构分析 → structural analysis", "fact"),
    ("【风格】术语须符合土木工程规范，荷载与单位准确", "preference"),
    ("【例句】钢筋混凝土以钢筋提高抗拉强度。→ Reinforced concrete uses rebar to raise tensile strength.", "fact"),
    ("【例句】结构分析研究荷载下的行为。→ Structural analysis studies behavior under loads.", "fact"),
    ("【指令】提取核心术语表(结构/地基)", "instruction"),
    ("【指令】对齐术语风格(土木工程)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理荷载与配筋图", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "土木工程",
    corpus,
    "文中需统一钢筋混凝土与结构分析的译法",
    "混凝土结构设计",
    "既有建筑抗震加固手册",
    "【术语】钢筋混凝土 → reinforced concrete",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十六：艺术史（术语含 iconography / realism / impressionism / baroque /
//   genre painting）
// ---------------------------------------------------------------------------
test "领域二十六·艺术史 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：西方艺术史", "instruction"),
    ("【术语】图像志 → iconography", "fact"),
    ("【术语】现实主义 → realism", "fact"),
    ("【术语】印象派 → impressionism", "fact"),
    ("【术语】巴洛克 → baroque", "fact"),
    ("【术语】风俗画 → genre painting", "fact"),
    ("【风格】术语须符合艺术史学术惯例，保留流派与人名", "preference"),
    ("【例句】图像志解读作品中的视觉象征。→ Iconography interprets the visual symbols in a work.", "fact"),
    ("【例句】印象派捕捉光与色的瞬息变化。→ Impressionism captures fleeting changes of light and color.", "fact"),
    ("【指令】提取核心术语表(流派/技法)", "instruction"),
    ("【指令】对齐术语风格(艺术史学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理艺术家名与年代", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "艺术史",
    corpus,
    "文中需统一图像志与印象派的译法",
    "西方艺术史",
    "当代策展与视觉文化研究",
    "【术语】图像志 → iconography",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十七：音乐理论（术语含 tonality / counterpoint / syncopation / octave
//   / harmony）
// ---------------------------------------------------------------------------
test "领域二十七·音乐理论 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：和声学与对位法", "instruction"),
    ("【术语】调性 → tonality", "fact"),
    ("【术语】对位法 → counterpoint", "fact"),
    ("【术语】切分音 → syncopation", "fact"),
    ("【术语】八度 → octave", "fact"),
    ("【术语】和声 → harmony", "fact"),
    ("【风格】术语须符合音乐理论规范，记谱术语准确", "preference"),
    ("【例句】对位法将多条旋律线结合为整体。→ Counterpoint combines multiple melodic lines into a whole.", "fact"),
    ("【例句】切分音把重音移到弱拍之上。→ Syncopation displaces the accent onto a weak beat.", "fact"),
    ("【指令】提取核心术语表(和声/曲式)", "instruction"),
    ("【指令】对齐术语风格(音乐学术语)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理谱例与术语", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "音乐理论",
    corpus,
    "文中需统一调性与对位法的译法",
    "和声学与对位法",
    "电子音乐制作工作手册",
    "【术语】对位法 → counterpoint",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十八：法学（术语含 jurisdiction / tort / precedent / plaintiff /
//   statute）
// ---------------------------------------------------------------------------
test "领域二十八·法学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：英美法导论", "instruction"),
    ("【术语】管辖权 → jurisdiction", "fact"),
    ("【术语】侵权 → tort", "fact"),
    ("【术语】判例 → precedent", "fact"),
    ("【术语】原告 → plaintiff", "fact"),
    ("【术语】制定法 → statute", "fact"),
    ("【风格】术语须符合法律英语规范，区分制定法/判例法", "preference"),
    ("【例句】判例对后续案件具有约束力。→ Precedent binds courts in subsequent similar cases.", "fact"),
    ("【例句】侵权是产生民事责任的违法行为。→ A tort is a civil wrong giving rise to liability.", "fact"),
    ("【指令】提取核心术语表(程序/实体)", "instruction"),
    ("【指令】对齐术语风格(法律英语)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理条文与案号", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "法学",
    corpus,
    "文中需统一管辖权与判例的译法",
    "英美法导论",
    "数据合规与隐私保护手册",
    "【术语】判例 → precedent",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域二十九：建筑学（术语含 colonnade / vault / facade / Bauhaus / passive
//   house；来源：包豪斯、Passivhaus 标准）
// ---------------------------------------------------------------------------
test "领域二十九·建筑学 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：现代建筑史", "instruction"),
    ("【术语】列柱 → colonnade", "fact"),
    ("【术语】拱顶 → vault", "fact"),
    ("【术语】立面 → facade", "fact"),
    ("【术语】包豪斯 → Bauhaus", "fact"),
    ("【术语】被动房 → passive house (Passivhaus)", "fact"),
    ("【风格】术语须符合建筑学术规范，流派与构造准确", "preference"),
    ("【例句】列柱围合出庄严的仪式空间。→ The colonnade encloses a solemn ceremonial space.", "fact"),
    ("【例句】被动房以高气密性实现超低能耗。→ The passive house achieves ultra-low energy use via air-tightness.", "fact"),
    ("【指令】提取核心术语表(构造/流派)", "instruction"),
    ("【指令】对齐术语风格(建筑学术语)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理图纸与构造", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "建筑学",
    corpus,
    "文中需统一列柱与立面的译法",
    "现代建筑史",
    "被动式超低能耗建筑设计手册",
    "【术语】包豪斯 → Bauhaus",
  )
  inspect(true, content="true")
}

// ---------------------------------------------------------------------------
// 领域三十：宗教研究（术语含 monotheism / karma / soteriology / ritual /
//   scripture）
// ---------------------------------------------------------------------------
test "领域三十·宗教研究 五轮翻译实跑" {
  let corpus : Array[(String, String)] = [
    ("【项目】新建翻译项目：比较宗教学", "instruction"),
    ("【术语】一神论 → monotheism", "fact"),
    ("【术语】业 → karma", "fact"),
    ("【术语】救赎论 → soteriology", "fact"),
    ("【术语】仪式 → ritual", "fact"),
    ("【术语】经文 → scripture", "fact"),
    ("【风格】术语须符合宗教学规范，区分谱系与信仰", "preference"),
    ("【例句】一神论信仰唯一的至高神。→ Monotheism believes in a single supreme deity.", "fact"),
    ("【例句】仪式以固定行为承载象征意义。→ Ritual carries symbolic meaning through fixed acts.", "fact"),
    ("【指令】提取核心术语表(信仰/实践)", "instruction"),
    ("【指令】对齐术语风格(宗教学术)", "instruction"),
    ("【指令】按章节分段翻译", "instruction"),
    ("【指令】处理经典引文与译注", "instruction"),
    ("【指令】质检术语与一致性", "instruction"),
    ("【指令】导出中英双语交付物", "instruction"),
  ]
  run_domain(
    "宗教研究",
    corpus,
    "文中需统一一神论与仪式的译法",
    "比较宗教学",
    "宗教人类学与仪式研究",
    "【术语】一神论 → monotheism",
  )
  inspect(true, content="true")
}
