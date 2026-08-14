# Git Hooks

## Pre-commit Hook

This pre-commit hook performs automatic checks before finalizing your commit.

### What it does (纯本地、零云端依赖)

每次 `git commit` 前自动运行：

1. `moon check` —— 类型检查
2. `moon test --target wasm-gc` —— 全量确定性回归（128/128）

任一失败即中止提交，保护「确定性硬契约」不被破坏。

### Enable (one-time)

```bash
git config core.hooksPath .githooks
```

（本仓库已默认接入；若 clone 到新机器，执行上面一行即可启用。）
