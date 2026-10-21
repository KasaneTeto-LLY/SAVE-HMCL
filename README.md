# SAVE-HMCL

HMCL（Hello Minecraft! Launcher）的**非官方修改版**：恢复被上游移除的游戏下载功能。

> 与 HMCL 作者、HMCL 社区**没有任何隶属或授权关系**，不是官方发布。
> 修改版依旧以 GPL-3.0 发布，源码随二进制一并提供。

## 下载

到 [Releases](https://github.com/KasaneTeto-LLY/SAVE-HMCL/releases) 下载最新版本：

| 文件 | 说明 | 大小 |
|---|---|---|
| `HMCL-3.17.0.362+restore1.exe` | Windows 双击运行（官方启动器存根 + 完整 jar 拼接） | ~11.5 MB |
| `HMCL-3.17.0.362+restore1.jar` | 跨平台，`java -jar` 运行 | ~11.0 MB |
| `HMCL-3.17.0.362+restore1-src.zip` | 修改后的**完整源码**（GPL-3.0 对应源码） | ~5.9 MB |
| `SHA256SUMS` | 上述文件的校验值 | — |

运行需要 Java 运行时；exe 启动器会自动查找本机 Java。首次启动时日志里会出现一次
`Self verification failed`——未签名构建的正常现象，只影响自动更新检查。

## 版本号说明

程序内显示 **3.17.0.362**（`hmcl.version.type=unofficial`）；文件名里的 `+restore1`
是本仓库自己加的非官方修改标记，不参与版本比较。

## 这一版改了什么

基于上游提交 `acc9740`（2026-10-20，晚于正式版 v3.17.0.362），改动 4 个文件：

| 文件 | 改动 |
|---|---|
| `Launcher.java` | 移除 `RegionUtils.init();`，启动时不再查询 IP 地区 |
| `RegionUtils.java` | 删除 IP 地区检测（`checkChinaMainlandNetwork` / `isIsChinaMainlandNetwork` 与 11 个时区豁免），保留原有的机器地区判定（时区 / locale / GeoID），与 v3.17.0.361 之前的行为一致 |
| `VersionsPage.java` | 去掉"安装游戏"页的整页禁用与警告条 |
| `DownloadListPage.java` | 去掉"下载"页（模组 / 整合包 / 资源包 / 光影）的整页禁用 |

效果：恢复游戏本体、模组加载器（Forge / NeoForge / Fabric / Quilt）、
Modrinth / CurseForge 资源与整合包的下载与安装入口；启动已有实例、联机、离线登录等行为不受影响。

完整 diff 见 [`HMCL-restore-download.patch`](HMCL-restore-download.patch)。

## 一键构建

```powershell
# 需要 Git、JDK 17+；脚本会自动准备 Gradle 与依赖
powershell -ExecutionPolicy Bypass -File .\Build-HMCL.ps1 -SkipTests -VersionRoot 3.17.0 -BuildNumber 362
```

| 参数 | 作用 |
|---|---|
| `-SkipTests` | 跳过单元测试 |
| `-VersionRoot 3.17.0 -BuildNumber 362` | 让程序内显示 `3.17.0.362`（不传时上游默认是 `3.17.SNAPSHOT`） |
| `-Clean` | 删掉工作目录重来 |
| `-GhProxy <前缀>` | 换 GitHub 加速线路，传空字符串表示直连 |
| `-MavenMirror official` | 改用官方 Maven 源（默认阿里云镜像） |
| `-DryRun` | 只检查环境并打印计划 |

也可以直接双击 `Build-HMCL.cmd`（默认跳过测试）。产物输出到 `out\`。
## 其它启动器的补丁

本仓库同时归档另外两个启动器的同类补丁，仅用于代码学习研究：

| 文件 | 目标 | 改动 |
|---|---|---|
| `PCL-restore-download.patch` | [Meloong-Git/PCL](https://github.com/Meloong-Git/PCL) `6b9a50d` | 常量 `RestrictMcDownload` 由 `True` 改为 `False` |
| `PCL-CE-restore-download.patch` | [PCL-Community/PCL-CE](https://github.com/PCL-Community/PCL-CE) `1a76531` | `RestrictedFeaturePolicy.Assess()` 恒返回 `Other` |

## 许可证与源码

- 本项目是 HMCL 的衍生作品。HMCL 以 **GNU GPL v3.0** 发布，本修改版同样以 GPL-3.0 发布，
  全文见 [`LICENSE`](LICENSE)。
- 每个 Release 都附带修改后的完整源码，满足 GPL-3.0 对"对应源代码"的要求；
  修改声明见 [`NOTICE.md`](NOTICE.md)。
- 产物中打包的第三方库保留各自许可证文本（jar 内 `META-INF/LICENSE*`），清单见 `NOTICE.md`。

## 免责

- 本修改按"现状"提供，不附带任何明示或暗示的担保，使用后果自负。
- 请遵守你所在国家或地区的法律法规，并支持正版《我的世界》。
- HMCL 名称与图标版权归原作者所有；本仓库不代表、也不应被误认为官方版本。
