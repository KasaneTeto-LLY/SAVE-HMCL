# 发布 / 更新 GitHub Release
#
# 用法：
#   1. 安装 GitHub CLI 并登录：winget install GitHub.cli ; gh auth login
#   2. 把构建产物（exe / jar / src.zip / SHA256SUMS）放进 release-assets\
#      或者直接指定 -AssetsDir F:\SaveMC\release
#   3. powershell -ExecutionPolicy Bypass -File .\publish.ps1
#
# 行为：
#   - 该 tag 的 Release 不存在 → 新建
#   - 已存在 → 用同名资产覆盖上传（--clobber），无- 需先删旧资产
#
# 注意：发布前请确认仓库里已有 LICENSE、NOTICE.md、README.md。

[CmdletBinding()]
param(
    [string]$Tag = 'v3.17.0.362-restore1',
    [string]$Repo = 'KasaneTeto-LLY/SAVE-HMCL',
    [string]$AssetsDir = '',
    [string]$NotesFile = '',
    [string]$Title = 'restore1 - 3.17.0.362 非官方修改版',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not $NotesFile) { $NotesFile = Join-Path $PSScriptRoot 'RELEASE_NOTES.md' }

if (-not $AssetsDir) {
    $candidates = @(
        (Join-Path $PSScriptRoot 'release-assets'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'release')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $AssetsDir = $c; break }
    }
}
if (-not $AssetsDir -or -not (Test-Path $AssetsDir)) {
    throw '找不到资产目录，请用 -AssetsDir 指定（例如 -AssetsDir F:\SaveMC\release）'
}

$names = @(
    'HMCL-3.17.0.362+restore1.exe',
    'HMCL-3.17.0.362+restore1.jar',
    'HMCL-3.17.0.362+restore1-src.zip',
    'SHA256SUMS'
)
$assets = @()
foreach ($n in $names) {
    $path = Join-Path $AssetsDir $n
    if (-not (Test-Path $path)) { throw "缺少资产：$path" }
    $assets += $path
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw '未找到 gh（GitHub CLI）。先执行：winget install GitHub.cli，然后 gh auth login'
}

Write-Host "仓库：$Repo" -ForegroundColor Cyan
Write-Host "标签：$Tag" -ForegroundColor Cyan
Write-Host "资产目录：$AssetsDir" -ForegroundColor Cyan
$assets | ForEach-Object { Write-Host ("  + {0}" -f (Split-Path -Leaf $_)) -ForegroundColor DarkGray }

$exists = $false
$prevEa = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & gh release view $Tag --repo $Repo --json tagName *> $null
    if ($LASTEXITCODE -eq 0) { $exists = $true }
} catch { }
$ErrorActionPreference = $prevEa

if ($DryRun) {
    if ($exists) { Write-Host '计划：Release 已存在 → 覆盖上传资产' -ForegroundColor Yellow }
    else { Write-Host '计划：新建 Release 并上传资产' -ForegroundColor Yellow }
    exit 0
}

if ($exists) {
    Write-Host 'Release 已存在，覆盖上传资产…' -ForegroundColor Yellow
    & gh release upload $Tag @assets --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) { throw 'gh release upload 失败' }
} else {
    Write-Host '新建 Release…' -ForegroundColor Green
    & gh release create $Tag @assets --repo $Repo --title $Title --notes-file $NotesFile
    if ($LASTEXITCODE -ne 0) { throw 'gh release create 失败' }
}

Write-Host '完成。' -ForegroundColor Green
& gh release view $Tag --repo $Repo --web
