#!/usr/bin/env node
// 网页单机版的冒烟：在 node 里装上 tongsui-local.js（假装是浏览器），开一条人生线、投胎、让电脑替两个人过几天，
// 查：服务器没回错、对门的电脑在做事、日子在往前走、存档写进了 localStorage、重开页面能接着过。
//   npm run server:build && node web/build.mjs build/web && node web/local.test.mjs build/web/tongsui-local.js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const file = process.argv[2] || new URL("../build/web/tongsui-local.js", import.meta.url).pathname;
const code = readFileSync(file, "utf8");
const disk = new Map();
function boot() {
  const timers = [];
  const ctx = {
    console, JSON, Math, Date, TextEncoder, TextDecoder, structuredClone, performance,
    localStorage: { getItem: (k) => (disk.has(k) ? disk.get(k) : null), setItem: (k, v) => disk.set(k, String(v)), removeItem: (k) => disk.delete(k) },
    document: { hidden: true }, // 不让定时器自己跑，测试里手动推
    setInterval: () => 0, setTimeout: (f) => { timers.push(f); return timers.length; }, clearTimeout: () => {},
    location: { reload() {} },
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(code, ctx);
  const flush = () => { while (timers.length) timers.shift()(); };
  return { T: ctx.TongsuiLocal, flush };
}

let { T, flush } = boot();
const rpc = (name, body) => JSON.parse(T.rpcCall(name, JSON.stringify(body)));
const D = () => T._debug();
const S = D().S;
const made = rpc("lifeline_create", { name: "小满" });
assert.ok(made.lifelineId && made.code, "开得出人生线");
const open = rpc("lifeline_open", { lifelineId: made.lifelineId, protocol: S.PROTOCOL_VERSION });
assert.ok(open.matchId, "对门的电脑已经输了配对码，房间直接开");
assert.equal(T.joinMatch(open.matchId, JSON.stringify({ protocol: String(S.PROTOCOL_VERSION) })), true, "进得去房间");
T.sendMsg(S.OP.ROLL, JSON.stringify({ confirm: true }));
T._autopilot(true); // 「你」也交给电脑
const errors = [];
let palActs = 0;
const startTurn = () => D().room.state.record.life.turn;
for (let i = 0; i < 10 * 60 * 25; i++) {
  D().step();
  const life = D().room.state.record.life;
  if (life.phase === "life" && life.world.actors.mei && life.world.actors.mei.action) palActs++;
  const out = T.drain();
  if (out) for (const m of JSON.parse(out)) if (m.op === S.OP.ERROR) errors.push(m.data);
}
const life = D().room.state.record.life;
assert.equal(life.phase, "life", "投胎过了，在过日子");
assert.deepEqual(errors, [], "服务器没回错");
assert.ok(palActs > 0, "对门的电脑在做事");
assert.ok(life.turn >= 3, `二十五分钟过了几个日子（现在第 ${life.turn} 个）`);
D().saveNow(); // 页面切到后台时会调
flush();
assert.ok(disk.size === 1, "存档写进了 localStorage");
const turn = life.turn;

// 重开页面：房间没了，存档还在，接着过
({ T, flush } = boot());
const list = rpc("lifeline_list", {});
assert.equal(list.lifelines.length, 1, "大厅里有上次那条");
const again = rpc("lifeline_open", { lifelineId: made.lifelineId, protocol: S.PROTOCOL_VERSION });
assert.ok(again.matchId, "重开页面后房间重新拉起来（存档里记的旧房间要清掉）");
assert.equal(T.joinMatch(again.matchId, "{}"), true);
assert.equal(T._debug().room.state.record.life.turn, turn, "从关掉的那一天接着过");
console.log(`✓ 网页单机版：投胎、过了 ${turn} 个日子、对门做了 ${palActs} 跳的事、没回错、存档能接着过`);
