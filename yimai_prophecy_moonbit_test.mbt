// Blackbox tests: high-level behavior via the public API.
// Run `moon test`.

// 端到端：observe 建立上下文链后，predict 应产出非空 Top-K（M1 后转移为 Double，
// 单次转移不会因 to_int 截断而在一次 consolidate 后消失）。
test "blackbox predict returns non-empty top-k after observe chain" {
  let e = ProphecyEngine::make()
  let _ = e.observe("新建翻译项目：新能源汽车白皮书", "instruction")
  let _ = e.observe("提取核心术语表并锁定", "fact")
  let _ = e.observe("对齐术语风格：正式技术中性", "preference")
  let p = e.predict(3)
  match p {
    Json::Object(m) =>
      match m.get("predictions") {
        Some(Json::Array(a)) => inspect(a.length() > 0, content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}
