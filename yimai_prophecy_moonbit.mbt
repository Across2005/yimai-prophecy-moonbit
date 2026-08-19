// Main package file for your library code.
// Put public APIs and shared helpers here.
// Keep blocks small and focused for easy refactors.

// ---------------------------------------------------------------------------
// P1 路由层契约 —— 单一来源（routes / cmd/service 都参考此清单）
// ---------------------------------------------------------------------------
//
// routes_meta 形式 (path, handler_name)：
//   - path: HTTP 路径（已剥离 query string）
//   - handler_name: 路由表中的简短名，cmd/service 内部 `match` 后派发到对应 handle_xxx
// 契约不变：每个 path 的入参 / 出参 / 错误码与 24 端点初版一致；新增 metrics / health
// 走同一清单路径。
//
// cmd/service/moon.pkg 是 native-only，wasm-gc 测试只能验证「meta 结构」而非 handler 实际行为。
// 因此 routes_meta 与 error_codes 抽到根包，测试通过同一包内可见性验证。
//
// 同步点：改 routes 时，cmd/service/routes.mbt 的 `let routes` 需同步（两者都为 26 项）。
//        L19 测试断言 24 端点 + 2 新增 全部在表内。
// ---------------------------------------------------------------------------

// 路由表：27 项（24 既有 + metrics + health + mqm_re_annotate）。handler_name 为 handler 内部短名。
//   P5 增量：mqm_re_annotate 加入（Google 2025-10-28 re-annotation 论文对齐）
pub let routes_meta : Array[(String, String)] = [
  ("/api/ping", "ping"),
  ("/api/tm_count", "tm_count"),
  ("/api/fuzzy_match", "fuzzy_match"),
  ("/api/add_tm", "add_tm"),
  ("/api/check_terms", "check_terms"),
  ("/api/concordance", "concordance"),
  ("/api/qe_auto", "qe_auto"),
  ("/api/predict", "predict"),
  ("/api/observe", "observe"),
  ("/api/recall", "recall"),
  ("/api/explain", "explain"),
  ("/api/reward", "reward"),
  ("/api/consolidate", "consolidate"),
  ("/api/retrieve_prompt", "retrieve_prompt"),
  ("/api/bleu", "bleu"),
  ("/api/chrf", "chrf"),
  ("/api/style_check", "style_check"),
  ("/api/style_report", "style_report"),
  ("/api/back_align", "back_align"),
  ("/api/term_conflicts", "term_conflicts"),
  ("/api/fed_export", "fed_export"),
  ("/api/fed_import", "fed_import"),
  ("/api/distill_inject", "distill_inject"),
  ("/api/active_learning", "active_learning"),
  ("/api/metrics", "metrics"),
  ("/api/health", "health"),
  ("/api/mqm_re_annotate", "mqm_re_annotate"),
]

// 错误码稳定表：send_error 全部用此六码（机器可读）；L22 测试断言覆盖。
//   400 invalid_json     JSON 解析失败（read_json_or_400 走 400 分支）
//   413 body_too_large   request body 超过 MAX_BODY_BYTES
//   400 missing_field    必填字段缺失（add_tm.src / observe.text）
//   404 unknown_mid      reward 收到不存在的 mid
//   500 internal_error   handler 顶层 panic 兜底
//   500 align_failed     back_align 引擎返回非 Object（异常路径）
//   P3 增量：原表只列 3 码，实际 7 个 send_error 调用点用到 6 码（routes.mbt L85/87/153/293/389/452/590）。
//   补全后与 send_error 实际出口严格一一对应；新增 send_error 调用点必须同步此表 + L22 测试。
pub let error_codes : Array[String] = [
  "invalid_json",
  "body_too_large",
  "missing_field",
  "unknown_mid",
  "internal_error",
  "align_failed",
]

// API 版本（moon.mod 同步）：/api/health 透出
pub let api_version : String = "0.1.0"

// 24 既有端点的路径集合（L19 用：断言 routes_meta 至少覆盖这些 baseline）
pub let baseline_paths : Array[String] = [
  "/api/ping", "/api/tm_count", "/api/fuzzy_match", "/api/add_tm",
  "/api/check_terms", "/api/concordance", "/api/qe_auto", "/api/predict",
  "/api/observe", "/api/recall", "/api/explain", "/api/reward",
  "/api/consolidate", "/api/retrieve_prompt", "/api/bleu", "/api/chrf",
  "/api/style_check", "/api/style_report", "/api/back_align",
  "/api/term_conflicts", "/api/fed_export", "/api/fed_import",
  "/api/distill_inject", "/api/active_learning",
]
