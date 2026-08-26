// routes_handlers_metrics.mbt —— 8 个度量 / 风格 / 对齐类 REST handler
// =====================================================================
// P11-C 拆自 routes.mbt：8 个 handler 按 REST 端点语义层次分组到「度量」
//   类。包含 BLEU/chrF 评测、风格检查、回译对齐、术语冲突、引擎指标、
//   服务健康等 8 个端点。
//
// 包含的端点（与 @lib.routes_meta 同步）：
//   bleu / chrf / style_check / style_report / back_align / term_conflicts
//   metrics / health
//
// 本文件还包含 json_str / json_int / json_num 3 个 JSON 字段提取 helper
// （仅 handle_metrics 用到，物理隔离到本文件以让 diff 范围最小）。

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

// POST /api/bleu  {"ref","hyp"}  BLEU-4 评测
async fn handle_bleu(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  with_json_object(body, conn, async fn(o, conn) {
    // P1 加固：ref/hyp ≤ MAX_TEXT_CHARS（句子级评测，超长请分句）
    if !(validate_text_field_or_send(conn, o, "ref")) { return }
    if !(validate_text_field_or_send(conn, o, "hyp")) { return }
    let ref_str = json_str(o, "ref")
    let hyp_str = json_str(o, "hyp")
    let score = @lib.bleu_score(ref_str, hyp_str)
    // P1: 用 @lib.obj 替代字符串拼接（防止 score.to_string() 边界行为差异）
    send_json(conn, 200, @lib.obj([("bleu", @lib.num_json(score))]).stringify())
  })
}

// POST /api/chrf  {"ref","hyp"}  chrF++ 评测
async fn handle_chrf(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：ref/hyp ≤ MAX_TEXT_CHARS
      if !(validate_text_field_or_send(conn, o, "ref")) { return }
      if !(validate_text_field_or_send(conn, o, "hyp")) { return }
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
      if !(validate_text_field_or_send(conn, o, "text")) { return }
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
          if !(validate_text_field_or_send(conn, o, "text")) { return }
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
      if !(validate_text_field_or_send(conn, o, "source")) { return }
      if !(validate_text_field_or_send(conn, o, "target")) { return }
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
async fn handle_term_conflicts(_body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let result = engine_ref.val.term_conflicts()
  send_json(conn, 200, result.stringify())
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
