// util.mbt —— 译脉·先知 2.0 (MoonBit) 编码层 + JSON 辅助
// 零依赖：仅 moonbitlang/core/json 与 moonbitlang/core/math
// 对应原 Python 版的 tokenize / tf_vector / cosine 与共享 JSON 构造逻辑。

// ---- 算法常量（HEBB_LR 等权重参数在 engine.mbt 定义，与 Python 版逐项一致）----

// 停用词：中文功能词 + 英文停用词（与 Python 版一致）
let stop_words : Array[String] = [
  "的", "了", "和", "是", "在", "我", "你", "他", "她", "它", "们", "这", "那", "有",
  "就", "不", "也", "都", "一个", "上", "下", "中", "与", "及", "或", "把", "被", "给",
  "对", "从", "到", "等", "用", "将", "要", "会", "能", "可以", "通过", "根据", "按照",
  "关于", "进行", "以及", "a", "an", "the", "of", "to", "and", "or", "in", "on", "for",
  "with", "is", "are", "be",
]

fn is_stop(t : String) -> Bool {
  for s in stop_words {
    if s == t {
      return true
    }
  }
  false
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

// 概念抽象·角色抽取：取文本前 4 字作为粗略类别键（跨主题稳定）
fn role_of(text : String) -> String {
  (text[:4]).to_owned()
}

// ---------------------------------------------------------------------------
// 编码层：tokenize -> tf_vector -> cosine
// ---------------------------------------------------------------------------

// 分词：ASCII [a-z0-9_]+ 段 + CJK 单字与相邻二元组；小写并去停用词。
// 对应原 Python 版正则分词 + 中文 unigram/bigram 展开。
fn yimai_tokenize(text : String) -> Array[String] {
  let lower = to_lower_ascii(text)
  let toks : Array[String] = []
  let mut lat = StringBuilder()
  let mut lat_len = 0
  let mut prev_cjk = ""
  for c in lower.iter() {
    let code = c.to_int()
    let is_lat = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'
    if is_lat {
      lat.write_char(c)
      lat_len = lat_len + 1
    } else {
      if lat_len > 0 {
        toks.push(lat.to_string())
        lat = StringBuilder()
        lat_len = 0
      }
      if code >= 0x4E00 && code <= 0x9FFF {
        let s = c.to_string()
        toks.push(s)
        if prev_cjk != "" {
          toks.push(prev_cjk + s)
        }
        prev_cjk = s
      } else {
        prev_cjk = ""
      }
    }
  }
  if lat_len > 0 {
    toks.push(lat.to_string())
  }
  let out : Array[String] = []
  for t in toks {
    if !is_stop(t) {
      out.push(t)
    }
  }
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

// 余弦相似度（在 TF 向量上，等价于原 Python 版）
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

// 四舍五入到 4 位小数（用于展示，对应 Python round(...,4)）
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

// ---------------------------------------------------------------------------
// JSON 构造 / 访问辅助（复用 AL-world 风格，零依赖 moonbitlang/core/json）
// ---------------------------------------------------------------------------

fn str_json(s : String) -> Json {
  s.to_json()
}

fn num_json(d : Double) -> Json {
  d.to_json()
}

fn arr_json(items : Array[Json]) -> Json {
  items.to_json()
}

fn obj(pairs : Array[(String, Json)]) -> Json {
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
