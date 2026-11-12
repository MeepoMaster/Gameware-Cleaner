<#
.SYNOPSIS
    雷神加速器一键精简（Gameware-Cleaner 独立版）

.DESCRIPTION
    双击后逐项用中文 Y/N 选择；M3E 默认开启，系统主题色跟随默认关闭：

      - 渲染层去广告：社区侧栏、底部推广条、首页/游戏列表大横幅、
        顶栏轮播口号、搜索框轮播游戏名
      - 详情页“停止加速”按钮改为“点一下就停表”：直接暂停时长并停止加速，
        不再出现“没加速了但时长还在跑”（不弹确认框，也不弹时长面板）
      - 游戏详情页重新排版（居中单列 + 操作卡片，两个按钮等宽等高）
      - 顶栏固定为悬停高度 60px，鼠标移入/移出不再上下跳
      - 连续 3 分钟未加速时自动暂停计时（默认 Y）
      - M3E 控件换肤，可选择跟随 Windows 系统主题色
      - IPC 层拦截广告接口、广告通知、工具自动下载、活动外链
      - 精简安装目录：client_tools、可下载工具包、SDK 自带工具、应用宝、
        旧 SDK 更新包、日志、更新缓存
      - 工具运行时做硬链接（约省 165 MB）
      - 默认停更：updater.exe 改名 + hosts 屏蔽 buildnum 域名
        （不想停更加 -KeepUpdates）

    所有改动都备份在 %USERPROFILE%\GamewareCleanerBackup\leigod-<时间>，
    备份目录里自带 restore.cmd，随时可以一键还原。

.PARAMETER Root
    雷神安装目录。默认自动在 Program Files / 注册表 / 运行中进程里查找。

.PARAMETER Restore
    还原模式：从备份目录恢复 renderer.asar、被隔离的文件、updater 和 hosts。

.PARAMETER BackupDir
    还原时指定备份目录；不填则自动使用最新的一份。

.PARAMETER KeepUpdates
    不停更：不改 updater.exe，也不改 hosts。

.PARAMETER NoHosts
    只跳过 hosts 修改（调试用）。

.PARAMETER DryRun
    只检查并演练补丁，不修改安装目录、不隔离文件、不写 hosts。

.PARAMETER NoPause
    跳过功能选择和结束等待（自动化测试用）。

.PARAMETER Md3eTheme
    启用 Material Design 3 Expressive 控件外观，默认开启。
.PARAMETER FollowSystemAccent
    M3E 跟随 Windows 系统主题色，默认关闭。增加当前用户登录启动的本地取色助手。
    需同时启用 M3E；普通用户直接在启动后的 Y/N 提示中选择。

.PARAMETER AutoPauseIdleTime
    计时开启且连续 3 分钟未加速时自动暂停时长（默认 Y）。启动时选择 N 可跳过。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\LeiGod-OneClick.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\LeiGod-OneClick.ps1 -KeepUpdates

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\LeiGod-OneClick.ps1 -Restore
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Restore,
    [string]$BackupDir = '',
    [switch]$KeepUpdates,
    [switch]$NoHosts,
    [string]$HostsFile = '',
    [switch]$NoElevate,
    [switch]$DryRun,
    [switch]$NoPause,
    [switch]$Md3eTheme = $true,
    [switch]$FollowSystemAccent,
    [switch]$NonInteractive,
    [string]$DisabledFeatures = '',
    [switch]$HideCommunitySidebar = $true,
    [switch]$HideBottomPromoBar = $true,
    [switch]$HideHomeBanner = $true,
    [switch]$HideHeaderPromo = $true,
    [switch]$PinHeaderHeight = $true,
    [switch]$StopButtonPauses = $true,
    [switch]$BlockAds = $true,
    [switch]$CleanTools = $true,
    [switch]$HardlinkTools = $true,
    [switch]$AutoPauseIdleTime = $true
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$script:ScriptVersion = '0.12.0'
$script:AppTag = 'leigod'
$script:LogPath = $null
$script:TempDir = $null
$script:BackupPath = $null
$script:QuarantineBytes = [int64]0
$script:HardlinkSavedBytes = [int64]0
$script:Completed = $false
$script:ElevationStarted = $false
$featureSwitches = @('Md3eTheme', 'FollowSystemAccent', 'AutoPauseIdleTime', 'HideCommunitySidebar', 'HideBottomPromoBar', 'HideHomeBanner', 'HideHeaderPromo', 'PinHeaderHeight', 'StopButtonPauses', 'BlockAds', 'CleanTools', 'HardlinkTools')
foreach ($feature in ($DisabledFeatures -split ',' | Where-Object { $_.Trim() })) {
    $feature = $feature.Trim()
    if ($featureSwitches -notcontains $feature) { throw ('未知功能名称：' + $feature) }
    Set-Variable -Name $feature -Scope Script -Value $false
}

# ===========================================================================
# 嵌入资源：adblock.js / game-detail-layout.css / header-height-fixed.css / md3e-theme.css
# 与各 JS 补丁一起维护，改动时请整组同步。
# ===========================================================================

$script:AdblockJs = @'
/* Leigod ad / useless-component blocker (user-installed cleanup).
 * Runs in the renderer page world, before the app bundle. */
(function () {
  'use strict';

  var AD_API = /(?:\/secapi\/tools\/(?:banner\/list|inner\/banner\/list|game\/popup\/carousel|notice\/popup|game\/toolbox)|\/webapi\/api\/(?:activity|invite)|\/window-advertise)/i;
  var AD_LINK = /(?:leigod\.com\/(?:activitys|activities_greatest|activity\/)|\/window-advertise|\/follow-reward)/i;
  var AD_CSS = [
    '.acc-advertise__wrapper',
    '.simple-advertise-wrapper',
    '[class*="advertise-wrapper"]',
    '.modal-content-banner',
    '.activity-pack-ad'
  ].join(',');

  function toUrl(v) {
    if (!v) return '';
    if (typeof v === 'string') return v;
    if (typeof v === 'object') return String(v.url || v.URL || v.href || '');
    return String(v);
  }

  // Block promotional pages opened as external links / popup windows.
  var origOpen = window.open;
  if (typeof origOpen === 'function') {
    window.open = function (url) {
      if (AD_LINK.test(toUrl(url))) return null;
      return origOpen.apply(window, arguments);
    };
  }

  // Hide any ad containers that still get rendered from cached data.
  function hideAds(root) {
    if (!root || !root.querySelectorAll) return;
    var nodes = root.querySelectorAll(AD_CSS);
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].style.setProperty('display', 'none', 'important');
    }
  }

  function startObserver() {
    hideAds(document);
    if (typeof MutationObserver !== 'function') return;
    new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var added = records[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          if (added[j] && added[j].nodeType === 1) hideAds(added[j]);
        }
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startObserver, { once: true });
  } else {
    startObserver();
  }

  // Keep the ad-only route from being reached if something navigates to it.
  function guardHistory(name) {
    var orig = history[name];
    if (typeof orig !== 'function') return;
    history[name] = function (state, title, url) {
      if (url && String(url).indexOf('window-advertise') !== -1) {
        return orig.call(this, state, title, '/home');
      }
      return orig.apply(this, arguments);
    };
  }
  guardHistory('pushState');
  guardHistory('replaceState');
})();
'@

$script:GameDetailLayoutCss = @'
/* Gameware-Cleaner: re-layout the LeiGod game-detail page after the bottom
 * promo bar has been removed from the renderer (and optionally the community
 * sidebar as well).
 *
 * Why this file exists: with the 247px banner gone, .game-detail-content gets
 * the full page height. .game-info is a column with justify-content:space-between,
 * so the poster, the link diagram and the action buttons get spread far apart,
 * and the removed sidebar leaves the right side empty.
 *
 * This stylesheet turns the loose column into one centered 572px column:
 *   identity block -> link diagram -> status line -> CTA card
 * and gives the two action buttons a proper card of their own.
 *
 * Install together with hideBottomPromoBar. It is safe to keep when the
 * community sidebar is also removed; if only the sidebar is removed (banner
 * still present) do NOT install it - the original layout still fits the
 * shorter content row.
 */

/* Center the composition in the freed space. .flex-jsb (space-between) is
 * overridden on purpose. padding-left:256px stays as-is: it is the space
 * reserved for the app slider. */
.game-detail .game-info {
  justify-content: center !important;
  align-items: center !important;
  gap: 34px !important;
  height: 100% !important;
  padding-top: 12px !important;
  padding-bottom: 12px !important;
  box-sizing: border-box;
}

/* One shared column so the identity block, link diagram, status line and CTA
 * all line up on the same left/right edges. 572px is the width the link
 * diagram already uses. */
.game-detail .game-info > * {
  flex-shrink: 0;
  width: 572px;
  max-width: 100%;
}

/* Larger identity block: the poster grows from 120px to 132px. */
.game-detail .game-info .game-info-wrap {
  height: 132px !important;
}
.game-detail .game-info .game-info-wrap .game-logo {
  width: 132px !important;
  height: 132px !important;
}
.game-detail .game-info .game-info-wrap .game-info-detail {
  height: 132px !important;
  margin-top: 0 !important;
  justify-content: center;
}
.game-detail .game-info .game-info-wrap .game-title-wrap {
  width: auto !important;
  max-width: 473px;
}

/* Status line: server entry on the left, network monitor on the right edge. */
.game-detail .game-info .acc-info-detail-line-wrap {
  justify-content: space-between;
}

/* Action area as one card. */
.game-detail .game-info .acc-info-bottom-wrap {
  flex: 0 0 auto !important;
  width: 572px;
  max-width: 100%;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 22px !important;
  background: var(--ls-color-gray-10, rgba(255, 255, 255, .04));
  border: 1px solid var(--ls-color-gray-9, rgba(255, 255, 255, .06));
  border-radius: var(--ls-radius-10r, 10px);
}
.game-detail .game-info .game-acc-btn-wrap {
  margin-bottom: 0 !important;
}
/* Both action buttons split the card evenly. The tooltip renders a
 * display:contents wrapper, so the real flex item is its inner div - flex on
 * the wrapper itself does nothing; target the wrapper's children instead. */
.game-detail .game-info .game-acc-btn-wrap > * {
  flex: 1 1 0;
  min-width: 0;
}
.game-detail .game-info .game-acc-btn-wrap .tooltip-wrapper > * {
  flex: 1 1 0;
  min-width: 0;
}
.game-detail .game-info .game-acc-btn-wrap .leigod-button,
.game-detail .game-info .game-acc-btn-wrap .launch-btn {
  flex: 1 1 0;
  width: 100% !important;
  height: 54px !important;
  min-width: 0;
}
.game-detail .game-info .game-acc-btn-wrap .leigod-button {
  --ls-lei-button-width: auto !important;
  --ls-lei-button-height: 54px !important;
  --ls-lei-button-font-size: 20px !important;
}
'@

$script:HeaderHeightCss = @'
/* Gameware-Cleaner: pin the LeiGod top bar to its hover height.
 *
 * Stock rules in the main bundle (index-<hash>.css):
 *   .app-layout .app-layout-header        { height: var(--app-header-height, 50px);
 *                                           transition: height .2s linear; }
 *   .app-layout .app-layout-header:hover  { height: 60px; }
 *
 * The bar is absolutely positioned at top: 0 and its contents are vertically
 * centred, so the 50 -> 60 change only makes the logo/search/timer row jump
 * down 5px on hover and jump back up when the pointer leaves. Pin the box to
 * 60px so it always stays at the position that looked right on hover, and drop
 * the animation.
 *
 * --app-header-height stays at 50px on purpose: the hover state never moved
 * the content area below the bar either, so the visual result is identical to
 * the old hover state without pushing the page content down.
 */
.app-layout .app-layout-header {
  height: 60px !important;
  transition: none !important;
}

.app-layout .app-layout-header:hover {
  height: 60px !important;
}
'@

$script:Md3eThemeCss = @'
/* Gameware-Cleaner: Material Design 3 Expressive (MD3E) theme layer for LeiGod.
 *
 * This is a PURE CSS theme. It does not touch any JS, does not change behaviour,
 * and is removed by deleting one <link> from index.html.
 *
 * How it works, in two layers:
 *
 *   Layer A - token redefinition. The LeiGod renderer funnels part of its visual
 *   layer through CSS custom properties (--ls-*, --el-*). Redefining those tokens
 *   re-skins every component that reads them, at once.
 *
 *   Layer B - explicit component rules. Only ~26% of the renderer's
 *   border-radius declarations go through a token; 434 of 595 are literal pixel
 *   values (4px / 2px / 6px / 8px ...) that no token can reach. Layer A alone
 *   therefore leaves most of the UI - nav chips, tabs, segmented controls,
 *   search fields, list rows, icon tiles, tags, close buttons - looking exactly
 *   as sharp as before. Layer B patches those selectors directly, at the same
 *   specificity the app uses, so the shape really changes everywhere.
 *
 * Colour: seed = LeiGod brand blue #4E41DB, HCT variant "tonalspot" so the hue is
 * preserved rather than shifted. Role values are generated by the md3e skill's
 * generate_theme.py (material-color-utilities HCT). Dark scheme is authoritative -
 * the renderer ships <html class="dark">.
 *
 * The header recharge entry follows the theme; its payment flow is unchanged.
 * Scope note: other account-, pay-, activity-, ad- and update-related surfaces
 * (pay*, activity*, ranking*, invite*, coupon*, gift*, advertise*, wx-*, login*,
 * bind*, forget*, memory*, scan*, repair*, process*, upload*) are deliberately
 * left alone. They are either removed by adblock.js, unreachable after the
 * optional update freeze, or out of scope for a "make the app look MD3E" pass,
 * and restyling them multiplies the surface area we would have to re-verify.
 *
 * Reversible: delete the <link rel="stylesheet" href="./md3e-theme.css"> line.
 */

/* ==========================================================================
 * 1. MD3E colour roles (dark, seed #4E41DB / tonalspot)
 * ======================================================================== */

/* Recharge artwork comes from the server and has baked-in colours. Use a
 * monochrome card glyph while retaining the original entry and click handler. */
html.dark .layout-header .recharge-enrty {
  color: var(--md3e-primary) !important;
  gap: 6px;
}
html.dark .layout-header .recharge-enrty .recharge-icon {
  display: none !important;
}
html.dark .layout-header .recharge-enrty .recharge-text::before {
  content: "";
  display: inline-block;
  vertical-align: middle;
  margin-right: 6px;
  width: 20px;
  height: 20px;
  flex: 0 0 20px;
  background: currentColor;
  -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Zm0 2v3h16V6H4Zm0 6v6h16v-6H4Zm2 2h5v2H6v-2Z'/%3E%3C/svg%3E") center / contain no-repeat;
}
html.dark .layout-header .recharge-enrty .recharge-text {
  color: var(--md3e-primary) !important;
  background-image: none !important;
  -webkit-text-fill-color: currentColor !important;
}
html.dark .layout-header .recharge-enrty:hover {
  color: var(--md3e-on-primary-container) !important;
}
html.dark .layout-header .recharge-enrty:hover .recharge-text {
  color: inherit !important;
}

html.dark:root,
:root[data-theme="dark"] {
  --md3e-primary: #C4C0FF;
  --md3e-on-primary: #2C2960;
  --md3e-primary-container: #434078;
  --md3e-on-primary-container: #E3DFFF;
  --md3e-secondary: #C7C4DC;
  --md3e-on-secondary: #302E42;
  --md3e-secondary-container: #464559;
  --md3e-on-secondary-container: #E3E0F9;
  --md3e-tertiary: #EAB9D1;
  --md3e-on-tertiary: #472638;
  --md3e-tertiary-container: #603B4F;
  --md3e-on-tertiary-container: #FFD8EA;

  --md3e-error: #FFB4AB;
  --md3e-on-error: #690005;
  --md3e-error-container: #93000A;
  --md3e-on-error-container: #FFDAD6;

  --md3e-surface: #131318;
  --md3e-on-surface: #E5E1E9;
  --md3e-surface-variant: #47464F;
  --md3e-on-surface-variant: #C8C5D0;
  --md3e-surface-dim: #131318;
  --md3e-surface-bright: #39383F;
  --md3e-surface-container-lowest: #0E0E13;
  --md3e-surface-container-low: #1C1B21;
  --md3e-surface-container: #201F25;
  --md3e-surface-container-high: #2A292F;
  --md3e-surface-container-highest: #35343A;

  --md3e-outline: #928F99;
  --md3e-outline-variant: #47464F;
  --md3e-inverse-surface: #E5E1E9;
  --md3e-inverse-on-surface: #313036;
  --md3e-scrim: #000000;

  /* state-layer opacity, MD3E: hover 8%, focus 10%, pressed 12% */
  --md3e-state-hover: 0.08;
  --md3e-state-pressed: 0.12;
}

/* Baseline M3 + MD3E for the (unused today) light path, so a future theme
 * switch does not fall back to raw black-on-white. */
:root:not(.dark):not([data-theme="dark"]) {
  --md3e-primary: #5B5891;
  --md3e-on-primary: #FFFFFF;
  --md3e-primary-container: #E3DFFF;
  --md3e-on-primary-container: #17134A;
  --md3e-secondary: #5C5B70;
  --md3e-on-secondary: #FFFFFF;
  --md3e-secondary-container: #E1E0F9;
  --md3e-on-secondary-container: #19182B;
  --md3e-tertiary: #795367;
  --md3e-on-tertiary: #FFFFFF;
  --md3e-tertiary-container: #FFD8EA;
  --md3e-on-tertiary-container: #2F1123;
  --md3e-error: #BA1A1A;
  --md3e-on-error: #FFFFFF;
  --md3e-error-container: #FFDAD6;
  --md3e-on-error-container: #93000A;
  --md3e-surface: #FCF8FF;
  --md3e-on-surface: #1B1B21;
  --md3e-surface-variant: #E5E1EC;
  --md3e-on-surface-variant: #47464F;
  --md3e-surface-dim: #DCD9E0;
  --md3e-surface-bright: #FCF8FF;
  --md3e-surface-container-lowest: #FFFFFF;
  --md3e-surface-container-low: #F6F2FA;
  --md3e-surface-container: #F0ECF4;
  --md3e-surface-container-high: #EAE6EF;
  --md3e-surface-container-highest: #E5E1E9;
  --md3e-outline: #777680;
  --md3e-outline-variant: #C8C5D0;
  --md3e-inverse-surface: #303036;
  --md3e-inverse-on-surface: #F3EFF7;
  --md3e-scrim: #000000;
  --md3e-state-hover: 0.08;
  --md3e-state-pressed: 0.12;
}

/* ==========================================================================
 * 2. Re-map the app's own token layer onto the MD3E roles
 *
 * LeiGod resolves every surface/text colour through --ls-color-gray-N and a few
 * semantic aliases. Redefining them here re-skins the whole app at once, instead
 * of chasing individual rules.
 * ======================================================================== */

html.dark:root,
:root[data-theme="dark"] {
  /* Elevation ladder -> MD3E surface container hierarchy.
     gray-1 is the page background, gray-2 the persistent panel/drawer. */
  --ls-color-gray-1: var(--md3e-surface);
  --ls-color-gray-2: var(--md3e-surface-container);
  --ls-color-gray-3: var(--md3e-on-surface);
  --ls-color-gray-4: var(--md3e-on-surface);
  --ls-color-gray-5: var(--md3e-on-surface-variant);
  --ls-color-gray-6: var(--md3e-on-surface-variant);
  --ls-color-gray-7: var(--md3e-outline-variant);
  --ls-color-gray-8: var(--md3e-outline-variant);
  --ls-color-gray-9: var(--md3e-outline-variant);
  --ls-color-gray-10: var(--md3e-surface-container-high);
  --ls-color-gray-11: var(--md3e-surface-container-highest);
  --ls-color-gray-12: var(--md3e-scrim);
  --ls-color-gray-13: var(--md3e-on-surface-variant);
  --ls-color-gray-14: var(--md3e-surface-container-low);
  --ls-color-gray-15: var(--md3e-primary);

  --ls-color-shadow: rgba(0, 0, 0, 0.4);
  --ls-color-mask: rgba(0, 0, 0, 0.6);

  /* Brand accent -> MD3E primary. Kept as the *container* tone on large fills so
     the client still reads as LeiGod, with the light primary reserved for
     accents, icons and active states. */
  --ls-color-Esports_Blue: var(--md3e-primary-container);
  --ls-color-Esports_Blue-dark: var(--md3e-primary);
}

/* ==========================================================================
 * 3. Shape scale -> MD3E 8-step scale
 *
 * MD3E: 4 / 8 / 12 / 16 / 20 / 28 / 32 / 48. LeiGod sat at 2-16px, which read
 * flat; this raises the whole corner language one step.
 * --ls-lei-*-radius are the radii the app's own button/input components read,
 * so setting them here reaches every instance that already opted into a token.
 * ======================================================================== */

:root {
  --ls-radius-2r: 8px;
  --ls-radius-3r: 4px;
  --ls-radius-4r: 8px;
  --ls-radius-5r: 8px;
  --ls-radius-6r: 12px;
  --ls-radius-8r: 12px;
  --ls-radius-10r: 12px;
  --ls-radius-12r: 16px;
  --ls-radius-14r: 16px;
  --ls-radius-16r: 20px;
  --ls-radius-sm: 8px;
  --ls-radius-md: 12px;
  --ls-radius-lg: 16px;
  --ls-radius-xl: 28px;
  --ls-radius-xxl: 32px;

  /* Component-level radii the app reads for its own button/input/tag/switch. */
  --ls-lei-button-radius: 999px;
  --ls-lei-input-radius: 8px;
  --leigod-tag-border-radius: 999px;
  --scrollbar-thumb-radius: 999px;

  /* Element Plus radius tokens inherit the same scale. */
  --el-border-radius-small: 4px;
  --el-border-radius-base: 8px;
  --el-border-radius-round: 999px;
}

/* ==========================================================================
 * 4. Motion -> MD3E emphasized easing + duration tokens
 *
 * MD3E replaces the old ease-in-out curves with the "emphasized" family:
 *   emphasized           cubic-bezier(0.2, 0, 0, 1)
 *   emphasizedDecelerate cubic-bezier(0.05, 0.7, 0.1, 1)
 *   emphasizedAccelerate cubic-bezier(0.3, 0, 0.8, 0.15)
 * Durations: short 50-200, medium 250-400, long 450-600.
 * ======================================================================== */

:root {
  --md3e-ease-emphasized: cubic-bezier(0.2, 0, 0, 1);
  --md3e-ease-emphasized-decelerate: cubic-bezier(0.05, 0.7, 0.1, 1);
  --md3e-ease-emphasized-accelerate: cubic-bezier(0.3, 0, 0.8, 0.15);
  --md3e-duration-short: 150ms;
  --md3e-duration-medium: 300ms;
  --md3e-duration-long: 500ms;

  --el-transition-duration: 300ms;
  --el-transition-duration-fast: 150ms;
  --el-transition-function-ease-in-out-bezier: cubic-bezier(0.2, 0, 0, 1);
  --el-transition-function-fast-bezier: cubic-bezier(0.05, 0.7, 0.1, 1);
}

/* ==========================================================================
 * 5. Typography -> MD3E roles
 *
 * Tokens keep LeiGod's CJK font stack (Microsoft YaHei / PingFang) because the
 * UI is Simplified Chinese, but adopt the MD3E ramp sizes, line heights and
 * letter spacing.
 * ======================================================================== */

:root {
  --ls-font-small: 11px;   /* labelSmall 11/16 */
  --ls-font-medium: 12px;  /* bodySmall/labelMedium 12/16 */
  --ls-font-default: 14px; /* bodyMedium 14/20 */
  --ls-font-large: 16px;   /* bodyLarge 16/24 */
}

body,
#app {
  line-height: 1.45;
  letter-spacing: 0.15px;
  -webkit-font-smoothing: antialiased;
}

/* ==========================================================================
 * 6. Buttons, tags, switches
 * ======================================================================== */

/* --- Filled buttons: MD3E pill shape, tonal state layer ------------------- */

html.dark .leigod-button {
  border-radius: 999px !important;
  background-image: none !important;
  box-shadow: none;
  transition:
    background-color var(--md3e-duration-medium) var(--md3e-ease-emphasized),
    box-shadow var(--md3e-duration-medium) var(--md3e-ease-emphasized),
    transform var(--md3e-duration-short) var(--md3e-ease-emphasized);
}

html.dark .leigod-button::before {
  border-radius: inherit;
}


html.dark .leigod-button:not(.disabled):not(.static):not([disabled]):active {
  transform: scale(0.97);
}

/* --- Compact action buttons that hardcode a 2px corner ------------------- */

html.dark .detail-btn,
html.dark .network-detection .detection-info .button,
html.dark .detection-report .report-retest-button,
html.dark .system-tuning-container .system-tuning-status .system-tuning-status-desc .system-tuning-status-desc-btn,
html.dark .system-tuning-container .system-tuning-status .system-tuning-status-action .back .back-btn,
html.dark .select-line-node-content .footer-wrap .start-acc-wrap .acc-button-container .acc-button,
html.dark .close-tip-modal-dialog .close-tip-modal-button-groups .close-tip-modal-button1,
html.dark .close-tip-modal-dialog .close-tip-modal-button-groups .close-tip-modal-button2,
html.dark .user-center-layout .layout-content .page-header .close-btn .close {
  border-radius: 999px !important;
}

/* --- Toggle switch: MD3E pill track + pill thumb ------------------------- */

html.dark .leigod-switch,
html.dark .leigod-switch-block {
  border-radius: 999px !important;
}

html.dark .leigod-switch::before,
html.dark .leigod-switch-block::before,
html.dark .frame-boost-container .system-tuning-status .switch-wrapper .frame-boost-switch::before,
html.dark .options-detail .options-item .leigod-switch::before,
html.dark .timelong-popover-content .time-info-detail-wrap .time-info-list-container .time-auto-open-setting .time-auto-open-switch::before {
  border-radius: 999px !important;
}

/* --- Tags / badges / counters ------------------------------------------- */

html.dark .leigod-tag,
html.dark .el-tag,
html.dark .user-menu .tip,
html.dark .user-menu .new-tip,
html.dark .user-menu .show-num,
html.dark .layout-header .icon-button.nav-button .unread-num,
html.dark .user-center-layout .sidebar .show-num,
html.dark .node-drawer-overlay .node-drawer-content .drawer-list-wrap .drawer-node-item .node-status .best-tag,
html.dark .select-line-node-content .line-node-title .line-node .best-node-tag,
html.dark .select-line-node-content .line-node-list-wrap .line-node-item .line-node .best-node-tag,
html.dark .select-line-node-content .line-node-list-container .refresh .last-select-tag,
html.dark .select-line-node-content .select-area-list .select-area-item .node-status .best-tag,
html.dark .select-line-node-content .start-acc-wrap .exclusively-tag,
html.dark .select-line-node-content .footer-wrap .start-acc-wrap .acc-button-container .dy-game-tag,
html.dark .ex-ip-pop-content .ex-ip-header .ex-ip-info .ex-title-row .ex-badge,
html.dark .search-result .search-result-item .search-result-item-desc .free-icon {
  border-radius: 999px !important;
}

/* --- Element Plus buttons: pill, matching .leigod-button ---------------- */

html.dark .el-button {
  border-radius: 999px;
}

/* ==========================================================================
 * 7. Containers: cards, panels, rows, sheets
 *
 * Every selector here was hardcoding 2-4px. Grouped by the MD3E shape step they
 * map onto:
 *   16px - content cards and standalone panels
 *   12px - dense list rows, nested detail cards, icon tiles, small media
 *   28px - top-level surfaces (dialogs)
 * ======================================================================== */

/* --- 16px: content cards, report panels, standalone containers ---------- */

html.dark .game-item-wrap,
html.dark .game-item-wrap::before,
html.dark .game-download-item-wrap,
html.dark .game-download-item-wrap::before,
html.dark .game-item,
html.dark .game-item-palceholder,
html.dark .game-list-container .game-list-wrapper .game-list-item:not(.title) .game-item-palceholder,
html.dark .detection-report .report-card,
html.dark .detection-report .report-panel,
html.dark .game-area-list > .game-area-item,
html.dark .lan-game-card,
html.dark .local-game-dialog .game-item {
  border-radius: 16px !important;
}

/* The card hairline inherits the same corner so the outline does not poke out. */
html.dark .game-item-wrap::before,
html.dark .game-download-item-wrap::before {
  border-radius: inherit !important;
}

/* --- 12px: dense rows, nested cards, icon tiles, small media ----------- */

html.dark .list-item,
html.dark .list-item .icon-wrapper,
html.dark .game-tools-item .game-tools-item-icon,
html.dark .all-tool-modal-header .close-button,
html.dark .all-tools-modal-body .all-tools-modal-add .all-tools-modal-add-list .all-tools-modal-add-item .game-tools-item-icon,
html.dark .all-tools-modal-body .all-tools-modal-no-add .all-tools-modal-add-list .all-tools-modal-add-item .game-tools-item-icon,
html.dark .card-logo,
html.dark .game-info .acc-info-detail-line-wrap .acc-line-info,
html.dark .game-item .logo-background,
html.dark .game-item .logo-loading,
html.dark .game-item .logo.image .logo-img,
html.dark .node-drawer-overlay .node-drawer-content,
html.dark .select-line-node-content .area-list-wrap .area-list-item,
html.dark .system-tuning-container .system-tuning-detail,
html.dark .search-result-item,
html.dark .nav-nav-dropdown {
  border-radius: 12px !important;
}

/* Small square icon tiles that should read as full circles, not squircles. */
html.dark .game-tools-item .icon-wrapper {
  border-radius: 999px !important;
}

/* --- 28px: top-level dialog / sheet surfaces --------------------------- */

html.dark .leigod-modal,
html.dark .new-local-game-dialog .leigod-modal {
  border-radius: 28px !important;
}

/* The app rounds only the top two corners of the pay-success header shell to
 * match its dialog. Follow suit with the MD3E step so the seam still lines up. */
html.dark .leigod-modal .leigod-modal-header {
  border-radius: 28px 28px 0 0 !important;
}

html.dark .leigod-modal .leigod-modal-body,
html.dark .leigod-modal-mask,
html.dark .leigod-modal-mask .leigod-modal .leigod-modal-body {
  border-radius: inherit !important;
}

/* --- Close affordances: circle, wherever they were 4-15px squircles ---- */

html.dark .leigod-modal-header .close-button,
html.dark .leigod-modal .leigod-modal-header .close-button,
html.dark .leigod-modal-mask .leigod-modal .leigod-modal-header .leigod-modal-header-content .close-button,
html.dark .close-tip-modal-header .close-button,
html.dark .erweima-modal-header .close-button,
html.dark .header-logo-ad-modal-header .close-button,
html.dark .network-type-content .close-button,
html.dark .receive-success-modal-header .close-button,
html.dark .rule-modal-header .close-button,
html.dark .task-modal-header .close-button,
html.dark .task-win-dialog-header .close-button,
html.dark .tool-satisfaction-survey-modal-header .close-button {
  border-radius: 999px !important;
}

/* ==========================================================================
 * 8. Navigation, tabs and segmented controls
 *
 * These are the surfaces that read as "sharp" most often, because their radii
 * were literal 2-4px values in per-component stylesheets.
 * ======================================================================== */

/* --- Top-level nav chips: pill ----------------------------------------- */

html.dark .home-page .home-nav-wrap .home-nav .home-nav-item,
html.dark .tab-list .tab,
html.dark .tab-item {
  border-radius: 999px !important;
}

/* --- Active indicators: keep the MD3E rounded bar ---------------------- */

html.dark .home-page .home-nav-wrap .home-nav .home-nav-item.active::after {
  border-radius: 999px 999px 0 0 !important;
}

/* --- Segmented control: pill track + pill segment ---------------------- */

html.dark .segmented {
  border-radius: 999px !important;
  overflow: hidden;
}

html.dark .segmented div,
html.dark .segmented .active {
  border-radius: 999px !important;
}

/* --- Search fields: pill, matching the MD3E search treatment ----------- */

html.dark .header-game-search,
html.dark .header-game-search::before,
html.dark .search-modal-container .search-modal-content .search-modal-title .header-game-search,
html.dark .search-modal-container .search-modal-content .search-modal-title .header-game-search::before {
  border-radius: 999px !important;
}

/* ==========================================================================
 * 9. Inputs and text fields
 * ======================================================================== */

html.dark .input-container,
html.dark .leigod-input,
html.dark .search-input,
html.dark .el-input__wrapper,
html.dark .el-textarea__inner {
  border-radius: 8px !important;
  background-color: var(--md3e-surface-container-high) !important;
  transition:
    background-color var(--md3e-duration-medium) var(--md3e-ease-emphasized),
    box-shadow var(--md3e-duration-medium) var(--md3e-ease-emphasized);
}

html.dark .input-container:focus-within,
html.dark .leigod-input:focus-within,
html.dark .search-input:focus-within,
html.dark .el-input__wrapper.is-focus {
  background-color: var(--md3e-surface-container-highest) !important;
  box-shadow: inset 0 -2px 0 0 var(--md3e-primary);
}

/* The search field is a pill; a straight underline would look wrong there. */
html.dark .search-input:focus-within,
html.dark .header-game-search:focus-within {
  box-shadow: none;
  border-color: var(--md3e-primary) !important;
}

/* ==========================================================================
 * 10. Dialogs, popovers, dropdowns, tooltips
 * ======================================================================== */

html.dark .el-dialog,
html.dark .el-popover,
html.dark .el-popper,
html.dark .el-select__popper,
html.dark .toast {
  border-radius: 12px !important;
  background-color: var(--md3e-surface-container-high) !important;
  border: 1px solid var(--md3e-outline-variant);
}

/* Menu rows keep the popper's own surface; only the shape changes. Giving
 * them the surface tone made every row look like a separate outlined card. */
html.dark .nav-nav-dropdown .el-dropdown-menu__item {
  border-radius: 12px !important;
  background-color: transparent !important;
  border: 0 !important;
}

html.dark .nav-nav-dropdown .el-dropdown-menu__item:hover,
html.dark .nav-nav-dropdown .el-dropdown-menu__item:focus,
html.dark .nav-nav-dropdown .el-dropdown-menu__item.is-active {
  background-color: var(--md3e-surface-container-highest) !important;
}

html.dark .el-popper.ex-ip-pop {
  border-radius: 12px !important;
}

html.dark .toast {
  border-radius: 16px !important;
}

html.dark .lei-tooltip,
html.dark .lei-tooltip.cycle-tooltip-popper {
  border-radius: 8px !important;
}

html.dark .nav-nav-dropdown {
  border-radius: 12px !important;
  overflow: hidden;
}

/* ==========================================================================
 * 11. Progress and sliders
 * ======================================================================== */

html.dark .progress-bar,
html.dark .progress-bar::before,
html.dark .progress-bar::after,
html.dark .dnsBoxBaseModal .dnsBox .progress-bar,
html.dark .dnsBoxBaseModal .dnsBox .progress-bar .progress-bar-inner,
html.dark .el-progress-bar__outer,
html.dark .el-progress-bar__inner,
html.dark .el-slider__runway,
html.dark .el-slider__bar,
html.dark .el-slider__button,
html.dark .el-slider.custom-slider,
html.dark .el-slider.custom-slider .el-slider__button {
  border-radius: 999px !important;
}

html.dark .el-slider.is-vertical .el-slider__bar {
  border-radius: 0 0 8px 8px !important;
}

html.dark .el-steps--simple {
  border-radius: 12px !important;
}

/* ==========================================================================
 * 12. Scrollbars: pill thumb, matched to the surface ladder
 * ======================================================================== */

html.dark ::-webkit-scrollbar-thumb,
html.dark ::-webkit-scrollbar-thumb:not(.el-scrollbar__wrap),
html.dark .el-scrollbar__bar,
html.dark .el-scrollbar__thumb,
html.dark .el-input::-webkit-scrollbar-thumb,
html.dark .wrapper::-webkit-scrollbar-thumb,
html.dark .header-logo-ad-modal-body::-webkit-scrollbar-thumb {
  border-radius: 999px !important;
  background-color: var(--md3e-outline-variant);
}

/* ==========================================================================
 * 13. Remaining corner fixes the shape table above does not classify
 * ======================================================================== */

/* Icon-logo pinned to the top-left of a game card keeps ONE square corner so it
 * still reads as a corner flag; only the outer corner follows the card. */
html.dark .game-item-wrap .platform-icon-wrap {
  border-radius: 16px 0 !important;
}

/* Download-progress sliver inside a tool tile: only the trailing corners. */
html.dark .game-image-tools-item.downloading::after,
html.dark .game-image-tools-item.starting::after {
  border-radius: 0 12px 12px 0 !important;
}

/* Section heading marker: was a 4px-wide 10px-radius bar, now a capsule. */
html.dark .game-list-container .game-list-wrapper .game-list-title::before {
  border-radius: 999px !important;
}

/* ==========================================================================
 * 14. Motion: swap the app's ease-in-out curves for MD3E emphasized
 *
 * The renderer still ships `transition: all .2s` on most interactive surfaces.
 * We re-declare the properties that actually change so the curve and duration
 * come from the MD3E tokens instead, without a blanket `transition: all` that
 * would also animate layout offsets.
 * ======================================================================== */

html.dark .leigod-button,
html.dark .game-item-wrap,
html.dark .home-page .home-nav-wrap .home-nav .home-nav-item,
html.dark .tab-list .tab,
html.dark .tab-item,
html.dark .segmented div,
html.dark .list-item .icon-wrapper,
html.dark .menu-list-item,
html.dark .user-menu .user-menu-list-item,
html.dark .nav-nav-dropdown .el-dropdown-menu__item,
html.dark .leigod-tag,
html.dark .el-tag,
html.dark .header-game-search,
html.dark .search-input,
html.dark .leigod-switch,
html.dark .el-slider__button {
  transition:
    background-color var(--md3e-duration-medium) var(--md3e-ease-emphasized),
    border-color var(--md3e-duration-medium) var(--md3e-ease-emphasized),
    color var(--md3e-duration-short) var(--md3e-ease-emphasized),
    box-shadow var(--md3e-duration-medium) var(--md3e-ease-emphasized),
    transform var(--md3e-duration-short) var(--md3e-ease-emphasized);
}

/* --- Entrance: container transform (MD3E "container transform" pattern) --
 * Dialogs and the toast fade up from a slightly compressed scale, on the
 * emphasized-decelerate curve so they arrive quickly and settle softly. */

@keyframes md3e-container-enter {
  from {
    opacity: 0;
    transform: scale(0.96) translateY(8px);
  }
  to {
    opacity: 1;
    transform: scale(1) translateY(0);
  }
}

@keyframes md3e-fade-enter {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

html.dark .leigod-modal,
html.dark .el-dialog,
html.dark .el-popover,
html.dark .el-popper {
  animation: md3e-fade-enter var(--md3e-duration-medium) var(--md3e-ease-emphasized-decelerate) both;
}

html.dark .toast,
html.dark .el-scrollbar__thumb,
html.dark .lei-tooltip {
  animation: md3e-fade-enter var(--md3e-duration-short) var(--md3e-ease-emphasized) both;
}

/* Honour the OS "reduce motion" setting: keep the theme, drop the movement. */
@media (prefers-reduced-motion: reduce) {
  html.dark .leigod-modal,
  html.dark .el-dialog,
  html.dark .el-popover,
  html.dark .el-popper,
  html.dark .toast,
  html.dark .el-scrollbar__thumb,
  html.dark .lei-tooltip {
    animation: none !important;
  }

  html.dark .leigod-button:active {
    transform: none !important;
  }
}

/* ==========================================================================
 * 15. Component treatment carried over from the first pass
 * ======================================================================== */

/* --- Cards: content grouping on a surface container tone ------------------- */

html.dark .game-item-wrap {
  background-color: var(--md3e-surface-container) !important;
  transition:
    background-color var(--md3e-duration-medium) var(--md3e-ease-emphasized),
    transform var(--md3e-duration-medium) var(--md3e-ease-emphasized);
}

html.dark .game-item-wrap:before {
  border-color: var(--md3e-outline-variant) !important;
}

html.dark .game-item-wrap:hover {
  background-color: var(--md3e-surface-container-high) !important;
  transform: translateY(-2px);
}

html.dark .game-item-wrap:hover:before {
  opacity: 1;
}

/* --- Top bar: same surface-container tone as the cards --------------------- */

html.dark .app-layout .app-layout-header,
html.dark .layout-header {
  background-color: var(--md3e-surface-container) !important;
}

/* --- Detail-page CTA card (installed by game-detail-layout.css) ------------ */

html.dark .game-detail .game-info .acc-info-bottom-wrap {
  background: var(--md3e-surface-container) !important;
  border: 1px solid var(--md3e-outline-variant) !important;
  border-radius: 16px !important;
  padding: 24px !important;
}

/* --- Hero moment: the primary accelerate CTA ------------------------------- */

html.dark .game-detail .game-info .game-acc-btn-wrap .leigod-button:not(.warning):not(.disabled):not([disabled]) {
  background-color: var(--md3e-primary) !important;
  color: var(--md3e-on-primary) !important;
  box-shadow: 0 2px 6px 2px rgba(0, 0, 0, 0.15), 0 1px 2px 0 rgba(0, 0, 0, 0.3);
}


/* ==========================================================================
 * 16. Second-pass coverage (2026-11-10)
 *
 * The Layer B sweep in section 7-13 was built from the flat list of
 * border-radius declarations. This section closes the components that list
 * could not classify: the detail-page poster, the line/node drawer, list
 * rows, avatars, badges and the small status strips. Same rule as above -
 * reach the literal pixel values, leave every surface the theme already
 * covers untouched.
 * ======================================================================== */

/* --- Detail page: the game poster and its corner label ------------------- */

/* .game-logo asks for --ls-radius-10r, but .game-logo-img re-declares a
 * literal 6px after `border-radius: inherit`, so the poster has been rendering
 * at 6px all along. */
html.dark .game-info .game-info-wrap .game-logo,
html.dark .game-info .game-info-wrap .game-logo .game-logo-img {
  border-radius: 16px !important;
}

html.dark .game-info .game-info-wrap .game-logo .free-label {
  border-radius: 16px 0 12px 0 !important;
}

/* --- Line / node drawer: segmented control, area rows, table header ------ */

/* Track + segments read as one pill each, matching the nav chips in
 * section 8. The track itself was square. */
html.dark .select-line-node-content .view-type-wrap {
  border-radius: 999px !important;
  overflow: hidden;
}

html.dark .select-line-node-content .view-type-wrap .view-type-item {
  border-radius: 999px !important;
}

html.dark .select-line-node-content .select-area-list .select-area-item,
html.dark .select-line-node-content .select-area-list .select-area-item .area-flag img,
html.dark .select-line-node-content .line-node-list-container .line-node-title {
  border-radius: 12px !important;
}

html.dark .select-line-node-content .area-list-wrap .area-list-item {
  border-radius: 999px !important;
}

/* --- Cards and tiles outside the main grid ------------------------------ */

html.dark .network-analyze .acc-info-wrap,
html.dark .network-log-wrap,
html.dark .status-logo,
html.dark .new-local-game-dialog .list .game_logo .logo,
html.dark .game-image-tools-item,
html.dark .link-btn {
  border-radius: 12px !important;
}

html.dark .profile-page .user-info {
  border-radius: 16px !important;
}

html.dark .game-image-tools-item.downloading::after,
html.dark .game-image-tools-item.starting::after {
  border-radius: 0 12px 12px 0 !important;
}

/* --- List rows, navigation pills outside the home nav -------------------- */

html.dark .sub-nav-wrap .sub-nav,
html.dark .user-center-layout .sidebar li:hover,
html.dark .user-center-layout .sidebar li.current,
html.dark .app-slider .user-info,
html.dark .app-slider .slider-game-skeleton,
html.dark .secondary-category-item,
html.dark .game-list-container .game-list-wrapper .game-list-item .game-item-palceholder {
  border-radius: 12px !important;
}

html.dark .app-slider .user-info .avator,
html.dark .secondary-category-item .secondary-category-icon {
  border-radius: 999px !important;
}

html.dark .secondary-category-item .dot {
  border-radius: 50% !important;
}

/* --- Small badges, tags, chips ------------------------------------------ */

html.dark .clean-result .clean-result-interval,
html.dark .tip-line,
html.dark .waring-box,
html.dark .ex-ip-pop-content .renew-btn,
html.dark .join-btn,
html.dark .room-input {
  border-radius: 999px !important;
}

/* The tuning-mode description is a multi-line card, not a chip. */
html.dark .system-tuning-container .system-tuning-status .mode-description {
  border-radius: 12px !important;
}

html.dark .udp-error-tip .close-button {
  border-radius: 999px !important;
}

/* --- Element Plus leftovers --------------------------------------------- */

html.dark .el-slider {
  --el-slider-border-radius: 999px;
}

html.dark .el-steps.el-steps--horizontal .el-step__line {
  border-radius: 999px !important;
}

html.dark .el-input .el-input-group__append,
html.dark .el-input .el-input-group__prepend {
  border-radius: 0 8px 8px 0 !important;
}

html.dark .el-input .el-input-group__prepend {
  border-radius: 8px 0 0 8px !important;
}

/* --- Last handful from the second sweep -------------------------------- */

html.dark .close-tip-modal-dialog {
  border-radius: 28px !important;
}

html.dark .simultaneouslyBox {
  border-radius: 16px !important;
}

html.dark .simultaneouslyBox .simultaneously-acc-pop .simultaneously-acc-item {
  border-radius: 12px !important;
}

html.dark .frame-boost-container .system-tuning-status .switch-wrapper .custome-tooltip {
  border-radius: 8px !important;
}

html.dark .service-window .service-window-header .service-window-header-buttons .icon-button {
  border-radius: 999px !important;
}

html.dark .profile-page .avatar-list img {
  border-radius: 50% !important;
}

html.dark .about-page .current-version .new-version {
  border-radius: 999px !important;
}

html.dark .tools-satisfaction-survey-modal-header .tools-satisfaction-survey-modal-header-subtitle {
  border-radius: 8px !important;
}
/* ==========================================================================
 * 17. Third pass (2026-11-12): hierarchy, semantic states and desktop rhythm
 *
 * Keep card dimensions and scroll geometry owned by the app. Surface, type and
 * selection distinguish navigation from content; rounding alone cannot do it.
 * No remote fonts, assets, JS or dependencies are needed by this theme.
 * ======================================================================== */

/* A quieter shell and a distinct navigation rail. */
html.dark .app-layout .app-layout-header,
html.dark .layout-header {
  background-color: var(--md3e-surface-container-low) !important;
}
html.dark .app-slider {
  background: var(--md3e-surface-container-low);
  border-radius: 0 24px 0 0;
}
html.dark .app-slider .game-item {
  border-radius: 16px !important;
  transition: background-color 150ms var(--md3e-ease-emphasized);
}
html.dark .app-slider .game-item:hover {
  background: var(--md3e-surface-container-high) !important;
}
html.dark .app-slider .game-item.active {
  background: var(--md3e-secondary-container) !important;
}
html.dark .app-slider .game-item.active .custom-content,
html.dark .app-slider .game-item.active .svg-icon {
  color: var(--md3e-on-secondary-container) !important;
}
html.dark .app-slider .game-item::before {
  opacity: 0 !important;
}
html.dark .app-slider .slider-wrapper .my-acc-title {
  color: var(--md3e-on-surface-variant);
  font-size: 12px;
  letter-spacing: .5px;
}

/* Connected navigation with a filled, clearly selected destination. The app
 * already scrolls this row horizontally when it cannot fit all categories. */
html.dark .home-page .home-nav-wrap .home-nav {
  gap: 4px !important;
  align-items: center;
}
html.dark .home-page .home-nav-wrap .home-nav .home-nav-item {
  height: 36px !important;
  padding: 0 12px;
  color: var(--md3e-on-surface-variant) !important;
}
html.dark .home-page .home-nav-wrap .home-nav .home-nav-item .nav-title {
  font-size: 14px !important;
  font-weight: 600;
}
html.dark .home-page .home-nav-wrap .home-nav .home-nav-item .nav-count {
  font-size: 12px !important;
  opacity: .8;
}
html.dark .home-page .home-nav-wrap .home-nav .home-nav-item:hover {
  background: var(--md3e-surface-container-high);
}
html.dark .home-page .home-nav-wrap .home-nav .home-nav-item.active {
  background: var(--md3e-secondary-container);
  color: var(--md3e-on-secondary-container) !important;
}
html.dark .home-page .home-nav-wrap .home-nav .home-nav-item.active::after {
  content: none !important;
}
html.dark .sub-nav-wrap .sub-nav.active,
html.dark .select-line-node-content .view-type-wrap .view-type-item.active,
html.dark .segmented .active {
  background: var(--md3e-secondary-container) !important;
  color: var(--md3e-on-secondary-container) !important;
  border-color: transparent !important;
}

/* A single search surface; the old inner .search-input was another dark box
 * inside the capsule. The original shine animation is purely decorative. */
html.dark .header-game-search,
html.dark .search-modal-container .search-modal-content .search-modal-title .header-game-search {
  background: var(--md3e-surface-container-high) !important;
  border-color: transparent !important;
}
html.dark .header-game-search .search-input {
  background: transparent !important;
  box-shadow: none !important;
  border-radius: inherit !important;
}
html.dark .header-game-search::before {
  animation: none !important;
  background-image: none !important;
  filter: none !important;
}
html.dark .header-game-search:focus-within {
  outline: 2px solid var(--md3e-primary);
  outline-offset: 2px;
}

/* Keep the virtualized 220 x 300 grid intact. A larger outer corner and a
 * smaller media corner give each card a container and a readable title. */
html.dark .game-item-wrap,
html.dark .game-download-item-wrap {
  border-radius: 24px !important;
  background: var(--md3e-surface-container-low) !important;
}
html.dark .game-item-wrap:hover,
html.dark .game-download-item-wrap:hover {
  background: var(--md3e-surface-container) !important;
  transform: none !important;
}
html.dark .game-item-wrap .game-info .game-title,
html.dark .game-download-item-wrap .game-info .game-title {
  color: var(--md3e-on-surface) !important;
  font-size: 16px !important;
  font-weight: 600;
}
html.dark .game-item-wrap .game-info .game-desc,
html.dark .game-download-item-wrap .game-info .game-desc {
  color: var(--md3e-on-surface-variant) !important;
  font-size: 13px !important;
}
html.dark .game-item-wrap .platform-icon-wrap {
  border-radius: 24px 0 12px 0 !important;
}

/* Roles belong to variants, not to :hover on every button. In particular a
 * stop/warning action must stay an error action, and disabled stays disabled. */
html.dark .leigod-button.primary {
  --ls-lei-button-bg-color: var(--md3e-primary);
  --ls-lei-button-font-color: var(--md3e-on-primary);
  --ls-lei-button-hover-bg-color: var(--md3e-primary);
  --ls-lei-button-hover-font-color: var(--md3e-on-primary);
}
html.dark .leigod-button.info {
  --ls-lei-button-bg-color: var(--md3e-secondary-container);
  --ls-lei-button-font-color: var(--md3e-on-secondary-container);
  --ls-lei-button-hover-bg-color: var(--md3e-secondary-container);
  --ls-lei-button-hover-font-color: var(--md3e-on-secondary-container);
}
html.dark .leigod-button.warning {
  --ls-lei-button-bg-color: var(--md3e-error-container);
  --ls-lei-button-font-color: var(--md3e-on-error-container);
  --ls-lei-button-hover-bg-color: var(--md3e-error-container);
  --ls-lei-button-hover-font-color: var(--md3e-on-error-container);
}
html.dark .leigod-button:not(.disabled):not(.checked):not(.static):not([disabled]):hover {
  background-color: var(--ls-lei-button-hover-bg-color, var(--ls-lei-button-bg-color)) !important;
  color: var(--ls-lei-button-hover-font-color, var(--ls-lei-button-font-color)) !important;
  box-shadow: inset 0 0 0 999px rgba(255, 255, 255, .08);
}
/* Outlined buttons keep their variant's border and text instead of filling. */
html.dark .leigod-button.line:not(.disabled):not(.checked):not(.static):not([disabled]):hover {
  background-color: var(--md3e-surface-container) !important;
  color: var(--ls-lei-button-bg-color, var(--md3e-primary)) !important;
}

/* Give the two detail actions different emphasis. Clip only the launch
 * button's own pieces so its square inner hover fills follow its capsule. */
html.dark .game-detail .game-info .acc-info-bottom-wrap {
  background: var(--md3e-surface-container-low) !important;
  border: 0 !important;
  border-radius: 28px !important;
}
html.dark .game-detail .game-info .game-acc-btn-wrap .launch-btn {
  border-radius: 999px !important;
  overflow: hidden;
  background: var(--md3e-secondary-container) !important;
  color: var(--md3e-on-secondary-container) !important;
}
html.dark .game-detail .game-info .game-acc-btn-wrap .launch-btn .btn,
html.dark .game-detail .game-info .game-acc-btn-wrap .launch-btn .setting-btn {
  border-radius: 0 !important;
}
html.dark .game-detail .game-info .game-acc-btn-wrap .launch-btn .setting-btn {
  border-left: 1px solid var(--md3e-outline);
}
html.dark .game-detail .game-info .game-acc-btn-wrap .leigod-button.warning {
  background-color: var(--md3e-error-container) !important;
  color: var(--md3e-on-error-container) !important;
}
html.dark .game-info .game-info-wrap .game-info-detail .game-title-wrap .game-name {
  font-weight: 650;
  letter-spacing: -.5px;
}

/* Sheets and menus share tonal surfaces. Never animate `transform` on a
 * Popper-controlled element: Popper uses it to position the overlay. */
html.dark .el-dialog {
  border-radius: 28px !important;
}
html.dark .el-popover,
html.dark .el-popper,
html.dark .leigod-modal,
html.dark .el-dialog {
  animation: md3e-fade-enter 150ms var(--md3e-ease-emphasized);
}
html.dark .node-drawer-overlay .node-drawer-content {
  background: var(--md3e-surface-container) !important;
  border-radius: 28px !important;
}
html.dark .user-center-layout .sidebar li.current {
  background: var(--md3e-secondary-container) !important;
}
html.dark .user-center-layout .sidebar li.current span,
html.dark .user-center-layout .sidebar li.current .user-menu-list-item-icon {
  color: var(--md3e-on-secondary-container) !important;
}
html.dark .leigod-switch {
  --ls-leigod-switch-active-background: var(--md3e-primary);
  --ls-leigod-switch-active-slider-color: var(--md3e-on-primary);
}

/* Visible keyboard focus without changing the app's tab order. */
html.dark .leigod-button:focus-visible,
html.dark .home-nav-item:focus-visible,
html.dark .game-item:focus-visible,
html.dark .game-item-wrap:focus-visible,
html.dark .icon-button:focus-visible,
html.dark .launch-btn .btn:focus-visible {
  outline: 2px solid var(--md3e-primary) !important;
  outline-offset: -3px;
}
@media (prefers-reduced-motion: reduce) {
  html.dark .leigod-button,
  html.dark .game-item-wrap,
  html.dark .game-item,
  html.dark .home-nav-item,
  html.dark .segmented div,
  html.dark .header-game-search,
  html.dark .leigod-switch::before {
    transition: none !important;
  }
}
html.dark .app-slider .game-item-wrapper.game.active {
  background: transparent !important;
}
'@

$script:IpcGuardTemplate = @'
const LG_AD_API=/(?:\/secapi\/tools\/(?:banner\/list|inner\/banner\/list|game\/popup\/carousel|notice\/popup|game\/toolbox)|\/webapi\/api\/(?:activity|invite)|\/window-advertise)/i,LG_AD_LINK=/(?:leigod\.com\/(?:activitys|activities_greatest|activity\/)|\/window-advertise|\/follow-reward)/i;const c=__REST__[0],a=__REST__.slice(1);try{const q=a[0]||{},u=typeof q=="string"?q:String(q.url||q.URL||q.href||"");if(c==="http-request"&&LG_AD_API.test(u))return Promise.resolve({code:0,data:[],msg:""});if(c==="notification-show"&&(a[0]==="ad-link"||a[0]==="tool-ad"))return Promise.resolve();if(c==="auto-run-game-tools"||c==="get-game-tools")return Promise.resolve([]);if(c==="client-tool-init"||c==="client-tool-download")return Promise.resolve({code:0,data:null});if(c==="open-external"||c==="create-window"){const v=a[0],z=typeof v=="string"?v:String(v&&(v.url||v.URL||v.href)||"");if(LG_AD_LINK.test(z))return Promise.resolve()}}catch(e){}return window.leigodSimplify.invoke(...__REST__.map(__MAP__))
'@

# ===========================================================================
# 通用工具
# ===========================================================================

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    if ($script:LogPath) {
        try { Add-Content -LiteralPath $script:LogPath -Value $Message -Encoding UTF8 } catch { }
    }
}

function Write-Step {
    param([string]$Message)
    Write-Log ''
    Write-Log ('==> ' + $Message) 'Cyan'
}

function Write-WarnLine {
    param([string]$Message)
    Write-Log ('[提示] ' + $Message) 'Yellow'
}

function Write-Ok {
    param([string]$Message)
    Write-Log ('[完成] ' + $Message) 'Green'
}

function Write-ErrLine {
    param([string]$Message)
    Write-Log ('[错误] ' + $Message) 'Red'
}

function Format-Size {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Read-Utf8 {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Convert-ToLf {
    param([string]$Text)
    $t = $Text -replace "`r`n", "`n"
    if (-not $t.EndsWith("`n")) { $t += "`n" }
    return $t
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-HostsPath {
    if ($HostsFile) { return $HostsFile }
    return (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts')
}

function Invoke-PauseIfNeeded {
    if ($script:ElevationStarted) { return }
    Write-Host ''
    if ($script:BackupPath) {
        Write-Host ('备份文件位置：' + $script:BackupPath) -ForegroundColor Yellow
        if ($Restore) {
            Write-Host '已使用上述备份执行还原。请启动雷神检查结果。' -ForegroundColor Yellow
        } elseif (Test-Path -LiteralPath (Join-Path $script:BackupPath 'restore.cmd')) {
            Write-Host '恢复方法：先完全退出雷神，再打开上述目录，双击 restore.cmd，允许管理员权限。' -ForegroundColor Yellow
            Write-Host '若有多次备份，请从最新一次开始依次还原。' -ForegroundColor Yellow
        } else {
            Write-Host '本次未完成，尚未生成一键还原入口；请保留备份和日志。' -ForegroundColor Yellow
            Write-Host '可先退出雷神，将备份中的 renderer.asar.original（或 renderer.asar.as-found）复制回安装目录 resources\renderer.asar。' -ForegroundColor Yellow
        }
    } elseif ($DryRun) {
        Write-Host '本次仅演练，没有修改安装，也没有生成备份。'
    } else {
        Write-Host '本次尚未生成备份。'
    }
    if (-not $NoPause) {
        Write-Host ''
        Write-Host '按任意键退出...'
        try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
        catch { Read-Host '当前终端不支持单键读取，请按回车键退出' | Out-Null }
    }
}

# ===========================================================================
# JavaScript 补丁引擎（按代码结构匹配，不依赖压缩后的变量名）
# ===========================================================================

function Skip-JsString {
    param([string]$s, [int]$i)
    $q = $s[$i]
    $i++
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq [char]92) { $i += 2; continue }
        if ($c -eq $q) { return $i + 1 }
        $i++
    }
    throw '遇到未闭合的字符串'
}

function Skip-JsTemplate {
    param([string]$s, [int]$i)
    $i++
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq [char]92) { $i += 2; continue }
        if ($c -eq [char]96) { return $i + 1 }
        if ($c -eq [char]36 -and ($i + 1) -lt $s.Length -and $s[$i + 1] -eq [char]123) {
            $depth = 1
            $i += 2
            while ($i -lt $s.Length -and $depth -gt 0) {
                $d = $s[$i]
                if ($d -eq [char]34 -or $d -eq [char]39) { $i = Skip-JsString $s $i; continue }
                if ($d -eq [char]96) { $i = Skip-JsTemplate $s $i; continue }
                if ($d -eq [char]123) { $depth++ }
                elseif ($d -eq [char]125) { $depth-- }
                $i++
            }
            continue
        }
        $i++
    }
    throw '遇到未闭合的模板字符串'
}

function Find-MatchingChar {
    param([string]$s, [int]$OpenIndex, [char]$OpenChar, [char]$CloseChar)
    $depth = 0
    $i = $OpenIndex
    $n = $s.Length
    while ($i -lt $n) {
        $c = $s[$i]
        if ($c -eq [char]34 -or $c -eq [char]39) { $i = Skip-JsString $s $i; continue }
        if ($c -eq [char]96) { $i = Skip-JsTemplate $s $i; continue }
        if ($c -eq [char]47 -and ($i + 1) -lt $n -and $s[$i + 1] -eq [char]47) {
            $nl = $s.IndexOf([string][char]10, $i + 2)
            if ($nl -lt 0) { return -1 }
            $i = $nl + 1
            continue
        }
        if ($c -eq [char]47 -and ($i + 1) -lt $n -and $s[$i + 1] -eq [char]42) {
            $end = $s.IndexOf('*/', $i + 2)
            if ($end -lt 0) { return -1 }
            $i = $end + 2
            continue
        }
        if ($c -eq $OpenChar) { $depth++ }
        elseif ($c -eq $CloseChar) {
            $depth--
            if ($depth -eq 0) { return $i }
        }
        $i++
    }
    return -1
}

function Invoke-ReplaceOnce {
    param([string]$s, [string]$From, [string]$To, [string]$Label)
    $i = $s.IndexOf($From)
    if ($i -lt 0) { throw ('找不到标记：' + $Label) }
    if ($s.IndexOf($From, $i + 1) -ge 0) { throw ('标记不唯一：' + $Label) }
    return $s.Substring(0, $i) + $To + $s.Substring($i + $From.Length)
}

function Invoke-RegexOnce {
    param([string]$s, [string]$Pattern, [scriptblock]$Builder, [string]$Label)
    $re = New-Object System.Text.RegularExpressions.Regex($Pattern)
    $m = $re.Match($s)
    if (-not $m.Success) { throw ('找不到模式：' + $Label) }
    if ($m.NextMatch().Success) { throw ('模式不唯一：' + $Label) }
    $repl = & $Builder $m
    return $s.Substring(0, $m.Index) + $repl + $s.Substring($m.Index + $m.Length)
}

function Get-ComponentBounds {
    param([string]$s, [string]$Name)
    $start = $s.IndexOf('name:"' + $Name + '"')
    if ($start -lt 0) { throw ('找不到组件：' + $Name) }
    $end = $s.IndexOf('__scopeId', $start)
    if ($end -lt 0) { throw ('找不到组件结尾：' + $Name) }
    return @{ Start = $start; End = $end }
}

function Get-EmptyNodeHelper {
    param([string]$s, [string]$Name)
    $b = Get-ComponentBounds $s $Name
    $comp = $s.Substring($b.Start, $b.End - $b.Start)
    $m = [regex]::Match($comp, '([A-Za-z_$][\w$]*)\(\"\",!0\)')
    if (-not $m.Success) { throw ('无法识别空节点辅助函数（X("",!0)）：' + $Name) }
    return $m.Groups[1].Value
}

function Find-DivVnodeCall {
    param([string]$s, [string]$VarName, [string]$Label)
    $re = New-Object System.Text.RegularExpressions.Regex('[A-Za-z_$][\w$]*\("div",' + [regex]::Escape($VarName) + ',\[')
    $calls = $re.Matches($s)
    if ($calls.Count -lt 1) { throw ('找不到节点：' + $Label) }
    if ($calls.Count -gt 1) { throw ('节点不唯一：' + $Label) }
    return $calls[0]
}

function Patch-GameDetailSidebar {
    param([string]$s)
    $log = New-Object System.Collections.ArrayList

    $b = Get-ComponentBounds $s 'gameDetail'
    $comp = $s.Substring($b.Start, $b.End - $b.Start)
    $m = [regex]::Match($comp, '=([A-Za-z_$][\w$]*)\(null\)')
    if (-not $m.Success) { throw '无法识别 ref 辅助函数（=X(null)），雷神版本可能变了' }
    $refFn = $m.Groups[1].Value
    $m = [regex]::Match($comp, '([A-Za-z_$][\w$]*)\(\"\",!0\)')
    if (-not $m.Success) { throw '无法识别空节点辅助函数（X("",!0)），雷神版本可能变了' }
    $emptyNode = $m.Groups[1].Value
    $log.Add('识别到 ref 辅助函数 ' + $refFn + '，空节点辅助函数 ' + $emptyNode) | Out-Null

    $m = [regex]::Match($s, '([A-Za-z_$][\w$]*)=\{class:[^{}]{0,80}"game-detail-tools"')
    if (-not $m.Success) { throw '找不到 game-detail-tools 的 class 绑定' }
    $panelVar = $m.Groups[1].Value
    $call = Find-DivVnodeCall $s $panelVar 'game-detail-tools vnode'
    $open = $call.Index + $call.Value.IndexOf([char]40)
    $close = Find-MatchingChar $s $open ([char]40) ([char]41)
    if ($close -lt 0) { throw '找不到社区侧栏节点的结尾' }
    $len = $close + 1 - $call.Index
    $s = $s.Substring(0, $call.Index) + $emptyNode + '("",!0)' + $s.Substring($close + 1)
    $log.Add('移除 .game-detail-tools 节点（' + $len + ' 字节）') | Out-Null

    $s = Invoke-RegexOnce $s 'const\{inlineInfo:([\w$]+),activeTab:([\w$]+),setActiveTab:([\w$]+)\}=([\w$]+)\(\(\)=>t\.gameId\)' {
        param($mm)
        'const ' + $mm.Groups[1].Value + '=' + $refFn + '(null),' + $mm.Groups[2].Value + '=' + $refFn + '("tool"),' + $mm.Groups[3].Value + '=()=>{}'
    } '停止社区轮询'
    $log.Add('停止社区 inline-info 轮询') | Out-Null

    $s = Invoke-RegexOnce $s 'const\{toolsPlace:([\w$]+),servicePlace:([\w$]+)\}=([\w$]+)\(\(\)=>t\.gameId\)' {
        param($mm)
        'const ' + $mm.Groups[1].Value + '=' + $refFn + '([]),' + $mm.Groups[2].Value + '=' + $refFn + '([])'
    } '停止工具列表请求'
    $log.Add('停止游戏工具列表请求') | Out-Null

    $s = Invoke-RegexOnce $s '\{advertises:([\w$]+)\}=([\w$]+)\(\["tool_list_shown","client_tool_notice_ad"\]\)' {
        param($mm)
        $mm.Groups[1].Value + '={}'
    } '停止工具广告配置'
    $log.Add('停止工具广告位配置请求') | Out-Null

    $re = New-Object System.Text.RegularExpressions.Regex('\(async\(\)=>\{const [\w$]+=await [\w$]+\(\)\.load\(\["tools_title_txt"')
    $m = $re.Match($s)
    if (-not $m.Success) { throw '找不到侧栏设置 IIFE' }
    if ($m.NextMatch().Success) { throw '侧栏设置 IIFE 不唯一' }
    $open = $s.IndexOf([char]123, $m.Index)
    $close = Find-MatchingChar $s $open ([char]123) ([char]125)
    if ($close -lt 0) { throw '找不到侧栏设置 IIFE 的结尾' }
    if ($s.Substring($close + 1, 4) -ne ')();') { throw '侧栏设置 IIFE 结尾异常' }
    $s = $s.Substring(0, $m.Index) + 'void 0;' + $s.Substring($close + 5)
    $log.Add('移除侧栏设置加载') | Out-Null

    $re = New-Object System.Text.RegularExpressions.Regex('const ([\w$]+)=async\(\)=>\{if\(await [\w$]+\(300\),![\w$]+\.value\)return;')
    $m = $re.Match($s)
    if (-not $m.Success) { throw '找不到工具满意度处理函数' }
    if ($m.NextMatch().Success) { throw '工具满意度处理函数不唯一' }
    $open = $s.IndexOf([char]123, $m.Index)
    $close = Find-MatchingChar $s $open ([char]123) ([char]125)
    if ($close -lt 0) { throw '找不到工具满意度处理函数的结尾' }
    $s = $s.Substring(0, $m.Index) + 'const ' + $m.Groups[1].Value + '=async()=>{}' + $s.Substring($close + 1)
    $log.Add('禁用工具满意度点击处理') | Out-Null

    return @{ Text = $s; Log = $log }
}

function Patch-GameDetailBottomBanner {
    param([string]$s)
    $log = New-Object System.Collections.ArrayList
    $emptyNode = Get-EmptyNodeHelper $s 'gameDetail'

    $m = [regex]::Match($s, '([A-Za-z_$][\w$]*)=\{class:"game-detail-banner')
    if (-not $m.Success) { throw '找不到 game-detail-banner 的 class 绑定' }
    $bannerVar = $m.Groups[1].Value
    $call = Find-DivVnodeCall $s $bannerVar 'game-detail-banner vnode'
    $open = $call.Index + $call.Value.IndexOf([char]40)
    $close = Find-MatchingChar $s $open ([char]40) ([char]41)
    if ($close -lt 0) { throw '找不到底部推广条节点的结尾' }
    $len = $close + 1 - $call.Index
    $s = $s.Substring(0, $call.Index) + $emptyNode + '("",!0)' + $s.Substring($close + 1)
    $log.Add('移除 .game-detail-banner 节点（' + $len + ' 字节）') | Out-Null

    $s = Invoke-RegexOnce $s '\{advertises:([\w$]+)\}=([\w$]+)\(\["pc11_home_banner_v4_new"\],\{cache:!1,cacheLast:!0\}\)' {
        param($mm)
        $mm.Groups[1].Value + '={}'
    } '停止 pc11_home_banner 广告配置'
    $log.Add('停止底部推广条广告配置请求') | Out-Null

    $s = Invoke-ReplaceOnce $s '[`game_bottom_banner_11_v4_new_${t.gameId}`]:[],' '' '从广告结果里移除 game_bottom_banner'
    $s = Invoke-ReplaceOnce $s '"game_bottom_banner_11_v4_new",' '' '从广告组列表里移除 game_bottom_banner'
    $log.Add('从广告请求里移除 game_bottom_banner 广告组') | Out-Null

    return @{ Text = $s; Log = $log }
}

function Patch-GameDetailStopButton {
    param([string]$s)
    $log = New-Object System.Collections.ArrayList

    $b = Get-ComponentBounds $s 'GameInfo'
    $gi = $s.Substring($b.Start, $b.End - $b.Start)

    # 幂等：已经改过就跳过
    if ($gi.IndexOf('reason:"timePause"') -ge 0) {
        $log.Add('详情页“停止加速”按钮已经是暂停逻辑，跳过') | Out-Null
        return @{ Text = $s; Log = $log }
    }

    # props 别名：setup(r){const t=r, ... }
    $m = [regex]::Match($gi, 'setup\(([A-Za-z_$][\w$]*)\)\{const ([A-Za-z_$][\w$]*)=\1[,;]')
    if (-not $m.Success) { throw '无法识别 GameInfo 的 props 别名，雷神版本可能变了' }
    $propVar = $m.Groups[2].Value
    if (-not [regex]::IsMatch($gi, [regex]::Escape($propVar) + '\.gameId')) {
        throw 'GameInfo 的 props 别名上找不到 gameId'
    }

    # 用户 store（时长）别名：用 userInfo?.nn_number，且在 GameInfo 里声明为 X()
    $userVar = @()
    foreach ($mm in [regex]::Matches($gi, '([A-Za-z_$][\w$]*)\.userInfo\?\.nn_number')) {
        $name = $mm.Groups[1].Value
        if (([regex]::IsMatch($gi, '[^\w$.]' + [regex]::Escape($name) + '\s*=\s*[A-Za-z_$][\w$]*\(\)')) -and ($userVar -notcontains $name)) {
            $userVar += $name
        }
    }
    if ($userVar.Count -ne 1) { throw ('无法唯一识别 GameInfo 里的用户 store 别名：' + ($userVar -join ',')) }

    # 加速 store 别名：用 stopAcc(，且在 GameInfo 里声明为 X()
    $accVar = @()
    foreach ($mm in [regex]::Matches($gi, '([A-Za-z_$][\w$]*)\.stopAcc\(')) {
        $name = $mm.Groups[1].Value
        if (([regex]::IsMatch($gi, '[^\w$.]' + [regex]::Escape($name) + '\s*=\s*[A-Za-z_$][\w$]*\(\)')) -and ($accVar -notcontains $name)) {
            $accVar += $name
        }
    }
    if ($accVar.Count -ne 1) { throw ('无法唯一识别 GameInfo 里的加速 store 别名：' + ($accVar -join ',')) }

    $log.Add('识别到 props 别名 ' + $propVar + '，用户 store ' + $userVar[0] + '，加速 store ' + $accVar[0]) | Out-Null

    # 点击处理函数：pe=()=>{ s.stopAcc({game_id:t.gameId,reason:"detail"}) },
    $pat = '\},([A-Za-z_$][\w$]*)=\(\)=>\{' + [regex]::Escape($accVar[0]) +
           '\.stopAcc\(\{game_id:' + [regex]::Escape($propVar) + '\.gameId,reason:"detail"\}\)\},'
    $re = New-Object System.Text.RegularExpressions.Regex($pat)
    $m = $re.Match($s)
    if (-not $m.Success) { throw '找不到详情页停止加速按钮的处理函数（标记 reason:"detail"）' }
    if ($m.NextMatch().Success) { throw '详情页停止加速按钮的处理函数不唯一' }
    $fn = $m.Groups[1].Value

    # 改写：点“停止加速”改为暂停时长。
    #  - 已经暂停 / 没有可暂停时长 -> 保持原来的 stopAcc
    #  - 否则 -> toggleTimeStatus("pause",{scene:"close_tip_type2"})，
    #    并补一次 stopAcc 停掉隧道。
    #  scene 用 "close_tip_type2" 而不是 "top_nav"：后者会弹确认框，并让右上角
    #  TimeLong 在请求期间弹出“剩余时长”面板；close_tip_type2 是 store 自己的
    #  “程序化暂停”场景，直接暂停、不弹窗。
    $code = '},' + $fn + '=async()=>{const __gcUser=' + $userVar[0] + ',__gcAcc=' + $accVar[0] +
            ',__gcGame=' + $propVar + '.gameId;' +
            'try{const __gcT=__gcUser.userTimeInfo;' +
            'if(!__gcT||__gcT.timeStatus==="pause"||!(__gcT.canPauseTimeLeft>0)||__gcT.notCanPauseTimeLeft>0){' +
            '__gcAcc.stopAcc({game_id:__gcGame,reason:"detail"});return}' +
            'const __gcPause=__gcUser.toggleTimeStatus("pause",{scene:"close_tip_type2"});' +
            '__gcAcc.stopAcc({isConfirm:!1,reason:"timePause"});' +
            'return __gcPause' +
            '}catch(__gcErr){console.error("pause by stop button failed",__gcErr);' +
            '__gcAcc.stopAcc({game_id:__gcGame,reason:"detail"})}},'
    $s = $s.Substring(0, $m.Index) + $code + $s.Substring($m.Index + $m.Length)
    $log.Add('改写 ' + $fn + '()：点“停止加速”改为暂停时长（scene=close_tip_type2，无确认框、不弹时长面板）；无法暂停时回退为原来的停止加速') | Out-Null

    return @{ Text = $s; Log = $log }
}

function Patch-HomeBanner {
    param([string]$s)
    $log = New-Object System.Collections.ArrayList

    $b = Get-ComponentBounds $s 'NavContentLayout'
    $empty = Get-EmptyNodeHelper $s 'NavContentLayout'
    $nav = $s.Substring($b.Start, $b.End - $b.Start)

    $re = New-Object System.Text.RegularExpressions.Regex('([A-Za-z_$][\w$]*)\.value\?\(c\(\),N\([A-Za-z_$][\w$]*,\{key:0,class:"banner-wrap"\}\)\):\(c\(\),N\(')
    $m = $re.Match($nav)
    if (-not $m.Success) { throw '找不到游戏列表大横幅的三元表达式' }
    if ($m.NextMatch().Success) { throw '游戏列表大横幅的三元表达式不唯一' }

    $abs = $b.Start + $m.Index
    $secondRel = $m.Index + $m.Value.LastIndexOf('(c(),N(')
    $open = $b.Start + $secondRel
    $close = Find-MatchingChar $s $open ([char]40) ([char]41)
    if ($close -lt 0) { throw '找不到游戏列表大横幅节点的结尾' }
    $cutEnd = $close + 1
    if ($s[$cutEnd] -ne [char]44) { throw '游戏列表大横幅节点后面不是逗号' }
    $len = $cutEnd - $abs
    $s = $s.Substring(0, $abs) + $empty + '("",!0)' + $s.Substring($cutEnd)
    $log.Add('移除 NavContentLayout 的 .banner-wrap（' + $len + ' 字节）') | Out-Null

    $s = Invoke-ReplaceOnce $s '["pc11_home_banner_v4_new","pc11_home_advertise_v11_5_new","pc11_game_list_banner_v11_4_new"]' '["pc11_home_advertise_v11_5_new"]' '移除列表页横幅广告组'
    $log.Add('列表页不再请求首页/列表横幅广告组') | Out-Null

    $b = Get-ComponentBounds $s 'NavAccRencent'
    $empty = Get-EmptyNodeHelper $s 'NavAccRencent'

    $decl = [regex]::Match($s, '([A-Za-z_$][\w$]*)=\{class:"bottom-banner-wrap"\}')
    if (-not $decl.Success) { throw '找不到 bottom-banner-wrap 的 class 绑定' }
    $varName = $decl.Groups[1].Value
    $call = Find-DivVnodeCall $s $varName 'home bottom-banner vnode'
    $open = $call.Index + $call.Value.IndexOf([char]40)
    $close = Find-MatchingChar $s $open ([char]40) ([char]41)
    if ($close -lt 0) { throw '找不到游戏首页横幅节点的结尾' }
    $len = $close + 1 - $call.Index
    $s = $s.Substring(0, $call.Index) + $empty + '("",!0)' + $s.Substring($close + 1)
    $log.Add('移除 NavAccRencent 的横幅节点（' + $len + ' 字节）') | Out-Null

    $s = Invoke-ReplaceOnce $s '{class:"list-wrap",onTransitionend:' '{class:"list-wrap",style:{transform:"none"},onTransitionend:' '让游戏列表贴顶'
    $log.Add('给首页列表加上 transform:none，抵消 --banner-height 位移') | Out-Null

    $s = Invoke-ReplaceOnce $s '["pc11_home_banner_v4_new","pc11_home_advertise_v11_5_new"]' '["pc11_home_advertise_v11_5_new"]' '移除游戏首页横幅广告组'
    $log.Add('游戏首页不再请求 pc11_home_banner 广告组') | Out-Null

    # 网格内插卡广告（pc11_home_advertise_v11_5_new）：全部游戏页把它 splice 进列表
    # （220x300 卡，关掉后下面的游戏补位），游戏首页渲染 199x360 卡并把游戏项隐藏。
    # IPC 层虽然已经拦了 banner 请求，但 cacheLast 会留下旧数据，所以这里把派生值钉成空数组。
    $s = Invoke-ReplaceOnce $s 'h=C(()=>u.pc11_home_advertise_v11_5_new)' 'h=C(()=>[])' '停用游戏首页网格内广告卡'
    $log.Add('游戏首页不再渲染网格内插卡广告（acc_advertise）') | Out-Null
    $s = Invoke-ReplaceOnce $s 'f=C(()=>u.pc11_home_advertise_v11_5_new||[])' 'f=C(()=>[])' '停用全部游戏页网格内广告卡'
    $log.Add('全部游戏页不再把广告卡 splice 进游戏列表') | Out-Null

    return @{ Text = $s; Log = $log }
}

function Patch-HeaderAds {
    param([string]$s)
    $log = New-Object System.Collections.ArrayList

    $s = Invoke-ReplaceOnce $s '"leigod_header_slogn",' '' '移除顶栏口号广告组'
    $log.Add('顶栏不再请求 leigod_header_slogn 广告组') | Out-Null

    $s = Invoke-RegexOnce $s ',[A-Za-z_$][\w$]*\([A-Za-z_$][\w$]*,\{ads:[A-Za-z_$][\w$]*\.value,class:"header-ad-carousel flex-1",clickable:"","hover-color-change":"",onClick:[A-Za-z_$][\w$]*\},null,8,\["ads"\]\)' {
        param($mm)
        ''
    } '移除顶栏口号轮播节点'
    $log.Add('移除顶栏口号轮播（HeaderLogoAdCarousel）') | Out-Null

    $re = New-Object System.Text.RegularExpressions.Regex('class:ie\(\["header-logo",\{"telecom-logo":([A-Za-z_$][\w$]*)\.value,"flex flex-aic dual-logo-layout":!([A-Za-z_$][\w$]*)\.value&&!([A-Za-z_$][\w$]*)\.value\}\]\)')
    $m = $re.Match($s)
    if (-not $m.Success) { throw '找不到顶栏 logo 的 class 绑定' }
    if ($m.NextMatch().Success) { throw '顶栏 logo 的 class 绑定不唯一' }
    $replacement = $m.Value + ',style:!' + $m.Groups[2].Value + '.value&&!' + $m.Groups[3].Value + '.value?{width:"auto"}:null'
    $s = $s.Substring(0, $m.Index) + $replacement + $s.Substring($m.Index + $m.Length)
    $log.Add('顶栏 logo 宽度改为 auto（不再给口号留位置）') | Out-Null

    $s = Invoke-RegexOnce $s '([A-Za-z_$][\w$]*)\(([A-Za-z_$][\w$]*),\{size:5,useRecommend:!0(,query:\{is_download_game:"0"\}\})\)' {
        param($mm)
        $mm.Groups[1].Value + '(' + $mm.Groups[2].Value + ',{size:5,useRecommend:!1' + $mm.Groups[3].Value + ')'
    } '停止搜索框推荐列表请求'
    $log.Add('搜索框不再请求热门游戏推荐列表') | Out-Null

    $b = Get-ComponentBounds $s 'HeaderGameSearch'
    $local = $s.Substring($b.Start, $b.End - $b.Start)
    $re = New-Object System.Text.RegularExpressions.Regex('([A-Za-z_$][\w$]*)\.value\?[A-Za-z_$][\w$]*\("",!0\):\(C\(\),Te\(')
    $m = $re.Match($local)
    if (-not $m.Success) { throw '找不到搜索框游戏名轮播' }
    if ($m.NextMatch().Success) { throw '搜索框游戏名轮播不唯一' }

    $abs = $b.Start + $m.Index
    $secondRel = $m.Index + $m.Value.LastIndexOf('(C(),Te(')
    $open = $b.Start + $secondRel
    $close = Find-MatchingChar $s $open ([char]40) ([char]41)
    if ($close -lt 0) { throw '找不到搜索框轮播节点的结尾' }
    if ($s[$close + 1] -ne [char]44) { throw '搜索框轮播节点后面不是逗号' }
    $len = $close + 2 - $abs
    $s = $s.Substring(0, $abs) + $s.Substring($close + 2)
    $log.Add('移除搜索框游戏名轮播（' + $len + ' 字节）') | Out-Null

    $s = Invoke-RegexOnce $s '([A-Za-z_$][\w$]*)\.value\|\|([A-Za-z_$][\w$]*)\.value\?Lt\(' {
        param($mm)
        '!0?Lt('
    } '让搜索输入框常驻'
    $log.Add('搜索输入框改为常驻显示') | Out-Null

    $s = Invoke-RegexOnce $s 'placeholder:([A-Za-z_$][\w$]*)\.value,onFocus:' {
        param($mm)
        'placeholder:"搜索游戏",onFocus:'
    } '固定搜索占位文字'
    $log.Add('搜索占位文字固定为“搜索游戏”') | Out-Null

    $s = Invoke-RegexOnce $s 'async function ([A-Za-z_$][\w$]*)\(\)\{([A-Za-z_$][\w$]*)\.value=([A-Za-z_$][\w$]*)\.value\[([A-Za-z_$][\w$]*)\.value\]\.title,[A-Za-z_$][\w$]*\.value=!1,await [A-Za-z_$][\w$]*\(\),setTimeout\(\(\)=>\{\2\.value="",[A-Za-z_$][\w$]*\.value=""\},300\)\}' {
        param($mm)
        'async function ' + $mm.Groups[1].Value + '(){}'
    } '禁用依赖轮播项的搜索处理函数'
    $log.Add('禁用依赖轮播项的搜索点击处理') | Out-Null

    return @{ Text = $s; Log = $log }
}

function Patch-IpcAdGuard {
    param([string]$s)
    $pattern = '([A-Za-z_$][\w$]*)=\(\.\.\.([A-Za-z_$][\w$]*)\)=>window\.leigodSimplify\.invoke\(\.\.\.\2\.map\(([A-Za-z_$][\w$]*)\)\)'
    $bodyTemplate = $script:IpcGuardTemplate
    $patched = Invoke-RegexOnce $s $pattern {
        param($mm)
        $var = $mm.Groups[1].Value
        $rest = $mm.Groups[2].Value
        $mapFn = $mm.Groups[3].Value
        $body = $bodyTemplate.Replace('__REST__', $rest).Replace('__MAP__', $mapFn)
        $var + '=(...' + $rest + ')=>{' + $body + '}'
    } 'IPC invoke 包装'
    return $patched
}

# ===========================================================================
# ASAR 读写
# ===========================================================================

function Get-AsarInfo {
    param([string]$Path)
    $fileLength = (Get-Item -LiteralPath $Path).Length
    $headLen = [int][Math]::Min(4096, $fileLength)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $head = New-Object byte[] $headLen
        $read = 0
        while ($read -lt $headLen) {
            $n = $fs.Read($head, $read, $headLen - $read)
            if ($n -le 0) { break }
            $read += $n
        }
        if ($read -lt 8) { throw ('asar 文件太小：' + $fileLength + ' 字节') }

        # asar 的头部是“ pickle + JSON 头”。不同打包器/版本前导整数个数可能不同，
        # 这里不写死 16 字节，而是找 JSON 的起点，再用它前面 4 字节的长度校验。
        $jsonOffsets = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $read; $i++) {
            if ($head[$i] -eq 123) { $jsonOffsets.Add($i) | Out-Null }
        }
        foreach ($jsonOffset in $jsonOffsets) {
            if ($jsonOffset -lt 4) { continue }
            $jsonLen = [BitConverter]::ToUInt32($head, $jsonOffset - 4)
            if ($jsonLen -le 2) { continue }
            if ($jsonLen -gt 33554432) { continue }
            if (([int64]$jsonOffset + [int64]$jsonLen) -gt $fileLength) { continue }
            $jsonBytes = New-Object byte[] $jsonLen
            $fs.Position = $jsonOffset
            $readJson = 0
            while ($readJson -lt $jsonLen) {
                $n = $fs.Read($jsonBytes, $readJson, $jsonLen - $readJson)
                if ($n -le 0) { break }
                $readJson += $n
            }
            if ($readJson -ne $jsonLen) { continue }
            $json = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
            $json = $json.TrimStart([char[]]@([char]0xFEFF, ' ', "`r", "`n", "`t"))
            if (-not $json.StartsWith('{')) { continue }
            $header = $null
            try { $header = $json | ConvertFrom-Json } catch { continue }
            if (-not $header -or -not ($header.PSObject.Properties.Name -contains 'files')) { continue }
            return @{
                Path = $Path
                DataStart = [int64]($jsonOffset + (([int64]$jsonLen + 3) -band (-4)))
                Json = $json
                JsonOffset = $jsonOffset
                JsonLen = $jsonLen
                Header = $header
            }
        }
    } finally {
        $fs.Close()
    }
    $previewLen = [int][Math]::Min(64, $read)
    $preview = New-Object byte[] $previewLen
    [Array]::Copy($head, 0, $preview, 0, $previewLen)
    $hex = (($preview | ForEach-Object { $_.ToString('x2') }) -join ' ')
    $ascii = ([System.Text.Encoding]::ASCII.GetString($preview) -replace '[^\x20-\x7E]', '.')
    throw ('不是可识别的 asar 文件（大小 ' + $fileLength + ' 字节；前 ' + $previewLen + ' 字节：' + $hex + '；ASCII：' + $ascii + '）')
}

function Get-AsarLeafPaths {
    param($Node, [string]$Prefix)
    $result = New-Object System.Collections.ArrayList
    foreach ($p in $Node.files.PSObject.Properties) {
        $child = $p.Value
        $rel = if ($Prefix) { $Prefix + '/' + $p.Name } else { $p.Name }
        if ($child.PSObject.Properties.Name -contains 'files') {
            foreach ($x in (Get-AsarLeafPaths -Node $child -Prefix $rel)) {
                $result.Add($x) | Out-Null
            }
        } else {
            $result.Add($rel) | Out-Null
        }
    }
    return $result.ToArray()
}

function Expand-AsarNode {
    param($Node, [string]$Prefix, [byte[]]$Bytes, [int64]$DataStart, [string]$OutDir)
    foreach ($p in $Node.files.PSObject.Properties) {
        $entry = $p.Value
        $rel = if ($Prefix) { $Prefix + '/' + $p.Name } else { $p.Name }
        if ($entry.PSObject.Properties.Name -contains 'files') {
            Expand-AsarNode -Node $entry -Prefix $rel -Bytes $Bytes -DataStart $DataStart -OutDir $OutDir
            continue
        }
        if ($entry.PSObject.Properties.Name -contains 'unpacked' -and $entry.unpacked) {
            throw ('renderer.asar 含 unpacked 条目，本脚本暂不支持：' + $rel)
        }
        if ($entry.PSObject.Properties.Name -contains 'link') {
            throw ('renderer.asar 含 link 条目，本脚本暂不支持：' + $rel)
        }
        $target = Join-Path $OutDir ($rel -replace '/', '\')
        $dir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $size = [int64]$entry.size
        $offset = [int64]$entry.offset
        if ($size -lt 0 -or $offset -lt 0 -or ($DataStart + $offset + $size) -gt $Bytes.Length) {
            throw ('asar 条目越界，头部布局可能不兼容：' + $rel + '（offset ' + $offset + '，size ' + $size + '）')
        }
        $buf = New-Object byte[] $size
        if ($size -gt 0) {
            [Array]::Copy($Bytes, [int64]($DataStart + $offset), $buf, [int64]0, $size)
        }
        [System.IO.File]::WriteAllBytes($target, $buf)
    }
}

function Expand-Asar {
    param([string]$AsarPath, [string]$OutDir)
    $info = Get-AsarInfo $AsarPath
    $bytes = [System.IO.File]::ReadAllBytes($AsarPath)
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Expand-AsarNode -Node $info.Header -Prefix '' -Bytes $bytes -DataStart $info.DataStart -OutDir $OutDir
}

function Get-FileIntegrity {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $blockSize = 4194304
        $blocks = New-Object System.Collections.ArrayList
        $offset = 0
        if ($Bytes.Length -eq 0) {
            $blocks.Add((([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant())) | Out-Null
        } else {
            while ($offset -lt $Bytes.Length) {
                $count = [Math]::Min($blockSize, $Bytes.Length - $offset)
                $h = $sha.ComputeHash($Bytes, $offset, $count)
                $blocks.Add((([BitConverter]::ToString($h) -replace '-', '').ToLowerInvariant())) | Out-Null
                $offset += $count
            }
        }
        $all = ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
        return [ordered]@{
            algorithm = 'SHA256'
            hash = $all
            blockSize = $blockSize
            blocks = @($blocks)
        }
    } finally {
        $sha.Dispose()
    }
}

function Add-AsarTreeFile {
    param($TreeRoot, [string]$RelPath, [int64]$Size, [int64]$Offset, $Integrity)
    $parts = $RelPath.Split('/')
    $node = $TreeRoot
    $last = $parts.Length - 1
    for ($i = 0; $i -lt $last; $i++) {
        $name = $parts[$i]
        if (-not $node.files.Contains($name)) {
            $node.files[$name] = [ordered]@{ files = [ordered]@{} }
        }
        $node = $node.files[$name]
    }
    $leaf = $parts[$last]
    $node.files[$leaf] = [ordered]@{
        size = $Size
        offset = [string]$Offset
        integrity = $Integrity
    }
}

function Get-CanonicalDir {
    # 目录的“长名”规范形式。$env:TEMP 在启用了 8.3 别名的用户目录下是短名
    # （如 C:\Users\SOMEUS~1\AppData\Local\Temp），而 Get-ChildItem 返回的是长名
    # （C:\Users\SomeUser\...），两者长度不同；用 Substring 相减取相对路径
    # 会整体错位（renderer/adblock.js 变成 derer/adblock.js），打包时找不到文件。
    # 所以凡是要和子项 FullName 相减的基准目录，都必须先取长名。
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($item) { $full = $item.FullName }
    return $full.TrimEnd('\')
}

function Get-UnderRootRel {
    param([string]$FullName, [string]$Root)
    $rootFull = Get-CanonicalDir $Root
    if ($FullName.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return $FullName.Substring($rootFull.Length + 1)
    }
    $item = Get-Item -LiteralPath $FullName -Force -ErrorAction SilentlyContinue
    if ($item -and $item.FullName.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return $item.FullName.Substring($rootFull.Length + 1)
    }
    throw ('无法计算相对路径：' + $FullName + '（基准 ' + $rootFull + '）')
}

function Get-WorkRelPaths {
    param([string]$WorkDir)
    $result = New-Object System.Collections.ArrayList
    $rootFull = Get-CanonicalDir $WorkDir
    $files = Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\') -replace '\\', '/'
        $result.Add($rel) | Out-Null
    }
    return $result.ToArray()
}

function New-AsarArchive {
    param([string]$SourceDir, [string[]]$OrderedPaths, [string]$OutPath)
    $tree = [ordered]@{ files = [ordered]@{} }
    $seen = @{}
    $dataStream = New-Object System.IO.MemoryStream
    $offset = [int64]0
    $all = New-Object System.Collections.ArrayList

    foreach ($p in $OrderedPaths) {
        $key = $p.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $all.Add($p) | Out-Null
    }
    $workPaths = Get-WorkRelPaths $SourceDir
    foreach ($p in $workPaths) {
        $key = $p.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $all.Add($p) | Out-Null
    }

    foreach ($rel in $all) {
        $src = Join-Path $SourceDir ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            throw ('打包失败，缺少文件：' + $rel)
        }
        $bytes = [System.IO.File]::ReadAllBytes($src)
        $integrity = Get-FileIntegrity $bytes
        Add-AsarTreeFile -TreeRoot $tree -RelPath $rel -Size $bytes.Length -Offset $offset -Integrity $integrity
        $dataStream.Write($bytes, 0, $bytes.Length)
        $offset += $bytes.Length
    }

    $json = $tree | ConvertTo-Json -Depth 100 -Compress
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $out = [System.IO.File]::Create($OutPath)
    try {
        $bw = New-Object System.IO.BinaryWriter($out)
        # asar 的 pickle 头要求 JSON 头补齐到 4 字节边界：
        #   [4..7]  = align4(jsonLen) + 8
        #   [8..11] = align4(jsonLen) + 4
        #   [12..15]= jsonLen
        # 数据从 16 + align4(jsonLen) 开始；JSON 后要补 0 到 4 字节边界。
        # 不补齐会让数据区整体错位，Electron 读出来每个文件都偏移几字节（黑屏）。
        $jsonLen = [int64]$jsonBytes.Length
        $paddedJsonLen = [int64](($jsonLen + 3) -band (-4))
        $padLen = [int]($paddedJsonLen - $jsonLen)
        $headerSize = [uint32]($paddedJsonLen + 8)
        $bw.Write([uint32]4)
        $bw.Write($headerSize)
        $bw.Write([uint32]($headerSize - 4))
        $bw.Write([uint32]$jsonLen)
        $bw.Write($jsonBytes)
        if ($padLen -gt 0) {
            $bw.Write((New-Object byte[] $padLen))
        }
        $bw.Flush()
        $dataStream.Position = 0
        $dataStream.CopyTo($out)
        $bw.Flush()
    } finally {
        $out.Close()
        $dataStream.Dispose()
    }
}

function Assert-AsarLayout {
    # 独立校验重打包出的 asar 头部自洽，防止"打包和解包用同一套错公式"互相掩盖。
    param([string]$AsarPath)
    $info = Get-AsarInfo $AsarPath
    $jsonLen = [int64]$info.JsonLen
    $paddedJsonLen = [int64](($jsonLen + 3) -band (-4))
    $expectedHeaderSize = [uint32]($paddedJsonLen + 8)

    $fs = [System.IO.File]::OpenRead($AsarPath)
    try {
        $h = New-Object byte[] 16
        $read = 0
        while ($read -lt 16) {
            $n = $fs.Read($h, $read, 16 - $read)
            if ($n -le 0) { break }
            $read += $n
        }
    } finally {
        $fs.Close()
    }
    if ($read -lt 16) { throw '重打包失败：asar 头部不足 16 字节' }
    if ([BitConverter]::ToUInt32($h, 0) -ne [uint32]4) {
        throw '重打包失败：asar 头部第一个整数不是 4'
    }
    $headerSize = [BitConverter]::ToUInt32($h, 4)
    $jsonLenField = [BitConverter]::ToUInt32($h, 12)
    if ($jsonLenField -ne [uint32]$jsonLen) {
        throw ('重打包失败：header jsonLen 不一致（声明 ' + $jsonLenField + '，实际 ' + $jsonLen + '）')
    }
    if ($headerSize -ne $expectedHeaderSize) {
        throw ('重打包失败：header 长度未 4 字节对齐（[4..7]=' + $headerSize + '，应为 ' + $expectedHeaderSize + '）')
    }
    if (([int64]($info.JsonOffset + $paddedJsonLen)) -ne [int64]$info.DataStart) {
        throw ('重打包失败：数据起点与 header 不符（DataStart=' + $info.DataStart + '，应为 ' + [int64]($info.JsonOffset + $paddedJsonLen) + '）')
    }
    if (([int64]$info.DataStart % 4) -ne 0) {
        throw ('重打包失败：数据起点未 4 字节对齐（' + $info.DataStart + '）')
    }
}

function Assert-AsarRoundTrip {
    param([string]$AsarPath, [string]$WorkDir)
    $checkDir = Join-Path $script:TempDir ('roundtrip-' + [guid]::NewGuid().ToString('N'))
    Expand-Asar -AsarPath $AsarPath -OutDir $checkDir
    try {
        $workRoot = Get-CanonicalDir $WorkDir
        $checkRoot = Get-CanonicalDir $checkDir
        $srcFiles = Get-ChildItem -LiteralPath $workRoot -Recurse -File -Force
        $srcMap = @{}
        foreach ($f in $srcFiles) {
            $rel = $f.FullName.Substring($workRoot.Length).TrimStart('\') -replace '\\', '/'
            $srcMap[$rel] = $f.FullName
        }
        $dstFiles = Get-ChildItem -LiteralPath $checkRoot -Recurse -File -Force
        if ($dstFiles.Count -ne $srcFiles.Count) {
            throw ('重打包校验失败：文件数量不一致（源 ' + $srcFiles.Count + '，包内 ' + $dstFiles.Count + '）')
        }
        foreach ($f in $dstFiles) {
            $rel = $f.FullName.Substring($checkRoot.Length).TrimStart('\') -replace '\\', '/'
            if (-not $srcMap.ContainsKey($rel)) {
                throw ('重打包校验失败：包内多出文件 ' + $rel)
            }
            if ((Get-Sha256 $srcMap[$rel]) -ne (Get-Sha256 $f.FullName)) {
                throw ('重打包校验失败：内容不一致 ' + $rel)
            }
        }
    } finally {
        try { Remove-Item -LiteralPath $checkDir -Recurse -Force } catch { }
    }
}

# ===========================================================================
# 安装目录 / 进程 / 备份
# ===========================================================================

function Find-LeigodRoot {
    $candidates = New-Object System.Collections.ArrayList
    if ($Root) { $candidates.Add($Root) | Out-Null }
    $pf86 = ${env:ProgramFiles(x86)}
    $pf = $env:ProgramFiles
    if ($pf86) { $candidates.Add((Join-Path $pf86 'LeiGod_Acc')) | Out-Null }
    if ($pf) { $candidates.Add((Join-Path $pf 'LeiGod_Acc')) | Out-Null }

    $hives = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($hive in $hives) {
        try {
            Get-ChildItem -Path $hive -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if ($props -and $props.InstallLocation -and $props.DisplayName -and
                    ($props.DisplayName -match '雷神|LeiGod|leigod')) {
                    $candidates.Add([string]$props.InstallLocation) | Out-Null
                }
            }
        } catch { }
    }

    try {
        Get-Process -Name 'leigod','leigod_launcher','leigod-tool' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Path) { $candidates.Add((Split-Path -Parent $_.Path)) | Out-Null }
        }
    } catch { }

    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $p = [string]$c
        if (Test-Path -LiteralPath (Join-Path $p 'resources\renderer.asar')) {
            return (Get-CanonicalDir $p)
        }
    }
    return $null
}

function Get-TargetProcesses {
    param([string]$InstallRoot, [string]$Name)
    $prefix = $InstallRoot.TrimEnd('\') + '\'
    $result = @()
    foreach ($p in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $p.Path } catch { }
        if ($path -and $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $result += $p
        }
    }
    return $result
}

function Stop-LeigodProcesses {
    param([string]$InstallRoot)
    $names = @('leigod', 'leigod_launcher', 'leigod-tool', 'leishenSdk')
    $stopped = @()
    foreach ($n in $names) {
        $procs = @(Get-TargetProcesses -InstallRoot $InstallRoot -Name $n)
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $stopped += ($n + '(' + $p.Id + ')')
            } catch {
                Write-WarnLine ('无法结束进程 ' + $n + '(' + $p.Id + ')：' + $_.Exception.Message)
            }
        }
    }
    if ($stopped.Count -gt 0) {
        Write-Log ('已结束进程：' + ($stopped -join '、'))
        Start-Sleep -Seconds 3
    }
    foreach ($n in $names) {
        if (@(Get-TargetProcesses -InstallRoot $InstallRoot -Name $n).Count -gt 0) {
            throw ('进程仍在运行：' + $n + '。请先手动退出雷神再重试。')
        }
    }
}

function New-BackupDirectory {
    param([string]$InstallRoot)
    $backupRoot = Join-Path $env:USERPROFILE 'GamewareCleanerBackup'
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $backupRoot ('leigod-' + $stamp)
    $n = 1
    while (Test-Path -LiteralPath $dir) {
        $dir = Join-Path $backupRoot ('leigod-' + $stamp + '-' + $n)
        $n++
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'quarantine') | Out-Null
    $script:LogPath = Join-Path $dir 'run.log'
    return $dir
}

# ===========================================================================
# 渲染层补丁
# ===========================================================================

function Get-JsText {
    param([string]$Path)
    if (-not $script:JsCache.ContainsKey($Path)) {
        $script:JsCache[$Path] = Read-Utf8 $Path
    }
    return $script:JsCache[$Path]
}

function Set-JsText {
    param([string]$Path, [string]$Text)
    Write-Utf8NoBom $Path $Text
    $script:JsCache[$Path] = $Text
}

function Find-JsChunk {
    param([string]$WorkDir, [string[]]$MustContain)
    $assets = Join-Path $WorkDir 'assets'
    $files = @()
    if (Test-Path -LiteralPath $assets) {
        $files += @(Get-ChildItem -LiteralPath $assets -Filter '*.js' -File -Force)
    }
    $files += @(Get-ChildItem -LiteralPath $WorkDir -Filter '*.js' -File -Force)
    foreach ($f in $files) {
        $text = Get-JsText $f.FullName
        $ok = $true
        foreach ($m in $MustContain) {
            if ($text.IndexOf($m) -lt 0) { $ok = $false; break }
        }
        if ($ok) { return $f.FullName }
    }
    return $null
}

function Find-JsChunkByRegex {
    param([string]$WorkDir, [string]$Pattern, [string[]]$MustContain)
    $assets = Join-Path $WorkDir 'assets'
    $files = @()
    if (Test-Path -LiteralPath $assets) {
        $files += @(Get-ChildItem -LiteralPath $assets -Filter '*.js' -File -Force)
    }
    foreach ($f in $files) {
        $text = Get-JsText $f.FullName
        $ok = $true
        foreach ($m in $MustContain) {
            if ($text.IndexOf($m) -lt 0) { $ok = $false; break }
        }
        if (-not $ok) { continue }
        if ([regex]::IsMatch($text, $Pattern)) { return $f.FullName }
    }
    return $null
}

function Add-IndexScriptTag {
    param([string]$IndexPath)
    $html = Read-Utf8 $IndexPath
    if ($html.IndexOf('adblock.js') -ge 0) {
        Write-Log 'index.html 已包含 adblock.js，跳过'
        return
    }
    $eol = if ($html.Contains("`r`n")) { "`r`n" } else { "`n" }
    $tag = '  <script src="./adblock.js"></script>' + $eol
    $m = [regex]::Match($html, '<script\s+type="module"', 'IgnoreCase')
    if ($m.Success) {
        $insertAt = $m.Index
        $nl = $html.LastIndexOf([string][char]10, [Math]::Max(0, $m.Index - 1))
        if ($nl -ge 0) { $insertAt = $nl + 1 }
        $indent = $html.Substring($insertAt, $m.Index - $insertAt)
        $tag = $indent + '<script src="./adblock.js"></script>' + $eol
        $html = $html.Substring(0, $insertAt) + $tag + $html.Substring($insertAt)
    } else {
        $m = [regex]::Match($html, '</head>', 'IgnoreCase')
        if (-not $m.Success) { throw 'index.html 里找不到 </head>，无法注入 adblock.js' }
        $html = $html.Substring(0, $m.Index) + $tag + $html.Substring($m.Index)
    }
    Write-Utf8NoBom $IndexPath $html
    Write-Log 'index.html 已注入 adblock.js'
}

function Add-IndexStyleLink {
    param([string]$IndexPath, [string]$CssName)
    $html = Read-Utf8 $IndexPath
    if ($html.IndexOf($CssName) -ge 0) {
        Write-Log ('index.html 已包含 ' + $CssName + '，跳过')
        return
    }
    $m = [regex]::Match($html, '</head>', 'IgnoreCase')
    if (-not $m.Success) { throw ('index.html 里找不到 </head>，无法注入 ' + $CssName) }
    $eol = if ($html.Contains("`r`n")) { "`r`n" } else { "`n" }
    $link = '  <link rel="stylesheet" crossorigin href="./' + $CssName + '">' + $eol
    $html = $html.Substring(0, $m.Index) + $link + $html.Substring($m.Index)
    Write-Utf8NoBom $IndexPath $html
    Write-Log ('index.html 已注入 ' + $CssName)
}

$script:IdleTimePauseJs = @'
// Shared runtime embedded by both installers. No network or acceleration calls.
function installIdleTimePause(read, pause, watch) {
  let timer = null;
  let pending = false;
  let active = false;
  function eligible() {
    const state = read();
    const time = state.time;
    const acc = state.acc;
    // Unknown / connecting / stopping states must never be treated as idle.
    return !!(state.loggedIn && !state.busy && time &&
      time.timeStatus === "timeing" && time.canPauseTimeLeft > 0 &&
      time.notCanPauseTimeLeft <= 0 && acc &&
      acc.accStatus === "normal" && !acc.game_id);
  }
  function key() {
    return JSON.stringify([read().account, eligible()]);
  }
  function cancel() {
    if (timer !== null) clearTimeout(timer);
    timer = null;
  }
  function arm(expected) {
    if (pending || !eligible()) return;
    timer = setTimeout(async function () {
      timer = null;
      // Recheck at the deadline, including login identity and acceleration.
      if (pending || key() !== expected || !eligible()) return;
      pending = true;
      try {
        await pause();
      } catch (_) {
        console.error("Gameware-Cleaner: idle time pause failed");
      } finally {
        pending = false;
        // If the server did not pause, wait another full 3 minutes to retry.
        if (active && eligible()) arm(key());
      }
    }, 180000);
  }
  // Vue owns this watcher in the user store scope; cleanup also cancels timers
  // when that scope is disposed. Comparing a primitive avoids resetting the
  // deadline whenever remaining time is refreshed by the server.
  watch(key, function (current, previous, onCleanup) {
    cancel();
    active = true;
    onCleanup(function () { active = false; cancel(); });
    arm(current);
  }, { immediate: true, flush: "sync" });
}
'@

function Patch-IdleTimePause {
    param([string]$WorkDir)
    $chunks = @(Get-ChildItem -LiteralPath (Join-Path $WorkDir 'assets') -Filter '*.js' -File | Where-Object {
        $candidate = Get-JsText $_.FullName
        $candidate.Contains('return{accountToken:') -and $candidate.Contains('toggleTimeStatus:')
    })
    if ($chunks.Count -ne 1) { throw '全局用户计时状态不唯一或缺失，无法安装空闲自动暂停' }
    $chunk = $chunks[0].FullName
    $text = Read-Utf8 $chunk
    if ($text.Contains('/*gc-idle-pause:start*/')) { return $false }
    $id = '[A-Za-z_$][\w$]*'
    $pattern = ';return\{accountToken:(' + $id + '),userInfo:(' + $id + '),userTimeInfo:(' + $id + '),userSpeedTimeInfo:(' + $id + '),isLogin:(' + $id + '),refreshing:(' + $id + '),progressing:(' + $id + '),viewTimeStatus:(' + $id + '),timeStatusScene:(' + $id + '),toggleTimeStatus:(' + $id + '),'
    $matchesApi = [regex]::Matches($text, $pattern)
    $storeAt = $text.IndexOf('("user",()=>{const ')
    $watchAt = $text.IndexOf('.userInfo?.is_use_pause_time,')
    if ($storeAt -lt 0 -or $watchAt -lt 128) { throw '找不到用户状态或监听器绑定' }
    $stores = [regex]::Matches($text.Substring([Math]::Max(0, $storeAt - 128), 256), '=\w+\("user",\(\)=>\{const (' + $id + ')=(' + $id + ')\(\),')
    $watch = [regex]::Match($text.Substring($watchAt - 128, 180), '(' + $id + ')\(\(\)=>(' + $id + ')\.userInfo\?\.is_use_pause_time,')
    if ($matchesApi.Count -ne 1 -or $stores.Count -ne 1 -or -not $watch.Success) {
        throw '用户计时状态结构不匹配，未安装空闲自动暂停'
    }
    $api = $matchesApi[0]
    $hook = '/*gc-idle-pause:start*/(' + (Convert-ToLf $script:IdleTimePauseJs).Trim() +
        ')(()=>({account:' + $api.Groups[2].Value + '.value?.nn_number,loggedIn:' +
        $api.Groups[5].Value + '.value,time:' + $api.Groups[3].Value + '.value,busy:' +
        $api.Groups[7].Value + '.value,acc:' + $stores[0].Groups[1].Value +
        '.accInfo}),()=>'+ $api.Groups[10].Value + '("pause",{scene:"close_tip_type2"}),' +
        $watch.Groups[1].Value + ');/*gc-idle-pause:end*/'
    $at = $api.Index + 1
    Set-JsText $chunk ($text.Substring(0, $at) + $hook + $text.Substring($at))
    Write-Ok '已开启：计时开启且连续 3 分钟未加速时，自动暂停时长'
    return $true
}

# gc-medium-embedded:start
$script:Md3eSystemColorJs = @'
// Offline Material Color Utilities 0.4.0; generated by tools/build-medium.mjs.
/*
Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   Copyright 2021 Google LLC

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
(()=>{/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function z(r){return r<0?-1:r===0?0:1}function ot(r,t,e){return(1-e)*r+e*t}function Wt(r,t,e){return e<r?r:e>t?t:e}function H(r,t,e){return e<r?r:e>t?t:e}function ut(r){return r=r%360,r<0&&(r=r+360),r}function _(r){return r=r%360,r<0&&(r=r+360),r}function Ot(r,t){return 180-Math.abs(Math.abs(r-t)-180)}function mt(r,t){let e=r[0]*t[0][0]+r[1]*t[0][1]+r[2]*t[0][2],n=r[0]*t[1][0]+r[1]*t[1][1]+r[2]*t[1][2],a=r[0]*t[2][0]+r[1]*t[2][1]+r[2]*t[2][2];return[e,n,a]}/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var Jt=[[.41233895,.35762064,.18051042],[.2126,.7152,.0722],[.01932141,.11916382,.95034478]],me=[[3.2413774792388685,-1.5376652402851851,-.49885366846268053],[-.9691452513005321,1.8758853451067872,.04156585616912061],[.05562093689691305,-.20395524564742123,1.0571799111220335]],Zt=[95.047,100,108.883];function Dt(r,t,e){return(255<<24|(r&255)<<16|(t&255)<<8|e&255)>>>0}function Vt(r){let t=it(r[0]),e=it(r[1]),n=it(r[2]);return Dt(t,e,n)}function pt(r){return r>>16&255}function dt(r){return r>>8&255}function gt(r){return r&255}function Qt(r,t,e){let n=me,a=n[0][0]*r+n[0][1]*t+n[0][2]*e,s=n[1][0]*r+n[1][1]*t+n[1][2]*e,o=n[2][0]*r+n[2][1]*t+n[2][2]*e,l=it(a),f=it(s),p=it(o);return Dt(l,f,p)}function fe(r){let t=j(pt(r)),e=j(dt(r)),n=j(gt(r));return mt([t,e,n],Jt)}function Nt(r){let t=j(pt(r)),e=j(dt(r)),n=j(gt(r)),a=Jt,s=a[0][0]*t+a[0][1]*e+a[0][2]*n,o=a[1][0]*t+a[1][1]*e+a[1][2]*n,l=a[2][0]*t+a[2][1]*e+a[2][2]*n,f=Zt,p=s/f[0],d=o/f[1],S=l/f[2],g=ft(p),y=ft(d),m=ft(S),h=116*y-16,P=500*(g-y),b=200*(y-m);return[h,P,b]}function te(r){let t=X(r),e=it(t);return Dt(e,e,e)}function kt(r){let t=fe(r)[1];return 116*ft(t/100)-16}function X(r){return 100*pe((r+16)/116)}function yt(r){return ft(r/100)*116-16}function j(r){let t=r/255;return t<=.040449936?t/12.92*100:Math.pow((t+.055)/1.055,2.4)*100}function it(r){let t=r/100,e=0;return t<=.0031308?e=t*12.92:e=1.055*Math.pow(t,1/2.4)-.055,Wt(0,255,Math.round(e*255))}function ee(){return Zt}function ft(r){let t=.008856451679035631,e=24389/27;return r>t?Math.pow(r,1/3):(e*r+16)/116}function pe(r){let t=.008856451679035631,e=24389/27,n=r*r*r;return n>t?n:(116*r-16)/e}/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var G=class r{static make(t=ee(),e=200/Math.PI*X(50)/100,n=50,a=2,s=!1){let o=t,l=o[0]*.401288+o[1]*.650173+o[2]*-.051461,f=o[0]*-.250268+o[1]*1.204414+o[2]*.045854,p=o[0]*-.002079+o[1]*.048952+o[2]*.953127,d=.8+a/10,S=d>=.9?ot(.59,.69,(d-.9)*10):ot(.525,.59,(d-.8)*10),g=s?1:d*(1-1/3.6*Math.exp((-e-42)/92));g=g>1?1:g<0?0:g;let y=d,m=[g*(100/l)+1-g,g*(100/f)+1-g,g*(100/p)+1-g],h=1/(5*e+1),P=h*h*h*h,b=1-P,v=P*e+.1*b*b*Math.cbrt(5*e),I=X(n)/t[1],B=1.48+Math.sqrt(I),O=.725/Math.pow(I,.2),R=O,E=[Math.pow(v*m[0]*l/100,.42),Math.pow(v*m[1]*f/100,.42),Math.pow(v*m[2]*p/100,.42)],N=[400*E[0]/(E[0]+27.13),400*E[1]/(E[1]+27.13),400*E[2]/(E[2]+27.13)],U=(2*N[0]+N[1]+.05*N[2])*O;return new r(I,U,O,R,S,y,m,v,Math.pow(v,.25),B)}constructor(t,e,n,a,s,o,l,f,p,d){this.n=t,this.aw=e,this.nbb=n,this.ncb=a,this.c=s,this.nc=o,this.rgbD=l,this.fl=f,this.fLRoot=p,this.z=d}};G.DEFAULT=G.make();/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var W=class r{constructor(t,e,n,a,s,o,l,f,p){this.hue=t,this.chroma=e,this.j=n,this.q=a,this.m=s,this.s=o,this.jstar=l,this.astar=f,this.bstar=p}distance(t){let e=this.jstar-t.jstar,n=this.astar-t.astar,a=this.bstar-t.bstar,s=Math.sqrt(e*e+n*n+a*a);return 1.41*Math.pow(s,.63)}static fromInt(t){return r.fromIntInViewingConditions(t,G.DEFAULT)}static fromIntInViewingConditions(t,e){let n=(t&16711680)>>16,a=(t&65280)>>8,s=t&255,o=j(n),l=j(a),f=j(s),p=.41233895*o+.35762064*l+.18051042*f,d=.2126*o+.7152*l+.0722*f,S=.01932141*o+.11916382*l+.95034478*f,g=.401288*p+.650173*d-.051461*S,y=-.250268*p+1.204414*d+.045854*S,m=-.002079*p+.048952*d+.953127*S,h=e.rgbD[0]*g,P=e.rgbD[1]*y,b=e.rgbD[2]*m,v=Math.pow(e.fl*Math.abs(h)/100,.42),I=Math.pow(e.fl*Math.abs(P)/100,.42),B=Math.pow(e.fl*Math.abs(b)/100,.42),O=z(h)*400*v/(v+27.13),R=z(P)*400*I/(I+27.13),E=z(b)*400*B/(B+27.13),N=(11*O+-12*R+E)/11,U=(O+R-2*E)/9,L=(20*O+20*R+21*E)/20,J=(40*O+20*R+E)/20,ct=Math.atan2(U,N)*180/Math.PI,K=_(ct),St=K*Math.PI/180,xt=J*e.nbb,et=100*Math.pow(xt/e.aw,e.c*e.z),At=4/e.c*Math.sqrt(et/100)*(e.aw+4)*e.fLRoot,Mt=K<20.14?K+360:K,Bt=.25*(Math.cos(Mt*Math.PI/180+2)+3.8),Lt=5e4/13*Bt*e.nc*e.ncb*Math.sqrt(N*N+U*U)/(L+.305),Tt=Math.pow(Lt,.9)*Math.pow(1.64-Math.pow(.29,e.n),.73),qt=Tt*Math.sqrt(et/100),$t=qt*e.fLRoot,ce=50*Math.sqrt(Tt*e.c/(e.aw+4)),ue=(1+100*.007)*et/(1+.007*et),jt=1/.0228*Math.log(1+.0228*$t),le=jt*Math.cos(St),he=jt*Math.sin(St);return new r(K,qt,et,At,$t,ce,ue,le,he)}static fromJch(t,e,n){return r.fromJchInViewingConditions(t,e,n,G.DEFAULT)}static fromJchInViewingConditions(t,e,n,a){let s=4/a.c*Math.sqrt(t/100)*(a.aw+4)*a.fLRoot,o=e*a.fLRoot,l=e/Math.sqrt(t/100),f=50*Math.sqrt(l*a.c/(a.aw+4)),p=n*Math.PI/180,d=(1+100*.007)*t/(1+.007*t),S=1/.0228*Math.log(1+.0228*o),g=S*Math.cos(p),y=S*Math.sin(p);return new r(n,e,t,s,o,f,d,g,y)}static fromUcs(t,e,n){return r.fromUcsInViewingConditions(t,e,n,G.DEFAULT)}static fromUcsInViewingConditions(t,e,n,a){let s=e,o=n,l=Math.sqrt(s*s+o*o),p=(Math.exp(l*.0228)-1)/.0228/a.fLRoot,d=Math.atan2(o,s)*(180/Math.PI);d<0&&(d+=360);let S=t/(1-(t-100)*.007);return r.fromJchInViewingConditions(S,p,d,a)}toInt(){return this.viewed(G.DEFAULT)}viewed(t){let e=this.chroma===0||this.j===0?0:this.chroma/Math.sqrt(this.j/100),n=Math.pow(e/Math.pow(1.64-Math.pow(.29,t.n),.73),1/.9),a=this.hue*Math.PI/180,s=.25*(Math.cos(a+2)+3.8),o=t.aw*Math.pow(this.j/100,1/t.c/t.z),l=s*(5e4/13)*t.nc*t.ncb,f=o/t.nbb,p=Math.sin(a),d=Math.cos(a),S=23*(f+.305)*n/(23*l+11*n*d+108*n*p),g=S*d,y=S*p,m=(460*f+451*g+288*y)/1403,h=(460*f-891*g-261*y)/1403,P=(460*f-220*g-6300*y)/1403,b=Math.max(0,27.13*Math.abs(m)/(400-Math.abs(m))),v=z(m)*(100/t.fl)*Math.pow(b,1/.42),I=Math.max(0,27.13*Math.abs(h)/(400-Math.abs(h))),B=z(h)*(100/t.fl)*Math.pow(I,1/.42),O=Math.max(0,27.13*Math.abs(P)/(400-Math.abs(P))),R=z(P)*(100/t.fl)*Math.pow(O,1/.42),E=v/t.rgbD[0],N=B/t.rgbD[1],U=R/t.rgbD[2],L=1.86206786*E-1.01125463*N+.14918677*U,J=.38752654*E+.62144744*N-.00897398*U,tt=-.0158415*E-.03412294*N+1.04996444*U;return Qt(L,J,tt)}static fromXyzInViewingConditions(t,e,n,a){let s=.401288*t+.650173*e-.051461*n,o=-.250268*t+1.204414*e+.045854*n,l=-.002079*t+.048952*e+.953127*n,f=a.rgbD[0]*s,p=a.rgbD[1]*o,d=a.rgbD[2]*l,S=Math.pow(a.fl*Math.abs(f)/100,.42),g=Math.pow(a.fl*Math.abs(p)/100,.42),y=Math.pow(a.fl*Math.abs(d)/100,.42),m=z(f)*400*S/(S+27.13),h=z(p)*400*g/(g+27.13),P=z(d)*400*y/(y+27.13),b=(11*m+-12*h+P)/11,v=(m+h-2*P)/9,I=(20*m+20*h+21*P)/20,B=(40*m+20*h+P)/20,R=Math.atan2(v,b)*180/Math.PI,E=R<0?R+360:R>=360?R-360:R,N=E*Math.PI/180,U=B*a.nbb,L=100*Math.pow(U/a.aw,a.c*a.z),J=4/a.c*Math.sqrt(L/100)*(a.aw+4)*a.fLRoot,tt=E<20.14?E+360:E,ct=1/4*(Math.cos(tt*Math.PI/180+2)+3.8),St=5e4/13*ct*a.nc*a.ncb*Math.sqrt(b*b+v*v)/(I+.305),xt=Math.pow(St,.9)*Math.pow(1.64-Math.pow(.29,a.n),.73),et=xt*Math.sqrt(L/100),At=et*a.fLRoot,Mt=50*Math.sqrt(xt*a.c/(a.aw+4)),Bt=(1+100*.007)*L/(1+.007*L),Rt=Math.log(1+.0228*At)/.0228,Lt=Rt*Math.cos(N),Tt=Rt*Math.sin(N);return new r(E,et,L,J,At,Mt,Bt,Lt,Tt)}xyzInViewingConditions(t){let e=this.chroma===0||this.j===0?0:this.chroma/Math.sqrt(this.j/100),n=Math.pow(e/Math.pow(1.64-Math.pow(.29,t.n),.73),1/.9),a=this.hue*Math.PI/180,s=.25*(Math.cos(a+2)+3.8),o=t.aw*Math.pow(this.j/100,1/t.c/t.z),l=s*(5e4/13)*t.nc*t.ncb,f=o/t.nbb,p=Math.sin(a),d=Math.cos(a),S=23*(f+.305)*n/(23*l+11*n*d+108*n*p),g=S*d,y=S*p,m=(460*f+451*g+288*y)/1403,h=(460*f-891*g-261*y)/1403,P=(460*f-220*g-6300*y)/1403,b=Math.max(0,27.13*Math.abs(m)/(400-Math.abs(m))),v=z(m)*(100/t.fl)*Math.pow(b,1/.42),I=Math.max(0,27.13*Math.abs(h)/(400-Math.abs(h))),B=z(h)*(100/t.fl)*Math.pow(I,1/.42),O=Math.max(0,27.13*Math.abs(P)/(400-Math.abs(P))),R=z(P)*(100/t.fl)*Math.pow(O,1/.42),E=v/t.rgbD[0],N=B/t.rgbD[1],U=R/t.rgbD[2],L=1.86206786*E-1.01125463*N+.14918677*U,J=.38752654*E+.62144744*N-.00897398*U,tt=-.0158415*E-.03412294*N+1.04996444*U;return[L,J,tt]}};/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var $=class r{static sanitizeRadians(t){return(t+Math.PI*8)%(Math.PI*2)}static trueDelinearized(t){let e=t/100,n=0;return e<=.0031308?n=e*12.92:n=1.055*Math.pow(e,1/2.4)-.055,n*255}static chromaticAdaptation(t){let e=Math.pow(Math.abs(t),.42);return z(t)*400*e/(e+27.13)}static hueOf(t){let e=mt(t,r.SCALED_DISCOUNT_FROM_LINRGB),n=r.chromaticAdaptation(e[0]),a=r.chromaticAdaptation(e[1]),s=r.chromaticAdaptation(e[2]),o=(11*n+-12*a+s)/11,l=(n+a-2*s)/9;return Math.atan2(l,o)}static areInCyclicOrder(t,e,n){let a=r.sanitizeRadians(e-t),s=r.sanitizeRadians(n-t);return a<s}static intercept(t,e,n){return(e-t)/(n-t)}static lerpPoint(t,e,n){return[t[0]+(n[0]-t[0])*e,t[1]+(n[1]-t[1])*e,t[2]+(n[2]-t[2])*e]}static setCoordinate(t,e,n,a){let s=r.intercept(t[a],e,n[a]);return r.lerpPoint(t,s,n)}static isBounded(t){return 0<=t&&t<=100}static nthVertex(t,e){let n=r.Y_FROM_LINRGB[0],a=r.Y_FROM_LINRGB[1],s=r.Y_FROM_LINRGB[2],o=e%4<=1?0:100,l=e%2===0?0:100;if(e<4){let f=o,p=l,d=(t-f*a-p*s)/n;return r.isBounded(d)?[d,f,p]:[-1,-1,-1]}else if(e<8){let f=o,p=l,d=(t-p*n-f*s)/a;return r.isBounded(d)?[p,d,f]:[-1,-1,-1]}else{let f=o,p=l,d=(t-f*n-p*a)/s;return r.isBounded(d)?[f,p,d]:[-1,-1,-1]}}static bisectToSegment(t,e){let n=[-1,-1,-1],a=n,s=0,o=0,l=!1,f=!0;for(let p=0;p<12;p++){let d=r.nthVertex(t,p);if(d[0]<0)continue;let S=r.hueOf(d);if(!l){n=d,a=d,s=S,o=S,l=!0;continue}(f||r.areInCyclicOrder(s,S,o))&&(f=!1,r.areInCyclicOrder(s,e,S)?(a=d,o=S):(n=d,s=S))}return[n,a]}static midpoint(t,e){return[(t[0]+e[0])/2,(t[1]+e[1])/2,(t[2]+e[2])/2]}static criticalPlaneBelow(t){return Math.floor(t-.5)}static criticalPlaneAbove(t){return Math.ceil(t-.5)}static bisectToLimit(t,e){let n=r.bisectToSegment(t,e),a=n[0],s=r.hueOf(a),o=n[1];for(let l=0;l<3;l++)if(a[l]!==o[l]){let f=-1,p=255;a[l]<o[l]?(f=r.criticalPlaneBelow(r.trueDelinearized(a[l])),p=r.criticalPlaneAbove(r.trueDelinearized(o[l]))):(f=r.criticalPlaneAbove(r.trueDelinearized(a[l])),p=r.criticalPlaneBelow(r.trueDelinearized(o[l])));for(let d=0;d<8&&!(Math.abs(p-f)<=1);d++){let S=Math.floor((f+p)/2),g=r.CRITICAL_PLANES[S],y=r.setCoordinate(a,g,o,l),m=r.hueOf(y);r.areInCyclicOrder(s,e,m)?(o=y,p=S):(a=y,s=m,f=S)}}return r.midpoint(a,o)}static inverseChromaticAdaptation(t){let e=Math.abs(t),n=Math.max(0,27.13*e/(400-e));return z(t)*Math.pow(n,1/.42)}static findResultByJ(t,e,n){let a=Math.sqrt(n)*11,s=G.DEFAULT,o=1/Math.pow(1.64-Math.pow(.29,s.n),.73),f=.25*(Math.cos(t+2)+3.8)*(5e4/13)*s.nc*s.ncb,p=Math.sin(t),d=Math.cos(t);for(let S=0;S<5;S++){let g=a/100,y=e===0||a===0?0:e/Math.sqrt(g),m=Math.pow(y*o,1/.9),P=s.aw*Math.pow(g,1/s.c/s.z)/s.nbb,b=23*(P+.305)*m/(23*f+11*m*d+108*m*p),v=b*d,I=b*p,B=(460*P+451*v+288*I)/1403,O=(460*P-891*v-261*I)/1403,R=(460*P-220*v-6300*I)/1403,E=r.inverseChromaticAdaptation(B),N=r.inverseChromaticAdaptation(O),U=r.inverseChromaticAdaptation(R),L=mt([E,N,U],r.LINRGB_FROM_SCALED_DISCOUNT);if(L[0]<0||L[1]<0||L[2]<0)return 0;let J=r.Y_FROM_LINRGB[0],tt=r.Y_FROM_LINRGB[1],ct=r.Y_FROM_LINRGB[2],K=J*L[0]+tt*L[1]+ct*L[2];if(K<=0)return 0;if(S===4||Math.abs(K-n)<.002)return L[0]>100.01||L[1]>100.01||L[2]>100.01?0:Vt(L);a=a-(K-n)*a/(2*K)}return 0}static solveToInt(t,e,n){if(e<1e-4||n<1e-4||n>99.9999)return te(n);t=_(t);let a=t/180*Math.PI,s=X(n),o=r.findResultByJ(a,e,s);if(o!==0)return o;let l=r.bisectToLimit(s,a);return Vt(l)}static solveToCam(t,e,n){return W.fromInt(r.solveToInt(t,e,n))}};$.SCALED_DISCOUNT_FROM_LINRGB=[[.001200833568784504,.002389694492170889,.0002795742885861124],[.0005891086651375999,.0029785502573438758,.0003270666104008398],[.00010146692491640572,.0005364214359186694,.0032979401770712076]];$.LINRGB_FROM_SCALED_DISCOUNT=[[1373.2198709594231,-1100.4251190754821,-7.278681089101213],[-271.815969077903,559.6580465940733,-32.46047482791194],[1.9622899599665666,-57.173814538844006,308.7233197812385]];$.Y_FROM_LINRGB=[.2126,.7152,.0722];$.CRITICAL_PLANES=[.015176349177441876,.045529047532325624,.07588174588720938,.10623444424209313,.13658714259697685,.16693984095186062,.19729253930674434,.2276452376616281,.2579979360165119,.28835063437139563,.3188300904430532,.350925934958123,.3848314933096426,.42057480301049466,.458183274052838,.4976837250274023,.5391024159806381,.5824650784040898,.6277969426914107,.6751227633498623,.7244668422128921,.775853049866786,.829304845476233,.8848452951698498,.942497089126609,1.0022825574869039,1.0642236851973577,1.1283421258858297,1.1946592148522128,1.2631959812511864,1.3339731595349034,1.407011200216447,1.4823302800086415,1.5599503113873272,1.6398909516233677,1.7221716113234105,1.8068114625156377,1.8938294463134073,1.9832442801866852,2.075074464868551,2.1693382909216234,2.2660538449872063,2.36523901573795,2.4669114995532007,2.5710888059345764,2.6777882626779785,2.7870270208169257,2.898822059350997,3.0131901897720907,3.1301480604002863,3.2497121605402226,3.3718988244681087,3.4967242352587946,3.624204428461639,3.754355295633311,3.887192587735158,4.022731918402185,4.160988767090289,4.301978482107941,4.445716283538092,4.592217266055746,4.741496401646282,4.893568542229298,5.048448422192488,5.20615066083972,5.3666897647573375,5.5300801301023865,5.696336044816294,5.865471690767354,6.037501145825082,6.212438385869475,6.390297286737924,6.571091626112461,6.7548350853498045,6.941541251256611,7.131223617812143,7.323895587840543,7.5195704746346665,7.7182615035334345,7.919981813454504,8.124744458384042,8.332562408825165,8.543448553206703,8.757415699253682,8.974476575321063,9.194643831691977,9.417930041841839,9.644347703669503,9.873909240696694,10.106627003236781,10.342513269534024,10.58158024687427,10.8238400726681,11.069304815507364,11.317986476196008,11.569896988756009,11.825048221409341,12.083451977536606,12.345119996613247,12.610063955123938,12.878295467455942,13.149826086772048,13.42466730586372,13.702830557985108,13.984327217668513,14.269168601521828,14.55736596900856,14.848930523210871,15.143873411576273,15.44220572664832,15.743938506781891,16.04908273684337,16.35764934889634,16.66964922287304,16.985093187232053,17.30399201960269,17.62635644741625,17.95219714852476,18.281524751807332,18.614349837764564,18.95068293910138,19.290534541298456,19.633915083172692,19.98083495742689,20.331304511189067,20.685334046541502,21.042933821039977,21.404114048223256,21.76888489811322,22.137256497705877,22.50923893145328,22.884842241736916,23.264076429332462,23.6469514538663,24.033477234264016,24.42366364919083,24.817520537484558,25.21505769858089,25.61628489293138,26.021211842414342,26.429848230738664,26.842203703840827,27.258287870275353,27.678110301598522,28.10168053274597,28.529008062403893,28.96010235337422,29.39497283293396,29.83362889318845,30.276079891419332,30.722335150426627,31.172403958865512,31.62629557157785,32.08401920991837,32.54558406207592,33.010999283389665,33.4802739966603,33.953417292456834,34.430438229418264,34.911345834551085,35.39614910352207,35.88485700094671,36.37747846067349,36.87402238606382,37.37449765026789,37.87891309649659,38.38727753828926,38.89959975977785,39.41588851594697,39.93615253289054,40.460400508064545,40.98864111053629,41.520882981230194,42.05713473317016,42.597404951718396,43.141702194811224,43.6900349931913,44.24241185063697,44.798841244188324,45.35933162437017,45.92389141541209,46.49252901546552,47.065252796817916,47.64207110610409,48.22299226451468,48.808024568002054,49.3971762874833,49.9904556690408,50.587870934119984,51.189430279724725,51.79514187861014,52.40501387947288,53.0190544071392,53.637271562750364,54.259673423945976,54.88626804504493,55.517063457223934,56.15206766869424,56.79128866487574,57.43473440856916,58.08241284012621,58.734331877617365,59.39049941699807,60.05092333227251,60.715611475655585,61.38457167773311,62.057811747619894,62.7353394731159,63.417162620860914,64.10328893648692,64.79372614476921,65.48848194977529,66.18756403501224,66.89098006357258,67.59873767827808,68.31084450182222,69.02730813691093,69.74813616640164,70.47333615344107,71.20291564160104,71.93688215501312,72.67524319850172,73.41800625771542,74.16517879925733,74.9167682708136,75.67278210128072,76.43322770089146,77.1981124613393,77.96744375590167,78.74122893956174,79.51947534912904,80.30219030335869,81.08938110306934,81.88105503125999,82.67721935322541,83.4778813166706,84.28304815182372,85.09272707154808,85.90692527145302,86.72564993000343,87.54890820862819,88.3767072518277,89.2090541872801,90.04595612594655,90.88742016217518,91.73345337380438,92.58406282226491,93.43925555268066,94.29903859396902,95.16341895893969,96.03240364439274,96.9059996312159,97.78421388448044,98.6670533535366,99.55452497210776];/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var x=class r{static from(t,e,n){return new r($.solveToInt(t,e,n))}static fromInt(t){return new r(t)}toInt(){return this.argb}get hue(){return this.internalHue}set hue(t){this.setInternalState($.solveToInt(t,this.internalChroma,this.internalTone))}get chroma(){return this.internalChroma}set chroma(t){this.setInternalState($.solveToInt(this.internalHue,t,this.internalTone))}get tone(){return this.internalTone}set tone(t){this.setInternalState($.solveToInt(this.internalHue,this.internalChroma,t))}setValue(t,e){this[t]=e}toString(){return`HCT(${this.hue.toFixed(0)}, ${this.chroma.toFixed(0)}, ${this.tone.toFixed(0)})`}static isBlue(t){return t>=250&&t<270}static isYellow(t){return t>=105&&t<125}static isCyan(t){return t>=170&&t<207}constructor(t){this.argb=t;let e=W.fromInt(t);this.internalHue=e.hue,this.internalChroma=e.chroma,this.internalTone=kt(t),this.argb=t}setInternalState(t){let e=W.fromInt(t);this.internalHue=e.hue,this.internalChroma=e.chroma,this.internalTone=kt(t),this.argb=t}inViewingConditions(t){let n=W.fromInt(this.toInt()).xyzInViewingConditions(t),a=W.fromXyzInViewingConditions(n[0],n[1],n[2],G.make());return r.from(a.hue,a.chroma,yt(n[1]))}};/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var V=class r{static ratioOfTones(t,e){return t=H(0,100,t),e=H(0,100,e),r.ratioOfYs(X(t),X(e))}static ratioOfYs(t,e){let n=t>e?t:e,a=n===e?t:e;return(n+5)/(a+5)}static lighter(t,e){if(t<0||t>100)return-1;let n=X(t),a=e*(n+5)-5,s=r.ratioOfYs(a,n),o=Math.abs(s-e);if(s<e&&o>.04)return-1;let l=yt(a)+.4;return l<0||l>100?-1:l}static darker(t,e){if(t<0||t>100)return-1;let n=X(t),a=(n+5)/e-5,s=r.ratioOfYs(n,a),o=Math.abs(s-e);if(s<e&&o>.04)return-1;let l=yt(a)-.4;return l<0||l>100?-1:l}static lighterUnsafe(t,e){let n=r.lighter(t,e);return n<0?100:n}static darkerUnsafe(t,e){let n=r.darker(t,e);return n<0?0:n}};/**
 * @license
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var st=class r{static isDisliked(t){let e=Math.round(t.hue)>=90&&Math.round(t.hue)<=111,n=Math.round(t.chroma)>16,a=Math.round(t.tone)<65;return e&&n&&a}static fixIfDisliked(t){return r.isDisliked(t)?x.from(t.hue,t.chroma,70):t}};/**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function de(r,t,e){if(r.name!==e.name)throw new Error(`Attempting to extend color ${r.name} with color ${e.name} of different name for spec version ${t}.`);if(r.isBackground!==e.isBackground)throw new Error(`Attempting to extend color ${r.name} as a ${r.isBackground?"background":"foreground"} with color ${e.name} as a ${e.isBackground?"background":"foreground"} for spec version ${t}.`)}function D(r,t,e){return de(r,t,e),c.fromPalette({name:r.name,palette:n=>n.specVersion===t?e.palette(n):r.palette(n),tone:n=>n.specVersion===t?e.tone(n):r.tone(n),isBackground:r.isBackground,chromaMultiplier:n=>{let a=n.specVersion===t?e.chromaMultiplier:r.chromaMultiplier;return a!==void 0?a(n):1},background:n=>{let a=n.specVersion===t?e.background:r.background;return a!==void 0?a(n):void 0},secondBackground:n=>{let a=n.specVersion===t?e.secondBackground:r.secondBackground;return a!==void 0?a(n):void 0},contrastCurve:n=>{let a=n.specVersion===t?e.contrastCurve:r.contrastCurve;return a!==void 0?a(n):void 0},toneDeltaPair:n=>{let a=n.specVersion===t?e.toneDeltaPair:r.toneDeltaPair;return a!==void 0?a(n):void 0}})}var c=class r{static fromPalette(t){return new r(t.name??"",t.palette,t.tone??r.getInitialToneFromBackground(t.background),t.isBackground??!1,t.chromaMultiplier,t.background,t.secondBackground,t.contrastCurve,t.toneDeltaPair)}static getInitialToneFromBackground(t){return t===void 0?e=>50:e=>t(e)?t(e).getTone(e):50}constructor(t,e,n,a,s,o,l,f,p){if(this.name=t,this.palette=e,this.tone=n,this.isBackground=a,this.chromaMultiplier=s,this.background=o,this.secondBackground=l,this.contrastCurve=f,this.toneDeltaPair=p,this.hctCache=new Map,!o&&l)throw new Error(`Color ${t} has secondBackgrounddefined, but background is not defined.`);if(!o&&f)throw new Error(`Color ${t} has contrastCurvedefined, but background is not defined.`);if(o&&!f)throw new Error(`Color ${t} has backgrounddefined, but contrastCurve is not defined.`)}clone(){return r.fromPalette({name:this.name,palette:this.palette,tone:this.tone,isBackground:this.isBackground,chromaMultiplier:this.chromaMultiplier,background:this.background,secondBackground:this.secondBackground,contrastCurve:this.contrastCurve,toneDeltaPair:this.toneDeltaPair})}clearCache(){this.hctCache.clear()}getArgb(t){return this.getHct(t).toInt()}getHct(t){let e=this.hctCache.get(t);if(e!=null)return e;let n=re(t.specVersion).getHct(t,this);return this.hctCache.size>4&&this.hctCache.clear(),this.hctCache.set(t,n),n}getTone(t){return re(t.specVersion).getTone(t,this)}static foregroundTone(t,e){let n=V.lighterUnsafe(t,e),a=V.darkerUnsafe(t,e),s=V.ratioOfTones(n,t),o=V.ratioOfTones(a,t);if(r.tonePrefersLightForeground(t)){let f=Math.abs(s-o)<.1&&s<e&&o<e;return s>=e||s>=o||f?n:a}else return o>=e||o>=s?a:n}static tonePrefersLightForeground(t){return Math.round(t)<60}static toneAllowsLightForeground(t){return Math.round(t)<=49}static enableLightForeground(t){return r.tonePrefersLightForeground(t)&&!r.toneAllowsLightForeground(t)?49:t}},Ht=class{getHct(t,e){let n=e.getTone(t);return e.palette(t).getHct(n)}getTone(t,e){let n=t.contrastLevel<0,a=e.toneDeltaPair?e.toneDeltaPair(t):void 0;if(a){let s=a.roleA,o=a.roleB,l=a.delta,f=a.polarity,p=a.stayTogether,d=f==="nearer"||f==="lighter"&&!t.isDark||f==="darker"&&t.isDark,S=d?s:o,g=d?o:s,y=e.name===S.name,m=t.isDark?1:-1,h=S.tone(t),P=g.tone(t);if(e.background&&S.contrastCurve&&g.contrastCurve){let b=e.background(t),v=S.contrastCurve(t),I=g.contrastCurve(t);if(b&&v&&I){let B=b.getTone(t),O=v.get(t.contrastLevel),R=I.get(t.contrastLevel);V.ratioOfTones(B,h)<O&&(h=c.foregroundTone(B,O)),V.ratioOfTones(B,P)<R&&(P=c.foregroundTone(B,R)),n&&(h=c.foregroundTone(B,O),P=c.foregroundTone(B,R))}}return(P-h)*m<l&&(P=H(0,100,h+l*m),(P-h)*m>=l||(h=H(0,100,P-l*m))),50<=h&&h<60?m>0?(h=60,P=Math.max(P,h+l*m)):(h=49,P=Math.min(P,h+l*m)):50<=P&&P<60&&(p?m>0?(h=60,P=Math.max(P,h+l*m)):(h=49,P=Math.min(P,h+l*m)):m>0?P=60:P=49),y?h:P}else{let s=e.tone(t);if(e.background==null||e.background(t)===void 0||e.contrastCurve==null||e.contrastCurve(t)===void 0)return s;let o=e.background(t).getTone(t),l=e.contrastCurve(t).get(t.contrastLevel);if(V.ratioOfTones(o,s)>=l||(s=c.foregroundTone(o,l)),n&&(s=c.foregroundTone(o,l)),e.isBackground&&50<=s&&s<60&&(V.ratioOfTones(49,o)>=l?s=49:s=60),e.secondBackground==null||e.secondBackground(t)===void 0)return s;let[f,p]=[e.background,e.secondBackground],[d,S]=[f(t).getTone(t),p(t).getTone(t)],[g,y]=[Math.max(d,S),Math.min(d,S)];if(V.ratioOfTones(g,s)>=l&&V.ratioOfTones(y,s)>=l)return s;let m=V.lighter(g,l),h=V.darker(y,l),P=[];return m!==-1&&P.push(m),h!==-1&&P.push(h),c.tonePrefersLightForeground(d)||c.tonePrefersLightForeground(S)?m<0?100:m:P.length===1?P[0]:h<0?0:h}}},_t=class{getHct(t,e){let n=e.palette(t),a=e.getTone(t),s=n.hue,o=n.chroma*(e.chromaMultiplier?e.chromaMultiplier(t):1);return x.from(s,o,a)}getTone(t,e){let n=e.toneDeltaPair?e.toneDeltaPair(t):void 0;if(n){let a=n.roleA,s=n.roleB,o=n.polarity,l=n.constraint,f=o==="darker"||o==="relative_lighter"&&t.isDark||o==="relative_darker"&&!t.isDark?-n.delta:n.delta,p=e.name===a.name,d=p?a:s,S=p?s:a,g=d.tone(t),y=S.getTone(t),m=f*(p?1:-1);if(l==="exact"?g=H(0,100,y+m):l==="nearer"?m>0?g=H(0,100,H(y,y+m,g)):g=H(0,100,H(y+m,y,g)):l==="farther"&&(m>0?g=H(y+m,100,g):g=H(0,y+m,g)),e.background&&e.contrastCurve){let h=e.background(t),P=e.contrastCurve(t);if(h&&P){let b=h.getTone(t),v=P.get(t.contrastLevel);g=V.ratioOfTones(b,g)>=v&&t.contrastLevel>=0?g:c.foregroundTone(b,v)}}return e.isBackground&&!e.name.endsWith("_fixed_dim")&&(g>=57?g=H(65,100,g):g=H(0,49,g)),g}else{let a=e.tone(t);if(e.background==null||e.background(t)===void 0||e.contrastCurve==null||e.contrastCurve(t)===void 0)return a;let s=e.background(t).getTone(t),o=e.contrastCurve(t).get(t.contrastLevel);if(a=V.ratioOfTones(s,a)>=o&&t.contrastLevel>=0?a:c.foregroundTone(s,o),e.isBackground&&!e.name.endsWith("_fixed_dim")&&(a>=57?a=H(65,100,a):a=H(0,49,a)),e.secondBackground==null||e.secondBackground(t)===void 0)return a;let[l,f]=[e.background,e.secondBackground],[p,d]=[l(t).getTone(t),f(t).getTone(t)],[S,g]=[Math.max(p,d),Math.min(p,d)];if(V.ratioOfTones(S,a)>=o&&V.ratioOfTones(g,a)>=o)return a;let y=V.lighter(S,o),m=V.darker(g,o),h=[];return y!==-1&&h.push(y),m!==-1&&h.push(m),c.tonePrefersLightForeground(p)||c.tonePrefersLightForeground(d)?y<0?100:y:h.length===1?h[0]:m<0?0:m}}},ge=new Ht,ye=new _t;function re(r){return r==="2025"?ye:ge}/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var C=class r{static fromInt(t){let e=x.fromInt(t);return r.fromHct(e)}static fromHct(t){return new r(t.hue,t.chroma,t)}static fromHueAndChroma(t,e){let n=new Ut(t,e).create();return new r(t,e,n)}constructor(t,e,n){this.hue=t,this.chroma=e,this.keyColor=n,this.cache=new Map}tone(t){let e=this.cache.get(t);return e===void 0&&(t==99&&x.isYellow(this.hue)?e=this.averageArgb(this.tone(98),this.tone(100)):e=x.from(this.hue,this.chroma,t).toInt(),this.cache.set(t,e)),e}getHct(t){return x.fromInt(this.tone(t))}averageArgb(t,e){let n=t>>>16&255,a=t>>>8&255,s=t&255,o=e>>>16&255,l=e>>>8&255,f=e&255,p=Math.round((n+o)/2),d=Math.round((a+l)/2),S=Math.round((s+f)/2);return(255<<24|(p&255)<<16|(d&255)<<8|S&255)>>>0}},Ut=class{constructor(t,e){this.hue=t,this.requestedChroma=e,this.chromaCache=new Map,this.maxChromaValue=200}create(){let a=0,s=100;for(;a<s;){let o=Math.floor((a+s)/2),l=this.maxChroma(o)<this.maxChroma(o+1);if(this.maxChroma(o)>=this.requestedChroma-.01)if(Math.abs(a-50)<Math.abs(s-50))s=o;else{if(a===o)return x.from(this.hue,this.requestedChroma,a);a=o}else l?a=o+1:s=o}return x.from(this.hue,this.requestedChroma,a)}maxChroma(t){if(this.chromaCache.has(t))return this.chromaCache.get(t);let e=x.from(this.hue,this.maxChromaValue,t).chroma;return this.chromaCache.set(t,e),e}};/**
 * @license
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var Pt=class r{constructor(t){this.input=t,this.hctsByTempCache=[],this.hctsByHueCache=[],this.tempsByHctCache=new Map,this.inputRelativeTemperatureCache=-1,this.complementCache=null}get hctsByTemp(){if(this.hctsByTempCache.length>0)return this.hctsByTempCache;let t=this.hctsByHue.concat([this.input]),e=this.tempsByHct;return t.sort((n,a)=>e.get(n)-e.get(a)),this.hctsByTempCache=t,t}get warmest(){return this.hctsByTemp[this.hctsByTemp.length-1]}get coldest(){return this.hctsByTemp[0]}analogous(t=5,e=12){let n=Math.round(this.input.hue),a=this.hctsByHue[n],s=this.relativeTemperature(a),o=[a],l=0;for(let m=0;m<360;m++){let h=ut(n+m),P=this.hctsByHue[h],b=this.relativeTemperature(P),v=Math.abs(b-s);s=b,l+=v}let f=1,p=l/e,d=0;for(s=this.relativeTemperature(a);o.length<e;){let m=ut(n+f),h=this.hctsByHue[m],P=this.relativeTemperature(h),b=Math.abs(P-s);d+=b;let v=o.length*p,I=d>=v,B=1;for(;I&&o.length<e;){o.push(h);let O=(o.length+B)*p;I=d>=O,B++}if(s=P,f++,f>360){for(;o.length<e;)o.push(h);break}}let S=[this.input],g=Math.floor((t-1)/2);for(let m=1;m<g+1;m++){let h=0-m;for(;h<0;)h=o.length+h;h>=o.length&&(h=h%o.length),S.splice(0,0,o[h])}let y=t-g-1;for(let m=1;m<y+1;m++){let h=m;for(;h<0;)h=o.length+h;h>=o.length&&(h=h%o.length),S.push(o[h])}return S}get complement(){if(this.complementCache!=null)return this.complementCache;let t=this.coldest.hue,e=this.tempsByHct.get(this.coldest),n=this.warmest.hue,s=this.tempsByHct.get(this.warmest)-e,o=r.isBetween(this.input.hue,t,n),l=o?n:t,f=o?t:n,p=1,d=1e3,S=this.hctsByHue[Math.round(this.input.hue)],g=1-this.inputRelativeTemperature;for(let y=0;y<=360;y+=1){let m=_(l+p*y);if(!r.isBetween(m,l,f))continue;let h=this.hctsByHue[Math.round(m)],P=(this.tempsByHct.get(h)-e)/s,b=Math.abs(g-P);b<d&&(d=b,S=h)}return this.complementCache=S,this.complementCache}relativeTemperature(t){let e=this.tempsByHct.get(this.warmest)-this.tempsByHct.get(this.coldest),n=this.tempsByHct.get(t)-this.tempsByHct.get(this.coldest);return e===0?.5:n/e}get inputRelativeTemperature(){return this.inputRelativeTemperatureCache>=0?this.inputRelativeTemperatureCache:(this.inputRelativeTemperatureCache=this.relativeTemperature(this.input),this.inputRelativeTemperatureCache)}get tempsByHct(){if(this.tempsByHctCache.size>0)return this.tempsByHctCache;let t=this.hctsByHue.concat([this.input]),e=new Map;for(let n of t)e.set(n,r.rawTemperature(n));return this.tempsByHctCache=e,e}get hctsByHue(){if(this.hctsByHueCache.length>0)return this.hctsByHueCache;let t=[];for(let e=0;e<=360;e+=1){let n=x.from(e,this.input.chroma,this.input.tone);t.push(n)}return this.hctsByHueCache=t,this.hctsByHueCache}static isBetween(t,e,n){return e<n?e<=t&&t<=n:e<=t||t<=n}static rawTemperature(t){let e=Nt(t.toInt()),n=_(Math.atan2(e[2],e[1])*180/Math.PI),a=Math.sqrt(e[1]*e[1]+e[2]*e[2]);return-.5+.02*Math.pow(a,1.07)*Math.cos(_(n-50)*Math.PI/180)}};/**
 * @license
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var A=class{constructor(t,e,n,a){this.low=t,this.normal=e,this.medium=n,this.high=a}get(t){return t<=-1?this.low:t<0?ot(this.low,this.normal,(t- -1)/1):t<.5?ot(this.normal,this.medium,(t-0)/.5):t<1?ot(this.medium,this.high,(t-.5)/.5):this.high}};/**
 * @license
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var w=class{constructor(t,e,n,a,s,o){this.roleA=t,this.roleB=e,this.delta=n,this.polarity=a,this.stayTogether=s,this.constraint=o,this.constraint=o??"exact"}};/**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var i;(function(r){r[r.MONOCHROME=0]="MONOCHROME",r[r.NEUTRAL=1]="NEUTRAL",r[r.TONAL_SPOT=2]="TONAL_SPOT",r[r.VIBRANT=3]="VIBRANT",r[r.EXPRESSIVE=4]="EXPRESSIVE",r[r.FIDELITY=5]="FIDELITY",r[r.CONTENT=6]="CONTENT",r[r.RAINBOW=7]="RAINBOW",r[r.FRUIT_SALAD=8]="FRUIT_SALAD"})(i||(i={}));/**
 * @license
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function lt(r){return r.variant===i.FIDELITY||r.variant===i.CONTENT}function M(r){return r.variant===i.MONOCHROME}function Pe(r,t,e,n){let a=e,s=x.from(r,t,e);if(s.chroma<t){let o=s.chroma;for(;s.chroma<t;){a+=n?-1:1;let l=x.from(r,t,a);if(o>l.chroma||Math.abs(l.chroma-t)<.4)break;let f=Math.abs(l.chroma-t),p=Math.abs(s.chroma-t);f<p&&(s=l),o=Math.max(o,l.chroma)}}return a}var bt=class{primaryPaletteKeyColor(){return c.fromPalette({name:"primary_palette_key_color",palette:t=>t.primaryPalette,tone:t=>t.primaryPalette.keyColor.tone})}secondaryPaletteKeyColor(){return c.fromPalette({name:"secondary_palette_key_color",palette:t=>t.secondaryPalette,tone:t=>t.secondaryPalette.keyColor.tone})}tertiaryPaletteKeyColor(){return c.fromPalette({name:"tertiary_palette_key_color",palette:t=>t.tertiaryPalette,tone:t=>t.tertiaryPalette.keyColor.tone})}neutralPaletteKeyColor(){return c.fromPalette({name:"neutral_palette_key_color",palette:t=>t.neutralPalette,tone:t=>t.neutralPalette.keyColor.tone})}neutralVariantPaletteKeyColor(){return c.fromPalette({name:"neutral_variant_palette_key_color",palette:t=>t.neutralVariantPalette,tone:t=>t.neutralVariantPalette.keyColor.tone})}errorPaletteKeyColor(){return c.fromPalette({name:"error_palette_key_color",palette:t=>t.errorPalette,tone:t=>t.errorPalette.keyColor.tone})}background(){return c.fromPalette({name:"background",palette:t=>t.neutralPalette,tone:t=>t.isDark?6:98,isBackground:!0})}onBackground(){return c.fromPalette({name:"on_background",palette:t=>t.neutralPalette,tone:t=>t.isDark?90:10,background:t=>this.background(),contrastCurve:t=>new A(3,3,4.5,7)})}surface(){return c.fromPalette({name:"surface",palette:t=>t.neutralPalette,tone:t=>t.isDark?6:98,isBackground:!0})}surfaceDim(){return c.fromPalette({name:"surface_dim",palette:t=>t.neutralPalette,tone:t=>t.isDark?6:new A(87,87,80,75).get(t.contrastLevel),isBackground:!0})}surfaceBright(){return c.fromPalette({name:"surface_bright",palette:t=>t.neutralPalette,tone:t=>t.isDark?new A(24,24,29,34).get(t.contrastLevel):98,isBackground:!0})}surfaceContainerLowest(){return c.fromPalette({name:"surface_container_lowest",palette:t=>t.neutralPalette,tone:t=>t.isDark?new A(4,4,2,0).get(t.contrastLevel):100,isBackground:!0})}surfaceContainerLow(){return c.fromPalette({name:"surface_container_low",palette:t=>t.neutralPalette,tone:t=>t.isDark?new A(10,10,11,12).get(t.contrastLevel):new A(96,96,96,95).get(t.contrastLevel),isBackground:!0})}surfaceContainer(){return c.fromPalette({name:"surface_container",palette:t=>t.neutralPalette,tone:t=>t.isDark?new A(12,12,16,20).get(t.contrastLevel):new A(94,94,92,90).get(t.contrastLevel),isBackground:!0})}surfaceContainerHigh(){return c.fromPalette({name:"surface_container_high",palette:t=>t.neutralPalette,tone:t=>t.isDark?new A(17,17,21,25).get(t.contrastLevel):new A(92,92,88,85).get(t.contrastLevel),isBackground:!0})}surfaceContainerHighest(){return c.fromPalette({name:"surface_container_highest",palette:t=>t.neutralPalette,tone:t=>t.isDark?new A(22,22,26,30).get(t.contrastLevel):new A(90,90,84,80).get(t.contrastLevel),isBackground:!0})}onSurface(){return c.fromPalette({name:"on_surface",palette:t=>t.neutralPalette,tone:t=>t.isDark?90:10,background:t=>this.highestSurface(t),contrastCurve:t=>new A(4.5,7,11,21)})}surfaceVariant(){return c.fromPalette({name:"surface_variant",palette:t=>t.neutralVariantPalette,tone:t=>t.isDark?30:90,isBackground:!0})}onSurfaceVariant(){return c.fromPalette({name:"on_surface_variant",palette:t=>t.neutralVariantPalette,tone:t=>t.isDark?80:30,background:t=>this.highestSurface(t),contrastCurve:t=>new A(3,4.5,7,11)})}inverseSurface(){return c.fromPalette({name:"inverse_surface",palette:t=>t.neutralPalette,tone:t=>t.isDark?90:20,isBackground:!0})}inverseOnSurface(){return c.fromPalette({name:"inverse_on_surface",palette:t=>t.neutralPalette,tone:t=>t.isDark?20:95,background:t=>this.inverseSurface(),contrastCurve:t=>new A(4.5,7,11,21)})}outline(){return c.fromPalette({name:"outline",palette:t=>t.neutralVariantPalette,tone:t=>t.isDark?60:50,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1.5,3,4.5,7)})}outlineVariant(){return c.fromPalette({name:"outline_variant",palette:t=>t.neutralVariantPalette,tone:t=>t.isDark?30:80,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5)})}shadow(){return c.fromPalette({name:"shadow",palette:t=>t.neutralPalette,tone:t=>0})}scrim(){return c.fromPalette({name:"scrim",palette:t=>t.neutralPalette,tone:t=>0})}surfaceTint(){return c.fromPalette({name:"surface_tint",palette:t=>t.primaryPalette,tone:t=>t.isDark?80:40,isBackground:!0})}primary(){return c.fromPalette({name:"primary",palette:t=>t.primaryPalette,tone:t=>M(t)?t.isDark?100:0:t.isDark?80:40,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(3,4.5,7,7),toneDeltaPair:t=>new w(this.primaryContainer(),this.primary(),10,"nearer",!1)})}primaryDim(){}onPrimary(){return c.fromPalette({name:"on_primary",palette:t=>t.primaryPalette,tone:t=>M(t)?t.isDark?10:90:t.isDark?20:100,background:t=>this.primary(),contrastCurve:t=>new A(4.5,7,11,21)})}primaryContainer(){return c.fromPalette({name:"primary_container",palette:t=>t.primaryPalette,tone:t=>lt(t)?t.sourceColorHct.tone:M(t)?t.isDark?85:25:t.isDark?30:90,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.primaryContainer(),this.primary(),10,"nearer",!1)})}onPrimaryContainer(){return c.fromPalette({name:"on_primary_container",palette:t=>t.primaryPalette,tone:t=>lt(t)?c.foregroundTone(this.primaryContainer().tone(t),4.5):M(t)?t.isDark?0:100:t.isDark?90:30,background:t=>this.primaryContainer(),contrastCurve:t=>new A(3,4.5,7,11)})}inversePrimary(){return c.fromPalette({name:"inverse_primary",palette:t=>t.primaryPalette,tone:t=>t.isDark?40:80,background:t=>this.inverseSurface(),contrastCurve:t=>new A(3,4.5,7,7)})}secondary(){return c.fromPalette({name:"secondary",palette:t=>t.secondaryPalette,tone:t=>t.isDark?80:40,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(3,4.5,7,7),toneDeltaPair:t=>new w(this.secondaryContainer(),this.secondary(),10,"nearer",!1)})}secondaryDim(){}onSecondary(){return c.fromPalette({name:"on_secondary",palette:t=>t.secondaryPalette,tone:t=>M(t)?t.isDark?10:100:t.isDark?20:100,background:t=>this.secondary(),contrastCurve:t=>new A(4.5,7,11,21)})}secondaryContainer(){return c.fromPalette({name:"secondary_container",palette:t=>t.secondaryPalette,tone:t=>{let e=t.isDark?30:90;return M(t)?t.isDark?30:85:lt(t)?Pe(t.secondaryPalette.hue,t.secondaryPalette.chroma,e,!t.isDark):e},isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.secondaryContainer(),this.secondary(),10,"nearer",!1)})}onSecondaryContainer(){return c.fromPalette({name:"on_secondary_container",palette:t=>t.secondaryPalette,tone:t=>M(t)?t.isDark?90:10:lt(t)?c.foregroundTone(this.secondaryContainer().tone(t),4.5):t.isDark?90:30,background:t=>this.secondaryContainer(),contrastCurve:t=>new A(3,4.5,7,11)})}tertiary(){return c.fromPalette({name:"tertiary",palette:t=>t.tertiaryPalette,tone:t=>M(t)?t.isDark?90:25:t.isDark?80:40,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(3,4.5,7,7),toneDeltaPair:t=>new w(this.tertiaryContainer(),this.tertiary(),10,"nearer",!1)})}tertiaryDim(){}onTertiary(){return c.fromPalette({name:"on_tertiary",palette:t=>t.tertiaryPalette,tone:t=>M(t)?t.isDark?10:90:t.isDark?20:100,background:t=>this.tertiary(),contrastCurve:t=>new A(4.5,7,11,21)})}tertiaryContainer(){return c.fromPalette({name:"tertiary_container",palette:t=>t.tertiaryPalette,tone:t=>{if(M(t))return t.isDark?60:49;if(!lt(t))return t.isDark?30:90;let e=t.tertiaryPalette.getHct(t.sourceColorHct.tone);return st.fixIfDisliked(e).tone},isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.tertiaryContainer(),this.tertiary(),10,"nearer",!1)})}onTertiaryContainer(){return c.fromPalette({name:"on_tertiary_container",palette:t=>t.tertiaryPalette,tone:t=>M(t)?t.isDark?0:100:lt(t)?c.foregroundTone(this.tertiaryContainer().tone(t),4.5):t.isDark?90:30,background:t=>this.tertiaryContainer(),contrastCurve:t=>new A(3,4.5,7,11)})}error(){return c.fromPalette({name:"error",palette:t=>t.errorPalette,tone:t=>t.isDark?80:40,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(3,4.5,7,7),toneDeltaPair:t=>new w(this.errorContainer(),this.error(),10,"nearer",!1)})}errorDim(){}onError(){return c.fromPalette({name:"on_error",palette:t=>t.errorPalette,tone:t=>t.isDark?20:100,background:t=>this.error(),contrastCurve:t=>new A(4.5,7,11,21)})}errorContainer(){return c.fromPalette({name:"error_container",palette:t=>t.errorPalette,tone:t=>t.isDark?30:90,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.errorContainer(),this.error(),10,"nearer",!1)})}onErrorContainer(){return c.fromPalette({name:"on_error_container",palette:t=>t.errorPalette,tone:t=>M(t)?t.isDark?90:10:t.isDark?90:30,background:t=>this.errorContainer(),contrastCurve:t=>new A(3,4.5,7,11)})}primaryFixed(){return c.fromPalette({name:"primary_fixed",palette:t=>t.primaryPalette,tone:t=>M(t)?40:90,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.primaryFixed(),this.primaryFixedDim(),10,"lighter",!0)})}primaryFixedDim(){return c.fromPalette({name:"primary_fixed_dim",palette:t=>t.primaryPalette,tone:t=>M(t)?30:80,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.primaryFixed(),this.primaryFixedDim(),10,"lighter",!0)})}onPrimaryFixed(){return c.fromPalette({name:"on_primary_fixed",palette:t=>t.primaryPalette,tone:t=>M(t)?100:10,background:t=>this.primaryFixedDim(),secondBackground:t=>this.primaryFixed(),contrastCurve:t=>new A(4.5,7,11,21)})}onPrimaryFixedVariant(){return c.fromPalette({name:"on_primary_fixed_variant",palette:t=>t.primaryPalette,tone:t=>M(t)?90:30,background:t=>this.primaryFixedDim(),secondBackground:t=>this.primaryFixed(),contrastCurve:t=>new A(3,4.5,7,11)})}secondaryFixed(){return c.fromPalette({name:"secondary_fixed",palette:t=>t.secondaryPalette,tone:t=>M(t)?80:90,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.secondaryFixed(),this.secondaryFixedDim(),10,"lighter",!0)})}secondaryFixedDim(){return c.fromPalette({name:"secondary_fixed_dim",palette:t=>t.secondaryPalette,tone:t=>M(t)?70:80,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.secondaryFixed(),this.secondaryFixedDim(),10,"lighter",!0)})}onSecondaryFixed(){return c.fromPalette({name:"on_secondary_fixed",palette:t=>t.secondaryPalette,tone:t=>10,background:t=>this.secondaryFixedDim(),secondBackground:t=>this.secondaryFixed(),contrastCurve:t=>new A(4.5,7,11,21)})}onSecondaryFixedVariant(){return c.fromPalette({name:"on_secondary_fixed_variant",palette:t=>t.secondaryPalette,tone:t=>M(t)?25:30,background:t=>this.secondaryFixedDim(),secondBackground:t=>this.secondaryFixed(),contrastCurve:t=>new A(3,4.5,7,11)})}tertiaryFixed(){return c.fromPalette({name:"tertiary_fixed",palette:t=>t.tertiaryPalette,tone:t=>M(t)?40:90,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.tertiaryFixed(),this.tertiaryFixedDim(),10,"lighter",!0)})}tertiaryFixedDim(){return c.fromPalette({name:"tertiary_fixed_dim",palette:t=>t.tertiaryPalette,tone:t=>M(t)?30:80,isBackground:!0,background:t=>this.highestSurface(t),contrastCurve:t=>new A(1,1,3,4.5),toneDeltaPair:t=>new w(this.tertiaryFixed(),this.tertiaryFixedDim(),10,"lighter",!0)})}onTertiaryFixed(){return c.fromPalette({name:"on_tertiary_fixed",palette:t=>t.tertiaryPalette,tone:t=>M(t)?100:10,background:t=>this.tertiaryFixedDim(),secondBackground:t=>this.tertiaryFixed(),contrastCurve:t=>new A(4.5,7,11,21)})}onTertiaryFixedVariant(){return c.fromPalette({name:"on_tertiary_fixed_variant",palette:t=>t.tertiaryPalette,tone:t=>M(t)?90:30,background:t=>this.tertiaryFixedDim(),secondBackground:t=>this.tertiaryFixed(),contrastCurve:t=>new A(3,4.5,7,11)})}highestSurface(t){return t.isDark?this.surfaceBright():this.surfaceDim()}};/**
 * @license
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function k(r,t=0,e=100,n=1){let a=ne(r.hue,r.chroma*n,100,!0);return H(t,e,a)}function rt(r,t=0,e=100){let n=ne(r.hue,r.chroma,0,!1);return H(t,e,n)}function ne(r,t,e,n){let a=e,s=x.from(r,t,a);for(;s.chroma<t&&!(e<0||e>100);){e+=n?-1:1;let o=x.from(r,t,e);s.chroma<o.chroma&&(s=o,a=e)}return a}function T(r){return r===1.5?new A(1.5,1.5,3,5.5):r===3?new A(3,3,4.5,7):r===4.5?new A(4.5,4.5,7,11):r===6?new A(6,6,7,11):r===7?new A(7,7,11,21):r===9?new A(9,9,11,21):r===11?new A(11,11,21,21):r===21?new A(21,21,21,21):new A(r,r,7,21)}var wt=class extends bt{surface(){let t=c.fromPalette({name:"surface",palette:e=>e.neutralPalette,tone:e=>(super.surface().tone(e),e.platform==="phone"?e.isDark?4:x.isYellow(e.neutralPalette.hue)?99:e.variant===i.VIBRANT?97:98:0),isBackground:!0});return D(super.surface(),"2025",t)}surfaceDim(){let t=c.fromPalette({name:"surface_dim",palette:e=>e.neutralPalette,tone:e=>e.isDark?4:x.isYellow(e.neutralPalette.hue)?90:e.variant===i.VIBRANT?85:87,isBackground:!0,chromaMultiplier:e=>{if(!e.isDark){if(e.variant===i.NEUTRAL)return 2.5;if(e.variant===i.TONAL_SPOT)return 1.7;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?2.7:1.75;if(e.variant===i.VIBRANT)return 1.36}return 1}});return D(super.surfaceDim(),"2025",t)}surfaceBright(){let t=c.fromPalette({name:"surface_bright",palette:e=>e.neutralPalette,tone:e=>e.isDark?18:x.isYellow(e.neutralPalette.hue)?99:e.variant===i.VIBRANT?97:98,isBackground:!0,chromaMultiplier:e=>{if(e.isDark){if(e.variant===i.NEUTRAL)return 2.5;if(e.variant===i.TONAL_SPOT)return 1.7;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?2.7:1.75;if(e.variant===i.VIBRANT)return 1.36}return 1}});return D(super.surfaceBright(),"2025",t)}surfaceContainerLowest(){let t=c.fromPalette({name:"surface_container_lowest",palette:e=>e.neutralPalette,tone:e=>e.isDark?0:100,isBackground:!0});return D(super.surfaceContainerLowest(),"2025",t)}surfaceContainerLow(){let t=c.fromPalette({name:"surface_container_low",palette:e=>e.neutralPalette,tone:e=>e.platform==="phone"?e.isDark?6:x.isYellow(e.neutralPalette.hue)?98:e.variant===i.VIBRANT?95:96:15,isBackground:!0,chromaMultiplier:e=>{if(e.platform==="phone"){if(e.variant===i.NEUTRAL)return 1.3;if(e.variant===i.TONAL_SPOT)return 1.25;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?1.3:1.15;if(e.variant===i.VIBRANT)return 1.08}return 1}});return D(super.surfaceContainerLow(),"2025",t)}surfaceContainer(){let t=c.fromPalette({name:"surface_container",palette:e=>e.neutralPalette,tone:e=>e.platform==="phone"?e.isDark?9:x.isYellow(e.neutralPalette.hue)?96:e.variant===i.VIBRANT?92:94:20,isBackground:!0,chromaMultiplier:e=>{if(e.platform==="phone"){if(e.variant===i.NEUTRAL)return 1.6;if(e.variant===i.TONAL_SPOT)return 1.4;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?1.6:1.3;if(e.variant===i.VIBRANT)return 1.15}return 1}});return D(super.surfaceContainer(),"2025",t)}surfaceContainerHigh(){let t=c.fromPalette({name:"surface_container_high",palette:e=>e.neutralPalette,tone:e=>e.platform==="phone"?e.isDark?12:x.isYellow(e.neutralPalette.hue)?94:e.variant===i.VIBRANT?90:92:25,isBackground:!0,chromaMultiplier:e=>{if(e.platform==="phone"){if(e.variant===i.NEUTRAL)return 1.9;if(e.variant===i.TONAL_SPOT)return 1.5;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?1.95:1.45;if(e.variant===i.VIBRANT)return 1.22}return 1}});return D(super.surfaceContainerHigh(),"2025",t)}surfaceContainerHighest(){let t=c.fromPalette({name:"surface_container_highest",palette:e=>e.neutralPalette,tone:e=>e.isDark?15:x.isYellow(e.neutralPalette.hue)?92:e.variant===i.VIBRANT?88:90,isBackground:!0,chromaMultiplier:e=>e.variant===i.NEUTRAL?2.2:e.variant===i.TONAL_SPOT?1.7:e.variant===i.EXPRESSIVE?x.isYellow(e.neutralPalette.hue)?2.3:1.6:e.variant===i.VIBRANT?1.29:1});return D(super.surfaceContainerHighest(),"2025",t)}onSurface(){let t=c.fromPalette({name:"on_surface",palette:e=>e.neutralPalette,tone:e=>e.variant===i.VIBRANT?k(e.neutralPalette,0,100,1.1):c.getInitialToneFromBackground(n=>n.platform==="phone"?this.highestSurface(n):this.surfaceContainerHigh())(e),chromaMultiplier:e=>{if(e.platform==="phone"){if(e.variant===i.NEUTRAL)return 2.2;if(e.variant===i.TONAL_SPOT)return 1.7;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?e.isDark?3:2.3:1.6}return 1},background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.isDark&&e.platform==="phone"?T(11):T(9)});return D(super.onSurface(),"2025",t)}onSurfaceVariant(){let t=c.fromPalette({name:"on_surface_variant",palette:e=>e.neutralPalette,chromaMultiplier:e=>{if(e.platform==="phone"){if(e.variant===i.NEUTRAL)return 2.2;if(e.variant===i.TONAL_SPOT)return 1.7;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?e.isDark?3:2.3:1.6}return 1},background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.platform==="phone"?e.isDark?T(6):T(4.5):T(7)});return D(super.onSurfaceVariant(),"2025",t)}outline(){let t=c.fromPalette({name:"outline",palette:e=>e.neutralPalette,chromaMultiplier:e=>{if(e.platform==="phone"){if(e.variant===i.NEUTRAL)return 2.2;if(e.variant===i.TONAL_SPOT)return 1.7;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?e.isDark?3:2.3:1.6}return 1},background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.platform==="phone"?T(3):T(4.5)});return D(super.outline(),"2025",t)}outlineVariant(){let t=c.fromPalette({name:"outline_variant",palette:e=>e.neutralPalette,chromaMultiplier:e=>{if(e.platform==="phone"){if(e.variant===i.NEUTRAL)return 2.2;if(e.variant===i.TONAL_SPOT)return 1.7;if(e.variant===i.EXPRESSIVE)return x.isYellow(e.neutralPalette.hue)?e.isDark?3:2.3:1.6}return 1},background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.platform==="phone"?T(1.5):T(3)});return D(super.outlineVariant(),"2025",t)}inverseSurface(){let t=c.fromPalette({name:"inverse_surface",palette:e=>e.neutralPalette,tone:e=>e.isDark?98:4,isBackground:!0});return D(super.inverseSurface(),"2025",t)}inverseOnSurface(){let t=c.fromPalette({name:"inverse_on_surface",palette:e=>e.neutralPalette,background:e=>this.inverseSurface(),contrastCurve:e=>T(7)});return D(super.inverseOnSurface(),"2025",t)}primary(){let t=c.fromPalette({name:"primary",palette:e=>e.primaryPalette,tone:e=>e.variant===i.NEUTRAL?e.platform==="phone"?e.isDark?80:40:90:e.variant===i.TONAL_SPOT?e.platform==="phone"?e.isDark?80:k(e.primaryPalette):k(e.primaryPalette,0,90):e.variant===i.EXPRESSIVE?e.platform==="phone"?k(e.primaryPalette,0,x.isYellow(e.primaryPalette.hue)?25:x.isCyan(e.primaryPalette.hue)?88:98):k(e.primaryPalette):e.platform==="phone"?k(e.primaryPalette,0,x.isCyan(e.primaryPalette.hue)?88:98):k(e.primaryPalette),isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.platform==="phone"?T(4.5):T(7),toneDeltaPair:e=>e.platform==="phone"?new w(this.primaryContainer(),this.primary(),5,"relative_lighter",!0,"farther"):void 0});return D(super.primary(),"2025",t)}primaryDim(){return c.fromPalette({name:"primary_dim",palette:t=>t.primaryPalette,tone:t=>t.variant===i.NEUTRAL?85:t.variant===i.TONAL_SPOT?k(t.primaryPalette,0,90):k(t.primaryPalette),isBackground:!0,background:t=>this.surfaceContainerHigh(),contrastCurve:t=>T(4.5),toneDeltaPair:t=>new w(this.primaryDim(),this.primary(),5,"darker",!0,"farther")})}onPrimary(){let t=c.fromPalette({name:"on_primary",palette:e=>e.primaryPalette,background:e=>e.platform==="phone"?this.primary():this.primaryDim(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.onPrimary(),"2025",t)}primaryContainer(){let t=c.fromPalette({name:"primary_container",palette:e=>e.primaryPalette,tone:e=>e.platform==="watch"?30:e.variant===i.NEUTRAL?e.isDark?30:90:e.variant===i.TONAL_SPOT?e.isDark?rt(e.primaryPalette,35,93):k(e.primaryPalette,0,90):e.variant===i.EXPRESSIVE?e.isDark?k(e.primaryPalette,30,93):k(e.primaryPalette,78,x.isCyan(e.primaryPalette.hue)?88:90):e.isDark?rt(e.primaryPalette,66,93):k(e.primaryPalette,66,x.isCyan(e.primaryPalette.hue)?88:93),isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):void 0,toneDeltaPair:e=>e.platform==="phone"?void 0:new w(this.primaryContainer(),this.primaryDim(),10,"darker",!0,"farther"),contrastCurve:e=>e.platform==="phone"&&e.contrastLevel>0?T(1.5):void 0});return D(super.primaryContainer(),"2025",t)}onPrimaryContainer(){let t=c.fromPalette({name:"on_primary_container",palette:e=>e.primaryPalette,background:e=>this.primaryContainer(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.onPrimaryContainer(),"2025",t)}primaryFixed(){let t=c.fromPalette({name:"primary_fixed",palette:e=>e.primaryPalette,tone:e=>{let n=Object.assign({},e,{isDark:!1,contrastLevel:0});return this.primaryContainer().getTone(n)},isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):void 0,contrastCurve:e=>e.platform==="phone"&&e.contrastLevel>0?T(1.5):void 0});return D(super.primaryFixed(),"2025",t)}primaryFixedDim(){let t=c.fromPalette({name:"primary_fixed_dim",palette:e=>e.primaryPalette,tone:e=>this.primaryFixed().getTone(e),isBackground:!0,toneDeltaPair:e=>new w(this.primaryFixedDim(),this.primaryFixed(),5,"darker",!0,"exact")});return D(super.primaryFixedDim(),"2025",t)}onPrimaryFixed(){let t=c.fromPalette({name:"on_primary_fixed",palette:e=>e.primaryPalette,background:e=>this.primaryFixedDim(),contrastCurve:e=>T(7)});return D(super.onPrimaryFixed(),"2025",t)}onPrimaryFixedVariant(){let t=c.fromPalette({name:"on_primary_fixed_variant",palette:e=>e.primaryPalette,background:e=>this.primaryFixedDim(),contrastCurve:e=>T(4.5)});return D(super.onPrimaryFixedVariant(),"2025",t)}inversePrimary(){let t=c.fromPalette({name:"inverse_primary",palette:e=>e.primaryPalette,tone:e=>k(e.primaryPalette),background:e=>this.inverseSurface(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.inversePrimary(),"2025",t)}secondary(){let t=c.fromPalette({name:"secondary",palette:e=>e.secondaryPalette,tone:e=>e.platform==="watch"?e.variant===i.NEUTRAL?90:k(e.secondaryPalette,0,90):e.variant===i.NEUTRAL?e.isDark?rt(e.secondaryPalette,0,98):k(e.secondaryPalette):e.variant===i.VIBRANT?k(e.secondaryPalette,0,e.isDark?90:98):e.isDark?80:k(e.secondaryPalette),isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.platform==="phone"?T(4.5):T(7),toneDeltaPair:e=>e.platform==="phone"?new w(this.secondaryContainer(),this.secondary(),5,"relative_lighter",!0,"farther"):void 0});return D(super.secondary(),"2025",t)}secondaryDim(){return c.fromPalette({name:"secondary_dim",palette:t=>t.secondaryPalette,tone:t=>t.variant===i.NEUTRAL?85:k(t.secondaryPalette,0,90),isBackground:!0,background:t=>this.surfaceContainerHigh(),contrastCurve:t=>T(4.5),toneDeltaPair:t=>new w(this.secondaryDim(),this.secondary(),5,"darker",!0,"farther")})}onSecondary(){let t=c.fromPalette({name:"on_secondary",palette:e=>e.secondaryPalette,background:e=>e.platform==="phone"?this.secondary():this.secondaryDim(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.onSecondary(),"2025",t)}secondaryContainer(){let t=c.fromPalette({name:"secondary_container",palette:e=>e.secondaryPalette,tone:e=>e.platform==="watch"?30:e.variant===i.VIBRANT?e.isDark?rt(e.secondaryPalette,30,40):k(e.secondaryPalette,84,90):e.variant===i.EXPRESSIVE?e.isDark?15:k(e.secondaryPalette,90,95):e.isDark?25:90,isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):void 0,toneDeltaPair:e=>e.platform==="watch"?new w(this.secondaryContainer(),this.secondaryDim(),10,"darker",!0,"farther"):void 0,contrastCurve:e=>e.platform==="phone"&&e.contrastLevel>0?T(1.5):void 0});return D(super.secondaryContainer(),"2025",t)}onSecondaryContainer(){let t=c.fromPalette({name:"on_secondary_container",palette:e=>e.secondaryPalette,background:e=>this.secondaryContainer(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.onSecondaryContainer(),"2025",t)}secondaryFixed(){let t=c.fromPalette({name:"secondary_fixed",palette:e=>e.secondaryPalette,tone:e=>{let n=Object.assign({},e,{isDark:!1,contrastLevel:0});return this.secondaryContainer().getTone(n)},isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):void 0,contrastCurve:e=>e.platform==="phone"&&e.contrastLevel>0?T(1.5):void 0});return D(super.secondaryFixed(),"2025",t)}secondaryFixedDim(){let t=c.fromPalette({name:"secondary_fixed_dim",palette:e=>e.secondaryPalette,tone:e=>this.secondaryFixed().getTone(e),isBackground:!0,toneDeltaPair:e=>new w(this.secondaryFixedDim(),this.secondaryFixed(),5,"darker",!0,"exact")});return D(super.secondaryFixedDim(),"2025",t)}onSecondaryFixed(){let t=c.fromPalette({name:"on_secondary_fixed",palette:e=>e.secondaryPalette,background:e=>this.secondaryFixedDim(),contrastCurve:e=>T(7)});return D(super.onSecondaryFixed(),"2025",t)}onSecondaryFixedVariant(){let t=c.fromPalette({name:"on_secondary_fixed_variant",palette:e=>e.secondaryPalette,background:e=>this.secondaryFixedDim(),contrastCurve:e=>T(4.5)});return D(super.onSecondaryFixedVariant(),"2025",t)}tertiary(){let t=c.fromPalette({name:"tertiary",palette:e=>e.tertiaryPalette,tone:e=>e.platform==="watch"?e.variant===i.TONAL_SPOT?k(e.tertiaryPalette,0,90):k(e.tertiaryPalette):e.variant===i.EXPRESSIVE||e.variant===i.VIBRANT?k(e.tertiaryPalette,0,x.isCyan(e.tertiaryPalette.hue)?88:e.isDark?98:100):e.isDark?k(e.tertiaryPalette,0,98):k(e.tertiaryPalette),isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.platform==="phone"?T(4.5):T(7),toneDeltaPair:e=>e.platform==="phone"?new w(this.tertiaryContainer(),this.tertiary(),5,"relative_lighter",!0,"farther"):void 0});return D(super.tertiary(),"2025",t)}tertiaryDim(){return c.fromPalette({name:"tertiary_dim",palette:t=>t.tertiaryPalette,tone:t=>t.variant===i.TONAL_SPOT?k(t.tertiaryPalette,0,90):k(t.tertiaryPalette),isBackground:!0,background:t=>this.surfaceContainerHigh(),contrastCurve:t=>T(4.5),toneDeltaPair:t=>new w(this.tertiaryDim(),this.tertiary(),5,"darker",!0,"farther")})}onTertiary(){let t=c.fromPalette({name:"on_tertiary",palette:e=>e.tertiaryPalette,background:e=>e.platform==="phone"?this.tertiary():this.tertiaryDim(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.onTertiary(),"2025",t)}tertiaryContainer(){let t=c.fromPalette({name:"tertiary_container",palette:e=>e.tertiaryPalette,tone:e=>e.platform==="watch"?e.variant===i.TONAL_SPOT?k(e.tertiaryPalette,0,90):k(e.tertiaryPalette):e.variant===i.NEUTRAL?e.isDark?k(e.tertiaryPalette,0,93):k(e.tertiaryPalette,0,96):e.variant===i.TONAL_SPOT?k(e.tertiaryPalette,0,e.isDark?93:100):e.variant===i.EXPRESSIVE?k(e.tertiaryPalette,75,x.isCyan(e.tertiaryPalette.hue)?88:e.isDark?93:100):e.isDark?k(e.tertiaryPalette,0,93):k(e.tertiaryPalette,72,100),isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):void 0,toneDeltaPair:e=>e.platform==="watch"?new w(this.tertiaryContainer(),this.tertiaryDim(),10,"darker",!0,"farther"):void 0,contrastCurve:e=>e.platform==="phone"&&e.contrastLevel>0?T(1.5):void 0});return D(super.tertiaryContainer(),"2025",t)}onTertiaryContainer(){let t=c.fromPalette({name:"on_tertiary_container",palette:e=>e.tertiaryPalette,background:e=>this.tertiaryContainer(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.onTertiaryContainer(),"2025",t)}tertiaryFixed(){let t=c.fromPalette({name:"tertiary_fixed",palette:e=>e.tertiaryPalette,tone:e=>{let n=Object.assign({},e,{isDark:!1,contrastLevel:0});return this.tertiaryContainer().getTone(n)},isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):void 0,contrastCurve:e=>e.platform==="phone"&&e.contrastLevel>0?T(1.5):void 0});return D(super.tertiaryFixed(),"2025",t)}tertiaryFixedDim(){let t=c.fromPalette({name:"tertiary_fixed_dim",palette:e=>e.tertiaryPalette,tone:e=>this.tertiaryFixed().getTone(e),isBackground:!0,toneDeltaPair:e=>new w(this.tertiaryFixedDim(),this.tertiaryFixed(),5,"darker",!0,"exact")});return D(super.tertiaryFixedDim(),"2025",t)}onTertiaryFixed(){let t=c.fromPalette({name:"on_tertiary_fixed",palette:e=>e.tertiaryPalette,background:e=>this.tertiaryFixedDim(),contrastCurve:e=>T(7)});return D(super.onTertiaryFixed(),"2025",t)}onTertiaryFixedVariant(){let t=c.fromPalette({name:"on_tertiary_fixed_variant",palette:e=>e.tertiaryPalette,background:e=>this.tertiaryFixedDim(),contrastCurve:e=>T(4.5)});return D(super.onTertiaryFixedVariant(),"2025",t)}error(){let t=c.fromPalette({name:"error",palette:e=>e.errorPalette,tone:e=>e.platform==="phone"?e.isDark?rt(e.errorPalette,0,98):k(e.errorPalette):rt(e.errorPalette),isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):this.surfaceContainerHigh(),contrastCurve:e=>e.platform==="phone"?T(4.5):T(7),toneDeltaPair:e=>e.platform==="phone"?new w(this.errorContainer(),this.error(),5,"relative_lighter",!0,"farther"):void 0});return D(super.error(),"2025",t)}errorDim(){return c.fromPalette({name:"error_dim",palette:t=>t.errorPalette,tone:t=>rt(t.errorPalette),isBackground:!0,background:t=>this.surfaceContainerHigh(),contrastCurve:t=>T(4.5),toneDeltaPair:t=>new w(this.errorDim(),this.error(),5,"darker",!0,"farther")})}onError(){let t=c.fromPalette({name:"on_error",palette:e=>e.errorPalette,background:e=>e.platform==="phone"?this.error():this.errorDim(),contrastCurve:e=>e.platform==="phone"?T(6):T(7)});return D(super.onError(),"2025",t)}errorContainer(){let t=c.fromPalette({name:"error_container",palette:e=>e.errorPalette,tone:e=>e.platform==="watch"?30:e.isDark?rt(e.errorPalette,30,93):k(e.errorPalette,0,90),isBackground:!0,background:e=>e.platform==="phone"?this.highestSurface(e):void 0,toneDeltaPair:e=>e.platform==="watch"?new w(this.errorContainer(),this.errorDim(),10,"darker",!0,"farther"):void 0,contrastCurve:e=>e.platform==="phone"&&e.contrastLevel>0?T(1.5):void 0});return D(super.errorContainer(),"2025",t)}onErrorContainer(){let t=c.fromPalette({name:"on_error_container",palette:e=>e.errorPalette,background:e=>this.errorContainer(),contrastCurve:e=>e.platform==="phone"?T(4.5):T(7)});return D(super.onErrorContainer(),"2025",t)}surfaceVariant(){let t=Object.assign(this.surfaceContainerHighest().clone(),{name:"surface_variant"});return D(super.surfaceVariant(),"2025",t)}surfaceTint(){let t=Object.assign(this.primary().clone(),{name:"surface_tint"});return D(super.surfaceTint(),"2025",t)}background(){let t=Object.assign(this.surface().clone(),{name:"background"});return D(super.background(),"2025",t)}onBackground(){let t=Object.assign(this.onSurface().clone(),{name:"on_background",tone:e=>e.platform==="watch"?100:this.onSurface().getTone(e)});return D(super.onBackground(),"2025",t)}};/**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var u=class r{constructor(){this.allColors=[this.background(),this.onBackground(),this.surface(),this.surfaceDim(),this.surfaceBright(),this.surfaceContainerLowest(),this.surfaceContainerLow(),this.surfaceContainer(),this.surfaceContainerHigh(),this.surfaceContainerHighest(),this.onSurface(),this.onSurfaceVariant(),this.outline(),this.outlineVariant(),this.inverseSurface(),this.inverseOnSurface(),this.primary(),this.primaryDim(),this.onPrimary(),this.primaryContainer(),this.onPrimaryContainer(),this.primaryFixed(),this.primaryFixedDim(),this.onPrimaryFixed(),this.onPrimaryFixedVariant(),this.inversePrimary(),this.secondary(),this.secondaryDim(),this.onSecondary(),this.secondaryContainer(),this.onSecondaryContainer(),this.secondaryFixed(),this.secondaryFixedDim(),this.onSecondaryFixed(),this.onSecondaryFixedVariant(),this.tertiary(),this.tertiaryDim(),this.onTertiary(),this.tertiaryContainer(),this.onTertiaryContainer(),this.tertiaryFixed(),this.tertiaryFixedDim(),this.onTertiaryFixed(),this.onTertiaryFixedVariant(),this.error(),this.errorDim(),this.onError(),this.errorContainer(),this.onErrorContainer()].filter(t=>t!==void 0)}highestSurface(t){return r.colorSpec.highestSurface(t)}primaryPaletteKeyColor(){return r.colorSpec.primaryPaletteKeyColor()}secondaryPaletteKeyColor(){return r.colorSpec.secondaryPaletteKeyColor()}tertiaryPaletteKeyColor(){return r.colorSpec.tertiaryPaletteKeyColor()}neutralPaletteKeyColor(){return r.colorSpec.neutralPaletteKeyColor()}neutralVariantPaletteKeyColor(){return r.colorSpec.neutralVariantPaletteKeyColor()}errorPaletteKeyColor(){return r.colorSpec.errorPaletteKeyColor()}background(){return r.colorSpec.background()}onBackground(){return r.colorSpec.onBackground()}surface(){return r.colorSpec.surface()}surfaceDim(){return r.colorSpec.surfaceDim()}surfaceBright(){return r.colorSpec.surfaceBright()}surfaceContainerLowest(){return r.colorSpec.surfaceContainerLowest()}surfaceContainerLow(){return r.colorSpec.surfaceContainerLow()}surfaceContainer(){return r.colorSpec.surfaceContainer()}surfaceContainerHigh(){return r.colorSpec.surfaceContainerHigh()}surfaceContainerHighest(){return r.colorSpec.surfaceContainerHighest()}onSurface(){return r.colorSpec.onSurface()}surfaceVariant(){return r.colorSpec.surfaceVariant()}onSurfaceVariant(){return r.colorSpec.onSurfaceVariant()}outline(){return r.colorSpec.outline()}outlineVariant(){return r.colorSpec.outlineVariant()}inverseSurface(){return r.colorSpec.inverseSurface()}inverseOnSurface(){return r.colorSpec.inverseOnSurface()}shadow(){return r.colorSpec.shadow()}scrim(){return r.colorSpec.scrim()}surfaceTint(){return r.colorSpec.surfaceTint()}primary(){return r.colorSpec.primary()}primaryDim(){return r.colorSpec.primaryDim()}onPrimary(){return r.colorSpec.onPrimary()}primaryContainer(){return r.colorSpec.primaryContainer()}onPrimaryContainer(){return r.colorSpec.onPrimaryContainer()}inversePrimary(){return r.colorSpec.inversePrimary()}primaryFixed(){return r.colorSpec.primaryFixed()}primaryFixedDim(){return r.colorSpec.primaryFixedDim()}onPrimaryFixed(){return r.colorSpec.onPrimaryFixed()}onPrimaryFixedVariant(){return r.colorSpec.onPrimaryFixedVariant()}secondary(){return r.colorSpec.secondary()}secondaryDim(){return r.colorSpec.secondaryDim()}onSecondary(){return r.colorSpec.onSecondary()}secondaryContainer(){return r.colorSpec.secondaryContainer()}onSecondaryContainer(){return r.colorSpec.onSecondaryContainer()}secondaryFixed(){return r.colorSpec.secondaryFixed()}secondaryFixedDim(){return r.colorSpec.secondaryFixedDim()}onSecondaryFixed(){return r.colorSpec.onSecondaryFixed()}onSecondaryFixedVariant(){return r.colorSpec.onSecondaryFixedVariant()}tertiary(){return r.colorSpec.tertiary()}tertiaryDim(){return r.colorSpec.tertiaryDim()}onTertiary(){return r.colorSpec.onTertiary()}tertiaryContainer(){return r.colorSpec.tertiaryContainer()}onTertiaryContainer(){return r.colorSpec.onTertiaryContainer()}tertiaryFixed(){return r.colorSpec.tertiaryFixed()}tertiaryFixedDim(){return r.colorSpec.tertiaryFixedDim()}onTertiaryFixed(){return r.colorSpec.onTertiaryFixed()}onTertiaryFixedVariant(){return r.colorSpec.onTertiaryFixedVariant()}error(){return r.colorSpec.error()}errorDim(){return r.colorSpec.errorDim()}onError(){return r.colorSpec.onError()}errorContainer(){return r.colorSpec.errorContainer()}onErrorContainer(){return r.colorSpec.onErrorContainer()}static highestSurface(t){return r.colorSpec.highestSurface(t)}};u.contentAccentToneDelta=15;u.colorSpec=new wt;u.primaryPaletteKeyColor=u.colorSpec.primaryPaletteKeyColor();u.secondaryPaletteKeyColor=u.colorSpec.secondaryPaletteKeyColor();u.tertiaryPaletteKeyColor=u.colorSpec.tertiaryPaletteKeyColor();u.neutralPaletteKeyColor=u.colorSpec.neutralPaletteKeyColor();u.neutralVariantPaletteKeyColor=u.colorSpec.neutralVariantPaletteKeyColor();u.background=u.colorSpec.background();u.onBackground=u.colorSpec.onBackground();u.surface=u.colorSpec.surface();u.surfaceDim=u.colorSpec.surfaceDim();u.surfaceBright=u.colorSpec.surfaceBright();u.surfaceContainerLowest=u.colorSpec.surfaceContainerLowest();u.surfaceContainerLow=u.colorSpec.surfaceContainerLow();u.surfaceContainer=u.colorSpec.surfaceContainer();u.surfaceContainerHigh=u.colorSpec.surfaceContainerHigh();u.surfaceContainerHighest=u.colorSpec.surfaceContainerHighest();u.onSurface=u.colorSpec.onSurface();u.surfaceVariant=u.colorSpec.surfaceVariant();u.onSurfaceVariant=u.colorSpec.onSurfaceVariant();u.inverseSurface=u.colorSpec.inverseSurface();u.inverseOnSurface=u.colorSpec.inverseOnSurface();u.outline=u.colorSpec.outline();u.outlineVariant=u.colorSpec.outlineVariant();u.shadow=u.colorSpec.shadow();u.scrim=u.colorSpec.scrim();u.surfaceTint=u.colorSpec.surfaceTint();u.primary=u.colorSpec.primary();u.onPrimary=u.colorSpec.onPrimary();u.primaryContainer=u.colorSpec.primaryContainer();u.onPrimaryContainer=u.colorSpec.onPrimaryContainer();u.inversePrimary=u.colorSpec.inversePrimary();u.secondary=u.colorSpec.secondary();u.onSecondary=u.colorSpec.onSecondary();u.secondaryContainer=u.colorSpec.secondaryContainer();u.onSecondaryContainer=u.colorSpec.onSecondaryContainer();u.tertiary=u.colorSpec.tertiary();u.onTertiary=u.colorSpec.onTertiary();u.tertiaryContainer=u.colorSpec.tertiaryContainer();u.onTertiaryContainer=u.colorSpec.onTertiaryContainer();u.error=u.colorSpec.error();u.onError=u.colorSpec.onError();u.errorContainer=u.colorSpec.errorContainer();u.onErrorContainer=u.colorSpec.onErrorContainer();u.primaryFixed=u.colorSpec.primaryFixed();u.primaryFixedDim=u.colorSpec.primaryFixedDim();u.onPrimaryFixed=u.colorSpec.onPrimaryFixed();u.onPrimaryFixedVariant=u.colorSpec.onPrimaryFixedVariant();u.secondaryFixed=u.colorSpec.secondaryFixed();u.secondaryFixedDim=u.colorSpec.secondaryFixedDim();u.onSecondaryFixed=u.colorSpec.onSecondaryFixed();u.onSecondaryFixedVariant=u.colorSpec.onSecondaryFixedVariant();u.tertiaryFixed=u.colorSpec.tertiaryFixed();u.tertiaryFixedDim=u.colorSpec.tertiaryFixedDim();u.onTertiaryFixed=u.colorSpec.onTertiaryFixed();u.onTertiaryFixedVariant=u.colorSpec.onTertiaryFixedVariant();/**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var F=class r{static maybeFallbackSpecVersion(t,e){switch(e){case i.EXPRESSIVE:case i.VIBRANT:case i.TONAL_SPOT:case i.NEUTRAL:return t;default:return"2021"}}constructor(t){this.sourceColorArgb=t.sourceColorHct.toInt(),this.variant=t.variant,this.contrastLevel=t.contrastLevel,this.isDark=t.isDark,this.platform=t.platform??"phone",this.specVersion=r.maybeFallbackSpecVersion(t.specVersion??"2021",this.variant),this.sourceColorHct=t.sourceColorHct,this.primaryPalette=t.primaryPalette??ht(this.specVersion).getPrimaryPalette(this.variant,t.sourceColorHct,this.isDark,this.platform,this.contrastLevel),this.secondaryPalette=t.secondaryPalette??ht(this.specVersion).getSecondaryPalette(this.variant,t.sourceColorHct,this.isDark,this.platform,this.contrastLevel),this.tertiaryPalette=t.tertiaryPalette??ht(this.specVersion).getTertiaryPalette(this.variant,t.sourceColorHct,this.isDark,this.platform,this.contrastLevel),this.neutralPalette=t.neutralPalette??ht(this.specVersion).getNeutralPalette(this.variant,t.sourceColorHct,this.isDark,this.platform,this.contrastLevel),this.neutralVariantPalette=t.neutralVariantPalette??ht(this.specVersion).getNeutralVariantPalette(this.variant,t.sourceColorHct,this.isDark,this.platform,this.contrastLevel),this.errorPalette=t.errorPalette??ht(this.specVersion).getErrorPalette(this.variant,t.sourceColorHct,this.isDark,this.platform,this.contrastLevel)??C.fromHueAndChroma(25,84),this.colors=new u}toString(){return`Scheme: variant=${i[this.variant]}, mode=${this.isDark?"dark":"light"}, platform=${this.platform}, contrastLevel=${this.contrastLevel.toFixed(1)}, seed=${this.sourceColorHct.toString()}, specVersion=${this.specVersion}`}static getPiecewiseHue(t,e,n){let a=Math.min(e.length-1,n.length),s=t.hue;for(let o=0;o<a;o++)if(s>=e[o]&&s<e[o+1])return _(n[o]);return s}static getRotatedHue(t,e,n){let a=r.getPiecewiseHue(t,e,n);return Math.min(e.length-1,n.length)<=0&&(a=0),_(t.hue+a)}getArgb(t){return t.getArgb(this)}getHct(t){return t.getHct(this)}get primaryPaletteKeyColor(){return this.getArgb(this.colors.primaryPaletteKeyColor())}get secondaryPaletteKeyColor(){return this.getArgb(this.colors.secondaryPaletteKeyColor())}get tertiaryPaletteKeyColor(){return this.getArgb(this.colors.tertiaryPaletteKeyColor())}get neutralPaletteKeyColor(){return this.getArgb(this.colors.neutralPaletteKeyColor())}get neutralVariantPaletteKeyColor(){return this.getArgb(this.colors.neutralVariantPaletteKeyColor())}get errorPaletteKeyColor(){return this.getArgb(this.colors.errorPaletteKeyColor())}get background(){return this.getArgb(this.colors.background())}get onBackground(){return this.getArgb(this.colors.onBackground())}get surface(){return this.getArgb(this.colors.surface())}get surfaceDim(){return this.getArgb(this.colors.surfaceDim())}get surfaceBright(){return this.getArgb(this.colors.surfaceBright())}get surfaceContainerLowest(){return this.getArgb(this.colors.surfaceContainerLowest())}get surfaceContainerLow(){return this.getArgb(this.colors.surfaceContainerLow())}get surfaceContainer(){return this.getArgb(this.colors.surfaceContainer())}get surfaceContainerHigh(){return this.getArgb(this.colors.surfaceContainerHigh())}get surfaceContainerHighest(){return this.getArgb(this.colors.surfaceContainerHighest())}get onSurface(){return this.getArgb(this.colors.onSurface())}get surfaceVariant(){return this.getArgb(this.colors.surfaceVariant())}get onSurfaceVariant(){return this.getArgb(this.colors.onSurfaceVariant())}get inverseSurface(){return this.getArgb(this.colors.inverseSurface())}get inverseOnSurface(){return this.getArgb(this.colors.inverseOnSurface())}get outline(){return this.getArgb(this.colors.outline())}get outlineVariant(){return this.getArgb(this.colors.outlineVariant())}get shadow(){return this.getArgb(this.colors.shadow())}get scrim(){return this.getArgb(this.colors.scrim())}get surfaceTint(){return this.getArgb(this.colors.surfaceTint())}get primary(){return this.getArgb(this.colors.primary())}get primaryDim(){let t=this.colors.primaryDim();if(t===void 0)throw new Error("`primaryDim` color is undefined prior to 2025 spec.");return this.getArgb(t)}get onPrimary(){return this.getArgb(this.colors.onPrimary())}get primaryContainer(){return this.getArgb(this.colors.primaryContainer())}get onPrimaryContainer(){return this.getArgb(this.colors.onPrimaryContainer())}get primaryFixed(){return this.getArgb(this.colors.primaryFixed())}get primaryFixedDim(){return this.getArgb(this.colors.primaryFixedDim())}get onPrimaryFixed(){return this.getArgb(this.colors.onPrimaryFixed())}get onPrimaryFixedVariant(){return this.getArgb(this.colors.onPrimaryFixedVariant())}get inversePrimary(){return this.getArgb(this.colors.inversePrimary())}get secondary(){return this.getArgb(this.colors.secondary())}get secondaryDim(){let t=this.colors.secondaryDim();if(t===void 0)throw new Error("`secondaryDim` color is undefined prior to 2025 spec.");return this.getArgb(t)}get onSecondary(){return this.getArgb(this.colors.onSecondary())}get secondaryContainer(){return this.getArgb(this.colors.secondaryContainer())}get onSecondaryContainer(){return this.getArgb(this.colors.onSecondaryContainer())}get secondaryFixed(){return this.getArgb(this.colors.secondaryFixed())}get secondaryFixedDim(){return this.getArgb(this.colors.secondaryFixedDim())}get onSecondaryFixed(){return this.getArgb(this.colors.onSecondaryFixed())}get onSecondaryFixedVariant(){return this.getArgb(this.colors.onSecondaryFixedVariant())}get tertiary(){return this.getArgb(this.colors.tertiary())}get tertiaryDim(){let t=this.colors.tertiaryDim();if(t===void 0)throw new Error("`tertiaryDim` color is undefined prior to 2025 spec.");return this.getArgb(t)}get onTertiary(){return this.getArgb(this.colors.onTertiary())}get tertiaryContainer(){return this.getArgb(this.colors.tertiaryContainer())}get onTertiaryContainer(){return this.getArgb(this.colors.onTertiaryContainer())}get tertiaryFixed(){return this.getArgb(this.colors.tertiaryFixed())}get tertiaryFixedDim(){return this.getArgb(this.colors.tertiaryFixedDim())}get onTertiaryFixed(){return this.getArgb(this.colors.onTertiaryFixed())}get onTertiaryFixedVariant(){return this.getArgb(this.colors.onTertiaryFixedVariant())}get error(){return this.getArgb(this.colors.error())}get errorDim(){let t=this.colors.errorDim();if(t===void 0)throw new Error("`errorDim` color is undefined prior to 2025 spec.");return this.getArgb(t)}get onError(){return this.getArgb(this.colors.onError())}get errorContainer(){return this.getArgb(this.colors.errorContainer())}get onErrorContainer(){return this.getArgb(this.colors.onErrorContainer())}};F.DEFAULT_SPEC_VERSION="2021";F.DEFAULT_PLATFORM="phone";var vt=class{getPrimaryPalette(t,e,n,a,s){switch(t){case i.CONTENT:case i.FIDELITY:return C.fromHueAndChroma(e.hue,e.chroma);case i.FRUIT_SALAD:return C.fromHueAndChroma(_(e.hue-50),48);case i.MONOCHROME:return C.fromHueAndChroma(e.hue,0);case i.NEUTRAL:return C.fromHueAndChroma(e.hue,12);case i.RAINBOW:return C.fromHueAndChroma(e.hue,48);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,36);case i.EXPRESSIVE:return C.fromHueAndChroma(_(e.hue+240),40);case i.VIBRANT:return C.fromHueAndChroma(e.hue,200);default:throw new Error(`Unsupported variant: ${t}`)}}getSecondaryPalette(t,e,n,a,s){switch(t){case i.CONTENT:case i.FIDELITY:return C.fromHueAndChroma(e.hue,Math.max(e.chroma-32,e.chroma*.5));case i.FRUIT_SALAD:return C.fromHueAndChroma(_(e.hue-50),36);case i.MONOCHROME:return C.fromHueAndChroma(e.hue,0);case i.NEUTRAL:return C.fromHueAndChroma(e.hue,8);case i.RAINBOW:return C.fromHueAndChroma(e.hue,16);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,16);case i.EXPRESSIVE:return C.fromHueAndChroma(F.getRotatedHue(e,[0,21,51,121,151,191,271,321,360],[45,95,45,20,45,90,45,45,45]),24);case i.VIBRANT:return C.fromHueAndChroma(F.getRotatedHue(e,[0,41,61,101,131,181,251,301,360],[18,15,10,12,15,18,15,12,12]),24);default:throw new Error(`Unsupported variant: ${t}`)}}getTertiaryPalette(t,e,n,a,s){switch(t){case i.CONTENT:return C.fromHct(st.fixIfDisliked(new Pt(e).analogous(3,6)[2]));case i.FIDELITY:return C.fromHct(st.fixIfDisliked(new Pt(e).complement));case i.FRUIT_SALAD:return C.fromHueAndChroma(e.hue,36);case i.MONOCHROME:return C.fromHueAndChroma(e.hue,0);case i.NEUTRAL:return C.fromHueAndChroma(e.hue,16);case i.RAINBOW:case i.TONAL_SPOT:return C.fromHueAndChroma(_(e.hue+60),24);case i.EXPRESSIVE:return C.fromHueAndChroma(F.getRotatedHue(e,[0,21,51,121,151,191,271,321,360],[120,120,20,45,20,15,20,120,120]),32);case i.VIBRANT:return C.fromHueAndChroma(F.getRotatedHue(e,[0,41,61,101,131,181,251,301,360],[35,30,20,25,30,35,30,25,25]),32);default:throw new Error(`Unsupported variant: ${t}`)}}getNeutralPalette(t,e,n,a,s){switch(t){case i.CONTENT:case i.FIDELITY:return C.fromHueAndChroma(e.hue,e.chroma/8);case i.FRUIT_SALAD:return C.fromHueAndChroma(e.hue,10);case i.MONOCHROME:return C.fromHueAndChroma(e.hue,0);case i.NEUTRAL:return C.fromHueAndChroma(e.hue,2);case i.RAINBOW:return C.fromHueAndChroma(e.hue,0);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,6);case i.EXPRESSIVE:return C.fromHueAndChroma(_(e.hue+15),8);case i.VIBRANT:return C.fromHueAndChroma(e.hue,10);default:throw new Error(`Unsupported variant: ${t}`)}}getNeutralVariantPalette(t,e,n,a,s){switch(t){case i.CONTENT:return C.fromHueAndChroma(e.hue,e.chroma/8+4);case i.FIDELITY:return C.fromHueAndChroma(e.hue,e.chroma/8+4);case i.FRUIT_SALAD:return C.fromHueAndChroma(e.hue,16);case i.MONOCHROME:return C.fromHueAndChroma(e.hue,0);case i.NEUTRAL:return C.fromHueAndChroma(e.hue,2);case i.RAINBOW:return C.fromHueAndChroma(e.hue,0);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,8);case i.EXPRESSIVE:return C.fromHueAndChroma(_(e.hue+15),12);case i.VIBRANT:return C.fromHueAndChroma(e.hue,12);default:throw new Error(`Unsupported variant: ${t}`)}}getErrorPalette(t,e,n,a,s){}},zt=class r extends vt{getPrimaryPalette(t,e,n,a,s){switch(t){case i.NEUTRAL:return C.fromHueAndChroma(e.hue,a==="phone"?x.isBlue(e.hue)?12:8:x.isBlue(e.hue)?16:12);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,a==="phone"&&n?26:32);case i.EXPRESSIVE:return C.fromHueAndChroma(e.hue,a==="phone"?n?36:48:40);case i.VIBRANT:return C.fromHueAndChroma(e.hue,a==="phone"?74:56);default:return super.getPrimaryPalette(t,e,n,a,s)}}getSecondaryPalette(t,e,n,a,s){switch(t){case i.NEUTRAL:return C.fromHueAndChroma(e.hue,a==="phone"?x.isBlue(e.hue)?6:4:x.isBlue(e.hue)?10:6);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,16);case i.EXPRESSIVE:return C.fromHueAndChroma(F.getRotatedHue(e,[0,105,140,204,253,278,300,333,360],[-160,155,-100,96,-96,-156,-165,-160]),a==="phone"&&n?16:24);case i.VIBRANT:return C.fromHueAndChroma(F.getRotatedHue(e,[0,38,105,140,333,360],[-14,10,-14,10,-14]),a==="phone"?56:36);default:return super.getSecondaryPalette(t,e,n,a,s)}}getTertiaryPalette(t,e,n,a,s){switch(t){case i.NEUTRAL:return C.fromHueAndChroma(F.getRotatedHue(e,[0,38,105,161,204,278,333,360],[-32,26,10,-39,24,-15,-32]),a==="phone"?20:36);case i.TONAL_SPOT:return C.fromHueAndChroma(F.getRotatedHue(e,[0,20,71,161,333,360],[-40,48,-32,40,-32]),a==="phone"?28:32);case i.EXPRESSIVE:return C.fromHueAndChroma(F.getRotatedHue(e,[0,105,140,204,253,278,300,333,360],[-165,160,-105,101,-101,-160,-170,-165]),48);case i.VIBRANT:return C.fromHueAndChroma(F.getRotatedHue(e,[0,38,71,105,140,161,253,333,360],[-72,35,24,-24,62,50,62,-72]),56);default:return super.getTertiaryPalette(t,e,n,a,s)}}static getExpressiveNeutralHue(t){return F.getRotatedHue(t,[0,71,124,253,278,300,360],[10,0,10,0,10,0])}static getExpressiveNeutralChroma(t,e,n){let a=r.getExpressiveNeutralHue(t);return n==="phone"?e?x.isYellow(a)?6:14:18:12}static getVibrantNeutralHue(t){return F.getRotatedHue(t,[0,38,105,140,333,360],[-14,10,-14,10,-14])}static getVibrantNeutralChroma(t,e){let n=r.getVibrantNeutralHue(t);return e==="phone"||x.isBlue(n)?28:20}getNeutralPalette(t,e,n,a,s){switch(t){case i.NEUTRAL:return C.fromHueAndChroma(e.hue,a==="phone"?1.4:6);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,a==="phone"?5:10);case i.EXPRESSIVE:return C.fromHueAndChroma(r.getExpressiveNeutralHue(e),r.getExpressiveNeutralChroma(e,n,a));case i.VIBRANT:return C.fromHueAndChroma(r.getVibrantNeutralHue(e),r.getVibrantNeutralChroma(e,a));default:return super.getNeutralPalette(t,e,n,a,s)}}getNeutralVariantPalette(t,e,n,a,s){switch(t){case i.NEUTRAL:return C.fromHueAndChroma(e.hue,(a==="phone"?1.4:6)*2.2);case i.TONAL_SPOT:return C.fromHueAndChroma(e.hue,(a==="phone"?5:10)*1.7);case i.EXPRESSIVE:let o=r.getExpressiveNeutralHue(e),l=r.getExpressiveNeutralChroma(e,n,a);return C.fromHueAndChroma(o,l*(o>=105&&o<125?1.6:2.3));case i.VIBRANT:let f=r.getVibrantNeutralHue(e),p=r.getVibrantNeutralChroma(e,a);return C.fromHueAndChroma(f,p*1.29);default:return super.getNeutralVariantPalette(t,e,n,a,s)}}getErrorPalette(t,e,n,a,s){let o=F.getPiecewiseHue(e,[0,3,13,23,33,43,153,273,360],[12,22,32,12,22,32,22,12]);switch(t){case i.NEUTRAL:return C.fromHueAndChroma(o,a==="phone"?50:40);case i.TONAL_SPOT:return C.fromHueAndChroma(o,a==="phone"?60:48);case i.EXPRESSIVE:return C.fromHueAndChroma(o,a==="phone"?64:48);case i.VIBRANT:return C.fromHueAndChroma(o,a==="phone"?80:60);default:return super.getErrorPalette(t,e,n,a,s)}}},Ce=new vt,Se=new zt;function ht(r){return r==="2025"?Se:Ce}/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var Ft=class extends F{constructor(t,e,n,a=F.DEFAULT_SPEC_VERSION,s=F.DEFAULT_PLATFORM){super({sourceColorHct:t,variant:i.TONAL_SPOT,contrastLevel:n,isDark:e,platform:s,specVersion:a})}};/**
 * @license
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var xe={desired:4,fallbackColorARGB:4282549748,filter:!0};function Ae(r,t){return r.score>t.score?-1:r.score<t.score?1:0}var Z=class r{constructor(){}static score(t,e){let{desired:n,fallbackColorARGB:a,filter:s}={...xe,...e},o=[],l=new Array(360).fill(0),f=0;for(let[y,m]of t.entries()){let h=x.fromInt(y);o.push(h);let P=Math.floor(h.hue);l[P]+=m,f+=m}let p=new Array(360).fill(0);for(let y=0;y<360;y++){let m=l[y]/f;for(let h=y-14;h<y+16;h++){let P=ut(h);p[P]+=m}}let d=new Array;for(let y of o){let m=ut(Math.round(y.hue)),h=p[m];if(s&&(y.chroma<r.CUTOFF_CHROMA||h<=r.CUTOFF_EXCITED_PROPORTION))continue;let P=h*100*r.WEIGHT_PROPORTION,b=y.chroma<r.TARGET_CHROMA?r.WEIGHT_CHROMA_BELOW:r.WEIGHT_CHROMA_ABOVE,v=(y.chroma-r.TARGET_CHROMA)*b,I=P+v;d.push({hct:y,score:I})}d.sort(Ae);let S=[];for(let y=90;y>=15;y--){S.length=0;for(let{hct:m}of d)if(S.find(P=>Ot(m.hue,P.hue)<y)||S.push(m),S.length>=n)break;if(S.length>=n)break}let g=[];S.length===0&&g.push(a);for(let y of S)g.push(y.toInt());return g}};Z.TARGET_CHROMA=48;Z.WEIGHT_PROPORTION=.7;Z.WEIGHT_CHROMA_ABOVE=.3;Z.WEIGHT_CHROMA_BELOW=.1;Z.CUTOFF_CHROMA=5;Z.CUTOFF_EXCITED_PROPORTION=.01;/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function Gt(r){let t=pt(r),e=dt(r),n=gt(r),a=[t.toString(16),e.toString(16),n.toString(16)];for(let[s,o]of a.entries())o.length===1&&(a[s]="0"+o);return"#"+a.join("")}function oe(r){r=r.replace("#","");let t=r.length===3,e=r.length===6,n=r.length===8;if(!t&&!e&&!n)throw new Error("unexpected hex "+r);let a=0,s=0,o=0;return t?(a=Q(r.slice(0,1).repeat(2)),s=Q(r.slice(1,2).repeat(2)),o=Q(r.slice(2,3).repeat(2))):e?(a=Q(r.slice(0,2)),s=Q(r.slice(2,4)),o=Q(r.slice(4,6))):n&&(a=Q(r.slice(2,4)),s=Q(r.slice(4,6)),o=Q(r.slice(6,8))),(255<<24|(a&255)<<16|(s&255)<<8|o&255)>>>0}function Q(r){return parseInt(r,16)}/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *//**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var Te=["primary","onPrimary","primaryContainer","onPrimaryContainer","secondary","onSecondary","secondaryContainer","onSecondaryContainer","tertiary","onTertiary","tertiaryContainer","onTertiaryContainer","error","onError","errorContainer","onErrorContainer","surface","onSurface","surfaceVariant","onSurfaceVariant","surfaceDim","surfaceBright","surfaceContainerLowest","surfaceContainerLow","surfaceContainer","surfaceContainerHigh","surfaceContainerHighest","outline","outlineVariant","inverseSurface","inverseOnSurface","scrim"],ga=document.documentElement,Et=document.currentScript?.getAttribute("data-color-source");window.__gcMd3eColor&&window.__gcMd3eColor.dispose();var It=null,nt=null,Yt=null,at=null,Kt=0;function De(r){return"--md3e-"+r.replace(/[A-Z]/g,t=>"-"+t.toLowerCase())}function ie(r,t){let e=new Ft(x.fromInt(oe(r)),t,0,"2021");return Te.map(n=>De(n)+":"+Gt(e[n])+";").join("")}function Ct(r){if(r!==null&&!/^#[0-9a-f]{6}$/i.test(r))return!1;if(r===It)return!0;if(r===null)return nt&&nt.remove(),nt=null,It=null,!0;try{let t='html.dark:root,:root[data-theme="dark"]{'+ie(r,!0)+'}:root:not(.dark):not([data-theme="dark"]){'+ie(r,!1)+"}";return nt||(nt=document.createElement("style"),nt.id="gc-md3e-system-palette",document.head.appendChild(nt)),nt.textContent=t,It=r,!0}catch{return!1}}function Xt(){Yt!==null&&clearInterval(Yt),at&&at.remove(),Ct(null),window.removeEventListener("pagehide",Xt),delete window.__gcMd3eSetAccent,delete window.__gcMd3eColor,delete window.__gcMd3eReceiveAccent}window.__gcMd3eSetAccent=Ct;window.__gcMd3eColor={dispose:Xt,get seed(){return It},level:"Medium"};window.__gcMd3eReceiveAccent=(r,t)=>{if(!Number.isSafeInteger(t)||t>Date.now()+5e3||Date.now()-t>15e3){Ct(null);return}Kt=Date.now(),Ct(r)};function se(){Kt&&Date.now()-Kt>15e3&&Ct(null),at&&(at.remove(),at=null);let r=document.createElement("script");r.src=Et+"?v="+Date.now(),at=r,r.onload=r.onerror=()=>{r.remove(),at===r&&(at=null)},document.head.appendChild(r)}Et&&/^file:\/\//i.test(Et)&&!/[?#]/.test(Et)&&(se(),Yt=setInterval(se,2e3));window.addEventListener("pagehide",Xt);})();
'@
$script:Md3eColorWorkerPs = @'
param([Parameter(Mandatory=$true)][string]$State)
$ErrorActionPreference = 'Stop'
$State = [IO.Path]::GetFullPath($State)
$sha = [Security.Cryptography.SHA256]::Create()
try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($State.ToLowerInvariant())))).Replace('-', '') }
finally { $sha.Dispose() }
$gate = New-Object Threading.Mutex($false, ('Local\GamewareCleanerMedium-' + $key))
if (-not $gate.WaitOne(0)) { $gate.Dispose(); exit }
try {
    $settings = $null
    $enabled = Join-Path $State 'enabled.txt'
    $feed = Join-Path $State 'accent.js'
    while ((Test-Path -LiteralPath $enabled) -and [IO.File]::ReadAllText($enabled).Trim() -eq '1') {
        $seed = 'null'
        try {
            if (-not $settings) {
                $null = [Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime]
                $settings = New-Object Windows.UI.ViewManagement.UISettings
            }
            $color = $settings.GetColorValue([Windows.UI.ViewManagement.UIColorType]::Accent)
            if ($color.A -ne 0) { $seed = '"#{0:x2}{1:x2}{2:x2}"' -f $color.R, $color.G, $color.B }
        } catch { $settings = $null }
        $timestamp = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        $text = 'window.__gcMd3eReceiveAccent && window.__gcMd3eReceiveAccent(' + $seed + ',' + $timestamp + ');'
        $temp = Join-Path $State ('accent-' + $PID + '.tmp')
        [IO.File]::WriteAllText($temp, $text, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $feed) { [IO.File]::Replace($temp, $feed, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp, $feed) }
        Start-Sleep -Seconds 2
    }
} finally { $gate.ReleaseMutex(); $gate.Dispose() }
'@
# Shared installer functions. ASCII; no administrative access is required here.
function Get-MediumState {
    param([string]$InstallRoot)
    $rootPath = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\').ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rootPath)))).Replace('-', '').Substring(0, 16).ToLowerInvariant() }
    finally { $sha.Dispose() }
    $state = Join-Path $env:LOCALAPPDATA ('GamewareCleaner\Medium\' + $key)
    $worker = Join-Path $state 'worker.ps1'
    $command = '"' + (Join-Path $PSHOME 'powershell.exe') + '" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $worker + '" -State "' + $state + '"'
    return @{ Path = $state; Worker = $worker; RunName = ('GamewareCleaner-Medium-' + $key); RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Command = $command; Feed = ([Uri](Join-Path $state 'accent.js')).AbsoluteUri }
}

function Set-MediumWorker {
    param([string]$InstallRoot, [string]$BackupPath, [bool]$Enabled)
    $state = Get-MediumState $InstallRoot
    $prior = Get-ItemProperty -LiteralPath $state.RunKey -Name $state.RunName -ErrorAction SilentlyContinue
    $hasRun = $prior -and ($prior.PSObject.Properties.Name -contains $state.RunName)
    $runValue = if ($hasRun) { [string]$prior.($state.RunName) } else { $null }
    if ($hasRun -and $runValue -cne $state.Command) { throw 'Medium startup entry was changed externally; refusing to overwrite' }
    $hasState = Test-Path -LiteralPath $state.Path
    $snapshot = [ordered]@{ statePath = $state.Path; hadState = [bool]$hasState; hadRun = [bool]$hasRun; runValue = $runValue }
    [IO.File]::WriteAllText((Join-Path $BackupPath 'medium-worker.json'), ($snapshot | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if ($hasState) { Copy-Item -LiteralPath $state.Path -Destination (Join-Path $BackupPath 'medium-state.previous') -Recurse -Force }
    try {
        if ($hasState) {
            [IO.File]::WriteAllText((Join-Path $state.Path 'enabled.txt'), '0')
            Start-Sleep -Milliseconds 2500
        }
        if ($Enabled) {
            New-Item -ItemType Directory -Path $state.Path -Force | Out-Null
            [IO.File]::WriteAllText($state.Worker, ($script:Md3eColorWorkerPs -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $state.Path 'enabled.txt'), '1')
            if (-not (Test-Path -LiteralPath $state.RunKey)) { New-Item -Path $state.RunKey -Force | Out-Null }
            New-ItemProperty -LiteralPath $state.RunKey -Name $state.RunName -Value $state.Command -PropertyType String -Force | Out-Null
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $state.Worker + '" -State "' + $state.Path + '"') -WindowStyle Hidden | Out-Null
        } elseif ($hasRun) { Remove-ItemProperty -LiteralPath $state.RunKey -Name $state.RunName }
    } catch {
        Restore-MediumWorker $InstallRoot $BackupPath
        throw
    }
}

function Restore-MediumWorker {
    param([string]$InstallRoot, [string]$BackupPath)
    $file = Join-Path $BackupPath 'medium-worker.json'
    if (-not (Test-Path -LiteralPath $file)) { return }
    $snapshot = [IO.File]::ReadAllText($file) | ConvertFrom-Json
    $state = Get-MediumState $InstallRoot
    if ($snapshot.statePath -cne $state.Path) { throw 'Medium state path mismatch; restore under the original Windows user' }
    $current = Get-ItemProperty -LiteralPath $state.RunKey -Name $state.RunName -ErrorAction SilentlyContinue
    if ($current -and $current.($state.RunName) -cne $state.Command) { throw 'Medium startup entry changed externally; refusing to overwrite' }
    if (Test-Path -LiteralPath $state.Path) {
        [IO.File]::WriteAllText((Join-Path $state.Path 'enabled.txt'), '0')
        Start-Sleep -Milliseconds 2500
        # Both paths are resolved and checked before moving the generated state directory.
        $resolved = [IO.Path]::GetFullPath($state.Path)
        $base = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'GamewareCleaner\Medium')).TrimEnd('\') + '\'
        $destination = [IO.Path]::GetFullPath((Join-Path $BackupPath ('medium-state.displaced-' + [Guid]::NewGuid().ToString('N'))))
        if (-not $resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or -not $destination.StartsWith(([IO.Path]::GetFullPath($BackupPath).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Medium state move outside allowed roots' }
        Move-Item -LiteralPath $resolved -Destination $destination
    }
    if ($snapshot.hadState) { Copy-Item -LiteralPath (Join-Path $BackupPath 'medium-state.previous') -Destination $state.Path -Recurse -Force }
    if ($snapshot.hadRun) {
        if (-not (Test-Path -LiteralPath $state.RunKey)) { New-Item -Path $state.RunKey -Force | Out-Null }
        New-ItemProperty -LiteralPath $state.RunKey -Name $state.RunName -Value $snapshot.runValue -PropertyType String -Force | Out-Null
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $state.Worker + '" -State "' + $state.Path + '"') -WindowStyle Hidden | Out-Null
    } elseif ($current) { Remove-ItemProperty -LiteralPath $state.RunKey -Name $state.RunName }
}
function Set-MediumRenderer {
    param([string]$WorkDir, [bool]$Enabled)
    $index = Join-Path $WorkDir 'index.html'
    $html = Read-Utf8 $index
    $scriptFile = Join-Path $WorkDir 'md3e-system-color.js'
    $changed = $false
    $next = [regex]::Replace($html, '[ \t]*<script src="\./md3e-system-color\.js"[^>]*></script>[ \t]*(?:\r?\n)?', '')
    if ($Enabled) {
        $expected = Convert-ToLf $script:Md3eSystemColorJs
        if (-not (Test-Path -LiteralPath $scriptFile) -or (Read-Utf8 $scriptFile) -cne $expected) {
            Write-Utf8NoBom $scriptFile $expected
            $changed = $true
        }
        $feed = (Get-MediumState $installRoot).Feed
        $nl = if ($html.Contains("`r`n")) { "`r`n" } else { "`n" }
        if (-not $next.Contains('</head>')) { throw 'Missing head in index.html' }
        $next = $next.Replace('</head>', ('  <script src="./md3e-system-color.js" data-color-source="' + $feed + '"></script>' + $nl + '</head>'))
    } elseif (Test-Path -LiteralPath $scriptFile) { Remove-Item -LiteralPath $scriptFile -Force; $changed = $true }
    if ($next -cne $html) { Write-Utf8NoBom $index $next; $changed = $true }
    return $changed
}
# gc-medium-embedded:end

function Invoke-RendererPatches {
    param([string]$WorkDir, [string]$AppVersion)

    $sentinel = Join-Path $WorkDir 'gameware-cleaner.json'
    if (Test-Path -LiteralPath $sentinel) {
        $info = Read-Utf8 $sentinel | ConvertFrom-Json
        $changed = $false
        if ($AutoPauseIdleTime) {
            $changed = Patch-IdleTimePause $WorkDir
            $info.patches = @($info.patches | Where-Object { $_ -ne 'idle-time-pause' }) + 'idle-time-pause'
        }
        if ($Md3eTheme) {
            $css = Join-Path $WorkDir 'md3e-theme.css'
            $expected = Convert-ToLf $script:Md3eThemeCss
            if (-not (Test-Path -LiteralPath $css) -or (Read-Utf8 $css) -cne $expected -or -not (Read-Utf8 (Join-Path $WorkDir 'index.html')).Contains('./md3e-theme.css')) {
                Write-Utf8NoBom $css $expected
                Add-IndexStyleLink (Join-Path $WorkDir 'index.html') 'md3e-theme.css'
                $changed = $true
            }
            $info.patches = @($info.patches | Where-Object { $_ -ne 'md3e-theme' }) + 'md3e-theme'
            if (Set-MediumRenderer $WorkDir ([bool]$FollowSystemAccent)) { $changed = $true }
            $info.patches = @($info.patches | Where-Object { $_ -ne 'md3e-system-color' })
            if ([bool]$FollowSystemAccent) { $info.patches += 'md3e-system-color' }
            $info | Add-Member -NotePropertyName md3eFollowSystemAccent -NotePropertyValue ([bool]$FollowSystemAccent) -Force
        }
        if ($changed) {
            $info.scriptVersion = $script:ScriptVersion
            Write-Utf8NoBom $sentinel ($info | ConvertTo-Json -Depth 5)
            return 'applied'
        }
        Write-Ok 'renderer.asar 已经由本脚本处理过（检测到 gameware-cleaner.json），跳过补丁'
        return 'already'
    }
    $hasAdblock = Test-Path -LiteralPath (Join-Path $WorkDir 'adblock.js')
    $hasLayout = Test-Path -LiteralPath (Join-Path $WorkDir 'game-detail-layout.css')
    $hasHeader = Test-Path -LiteralPath (Join-Path $WorkDir 'header-height-fixed.css')
    if ($hasAdblock -and $hasLayout -and $hasHeader) {
        $legacyChanged = $false
        if ($AutoPauseIdleTime -and (Patch-IdleTimePause $WorkDir)) { $legacyChanged = $true }
        if ($Md3eTheme) {
            $themeFile = Join-Path $WorkDir 'md3e-theme.css'
            $themeText = Convert-ToLf $script:Md3eThemeCss
            if (-not (Test-Path -LiteralPath $themeFile) -or (Read-Utf8 $themeFile) -cne $themeText -or -not (Read-Utf8 (Join-Path $WorkDir 'index.html')).Contains('./md3e-theme.css')) {
                Write-Utf8NoBom $themeFile $themeText
                Add-IndexStyleLink (Join-Path $WorkDir 'index.html') 'md3e-theme.css'
                $legacyChanged = $true
            }
            if (Set-MediumRenderer $WorkDir ([bool]$FollowSystemAccent)) { $legacyChanged = $true }
        }
        if ($legacyChanged) { return 'applied' }
        Write-WarnLine 'renderer.asar 看起来是旧版手动/脚本处理过的状态（adblock.js 和两个 CSS 都在），跳过渲染层补丁'
        return 'legacy'
    }

    $indexPath = Join-Path $WorkDir 'index.html'
    if (-not (Test-Path -LiteralPath $indexPath)) { throw '找不到 index.html' }
    if ($BlockAds) {
    # 1) 写入 adblock.js，并在 index.html 里引用
    $adblockPath = Join-Path $WorkDir 'adblock.js'
    if (-not (Test-Path -LiteralPath $adblockPath)) {
        Write-Utf8NoBom $adblockPath (Convert-ToLf $script:AdblockJs)
        Write-Log '已写入 adblock.js'
    }
    $indexPath = Join-Path $WorkDir 'index.html'
    if (-not (Test-Path -LiteralPath $indexPath)) { throw 'renderer.asar 里找不到 index.html' }
    Add-IndexScriptTag $indexPath

    # 2) IPC 层拦截
    $ipcPattern = '([A-Za-z_$][\w$]*)=\(\.\.\.([A-Za-z_$][\w$]*)\)=>window\.leigodSimplify\.invoke\(\.\.\.\2\.map\(([A-Za-z_$][\w$]*)\)\)'
    $ipcChunk = Find-JsChunkByRegex -WorkDir $WorkDir -Pattern $ipcPattern -MustContain @('get-game-tools', 'window.leigodSimplify.invoke')
    if (-not $ipcChunk) {
        throw '找不到负责 IPC 调用的 chunk（含 get-game-tools 和 simplify.invoke 包装），雷神版本可能变了'
    }
    Write-Log ('IPC chunk：' + (Get-UnderRootRel $ipcChunk $WorkDir))
    $ipcText = Get-JsText $ipcChunk
    $ipcText = Patch-IpcAdGuard $ipcText
    Set-JsText $ipcChunk $ipcText
    Write-Ok 'IPC 层广告/工具/外链拦截已安装'

    }
    # 3) 社区侧栏 + 底部推广条（同一个 gameDetail chunk）
    $gdChunk = Find-JsChunk -WorkDir $WorkDir -MustContain @('name:"gameDetail"', 'game-detail-tools')
    if (-not $gdChunk) { throw '找不到 gameDetail chunk（含 game-detail-tools）' }
    Write-Log ('游戏详情 chunk：' + (Get-UnderRootRel $gdChunk $WorkDir))
    $gdText = Get-JsText $gdChunk
    if ($HideCommunitySidebar) {
    $r = Patch-GameDetailSidebar $gdText
    $r.Log | ForEach-Object { Write-Log ('  - ' + $_) }
    $gdText = $r.Text
    }
    if ($HideBottomPromoBar) {
    $r = Patch-GameDetailBottomBanner $gdText
    $r.Log | ForEach-Object { Write-Log ('  - ' + $_) }
    $gdText = $r.Text
    }
    if ($StopButtonPauses) {
    $r = Patch-GameDetailStopButton $gdText
    $r.Log | ForEach-Object { Write-Log ('  - ' + $_) }
    $gdText = $r.Text
    }
    Set-JsText $gdChunk $gdText
    Write-Ok '详情页补丁已按所选项目处理'

    # 4) 详情页排版 + 顶栏高度 CSS
    if ($HideBottomPromoBar) {
    $layoutCss = Join-Path $WorkDir 'game-detail-layout.css'
    Write-Utf8NoBom $layoutCss (Convert-ToLf $script:GameDetailLayoutCss)
    Add-IndexStyleLink $indexPath 'game-detail-layout.css'
    Write-Ok '详情页排版 CSS 已安装'

    }
    if ($PinHeaderHeight) {
    $headerCss = Join-Path $WorkDir 'header-height-fixed.css'
    Write-Utf8NoBom $headerCss (Convert-ToLf $script:HeaderHeightCss)
    Add-IndexStyleLink $indexPath 'header-height-fixed.css'
    Write-Ok '顶栏高度固定 CSS 已安装'

    }
    if ($AutoPauseIdleTime) { $null = Patch-IdleTimePause $WorkDir }

    # 4b) MD3E 主题（交互默认 Y）。必须最后安装，让它的 <link> 排在
    #     game-detail-layout.css / header-height-fixed.css 之后才能盖住它们。
    if ($Md3eTheme) {
        $md3eCss = Join-Path $WorkDir 'md3e-theme.css'
        Write-Utf8NoBom $md3eCss (Convert-ToLf $script:Md3eThemeCss)
        Add-IndexStyleLink $indexPath 'md3e-theme.css'
        $null = Set-MediumRenderer $WorkDir ([bool]$FollowSystemAccent)
        Write-Ok 'MD3E 主题 CSS 已安装（最后一个渲染层补丁）'
    }

    if ($HideHomeBanner) {
    # 5) 首页/游戏列表大横幅
    $homeChunk = Find-JsChunk -WorkDir $WorkDir -MustContain @('name:"NavContentLayout"', 'name:"NavAccRencent"')
    if (-not $homeChunk) { throw '找不到首页/游戏列表 chunk（NavContentLayout / NavAccRencent）' }
    Write-Log ('首页 chunk：' + (Get-UnderRootRel $homeChunk $WorkDir))
    $homeText = Get-JsText $homeChunk
    $r = Patch-HomeBanner $homeText
    $r.Log | ForEach-Object { Write-Log ('  - ' + $_) }
    Set-JsText $homeChunk $r.Text
    Write-Ok '首页/游戏列表大横幅已移除'

    }
    if ($HideHeaderPromo) {
    # 6) 顶栏口号 + 搜索框轮播
    $headerChunk = Find-JsChunk -WorkDir $WorkDir -MustContain @('name:"HeaderGameSearch"', 'leigod_header_slogn')
    if (-not $headerChunk) { throw '找不到顶栏 chunk（HeaderGameSearch / leigod_header_slogn）' }
    Write-Log ('顶栏 chunk：' + (Get-UnderRootRel $headerChunk $WorkDir))
    Write-Log '  这一步要对约 3 MB 的顶栏 chunk 做正则扫描，是全流程最慢的一步，通常要 1 分钟左右，请耐心等待，不是卡住了。' 'DarkGray'
    $headerText = Get-JsText $headerChunk
    $r = Patch-HeaderAds $headerText
    $r.Log | ForEach-Object { Write-Log ('  - ' + $_) }
    Set-JsText $headerChunk $r.Text
    Write-Ok '顶栏轮播口号、搜索框轮播游戏名已移除'

    }
    # 7) 写入标记文件
    $patches = @()
    if ($BlockAds) { $patches += @('adblock', 'ipc-ad-guard') }
    if ($HideCommunitySidebar) { $patches += 'community-sidebar' }
    if ($HideBottomPromoBar) { $patches += @('bottom-promo-bar', 'game-detail-layout') }
    if ($StopButtonPauses) { $patches += 'stop-button-pause' }
    if ($HideHomeBanner) { $patches += 'home-banner' }
    if ($HideHeaderPromo) { $patches += 'header-ads' }
    if ($PinHeaderHeight) { $patches += 'header-height' }
    if ($AutoPauseIdleTime) { $patches += 'idle-time-pause' }
    if ($Md3eTheme) { $patches += 'md3e-theme' }
    if ($Md3eTheme -and $FollowSystemAccent) { $patches += 'md3e-system-color' }
    $info = [ordered]@{
        tool = 'Gameware-Cleaner'
        app = 'leigod'
        scriptVersion = $script:ScriptVersion
        appVersion = $AppVersion
        patchedAt = (Get-Date).ToString('o')
        md3eFollowSystemAccent = [bool]$FollowSystemAccent
        patches = $patches
    }
    Write-Utf8NoBom $sentinel ($info | ConvertTo-Json -Depth 5)
    Write-Log '已写入 gameware-cleaner.json 标记'

    return 'applied'
}

# ===========================================================================
# 精简 / 硬链接 / 停更
# ===========================================================================

function Get-RootItem {
    param([string]$InstallRoot, [string]$Relative)
    if ([System.IO.Path]::IsPathRooted($Relative)) { throw ('拒绝绝对路径：' + $Relative) }
    $relative = $Relative.TrimStart('\', '/')
    $full = [System.IO.Path]::GetFullPath((Join-Path $InstallRoot $relative))
    $prefix = $InstallRoot.TrimEnd('\') + '\'
    if (-not ($full.Equals($InstallRoot, [StringComparison]::OrdinalIgnoreCase) -or
              $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw ('拒绝访问安装目录以外的路径：' + $full)
    }
    return $full
}

function Expand-RootItems {
    param([string]$InstallRoot, [string]$Pattern)
    $hasWildcard = $Pattern.IndexOfAny([char[]]@('*', '?')) -ge 0
    if ($hasWildcard) {
        $parent = Split-Path -Parent $Pattern
        if ([string]::IsNullOrEmpty($parent)) { $parent = '.' }
        $leaf = Split-Path -Leaf $Pattern
        $fullParent = Get-RootItem $InstallRoot $parent
        return @(Get-ChildItem -Path (Join-Path $fullParent $leaf) -Force -ErrorAction SilentlyContinue)
    }
    $full = Get-RootItem $InstallRoot $Pattern
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($item) { return @($item) }
    return @()
}

function Get-UniqueQuarantinePath {
    param([string]$QuarantineDir, [string]$Relative)
    $dst = Join-Path $QuarantineDir $Relative
    if (-not (Test-Path -LiteralPath $dst)) { return $dst }
    $base = [IO.Path]::GetFileNameWithoutExtension($dst)
    $ext = [IO.Path]::GetExtension($dst)
    $n = 1
    do {
        $dst = Join-Path (Split-Path -Parent $dst) ('{0}.{1}{2}' -f $base, $n, $ext)
        $n++
    } while (Test-Path -LiteralPath $dst)
    return $dst
}

function Get-ItemSize {
    param($Item)
    if ($Item.PSIsContainer) {
        return [int64]((Get-ChildItem -LiteralPath $Item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum)
    }
    return [int64]$Item.Length
}

function Invoke-LeigodQuarantine {
    param([string]$InstallRoot, [string]$BackupPath, $Manifest)
    $specs = @(
        'resources\client_tools',
        'resources\tools\resources\tool_*',
        'resources\leishenSdk\tool_*.exe',
        'resources\leishenSdk\leigod_pubg_tool.exe',
        'resources\leishenSdk\pc_yyb',
        'resources\leishenSdk\*sslproxy.zip',
        'resources\leishenSdk\log',
        'resources\llogs',
        'update\*',
        'resources\static\*.tmp',
        'resources\icons\*.tmp'
    )
    $quarantineDir = Join-Path $BackupPath 'quarantine'
    foreach ($spec in $specs) {
        $items = @(Expand-RootItems $InstallRoot $spec | Sort-Object { $_.FullName.Length } -Descending)
        if ($items.Count -eq 0) {
            Write-Log ('  未找到：' + $spec)
            continue
        }
        foreach ($item in $items) {
            if (-not $item) { continue }
            $rel = (Get-UnderRootRel $item.FullName $InstallRoot)
            $size = Get-ItemSize $item
            $dst = Get-UniqueQuarantinePath $quarantineDir $rel
            try {
                $parent = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory -Force -Path $parent | Out-Null
                }
                Move-Item -LiteralPath $item.FullName -Destination $dst -Force
                $script:QuarantineBytes += $size
                $Manifest.quarantine += [ordered]@{
                    relative = $rel
                    type = if ($item.PSIsContainer) { 'Directory' } else { 'File' }
                    bytes = $size
                    quarantinedTo = $dst
                }
                Write-Log ('  隔离：' + $rel + '（' + (Format-Size $size) + '）')
            } catch {
                Write-WarnLine ('隔离失败：' + $rel + '：' + $_.Exception.Message)
            }
        }
    }
}

function Test-AlreadyHardLinked {
    param([string]$LinkPath, [string]$TargetPath)
    try {
        $out = @(& fsutil hardlink list $LinkPath 2>$null)
        if ($out.Count -eq 0) { return $false }
        $targetRel = $TargetPath.Substring($TargetPath.IndexOf(':') + 2)
        $joined = $out -join "`n"
        return ($joined.IndexOf($targetRel, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    } catch {
        return $false
    }
}

function Invoke-LeigodHardlinks {
    param([string]$InstallRoot, $Manifest)
    $pairs = @(
        @{ target = 'leigod.exe'; link = 'resources\tools\leigod-tool.exe' },
        @{ target = 'd3dcompiler_47.dll'; link = 'resources\tools\d3dcompiler_47.dll' },
        @{ target = 'ffmpeg.dll'; link = 'resources\tools\ffmpeg.dll' },
        @{ target = 'icudtl.dat'; link = 'resources\tools\icudtl.dat' },
        @{ target = 'libEGL.dll'; link = 'resources\tools\libEGL.dll' },
        @{ target = 'libGLESv2.dll'; link = 'resources\tools\libGLESv2.dll' },
        @{ target = 'resources.pak'; link = 'resources\tools\resources.pak' },
        @{ target = 'snapshot_blob.bin'; link = 'resources\tools\snapshot_blob.bin' },
        @{ target = 'v8_context_snapshot.bin'; link = 'resources\tools\v8_context_snapshot.bin' },
        @{ target = 'vk_swiftshader.dll'; link = 'resources\tools\vk_swiftshader.dll' },
        @{ target = 'vk_swiftshader_icd.json'; link = 'resources\tools\vk_swiftshader_icd.json' },
        @{ target = 'vulkan-1.dll'; link = 'resources\tools\vulkan-1.dll' },
        @{ target = 'chrome_100_percent.pak'; link = 'resources\tools\chrome_100_percent.pak' },
        @{ target = 'chrome_200_percent.pak'; link = 'resources\tools\chrome_200_percent.pak' }
    )
    foreach ($pair in $pairs) {
        $target = Get-RootItem $InstallRoot $pair.target
        $link = Get-RootItem $InstallRoot $pair.link
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            Write-Log ('  硬链接跳过（目标不存在）：' + $pair.target)
            continue
        }
        if (-not (Test-Path -LiteralPath $link -PathType Leaf)) {
            Write-Log ('  硬链接跳过（文件不存在）：' + $pair.link)
            continue
        }
        $targetInfo = Get-Item -LiteralPath $target -Force
        $linkInfo = Get-Item -LiteralPath $link -Force
        if ($targetInfo.Length -ne $linkInfo.Length) {
            Write-WarnLine ('硬链接跳过（大小不同）：' + $pair.link)
            continue
        }
        if (Test-AlreadyHardLinked $link $target) {
            Write-Log ('  已硬链接：' + $pair.link)
            continue
        }
        if ((Get-Sha256 $target) -ne (Get-Sha256 $link)) {
            Write-WarnLine ('硬链接跳过（内容不同）：' + $pair.link)
            continue
        }
        $saved = [int64]$linkInfo.Length
        try {
            Remove-Item -LiteralPath $link -Force
            New-Item -ItemType HardLink -Path $link -Target $target | Out-Null
            $script:HardlinkSavedBytes += $saved
            $Manifest.hardlink += [ordered]@{ target = $pair.target; link = $pair.link; bytes = $saved }
            Write-Log ('  硬链接：' + $pair.link + ' -> ' + $pair.target + '（省 ' + (Format-Size $saved) + '）')
        } catch {
            if (-not (Test-Path -LiteralPath $link)) {
                Copy-Item -LiteralPath $target -Destination $link -Force
            }
            Write-WarnLine ('硬链接失败，已恢复原文件：' + $pair.link + '：' + $_.Exception.Message)
        }
    }
}

function Invoke-LeigodUpdateFreeze {
    param([string]$InstallRoot, [string]$BackupPath, $Manifest)
    if ($KeepUpdates) {
        Write-Log '按 -KeepUpdates 跳过停更'
        return
    }

    try {
        $updater = Get-RootItem $InstallRoot 'resources\leishenSdk\updater.exe'
        $disabled = Get-RootItem $InstallRoot 'resources\leishenSdk\updater.exe.disabled'
        if (Test-Path -LiteralPath $updater) {
            if (Test-Path -LiteralPath $disabled) {
                # 更新把 updater.exe 重新放回来了，旧的 .disabled 先移进隔离区
                $rel = 'resources\leishenSdk\updater.exe.disabled'
                $quarantineDir = Join-Path $BackupPath 'quarantine'
                $dst = Get-UniqueQuarantinePath $quarantineDir $rel
                $parent = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                $oldBytes = (Get-Item -LiteralPath $disabled -Force).Length
                Move-Item -LiteralPath $disabled -Destination $dst -Force
                $Manifest.quarantine += [ordered]@{ relative = $rel; type = 'File'; bytes = $oldBytes; quarantinedTo = $dst }
                Write-Log '旧的 updater.exe.disabled 已移入隔离区'
            }
            Move-Item -LiteralPath $updater -Destination $disabled -Force
            $Manifest.rename += [ordered]@{ from = 'resources\leishenSdk\updater.exe'; to = 'resources\leishenSdk\updater.exe.disabled' }
            Write-Log '已停用 updater.exe（改名为 updater.exe.disabled）'
        } elseif (Test-Path -LiteralPath $disabled) {
            Write-Log 'updater.exe 已经是停用状态'
        } else {
            Write-WarnLine '没有找到 resources\leishenSdk\updater.exe，跳过改名'
        }
    } catch {
        Write-WarnLine ('停用 updater.exe 失败（不影响去广告）：' + $_.Exception.Message)
    }

    if ($NoHosts) {
        Write-Log '按 -NoHosts 跳过 hosts 修改'
        return
    }

    try {
        $hostsPath = Get-HostsPath
    $hostsBackup = Join-Path $BackupPath 'hosts.original'
    if (-not (Test-Path -LiteralPath $hostsBackup)) {
        Copy-Item -LiteralPath $hostsPath -Destination $hostsBackup -Force
        $Manifest.hostsBackup = $hostsBackup
    }
    $begin = '# >>> Gameware-Cleaner: leigod >>>'
    $end = '# <<< Gameware-Cleaner: leigod <<<'
    $domainList = @('resources.leigodtech.com', 'dev-update.leigod.com')
    $text = [System.IO.File]::ReadAllText($hostsPath, [System.Text.Encoding]::Default)
    $missing = @()
    foreach ($d in $domainList) {
        if ($text -notmatch [regex]::Escape($d)) { $missing += $d }
    }
    if ($missing.Count -eq 0) {
        Write-Log 'hosts 已包含全部雷神停更条目'
    } else {
        $add = "`r`n" + $begin + "`r`n"
        foreach ($d in $missing) {
            $add += ('0.0.0.0 ' + $d) + "`r`n"
            $Manifest.hostsBlock += [ordered]@{ domain = $d }
            Write-Log ('hosts 屏蔽：' + $d)
        }
        $add += $end + "`r`n"
        [System.IO.File]::AppendAllText($hostsPath, $add, [System.Text.Encoding]::ASCII)
    }
        try { & ipconfig /flushdns | Out-Null } catch { }
    } catch {
        Write-WarnLine ('hosts 修改失败（去广告不受影响）：' + $_.Exception.Message)
    }
}

# ===========================================================================
# 还原
# ===========================================================================

function Remove-HostsSections {
    param([string]$Text)
    $markers = @(
        @{ begin = '# >>> Gameware-Cleaner: leigod >>>'; end = '# <<< Gameware-Cleaner: leigod <<<' },
        @{ begin = '# >>> LeiGod cleanup >>>'; end = '# <<< LeiGod cleanup <<<' }
    )
    $lines = $Text -split "`r?`n"
    $out = New-Object System.Collections.ArrayList
    $skipping = $false
    $currentEnd = $null
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if (-not $skipping) {
            foreach ($mk in $markers) {
                if ($trim -eq $mk.begin) {
                    $skipping = $true
                    $currentEnd = $mk.end
                    break
                }
            }
            if (-not $skipping) { $out.Add($line) | Out-Null }
        } else {
            if ($trim -eq $currentEnd) {
                $skipping = $false
                $currentEnd = $null
            }
        }
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') {
        $out.RemoveAt($out.Count - 1)
    }
    return ($out -join "`r`n") + "`r`n"
}

function Invoke-Restore {
    param([string]$RequestedBackup)
    $backup = $RequestedBackup
    if (-not $backup) {
        $rootDir = Join-Path $env:USERPROFILE 'GamewareCleanerBackup'
        if (-not (Test-Path -LiteralPath $rootDir)) {
            throw ('找不到备份目录：' + $rootDir)
        }
        $all = @(Get-ChildItem -LiteralPath $rootDir -Directory -Filter 'leigod-*' -ErrorAction SilentlyContinue)
        $withOriginal = @($all | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'renderer.asar.original') } | Sort-Object Name -Descending)
        if ($withOriginal.Count -gt 0) {
            $latest = $withOriginal[0]
        } else {
            $latest = $all | Sort-Object Name -Descending | Select-Object -First 1
        }
        if (-not $latest) { throw 'GamewareCleanerBackup 里没有雷神的备份' }
        $backup = $latest.FullName
    }
    $backup = Get-CanonicalDir $backup
    $script:BackupPath = $backup
    $manifestPath = Join-Path $backup 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw ('备份里没有 manifest.json：' + $backup) }

    $script:LogPath = Join-Path $backup 'restore.log'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $installRoot = [string]$manifest.root
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot 'resources'))) {
        throw ('备份记录的安装目录不存在：' + $installRoot)
    }
    Write-Step '开始还原雷神'
    Write-Log ('安装目录：' + $installRoot)
    Write-Log ('备份目录：' + $backup)

    $isAdmin = Test-IsAdmin
    $hostsNeedsAdmin = (-not $NoHosts) -and (-not $HostsFile)
    if (-not $isAdmin -and ($hostsNeedsAdmin -or (Test-PathNeedsAdmin $installRoot))) {
        throw '还原需要管理员权限，请右键 restore.cmd 选择「以管理员身份运行」。'
    }
    Stop-LeigodProcesses $installRoot

    $renderer = Join-Path $installRoot 'resources\renderer.asar'
    $rendererBackup = Join-Path $backup 'renderer.asar.original'
    if (-not (Test-Path -LiteralPath $rendererBackup)) { $rendererBackup = Join-Path $backup 'renderer.asar.as-found' }
    if (Test-Path -LiteralPath $rendererBackup) {
        Copy-Item -LiteralPath $rendererBackup -Destination $renderer -Force
        $restoredRendererHash = Get-Sha256 $renderer
        Write-Log ('已还原 renderer.asar（SHA256 ' + $restoredRendererHash + '）')
    } else {
        Write-WarnLine '备份里没有 renderer.asar.original，跳过渲染层还原'
    }

    Restore-MediumWorker $installRoot $backup

    foreach ($q in @($manifest.quarantine)) {
        if (-not $q) { continue }
        $rel = [string]$q.relative
        $src = [string]$q.quarantinedTo
        if (-not $src -or -not (Test-Path -LiteralPath $src)) { continue }
        $dst = Get-RootItem $installRoot $rel
        if (Test-Path -LiteralPath $dst) {
            Write-WarnLine ('还原跳过（目标已存在）：' + $rel)
            continue
        }
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Move-Item -LiteralPath $src -Destination $dst -Force
        Write-Log ('已还原：' + $rel)
    }

    foreach ($h in @($manifest.hardlink)) {
        if (-not $h) { continue }
        $link = Get-RootItem $installRoot ([string]$h.link)
        $target = Get-RootItem $installRoot ([string]$h.target)
        if (-not (Test-Path -LiteralPath $link -PathType Leaf)) { continue }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        if ((Get-Sha256 $link) -ne (Get-Sha256 $target)) {
            Write-WarnLine ('硬链接还原跳过（内容已不同）：' + $h.link)
            continue
        }
        Remove-Item -LiteralPath $link -Force
        Copy-Item -LiteralPath $target -Destination $link -Force
        Write-Log ('已恢复独立文件：' + $h.link)
    }

    foreach ($r in @($manifest.rename)) {
        if (-not $r) { continue }
        $from = Get-RootItem $installRoot ([string]$r.from)
        $to = Get-RootItem $installRoot ([string]$r.to)
        if ((Test-Path -LiteralPath $to) -and -not (Test-Path -LiteralPath $from)) {
            Move-Item -LiteralPath $to -Destination $from -Force
            Write-Log ('已恢复更新器：' + $r.from)
        }
    }

    if (-not $NoHosts) {
        $hostsPath = Get-HostsPath
        $text = [System.IO.File]::ReadAllText($hostsPath, [System.Text.Encoding]::Default)
        $newText = Remove-HostsSections $text
        if ($newText -ne $text) {
            [System.IO.File]::WriteAllText($hostsPath, $newText, [System.Text.Encoding]::Default)
            Write-Log '已移除 hosts 里的雷神停更条目'
            try { & ipconfig /flushdns | Out-Null } catch { }
        } else {
            Write-Log 'hosts 里没有本工具添加的条目'
        }
    }

    $manifest | Add-Member -NotePropertyName restoredAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Step '还原完成'
    Write-Log '请重新启动雷神。'
    Write-Log ('还原日志：' + $script:LogPath)
}

# ===========================================================================
# 主流程
# ===========================================================================

function Test-PathNeedsAdmin {
    param([string]$InstallRoot)
    $pf86 = ${env:ProgramFiles(x86)}
    $pf = $env:ProgramFiles
    $prefixes = @()
    if ($pf86) { $prefixes += $pf86.TrimEnd('\') + '\' }
    if ($pf) { $prefixes += $pf.TrimEnd('\') + '\' }
    foreach ($p in $prefixes) {
        if ($InstallRoot.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-NeedsAdmin {
    param([string]$InstallRoot)
    if (-not $NoHosts -and -not $KeepUpdates -and -not $HostsFile) { return $true }
    return (Test-PathNeedsAdmin $InstallRoot)
}

function Request-Elevation {
    Write-Log '需要管理员权限，正在请求 UAC 提权...' 'Yellow'
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($Restore) { $argLine += ' -Restore' }
    if ($BackupDir) { $argLine += ' -BackupDir "' + $BackupDir + '"' }
    if ($Root) { $argLine += ' -Root "' + $Root + '"' }
    if ($KeepUpdates) { $argLine += ' -KeepUpdates' }
    if ($NoHosts) { $argLine += ' -NoHosts' }
    if ($HostsFile) { $argLine += ' -HostsFile "' + $HostsFile + '"' }
    if ($DryRun) { $argLine += ' -DryRun' }
    $disabled = @($featureSwitches | Where-Object { -not [bool](Get-Variable -Name $_ -Scope Script).Value })
    if ($disabled.Count) { $argLine += ' -DisabledFeatures "' + ($disabled -join ',') + '"' }
    if ($NoPause) { $argLine += ' -NoPause' }
    if ($NonInteractive) { $argLine += ' -NonInteractive' }
    if ($FollowSystemAccent) { $argLine += ' -FollowSystemAccent' }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argLine | Out-Null
        $script:ElevationStarted = $true
    } catch {
        throw '提权被取消或失败。请右键脚本选择「以管理员身份运行」。'
    }
}

function Read-FeatureChoice {
    param([string]$Label, [bool]$Default = $true)
    $hint = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $answer = Read-Host ($Label + ' [' + $hint + ']')
        if ($null -eq $answer) { throw '未能读取选择，已停止。' }
        $answer = $answer.Trim()
        if ($answer -eq '') { return $Default }
        if ($answer -match '^(?i:y|yes)$') { return $true }
        if ($answer -match '^(?i:n|no)$') { return $false }
        Write-WarnLine '请输入 Y 或 N；直接回车使用默认选择。'
    }
}

function Select-Features {
    Write-Step '选择本次要开启的功能'
    Write-Log '各项功能输入 Y/N；直接回车选择默认值。'
    Write-Log '已安装的旧补丁不会因选择 N 而撤销；需要撤销请先还原。' 'Yellow'
    $choices = @(
        @('BlockAds', '拦截广告接口、通知与工具自动下载'),
        @('HideCommunitySidebar', '移除详情页社区侧栏'),
        @('HideBottomPromoBar', '移除详情页底部推广条并修复排版'),
        @('HideHomeBanner', '移除首页横幅和游戏列表插卡广告'),
        @('HideHeaderPromo', '移除顶栏口号与搜索框轮播'),
        @('PinHeaderHeight', '固定顶栏高度，避免上下跳动'),
        @('StopButtonPauses', '点击停止加速时同时暂停计时'),
        @('AutoPauseIdleTime', '计时开启但连续 3 分钟未加速时自动暂停计时'),
        @('Md3eTheme', '是否需要 M3E 主题外观'),
        @('CleanTools', '隔离捆绑工具和更新残留'),
        @('HardlinkTools', '合并重复运行库以节省空间')
    )
    foreach ($choice in $choices) {
        $current = [bool](Get-Variable -Name $choice[0] -Scope Script).Value
        if (-not $NonInteractive -and -not $NoPause) {
            $current = Read-FeatureChoice $choice[1] $current
            Set-Variable -Name $choice[0] -Scope Script -Value $current
        }
        if ($choice[0] -eq 'Md3eTheme') {
            if (-not $current) { $script:FollowSystemAccent = $false }
            elseif (-not $NonInteractive -and -not $NoPause) {
                $script:FollowSystemAccent = Read-FeatureChoice '是否需要取色功能（跟随 Windows 系统主题色）' ([bool]$FollowSystemAccent)
            }
        }
    }
    $freeze = -not $KeepUpdates
    if (-not $NonInteractive -and -not $NoPause) {
        $freeze = Read-FeatureChoice '冻结客户端更新（改名更新程序并拦截更新域名）' $freeze
        Set-Variable -Name KeepUpdates -Scope Script -Value (-not $freeze)
    }
    Write-Step '本次选择'
    foreach ($choice in $choices) {
        $enabled = [bool](Get-Variable -Name $choice[0] -Scope Script).Value
        $label = if ($enabled) { '开启' } else { '跳过' }
        Write-Log ($label + '：' + $choice[1])
    }
    Write-Log ('冻结更新：' + $freeze)
    Write-Log ('跟随 Windows 系统主题色：' + [bool]$FollowSystemAccent)
}

function Main {
    Write-Log ''
    Write-Log '==============================================' 'Cyan'
    Write-Log ('  Gameware-Cleaner — 雷神加速器一键精简 v' + $script:ScriptVersion) 'Cyan'
    Write-Log '==============================================' 'Cyan'
    Write-Log ''

    if ($Restore) {
        if (-not (Test-IsAdmin) -and -not $NoPause -and -not $NoElevate) {
            Request-Elevation
            return
        }
        Invoke-Restore $BackupDir
        return
    }

    $installRoot = Find-LeigodRoot
    if (-not $installRoot) {
        throw '找不到雷神加速器安装目录。请确认已安装雷神，或用 -Root "安装目录" 指定。'
    }
    $installRoot = Get-CanonicalDir $installRoot
    Write-Log ('安装目录：' + $installRoot)

    $versionFile = Join-Path $installRoot 'version_f.txt'
    $appVersion = '未知'
    if (Test-Path -LiteralPath $versionFile) {
        $appVersion = (Read-Utf8 $versionFile).Trim()
    }
    Write-Log ('雷神版本：' + $appVersion)
    Write-Log ('脚本版本：' + $script:ScriptVersion)
    $rendererPath = Join-Path $installRoot 'resources\renderer.asar'
    if (-not (Test-Path -LiteralPath $rendererPath)) {
        throw ('找不到 renderer.asar：' + $rendererPath)
    }
    $originalHash = Get-Sha256 $rendererPath
    Write-Log ('当前 renderer.asar SHA256：' + $originalHash)

    if (-not $DryRun) {
        $isAdmin = Test-IsAdmin
        if (-not $isAdmin -and -not $NoElevate -and (Test-NeedsAdmin $installRoot)) {
            Request-Elevation
            return
        }
    }

    Select-Features

    # 先创建再取长名：$env:TEMP 可能是 8.3 短名（SOMEUS~1 这种），而 GetFullPath 只做
    # 词法规范化、不会展开短名，必须让 Get-Item 在目录真实存在后回报长名。
    $script:TempDir = Join-Path $env:TEMP ('gameware-cleaner-leigod-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:TempDir | Out-Null
    $script:TempDir = Get-CanonicalDir $script:TempDir
    $workDir = Join-Path $script:TempDir 'renderer'
    $newAsar = Join-Path $script:TempDir 'renderer.asar.new'

    try {
        Write-Step '解包 renderer.asar'
        Expand-Asar -AsarPath $rendererPath -OutDir $workDir
        $count = @(Get-ChildItem -LiteralPath $workDir -Recurse -File -Force).Count
        Write-Log ('已解包 ' + $count + ' 个文件')

        Write-Step '应用渲染层补丁'
        $result = Invoke-RendererPatches -WorkDir $workDir -AppVersion $appVersion
        $installedHash = $null
        $rendererOriginalName = $null

        if ($result -eq 'already' -or $result -eq 'legacy') {
            Write-Step '渲染层已经是精简状态，跳过重打包'
        } else {
            Write-Step '重新打包 renderer.asar'
            $ordered = @()
            $info = Get-AsarInfo $rendererPath
            $ordered = @(Get-AsarLeafPaths -Node $info.Header -Prefix '')
            if ($Md3eTheme -and (-not $FollowSystemAccent)) {
                $ordered = @($ordered | Where-Object { $_ -ne 'md3e-system-color.js' })
            }
            New-AsarArchive -SourceDir $workDir -OrderedPaths $ordered -OutPath $newAsar
            Write-Log ('新 renderer.asar：' + (Format-Size (Get-Item -LiteralPath $newAsar).Length))
            Write-Step '校验新 renderer.asar'
            Assert-AsarRoundTrip -AsarPath $newAsar -WorkDir $workDir
            Write-Ok '重打包校验通过（文件数量、内容、完整性字段都一致）'

            if ($DryRun) {
                Write-Step '演练完成（-DryRun）'
                Write-Log '未修改安装目录、未隔离文件、未修改 hosts。'
                Write-Log ('新 asar 临时路径：' + $newAsar)
                return
            }

            Write-Step '备份并替换 renderer.asar'
            $backupPath = New-BackupDirectory $installRoot
            $script:BackupPath = $backupPath
            Write-Log ('备份目录：' + $backupPath)
            $rendererBackup = Join-Path $backupPath 'renderer.asar.original'
            Copy-Item -LiteralPath $rendererPath -Destination $rendererBackup -Force
            $rendererOriginalName = 'renderer.asar.original'
            Write-Log ('已备份原版 renderer.asar（' + (Format-Size (Get-Item -LiteralPath $rendererBackup).Length) + '）')

            Stop-LeigodProcesses $installRoot
            Copy-Item -LiteralPath $newAsar -Destination $rendererPath -Force
            $installedHash = Get-Sha256 $rendererPath
            if ($installedHash -ne (Get-Sha256 $newAsar)) {
                throw '安装后哈希不一致，renderer.asar 可能没有正确写入'
            }
            Write-Ok ('已安装新 renderer.asar（SHA256 ' + $installedHash + '）')
        }

        if ($DryRun) {
            Write-Step '演练完成（-DryRun）'
            Write-Log '未修改安装目录、未隔离文件、未修改 hosts。'
            return
        }

        if (-not $script:BackupPath) {
            # 渲染层已经是精简状态时，仍然需要备份目录来放隔离文件
            $script:BackupPath = New-BackupDirectory $installRoot
            Write-Log ('备份目录：' + $script:BackupPath)
            $asFound = Join-Path $script:BackupPath 'renderer.asar.as-found'
            Copy-Item -LiteralPath $rendererPath -Destination $asFound -Force
            Write-Log '已保存当前 renderer.asar 副本（renderer.asar.as-found，已是精简版）'
        }
        $backupPath = $script:BackupPath
        if ($Md3eTheme) {
            try {
                Set-MediumWorker $installRoot $backupPath ([bool]$FollowSystemAccent)
            } catch {
                if ($rendererOriginalName) { Copy-Item -LiteralPath (Join-Path $backupPath $rendererOriginalName) -Destination $rendererPath -Force }
                throw
            }
            Write-Ok '系统主题色助手已处理（当前用户登录启动项随备份还原）'
        }
        $installedSha = if ($installedHash) { $installedHash } else { $originalHash }

        $manifest = [ordered]@{
            schemaVersion = 1
            tool = 'Gameware-Cleaner oneclick'
            scriptVersion = $script:ScriptVersion
            app = 'leigod'
            appVersion = $appVersion
            root = $installRoot
            backup = $backupPath
            createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            rendererOriginal = $rendererOriginalName
            rendererOriginalSha256 = $originalHash
            rendererInstalledSha256 = $installedSha
            md3eFollowSystemAccent = [bool]$FollowSystemAccent
            keepUpdates = [bool]$KeepUpdates
            quarantine = @()
            hardlink = @()
            rename = @()
            hostsBlock = @()
            hostsBackup = $null
            errors = @()
        }

        Write-Step '精简安装目录（隔离，不删除）'
        if ($CleanTools) { Invoke-LeigodQuarantine -InstallRoot $installRoot -BackupPath $backupPath -Manifest $manifest }

        Write-Step '工具运行时硬链接'
        if ($HardlinkTools) { Invoke-LeigodHardlinks -InstallRoot $installRoot -Manifest $manifest }

        Write-Step '处理更新'
        Invoke-LeigodUpdateFreeze -InstallRoot $installRoot -BackupPath $backupPath -Manifest $manifest

        Write-Step '保存备份清单和还原脚本'
        $manifestJson = $manifest | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath (Join-Path $backupPath 'manifest.json') -Value $manifestJson -Encoding UTF8
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $backupPath 'LeiGod-OneClick.ps1') -Force
        $restoreCmd = @'
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0LeiGod-OneClick.ps1" -Restore -BackupDir "%~dp0"
'@
        Set-Content -LiteralPath (Join-Path $backupPath 'restore.cmd') -Value $restoreCmd -Encoding ASCII
        $readme = @'
Gameware-Cleaner — 雷神精简备份

还原方法（任选一种）：
  1. 双击本目录里的 restore.cmd（会自动请求管理员权限）。
  2. 或者用管理员 PowerShell 运行：
       powershell -NoProfile -ExecutionPolicy Bypass -File "LeiGod-OneClick.ps1" -Restore -BackupDir "<本目录>"

还原内容：
  - renderer.asar.original 放回 resources\renderer.asar
  - quarantine\ 里被隔离的文件放回原位置
  - resources\tools 下的硬链接恢复成独立文件
  - updater.exe.disabled 改回 updater.exe
  - 移除 hosts 里的雷神停更条目

注意：
  - 还原前请先退出雷神。
  - run.log 里可能有账号相关的日志行，分享前请打码。
  - 确认精简版稳定几天后，可以删除整个备份目录释放空间。
'@
        Set-Content -LiteralPath (Join-Path $backupPath 'README.txt') -Value $readme -Encoding UTF8
        Write-Ok ('备份与还原脚本已写入：' + $backupPath)

        Write-Step '完成'
        Write-Log ''
        Write-Log ('雷神版本：' + $appVersion)
        Write-Log ('renderer.asar：' + $originalHash.Substring(0, 12) + '... -> ' + $manifest.rendererInstalledSha256.Substring(0, 12) + '...')
        Write-Log ('隔离文件：' + $manifest.quarantine.Count + ' 项，约 ' + (Format-Size $script:QuarantineBytes))
        Write-Log ('硬链接：' + $manifest.hardlink.Count + ' 项，省约 ' + (Format-Size $script:HardlinkSavedBytes))
        if ($KeepUpdates) {
            Write-Log '更新：保留（-KeepUpdates）'
        } else {
            Write-Log '更新：已停更（updater.exe 改名 + hosts 屏蔽 buildnum 域名）'
        }
        Write-Log ''
        if ($result -eq 'applied') {
            Write-Log '渲染层已按本次选择处理，新产物已备份并安装。' 'Green'
        } else {
            Write-Log '渲染层此前已经是精简状态，本次只做安装目录清理和更新处理。' 'Green'
        }
        Write-Log ''
        Write-Log ('回滚：双击 ' + (Join-Path $backupPath 'restore.cmd')) 'Yellow'
        Write-Log ('日志：' + (Join-Path $backupPath 'run.log')) 'Yellow'
        Write-Log ''
        Write-Log '请启动雷神检查：登录、加速、游戏列表是否正常。'
        Write-Log '确认稳定几天后，可以删除备份目录释放空间。'
        $script:Completed = $true
    } finally {
        if ($script:Completed -and -not $DryRun -and $script:TempDir -and (Test-Path -LiteralPath $script:TempDir)) {
            try { Remove-Item -LiteralPath $script:TempDir -Recurse -Force } catch { }
        }
    }
}

$script:JsCache = @{}

try {
    Main
} catch {
    Write-ErrLine $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Write-Log ('调用栈：' + $_.ScriptStackTrace) 'DarkGray'
    }
    Write-Log ''
    Write-Log '本次操作没有完成。' 'Red'
    Write-Log '如果已经替换过 renderer.asar，可以用备份目录里的 restore.cmd 还原。' 'Yellow'
    if ($script:BackupPath) {
        Write-Log ('本次备份目录：' + $script:BackupPath) 'Yellow'
    }
    if ($script:TempDir -and (Test-Path -LiteralPath $script:TempDir)) {
        Write-Log ('现场文件已保留：' + $script:TempDir) 'Yellow'
        Write-Log '如果是版本结构变化，把该目录里的报错信息和 assets 下对应 chunk 发回来即可。' 'Yellow'
    }
    $script:ExitCode = 1
} finally {
    Invoke-PauseIfNeeded
}
if ($script:ExitCode) { exit $script:ExitCode }
