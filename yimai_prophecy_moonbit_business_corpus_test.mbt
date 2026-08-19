// yimai_prophecy_moonbit_business_corpus_test.mbt —— P5 商务领域语料
// 覆盖：8 句合同 / 商务信函 / 招投标场景
//
// 标准对齐：
//   - ISO 11669:2024 (TS) 翻译项目交付指南：商务领域（合同、招投标、议价）是核心场景
//   - GB/T 30539-2025 中国商务领域语言服务国家标准（2026-02-01 实施）：
//     13 种语言、3 个能力等级（高级/中级/初级）、4 维度考核
//     商务领域为最高频场景，本语料覆盖其中 6 类
//   - yimai P5 路线图：把商务领域作为测试基线的"必须命中"域
//
// 测试断言：
//   1) 8 句训练后，跨句 fuzzy_match Hit@3 ≥ 5/8（62.5%）
//   2) 数字守门：商务句含 30/30% / FOB / 30 days 等数字/单位，
//      故意漏译数字 → mqm_tags 检出 numeric_consistency/critical
//   3) 术语一致性：load_tbx 加载 "force majeure" → 不可抗力 /
//      "FOB Shanghai" → 上海港船上交货，加载后 check_terms 命中
//
// 关联：engine.mbt::fuzzy_match / mqm_tags / check_terms + util.mbt::numeric_tokens

// ---------------------------------------------------------------------------
// 8 句商务英中双语对（覆盖 6 类场景）
// ---------------------------------------------------------------------------
let business_corpus : Array[(String, String)] = [
  ("The subject matter of this contract", "本合同标的"),
  ("Neither party shall be liable for force majeure", "任何一方对不可抗力均不承担责任"),
  ("Payment shall be made within 30 days of invoice date", "应于发票日期后 30 日内付款"),
  ("Shipment shall be effected by sea freight FOB Shanghai", "应通过海运 FOB 上海装运"),
  ("Any dispute shall be settled by arbitration in Shanghai", "任何争议应在上海通过仲裁解决"),
  ("The breaching party shall compensate for direct losses", "违约方应赔偿直接损失"),
  ("We are pleased to enclose our latest catalogue", "我们欣然附上最新产品目录"),
  ("Tender documents must be submitted before the deadline", "投标文件须于截止日期前提交"),
]

// ---------------------------------------------------------------------------
// T42: 8 句 add_tm 入索引后 Hit@3 ≥ 5/8（62.5% 底线）
//   fuzzy_match 只搜 mtype="tm" 的 memory；add_tm 是 fuzzy_match 真正测试的入口
//   （P4 frontier_corpus T48 已验证此模式）
// ---------------------------------------------------------------------------
test "T42 business_corpus_hit_at_3" {
  let eng = ProphecyEngine::make()
  // add_tm 8 句入 TM 索引
  for i = 0; i < business_corpus.length(); i = i + 1 {
    let (s, t) = business_corpus[i]
    let _ = eng.add_tm(s, t)
  }
  // 命中检测
  let mut hits = 0
  for i = 0; i < business_corpus.length(); i = i + 1 {
    let (s, t) = business_corpus[i]
    let top = eng.fuzzy_match(s, 3, 0.30)
    // top 是 Array[Json]，检查 t 是否在 target 字段中
    let mut found = false
    match top {
      Json::Array(a) =>
        for j = 0; j < a.length(); j = j + 1 {
          let cand = a[j]
          match cand {
            Json::Object(co) =>
              match co.get("target") {
                Some(Json::String(ts)) => if ts == t { found = true }
                _ => ()
              }
            _ => ()
          }
        }
      _ => ()
    }
    if found { hits = hits + 1 }
  }
  // Hit@3 ≥ 5/8 (62.5%)
  inspect(hits >= 5, content="true")
}

// ---------------------------------------------------------------------------
// T43: 数字守门 — 商务句故意漏译"30 days" → mqm_tags 检出 critical
//   这是商务翻译最常见的硬伤：付款条件漏数字会导致合同争议
// ---------------------------------------------------------------------------
test "T43 business_corpus_numeric_gate_critical" {
  let eng = ProphecyEngine::make()
  // add_tm 8 句入索引
  for i = 0; i < business_corpus.length(); i = i + 1 {
    let (s, t) = business_corpus[i]
    let _ = eng.add_tm(s, t)
  }
  // 故意漏译数字
  let bad_target = "应于发票日期后付款"  // 漏掉 "30 days"
  let tags = eng.mqm_tags(
    "Payment shall be made within 30 days of invoice date",
    bad_target,
    0.0,  // match_rate 不影响 numeric_consistency 触发
    true,
  )
  let s = tags.stringify()
  // 必须检出 numeric_consistency critical
  inspect(s.contains("\"dimension\":\"numeric_consistency\""), content="true")
  inspect(s.contains("\"severity\":\"critical\""), content="true")
}

// ---------------------------------------------------------------------------
// T44: 术语守门 — load_tbx 加载 force majeure/FOB 术语后，check_terms 命中
//   商务术语一致性是 ISO 11669 强调的硬要求
// ---------------------------------------------------------------------------
test "T44 business_corpus_term_gate" {
  let eng = ProphecyEngine::make()
  // add_tm 8 句入索引
  for i = 0; i < business_corpus.length(); i = i + 1 {
    let (s, t) = business_corpus[i]
    let _ = eng.add_tm(s, t)
  }
  // 加载 2 个商务术语（force majeure / FOB Shanghai）
  let tbx_xml =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
    "<martif type=\"TBX\">\n" +
    "  <martifHeader><fileDesc><sourceDesc><p>test</p></sourceDesc></fileDesc></martifHeader>\n" +
    "  <text><body>\n" +
    "    <termEntry id=\"c1\">\n" +
    "      <langSet xml:lang=\"en-US\"><tig><term>force majeure</term></tig></langSet>\n" +
    "      <langSet xml:lang=\"zh-CN\"><tig><term>不可抗力</term></tig></langSet>\n" +
    "    </termEntry>\n" +
    "    <termEntry id=\"c2\">\n" +
    "      <langSet xml:lang=\"en-US\"><tig><term>FOB Shanghai</term></tig></langSet>\n" +
    "      <langSet xml:lang=\"zh-CN\"><tig><term>上海港船上交货</term></tig></langSet>\n" +
    "    </termEntry>\n" +
    "  </body></text>\n" +
    "</martif>"
  let _ = eng.load_tbx(tbx_xml)
  // 故意错译 force majeure → 不可抗拒（错误译法）
  let bad_target = "任何一方对不可抗拒均不承担责任"
  let violations = eng.check_terms(
    "Neither party shall be liable for force majeure",
    bad_target,
  )
  // 应该有 ≥ 1 条术语违规（JSON 数组长度 > 5 字符）
  let s = violations.stringify()
  inspect(s.length() > 5, content="true")
}
