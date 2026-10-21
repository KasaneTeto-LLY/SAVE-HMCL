# NOTICE / 版权与许可证说明

本仓库发布的二进制（`HMCL-3.17.0.362+restore1.exe` / `.jar`）与源码包
（`HMCL-3.17.0.362+restore1-src.zip`）是 **Hello Minecraft! Launcher (HMCL) 的非官方修改版**。

## 上游

- 项目：HMCL — <https://github.com/HMCL-dev/HMCL>
- 版权：Copyright (C) 2013-2026 huangyuhui <huanghongxun2008@126.com> 及贡献者
- 许可证：GNU General Public License v3.0（全文见 `LICENSE`）
- 使用的上游提交：`acc9740`（2026-10-20，晚于 v3.17.0.362）

## 修改声明（GPL-3.0 §5(a)）

本版本是**修改过的版本**，修改日期 2026-10-21，修改内容为移除地区判定与下载页禁用逻辑
（详见源码包内 `MODIFICATION.md` 与 `patches/HMCL-restore-download.patch`）。
本版本与 HMCL 作者及社区**无隶属或授权关系**，不代表官方发布。

## 对应源码（GPL-3.0 §6）

每个 Release 均同时提供修改后的完整源码 `HMCL-3.17.0.362+restore1-src.zip`，
其中包含完整源码树、GPL-3.0 全文、修改说明与补丁，满足 GPL-3.0 对"对应源代码"的要求。

## 第三方组件

构建产物是把 HMCL 及其依赖打包后的 fat jar（再与官方启动器存根拼接成 exe）。
其中包含的第三方库仍受各自许可证约束，例如（不完全列表）：

| 组件 | 许可证 |
|---|---|
| Gson | Apache License 2.0 |
| JNA / jna-platform | Apache License 2.0 或 LGPL 2.1 |
| JavaFX | GPL-2.0 with Classpath Exception |
| JFoenix | Apache License 2.0 |
| Kotlin Standard Library | Apache License 2.0 |
| 其他 MPL-2.0 / BSD 组件 | 见产物 jar 内 `META-INF/LICENSE*`、`LICENSE.txt` |

上述许可证文本随产物保留在 jar 内（`META-INF/LICENSE`、`META-INF/LICENSE.txt`、`LICENSE.txt`），
本仓库未删除或修改任何第三方版权声明。

## 免责

- 本修改版按"现状"提供，不附带任何明示或暗示的担保。
- 使用本修改版产生的任何后果由使用者自行承担。
- 请遵守你所在国家或地区的法律法规，并支持正版《我的世界》。
