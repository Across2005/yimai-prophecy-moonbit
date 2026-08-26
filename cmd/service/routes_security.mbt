// routes_security.mbt —— HTTP 路由层安全 helper（5 个内聚单元）
// =====================================================================
// P11-C 拆自 routes.mbt（747 → 5 文件拆分）：
//   - routes_security.mbt（本文件）：5 个 P9 收紧的安全 helper，主题内聚
//   - 同包 cmd/service 零 import 改动
//
// 5 个 helper 都围绕「拒绝非授权输入 / 输出」：
//   - is_safe_origin         P9 DNS 重绑定防护（Origin 头校验）
//   - is_loopback_hostport   P10 IPv6 [host]:port 解析修复
//   - is_safe_static_path    P4 静态文件防路径穿越
//   - parse_nonnegative_int  P6 Content-Length 防 Int 溢出
//   - content_length_too_large  P6 请求体大小预拒绝

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

// P9 安全加固 + P10 修订：DNS 重绑定防护（MCP 2025-11-25 Streamable HTTP 安全要求）
//   本地 MCP/REST server 必须校验 Origin，防止恶意网页借 DNS 重绑定访问 127.0.0.1:8787。
//   放行：无 Origin（curl / CLI / PowerShell Invoke-RestMethod 不发送）、null origin、
//   以及 host ∈ {127.0.0.1, localhost, [::1]} 的回环地址；其余一律拒绝（含 https://evil.com）。
//   注意：浏览器按真实页面 origin 发送 Origin，攻击者的跨站请求无法伪造为回环 origin，
//   故"回环 host 白名单"即可阻断 DNS 重绑定；端口对环路判定无关，不限制。
//
//   P10 修订：原版 IPv6 解析有 bug — 对 `http://[::1]:8787`：
//     `hostport.split(":")` 得 `["[", "", "1]", "8787"]`，`host = "["`，
//     `host.has_prefix("[::1]")` 恒 false，IPv6 回环被误拒。
//   修复：用 is_loopback_hostport 解析 IPv6 [host]:port 与 IPv4/hostname:port 两种格式。
fn is_safe_origin(req : @http.Request) -> Bool {
  match req.headers.get("Origin") {
    None => true  // 无 Origin：本地 CLI / curl，放行
    Some(origin) => {
      if origin == "null" { true }  // 部分 fetch 上下文 origin 为 null，放行
      else {
        let lower = origin.to_lower()
        if !(lower.has_prefix("http://") || lower.has_prefix("https://")) { return false }
        let rest = if lower.has_prefix("https://") { lower[8:].to_owned() } else { lower[7:].to_owned() }
        let hostport = rest.split("/").to_array()[0].to_owned()  // 剥离 path
        is_loopback_hostport(hostport)
      }
    }
  }
}

// P10: 判定 hostport 是否回环
//   IPv6 形式 [host]:port  → 拆 [ 与 ] 取内部 host 比 "::1"
//   IPv4 / 主机名 :port  →  split(":") 第一个段比 "127.0.0.1" / "localhost"
//   空 / 仅端口 / 畸形 [xxx → false
fn is_loopback_hostport(hostport : String) -> Bool {
  if hostport.length() == 0 { return false }
  if hostport[0] == '[' {
    // IPv6 形式 — 找配对的 ']'，取内部内容
    let chars = hostport.iter().to_array()
    let mut end = -1
    for i = 0; i < chars.length(); i = i + 1 {
      if chars[i] == ']' { end = i; break }
    }
    if end <= 0 { return false }  // 缺 ']' 或 '[]' 空内容
    let inner = hostport[1:end].to_owned()
    inner == "::1"
  } else {
    // IPv4 / 主机名 :port
    let host = hostport.split(":").to_array()[0]
    host == "127.0.0.1" || host == "localhost"
  }
}

// 判断静态文件请求路径是否安全：拒绝绝对路径、反斜杠、空字节、父目录引用及空路径
fn is_safe_static_path(rel : String) -> Bool {
  if rel == "" { return false }
  // 拒绝绝对路径 / 驱动器前缀 / 前导 slash，防止越出 WEB_ROOT
  if rel.has_prefix("/") || rel.has_prefix("\\") { return false }
  if @lib.str_contains(rel, ":") { return false }
  // 拒绝父目录引用与反斜杠（反斜杠在某些 FS 上等价于斜杠）
  if @lib.str_contains(rel, "..") || @lib.str_contains(rel, "\\") { return false }
  // 拒绝空字节：URL 解码后不应出现控制字符
  if @lib.str_contains(rel, "\u0000") { return false }
  true
}
