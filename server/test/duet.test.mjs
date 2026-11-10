// 「接话」的测试：搭上了 / 猜 TA / 回话。规则见 src/duet.ts，设计见 docs/DUET.md。
import assert from "node:assert/strict";
import { G, C, J, fakeNakama, room } from "./harness.mjs";

const byId = new Map(C.events.map((e) => [e.id, e]));
const DUET_ECHO_KEEP = G("DUET_ECHO_KEEP");

/** 开一条人生，命运清空（这里只测默契事件本身） */
function life(seed = 11) {
  const s = G("lifeCreate")(seed, C);
  G("lifeConfirm")(s, C, "qing", { qing: "青", mei: "梅" });
  G("lifeConfirm")(s, C, "mei", { qing: "青", mei: "梅" });
  s.world.fate = { mirror: null, qing: null, mei: null };
  return s;
}
/** 直接摆出一个默契事件，两人各选各的（可带猜测 / 影子），返回结算日志 */
function play(s, eventId, pick, { guess = {}, shadow = [] } = {}) {
  s.world.event = { eventId, kind: "mirror", roles: ["qing", "mei"], choices: {}, shadow: [] };
  for (const r of ["qing", "mei"]) if (guess[r]) G("duetGuess")(s, C, r, guess[r]);
  assert.equal(G("worldChoose")(s, C, "qing", pick.qing, shadow.includes("qing")).entry, null);
  const entry = G("worldChoose")(s, C, "mei", pick.mei, shadow.includes("mei")).entry;
  assert.ok(entry && s.world.event === null);
  return entry;
}

// ---------- 0. 内容：每组「搭上了」都指向真的选项，而且不会盖掉共鸣 ----------
{
  let n = 0;
  for (const ev of C.events) {
    if (ev.kind !== "mirror") { assert.equal((ev.catches ?? []).length, 0, `${ev.id} 不是默契事件，不能挂搭上了`); continue; }
    for (const c of ev.catches ?? []) {
      n++;
      assert.equal(c.pair.length, 2);
      assert.notEqual(c.pair[0], c.pair[1], `${ev.id} 的搭上了必须是两个不同的选项`);
      for (const o of c.pair) assert.ok(ev.options.some((x) => x.id === o), `${ev.id} 没有选项 ${o}`);
      assert.ok(c.text.length > 0 && c.text.length <= 48 && !/[{}]/.test(c.text), `${ev.id} 搭上了的文案`);
      assert.ok(c.memory && c.memory.length <= 8, `${ev.id} 搭上了要留下一样握得住的东西`);
      assert.ok((c.bond.sync ?? 0) >= (c.bond.close ?? 0), `${ev.id}：搭上了长的是默契，不是亲近`);
    }
  }
  assert.ok(n >= 8, "至少 8 组搭上了");
  const stages = new Set(C.events.filter((e) => (e.catches ?? []).length > 0).map((e) => e.stage));
  for (const st of ["childhood", "teen", "middle", "old"]) assert.ok(stages.has(st), `${st} 没有能搭上的事`);
  for (const k of ["lines", "echo", "epitaph"]) assert.ok(C.duet[k], `内容里缺 duet.${k}`);
  console.log(`✓ 内容：${n} 组搭上了，都指向真的选项 / 童年到老年都有 / 文案 48 字内、回忆 8 字内`);
}

// ---------- 1. 搭上了：选得不一样，但一个抛、一个接 ----------
{
  const s = life();
  const sync0 = s.bond.sync, mem0 = s.memories.length;
  const e = play(s, "d_kite_tree", { qing: "climb", mei: "hold" });
  assert.equal(e.resonance, true, "搭上了也算默契");
  assert.equal(e.duet.outcome, "catch");
  assert.equal(e.text, byId.get("d_kite_tree").catches[0].text);
  assert.equal(s.memories.length, mem0 + 1);
  assert.equal(s.memories.at(-1).title, "都接住了");
  assert.ok(s.bond.sync > sync0);
  assert.equal(G("lifeStats")(s).rate, 100, "计入默契率");
  // 反过来也算：谁抛谁接不分先后
  const e2 = play(s, "d_teen_bike", { qing: "seat", mei: "ride" });
  assert.equal(e2.duet.outcome, "catch");
  // 没写进 catches 的组合仍然是错位
  const e3 = play(s, "d_wheel_steps", { qing: "front", mei: "call" });
  assert.equal(e3.resonance, false);
  assert.equal(e3.duet.outcome, "miss");
  assert.equal(e3.text, byId.get("d_wheel_steps").dissonance.text);
  // 选一样照旧是共鸣
  const e4 = play(s, "d_old_bench", { qing: "quiet", mei: "quiet" });
  assert.equal(e4.resonance, true);
  assert.equal(e4.duet.outcome, "res");
  assert.equal(G("lifeStats")(s).hits, 3);
  // 老事件挂上的搭上了：不改事件文件
  const e5 = play(s, "c_roof_summer", { qing: "popsicle", mei: "stars" });
  assert.equal(e5.duet.outcome, "catch");
  assert.equal(s.memories.at(-1).title, "楼顶的冰棍");
  console.log("✓ 搭上了：算默契、留回忆、进默契率 / 不分谁抛谁接 / 没写的组合仍是错位 / 共鸣照旧 / 老事件也能挂");
}

// ---------- 2. 猜 TA：懂是有方向的 ----------
{
  const s = life();
  // 都猜中、选得一样
  let e = play(s, "d_old_bench", { qing: "talk", mei: "talk" }, { guess: { qing: "talk", mei: "talk" } });
  assert.deepEqual(J(e.duet.knew), { qing: true, mei: true });
  assert.equal(e.duet.line, C.duet.lines.knew_both_same);
  // 只有青猜中
  e = play(s, "d_kite_tree", { qing: "climb", mei: "wait" }, { guess: { qing: "wait", mei: "hold" } });
  assert.deepEqual(J(e.duet.knew), { qing: true, mei: false });
  assert.equal(e.duet.line, "青猜着了梅，梅没猜着青。");
  assert.deepEqual(J(s.duet.know), { qing: [2, 2], mei: [1, 2] });
  // 选得不一样，可谁也没猜错谁：亲近 +1
  const close0 = s.bond.close, sync0 = s.bond.sync;
  e = play(s, "d_wheel_steps", { qing: "front", mei: "call" }, { guess: { qing: "call", mei: "front" } });
  assert.equal(e.resonance, false);
  assert.equal(e.duet.line, C.duet.lines.knew_both_diff);
  assert.equal(s.bond.close - close0, (byId.get("d_wheel_steps").dissonance.bond.close ?? 0) + 1);
  assert.equal(s.bond.sync - sync0, (byId.get("d_wheel_steps").dissonance.bond.sync ?? 0) + 2, "猜中一回默契 +1");
  // 都没猜中
  e = play(s, "d_teen_bike", { qing: "ride", mei: "seat" }, { guess: { qing: "walk", mei: "walk" } });
  assert.equal(e.duet.outcome, "catch");
  assert.equal(e.duet.line, C.duet.lines.knew_none);
  // 只有一个人猜：猜中才说话；不猜不记数
  e = play(s, "d_radio_show", { qing: "pick", mei: "fix" }, { guess: { mei: "pick" } });
  assert.equal(e.duet.line, "梅猜着了。");
  assert.equal(e.duet.guess.qing, null);
  assert.deepEqual(J(s.duet.know), { qing: [3, 4], mei: [3, 5] });
  // 乱填的猜测当没猜；不在事件里时猜也没用
  s.world.event = { eventId: "d_broken_window", kind: "mirror", roles: ["qing", "mei"], choices: {}, shadow: [] };
  G("duetGuess")(s, C, "qing", "no_such_option");
  G("duetGuess")(s, C, "mei", 42);
  assert.equal(s.world.event.guess, undefined);
  s.world.event = null;
  G("duetGuess")(s, C, "qing", "own");
  // 一生的闲话
  assert.ok(s.duet.epitaph[0].includes("青猜中梅 3 回") && s.duet.epitaph[0].includes("梅猜中青 3 回"));
  assert.ok(C.duet.epitaph.last.some((l) => l.text === s.duet.epitaph.at(-1)), "最后一句按默契率取");
  console.log("✓ 猜 TA：分别记谁懂谁 / 四种旁白 / 选得不一样但都猜中亲近 +1 / 不猜不记 / 乱填当没猜 / 结局闲话");
}

// ---------- 3. 回话：影子替你选过的，本人回来补答 ----------
{
  const s = life();
  const turn0 = s.turn;
  // 梅不在，影子替她选了 wait；青选 climb，还猜她会 hold → 当时是错位
  let e = play(s, "d_kite_tree", { qing: "climb", mei: "wait" }, { guess: { qing: "hold", mei: "climb" }, shadow: ["mei"] });
  assert.equal(e.duet.outcome, "miss");
  assert.equal(e.duet.owed, "mei");
  assert.equal(e.duet.guess.mei, null, "影子不猜");
  assert.deepEqual(J(s.duet.know), { qing: [0, 1], mei: [0, 0] });
  assert.equal(s.duet.owed.mei.length, 1);
  assert.deepEqual(J(s.duet.owed.mei[0]), { turn: turn0, age: e.age, label: e.label, eventId: "d_kite_tree", shadow: "wait", partner: "climb", guess: "hold", outcome: "miss" });
  // 快照里只看得到自己欠的，而且不带对门当时的猜测
  const view = G("duetView")(s, "mei");
  assert.equal(view.owed.mei.length, 1);
  assert.equal(view.owed.mei[0].guess, undefined);
  assert.equal(G("duetView")(s, "qing").owed.mei.length, 0);
  // 两个都是影子：没人在场，不欠
  play(s, "d_broken_window", { qing: "own", mei: "run" }, { shadow: ["qing", "mei"] });
  assert.equal(s.duet.owed.qing.length, 0);
  assert.equal(s.duet.owed.mei.length, 1);

  // 过了三个日子，梅回来了：她说她会在底下接着 → 搭上了，补一段回忆，长卷上那一笔也改过来
  s.turn += 3;
  assert.match(G("duetEcho")(s, C, "qing", turn0, "hold").error, /接不上/, "不是你欠的话");
  assert.match(G("duetEcho")(s, C, "mei", turn0, "nope").error, /没有这个选项/);
  const tags0 = s.persons.mei.tags.gentle ?? 0, sync0 = s.bond.sync, rate0 = G("lifeStats")(s).rate, log0 = s.log.length;
  const r = G("duetEcho")(s, C, "mei", turn0, "hold");
  assert.equal(r.error, null);
  const d = r.entry.duet;
  assert.equal(d.echo, true);
  assert.equal(d.outcome, "catch");
  assert.equal(d.was, "miss");
  assert.equal(d.like, false);
  assert.equal(d.partnerKnew, true, "青当时猜的就是 hold");
  assert.equal(r.entry.text, byId.get("d_kite_tree").catches[0].text);
  assert.deepEqual(J(d.lines), ["隔了三个日子，还是搭上了。", "影子替你选的是「等风把它吹下来」。它还得学。", "青当时猜的就是这个。青比影子懂你。"]);
  assert.equal(s.memories.at(-1).title, "都接住了");
  assert.equal(s.memories.at(-1).vivid, 2, "补的回忆淡一级");
  assert.equal(s.memories.at(-1).turn, turn0, "回忆记在当年");
  assert.equal(s.bond.sync - sync0, 3, "接上 +2，青其实猜中了 +1");
  assert.deepEqual(J(s.duet.know.qing), [1, 1]);
  assert.deepEqual(J(s.duet.like.mei), [0, 1]);
  assert.equal(s.persons.mei.tags.gentle, tags0 + 1, "本人的回答接着教影子");
  assert.equal(s.duet.owed.mei.length, 0);
  assert.equal(s.log.length, log0 + 1);
  const past = s.log.find((x) => x.kind === "mirror" && x.events.qing === "d_kite_tree");
  assert.equal(past.resonance, true);
  assert.equal(past.duet.mended, "catch");
  assert.ok(G("lifeStats")(s).rate > rate0, "接上的话计入默契率");
  assert.match(G("duetEcho")(s, C, "mei", turn0, "hold").error, /接不上/, "一句话只能回一次");
  assert.ok(s.duet.epitaph.some((l) => l === "影子替梅去过 1 回，有 0 回选得跟本人一样。"));

  // 影子选对了：本人回的和影子一样，什么也不用改
  const t1 = s.turn;
  play(s, "d_old_bench", { qing: "talk", mei: "talk" }, { guess: { qing: "talk" }, shadow: ["mei"] });
  const mem1 = s.memories.length, b1 = J(s.bond);
  const r2 = G("duetEcho")(s, C, "mei", t1, "talk");
  assert.equal(r2.entry.duet.outcome, "res");
  assert.equal(r2.entry.duet.like, true);
  assert.deepEqual(J(r2.entry.duet.lines), [C.duet.echo.res.replace("{gap}", "一个日子"), C.duet.echo.like]);
  assert.equal(s.memories.length, mem1, "当时已经共鸣过，不重复给回忆");
  assert.deepEqual(J(s.bond), b1, "也不重复加关系");
  assert.deepEqual(J(s.duet.like.mei), [1, 2]);

  // 影子蒙对了、本人其实不这么选：对门当时的「猜中」要收回
  const t2 = s.turn;
  play(s, "d_wheel_steps", { qing: "front", mei: "back" }, { guess: { qing: "back" }, shadow: ["mei"] });
  const k0 = s.duet.know.qing[0];
  const r3 = G("duetEcho")(s, C, "mei", t2, "call");
  assert.equal(r3.entry.duet.outcome, "miss");
  assert.equal(r3.entry.duet.partnerKnew, false);
  assert.equal(r3.entry.text, C.duet.echo.miss);
  assert.equal(s.duet.know.qing[0], k0 - 1);
  const pastCatch = s.log.find((x) => x.kind === "mirror" && x.events.qing === "d_wheel_steps");
  assert.equal(pastCatch.resonance, true, "当时搭上的不因为回话收回：那天确实接住了");

  // 「不提了」：放下，不留日志。只认 null / 不带；别的类型是发错了，话还欠着
  const t3 = s.turn;
  play(s, "d_teen_bike", { qing: "ride", mei: "walk" }, { shadow: ["mei"] });
  const log3 = s.log.length;
  for (const bad of [123, {}, [], true, 0]) {
    assert.match(G("duetEcho")(s, C, "mei", t3, bad).error, /没有这个选项/);
    assert.equal(s.duet.owed.mei.length, 1, "发错了不能把话丢掉");
  }
  const r4 = G("duetEcho")(s, C, "mei", t3, null);
  assert.equal(r4.error, null);
  assert.equal(r4.entry, null);
  assert.equal(s.log.length, log3);
  assert.equal(s.duet.owed.mei.length, 0);

  // 过期：隔了 DUET_ECHO_KEEP 个日子就接不上了
  const t4 = s.turn;
  play(s, "d_radio_show", { qing: "pick", mei: "fix" }, { shadow: ["mei"] });
  s.turn += DUET_ECHO_KEEP;
  assert.equal(G("duetView")(s, "mei").owed.mei.length, 0);
  assert.match(G("duetEcho")(s, C, "mei", t4, "clap").error, /接不上/);
  assert.equal(s.duet.owed.mei.length, 0);

  // 欠得太多：只留最近的几句
  const many = life(5);
  const mirrors = C.events.filter((x) => x.kind === "mirror").slice(0, G("DUET_OWED_MAX") + 2);
  for (const ev of mirrors) play(many, ev.id, { qing: ev.options[0].id, mei: ev.options[1].id }, { shadow: ["qing"] });
  assert.equal(many.duet.owed.qing.length, G("DUET_OWED_MAX"));
  console.log("✓ 回话：影子替选的欠着 / 接上了补回忆、改长卷、进默契率 / 影子像不像 / 对门的猜测按本人重算 / 不提了 / 过期 / 最多欠 6 句");
}

// ---------- 4. 存档：旧存档没有 duet；剧情改了以后欠着的话放下 ----------
{
  const s = life();
  delete s.duet;
  const e = play(s, "d_kite_tree", { qing: "climb", mei: "hold" });
  assert.equal(e.duet.outcome, "catch");
  assert.ok(s.duet, "用到时才建，不用升存档版本");
  play(s, "d_old_bench", { qing: "talk", mei: "go" }, { guess: { qing: "quiet" }, shadow: ["mei"] });
  play(s, "d_teen_bike", { qing: "ride", mei: "walk" }, { shadow: ["mei"] });
  assert.equal(s.duet.owed.mei.length, 2);
  // 存档往返
  const back = J(s);
  assert.deepEqual(back.duet, J(s.duet));
  // 内容里删掉一个事件、改掉一个选项
  const c2 = J(C);
  c2.version = "changed";
  c2.events = c2.events.filter((x) => x.id !== "d_teen_bike");
  c2.events.find((x) => x.id === "d_old_bench").options.find((o) => o.id === "quiet").id = "hush";
  back.world.event = { eventId: "d_kite_tree", kind: "mirror", roles: ["qing", "mei"], choices: {}, shadow: [], guess: { qing: "gone", mei: "hold" } };
  // 走存档修复的正门（save.ts 的 lifeRepair），不直接调 duetRepair：那根线断了这里要能发现
  const notes = G("lifeRepair")(back, c2);
  assert.equal(back.duet.owed.mei.length, 1);
  assert.equal(back.duet.owed.mei[0].eventId, "d_old_bench");
  assert.equal(back.duet.owed.mei[0].guess, null, "猜的选项没了，当没猜");
  assert.deepEqual(back.world.event.guess, { mei: "hold" });
  assert.ok(notes.some((n) => n.includes("duet.owed.mei") && n.includes("d_teen_bike")), notes.join(" / "));
  assert.equal(G("lifeRepair")(back, c2).length, 0, "修过一次就干净了");
  console.log("✓ 存档：旧存档自动补上 duet / JSON 往返不丢 / 事件或选项被删后欠着的话放下并记一笔");
}

// ---------- 5. 联机：CHOOSE 带猜测、影子代选、重连后 ECHO ----------
{
  // 发快照不能改存档：一条还没有 duet 的人生，连发两次快照，存档里不多出 duet，快照里也不漏原始的
  {
    const { nk, rpc } = fakeNakama();
    const a = rpc("rpcLifelineCreate", "user-a", { name: "小青" });
    rpc("rpcLifelineJoin", "user-b", { code: a.code, name: "小梅" });
    const R = room(nk, rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId }).matchId);
    const pa = { userId: "user-a", sessionId: "sa" }, pb = { userId: "user-b", sessionId: "sb" };
    R.join([pa, pb]);
    assert.equal(R.to(pa, 1).at(-1).data.life.duet, undefined, "抽卡阶段没有 duet");
    R.loop([R.msg(pa, 2, { confirm: true }), R.msg(pb, 2, { confirm: true })]);
    assert.equal(R.life().duet, undefined);
    R.join([pa]); R.join([pa]);
    assert.equal(R.life().duet, undefined, "发快照不写状态");
    assert.deepEqual(R.to(pa, 1).at(-1).data.life.duet.owed, { qing: [], mei: [] });
    // 就算抽卡阶段的存档里已经有 duet（以后的版本、手改的存档），原始的 owed.guess 也出不去
    R.life().duet = { know: { qing: [0, 0], mei: [0, 0] }, like: { qing: [0, 0], mei: [0, 0] }, epitaph: [], owed: { qing: [], mei: [{ turn: 0, age: 3, label: "x", eventId: "d_kite_tree", shadow: "wait", partner: "climb", guess: "hold", outcome: "miss" }] } };
    R.life().phase = "roll";
    R.join([pb]);
    assert.equal(JSON.stringify(R.to(pb, 1).at(-1).data).includes('"guess"'), false, "原始的 duet 不进快照");
  }

  const OP = { SNAPSHOT: 1, ROLL: 2, CHOOSE: 6, ERROR: 9, LOG: 10, ECHO: 30 };
  const { nk, rpc } = fakeNakama();
  const a = rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  rpc("rpcLifelineJoin", "user-b", { code: a.code, name: "小梅" });
  const open = rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId });
  const R = room(nk, open.matchId);
  const pa = { userId: "user-a", sessionId: "sa" }, pb = { userId: "user-b", sessionId: "sb" };
  R.join([pa, pb]);
  R.loop([R.msg(pa, OP.ROLL, { confirm: true }), R.msg(pb, OP.ROLL, { confirm: true })]);
  const L = R.life();
  L.world.fate = { mirror: null, qing: null, mei: null };
  const stage = (eventId) => { L.world.event = { eventId, kind: "mirror", roles: ["qing", "mei"], choices: {}, shadow: [] }; };
  const lastLog = () => R.sent.filter((m) => m.op === OP.LOG).at(-1).data.entries.at(-1);

  // 两人都在：选 + 猜一起发
  stage("d_kite_tree");
  R.loop([R.msg(pa, OP.CHOOSE, { optionId: "climb", guess: "hold" })]);
  const mid = R.sent.filter((m) => m.op === OP.SNAPSHOT).length;
  assert.equal(L.world.event.guess.qing, "hold");
  R.loop([R.msg(pb, OP.CHOOSE, { optionId: "hold", guess: "wait" })]);
  let e = lastLog();
  assert.equal(e.duet.outcome, "catch");
  assert.deepEqual(e.duet.knew, { qing: true, mei: false });
  assert.equal(e.duet.line, "小青猜着了小梅，小梅没猜着小青。");
  assert.equal(R.sent.filter((m) => m.op === OP.SNAPSHOT).length, mid);
  // 不带 guess 的旧客户端照常
  stage("d_old_bench");
  R.loop([R.msg(pa, OP.CHOOSE, { optionId: "talk" }), R.msg(pb, OP.CHOOSE, { optionId: "talk" })]);
  e = lastLog();
  assert.equal(e.duet.outcome, "res");
  assert.equal(e.duet.line, null);

  // 梅掉线；青遇到默契事件，等够了影子替她选
  R.leave([pb]);
  for (let i = 0; i < 200 && R.state.presences.mei; i++) R.loop(); // 过掉断线宽限
  assert.equal(R.state.presences.mei, undefined);
  stage("d_wheel_steps");
  const turn = L.turn;
  R.loop([R.msg(pa, OP.CHOOSE, { optionId: "front", guess: "back" })]);
  // 快照不泄露猜测
  R.join([{ userId: "user-a", sessionId: "sa" }]);
  const snapA = R.to(pa, OP.SNAPSHOT).at(-1).data;
  assert.equal(JSON.stringify(snapA.life.world.event).includes("guess"), false, "进行中的猜测不能进快照");
  for (let i = 0; i < 2000 && L.world.event; i++) R.loop();
  assert.equal(L.world.event, null, "影子应该替梅选了");
  e = lastLog();
  assert.deepEqual(e.shadow, ["mei"]);
  assert.equal(e.duet.owed, "mei");
  assert.equal(L.duet.owed.mei.length, 1);
  const shadowPick = L.duet.owed.mei[0].shadow;

  // 梅回来：快照里带着欠的那句；回话后两个人都收到日志
  const pb2 = { userId: "user-b", sessionId: "sb2" };
  R.join([pb2]);
  const snapB = R.to(pb2, OP.SNAPSHOT).at(-1).data;
  assert.equal(snapB.life.duet.owed.mei.length, 1);
  assert.equal(snapB.life.duet.owed.mei[0].eventId, "d_wheel_steps");
  assert.equal(snapB.life.duet.owed.mei[0].guess, undefined);
  assert.equal(snapB.life.duet.keep, DUET_ECHO_KEEP);
  // 日志尾巴里那天的记录也不带青的猜测：等梅回完话才揭晓。青自己的快照里照常有
  const dayB = snapB.life.log.find((x) => x.kind === "mirror" && x.turn === turn && x.events.qing === "d_wheel_steps");
  assert.deepEqual(dayB.duet, { outcome: e.duet.outcome, owed: "mei" });
  R.join([pa]);
  const dayA = R.to(pa, OP.SNAPSHOT).at(-1).data.life.log.find((x) => x.kind === "mirror" && x.turn === turn && x.events.qing === "d_wheel_steps");
  assert.equal(dayA.duet.guess.qing, "back");
  assert.equal(L.log.find((x) => x.kind === "mirror" && x.turn === turn && x.events.qing === "d_wheel_steps").duet.guess.qing, "back", "存档里的日志不动");
  // 青不能替梅回
  R.loop([R.msg(pa, OP.ECHO, { turn, optionId: "back" })]);
  assert.ok(R.to(pa, OP.ERROR).at(-1).to[0] === "sa");
  assert.equal(L.duet.owed.mei.length, 1);
  R.loop([R.msg(pb2, OP.ECHO, { turn, optionId: "back" })]);
  e = lastLog();
  assert.equal(e.duet.echo, true);
  assert.equal(e.duet.role, "mei");
  assert.equal(e.duet.outcome, "catch");
  assert.equal(e.duet.like, shadowPick === "back");
  assert.equal(e.duet.partnerKnew, true);
  assert.equal(R.sent.filter((m) => m.op === OP.LOG).at(-1).to, null, "回话的结果两个人都看得到");
  assert.equal(L.duet.owed.mei.length, 0);
  // 回完话，那天的猜测就可以看了
  R.join([pb2]);
  const after = R.to(pb2, OP.SNAPSHOT).at(-1).data.life.log.find((x) => x.kind === "mirror" && x.turn === turn && x.events.qing === "d_wheel_steps");
  assert.equal(after.duet.guess.qing, "back");
  // 乱发：不崩，只回错误
  const errs = R.to(pb2, OP.ERROR).length;
  R.loop([R.msg(pb2, OP.ECHO, { turn: "x", optionId: {} }), R.msg(pb2, OP.ECHO, {})]);
  assert.equal(R.to(pb2, OP.ERROR).length, errs + 2);
  assert.ok(nk.matches.size === 1, "房间还在");
  console.log("✓ 联机：CHOOSE 带猜测 / 旧客户端不带也行 / 快照不泄露猜测 / 影子代选记欠 / 重连快照带欠的话 / ECHO 只有本人能回、结果两人都收到 / 乱发只回 ERROR");
}
