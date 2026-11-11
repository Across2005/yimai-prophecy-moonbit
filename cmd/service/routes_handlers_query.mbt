// routes_handlers_query.mbt —— 12 个查询/记忆写入类 REST handler
// =====================================================================
// P11-C 拆自 routes.mbt：12 个 handler 按 REST 端点语义层次分组到「查询/记忆」
//   类。所有写操作（add_tm / observe / reward / consolidate / fed_import /
//   distill_inject）都在调 save_store() 原子落盘；读操作直接返 Json。
//
// 包含的端点（与 @lib.routes_meta 同步）：
//   fuzzy_match / add_tm / tm_count / check_terms / concordance / qe_auto
//   mqm_re_annotate / predict / observe / recall / explain / retrieve_prompt

// GET /api/tm_count
async fn handle_tm_count(conn : @http.ServerConnection) -> Unit {
  let c = tm_count()
  // P1: 用 @lib.obj 替代字符串拼接（保持响应字段顺序与稳定性）
  send_json(conn, 200, @lib.obj([("tm_count", @json.to_json(c))]).stringify())
}

// POST /api/fuzzy_match  {"query":"..","k":3,"threshold":0.5}
async fn handle_fuzzy_match(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  with_json_object(body, conn, async fn(o, conn) {
    // P1 加固：字段级范围校验（k ∈ [0,100], threshold ∈ [0,1]）
    if !(validate_text_field_or_send(conn, o, "query")) { return }
    if !(validate_int_field_or_send(conn, o, "k", 3)) { return }
    if !(validate_num_field_or_send(conn, o, "threshold", 0.70, 0.0, 1.0)) { return }
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
  })
}

// POST /api/add_tm  {"src":"..","tgt":".."}
async fn handle_add_tm(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  with_json_object(body, conn, async fn(o, conn) {
    // P1 加固：字段级长度校验（防 DoS：src 单字段 ≤ MAX_TEXT_CHARS）
    if !(validate_text_field_or_send(conn, o, "src")) { return }
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
  })
}

// POST /api/check_terms  {"source":"..","target":".."}  术语一致性校验（白盒返回违规）
async fn handle_check_terms(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：source/target ≤ MAX_TEXT_CHARS（check_terms 对两个翻译段做白盒校验）
      if !(validate_text_field_or_send(conn, o, "source")) { return }
      if !(validate_text_field_or_send(conn, o, "target")) { return }
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
      if !(validate_text_field_or_send(conn, o, "term")) { return }
      if !(validate_int_field_or_send(conn, o, "k", 3)) { return }
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
      if !(validate_text_field_or_send(conn, o, "source")) { return }
      if !(validate_text_field_or_send(conn, o, "target")) { return }
      if !(validate_num_field_or_send(conn, o, "match_rate", 0.0, 0.0, 1.0)) { return }
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
      if !(validate_text_field_or_send(conn, o, "source")) { return }
      if !(validate_text_field_or_send(conn, o, "target")) { return }
      if !(validate_num_field_or_send(conn, o, "match_rate", 0.0, 0.0, 1.0)) { return }
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

// POST /api/predict  {"k":3}  下一步预测（白盒：activation_path 证据链）
async fn handle_predict(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：k ∈ [0,100]（防 DoS：k=1e9 让排序浪费大量 CPU）
      if !(validate_int_field_or_send(conn, o, "k", 3)) { return }
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

// POST /api/observe  {"text":"..","mtype":"step"}  记录真实步骤（学习/转移/命中核算）→ 落盘
async fn handle_observe(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：text 必填 + ≤ MAX_TEXT_CHARS（防 DoS：超大 text 触发分词卡死）
      if !(validate_text_field_or_send(conn, o, "text")) { return }
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
      if !(validate_text_field_or_send(conn, o, "query")) { return }
      if !(validate_int_field_or_send(conn, o, "k", 5)) { return }
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
      if !(validate_text_field_or_send(conn, o, "mid")) { return }
      let mid = json_str(o, "mid")
      let result = engine_ref.val.explain_card(mid)
      send_json(conn, 200, result.stringify())
    }
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}

// POST /api/retrieve_prompt  {"query","k","threshold"}  TMPlm 三段式 prompt 上下文
async fn handle_retrieve_prompt(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：query ≤ MAX_TEXT_CHARS；k ∈ [0,100]；threshold ∈ [0,1]
      if !(validate_text_field_or_send(conn, o, "query")) { return }
      if !(validate_int_field_or_send(conn, o, "k", 3)) { return }
      if !(validate_num_field_or_send(conn, o, "threshold", 0.70, 0.0, 1.0)) { return }
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
