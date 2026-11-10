// 冒烟测试：把编译好的 build/index.js 放进一个假的 Nakama 环境里（见 harness.mjs）。
// 1) 抽卡规则；2) 用「影子」跑完 60 条完整人生（两人都离线，全靠影子过日子）；
// 3) 走一遍联机：配对 → 抽卡 → 走动 → 行动/同框 → 事件 → 一天结束 → 影子代选 → 关房。
import assert from "node:assert/strict";
import { G, C, J, fakeNakama, room } from "./harness.mjs";

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
  s.world.fate = { mirror: null, qing: null, mei: null, milestone: null }; // 这里只测行动
  const w = s.world;
  assert.match(G("worldAct")(s, C, "qing", "river_bank").error, /走近/);
  assert.match(G("worldAct")(s, C, "qing", "bed_mei").error, /走近|不是你的家/);
  // 限速：一次上报 2000 像素会被截断
  G("worldMove")(s, C, "qing", 2300, 560, 0.1);
  assert.ok(w.actors.qing.x < 400, "瞬移要被限速");
  // 顺手的事：两人都去楼下早点铺买煎饼果子 → 同框，当场做完，不占这一段；钱不够买不了，一段里只买一回
  for (const r of ["qing", "mei"]) { w.actors[r].x = 1630; w.actors[r].y = 470; s.persons[r].money = 10; s.persons[r].needs.hunger = 40; }
  s.persons.mei.money = 1;
  assert.match(G("worldAct")(s, C, "mei", "breakfast_stall").error, /钱/);
  s.persons.mei.money = 10;
  assert.equal(G("worldAct")(s, C, "qing", "breakfast_stall").error, null);
  const both = G("worldAct")(s, C, "mei", "breakfast_stall");
  assert.equal(both.error, null);
  assert.ok(both.together, "一起买煎饼果子应触发同框");
  assert.equal(s.persons.qing.money, 8);
  assert.equal(w.actors.qing.action, null, "顺手的事当场做完");
  assert.match(G("worldAct")(s, C, "qing", "breakfast_stall").error, /过/, "一段里同一件顺手的事只做一回");
  assert.equal(w.minute, 390, "顺手的事不花时间");
  // 一段：两个人都定了才过。坐在同一张书桌前翻小人书 = 搭伴
  for (const r of ["qing", "mei"]) { w.actors[r].x = 250; w.actors[r].y = 360; }
  const mind0 = s.persons.qing.stats.mind;
  assert.equal(G("worldAct")(s, C, "qing", "desk_qing").error, null);
  for (let i = 0; i < 20; i++) G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.equal(w.minute, 390, "对门没定，钟不走");
  assert.equal(w.playing, false);
  assert.equal(G("worldAct")(s, C, "mei", "desk_qing").error, null);
  assert.ok(w.actors.qing.together && w.actors.mei.together, "后定的也算搭伴");
  const closeBefore = s.bond.close;
  const st0 = G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.ok(w.playing && st0.entries.some((e) => e.kind === "together"), "开始过的时候给搭伴的那一句");
  assert.match(G("worldAct")(s, C, "qing", "table_qing").error, /正在过/);
  for (let i = 0; i < 100 && w.slot === 0; i++) G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.equal(w.slot, 1, "早上过完是上午");
  assert.equal(w.minute, 480);
  assert.equal(w.actors.qing.action, null, "这一段的事做完了");
  assert.ok(s.persons.qing.stats.mind > mind0, "翻了一早上小人书，心智长了");
  assert.ok(s.bond.close >= closeBefore);
  // 改主意：定了还能撤；歇着也能撤
  assert.equal(G("worldAct")(s, C, "qing", "desk_qing").error, null);
  assert.equal(G("worldCancel")(s, C, "qing"), null);
  assert.equal(w.actors.qing.action, null);
  assert.equal(G("worldPass")(s, C, "qing"), null);
  assert.equal(G("worldReady")(s, "qing"), true);
  assert.equal(G("worldCancel")(s, C, "qing"), null);
  assert.equal(G("worldReady")(s, "qing"), false);
  // 等人：青歇着，梅在线一直不定，等够了影子替梅定这一段
  assert.equal(G("worldPass")(s, C, "qing"), null);
  for (let i = 0; i < 10 * G("SLOT_PATIENCE") - 5; i++) G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.equal(w.playing, false, "还没等够");
  for (let i = 0; i < 10; i++) G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.ok(w.playing || w.slot === 2, "等够了，影子替他定");
  for (let i = 0; i < 100 && w.playing; i++) G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  // 两人都去睡觉 → 一天结束，进入下一天
  for (const r of ["qing", "mei"]) { const sp = C.map.spawn[r]; w.actors[r].x = sp[0]; w.actors[r].y = sp[1]; }
  assert.equal(G("worldAct")(s, C, "qing", "bed_qing").error, null);
  assert.equal(G("worldAct")(s, C, "mei", "bed_mei").error, null);
  const t = G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.ok(t.dayEnded && s.turn === 1 && s.world.minute === 390 && s.world.slot === 0);
  // mirror 事件：两人都在 where、这一段碰得上它的钟点才触发
  const mev = C.events.find((e) => e.id === "c_roof_summer");
  s.world.fate = { mirror: mev.id, qing: null, mei: null };
  s.world.actors.qing.x = 600; s.world.actors.qing.y = 130;
  s.world.actors.mei.x = 900; s.world.actors.mei.y = 120;
  G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
  assert.equal(s.world.event, null, "早上不是楼顶乘凉的时候");
  s.world.slot = 3; s.world.minute = 930;
  s.world.actors.mei.x = 1180; s.world.actors.mei.y = 560;
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
  // 本人回来：影子替他定的这一段还没开始过，撤回来让他自己定
  {
    const z = G("lifeCreate")(11, C);
    G("lifeConfirm")(z, C, "qing", { qing: "青", mei: "梅" });
    G("lifeConfirm")(z, C, "mei", { qing: "青", mei: "梅" });
    z.world.fate = { mirror: null, qing: null, mei: null, milestone: null };
    G("worldShadowAct")(z, C, "mei");
    assert.equal(G("worldReady")(z, "mei"), true);
    z.world.wait = 85;
    assert.equal(G("worldReclaim")(z, "mei"), true);
    assert.equal(G("worldReady")(z, "mei"), false);
    assert.equal(z.world.wait, 0, "本人回来，重新开始等他");
    // v7 的存档：做到一半的事（这里是睡下了）是前面那段开始的，升上来撤不回
    const old = JSON.parse(JSON.stringify(z));
    old.version = 7;
    for (const k of ["slot", "ready", "playing", "wait", "quick"]) delete old.world[k];
    const bed = C.map.spots.find((sp) => sp.id === "bed_qing");
    Object.assign(old.world.actors.qing, { x: bed.at[0], y: bed.at[1], action: "sleep", spot: "bed_qing", until: null, asleep: true });
    old.world.minute = 800;
    G("lifeUpgrade")(old);
    assert.equal(old.world.slot, 2);
    assert.equal(old.world.actors.qing.from, -1);
    assert.match(G("worldCancel")(old, C, "qing"), /已经/, "升上来之前就开始的事撤不回");
  }
  console.log("✓ 世界：距离判定 / 不能睡别人家 / 限速 / 顺手的事不花时间 / 两人都定了才过 / 搭伴 / 改主意和歇着 / 等人 / 睡觉换天 / 地点和那一段 / 选择时停表 / 共鸣回忆");
}

// ---------- 4. 联机流程（假 Nakama，见 harness.mjs） ----------
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
  assert.equal(R.attempt({ userId: "user-a", sessionId: "sa" }, { protocol: "3" }).accept, false, "报了版本又太旧的挡在门外");
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
  R.life().world.fate = { mirror: null, qing: null, mei: null, milestone: null };

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
  // 影子等在线的人先定：青这一段歇着（今天的命运先清掉，免得半路弹出事来）
  R.life().world.fate = { mirror: null, qing: null, mei: null, milestone: null };
  R.life().world.event = null;
  R.leave([pb2]);
  R.loop([R.msg(pa, 22, {})]);
  assert.equal(G("worldReady")(R.life(), "qing"), true, "PASS：这一段歇着");
  for (let i = 0; i < 50; i++) R.loop();
  assert.equal(G("worldReady")(R.life(), "mei"), false, "刚掉线几秒，影子不接手");
  const slotBefore = R.life().world.slot;
  for (let i = 0; i < 60 && !R.life().world.actors.mei.shadow; i++) R.loop();
  assert.ok(R.life().world.actors.mei.shadow && (R.life().world.playing || R.life().world.slot > slotBefore), "掉线超过宽限期，影子替他定了这一段");
  for (let i = 0; i < 100 && R.life().world.playing; i++) R.loop();
  const pb2b = { userId: "user-b", sessionId: "sb2b" };
  R.join([pb2b]);
  assert.equal(R.life().world.actors.mei.shadow, false, "本人回来，影子把身体还给他");
  assert.equal(G("worldReady")(R.life(), "mei"), false, "新的一段由本人自己定");
  // 改主意的消息
  R.loop([R.msg(pa, 23, {})]);
  assert.equal(G("worldReady")(R.life(), "qing"), false);

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
