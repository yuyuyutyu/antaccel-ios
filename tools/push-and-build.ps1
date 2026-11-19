<#
.SYNOPSIS
  一条命令把本目录推上 GitHub、触发云端 macOS 编译、把未签名 IPA 拉回本地。
  不装 git、不装 Node、不需要 Mac。

.EXAMPLE
  .\push-and-build.ps1 -Token ghp_xxx -Owner 你的用户名

.EXAMPLE
  # 只预演:列出要推哪些文件,不联网
  .\push-and-build.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$Token = $env:GITHUB_TOKEN,
    [string]$Owner = "",
    [string]$Repo = "antaccel-ios",
    [string]$Branch = "main",
    [string]$Source = "",
    [string]$OutDir = "",
    [int]$TimeoutMinutes = 40,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

if ([string]::IsNullOrWhiteSpace($Source)) { $Source = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $Source "build-out" }

# ---------- 1. 收集文件 ----------
$skipNames = @(".git", "build", "build-unsigned", "build-out", "__pycache__", "signing")
$skipExt = @(".ipa", ".p12", ".mobileprovision", ".zip", ".pyc")
$files = @()
Get-ChildItem -LiteralPath $Source -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($Source.Length).TrimStart("\").Replace("\", "/")
    $parts = $rel.Split("/")
    $skip = $false
    foreach ($p in $parts) { if ($skipNames -contains $p) { $skip = $true } }
    if ($skipExt -contains $_.Extension.ToLower()) { $skip = $true }
    if (-not $skip) {
        $files += [pscustomobject]@{ Path = $rel; Full = $_.FullName; Size = $_.Length }
    }
}

Info ("待推送文件: " + $files.Count + " 个,合计 " + [math]::Round(($files | Measure-Object -Property Size -Sum).Sum / 1KB, 1) + " KB")
if ($DryRun) {
    $files | Select-Object -First 12 | ForEach-Object { Write-Host ("    " + $_.Path + "  " + $_.Size) }
    Write-Host ("    ... 共 " + $files.Count + " 个")
    $hasWf = @($files | Where-Object { $_.Path -eq ".github/workflows/ios-build.yml" }).Count -gt 0
    if ($hasWf) { Good "工作流文件就位: .github/workflows/ios-build.yml" } else { Warn "缺工作流文件!" }
    return
}

if ([string]::IsNullOrWhiteSpace($Token)) { throw "缺 -Token(GitHub 个人访问令牌),或先设环境变量 GITHUB_TOKEN" }

$api = "https://api.github.com"
$headers = @{
    "Authorization"        = "Bearer $Token"
    "Accept"               = "application/vnd.github+json"
    "User-Agent"           = "antaccel-ipa-builder"
    "X-GitHub-Api-Version" = "2022-11-28"
}

function Invoke-Api {
    param([string]$Method = "GET", [string]$Path, $Body, [switch]$Raw)
    $params = @{ Method = $Method; Uri = ($api + $Path); Headers = $headers; TimeoutSec = 60 }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 12 -Compress
        $params["Body"] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params["ContentType"] = "application/json; charset=utf-8"
    }
    try {
        $resp = Invoke-RestMethod @params
        return $resp
    } catch {
        $code = ""
        $msg = $_.Exception.Message
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            try {
                $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $bodyText = $sr.ReadToEnd()
                if ($bodyText) { $msg = $bodyText }
            } catch { }
        }
        throw ("GitHub " + $Method + " " + $Path + " -> " + $code + " " + $msg)
    }
}

# ---------- 2. 账号校验 ----------
Info "校验令牌..."
$me = Invoke-Api -Path "/user"
if ([string]::IsNullOrWhiteSpace($Owner)) { $Owner = $me.login }
Good ("令牌属于: " + $me.login + "  目标仓库: " + $Owner + "/" + $Repo)

# ---------- 3. 建仓(存在就复用) ----------
$repoExists = $true
try { $null = Invoke-Api -Path "/repos/$Owner/$Repo" } catch { $repoExists = $false }
if (-not $repoExists) {
    Info "创建仓库 $Owner/$Repo"
    $payload = @{ name = $Repo; private = $false; auto_init = $true; description = "安心加速器 iOS 壳(自建,可自签)" }
    if ($Owner -eq $me.login) { $null = Invoke-Api -Method "POST" -Path "/user/repos" -Body $payload }
    else { $null = Invoke-Api -Method "POST" -Path "/orgs/$Owner/repos" -Body $payload }
    Start-Sleep -Seconds 2
    Good "仓库已建"
} else {
    Good "仓库已存在,直接更新内容"
}

Start-Sleep -Seconds 4
$repoInfo = Invoke-Api -Path "/repos/$Owner/$Repo"
if ($repoInfo.default_branch) { $Branch = $repoInfo.default_branch }
Good ("工作分支: " + $Branch)

# 空仓库先放一个 README 建立初始提交(否则 git/blobs 会 409)
$needBoot = $false
try { $null = Invoke-Api -Path "/repos/$Owner/$Repo/git/ref/heads/$Branch" } catch { $needBoot = $true }
if ($needBoot) {
    Info "空仓库,先做一次引导提交..."
    $readme = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("# antaccel ios shell"))
    $null = Invoke-Api -Method "PUT" -Path "/repos/$Owner/$Repo/contents/README.md" -Body @{ message = "bootstrap"; content = $readme }
    Start-Sleep -Seconds 3
    $repoInfo2 = Invoke-Api -Path "/repos/$Owner/$Repo"
    if ($repoInfo2.default_branch) { $Branch = $repoInfo2.default_branch }
    Good ("引导完成,工作分支: " + $Branch)
}

# ---------- 4. 上传文件(blob -> tree -> commit -> ref) ----------
Info "上传文件..."
$tree = @()
$i = 0
foreach ($f in $files) {
    $i++
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.Full))
    $blob = Invoke-Api -Method "POST" -Path "/repos/$Owner/$Repo/git/blobs" -Body @{ content = $b64; encoding = "base64" }
    $tree += @{ path = $f.Path; mode = "100644"; type = "blob"; sha = $blob.sha }
    if ($i % 10 -eq 0 -or $i -eq $files.Count) { Write-Host ("    已上传 " + $i + "/" + $files.Count) }
}

$treeObj = Invoke-Api -Method "POST" -Path "/repos/$Owner/$Repo/git/trees" -Body @{ tree = $tree }

$parent = $null
try {
    $ref = Invoke-Api -Path "/repos/$Owner/$Repo/git/ref/heads/$Branch"
    $parent = @($ref.object.sha)
} catch { $parent = @() }

$commit = Invoke-Api -Method "POST" -Path "/repos/$Owner/$Repo/git/commits" -Body @{
    message = "shake shell: 安心加速器 iOS 壳 " + (Get-Date -Format "yyyy-MM-dd HH:mm")
    tree    = $treeObj.sha
    parents = $parent
}

if ($parent.Count -eq 0) {
    $null = Invoke-Api -Method "POST" -Path "/repos/$Owner/$Repo/git/refs" -Body @{ ref = "refs/heads/$Branch"; sha = $commit.sha }
} else {
    $null = Invoke-Api -Method "PATCH" -Path "/repos/$Owner/$Repo/git/refs/heads/$Branch" -Body @{ sha = $commit.sha; force = $true }
}
Good ("代码已提交: " + $commit.sha.Substring(0, 8))

# ---------- 5. 触发工作流 ----------
Info "触发 build-signed-ipa 工作流..."
$triggered = $false
for ($attempt = 1; $attempt -le 6; $attempt++) {
    try {
        $null = Invoke-Api -Method "POST" -Path "/repos/$Owner/$Repo/actions/workflows/ios-build.yml/dispatches" -Body @{ ref = $Branch }
        $triggered = $true
        break
    } catch {
        Warn ("第 " + $attempt + " 次触发未成功(GitHub 索引工作流需要几秒),等 8 秒重试")
        Start-Sleep -Seconds 8
    }
}
if (-not $triggered) { throw "工作流触发失败,去 https://github.com/$Owner/$Repo/actions 手动点 Run workflow" }
Good "已触发"

# ---------- 6. 等结果 ----------
Info "等待构建(首次约 3~6 分钟)..."
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$runId = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    $runs = Invoke-Api -Path "/repos/$Owner/$Repo/actions/runs?per_page=10"
    if (-not $runs.workflow_runs) { continue }
    $mine = $runs.workflow_runs | Where-Object { $_.head_branch -eq $Branch } | Select-Object -First 1
    if (-not $mine) { continue }
    $runId = $mine.id
    Write-Host ("    状态: " + $mine.status + " / " + $mine.conclusion + "  (" + [math]::Round(((Get-Date) - $mine.created_at).TotalSeconds) + "s)")
    if ($mine.status -eq "completed") {
        if ($mine.conclusion -ne "success") { throw ("构建失败,看日志: " + $mine.html_url) }
        break
    }
}
if (-not $runId) { throw "等超时了,去 Actions 页面看" }

# ---------- 7. 下载产物 ----------
Info "下载产物..."
$arts = Invoke-Api -Path ("/repos/$Owner/$Repo/actions/runs/" + $runId + "/artifacts")
if (-not $arts.artifacts -or @($arts.artifacts).Count -eq 0) { throw "这次运行没有产物,检查日志" }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$got = 0
foreach ($a in $arts.artifacts) {
    $zipPath = Join-Path $OutDir ($a.name + ".zip")
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("ipa-builder")
    $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $Token)
    $resp = $client.GetAsync($a.archive_download_url).Result
    $code = [int]$resp.StatusCode
    if ($code -ge 300 -and $code -lt 400 -and $resp.Headers.Location) {
        $loc = $resp.Headers.Location.ToString()
        $client2 = New-Object System.Net.Http.HttpClient
        $client2.DefaultRequestHeaders.UserAgent.ParseAdd("ipa-builder")
        $bytes = $client2.GetByteArrayAsync($loc).Result
        [IO.File]::WriteAllBytes($zipPath, $bytes)
        Write-Host ("    下载完成 " + [math]::Round(([IO.FileInfo]$zipPath).Length / 1KB, 1) + " KB")
    } else {
        Write-Host ("    下载直连返回 " + $code)
        [IO.File]::WriteAllBytes($zipPath, $resp.Content.ReadAsByteArrayAsync().Result)
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath (Join-Path $OutDir $a.name) -Force
    Remove-Item -LiteralPath $zipPath -Force
    $ipa = Get-ChildItem -LiteralPath (Join-Path $OutDir $a.name) -Filter *.ipa -Recurse | Select-Object -First 1
    if ($ipa) {
        $target = Join-Path $OutDir $ipa.Name
        Copy-Item -LiteralPath $ipa.FullName -Destination $target -Force
        Good ("拿到: " + $target + "  " + [math]::Round($ipa.Length / 1MB, 2) + " MB")
        $got++
    }
}
if ($got -eq 0) { throw "产物里没找到 .ipa,看 Artifacts 页面" }

Write-Host ""
Good "全部完成。下一步:把上面的 .ipa 丢进全能签,证书选你的 p12,描述文件配套,Bundle ID 填 com.arknet.shell"
Info ("产物目录: " + $OutDir)
