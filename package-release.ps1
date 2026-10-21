# 把一个已编译好的 HMCL 产物打包成"符合 GPL 的发布资产"
#
# 做四件事：
#   1. 给 jar 补上 GPL-3.0 全文（META-INF/LICENSE-GPL-3.0.txt）和修改声明（META-INF/NOTICE-SAVE-HMCL.txt）
#   2. 用官方启动器存根 + 新 jar 重新拼出 exe（保持"exe + 尾部 jar"结构）
#   3. 把已打补丁的源码树打成 -src.zip（含 LICENSE / MODIFICATION.md / patches/）
#   4. 生成 SHA256SUMS
#
# 前提：先跑过 Build-HMCL.ps1，产物在 out\ 里（HMCL-<Version>.jar / .exe）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\package-release.ps1 -Version 3.17.0.362

[CmdletBinding()]
param(
    [string]$Version = '3.17.0.362',
    [string]$Suffix = '+restore1',
    [string]$OutDir = '',
    [string]$ReleaseDir = '',
    [string]$SrcRoot = '',
    [string]$Commit = 'acc9740',
    [string]$Upstream = 'https://github.com/HMCL-dev/HMCL'
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'out' }
if (-not $ReleaseDir) { $ReleaseDir = Join-Path $PSScriptRoot 'release-assets' }
if (-not $SrcRoot) { $SrcRoot = Join-Path $env:LOCALAPPDATA 'SaveMC-build\HMCL' }
Add-Type -AssemblyName System.IO.Compression.FileSystem

$jarName = "HMCL-$Version.jar"
$exeName = "HMCL-$Version.exe"
$jarPath = Join-Path $OutDir $jarName
$exePath = Join-Path $OutDir $exeName

if (-not (Test-Path $jarPath)) { throw "找不到 $jarPath，先运行 Build-HMCL.ps1（并传入 -VersionRoot/-BuildNumber）" }
if (-not (Test-Path $exePath)) { throw "找不到 $exePath" }
if (-not (Test-Path (Join-Path $PSScriptRoot 'LICENSE'))) { throw '脚本目录缺少 LICENSE（GPL-3.0 全文）' }
if (-not (Test-Path (Join-Path $PSScriptRoot 'NOTICE.md'))) { throw '脚本目录缺少 NOTICE.md' }

if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null }

$outJar = Join-Path $ReleaseDir "HMCL-$Version$Suffix.jar"
$outExe = Join-Path $ReleaseDir "HMCL-$Version$Suffix.exe"
$outSrc = Join-Path $ReleaseDir "HMCL-$Version$Suffix-src.zip"

# 1. jar 内嵌许可证与修改声明
Copy-Item $jarPath $outJar -Force
$zip = [System.IO.Compression.ZipFile]::Open($outJar, 'Update')
foreach ($pair in @(
    @('META-INF/LICENSE-GPL-3.0.txt', (Join-Path $PSScriptRoot 'LICENSE')),
    @('META-INF/NOTICE-SAVE-HMCL.txt', (Join-Path $PSScriptRoot 'NOTICE.md'))
)) {
    $entry = $zip.CreateEntry($pair[0])
    $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
    $writer.Write([System.IO.File]::ReadAllText($pair[1], [System.Text.Encoding]::UTF8))
    $writer.Close()
}
$zip.Dispose()
Write-Host "jar 已写入许可证条目：$outJar" -ForegroundColor Green

# 2. exe = 官方启动器存根 + 新 jar
$stubLen = (Get-Item $exePath).Length - (Get-Item $jarPath).Length
if ($stubLen -le 0) { throw 'exe 与 jar 大小关系异常，无法拆分启动器存根' }
$exeBytes = [System.IO.File]::ReadAllBytes($exePath)
$jarBytes = [System.IO.File]::ReadAllBytes($outJar)
$stream = [System.IO.File]::Create($outExe)
$stream.Write($exeBytes, 0, [int]$stubLen)
$stream.Write($jarBytes, 0, $jarBytes.Length)
$stream.Close()
Write-Host "exe 已重新拼接：$outExe（存根 $stubLen 字节 + jar $($jarBytes.Length) 字节）" -ForegroundColor Green

# 3. 源码包
if (-not (Test-Path (Join-Path $SrcRoot '.git'))) {
    Write-Host "跳过源码包：$SrcRoot 不是源码树（可用 -SrcRoot 指定）" -ForegroundColor Yellow
} else {
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("save-hmcl-src-" + [guid]::NewGuid().ToString('N'))
    $dest = Join-Path $stage "HMCL-$Version$Suffix-src"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    & robocopy $SrcRoot $dest /E /XD .git build .gradle /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy 失败（$LASTEXITCODE）" }

    New-Item -ItemType Directory -Force -Path (Join-Path $dest 'patches') | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'HMCL-restore-download.patch') (Join-Path $dest 'patches') -Force
    Copy-Item (Join-Path $PSScriptRoot 'LICENSE') $dest -Force

    $modification = @"
# 本源码包的修改说明（GPL-3.0 第 5(a) 条要求的"标明修改"）

| 项 | 内容 |
|---|---|
| 上游项目 | [$Upstream]($Upstream) |
| 上游提交 | ``$Commit`` |
| 本包修改日期 | $(Get-Date -Format 'yyyy-MM-dd') |
| 版本号 | $Version |
| 许可证 | GNU General Public License v3.0，全文见同目录 ``LICENSE`` |

完整 diff 见 ``patches/HMCL-restore-download.patch``，改动 4 个文件：

1. ``Launcher.java``：删除 ``RegionUtils.init();``
2. ``RegionUtils.java``：删除 IP 地区检测与时区豁免列表，保留机器地区判定
3. ``VersionsPage.java``：去掉"安装游戏"页整页禁用
4. ``DownloadListPage.java``：去掉"下载"页整页禁用

除上述改动外，本源码包与上游 ``$Commit`` 完全一致，未删除任何版权声明或许可证文本。

本修改版与 HMCL 作者、HMCL 社区无隶属或授权关系，按"现状"提供，不附带任何担保。
"@
    [System.IO.File]::WriteAllText((Join-Path $dest 'MODIFICATION.md'), $modification, (New-Object System.Text.UTF8Encoding($false)))

    if (Test-Path $outSrc) { Remove-Item $outSrc -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($dest, $outSrc, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    Remove-Item -Recurse -Force $stage
    Write-Host "源码包已生成：$outSrc" -ForegroundColor Green
}

# 4. 校验值
$files = @($outExe, $outJar, $outSrc) | Where-Object { Test-Path $_ }
$lines = foreach ($file in $files) {
    "{0}  {1}" -f (Get-FileHash $file -Algorithm SHA256).Hash.ToLower(), (Split-Path -Leaf $file)
}
[System.IO.File]::WriteAllText((Join-Path $ReleaseDir 'SHA256SUMS'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "发布资产目录：$ReleaseDir" -ForegroundColor Cyan
Get-ChildItem $ReleaseDir | ForEach-Object { Write-Host ("  {0,-45} {1,10:N0} B" -f $_.Name, $_.Length) -ForegroundColor DarkGray }
