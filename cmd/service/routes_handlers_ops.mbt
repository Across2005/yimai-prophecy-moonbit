// routes_handlers_ops.mbt —— 6 个运维类 REST handler（写操作/落盘）
// =====================================================================
// P11-C 拆自 routes.mbt：6 个 handler 按 REST 端点语义层次分组到「运维」
//   类。所有写操作都调 save_store() 原子落盘。
//
// 包含的端点（与 @lib.routes_meta 同步）：
//   reward / consolidate / fed_export / fed_import / distill_inject / active_learning

// POST /api/reward  {"mid":"..","score":1.0}  采纳/拒绝反馈 → predictive_value（闭环核心）
async fn handle_reward(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：mid 必填 + ≤ MAX_TEXT_CHARS；score ∈ [-1, 1]（引擎内部已 clamp，此处防 NaN/Inf）
      if !(validate_text_field_or_send(conn, o, "mid")) { return }
      if !(validate_num_field_or_send(conn, o, "score", 1.0, -1.0, 1.0)) { return }
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
      //   P8：as_bool() 已废弃；本版本 Json 的 Bool 构造器已拆为 True/False 单例，
      //   按官方建议用 is True / is False 判别（语义不变：非 bool 一律 400）。
      let prune_field = o.get("prune")
      let prune = match prune_field {
        Some(v) =>
          if v is True {
            true
          } else if v is False {
            false
          } else {
            send_error(conn, 400, "field_type", "prune must be bool")
            return
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

// POST /api/fed_export  {}  联邦增量导出
async fn handle_fed_export(_body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let result = engine_ref.val.fed_export()
  send_json(conn, 200, result.stringify())
}

// POST /api/fed_import  {"added","updated"}  联邦增量导入（写操作落盘）
async fn handle_fed_import(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => {
      // P1 加固：added/updated ∈ [0, MAX_INT_K]（防 DoS：极大值刷统计）
      if !(validate_int_field_or_send(conn, o, "added", 0)) { return }
      if !(validate_int_field_or_send(conn, o, "updated", 0)) { return }
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
      let table : Map[String, Double] = Map([])
      match o.get("table") {
        Some(Json::Object(t)) =>
          // P1 加固：单 value 必为有限 Double（拒绝 NaN/Inf 污染领域偏置）
          for k, v in t.iter2() {
            match v {
              Json::Number(n, ..) =>
                if !(n.is_nan()) && !(n.is_inf()) {
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
        ("keys", table.length().to_json()),
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
      if !(validate_int_field_or_send(conn, o, "k", 5)) { return }
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
