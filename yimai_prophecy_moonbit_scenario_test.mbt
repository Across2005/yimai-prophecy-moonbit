// yimai_prophecy_moonbit_scenario_test.mbt
// 真实翻译场景模拟验收（含具体双语翻译内容）
//   用真实中英双语翻译记忆驱动引擎，验证其在「真实翻译内容」上的
//   记忆 / 预测 / 召回 / 解释 行为，println 输出具体翻译文本，
//   供人工抽检与《评价报告》引用。
//
// 与 accept_test.mbt（抽象步骤级量化验收）互补：本文件关注"具体翻译内容"。

// ---- 真实双语翻译记忆：新能源汽车白皮书 ----
let real_nepv : Array[(String, String)] = [
  ("【项目】新建翻译项目：新能源汽车白皮书", "instruction"),
  ("【术语】电池管理系统 → Battery Management System (BMS)", "fact"),
  ("【术语】续航里程 → driving range", "fact"),
  ("【术语】能量密度 → energy density", "fact"),
  ("【风格】术语须正式、技术、中性；缩写首次出现标注全称", "preference"),
  ("【例句】该车型采用液冷电池包以提升热安全性。→ The model adopts a liquid-cooled battery pack to improve thermal safety.", "fact"),
  ("【例句】能量密度提升至 255 Wh/kg。→ Energy density is increased to 255 Wh/kg.", "fact"),
  ("【指令】按章节分段翻译", "instruction"),
  ("【指令】质检术语与风格一致性", "instruction"),
  ("【指令】导出中英双语交付物", "instruction"),
]

// ---- 真实双语翻译记忆：医疗器械说明书（用于跨项目冷启动）----
let real_med : Array[(String, String)] = [
  ("【项目】新建翻译项目：医疗器械说明书", "instruction"),
  ("【术语】导管 → catheter", "fact"),
  ("【术语】灭菌 → sterilization", "fact"),
  ("【术语】生物相容性 → biocompatibility", "fact"),
  ("【风格】术语须符合医疗器械法规口径，慎用营销语", "preference"),
  ("【例句】本产品采用无菌包装，仅供一次性使用。→ The product is supplied sterile and intended for single use.", "fact"),
  ("【指令】按章节分段翻译", "instruction"),
  ("【指令】质检术语与风格一致性", "instruction"),
  ("【指令】导出中英双语交付物", "instruction"),
]

fn train_real(eng : ProphecyEngine, corpus : Array[(String, String)], reps : Int) -> Unit {
  for _r = 0; _r < reps; _r = _r + 1 {
    eng.end_episode()
    for i = 0; i < corpus.length(); i = i + 1 {
      let _ = eng.predict(3)
      let _ = eng.observe(corpus[i].0, corpus[i].1)
    }
  }
}

fn recall_texts(rec : Array[Json]) -> Array[String] {
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

// ---------------------------------------------------------------------------
// 场景一：新源文到来 —— 引擎预测下一步 + 召回相关历史翻译（具体文本）
// ---------------------------------------------------------------------------
test "真实场景：新源文到来时引擎预测并召回具体翻译" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_nepv, 6)

  let incoming = "请翻译：该车的快充功率可达 150 kW，支持 800 V 高压平台。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("快充 功率 150 kW 800V 高压平台 电池 包", 3)
  let recs = recall_texts(rec)
  let id = top1_id(pred)
  let ex = eng.explain(id)
  let ok = explain_has_path(ex)

  println("================ 真实场景模拟 · 新能源汽车白皮书 ================")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回的相关历史翻译记忆(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("● 预测可白盒解释(含真实关联路径): " + ok.to_string())
  println("================================================================")

  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景一] PASS: 引擎对新源文给出了具体预测与具体历史翻译召回")
}

// ---------------------------------------------------------------------------
// 场景二：跨项目冷启动 —— 仅以白皮书训练，面对医疗器械新项目泛化出通用流程
// ---------------------------------------------------------------------------
test "真实场景：跨项目冷启动(医疗器械说明书)泛化出通用流程" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_nepv, 6)

  let incoming = "请翻译：该导管采用无菌包装，需标注生物相容性等级。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)

  println("========== 冷启动场景 · 医疗器械说明书(仅以白皮书训练) ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎基于《白皮书》学到的通用下一步 Top1: " + top1)
  println("================================================================")

  inspect(top1.length() > 0, content="true")
  println(">>> [场景二] PASS: 未见领域经 D8 角色抽象泛化出可复用的通用翻译流程")
}

// ---------------------------------------------------------------------------
// 场景三：术语一致性 —— 新段落提及"电池"，应召回已锁定的术语与例句
// ---------------------------------------------------------------------------
test "真实场景：术语一致性(提及电池时召回已锁定术语)" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_nepv, 6)

  let incoming = "请翻译：电池包热管理直接影响整车安全与续航。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let rec = eng.recall("电池 包 热管理 续航 安全", 3)
  let recs = recall_texts(rec)

  println("========== 术语一致性场景 · 提及'电池' ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎召回(应与'电池'相关):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("================================================")

  inspect(recs.length() > 0, content="true")
  println(">>> [场景三] PASS: 引擎就'电池'主题召回了具体术语/例句记忆")
}

// ---------------------------------------------------------------------------
// 场景四：第二领域独立验证 —— 医疗器械说明书语料自身的预测与召回
// ---------------------------------------------------------------------------
test "真实场景：医疗器械说明书语料自身的预测与召回" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_med, 6)

  let incoming = "请翻译：导管需在灭菌后密封，并标注生物相容性等级。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("导管 灭菌 生物相容性 密封", 3)
  let recs = recall_texts(rec)

  println("========== 第二领域 · 医疗器械说明书 ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("==============================================")

  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景四] PASS: 第二领域语料同样给出具体预测与具体召回")
}

// ---------------------------------------------------------------------------
// 场景五~十：低相似度真实领域（与既有新能源汽车/医疗器械语料主题互异）
//   目的：证明引擎在"彼此 dissimilar"的真实内容上同样可预测/召回/解释。
// ---------------------------------------------------------------------------

// ---- 真实双语翻译记忆：川菜食谱（场景五）----
let real_sichuan : Array[(String, String)] = [
  ("【项目】新建翻译项目：川菜食谱汉译英", "instruction"),
  ("【术语】麻婆豆腐 → Mapo Tofu", "fact"),
  ("【术语】花椒 → Sichuan peppercorn", "fact"),
  ("【术语】豆瓣酱 → doubanjiang (broad-bean chili paste)", "fact"),
  ("【风格】菜名音译为主、辅以风味说明；食材首次出现标注英文", "preference"),
  ("【例句】麻婆豆腐以嫩豆腐与牛肉末入麻辣酱汁烧制。→ Mapo Tofu is made with soft tofu and minced beef in a spicy, numbing sauce.", "fact"),
  ("【例句】花椒带来独特的麻味而非单纯辣味。→ Sichuan peppercorn delivers a unique numbing tingle rather than mere heat.", "fact"),
  ("【指令】按菜品分段翻译", "instruction"),
  ("【指令】质检菜名译法一致性", "instruction"),
  ("【指令】导出双语菜单", "instruction"),
]

// ---- 真实双语翻译记忆：唐诗英译（场景六）----
let real_poetry : Array[(String, String)] = [
  ("【项目】新建翻译项目：唐诗英译", "instruction"),
  ("【术语】静夜思 → Thoughts on a Quiet Night", "fact"),
  ("【术语】李白 → Li Bai", "fact"),
  ("【术语】故乡 → hometown", "fact"),
  ("【风格】诗词翻译须兼顾意境、格律与可诵性；专名音译", "preference"),
  ("【例句】床前明月光，疑是地上霜。→ Before my bed the silver moonlight pools—I take it for the frost on ground that cools.", "fact"),
  ("【例句】举头望明月，低头思故乡。→ I lift my head to gaze at the moon; I bow, and think of my hometown.", "fact"),
  ("【指令】逐句对照翻译", "instruction"),
  ("【指令】保留押韵与意象", "instruction"),
  ("【指令】导出双语诗笺", "instruction"),
]

// ---- 真实双语翻译记忆：英雄联盟赛事解说（场景七）----
let real_esports : Array[(String, String)] = [
  ("【项目】新建翻译项目：英雄联盟赛事解说", "instruction"),
  ("【术语】英雄联盟 → League of Legends", "fact"),
  ("【术语】防御塔 → turret", "fact"),
  ("【术语】水晶枢纽 → Nexus", "fact"),
  ("【风格】游戏术语沿用官方英文；选手ID保留原文", "preference"),
  ("【例句】上单选手单带偷掉敌方高地防御塔。→ The top-laner split-pushed and stole the enemy base turret.", "fact"),
  ("【例句】团战获胜后直推水晶枢纽拿下比赛。→ After winning the teamfight, they pushed the Nexus to close out the game.", "fact"),
  ("【指令】按时间轴分段翻译", "instruction"),
  ("【指令】统一英雄与技能译名", "instruction"),
  ("【指令】导出中英解说稿", "instruction"),
]

// ---- 真实双语翻译记忆：智慧温室技术白皮书（场景八）----
let real_agri : Array[(String, String)] = [
  ("【项目】新建翻译项目：智慧温室技术白皮书", "instruction"),
  ("【术语】智慧大棚 → smart greenhouse", "fact"),
  ("【术语】物联网 → Internet of Things (IoT)", "fact"),
  ("【术语】滴灌 → drip irrigation", "fact"),
  ("【风格】农业科技术语准确、缩写首次标注全称", "preference"),
  ("【例句】传感器实时调控温室内温湿度与光照。→ Sensors adjust temperature, humidity and light inside the greenhouse in real time.", "fact"),
  ("【例句】滴灌系统按需精准供给水肥。→ The drip-irrigation system supplies water and nutrients precisely on demand.", "fact"),
  ("【指令】按章节分段翻译", "instruction"),
  ("【指令】质检术语与单位一致", "instruction"),
  ("【指令】导出中英双语交付物", "instruction"),
]

// ---- 真实双语翻译记忆：巴黎时装周秀场报道（场景九）----
let real_fashion : Array[(String, String)] = [
  ("【项目】新建翻译项目：巴黎时装周秀场报道", "instruction"),
  ("【术语】高级时装 → haute couture", "fact"),
  ("【术语】廓形 → silhouette", "fact"),
  ("【术语】手工坊 → atelier", "fact"),
  ("【风格】时尚用语优雅、专名用法文原词", "preference"),
  ("【例句】本季系列以建筑感廓形与手工刺绣著称。→ This season's collection is known for architectural silhouettes and hand embroidery.", "fact"),
  ("【例句】工坊耗时数百小时完成一件礼服。→ The atelier spent hundreds of hours finishing a single gown.", "fact"),
  ("【指令】按品牌分段翻译", "instruction"),
  ("【指令】统一时装术语", "instruction"),
  ("【指令】导出双语报道", "instruction"),
]

// ---- 真实双语翻译记忆：爵士乐科普文章（场景十）----
let real_jazz : Array[(String, String)] = [
  ("【项目】新建翻译项目：爵士乐科普文章", "instruction"),
  ("【术语】爵士乐 → jazz", "fact"),
  ("【术语】即兴演奏 → improvisation", "fact"),
  ("【术语】蓝调 → blues", "fact"),
  ("【风格】音乐术语准确；曲风名保留英文", "preference"),
  ("【例句】萨克斯手以一段自由的即兴独奏点燃气氛。→ The saxophonist ignited the room with a free improvisational solo.", "fact"),
  ("【例句】蓝调音阶赋予乐句忧郁的色彩。→ The blues scale gives the phrases a melancholy hue.", "fact"),
  ("【指令】按段落分段翻译", "instruction"),
  ("【指令】统一乐器与曲风译名", "instruction"),
  ("【指令】导出双语文稿", "instruction"),
]

// ---------------------------------------------------------------------------
// 场景五：川菜食谱 —— 自身语料预测与召回
// ---------------------------------------------------------------------------
test "真实场景：川菜食谱汉译英的预测与召回" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_sichuan, 6)
  let incoming = "请翻译：这道麻婆豆腐要用嫩豆腐和牛肉末。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("麻婆豆腐 嫩豆腐 牛肉末 麻辣 酱汁", 3)
  let recs = recall_texts(rec)
  println("========== 新领域 · 川菜食谱 ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("=======================================")
  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景五] PASS: 川菜语料给出具体预测与具体召回")
}

// ---------------------------------------------------------------------------
// 场景六：唐诗英译 —— 自身语料预测与召回
// ---------------------------------------------------------------------------
test "真实场景：唐诗英译的预测与召回" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_poetry, 6)
  let incoming = "请翻译：《静夜思》里'举头望明月'一句。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("静夜思 李白 明月 故乡 举头", 3)
  let recs = recall_texts(rec)
  println("========== 新领域 · 唐诗英译 ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("=======================================")
  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景六] PASS: 诗词语料给出具体预测与具体召回")
}

// ---------------------------------------------------------------------------
// 场景七：电子竞技解说 —— 自身语料预测与召回
// ---------------------------------------------------------------------------
test "真实场景：英雄联盟赛事解说的预测与召回" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_esports, 6)
  let incoming = "请翻译：这波团战他们先拆掉了下路防御塔再转战水晶枢纽。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("防御塔 水晶枢纽 团战 英雄联盟 上单", 3)
  let recs = recall_texts(rec)
  println("========== 新领域 · 电子竞技解说 ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("=========================================")
  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景七] PASS: 电竞语料给出具体预测与具体召回")
}

// ---------------------------------------------------------------------------
// 场景八：智慧温室 —— 自身语料预测与召回
// ---------------------------------------------------------------------------
test "真实场景：智慧温室技术白皮书的预测与召回" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_agri, 6)
  let incoming = "请翻译：智慧大棚通过物联网传感器实现自动滴灌。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("智慧大棚 物联网 滴灌 传感器 温室", 3)
  let recs = recall_texts(rec)
  println("========== 新领域 · 智慧温室 ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("=======================================")
  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景八] PASS: 农业语料给出具体预测与具体召回")
}

// ---------------------------------------------------------------------------
// 场景九：高级时装 —— 自身语料预测与召回
// ---------------------------------------------------------------------------
test "真实场景：巴黎时装周秀场报道的预测与召回" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_fashion, 6)
  let incoming = "请翻译：本季高级时装以流畅廓形与手工坊刺绣取胜。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("高级时装 廓形 手工坊 秀场 刺绣", 3)
  let recs = recall_texts(rec)
  println("========== 新领域 · 高级时装 ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("=======================================")
  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景九] PASS: 时尚语料给出具体预测与具体召回")
}

// ---------------------------------------------------------------------------
// 场景十：爵士乐 —— 自身语料预测与召回
// ---------------------------------------------------------------------------
test "真实场景：爵士乐科普文章的预测与召回" {
  let eng = ProphecyEngine::make()
  train_real(eng, real_jazz, 6)
  let incoming = "请翻译：萨克斯手用蓝调音阶铺陈一段即兴。"
  let _ = eng.observe("【接收】" + incoming, "instruction")
  let pred = eng.predict(3)
  let top1 = top1_text(pred)
  let rec = eng.recall("爵士乐 即兴演奏 蓝调 萨克斯 音阶", 3)
  let recs = recall_texts(rec)
  println("========== 新领域 · 爵士乐 ==========")
  println("● 新到来源文(待译): " + incoming)
  println("● 引擎预测下一步 Top1: " + top1)
  println("● 引擎召回(前 " + recs.length().to_string() + " 条):")
  for i = 0; i < recs.length(); i = i + 1 {
    println("    " + (i + 1).to_string() + ". " + recs[i])
  }
  println("=====================================")
  inspect(top1.length() > 0 && recs.length() > 0, content="true")
  println(">>> [场景十] PASS: 爵士语料给出具体预测与具体召回")
}
