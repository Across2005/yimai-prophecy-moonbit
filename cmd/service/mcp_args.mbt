// mcp_args.mbt —— /mcp 端点参数提取 + JSON Schema 字段辅助
// =====================================================================
// P11-B 拆自 mcp.mbt（440 → 4 文件拆分）：
//   - mcp_args.mbt（本文件）：arg_str/int/num/bool 4 个 JSON 字段提取 helper
//     + schema_prop（单条 JSON Schema property 构造）
//   - 同包 cmd/service 零 import 改动；mcp_schemas.mbt / mcp_dispatch.mbt / mcp.mbt
//     都在同一包内可见。
//
// 5 个 helper 主题内聚：JSON → 强类型值的提取与 JSON Schema property 构造。

// 取 args 对象的 string 字段
fn arg_str(args : Json, key : String) -> String {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::String(v)) => v
        _ => ""
      }
    _ => ""
  }
}

// 取 args 对象的 int 字段（缺省 default）
fn arg_int(args : Json, key : String, default : Int) -> Int {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

// 取 args 对象的 double 字段（缺省 default）
fn arg_num(args : Json, key : String, default : Double) -> Double {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(Json::Number(n, ..)) => n
        _ => default
      }
    _ => default
  }
}

// 取 args 对象的 bool 字段（缺省 default）
//   P8：as_bool() 已废弃；本版本 Json 的 Bool 构造器已拆为 True/False 单例，
//   按官方建议用 is True / is False 判别（等价：仅 bool 命中，其余走 default）。
fn arg_bool(args : Json, key : String, default : Bool) -> Bool {
  match args {
    Json::Object(o) =>
      match o.get(key) {
        Some(v) => if v is True { true } else if v is False { false } else { default }
        None => default
      }
    _ => default
  }
}

// 构造单条 JSON Schema property
fn schema_prop(kind : String, desc : String) -> Json {
  @lib.obj([("type", @lib.str_json(kind)), ("description", @lib.str_json(desc))])
}
