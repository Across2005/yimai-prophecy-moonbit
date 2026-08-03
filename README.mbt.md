# yimai_prophecy_moonbit

**译脉·先知 2.0** —— 带预测能力的确定性记忆网络引擎（MoonBit 零依赖实现）。

- 零第三方依赖（仅 `core/json` + `core/math`）
- D1-D8 记忆预测模块 + #22 翻译记忆/术语库 + #2-#7 扩展能力 + S1 检索升级
- 确定性：逻辑时钟替代 wall-clock，同输入必同输出（`to_json` 逐字节一致）
- 99/99 测试全绿，Hit@3 = 0.8246（相对随机 3.57×）

## 快速使用（库方式）

```moonbit
import {
  "Across2005/yimai_prophecy_moonbit" @lib,
}

let mut eng = @lib.ProphecyEngine::make()
let _ = eng.observe("解析源文件结构", "step")
let _ = eng.observe("提取核心术语表并锁定", "step")
let pred = eng.predict(3)              // 下一步预测 + 白盒路径
let hits = eng.recall("术语", 5)       // 语义召回
let snap = eng.to_json()               // 持久化导出
```

## 服务层（HTTP + MCP）

`cmd/service` 提供 13 个 REST 端点 + `/mcp` MCP Server（spec 2025-11-25）+ 三面板前端工作台。详见仓库 `README.md` 的「Service Layer」章节；`scripts/dev.ps1` 一键构建-启动-灌数据-冒烟。

## 测试

```bash
moon test --target wasm-gc     # 99/99
```
