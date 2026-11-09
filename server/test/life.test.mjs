// 冒烟测试：把编译好的 build/index.js 放进一个假的 Nakama 环境里。
// 1) 抽卡规则；2) 用「影子」跑完 60 条完整人生（两人都离线，全靠影子过日子）；
// 3) 走一遍联机：配对 → 抽卡 → 走动 → 行动/同框 → 事件 → 一天结束 → 影子代选 → 关房。
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const code = readFileSync(new URL("../build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);
const C = G("CONTENT");
const J = (x) => JSON.parse(JSON.stringify(x));

// ---------- 1. 抽卡 ----------
{
  const s = G("lifeCreate")(42, C);
  assert.equal(s.phase, "roll");
  assert.notEqual(s.rolls.qing.familyId, s.rolls.mei.familyId, "两户人家不能相同");
  for (let i = 0; i < 3; i++) assert.equal(G("lifeReroll")(s, C, "qing"), null);
  assert.match(G("lifeReroll")(s, C, "qing"), /次数/);
  assert.notEqual(s.rolls.qing.familyId, s.rolls.mei.familyId);
  for (const v of Object.values(s.rolls.mei.stats)) assert.ok(v >= 0 && v <= 10);
  assert.equal(G("lifeConfirm")(s, C, "qing", { qing: "青", mei: "梅" }), false);
  assert.equal(G("lifeConfirm")(s, C, "mei", { qing: "青", mei: "梅" }), true);
  assert.equal(s.phase, "life");
  assert.ok(s.world && s.world.minute === 390);
  const fam = C.families.find((f) => f.id === s.persons.qing.familyId);
  assert.equal(s.persons.qing.money, fam.money);
  // 分布：1000 次抽卡里每户人家都出现过
  const seen = new Set();
  for (let i = 0; i < 1000; i++) seen.add(G("lifeRollOnce")({ rng: i * 7919 }, C, null).familyId);
  assert.equal(seen.size, C.families.length);
  console.log("✓ 抽卡：邻居不同户 / 重抽 3 次 / 属性 0~10 / 两人确认后开局 / 十户人家都抽得到");
}

// ---------- 2. 完整人生（全影子） ----------
{
  const turns = [], together = [], memories = [], events = [];
  for (let seed = 1; seed <= 60; seed++) {
    const s = G("lifeCreate")(seed, C);
    G("lifeConfirm")(s, C, "qing", { qing: "青", mei: "梅" });
    G("lifeConfirm")(s, C, "mei", { qing: "青", mei: "梅" });
    let ticks = 0;
    while (s.phase !== "ended") {
      const t = G("worldAdvance")(s, C, 0.1, { qing: false, mei: false });
      if (s.world && s.world.event) {
        const pe = s.world.event;
        for (const r of pe.roles) G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, pe.eventId), true);
      }
      assert.ok(++ticks < 400000, "人生没有结束");
    }
    assert.equal(s.log.at(-1).kind, "end");
    assert.equal(s.log.filter((e) => e.kind === "death").length, 2);
    for (const r of ["qing", "mei"]) {
      for (const v of Object.values(s.persons[r].stats)) assert.ok(v >= 0 && v <= 10);
      for (const v of Object.values(s.persons[r].needs)) assert.ok(v >= 0 && v <= 100);
    }
    turns.push(s.turn);
    together.push(s.log.filter((e) => e.kind === "together").length);
    memories.push(s.memories.length);
    events.push(s.log.filter((e) => e.kind === "mirror" || e.kind === "solo").length);
  }
  const avg = (a) => (a.reduce((x, y) => x + y, 0) / a.length).toFixed(1);
  console.log(`✓ 60 条影子人生跑完  平均 ${avg(turns)} 天  同框 ${avg(together)} 次  事件 ${avg(events)} 个  回忆 ${avg(memories)} 段`);
}

// ---------- 3. 世界规则单点 ----------
{
  const s = G("lifeCreate")(7, C);
  G("lifeConfirm")(s, C, "qing", { qing: "青", mei: "梅" });
  G("lifeConfirm")(s, C, "mei", { qing: "青", mei: "梅" });
  s.world.fate = { mirror: null, qing: null, mei: null }; // 这里只测行动
  const w = s.world;
  assert.match(G("worldAct")(s, C, "qing", "river_bank").error, /走近/);
  assert.match(G("worldAct")(s, C, "qing", "bed_mei").error, /走近|不是你的家/);
  // 限速：一次上报 2000 像素会被截断
  G("worldMove")(s, C, "qing", 2300, 560, 0.1);
  assert.ok(w.actors.qing.x < 400, "瞬移要被限速");
  // 两人都去楼下早点铺买煎饼果子 → 同框；钱不够买不了
  for (const r of ["qing", "mei"]) { w.actors[r].x = 1630; w.actors[r].y = 470; s.persons[r].money = 10; }
  s.persons.mei.money = 1;
  assert.match(G("worldAct")(s, C, "mei", "breakfast_stall").error, /钱/);
  s.persons.mei.money = 10;
  assert.equal(G("worldAct")(s, C, "qing", "breakfast_stall").error, null);
  const both = G("worldAct")(s, C, "mei", "breakfast_stall");
  assert.equal(both.error, null);
  assert.ok(both.together, "一起买煎饼果子应触发同框");
  const closeBefore = s.bond.close;
  // 两人都忙时时间快进
  const m0 = w.minute;
  G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.ok(w.minute - m0 > 3, "两人都忙时应快进");
  for (let i = 0; i < 200 && w.actors.qing.action; i++) G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.equal(w.actors.qing.action, null, "行动应结束");
  assert.ok(s.bond.close >= closeBefore);
  // 两人都去睡觉 → 一天结束，进入下一天
  for (const r of ["qing", "mei"]) { const sp = C.map.spawn[r]; w.actors[r].x = sp[0]; w.actors[r].y = sp[1]; }
  assert.equal(G("worldAct")(s, C, "qing", "bed_qing").error, null);
  assert.equal(G("worldAct")(s, C, "mei", "bed_mei").error, null);
  const t = G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.ok(t.dayEnded && s.turn === 1 && s.world.minute === 390);
  // mirror 事件：两人都在 where 才触发
  const mev = C.events.find((e) => e.id === "c_roof_summer");
  s.world.fate = { mirror: mev.id, qing: null, mei: null };
  s.world.minute = 1100;
  s.world.actors.qing.x = 600; s.world.actors.qing.y = 130;
  G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.equal(s.world.event, null, "只有一个人到了不触发");
  s.world.actors.mei.x = 900; s.world.actors.mei.y = 120;
  const st = G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.equal(st.started.eventId, "c_roof_summer");
  const m1 = s.world.minute;
  G("worldAdvance")(s, C, 1, { qing: true, mei: true });
  assert.equal(s.world.minute, m1, "选择时时间停住");
  assert.equal(G("worldChoose")(s, C, "qing", "stars", false).entry, null);
  const res = G("worldChoose")(s, C, "mei", "stars", false).entry;
  assert.equal(res.resonance, true);
  assert.equal(s.memories.at(-1).title, "第四十七颗星");
  console.log("✓ 世界：距离判定 / 不能睡别人家 / 限速 / 同框 / 快进 / 行动结算 / 睡觉换天 / 地点触发 / 选择时停表 / 共鸣回忆");
}

// ---------- 4. 联机流程（假 Nakama） ----------
{
  const store = new Map();
  const k = (c, key, u) => `${c}/${u}/${key}`;
  let matchSeq = 0;
  const matches = new Map();
  const nk = {
    uuidv4: () => `uuid-${Math.random().toString(16).slice(2)}`,
    storageRead: (reqs) => reqs.flatMap((r) => (store.has(k(r.collection, r.key, r.userId)) ? [{ key: r.key, value: structuredClone(store.get(k(r.collection, r.key, r.userId))) }] : [])),
    storageWrite: (ws) => ws.forEach((w) => store.set(k(w.collection, w.key, w.userId), structuredClone(w.value))),
    storageList: (u, c) => ({ objects: [...store.entries()].filter(([key]) => key.startsWith(`${c}/${u}/`)).map(([key, value]) => ({ key: key.split("/")[2], value })) }),
    matchCreate: (name, params) => { const id = `m${++matchSeq}`; matches.set(id, params); return id; },
    matchGet: (id) => (matches.has(id) ? { matchId: id } : null),
    binaryToString: (b) => Buffer.from(b).toString("utf8"),
  };
  const logger = { info() {}, warn() {}, error() {}, debug() {} };
  const rpc = (name, userId, payload) => JSON.parse(G(name)({ userId }, logger, nk, JSON.stringify(payload)));

  const a = rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  assert.equal(a.code.length, 6);
  assert.throws(() => rpc("rpcLifelineJoin", "user-b", { code: "NOPE00" }));
  const b = rpc("rpcLifelineJoin", "user-b", { code: a.code.toLowerCase(), name: "小梅" });
  assert.equal(b.role, "mei");
  assert.throws(() => rpc("rpcLifelineJoin", "user-c", { code: a.code }), /两个人/);
  const openA = rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId });
  const openB = rpc("rpcLifelineOpen", "user-b", { lifelineId: a.lifelineId });
  assert.equal(openA.matchId, openB.matchId, "两人应进入同一个房间");
  assert.equal(rpc("rpcLifelineList", "user-a", {}).lifelines.length, 1);

  const sent = [];
  const dispatcher = { broadcastMessage: (op, data, to) => sent.push({ op, data: JSON.parse(data), to: to?.map((p) => p.userId) }) };
  let { state } = G("matchInit")({}, logger, nk, { lifelineId: a.lifelineId });
  const pa = { userId: "user-a", sessionId: "sa" }, pb = { userId: "user-b", sessionId: "sb" };
  assert.equal(G("matchJoinAttempt")({}, logger, nk, dispatcher, 0, state, { userId: "intruder" }).accept, false);
  state = G("matchJoin")({}, logger, nk, dispatcher, 0, state, [pa, pb]).state;
  assert.equal(sent.filter((m) => m.op === 1).length, 2);
  assert.equal(sent.find((m) => m.op === 1).data.life.phase, "roll");

  const msg = (p, op, body) => ({ sender: p, opCode: op, data: new TextEncoder().encode(JSON.stringify(body)) });
  let tick = 1;
  const loop = (msgs = []) => (state = G("matchLoop")({}, logger, nk, dispatcher, tick++, state, msgs).state);
  const life = () => state.record.life;

  // 抽卡
  const before = J(life().rolls.qing);
  loop([msg(pa, 2, { reroll: true })]);
  assert.equal(life().rolls.qing.rerollsLeft, before.rerollsLeft - 1);
  assert.ok(sent.some((m) => m.op === 3));
  loop([msg(pa, 2, { confirm: true }), msg(pb, 2, { confirm: true })]);
  assert.equal(life().phase, "life");
  assert.equal(sent.filter((m) => m.op === 1 && m.data.life.phase === "life").length, 2, "开局后重发快照");
  life().world.fate = { mirror: null, qing: null, mei: null };

  // 走动 + 世界广播
  loop([msg(pa, 4, { x: 330, y: 600 })]);
  loop();
  const wv = sent.filter((m) => m.op === 7).at(-1).data;
  assert.equal(wv.actors.qing.x, 330);
  assert.ok(wv.minute >= 390 && wv.needs.mei.hunger <= 80);
  // 行动报错要回给本人
  loop([msg(pb, 5, { spot: "river_bank" })]);
  assert.ok(sent.at(-1).op === 9 || sent.some((m) => m.op === 9 && m.to?.includes("user-b")));

  // 事件：梅掉线，青触发 mirror 并选好，30 秒后影子替梅选
  life().world.fate.mirror = "c_stray_cat";
  for (const r of ["qing", "mei"]) { life().world.actors[r].x = 740; life().world.actors[r].y = 470; }
  state = G("matchLeave")({}, logger, nk, dispatcher, tick, state, [pb]).state;
  loop(); // 梅的影子可能正要去做别的事，也会被叫住
  assert.equal(life().world.event?.eventId, "c_stray_cat", "两人在楼道应触发");
  assert.ok(sent.some((m) => m.op === 8));
  loop([msg(pa, 6, { optionId: "hide" })]);
  for (let i = 0; i < 29 * 10; i++) loop();
  assert.ok(life().world.event, "还没到影子时间");
  for (let i = 0; i < 15; i++) loop();
  assert.equal(life().world.event, null, "影子应代选");
  const ev = life().log.filter((e) => e.kind === "mirror").at(-1);
  assert.equal(JSON.stringify(ev.shadow), JSON.stringify(["mei"]));
  assert.ok(sent.some((m) => m.op === 10));
  const saved = store.get(k("lifelines", a.lifelineId, "00000000-0000-0000-0000-000000000000"));
  assert.equal(saved.life.phase, "life", "掉线时要存档");

  // 两人都离线：时间停住，120 秒后关房
  state = G("matchLeave")({}, logger, nk, dispatcher, tick, state, [pa]).state;
  const mStop = life().world.minute;
  let closed = false;
  for (let i = 0; i < 1300 && !closed; i++) closed = G("matchLoop")({}, logger, nk, dispatcher, tick++, state, []) === null;
  assert.ok(closed, "空房间应关闭");
  assert.equal(life().world.minute, mStop, "没人在线时世界不走");
  console.log("✓ 联机流程：配对 / 同房 / 抽卡 / 开局快照 / 走动广播 / 报错 / 地点事件 / 影子代选 / 存档 / 关房");
}
