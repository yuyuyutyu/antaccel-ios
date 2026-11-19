<#
.SYNOPSIS
  安心加速器 iOS 壳 —— Windows 端 IPA 重签脚本(基于 zsign)

.DESCRIPTION
  输入任意 IPA(本工程云构建产物 / 官方 iOS 包),用你的 p12 + mobileprovision 重签。

.EXAMPLE
  .\resign.ps1 -Ipa .\AntiAccel-unsigned.ipa -P12 .\cert.p12 -P12Password 123456 -Profile .\profile.mobileprovision -Zsign .\tools\zsign.exe
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Ipa,
    [Parameter(Mandatory = $true)][string]$P12,
    [string]$P12Password = "",
    [Parameter(Mandatory = $true)][string]$Profile,
    [string]$Zsign = "",
    [string]$Out = "",
    [string]$BundleId = "",
    [switch]$AdHoc
)

$ErrorActionPreference = "Stop"
function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

foreach ($f in @($Ipa, $P12, $Profile)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "路径不存在: $f" }
}
if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = [System.IO.Path]::Combine((Split-Path -Parent (Resolve-Path -LiteralPath $Ipa)), "signed-" + (Split-Path -Leaf $Ipa))
}

# --- 定位 zsign ---
if ([string]::IsNullOrWhiteSpace($Zsign)) {
    $candidates = @(
        (Join-Path $PSScriptRoot "zsign.exe"),
        (Join-Path (Get-Location) "zsign.exe"),
        (Join-Path (Get-Location) "tools\zsign.exe")
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $Zsign = $c; break } }
    if ([string]::IsNullOrWhiteSpace($Zsign)) {
        $cmd = Get-Command zsign.exe -ErrorAction SilentlyContinue
        if ($cmd) { $Zsign = $cmd.Source }
    }
}
if ([string]::IsNullOrWhiteSpace($Zsign) -or -not (Test-Path -LiteralPath $Zsign)) {
    Warn "缺少 zsign.exe。下载 zsign(zhlynn/zsign 的 Windows 构建)后放到脚本同目录,或用 -Zsign 指定完整路径。"
    throw "缺少 zsign 可执行文件"
}
Good "zsign = $Zsign"

# --- 读取描述文件里的 Bundle ID / TeamID ---
function Get-ProfileMeta([string]$path) {
    $result = @{ ApplicationIdentifier = ""; TeamId = ""; Uuid = ""; Name = ""; Expiration = ""; AllDevices = $false; GetTaskAllow = $false }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms
        $cms.Decode($bytes)
        $content = [System.Text.Encoding]::UTF8.GetString($cms.ContentInfo.Content)
    } catch {
        Warn "CMS 解码失败,尝试直接按文本解析: $($_.Exception.Message)"
        $content = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($path))
    }
    if ($content -match "(?s)<key>application-identifier</key>\s*<string>([^<]+)</string>") { $result.ApplicationIdentifier = $Matches[1] }
    if ($content -match "(?s)<key>com\.apple\.developer\.team-identifier</key>\s*<string>([^<]+)</string>") { $result.TeamId = $Matches[1] }
    if ($content -match "(?s)<key>UUID</key>\s*<string>([^<]+)</string>") { $result.Uuid = $Matches[1] }
    if ($content -match "(?s)<key>Name</key>\s*<string>([^<]+)</string>") { $result.Name = $Matches[1] }
    if ($content -match "(?s)<key>CreationDate</key>\s*<date>([^<]+)</date>") { }
    if ($content -match "(?s)<key>ExpirationDate</key>\s*<date>([^<]+)</date>") { $result.Expiration = $Matches[1] }
    if ($content -match "<key>ProvisionsAllDevices</key>\s*<true/>") { $result.AllDevices = $true }
    if ($content -match "<key>get-task-allow</key>\s*<true/>") { $result.GetTaskAllow = $true }
    return $result
}

$meta = Get-ProfileMeta (Resolve-Path -LiteralPath $Profile)
$profileBundle = ""
if ($meta.ApplicationIdentifier -match "^(.+?)\.(.+)$") {
    $profileTeam = $Matches[1]
    $profileBundle = $Matches[2]
}
Info "描述文件名 : $($meta.Name)"
Info "描述文件UUID: $($meta.Uuid)"
Info "配置的包名  : $profileBundle"
Info "TeamID      : $profileTeam"
Info "到期时间    : $($meta.Expiration)"
if ($meta.AllDevices) { Good "企业(In-House)证书: 不校验 UDID,可直接装机" } else { Warn "非企业证书: 手机 UDID 必须已登记在描述文件里,否则装完闪退" }

if ([string]::IsNullOrWhiteSpace($BundleId)) { $BundleId = $profileBundle }
if ([string]::IsNullOrWhiteSpace($BundleId)) { throw "描述文件里没解出包名,请用 -BundleId 手动指定" }
Info "本次签入包名: $BundleId"

# --- 调用 zsign ---
$args = @("-k", $P12)
if (-not [string]::IsNullOrWhiteSpace($P12Password)) { $args += @("-p", $P12Password) }
$args += @("-m", $Profile, "-b", $BundleId, "-o", $Out, "-z", "9")
if ($AdHoc) { $args += @("-a") }
$args += @($Ipa)

Info ("执行: " + $Zsign + " " + ($args -join " "))
& $Zsign @args
$code = $LASTEXITCODE
if ($code -ne 0) { throw "zsign 返回 $code,签名失败(多半是 p12 口令错或证书链不全)" }

if (-not (Test-Path -LiteralPath $Out)) { throw "签名后没有产出 IPA: $Out" }
$item = Get-Item -LiteralPath $Out
Good ("产出: " + $item.FullName + "  " + [math]::Round($item.Length / 1MB, 2) + " MB")

# --- 解包自检 ---
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Out)
    $names = $zip.Entries | ForEach-Object { $_.FullName }
    $zip.Dispose()
    $hasPayload = ($names | Where-Object { $_ -like "Payload/*.app/Info.plist" }).Count -gt 0
    $hasSig = ($names | Where-Object { $_ -like "Payload/*.app/_CodeSignature/CodeResources" }).Count -gt 0
    $hasProv = ($names | Where-Object { $_ -like "Payload/*.app/embedded.mobileprovision" }).Count -gt 0
    Info "IPA 结构: Payload/Info.plist=$hasPayload  签名=$hasSig  描述文件=$hasProv"
    if (-not ($hasPayload -and $hasSig -and $hasProv)) { Warn "结构不完整,装机会失败" }
} catch {
    Warn "解包自检跳过: $($_.Exception.Message)"
}

Good "完成。投放方式: 爱思助手 / Sideloadly / OTA 清单页"
Info "装完首次打开若提示未受信任: 设置 -> 通用 -> VPN与设备管理 -> 信任 $profileTeam"
