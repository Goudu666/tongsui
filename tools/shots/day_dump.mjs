#!/usr/bin/env node
// 给 tools/shots/day.gd 准备几帧真服务器的状态，截「一件一件做」和一天收工的小结卡用。
// 用法：npm run server:build && node tools/shots/day_dump.mjs [输出，默认 tools/shots/day.json]
import { writeFileSync } from "node:fs";
import { G, C, fakeNakama, room } from "../../server/test/harness.mjs";

const OP = G("OP");
const out = process.argv[2] || new URL("./day.json", import.meta.url).pathname;
const env = fakeNakama();
const qa = { userId: "u-qing", sessionId: "s-qing" };
const ma = { userId: "u-mei", sessionId: "s-mei" };
const made = env.rpc("rpcLifelineCreate", qa.userId, { name: "小满" });
env.rpc("rpcLifelineJoin", ma.userId, { code: made.code, name: "阿蘅" });
const open = env.rpc("rpcLifelineOpen", qa.userId, { lifelineId: made.lifelineId });
const R = room(env.nk, open.matchId);
R.join([qa, ma]);
R.state.record.life.rng = 7;
R.loop([R.msg(qa, OP.ROLL, { confirm: true }), R.msg(ma, OP.ROLL, { confirm: true })]);
const SLOTS = G("SLOTS");
const spot = (id) => C.map.spots.find((sp) => sp.id === id);
const life = () => R.life();
// 十岁，歇着的一天，傍晚
let turn = 0;
while (G("lifeTimeAt")(turn).age < 10) turn++;
const s = life();
s.turn = turn + 1;
G("worldStartDay")(s, C);
const w = s.world;
w.rest = true;
w.fate = { mirror: null, qing: null, mei: null };
w.dutyDone = { qing: true, mei: true };
const put = (r, id) => { const a = w.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; };
const frames = {};
const grab = (name, extra = {}) => {
  w.event = null;
  R.sent.length = 0;
  R.loop();
  frames[name] = { snapshot: G("snapshot")(R.state, "qing"), world: G("worldView")(R.state), ...extra };
};
// 早上：吃口饭（顺手的事），下午以前一路做：早上翻书、上午写作业两回、踢球……都用一回一回的按法
const once = (r, id) => { put(r, id); const e = G("worldAct")(s, C, r, id, true).error; if (e) console.log("!", r, id, e); };
const fill = (r, id) => { put(r, id); const e = G("worldAct")(s, C, r, id).error; if (e) console.log("!", r, id, e); };
const pass = () => { const from = w.slot; for (let i = 0; i < 4000 && s.world && s.world.slot === from && s.turn === turn + 1; i++) { const t = G("worldAdvance")(s, C, 0.5, { qing: true, mei: true }); if (t.dayEnded) return t; } return null; };
// 早上
once("qing", "desk_qing"); fill("mei", "desk_mei"); pass();
// 上午：楼道里搭伴写作业，第一回之前截一张（按钮上写着花多久、累多少）
put("qing", "hall_stool"); put("mei", "hall_stool");
grab("am_open");
once("mei", "hall_stool");
grab("am_partner");
once("qing", "hall_stool");
grab("am_did");
once("qing", "hall_stool");
once("mei", "hall_stool");
grab("am_did2");
once("qing", "roof_pigeon"); w.ready.mei = true; pass();
// 下午、傍晚：各干各的
fill("qing", "alley_rope"); fill("mei", "tea_seat"); pass();
once("qing", "tea_seat"); once("qing", "tea_seat"); once("qing", "desk_qing"); fill("mei", "desk_mei"); pass();
// 晚上：写一回，睡下；对门写到点
once("qing", "desk_qing");
put("qing", "bed_qing");
G("worldAct")(s, C, "qing", "bed_qing");
fill("mei", "desk_mei");
const end = pass();
const day = end && end.entries.find((e) => e.kind === "day");
if (!day) throw new Error("一天没过完");
frames.day_end = { entry: day };
writeFileSync(out, JSON.stringify(frames));
console.log("✓", out, Object.keys(frames).join(" "), JSON.stringify(day.goal), JSON.stringify(day.spent.qing.map((x) => x.l + " " + x.f + "-" + x.t + (x.tg ? "*" : ""))));
