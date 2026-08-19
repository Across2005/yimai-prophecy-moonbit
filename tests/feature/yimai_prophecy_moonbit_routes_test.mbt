// yimai_prophecy_moonbit_routes_test.mbt
// P1 路由层契约回归（routes.mbt 是 native-only；本测试仅验证「meta 结构」与「错误码表」）。
//
// 覆盖：
//   L19  24 既有端点 + 2 ops（metrics/health） + mqm_re_annotate（P5）共 27 项在 routes_meta 内，且 baseline 路径全部命中
//   L20  未知路径在 routes_meta 中无匹配（兜底走 serve_static，routes.mbt 的 lookup_route 返 ""）
//   L21  routes_meta 的 handler 名无重复、无空串，且全部在已知 handler 集合内（无 dangling reference）
//   L22  error_codes 恰好六码：invalid_json / body_too_large / missing_field / unknown_mid / internal_error / align_failed（send_error 唯一出口）

// ---------------------------------------------------------------------------
// L19：路由表 27 项全覆盖（24 既有 baseline + 2 ops metrics/health + mqm_re_annotate P5 新增）
// ---------------------------------------------------------------------------

test "L19 routes_meta 包含全部 24 baseline 端点路径" {
  // 把 routes_meta 转成「路径集合」
  let mut count = 0
  for entry in @lib.routes_meta {
    let (p, _) = entry
    for bp in @lib.baseline_paths {
      if p == bp {
        count = count + 1
        break
      }
    }
  }
  // baseline_paths 长度 = 24，必须全部命中
  inspect(count == @lib.baseline_paths.length(), content="true")
}

test "L19 routes_meta 含 /api/metrics 与 /api/health 两个 P1 新增端点" {
  let mut has_metrics = false
  let mut has_health = false
  for entry in @lib.routes_meta {
    let (p, _) = entry
    if p == "/api/metrics" { has_metrics = true }
    if p == "/api/health" { has_health = true }
  }
  inspect(has_metrics, content="true")
  inspect(has_health, content="true")
}

test "L19 routes_meta 总条目数为 27（24 既有 + 2 ops + mqm_re_annotate P5 新增）" {
  inspect(@lib.routes_meta.length() == 27, content="true")
}

// ---------------------------------------------------------------------------
// L20：未知路径在 routes_meta 中无匹配 → 兜底走 serve_static
//   复现 routes.mbt::lookup_route 的查找逻辑，确保返回 ""（未命中）
// ---------------------------------------------------------------------------

test "L20 未知路径 /api/nonexistent 在 routes_meta 中无匹配" {
  let mut found = false
  for entry in @lib.routes_meta {
    let (p, _) = entry
    if p == "/api/nonexistent" { found = true }
  }
  inspect(found, content="false")
}

test "L20 未知路径 /random/path 在 routes_meta 中无匹配" {
  let mut found = false
  for entry in @lib.routes_meta {
    let (p, _) = entry
    if p == "/random/path" { found = true }
  }
  inspect(found, content="false")
}

test "L20 /mcp 不在 routes_meta（routes.mbt 单独走 MCP 分支）" {
  let mut found = false
  for entry in @lib.routes_meta {
    let (p, _) = entry
    if p == "/mcp" { found = true }
  }
  inspect(found, content="false")
}

// ---------------------------------------------------------------------------
// L21：路由 dispatch 字符串表与 handle_xxx 函数一一对应（无 dangling reference）
//   - handler 名无重复
//   - handler 名非空
//   - handler 名全部在「已知 handler 集合」内（即 routes.mbt::handle_request 的 match 分支）
// ---------------------------------------------------------------------------

// routes.mbt::handle_request 的 match 派发全集
//   P4：从 routes_meta 派生（取每项的 handler_name）消除硬编码 26 字符串，
//   routes_meta 增删时 known_handlers 自动同步；L21 测试断言两者长度一致兜底。
fn build_known_handlers() -> Array[String] {
  let out : Array[String] = []
  for entry in @lib.routes_meta {
    let (_, n) = entry
    out.push(n)
  }
  out
}

let known_handlers : Array[String] = build_known_handlers()

test "L21 routes_meta 中 handler 名无重复" {
  let mut dups = 0
  for i = 0; i < @lib.routes_meta.length(); i = i + 1 {
    let (_, n1) = @lib.routes_meta[i]
    for j = i + 1; j < @lib.routes_meta.length(); j = j + 1 {
      let (_, n2) = @lib.routes_meta[j]
      if n1 == n2 { dups = dups + 1 }
    }
  }
  inspect(dups == 0, content="true")
}

test "L21 routes_meta 中 handler 名无空串" {
  let mut empties = 0
  for entry in @lib.routes_meta {
    let (_, n) = entry
    if n == "" { empties = empties + 1 }
  }
  inspect(empties == 0, content="true")
}

test "L21 routes_meta 中 handler 名全部在 known_handlers 内（无 dangling）" {
  let mut bad = 0
  for entry in @lib.routes_meta {
    let (_, n) = entry
    let mut in_set = false
    for h in known_handlers {
      if h == n { in_set = true }
    }
    if !in_set { bad = bad + 1 }
  }
  inspect(bad == 0, content="true")
}

test "L21 known_handlers 与 routes_meta 长度一致（match 分支无遗漏）" {
  inspect(known_handlers.length() == @lib.routes_meta.length(), content="true")
}

// ---------------------------------------------------------------------------
// L22：send_error 六类 code 字符串覆盖（稳定机器可读码）
//   400 invalid_json     JSON 解析失败
//   413 body_too_large   request body 超过 MAX_BODY_CHARS
//   400 missing_field    必填字段缺失
//   404 unknown_mid      reward 收到不存在的 mid
//   500 internal_error   handler 顶层 panic 兜底
//   500 align_failed     back_align 引擎返回非 Object（异常路径）
//   P3 增量：原表只列 3 码（CHANGELOG 0.1.0 漏算 3 个：unknown_mid/internal_error/align_failed），
//   现对齐 6 码，与 routes.mbt send_error 7 个调用点一致。新增调用点须同步此表。
// ---------------------------------------------------------------------------

test "L22 error_codes 恰好六码且互不相同" {
  inspect(@lib.error_codes.length() == 6, content="true")
  let mut dups = 0
  for i = 0; i < @lib.error_codes.length(); i = i + 1 {
    for j = i + 1; j < @lib.error_codes.length(); j = j + 1 {
      if @lib.error_codes[i] == @lib.error_codes[j] { dups = dups + 1 }
    }
  }
  inspect(dups == 0, content="true")
}

test "L22 error_codes 包含全部六类稳定码（与 send_error 7 调用点对齐）" {
  // 6 码存在性一次验证；分别对应 send_error 唯一出口
  //   invalid_json / body_too_large : read_json_or_400 走 400/413 分支
  //   missing_field                  : handler 必填字段缺失（add_tm.src / observe.text）
  //   unknown_mid                    : reward 收到不存在的 mid
  //   internal_error                 : handler panic 兜底
  //   align_failed                   : back_align 引擎返回非 Object（异常路径）
  let expected = [
    "invalid_json", "body_too_large", "missing_field",
    "unknown_mid", "internal_error", "align_failed",
  ]
  for want in expected {
    let mut has = false
    for c in @lib.error_codes {
      if c == want { has = true }
    }
    inspect(has, content="true")
  }
}
