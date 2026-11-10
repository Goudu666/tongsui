// 搭伴小游戏（放风筝）：什么时候问 / 不玩照常 / 玩的结果只落在这一次搭伴的倍率上 / 房间里的收发。
import assert from "node:assert/strict";
import { G, C, NAMES, fakeNakama, room } from "./harness.mjs";

const OP = G("OP");
const ON = { qing: true, mei: true };
const BANK = C.map.spots.find((s) => s.action === "play_river");

function newLife(seed) {
  const s = G("lifeCreate")(seed, C);
  G("lifeConfirm")(s, C, "qing", NAMES);
  G("lifeConfirm")(s, C, "mei", NAMES);
  s.world.fate = { mirror: null, qing: null, mei: null };
  return s;
}
/** 两个人都走到河边，一起放风筝 */
function pair(s) {
  for (const r of ["qing", "mei"]) {
    s.world.actors[r].x = BANK.at[0];
    s.world.actors[r].y = BANK.at[1];
    assert.equal(G("worldAct")(s, C, r, BANK.id).error, null);
  }
}
const tick = (s, n = 1, online = ON) => { let last; for (let i = 0; i < n; i++) { last = G("gameTick")(s, C, 0.1, online); if (last.closed) break; } return last; };
/** 一个会放的人：盯着 lag 秒之前的风口，手有点抖 */
function play(s, { lag = 0.3, shake = 0, idle = false } = {}) {
  const g = s.world.game;
  const hist = [];
  let out, n = 0;
  do {
    const d = g.d;
    if (d && !idle) {
      hist.push([d.wx, d.wh]);
      const [wx, wh] = hist[Math.max(0, hist.length - 1 - Math.round(lag * 10))];
      const wob = shake * Math.sin(n * 0.37);
      const runner = d.holder === "qing" ? "mei" : "qing";
      G("gameInput")(s, d.holder, { k: "line", v: (wh - 0.06) / 0.9 + wob });
      G("gameInput")(s, runner, { k: "run", v: wx + wob });
    }
    out = G("gameTick")(s, C, 0.1, ON);
    assert.ok(++n < 1000, "一局没打完");
  } while (!out.closed);
  return out;
}

// ---------- 1. 什么时候问，问了以后 ----------
{
  const s = newLife(11);
  const w = s.world;
  // 一个人放：不问
  w.actors.qing.x = BANK.at[0]; w.actors.qing.y = BANK.at[1];
  G("worldAct")(s, C, "qing", BANK.id);
  tick(s);
  assert.equal(w.game ?? null, null, "一个人放风筝不问");
  // 对方不在线（影子）：不问
  w.actors.mei.x = BANK.at[0]; w.actors.mei.y = BANK.at[1];
  G("worldAct")(s, C, "mei", BANK.id);
  tick(s, 1, { qing: true, mei: false });
  assert.equal(w.game ?? null, null, "影子不玩小游戏");
  // 两人都在线：问一句，表停住
  tick(s);
  assert.equal(w.game.phase, "offer");
  const m0 = w.minute;
  G("worldAdvance")(s, C, 1, ON);
  assert.equal(w.minute, m0, "问的时候停表");
  // 没人理：8 秒后当没问过，行动照常结算
  const out = tick(s, 100);
  assert.ok(out.closed && out.result === null);
  assert.equal(w.game, null);
  assert.equal(w.actors.qing.boost, undefined, "没玩就不写倍率");
  for (let i = 0; i < 50 && w.actors.qing.action; i++) G("worldAdvance")(s, C, 0.1, ON);
  assert.equal(w.actors.qing.action, null, "行动照常结束");
  // 今天问过了，再一起放也不问
  pair(s);
  tick(s);
  assert.equal(w.game, null, "每天只问一次");

  // 有人点「不了」
  const s2 = newLife(12);
  pair(s2); tick(s2);
  G("gameInput")(s2, "qing", { k: "ready" });
  assert.equal(s2.world.game.ready.qing, true);
  assert.ok(G("gameInput")(s2, "mei", { k: "pass" }).closed);
  assert.equal(s2.world.game, null);

  // 玩到一半有人掉线：当没玩过
  const s3 = newLife(13);
  pair(s3); tick(s3);
  G("gameInput")(s3, "qing", { k: "ready" });
  G("gameInput")(s3, "mei", { k: "ready" });
  tick(s3, 40);
  assert.equal(s3.world.game.phase, "play");
  const dropped = tick(s3, 1, { qing: true, mei: false });
  assert.ok(dropped.closed && dropped.result === null);
  assert.equal(s3.world.actors.qing.boost, undefined);
  console.log("✓ 搭伴小游戏：一个人不问 / 影子不问 / 问的时候停表 / 没人理照常 / 每天一次 / 不了 / 掉线当没玩过");
}

// ---------- 2. 放风筝：只管自己那一头，结果只落在倍率上 ----------
{
  const s = newLife(21);
  pair(s); tick(s);
  G("gameInput")(s, "qing", { k: "ready" });
  G("gameInput")(s, "mei", { k: "ready" });
  tick(s);
  const g = s.world.game;
  assert.equal(g.phase, "play");
  tick(s, 31); // 开局前三秒
  const d = g.d;
  const runner = d.holder === "qing" ? "mei" : "qing";
  // 管错了头的输入不算
  G("gameInput")(s, runner, { k: "line", v: 0.9 });
  G("gameInput")(s, d.holder, { k: "run", v: 0.9 });
  assert.ok(d.tl < 0.1 && d.tx === 0.5, "各管各的一头");
  G("gameInput")(s, d.holder, { k: "line", v: "abc" });
  G("gameInput")(s, d.holder, { k: "line", v: 99 });
  assert.equal(d.tl, 1, "乱报的数会被夹住");
  const before = JSON.stringify([s.persons, s.bond, s.memories, s.log.length]);
  const m0 = s.world.minute;
  const out = play(s);
  assert.equal(JSON.stringify([s.persons, s.bond, s.memories, s.log.length]), before, "小游戏不碰属性、关系、回忆、日志");
  assert.equal(s.world.minute, m0, "也不占这一天的时间");
  assert.ok(out.result.boost >= 1.5 && out.result.boost <= 2.0);
  assert.equal(s.world.actors.qing.boost, out.result.boost);
  assert.equal(s.world.actors.mei.boost, out.result.boost);
  assert.equal(s.world.actors.qing.action, "play_river", "人还在放风筝，行动接着走");

  // 行动做完：这一次长的属性乘上倍率，用完就清掉，不带到下一件事
  const act = C.map.actions.find((x) => x.id === "play_river");
  // 属性越高长得越慢，还会四舍五入到千分位（一次只长百分之几，所以比值留 0.08 的余量）：三边都从同一个低起点比。
  // 两个人体魄一样，免得「强的带弱的」那一截混进来（world.ts → LEAD_PER_POINT）
  const body0 = 2;
  const level = (life) => { life.persons.qing.stats.body = body0; life.persons.mei.stats.body = body0; };
  level(s);
  G("worldFinish")(s, C, "qing");
  // 对照一：一个人放
  const alone = newLife(21);
  alone.world.actors.qing.x = BANK.at[0]; alone.world.actors.qing.y = BANK.at[1];
  assert.equal(G("worldAct")(alone, C, "qing", BANK.id).error, null);
  level(alone);
  G("worldFinish")(alone, C, "qing");
  // 对照二：两个人搭伴放，但没玩小游戏
  const plain = newLife(21);
  pair(plain);
  level(plain);
  G("worldFinish")(plain, C, "qing");
  const grew = s.persons.qing.stats.body - body0, solo = alone.persons.qing.stats.body - body0, usual = plain.persons.qing.stats.body - body0;
  assert.ok(solo > 0 && Math.abs(grew / solo - out.result.boost) < 0.08, `长得是一个人放的 ×${out.result.boost}（实际 ×${(grew / solo).toFixed(2)}）`);
  assert.ok(Math.abs(usual / solo - G("TOGETHER_BOOST")) < 0.08, `不玩小游戏，搭伴也有默认的 ×${G("TOGETHER_BOOST")}（实际 ×${(usual / solo).toFixed(2)}）`);
  assert.ok(grew >= usual - 1e-9, "玩了不会比不玩差");
  assert.equal(s.world.actors.qing.boost, undefined, "倍率用完就清");
  assert.ok(act.stats.body > 0);
  s.world.actors.mei.action = null; // 另一个人半路走了去做别的
  s.world.actors.mei.until = null;
  const spot = C.map.spots.find((x) => x.action === "play_alley");
  s.world.actors.mei.x = spot.at[0]; s.world.actors.mei.y = spot.at[1];
  const r = G("worldAct")(s, C, "mei", spot.id);
  if (!r.error) assert.equal(s.world.actors.mei.boost, undefined, "换了一件事，倍率不跟过去");

  // 手感分布：都不动 / 配合得上 / 配合得好
  const run = (opt) => {
    const xs = [];
    for (let seed = 1; seed <= 40; seed++) {
      const t = newLife(seed * 31);
      pair(t); tick(t);
      G("gameInput")(t, "qing", { k: "ready" });
      G("gameInput")(t, "mei", { k: "ready" });
      tick(t);
      xs.push(play(t, opt).result);
    }
    xs.sort((a, b) => a.score - b.score);
    return xs;
  };
  const idle = run({ idle: true }), ok = run({ lag: 0.8, shake: 0.15 }), good = run({ lag: 0.25, shake: 0.03 });
  assert.ok(idle[20].boost <= 1.6, "两个人都不动，倍率接近下限");
  assert.ok(good[20].boost >= 1.9, "配合得好，倍率接近上限");
  assert.ok(ok[20].score > idle[20].score && ok[20].score < good[20].score);
  const fmt = (xs) => `${xs[20].score} 分 ×${xs[20].boost}`;
  console.log(`✓ 放风筝：各管一头 / 只写倍率 / 不占时间  |  中位数：不动 ${fmt(idle)}，手生 ${fmt(ok)}，默契 ${fmt(good)}`);
}

// ---------- 3. 房间里：消息号、广播、结果 ----------
{
  const env = fakeNakama();
  const pa = { userId: "user-a", sessionId: "sa" }, pb = { userId: "user-b", sessionId: "sb" };
  const a = env.rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  env.rpc("rpcLifelineJoin", "user-b", { code: a.code, name: "小梅" });
  const R = room(env.nk, env.rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId }).matchId);
  R.join([pa, pb]);
  R.loop([R.msg(pa, OP.ROLL, { confirm: true }), R.msg(pb, OP.ROLL, { confirm: true })]);
  const life = R.life();
  life.world.fate = { mirror: null, qing: null, mei: null };
  for (const r of ["qing", "mei"]) { life.world.actors[r].x = BANK.at[0]; life.world.actors[r].y = BANK.at[1]; }
  R.loop([R.msg(pa, OP.ACT, { spot: BANK.id }), R.msg(pb, OP.ACT, { spot: BANK.id })]);
  const offers = R.sent.filter((m) => m.op === OP.GAME);
  assert.equal(offers.at(-1).data.game.phase, "offer", "两人一搭上伴就问");
  const minute = life.world.minute;
  R.loop([R.msg(pa, OP.GAME_INPUT, { k: "ready" })]);
  R.loop([R.msg(pb, OP.GAME_INPUT, { k: "ready" })]);
  R.loop();
  assert.equal(R.sent.filter((m) => m.op === OP.GAME).at(-1).data.game.phase, "play");
  for (let i = 0; i < 400 && life.world.game; i++) R.loop();
  const last = R.sent.filter((m) => m.op === OP.GAME).at(-1).data;
  assert.equal(last.game, null);
  assert.ok(last.result.boost >= 1.5, "打完广播结果");
  assert.ok(life.world.minute - minute <= 4.01, "从问到打完表没走（最后一跳关局后才接着走）");
  assert.ok(!R.sent.some((m) => m.op === OP.ERROR), "没有报错");
  for (let i = 0; i < 30 && life.world.actors.qing.action; i++) R.loop();
  assert.equal(life.world.actors.qing.action, null, "打完行动接着走完");
  console.log("✓ 房间：搭上伴就问 / 两人都点了才开 / 打完广播结果 / 全程停表 / 行动照常走完");
}
