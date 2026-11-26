# 这个 fork 是怎么工作的

> 上游：[TG-Twilight/Gameware-Cleaner](https://github.com/TG-Twilight/Gameware-Cleaner)
> 本 fork 只额外加一个功能：**「系统设置 → IPV6 禁用」默认关闭并固定为关闭**
> （雷神原本会在加速时让驱动禁用本机 IPv6，部分网络下会导致 IPv6 应用、部分游戏联机异常）。

## 一句话：仓库里的脚本是上游原样，带补丁的版本在 Releases

| 位置 | 内容 |
|---|---|
| `LeiGod-OneClick.ps1`（仓库里） | **与上游一字不差**，方便自动跟随上游更新 |
| [Releases](https://github.com/MeepoMaster/Gameware-Cleaner/releases/latest) | 打包时注入 IPV6 补丁后的成品，**下载用这个** |
| `tools/ipv6-off.ps1` | 补丁器：把 IPV6 功能注入到上游脚本 |
| `tools/build-release.ps1` | 打包器：生成 release 附件（脚本 + .cmd + LICENSE + 使用说明） |
| `.github/workflows/sync-upstream.yml` | 定时任务：同步上游 → 打补丁 → 语法检查 → 发布 |

**不要用 Code → Download ZIP**，那个包里是没有补丁的上游原版。

## 为什么这么设计

以前的做法是直接把 IPV6 的代码写进 `LeiGod-OneClick.ps1`。上游每改一次这个文件就可能和我们的改动撞车
（2026-11-25 上游发 0.13.1 时就撞了，需要人工合并）。

现在上游脚本保持原样、补丁在打包时注入，于是：

- `git merge upstream/main` **永远干净**，不会再有合并冲突
- 上游发新版 → 定时任务自动合并 → 自动重新打包 → 自动发布新 release
- 补丁注入有严格校验：任何"功能性锚点"找不到就**直接报错停止**，绝不会发布半成品

已经验证：补丁器对上游 0.13.1 的产物在雷神 11.3.3.2 上 `-DryRun` 全流程通过
（渲染层 506 个文件、重打包往返校验一致、`banipv6` 三处改动全部命中）。

## 自动更新怎么跑

- 每天（GitHub 的调度会延迟，实测在北京时间晚间）自动跑一次
- 也可以在 **Actions → Sync upstream → Run workflow** 手动触发
- 判断逻辑：
  - 上游没变且 release 已存在 → 什么都不做
  - 上游有变动 → 合并 + 重新打包 + 覆盖 release 附件
  - 合并冲突 / 补丁锚点失效 / 语法检查失败 → **停止，不发布**，并在 Issues 里开一条提醒

## 出问题了怎么办

看到红色运行记录或 `同步/打包失败` 的 issue，基本是这几类：

| 日志里的关键字 | 含义 | 处理 |
|---|---|---|
| `CONFLICT (content)` | 上游改到了本 fork 也改过的行（理论上只剩 README/功能表那几行） | 手动解决冲突 |
| `锚点缺失，无法打补丁` | 上游重构了脚本结构，补丁位置失效 | 适配 `tools/ipv6-off.ps1` 里对应的锚点 |
| `语法检查不通过` | 补丁后的脚本有问题 | 不要发布，先修 |
| `Resource not accessible` / 权限类 | token 权限或仓库设置 | 检查 Settings → Actions → Workflow permissions |

## 想保留雷神原行为

运行时在「IPV6 禁用默认关闭」这一项选 **N**，或加参数 `-DisabledFeatures KeepIpv6`。

## 还原

完全退出雷神，双击备份目录里的 `restore.cmd`（默认在 `%USERPROFILE%\GamewareCleanerBackup\leigod-<时间>\`）。
「IPV6 禁用」会随 `renderer.asar` 一起恢复成雷神默认行为。

## 许可

原始代码 Copyright (C) 2026 TG-Twilight，[GPL-3.0-only](LICENSE)。
本 fork 的补丁与打包脚本同样按 GPL-3.0-only 授权。
本项目为独立第三方工具，与雷神官方无隶属或合作关系。