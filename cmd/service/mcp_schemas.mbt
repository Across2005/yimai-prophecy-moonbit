// mcp_schemas.mbt —— 25 MCP tools 的 JSON Schema 定义
// =====================================================================
// P11-B 拆自 mcp.mbt：25 个 tool_def 调用集中在 all_tools()，物理隔离以让
//   schema 改动 review 范围最小（变更 1 个 tool 不再触发整 440 行 diff）。
//
// 25 个 tool 与 cmd/service/routes.mbt 的 27 REST 端点能力一一对应（REST 比
// MCP 多 2 个：metrics / health，service 内部用）。

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
