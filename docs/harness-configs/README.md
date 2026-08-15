# Multi-Harness MCP Configuration Samples

This directory contains **drop-in MCP config samples** for the AI coding harnesses
that consume yimai-prophecy-moonbit's local MCP server. All of them point at the
same `http://127.0.0.1:8787/mcp` Streamable HTTP endpoint — start the service
once (`scripts/run.ps1` / `scripts/dev.ps1`), then copy the file for your
harness into the location the harness reads from.

> Pure local, zero cloud dependency. The service runs on `127.0.0.1` only; no
> traffic ever leaves your machine.

## Files in this directory

| File | Harness | Where the harness actually reads it | Transport |
|---|---|---|---|
| `claude-desktop.json` | Claude Desktop (Anthropic) | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows) | HTTP |
| `claude-code.json` | Claude Code (CLI) | `~/.claude/mcp.json` or via `/mcp` slash command | HTTP |
| `gemini-cli.json` | Gemini CLI (Google) | `~/.gemini/settings.json` (merged under `mcpServers`) | HTTP |
| `cursor.json` | Cursor | `~/.cursor/mcp.json` (or per-project `.cursor/mcp.json`) | HTTP |
| `cline.json` | Cline (VS Code) | Cline → MCP Servers → Add → name=`yimai`, type=`http`, url=`http://127.0.0.1:8787/mcp` | HTTP |
| `continue.json` | Continue.dev (VS Code / JetBrains) | `~/.continue/config.json` under `mcpServers` | HTTP (stdio) |
| `roo-code.json` | Roo Code (VS Code) | Roo Code → MCP → Add Server (HTTP transport) | HTTP |
| `windsurf.json` | Windsurf / Cascade | `~/.windsurf/mcp.json` | HTTP |
| `codex.toml` | OpenAI Codex CLI (≥ 0.21) | `~/.codex/config.toml` or `.codex/config.toml` (per-project) | HTTP |
| `aider.conf.yml` | Aider (chat-based) | repo root `.aider.conf.yml` or `~/.aider.conf.yml` | HTTP (via `--mcp`) |
| `cody.json` | Sourcegraph Cody (VS Code) | Cody → Settings → MCP Servers | HTTP |
| `zed.json` | Zed (editor) | `~/.config/zed/settings.json` (under `context_servers`) | HTTP |
| `github-copilot.yml` | GitHub Copilot Coding Agent | `.github/copilot-setup-steps.yml` (already in repo) | n/a (CI) |

## Why every config is the same shape

The MCP spec (`2025-11-25`, Streamable HTTP, JSON-RPC 2.0) is a wire-level
contract. Every client above speaks the same wire — only the **config file
path** and the **field names** differ. The yimai service does not care which
client is on the other end: `initialize` → `tools/list` (24 tools) →
`tools/call` works the same way for all of them.

## Quick start

```powershell
# 1) build & start the service (one command)
powershell -ExecutionPolicy Bypass -File scripts/dev.ps1

# 2) pick your harness and copy the matching file to its expected path
#    (see the table above)
Copy-Item docs/harness-configs/cursor.json ~/.cursor/mcp.json

# 3) restart the harness so it picks up the new server
```

## Verifying

After the harness restarts, ask it to call one of the 24 tools, e.g.:

> "Use the yimai MCP server's `fuzzy_match` tool to find translations of
>  '电池包热管理方案'."

If the harness does not see the tool, check `tools/list` returns 24 entries:

```bash
curl -s -X POST http://127.0.0.1:8787/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```
