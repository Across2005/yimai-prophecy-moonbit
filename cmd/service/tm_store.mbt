// tm_store.mbt —— TM 持久化（async/fs 读写 JSON，原子写：临时文件 + rename）
// 注：MoonBit async 调用无需 await（编译器自动调度）。

// 落盘节流标志（P3-2）：
//  - save_busy：某次落盘在途（已序列化快照，正在写临时文件/rename）为 true。
//  - save_pending：busy 期间又有写发生，标记"需补落盘"。
// 写端点在 handler 中为 fire-and-forget（async 不 await），高并发写会造成多个原子写
// 重叠（临时文件同路径 rename 争用）。busy 时新写置 pending 并跳过；busy 释放后由
// 下一次 save_store 若见 pending 则补落最新状态，保证最终一致且不丢失最后一次更新。
let save_busy : @ref.Ref[Bool] = @ref.new(false)
let save_pending : @ref.Ref[Bool] = @ref.new(false)

// P1：最近一次 save_store 的结果（/api/health 用：判断"degraded"）
//   last_save_ok：true=落盘成功（含节流跳过场景），false=真正写盘失败
//   last_save_ts：save_store 退出时间戳（ms since epoch，0=尚未发生）
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

// 启动时加载 tm_store.json（若存在）到引擎
async fn load_store() -> Unit {
  if @fs.exists(TM_STORE_PATH) {
    let data = @fs.read_file(TM_STORE_PATH)
    let s = try { data.text() } catch { _ => "" }
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
// P3-2 节流：busy 在途时置 pending 并跳过，避免并发写风暴；busy 结束后若期间有
// 更新被跳过则补落一次最新状态，保证最终一致。成功与失败统一在 try/catch 后释放 busy。
// 注：write_file 默认 create_mode=TruncateExisting（文件不存在则失败），需显式 CreateOrTruncate
//   返回 Bool：true=落盘成功（含 P3-2 节流跳过场景），false=写盘/rename 真正失败
//   handler 据此决定 200 / 5xx；之前只 println 丢信号
//   P1 增量：每次退出都更新 last_save_ok / last_save_ts；/api/health 据此判定 degraded
async fn save_store() -> Bool {
  if save_busy.val {
    save_pending.val = true   // 在途落盘未完成，标需补落最新状态
    return true                // 节流跳过视为"成功"（最终一致性由后续补落保证）
  }
  save_busy.val = true
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
  // 成功或失败均到此：释放 busy；若期间有写被跳过，补落一次最新状态
  save_busy.val = false
  // P1：每次 save_store 退出都更新结果（健康端点查询路径最短）
  last_save_ok.val = ok
  last_save_ts.val = @env.now()
  if save_pending.val {
    save_pending.val = false
    // 补落成功与否不冲销当前 ok（已是最新的"曾经成功"语义；真正落盘失败会在递归里继续报）
    let _ = save_store()
  }
  ok
}
