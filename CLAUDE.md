# CLAUDE.md — Claude Code Out-of-the-Box Guide

This file is auto-loaded by **Claude Code** (Anthropic's CLI coding agent) and
gives it the same first-class onboarding as `AGENTS.md`. If you use Claude Code
on this repository, you can skip `AGENTS.md` and just read this.

> Companion: see [`AGENTS.md`](./AGENTS.md) for the full multi-harness guide
> (Cursor / Copilot / Codex / Devin / Gemini CLI / Cline / Continue.dev / Roo Code / Windsurf).

## What this project is

**译脉·先知 2.0** — a deterministic memory-prediction engine written in
[MoonBit](https://www.moonbitlang.com), zero third-party dependencies
(`core/json` + `core/math` only). It remembers workflows / translation-memory
entries and predicts the next step, with white-box explanations.

Three layers, one language (no bridge code):

| Layer | Where | What |
|---|---|---|
| Layer 0 · engine | `engine.mbt` / `util.mbt` | D1-D8 memory network + #22 TM/TB + #2-#7 extensions + S1 fuzzy-match |
| Layer 2 · service | `cmd/service/` | 27 REST endpoints (`/api/*`) + `/mcp` MCP server + web workbench |
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
moon test --target wasm-gc        # 159/159 green
```

## Using this project as MCP tools (recommended for Claude Code)

After `scripts/run.ps1` is running on `http://127.0.0.1:8787`, register the
service in your Claude Code config (`~/.claude/mcp.json` or via the
`/mcp` slash command):

```json
{
  "mcpServers": {
    "yimai": {
      "url": "http://127.0.0.1:8787/mcp"
    }
  }
}
```

The service speaks MCP spec `2025-11-25` (Streamable HTTP, JSON-RPC 2.0) and
exposes **25 tools** — `fuzzy_match`, `add_tm`, `check_terms`, `concordance`,
`qe_auto`, `predict`, `observe`, `recall`, `explain`, `reward`, `consolidate`,
`tm_count`, `ping`, `retrieve_prompt`, `bleu`, `chrf`, `style_check`,
`style_report`, `back_align`, `term_conflicts`, `fed_export`, `fed_import`,
`distill_inject`, `active_learning`, `mqm_re_annotate`.

## Determinism contract (read before refactoring)

This project enforces a hard R15 contract: identical input sequences must
produce **byte-identical** `to_json` output. A logical clock (`self.clock`)
replaces wall-clock time. Do not introduce `Date::now()`, `Random::new()`, or
any non-deterministic source into the engine path.

Local pre-commit gate (`.githooks/pre-commit`) already runs
`moon check && moon test --target wasm-gc` before every commit. After
cloning, activate it once:

```bash
git config core.hooksPath .githooks
```

## MoonBit gotchas to remember

- async calls need **no `await`** (`await` is a reserved word).
- no top-level `let mut` — use `@ref.Ref[T]` (see `cmd/service/main.mbt`).
- `Json` is an FFI type: **cannot construct values** like `Json::Object`/`Json::Bool`; build them
  via `@lib.obj/str_json/num_json/arr_json` (util.mbt) or `Int.to_json()/Bool.to_json()` (builtin ToJson).
- `Request.path` includes the full query string — strip `?` before routing (see `extract_base_path`).
- `@fs.write_file` default `create_mode=TruncateExisting` fails when the file is absent — pass
  `create_mode=@fs.CreateMode::CreateOrTruncate` for first writes.
- `moon fmt` reformats the whole repo (2585-line diffs historically) — avoid unless asked.
- **Map ≠ HashMap** — `Map[String, T]` (MoonBit) is **ordered by insertion** and is
  load-bearing for the determinism contract (R15): `predict` scores, `fuzzy_match` ranking,
  `metrics` JSON field order all depend on iteration order. Do **not** swap in `@hashmap`
  or any `HashSet/HashMap` from a hypothetical future stdlib — that would break R15 silently.

## Useful entry points

| File | Purpose |
|---|---|
| `engine.mbt` | all engine methods (fuzzy_match L1737, check_terms L2085, predict L954, recall L804, …) |
| `cmd/service/routes.mbt` | REST handlers + static file serving + `/mcp` branch |
| `cmd/service/mcp.mbt` | MCP JSON-RPC layer (initialize/tools/list/tools/call) |
| `cmd/service/tm_store.mbt` | load/save persistence (atomic write) |
| `cmd/service/web/` | front-end workbench (index.html + app.js, no build step) |
| `scripts/` | setup / build / run / seed / smoke / dev |
