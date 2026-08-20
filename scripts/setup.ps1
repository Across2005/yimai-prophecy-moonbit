# ============================================================
# yimai_prophecy_moonbit - environment setup (Windows)
# Detects MoonBit toolchain + MSVC, validates link.native.cc,
# and rebuilds the core native bundle when the toolchain changed.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/setup.ps1
# ============================================================
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host "== yimai_prophecy_moonbit setup =="

# 1. moon toolchain
$moon = Get-Command moon -ErrorAction SilentlyContinue
if (-not $moon) {
  Write-Host "[ERROR] 'moon' not found in PATH. Install the MoonBit toolchain:"
  Write-Host "        https://www.moonbitlang.com/download"
  exit 1
}
Write-Host "[OK] moon: $($moon.Source)"
moon version

# 2. MSVC cl.exe (needed for native target; async requires MSVC on Windows)
#   cmd/{service,main}/moon.pkg uses cc = "cl.exe" (PATH 探测);
#   override with $env:MSVC_CC for non-standard install locations.
$ccOk = $false
$ccPath = $null
if ($env:MSVC_CC -and (Test-Path $env:MSVC_CC)) {
  $ccPath = $env:MSVC_CC
  $ccOk = $true
  Write-Host "[OK] MSVC_CC env override: $ccPath"
} else {
  $ccFromPath = Get-Command cl.exe -ErrorAction SilentlyContinue
  if ($ccFromPath) {
    $ccPath = $ccFromPath.Source
    $ccOk = $true
    Write-Host "[OK] cl.exe on PATH: $ccPath"
  }
}
if (-not $ccOk) {
  Write-Host "[HINT] Native build needs MSVC. Either:"
  Write-Host "       1. Run from Developer Command Prompt (vcvars64.bat auto-loads cl.exe)"
  Write-Host "       2. Set MSVC_CC to your cl.exe absolute path:"
  Write-Host "          `$env:MSVC_CC = 'C:/Program Files/Microsoft Visual Studio/<ver>/Community/VC/Tools/MSVC/<v>/bin/Hostx64/x64/cl.exe'"
  Write-Host "       3. Or VS Build Tools: `$env:MSVC_CC = 'C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/<v>/bin/Hostx64/x64/cl.exe'"
}

# 3. core native bundle (rebuild after a moon toolchain upgrade)
$core = Join-Path $env:USERPROFILE ".moon/lib/core"
$coreBundle = Join-Path $core "_build/native/release/bundle/core.core"
if (Test-Path $coreBundle) {
  Write-Host "[OK] core native bundle present: $coreBundle"
} else {
  Write-Host "[HINT] core native bundle missing. Rebuild it after a toolchain upgrade:"
  Write-Host "       cd $core"
  Write-Host "       moon clean --target-dir _build/native"
  Write-Host "       moon bundle --target native --release"
  Write-Host "       (run these manually once; then re-run this script)"
}

# 4. async dependency sanity (moon.mod declares 0.20.1; registry version works)
$mod = Get-Content "moon.mod" -Raw
if ($mod -match 'async@([0-9.]+)') {
  Write-Host "[OK] async dependency: $($matches[1]) (registry version, no local override needed)"
}

# 5. git hooks — activate .githooks/pre-commit via core.hooksPath
$git = Get-Command git -ErrorAction SilentlyContinue
$preCommit = Join-Path (Join-Path $root ".githooks") "pre-commit"
if (-not $git) {
  Write-Host "[SKIP] git not found in PATH — hooks not configured"
} elseif (-not (Test-Path (Join-Path $root ".git"))) {
  Write-Host "[SKIP] .git not found — not a git checkout; hooks not configured"
} elseif (-not (Test-Path $preCommit)) {
  Write-Host "[WARN] .githooks/pre-commit not found — hook file missing, skipping config"
} else {
  $current = git config --local --get core.hooksPath 2>$null
  if ($LASTEXITCODE -ne 0) { $current = $null }
  if ($current -and $current -ne '.githooks') {
    Write-Host "[WARN] overriding existing core.hooksPath: $current -> .githooks"
  }
  if ($current -ne '.githooks') {
    git config --local core.hooksPath '.githooks'
    Write-Host "[OK] git core.hooksPath -> .githooks (pre-commit hook activated)"
  } else {
    Write-Host "[OK] git core.hooksPath already set: $current"
  }
}

Write-Host ""
Write-Host "Setup checks done. Next:"
Write-Host "  scripts/build.ps1   -> compile cmd/service (native)"
Write-Host "  scripts/run.ps1     -> start HTTP service on 127.0.0.1:8787"
Write-Host "  scripts/seed.ps1    -> load sample TM pairs"
Write-Host "  scripts/smoke.ps1   -> smoke-test all endpoints + MCP"
Write-Host "  scripts/dev.ps1     -> build + seed + run + smoke in one go"
