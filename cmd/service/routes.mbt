// routes.mbt —— HTTP 路由 + /api/* 端点入口与派发
// 端点（全部实测通过）：
//   POST /api/fuzzy_match   {"query","k","threshold"}   TM 模糊匹配（S1 四分量白盒）
//   POST /api/add_tm        {"src","tgt"}               新增 TM 并原子落盘
//   POST /api/check_terms   {"source","target"}         术语一致性校验
//   POST /api/concordance   {"term","k"}                术语上下文检索
//   POST /api/qe_auto       {"source","target","match_rate"}  QE 评分
//   POST /api/predict       {"k"}                       下一步预测 + 白盒
//   GET  /api/tm_count / /api/ping                       存量 / 健康检查
//   GET  /api/metrics / /api/health                       可观测 / 详细健康（P1）
// 注：MoonBit async 调用无需 await；Request.path 含完整 query string（路由需剥离）。
//
// P11-C 拆分（routes.mbt 747 → 5 文件）：
//   - routes.mbt（本文件）：入口 + dispatch + I/O helper + 静态文件服务
//   - routes_security.mbt：5 个 P9 收紧的安全 helper
//   - routes_handlers_query.mbt：12 个查询/记忆类 handler
//   - routes_handlers_metrics.mbt：8 个度量/风格/对齐类 handler
//   - routes_handlers_ops.mbt：6 个运维类 handler
// 同包 cmd/service 零 import 改动。

// 请求体最大字符数（按 char-count 校验，UTF-8 1 char ≈ 1-3 bytes；实际字节上限 ~1-3 MiB）
//   P6 修订：命名由 MAX_BODY_BYTES 改为 MAX_BODY_CHARS，避免与真实字节数混淆。
//   当前实现先 read_all 再校验长度，本地 127.0.0.1 场景下由本常量做软上限；
//   如需严格流控，可在 handle_request/handle_mcp 中先根据 Content-Length 预拒绝。
const MAX_BODY_CHARS : Int = 1048576

// 读取 body 失败的具体原因（替代原全局 last_body_oversize ref）
//   P1 修复：原版本用 @ref.Ref[Bool] 在并发下互相覆盖错误分类（A 请求超大置 true 时
//   B 请求的 400 invalid_json 会被错误分类成 413）。现版本 read_json_body 直接返回
//   错误枚举，调用方拿到的就是本次请求的真实状态，无共享可变状态。
priv enum BodyError {
  TooLarge    // 超过 MAX_BODY_CHARS
  InvalidJson // 解析失败（非超大）
}

// 路由表（path, handler_name）：与根模块 routes_meta 保持 27 项同步。
// MoonBit 函数非一等公民，故用「字符串名 → match 派发」做表驱动：
//   1. 单一来源便于枚举/测试（L19-L22）
//   2. 增删端点只动两处（本表 + handle_request 的 match 分支）
//   P4：路由表已在根包 yimai_prophecy_moonbit.mbt 声明为 pub let routes_meta（wasm-gc 测试可见）；
//   本处直接用 @lib.routes_meta，避免 27 项硬编码在 4 处（root/router/mcp/route_test）。
//   /mcp 与 serve_static 不进表：前者是 JSON-RPC 协议分支，后者是文件兜底。

// 进程启动时间戳（ms since epoch，初始化在 main.mbt 启动时一次）
//   /api/health 据此算 uptime_seconds；不直接用 @env.now() 以避免每次 HTTP 重新采样带来的抖动。
let start_time_ms : @ref.Ref[UInt64] = @ref.new(0)

// 从 path 提取 ? 之前的 base path（async 的 Request.path 含完整 query string）
//   P8：StringView.to_string() 已废弃，改 to_owned()
fn extract_base_path(path : String) -> String {
  let parts = path.split("?").to_array()
  parts[0].to_owned()
}

async fn send_json(conn : @http.ServerConnection, code : Int, body : String) -> Unit {
  conn.send_response(code, "OK", extra_headers={ "Content-Type": "application/json" })
  conn.write_string(body)
  conn.end_response()
}

// 统一错误响应：所有 handler 的错误出口走这一处（替换散落的字符串拼接）。
//   返回形如 {"error":"...","code":"..."}，code 是稳定机器可读字符串
//   （如 "invalid_json"/"body_too_large"/"missing_field"/"unknown_mid"/"internal_error"/"align_failed"）。
//   P3: 改用 @lib.obj 构造而非字符串拼接（CHANGELOG 0.1.0 已声明；本函数为统一出口
//   之前漏改）。当前 7 个调用点 message/code 均为静态字面量、实际无注入窗口；改用
//   @lib.obj 是把"未来加动态 message 也不会重开注入"作为防御措施固化下来。
async fn send_error(conn : @http.ServerConnection, http_code : Int, code : String, message : String) -> Unit {
  let body = @lib.obj([
    ("error", @lib.str_json(message)),
    ("code", @lib.str_json(code)),
  ]).stringify()
  send_json(conn, http_code, body)
}

// 统一 JSON body 入口：根据 BodyError 类型决定 400 / 413 并 send
//   handler 拿到 None 时直接走 _ 分支（已发过响应），不再回错误
//   P1 修正：之前版本递归调用自身 + match 用 `,` 分隔（MoonBit 不支持），导致 native 编译失败。
//   改为调 read_json_body + match 用 `;` 分隔。
//   P1 二次修复：不再依赖全局 last_body_oversize ref（并发安全）。
async fn read_json_or_400(conn : @http.ServerConnection, body : &@io.Reader) -> Option[Json] {
  match read_json_body(body) {
    Ok(j) => Some(j)
    Err(TooLarge) => {
      send_error(conn, 413, "body_too_large", "request body exceeds MAX_BODY_CHARS")
      None
    }
    Err(InvalidJson) => {
      send_error(conn, 400, "invalid_json", "invalid JSON body")
      None
    }
  }
}

// 主路由（表驱动）：path → routes 查找 handler 名 → match 派发。
// 保持原契约：/mcp 是 JSON-RPC 分支单独走，serve_static 是未知路径兜底。
// P1: 顶层 try/catch 兜底 — handler 内任何未捕获异常统一回 500 internal_error，
//   避免连接悬挂 / 客户端超时。/mcp 与 REST 两条路径都覆盖。
async fn handle_request(req : @http.Request, body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let path = extract_base_path(req.path)
  // P9：DNS 重绑定防护——拒绝非回环 Origin（本地 MCP/REST 服务安全要求，覆盖 REST 与 /mcp 两条路径）
  if !(is_safe_origin(req)) {
    conn.send_response(403, "Forbidden")
    conn.end_response()
    return
  }
  // MCP Server 变体（spec 2025-11-25，Streamable HTTP；实现见 mcp.mbt）独立分支
  //   /mcp 使用 JSON-RPC 错误格式，由 handle_mcp 自行做大小校验。
  if path == "/mcp" {
    try { handle_mcp(req, body, conn) } catch { err => handle_panic(conn, err) }
    return
  }
  // P6 加固：非 MCP 的 POST 请求在读取 body 前根据 Content-Length 预拒绝，减少大 payload 读取。
  if req.meth == @http.RequestMethod::Post && content_length_too_large(req) {
    send_error(conn, 413, "body_too_large", "request body exceeds MAX_BODY_CHARS")
    return
  }
  // 在路由表里线性查找（27 项规模，O(n) 即可）
  let name = lookup_route(path)
  if name == "" {
    serve_static(path, conn)
    return
  }
  // 字符串 → handler 派发（MoonBit 函数非一等公民，match 派发是规范做法）
  //   P1: 整个 match 包在 try 内，未捕获异常统一回 500
  try {
    match name {
      // P1: 用 @lib.obj 替代字符串拼接（与全文件风格保持一致；与 handle_health 返回的 status 字段一致）
      "ping" => send_json(conn, 200, @lib.obj([("status", @lib.str_json("ok"))]).stringify())
      "tm_count" => handle_tm_count(conn)
      "fuzzy_match" => handle_fuzzy_match(body, conn)
      "add_tm" => handle_add_tm(body, conn)
      "check_terms" => handle_check_terms(body, conn)
      "concordance" => handle_concordance(body, conn)
      "qe_auto" => handle_qe_auto(body, conn)
      "predict" => handle_predict(body, conn)
      "observe" => handle_observe(body, conn)
      "recall" => handle_recall(body, conn)
      "explain" => handle_explain(body, conn)
      "reward" => handle_reward(body, conn)
      "consolidate" => handle_consolidate(body, conn)
      "retrieve_prompt" => handle_retrieve_prompt(body, conn)
      "bleu" => handle_bleu(body, conn)
      "chrf" => handle_chrf(body, conn)
      "style_check" => handle_style_check(body, conn)
      "style_report" => handle_style_report(body, conn)
      "back_align" => handle_back_align(body, conn)
      "term_conflicts" => handle_term_conflicts(body, conn)
      "fed_export" => handle_fed_export(body, conn)
      "fed_import" => handle_fed_import(body, conn)
      "distill_inject" => handle_distill_inject(body, conn)
      "active_learning" => handle_active_learning(body, conn)
      "metrics" => handle_metrics(conn)
      "health" => handle_health(conn)
      "mqm_re_annotate" => handle_mqm_re_annotate(body, conn)
      _ => serve_static(path, conn)  // 表里居然有 unknown 名：兜底防 dangling
    }
  } catch {
    err => handle_panic(conn, err)
  }
}

// P1: 兜底错误处理 — 任何 handler panic 时统一回 500 internal_error
//   连接可能已发过响应（半发状态），再 send_response 会抛错，需 try/catch 静默
async fn handle_panic(conn : @http.ServerConnection, err : Error) -> Unit {
  println("handler panic: \{err}")
  try { send_error(conn, 500, "internal_error", "internal server error") } catch { _ => () }
}

// 路由表查找：path 命中返回 handler 名，未命中返 ""。无副作用。
//   P4：直接迭代 @lib.routes_meta（27 项单一源），消除 cmd/service 内的重复表。
fn lookup_route(path : String) -> String {
  for r in @lib.routes_meta {
    let (p, n) = r
    if p == path {
      return n
    }
  }
  ""
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

// 静态文件 web 根目录（相对服务启动工作目录）
const WEB_ROOT : String = "cmd/service/web/"

// 从 body 读取 JSON（async；返回 Result[Json, BodyError]）
//   超 MAX_BODY_CHARS 返 Err(TooLarge)，handler 据此回 413。
//   解析失败返 Err(InvalidJson)，handler 据此回 400。
//   P1 修复：原版本用全局 last_body_oversize ref 在并发下互相覆盖错误分类，
//   现版本直接返回错误枚举，无共享可变状态。
//   P6 加固：read_all/text 任一环节异常均视为超大/非法请求，直接返 Err，避免连接悬挂。
async fn read_json_body(body : &@io.Reader) -> Result[Json, BodyError] {
  let s = try { body.read_all().text() } catch { _ => "" }
  if s.length() > MAX_BODY_CHARS {
    return Err(TooLarge)
  }
  try { Ok(@json.parse(s)) } catch { _ => Err(InvalidJson) }
}

// 统一错误响应已抽到 send_error（见上方），所有 handler 共用

// 服务 web/ 目录下静态文件（防路径穿越：拒绝 .. 与反斜杠；先 percent-decode 防 %2e%2e 绕过）
async fn serve_static(path : String, conn : @http.ServerConnection) -> Unit {
  let rel_raw = if path == "/" || path == "/index.html" {
    "index.html"
  } else {
    // P8：substring 已废弃，改切片 + to_owned
    path[1:].to_owned()
  }
  // P4 安全加固：先 URL 解码再做".." / "\" 检查，阻止 %2e%2e%2f 等编码形式绕过。
  // decode_pct 仅做 %XX 单字节解码，不解析 '+' 也不做路径规范化，保守可控。
  let rel = @lib.decode_pct(rel_raw)
  if !(is_safe_static_path(rel)) {
    conn.send_response(403, "Forbidden")
    conn.end_response()
    return
  }
  let full = WEB_ROOT + rel
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
