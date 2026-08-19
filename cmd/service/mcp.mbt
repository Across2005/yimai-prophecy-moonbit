// mcp.mbt —— /mcp 端点：MCP (Model Context Protocol) Server 变体
// spec 2025-11-25 · Streamable HTTP 传输（挂 8787 服务，POST 单 JSON-RPC 消息，application/json 响应）
// 24 个引擎能力映射为 MCP tools，供 Claude Desktop / 通用 MCP 客户端消费。
// 注：MoonBit Json 为 FFI 类型，构造一律走 @lib.obj/str_json/num_json/arr_json。

// ===== JSON-RPC 响应构造 =====
fn rpc_result(id : Json, result : Json) -> Json {
  @lib.obj([("jsonrpc", @lib.str_json("2.0")), ("id", id), ("result", result)])
}

fn rpc_error(id : Json, code : Int, msg : String) -> Json {
  @lib.obj([
    ("jsonrpc", @lib.str_json("2.0")),
    ("id", id),
    ("error", @lib.obj([("code", code.to_json()), ("message", @lib.str_json(msg))])),
  ])
}

// 从请求提取 id（String/Number 原样回写；无 id 回空串）
fn extract_id(req : Json) -> Json {
  match req {
    Json::Object(o) =>
      match o.get("id") {
        Some(id) => id
        None => @lib.str_json("")
      }
    _ => @lib.str_json("")
  }
}

fn extract_method(req : Json) -> String {
  match req {
    Json::Object(o) =>
      match o.get("method") {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

fn extract_params(req : Json) -> Json {
  match req {
    Json::Object(o) =>
      match o.get("params") {
        Some(p) => p
        None => @lib.obj([])
      }
    _ => @lib.obj([])
  }
}

// ===== 工具参数提取 =====
fn arg_str(args : Json, key : String) -> String {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::String(v)) => v
        _ => ""
      }
    _ => ""
  }
}

fn arg_int(args : Json, key : String, default : Int) -> Int {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

fn arg_num(args : Json, key : String, default : Double) -> Double {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::Number(n, ..)) => n
        _ => default
      }
    _ => default
  }
}

fn arg_bool(args : Json, key : String, default : Bool) -> Bool {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(v) => match v.as_bool() {
          Some(b) => b
          None => default
        }
        None => default
      }
    _ => default
  }
}

// ===== 工具表 =====
fn schema_prop(kind : String, desc : String) -> Json {
  @lib.obj([("type", @lib.str_json(kind)), ("description", @lib.str_json(desc))])
}

fn tool_def(name : String, desc : String, props : Array[(String, Json)], required : Array[String]) -> Json {
  let req_json = Array::map(required, fn(s) { @lib.str_json(s) })
  // P1: 补 additionalProperties: false（OpenAI Agents SDK 严格模式要求 + mcp-lint 业界基线）
  //   spec 2025-11-25 + JSON Schema 2020-12（SEP-1613 默认 dialect）下，LLM 误传多余字段会被拒
  @lib.obj([
    ("name", @lib.str_json(name)),
    ("description", @lib.str_json(desc)),
    ("inputSchema", @lib.obj([
      ("type", @lib.str_json("object")),
      ("properties", @lib.obj(props)),
      ("required", @lib.arr_json(req_json)),
      ("additionalProperties", false.to_json()),
    ])),
  ])
}

fn all_tools() -> Json {
  let tools = [
    tool_def("fuzzy_match", "TM 模糊检索 Top-K，返回 S1 四分量白盒分数（match_pct/sim_token/sim_tfidf/sim_char/sim_ngram/sim_tokenset）", [
      ("query", schema_prop("string", "源文查询")),
      ("k", schema_prop("integer", "Top-K（默认 3）")),
      ("threshold", schema_prop("number", "相似度阈值（默认 0.5）")),
    ], ["query"]),
    tool_def("add_tm", "新增 TM 条目（source→target）并原子落盘", [
      ("src", schema_prop("string", "源文")),
      ("tgt", schema_prop("string", "译文")),
    ], ["src", "tgt"]),
    tool_def("check_terms", "术语一致性校验：返回漏译/错译术语违规", [
      ("source", schema_prop("string", "源文")),
      ("target", schema_prop("string", "译文")),
    ], ["source", "target"]),
    tool_def("concordance", "术语上下文检索：返回含该术语的 TM 段", [
      ("term", schema_prop("string", "术语")),
      ("k", schema_prop("integer", "Top-K（默认 3）")),
    ], ["term"]),
    tool_def("qe_auto", "自动 QE 评分 + MQM 标签", [
      ("source", schema_prop("string", "源文")),
      ("target", schema_prop("string", "译文")),
      ("match_rate", schema_prop("number", "匹配率（默认 0）")),
    ], ["source", "target"]),
    tool_def("predict", "下一步预测 Top-K + 白盒路径", [
      ("k", schema_prop("integer", "Top-K（默认 3）")),
    ], []),
    tool_def("observe", "记录真实步骤（学习/转移/命中核算）并落盘", [
      ("text", schema_prop("string", "步骤文本")),
      ("mtype", schema_prop("string", "类型（默认 step）")),
    ], ["text"]),
    tool_def("recall", "激活扩散语义召回", [
      ("query", schema_prop("string", "查询")),
      ("k", schema_prop("integer", "Top-K（默认 5）")),
    ], ["query"]),
    tool_def("explain", "白盒卡片：value_breakdown / activation_path 证据链", [
      ("mid", schema_prop("string", "节点 id")),
    ], ["mid"]),
    tool_def("reward", "采纳/拒绝反馈（-1/+1 写入 predictive_value）", [
      ("mid", schema_prop("string", "节点 id")),
      ("score", schema_prop("number", "反馈分数（默认 1.0）")),
    ], ["mid"]),
    tool_def("consolidate", "固化重放：价值重算 + 可选剪枝", [
      ("prune", schema_prop("boolean", "是否剪枝（默认 true）")),
    ], []),
    tool_def("tm_count", "TM 条目存量统计", [], []),
    tool_def("ping", "健康检查", [], []),
    tool_def("retrieve_prompt", "TMPlm：为 LLM prompt 组装三段式检索上下文（suggestions/terms/glossary）", [
      ("query", schema_prop("string", "源文查询")),
      ("k", schema_prop("integer", "Top-K（默认 3）")),
      ("threshold", schema_prop("number", "相似度阈值（默认 0.70）")),
    ], ["query"]),
    tool_def("bleu", "BLEU-4 评测（ref vs hyp）", [
      ("ref", schema_prop("string", "参考译文")),
      ("hyp", schema_prop("string", "候选译文")),
    ], ["ref", "hyp"]),
    tool_def("chrf", "chrF++ 评测（ref vs hyp）", [
      ("ref", schema_prop("string", "参考译文")),
      ("hyp", schema_prop("string", "候选译文")),
    ], ["ref", "hyp"]),
    tool_def("style_check", "风格一致性检查（句长/标点/括号/术语命中）", [
      ("text", schema_prop("string", "待检查文本")),
    ], ["text"]),
    tool_def("style_report", "风格一致报告：记忆库句长/正式度分布 + 术语变体族 + 新译文偏离建议", [
      ("text", schema_prop("string", "待检译文（可空：仅报告记忆库分布）")),
    ], []),
    tool_def("back_align", "回译 LCS 对齐验证", [
      ("source", schema_prop("string", "源文")),
      ("target", schema_prop("string", "译文")),
    ], ["source", "target"]),
    tool_def("term_conflicts", "术语冲突检测（一词多译/多词一译）", [], []),
    tool_def("fed_export", "联邦增量导出", [], []),
    tool_def("fed_import", "联邦增量导入", [
      ("added", schema_prop("integer", "新增数（默认 0）")),
      ("updated", schema_prop("integer", "更新数（默认 0）")),
    ], []),
    tool_def("distill_inject", "蒸馏偏置表注入", [
      ("table", schema_prop("object", "角色→偏置 Map")),
    ], []),
    tool_def("active_learning", "主动学习推荐：按 uncertainty+diversity 推 Top-K 待标注句", [
      ("k", schema_prop("integer", "Top-K（默认 5）")),
    ], []),
    tool_def("mqm_re_annotate", "MQM 二次标注：对 Critical 段强制重审（Google 2025-10-28 论文对齐），返回 re_annotated/critical_count/re_annotations", [
      ("source", schema_prop("string", "源文")),
      ("target", schema_prop("string", "译文")),
      ("match_rate", schema_prop("number", "匹配率（默认 0）")),
    ], ["source", "target"]),
  ]
  @lib.arr_json(tools)
}

// 工具名清单（25 项；与 all_tools 内的 tool_def name 必须同步）。
// P4 抽出来为顶层 let，便于 is_known_tool 用 Array::contains 替代手写循环，
// 减少一处 24 字符串表（all_tools 仍硬编码，因 tool_def 的 name/desc/props 三元组不便拆分）。
// P5 增量：mqm_re_annotate 加入（25 项）。
pub let known_tool_names : Array[String] = [
  "fuzzy_match", "add_tm", "check_terms", "concordance", "qe_auto", "predict", "observe",
  "recall", "explain", "reward", "consolidate", "tm_count", "ping", "retrieve_prompt", "bleu", "chrf",
  "style_check", "style_report", "back_align", "term_conflicts", "fed_export", "fed_import", "distill_inject",
  "active_learning", "mqm_re_annotate",
]

fn is_known_tool(name : String) -> Bool {
  // P4：用 Array::contains 替代手写 found 循环；性能 O(n) 同，但更声明式。
  Array::contains(known_tool_names, name)
}

// 分派工具调用（写操作后落盘；async 因调用 save_store）
async fn invoke_tool(name : String, args : Json) -> Json {
  if name == "fuzzy_match" {
    engine_ref.val.fuzzy_match(arg_str(args, "query"), arg_int(args, "k", 3), arg_num(args, "threshold", 0.70))
  } else if name == "add_tm" {
    let id = engine_ref.val.add_tm(arg_str(args, "src"), arg_str(args, "tgt"))
    let _ = save_store()  // save_store 已返回 Bool 不再抛（P0 路由加固一致化）
    @lib.obj([("id", @lib.str_json(id)), ("status", @lib.str_json("stored"))])
  } else if name == "check_terms" {
    engine_ref.val.check_terms(arg_str(args, "source"), arg_str(args, "target"))
  } else if name == "concordance" {
    engine_ref.val.concordance(arg_str(args, "term"), arg_int(args, "k", 3))
  } else if name == "qe_auto" {
    engine_ref.val.qe_auto(arg_str(args, "source"), arg_str(args, "target"), arg_num(args, "match_rate", 0.0))
  } else if name == "predict" {
    engine_ref.val.predict(arg_int(args, "k", 3))
  } else if name == "observe" {
    let mid = engine_ref.val.observe(arg_str(args, "text"), arg_str(args, "mtype"))
    let _ = save_store()  // save_store 已返回 Bool 不再抛（P0 路由加固一致化）
    @lib.obj([("mid", @lib.str_json(mid)), ("status", @lib.str_json("learned"))])
  } else if name == "recall" {
    @lib.arr_json(engine_ref.val.recall(arg_str(args, "query"), arg_int(args, "k", 5)))
  } else if name == "explain" {
    engine_ref.val.explain_card(arg_str(args, "mid"))
  } else if name == "reward" {
    let ok = engine_ref.val.reward(arg_str(args, "mid"), arg_num(args, "score", 1.0))
    if ok {
      let _ = save_store()  // save_store 已返回 Bool 不再抛（P0 路由加固一致化）
      @lib.obj([("ok", true.to_json())])
    } else {
      @lib.obj([("ok", false.to_json()), ("error", @lib.str_json("unknown mid"))])
    }
  } else if name == "consolidate" {
    let result = engine_ref.val.consolidate(arg_bool(args, "prune", true))
    let _ = save_store()  // save_store 已返回 Bool 不再抛（P0 路由加固一致化）
    result
  } else if name == "tm_count" {
    @lib.obj([("tm_count", @lib.num_json(tm_count().to_double()))])
  } else if name == "ping" {
    @lib.obj([("status", @lib.str_json("ok"))])
  } else if name == "retrieve_prompt" {
    engine_ref.val.retrieve_for_prompt(arg_str(args, "query"), arg_int(args, "k", 3), arg_num(args, "threshold", 0.70))
  } else if name == "bleu" {
    @lib.obj([("bleu", @lib.num_json(@lib.bleu_score(arg_str(args, "ref"), arg_str(args, "hyp"))))])
  } else if name == "chrf" {
    @lib.obj([("chrf", @lib.num_json(@lib.chrf_score(arg_str(args, "ref"), arg_str(args, "hyp"))))])
  } else if name == "style_check" {
    engine_ref.val.style_check(arg_str(args, "text"))
  } else if name == "style_report" {
    engine_ref.val.style_report(arg_str(args, "text"))
  } else if name == "back_align" {
    engine_ref.val.back_align(arg_str(args, "source"), arg_str(args, "target"))
  } else if name == "term_conflicts" {
    engine_ref.val.term_conflicts()
  } else if name == "fed_export" {
    engine_ref.val.fed_export()
  } else if name == "fed_import" {
    engine_ref.val.fed_import(arg_int(args, "added", 0), arg_int(args, "updated", 0))
    let _ = save_store()  // save_store 已返回 Bool 不再抛（P0 路由加固一致化）
    @lib.obj([("status", @lib.str_json("imported"))])
  } else if name == "distill_inject" {
    let table : Map[String, Double] = Map::new()
    let mut ignored = 0
    let tbl = args
    match tbl {
      Json::Object(o) =>
        match o.get("table") {
          Some(Json::Object(t)) =>
            for k, v in t.iter2() {
              match v {
                Json::Number(n, ..) => table.set(k, n)
                // P4：累计被跳过的非数值字段（client 传 {"role":"foo"} 等 schema 错误时可感知）
                _ => ignored = ignored + 1
              }
            }
          _ => ()
        }
      _ => ()
    }
    engine_ref.val.inject_distillation(table)
    let _ = save_store()  // save_store 已返回 Bool 不再抛（P0 路由加固一致化）
    @lib.obj([
      ("status", @lib.str_json("injected")),
      ("keys", @lib.num_json(table.size().to_double())),
      ("ignored", @lib.num_json(ignored.to_double())),
    ])
  } else if name == "active_learning" {
    @lib.arr_json(engine_ref.val.active_learning_candidates(arg_int(args, "k", 5)))
  } else if name == "mqm_re_annotate" {
    engine_ref.val.mqm_re_annotate(arg_str(args, "source"), arg_str(args, "target"), arg_num(args, "match_rate", 0.0))
  } else {
    @lib.obj([("error", @lib.str_json("unknown tool"))])
  }
}

// ===== 各 method 处理 =====
//   P3 修正：serverInfo.version 从 "2.0.0" 改为与 moon.mod / @lib.api_version / /api/health 一致的 "0.1.0"。
//   "2.0" 是产品家族名（译脉·先知 2.0），不是 MCP server 的 semver；spec 2025-11-25 期望 serverInfo.version
//   反映实现版本，与 api_version 同步便于 MCP client 端做 capability 匹配与日志去重。
fn handle_initialize(id : Json) -> Json {
  rpc_result(id, @lib.obj([
    ("protocolVersion", @lib.str_json("2025-11-25")),
    ("capabilities", @lib.obj([("tools", @lib.obj([("listChanged", false.to_json())]))])),
    ("serverInfo", @lib.obj([
      ("name", @lib.str_json("yimai-prophecy")),
      ("version", @lib.str_json(@lib.api_version)),
    ])),
  ]))
}

fn handle_tools_list(id : Json) -> Json {
  rpc_result(id, @lib.obj([("tools", all_tools())]))
}

async fn handle_tools_call(id : Json, params : Json) -> Json {
  let name = arg_str(params, "name")
  let args = match params {
    Json::Object(o) =>
      match o.get("arguments") {
        Some(a) => a
        None => @lib.obj([])
      }
    _ => @lib.obj([])
  }
  if not(is_known_tool(name)) {
    // P1: unknown tool 属 method-level 而非 param-level，业界惯例 -32601 (Method not found)
    return rpc_error(id, -32601, "Unknown tool: " + name)
  }
  let result = try { invoke_tool(name, args) } catch {
    err => @lib.obj([("error", @lib.str_json(err.to_string()))])
  }
  // 引擎异常（含 error 字段）标记 isError
  let is_err = match result {
    Json::Object(o) =>
      match o.get("error") {
        Some(_) => true
        None => false
      }
    _ => false
  }
  let content = @lib.arr_json([@lib.obj([
    ("type", @lib.str_json("text")),
    ("text", @lib.str_json(result.stringify())),
  ])])
  rpc_result(id, @lib.obj([
    ("content", content),
    ("isError", is_err.to_json()),
  ]))
}

// JSON-RPC 分派（None = 无响应体，如 notifications/initialized）
async fn dispatch(method : String, id : Json, params : Json) -> Option[Json] {
  // P1: 框架级校验 — 缺 method 应回 -32600 (Invalid Request) 而非 -32601 (Method not found)
  if method == "" {
    return Some(rpc_error(id, -32600, "Invalid Request: missing method"))
  }
  if method == "initialize" {
    Some(handle_initialize(id))
  } else if method == "tools/list" {
    Some(handle_tools_list(id))
  } else if method == "tools/call" {
    Some(handle_tools_call(id, params))
  } else if method == "ping" {
    Some(rpc_result(id, @lib.obj([])))
  } else if method == "notifications/initialized" {
    None
  } else if method.has_prefix("notifications/") {
    // P4：JSON-RPC 2.0 规范 — notification 类（无 id）一律不回包。任意外发 notifications/cancelled、
    //   notifications/progress 等不应触发 -32601。原代码只显式豁免 notifications/initialized，
    //   其余走 -32601 违反 spec。客户端可能据此重连或退避，造成不稳。
    None
  } else {
    Some(rpc_error(id, -32601, "Method not found: " + method))
  }
}

// ===== /mcp 端点入口 =====
async fn handle_mcp(req : @http.Request, body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  if req.meth != @http.RequestMethod::Post {
    // 最小实现：GET 等非 POST 回 405（MCP Streamable HTTP 可选 GET/SSE，最小版不做）
    conn.send_response(405, "Method Not Allowed")
    conn.end_response()
    return
  }
  let parsed = read_json_body(body)
  match parsed {
    Some(req_json) => {
      let method = extract_method(req_json)
      let id = extract_id(req_json)
      let params = extract_params(req_json)
      match dispatch(method, id, params) {
        Some(resp) => send_json(conn, 200, resp.stringify())
        None => {
          // notification：无响应体，回 202
          conn.send_response(202, "Accepted")
          conn.end_response()
        }
      }
    }
    // P1: 改用 JSON-RPC -32700 (Parse error) 标准错误体替代裸字符串
    //   spec 2025-11-25 + JSON-RPC 2.0 标准；客户端可正确解析
    None => send_json(conn, 400, rpc_error(@lib.str_json(""), -32700, "Parse error: invalid JSON").stringify())
  }
}
