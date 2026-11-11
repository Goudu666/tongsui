// 关口上两个人之间的事（server/src/pull.ts）：拉一把（看分的、看钱的）、没拉上、拉不动的几种、影子跟着拉、重逢、旧安装包看到的锁。
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const R = C.rules.bond;

/** 走到 age 岁那天早上，属性按 stats 设好，亲近默契按 bond 设好 */
function lifeAt(seed, age, stats, bond = {}, money = {}) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  for (const r of ROLES) {
    s.persons[r].stats.luck = 5; // 运气 5：发挥只看手气
    Object.assign(s.persons[r].stats, stats[r] || {});
    for (const f of [...s.persons[r].flags]) if (f.startsWith("fam_")) s.persons[r].flags.splice(s.persons[r].flags.indexOf(f), 1);
    if (money[r] !== undefined) s.persons[r].money = money[r];
  }
  Object.assign(s.bond, bond);
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  return s;
}
function untilMilestone(s) {
  for (let i = 0; i < 600; i++) {
    const out = G("worldAdvance")(s, C, 0.1, ON);
    if (out.started || out.dayEnded || out.entries.some((e) => e.kind === "milestone")) return out;
  }
  assert.fail("这一天没有走完");
}
/** 去掉手气：两个人这一场的发挥都按 0 算（swing 在开考那一刻定，测试改掉它再算锁和拉） */
function noSwing(s) {
  const pe = s.world.event;
  for (const r of ROLES) { pe.swing[r] = 0; delete pe.choices[r]; }
  if (pe.steady) for (const r of ROLES) delete pe.steady[r];
}
const pullsOf = (s) => J(G("lifeMilestonePulls")(s, C) || {});
const locksOf = (s) => J(G("lifeMilestoneLocks")(s, C) || {});

// 中考 m_senior：far 线 7.6（76 分），near 5.8。青 73 分，梅 82 分
const senior = (sync, q = 7.3, m = 8.2) => {
  const s = lifeAt(31, 15, { qing: { mind: q }, mei: { mind: m } }, { sync, close: 40 });
  const out = untilMilestone(s);
  assert.ok(out.started && out.started.eventId === "m_senior", "中考开考");
  noSwing(s);
  return s;
};

// ---------- 1. 看分的线：差 3 分，默契够，对门富余 6 分 → 拉得动 ----------
{
  const s = senior(35);
  const pulls = pullsOf(s);
  assert.ok(pulls.qing && pulls.qing.far, "青差 3 分的那条有人拉");
  assert.deepEqual({ by: pulls.qing.far.by, gap: pulls.qing.far.gap, unit: pulls.qing.far.unit }, { by: "mei", gap: 3, unit: "分" });
  assert.equal(pulls.qing.far.reach, Math.floor(R.pullFull * 10), "默契满了拉得最多");
  assert.ok(!pulls.mei || !pulls.mei.far, "梅自己够得着，没人要拉");
  // 旧安装包：这条路照旧灰着（它不认 pulls，选不了，也就不会选错）
  assert.ok(locksOf(s).qing.far, "locks 里仍然锁着");
  // 选：青先选这条，服务器收；梅也走这条 → 青过去了
  assert.equal(G("worldChoose")(s, C, "qing", "far", false).error, null);
  const r = G("worldChoose")(s, C, "mei", "far", false);
  assert.equal(r.error, null);
  const e = J(r.entry);
  assert.equal(e.choices.qing, "far");
  assert.equal(e.results.qing.option, "far");
  assert.equal(e.results.qing.score, 73, "成绩单记的是自己的分");
  assert.equal(e.results.qing.line, 76);
  assert.deepEqual(e.gate.pull.qing, { by: "mei", gap: 3, unit: "分" });
  assert.equal(e.resonance, true, "同路");
  assert.ok(e.gate.lines.some((l) => l.text.includes("3 分") && l.role === "mei"), "有一句说梅拉了青");
  assert.ok(s.memories.some((m) => m.title === C.duet.gate.pullMemory), "留一段回忆");
  assert.ok(s.persons.qing.flags.includes("hs_far") || J(s.persons.qing.flags).length > 0);
  const far = C.events.find((x) => x.id === "m_senior").options.find((o) => o.id === "far");
  for (const f of far.effects.flags) assert.ok(s.persons.qing.flags.includes(f), `青带上了 far 的标记 ${f}`);
}

// ---------- 2. 没拉上：对门走了别的路 → 走自己够得着的路里线最高的 ----------
{
  const s = senior(35);
  assert.equal(G("worldChoose")(s, C, "qing", "far", false).error, null);
  const e = J(G("worldChoose")(s, C, "mei", "near", false).entry);
  assert.equal(e.choices.qing, "near", "青一个人够不着 far，走了 near（够得着的里线最高）");
  assert.equal(e.gate.miss.qing, "far");
  assert.ok(!e.gate.pull);
  assert.equal(e.resonance, true, "最后两个人还是落在一条路上");
}

// ---------- 3. 拉不动的几种 ----------
{
  // 默契低：只拉得动 pullFrom（1 分），差 3 分拉不动
  const low = senior(0);
  assert.ok(!(pullsOf(low).qing || {}).far, "默契低拉不动 3 分");
  assert.match(G("worldChoose")(low, C, "qing", "far", false).error || "", /走不了/);
  // 默契低、差 1 分：拉得动
  const one = senior(0, 7.5);
  assert.equal(pullsOf(one).qing.far.gap, 1);
  assert.equal(pullsOf(one).qing.far.reach, Math.floor(R.pullFrom * 10 + 1e-6));
  // 对门富余不够：梅 78 分，只多 2 分，青差 3 分
  const thin = senior(35, 7.3, 7.8);
  assert.ok(!(pullsOf(thin).qing || {}).far, "对门富余不够");
  // 差太多：差 9 分
  const far = senior(35, 6.7);
  assert.ok(!(pullsOf(far).qing || {}).far, "差太多拉不动");
  // 两个人都够不着
  const both = senior(35, 7.3, 7.4);
  assert.equal(JSON.stringify(pullsOf(both)), "{}");
}

// ---------- 4. 看钱的线：三十岁买房，差 15 块，对门塞过去 ----------
{
  const s = lifeAt(32, 30, {}, { sync: 10, close: 70 }, { qing: 185, mei: 260 });
  const out = untilMilestone(s);
  assert.ok(out.started && out.started.eventId === "m_settle");
  noSwing(s);
  const p = pullsOf(s);
  assert.deepEqual({ by: p.qing.buy.by, gap: p.qing.buy.gap, unit: p.qing.buy.unit }, { by: "mei", gap: 15, unit: "块" });
  assert.equal(p.qing.buy.reach, R.pullMoney, "亲近够了塞得最多");
  assert.equal(G("worldChoose")(s, C, "qing", "buy", false).error, null);
  const e = J(G("worldChoose")(s, C, "mei", "buy", false).entry);
  assert.equal(e.results.qing.option, "buy");
  assert.equal(e.results.qing.score, 185, "成绩单上是自己兜里的");
  assert.equal(e.results.mei.score, 260, "塞钱的那个记的也是塞之前的");
  assert.deepEqual(e.gate.pull.qing, { by: "mei", gap: 15, unit: "块" });
  assert.equal(Math.round(s.persons.qing.money), 0, "塞的钱和自己的一起交了房钱");
  assert.equal(Math.round(s.persons.mei.money), 260 - 15 - 200, "梅少了塞过去的那截");
  // 亲近低：塞不了那么多
  const cold = lifeAt(32, 30, {}, { sync: 10, close: 15 }, { qing: 185, mei: 260 });
  untilMilestone(cold);
  noSwing(cold);
  assert.ok(!(pullsOf(cold).qing || {}).buy, "亲近 15 只塞得动 5 块");
  // 对门塞完自己就买不起了：不让塞
  const tight = lifeAt(32, 30, {}, { sync: 10, close: 70 }, { qing: 185, mei: 210 });
  untilMilestone(tight);
  noSwing(tight);
  assert.ok(!(pullsOf(tight).qing || {}).buy, "梅只富余 10 块，塞不了 15");
}

// ---------- 5. 看亲近的线不拉；一个人过的关不拉 ----------
{
  const s = lifeAt(33, 70, { qing: { body: 4 }, mei: { body: 4 } }, { sync: 40, close: 55 }, { qing: 10, mei: 10 });
  const out = untilMilestone(s);
  if (out.started && out.started.eventId === "m_evening") {
    noSwing(s);
    assert.ok(!(pullsOf(s).qing || {}).pair, "亲近是两个人同一个数，拉不了");
  }
  const solo = senior(35);
  solo.world.event.roles = ["qing"];
  assert.equal(G("lifeMilestonePulls")(solo, C), null, "一个人的关没人拉");
}

// ---------- 6. 影子：本人选了要对门拉的路，对门的影子跟着走这条；影子不替被拉的人赌 ----------
{
  const s = senior(35);
  assert.equal(G("worldChoose")(s, C, "qing", "far", false).error, null);
  assert.equal(G("lifeShadowChoose")(s, C, "mei", "m_senior"), "far", "梅的影子跟着走 far");
  const t = senior(35);
  assert.notEqual(G("lifeShadowChoose")(t, C, "qing", "m_senior"), "far", "青的影子不去赌要人拉的路");
}

// ---------- 7. 只有一条自己走得了的路、但有人拉得动另一条：要弹窗让他选，不直接替他定 ----------
{
  // 六岁选小干部：没有发挥。青心智 5.4（线 5.5，差 1 分），其他两项都够不着；梅心智 6.0
  const s = lifeAt(34, 6, { qing: { mind: 5.4, body: 3, charm: 3 }, mei: { mind: 6.0, body: 3, charm: 3 } }, { sync: 0, close: 10 });
  const out = untilMilestone(s);
  assert.ok(out.started && out.started.eventId === "m_school", "要弹窗");
  assert.ok(!s.world.event.choices.qing, "青有两条路（自己的 go 和要人拉的 study），等他选");
}

// ---------- 8. 重逢：上一道两个人的关走散了，这一道又走到一块儿 ----------
{
  const s = senior(35);
  // 先造一条十二岁小升初走散的记录
  s.log.push({ turn: turnAtAge(12), age: 12, label: "", kind: "milestone", minute: 0, events: { qing: "m_junior", mei: "m_junior" }, choices: { qing: "key", mei: "normal" }, shadow: [], resonance: false, text: "", results: { qing: { score: 80, unit: "分", grade: null, option: "key", track: "" }, mei: { score: 60, unit: "分", grade: null, option: "normal", track: "" } } });
  const before = { close: s.bond.close, sync: s.bond.sync };
  G("worldChoose")(s, C, "qing", "near", false);
  const e = J(G("worldChoose")(s, C, "mei", "near", false).entry);
  assert.equal(e.gate.reunion, 3, "隔了三年");
  assert.ok(e.gate.lines.some((l) => l.text.includes("三年")));
  assert.ok(s.memories.some((m) => m.title === C.duet.gate.reunionMemory));
  assert.ok(s.bond.close > before.close && s.bond.sync > before.sync, "亲近默契都添了一点");
  // 再下一道还同路：不是重逢
  const s2 = senior(35);
  s2.log.push({ ...J(s.log.at(-1)), resonance: true });
  G("worldChoose")(s2, C, "qing", "near", false);
  const e2 = J(G("worldChoose")(s2, C, "mei", "near", false).entry);
  assert.ok(!e2.gate || !e2.gate.reunion, "一直同路不算重逢");
}

// ---------- 9. 考前的目标条上就看得见「TA 能拉你几分」 ----------
{
  const s = lifeAt(31, 15, { qing: { mind: 7.3 }, mei: { mind: 8.2 } }, { sync: 35, close: 40 });
  const g = J(G("lifeGoal")(s, C, "qing"));
  assert.equal(g.id, "m_senior");
  const far = g.lines.find((l) => l.id === "far");
  assert.ok(far && !far.ok && far.pull, "青差的那条，目标条上写着有人拉");
  assert.deepEqual({ by: far.pull.by, gap: far.pull.gap }, { by: "mei", gap: 3 });
  const mg = J(G("lifeGoal")(s, C, "mei"));
  assert.ok(mg.lines.every((l) => !l.pull), "梅自己够得着，没有");
  // 默契低：拉不动，目标条上也不写
  const low = lifeAt(31, 15, { qing: { mind: 7.3 }, mei: { mind: 8.2 } }, { sync: 0, close: 40 });
  assert.ok(J(G("lifeGoal")(low, C, "qing")).lines.every((l) => !l.pull));
  // 对门不在这一关（死了）：不写
  const gone = lifeAt(31, 15, { qing: { mind: 7.3 }, mei: { mind: 8.2 } }, { sync: 35, close: 40 });
  gone.persons.mei.alive = false;
  assert.ok(J(G("lifeGoal")(gone, C, "qing")).lines.every((l) => !l.pull));
}

console.log("✓ pull.test：拉一把（分、钱）、没拉上、拉不动、影子跟着、重逢、考前看得见");
