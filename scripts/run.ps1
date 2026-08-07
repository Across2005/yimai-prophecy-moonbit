# ============================================================
# yimai_prophecy_moonbit - run the HTTP service (native)
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/run.ps1
# Service: http://127.0.0.1:8787  (24 REST endpoints + /mcp MCP server + web workbench)
# ============================================================
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$exe = "_build/native/debug/build/cmd/service/service.exe"
if (-not (Test-Path $exe)) {
  Write-Host "[ERROR] $exe not found. Run scripts/build.ps1 first."
  exit 1
}
Write-Host "== starting yimai service on http://127.0.0.1:8787 =="
Write-Host "  - REST API : /api/ping /api/fuzzy_match /api/add_tm /api/tm_count /api/check_terms"
  Write-Host "               /api/concordance /api/qe_auto /api/predict /api/observe /api/recall"
  Write-Host "               /api/explain /api/reward /api/consolidate"
Write-Host "  - MCP      : POST /mcp (Claude Desktop: mcpServers.yimai.url = http://127.0.0.1:8787/mcp)"
Write-Host "  - Workbench: open http://127.0.0.1:8787/ in a browser"
Write-Host "  (Ctrl+C to stop)"
& $exe
