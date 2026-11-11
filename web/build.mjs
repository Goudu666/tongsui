#!/usr/bin/env node
// 网页单机版的脚本：把编译好的服务器（server/build/index.js）包进一个函数作用域，顶层的函数和常量挂在 TongsuiServer 上，
// 再接上 web/local.js（假 Nakama + 对门的电脑），写成一个 tongsui-local.js 放在网页导出的旁边。
// 用法：npm run server:build && node web/build.mjs <输出目录>
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const out = process.argv[2] || new URL("../build/web", import.meta.url).pathname;
const server = readFileSync(new URL("../server/build/index.js", import.meta.url), "utf8");
const local = readFileSync(new URL("./local.js", import.meta.url), "utf8");
// 顶层声明（var/function），tsc 输出的是 ES5 脚本，没有 import/export
const names = [...new Set([...server.matchAll(/^(?:var|let|const|function)\s+([A-Za-z_$][\w$]*)/gm)].map((m) => m[1]))];
if (!names.includes("matchLoop") || !names.includes("CONTENT")) throw new Error("server/build/index.js 里没找到 matchLoop / CONTENT，先 npm run server:build");
const exportsObj = names.map((n) => `${JSON.stringify(n)}: typeof ${n} === "undefined" ? undefined : ${n}`).join(",\n  ");
const bundle = `/* 同岁 · 网页单机版（自动生成：node web/build.mjs，别手改） */
var TongsuiServer = (function () {
${server}
return {
  ${exportsObj}
};
})();
${local}`;
mkdirSync(out, { recursive: true });
writeFileSync(`${out}/tongsui-local.js`, bundle);
console.log(`✓ ${out}/tongsui-local.js（${(bundle.length / 1024).toFixed(0)} KB，${names.length} 个名字）`);
