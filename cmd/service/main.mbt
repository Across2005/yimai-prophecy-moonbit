// main.mbt —— 译脉·先知 2.0 纯 MoonBit 服务层（黑客松双层架构 Layer 2）
// 零桥接：内核（@lib，零依赖）+ async/http + async/fs，单一语言全栈。
// 起本地 HTTP server，暴露 /api/* 端点供前端工作台 / Agent / LLM 宿主消费。
// 构建（Windows 需 MSVC 环境变量 INCLUDE/LIB）：
//   moon build cmd/service --target native
// 运行：
//   moon run cmd/service --target native
// 注：MoonBit async 调用无需 await 关键字（编译器自动调度）。

// 全局引擎（Ref 可变单元，服务进程生命周期内单例；写操作后落盘）
let engine_ref : @ref.Ref[@lib.ProphecyEngine] = @ref.new(@lib.ProphecyEngine::make())

// TM 持久化文件（相对路径，写于服务启动目录；write_file 需 CreateOrTruncate 见 tm_store.mbt）
const TM_STORE_PATH : String = "tm_store.json"

async fn main {
  load_store()
  println("译脉引擎服务: http://127.0.0.1:8787")
  println("TM 条目数: " + tm_count().to_string())
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:8787"))
  server.run_forever(handle_request) catch {
    err => println("server terminated: \{err}")
  }
}
