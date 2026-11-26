<#
.SYNOPSIS
    把「系统设置 → IPV6 禁用 默认关闭」打到上游 LeiGod-OneClick.ps1 上。

.DESCRIPTION
    上游脚本保持一字不改；本文件负责生成带 IPV6 补丁的脚本。
    任何“功能性”锚点缺失都会直接报错退出，不会产出半成品；
    纯文档/记账类锚点（帮助文字、参数说明、标记文件、交互列表）缺失只警告。

    用法：
        powershell -File tools\ipv6-off.ps1 -Source .\LeiGod-OneClick.ps1 -Out build\LeiGod-OneClick.ps1 -VersionSuffix +ipv6.1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$VersionSuffix = ''
)

$ErrorActionPreference = 'Stop'
$script:Warnings = New-Object System.Collections.ArrayList

function Write-Step { param([string]$m) Write-Host ('  - ' + $m) }

function Invoke-ReplaceOnce {
    param(
        [string]$Text, [string]$Old, [string]$New, [string]$Name, [switch]$Optional
    )
    $i = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($i -lt 0) {
        if ($Optional) { $script:Warnings.Add($Name) | Out-Null; Write-Step ('跳过（上游已改动，不影响功能）：' + $Name); return $Text }
        throw ('锚点缺失，无法打补丁：' + $Name + '。上游脚本结构变了，需要适配 tools\ipv6-off.ps1。')
    }
    $j = $Text.IndexOf($Old, $i + $Old.Length, [StringComparison]::Ordinal)
    if ($j -ge 0) {
        throw ('锚点不唯一，拒绝打补丁：' + $Name)
    }
    Write-Step ('已应用：' + $Name)
    return $Text.Substring(0, $i) + $New + $Text.Substring($i + $Old.Length)
}

# ---------------------------------------------------------------------------
# 补丁内容（由已验证的构建版本抽出，勿手改；改这里等于改功能）
# ---------------------------------------------------------------------------

$payloadFunctions = @'
function Patch-Ipv6SettingSwitch {
    # 「系统设置 → IPV6 禁用」开关：默认关、读到旧设置也按关显示、去掉自动打开。
    # 依赖三个结构（压缩后的变量名各版本不同，这里按结构识别）：
    #   ...=de(()=>({onAppQuite:V,trendLines:T,banipv6:S,nodeSelect:C}))
    #   {switchValue:S,toggleSwitch:B,switchClass:ee}=g({normalVal:!1,openVal:!0})
    #   S.value=u.banipv6, ..., X().then(_=>{_&&(S.value=!0)})
    # 不是系统设置页的 chunk 返回 $null。
    param([string]$s)
    $log = New-Object System.Collections.ArrayList

    $m = [regex]::Match($s, 'onAppQuite\s*:\s*[A-Za-z_$][\w$]*\s*,\s*trendLines\s*:\s*[A-Za-z_$][\w$]*\s*,\s*banipv6\s*:\s*([A-Za-z_$][\w$]*)')
    if (-not $m.Success) {
        $m = [regex]::Match($s, 'banipv6\s*:\s*([A-Za-z_$][\w$]*)\s*,\s*nodeSelect\s*:')
    }
    if (-not $m.Success) { return $null }
    $var = $m.Groups[1].Value
    $varRe = [regex]::Escape($var)

    # 1) 开关默认值：normalVal:!0 -> !1（有的版本默认就是 !1，这里幂等）
    $sw = [regex]::Match($s, '\{switchValue:' + $varRe + '\s*,')
    if ($sw.Success) {
        $len = [Math]::Min(260, $s.Length - $sw.Index)
        $window = $s.Substring($sw.Index, $len)
        $fixed = $window.Replace('normalVal:!0', 'normalVal:!1')
        if ($fixed -cne $window) {
            $s = $s.Substring(0, $sw.Index) + $fixed + $s.Substring($sw.Index + $len)
            $log.Add('开关默认值改为关闭') | Out-Null
        }
    }

    # 2) 读本地存储时固定为关（以前存过 true 的机器也会显示关闭）
    $readPattern = $varRe + '\.value\s*=\s*[A-Za-z_$][\w$]*\.banipv6'
    if ([regex]::IsMatch($s, $readPattern)) {
        $s = [regex]::Replace($s, $readPattern, ($var + '.value=!1'))
        $log.Add('读取已保存的设置时按关闭处理') | Out-Null
    }

    # 3) 去掉“环境检查通过就自动打开”的调用
    $autoPattern = ',\s*[A-Za-z_$][\w$]*\(\)\.then\(\s*([A-Za-z_$][\w$]*)\s*=>\s*\{\s*\1\s*&&\s*\(\s*' + $varRe + '\.value\s*=\s*!0\s*\)\s*\}\s*\)'
    if ([regex]::IsMatch($s, $autoPattern)) {
        $s = [regex]::Replace($s, $autoPattern, '')
        $log.Add('去掉自动打开「IPV6 禁用」的逻辑') | Out-Null
    }

    # 4) 开关点不动：避免“界面上打开了、实际不生效”的错觉
    $propIndex = $s.IndexOf('prop:"banipv6"', [StringComparison]::Ordinal)
    if ($propIndex -ge 0) {
        $tailLen = [Math]::Min(420, $s.Length - $propIndex)
        $tail = $s.Substring($propIndex, $tailLen)
        if ($tail.IndexOf('onClick:()=>{}', [StringComparison]::Ordinal) -lt 0) {
            $onClick = [regex]::Match($tail, 'onClick:e\[\d+\]\|\|\(e\[\d+\]=\(\.\.\.([A-Za-z_$][\w$]*)\)=>s\(([A-Za-z_$][\w$]*)\)&&s\(\2\)\(\.\.\.\1\)\)')
            if ($onClick.Success) {
                $abs = $propIndex + $onClick.Index
                $s = $s.Substring(0, $abs) + 'onClick:()=>{}' + $s.Substring($abs + $onClick.Length)
                $log.Add('开关点击已禁用（保持关闭）') | Out-Null
            } else {
                $log.Add('没能禁用开关点击：界面上的开关仍可点，但加速时已按关闭处理') | Out-Null
            }
        }
    }

    if ([regex]::IsMatch($s, $varRe + '\.value\s*=\s*!0')) {
        throw ('「IPV6 禁用」开关里仍有强制打开的代码（变量 ' + $var + '），请把 assets 下对应的 chunk 发回反馈')
    }
    return @{ Text = $s; Log = $log }
}

function Patch-Ipv6AccParam {
    # 加速请求参数 banipv6 固定为 0：不再让驱动在加速时禁用本机 IPv6。
    # 只认 banipv6:+变量 这种“取反/转换后下发”的写法，避免误改设置页的映射对象。
    # 找不到该写法时返回 $null（不是加速参数 chunk）。
    param([string]$s)
    $log = New-Object System.Collections.ArrayList
    $pattern = 'banipv6\s*:\s*\+\s*[A-Za-z_$][\w$]*'
    $count = [regex]::Matches($s, $pattern).Count
    if ($count -eq 0) {
        if ([regex]::IsMatch($s, 'banipv6\s*:\s*0')) { return @{ Text = $s; Log = $log } }
        return $null
    }
    $s = [regex]::Replace($s, $pattern, 'banipv6:0')
    $log.Add('加速参数 banipv6 固定为 0（共 ' + $count + ' 处）') | Out-Null
    return @{ Text = $s; Log = $log }
}

function Invoke-Ipv6BanOffPatches {
    # 把「系统设置 → IPV6 禁用」整体固定为关闭。返回 $true 表示本次有改动。
    # 不写死 chunk 名：逐个扫描 assets 下的 js，按代码结构定位。
    param([string]$WorkDir)
    $changed = $false
    $switchSeen = $false
    $paramSeen = $false

    $files = @()
    $assets = Join-Path $WorkDir 'assets'
    if (Test-Path -LiteralPath $assets) {
        $files += @(Get-ChildItem -LiteralPath $assets -Filter '*.js' -File -Force)
    }
    $files += @(Get-ChildItem -LiteralPath $WorkDir -Filter '*.js' -File -Force)

    foreach ($file in $files) {
        $text = Get-JsText $file.FullName
        if ($text.IndexOf('banipv6', [StringComparison]::Ordinal) -lt 0) { continue }
        $rel = Get-UnderRootRel $file.FullName $WorkDir

        $r = Patch-Ipv6SettingSwitch $text
        if ($r) {
            $switchSeen = $true
            Write-Log ('系统设置 chunk：' + $rel)
            $r.Log | ForEach-Object { Write-Log ('  - ' + $_) }
            if ($r.Text -cne $text) { Set-JsText $file.FullName $r.Text; $changed = $true }
            $text = $r.Text
        }

        $r = Patch-Ipv6AccParam $text
        if ($r) {
            $paramSeen = $true
            Write-Log ('加速参数 chunk：' + $rel)
            $r.Log | ForEach-Object { Write-Log ('  - ' + $_) }
            if ($r.Text -cne $text) { Set-JsText $file.FullName $r.Text; $changed = $true }
        }
    }

    if (-not $switchSeen) { throw '找不到「系统设置 → IPV6 禁用」开关的代码（banipv6:…），雷神版本可能变了' }
    if (-not $paramSeen) { throw '找不到加速请求里的 banipv6 参数，雷神版本可能变了' }
    return $changed
}
'@

$payloadSentinel = @'
        if ($KeepIpv6) {
            if (Invoke-Ipv6BanOffPatches $WorkDir) { $changed = $true }
            $info.patches = @($info.patches | Where-Object { $_ -ne 'ipv6-ban-off' }) + 'ipv6-ban-off'
        }
'@

$payloadFresh = @'
    # 2b) 「系统设置 → IPV6 禁用」默认关闭
    if ($KeepIpv6) {
    if (Invoke-Ipv6BanOffPatches $WorkDir) {
        Write-Ok '「系统设置 → IPV6 禁用」已固定为关闭（加速时不禁用 IPv6）'
    } else {
        Write-Ok '「系统设置 → IPV6 禁用」已经是关闭状态，无需改动'
    }
    }
'@

# ---------------------------------------------------------------------------
# 应用
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Source)) { throw ('找不到上游脚本：' + $Source) }
$text = [IO.File]::ReadAllText($Source)
$crlf = "`r`n"

# 1) 帮助文字（可选）
$old = '      - 顶栏固定为悬停高度 60px，鼠标移入/移出不再上下跳' + $crlf
$new = $old + '      - 系统设置里的「IPV6 禁用」默认关闭：开关不再自动打开，' + $crlf + '        加速时也不向驱动下发禁用 IPv6 的指令（默认 Y）' + $crlf
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '帮助文字' -Optional

# 2) .PARAMETER 说明（可选）
$old = '    计时开启且连续 3 分钟未加速时自动暂停时长（默认 Y）。启动时选择 N 可跳过。' + $crlf
$new = $old + $crlf + '.PARAMETER KeepIpv6' + $crlf + '    把「系统设置 → IPV6 禁用」固定为关闭（默认 Y）：开关不再自动打开，读到的旧设置也按关闭显示，' + $crlf + '    加速请求里的 banipv6 固定为 0，不会再让驱动禁用本机 IPv6。启动时选择 N 可跳过。' + $crlf
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '参数说明' -Optional

# 3) 新开关参数（必须）
$old = '    [switch]$AutoPauseIdleTime = $true' + $crlf + ')'
$new = '    [switch]$AutoPauseIdleTime = $true,' + $crlf + '    [switch]$KeepIpv6 = $true' + $crlf + ')'
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '新开关 -KeepIpv6'

# 4) -DisabledFeatures 白名单（必须）
$text = Invoke-ReplaceOnce -Text $text -Old "'AutoPauseIdleTime', 'HideCommunitySidebar'" -New "'AutoPauseIdleTime', 'KeepIpv6', 'HideCommunitySidebar'" -Name '功能白名单'

# 5) 补丁函数本体（必须）
$old = $crlf + '# ===========================================================================' + $crlf + '# ASAR 读写'
$new = $crlf + $payloadFunctions + $crlf + '# ===========================================================================' + $crlf + '# ASAR 读写'
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '补丁函数'

# 6) 已打过旧补丁的升级路径（必须）
$old = "            if (`$added -contains 'stop-button-pause') { `$info.patches = @(`$info.patches | Where-Object { `$_ -ne 'stop-button-pause' }) + 'stop-button-pause' }" + $crlf + '        }' + $crlf
$new = $old + $payloadSentinel + $crlf
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '升级路径调用'

# 7) 全新安装路径（必须）
$old = "    Write-Ok 'IPC 层广告/工具/外链拦截已安装'" + $crlf + $crlf + '    }' + $crlf
$new = $old + $payloadFresh + $crlf
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '全新安装调用'

# 8) 标记文件里的补丁名（可选）
$old = "    if (`$AutoPauseIdleTime) { `$patches += 'idle-time-pause' }" + $crlf
$new = $old + "    if (`$KeepIpv6) { `$patches += 'ipv6-ban-off' }" + $crlf
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '标记文件记录' -Optional

# 9) 交互选择列表（可选：缺了也不影响默认开启，只是不能交互关闭）
$old = "        @('StopButtonPauses', '点击停止加速时同时暂停计时')," + $crlf
$new = $old + "        @('KeepIpv6', '系统设置里的「IPV6 禁用」默认关闭（保持本机 IPv6 可用）')," + $crlf
$text = Invoke-ReplaceOnce -Text $text -Old $old -New $new -Name '交互选择项' -Optional

# 10) 版本号后缀（发布产物专用；上游脚本本身不改）
if ($VersionSuffix) {
    $verRe = [regex]::Match($text, "\`$script:ScriptVersion = '([0-9][^']*)'")
    if (-not $verRe.Success) { throw '找不到 $script:ScriptVersion，无法加版本后缀' }
    $ver = $verRe.Groups[1].Value
    $text = [regex]::Replace($text, "\`$script:ScriptVersion = '" + [regex]::Escape($ver) + "'", "`$script:ScriptVersion = '" + $ver + $VersionSuffix + "'")
    Write-Step ('版本号：' + $ver + $VersionSuffix + '（上游 ' + $ver + '）')
}

# 自检：关键标记必须都在
foreach ($marker in @('Patch-Ipv6SettingSwitch', 'Patch-Ipv6AccParam', 'Invoke-Ipv6BanOffPatches', 'KeepIpv6')) {
    if ($text.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { throw ('补丁后缺少关键内容：' + $marker) }
}

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[IO.File]::WriteAllText($Out, $text, (New-Object System.Text.UTF8Encoding($true)))

Write-Host ('已生成：' + $Out)
if ($script:Warnings.Count -gt 0) {
    Write-Host ('可选项跳过 ' + $script:Warnings.Count + ' 处：' + ($script:Warnings -join '、'))
}