# push.ps1 — 统一推送脚本（GitHub + GitLink 双 remote）
#
# 用法：
#   pwsh -File scripts/push.ps1                    # 推当前分支到两 remote
#   pwsh -File scripts/push.ps1 -Remote github     # 只推 GitHub
#   pwsh -File scripts/push.ps1 -Remote gitlink    # 只推 GitLink
#   pwsh -File scripts/push.ps1 -Remote both -Branch main
#   pwsh -File scripts/push.ps1 -DryRun            # 只看会推什么，不真推
#
# 安全：
#   - 本脚本不含 token（依赖 ~/.git-credentials + credential.helper = store）
#   - 推送前确认分支 + 远端，强制推送需显式 -Force

param(
    [ValidateSet('github', 'gitlink', 'both')] [string] $Remote = 'both',
    [string] $Branch,
    [switch] $Force,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# 当前分支
if (-not $Branch) {
    $Branch = (git rev-parse --abbrev-ref HEAD 2>&1).Trim()
    if ($Branch -eq 'HEAD' -or -not $Branch) {
        Write-Error "无法确定当前分支，请显式传 -Branch"; exit 1
    }
}

# 工作目录校验
$gitRoot = (git rev-parse --show-toplevel 2>&1).Trim()
Write-Host "[push] cwd: $gitRoot  branch: $Branch"

# 远端配置
# P2：github 默认走 ghproxy.net 代理（用户全局 gitconfig 的 insteadOf 会把
#     https://github.com/ 重写为 https://ghproxy.net/https://github.com/），
#     首次 clone 时已写入凭据；脚本沿用代理 URL，避免触发全局重写时再次
#     误将直连 URL 改回代理 URL 导致 push 失败。
$remotes = @{
    'github'  = 'https://ghproxy.net/https://github.com/Across2005/yimai-prophecy-moonbit.git'
    'gitlink' = 'https://gitlink.org.cn/Across2005/yimai_prophecy_moonbit.git'
}

function Push-To {
    param([string] $Name, [string] $Url)
    Write-Host ""
    Write-Host "[push->$Name] $Branch -> $Url"
    # 确保 remote 存在
    $exists = git remote get-url $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        git remote add $Name $Url
        Write-Host "[push->$Name] added remote"
    } elseif ($exists -ne $Url) {
        git remote set-url $Name $Url
        Write-Host "[push->$Name] updated remote URL"
    }
    # 推送
    $flag = if ($Force) { '--force' } else { '' }
    if ($DryRun) {
        $flag = '--dry-run ' + $flag
    }
    $cmd = "git push $flag $Name $Branch"
    Write-Host "[push->$Name] $cmd"
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[push->$Name] push exited with code $LASTEXITCODE"
    }
}

if ($Remote -eq 'both') {
    Push-To -Name 'github'  -Url $remotes['github']
    Push-To -Name 'gitlink' -Url $remotes['gitlink']
} else {
    Push-To -Name $Remote -Url $remotes[$Remote]
}

Write-Host ""
Write-Host "[done] Push complete (errors above if any)"
