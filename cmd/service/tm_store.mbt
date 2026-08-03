// tm_store.mbt —— TM 持久化（async/fs 读写 JSON，原子写：临时文件 + rename）
// 注：MoonBit async 调用无需 await（编译器自动调度）。

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
// 注：write_file 默认 create_mode=TruncateExisting（文件不存在则失败），需显式 CreateOrTruncate
async fn save_store() -> Unit {
  try {
    let json_str = engine_ref.val.to_json().stringify()
    let tmp = TM_STORE_PATH + ".tmp"
    @fs.write_file(tmp, json_str, create_mode=@fs.CreateMode::CreateOrTruncate)
    @fs.rename(tmp, TM_STORE_PATH)
  } catch {
    err => println("save_store error: \{err}")
  }
}
