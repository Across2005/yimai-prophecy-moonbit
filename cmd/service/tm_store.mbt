// tm_store.mbt —— TM 持久化（async/fs 读写 JSON，原子写：临时文件 + rename）
// 注：MoonBit async 调用无需 await（编译器自动调度）。

// P1：最近一次 save_store 的结果（/api/health 用：判断"degraded"）
//   last_save_ok：true=落盘成功，false=真正写盘失败
//   last_save_ts：save_store 退出时间戳（ms since epoch，0=尚未发生）
// P1 二次修复：删除了原 save_busy / save_pending / MAX_SAVE_DEPTH / save_depth
//   防御性代码。注释承认「MoonBit 协作式调度下不会真触发」——纯死代码，
//   保留之反而是认知负担与并发隐患（全局 Ref 单例同 Phase 1.1 已暴露问题）。
let last_save_ok : @ref.Ref[Bool] = @ref.new(true)
let last_save_ts : @ref.Ref[UInt64] = @ref.new(0)

// 引擎 TM 条目数（metrics 用）
fn tm_count() -> Int {
  let m = engine_ref.val.metrics()
  match m {
    Json::Object(o) =>
      match o.get("tm_count") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

// TM 存储文件字符数上限（软防御：防止启动时加载被恶意放大的 JSON）
//   P1 收紧：100MB → 50MB。原 100MB 启动加载峰值内存 ~300MB，小机器（4GB RAM）易 OOM；
//   50MB 启动峰值 ~150MB，4GB 机器亦可承受。超出即冷启动告警并忽略。
const MAX_STORE_CHARS : Int = 50000000

// 启动时加载 tm_store.json（若存在）到引擎
async fn load_store() -> Unit {
  if @fs.exists(TM_STORE_PATH) {
    let data = @fs.read_file(TM_STORE_PATH)
    let s = try { data.text() } catch { _ => "" }
    // P6 加固：拒绝过大的持久化文件，防止 OOM
    if s.length() > MAX_STORE_CHARS {
      println("警告: TM 存储文件过大，忽略并冷启动")
      return
    }
    let parsed : Option[Json] = try { Some(@json.parse(s)) } catch { _ => None }
    match parsed {
      None => println("警告: TM 存储解析失败，使用空引擎")
      Some(j) => {
        engine_ref.val = @lib.ProphecyEngine::from_json(j)
        println("已加载 TM 存储: " + TM_STORE_PATH)
      }
    }
  } else {
    println("无既有 TM 存储，冷启动")
  }
}

// 保存引擎状态到 tm_store.json（原子写：先写临时文件再 rename）
// P1 修复：删除了原 P3-2 节流与 P4 深度守卫（save_busy/save_pending/MAX_SAVE_DEPTH/save_depth）。
//   原节流基于「协作式调度下 save_busy 永远 false」的前提，纯死代码；保留之反而
//   与 Phase 1.1 同源的全局 Ref 单例并发隐患。当前 MoonBit async 协作式调度下，
//   save_store 在 handler 中是 fire-and-forget，调用顺序由调度器保证，无并发写。
// 注：write_file 默认 create_mode=TruncateExisting（文件不存在则失败），需显式 CreateOrTruncate
//   返回 Bool：true=落盘成功，false=写盘/rename 真正失败
//   handler 据此决定 200 / 5xx；之前只 println 丢信号
//   P1 增量：每次退出都更新 last_save_ok / last_save_ts；/api/health 据此判定 degraded
async fn save_store() -> Bool {
  let ok : Bool = try {
    let json_str = engine_ref.val.to_json().stringify()
    let tmp = TM_STORE_PATH + ".tmp"
    @fs.write_file(tmp, json_str, create_mode=@fs.CreateMode::CreateOrTruncate)
    @fs.rename(tmp, TM_STORE_PATH)
    true
  } catch {
    err => {
      println("save_store error: \{err}")
      false
    }
  }
  // P1：每次 save_store 退出都更新结果（健康端点查询路径最短）
  last_save_ok.val = ok
  last_save_ts.val = @env.now()
  ok
}
