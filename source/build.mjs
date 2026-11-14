// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 TG-Twilight
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const license = fs.readFileSync(path.join(dir, '../licenses/Apache-2.0.txt'), 'utf8').replace(/\r\n/g, '\n');
const result = await build({
  absWorkingDir: dir,
  entryPoints: ['md3e-system-color-entry.js'],
  bundle: true,
  write: false,
  format: 'iife',
  target: 'chrome100',
  minify: true,
  legalComments: 'inline',
  charset: 'ascii',
  banner: { js: '// Offline Material Color Utilities 0.4.0; generated from md3e-system-color-entry.js.\n/*\n' + license.trim() + '\n*/' }
});
const file = path.join(dir, '../LeiGod-OneClick.ps1');
const ps = fs.readFileSync(file, 'utf8');
const match = /\$script:Md3eSystemColorJs = @'(\r?\n)/.exec(ps);
if (!match) throw new Error('找不到脚本内嵌配色资源');
const marker = match[0];
const start = match.index;
const eol = match[1];
const end = ps.indexOf(eol + "'@", start + marker.length);
if (end < 0) throw new Error('找不到资源结束标记');
const js = result.outputFiles[0].text.trimEnd().replace(/\r?\n/g, eol);
if (js.split('\n').some(line => line.startsWith("'@"))) throw new Error('资源包含 PowerShell here-string 结束标记');
const next = ps.slice(0, start + marker.length) + js + ps.slice(end);
if (process.argv.includes('--check')) {
  if (next !== ps) throw new Error('生成结果与内嵌资源不一致');
  console.log('配色源码与内嵌资源逐字节一致。');
} else {
  fs.writeFileSync(file, next);
  console.log('已更新脚本内嵌配色资源。');
}
