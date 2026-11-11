#!/usr/bin/env node
// 年代对比：同一套活法机器人（tools/paths.mjs），按五个出生年代各过一遍人生，看每道关上各条线够得着的比例、积蓄和吃到的大事。
// 用法：npm run build && node tools/eras.mjs [--lives N] [--json out.json] [--check] [--jobs J] [--until AGE]
//   --lives N   每个年代每种活法跑几条人生，默认 16（五个年代 × 12 种活法 × 16 = 960 条）
//   --json      把汇总写成 JSON（每个年代 × 每种活法 × 每道关的计数）
//   --check     断言：c92（默认年代）30 岁以前每条人生每道关够得着的线，和 paths.mjs 不指定年代跑出来的逐条一致；
//               别的年代至少有一道关的一条路比例和 c92 差 15 个点以上。不满足就退出码 1
//   --jobs J    并行几个子进程，默认 CPU 个数
//   --until AGE 过到几岁，默认 76（最后一道关在 75 岁）
// 说明见 docs/ERAS.md。种子和 paths.mjs 一样：第 i 条人生用 i × 7919，所以同一条人生在各个年代里只差出生年代。
//
// 指定年代：paths.mjs 的 live() 里写死了 lifeCreate(seed, C)，这里用它的 setup 钩子在投胎确认之前把 s.cohort 换掉。
// lifeCreate(seed, C, legacy, cohortId) 的第四个参数也只是赋 s.cohort（抽家境、天赋都在那之前，不读年代），
// 所以两种写法得到的是同一个状态；--check 会顺手比一遍。
import { readFileSync, writeFileSync } from "node:fs";
import { execFile } from "node:child_process";
import { availableParallelism } from "node:os";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { WAYS, live, climb } from "./paths.mjs";

const code = readFileSync(new URL("../server/build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math, Date });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);
const C = G("CONTENT");
const ROLES = ["qing", "mei"];
const COHORTS = C.eras.cohorts;
const BASE = (COHORTS.find((c) => c.default) || COHORTS[0]).id;
const STONES = C.events.filter((e) => e.kind === "milestone" && e.options.some((o) => o.min)).sort((a, b) => a.age - b.age);
const SHOWN = STONES.filter((e) => e.age >= 18); // 表上只放成年以后这几道：高考、找事由、安家、四十五、退休、七十
const EARLY = STONES.filter((e) => e.age <= 30); // --check 逐条比的
const seedOf = (i) => i * 7919;

// ---------- 子进程：一个年代 × 一种活法 ----------

/** 跑 n 条人生。cohort 为 null：不动年代（就是 paths.mjs 的跑法）。detail：把 30 岁以前每条人生的结果也带回来 */
function runTask(cohort, wayName, n, until, detail) {
  const way = WAYS[wayName];
  const acc = {}; // 关口 id → { n, open: {选项: 人数}, money }
  const eras = {}; // 大事 id → { n: 几条人生吃到, shown: 其中弹了卡的 }
  const lives = [];
  for (let i = 1; i <= n; i++) {
    const { s, marks } = live(seedOf(i), way, until, climb, cohort ? (st) => { st.cohort = cohort; } : undefined);
    for (const ev of STONES) for (const r of way.shadow || ROLES) {
      const m = marks[ev.id]?.[r];
      if (!m) continue;
      const a = (acc[ev.id] ||= { n: 0, open: {}, money: 0 });
      a.n++;
      a.money += m.money;
      for (const id of m.open) a.open[id] = (a.open[id] || 0) + 1;
    }
    const shown = new Set(s.log.filter((e) => e.era).map((e) => e.era.id));
    for (const id of s.eras || []) {
      const e = (eras[id] ||= { n: 0, shown: 0 });
      e.n++;
      if (shown.has(id)) e.shown++;
    }
    if (detail) {
      const early = {};
      for (const ev of EARLY) for (const r of way.shadow || ROLES) {
        const m = marks[ev.id]?.[r];
        if (m) early[ev.id + "." + r] = { open: m.open, money: m.money, stats: m.stats };
      }
      lives.push({ seed: seedOf(i), cohort: s.cohort, early });
    }
  }
  return { cohort, way: wayName, n, acc, eras, lives: detail ? lives : undefined };
}

// ---------- 主进程 ----------

function args(argv) {
  const o = { lives: 16, json: null, check: false, jobs: availableParallelism(), until: 76 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--lives") o.lives = Number(argv[++i]);
    else if (a === "--json") o.json = argv[++i];
    else if (a === "--check") o.check = true;
    else if (a === "--jobs") o.jobs = Number(argv[++i]);
    else if (a === "--until") o.until = Number(argv[++i]);
    else throw new Error("不认识的参数 " + a);
  }
  if (!(o.lives > 0) || !(o.jobs > 0) || !(o.until > 0)) throw new Error("--lives / --jobs / --until 要正数");
  return o;
}

/** 把任务分给 jobs 个子进程，每个子进程一次跑一个任务 */
function pool(tasks, jobs) {
  const self = fileURLToPath(import.meta.url);
  const out = new Array(tasks.length);
  let next = 0, done = 0;
  return new Promise((resolve, reject) => {
    const start = () => {
      if (next >= tasks.length) return;
      const k = next++;
      execFile(process.execPath, [self, "--worker", JSON.stringify(tasks[k])], { maxBuffer: 256 << 20 }, (err, stdout, stderr) => {
        if (err) return reject(new Error(`任务 ${JSON.stringify(tasks[k])} 失败：${stderr || err.message}`));
        out[k] = JSON.parse(stdout);
        process.stderr.write(`\r  ${++done}/${tasks.length}`);
        if (done === tasks.length) { process.stderr.write("\n"); resolve(out); } else start();
      });
    };
    for (let j = 0; j < Math.min(jobs, tasks.length); j++) start();
  });
}

/** 按显示宽度补齐（汉字算两格） */
const width = (t) => [...String(t)].reduce((w, ch) => w + (ch.charCodeAt(0) > 0x2e7f ? 2 : 1), 0);
const pad = (t, w) => String(t) + " ".repeat(Math.max(0, w - width(t)));
const lpad = (t, w) => " ".repeat(Math.max(0, w - width(t))) + String(t);

/** 每个年代把所有活法加在一起：关口 → { n, open, money } */
function merge(results) {
  const by = {};
  for (const r of results) {
    const c = (by[r.cohort] ||= { acc: {}, eras: {}, lives: 0 });
    c.lives += r.n;
    for (const [id, a] of Object.entries(r.acc)) {
      const t = (c.acc[id] ||= { n: 0, open: {}, money: 0 });
      t.n += a.n; t.money += a.money;
      for (const [o, k] of Object.entries(a.open)) t.open[o] = (t.open[o] || 0) + k;
    }
    for (const [id, e] of Object.entries(r.eras)) {
      const t = (c.eras[id] ||= { n: 0, shown: 0 });
      t.n += e.n; t.shown += e.shown;
    }
  }
  return by;
}

const pct = (a, id) => (a && a.n ? Math.round(((a.open[id] || 0) / a.n) * 100) : null);

function table(by, opt, results) {
  const ids = COHORTS.map((c) => c.id);
  const W0 = 30, W = 11;
  const lines = [];
  lines.push(`每个年代 × ${Object.keys(WAYS).length} 种活法 × ${opt.lives} 条人生（种子 i×7919），关口上总选够得着的最高那条线（tools/paths.mjs 的 climb），过到 ${opt.until} 岁。`);
  lines.push("数字是关口那天一早够得着这条线的人占多少（不算发挥）；所有活法的人放在一起算。积蓄是关口那天一早的平均数（块）。");
  lines.push("");
  lines.push(pad("关口 · 路", W0) + ids.map((id) => lpad(id === BASE ? id + "*" : id, W)).join(""));
  lines.push(pad("", W0) + COHORTS.map((c) => lpad([...c.name.replace(/生$/, "")].slice(0, 5).join(""), W)).join(""));
  for (const ev of SHOWN) {
    lines.push(pad(`${ev.age} 岁 ${ev.title}`, W0));
    for (const o of ev.options.filter((x) => x.min)) {
      const cells = ids.map((id) => { const v = pct(by[id]?.acc[ev.id], o.id); return lpad(v === null ? "—" : v + "%", W); });
      lines.push(pad(`  ${o.id} ${[...String(o.text)].slice(0, 10).join("")}`, W0) + cells.join(""));
    }
  }
  const money = (evId, label) => pad(label, W0) + ids.map((id) => { const a = by[id]?.acc[evId]; return lpad(a && a.n ? Math.round(a.money / a.n) : "—", W); }).join("");
  const settle = STONES.find((e) => e.age === 30), retire = STONES.find((e) => e.age === 60);
  lines.push("");
  if (settle) lines.push(money(settle.id, "30 岁积蓄（块）"));
  if (retire) lines.push(money(retire.id, "60 岁积蓄（块）"));
  lines.push(pad("人数（30 岁那道关）", W0) + ids.map((id) => lpad(by[id]?.acc[settle?.id]?.n ?? "—", W)).join(""));
  lines.push("");
  lines.push("* 默认年代（老存档、测试、paths.mjs 用的那个）。现有数值按它校的。");
  lines.push("");
  // 分活法看几条最会随年代动的线：加在一起的数会把「专心」和「不上心」的差抹平
  const KEY = [["m_gaokao", "local"], ["m_job", "desk"], ["m_settle", "buy"], ["m_evening", "care"]];
  for (const [evId, oId] of KEY) {
    const ev = STONES.find((e) => e.id === evId);
    if (!ev || !ev.options.some((o) => o.id === oId)) continue;
    lines.push(pad(`分活法 · ${ev.age} 岁 ${oId}`, W0) + ids.map((id) => lpad(id === BASE ? id + "*" : id, W)).join(""));
    for (const name of Object.keys(WAYS)) {
      const cells = ids.map((id) => { const v = pct(results.find((r) => r.cohort === id && r.way === name)?.acc[evId], oId); return lpad(v === null ? "—" : v + "%", W); });
      lines.push(pad("  " + name, W0) + cells.join(""));
    }
    lines.push("");
  }
  lines.push("吃到的大事（按年份；[生前] = 出生 + 3 岁以前，只打标记、不弹卡；数字是吃到它的人生占多少，不到 100% 的是没活到那一年）");
  const evById = new Map(C.eras.events.map((e) => [e.id, e]));
  for (const co of COHORTS) {
    const b = by[co.id];
    if (!b) continue;
    const list = Object.entries(b.eras).sort((x, y) => evById.get(x[0]).year - evById.get(y[0]).year || x[0].localeCompare(y[0]));
    const items = list.map(([id, e]) => {
      const ev = evById.get(id);
      const tag = e.shown === 0 ? "[生前]" : "";
      const share = Math.round((e.n / b.lives) * 100);
      return `${ev.title}${tag}${share < 100 ? " " + share + "%" : ""}`;
    });
    lines.push(`  ${pad(co.id + " " + co.name, 18)} ${items.join("、")}`);
  }
  return lines.join("\n");
}

/** --check：返回不满足的条目 */
function check(results, paths, by) {
  const bad = [];
  // 1. lifeCreate 第四个参数和 setup 换 s.cohort 是同一个状态
  for (const co of COHORTS) {
    const a = G("lifeCreate")(seedOf(1), C, undefined, co.id);
    const b = G("lifeCreate")(seedOf(1), C);
    b.cohort = co.id;
    if (JSON.stringify(a) !== JSON.stringify(b)) bad.push(`lifeCreate(seed, C, undefined, "${co.id}") 和投胎前换 s.cohort 得到的状态不一样`);
  }
  // 2. c92 30 岁以前逐条人生和 paths.mjs 默认一致
  for (const p of paths) {
    const mine = results.find((r) => r.cohort === BASE && r.way === p.way);
    for (let i = 0; i < p.lives.length; i++) {
      const x = p.lives[i], y = mine.lives[i];
      if (x.cohort !== BASE) bad.push(`paths.mjs 默认年代是 ${x.cohort}，不是 ${BASE}`);
      if (JSON.stringify(x.early) !== JSON.stringify(y.early)) {
        const k = Object.keys({ ...x.early, ...y.early }).find((k) => JSON.stringify(x.early[k]) !== JSON.stringify(y.early[k]));
        bad.push(`【${p.way}】种子 ${x.seed} 在 ${k} 上和 paths.mjs 不一致：${JSON.stringify(x.early[k])} ≠ ${JSON.stringify(y.early[k])}`);
      }
    }
  }
  // 3. 别的年代至少有一道关的一条路和 c92 差 15 个点。
  //    按活法看（paths.mjs 的表也是按活法列的）；影子活法只算梅一个人、样本小，不算。所有活法加在一起的最大差也列出来
  const spread = {};
  const lined = (ev) => ev.options.filter((x) => x.min);
  for (const co of COHORTS) {
    if (co.id === BASE) continue;
    const cmp = (A, B, label) => {
      let best = { d: 0 };
      for (const ev of SHOWN) for (const o of lined(ev)) {
        const a = pct(A?.[ev.id], o.id), b = pct(B?.[ev.id], o.id);
        if (a === null || b === null) continue;
        if (Math.abs(a - b) > Math.abs(best.d)) best = { d: a - b, at: `${label}${ev.age} 岁 ${ev.id}.${o.id}`, a, b };
      }
      return best;
    };
    const all = cmp(by[co.id]?.acc, by[BASE]?.acc, "所有活法 · ");
    let way = { d: 0 };
    for (const [name, w] of Object.entries(WAYS)) {
      if (w.shadow) continue;
      const A = results.find((r) => r.cohort === co.id && r.way === name)?.acc;
      const B = results.find((r) => r.cohort === BASE && r.way === name)?.acc;
      const b = cmp(A, B, `【${name}】`);
      if (Math.abs(b.d) > Math.abs(way.d)) way = b;
    }
    spread[co.id] = { all, way };
    if (Math.abs(way.d) < 15) bad.push(`${co.id} 和 ${BASE} 按活法看最大只差 ${way.d} 个点（${way.at || "无"}），不到 15`);
  }
  return { bad, spread };
}

async function main() {
  const opt = args(process.argv.slice(2));
  const t0 = Date.now();
  const tasks = [];
  for (const co of COHORTS) for (const way of Object.keys(WAYS)) tasks.push({ cohort: co.id, way, n: opt.lives, until: opt.until, detail: opt.check && co.id === BASE });
  // --check 另跑一遍不指定年代的（paths.mjs 原样），过到 31 岁就够
  if (opt.check) for (const way of Object.keys(WAYS)) tasks.push({ cohort: null, way, n: opt.lives, until: 31, detail: true });
  process.stderr.write(`${tasks.length} 个任务，${opt.jobs} 个子进程\n`);
  const all = await pool(tasks, opt.jobs);
  const results = all.filter((r) => r.cohort !== null);
  const paths = all.filter((r) => r.cohort === null);
  const by = merge(results);
  console.log(table(by, opt, results));
  let verdict = null;
  if (opt.check) {
    verdict = check(results, paths, by);
    console.log("");
    console.log(`--check：c92 30 岁以前 ${EARLY.length} 道关 × ${Object.keys(WAYS).length} 种活法 × ${opt.lives} 条人生和 paths.mjs 默认年代逐条比对；别的年代和 c92 差得最多的一条（按活法 / 所有活法加在一起）：`);
    const show = (b) => `${b.at}  ${b.a}% vs ${b.b}%（${b.d > 0 ? "+" : ""}${b.d}）`;
    for (const [id, b] of Object.entries(verdict.spread)) console.log(`  ${id}  ${show(b.way)}\n        ${show(b.all)}`);
    if (verdict.bad.length) { console.log("不通过："); for (const b of verdict.bad.slice(0, 20)) console.log("  ✗ " + b); }
    else console.log("通过。");
  }
  console.log(`\n用时 ${((Date.now() - t0) / 1000).toFixed(0)} 秒`);
  if (opt.json) {
    const strip = results.map(({ lives, ...r }) => r);
    writeFileSync(opt.json, JSON.stringify({ lives: opt.lives, until: opt.until, base: BASE, cohorts: COHORTS.map(({ id, name, born }) => ({ id, name, born })), byCohort: by, byWay: strip, check: verdict }, null, 1));
  }
  if (verdict && verdict.bad.length) process.exit(1);
}

if (process.argv[2] === "--worker") {
  const t = JSON.parse(process.argv[3]);
  process.stdout.write(JSON.stringify(runTask(t.cohort, t.way, t.n, t.until, t.detail)));
} else if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
