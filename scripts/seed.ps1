# ============================================================
# yimai_prophecy_moonbit - seed sample TM pairs
# Reads scripts/seed_tm.json and POSTs each pair to /api/add_tm.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/seed.ps1
# Assumes the service is running on 127.0.0.1:8787
# ============================================================
$root = Split-Path -Parent $PSScriptRoot
# 显式 UTF-8 读取（PowerShell 5.1 Get-Content 默认编码会破坏中文）
$json = [System.IO.File]::ReadAllText("$root/scripts/seed_tm.json", [System.Text.Encoding]::UTF8)
$data = $json | ConvertFrom-Json
$base = "http://127.0.0.1:8787"
$added = 0
foreach ($pair in $data) {
  $body = @{ src = $pair.src; tgt = $pair.tgt } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Method Post -Uri "$base/api/add_tm" -ContentType "application/json" -Body $body
    if ($r.status -eq "stored") { $added++ }
  } catch { Write-Host "[skip] $($pair.src): $_" }
}
Write-Host "== seeded $added / $($data.Count) TM pairs =="
$c = Invoke-RestMethod "$base/api/tm_count"
Write-Host "tm_count now: $($c.tm_count)"
