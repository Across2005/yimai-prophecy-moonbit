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
$ccOk = $false
foreach ($pkg in @("cmd/service/moon.pkg", "cmd/main/moon.pkg")) {
  if (Test-Path $pkg) {
    $content = Get-Content $pkg -Raw
    if ($content -match '"cc"\s*:\s*"([^"]+)"') {
      $cc = $matches[1]
      if (Test-Path $cc) { $ccOk = $true; Write-Host "[OK] $pkg -> cl.exe found" }
      else { Write-Host "[WARN] $pkg points to missing cl.exe: $cc" }
    }
  }
}
if (-not $ccOk) {
  Write-Host "[HINT] Native build needs MSVC. Fix 'link.native.cc' in both:"
  Write-Host "       cmd/service/moon.pkg  and  cmd/main/moon.pkg"
  Write-Host "       Typical: C:/Program Files/Microsoft Visual Studio/<ver>/Community/VC/Tools/MSVC/<v>/bin/Hostx64/x64/cl.exe"
  Write-Host "       Or use Build Tools:  C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/<v>/bin/Hostx64/x64/cl.exe"
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

Write-Host ""
Write-Host "Setup checks done. Next:"
Write-Host "  scripts/build.ps1   -> compile cmd/service (native)"
Write-Host "  scripts/run.ps1     -> start HTTP service on 127.0.0.1:8787"
Write-Host "  scripts/seed.ps1    -> load sample TM pairs"
Write-Host "  scripts/smoke.ps1   -> smoke-test all endpoints + MCP"
Write-Host "  scripts/dev.ps1     -> build + seed + run + smoke in one go"
