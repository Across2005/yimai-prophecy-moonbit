// util.mbt —— 译脉·先知 2.0 (MoonBit) 编码层 + JSON 辅助
// 零依赖：仅 moonbitlang/core/json 与 moonbitlang/core/math
// 对应 D1–D8 规范的分词 / TF 向量 / 余弦与共享 JSON 构造逻辑。

// ---- 算法常量（HEBB_LR 等权重参数在 engine.mbt 定义，按 D1–D8 规范设定）----

// 长文兜底：分词 / 字符 N-gram 输出的最大 token 数。
// 防恶意/错误输入（如 5MB 文档）撑爆内存；CJK 因 bigram 折算会接近 2× char 数。
// 经验值：1 万汉字 ≈ 2 万 token，远低于工业 NLU（512 token 上限），留 4× 余量。
const MAX_TOKENS : Int = 20000

// 停用词：中文功能词 + 英文停用词（按 D1–D8 分词规范设定）
// P0 性能：数组线性扫描 → Map 集合 O(1) 查询（yimai_tokenize 对每个 token 调一次，
//   58 词 × 每 token 一次字符串比较是分词热点）。R15：仅 contains 查询、不迭代，顺序无关。
let stop_map : Map[String, Bool] = Map([
  ("的", true), ("了", true), ("和", true), ("是", true), ("在", true), ("我", true),
  ("你", true), ("他", true), ("她", true), ("它", true), ("们", true), ("这", true),
  ("那", true), ("有", true), ("就", true), ("不", true), ("也", true), ("都", true),
  ("一个", true), ("上", true), ("下", true), ("中", true), ("与", true), ("及", true),
  ("或", true), ("把", true), ("被", true), ("给", true), ("对", true), ("从", true),
  ("到", true), ("等", true), ("用", true), ("将", true), ("要", true), ("会", true),
  ("能", true), ("可以", true), ("通过", true), ("根据", true), ("按照", true), ("关于", true),
  ("进行", true), ("以及", true), ("a", true), ("an", true), ("the", true), ("of", true),
  ("to", true), ("and", true), ("or", true), ("in", true), ("on", true), ("for", true),
  ("with", true), ("is", true), ("are", true), ("be", true),
])

fn is_stop(t : String) -> Bool {
  stop_map.contains(t)
}

// ---------------------------------------------------------------------------
// 字符串辅助
// ---------------------------------------------------------------------------

// 仅对 ASCII 字母做小写（中文等不受影响）
fn to_lower_ascii(s : String) -> String {
  let b = StringBuilder()
  for c in s.iter() {
    if c >= 'A' && c <= 'Z' {
      b.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

// URL 百分号解码（仅解码 %XX 形式；保留 '+' 为字面，不做 form-encoding 转换）。
//   用途：serve_static 在路径安全检查前先解码，让 %2e%2e%2f 不能绕过 ".." 字符串检查。
//   非 ASCII 字符按 UTF-8 多字节原样透传；不识别的 % 序列保留原样（保守策略）。
//   零依赖；不调 @fs / @io，纯字符串处理。
pub fn decode_pct(s : String) -> String {
  let b = StringBuilder()
  let chars = s.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let cur = chars[i]
    if cur == '%' && i + 2 < n {
      // 尝试解码 %XX
      let d1 = hex_nibble_char(chars[i + 1])
      let d2 = hex_nibble_char(chars[i + 2])
      match (d1, d2) {
        (Some(n1), Some(n2)) => {
          b.write_char((n1 * 16 + n2).unsafe_to_char())
          i = i + 3
          continue
        }
        _ => ()
      }
    }
    b.write_char(cur)
    i = i + 1
  }
  b.to_string()
}

// 单个十六进制字符 → 0..15；非 hex 返回 None
fn hex_nibble_char(c : Char) -> Option[Int] {
  let v = c.to_int()
  if v >= 0x30 && v <= 0x39 { Some(v - 0x30) }                    // 0-9
  else if v >= 0x41 && v <= 0x46 { Some(v - 0x41 + 10) }          // A-F
  else if v >= 0x61 && v <= 0x66 { Some(v - 0x61 + 10) }          // a-f
  else { None }
}


// WAL 字段转义：确保控制字符分隔符 \u0001 不会出现在字段内容中。
//   转义规则（双字符）：\u0002 -> \u0002\u0002, \u0001 -> \u0002\u0001
//   正常文本不会包含这两个控制字符，因此转义操作通常是零开销。
// 将 UTF-16 码点转换为 Char（控制字符走此路径）
fn u16_to_char(c : UInt16) -> Char {
  c.to_int().unsafe_to_char()
}

pub fn wal_escape_field(s : String) -> String {
  let b = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = u16_to_char(s[i])
    if c == '\u0002' {
      b.write_char('\u0002')
      b.write_char('\u0002')
    } else if c == '\u0001' {
      b.write_char('\u0002')
      b.write_char('\u0001')
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

// WAL 字段反转义：与 wal_escape_field 配对。
pub fn wal_unescape_field(s : String) -> String {
  let b = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let c = u16_to_char(s[i])
    if c == '\u0002' && i + 1 < s.length() {
      let next = u16_to_char(s[i + 1])
      if next == '\u0002' {
        b.write_char('\u0002')
        i = i + 2
      } else if next == '\u0001' {
        b.write_char('\u0001')
        i = i + 2
      } else {
        b.write_char(c)
        i = i + 1
      }
    } else {
      b.write_char(c)
      i = i + 1
    }
  }
  b.to_string()
}

// 概念抽象·角色抽取：取文本前 4 字作为粗略类别键（跨主题稳定）
// 注意：须对短文本做长度钳制，否则 text[:4] 在 length<4 时抛异常
pub fn role_of(text : String) -> String {
  let n = text.length()
  if n <= 4 {
    text
  } else {
    (text[:4]).to_owned()
  }
}

// 多粒度角色：前二 / 前四(保留，B2 冷启动依赖) / 前后各二
// 返回所有可用粒度键，供 role_index / role_trans / D8 回退统一使用
pub fn roles_of(text : String) -> Array[String] {
  let n = text.length()
  let out : Array[String] = []
  if n >= 2 {
    out.push(text[:2].to_owned())
    if n >= 4 {
      out.push(role_of(text))
      out.push(text[:2].to_owned() + text[(n - 2):].to_owned())
    }
  }
  out
}

// ---------------------------------------------------------------------------
// 编码层：tokenize -> tf_vector -> cosine
// ---------------------------------------------------------------------------

// 分词：ASCII [a-z0-9_]+ 段 + CJK 单字与相邻二元组；小写并去停用词。
// 对应 D1–D8 规范的正则分词 + 中文 unigram/bigram 展开。
pub fn yimai_tokenize(text : String) -> Array[String] {
  let lower = to_lower_ascii(text)
  let toks : Array[String] = []
  let mut lat = StringBuilder()
  let mut lat_len = 0
  let mut prev_cjk = ""
  // 长文兜底：超 MAX_TOKENS 即截断（CJK 算单/双字均计入）；截断后剩余字符不再展开，
  // 残留 lat 段也丢弃（语义已不完整，多一字少一字不影响 fuzzy/Hit 评估）。
  let mut tok_count = 0
  let mut truncated = false
  for c in lower.iter() {
    if tok_count >= MAX_TOKENS {
      truncated = true
      break
    }
    let code = c.to_int()
    let is_lat = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'
    if is_lat {
      lat.write_char(c)
      lat_len = lat_len + 1
    } else {
      if lat_len > 0 {
        toks.push(lat.to_string())
        tok_count = tok_count + 1
        lat = StringBuilder()
        lat_len = 0
      }
      if code >= 0x4E00 && code <= 0x9FFF {
        let s = c.to_string()
        toks.push(s)
        tok_count = tok_count + 1
        if tok_count < MAX_TOKENS && prev_cjk != "" {
          toks.push(prev_cjk + s)
          tok_count = tok_count + 1
        }
        prev_cjk = s
      } else {
        prev_cjk = ""
      }
    }
  }
  if lat_len > 0 && tok_count < MAX_TOKENS {
    toks.push(lat.to_string())
    tok_count = tok_count + 1
  }
  // 截断标记：调用方可经外部状态检测（fuzzy_match 内部不计；本函数只管分词语义闭合）
  let _ = truncated
  let out : Array[String] = []
  for t in toks {
    if !is_stop(t) {
      out.push(t)
    }
  }
  out
}

// 数字/单位抽取（数字守门依赖）：
//   匹配模式：十进制 / 浮点（不接单位字母，数字守门只关心「数字是否被保留」）。
//   用途：qe_score 数字一致性维度 + mqm_tags numeric_consistency 标签。
//   设计取舍：纯字符扫描，零正则依赖；千分位逗号不在 v1 范围（避免 "1,000" 误吞），下版按需扩展。
//   顺序：先按出现位置输出（确定性）；同数字多次出现计多次（计数交给调用方按 Map 累加）。
//   v1 不接单位：避免 "3.7V" / "100℃" 因带单位而不等于 "3.7" / "100"，让数字一致性集合运算简单可靠；
//                单位一致性作为下个 MQM 标签（unit_consistency）单独跑。
pub fn numeric_tokens(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  let mut buf_has_digit = false
  let mut buf_has_dot = false
  let flush = () => {
    if buf_has_digit {
      out.push(buf.to_string())
    }
    buf = StringBuilder()
    buf_has_digit = false
    buf_has_dot = false
  }
  for c in text.iter() {
    let is_digit = c >= '0' && c <= '9'
    let is_dot = c == '.'
    if is_digit {
      buf.write_char(c)
      buf_has_digit = true
    } else if is_dot && !buf_has_dot && buf_has_digit {
      // 浮点：仅当之前已有数字时认作小数点（避免 "abc." 被吞）
      buf.write_char(c)
      buf_has_dot = true
    } else {
      // 任何非数字/非小数点都立即 flush（单位不带走，简化集合对比）
      flush()
    }
  }
  flush()
  out
}

// 长文分句（observe / fuzzy_match 长 query 拆分的底层工具）：
//   切分依据（优先级高→低）：换行 / 中文句号「。!?；」/ 英文 . ! ? ;
//   额外规则：每段超过 max_chars 时再按最近空格二次切；空段丢弃；顺序稳定。
//   用途：调用方拿到 segments 数组后逐段 observe / fuzzy_match，避免长文单点稀释信号。
//   不破坏任何现有 API；P0 范围内的「长文能力」落地方式。
pub fn split_into_segments(text : String, max_chars : Int) -> Array[String] {
  let out : Array[String] = []
  if text.length() == 0 {
    return out
  }
  let mut buf = StringBuilder()
  let flush_buf = () => {
    let s = buf.to_string()
    if s.length() > 0 {
      out.push(s)
    }
    buf = StringBuilder()
  }
  for c in text.iter() {
    let is_break =
      c == '\n' ||
      c == '。' ||
      c == '！' ||
      c == '？' ||
      c == ';' ||
      c == '；' ||
      c == '!' ||
      c == '?' ||
      c == '：'
    if is_break {
      flush_buf()
    } else if c == '.' {
      // 英文句号：v1 简化直接当 break；二级 max_chars 兜底（避免 "3.7" "U.S." 误切伤到下个 break 字符）
      flush_buf()
    } else {
      buf.write_char(c)
      // 超 max_chars 触发二级切（按空格或全角空格切）
      if buf.to_string().length() >= max_chars {
        let s = buf.to_string()
        // 收集 chars，找最近空格位置
        let chars : Array[Char] = []
        for cc in s.iter() {
          chars.push(cc)
        }
        let mut cut_idx = -1
        let mut i = chars.length() - 1
        while i >= 0 {
          if chars[i] == ' ' || chars[i] == '　' {
            cut_idx = i
            break
          }
          i = i - 1
        }
        if cut_idx > 0 {
          let head = StringBuilder()
          for j = 0; j < cut_idx; j = j + 1 {
            head.write_char(chars[j])
          }
          let tail = StringBuilder()
          for j = cut_idx + 1; j < chars.length(); j = j + 1 {
            tail.write_char(chars[j])
          }
          out.push(head.to_string())
          buf = StringBuilder()
          buf.write_string(tail.to_string())
        }
        // 找不到空格就不切（避免单词被腰斩），下个 break 字符再 flush
      }
    }
  }
  flush_buf()
  out
}

// TF 向量：term -> tf（词频 / 总词数）
fn tf_vector(tokens : Array[String]) -> Map[String, Double] {
  let c : Map[String, Int] = Map::from_iter(([] : Array[(String, Int)]).iter())
  for t in tokens {
    let v = match c.get(t) {
      Some(x) => x
      None => 0
    }
    c.set(t, v + 1)
  }
  let mut total = 0
  for _, v in c.iter2() {
    total = total + v
  }
  let n = if total == 0 { 1 } else { total }
  let out : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  for t, v in c.iter2() {
    out.set(t, v.to_double() / n.to_double())
  }
  out
}

// 余弦相似度（在 TF 向量上计算）
fn cosine(a : Map[String, Double], b : Map[String, Double]) -> Double {
  if a.length() == 0 || b.length() == 0 {
    return 0.0
  }
  let mut num = 0.0
  for k, va in a.iter2() {
    match b.get(k) {
      Some(vb) => num = num + va * vb
      None => ()
    }
  }
  if num == 0.0 {
    return 0.0
  }
  let mut na2 = 0.0
  for _, v in a.iter2() {
    na2 = na2 + v * v
  }
  let mut nb2 = 0.0
  for _, v in b.iter2() {
    nb2 = nb2 + v * v
  }
  let na = na2.sqrt()
  let nb = nb2.sqrt()
  if na == 0.0 || nb == 0.0 {
    return 0.0
  }
  num / (na * nb)
}

fn clamp01(x : Double) -> Double {
  if x < 0.0 {
    0.0
  } else if x > 1.0 {
    1.0
  } else {
    x
  }
}

// 四舍五入到 4 位小数（用于展示）
fn r4(x : Double) -> Double {
  @math.round(x * 10000.0) / 10000.0
}

// Array[String] 是否包含 s
fn arr_contains(arr : Array[String], s : String) -> Bool {
  for x in arr {
    if x == s {
      return true
    }
  }
  false
}

// 对齐长度上限：单串字符数与动态规划表总 cell 数双限制，防止恶意长输入 OOM/CPU 耗尽
const MAX_ALIGN_CHARS : Int = 4096
const MAX_ALIGN_CELLS : Int = 4000000

// 双语字符级对齐（LCS 编辑脚本，等价于 Myers 差分的对齐结果）
// 返回对齐序列：op 0=对齐 1=删A 2=插B；i/j 为 A/B 中的字符下标
// 供术语/句段双语对齐热力图与对齐质量评估使用（纯算法，零依赖）
pub fn align_diff(a : String, b : String) -> Array[(Int, Int, Int)] {
  let n = a.length()
  let m = b.length()
  if n > MAX_ALIGN_CHARS || m > MAX_ALIGN_CHARS || n.to_double() * m.to_double() > MAX_ALIGN_CELLS.to_double() {
    return []
  }
  let dp : Array[Array[Int]] = []
  let mut i = 0
  while i <= n {
    let row : Array[Int] = []
    let mut j = 0
    while j <= m {
      row.push(0)
      j = j + 1
    }
    dp.push(row)
    i = i + 1
  }
  i = n - 1
  while i >= 0 {
    let mut j = m - 1
    while j >= 0 {
      if a[i] == b[j] {
        dp[i][j] = dp[i + 1][j + 1] + 1
      } else {
        let down = dp[i + 1][j]
        let right = dp[i][j + 1]
        dp[i][j] = if down > right { down } else { right }
      }
      j = j - 1
    }
    i = i - 1
  }
  let out : Array[(Int, Int, Int)] = []
  i = 0
  let mut k = 0
  while i < n && k < m {
    if a[i] == b[k] {
      out.push((0, i, k))
      i = i + 1
      k = k + 1
    } else if dp[i + 1][k] >= dp[i][k + 1] {
      out.push((1, i, k))
      i = i + 1
    } else {
      out.push((2, i, k))
      k = k + 1
    }
  }
  while i < n {
    out.push((1, i, k))
    i = i + 1
  }
  while k < m {
    out.push((2, i, k))
    k = k + 1
  }
  out
}

// ---- TM/TB 辅助：字符串相似度与极简 TBX 解析（零依赖） ----

pub fn levenshtein(a : String, b : String) -> Int {
  let n = a.length()
  let m = b.length()
  if n == 0 { return m }
  if m == 0 { return n }
  let mut prev : Array[Int] = []
  let mut i = 0
  while i <= m {
    prev.push(i)
    i = i + 1
  }
  let mut cur : Array[Int] = []
  i = 0
  while i <= m {
    cur.push(0)
    i = i + 1
  }
  let mut x = 0
  while x < n {
    cur[0] = x + 1
    let mut y = 0
    while y < m {
      let cost = if a[x] == b[y] { 0 } else { 1 }
      let del = cur[y] + 1
      let ins = prev[y + 1] + 1
      let sub = prev[y] + cost
      let e = if del < ins { del } else { ins }
      cur[y + 1] = if e < sub { e } else { sub }
      y = y + 1
    }
    let tmp = prev
    prev = cur
    cur = tmp
    x = x + 1
  }
  prev[m]
}

// ---- 跨语种判定（供 MQM 启发式屏蔽误报） ----

// 字符是否落在中日韩统一表意文字（CJK）主区间 / 扩展A / CJK 标点 / 全角区
fn is_cjk_char(c : Char) -> Bool {
  let cp = c.to_int()
  (cp >= 0x4E00 && cp <= 0x9FFF) ||
  (cp >= 0x3400 && cp <= 0x4DBF) ||
  (cp >= 0x3000 && cp <= 0x303F) ||
  (cp >= 0xFF00 && cp <= 0xFFEF)
}

// 文本主导文字：0=混合/无法判定, 1=CJK 主导, 2=拉丁主导
fn script_kind(s : String) -> Int {
  let mut cjk = 0
  let mut lat = 0
  for c in s.iter() {
    if is_cjk_char(c) {
      cjk = cjk + 1
    } else {
      let code = c.to_int()
      if (code >= 97 && code <= 122) || (code >= 65 && code <= 90) {
        lat = lat + 1
      }
    }
  }
  if cjk > lat && cjk > 0 {
    1
  } else if lat > cjk && lat > 0 {
    2
  } else {
    0
  }
}

// 跨语种判定：源/译文主导文字分属不同体系（如 英文→中文）时为真。
// 用于屏蔽 char_ratio / 长度比 这类仅同语种有效的启发式，避免跨语言误报。
fn cross_script(a : String, b : String) -> Bool {
  let ka = script_kind(a)
  let kb = script_kind(b)
  if ka == 0 || kb == 0 {
    false
  } else {
    ka != kb
  }
}

pub fn char_ratio(a : String, b : String) -> Double {
  let n = a.length()
  let m = b.length()
  if n == 0 && m == 0 { return 1.0 }
  let d = levenshtein(a, b).to_double()
  let mx = (if n > m { n } else { m }).to_double()
  1.0 - d / mx
}

// ---------------------------------------------------------------------------
// 检索强化（S1）：字符 n-gram / 集合 Dice / 首锚 token（零依赖）
// 用于 fuzzy_match 升级：2-gram 捕捉形态变体，Dice 对短文本比对 Jaccard 更宽容。
// ---------------------------------------------------------------------------

// 字符 n-gram 去重集合（不足 n 长度返回空集合；MoonBit 字符串按 UTF-16 码元索引，中文 BMP 一字符一码元）
// P1 性能：直接产出 Map（原 Array 版仅供 dice_coeff 内部去重用；现节点侧缓存 Map，
//   打分循环零分配）。key 首现顺序与原数组扫描顺序一致，仅做 contains 查询，R15 无关。
fn char_ngram_set(s : String, n : Int) -> Map[String, Bool] {
  let m : Map[String, Bool] = Map([])
  let len = s.length()
  if n <= 0 || len < n {
    return m
  }
  let mut i = 0
  while i + n <= len {
    m.set(s[i:i + n].to_owned(), true)
    i = i + 1
  }
  m
}

// token 去重集合（保持首现顺序；Map 插入序 = 首现序，与原 unique 数组序一致）
// P1 性能：直接产出 Map 供 dice_mm O(1) 集合运算；替代原 unique 数组（调用方均改为集合消费）。
fn to_set(arr : Array[String]) -> Map[String, Bool] {
  let m : Map[String, Bool] = Map([])
  for x in arr {
    m.set(x, true)
  }
  m
}

// 集合 Dice 系数 = 2|A∩B| / (|A|+|B|)，∈ [0,1]；短文本下比 Jaccard 更宽容
// P1 优化：双 Map 直传（查询侧每次 fuzzy_match 预建一次 + 节点侧 add_tm 时缓存），
//   打分循环内零 Map 分配（原 dice_coeff 每候选×每分项各建 2 个 Map）。
//   与旧版逐字节等价：交集计数只做 contains、长度取去重基数，不依赖迭代顺序，R15 零影响。
fn dice_mm(am : Map[String, Bool], bm : Map[String, Bool]) -> Double {
  if am.length() == 0 || bm.length() == 0 {
    return 0.0
  }
  let mut inter = 0
  for k, _ in am.iter2() {
    if bm.contains(k) {
      inter = inter + 1
    }
  }
  2.0 * inter.to_double() / (am.length().to_double() + bm.length().to_double())
}

// 查询首锚 token：取首个长度≥2 的 token（中文 bigram 或英文整词）；无则取首 token。
// 用于位置惩罚：锚 token 命中 TM 源文则加分（句首对齐权重）。
// P0 性能：接受调用方已分词的 toks（fuzzy_match 原先对同一 query 分词 3 次——
//   tf_vector / unique / first_anchor 各一次，现收敛为 1 次由调用方传入）。
fn first_anchor(toks : Array[String]) -> String {
  if toks.length() == 0 {
    return ""
  }
  for t in toks {
    if t.length() >= 2 {
      return t
    }
  }
  toks[0]
}

// 字符串是否以子串 p 开头（用于 xml:lang 前缀匹配，如 en-US/en/zh-CN/zh-Hans）
fn starts_with(s : String, p : String) -> Bool {
  match str_index(s, p, 0) {
    Some(i) => i == 0
    None => false
  }
}

pub fn str_contains(s : String, sub : String) -> Bool {
  match str_index(s, sub, 0) {
    Some(_) => true
    None => false
  }
}

fn split_on(s : String, sep : String) -> Array[String] {
  let parts : Array[String] = []
  let n = s.length()
  let m = sep.length()
  if m == 0 { parts.push(s); return parts }
  let mut i = 0
  let mut start = 0
  while i + m <= n {
    let mut j = 0
    let mut ok = true
    while j < m {
      if s[i + j] != sep[j] { ok = false; break }
      j = j + 1
    }
    if ok {
      parts.push(s[start:i].to_owned())
      i = i + m
      start = i
    } else {
      i = i + 1
    }
  }
  parts.push(s[start:n].to_owned())
  parts
}

fn str_index(s : String, sub : String, from : Int) -> Option[Int] {
  let n = s.length()
  let m = sub.length()
  let mut i = from
  while i + m <= n {
    let mut j = 0
    let mut ok = true
    while j < m {
      if s[i + j] != sub[j] { ok = false; break }
      j = j + 1
    }
    if ok { return Some(i) }
    i = i + 1
  }
  None
}

// 提取片段中首个 <tag>...</tag> 文本（容忍 <tag ...> 带属性）
fn first_tag_text(s : String, tag : String) -> String {
  let open = "<" + tag
  let close = "</" + tag + ">"
  let n = s.length()
  let m = open.length()
  let mut i = 0
  while i + m <= n {
    let mut j = 0
    let mut ok = true
    while j < m {
      if s[i + j] != open[j] { ok = false; break }
      j = j + 1
    }
    // 边界检查：标签名后必须是标签分隔符（> / 空白 / /），否则是 <termGrp> 之类的前缀误匹配
    if ok {
      let nx = if i + m < n { s[i + m] } else { '>' }
      if nx != '>' && nx != ' ' && nx != '\t' && nx != '\n' && nx != '/' { ok = false }
    }
    if ok {
      let mut k = i + m
      while k < n {
        if s[k] == '>' { break }
        k = k + 1
      }
      let cstart = k + 1
      match str_index(s, close, cstart) {
        Some(end) => return s[cstart:end].to_owned()
        None => return ""
      }
    }
    i = i + 1
  }
  ""
}

// 判断字符是否为 ASCII 字母/数字（用于拉丁文术语的词边界判定）
// 注：MoonBit 字符串索引返回 UInt16（UTF-16 码元），故参数与比较均用码点数值
fn is_ascii_alnum(c : UInt16) -> Bool {
  (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
}

// 提取片段中 langSet 的 xml:lang / lang 属性值（如 "en-US"）；无则返回 ""
fn lang_attr(s : String) -> String {
  match str_index(s, "xml:lang=\"", 0) {
    Some(i) => {
      let q = i + 10  // "xml:lang=\"" 共 10 字符，末位为前导引号，值自此开始
      match str_index(s, "\"", q) {
        Some(end) => return s[q:end].to_owned()
        None => return ""
      }
    }
    None => {
      match str_index(s, "lang=\"", 0) {
        Some(i) => {
          let q = i + 6  // "lang=\"" 共 6 字符，末位为前导引号，值自此开始
          match str_index(s, "\"", q) {
            Some(end) => return s[q:end].to_owned()
            None => return ""
          }
        }
        None => return ""
      }
    }
  }
}

// 术语命中：区分拉丁文（需词边界，避免 log⊂logical 误报）与 CJK（直接子串，CJK 无空格词边界）
fn term_hit(text : String, term : String) -> Bool {
  if term == "" { return false }
  let tl = term.length()
  let n = text.length()
  if n < tl { return false }
  let term_is_latin = is_ascii_alnum(term[0])
  if !term_is_latin {
    return str_contains(text, term)
  }
  let mut i = 0
  while i + tl <= n {
    if (text[i:i + tl]).to_owned() == term {
      let left_ok = if i == 0 { true } else { !is_ascii_alnum(text[i - 1]) }
      let right_ok = if i + tl >= n { true } else { !is_ascii_alnum(text[i + tl]) }
      if left_ok && right_ok { return true }
    }
    i = i + 1
  }
  false
}

// ---------------------------------------------------------------------------
// JSON 构造 / 访问辅助（复用 AL-world 风格，零依赖 moonbitlang/core/json）
// ---------------------------------------------------------------------------

pub fn str_json(s : String) -> Json {
  s.to_json()
}

pub fn num_json(d : Double) -> Json {
  d.to_json()
}

pub fn arr_json(items : Array[Json]) -> Json {
  items.to_json()
}

pub fn obj(pairs : Array[(String, Json)]) -> Json {
  Map::from_iter(pairs.iter()).to_json()
}

// 取对象字段为字符串，缺省 ""
fn get_str(j : Json, key : String) -> String {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

// 取对象字段为数字，缺省 0.0
fn get_num(j : Json, key : String) -> Double {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => n
        _ => 0.0
      }
    _ => 0.0
  }
}

// 取对象字段为对象（Json 对象），缺省空对象
fn get_obj(j : Json, key : String) -> Json {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(v) =>
          match v {
            Json::Object(_) => v
            _ => obj([])
          }
        _ => obj([])
      }
    _ => obj([])
  }
}

// 取对象字段为字符串数组
fn get_str_arr(j : Json, key : String) -> Array[String] {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Array(a)) =>
          a.filter_map(fn(t) {
            match t {
              Json::String(s) => Some(s)
              _ => None
            }
          })
        _ => []
      }
    _ => []
  }
}

// 取对象任意字段为原始 Json（缺省空对象），用于原样透传数组/嵌套结构
fn get_field(j : Json, key : String) -> Json {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(v) => v
        _ => obj([])
      }
    _ => obj([])
  }
}

// Map[String, Double] -> Json 对象
fn dmap_to_json(m : Map[String, Double]) -> Json {
  let o : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for k, v in m.iter2() {
    o.set(k, num_json(v))
  }
  o.to_json()
}

// Map[String, Int] -> Json 对象
fn imap_to_json(m : Map[String, Int]) -> Json {
  let o : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for k, v in m.iter2() {
    o.set(k, num_json(v.to_double()))
  }
  o.to_json()
}

// Map[String, String] -> Json 对象
fn smap_to_json(m : Map[String, String]) -> Json {
  let o : Map[String, Json] = Map::from_iter(([] : Array[(String, Json)]).iter())
  for k, v in m.iter2() {
    o.set(k, str_json(v))
  }
  o.to_json()
}

// Json 对象 -> Map[String, Double]
fn json_to_dmap(j : Json) -> Map[String, Double] {
  let out : Map[String, Double] = Map::from_iter(([] : Array[(String, Double)]).iter())
  match j {
    Json::Object(m) =>
      for k, v in m.iter2() {
        match v {
          Json::Number(n, ..) => out.set(k, n)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

// Json 对象 -> Map[String, String]
fn json_to_smap(j : Json) -> Map[String, String] {
  let out : Map[String, String] = Map::from_iter(([] : Array[(String, String)]).iter())
  match j {
    Json::Object(m) =>
      for k, v in m.iter2() {
        match v {
          Json::String(s) => out.set(k, s)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

// ===== S4 评测：BLEU / chrF++（零依赖自实现，确定性）=====

// n-gram 总数（滑动窗口计数 = len-n+1；不足 n 为 0）。
// P0 性能：与「物化整个 n-gram 列表再取 length」等价的 O(1) 算术式，去掉中间分配。
fn ngram_total(len : Int, n : Int) -> Int {
  if len >= n {
    len - n + 1
  } else {
    0
  }
}

// n-gram 计数（key = join with unit separator）
// P0 性能：直接滑动窗口 + StringBuilder 拼 key（原版先物化 Array[Array[String]]
//   再 O(n²) 字符串拼接）；key 逐字节等价、首现顺序不变，R15 确定性零影响。
fn ngram_counts(toks : Array[String], n : Int) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  let len = toks.length()
  let mut i = 0
  while i + n <= len {
    let b = StringBuilder()
    let mut j = 0
    while j < n {
      b.write_string(toks[i + j])
      b.write_string("\u001F")
      j = j + 1
    }
    let key = b.to_string()
    let cur = match counts.get(key) {
      Some(v) => v
      None => 0
    }
    counts.set(key, cur + 1)
    i = i + 1
  }
  counts
}

// BLEU-4：modified n-gram precision（clipped）+ Add-1 平滑 + BP（Papineni 2002 口径）
pub fn bleu_score(ref_text : String, hyp_text : String) -> Double {
  let ref_toks = yimai_tokenize(ref_text)
  let hyp_toks = yimai_tokenize(hyp_text)
  let r_len = ref_toks.length()
  let c_len = hyp_toks.length()
  if c_len == 0 {
    return 0.0
  }
  let bp = if c_len > r_len { 1.0 } else { @math.exp(1.0 - r_len.to_double() / c_len.to_double()) }
  let mut log_sum = 0.0
  let mut orders = 0.0
  let mut n = 1
  while n <= 4 {
    let hyp_counts = ngram_counts(hyp_toks, n)
    let ref_counts = ngram_counts(ref_toks, n)
    let mut clipped = 0.0
    for key, hyp_c in hyp_counts.iter2() {
      let ref_c = match ref_counts.get(key) {
        Some(v) => v
        None => 0
      }
      let m = if hyp_c < ref_c { hyp_c } else { ref_c }
      clipped = clipped + m.to_double()
    }
    let total = ngram_total(c_len, n).to_double()
    let p_n = if total > 0.0 { (clipped + 1.0) / (total + 1.0) } else { 1.0 }
    log_sum = log_sum + @math.ln(p_n)
    orders = orders + 1.0
    n = n + 1
  }
  let bleu = bp * @math.exp(log_sum / orders)
  r4(bleu)
}

// 字符串码点数组（跳过空白）
fn chars_of(s : String) -> Array[String] {
  let out : Array[String] = []
  for c in s.iter() {
    if c != ' ' && c != '\n' && c != '\t' && c != '\r' {
      out.push(c.to_string())
    }
  }
  out
}

// 字符 n-gram 计数
// P0 性能：StringBuilder 拼 key（原版 O(n²) 字符串复制拼接）；key 逐字节等价、首现顺序不变。
fn char_ngram_counts(chars : Array[String], n : Int) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  let len = chars.length()
  let mut i = 0
  while i + n <= len {
    let b = StringBuilder()
    let mut j = 0
    while j < n {
      b.write_string(chars[i + j])
      j = j + 1
    }
    let key = b.to_string()
    let cur = match counts.get(key) {
      Some(v) => v
      None => 0
    }
    counts.set(key, cur + 1)
    i = i + 1
  }
  counts
}

// chrF++：字符 1..6-gram + 词 1..2-gram，F-beta（beta=2）（Popović 2017 口径）
pub fn chrf_score(ref_text : String, hyp_text : String) -> Double {
  let ref_chars = chars_of(ref_text)
  let hyp_chars = chars_of(hyp_text)
  let ref_words = ref_text.split(" ").to_array().map(fn(x) { x.to_owned() })
  let hyp_words = hyp_text.split(" ").to_array().map(fn(x) { x.to_owned() })
  if ref_chars.length() == 0 && hyp_chars.length() == 0 {
    return 1.0
  }
  if ref_chars.length() == 0 || hyp_chars.length() == 0 {
    return 0.0
  }
  let mut sum_p = 0.0
  let mut sum_r = 0.0
  let mut orders = 0.0
  let mut n = 1
  while n <= 6 {
    let hc = char_ngram_counts(hyp_chars, n)
    let rc = char_ngram_counts(ref_chars, n)
    let mut match_n = 0.0
    for key, h in hc.iter2() {
      let r = match rc.get(key) {
        Some(v) => v
        None => 0
      }
      let m = if h < r { h } else { r }
      match_n = match_n + m.to_double()
    }
    let hyp_total = ngram_total(hyp_chars.length(), n).to_double()
    let ref_total = ngram_total(ref_chars.length(), n).to_double()
    sum_p = sum_p + (if hyp_total > 0.0 { match_n / hyp_total } else { 0.0 })
    sum_r = sum_r + (if ref_total > 0.0 { match_n / ref_total } else { 0.0 })
    orders = orders + 1.0
    n = n + 1
  }
  let mut w = 1
  while w <= 2 {
    let hc = ngram_counts(hyp_words, w)
    let rc = ngram_counts(ref_words, w)
    let mut match_n = 0.0
    for key, h in hc.iter2() {
      let r = match rc.get(key) {
        Some(v) => v
        None => 0
      }
      let m = if h < r { h } else { r }
      match_n = match_n + m.to_double()
    }
    let hyp_total = ngram_total(hyp_words.length(), w).to_double()
    let ref_total = ngram_total(ref_words.length(), w).to_double()
    sum_p = sum_p + (if hyp_total > 0.0 { match_n / hyp_total } else { 0.0 })
    sum_r = sum_r + (if ref_total > 0.0 { match_n / ref_total } else { 0.0 })
    orders = orders + 1.0
    w = w + 1
  }
  let p = sum_p / orders
  let r = sum_r / orders
  if p == 0.0 && r == 0.0 {
    return 0.0
  }
  let beta2 = 4.0
  let f = (1.0 + beta2) * p * r / (beta2 * p + r)
  r4(f)
}
