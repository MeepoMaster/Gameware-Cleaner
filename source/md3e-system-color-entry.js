// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 TG-Twilight
// Source for the offline renderer bundle. Build with build.mjs.
import { Hct, SchemeTonalSpot, hexFromArgb, argbFromHex } from '@material/material-color-utilities';

const roles = ['primary', 'onPrimary', 'primaryContainer', 'onPrimaryContainer',
  'secondary', 'onSecondary', 'secondaryContainer', 'onSecondaryContainer',
  'tertiary', 'onTertiary', 'tertiaryContainer', 'onTertiaryContainer',
  'error', 'onError', 'errorContainer', 'onErrorContainer', 'surface', 'onSurface',
  'surfaceVariant', 'onSurfaceVariant', 'surfaceDim', 'surfaceBright',
  'surfaceContainerLowest', 'surfaceContainerLow', 'surfaceContainer',
  'surfaceContainerHigh', 'surfaceContainerHighest', 'outline', 'outlineVariant',
  'inverseSurface', 'inverseOnSurface', 'scrim'];
// The seed is read once by the installer (Windows UISettings Accent) and written into
// data-seed; there is no background process and no polling.
const seedAttr = document.currentScript?.getAttribute('data-seed') || null;
if (window.__gcMd3eColor) window.__gcMd3eColor.dispose();
let current = null;
let sheet = null;
function name(role) { return '--md3e-' + role.replace(/[A-Z]/g, c => '-' + c.toLowerCase()); }
function palette(seed, dark) {
  const scheme = new SchemeTonalSpot(Hct.fromInt(argbFromHex(seed)), dark, 0, '2021');
  return roles.map(role => name(role) + ':' + hexFromArgb(scheme[role]) + ';').join('');
}
function setAccent(seed) {
  if (seed !== null && !/^#[0-9a-f]{6}$/i.test(seed)) return false;
  if (seed === current) return true;
  if (seed === null) {
    if (sheet) sheet.remove();
    sheet = null;
    current = null;
    return true;
  }
  try {
    // Compute both schemes before changing DOM; invalid input preserves current UI.
    const css = 'html.dark:root,:root[data-theme="dark"]{' + palette(seed, true) + '}' +
      ':root:not(.dark):not([data-theme="dark"]){' + palette(seed, false) + '}';
    if (!sheet) {
      sheet = document.createElement('style');
      sheet.id = 'gc-md3e-system-palette';
      document.head.appendChild(sheet);
    }
    sheet.textContent = css;
    current = seed;
    return true;
  } catch (_) { return false; }
}
function dispose() {
  setAccent(null);
  window.removeEventListener('pagehide', dispose);
  delete window.__gcMd3eSetAccent;
  delete window.__gcMd3eColor;
}
window.__gcMd3eSetAccent = setAccent;
window.__gcMd3eColor = { dispose, get seed() { return current; }, source: 'install-time' };
setAccent(seedAttr);
window.addEventListener('pagehide', dispose);
