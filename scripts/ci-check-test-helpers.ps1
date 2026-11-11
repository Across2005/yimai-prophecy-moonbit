# ci-check-test-helpers.ps1 - drift guard for _test_helpers.mbt copies
# =====================================================================
# MoonBit sub-packages cannot import each other's symbols, so
#   tests/{core,corpus,feature}/_test_helpers.mbt must be inlined per package.
# The root cause cannot be removed under that constraint, but drift can be
# caught by CI.
#
# Policy:
#   - tests/core/_test_helpers.mbt == tests/corpus/_test_helpers.mbt (must match)
#   - tests/feature/_test_helpers.mbt is a subset (feature needs fewer helpers);
#     this script only hashes it, it does not enforce equality
#
# Hooked into .githooks/pre-commit (a failure blocks the commit).
#
# Exit codes:
#   0 - pass
#   1 - core and corpus copies drifted
#   2 - required file missing
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less files
#   using the OEM code page, so non-ASCII literals break parsing.

$ErrorActionPreference = 'Stop'

$root = (Get-Item $PSScriptRoot).Parent.FullName
$core = Join-Path $root 'tests/core/_test_helpers.mbt'
$corp = Join-Path $root 'tests/corpus/_test_helpers.mbt'
$feat = Join-Path $root 'tests/feature/_test_helpers.mbt'

foreach ($f in @($core, $corp, $feat)) {
  if (!(Test-Path -LiteralPath $f)) {
    Write-Error "[FAIL] missing file: $f"
    exit 2
  }
}

$hCore = (Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash
$hCorp = (Get-FileHash -LiteralPath $corp -Algorithm SHA256).Hash
$hFeat = (Get-FileHash -LiteralPath $feat -Algorithm SHA256).Hash

if ($hCore -ne $hCorp) {
  Write-Error "[FAIL] _test_helpers.mbt drift detected:"
  Write-Error "  tests/core/_test_helpers.mbt    = $hCore"
  Write-Error "  tests/corpus/_test_helpers.mbt  = $hCorp"
  Write-Error ""
  Write-Error "MoonBit sub-packages cannot import each other, so helpers must be"
  Write-Error "inlined per package. When editing, sync both core and corpus copies."
  Write-Error "tests/feature/ is a subset; verify manually instead of enforcing equality."
  exit 1
}

Write-Output "[OK] tests/core/_test_helpers.mbt == tests/corpus/_test_helpers.mbt ($hCore)"
Write-Output "[OK] tests/feature/_test_helpers.mbt ($hFeat) - manually verify subset"
exit 0
