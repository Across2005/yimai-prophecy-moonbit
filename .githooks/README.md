# Git Hooks

## Pre-commit Hook

This pre-commit hook performs automatic checks before finalizing your commit.

### What it does (纯本地、零云端依赖)

每次 `git commit` 前自动运行：

1. `moon check` —— 类型检查
2. `moon test --target wasm-gc` —— 全量确定性回归（128/128）

任一失败即中止提交，保护「确定性硬契约」不被破坏。

### Enable

`scripts/setup.ps1` 会自动完成配置（运行 `dev.ps1` 也会触发）。

如需手动启用：

```bash
git config core.hooksPath .githooks
```
