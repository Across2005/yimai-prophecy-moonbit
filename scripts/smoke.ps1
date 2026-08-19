# ============================================================
# yimai_prophecy_moonbit - smoke test (subset of 27 REST endpoints + MCP)
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
       -Body '{"src":"smoke test pair","tgt":"smoke test translation"}'
Check "add_tm" ($add.status -eq "stored")

$count1 = (Invoke-RestMethod "$base/api/tm_count").tm_count
Check "tm_count incremented" ($count1 -eq $count0 + 1)

$fm = Invoke-RestMethod -Method Post -Uri "$base/api/fuzzy_match" -ContentType "application/json" `
      -Body '{"query":"smoke test","k":1,"threshold":0.3}'
Check "fuzzy_match returns array" ($fm.Count -ge 1)

$ct = Invoke-RestMethod -Method Post -Uri "$base/api/check_terms" -ContentType "application/json" `
      -Body '{"source":"install the sensor","target":"install the device"}'
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
Check "MCP tools/list = 25" ($tools.result.tools.Count -eq 25)

$call = Invoke-RestMethod -Method Post -Uri "$base/mcp" -ContentType "application/json" `
        -Body '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tm_count","arguments":{}}}'
Check "MCP tools/call tm_count" ($call.result.content.Count -ge 1)

# --- supplementary endpoints ---
$rp = Invoke-RestMethod -Method Post -Uri "$base/api/retrieve_prompt" -ContentType "application/json" `
      -Body '{"query":"battery thermal management","k":1,"threshold":0.3}'
Check "retrieve_prompt three-section" ($null -ne $rp.suggestions -and $null -ne $rp.terms -and $null -ne $rp.glossary)

$bleu = Invoke-RestMethod -Method Post -Uri "$base/api/bleu" -ContentType "application/json" `
        -Body '{"ref":"the cat is on the mat","hyp":"the cat is on the mat"}'
Check "bleu exact match = 1" ($bleu.bleu -eq 1)

$chrf = Invoke-RestMethod -Method Post -Uri "$base/api/chrf" -ContentType "application/json" `
        -Body '{"ref":"the cat is on the mat","hyp":"the cat is on the mat"}'
Check "chrf exact match = 1" ($chrf.chrf -eq 1)

$sc = Invoke-RestMethod -Method Post -Uri "$base/api/style_check" -ContentType "application/json" `
      -Body '{"text":"test.."}'
Check "style_check returns array" ($sc -is [array])

$ba = Invoke-RestMethod -Method Post -Uri "$base/api/back_align" -ContentType "application/json" `
      -Body '{"source":"install sensor","target":"install the sensor"}'
Check "back_align score" ($ba.align_score -gt 0.5)

$tc = Invoke-RestMethod -Method Post -Uri "$base/api/term_conflicts" -ContentType "application/json" -Body '{}'
Check "term_conflicts returns array" ($tc -is [array])

$fe = Invoke-RestMethod -Method Post -Uri "$base/api/fed_export" -ContentType "application/json" -Body '{}'
Check "fed_export" ($null -ne $fe.added)

$di = Invoke-RestMethod -Method Post -Uri "$base/api/distill_inject" -ContentType "application/json" `
      -Body '{"table":{"test":0.5}}'
Check "distill_inject" ($di.status -eq "injected")

# --- mid-cycle endpoints ---
$al = Invoke-RestMethod -Method Post -Uri "$base/api/active_learning" -ContentType "application/json" `
      -Body '{"k":3}'
Check "active_learning returns array" ($al -is [array])

$ba2 = Invoke-RestMethod -Method Post -Uri "$base/api/back_align" -ContentType "application/json" `
       -Body '{"source":"install sensor","target":"install the sensor"}'
Check "back_align ops char-level script" ($null -ne $ba2.ops -and $ba2.ops.Count -ge 1)

$alM = Invoke-RestMethod -Method Post -Uri "$base/mcp" -ContentType "application/json" `
       -Body '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"active_learning","arguments":{"k":2}}}'
Check "MCP active_learning tool call" ($alM.result.content.Count -ge 1)

# --- style report ---
$sr = Invoke-RestMethod -Method Post -Uri "$base/api/style_report" -ContentType "application/json" `
      -Body '{"text":""}'
Check "style_report memory distribution" ($null -ne $sr.sentence_count -and $sr.distribution.Count -eq 4)

$sr2 = Invoke-RestMethod -Method Post -Uri "$base/api/style_report" -ContentType "application/json" `
       -Body '{"text":"this is an extremely long translated sentence that far exceeds the average length of the memory base corpus by a huge margin"}'
Check "style_report length deviation tip" ($sr2.tips.Count -ge 1)

$srM = Invoke-RestMethod -Method Post -Uri "$base/mcp" -ContentType "application/json" `
       -Body '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"style_report","arguments":{"text":""}}}'
Check "MCP style_report tool call" ($srM.result.content.Count -ge 1)

Write-Host ""
Write-Host "== smoke result: $pass passed, $fail failed =="
if ($fail -gt 0) { exit 1 }
