# setup-credentials.ps1 - one-shot GitHub + GitLink push credential setup
# Usage (run yourself in PowerShell; token only in this terminal once):
#   powershell -ExecutionPolicy Bypass -File scripts/setup-credentials.ps1
# Safe: token via Read-Host -AsSecureString, written to ~/.git-credentials (ACL 600)

$ErrorActionPreference = 'Stop'

# 0) resolve home dir (env -> $HOME -> .NET)
$homeDir = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = $HOME }
if ([string]::IsNullOrWhiteSpace($homeDir)) {
    $homeDir = [Environment]::GetFolderPath('UserProfile')
}
if ([string]::IsNullOrWhiteSpace($homeDir)) {
    Write-Error "home dir not found"
    exit 1
}
Write-Host "[setup] home = $homeDir"

# 1) GitHub token
$ghSecure = Read-Host -Prompt "GitHub PAT" -AsSecureString
$ghToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ghSecure))
if ($ghToken.Length -lt 10) { Write-Error "GitHub token too short"; exit 1 }

# 2) GitLink token
$glSecure = Read-Host -Prompt "GitLink token" -AsSecureString
$glToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($glSecure))
if ($glToken.Length -lt 10) { Write-Error "GitLink token too short"; exit 1 }

# 3) write ~/.git-credentials (one line per host)
$credFile = Join-Path $homeDir '.git-credentials'
Write-Host "[setup] target = $credFile"
$line1 = "https://Across2005:${ghToken}@github.com"
$line2 = "https://Across2005:${glToken}@gitlink.org.cn"
try {
    [System.IO.File]::WriteAllLines($credFile, @($line1, $line2), [System.Text.Encoding]::UTF8)
} catch {
    Write-Error "write failed: $_"
    exit 1
}

# 4) set ACL (600-ish: only current user read/write, no inheritance)
try {
    $acl = Get-Acl $credFile
    $acl.SetAccessRuleProtection($true, $false)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $me, 'Read,Write', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl $credFile $acl
} catch {
    Write-Warning "ACL set failed (non-fatal): $_"
}

# 5) git global config
git config --global credential.helper store
git config --global user.name "Across2005"
git config --global user.email "Across2005@users.noreply.github.com"

# 6) verify
Write-Host ""
Write-Host "[setup] file: $credFile (size: $((Get-Item $credFile).Length) bytes)"
Write-Host "[setup] credential.helper = store"
Write-Host "[setup] user.name = Across2005"
Write-Host ""
Write-Host "[verify] GitHub ls-remote..."
git ls-remote https://github.com/Across2005/yimai-prophecy-moonbit.git HEAD 2>&1 | Select-Object -First 1
Write-Host "[verify] GitLink ls-remote..."
git ls-remote https://gitlink.org.cn/Across2005/yimai_prophecy_moonbit.git HEAD 2>&1 | Select-Object -First 1
Write-Host ""
Write-Host "[done] run scripts/push.ps1 to push"
