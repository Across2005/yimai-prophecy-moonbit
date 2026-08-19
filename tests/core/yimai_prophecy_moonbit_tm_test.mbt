// yimai_prophecy_moonbit_tm_test.mbt
// #1 TM/TB 一等公民 专项回归（R16-R20）
// 覆盖：TM 模糊匹配(匹配率%)、concordance 检索、TBX 加载 + 强制对齐 + 一致性校验、序列化往返。

test "R16 TM 模糊匹配返回 Top-K 且匹配率正确" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.add_tm("电池包热管理策略", "Battery pack thermal management strategy")
  let _ = e.add_tm("电机冷却系统", "Motor cooling system")
  let _ = e.add_tm("电池包温度管理方案", "Battery pack temperature management plan")
  // 查询与其近重复条目都高于阈值 -> 返回 Top-2
  let r = e.fuzzy_match("电池包热管理方案", 3, 0.70)
  match r {
    Json::Array(a) => {
      inspect(a.length() == 2, content="true")
      match a[0] {
        Json::Object(m) => {
          match m.get("match_pct") {
            Some(Json::Number(p, ..)) => inspect(p > 70.0, content="true")
            _ => inspect(false, content="true")
          }
        }
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
  // 精确/高相似查询必须把它自己的 TM 排到 Top-1 且匹配率 > 90
  let r2 = e.fuzzy_match("电机冷却系统", 3, 0.70)
  match r2 {
    Json::Array(a) => {
      match a[0] {
        Json::Object(m) => {
          match m.get("source") {
            Some(Json::String(s)) => inspect(s == "电机冷却系统", content="true")
            _ => inspect(false, content="true")
          }
          match m.get("match_pct") {
            Some(Json::Number(p, ..)) => inspect(p > 90.0, content="true")
            _ => inspect(false, content="true")
          }
        }
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

test "R17 concordance 检索命中含术语的句段" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.add_tm("打开设置菜单选择网络", "Open Settings menu, choose Network")
  let _ = e.add_tm("网络连接有问题", "Network connection has issues")
  let _ = e.add_tm("保存文件到本地", "Save file locally")
  let r = e.concordance("网络", 5)
  match r {
    Json::Array(a) => inspect(a.length() >= 2, content="true")
    _ => inspect(false, content="true")
  }
}

test "R18 TBX 加载 + 强制对齐命中" {
  let e = @lib.ProphecyEngine::make()
  let tbx =
    "<martif><text><body>" +
    "<termEntry id=\"1\"><langSet xml:lang=\"en-US\"><ntig><termGrp><term>network logon</term></termGrp></ntig></langSet>" +
    "<langSet xml:lang=\"fr-FR\"><ntig><termGrp><term>ouverture de session reseau</term></termGrp></ntig></langSet></termEntry>" +
    "</body></text></martif>"
  let n = e.load_tbx(tbx)
  inspect(n == 1, content="true")
  let hits = e.enforce_terms("请完成 network logon 操作")
  match hits {
    Json::Array(a) => inspect(a.length() == 1, content="true")
    _ => inspect(false, content="true")
  }
}

test "R19 TBX 一致性校验捕获术语漏译" {
  let e = @lib.ProphecyEngine::make()
  let tbx =
    "<martif><text><body>" +
    "<termEntry id=\"1\"><langSet xml:lang=\"en-US\"><ntig><termGrp><term>sensor</term></termGrp></ntig></langSet>" +
    "<langSet xml:lang=\"zh-CN\"><ntig><termGrp><term>传感器</term></termGrp></ntig></langSet></termEntry>" +
    "</body></text></martif>"
  let _ = e.load_tbx(tbx)
  // 源文含 sensor，但译文未出现"传感器" -> 应报 1 条违规
  let v = e.check_terms("install the sensor", "install the device")
  match v {
    Json::Array(a) => inspect(a.length() == 1, content="true")
    _ => inspect(false, content="true")
  }
  // 译文含术语 -> 无违规
  let v2 = e.check_terms("install the sensor", "install the 传感器")
  match v2 {
    Json::Array(a) => inspect(a.length() == 0, content="true")
    _ => inspect(false, content="true")
  }
}

test "R20 TM 节点序列化往返保留 translation" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.add_tm("源句 A", "译文 A")
  let e2 = @lib.ProphecyEngine::from_json(e.to_json())
  let r = e2.fuzzy_match("源句 A", 1, 0.0)
  match r {
    Json::Array(a) => {
      match a[0] {
        Json::Object(m) =>
          match m.get("target") {
            Some(Json::String(s)) => inspect(s == "译文 A", content="true")
            _ => inspect(false, content="true")
          }
        _ => inspect(false, content="true")
      }
    }
    _ => inspect(false, content="true")
  }
}

test "R21 术语词边界：log 不应误命中 logical" {
  let e = @lib.ProphecyEngine::make()
  let tbx =
    "<martif><text><body>" +
    "<termEntry id=\"1\"><langSet xml:lang=\"en-US\"><ntig><termGrp><term>log</term></termGrp></ntig></langSet>" +
    "<langSet xml:lang=\"zh-CN\"><ntig><termGrp><term>日志</term></termGrp></ntig></langSet></termEntry>" +
    "</body></text></martif>"
  let _ = e.load_tbx(tbx)
  // "logical error" 中的 log 是拉丁文子串、无词边界 -> 不应命中
  let bad = e.enforce_terms("a logical error occurred")
  match bad {
    Json::Array(a) => inspect(a.length() == 0, content="true")
    _ => inspect(false, content="true")
  }
  // "check the log" 中的 log 有词边界 -> 应命中
  let ok = e.enforce_terms("please check the log now")
  match ok {
    Json::Array(a) => inspect(a.length() == 1, content="true")
    _ => inspect(false, content="true")
  }
}

test "R22 多语言 TBX：按 xml:lang 取 en→zh（忽略 fr）" {
  let e = @lib.ProphecyEngine::make()
  let tbx =
    "<martif><text><body>" +
    "<termEntry id=\"1\">" +
    "<langSet xml:lang=\"en-US\"><ntig><termGrp><term>server</term></termGrp></ntig></langSet>" +
    "<langSet xml:lang=\"fr-FR\"><ntig><termGrp><term>serveur</term></termGrp></ntig></langSet>" +
    "<langSet xml:lang=\"zh-CN\"><ntig><termGrp><term>服务器</term></termGrp></ntig></langSet>" +
    "</termEntry></body></text></martif>"
  let n = e.load_tbx(tbx)
  inspect(n == 1, content="true")
  // 译文给中文"服务器" -> 一致（证明 translation 锁定 zh-CN 而非 fr）
  let v = e.check_terms("restart the server", "重启服务器")
  match v {
    Json::Array(a) => inspect(a.length() == 0, content="true")
    _ => inspect(false, content="true")
  }
  // 译文给法文"serveur" -> 不一致（反证翻译目标已被锁定为中文）
  let v2 = e.check_terms("restart the server", "redémarrer le serveur")
  match v2 {
    Json::Array(a) => inspect(a.length() == 1, content="true")
    _ => inspect(false, content="true")
  }
}

// ---- S1 检索强化回归（R23-R25）：IDF 加权 + n-gram + 词序容忍 ----

fn json_score(j : Json) -> Double {
  match j {
    Json::Object(m) =>
      match m.get("score") {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
}

fn json_source(j : Json) -> String {
  match j {
    Json::Object(m) =>
      match m.get("source") {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

test "R23 S1 IDF 加权：常见词噪音下罕见术语优先召回，且 top1-top2 区分度 >= 旧公式" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.add_tm("打开文件保存", "Open file and save")
  let _ = e.add_tm("打开设置界面", "Open settings UI")
  let _ = e.add_tm("打开浏览器窗口", "Open browser window")
  let _ = e.add_tm("打开命令行工具", "Open command line tool")
  let _ = e.add_tm("打开网络连接面板", "Open network panel")
  let _ = e.add_tm("光子芯片散热设计", "Photonic chip thermal design")
  let r = e.fuzzy_match("光子芯片设计文件", 3, 0.0)
  let rl = e.fuzzy_match_legacy("光子芯片设计文件", 3, 0.0)
  // top1 必须是含罕见术语的条目（IDF 让"光子芯片"权重压过高频"打开"）
  match r {
    Json::Array(a) => {
      inspect(a.length() >= 1, content="true")
      inspect(json_source(a[0]) == "光子芯片散热设计", content="true")
    }
    _ => inspect(false, content="true")
  }
  // 区分度对比：新公式 top1-top2 差距 >= 旧公式（罕见术语更显著领先）
  match (r, rl) {
    (Json::Array(an), Json::Array(al)) => {
      let gap_new = if an.length() >= 2 { json_score(an[0]) - json_score(an[1]) } else { 0.0 }
      let gap_old = if al.length() >= 2 { json_score(al[0]) - json_score(al[1]) } else { 0.0 }
      inspect(gap_new >= gap_old, content="true")
    }
    _ => inspect(false, content="true")
  }
}

test "R24 S1 词序重排：新公式命中（>0.70），旧公式漏掉（<0.70）" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.add_tm("请检查设置按钮", "Please check the settings button")
  // 中文 bigram 分词下词序重排改变 bigram，旧公式的 token 余弦显著受损；新公式 sim_tokenset 不敏感
  let rn = e.fuzzy_match("设置按钮请检查", 1, 0.70)
  match rn {
    Json::Array(a) => inspect(a.length() == 1, content="true")
    _ => inspect(false, content="true")
  }
  let ro = e.fuzzy_match_legacy("设置按钮请检查", 1, 0.70)
  match ro {
    Json::Array(a) => inspect(a.length() == 0, content="true")
    _ => inspect(false, content="true")
  }
}

test "R25 S1 边界：空查询不崩溃；单字查询无 2-gram 时不过 0.70 阈值" {
  let e = @lib.ProphecyEngine::make()
  let _ = e.add_tm("请检查设置按钮", "Please check the settings button")
  let r1 = e.fuzzy_match("", 3, 0.0)
  match r1 {
    Json::Array(_) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
  let r2 = e.fuzzy_match("短", 3, 0.70)
  match r2 {
    Json::Array(a) => inspect(a.length() == 0, content="true")
    _ => inspect(false, content="true")
  }
}
