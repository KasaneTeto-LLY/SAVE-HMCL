# restore1 — 非官方 HMCL 修改版

基于上游 [HMCL-dev/HMCL](https://github.com/HMCL-dev/HMCL) 提交 `acc9740`
（2026-10-20，晚于正式版 v3.17.0.362），构建日期 2026-10-21。

程序内版本号显示 **3.17.0.362**（`hmcl.version.type=unofficial`），文件名里的 `+restore1`
是本仓库自己加的非官方标记，不参与版本比较。

> 本版本为**非官方修改版**，与 HMCL 作者及社区无隶属或授权关系。
> 以 GPL-3.0 发布，完整修改后源码随本 Release 一并提供。

## 变更

| 文件 | 改动 |
|---|---|
| `Launcher.java` | 移除 `RegionUtils.init();` |
| `RegionUtils.java` | 删除 IP 地区检测与时区豁免列表，保留机器地区判定（与 v3.17.0.361 之前行为一致） |
| `VersionsPage.java` | 去掉"安装游戏"页整页禁用 |
| `DownloadListPage.java` | 去掉"下载"页整页禁用 |

效果：恢复游戏本体、模组加载器（Forge / NeoForge / Fabric / Quilt）、
Modrinth / CurseForge 资源与整合包的下载与安装入口；
启动已有实例、联机、离线登录等行为不受影响。

## 资产

| 文件 | 说明 |
|---|---|
| `HMCL-3.17.0.362+restore1.exe` | Windows 双击运行 |
| `HMCL-3.17.0.362+restore1.jar` | 跨平台，`java -jar` |
| `HMCL-3.17.0.362+restore1-src.zip` | 修改后的完整源码（GPL-3.0 对应源码） |
| `SHA256SUMS` | 上述文件的 SHA-256 |

## 说明

- exe 为"官方启动器存根 + 完整 jar"拼接结构，与官方发行方式一致。
- 构建未使用官方签名密钥，因此首次启动日志会出现 `Self verification failed`（仅影响自动更新检查）。
- 使用前请确认本机有可用的 Java 运行时。

## 许可证

GPL-3.0，全文见源码包内 `LICENSE`。第三方组件许可证见 `NOTICE.md`。
