# AGENTS.md — AI Agent Out-of-the-Box Guide

This file tells AI agents (Claude, Copilot, Cursor, code agents, …) how to use
this repository immediately after cloning. Read this first.

> **Multi-harness companion files** (auto-loaded by specific agents):
> - [`CLAUDE.md`](./CLAUDE.md) — Claude Code (Anthropic CLI)
> - [`GEMINI.md`](./GEMINI.md) — Gemini CLI (Google)
> - Both point back to this file for the full multi-harness guide.

## What this project is

**译脉·先知 2.0** — a deterministic memory-prediction engine written in
[MoonBit](https://www.moonbitlang.com), zero third-party dependencies
(`core/json` + `core/math` only). It remembers workflows / translation-memory
entries and predicts the next step, with white-box explanations.

Three layers, one language (no bridge code):

| Layer | Where | What |
|---|---|---|
| Layer 0 · engine | `engine.mbt` / `util.mbt` | D1-D8 memory network + #22 TM/TB + #2-#7 extensions + S1 fuzzy-match |
| Layer 2 · service | `cmd/service/` | 24 REST endpoints (`/api/*`) + `/mcp` MCP server + web workbench |
| Layer 1 · knowledge | `README.md`, `AGENTS.md`, web workbench | docs + how-to |

## Fast start (Windows, verified environment)

```powershell
# one-shot: env check -> build -> start service -> seed sample TM -> smoke test
powershell -ExecutionPolicy Bypass -File scripts/dev.ps1
```

Or step by step:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup.ps1   # detect moon/MSVC, validate cl.exe paths
powershell -ExecutionPolicy Bypass -File scripts/build.ps1   # compile cmd/service (native)
powershell -ExecutionPolicy Bypass -File scripts/run.ps1     # start http://127.0.0.1:8787
powershell -ExecutionPolicy Bypass -File scripts/seed.ps1    # load sample TM pairs (optional)
powershell -ExecutionPolicy Bypass -File scripts/smoke.ps1   # verify endpoints + MCP
```

Engine tests (no MSVC needed):

```bash
moon test --target wasm-gc        # 89/89 green
```

## Consuming the service

- **REST**: 24 个 `/api/*` 端点（多数 `POST` JSON 体，`/api/ping` 与 `/api/tm_count` 为 GET）。示例
  `POST /api/fuzzy_match {"query":"电池包热管理方案","k":3,"threshold":0.5}` → Top-K with
  white-box scores (`sim_token/sim_tfidf/sim_char/sim_ngram/sim_tokenset`)（详见 `README.md` → Service Layer）。
- **MCP**: `POST /mcp` speaks JSON-RPC 2.0 (spec 2025-11-25). `initialize` → `tools/list` (24 tools)
  → `tools/call {"name":"fuzzy_match","arguments":{...}}`. Standard MCP config:
  `{"mcpServers":{"yimai":{"url":"http://127.0.0.1:8787/mcp"}}}`.
- **Web workbench**: open `http://127.0.0.1:8787/` (three panels: TM search / term check / evidence chain).
- **Persistence**: writes `tm_store.json` (atomic tmp+rename) next to the service working directory;
  restart restores state automatically.

## MCP integration per harness

| Harness | Config file | Example |
|---|---|---|
| **Claude Desktop** | `~/.config/claude-desktop/mcp.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows) | `{"mcpServers":{"yimai":{"url":"http://127.0.0.1:8787/mcp"}}}` |
| **Claude Code** | `~/.claude/mcp.json` or via `/mcp` slash command | see [`CLAUDE.md`](./CLAUDE.md) |
| **Gemini CLI** | `~/.gemini/settings.json` | see [`GEMINI.md`](./GEMINI.md) |
| **Cursor** | `~/.cursor/mcp.json` | `{"mcpServers":{"yimai":{"url":"http://127.0.0.1:8787/mcp"}}}` |
| **Cline** | VS Code → Cline → MCP Servers → Add → name=`yimai`, type=`http`, url=`http://127.0.0.1:8787/mcp` |
| **Continue.dev** | `~/.continue/config.json` under `"mcpServers"` | same shape |
| **Roo Code** | VS Code → Roo Code → MCP → Add Server (HTTP transport) |
| **Windsurf** | `~/.windsurf/mcp.json` (Cascade MCP) | same shape |
| **GitHub Copilot (Coding Agent)** | `.github/copilot-setup-steps.yml` already installs MoonBit (see file) |

All clients use the same MCP shape. The only thing that varies is the config
file path. After `scripts/run.ps1` is up, all clients should be able to
`tools/list` and see the 24 tools.

## Windows prerequisites (native build)

- **MSVC** is mandatory for `cmd/service` native target (async `thread_pool.c` has a hard `#error`
  otherwise; mingw/gcc won't work).
- `link.native.cc` in `cmd/service/moon.pkg` and `cmd/main/moon.pkg` points at `cl.exe`. **If the
  path is machine-specific, update both files** (setup.ps1 detects a missing cl.exe and prints a hint).
- After a **MoonBit toolchain upgrade**, rebuild the core native bundle once:
  `cd ~/.moon/lib/core && moon clean --target-dir _build/native && moon bundle --target native --release`
  (otherwise `moonc` link asserts).

## Code conventions

- Engine must stay **zero-dependency** (`core/json` + `core/math` only). All I/O lives in `cmd/service`.
- Determinism is a hard contract: same input ⇒ byte-identical `to_json` output (R15).
- MoonBit gotchas:
  - async calls need **no `await`** (`await` is a reserved word).
  - no top-level `let mut` — use `@ref.Ref[T]` (see `cmd/service/main.mbt`).
  - `Json` is an FFI type: **cannot construct values** like `Json::Object`/`Json::Bool`; build them
    via `@lib.obj/str_json/num_json/arr_json` (util.mbt) or `Int.to_json()/Bool.to_json()` (builtin ToJson).
  - `Request.path` includes the full query string — strip `?` before routing (see `extract_base_path`).
  - `@fs.write_file` default `create_mode=TruncateExisting` fails when the file is absent — pass
    `create_mode=@fs.CreateMode::CreateOrTruncate` for first writes.
- `moon fmt` reformats the whole repo (2585-line diffs historically) — avoid unless asked.
- Keep `moon test --target wasm-gc` green on every change.

## Useful entry points

| File | Purpose |
|---|---|
| `engine.mbt` | all engine methods (fuzzy_match L1503, check_terms L1702, predict, recall, …) |
| `cmd/service/routes.mbt` | REST handlers + static file serving + `/mcp` branch |
| `cmd/service/mcp.mbt` | MCP JSON-RPC layer (initialize/tools/list/tools/call) |
| `cmd/service/tm_store.mbt` | load/save persistence (atomic write) |
| `cmd/service/web/` | front-end workbench (index.html + app.js, no build step) |
| `scripts/` | setup / build / run / seed / smoke / dev |
