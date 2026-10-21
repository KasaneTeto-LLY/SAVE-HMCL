# 解除 MC 启动器「下载功能下线」补丁集（2026-10-20）

2026-10-20 国内 MC 启动器相继下线游戏下载功能，本目录是把三个主流启动器恢复成"下线前"行为的补丁。

| 日期/时间 (+08:00) | 项目 | 事件 |
|---|---|---|
| 10-20 14:33 | PCL | 提交 `e4b0489`（2.99.0.0）：新增常量 `RestrictMcDownload = True`，无条件关闭下载 |
| 10-20 14:51 | PCL | `6b9a50d` 发布 2.99.0.0 正式版（含上述限制） |
| 10-20 16:37 | HMCL | 合入 PR #7017（`583e004`）：中国大陆地区禁用游戏下载，机器 + IP 双重判定 |
| 10-20 18:06 | HMCL | 合入 PR #7020（`8827fd0`）：细化时区豁免名单 |
| 10-20 18:24 | PCL CE | 合入 PR #3673（`8cd9d37`）：`RegionPolicy` 地区判定 + 功能禁用 |
| 10-20 20:12 | PCL CE | 合入 PR #3676（`1a76531`）：增加读取 Windows 设备区域（注册表 GeoID） |

## 仓库地址

- HMCL：<https://github.com/HMCL-dev/HMCL>
- PCL（原版）：<https://github.com/Meloong-Git/PCL>
- PCL CE（社区版）：<https://github.com/PCL-Community/PCL-CE>

## 补丁清单

| 补丁 | 仓库 | 基线提交 | 改动规模 | 恢复原理 |
|---|---|---|---|---|
| `HMCL-restore-download.patch` | HMCL-dev/HMCL | `acc9740`（v3.17.0.362 之后，10-20） | 4 文件 +6 / −103 | 拆掉地区判定：删除 IP 检测与两个页面的禁用分支，保留"机器判定"（镜像优先级、Terracotta、离线登录不受影响） |
| `PCL-restore-download.patch` | Meloong-Git/PCL | `6b9a50d`（2.99.0.0 正式版） | 1 文件 1 行 | `RestrictMcDownload` 由 `True` 改为 `False`，6 个入口（安装页 / MC 卡片 / 整合包安装 ×2 / 资源详情 / 异常提示）全部自动恢复 |
| `PCL-CE-restore-download.patch` | PCL-Community/PCL-CE | `1a76531`（2.15.1，10-20） | 1 文件 1 行 | `RestrictedFeaturePolicy.Assess()` 恒返回 `Other`（不受限），所有 `Check/ThrowIfRestricted/IsRestricted` 调用点一次性放行 |

### HMCL 具体改动

- `Launcher.java`：删除 `RegionUtils.init();`（不再启动时请求 `ipwho.is`）。
- `RegionUtils.java`：删除 `init()`、IP 检测缓存、`checkChinaMainlandNetwork()`、`isIsChinaMainlandNetwork()` 以及 11 个时区豁免；只保留机器判定（时区 / locale / Windows GeoID）。
- `VersionsPage.java`、`DownloadListPage.java`：恢复为 `63207af`（v3.17.0.361）的原始代码，即 `this.getChildren().setAll(root / pane);`。

### PCL 具体改动

```vb
-    Public Const RestrictMcDownload As Boolean = True
+    Public Const RestrictMcDownload As Boolean = False
```

### PCL CE 具体改动

```csharp
-    internal static RegionAssessment Assess() => RegionPolicy.Evaluate(RegionPolicy.ReadWindowsSignals());
+    // [本地补丁] 关闭地区限制：恒返回 Other（不受限），保留原有判定代码以便上游更新后合并
+    internal static RegionAssessment Assess() => new(RegionClassification.Other, "restriction-disabled");
```

`RegionPolicy` 本身保留（它只被这里和单元测试引用），未改动的 `PCL.Core.Test/RegionPolicyTest.cs` 依然全部通过。

## 一键构建脚本（HMCL）

不想手动装工具链的话，直接双击 `Build-HMCL.cmd` 就行：

| 文件 | 作用 |
|---|---|
| `Build-HMCL.cmd` | 双击入口：绕过执行策略、默认跳过测试、结束前暂停显示结果 |
| `Build-HMCL.ps1` | 实际脚本：准备工具链 → 克隆 → 检出基线 → 打补丁 → 编译 → 收集产物 |

流程：

```
环境检查 → 缺什么装什么 → git clone --depth 1（走 gh-proxy）
        → 检出 acc9740 → git apply 补丁 → gradle :HMCL:build → 产物复制到 out\
```

- 需要 Windows 10+ 与网络。缺 Git 时脚本会尝试用 winget 安装；缺 JDK 时自动下载 Temurin 21；Gradle 9.8.0 从腾讯 / 华为镜像下载（官方源不通也能装）。
- 首次运行约下载 300–500 MB（Gradle + Maven 依赖），耗时 5–15 分钟；之后复用缓存。
- 脚本默认给 Gradle 加 `--no-watch-fs`：部分机器上 Gradle 的 fileevents 原生库会加载失败（报 `Could not initialize native services`），关掉文件系统监视即可绕开，对一次性构建没有影响。
- 常用参数（`.cmd` 会把参数透传给 `.ps1`）：
  - `-Clean`：删掉工作目录重来；
  - `-SkipTests`：跳过单元测试（`.cmd` 默认已加）；
  - `-GhProxy <前缀>`：换 GitHub 加速线路，传空字符串表示直连；
  - `-MavenMirror official`：改用官方 Maven 源（默认阿里云镜像）；
  - `-DryRun`：只检查环境并打印计划，不下载、不编译。
- 产物在 `out\`：`HMCL-<版本>.jar` / `.exe` / `.sh` / `.deb`，脚本会打印每个文件的 SHA-256 前缀。
- 上游若改动了补丁涉及的文件，脚本会先尝试三方合并；仍失败时会提示按上面「HMCL 具体改动」手工重做。
- 工作目录默认 `%LOCALAPPDATA%\SaveMC-build`，源码、JDK、Gradle 都在里面，可随时整个删掉。

## 应用方法

```powershell
cd <对应仓库>
git apply "F:\SaveMC\HMCL-restore-download.patch"      # 或 PCL / PCL-CE 的补丁
```

- 补丁由 `git diff` 直接生成，UTF-8，路径含空格，请用 `git apply`，不要手工复制粘贴。
- 若基线不同（你切到了其他分支/提交），先 `git apply --check` 验证；冲突多为上下文行变化，按上面"具体改动"手工重做即可。

## 构建

| 项目 | 环境 | 命令 |
|---|---|---|
| HMCL | JDK + 能下载 Gradle 9.8.0-dist 与 Maven 依赖 | `.\gradlew :HMCL:run`（或 `:HMCL:compileJava`） |
| PCL | .NET Framework 4.8 + VS2022 / MSBuild；先 `git submodule update --init`（MeloongCore） | 用 VS 打开 `Plain Craft Launcher 2.sln` 构建 |
| PCL CE | .NET 10 SDK（`net10.0-windows`） | `dotnet build "Plain Craft Launcher 2\Plain Craft Launcher 2.csproj"` |

## 校验

三个补丁均在各自干净基线上 `git apply --check` 通过并实际应用成功：

| SHA-256 | 文件 |
|---|---|
| `ec6f6afedab329a97c399915e6d4d0838188ae17d7f0c29a69c3c8425859f869` | HMCL-restore-download.patch |
| `196556a412fb1bbb9a602846b833ab6a4db7aba4aa1888d78a75c4fa9f827cd4` | PCL-restore-download.patch |
| `edc6ca6bb5fc6c9ab078cda9f1d3c676b06e6a5838cfdfb69c81c0e7f292d3e2` | PCL-CE-restore-download.patch |

本机实测结果：

- **HMCL**：已用 `Build-HMCL.ps1` 端到端跑通（JDK 23 + 自动下载的 Gradle 9.8.0 + 阿里云 Maven 镜像）。首次配置阶段约 10 分钟（下载依赖），缓存后增量构建约 50 秒；产出 `out\` 下 4 个文件，并用 `javap` 确认编译产物中的 `RegionUtils` 已只剩机器判定方法、`isIsChinaMainlandNetwork` 不存在。
- **PCL / PCL CE**：未编译，仅验证补丁可干净应用（本机没有 .NET 10 SDK 与 MSBuild；PCL 是 .NET Framework 4.8 项目，需要 VS / MSBuild）。

## 注意

- 这些只是"解除本地限制"，不改变启动器其他任何逻辑；作者写的是"暂时"，上游后续可能换别的方式，届时补丁需重做。
- 上游继续提交会让补丁上下文漂移，出现冲突属正常。
- 补丁只针对上述基线提交，不保证对未来版本有效。

## 免责声明

**本目录下的全部补丁、说明与相关分析内容，仅供代码学习与研究使用，不得用于任何商业用途或其他用途。**

- 内容仅用于了解启动器的地区判定实现方式、学习逆向与补丁分析思路，不构成对任何功能规避行为的建议或协助。
- 请遵守你所在国家或地区的法律法规，以及相关平台的服务条款；是否使用、如何使用由使用者自行判断并承担全部后果。
- 请支持正版《我的世界》：通过 Mojang / Microsoft 官方渠道购买，或使用官方中国版渠道。
- 本目录与 HMCL、PCL、PCL CE 的作者及所属社区均无隶属或授权关系，相关代码版权归原作者所有（HMCL 为 GPL-3.0，PCL / PCL CE 请参见各自仓库的许可协议）。
- 请勿传播修改后的构建产物，发布衍生版本前务必确认符合原项目的开源许可要求。
- 补丁按"现状"提供，不附带任何明示或暗示的担保；因使用本目录内容造成的任何直接或间接损失，制作者不承担责任。
