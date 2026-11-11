#!/usr/bin/env node
// 把 web/build.sh 出的网页版改成「单个文件有大小上限」的托管能放的样子（比如 claude.ai 的 Artifact：单个二进制 15 MB）：
// index.wasm / index.pck 先 gzip，再切成不超过 12 MB 的几块 parts/*.wasm（只是借后缀，内容是 gzip 块）；parts.js 里写清楚怎么拼，
// 外壳（client/web/shell.html）里的 fetch 拦截会取回来、解压、拼好再交给 Godot。
// 另外写一份 page.html：去掉 <!DOCTYPE>/<html>/<head>/<body> 外层（托管方会自己套）。
//   node web/split.mjs <网页版目录> <输出目录>
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync, rmSync } from "node:fs";
import { gzipSync } from "node:zlib";

const [src, out] = process.argv.slice(2);
if (!src || !out) { console.error("用法：node web/split.mjs <网页版目录> <输出目录>"); process.exit(1); }
const CHUNK = 12 * 1024 * 1024;
rmSync(out, { recursive: true, force: true });
mkdirSync(`${out}/parts`, { recursive: true });
const parts = {};
for (const [name, type] of [["index.wasm", "application/wasm"], ["index.pck", "application/octet-stream"]]) {
  const gz = gzipSync(readFileSync(`${src}/${name}`), { level: 9 });
  const chunks = [];
  for (let i = 0, n = 0; i < gz.length; i += CHUNK, n++) {
    const file = `parts/${name.replace(".", "-")}-${n}.wasm`; // 托管方认 .wasm 这个后缀（二进制原样传），里面其实是 gzip 的一块
    writeFileSync(`${out}/${file}`, gz.subarray(i, i + CHUNK));
    chunks.push(file);
  }
  parts[name] = { gzip: true, type, chunks };
  console.log(`${name}: ${(gz.length / 1048576).toFixed(1)} MB gzip，${chunks.length} 块`);
}
writeFileSync(`${out}/parts.js`, `window.TONGSUI_PARTS = ${JSON.stringify(parts)};\n`);
for (const f of readdirSync(src)) {
  if (["index.wasm", "index.pck", "parts.js"].includes(f) || f.endsWith(".html")) continue;
  copyFileSync(`${src}/${f}`, `${out}/${f}`);
}
const html = readFileSync(`${src}/index.html`, "utf8")
  .replace(/<!DOCTYPE html>\s*/i, "")
  .replace(/<\/?html[^>]*>\s*/gi, "")
  .replace(/<\/?head>\s*/gi, "")
  .replace(/<\/?body>\s*/gi, "")
  .replace(/<meta charset="utf-8">\s*/i, "")
  .replace(/<meta name="viewport"[^>]*>\s*/i, "");
writeFileSync(`${out}/page.html`, html);
writeFileSync(`${out}/index.html`, readFileSync(`${src}/index.html`, "utf8"));
console.log(`✓ ${out}`);
