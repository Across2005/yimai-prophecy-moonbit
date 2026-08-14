// yimai_prophecy_moonbit_long_text_test.mbt
// 长文 + 数字守门的回归测试（P0 加强）
// 覆盖：
//   L1-L3   numeric_tokens 识别基本数字 / 顺序确定性 / 千分位不吞
//   L4-L6   split_into_segments 切分 / 二次切 / 空文本
//   L7      yimai_tokenize 长文截断不爆（5万字 → ≤MAX_TOKENS）
//   L8-L10  mqm_tags 数字守门：漏译 critical / 集合不一致 major / 一致无 issue
//   L11     qe_auto 集成 numeric_consistency 到 MQM 输出
//   L12     fuzzy_match 5000 字符长 query 不崩

// ---------------------------------------------------------------------------
// L1 numeric_tokens: 基础识别（十进制 / 浮点 / 百分号 / 度数 / 单位）
// ---------------------------------------------------------------------------

test "L1 numeric_tokens: 浮点 + 整数 + 不接单位" {
  let nums = numeric_tokens("电池电压 3.7V，工作温度 20~85，效率 95")
  // 期望: 3.7 / 20 / 85 / 95（v1 不接单位字母/℃/°/%，浮点和整数都被识别）
  let mut found_3_7 = false
  let mut found_85 = false
  for n in nums {
    if n == "3.7" { found_3_7 = true }
    if n == "85" { found_85 = true }
  }
  inspect(found_3_7, content="true")
  inspect(found_85, content="true")
}

// ---------------------------------------------------------------------------
// L2 numeric_tokens: 顺序确定性（同输入两次输出严格一致）
// ---------------------------------------------------------------------------

test "L2 numeric_tokens: 确定性" {
  let s = "range 100-200m at 5GHz, peak 2.4V"
  let a = numeric_tokens(s)
  let b = numeric_tokens(s)
  let mut same = a.length() == b.length()
  if same {
    for i = 0; i < a.length(); i = i + 1 {
      if a[i] != b[i] { same = false; break }
    }
  }
  inspect(same, content="true")
}

// ---------------------------------------------------------------------------
// L3 numeric_tokens: 千分位逗号不吞（v1 不支持，避免误报 "1,000" → "1000"）
// ---------------------------------------------------------------------------

test "L3 numeric_tokens: 千分位逗号不会吞掉后续数字" {
  let nums = numeric_tokens("capacity 1,000mAh, 后续 2,500 字")
  // 期望：仅识别出 "1" "2" 两个独立数字（逗号作分隔）
  let mut one = false
  let mut two = false
  for n in nums {
    if n == "1" { one = true }
    if n == "2" { two = true }
  }
  inspect(one, content="true")
  inspect(two, content="true")
}

// ---------------------------------------------------------------------------
// L4 split_into_segments: 按中英文句号切
// ---------------------------------------------------------------------------

test "L4 split_into_segments: 中文句号/全角叹号/全角问号切分" {
  let segs = split_into_segments("第一句。第二句！第三句？", 100)
  inspect(segs.length() == 3, content="true")
}

// ---------------------------------------------------------------------------
// L5 split_into_segments: 超 max_chars 触发二次切（按空格）
// ---------------------------------------------------------------------------

test "L5 split_into_segments: 超长段按空格切" {
  // 构造一个 > 200 字符长段，无句号，max_chars=50 → 必触发二次切
  let long = "传感器A安装在3号支架与主控板通过屏蔽线缆连接并进行阻抗匹配 传感器B连接主控并接入数据采集模块以实现高精度信号调理与滤波 传感器C接入数据采集模块并通过光电隔离保护后端设备 传感器D作为冗余备份在主链路失效时自动切换至备用信道"
  let segs = split_into_segments(long, 50)
  // 至少切成 2 段
  inspect(segs.length() >= 2, content="true")
  // 每段不超过 50 + 一点余量（max_chars 边界）
  let mut all_ok = true
  for s in segs {
    if s.length() > 100 { all_ok = false }
  }
  inspect(all_ok, content="true")
}

// ---------------------------------------------------------------------------
// L6 split_into_segments: 空文本
// ---------------------------------------------------------------------------

test "L6 split_into_segments: 空文本返回空数组" {
  let segs = split_into_segments("", 100)
  inspect(segs.length() == 0, content="true")
}

// ---------------------------------------------------------------------------
// L7 yimai_tokenize: 5万字超长段不爆，输出 ≤ MAX_TOKENS
// ---------------------------------------------------------------------------

test "L7 yimai_tokenize: 5万字不爆" {
  // 构造 5 万字 CJK 长文（每字 1 token + bigram ≈ 2 token → 约 10 万 token 应被截断）
  let s = StringBuilder()
  for i = 0; i < 50000; i = i + 1 {
    s.write_char('中')
  }
  let toks = yimai_tokenize(s.to_string())
  // 截断后应 <= MAX_TOKENS（允许等于或略小）
  inspect(toks.length() <= 20000, content="true")
}

// ---------------------------------------------------------------------------
// L8 mqm_tags 数字守门：源文有数字，译文未保留 → critical
// ---------------------------------------------------------------------------

test "L8 mqm_tags: 数字漏译 → critical" {
  let e = ProphecyEngine::make()
  let tags = e.mqm_tags("Voltage 3.7V at 100mA", "电压电流正常", 0.8, true)
  // 期望 issues 数组含 dimension=numeric_consistency, severity=critical
  let mut found_critical = false
  match tags {
    Json::Array(arr) =>
      for it in arr {
        match it {
          Json::Object(o) =>
            match o.get("dimension") {
              Some(Json::String(d)) =>
                if d == "numeric_consistency" {
                  match o.get("severity") {
                    Some(Json::String(sev)) => if sev == "critical" { found_critical = true }
                    _ => ()
                  }
                }
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  inspect(found_critical, content="true")
}

// ---------------------------------------------------------------------------
// L9 mqm_tags 数字守门：集合不一致 → major
// ---------------------------------------------------------------------------

test "L9 mqm_tags: 数字集合不一致 → major" {
  let e = ProphecyEngine::make()
  // 源 3.7 / 100；译 3.7（漏 100）+ 多 200 → 不一致
  let tags = e.mqm_tags("Voltage 3.7V at 100mA", "电压 3.7V 额外 200", 0.8, true)
  let mut found_major = false
  match tags {
    Json::Array(arr) =>
      for it in arr {
        match it {
          Json::Object(o) =>
            match o.get("dimension") {
              Some(Json::String(d)) =>
                if d == "numeric_consistency" {
                  match o.get("severity") {
                    Some(Json::String(sev)) => if sev == "major" { found_major = true }
                    _ => ()
                  }
                }
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  inspect(found_major, content="true")
}

// ---------------------------------------------------------------------------
// L10 mqm_tags 数字守门：数字完全一致 → 无 numeric_consistency issue
// ---------------------------------------------------------------------------

test "L10 mqm_tags: 数字一致 → 无 numeric_consistency 标签" {
  let e = ProphecyEngine::make()
  let tags = e.mqm_tags("Voltage 3.7V", "电压 3.7V", 1.0, true)
  let mut found_num_issue = false
  match tags {
    Json::Array(arr) =>
      for it in arr {
        match it {
          Json::Object(o) =>
            match o.get("dimension") {
              Some(Json::String(d)) =>
                if d == "numeric_consistency" { found_num_issue = true }
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  inspect(found_num_issue, content="false")
}

// ---------------------------------------------------------------------------
// L11 qe_auto 集成数字守门（mqm 字段含 numeric_consistency）
// ---------------------------------------------------------------------------

test "L11 qe_auto: 数字漏译反映到 mqm 数组" {
  let e = ProphecyEngine::make()
  let r = e.qe_auto("Voltage 3.7V", "电压", 0.8)
  // r 是 {qe_score, term_ok, mqm}
  let mut found = false
  match r {
    Json::Object(o) =>
      match o.get("mqm") {
        Some(Json::Array(arr)) =>
          for it in arr {
            match it {
              Json::Object(io) =>
                match io.get("dimension") {
                  Some(Json::String(d)) =>
                    if d == "numeric_consistency" { found = true }
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  inspect(found, content="true")
}

// ---------------------------------------------------------------------------
// L12 fuzzy_match: 5000 字符超长 query 不崩
// ---------------------------------------------------------------------------

test "L12 fuzzy_match: 超长 query 不崩（空 TM 应返回 []）" {
  let e = ProphecyEngine::make()
  // 构造 5000 字符 query
  let q = StringBuilder()
  for i = 0; i < 5000; i = i + 1 {
    q.write_char('电')
  }
  let r = e.fuzzy_match(q.to_string(), 3, 0.0)
  // 空 TM → 数组长度 0（不抛、不超时）
  let mut ok = false
  match r {
    Json::Array(arr) => ok = arr.length() == 0
    _ => ()
  }
  inspect(ok, content="true")
}
