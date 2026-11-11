#!/usr/bin/env node
// 关口冲刺量表：每道关有没有得拼（玩法总把关 11-11，诊断见项目文档「同岁：要做上瘾的那一个循环」）。
//
// 用法：npm run server:build && node tools/sprint.mjs [每种玩法几世，默认 7] [--seed=3]
//   跑「认真」「随便」两种玩法各 N 世（tools/playthrough.mjs，SNAP=1 每个日子收工记一次纸带上的线），
//   每道关看每个人在这一阶段第一天的处境：
//     无可冲 —— 纸带上所有的线开局就过了（这一阶段怎么过都改变不了这道关）
//     跨过   —— 开局没够着的线里，到考那天至少跨过了一条（这一阶段的时间花得值）
//     失手   —— 冲了，没够着
//   再加：一个阶段里纸带上分数涨了多少（百分制，中位数）、没够着的线里差 5 分以内的有几条。
//
// 硬指标（认真的人）：每道关「无可冲」≤ 两成、「跨过」≥ 三成五；随便的人涨得是认真的三分之一到一半。
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const N = Number(args.find((a) => /^\d+$/.test(a)) || 7);
const SEED0 = Number((args.find((a) => a.startsWith("--seed=")) || "--seed=3").slice(7));
const ORDER = ["六一", "上小学", "三年级", "小升初", "中考", "高考", "找个正经事由", "安家", "四十五", "退休", "七十"];
const dir = mkdtempSync(join(tmpdir(), "sprint-"));

const runs = [];
for (const persona of ["careful", "casual"]) {
  for (let i = 0; i < N; i++) {
    const seed = SEED0 + i * 7;
    const out = join(dir, `${persona}-${seed}.json`);
    runs.push(new Promise((ok, bad) => {
      const p = spawn(process.execPath, [join(here, "playthrough.mjs"), "1", `--seed=${seed}`, "--quiet", `--json=${out}`], { env: { ...process.env, PERSONA: persona, SNAP: "1" }, stdio: "ignore" });
      p.on("exit", (code) => (code === 0 ? ok() : bad(new Error(`${persona} seed ${seed} 退出码 ${code}`))));
    }));
  }
}
await Promise.all(runs);

const med = (a) => (a.length ? a.slice().sort((x, y) => x - y)[a.length >> 1] : "-");
for (const persona of ["careful", "casual"]) {
  const gates = {};
  const minutes = [];
  let near = 0, missed = 0;
  for (const f of readdirSync(dir).filter((f) => f.startsWith(persona))) {
    const life = JSON.parse(readFileSync(join(dir, f), "utf8"))[0];
    minutes.push(Math.round(life.ticks / 600));
    for (const r of ["qing", "mei"]) {
      const byGate = {};
      for (const d of life.days) { const g = d.snap && d.snap[r].goal; if (g) (byGate[g.t] = byGate[g.t] || []).push(g); }
      for (const t in byGate) {
        const days = byGate[t], a = days[0], b = days[days.length - 1];
        if (b.turns !== 0) continue; // 没过到这道关（人走了）
        const G = (gates[t] = gates[t] || { none: 0, cross: 0, fail: 0, gain: [] });
        const lines = a.lines.map((l) => ({ ...l, end: (b.lines.find((x) => x.id === l.id) || l).have }));
        if (lines.every((l) => l.have >= l.need)) G.none++;
        else if (lines.some((l) => l.have < l.need && l.end >= l.need)) G.cross++;
        else G.fail++;
        G.gain.push(Math.max(...lines.map((l) => l.end - l.have)));
        for (const l of lines) if (l.end < l.need) { missed++; if (l.need - l.end <= 5) near++; }
      }
    }
  }
  console.log(`\n== ${persona === "careful" ? "认真" : "随便"}（${N} 世，现实 ${minutes.join("/")} 分钟；没够着的线里差 5 分以内 ${near}/${missed}）`);
  console.log("关口".padEnd(8, "　") + "人数  无可冲  跨过  失手  阶段涨分中位");
  for (const t of ORDER) {
    const G = gates[t];
    if (!G) continue;
    const n = G.none + G.cross + G.fail;
    const pct = (v) => (Math.round((v / n) * 100) + "%").padStart(5);
    console.log(t.padEnd(8, "　") + String(n).padStart(3) + "  " + pct(G.none) + "  " + pct(G.cross) + " " + pct(G.fail) + "   " + med(G.gain));
  }
}
