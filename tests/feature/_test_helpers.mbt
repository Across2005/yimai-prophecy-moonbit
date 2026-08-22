// tests/feature/_test_helpers.mbt
// feature 子包共享 helper（普通文件，进 lib 构建目标）。
// P8：feature 包此前只有 *_test.mbt（lib 构建目标为空），moon.pkg 的 @lib import
// 被判 unused_package 告警；corpus/core 两包正是靠各自的 _test_helpers.mbt 消除同类告警。
// 现把 routes_test 的 build_known_handlers / known_handlers 上移至此，
// @lib 在 lib 目标有真实使用，告警消除且行为零变化。

// routes.mbt::handle_request 的 match 派发全集
//   P4：从 routes_meta 派生（取每项的 handler_name）消除硬编码 26 字符串，
//   routes_meta 增删时 known_handlers 自动同步；L21 测试断言两者长度一致兜底。
//   P8：*_test.mbt 是黑盒测试，须 pub 才可见（与 corpus/core _test_helpers 先例一致）。
pub fn build_known_handlers() -> Array[String] {
  let out : Array[String] = []
  for entry in @lib.routes_meta {
    let (_, n) = entry
    out.push(n)
  }
  out
}

pub let known_handlers : Array[String] = build_known_handlers()
