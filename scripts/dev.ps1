# ============================================================
# yimai_prophecy_moonbit - one-shot dev workflow
#   check env -> build -> start service -> seed sample TM -> smoke test
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/dev.ps1
# ============================================================
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "==== Step 1/5: environment check ===="
& "$PSScriptRoot/setup.ps1"

Write-Host ""
Write-Host "==== Step 2/5: build (native) ===="
& "$PSScriptRoot/build.ps1"
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] build"; exit 1 }

Write-Host ""
Write-Host "==== Step 3/5: start service (background) ===="
$exe = Join-Path $root "_build/native/debug/build/cmd/service/service.exe"
$p = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden
Write-Host "service PID: $($p.Id)"
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "==== Step 4/5: seed sample TM ===="
& "$PSScriptRoot/seed.ps1"

Write-Host ""
Write-Host "==== Step 5/5: smoke test ===="
& "$PSScriptRoot/smoke.ps1"
if ($LASTEXITCODE -ne 0) {
  Write-Host "[FAIL] smoke"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; exit 1
}

Write-Host ""
Write-Host "==============================================="
Write-Host "All good! Service is running on http://127.0.0.1:8787"
Write-Host "  - Web workbench : http://127.0.0.1:8787/  (three-panel UI)"
Write-Host "  - REST API      : 13 endpoints under /api/*"
Write-Host "  - MCP server    : POST /mcp"
Write-Host "  - Stop          : Stop-Process -Id $($p.Id)"
Write-Host "==============================================="
