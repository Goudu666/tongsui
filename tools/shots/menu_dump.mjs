#!/usr/bin/env node
// 给 tools/shots/menu.gd 准备几帧真服务器的状态，截点位菜单（协议 8）用。
// 用法：npm run server:build && node tools/shots/menu_dump.mjs [输出，默认 tools/shots/menu.json]
import { writeFileSync } from "node:fs";
import { G, C, fakeNakama, room } from "../../server/test/harness.mjs";

const OP = G("OP");
const out = process.argv[2] || new URL("./menu.json", import.meta.url).pathname;
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
const frames = {};
/** 某个岁数、某一段，两个人站在哪、对门先做了一回什么 */
function scene(name, age, slot, qSpot, mSpot, mAct) {
  const s = R.life();
  let turn = 0;
  while (G("lifeTimeAt")(turn).age < age) turn++;
  s.turn = turn;
  G("worldStartDay")(s, C);
  const w = s.world;
  w.rest = true;
  w.fate = { mirror: null, qing: null, mei: null };
  w.dutyDone = { qing: true, mei: true };
  w.slot = slot;
  w.minute = SLOTS[slot][0];
  const put = (r, id) => { const a = w.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; };
  put("qing", qSpot);
  put("mei", mSpot);
  if (mAct) { const e = G("worldAct")(s, C, "mei", mSpot, true, mAct).error; if (e) console.log("!", name, e); }
  w.event = null;
  R.sent.length = 0;
  R.loop();
  frames[name] = { snapshot: G("snapshot")(R.state, "qing"), world: G("worldView")(R.state) };
}
scene("teahouse", 17, 2, "tea_seat", "tea_seat", "tea_runner");
scene("park", 62, 4, "square_ground", "square_ground", null);
writeFileSync(out, JSON.stringify(frames));
console.log("✓", out, Object.keys(frames).join(" "));
