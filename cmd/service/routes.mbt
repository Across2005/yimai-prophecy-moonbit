// routes.mbt —— HTTP 路由 + /api/* 端点实现
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

// 安全解析非负整数；失败返回 -1 表示无法解析（调用方可据此放行，由后续读取逻辑兜底）。
// P6 加固：Content-Length 超过 10 位必然已大于 MAX_BODY_CHARS，直接返回 MAX_BODY_CHARS+1 触发拒绝，
// 避免超长数字导致 Int 溢出后绕过大小检查。
fn parse_nonnegative_int(s : String) -> Int {
  if s == "" { return -1 }
  if s.length() > 10 { return MAX_BODY_CHARS + 1 }
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    } else {
      return -1
    }
  }
  n
}

// 根据 Content-Length 头判断请求体是否超过上限；缺失或无法解析时返回 false（由读取后校验兜底）
fn content_length_too_large(req : @http.Request) -> Bool {
  match req.headers.get("Content-Length") {
    Some(cl) => {
      let len = parse_nonnegative_int(cl)
      len > MAX_BODY_CHARS
    }
    None => false
  }
}

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

// 判断静态文件请求路径是否安全：拒绝绝对路径、反斜杠、空字节、父目录引用及空路径
fn is_safe_static_path(rel : String) -> Bool {
  if rel == "" { return false }
  // 拒绝绝对路径 / 驱动器前缀 / 前导 slash，防止越出 WEB_ROOT
  if rel.starts_with("/") || rel.starts_with("\\") { return false }
  if @lib.str_contains(rel, ":") { return false }
  // 拒绝父目录引用与反斜杠（反斜杠在某些 FS 上等价于斜杠）
  if @lib.str_contains(rel, "..") || @lib.str_contains(rel, "\\") { return false }
  // 拒绝空字节：URL 解码后不应出现控制字符
  if @lib.str_contains(rel, "\u0000") { return false }
  true
}

// 服务 web/ 目录下静态文件（防路径穿越：拒绝 .. 与反斜杠；先 percent-decode 防 %2e%2e 绕过）
async fn serve_static(path : String, conn : @http.ServerConnection) -> Unit {
  let rel_raw = if path == "/" || path == "/index.html" {
    "index.html"
  } else {
    path.substring(start=1, end=path.length())
  }
  // P4 安全加固：先 URL 解码再做".." / "\" 检查，阻止 %2e%2e%2f 等编码形式绕过。
  // decode_pct 仅做 %XX 单字节解码，不解析 '+' 也不做路径规范化，保守可控。
  let rel = @lib.decode_pct(rel_raw)
  if not(is_safe_static_path(rel)) {
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

// 从 JSON 对象取字符串字段
fn json_str(o : Map[String, Json], key : String) -> String {
  match o.get(key) {
    Some(Json::String(v)) => v
    _ => ""
  }
}

// 从 JSON 抽取 Int 字段（找不到/类型不符返 default）；用于 metrics/stats_view 聚合
fn json_int(j : Json, key : String, default : Int) -> Int {
  match j {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

// 从 JSON 抽取 Double 字段（找不到/类型不符返 default）
fn json_num(j : Json, key : String, default : Double) -> Double {
  match j {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::Number(n, ..)) => n
        _ => default
      }
    _ => default
  }
}

// POST /api/fuzzy_match  {"query":"..","k":3,"threshold":0.5}
async fn handle_fuzzy_match(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：字段级范围校验（k ∈ [0,100], threshold ∈ [0,1]）
      if not(validate_text_field_or_send(conn, o, "query")) { return }
      if not(validate_int_field_or_send(conn, o, "k", 3)) { return }
      if not(validate_num_field_or_send(conn, o, "threshold", 0.70, 0.0, 1.0)) { return }
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
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/add_tm  {"src":"..","tgt":".."}
async fn handle_add_tm(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：字段级长度校验（防 DoS：src 单字段 ≤ MAX_TEXT_CHARS）
      if not(validate_text_field_or_send(conn, o, "src")) { return }
      let src = json_str(o, "src")
      let tgt = json_str(o, "tgt")
      let id = engine_ref.val.add_tm(src, tgt)
      let saved = save_store()
      if !saved { println("save_store: 落盘失败但内存态已更新") }
      // P1: 用 @lib.obj 替代字符串拼接（防 JSON 注入：id 若含 " 会破坏响应）
      send_json(conn, 200, @lib.obj([
        ("id", @lib.str_json(id)),
        ("status", @lib.str_json("stored")),
      ]).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// GET /api/tm_count
async fn handle_tm_count(conn : @http.ServerConnection) -> Unit {
  let c = tm_count()
  // P1: 用 @lib.obj 替代字符串拼接（保持响应字段顺序与稳定性）
  send_json(conn, 200, @lib.obj([("tm_count", c.to_json())]).stringify())
}

// POST /api/check_terms  {"source":"..","target":".."}  术语一致性校验（白盒返回违规）
async fn handle_check_terms(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：source/target ≤ MAX_TEXT_CHARS（check_terms 对两个翻译段做白盒校验）
      if not(validate_text_field_or_send(conn, o, "source")) { return }
      if not(validate_text_field_or_send(conn, o, "target")) { return }
      let source = json_str(o, "source")
      let target = json_str(o, "target")
      let result = engine_ref.val.check_terms(source, target)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/concordance  {"term":"..","k":3}  含术语的 TM 段检索
async fn handle_concordance(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：term ≤ MAX_TEXT_CHARS；k ∈ [0,100]
      if not(validate_text_field_or_send(conn, o, "term")) { return }
      if not(validate_int_field_or_send(conn, o, "k", 3)) { return }
      let term = json_str(o, "term")
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 3
      }
      let result = engine_ref.val.concordance(term, k)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/qe_auto  {"source":"..","target":"..","match_rate":0.7}  自动 QE 评分
async fn handle_qe_auto(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：source/target ≤ MAX_TEXT_CHARS；match_rate ∈ [0,1]（NaN/负数会污染 QE）
      if not(validate_text_field_or_send(conn, o, "source")) { return }
      if not(validate_text_field_or_send(conn, o, "target")) { return }
      if not(validate_num_field_or_send(conn, o, "match_rate", 0.0, 0.0, 1.0)) { return }
      let source = json_str(o, "source")
      let target = json_str(o, "target")
      let mr = match o.get("match_rate") {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
      let result = engine_ref.val.qe_auto(source, target, mr)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/predict  {"k":3}  下一步预测（白盒：activation_path 证据链）
async fn handle_predict(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：k ∈ [0,100]（防 DoS：k=1e9 让排序浪费大量 CPU）
      if not(validate_int_field_or_send(conn, o, "k", 3)) { return }
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 3
      }
      let result = engine_ref.val.predict(k)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/mqm_re_annotate  {"source":"..","target":"..","match_rate":0.3}  MQM 二次标注
//   P5 增量（Google 2025-10-28 re-annotation 论文对齐）：
//   - 无 Critical 段时跳过二次审（re_annotated=false）
//   - 有 Critical 段时显式产出审计痕迹（re_annotated=true + critical_count + re_annotations 数组）
//   - 当前是 deterministic 自重审，未来可扩多标注员模型
async fn handle_mqm_re_annotate(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：source/target ≤ MAX_TEXT_CHARS；match_rate ∈ [0,1]
      if not(validate_text_field_or_send(conn, o, "source")) { return }
      if not(validate_text_field_or_send(conn, o, "target")) { return }
      if not(validate_num_field_or_send(conn, o, "match_rate", 0.0, 0.0, 1.0)) { return }
      let source = json_str(o, "source")
      let target = json_str(o, "target")
      let mr = match o.get("match_rate") {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
      let result = engine_ref.val.mqm_re_annotate(source, target, mr)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/observe  {"text":"..","mtype":"step"}  记录真实步骤（学习/转移/命中核算）→ 落盘
async fn handle_observe(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：text 必填 + ≤ MAX_TEXT_CHARS（防 DoS：超大 text 触发分词卡死）
      if not(validate_text_field_or_send(conn, o, "text")) { return }
      let text = json_str(o, "text")
      let mtype = json_str(o, "mtype")
      let mid = engine_ref.val.observe(text, mtype)
      let saved = save_store()
      if !saved { println("save_store: 落盘失败但内存态已更新") }
      // P1: 用 @lib.obj 替代字符串拼接（防 JSON 注入：mid 若含 " 会破坏响应）
      send_json(conn, 200, @lib.obj([
        ("mid", @lib.str_json(mid)),
        ("status", @lib.str_json("learned")),
      ]).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/recall  {"query":"..","k":5}  激活扩散语义召回
async fn handle_recall(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：query ≤ MAX_TEXT_CHARS；k ∈ [0,100]
      if not(validate_text_field_or_send(conn, o, "query")) { return }
      if not(validate_int_field_or_send(conn, o, "k", 5)) { return }
      let query = json_str(o, "query")
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 5
      }
      let result = engine_ref.val.recall(query, k)
      send_json(conn, 200, @lib.arr_json(result).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/explain  {"mid":".."}  白盒卡片（value_breakdown / activation_path / predicts_to）
async fn handle_explain(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：mid 必填 + ≤ 128 chars（mid 格式固定为 m<n>，限制 128 防 DoS）
      if not(validate_text_field_or_send(conn, o, "mid")) { return }
      let mid = json_str(o, "mid")
      let result = engine_ref.val.explain_card(mid)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/reward  {"mid":"..","score":1.0}  采纳/拒绝反馈 → predictive_value（闭环核心）
async fn handle_reward(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：mid 必填 + ≤ MAX_TEXT_CHARS；score ∈ [-1, 1]（引擎内部已 clamp，此处防 NaN/Inf）
      if not(validate_text_field_or_send(conn, o, "mid")) { return }
      if not(validate_num_field_or_send(conn, o, "score", 1.0, -1.0, 1.0)) { return }
      let mid = json_str(o, "mid")
      let score = match o.get("score") {
        Some(Json::Number(n, ..)) => n
        _ => 1.0
      }
      let ok = engine_ref.val.reward(mid, score)
      if ok {
        let saved = save_store()
        if !saved { println("save_store: 落盘失败但内存态已更新") }
        send_json(conn, 200, @lib.obj([("ok", true.to_json())]).stringify())
      } else {
        // P1: 改用 send_error 统一错误出口（其它 handler 已迁移）
        send_error(conn, 404, "unknown_mid", "unknown mid")
      }
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/consolidate  {"prune":true}  固化重放（价值重算 + 可选剪枝）
async fn handle_consolidate(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：prune 必须为 bool（拒绝字符串"false"绕过的歧义；原 as_bool 失败时 fallback string == "true"）
      //   严格化：必须是真正的 JSON bool；字符串/null/数字一律 400。
      let prune_field = o.get("prune")
      let prune = match prune_field {
        Some(v) =>
          match v.as_bool() {
            Some(b) => b
            None => {
              send_error(conn, 400, "field_type", "prune must be bool")
              return
            }
          }
        None => true
      }
      let result = engine_ref.val.consolidate(prune)
      let saved = save_store()
      if !saved { println("save_store: 落盘失败但内存态已更新") }
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// ===== 待办补齐端点（S4/M1/M2/M3/M5/FedAvg/蒸馏）=====

// POST /api/retrieve_prompt  {"query","k","threshold"}  TMPlm 三段式 prompt 上下文
async fn handle_retrieve_prompt(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：query ≤ MAX_TEXT_CHARS；k ∈ [0,100]；threshold ∈ [0,1]
      if not(validate_text_field_or_send(conn, o, "query")) { return }
      if not(validate_int_field_or_send(conn, o, "k", 3)) { return }
      if not(validate_num_field_or_send(conn, o, "threshold", 0.70, 0.0, 1.0)) { return }
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
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/bleu  {"ref","hyp"}  BLEU-4 评测
async fn handle_bleu(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：ref/hyp ≤ MAX_TEXT_CHARS（句子级评测，超长请分句）
      if not(validate_text_field_or_send(conn, o, "ref")) { return }
      if not(validate_text_field_or_send(conn, o, "hyp")) { return }
      let ref_str = json_str(o, "ref")
      let hyp_str = json_str(o, "hyp")
      let score = @lib.bleu_score(ref_str, hyp_str)
      // P1: 用 @lib.obj 替代字符串拼接（防止 score.to_string() 边界行为差异）
      send_json(conn, 200, @lib.obj([("bleu", @lib.num_json(score))]).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/chrf  {"ref","hyp"}  chrF++ 评测
async fn handle_chrf(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：ref/hyp ≤ MAX_TEXT_CHARS
      if not(validate_text_field_or_send(conn, o, "ref")) { return }
      if not(validate_text_field_or_send(conn, o, "hyp")) { return }
      let ref_str = json_str(o, "ref")
      let hyp_str = json_str(o, "hyp")
      let score = @lib.chrf_score(ref_str, hyp_str)
      // P1: 用 @lib.obj 替代字符串拼接
      send_json(conn, 200, @lib.obj([("chrf", @lib.num_json(score))]).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/style_check  {"text"}  风格一致性检查
async fn handle_style_check(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：text ≤ MAX_TEXT_CHARS
      if not(validate_text_field_or_send(conn, o, "text")) { return }
      let text = json_str(o, "text")
      let result = engine_ref.val.style_check(text)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/style_report  {"text"?}  风格一致报告（记忆库分布 + 新译文偏离建议）
async fn handle_style_report(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：text 为可选项，有则校验 ≤ MAX_TEXT_CHARS
      match o.get("text") {
        Some(Json::String(_)) =>
          if not(validate_text_field_or_send(conn, o, "text")) { return }
        _ => ()  // 缺省或非字符串均放行（原行为）
      }
      let text = json_str(o, "text")
      let result = engine_ref.val.style_report(text)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/back_align  {"source","target"}  回译 LCS 对齐（含字符级 ops 供热力图）
async fn handle_back_align(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：source/target ≤ MAX_TEXT_CHARS（双 LCS 算法 O(n·m)，超长易卡死）
      if not(validate_text_field_or_send(conn, o, "source")) { return }
      if not(validate_text_field_or_send(conn, o, "target")) { return }
      let source = json_str(o, "source")
      let target = json_str(o, "target")
      let result = engine_ref.val.back_align(source, target)
      match result {
        Json::Object(base) => {
          // 追加字符级编辑脚本 ops：[op,i,j]（0=对齐 1=删A 2=插B），供热力图逐字着色
          let ops_json : Array[Json] = []
          for op in @lib.align_diff(source, target) {
            match op {
              (k, i, j) => ops_json.push(@lib.arr_json([k.to_json(), i.to_json(), j.to_json()]))
            }
          }
          let score = match base.get("align_score") { Some(v) => v; None => @lib.num_json(0.0) }
          let matches = match base.get("match_chars") { Some(v) => v; None => @lib.num_json(0.0) }
          let mis = match base.get("misaligns") { Some(v) => v; None => @lib.arr_json([]) }
          send_json(
            conn,
            200,
            @lib.obj([
              ("align_score", score),
              ("match_chars", matches),
              ("misaligns", mis),
              ("ops", @lib.arr_json(ops_json)),
            ]).stringify(),
          )
        }
        _ => send_error(conn, 500, "align_failed", "align failed")
      }
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
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
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：added/updated ∈ [0, MAX_INT_K]（防 DoS：极大值刷统计）
      if not(validate_int_field_or_send(conn, o, "added", 0)) { return }
      if not(validate_int_field_or_send(conn, o, "updated", 0)) { return }
      let added = match o.get("added") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let updated = match o.get("updated") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      engine_ref.val.fed_import(added, updated)
      let saved = save_store()
      if !saved { println("save_store: 落盘失败但内存态已更新") }
      // P1: 用 @lib.obj 替代字符串拼接
      send_json(conn, 200, @lib.obj([("status", @lib.str_json("imported"))]).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/distill_inject  {"table":{"role":0.5}}  蒸馏表注入（写操作落盘）
async fn handle_distill_inject(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：table 必填 + 必须为 JSON object（防 null/array 注入歧义）
      match o.get("table") {
        Some(Json::Object(_)) => ()  // 通过
        Some(_) => {
          send_error(conn, 400, "field_type", "table must be JSON object")
          return
        }
        None => {
          send_error(conn, 400, "missing_field", "table required")
          return
        }
      }
      let table : Map[String, Double] = Map::new()
      match o.get("table") {
        Some(Json::Object(t)) =>
          // P1 加固：单 value 必为有限 Double（拒绝 NaN/Inf 污染领域偏置）
          for k, v in t.iter2() {
            match v {
              Json::Number(n) =>
                if not(@math.is_nan(n)) && not(@math.is_inf(n)) {
                  table.set(k, n)
                }
              _ => ()
            }
          }
        _ => ()
      }
      engine_ref.val.inject_distillation(table)
      let saved = save_store()
      if !saved { println("save_store: 落盘失败但内存态已更新") }
      // P1: BUG 修复：原版缺右括号 `}` 导致 JSON 非法；改用 @lib.obj
      send_json(conn, 200, @lib.obj([
        ("status", @lib.str_json("injected")),
        ("keys", table.size().to_json()),
      ]).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/active_learning  {"k":5}  主动学习推荐（uncertainty×0.6 + novelty×0.4，角色多样性）
async fn handle_active_learning(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：k ∈ [0,100]
      if not(validate_int_field_or_send(conn, o, "k", 5)) { return }
      let k = match o.get("k") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 5
      }
      let result = engine_ref.val.active_learning_candidates(k)
      send_json(conn, 200, @lib.arr_json(result).stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// ===== P1：可观测 / 详细健康（GET 即可，无 body）=====

// GET /api/metrics  引擎健康指标（observability）：合并 metrics() + stats_view()
//   metrics() 给「量」（tm/term/total_memories/term_coverage），stats_view() 给「质」（predict 闭环）
//   只读聚合，不影响引擎状态
async fn handle_metrics(conn : @http.ServerConnection) -> Unit {
  let m = engine_ref.val.metrics()
  let s = engine_ref.val.stats_view()
  send_json(
    conn,
    200,
    @lib.obj([
      ("tm_count", json_int(m, "tm_count", 0).to_json()),
      ("term_count", json_int(m, "term_count", 0).to_json()),
      ("total_memories", json_int(m, "total_memories", 0).to_json()),
      ("term_coverage", json_num(m, "term_coverage", 0.0).to_json()),
      ("predict_calls", json_int(s, "predict_calls", 0).to_json()),
      ("avg_predictive_value", json_num(s, "avg_predictive_value", 0.0).to_json()),
      ("hit_rate", json_num(s, "predict_hit_rate", 0.0).to_json()),
    ]).stringify(),
  )
}

// GET /api/health  比 /api/ping 详细：uptime / tm_count / last_save_status / version
//   status: "ok" 健康 / "degraded" 最近一次落盘失败
//   last_save_status: true=成功（含节流跳过）/ false=写盘失败
//   last_save_age_seconds: 距上次落盘秒数（-1=尚未发生）
async fn handle_health(conn : @http.ServerConnection) -> Unit {
  // UInt64 → Int：年份 2038 前时间戳远低于 Int 上界，安全
  let now = @env.now().to_int()
  let started = start_time_ms.val.to_int()
  let uptime_s = if started <= 0 { 0 } else { (now - started) / 1000 }
  let last_ok = last_save_ok.val
  let last_ts = last_save_ts.val.to_int()
  let age_s = if last_ts <= 0 { -1 } else { (now - last_ts) / 1000 }
  send_json(
    conn,
    200,
    @lib.obj([
      ("status", @lib.str_json(if last_ok { "ok" } else { "degraded" })),
      ("tm_count", tm_count().to_json()),
      ("uptime_seconds", uptime_s.to_json()),
      ("last_save_status", last_ok.to_json()),
      ("last_save_age_seconds", age_s.to_json()),
      ("version", @lib.str_json(@lib.api_version)),
    ]).stringify(),
  )
}
