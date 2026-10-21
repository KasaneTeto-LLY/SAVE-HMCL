<#
.SYNOPSIS
    HMCL 一键构建（源码 + 本地去限制补丁）。

.DESCRIPTION
    自动完成：检测 / 准备工具链（Git、JDK、Gradle）→ 克隆 HMCL 源码 → 检出补丁基线
    → 应用本地补丁 → 编译 → 把产物收集到 out 目录。

    首次运行需要联网下载 Gradle 与 Maven 依赖（约 300~500 MB），耗时 5~15 分钟；
    之后的构建会复用缓存，快很多。

    本脚本及其产出的补丁仅供代码学习与研究使用，详见同目录 README.md 的免责声明。

.PARAMETER Baseline
    补丁对应的上游基线提交，默认 acc9740（v3.17.0.362 之后的提交）。

.PARAMETER WorkDir
    源码与工具链的工作目录，默认 %LOCALAPPDATA%\SaveMC-build。

.PARAMETER OutDir
    构建产物输出目录，默认脚本所在目录下的 out。

.PARAMETER Patch
    要应用的补丁文件，默认同目录下的 HMCL-restore-download.patch。

.PARAMETER GhProxy
    GitHub 加速前缀。克隆与 JDK 下载都会走它，留空则直连。默认 https://v4.gh-proxy.org。

.PARAMETER MavenMirror
    传给构建的 MAVEN_CENTRAL_REPO，默认阿里云中央仓库镜像；传 official 表示用官方源。

.PARAMETER SkipTests
    跳过单元测试（-x test），第一次构建建议加上。

.PARAMETER DryRun
    只检查环境并打印计划，不下载、不克隆、不构建。

.PARAMETER Clean
    删除工作目录后重新开始。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Build-HMCL.ps1 -SkipTests

.EXAMPLE
    .\Build-HMCL.ps1 -DryRun
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Baseline = 'acc9740',
    [string]$WorkDir = '',
    [string]$OutDir = '',
    [string]$Patch = '',
    [string]$GhProxy = 'https://v4.gh-proxy.org',
    [string]$MavenMirror = 'https://maven.aliyun.com/repository/central',
    [switch]$SkipTests,
    [switch]$DryRun,
    [switch]$Clean
)

# 统一用 $LASTEXITCODE / Test-Path 判断成败；Continue 避免原生命令写 stderr 时被当成终止错误
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
if (-not $WorkDir) { $WorkDir = Join-Path $env:LOCALAPPDATA 'SaveMC-build' }
if (-not $OutDir)  { $OutDir = Join-Path $ScriptDir 'out' }
if (-not $Patch)   { $Patch = Join-Path $ScriptDir 'HMCL-restore-download.patch' }

$RepoUrl = 'https://github.com/HMCL-dev/HMCL.git'
$GradleVersion = '9.8.0'
$MinJavaVersion = 17
$GradleMirrors = @(
    "https://mirrors.cloud.tencent.com/gradle/gradle-$GradleVersion-bin.zip",
    "https://mirrors.huaweicloud.com/gradle/gradle-$GradleVersion-bin.zip",
    "https://services.gradle.org/distributions/gradle-$GradleVersion-bin.zip"
)

# ---------------------------------------------------------------- 日志

function Write-Step($Text)  { Write-Host ""; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok($Text)    { Write-Host "    [OK] $Text" -ForegroundColor Green }
function Write-Warn2($Text) { Write-Host "    [!]  $Text" -ForegroundColor Yellow }
function Write-Info($Text)  { Write-Host "        $Text" -ForegroundColor DarkGray }

function Fail($Text) {
    Write-Host ""
    Write-Host "[失败] $Text" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 下载

function Invoke-Download([string]$Url, [string]$Destination) {
    $dir = Split-Path -Parent $Destination
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    Write-Info "下载 $Url"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L --fail --retry 3 --connect-timeout 20 -o $Destination $Url 2>$null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Destination)) { throw "下载失败：$Url" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    }
}

function Get-FinalUrl([string]$Url) {
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { return $Url }
    $final = & curl.exe -sIL -o NUL -w '%{url_effective}' --connect-timeout 20 $Url 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($final)) { return $Url }
    return ([string]$final).Trim()
}

# ---------------------------------------------------------------- 依赖检测

$script:GitExe = $null
$script:JavaHome = $null
$script:GradleBat = $null

function Find-Git {
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-JavaInfo([string]$JavaExe) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = ''
    try { $raw = (& $JavaExe '-XshowSettings:properties' '-version' 2>&1 | Out-String) } catch { }
    $ErrorActionPreference = $old

    $version = 0
    $javaHomePath = $null
    if ($raw -match 'java\.version = (\d+)') { $version = [int]$Matches[1] }
    if ($raw -match 'java\.home = (.+)') { $javaHomePath = $Matches[1].Trim() }
    return @{ Version = $version; Home = $javaHomePath }
}

function Find-Java {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\java.exe') }
    $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }

    foreach ($exe in $candidates) {
        if (-not $exe) { continue }
        if (-not (Test-Path $exe)) { continue }
        $info = Get-JavaInfo $exe
        if ($info.Version -lt $MinJavaVersion) { continue }
        if (-not $info.Home) { continue }
        # Gradle 需要完整 JDK，只有 JRE 的机器继续找下一个候选
        if (-not (Test-Path (Join-Path $info.Home 'bin\javac.exe'))) { continue }
        return @{ Home = $info.Home; Version = $info.Version }
    }
    return $null
}

function Find-Gradle {
    $bat = Join-Path $WorkDir "gradle-$GradleVersion\bin\gradle.bat"
    if (Test-Path $bat) { return $bat }
    return $null
}

function Show-Environment {
    Write-Step '环境检查'

    if ($script:GitExe) {
        $version = (& $script:GitExe --version) -join ''
        Write-Ok "Git：$version"
    } else {
        Write-Warn2 'Git：未找到（将尝试用 winget 安装）'
    }

    if ($script:JavaHome) {
        Write-Ok "JDK：$($script:JavaHome.Home)（Java $($script:JavaHome.Version)）"
    } else {
        Write-Warn2 "JDK：未找到 Java $MinJavaVersion+（将自动下载 Temurin 21）"
    }

    if ($script:GradleBat) {
        Write-Ok "Gradle：$script:GradleBat"
    } else {
        Write-Warn2 "Gradle：未缓存 $GradleVersion（将自动下载）"
    }

    if (Test-Path $Patch) {
        Write-Ok "补丁：$Patch"
    } else {
        Write-Warn2 "补丁：$Patch 不存在（构建出的将是不带补丁的源码）"
    }

    Write-Info "工作目录：$WorkDir"
    Write-Info "输出目录：$OutDir"
    Write-Info "基线提交：$Baseline"
}

# ---------------------------------------------------------------- 工具链

function Install-Git {
    if ($script:GitExe) { return }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Fail '未找到 git，也没有 winget。请先安装 Git for Windows（https://git-scm.com/download/win）后重试。'
    }
    Write-Info '尝试通过 winget 安装 Git.Git（可能弹出确认框）'
    & winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
    $script:GitExe = Find-Git
    if (-not $script:GitExe) { Fail 'winget 安装后仍未找到 git.exe，请手动安装 Git 后重试。' }
}

function Install-Java {
    if ($script:JavaHome) { return $script:JavaHome }

    $jdkDir = Join-Path $WorkDir 'jdk-21'
    $javaExe = Join-Path $jdkDir 'bin\java.exe'

    if (-not (Test-Path $javaExe)) {
        $api = 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse'
        $final = Get-FinalUrl $api
        if ($GhProxy -and $final -match '^https://github\.com/') {
            $final = $GhProxy.TrimEnd('/') + '/' + $final
            Write-Info 'JDK 下载改走 GitHub 加速'
        }
        $zip = Join-Path $WorkDir 'jdk-21.zip'
        Invoke-Download $final $zip

        Write-Info '解压 JDK'
        $tmp = Join-Path $WorkDir 'jdk-21-extract'
        if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
        if ($inner) {
            if (Test-Path $jdkDir) { Remove-Item -Recurse -Force $jdkDir }
            Move-Item $inner.FullName $jdkDir
        }
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        Remove-Item -Force $zip -ErrorAction SilentlyContinue
    }

    $info = Get-JavaInfo $javaExe
    if ($info.Version -lt $MinJavaVersion -or -not (Test-Path (Join-Path $jdkDir 'bin\javac.exe'))) {
        Fail "自动准备的 JDK 不可用：$javaExe"
    }
    return @{ Home = $jdkDir; Version = $info.Version }
}

function Install-Gradle {
    if ($script:GradleBat) { return }

    $zip = Join-Path $WorkDir "gradle-$GradleVersion-bin.zip"
    $target = Join-Path $WorkDir "gradle-$GradleVersion"

    $downloaded = $false
    foreach ($mirror in $GradleMirrors) {
        try {
            Invoke-Download $mirror $zip
            $downloaded = $true
            Write-Ok "Gradle 发行包来自：$mirror"
            break
        } catch {
            Write-Warn2 "镜像不可用，换下一个：$mirror"
        }
    }
    if (-not $downloaded) { Fail '所有 Gradle 下载源都失败，请检查网络，或用 -GhProxy 换加速前缀。' }

    Write-Info '解压 Gradle'
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Expand-Archive -Path $zip -DestinationPath $WorkDir -Force
    Remove-Item -Force $zip -ErrorAction SilentlyContinue

    $bat = Join-Path $target 'bin\gradle.bat'
    if (-not (Test-Path $bat)) { Fail "Gradle 解压结果异常，未找到 $bat" }
    $script:GradleBat = $bat
}

# ---------------------------------------------------------------- 源码

function Prepare-Repo {
    $repo = Join-Path $WorkDir 'HMCL'

    if ($Clean -and (Test-Path $repo)) {
        Write-Info "删除旧源码目录 $repo"
        Remove-Item -Recurse -Force $repo
    }

    $cloneUrl = $RepoUrl
    if ($GhProxy) { $cloneUrl = $GhProxy.TrimEnd('/') + '/' + $RepoUrl }

    if (-not (Test-Path (Join-Path $repo '.git'))) {
        Write-Step '克隆 HMCL 源码'
        if (Test-Path $repo) { Remove-Item -Recurse -Force $repo }
        & $script:GitExe clone --depth 1 $cloneUrl $repo
        if ($LASTEXITCODE -ne 0) { Fail "克隆失败：$cloneUrl" }
    } else {
        Write-Step '复用已有源码目录'
        & $script:GitExe -C $repo remote set-url origin $cloneUrl
        & $script:GitExe -C $repo fetch --depth 1 origin 2>$null
    }

    Write-Step "检出基线提交 $Baseline"
    & $script:GitExe -C $repo rev-parse --verify --quiet "$Baseline^{commit}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & $script:GitExe -C $repo fetch --depth 1 origin $Baseline 2>$null
        if ($LASTEXITCODE -eq 0) {
            & $script:GitExe -C $repo checkout --detach FETCH_HEAD 2>$null | Out-Null
        } else {
            Write-Warn2 "拿不到基线 $Baseline，改用当前 HEAD 继续（补丁可能不适用）"
        }
    } else {
        & $script:GitExe -C $repo checkout --detach $Baseline 2>$null | Out-Null
    }
    & $script:GitExe -C $repo reset --hard 2>$null | Out-Null
    & $script:GitExe -C $repo clean -fdx 2>$null | Out-Null

    $head = (& $script:GitExe -C $repo rev-parse --short HEAD) -join ''
    Write-Ok "当前源码：$head"

    if (Test-Path $Patch) {
        Write-Step '应用补丁'
        & $script:GitExe -C $repo apply --check $Patch 2>$null
        if ($LASTEXITCODE -eq 0) {
            & $script:GitExe -C $repo apply $Patch
            if ($LASTEXITCODE -ne 0) { Fail '补丁应用失败（check 通过但 apply 失败）' }
            Write-Ok '补丁已应用'
        } else {
            Write-Warn2 '直接应用失败，尝试三方合并'
            & $script:GitExe -C $repo apply -3 $Patch 2>$null
            if ($LASTEXITCODE -ne 0) {
                Fail '补丁与当前源码不匹配（上游可能改动了相关文件）。请更新补丁，或按 README.md 中「HMCL 具体改动」手工重做。'
            }
            Write-Ok '三方合并成功，补丁已应用'
        }
    } else {
        Write-Warn2 '未找到补丁文件，跳过（将得到未修改的上游代码）'
    }

    return $repo
}

# ---------------------------------------------------------------- 构建

function Invoke-Build([string]$Repo) {
    Write-Step '开始编译（首次需要下载依赖，请耐心等待）'

    $env:JAVA_HOME = $script:JavaHome.Home
    $env:PATH = (Join-Path $script:JavaHome.Home 'bin') + ';' + $env:PATH
    if ($MavenMirror -and $MavenMirror -ne 'official') {
        $env:MAVEN_CENTRAL_REPO = $MavenMirror
    } else {
        Remove-Item Env:\MAVEN_CENTRAL_REPO -ErrorAction SilentlyContinue
    }

    # --no-watch-fs：部分机器上 Gradle 的 fileevents 原生库加载失败（native services 初始化报错），
    # 关掉文件系统监视可绕开；对一次性构建几乎没有影响。
    $gradleArgs = @('--no-daemon', '--console=plain', '--no-watch-fs', '-p', $Repo)
    if ($SkipTests) { $gradleArgs += @('-x', 'test') }
    $gradleArgs += ':HMCL:build'

    Write-Info ("执行：{0} {1}" -f $script:GradleBat, ($gradleArgs -join ' '))
    & $script:GradleBat @gradleArgs
    if ($LASTEXITCODE -ne 0) {
        Fail ('编译失败，请查看上面的 Gradle 输出。若提示 "Could not initialize native services"，' +
              '可删除 %USERPROFILE%\.gradle\native 后重试。')
    }
    Write-Ok '编译完成'
}

function Collect-Artifacts([string]$Repo) {
    Write-Step "收集产物到 $OutDir"
    $libs = Join-Path $Repo 'HMCL\build\libs'
    if (-not (Test-Path $libs)) { Fail "未找到产物目录 $libs" }

    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

    $files = @(Get-ChildItem $libs -File | Where-Object { @('.jar', '.exe', '.sh', '.deb') -contains $_.Extension })
    if ($files.Count -eq 0) { Fail "产物目录为空：$libs" }

    foreach ($file in $files) {
        $dest = Join-Path $OutDir $file.Name
        Copy-Item $file.FullName $dest -Force
        $hash = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
        $sizeKB = [math]::Round($file.Length / 1KB)
        Write-Host ("    {0,-30} {1,8} KB  {2}" -f $file.Name, $sizeKB, $hash.Substring(0, 16)) -ForegroundColor Green
    }
}

# ---------------------------------------------------------------- 主流程

Write-Host '============================================' -ForegroundColor Cyan
Write-Host ' HMCL 一键构建（源码 + 本地去限制补丁）' -ForegroundColor Cyan
Write-Host ' 仅供代码学习与研究，详见 README.md' -ForegroundColor DarkGray
Write-Host '============================================' -ForegroundColor Cyan

if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }

$script:GitExe = Find-Git
$script:JavaHome = Find-Java
$script:GradleBat = Find-Gradle

Show-Environment

if ($DryRun) {
    Write-Step 'DryRun：将会执行的步骤'
    if (-not $script:GitExe)    { Write-Info '1. 通过 winget 安装 Git' }
    if (-not $script:JavaHome)  { Write-Info '2. 下载并解压 Temurin JDK 21' }
    if (-not $script:GradleBat) { Write-Info "3. 下载并解压 Gradle $GradleVersion" }
    Write-Info "4. 克隆 $RepoUrl 并检出 $Baseline"
    Write-Info '5. 应用补丁'
    if ($SkipTests) { Write-Info '6. 执行 :HMCL:build（跳过测试）' } else { Write-Info '6. 执行 :HMCL:build' }
    Write-Info "7. 产物复制到 $OutDir"
    Write-Host ''
    Write-Host 'DryRun 结束，未做任何修改。' -ForegroundColor Green
    exit 0
}

Install-Git
Install-Java
Install-Gradle

$script:JavaHome = Find-Java
$script:GradleBat = Find-Gradle
if (-not $script:JavaHome) { Fail 'JDK 准备失败' }
if (-not $script:GradleBat) { Fail 'Gradle 准备失败' }

$repoPath = Prepare-Repo
Invoke-Build $repoPath
Collect-Artifacts $repoPath

Write-Host ''
Write-Host '全部完成。' -ForegroundColor Green
Write-Host "产物目录：$OutDir" -ForegroundColor Green
Write-Host '双击 out 目录里的 HMCL-*.exe，或用 java -jar 运行 HMCL-*.jar 即可。' -ForegroundColor DarkGray
exit 0
