# CLAUDE.md — Claude Code Out-of-the-Box Guide

> Auto-loaded by Claude Code (Anthropic's CLI coding agent).
> **All shared project knowledge lives in [`AGENTS.md`](./AGENTS.md)**
> ([Code conventions → R15](./AGENTS.md#code-conventions) / MoonBit gotchas / 项目布局).
> 📜 变更历史：[`CHANGELOG.md`](./CHANGELOG.md) — 每次 P 增量的完整 commit 列表。
> This file only documents **Claude Code specific** onboarding.

## Claude Code MCP auto-discovery (zero-copy)

After `scripts/run.ps1` (or `scripts/dev.ps1` for one-shot setup) is running
on `http://127.0.0.1:8787`, Claude Code auto-discovers the **25 tools** from
the project-level `.mcp.json` at the repo root — **no manual copy** to
`~/.claude/mcp.json` needed.

If you prefer a global config instead, add the same block to
`~/.claude/mcp.json` (or run `/mcp` → "Add this server" to register
interactively — note `/mcp` is for interactive add/inspect, not a config
substitute):

```json
{
  "mcpServers": {
    "yimai": {
      "url": "http://127.0.0.1:8787/mcp"
    }
  }
}
```

The service speaks MCP spec `2025-11-25` (Streamable HTTP, JSON-RPC 2.0).
Full tool list: see [`docs/harness-configs/README.md`](./docs/harness-configs/README.md).

## Quick verify

1. Confirm service is up:
   ```bash
   curl http://127.0.0.1:8787/api/ping      # → {"status":"ok"}
   ```
2. Confirm Claude Code sees the server:
   ```
   /mcp                                   # → should list "yimai" connected
   ```
3. Confirm tools work — just ask Claude in natural language:
   > "Ping the yimai server and show me tm_count"

   (Claude will invoke `mcp__yimai__ping` and `mcp__yimai__tm_count`
   internally; you don't type these directly — they're tool identifiers
   surfaced to the assistant, not REPL commands.)

## Troubleshooting

If `/mcp` shows yimai not connected:

- **Service not running**: `curl http://127.0.0.1:8787/api/ping` — if it
  fails, run `scripts/run.ps1` (or `scripts/dev.ps1`).
- **Port conflict**: check `127.0.0.1:8787` isn't bound by another service.
- **Stale config cache**: restart Claude Code — `.mcp.json` is reloaded
  on startup, not per-prompt.
- **Old binary**: rebuild with `scripts/build.ps1` if `cmd/service` changed.

## See also

| Doc | Purpose |
|---|---|
| [`AGENTS.md`](./AGENTS.md) | **Full** multi-harness guide (source of truth) |
| `README.md` | API reference + ISO/MQM standards alignment |
| `docs/harness-configs/README.md` | 13-harness overview + 25-tools list |
| `docs/harness-configs/claude-code.json` | Drop-in sample for `~/.claude/mcp.json` |