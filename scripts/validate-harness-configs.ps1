# ============================================================
# yimai_prophecy_moonbit - 13 harness config schema validator
#   读 docs/harness-configs/harness_manifest.json
#   逐个 harness 解析 config 文件 + 断言 URL 契约
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/validate-harness-configs.ps1
# Exit:   0 = 13/13 PASS ; 1 = 至少一个 FAIL
# ============================================================
$ErrorActionPreference = 'Stop'

# Step 0/4: 定位 manifest + 读 UTF-8（PowerShell 5.1 Get-Content 默认 ANSI，
# 遇中文会乱码，cody.json 注释段就是中文，强制走 .NET 显式 UTF-8 无 BOM）
$root         = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root 'docs/harness-configs/harness_manifest.json'
$utf8NoBom    = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $manifestPath)) {
  Write-Host "[FATAL] manifest not found: $manifestPath" -ForegroundColor Red
  exit 1
}

# Step 1/4: 解析 manifest —— 单一源（version / service / harnesses[*]）
$manifest = [System.IO.File]::ReadAllText($manifestPath, $utf8NoBom) | ConvertFrom-Json
$serviceUrl  = $manifest.service.url
$serviceSpec = $manifest.service.spec
$harnesses   = $manifest.harnesses

Write-Host "==== yimai harness config schema validator ===="
Write-Host ("manifest: {0} (v{1})" -f $manifestPath, $manifest.version)
Write-Host ("service:  url={0}  spec={1}" -f $serviceUrl, $serviceSpec)
Write-Host ("harnesses: {0} entries" -f $harnesses.Count)
Write-Host ""

# Step 2/4: 小工具 —— 按 PSObjectProperty 路径链取值；任意一段为 $null 即返回 $null
function Get-ByPath {
  param($Obj, [string[]]$Path)
  $cur = $Obj
  foreach ($seg in $Path) {
    if ($null -eq $cur) { return $null }
    $cur = $cur.$seg
    if ($null -eq $cur) { return $null }
  }
  return $cur
}

# 校验 JSON harness 中可选枚举字段：若声明，则必须落在白名单内。
function Test-ValidEnumField {
  param($Obj, [string[]]$Path, [string[]]$Allowed)
  $val = Get-ByPath $obj $Path
  if ($null -ne $val -and "$val" -notin $Allowed) {
    $name = $Path -join '.'
    throw "$name='$val' not in {$($Allowed -join ', ')}"
  }
}

# 简单 TOML 解析器：仅支持 `[section.sub]` 表头 + 标量键值（string / bareword）。
# 够用即可 —— codex.toml 只有一段 [mcp_servers.yimai] + url/transport 两键。
# 跳过空行 + `#` 注释行 + 段内 `key = # comment` 后的注释尾巴。
function Get-TomlSection {
  param([string]$Text, [string]$SectionPath)   # e.g. 'mcp_servers.yimai'

  $lines      = $Text -split "`r?`n"
  $inSection  = $false
  $depth      = 0                                 # 嵌套表深度（0 = 顶级）
  $kv         = [ordered]@{}                      # 当前 section 内的 key/value

  foreach ($raw in $lines) {
    # 去掉行尾注释 + 修剪空白
    $line = ($raw -replace '\s+#.*$', '') -replace '^\s+', '' -replace '\s+$', ''
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line.StartsWith('#')) { continue }

    # 表头 [a.b] —— 切分 section
    if ($line -match '^\[\s*([^\[\]]+?)\s*\]$') {
      $cur = $Matches[1]
      if ($cur -eq $SectionPath) {
        $inSection = $true; $depth = 0
        $kv = [ordered]@{}
      } else {
        $inSection = $false
      }
      continue
    }
    if (-not $inSection) { continue }

    # 子表头 [[foo.bar]] 或 [foo]（暂不递归）
    if ($line -match '^\[\[') { continue }

    # key = value  (string + bareword; both keys in codex.toml are strings)
    if ($line -match '^([A-Za-z0-9_\.\-]+)\s*=\s*"([^"]*)"\s*$') {
      $kv[$Matches[1]] = $Matches[2]
    } elseif ($line -match '^([A-Za-z0-9_\.\-]+)\s*=\s*([^\s]+)\s*$') {
      $kv[$Matches[1]] = $Matches[2]
    }
  }
  return $kv
}

# Step 3/4: 逐个 harness 校验
$pass = 0; $fail = 0
$rows = @()

foreach ($h in $harnesses) {
  $cfgPath = Join-Path (Split-Path $manifestPath -Parent) $h.config_file
  $name    = $h.name
  $form    = $h.form
  $urlResolved = 'n/a'
  $status  = 'PASS'
  $reason  = ''

  try {
    if (-not (Test-Path $cfgPath)) {
      throw "config file not found"
    }

    switch ($form) {
      'json' {
        # PowerShell 5.1 自带 ConvertFrom-Json；用 .NET UTF-8 读源避免 ANSI 误解码
        $text = [System.IO.File]::ReadAllText($cfgPath, $utf8NoBom)
        $obj  = $text | ConvertFrom-Json
        if ($null -eq $h.top_key) {
          throw "top_key is null in manifest but form=json (need explicit top_key)"
        }
        # top_key 是字面属性名（含 cody.mcp.servers 这种点号 key）—— PS 5.1 走 .PSObject.Properties
        $top  = Get-ByPath $obj @($h.top_key)
        if ($null -eq $top) {
          throw "top_key '$($h.top_key)' not found in $($h.config_file)"
        }
        if ($null -eq $h.url_path -or $h.url_path.Count -eq 0) {
          throw "url_path is empty in manifest (json form 必须声明 url_path)"
        }
        $urlResolved = Get-ByPath $top $h.url_path
        if ($null -eq $urlResolved) {
          throw "url_path '$($h.url_path -join '.')' not reachable from top_key"
        }
        if ($urlResolved -ne $serviceUrl) {
          throw "url='$urlResolved' != service.url='$serviceUrl'"
        }
        # P6 加固：JSON harness 若声明 type/transport，必须为允许的合法值
        Test-ValidEnumField $top @('type') @('http','streamable-http')
        Test-ValidEnumField $top @('transport') @('http','streamable-http')
      }
      'toml' {
        $text = [System.IO.File]::ReadAllText($cfgPath, $utf8NoBom)
        $sectionName = "$($h.top_key).yimai"
        $kv = Get-TomlSection -Text $text -SectionPath $sectionName
        if ($kv.Count -eq 0) {
          throw "TOML section [$sectionName] not found"
        }
        if (-not $kv.Contains('url')) {
          throw "TOML key 'url' missing in [$sectionName]"
        }
        if (-not $kv.Contains('transport')) {
          throw "TOML key 'transport' missing in [$sectionName] (Codex ≥ 0.46 强制显式 transport)"
        }
        $urlResolved = $kv['url']
        if ($urlResolved -ne $serviceUrl) {
          throw "url='$urlResolved' != service.url='$serviceUrl'"
        }
        # transport 软校验：允许 http / streamable-http（Codex 0.46+ 写 http）
        $tr = $kv['transport']
        if ($tr -notin @('http', 'streamable-http')) {
          throw "transport='$tr' not in {http, streamable-http}"
        }
      }
      'yaml' {
        # PS 5.1 没有 ConvertFrom-Yaml（PS 7+ 内置）；降级到文本搜索 + 关键字断言
        $text = [System.IO.File]::ReadAllText($cfgPath, $utf8NoBom)
        # 用文件里是否含 service.url 区分 config 型 (aider) vs 文档型 (github-copilot)
        $hasUrl = $text -match [regex]::Escape($serviceUrl)
        if ($hasUrl) {
          # config 型：URL 必须字面命中；附加断言含 yimai + transport 关键字
          $urlResolved = $serviceUrl
          if ($text -notmatch 'yimai')     { throw "name 'yimai' not found in $($h.config_file)" }
          if ($text -notmatch 'transport') { throw "transport keyword missing in $($h.config_file)" }
        } else {
          # 文档型：要求含 runner 隔离说明 + workflow 路径
          if ($text -notmatch '127\.0\.0\.1:8787') { throw "127.0.0.1:8787 not mentioned" }
          if ($text -notmatch 'workflow')           { throw "workflow reference missing" }
          if ($text -notmatch 'runner')             { throw "runner caveat missing" }
          $urlResolved = 'n/a (doc-only)'
        }
      }
      default {
        throw "unsupported form '$form' in manifest"
      }
    }
  } catch {
    $status = 'FAIL'
    $reason = $_.Exception.Message
  }

  if ($status -eq 'PASS') { $script:pass++ } else { $script:fail++ }
  $row = [pscustomobject]@{
    Harness = $name
    Form    = $form
    Status  = $status
    URL     = $urlResolved
    Reason  = $reason
  }
  $rows += $row
}

# Step 4/4: 打印结果表 + 汇总
$rows | Format-Table -AutoSize -Property Harness, Form, Status, URL, Reason | Out-String -Width 200 | Write-Host
Write-Host ""
Write-Host ("== validate-harness-configs: {0} passed, {1} failed ==" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
