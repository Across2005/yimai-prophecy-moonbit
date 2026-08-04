// routes.mbt —— HTTP 路由 + /api/* 端点实现
// 端点（全部实测通过）：
//   POST /api/fuzzy_match   {"query","k","threshold"}   TM 模糊匹配（S1 四分量白盒）
//   POST /api/add_tm        {"src","tgt"}               新增 TM 并原子落盘
//   POST /api/check_terms   {"source","target"}         术语一致性校验
//   POST /api/concordance   {"term","k"}                术语上下文检索
//   POST /api/qe_auto       {"source","target","match_rate"}  QE 评分
//   POST /api/predict       {"k"}                       下一步预测 + 白盒
//   GET  /api/tm_count / /api/ping                       存量 / 健康检查
// 注：MoonBit async 调用无需 await；Request.path 含完整 query string（路由需剥离）。

// 从 path 提取 ? 之前的 base path（async 的 Request.path 含完整 query string）
fn extract_base_path(path : String) -> String {
  let parts = path.split("?").to_array()
  parts[0].to_string()
}

async fn send_json(conn : @http.ServerConnection, code : Int, body : String) -> Unit {
  conn.send_response(code, "OK", extra_headers={ "Content-Type": "application/json" })
  conn.write_string(body)
  conn.end_response()
}

// 主路由
async fn handle_request(req : @http.Request, body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let path = extract_base_path(req.path)
  if path == "/api/ping" {
    send_json(conn, 200, "{\"status\":\"ok\"}")
  } else if path == "/api/fuzzy_match" {
    handle_fuzzy_match(body, conn)
  } else if path == "/api/add_tm" {
    handle_add_tm(body, conn)
  } else if path == "/api/tm_count" {
    handle_tm_count(conn)
  } else if path == "/api/check_terms" {
    handle_check_terms(body, conn)
  } else if path == "/api/concordance" {
    handle_concordance(body, conn)
  } else if path == "/api/qe_auto" {
    handle_qe_auto(body, conn)
  } else if path == "/api/predict" {
    handle_predict(body, conn)
  } else if path == "/api/observe" {
    handle_observe(body, conn)
  } else if path == "/api/recall" {
    handle_recall(body, conn)
  } else if path == "/api/explain" {
    handle_explain(body, conn)
  } else if path == "/api/reward" {
    handle_reward(body, conn)
  } else if path == "/api/consolidate" {
    handle_consolidate(body, conn)
  } else if path == "/api/retrieve_prompt" {
    handle_retrieve_prompt(body, conn)
  } else if path == "/api/bleu" {
    handle_bleu(body, conn)
  } else if path == "/api/chrf" {
    handle_chrf(body, conn)
  } else if path == "/api/style_check" {
    handle_style_check(body, conn)
  } else if path == "/api/back_align" {
    handle_back_align(body, conn)
  } else if path == "/api/term_conflicts" {
    handle_term_conflicts(body, conn)
  } else if path == "/api/fed_export" {
    handle_fed_export(body, conn)
  } else if path == "/api/fed_import" {
    handle_fed_import(body, conn)
  } else if path == "/api/distill_inject" {
    handle_distill_inject(body, conn)
  } else if path == "/mcp" {
    // MCP Server 变体（spec 2025-11-25，Streamable HTTP；实现见 mcp.mbt）
    handle_mcp(req, body, conn)
  } else {
    serve_static(path, conn)
  }
}

// ===== 静态文件服务（前端工作台，async 无 serve_directory，手写）=====

// 按扩展名推断 Content-Type
fn content_type(path : String) -> String {
  if @lib.str_contains(path, ".html") { "text/html" }
  else if @lib.str_contains(path, ".js") { "application/javascript" }
  else if @lib.str_contains(path, ".css") { "text/css" }
  else if @lib.str_contains(path, ".json") { "application/json" }
  else if @lib.str_contains(path, ".svg") { "image/svg+xml" }
  else { "text/plain" }
}

// 服务 web/ 目录下静态文件（防路径穿越：拒绝 .. 与反斜杠）
async fn serve_static(path : String, conn : @http.ServerConnection) -> Unit {
  let rel = if path == "/" || path == "/index.html" {
    "index.html"
  } else {
    path.substring(start=1, end=path.length())
  }
  if @lib.str_contains(rel, "..") || @lib.str_contains(rel, "\\") {
    conn.send_response(403, "Forbidden")
    conn.end_response()
    return
  }
  let full = "cmd/service/web/" + rel
  if @fs.exists(full) {
    let data = @fs.read_file(full)
    let body = try { data.text() } catch { _ => "" }
    conn.send_response(200, "OK", extra_headers={ "Content-Type": content_type(rel) })
    conn.write_string(body)
    conn.end_response()
  } else {
    conn.send_response(404, "Not Found")
    conn.end_response()
  }
}

// 从 body 读取 JSON（async；返回 Option[Json]）
async fn read_json_body(body : &@io.Reader) -> Option[Json] {
  let data = body.read_all()
  let s = try { data.text() } catch { _ => "" }
  try { Some(@json.parse(s)) } catch { _ => None }
}

// 从 JSON 对象取字符串字段
fn json_str(o : Map[String, Json], key : String) -> String {
  match o.get(key) {
    Some(Json::String(v)) => v
    _ => ""
  }
}

// POST /api/fuzzy_match  {"query":"..","k":3,"threshold":0.5}
async fn handle_fuzzy_match(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let query = json_str(o, "query")
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 3
      }
      let thr = match o.get("threshold") {
        Some(Json::Number(n, ..)) => n
        _ => 0.70
      }
      let result = engine_ref.val.fuzzy_match(query, k, thr)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/add_tm  {"src":"..","tgt":".."}
async fn handle_add_tm(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let data = body.read_all()
  let s = try { data.text() } catch { _ => "" }
  let parsed : Option[Json] = try { Some(@json.parse(s)) } catch { _ => None }
  match parsed {
    Some(Json::Object(o)) => {
      let src = match o.get("src") {
        Some(Json::String(v)) => v
        _ => ""
      }
      let tgt = match o.get("tgt") {
        Some(Json::String(v)) => v
        _ => ""
      }
      if src == "" {
        send_json(conn, 400, "{\"error\":\"src required\"}")
      } else {
        let id = engine_ref.val.add_tm(src, tgt)
        try { save_store() } catch { err => println("save_store error: \{err}") }
        send_json(conn, 200, "{\"id\":\"" + id + "\",\"status\":\"stored\"}")
      }
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// GET /api/tm_count
async fn handle_tm_count(conn : @http.ServerConnection) -> Unit {
  let c = tm_count()
  send_json(conn, 200, "{\"tm_count\":" + c.to_string() + "}")
}

// POST /api/check_terms  {"source":"..","target":".."}  术语一致性校验（白盒返回违规）
async fn handle_check_terms(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let source = json_str(o, "source")
      let target = json_str(o, "target")
      let result = engine_ref.val.check_terms(source, target)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/concordance  {"term":"..","k":3}  含术语的 TM 段检索
async fn handle_concordance(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let term = json_str(o, "term")
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 3
      }
      let result = engine_ref.val.concordance(term, k)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/qe_auto  {"source":"..","target":"..","match_rate":0.7}  自动 QE 评分
async fn handle_qe_auto(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let source = json_str(o, "source")
      let target = json_str(o, "target")
      let mr = match o.get("match_rate") {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
      let result = engine_ref.val.qe_auto(source, target, mr)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/predict  {"k":3}  下一步预测（白盒：activation_path 证据链）
async fn handle_predict(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 3
      }
      let result = engine_ref.val.predict(k)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/observe  {"text":"..","mtype":"step"}  记录真实步骤（学习/转移/命中核算）→ 落盘
async fn handle_observe(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let text = json_str(o, "text")
      let mtype = json_str(o, "mtype")
      if text == "" {
        send_json(conn, 400, "{\"error\":\"text required\"}")
      } else {
        let mid = engine_ref.val.observe(text, mtype)
        try { save_store() } catch { err => println("save_store error: \{err}") }
        send_json(conn, 200, "{\"mid\":\"" + mid + "\",\"status\":\"learned\"}")
      }
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/recall  {"query":"..","k":5}  激活扩散语义召回
async fn handle_recall(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let query = json_str(o, "query")
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 5
      }
      let result = engine_ref.val.recall(query, k)
      send_json(conn, 200, @lib.arr_json(result).stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/explain  {"mid":".."}  白盒卡片（value_breakdown / activation_path / predicts_to）
async fn handle_explain(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let mid = json_str(o, "mid")
      let result = engine_ref.val.explain_card(mid)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/reward  {"mid":"..","score":1.0}  采纳/拒绝反馈 → predictive_value（闭环核心）
async fn handle_reward(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let mid = json_str(o, "mid")
      let score = match o.get("score") {
        Some(Json::Number(n, ..)) => n
        _ => 1.0
      }
      let ok = engine_ref.val.reward(mid, score)
      if ok {
        try { save_store() } catch { err => println("save_store error: \{err}") }
        send_json(conn, 200, "{\"ok\":true}")
      } else {
        send_json(conn, 404, "{\"ok\":false,\"error\":\"unknown mid\"}")
      }
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/consolidate  {"prune":true}  固化重放（价值重算 + 可选剪枝）
async fn handle_consolidate(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let prune = match o.get("prune") {
        Some(v) => match v.as_bool() {
          Some(b) => b
          None => json_str(o, "prune") == "true"
        }
        None => true
      }
      let result = engine_ref.val.consolidate(prune)
      try { save_store() } catch { err => println("save_store error: \{err}") }
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// ===== 待办补齐端点（S4/M1/M2/M3/M5/FedAvg/蒸馏）=====

// POST /api/retrieve_prompt  {"query","k","threshold"}  TMPlm 三段式 prompt 上下文
async fn handle_retrieve_prompt(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let query = json_str(o, "query")
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 3
      }
      let thr = match o.get("threshold") {
        Some(Json::Number(n, ..)) => n
        _ => 0.70
      }
      let result = engine_ref.val.retrieve_for_prompt(query, k, thr)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/bleu  {"ref","hyp"}  BLEU-4 评测
async fn handle_bleu(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let ref = json_str(o, "ref")
      let hyp = json_str(o, "hyp")
      let score = @lib.bleu_score(ref, hyp)
      send_json(conn, 200, "{\"bleu\":" + score.to_string() + "}")
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/chrf  {"ref","hyp"}  chrF++ 评测
async fn handle_chrf(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let ref = json_str(o, "ref")
      let hyp = json_str(o, "hyp")
      let score = @lib.chrf_score(ref, hyp)
      send_json(conn, 200, "{\"chrf\":" + score.to_string() + "}")
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/style_check  {"text"}  风格一致性检查
async fn handle_style_check(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let text = json_str(o, "text")
      let result = engine_ref.val.style_check(text)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/back_align  {"source","target"}  回译 LCS 对齐
async fn handle_back_align(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let source = json_str(o, "source")
      let target = json_str(o, "target")
      let result = engine_ref.val.back_align(source, target)
      send_json(conn, 200, result.stringify())
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/term_conflicts  {}  术语冲突检测
async fn handle_term_conflicts(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let result = engine_ref.val.term_conflicts()
  send_json(conn, 200, result.stringify())
}

// POST /api/fed_export  {}  联邦增量导出
async fn handle_fed_export(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let result = engine_ref.val.fed_export()
  send_json(conn, 200, result.stringify())
}

// POST /api/fed_import  {"added","updated"}  联邦增量导入（写操作落盘）
async fn handle_fed_import(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let added = match o.get("added") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let updated = match o.get("updated") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      engine_ref.val.fed_import(added, updated)
      try { save_store() } catch { err => println("save_store error: \{err}") }
      send_json(conn, 200, "{\"status\":\"imported\"}")
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// POST /api/distill_inject  {"table":{"role":0.5}}  蒸馏表注入（写操作落盘）
async fn handle_distill_inject(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_body(body)
  match parsed {
    Some(Json::Object(o)) => {
      let table : Map[String, Double] = Map::new()
      match o.get("table") {
        Some(Json::Object(t)) =>
          for k, v in t.iter2() {
            match v {
              Json::Number(n, ..) => table.set(k, n)
              _ => ()
            }
          }
        _ => ()
      }
      engine_ref.val.inject_distillation(table)
      try { save_store() } catch { err => println("save_store error: \{err}") }
      send_json(conn, 200, "{\"status\":\"injected\",\"keys\":" + table.size().to_string() + "}")
    }
    _ => send_json(conn, 400, "{\"error\":\"invalid JSON body\"}")
  }
}

// ===== 待办补齐端点（S4/M1/M2/M3/M5/FedAvg/蒸馏）=====

// POST /api/retrieve_prompt  {"query","k","threshold"}  TMPlm 三段式 prompt 上下文