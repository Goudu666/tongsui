#!/usr/bin/env node
// 职业路线量表（docs/CAREER.md）：两道升迁关（26 站住脚、36 挑大梁）每个行当有没有得拼，升上去的人挣多少。
// 用法：npm run build && node tools/career.mjs [每种活法几世，默认 24] [--json=out.json]
//   用 tools/paths.mjs 的活法机器人（关口上总选够得着的最高那条线）把人生过到 37 岁。
//   每个人按他在这道关上自己那一行的升级线（up_* / top_*）看：
//     开局已过 —— 这一阶段第一天（26 关看 22 岁那天，36 关看 30 岁那天）就够着了
//     跨过     —— 第一天没够着、到关口那天够着了
//     没够着
//   硬指标（专心的活法）：开局已过 ≤ 三成五、跨过 ≥ 三成五；不上心的大多没够着。
//   家境：同一种活法殷实比小康多够着的不超过 15 个点（docs/MEANS.md，殷实另有花钱的路，按「本行的线 或 家里托人」算）。
import { WAYS, live, climb } from "./paths.mjs";
import { readFileSync, writeFileSync } from "node:fs";
import vm from "node:vm";

const code = readFileSync(new URL("../server/build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math, Date });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);
const C = G("CONTENT");
const args = process.argv.slice(2);
const N = Number(args.find((a) => /^\d+$/.test(a)) || 24);
const jsonOut = (args.find((a) => a.startsWith("--json=")) || "").slice(7);
const R1 = C.events.find((e) => e.id === "m_rise"), R2 = C.events.find((e) => e.id === "m_rise2");
const JOB = { job_desk: "desk", job_pull: "pull", job_teach: "teach", job_trade: "trade", job_craft: "craft", job_labor: "labor", job_succeed: "factory", job_odd: "odd" };
const careerOf = (flags) => (flags.includes("left_city") && !flags.includes("came_back") ? "away" : JOB[Object.keys(JOB).find((f) => flags.includes(f))] || "odd");
const score = (m, w) => Object.entries(w).reduce((a, [k, v]) => a + (k === "money" ? m.money : m.stats[k] || 0) * v, 0);
const lineOf = (ev, id) => ev.options.find((o) => o.id === id);
const fam = (s, r) => C.families.find((f) => f.id === s.rolls[r].familyId).wealth;

const rows = [];
const ways = Object.entries(WAYS).filter(([n, w]) => !w.shadow);
let k = 0;
for (const [name, way] of ways) {
  for (let i = 0; i < N; i++) {
    const seed = 9000 + 131 * k++;
    const { s, marks } = live(seed, way, 37, climb);
    for (const r of ["qing", "mei"]) {
      const p = s.persons[r];
      const m22 = marks.m_job?.[r], m26 = marks.m_rise?.[r], m30 = marks.m_settle?.[r], m36 = marks.m_rise2?.[r];
      if (!m26) continue;
      const log = s.log.filter((e) => e.results && e.results[r]);
      const chose = (id) => log.find((e) => e.events[r] === id)?.results[r].option || null;
      const row = { career26: careerOf(m26.flags), way: name, wealth: fam(s, r), career: careerOf(p.flags), rise: chose("m_rise"), rise2: chose("m_rise2"), rank: p.flags.includes("rank2") ? 2 : p.flags.includes("rank1") ? 1 : 0, money30: m30 ? Math.round(m30.money) : null, money36: m36 ? Math.round(m36.money) : null, alive: p.alive };
      // 26 关：看自己这一行（26 岁那天的行当）的 up_ 线
      const c26 = (() => { const o = R1.options.find((o) => o.id.startsWith("up_") && m26.open.includes(o.id)) ; return o; })();
      const myUp = R1.options.find((o) => o.id === "up_" + careerAt(m26));
      if (myUp && m22) { row.s22 = +score(m22, myUp.score).toFixed(2); row.s26 = +score(m26, myUp.score).toFixed(2); }
      if (m36 && m30) { const t = R2.options.find((o) => o.id === "top_" + careerAt(m36)); if (t) { row.s30 = +score(m30, t.score).toFixed(2); row.s36 = +score(m36, t.score).toFixed(2); } }
      if (myUp && m22) {
        const need = myUp.min;
        row.g26 = score(m22, myUp.score) >= need ? "none" : score(m26, myUp.score) >= need ? "cross" : "fail";
        row.g26open = m26.open.includes(myUp.id) || m26.open.includes("seat");
      }
      if (m36 && m30) {
        const myTop = R2.options.find((o) => o.id === "top_" + careerAt(m36));
        if (myTop && (m36.open.includes(myTop.id) || m36.flags1)) {}
        const had1 = rowRank1At36(s, r);
        if (myTop && had1) {
          const need = myTop.min;
          row.g36 = score(m30, myTop.score) >= need ? "none" : score(m36, myTop.score) >= need ? "cross" : "fail";
        }
      }
      rows.push(row);
    }
  }
}
function careerAt(m) { return careerOf(m.flags); }
function rowRank1At36(s, r) { const e = s.log.find((e) => e.events && e.events[r] === "m_rise" && e.results && e.results[r]); const o = e && R1.options.find((x) => x.id === e.results[r].option); return !!(o && o.effects.flags.includes("rank1")); }

const pct = (a, f) => (a.length ? Math.round((a.filter(f).length / a.length) * 100) + "%" : "-").padStart(5);
console.log(`每种活法 ${N} 世（两个人），过到 37 岁。\n`);
console.log("== 26 站住脚 / 36 挑大梁（按活法）：开局已过 / 跨过 / 没够着，升到的级");
for (const [name] of ways) {
  const a = rows.filter((x) => x.way === name), b = a.filter((x) => x.g26), c = a.filter((x) => x.g36);
  console.log(name.padEnd(9, "　") + " 26: " + pct(b, (x) => x.g26 === "none") + pct(b, (x) => x.g26 === "cross") + pct(b, (x) => x.g26 === "fail") + "   36: " + pct(c, (x) => x.g36 === "none") + pct(c, (x) => x.g36 === "cross") + pct(c, (x) => x.g36 === "fail") + "   升一级 " + pct(a, (x) => x.rank >= 1) + " 升两级 " + pct(a, (x) => x.rank >= 2) + "   积蓄30 " + String(med(a.map((x) => x.money30))).padStart(4) + " 36 " + String(med(a.map((x) => x.money36))).padStart(4));
}
console.log("\n== 按行当（所有活法合起来）：人数，26 开局已过/跨过/没够着，36 同，升一级 / 升两级");
for (const car of ["desk", "pull", "teach", "trade", "craft", "labor", "factory", "odd", "away"]) {
  const a = rows.filter((x) => x.career26 === car || (x.career26 === undefined && x.career === car)), b = a.filter((x) => x.g26), c = a.filter((x) => x.g36);
  console.log(car.padEnd(8) + String(a.length).padStart(4) + "  26: " + pct(b, (x) => x.g26 === "none") + pct(b, (x) => x.g26 === "cross") + pct(b, (x) => x.g26 === "fail") + "   36: " + pct(c, (x) => x.g36 === "none") + pct(c, (x) => x.g36 === "cross") + pct(c, (x) => x.g36 === "fail") + "   " + pct(a, (x) => x.rank >= 1) + pct(a, (x) => x.rank >= 2));
}
console.log("\n== 26 关上选了什么");
const pick = {}; for (const x of rows) if (x.rise) pick[x.rise] = (pick[x.rise] || 0) + 1;
console.log(Object.entries(pick).sort((a, b) => b[1] - a[1]).map(([k, v]) => k + " " + v).join("  "));
const pick2 = {}; for (const x of rows) if (x.rise2) pick2[x.rise2] = (pick2[x.rise2] || 0) + 1;
console.log("36：" + Object.entries(pick2).sort((a, b) => b[1] - a[1]).map(([k, v]) => k + " " + v).join("  "));
console.log("\n== 家境（同一种活法，升一级的比例：殷实 / 小康 / 清贫）");
for (const [name] of ways) {
  const a = rows.filter((x) => x.way === name);
  console.log(name.padEnd(9, "　") + pct(a.filter((x) => x.wealth === 2), (x) => x.rank >= 1) + pct(a.filter((x) => x.wealth === 1), (x) => x.rank >= 1) + pct(a.filter((x) => x.wealth === 0), (x) => x.rank >= 1) + "   升两级" + pct(a.filter((x) => x.wealth === 2), (x) => x.rank >= 2) + pct(a.filter((x) => x.wealth === 1), (x) => x.rank >= 2) + pct(a.filter((x) => x.wealth === 0), (x) => x.rank >= 2) + "   (n " + [2, 1, 0].map((w) => a.filter((x) => x.wealth === w).length).join("/") + ")");
}
function med(a) { a = a.filter((x) => x !== null && x !== undefined).sort((x, y) => x - y); return a.length ? a[a.length >> 1] : "-"; }
if (jsonOut) writeFileSync(jsonOut, JSON.stringify(rows));
