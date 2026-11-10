// 外地和写信的测试：规则在 src/world.ts（worldHomeBed、worldExit 的 ride、两片之间影子过不去）和 src/post.ts（写信）。
//   1) 在哪儿醒来：外地那条路的人在出租屋，买了房的在新家，别的在楼里自己家；两个人都在外地念书就错开一点
//   2) 路上的时间：过桥扣一个钟头（这一段做的事少做几遍），坐车去外地扣一整段（只剩顺手的事）
//   3) 两片之间：影子、跟着对门去的都过不去，只能本人坐车
//   4) 写信：分在两片才写得了，一天一封；下个日子早上到（出国的再晚一天），挂在「这一天过去了」上；亲近、心情；两封错过去多一点默契；按顺序轮着写
//   5) 主线在另一片：那天就在那一片醒来，歇着；大人那件落在上班的钟点上，那天歇着
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const at = (age) => { let t = 0; while (G("lifeTimeAt")(t).age < age) t++; return t; };
const sceneOf = (s, r) => G("worldSceneAt")(C, s.world.actors[r].y).id;
const spot = (id) => C.map.spots.find((x) => x.id === id);
const exit = (id) => C.map.exits.find((x) => x.id === id);
/** 一条人生，过到 age 岁那天早上。不想让主线插进来就把那一章的事都记成过了 */
function life(age, { qing = [], mei = [], quiet = true, seed = 11 } = {}) {
  const s = G("lifeCreate")(seed, C);
  G("lifeConfirm")(s, C, "qing", NAMES);
  G("lifeConfirm")(s, C, "mei", NAMES);
  s.turn = at(age);
  s.persons.qing.flags.push(...qing);
  s.persons.mei.flags.push(...mei);
  if (quiet) for (const e of C.story.events) s.log.push({ turn: 0, age: 3, kind: "solo", events: { qing: e.id, mei: e.id }, choices: {} });
  G("worldStartDay")(s, C);
  s.world.fate = { mirror: null, qing: null, mei: null };
  s.world.rest = true; // 不用去上学上班，想做什么做什么
  return s;
}
const stand = (s, r, id) => { const p = spot(id); s.world.actors[r].x = p.at[0]; s.world.actors[r].y = p.at[1]; };
const standExit = (s, r, id) => { const e = exit(id); s.world.actors[r].x = e.at[0]; s.world.actors[r].y = e.at[1]; };

// ---------- 1. 在哪儿醒来 ----------
{
  let s = life(19, { qing: ["uni_away"] });
  assert.equal(sceneOf(s, "qing"), "rental", "在外地念书的人在出租屋醒来");
  assert.equal(sceneOf(s, "mei"), "building");
  assert.equal(G("worldHomeBed")(s, C, "qing").id, "rent_bed");
  s = life(19, { qing: ["uni_away"], mei: ["uni_away"] });
  assert.equal(sceneOf(s, "qing"), "rental");
  assert.equal(sceneOf(s, "mei"), "rental", "两个人去了同一座城");
  assert.ok(Math.abs(s.world.actors.qing.x - s.world.actors.mei.x) >= 60, "睡一处的错开一点");
  for (const f of ["uni_abroad", "army"]) assert.equal(sceneOf(life(20, { mei: [f] }), "mei"), "rental", `${f} 也在外地`);
  assert.equal(sceneOf(life(25, { qing: ["left_city"] }), "qing"), "rental", "在外地上班");
  assert.equal(sceneOf(life(25, { qing: ["left_city", "came_back"] }), "qing"), "building", "回来了就在家");
  assert.equal(sceneOf(life(23, { qing: ["uni_away"] }), "qing"), "building", "念完书没留在外地");
  assert.equal(sceneOf(life(33, { qing: ["home_own"] }), "qing"), "newhome", "买了房住新家");
  // 外地的日程在外地那张图上
  const tr = (flags, age) => G("lifeTrack")(C, { flags }, age);
  for (const [f, age, sp] of [["uni_away", 19, "away_gate"], ["uni_abroad", 19, "away_gate"], ["army", 19, "away_work"], ["left_city", 30, "away_work"]]) {
    assert.equal(tr([f], age).duty.spot, sp, `${f} 的日程`);
    assert.equal(spot(sp).scene, "away");
  }
  // 外地那一片过得了日子：吃、洗、睡、念书、长身体、长魅力都有地方
  const there = C.map.spots.filter((p) => p.scene === "away" || p.scene === "rental").flatMap((p) => p.actions);
  for (const a of ["eat", "wash", "sleep", "read", "ball", "chat", "club_campus", "letter"]) assert.ok(there.includes(a), `外地缺 ${a}`);
  console.log("✓ 醒来：外地那条路的在出租屋（念书、出国、当兵、上班）/ 回来了、念完了在家 / 买了房在新家 / 外地那一片吃住学玩都有");
}

// ---------- 2. 路上的时间 ----------
{
  // 过桥一个钟头：对岸的书店，这一段少看几遍
  const s0 = life(19, { qing: ["uni_near"] });
  s0.world.slot = 2; s0.world.minute = 720;
  const base = J(s0);
  standExit(s0, "qing", "river.to_across");
  assert.equal(G("worldExit")(s0, C, "qing", "river.to_across"), null);
  assert.equal(s0.world.actors.qing.ride, 60);
  const store = C.map.spots.find((p) => p.scene === "across" && p.actions.includes("read_store"));
  stand(s0, "qing", store.id);
  assert.equal(G("worldAct")(s0, C, "qing", store.id).error, null);
  stand(base, "qing", store.id);
  assert.equal(G("worldAct")(base, C, "qing", store.id).error, null);
  const len = 930 - 720, use = C.rules.daily.slotUse, mins = C.map.actions.find((a) => a.id === "read_store").minutes;
  assert.equal(base.world.actors.qing.scale, Math.round((len * use / mins) * 100) / 100);
  assert.equal(s0.world.actors.qing.scale, Math.round(((len * use - 60) / mins) * 100) / 100, "过桥那一个钟头从这一段里扣");
  // 下一段就不扣了
  G("worldCancel")(s0, C, "qing"); G("worldClearAction")(s0.world.actors.qing);
  s0.world.slot = 3;
  assert.equal(G("worldRide")(s0.world.actors.qing, 3), 0);

  // 坐车回河畔里：一整段在路上，只剩顺手的事
  const s = life(19, { qing: ["uni_away"] });
  s.world.slot = 1; s.world.minute = 480;
  standExit(s, "qing", "rental.to_away");
  assert.equal(G("worldExit")(s, C, "qing", "rental.to_away"), null);
  assert.equal(sceneOf(s, "qing"), "away");
  standExit(s, "qing", "away.to_home");
  assert.equal(G("worldExit")(s, C, "qing", "away.to_home"), null);
  assert.equal(sceneOf(s, "qing"), "street", "坐车回来，下车在楼下");
  stand(s, "qing", "chess_table");
  s.world.slot = 2; s.world.minute = 720; s.world.actors.qing.rideSlot = 2; // 下午到的
  assert.equal(G("worldCanAct")(s, C, "qing", "chess_table"), "路上把这一段花掉了");
  stand(s, "qing", "breakfast_stall");
  s.world.minute = 450; s.world.slot = 0; s.world.actors.qing.rideSlot = 0;
  assert.equal(G("worldCanAct")(s, C, "qing", "breakfast_stall"), null, "顺手的事照样能做（买套煎饼）");
  // 没走外地那条路的人上不了车
  const h = life(19);
  standExit(h, "mei", "street.to_away");
  assert.match(G("worldExit")(h, C, "mei", "street.to_away"), /外地/);
  console.log("✓ 路上：过桥扣一个钟头、下一段不扣 / 坐车回来一整段，只剩顺手的事 / 没走那条路的上不了去外地的车");
}

// ---------- 3. 两片之间 ----------
{
  const s = life(19, { qing: ["uni_away"] });
  assert.equal(G("worldCanAct")(s, C, "qing", "chess_table", true), "隔着老远", "影子不坐车");
  assert.equal(G("worldCanAct")(s, C, "mei", "away_desk", true) !== null, true, "留下的人去不了外地");
  // 影子替在外地的人过一整天（要上课）：去外地的学校，不会出现在河畔里
  s.world.rest = false;
  const OFF = { qing: false, mei: false };
  const seen = new Set();
  for (let i = 0; i < 4000 && s.phase === "life" && s.turn === at(19); i++) {
    G("worldAdvance")(s, C, 0.2, OFF);
    if (s.world?.event) { const pe = s.world.event; for (const r of pe.roles) if (!pe.choices[r] && s.world.event === pe) G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, pe.eventId), true); }
    if (s.world && s.turn === at(19)) seen.add(sceneOf(s, "qing"));
  }
  assert.ok([...seen].every((x) => x === "away" || x === "rental") && seen.has("away"), `影子在外地过日子：${[...seen]}`);
  console.log(`✓ 两片之间：影子、被叫过去的都过不去 / 影子替在外地的人过一天只在 ${[...seen].join("、")}`);
}

// ---------- 4. 写信 ----------
{
  const s = life(19, { qing: ["uni_away"] });
  // 都在家：用不着写
  const home = life(19);
  stand(home, "mei", "mailbox");
  assert.equal(G("worldCanAct")(home, C, "mei", "mailbox"), "TA 就在跟前，用不着写信");
  // 外地的邮局、楼下的邮筒
  s.world.slot = 2; s.world.minute = 720;
  stand(s, "qing", "post_box");
  stand(s, "mei", "mailbox");
  assert.equal(G("worldCanAct")(s, C, "qing", "post_box"), null);
  assert.equal(G("worldAct")(s, C, "qing", "post_box").error, null);
  G("worldFinish")(s, C, "qing");
  assert.equal(s.post.length, 1);
  const L = s.post[0];
  assert.equal(L.from, "qing");
  assert.equal(L.side, "away");
  assert.equal(L.due, s.turn + 1, "下个日子早上到");
  assert.equal(L.lines.length, 3);
  assert.ok(C.letters.lines.uni_away.includes(L.lines[0]), "按在外地念书挑");
  assert.equal(G("worldCanAct")(s, C, "qing", "post_box"), "今天写过了", "一天一封");
  // 梅也写：第二天早上两封错过去
  G("worldAct")(s, C, "mei", "mailbox");
  G("worldFinish")(s, C, "mei");
  assert.ok(C.letters.lines.home.includes(s.post[1].lines[0]), "留下的人写家里的事");
  const close0 = s.bond.close, sync0 = s.bond.sync;
  const day = G("lifeEndDay")(s, C).find((e) => e.kind === "day");
  assert.equal(day.post.length, 2);
  assert.deepEqual(J(day.post.map((p) => [p.from, p.to])), [["qing", "mei"], ["mei", "qing"]]);
  assert.equal(day.crossed, C.letters.crossed);
  assert.ok(s.bond.close > close0 && s.bond.sync > sync0, "收到信亲近、错过去的两封默契");
  assert.equal(s.post.length, 0, "送到了就不在路上");
  assert.ok(s.log.at(-1).post || s.log.some((e) => e.kind === "day" && e.post), "长卷里留着");
  // 轮着写：下一封和上一封不一样
  const s2 = life(19, { qing: ["uni_abroad"] });
  const got = [];
  for (let k = 0; k < 2; k++) { stand(s2, "qing", "post_box"); G("worldAct")(s2, C, "qing", "post_box"); G("worldFinish")(s2, C, "qing"); got.push(s2.post.at(-1)); s2.turn += 1; }
  assert.notDeepEqual(J(got[0].lines), J(got[1].lines), "不重样");
  assert.equal(got[0].due, got[0].turn + 2, "出国的信多走一天");
  // 对门不在了：信寄不到
  const s3 = life(19, { qing: ["uni_away"] });
  s3.persons.mei.alive = false;
  stand(s3, "qing", "post_box");
  assert.equal(G("worldCanAct")(s3, C, "qing", "post_box"), "信寄不到了");
  // 旧存档没有 post
  const s4 = life(19, { qing: ["uni_away"] });
  delete s4.post;
  assert.ok(!G("lifeEndDay")(s4, C).find((e) => e.kind === "day").post);
  // 内容：每组至少四句、两边都有结尾
  for (const [k, list] of Object.entries(C.letters.lines)) assert.ok(list.length >= 4, k);
  console.log("✓ 写信：分在两片才写 / 一天一封 / 下个日子早上到、出国的晚一天 / 两封错过去 / 亲近、默契 / 轮着写不重样 / 对门不在了寄不到 / 旧存档");
}

// ---------- 5. 主线在另一片 ----------
{
  // 第四章第三件（过年那一夜，楼里）：在外地上班的人那天在家醒来，歇着
  const s = life(19, { qing: ["left_city"], quiet: false });
  for (const e of C.story.events) if (e.chapter < 4 || (e.chapter === 4 && e.beat < 3)) s.log.push({ turn: 0, age: 3, kind: "solo", events: { qing: e.id, mei: e.id }, choices: {} });
  let found = false;
  for (let t = at(19); t < at(30) && !found; t++) {
    s.turn = t;
    G("worldStartDay")(s, C);
    if (s.world.fate.mirror === "s4_new_year") {
      found = true;
      assert.equal(G("worldHomeBed")(s, C, "qing").scene, "rental", "平常在外地醒来");
      assert.equal(sceneOf(s, "qing"), "building", "过年那天在家醒来");
      assert.equal(s.world.off.qing, true, "回来那天不上班");
      assert.equal(G("worldDuty")(s, C, "qing"), null);
      assert.equal(s.world.back, true, "平常分在两片，这一天是回来一趟");
      // 回来一趟挡不住这一年的生分（growth.ts）：就算这天一起做了事
      s.world.warm = true;
      const close0 = s.bond.close = 60;
      G("growthDayEnd")(s, C);
      assert.ok(s.bond.close < close0, `回来一趟，亲近照样淡（${close0} → ${s.bond.close}）`);
    }
  }
  assert.ok(found, "第四章第三件排上了");
  // 大人那件落在上班的钟点：傍晚的楼下（第五章第一件），上班到傍晚的人那天歇着
  const w = life(31, { qing: ["job_desk"], mei: ["job_desk"], quiet: false });
  for (const e of C.story.events) if (e.chapter < 5) w.log.push({ turn: 0, age: 3, kind: "solo", events: { qing: e.id, mei: e.id }, choices: {} });
  let rested = 0, n = 0;
  for (let t = at(30); t < at(45); t++) {
    w.turn = t;
    G("worldStartDay")(w, C);
    const id = w.world.fate.mirror || w.world.fate.qing;
    const ev = id && G("storyFindEvent")(C, id);
    if (!ev || ev.chapter !== 5) continue;
    const k = G("storySlotIndex")(ev), d = G("lifeTrack")(C, w.persons.qing, G("lifeTimeAt")(t).age).duty, ds = G("worldDutySlots")(d);
    if (k >= ds[0] && k <= ds[1]) { n++; if (w.world.rest || w.world.off.qing) rested++; }
  }
  assert.ok(n > 0 && rested === n, `落在上班钟点的主线那天都歇着（${rested}/${n}）`);
  console.log(`✓ 主线在另一片：过年那天在家醒来、歇着、挡不住这一年的生分 / 落在上班钟点的那天歇着（${n} 回）`);
}
