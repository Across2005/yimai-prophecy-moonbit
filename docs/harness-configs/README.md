# Multi-Harness MCP Configuration Samples

This directory contains **drop-in MCP config samples** for the AI coding harnesses
that consume yimai-prophecy-moonbit's local MCP server. All of them point at the
same `http://127.0.0.1:8787/mcp` Streamable HTTP endpoint — start the service
once (`scripts/run.ps1` / `scripts/dev.ps1`), then copy the file for your
harness into the location the harness reads from.

> Pure local, zero cloud dependency. The service runs on `127.0.0.1` only; no
> traffic ever leaves your machine.

## Files in this directory

| File | Harness | Where the harness actually reads it | Transport | Form |
|---|---|---|---|---|
| `claude-desktop.json` | Claude Desktop (Anthropic) | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows) | HTTP | JSON |
| `claude-code.json` | Claude Code (CLI) | `~/.claude/mcp.json` or via `/mcp` slash command | HTTP | JSON |
| `gemini-cli.json` | Gemini CLI (Google) | `~/.gemini/settings.json` (merged under `mcpServers`) | HTTP | JSON |
| `cursor.json` | Cursor | `~/.cursor/mcp.json` (or per-project `.cursor/mcp.json`) | HTTP | JSON |
| `cline.json` | Cline (VS Code) | Cline → MCP Servers → Add (UI) or `cline_mcp_settings.json` | HTTP | JSON † |
| `continue.json` | Continue.dev (VS Code / JetBrains) | `~/.continue/config.json` under `mcpServers` | HTTP (streamable-http) | JSON |
| `roo-code.json` | Roo Code (VS Code) | Roo Code → MCP → Add Server (HTTP) or `.roo/mcp.json` | HTTP | JSON † |
| `windsurf.json` | Windsurf / Cascade (Codeium) | `~/.windsurf/mcp.json` | HTTP | JSON |
| `codex.toml` | OpenAI Codex CLI (≥ 0.21) | `~/.codex/config.toml` or `.codex/config.toml` (per-project) | HTTP | TOML |
| `aider.conf.yml` | Aider (chat-based, ≥ 0.86) | repo root `.aider.conf.yml` or `~/.aider.conf.yml` | HTTP (via `--mcp`) | YAML |
| `cody.json` | Sourcegraph Cody (VS Code) — *deprecated 2025-08* | `~/.config/sourcegraph/cody.json` (only `cody.mcp.servers` segment) | HTTP | JSON |
| `zed.json` | Zed (editor, ≥ 0.150) | `~/.config/zed/settings.json` (under `context_servers`) | HTTP | JSON |
| `github-copilot.yml` | GitHub Copilot Coding Agent (runner caveat) | `.github/workflows/copilot-setup-steps.yml` (snippet) | n/a (CI) | YAML doc |

> † Cline / Roo Code 在 VS Code UI 内可"Add Server"直接填 name/type/url；JSON 文件形式是新版 (≥ 3.x) 的可选项，文件路径以各扩展的 release notes 为准。
>
> ⚠ Sourcegraph Cody 自 2025-08 进入维护模式，AI 主线转入 Amp。`cody.json` 仅作历史参考。
>
> ⚠ GitHub Copilot Coding Agent 跑在 GitHub 托管 runner，与 `127.0.0.1:8787` 网络隔离。`github-copilot.yml` 不是 drop-in，是 PR 工作流内同 runner 启 yimai 的示例片段。

## Why every config is the same shape

The MCP spec (`2025-11-25`, Streamable HTTP, JSON-RPC 2.0) is a wire-level
contract. Every client above speaks the same wire — only the **config file
path** and the **field names** differ. The yimai service does not care which
client is on the other end: `initialize` → `tools/list` (24 tools) →
`tools/call` works the same way for all of them.

> **2026-08 现状**：`modelcontextprotocol/specification` 已在 2026-07-28 发布
> RC（移除 `initialize` 握手、`Mcp-Session-Id` 头、强制 `Mcp-Method`/`Mcp-Name`
> 头、JSON Schema 2020-12 完整支持等），属于 breaking change。yimai 仍按
> `2025-11-25` 实现，待 0.2.0 切换；不影响本目录现有 13 个 drop-in 在
> 当前 client 端的可用性。

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
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

> 验证段 `curl` 是临时调试用 — MCP Streamable HTTP 在生产路径上需要长连接
> JSON-RPC 会话（如 `mcp-remote` / `mcp-proxy` 桥接到 stdio），不是浏览器
> 一次性 POST 工具。
