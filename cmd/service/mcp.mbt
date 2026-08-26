// mcp.mbt —— /mcp 端点：MCP (Model Context Protocol) Server 变体
// spec 2025-11-25 · Streamable HTTP 传输（挂 8787 服务，POST 单 JSON-RPC 消息，application/json 响应）
// 25 个引擎能力映射为 MCP tools，供 Claude Desktop / 通用 MCP 客户端消费。
// 注：MoonBit Json 为 FFI 类型，构造一律走 @lib.obj/str_json/num_json/arr_json。
//
// P11-B 拆分：本文件仅保留 JSON-RPC 入口 + method 处理 + tool 名/必填字段校验
//   4 个主题内聚单元。25 个 tool 的 schema 定义在 mcp_schemas.mbt；
//   25 个 tool 的派发实现在 mcp_dispatch.mbt；JSON 字段提取 / schema property 构造
//   在 mcp_args.mbt。同包 cmd/service 零 import 改动。

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

// 工具名清单（25 项；与 mcp_schemas.mbt::all_tools 内的 tool_def name 必须同步）。
//   P4 抽出来为顶层 let，便于 is_known_tool 用 Array::contains 替代手写循环，
//   减少一处 24 字符串表（all_tools 仍硬编码，因 tool_def 的 name/desc/props 三元组不便拆分）。
//   P5 增量：mqm_re_annotate 加入（25 项）。
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

// P6 加固：根据 tool schema 的 required 数组校验必填参数，返回缺失字段列表。
fn check_required_fields(name : String, args : Json) -> Array[String] {
  let required = match name {
    "fuzzy_match" => ["query"]
    "add_tm" => ["src", "tgt"]
    "check_terms" => ["source", "target"]
    "concordance" => ["term"]
    "qe_auto" => ["source", "target"]
    "observe" => ["text"]
    "recall" => ["query"]
    "explain" => ["mid"]
    "reward" => ["mid"]
    "retrieve_prompt" => ["query"]
    "bleu" => ["ref", "hyp"]
    "chrf" => ["ref", "hyp"]
    "style_check" => ["text"]
    "back_align" => ["source", "target"]
    "mqm_re_annotate" => ["source", "target"]
    _ => []
  }
  let missing : Array[String] = []
  let arg_obj = match args {
    Json::Object(o) => o
    _ => Map::from_iter(([] : Array[(String, Json)]).iter())
  }
  for field in required {
    match arg_obj.get(field) {
      Some(_) => ()
      None => missing.push(field)
    }
  }
  missing
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
  if !(is_known_tool(name)) {
    // P6 修正：tool name 是 tools/call 的参数，不存在时应返回 -32602 (Invalid params)。
    return rpc_error(id, -32602, "Unknown tool: " + name)
  }
  // P6 加固：按 tool schema 的 required 字段校验必填参数
  let missing = check_required_fields(name, args)
  if missing.length() > 0 {
    return rpc_error(id, -32602, "Invalid params: missing '" + missing[0] + "'")
  }
  // P1 修复：异常路径走 JSON-RPC 标准错误码 -32603 (Internal error)，
  //   替代原"异常字符串 stringify 塞进 result.content.text"的反模式。
  //   之前 RPC 层 panic 会被吞成业务错误返回，丢失堆栈与 code。
  //   现版本：invoke_tool panic 直接走 rpc_error(-32603)，调用方可据此判断
  //   "服务端崩溃" vs "业务参数错误 (-32602)"，区分明确。
  let result = try { Ok(invoke_tool(name, args)) } catch {
    err => Err(err.to_string())
  }
  match result {
    Ok(r) => {
      // 引擎返回的业务错误（含 {"error":"..."} 字段）通过 content 包装并标记 isError
      let is_err = match r {
        Json::Object(o) =>
          match o.get("error") {
            Some(_) => true
            None => false
          }
        _ => false
      }
      let content = @lib.arr_json([@lib.obj([
        ("type", @lib.str_json("text")),
        ("text", @lib.str_json(r.stringify())),
      ])])
      rpc_result(id, @lib.obj([
        ("content", content),
        ("isError", is_err.to_json()),
      ]))
    }
    Err(_) =>
      // Internal error：invoke_tool 抛异常（引擎 panic / 不可恢复错误）
      // 错误信息脱敏（不暴露堆栈细节，仅保留错误摘要）；P8：panic_msg 本就未使用，改 `_` 消 unused 告警
      rpc_error(id, -32603, "Internal error: tool '" + name + "' execution failed")
  }
}

// JSON-RPC 分派（None = 无响应体，如 notifications/initialized）
//   P8：`method` 是 MoonBit 保留字（11 条 reserved_keyword 告警），参数改名 meth
//   （与 @http.Request.meth 命名一致）；JSON-RPC 线上的 "method" 字段名不受影响。
async fn dispatch(meth : String, id : Json, params : Json) -> Option[Json] {
  // P1: 框架级校验 — 缺 method 应回 -32600 (Invalid Request) 而非 -32601 (Method not found)
  if meth == "" {
    return Some(rpc_error(id, -32600, "Invalid Request: missing method"))
  }
  if meth == "initialize" {
    Some(handle_initialize(id))
  } else if meth == "tools/list" {
    Some(handle_tools_list(id))
  } else if meth == "tools/call" {
    Some(handle_tools_call(id, params))
  } else if meth == "ping" {
    Some(rpc_result(id, @lib.obj([])))
  } else if meth == "notifications/initialized" {
    None
  } else if meth.has_prefix("notifications/") {
    // P4：JSON-RPC 2.0 规范 — notification 类（无 id）一律不回包。任意外发 notifications/cancelled、
    //   notifications/progress 等不应触发 -32601。原代码只显式豁免 notifications/initialized，
    //   其余走 -32601 违反 spec。客户端可能据此重连或退避，造成不稳。
    None
  } else {
    Some(rpc_error(id, -32601, "Method not found: " + meth))
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
  // P6 加固：MCP 端点使用 JSON-RPC 错误格式返回 body 过大；Content-Length 缺失或无法解析时放行。
  match req.headers.get("Content-Length") {
    Some(cl) => {
      let len = parse_nonnegative_int(cl)
      if len > MAX_BODY_CHARS {
        send_json(conn, 413, rpc_error(@lib.str_json(""), -32700, "Parse error: request body too large").stringify())
        return
      }
    }
    None => ()
  }
  let parsed = read_json_body(body)
  match parsed {
    Ok(req_json) => {
      let meth = extract_method(req_json)
      let id = extract_id(req_json)
      let params = extract_params(req_json)
      match dispatch(meth, id, params) {
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
    //   P6: 用 Result 枚举区分过大/非法 JSON（替代已删除的 last_body_oversize 全局 ref）
    Err(TooLarge) =>
      send_json(conn, 413, rpc_error(@lib.str_json(""), -32700, "Parse error: request body too large").stringify())
    Err(InvalidJson) =>
      send_json(conn, 400, rpc_error(@lib.str_json(""), -32700, "Parse error: invalid JSON").stringify())
  }
}
