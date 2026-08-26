# ci-check-test-helpers.ps1 —— _test_helpers.mbt 漂移主动防御
# =====================================================================
# P11-D 增量：MoonBit 0.1.20260724 sub-package 不能跨包 import，所以
#   tests/{core,corpus,feature}/_test_helpers.mbt 必须在每个子包内 inline 一份。
#   根因无法在 MoonBit 限制下根除，但"何时漂移"可由 CI 拦截。
#
# 策略：
#   - tests/core/_test_helpers.mbt == tests/corpus/_test_helpers.mbt（必须完全一致）
#   - tests/feature/_test_helpers.mbt 是子集（feature 子包 helper 需求较少）
#     手动验证核心 fn 都在；本脚本只哈希，不强制相等
#
# 挂接：.githooks/pre-commit 末尾追加执行（commit 失败阻止推送）
#
# 退出码：
#   0 - 通过
#   1 - core 与 corpus 副本不一致（提示修改者同步）
#   2 - 必需文件缺失

$ErrorActionPreference = 'Stop'

$root = (Get-Item $PSScriptRoot).Parent.FullName
$core = Join-Path $root 'tests/core/_test_helpers.mbt'
$corp = Join-Path $root 'tests/corpus/_test_helpers.mbt'
$feat = Join-Path $root 'tests/feature/_test_helpers.mbt'

# 文件存在性检查
foreach ($f in @($core, $corp, $feat)) {
  if (!(Test-Path -LiteralPath $f)) {
    Write-Error "[FAIL] missing file: $f"
    exit 2
  }
}

# 哈希计算
$hCore = (Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash
$hCorp = (Get-FileHash -LiteralPath $corp -Algorithm SHA256).Hash
$hFeat = (Get-FileHash -LiteralPath $feat -Algorithm SHA256).Hash

# core == corpus 必须一致
if ($hCore -ne $hCorp) {
  Write-Error "[FAIL] _test_helpers.mbt drift detected:"
  Write-Error "  tests/core/_test_helpers.mbt    = $hCore"
  Write-Error "  tests/corpus/_test_helpers.mbt  = $hCorp"
  Write-Error ""
  Write-Error "P5 仓库整理：MoonBit 0.1.20260724 sub-package 不能跨包 import，"
  Write-Error "  helper 必须在每个子包内 inline 一份。修改时请同步 core / corpus 两份。"
  Write-Error "  tests/feature/ 是子集（部分 fn 不需要），不强制相等但需手动验证。"
  exit 1
}

Write-Output "[OK] tests/core/_test_helpers.mbt == tests/corpus/_test_helpers.mbt ($hCore)"
Write-Output "[OK] tests/feature/_test_helpers.mbt ($hFeat) — manually verify subset"
exit 0
