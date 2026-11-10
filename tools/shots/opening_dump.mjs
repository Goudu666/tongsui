#!/usr/bin/env node
// 给 tools/shots/opening.gd 准备几帧真服务器发出来的状态（SNAPSHOT / WORLD），截开局引导用。
// 用法：npm run server:build && node tools/shots/opening_dump.mjs [输出，默认 tools/shots/opening.json]
import { writeFileSync } from "node:fs";
import { G, C, fakeNakama, room } from "../../server/test/harness.mjs";

const OP = G("OP");
const out = process.argv[2] || new URL("./opening.json", import.meta.url).pathname;
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

const frames = {};
const grab = (name) => {
  // 截图只看引导：把命运里不是主线的那几件拿掉，免得一进来就弹一件随机的事挡住
  const w = R.life().world;
  for (const k of ["mirror", "qing", "mei"]) if (w.fate[k] && !G("storyFindEvent")(C, w.fate[k])) w.fate[k] = null;
  w.event = null;
  R.sent.length = 0;
  R.loop();
  R.loop();
  frames[name] = { snapshot: G("snapshot")(R.state, "qing"), world: G("worldView")(R.state) };
};
const life = () => R.life();
grab("day0_morning");
// 下楼到了街上：主线（上午，楼道里）在楼里，路标该指回「上楼」
const a = life().world.actors.qing;
const down = C.map.exits.find((e) => e.id === "building.hall_down");
a.x = down.arrive[0] + 300; a.y = down.arrive[1];
grab("day0_street");
// 某一天，换到第 n 个日子的早上（6 岁第二章、12 岁第三章 + 少年）
for (const [name, turn] of [["day12", 12], ["day36", 36]]) {
  const s = life();
  s.turn = turn;
  G("worldStartDay")(s, C);
  grab(name);
}
writeFileSync(out, JSON.stringify(frames));
console.log("✓", out, Object.keys(frames).map((k) => `${k}: ${frames[k].snapshot.life.turn} ${JSON.stringify(frames[k].world.story)}`).join("\n  "));
