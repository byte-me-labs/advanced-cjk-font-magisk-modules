#!/usr/bin/env node
// 重新生成 README「支持的字体」表格，补上最新版本与构建时间。
//
// 由工作流的 update 作业在合并本次构建的元数据后调用：
//   版本      来自 updates/<slug>.json（与 Magisk 更新清单同源）
//   构建时间   来自 .github/build-info/<slug>.json（构建期写入，Magisk 不读取）
//
// 表格行顺序沿用 README 中已有顺序（新增字体追加到末尾），避免每次运行整体重排。
// 未构建过的字体显示 “—”。脚本可重复执行，输出相同。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const README = path.join(ROOT, 'README.md');
const START = '<!-- fonts-table:start -->';
const END = '<!-- fonts-table:end -->';

const readJson = (p) => {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
};

const escapeCell = (s) => String(s).replace(/\|/g, '\\|');

const pad = (n) => String(n).padStart(2, '0');
const fmtTime = (iso) => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ` +
    `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())} UTC`;
};

const readme = fs.readFileSync(README, 'utf8');
const start = readme.indexOf(START);
const end = readme.indexOf(END);
if (start < 0 || end < start) {
  console.error(`README 缺少 ${START} / ${END} 标记`);
  process.exit(1);
}

// 现有表格里的 slug 顺序
const block = readme.slice(start + START.length, end);
const existing = [...block.matchAll(/^\|\s*`([^`]+)`/gm)].map((m) => m[1]);

// 配置目录名即 slug
const fontsDir = path.join(ROOT, '.github/fonts');
const slugs = fs.readdirSync(fontsDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(fontsDir, d.name, 'config.json')))
  .map((d) => d.name);
const ordered = [
  ...existing.filter((s) => slugs.includes(s)),
  ...slugs.filter((s) => !existing.includes(s)).sort(),
];

const rows = ordered.map((slug) => {
  const cfg = readJson(path.join(fontsDir, slug, 'config.json')) ?? {};
  const manifest = readJson(path.join(ROOT, 'updates', `${slug}.json`));
  const info = readJson(path.join(ROOT, '.github/build-info', `${slug}.json`));
  const upstream = cfg.upstream ?? '';
  const version = manifest?.version ? `\`${manifest.version}\`` : '—';
  const builtAt = info?.builtAt ? fmtTime(info.builtAt) : '—';
  return `| \`${slug}\` | ${escapeCell(cfg.name ?? slug)} | ` +
    `[${upstream}](https://github.com/${upstream}) | ${cfg.format ?? '—'} | ${version} | ${builtAt} |`;
});

const table = [
  '| slug | 字体 | 上游 | 格式 | 最新版本 | 构建时间 |',
  '| ---- | ---- | ---- | ---- | ---- | ---- |',
  ...rows,
].join('\n');

fs.writeFileSync(
  README,
  `${readme.slice(0, start + START.length)}\n${table}\n${readme.slice(end)}`,
);
console.log(`已刷新 README 字体表：${rows.length} 项`);
