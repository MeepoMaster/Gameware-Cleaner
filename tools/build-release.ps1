<#
.SYNOPSIS
    构建带「IPV6 禁用默认关闭」补丁的发布包。

.DESCRIPTION
    上游脚本（仓库根目录的 LeiGod-OneClick.ps1）保持一字不改；
    本脚本用 tools\ipv6-off.ps1 生成打过补丁的副本，连同 .cmd、LICENSE、使用说明一起打成 zip。

    命名与上游完全一致（不加任何后缀）：
        tag     : v<上游版本>
        附件    : LeiGod-OneClick-<上游版本>.zip
        包内目录: LeiGod-OneClick-<上游版本>\

    补丁失败时直接抛错（不会产出半成品），CI 里会因此变红并提 issue。
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

if (-not $OutRoot) { $OutRoot = Join-Path $RepoRoot 'build' }

$upstreamScript = Join-Path $RepoRoot 'LeiGod-OneClick.ps1'
$patcher = Join-Path $PSScriptRoot 'ipv6-off.ps1'
foreach ($p in @($upstreamScript, $patcher)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ('缺少文件：' + $p) }
}

# 1) 读上游版本号（产物与上游同名，不加后缀）
$text = [IO.File]::ReadAllText($upstreamScript)
$m = [regex]::Match($text, "\`$script:ScriptVersion = '([0-9][^']*)'")
if (-not $m.Success) { throw '从上游脚本里读不到 $script:ScriptVersion，上游结构可能变了（需要适配 build-release.ps1）' }
$version = $m.Groups[1].Value
$pkgName = 'LeiGod-OneClick-' + $version
Write-Host ('上游版本：' + $version)

# 2) 生成目录
$pkgDir = Join-Path $OutRoot $pkgName
if (Test-Path -LiteralPath $pkgDir) { Remove-Item -LiteralPath $pkgDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null

# 3) 打补丁
$built = Join-Path $pkgDir 'LeiGod-OneClick.ps1'
& $patcher -Source $upstreamScript -Out $built
if (-not (Test-Path -LiteralPath $built)) { throw '补丁器没有产出脚本' }

# 4) 附带文件
foreach ($f in @('Run-LeiGod-OneClick.cmd', 'Fix-Startup-Window.cmd', 'LICENSE')) {
    $src = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $src)) { throw ('仓库里缺少 ' + $f) }
    Copy-Item -LiteralPath $src -Destination (Join-Path $pkgDir $f) -Force
}

# 5) 使用说明
$readme = @'
雷神加速器一键精简 __VERSION__
==========================

本包基于上游同名版本（v__VERSION__），只额外加了一处改动：

  「系统设置 → IPV6 禁用」默认关闭并固定为关闭

雷神默认会在加速时下发 banipv6:1，让驱动禁用本机 IPv6；设置页里还会在环境检查
通过后自动把开关打开。部分网络下这会导致 IPv6 应用、部分游戏联机异常。
本版把这项固定为关闭（开关显示关闭、点击无效、加速参数固定 banipv6:0）。

想保留雷神原行为：运行时在「IPV6 禁用默认关闭」这一项选 N，
或加参数 -DisabledFeatures KeepIpv6。

使用
----
1. 把本压缩包完整解压（不要在压缩软件里直接双击运行）。
2. 完全退出雷神，包括托盘图标。
3. 双击 Run-LeiGod-OneClick.cmd，UAC 弹窗点“是”。
4. 按提示输入 Y 或 N，直接回车使用默认值。
5. 完成后记下备份位置，按任意键退出，再打开雷神。

还原
----
完全退出雷神，双击备份目录里的 restore.cmd。
默认备份位置：%USERPROFILE%\GamewareCleanerBackup\leigod-<时间>
处理过多次时，从最近一次开始依次还原；不要提前删除备份。
还原后「IPV6 禁用」也一起恢复成雷神默认行为。

文件说明
--------
Run-LeiGod-OneClick.cmd   双击运行一键精简
Fix-Startup-Window.cmd    只关闭旧版取色助手
LeiGod-OneClick.ps1       脚本本体（被上面两个 .cmd 调用，已含 IPV6 补丁）
LICENSE                   GPL-3.0 许可证
使用说明.txt              本文件

已验证版本：雷神 Windows 客户端 11.3.3.2。其他版本不保证兼容。

上游原版：https://github.com/TG-Twilight/Gameware-Cleaner
本 fork：https://github.com/MeepoMaster/Gameware-Cleaner
本项目为独立第三方工具，与雷神官方无隶属或合作关系。
原始代码 Copyright (C) 2026 TG-Twilight，按 GPL-3.0-only 授权；本 fork 保留同一许可。
'@
$readme = $readme.Replace('__VERSION__', $version)
# 用 CRLF 写，方便 Windows 记事本
$readme = $readme -replace "`r?`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $pkgDir '使用说明.txt'), $readme, (New-Object System.Text.UTF8Encoding($true)))

# 6) 打包
$zip = Join-Path $OutRoot ($pkgName + '.zip')
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($pkgDir, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)

Write-Host ('包目录：' + $pkgDir)
Write-Host ('zip：' + $zip + '（' + (Get-Item -LiteralPath $zip).Length + ' 字节）')

# 7) 供 CI 使用
if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ('base=' + $version) -Encoding UTF8
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ('zip=' + $zip) -Encoding UTF8
}