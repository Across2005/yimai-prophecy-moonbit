# ============================================================
# yimai_prophecy_moonbit - smoke test (13 REST endpoints + MCP)
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/smoke.ps1
# Assumes the service is running on 127.0.0.1:8787
# ============================================================
$base = "http://127.0.0.1:8787"
$pass = 0; $fail = 0

function Check($name, $cond) {
  if ($cond) { Write-Host "[PASS] $name"; $script:pass++ }
  else       { Write-Host "[FAIL] $name"; $script:fail++ }
}

# --- REST endpoints ---
$ping = Invoke-RestMethod "$base/api/ping"
Check "ping" ($ping.status -eq "ok")

$count0 = (Invoke-RestMethod "$base/api/tm_count").tm_count

$add = Invoke-RestMethod -Method Post -Uri "$base/api/add_tm" -ContentType "application/json" `
       -Body '{"src":"smoke test pair","tgt":"smoke 测试句对"}'
Check "add_tm" ($add.status -eq "stored")

$count1 = (Invoke-RestMethod "$base/api/tm_count").tm_count
Check "tm_count incremented" ($count1 -eq $count0 + 1)

$fm = Invoke-RestMethod -Method Post -Uri "$base/api/fuzzy_match" -ContentType "application/json" `
      -Body '{"query":"smoke test","k":1,"threshold":0.3}'
Check "fuzzy_match returns array" ($fm.Count -ge 1)

$ct = Invoke-RestMethod -Method Post -Uri "$base/api/check_terms" -ContentType "application/json" `
      -Body '{"source":"install the sensor","target":"安装设备"}'
Check "check_terms returns array" ($ct -is [array])

$ob = Invoke-RestMethod -Method Post -Uri "$base/api/observe" -ContentType "application/json" `
      -Body '{"text":"parse source file structure","mtype":"step"}'
Check "observe learned" ($ob.status -eq "learned")

$pr = Invoke-RestMethod -Method Post -Uri "$base/api/predict" -ContentType "application/json" -Body '{"k":1}'
Check "predict returns predictions" ($null -ne $pr.predictions)

$qa = Invoke-RestMethod -Method Post -Uri "$base/api/qe_auto" -ContentType "application/json" `
      -Body '{"source":"a","target":"b","match_rate":0.5}'
Check "qe_auto score" ($null -ne $qa.qe_score)

# --- MCP handshake ---
$init = Invoke-RestMethod -Method Post -Uri "$base/mcp" -ContentType "application/json" `
        -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
Check "MCP initialize" ($init.result.protocolVersion -eq "2025-11-25")

$tools = Invoke-RestMethod -Method Post -Uri "$base/mcp" -ContentType "application/json" `
         -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
Check "MCP tools/list = 13" ($tools.result.tools.Count -eq 13)

$call = Invoke-RestMethod -Method Post -Uri "$base/mcp" -ContentType "application/json" `
        -Body '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tm_count","arguments":{}}}'
Check "MCP tools/call tm_count" ($call.result.content.Count -ge 1)

Write-Host ""
Write-Host "== smoke result: $pass passed, $fail failed =="
if ($fail -gt 0) { exit 1 }
