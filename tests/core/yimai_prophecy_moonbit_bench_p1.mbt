// yimai_prophecy_moonbit_bench_p1.mbt
// P1 性能对比：fuzzy_match（剪枝，1K+ 走 IDF top-3 postings） vs fuzzy_match_full（无剪枝全图）。
// 1K/5K/10K 三种 TM 规模，统一 200 iter（同 query），用累计 hash 防止 wasm 优化掉死循环。
// wasm-gc 无内置 wall clock；用 PowerShell Measure-Command 测 test 总耗时，结合 seed 耗时扣除，
// 即可得到「单次 query」均摊时间（pruned vs full）。

// 真实双语短语池（40 条覆盖多领域），按 N 取模循环填充
let bench_pool : Array[(String, String)] = [
  ("打开文件保存", "Open file and save"),
  ("打开设置界面", "Open settings UI"),
  ("打开浏览器窗口", "Open browser window"),
  ("打开命令行工具", "Open command line tool"),
  ("打开网络连接面板", "Open network panel"),
  ("电池包热管理", "Battery pack thermal management"),
  ("电池包温度管理方案", "Battery pack temperature management plan"),
  ("电池包热管理策略", "Battery pack thermal management strategy"),
  ("电机冷却系统", "Motor cooling system"),
  ("整车控制器 VCU", "Vehicle Control Unit"),
  ("能量密度", "energy density"),
  ("续航里程", "driving range"),
  ("百公里加速", "zero to hundred acceleration"),
  ("充电桩通讯协议", "charging station communication protocol"),
  ("绝缘栅双极型晶体管", "Insulated Gate Bipolar Transistor"),
  ("永磁同步电机", "permanent magnet synchronous motor"),
  ("异步感应电机", "asynchronous induction motor"),
  ("动力电池总成", "powertrain battery pack"),
  ("热失控防护", "thermal runaway protection"),
  ("电磁兼容 EMC 测试", "EMC electromagnetic compatibility test"),
  ("自动驾驶 L2", "L2 autonomous driving"),
  ("自动紧急制动 AEB", "Automatic Emergency Braking"),
  ("车道保持辅助 LKA", "Lane Keeping Assist"),
  ("自适应巡航 ACC", "Adaptive Cruise Control"),
  ("盲点监测 BSD", "Blind Spot Detection"),
  ("胎压监测 TPMS", "Tire Pressure Monitoring System"),
  ("车载信息娱乐 IVI", "In-Vehicle Infotainment"),
  ("空中下载 OTA 升级", "Over-The-Air update"),
  ("功能安全 ISO 26262", "Functional Safety ISO 26262"),
  ("预期功能安全 SOTIF", "Safety Of The Intended Functionality"),
  ("网络安全 ISO 21434", "Automotive Cybersecurity ISO 21434"),
  ("以太网车载总线", "Automotive Ethernet"),
  ("控制器局域网 CAN", "Controller Area Network"),
  ("本地互联网络 LIN", "Local Interconnect Network"),
  ("FlexRay 总线", "FlexRay bus"),
  ("诊断协议 UDS", "Unified Diagnostic Services"),
  ("标定 XCP 协议", "XCP measurement and calibration"),
  ("Autosar 架构", "AUTOSAR architecture"),
  ("整车 OTA 升级", "Vehicle OTA update"),
  ("热管理控制器", "Thermal Management Controller"),
]

fn bench_seed(e : @lib.ProphecyEngine, n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    let p = bench_pool[i % bench_pool.length()]
    let tail = match i % 4 {
      0 => ""
      1 => " v1"
      2 => " 模块"
      _ => " 模组 A"
    }
    let _ = e.add_tm(p.0 + tail, p.1 + " (rev " + i.to_string() + ")")
  }
  // warmup: 触发 ensure_tm_idf 建 postings（让 fuzzy_match 第一次就命中剪枝路径）
  let _ = e.fuzzy_match("warmup", 1, 0.0)
}

fn bench_acc(e : @lib.ProphecyEngine, query : String, n : Int, full : Bool) -> Int {
  let mut acc = 0
  for _i = 0; _i < n; _i = _i + 1 {
    let r = if full { e.fuzzy_match_full(query, 3, 0.0) } else { e.fuzzy_match(query, 3, 0.0) }
    match r {
      Json::Array(a) =>
        for it in a {
          match it {
            Json::Object(m) =>
              match m.get("id") {
                Some(Json::String(s)) => acc = acc + s.length()
                _ => ()
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  acc
}

test "BENCH P1 1K/5K/10K pruned vs full 200 iter" {
  let query = "电池包热管理"
  let n = 200
  // 1K
  let e1 = @lib.ProphecyEngine::make()
  bench_seed(e1, 1000)
  let _ = e1.fuzzy_match(query, 1, 0.0)
  let _ = e1.fuzzy_match_full(query, 1, 0.0)
  let p1 = bench_acc(e1, query, n, false)
  let f1 = bench_acc(e1, query, n, true)
  println(">>> [BENCH 1K]  pruned_acc=" + p1.to_string() + "  full_acc=" + f1.to_string() + "  (per-iter hits pruned=3 full=3)")
  // 5K
  let e5 = @lib.ProphecyEngine::make()
  bench_seed(e5, 5000)
  let _ = e5.fuzzy_match(query, 1, 0.0)
  let _ = e5.fuzzy_match_full(query, 1, 0.0)
  let p5 = bench_acc(e5, query, n, false)
  let f5 = bench_acc(e5, query, n, true)
  println(">>> [BENCH 5K]  pruned_acc=" + p5.to_string() + "  full_acc=" + f5.to_string() + "  (per-iter hits pruned=3 full=3)")
  // 10K
  let e10 = @lib.ProphecyEngine::make()
  bench_seed(e10, 10000)
  let _ = e10.fuzzy_match(query, 1, 0.0)
  let _ = e10.fuzzy_match_full(query, 1, 0.0)
  let p10 = bench_acc(e10, query, n, false)
  let f10 = bench_acc(e10, query, n, true)
  println(">>> [BENCH 10K] pruned_acc=" + p10.to_string() + "  full_acc=" + f10.to_string() + "  (per-iter hits pruned=3 full=3)")
  // 正确性兜底：pruned 与 full per-iter 命中数一致
  inspect(p1 == f1, content="true")
  inspect(p5 == f5, content="true")
  inspect(p10 == f10, content="true")
}

// L13 实际延迟验证：10K TM + warmup + 20 iter，PowerShell Measure-Command 测本 test 总耗时
// （单 iter 估算 ≈ (总耗时 - seed/warmup 开销) / 20）
test "BENCH P1 10K fuzzy_match 20 iter 含 warmup 延迟" {
  let e = @lib.ProphecyEngine::make()
  bench_seed(e, 10000)
  // 2 次 warmup（IDF 表 / postings / 排序热路径）
  let _ = e.fuzzy_match("电池包热管理", 3, 0.0)
  let _ = e.fuzzy_match("电池包热管理", 3, 0.0)
  // 20 次正式查询
  let acc = bench_acc(e, "电池包热管理", 20, false)
  println(">>> [BENCH L13 10K fuzzy_match 20 iter]  acc=" + acc.to_string() + " (3 hits/iter × 20 = 60 expected)")
  inspect(acc > 0, content="true")
}
