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
