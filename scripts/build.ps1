# ============================================================
# yimai_prophecy_moonbit - build cmd/service (native)
# Locates MSVC + Windows SDK and sets INCLUDE/LIB, then runs
#   moon build cmd/service --target native
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/build.ps1
# ============================================================
# NOTE: $ErrorActionPreference stays at default ("Continue") so native stderr
# (moon/cl progress + warnings) does not terminate the script.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$vs = @(
  "C:/Program Files/Microsoft Visual Studio/18/Community",
  "C:/Program Files/Microsoft Visual Studio/17/Community",
  "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools",
  "C:/Program Files (x86)/Microsoft Visual Studio/2022/Community"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $vs) {
  Write-Host "[ERROR] Visual Studio / Build Tools not found. Install MSVC (C++ workload)."
  Write-Host "        Then fix 'link.native.cc' in cmd/service/moon.pkg and cmd/main/moon.pkg."
  exit 1
}
$msvc = Get-ChildItem "$vs/VC/Tools/MSVC" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
if (-not $msvc) {
  Write-Host "[ERROR] No MSVC toolset under $vs/VC/Tools/MSVC"
  exit 1
}
$kits = "C:/Program Files (x86)/Windows Kits/10"
$inc = Get-ChildItem "$kits/Include" -Directory -ErrorAction SilentlyContinue |
       Sort-Object Name -Descending | Select-Object -First 1
$lib = Get-ChildItem "$kits/Lib" -Directory -ErrorAction SilentlyContinue |
       Sort-Object Name -Descending | Select-Object -First 1
if (-not $inc -or -not $lib) {
  Write-Host "[ERROR] Windows SDK not found under $kits"
  exit 1
}

$env:INCLUDE = "$($msvc.FullName)\include;$($inc.FullName)\ucrt;$($inc.FullName)\um;$($inc.FullName)\shared;$($inc.FullName)\winrt"
$env:LIB = "$($msvc.FullName)\lib\x64;$($lib.FullName)\ucrt\x64;$($lib.FullName)\um\x64"

Write-Host "MSVC: $($msvc.Name)"
Write-Host "SDK : $($inc.Name)"
Write-Host "moon at: $((Get-Command moon -ErrorAction SilentlyContinue).Source)"
Write-Host "cwd  : $(Get-Location)"
Write-Host "INCLUDE: $env:INCLUDE"
Write-Host "LIB    : $env:LIB"
Write-Host "== moon build cmd/service --target native =="
& moon build cmd/service --target native
$code = $LASTEXITCODE
Write-Host "moon build exit code: $code"
if ($code -ne 0) { exit $code }
Write-Host ""
Write-Host "[OK] Built. Run:  scripts/run.ps1"
