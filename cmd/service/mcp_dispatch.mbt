// mcp_dispatch.mbt —— 25 MCP tools 的实际执行派发
// =====================================================================
// P11-B 拆自 mcp.mbt：invoke_tool 集中 25 个 else if 分支，物理隔离以让
//   工具实现改动 review 范围最小（增删 1 个 tool 不再触发整 440 行 diff）。
//
// 写操作（add_tm / observe / reward / consolidate / fed_import / distill_inject）
// 后调 save_store() 原子落盘。async 是因为 save_store 是 async fn。

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
      @lib.obj([("ok", @json.to_json(true))])
    } else {
      @lib.obj([("ok", @json.to_json(false)), ("error", @lib.str_json("unknown mid"))])
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
    let table : Map[String, Double] = Map([])
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
      ("keys", @lib.num_json(table.length().to_double())),
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
