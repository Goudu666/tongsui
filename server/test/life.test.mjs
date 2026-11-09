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
// 假 Nakama 尽量贴近真的：存储带版本号（条件写入会冲突）、matchCreate 同步调用 matchInit 并带 ctx.matchId、
// 房间关闭后 matchGet 返回 null、通知会被记下来。
const logger = { info() {}, warn() {}, error() {}, debug() {} };
function fakeNakama() {
  const store = new Map(); // key -> { value, version, updateTime }
  const k = (c, key, u) => `${c}/${u}/${key}`;
  let ver = 0, matchSeq = 0, clock = 1000;
  const matches = new Map(); // id -> { state }
  const notifications = [];
  const nk = {
    store, matches, notifications, k,
    uuidv4: () => `uuid-${Math.random().toString(16).slice(2)}`,
    storageRead: (reqs) => reqs.flatMap((r) => {
      const o = store.get(k(r.collection, r.key, r.userId));
      return o ? [{ key: r.key, value: structuredClone(o.value), version: o.version, updateTime: o.updateTime }] : [];
    }),
    storageWrite: (ws) => {
      for (const w of ws) {
        const cur = store.get(k(w.collection, w.key, w.userId));
        if (w.version !== undefined) {
          const ok = w.version === "*" ? !cur : cur && cur.version === w.version;
          if (!ok) throw new Error("Storage write rejected - version check failed.");
        }
      }
      ws.forEach((w) => store.set(k(w.collection, w.key, w.userId), { value: structuredClone(w.value), version: `v${++ver}`, updateTime: ++clock }));
    },
    storageList: (u, c) => ({
      objects: [...store.entries()].filter(([key]) => key.startsWith(`${c}/${u}/`)).map(([key, o]) => ({ key: key.split("/")[2], value: o.value, updateTime: o.updateTime })),
    }),
    matchCreate: (name, params) => {
      const id = `m${++matchSeq}.node`;
      const init = G("matchInit")({ matchId: id }, logger, nk, params); // 失败就抛出，和真的一样
      matches.set(id, { state: init.state });
      return id;
    },
    matchGet: (id) => (matches.has(id) ? { matchId: id } : null),
    notificationsSend: (ns) => notifications.push(...ns),
    binaryToString: (b) => Buffer.from(b).toString("utf8"),
  };
  const rpc = (name, userId, payload) => JSON.parse(G(name)({ userId }, logger, nk, JSON.stringify(payload)));
  const record = (id) => store.get(k("lifelines", id, "00000000-0000-0000-0000-000000000000")).value;
  return { nk, rpc, record };
}

/** 一个房间的驱动器：收发消息、推进 tick */
function room(nk, matchId) {
  const sent = [];
  const dispatcher = { broadcastMessage: (op, data, to) => sent.push({ op, data: JSON.parse(data), to: to ? to.map((p) => p.sessionId) : null }) };
  const m = nk.matches.get(matchId);
  let tick = 1;
  const msg = (p, op, body) => ({ sender: p, opCode: op, data: new TextEncoder().encode(JSON.stringify(body)) });
  const r = {
    sent, dispatcher, msg,
    get state() { return m.state; },
    life: () => m.state.record.life,
    join: (ps) => { m.state = G("matchJoin")({}, logger, nk, dispatcher, tick, m.state, ps).state; },
    leave: (ps) => { m.state = G("matchLeave")({}, logger, nk, dispatcher, tick, m.state, ps).state; },
    attempt: (p) => G("matchJoinAttempt")({}, logger, nk, dispatcher, tick, m.state, p),
    loop: (msgs = []) => {
      const res = G("matchLoop")({}, logger, nk, dispatcher, tick++, m.state, msgs);
      if (res === null) { nk.matches.delete(matchId); return false; }
      m.state = res.state;
      return true;
    },
    /** 发给某个连接的消息（含广播） */
    to: (p, op) => sent.filter((x) => x.op === op && (x.to === null || x.to.includes(p.sessionId))),
  };
  return r;
}

{
  const { nk, rpc, record } = fakeNakama();
  const a = rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  assert.equal(a.code.length, 6);
  assert.equal(rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId }).waitingForPartner, true, "TA 还没来时不开房");
  assert.throws(() => rpc("rpcLifelineJoin", "user-b", { code: "NOPE00" }));
  const b = rpc("rpcLifelineJoin", "user-b", { code: a.code.toLowerCase(), name: "小梅" });
  assert.equal(b.role, "mei");
  const joined = nk.notifications.find((n) => n.userId === "user-a" && n.subject === "partner_joined");
  assert.ok(joined && joined.content.lifelineId === a.lifelineId && joined.content.name === "小梅", "梅加入后要通知青");
  assert.equal(rpc("rpcLifelineJoin", "user-b", { code: a.code }).role, "mei", "重复输入配对码不报错");
  assert.throws(() => rpc("rpcLifelineJoin", "user-c", { code: a.code }), /两个人/);
  assert.throws(() => rpc("rpcLifelineOpen", "user-c", { lifelineId: a.lifelineId }), /不是你的/);

  // 打开：两个人进同一个房间；房间自己存档之后再打开，仍然是同一个（旧版这里会拉起第二个房间）
  const openB = rpc("rpcLifelineOpen", "user-b", { lifelineId: a.lifelineId });
  assert.equal(record(a.lifelineId).matchId, openB.matchId, "matchInit 要把 matchId 写进存档");
  const R = room(nk, openB.matchId);
  const pa = { userId: "user-a", sessionId: "sa" }, pb = { userId: "user-b", sessionId: "sb" };
  assert.equal(R.attempt({ userId: "intruder", sessionId: "x" }).accept, false);
  R.join([pb]);
  assert.ok(nk.notifications.some((n) => n.userId === "user-a" && n.subject === "partner_online"), "梅进房、青不在时通知青");
  R.leave([pb]); // 触发一次房间存档
  R.join([pb]);
  const openA = rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId });
  assert.equal(openA.matchId, openB.matchId, "两人应进入同一个房间");
  // 同时拉起：第二个房间在 matchInit 里发现已有活房间，拒绝
  assert.throws(() => nk.matchCreate("lifeline", { lifelineId: a.lifelineId }), /DUP_MATCH/);
  assert.equal(nk.matches.size, 1);

  const list = rpc("rpcLifelineList", "user-a", {}).lifelines;
  assert.equal(list.length, 1);
  assert.equal(list[0].names.mei, "小梅");
  assert.equal(list[0].phase, "roll");

  R.join([pa]);
  assert.equal(R.to(pa, 1).at(-1).data.life.phase, "roll");
  assert.equal(R.to(pa, 1).at(-1).data.life.rng, undefined, "快照不带随机数状态");

  // 心跳
  R.loop([R.msg(pa, 12, { t: 1234 })]);
  const pong = R.to(pa, 13).at(-1);
  assert.ok(pong && pong.data.t === 1234 && pong.to[0] === "sa", "PING 只回给本人");

  // 抽卡
  const before = J(R.life().rolls.qing);
  R.loop([R.msg(pa, 2, { reroll: true })]);
  assert.equal(R.life().rolls.qing.rerollsLeft, before.rerollsLeft - 1);
  assert.ok(R.sent.some((m) => m.op === 3));
  R.loop([R.msg(pa, 2, { confirm: true }), R.msg(pb, 2, { confirm: true })]);
  assert.equal(R.life().phase, "life");
  assert.equal(R.sent.filter((m) => m.op === 1 && m.data.life.phase === "life").length, 2, "开局后重发快照");
  R.life().world.fate = { mirror: null, qing: null, mei: null };

  // 走动：带序号，乱序的旧包丢掉；世界广播带 tick 和已处理序号
  R.loop([R.msg(pa, 4, { x: 330, y: 600, seq: 1 })]);
  R.loop([R.msg(pa, 4, { x: 360, y: 600, seq: 3 }), R.msg(pa, 4, { x: 345, y: 600, seq: 2 })]);
  R.loop();
  const wv = R.sent.filter((m) => m.op === 7).at(-1).data;
  assert.equal(wv.actors.qing.x, 360, "旧序号的 MOVE 不能把人拉回去");
  assert.equal(wv.actors.qing.seq, 3);
  assert.ok(typeof wv.tick === "number" && wv.tick > 0);
  assert.ok(wv.minute >= 390 && wv.needs.mei.hunger <= 80);
  // 站了很久再走：限速按 1 秒算，不能一步跨半张地图
  for (let i = 0; i < 50; i++) R.loop();
  R.loop([R.msg(pa, 4, { x: 2000, y: 600, seq: 4 })]);
  assert.ok(R.life().world.actors.qing.x < 360 + 700, "久站之后也要限速");
  R.life().world.actors.qing.x = 360;
  // 行动报错回给本人
  R.loop([R.msg(pb, 5, { spot: "river_bank" })]);
  assert.ok(R.to(pb, 9).length > 0 && R.to(pb, 9).at(-1).to[0] === "sb");

  // 断线重连：梅换了一条新连接，旧连接的 leave 和消息都不算数
  const pb2 = { userId: "user-b", sessionId: "sb2" };
  R.join([pb2]);
  const resnap = R.to(pb2, 1).at(-1).data;
  assert.equal(resnap.you, "mei");
  assert.equal(resnap.life.phase, "life");
  assert.ok(resnap.life.world && resnap.life.world.actors.mei, "重连快照带上世界，客户端直接回到河畔里");
  R.leave([pb]);
  assert.equal(R.state.presences.mei.sessionId, "sb2", "旧连接的 leave 不能把新连接踢掉");
  const meiX = R.life().world.actors.mei.x;
  R.loop([R.msg(pb, 4, { x: meiX + 40, y: R.life().world.actors.mei.y, seq: 99 })]);
  assert.equal(R.life().world.actors.mei.x, meiX, "旧连接发来的 MOVE 不算");
  R.loop([R.msg(pb2, 4, { x: meiX + 40, y: R.life().world.actors.mei.y, seq: 1 })]);
  assert.equal(R.life().world.actors.mei.x, meiX + 40, "重连后序号从 1 重新开始");

  // 掉线宽限：10 秒内影子不接手；超过之后影子替他做事；回来时影子把身体还给他
  R.leave([pb2]);
  for (let i = 0; i < 50; i++) R.loop();
  assert.equal(R.life().world.actors.mei.action, null, "刚掉线几秒，影子不接手");
  for (let i = 0; i < 60 && !R.life().world.actors.mei.action; i++) R.loop();
  assert.ok(R.life().world.actors.mei.action && R.life().world.actors.mei.shadow, "掉线超过宽限期，影子接手");
  const pb2b = { userId: "user-b", sessionId: "sb2b" };
  R.join([pb2b]);
  assert.equal(R.life().world.actors.mei.action, null, "本人回来，影子停手");
  assert.equal(R.to(pb2b, 1).at(-1).data.life.world.actors.mei.action, null);

  // 事件：快照不能泄露 TA 的选择
  R.life().world.fate.mirror = "c_stray_cat";
  for (const r of ["qing", "mei"]) { R.life().world.actors[r].x = 740; R.life().world.actors[r].y = 470; }
  R.loop();
  assert.equal(R.life().world.event?.eventId, "c_stray_cat", "两人在楼道应触发");
  assert.ok(R.sent.some((m) => m.op === 8));
  R.loop([R.msg(pa, 6, { optionId: "hide" })]);
  const pb3 = { userId: "user-b", sessionId: "sb3" };
  R.join([pb3]);
  const evSnap = R.to(pb3, 1).at(-1).data.life.world.event;
  assert.equal(evSnap.eventId, "c_stray_cat", "重连时还在事件里，要能把选择框弹回来");
  assert.equal(evSnap.chosen.qing, true);
  assert.equal(evSnap.mine, null);
  assert.ok(!JSON.stringify(R.to(pb3, 1).at(-1).data).includes('"hide"'), "快照里不能出现 TA 选的选项");
  assert.equal(R.to(pb3, 1).at(-1).data.life.world.fate, undefined, "快照不剧透今天的命运");

  // 梅掉线，30 秒后影子替梅选
  R.leave([pb3]);
  for (let i = 0; i < 29 * 10; i++) R.loop();
  assert.ok(R.life().world.event, "还没到影子时间");
  for (let i = 0; i < 15; i++) R.loop();
  assert.equal(R.life().world.event, null, "影子应代选");
  const ev = R.life().log.filter((e) => e.kind === "mirror").at(-1);
  assert.equal(JSON.stringify(ev.shadow), JSON.stringify(["mei"]));
  assert.ok(R.sent.some((m) => m.op === 10));
  assert.equal(record(a.lifelineId).life.phase, "life", "掉线时要存档");

  // 两人都离线：时间停住，120 秒后关房，存档里的 matchId 清掉
  R.leave([pa]);
  const mStop = R.life().world.minute;
  let alive = true;
  for (let i = 0; i < 1300 && alive; i++) alive = R.loop();
  assert.ok(!alive, "空房间应关闭");
  assert.equal(R.life().world.minute, mStop, "没人在线时世界不走");
  assert.equal(record(a.lifelineId).matchId, null, "关房后清掉 matchId");
  // 再打开：从存档拉起新房间，人生接着过
  const reopen = rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId });
  assert.notEqual(reopen.matchId, openA.matchId);
  const R2 = room(nk, reopen.matchId);
  R2.join([{ userId: "user-a", sessionId: "sa2" }]);
  assert.equal(R2.life().world.minute, mStop, "存档恢复后接着过");
  assert.equal(R2.life().turn, R.life().turn);
  // 存档里 matchId 是陈旧的（比如 Nakama 重启过）也能重新拉起
  nk.matches.clear();
  nk.store.get(nk.k("lifelines", a.lifelineId, "00000000-0000-0000-0000-000000000000")).value.matchClaimedAt = Date.now() - 60000;
  const afterRestart = rpc("rpcLifelineOpen", "user-b", { lifelineId: a.lifelineId });
  assert.ok(nk.matches.has(afterRestart.matchId));
  console.log("✓ 联机流程：配对通知 / 同房（含存档后、并发拉起）/ 心跳 / 抽卡 / 开局快照 / 走动序号与限速 / 报错只回本人");
  console.log("✓ 断线重连：新连接顶掉旧连接 / 重连快照 / 10 秒宽限 / 回来收回影子 / 快照不泄露选择和命运 / 影子代选 / 存档 / 关房 / 从存档重开 / 服务器重启后重开");
}
