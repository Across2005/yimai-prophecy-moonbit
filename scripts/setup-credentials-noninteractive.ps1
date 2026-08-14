# setup-credentials-noninteractive.ps1 - for agent invocation
# Reads token from $env:GH_TOKEN and $env:GL_TOKEN (set by caller).
# Writes ~/.git-credentials, sets git config, runs ls-remote verify.
# Not intended for direct human use; use setup-credentials.ps1 instead.

$ErrorActionPreference = 'Stop'

$ghToken = $env:GH_TOKEN
$glToken = $env:GL_TOKEN
if ([string]::IsNullOrWhiteSpace($ghToken)) { Write-Error "GH_TOKEN empty"; exit 1 }
if ([string]::IsNullOrWhiteSpace($glToken)) { Write-Error "GL_TOKEN empty"; exit 1 }

$homeDir = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = $HOME }
if ([string]::IsNullOrWhiteSpace($homeDir)) {
    $homeDir = [Environment]::GetFolderPath('UserProfile')
}
if ([string]::IsNullOrWhiteSpace($homeDir)) { Write-Error "home not found"; exit 1 }

$credFile = Join-Path $homeDir '.git-credentials'
$line1 = "https://Across2005:${ghToken}@github.com"
$line2 = "https://Across2005:${glToken}@gitlink.org.cn"
[System.IO.File]::WriteAllLines($credFile, @($line1, $line2), [System.Text.Encoding]::UTF8)

# ACL: only current user read/write
try {
    $acl = Get-Acl $credFile
    $acl.SetAccessRuleProtection($true, $false)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $me, 'Read,Write', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl $credFile $acl
} catch {
    Write-Warning "ACL failed: $_"
}

# git global config
git config --global credential.helper store
git config --global user.name "Across2005"
git config --global user.email "Across2005@users.noreply.github.com"

Write-Host "[setup] $credFile ($((Get-Item $credFile).Length) bytes)"
Write-Host "[setup] helper=store user=Across2005"

# verify
Write-Host "[verify] github..."
git ls-remote https://github.com/Across2005/yimai-prophecy-moonbit.git HEAD 2>&1 | Select-Object -First 1
Write-Host "[verify] gitlink..."
git ls-remote https://gitlink.org.cn/Across2005/yimai_prophecy_moonbit.git HEAD 2>&1 | Select-Object -First 1
Write-Host "[done]"
