// validate.mbt —— 字段级输入校验（Phase 1.2）
// =====================================================================
// P1 修复：原 cmd/service/routes.mbt 的 POST handler 没有字段级长度/范围校验，
// 攻击者可 POST `{"text":<50MB str>}` 触发 DoS / 让 tm_store.json 膨胀到 100MB+。
// 本文件统一收口校验入口，供 handler 调用，失败返统一 BodyFieldError。
//
// 设计原则：
//   1. 零依赖：仅用 core/string（已通过 cmd/service/moon.pkg 间接 import）
//   2. 确定性：所有错误信息字符串均为字面量（无格式化、无随机）
//   3. 最小侵入：handler 调 validate_text_field(o, "src") 即可，签名类似 json_str

/// 字段级输入错误（替代原裸 Option/裸字符串错误）
///   路径：cmd/service/validate.mbt（Phase 1.2 抽离；P6 移回同包）
pub enum BodyFieldError {
  /// 字符串字段超长（超过 max_chars）
  TextTooLong(String, Int)    // (字段名, 实际长度)
  /// 字符串字段为空（业务不允许）
  TextEmpty(String)            // (字段名)
  /// 整数字段超出 [min, max] 范围
  IntOutOfRange(String, Int, Int, Int)  // (字段名, 实际值, min, max)
  /// 数值字段超出 [min, max] 范围（Double）
  NumOutOfRange(String, Double, Double, Double) // (字段名, 实际值, min, max)
  /// 字段缺失（JSON 对象里没有该 key）
  MissingField(String)         // (字段名)
}

/// 默认字段长度上限（保守值，覆盖所有 P0 攻击面）
///   - MAX_TEXT_CHARS: TM 文本 / 目标文本 / query 的单字段上限
///   - MAX_INT_K: predict-k、concordance-k 等 top-k 参数上限
const MAX_TEXT_CHARS : Int = 4096
const MAX_INT_K : Int = 100

/// 验证字符串字段长度（非空 + ≤ MAX_TEXT_CHARS）
///   返回 Ok(text) 表示通过；Err(...) 表示具体失败原因。
pub fn validate_text_field(o : Map[String, Json], key : String) -> Result[String, BodyFieldError] {
  match o.get(key) {
    Some(Json::String(s)) =>
      if s.length() == 0 {
        Err(TextEmpty(key))
      } else if s.length() > MAX_TEXT_CHARS {
        Err(TextTooLong(key, s.length()))
      } else {
        Ok(s)
      }
    Some(_) => Err(MissingField(key))  // 类型不符也按缺失处理（统一 4xx）
    None => Err(MissingField(key))
  }
}

/// 验证 Int 字段范围（≥ 0 且 ≤ MAX_INT_K）
///   default 仅在字段缺失时使用；类型不符返 OutOfRange。
pub fn validate_int_field(
  o : Map[String, Json],
  key : String,
  default : Int,
) -> Result[Int, BodyFieldError] {
  match o.get(key) {
    Some(Json::Number(n, ..)) => {
      let v = n.to_int()
      if v < 0 || v > MAX_INT_K {
        Err(IntOutOfRange(key, v, 0, MAX_INT_K))
      } else {
        Ok(v)
      }
    }
    Some(_) => Err(MissingField(key))
    None => Ok(default)
  }
}

/// 验证 Double 字段范围（threshold 等 [0, 1] 区间参数）
pub fn validate_num_field(
  o : Map[String, Json],
  key : String,
  default : Double,
  min : Double,
  max : Double,
) -> Result[Double, BodyFieldError] {
  match o.get(key) {
    Some(Json::Number(n, ..)) => {
      let v = n
      if v < min || v > max {
        Err(NumOutOfRange(key, v, min, max))
      } else {
        Ok(v)
      }
    }
    Some(_) => Err(MissingField(key))
    None => Ok(default)
  }
}

/// 将 BodyFieldError 转为 (http_code, error_code, message)
///   handler 据此 send_error（统一错误出口）。
pub fn field_error_to_response(e : BodyFieldError) -> (Int, String, String) {
  match e {
    TextTooLong(key, len) =>
      (413, "field_too_long", key + " length=" + len.to_string() + " exceeds MAX_TEXT_CHARS=" + MAX_TEXT_CHARS.to_string())
    TextEmpty(key) =>
      (400, "field_empty", key + " must be non-empty")
    IntOutOfRange(key, v, min, max) =>
      (400, "int_out_of_range", key + "=" + v.to_string() + " out of [" + min.to_string() + "," + max.to_string() + "]")
    NumOutOfRange(key, v, min, max) =>
      (400, "num_out_of_range", key + "=" + v.to_string() + " out of [" + min.to_string() + "," + max.to_string() + "]")
    MissingField(key) =>
      (400, "missing_field", key + " is required")
  }
}

/// 便捷入口：校验后直接 send_error 到 conn；handler 拿 Bool 表示是否通过
///   用法：
///     if not(validate_text_field_or_send(o, "src", conn)) { return }
///   注：handler 拿到 false 即表示已发错误响应，直接 return。
async fn validate_text_field_or_send(
  conn : @http.ServerConnection,
  o : Map[String, Json],
  key : String,
) -> Bool {
  match validate_text_field(o, key) {
    Ok(_) => true
    Err(e) => {
      let (code, ec, msg) = field_error_to_response(e)
      send_error(conn, code, ec, msg)
      false
    }
  }
}

/// Int 字段便捷入口（缺失返 default）
async fn validate_int_field_or_send(
  conn : @http.ServerConnection,
  o : Map[String, Json],
  key : String,
  default : Int,
) -> Bool {
  match validate_int_field(o, key, default) {
    Ok(_) => true
    Err(e) => {
      let (code, ec, msg) = field_error_to_response(e)
      send_error(conn, code, ec, msg)
      false
    }
  }
}

/// Num 字段便捷入口
async fn validate_num_field_or_send(
  conn : @http.ServerConnection,
  o : Map[String, Json],
  key : String,
  default : Double,
  min : Double,
  max : Double,
) -> Bool {
  match validate_num_field(o, key, default, min, max) {
    Ok(_) => true
    Err(e) => {
      let (code, ec, msg) = field_error_to_response(e)
      send_error(conn, code, ec, msg)
      false
    }
  }
}

// ---------------------------------------------------------------------------
// 高阶封装：with_json_object —— 消除 22 个 POST handler 的 read_json_or_400 + match Object 样板
// ---------------------------------------------------------------------------
//
// 原本每个 handler 都得写：
//   let parsed = read_json_or_400(conn, body)
//   match parsed {
//     Some(Json::Object(o)) => {
//       if not(validate_text_field_or_send(conn, o, "xxx")) { return }
//       ...
//       send_json(conn, 200, result.stringify())
//     }
//     _ => ()  // read_json_or_400 已发 4xx 响应
//   }
//
// 改用：
//   with_json_object(body, conn, async fn(o, conn) {
//     if not(validate_text_field_or_send(conn, o, "xxx")) { return }
//     ...
//     send_json(conn, 200, result.stringify())
//   })
//
// 收益：
//   1. handler 缩 5-8 行（消除样板）
//   2. read_json_or_400 → Object 派发集中在一处，未来要加 tracing/logging 只改这里
//   3. 闭包内仍可直接调 validate_*_field_or_send + send_json（async 闭包支持）

/// 高阶封装：读 body 并在解析为 Object 时调用闭包；非 Object 已由 read_json_or_400 发 4xx。
///   注：MoonBit async fn 可接受 async 闭包作为参数，编译器沿 async 调用链自动调度。
async fn with_json_object(
  body : &@io.Reader,
  conn : @http.ServerConnection,
  f : async (Map[String, Json], @http.ServerConnection) -> Unit,
) -> Unit {
  let parsed = read_json_or_400(conn, body)
  match parsed {
    Some(Json::Object(o)) => f(o, conn)
    _ => ()  // read_json_or_400 已发 4xx 响应
  }
}
