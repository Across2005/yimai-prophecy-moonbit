// yimai_prophecy_moonbit_tm_test.mbt
// #1 TM/TB 一等公民 专项回归（R16-R20）
// 覆盖：TM 模糊匹配(匹配率%)、concordance 检索、TBX 加载 + 强制对齐 + 一致性校验、序列化往返。

test "R16 TM 模糊匹配返回 Top-K 且匹配率正确" {
  let e = ProphecyEngine::make()
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
  let e = ProphecyEngine::make()
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
  let e = ProphecyEngine::make()
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
  let e = ProphecyEngine::make()
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
  let e = ProphecyEngine::make()
  let _ = e.add_tm("源句 A", "译文 A")
  let e2 = ProphecyEngine::from_json(e.to_json())
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
  let e = ProphecyEngine::make()
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
  let e = ProphecyEngine::make()
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
