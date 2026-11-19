<#
.SYNOPSIS
  p12 + mobileprovision 体检器(纯 Windows,不上传任何文件)

.DESCRIPTION
  装进 iPhone 之前先跑这一遍,把证书类型/TeamID/包名/到期时间/UDID 策略一次性看明白,
  90% 的"装完闪退/装不上"都是这里能提前发现的。

.EXAMPLE
  .\inspect_signing.ps1 -P12 .\cert.p12 -P12Password 123456 -Profile .\profile.mobileprovision
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$P12,
    [string]$P12Password = "",
    [string]$Profile = ""
)

$ErrorActionPreference = "Continue"
function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Bad($m) { Write-Host "[-] $m" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $P12)) { throw "p12 不存在: $P12" }

Write-Host ""
Write-Host "=== 1. 证书 ===" -ForegroundColor White
$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]"Exportable"
try {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($P12, $P12Password, $flags)
} catch {
    Bad "p12 打开失败: $($_.Exception.Message)"
    Bad "口令错 / 不是标准 PKCS#12 / 缺少证书链 都会触发这一条"
    return
}

Good "Subject : $($cert.Subject)"
Info "Issuer  : $($cert.Issuer)"
Info "有效期  : $($cert.NotBefore) -> $($cert.NotAfter)"
Info "指纹    : $($cert.Thumbprint)"
if ($cert.HasPrivateKey) { Good "含私钥: 可以签名" } else { Bad "不含私钥: 这份 p12 只能看不能签" }

$teamId = ""
if ($cert.Subject -match "OU=([A-Z0-9]{10})") { $teamId = $Matches[1] }
if ([string]::IsNullOrEmpty($teamId) -and $cert.Subject -match "\(([A-Z0-9]{10})\)") { $teamId = $Matches[1] }
if ($teamId) { Good "TeamID  : $teamId" } else { Warn "从 Subject 里没解出 TeamID,检查证书是否 Apple 签发" }

if ($cert.NotAfter -lt (Get-Date)) {
    Bad "证书已过期($($cert.NotAfter)),签出来的包装不上"
} else {
    $days = [math]::Round(($cert.NotAfter - (Get-Date)).TotalDays)
    Good "剩余有效期: $days 天"
}

$isDev = $cert.Subject -match "Apple Development|iPhone Developer"
$isDist = $cert.Subject -match "Apple Distribution|iPhone Distribution"
if ($isDev) { Info "类型判定: 开发证书(Development),只适合登记过 UDID 的机器" }
if ($isDist) { Info "类型判定: 分发证书(Distribution),企业证书配合 In-House 描述文件可直装任意机器" }

Write-Host ""
Write-Host "=== 2. 证书链 ===" -ForegroundColor White
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$chainOk = $chain.Build($cert)
if ($chainOk) { Good "链验证通过(本机已装 Apple WWDR 中间证书)" }
else {
    Warn "链验证未通过,逐个元素看:"
    foreach ($el in $chain.ChainElements) { Info ("  " + $el.Certificate.Subject) }
    Info "  补一条 Apple Worldwide Developer Relations 中间证书通常就通了"
}

if ([string]::IsNullOrWhiteSpace($Profile)) {
    Write-Host ""
    Warn "没给 -Profile,跳过描述文件检查。光有 p12 签不出能装的包,必须配 mobileprovision。"
    return
}

Write-Host ""
Write-Host "=== 3. 描述文件 ===" -ForegroundColor White
if (-not (Test-Path -LiteralPath $Profile)) { Bad "描述文件不存在: $Profile"; return }
try {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue | Out-Null
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Profile))
    $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms
    $cms.Decode($bytes)
    $text = [System.Text.Encoding]::UTF8.GetString($cms.ContentInfo.Content)
    Good "CMS 解码成功,内层是 plist"
} catch {
    Warn "CMS 解码失败,退化为文本解析: $($_.Exception.Message)"
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Profile)))
}

function Grab([string]$key) {
    if ($text -match "(?s)<key>$key</key>\s*<(string|date)>([^<]+)</\1>") { return $Matches[2] }
    return ""
}

$pName = Grab "Name"
$pUuid = Grab "UUID"
$pAppId = Grab "application-identifier"
$pTeam = Grab "com.apple.developer.team-identifier"
$pExp = Grab "ExpirationDate"
$pPlatform = Grab "Platform"
if ([string]::IsNullOrEmpty($pPlatform) -and $text -match "(?s)<key>Platform</key>\s*<array>\s*<string>([^<]+)</string>") { $pPlatform = $Matches[1] }

Info "名称     : $pName"
Info "UUID     : $pUuid"
Info "包名     : $pAppId"
Info "TeamID   : $pTeam"
Info "平台     : $pPlatform"
Info "到期     : $pExp"

$allDevices = $text -match "<key>ProvisionsAllDevices</key>\s*<true/>"
$getTaskAllow = $text -match "<key>get-task-allow</key>\s*<true/>"
$udidCount = ([regex]::Matches($text, "<string>[0-9a-fA-F]{40}</string>")).Count

if ($allDevices) {
    Good "企业 In-House 描述文件: 不限设备,任意 iPhone 可装"
} elseif ($udidCount -gt 0) {
    Info "Ad Hoc/开发描述文件: 绑定 $udidCount 台设备"
    Warn "目标手机的 UDID 必须在列表里,否则装完打不开"
} else {
    Info "未见 UDID 列表(可能是 App Store 类型,不能直接装)"
}
if ($getTaskAllow) { Info "get-task-allow = true(开发调试签名)" }

Write-Host ""
Write-Host "=== 4. 一致性结论 ===" -ForegroundColor White
if ($teamId -and $pTeam -and $teamId -ne $pTeam) {
    Bad "证书 TeamID($teamId) 与描述文件 TeamID($pTeam) 不一致: 一定签名失败"
} elseif ($teamId -and $pTeam) {
    Good "TeamID 一致: $teamId"
}
if ($pAppId -match "^[A-Z0-9]{10}\.(.+)$") {
    $targetBundle = $Matches[1]
    Good "签名时必须把包名改成: $targetBundle"
    Info "  resign.ps1 会自动读出来填 -b,你也可以手动: -BundleId $targetBundle"
}

Write-Host ""
Write-Host "=== 5. 下一步 ===" -ForegroundColor White
Write-Host "  1) 云构建出未签名 IPA: 把本目录整体推到 GitHub 仓库,跑 build-signed-ipa 工作流"
Write-Host "  2) 本地重签: .\resign.ps1 -Ipa .\AntiAccel-unsigned.ipa -P12 .\cert.p12 -P12Password <口令> -Profile .\profile.mobileprovision -Zsign .\zsign.exe"
Write-Host "  3) 投放: 爱思助手 / Sideloadly,装完到 设置 里信任证书"

Write-Host ""
Write-Host "=== 6. ESign / 爱思 填写对照表(照抄即可) ===" -ForegroundColor White
$fillBundle = "com.arknet.shell"
if ($pAppId -match "^[A-Z0-9]{10}\.(.+)$") { $fillBundle = $Matches[1] }
$fillCert = $cert.Subject
if ($fillCert -match "CN=([^,]+)") { $fillCert = $Matches[1] }
Write-Host ("  证书名称      : " + $fillCert)
Write-Host ("  描述文件名称  : " + $pName)
Write-Host ("  Bundle ID     : " + $fillBundle)
Write-Host ("  是否企业包    : " + $(if ($allDevices) { "是(无需 UDID)" } else { "否(UDID 必须在描述文件里)" }))
Write-Host ("  get-task-allow: " + $(if ($getTaskAllow) { "true(勾上调试)" } else { "false(正式签)" }))
Write-Host "  entitlements  : 本壳零特殊资质,ESign 里保持默认即可"
Write-Host "  安装后信任    : 设置 -> 通用 -> VPN与设备管理 -> 找到证书名 -> 信任"

