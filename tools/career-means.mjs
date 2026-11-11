#!/usr/bin/env node
// 家境口径（docs/MEANS.md）复量：同一个种子、同一种活法，把两个人都放进殷实人家 / 小康人家各过一遍到 37 岁，
// 看升一级（26 岁）、升两级（36 岁）的比例。殷实比小康多不超过 15 个点。
// 用法：npm run build && node tools/career-means.mjs [每种活法几世，默认 16] [殷实人家 id，默认 xu] [小康人家 id，默认 zhou]
import { WAYS, live, climb } from "./paths.mjs";
const args = process.argv.slice(2);
const N = Number(args[0]) || 16, RICH = args[1] || "xu", MID = args[2] || "zhou";
const ways = ["不上心", "一个人念书", "搭伴念书", "一个人练身体", "嘴甜人缘好", "一半念书一半玩", "混着来"];
const pct = (n, d) => (Math.round((n / d) * 100) + "%").padStart(5);
let worst = 0;
console.log(`每种活法 ${N} 世，两个人放进同一档人家。殷实 ${RICH} / 小康 ${MID}：升一级、升两级`);
for (const name of ways) {
  const got = {};
  for (const fam of [RICH, MID]) {
    let n = 0, r1 = 0, r2 = 0;
    for (let i = 0; i < N; i++) {
      const { s } = live(4000 + i * 37, WAYS[name], 37, climb, (s) => { s.rolls.qing.familyId = fam; s.rolls.mei.familyId = fam; });
      for (const r of ["qing", "mei"]) { const p = s.persons[r]; if (!p.alive) continue; n++; if (p.flags.includes("rank1") || p.flags.includes("rank2")) r1++; if (p.flags.includes("rank2")) r2++; }
    }
    got[fam] = [r1 / n, r2 / n, n];
  }
  const d1 = (got[RICH][0] - got[MID][0]) * 100, d2 = (got[RICH][1] - got[MID][1]) * 100;
  worst = Math.max(worst, d1, d2);
  console.log(name.padEnd(9, "　") + " 升一级 " + pct(got[RICH][0] * 100, 100) + " /" + pct(got[MID][0] * 100, 100) + "   升两级 " + pct(got[RICH][1] * 100, 100) + " /" + pct(got[MID][1] * 100, 100) + `   差 ${Math.round(d1)} / ${Math.round(d2)} 点`);
}
console.log(`最大差 ${Math.round(worst)} 个点（口径 ≤ 15）`);
