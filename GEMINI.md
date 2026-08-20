# GEMINI.md — Gemini CLI Out-of-the-Box Guide

> Auto-loaded by Gemini CLI (Google's CLI coding agent).
> **All shared project knowledge lives in [`AGENTS.md`](./AGENTS.md)**
> ([Code conventions → R15](./AGENTS.md#code-conventions) / MoonBit gotchas / 项目布局).
> 📜 变更历史：[`CHANGELOG.md`](./CHANGELOG.md) — 每次 P 增量的完整 commit 列表。
> This file only documents **Gemini CLI specific** onboarding.

## Gemini CLI MCP auto-discovery (zero-copy)

After `scripts/run.ps1` (or `scripts/dev.ps1` for one-shot setup) is running
on `http://127.0.0.1:8787`, Gemini CLI auto-discovers the MCP server from the
project-level `.mcp.json` at the repo root — **no manual copy** to
`~/.gemini/settings.json` needed.

If you prefer a global config instead, add the same block to
`~/.gemini/settings.json`:

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
2. Confirm Gemini CLI sees the server — in the interactive prompt:
   ```
   /mcp list                              # → should list "yimai" connected
   ```
3. Confirm tools work — invoke directly from the prompt:
   ```
   @yimai ping                            # → {"status":"ok"}
   ```
   (Gemini CLI uses `@<server> <request>` syntax for direct MCP calls; this
   is the real equivalent of `mcp__yimai__ping` in Claude Code.)

## Troubleshooting

If `/mcp list` doesn't show yimai:

- **Service not running**: `curl http://127.0.0.1:8787/api/ping` — if it
  fails, run `scripts/run.ps1` (or `scripts/dev.ps1`).
- **Port conflict**: check `127.0.0.1:8787` isn't bound by another service.
- **Stale config cache**: restart Gemini CLI — `.mcp.json` is reloaded
  on startup, not per-prompt.
- **Old binary**: rebuild with `scripts/build.ps1` if `cmd/service` changed.

## See also

| Doc | Purpose |
|---|---|
| [`AGENTS.md`](./AGENTS.md) | **Full** multi-harness guide (source of truth) |
| `README.md` | API reference + ISO/MQM standards alignment |
| `docs/harness-configs/README.md` | 13-harness overview + 25-tools list |
| `docs/harness-configs/gemini-cli.json` | Drop-in sample for `~/.gemini/settings.json` |