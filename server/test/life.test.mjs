// 冒烟测试：把编译好的 build/index.js 放进一个假的 Nakama 环境里，
// 1) 用随机选择跑完 200 条人生；2) 走一遍 创建→加入→开房→选择→影子代选 的联机流程。
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const code = readFileSync(new URL("../build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);

// ---------- 1. 纯结算 ----------
const events = G("CONTENT_EVENTS");
let turns = [], resonances = 0, memories = 0;
for (let seed = 1; seed <= 200; seed++) {
  const s = G("lifeCreate")(seed, { qing: "青", mei: "梅" }, events);
  let guard = 0;
  while (!s.ended) {
    const req = G("lifeRequiredRoles")(s);
    const choices = {};
    for (const r of req) {
      const ev = G("lifeFindEvent")(events, s.scene.events[r]);
      choices[r] = ev.options[(seed + s.turn + r.length) % ev.options.length].id;
    }
    // 偶尔让影子代选
    const shadow = s.turn % 7 === 0 ? req.slice(0, 1) : [];
    for (const r of shadow) choices[r] = G("lifeShadowChoose")(s, events, r);
    G("lifeResolve")(s, events, choices, shadow);
    assert.ok(++guard < 500, "人生没有结束");
  }
  const t = G("lifeTimeAt")(s.turn);
  assert.equal(s.log.at(-1).kind, "end");
  assert.equal(s.log.filter((e) => e.kind === "death").length, 2);
  for (const r of ["qing", "mei"]) for (const v of Object.values(s.persons[r].stats)) assert.ok(v >= 0 && v <= 10);
  turns.push(s.turn);
  resonances += s.log.filter((e) => e.resonance).length;
  memories += s.memories.length;
}
turns.sort((a, b) => a - b);
console.log(`✓ 200 条人生跑完  回合数 中位 ${turns[100]}（${turns[0]}~${turns.at(-1)}）  平均共鸣 ${(resonances / 200).toFixed(1)}  平均回忆 ${(memories / 200).toFixed(1)}`);
console.log(`  时间轴样例：${[0, 1, 35, 36, 47, 48, 59, 60, 69, 70, 72].map((n) => G("lifeTimeAt")(n).label).join(" / ")}`);

// ---------- 2. 联机流程（假 Nakama） ----------
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

const choose = (p, optionId) => ({ sender: p, opCode: 2, data: new TextEncoder().encode(JSON.stringify({ optionId })) });
const firstOption = (role) => G("lifeFindEvent")(events, state.record.life.scene.events[role]).options[0].id;
let tick = 1;
const loop = (msgs) => (state = G("matchLoop")({}, logger, nk, dispatcher, tick++, state, msgs).state);

// 两人都在线：都选完才结算
loop([choose(pa, firstOption("qing"))]);
assert.equal(state.record.life.turn, 0);
loop([choose(pb, "not-an-option")]);
assert.ok(sent.some((m) => m.op === 9), "非法选项要报错");
loop([choose(pb, firstOption("mei"))]);
assert.equal(state.record.life.turn, 1, "两人都选完应进入下一回合");
assert.ok(sent.some((m) => m.op === 3));
assert.equal(store.get(k("lifelines", a.lifelineId, "00000000-0000-0000-0000-000000000000")).life.turn, 1, "每回合要存档");

// 梅掉线：青选完后 30 秒影子代选
state = G("matchLeave")({}, logger, nk, dispatcher, tick, state, [pb]).state;
loop([choose(pa, firstOption("qing"))]);
for (let i = 0; i < 29; i++) loop([]);
assert.equal(state.record.life.turn, 1, "还没到影子时间");
loop([]);
loop([]);
assert.equal(state.record.life.turn, 2, "影子应代选");
assert.equal(JSON.stringify(state.record.life.log.find((e) => e.turn === 1).shadow), JSON.stringify(["mei"]));

// 两人都离线：120 秒后关房
state = G("matchLeave")({}, logger, nk, dispatcher, tick, state, [pa]).state;
let closed = false;
for (let i = 0; i < 130 && !closed; i++) closed = G("matchLoop")({}, logger, nk, dispatcher, tick++, state, []) === null;
assert.ok(closed, "空房间应关闭");
console.log("✓ 联机流程：配对 / 同房 / 校验 / 结算 / 存档 / 影子 / 关房");
