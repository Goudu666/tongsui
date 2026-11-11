#!/usr/bin/env node
// 三扇门量表：同一种活法下，清贫 / 小康 / 殷实三档人家各走到哪（docs/MEANS.md 第八节，方案「三扇门三种难度」）。
//
// 用法：npm run build && node tools/origin.mjs [每格几世，默认 20] [只跑这几种活法…]
//   两个人放进同一档人家（按种子轮流抽这一档里的各户，两人是不同的两户），用 tools/paths.mjs 的机器人过到 31 岁
//   （UNTIL=76 过完一辈子）。关口上总选够得着的最高那条线（climb），三十岁安家那一关先要个落脚的地方（settleFirst）。每格 = 一种活法 × 一档人家。
//
// 看的是方案里的目标表：
//   中考重点 —— 中考那天够得着市重点（考的或交钱的）
//   办公室   —— 二十二岁够得着坐办公室（考的或托关系的，董家爸妈安排的单位也算）
//   房 / 落脚 —— 三十岁那道关以后有自己的房（home_own）/ 有个落脚的地方（买、分、合住、翻修）
//   助学金   —— 清贫人家拿到过 aid；断供 —— 殷实人家走到了 fam_cut
//   ¥30      —— 三十岁那天早上积蓄的中位数
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(import.meta.url);
const TIERS = { 清贫: 0, 小康: 1, 殷实: 2 };
const DEFAULT_WAYS = ["不上心", "一个人念书", "搭伴念书", "从小挣钱"];
const HOMES = ["home_own", "home_share", "home_fixed"];

if (process.argv[2] === "--one") {
  // 子进程：跑一格，输出 JSON
  const { WAYS, live, climb, C } = await import("./paths.mjs");
  // 三十岁安家那一关想要个落脚的地方：够得着自己的房先买房，再是翻修、合住、分房这些（线高的在前），都够不着才按 climb。
  // climb 总挑线最高的，会拿一百块去租房，不去翻修六十块的老屋（安家那一关的线都是积蓄、亲近，比得了高低）
  const homeOf = (o) => (o.effects.flags.includes("home_own") ? 2 : HOMES.some((h) => o.effects.flags.includes(h)) ? 1 : 0);
  const settleFirst = (s, r, ev, open) => {
    if (ev.id !== "m_settle") return climb(s, r, ev, open);
    const homes = open.filter((o) => homeOf(o)).sort((a, b) => homeOf(b) - homeOf(a) || (b.min || 0) - (a.min || 0));
    return homes.length ? homes[0].id : climb(s, r, ev, open);
  };
  const [, , , way, tier, s0, n, until] = process.argv;
  const fams = C.families.filter((f) => f.wealth === Number(tier)).map((f) => f.id);
  const out = [];
  for (let i = 0; i < Number(n); i++) {
    const seed = (Number(s0) + i) * 7919;
    const pair = [fams[i % fams.length], fams[(i + 1) % fams.length]];
    const { s, marks } = live(seed, WAYS[way], Number(until), settleFirst, (st) => { st.rolls.qing.familyId = pair[0]; st.rolls.mei.familyId = pair[1]; });
    for (const r of ["qing", "mei"]) {
      const p = s.persons[r];
      const m = (id) => marks[id]?.[r];
      out.push({
        key: m("m_senior") ? ["far", "far_aid", "paid", "nest"].some((o) => m("m_senior").open.includes(o)) : null,
        desk: m("m_job") ? ["desk", "pull", "pull_home"].some((o) => m("m_job").open.includes(o)) : null,
        money30: m("m_settle") ? m("m_settle").money : null,
        settled: !!m("m_settle"),
        flags: p.flags,
      });
    }
  }
  console.log(JSON.stringify(out));
  process.exit(0);
}

const N = Number(process.argv.slice(2).find((a) => /^\d+$/.test(a)) || 20);
const only = process.argv.slice(2).filter((a) => !/^\d+$/.test(a));
const UNTIL = Number(process.env.UNTIL) || 31;
const ways = only.length ? only : DEFAULT_WAYS;
const jobs = [];
for (const way of ways) for (const tier in TIERS) jobs.push({ way, tier });

const run = (j) => new Promise((ok, bad) => {
  let buf = "";
  const p = spawn(process.execPath, [here, "--one", j.way, String(TIERS[j.tier]), "1", String(N), String(UNTIL)], { stdio: ["ignore", "pipe", "inherit"] });
  p.stdout.on("data", (d) => (buf += d));
  p.on("exit", (code) => (code === 0 ? ok({ ...j, rows: JSON.parse(buf) }) : bad(new Error(`${j.way} ${j.tier} 退出码 ${code}`))));
});
// 一次跑四格
const results = [];
for (let i = 0; i < jobs.length; i += 4) results.push(...(await Promise.all(jobs.slice(i, i + 4).map(run))));

const pct = (rows, f) => { const xs = rows.filter((x) => f(x) !== null); return xs.length ? Math.round((100 * xs.filter(f).length) / xs.length) + "%" : "-"; };
const med = (a) => (a.length ? Math.round(a.slice().sort((x, y) => x - y)[a.length >> 1]) : "-");
console.log(`每格 ${N} 世（${N * 2} 个人），过到 ${UNTIL} 岁。\n`);
console.log(["活法", "出身", "中考重点", "办公室", "房", "落脚", "助学金", "断供", "¥30"].join("\t"));
for (const r of results) {
  const rows = r.rows, s30 = rows.filter((x) => x.settled);
  const has = (f) => (x) => x.flags.includes(f);
  console.log([
    r.way, r.tier,
    pct(rows, (x) => x.key), pct(rows, (x) => x.desk),
    s30.length ? pct(s30, has("home_own")) : "-",
    s30.length ? pct(s30, (x) => HOMES.some((h) => x.flags.includes(h))) : "-",
    r.tier === "清贫" ? pct(rows, has("aid")) : "",
    r.tier === "殷实" ? pct(rows, has("fam_cut")) : "",
    med(s30.map((x) => x.money30)),
  ].join("\t"));
}
