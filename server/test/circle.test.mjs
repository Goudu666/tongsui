// 人际圈子（docs/CIRCLE.md）：认识谁，决定能求谁。
// 钉住：生下来带的门路三档不一样 / 走动攒门路（一回回记数、够了认下、认下了菜单上就没了、被对门带着也记）/
// 关口上托人的路（老师推荐、递条子、托亲戚、街坊介绍、托人买房）锁得住、说得清、用了摘掉、欠下人情 /
// 换了学校老师就换了（fade）/ 每一笔人情都有事来讨 / 机器人和影子不走动。
import assert from "node:assert/strict";
import { G, C, NAMES } from "./harness.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const SLOTS = G("SLOTS");
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const fam = (id) => C.families.find((f) => f.id === id);
const ev = (id) => C.events.find((e) => e.id === id);
const opt = (eid, oid) => ev(eid).options.find((o) => o.id === oid);
const act = (id) => C.map.actions.find((a) => a.id === id);
const spot = (id) => C.map.spots.find((sp) => sp.id === id);
function at(s, r, id) { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; }
const shown = (o, why) => !(o.hide && why === (o.lock || "这条路不是给你留的"));

function bornInto(s, r, id) {
  const p = s.persons[r];
  const old = fam(p.familyId).traits;
  p.familyId = id;
  p.flags = p.flags.filter((f) => !old.includes(f)).concat(fam(id).traits);
  p.money = fam(id).money;
}
/** 青是 qf 家、梅是 mf 家，age 岁那天，停在第 slot 段（歇着的日子，没有日程挡着） */
function dayAt(age, slot, qf, mf, seed = 11) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  bornInto(s, "qing", qf);
  bornInto(s, "mei", mf);
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  const w = s.world;
  w.fate = { mirror: null, qing: null, mei: null };
  w.rest = true;
  w.slot = slot;
  w.minute = SLOTS[slot][0];
  for (const r of ROLES) {
    const p = s.persons[r];
    p.stats = { body: 5, mind: 5, charm: 5, luck: 5 };
    p.needs = { hunger: 80, energy: 90, mood: 80, clean: 80 };
    p.flags = p.flags.filter((f) => !f.startsWith("tal_"));
    p.money = Math.max(p.money, 20);
  }
  return s;
}
const doIt = (s, r, sp, a) => G("worldAct")(s, C, r, sp, true, a);
/** 走到 age 岁的关口那天早上 */
function atGate(age, qf, mf, mind, seed = 29, pre = null) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  bornInto(s, "qing", qf);
  bornInto(s, "mei", mf);
  for (const r of ROLES) { for (const k of ["body", "mind", "charm"]) s.persons[r].stats[k] = mind; s.persons[r].stats.luck = 5; }
  s.turn = turnAtAge(age);
  if (pre) pre(s);
  G("worldStartDay")(s, C);
  for (let i = 0; i < 3000; i++) {
    const pe = s.world.event;
    if (pe && ev(pe.eventId).kind === "milestone") { for (const r of pe.roles) pe.swing[r] = 0; break; } // 发挥拿掉，只看线
    if (pe) { for (const r of pe.roles) if (!pe.choices[r]) G("worldChoose")(s, C, r, ev(pe.eventId).options[0].id, false); continue; }
    G("worldAdvance")(s, C, 0.1, ON);
  }
  return s;
}
/** 另一个人只剩一条路时关口已经替他定了：没定的才选 */
const fin = (s, r, id) => { if (s.world.event && !s.world.event.choices[r]) assert.equal(G("worldChoose")(s, C, r, id, false).error, null); };
const locksOf = (s, r) => (G("lifeMilestoneLocks")(s, C) || {})[r] || {};

// ---------- 0. 内容：门路、人情都接得上 ----------
const TIES = new Set(C.circle.ties.map((t) => t.id));
{
  assert.ok(TIES.size >= 5, "门路至少五种");
  for (const a of C.map.actions.filter((x) => x.tie)) {
    assert.ok(TIES.has(a.tie.flag), `${a.id}：门路 ${a.tie.flag} 要在 circle.yaml 里`);
    assert.ok(a.menu, `${a.id}：攒门路的事只在菜单上（机器人、影子不走动）`);
    assert.ok((a.requires.notFlags || []).includes(a.tie.flag) || a.id === "coal", `${a.id}：认下了就不在菜单上`);
  }
  // 关口上要门路的路：用一回就摘掉（或者过了这道关自己淡了），要人情的那几条欠下一笔
  for (const e of C.events.filter((x) => x.kind === "milestone")) {
    for (const o of e.options) {
      const need = (o.requires?.flags || []).filter((f) => TIES.has(f));
      for (const f of need) {
        const fades = C.circle.ties.find((t) => t.id === f).fade.includes(e.id);
        assert.ok(fades || (o.effects.drop || []).includes(f), `${e.id}.${o.id}：用了 ${f} 要摘掉（人情用一回少一回）`);
      }
    }
  }
  // 每一笔人情都有事来讨：requires 它、选了就摘掉它
  for (const owe of C.circle.owes) {
    const given = C.events.some((e) => e.options.some((o) => (o.effects.flags || []).includes(owe)));
    assert.ok(given, `${owe}：总得有一条路欠下它`);
    const collect = C.events.filter((e) => (e.requires.flags || []).includes(owe));
    assert.ok(collect.length > 0, `${owe}：没有事来讨这笔人情`);
    for (const e of collect) assert.ok(e.options.every((o) => (o.effects.drop || []).includes(owe)), `${e.id}：每个选项都把 ${owe} 摘掉（这笔人情了了）`);
  }
  console.log(`✓ 内容：${TIES.size} 种门路、${C.circle.owes.length} 种人情，每种都有事来讨`);
}

// ---------- 1. 生下来带的门路：三档不一样 ----------
{
  const power = ["tie_school", "tie_house", "tie_unit"];
  for (const f of C.families) {
    const ties = f.traits.filter((t) => TIES.has(t));
    if (f.wealth === 0) assert.ok(!ties.some((t) => power.includes(t)), `${f.name}：清贫人家生下来没有能开关口的门路`);
  }
  assert.ok(fam("lin").traits.includes("tie_school"), "林家爸妈是老师：学校里说得上话");
  assert.ok(fam("zhao").traits.includes("tie_house"), "赵家是楼长：房管所有人");
  assert.ok(fam("chen").traits.includes("tie_street") && fam("zhou").traits.includes("tie_street"), "修车的、卖早点的：街坊都记着这两家的好");
  assert.ok(fam("zheng").traits.includes("tie_hospital"), "郑家是大夫");
  assert.ok(!fam("tang").traits.some((t) => TIES.has(t) || t === "kin_unit"), "唐家南方搬来的：有钱，没门路");
  const kin = C.families.filter((f) => f.traits.includes("kin_unit"));
  assert.ok(kin.length >= 2 && kin.every((f) => f.wealth === 1), "亲戚里有在单位的：小康人家里的几户");
  console.log(`✓ 生下来的门路：清贫没有能开关口的，小康 ${C.families.filter((f) => f.wealth === 1 && f.traits.some((t) => TIES.has(t) || t === "kin_unit")).length} 户有一门，唐家有钱没门路`);
}

// ---------- 2. 走动：一回回记数，够了认下，认下了就不在菜单上 ----------
{
  const s = dayAt(9, 3, "su", "he");
  at(s, "qing", "class_board");
  const need = act("class_help").tie.times;
  assert.equal(doIt(s, "qing", "class_board", "class_help").error, null);
  const d = s.world.actors.qing.did;
  assert.equal(d.a, "class_help");
  assert.equal(JSON.stringify(d.tp?.slice(0, 2)), JSON.stringify([1, need]), `做了一回：帮老师 1/${need}`);
  assert.equal(d.tp?.[2], "帮老师");
  assert.equal(s.persons.qing.ties.tie_teacher, 1);
  s.persons.qing.ties.tie_teacher = need - 1;
  assert.equal(doIt(s, "qing", "class_board", "class_help").error, null);
  const d2 = s.world.actors.qing.did;
  assert.equal(d2.tie?.f, "tie_teacher", "够了：认下");
  assert.equal(d2.tie?.l, "老师记住你了");
  assert.ok(s.persons.qing.flags.includes("tie_teacher"));
  assert.equal(s.persons.qing.ties.tie_teacher, undefined, "认下了，数清掉");
  assert.equal(doIt(s, "qing", "class_board", "class_help").error, "这件事轮不到你", "认下了菜单上就没了");
  // 钟点：帮老师是放了学那一段（傍晚），上午不行
  const m = dayAt(9, 1, "su", "he");
  at(m, "qing", "class_board");
  assert.equal(doIt(m, "qing", "class_board", "class_help").error, "现在不是时候");
  console.log(`✓ 走动：帮老师 1/${need} → 认下「老师记住你了」→ 菜单上没了；只在放了学那一段`);
}

// ---------- 3. 被对门带着去走亲戚：对门家的亲戚也认得你 ----------
{
  const s = dayAt(16, 4, "he", "su"); // 青清贫何家（没有这门亲戚），梅小康苏家（kin_unit）
  for (const r of ROLES) at(s, r, "mailbox");
  assert.equal(doIt(s, "qing", "mailbox", "visit_kin").error, "这件事轮不到你", "何家没有在单位的亲戚，自己去不了");
  const m0 = s.persons.mei.money;
  assert.equal(doIt(s, "mei", "mailbox", "visit_kin").error, null);
  assert.equal(doIt(s, "qing", "mailbox", "visit_kin").error, null, "梅带着去，青跟得上");
  assert.equal(s.persons.qing.ties?.tie_unit, 1, "跟着去的也记一回");
  assert.equal(s.persons.mei.ties?.tie_unit, 1);
  assert.ok(s.world.actors.qing.did.tg, "一块儿去的，算搭伴");
  assert.ok(s.persons.mei.money <= m0 + 2 * act("visit_kin").money + 1e-6, "两份东西都是带的人拎");
  console.log("✓ 走亲戚：对门家有这门亲戚，带上你一起去，两个人都记一回，东西是带的人拎");
}

// ---------- 4. 关口：老师推荐 / 递条子 ----------
{
  // 十二岁：心智 7.18（72 分上下，发挥 ±2.5），去重点班要 74，老师推荐、递条子的线是 69
  const s = atGate(12, "lin", "he", 7.18);
  assert.equal(s.world.event?.eventId, "m_junior");
  let L = locksOf(s, "mei");
  assert.equal(L.nod, "老师还没记住你", "何家孩子没留下来帮过老师：推荐那条灰着");
  assert.ok(shown(opt("m_junior", "nod"), L.nod), "推荐这条谁都看得见（知道有这条路，才会去攒）");
  assert.ok(!shown(opt("m_junior", "note"), L.note), "递条子：家里没人在学校的看不见");
  L = locksOf(s, "qing");
  assert.equal(L.note, undefined, "林家爸妈是老师：条子递得上");
  assert.ok(L.key, "考的线够不着");
  const m0 = s.persons.qing.money;
  assert.equal(G("worldChoose")(s, C, "qing", "note", false).error, null);
  fin(s, "mei", "normal");
  const q = s.persons.qing;
  assert.ok(q.flags.includes("junior_key") && q.flags.includes("owe_school") && !q.flags.includes("tie_school"), "进了重点班，条子用掉了，欠下一笔");
  assert.equal(q.money, m0 - opt("m_junior", "note").cost, "拎了点东西");
  // 帮老师攒下的：推荐进重点班，不欠人情；不管走哪条，过了这道关换了学校，老师就换了
  const t = atGate(12, "su", "he", 7.18, 31, (g) => {
    g.persons.qing.flags.push("tie_teacher");
    g.persons.mei.ties = { tie_teacher: 2 };
  });
  t.persons.mei.flags.push("tie_teacher"); // 关口弹出来以后再给：梅只有普通班一条路，不弹窗也行
  assert.equal(locksOf(t, "qing").nod, undefined, "老师看重你：推荐那条开着");
  assert.equal(G("worldChoose")(t, C, "qing", "nod", false).error, null);
  fin(t, "mei", "normal");
  assert.ok(t.persons.qing.flags.includes("junior_key") && !t.persons.qing.flags.some((f) => f.startsWith("owe_")), "推荐进去的，不欠人情");
  assert.ok(!t.persons.qing.flags.includes("tie_teacher") && !t.persons.mei.flags.includes("tie_teacher"), "上了初中换了老师：两个人的 tie_teacher 都摘了");
  assert.equal(t.persons.mei.ties?.tie_teacher, undefined, "攒到一半的也清零");
  const entry = t.log.findLast((e) => e.kind === "milestone");
  assert.equal(entry.resonance, false, "一个推荐进重点班、一个普通班：不同路");
  console.log("✓ 小升初：老师推荐谁都看得见、要攒；递条子只有林家这样的看得见，用掉、欠一笔；过了关老师就换了");
}

// ---------- 5. 二十二岁：托亲戚进单位 / 街坊介绍当学徒；殷实托家里的欠的是爸妈的人情 ----------
{
  const s = atGate(22, "su", "he", 9.0);
  assert.equal(s.world.event?.eventId, "m_job");
  let Lq = locksOf(s, "qing"), Lm = locksOf(s, "mei");
  assert.equal(Lq.kin, "亲戚那边没走动", "苏家有这门亲戚，没走动：灰着说清楚");
  assert.ok(shown(opt("m_job", "kin"), Lq.kin));
  assert.ok(!shown(opt("m_job", "kin"), Lm.kin), "何家没有这门亲戚：看不见");
  s.persons.qing.flags.push("tie_unit");
  s.persons.qing.money = 30;
  assert.equal(locksOf(s, "qing").kin, undefined, "走动过了：托得上（关口开着的时候认下的也算）");
  assert.equal(G("worldChoose")(s, C, "qing", "kin", false).error, null);
  fin(s, "mei", "odd");
  const q = s.persons.qing;
  assert.ok(q.flags.includes("job_pull") && q.flags.includes("owe_kin") && !q.flags.includes("tie_unit"), "进了单位，欠下亲戚的人情");
  assert.equal(q.money, 30 - opt("m_job", "kin").cost);
  // 殷实人家托家里的关系：同一条路，欠的是爸妈的人情
  const r = atGate(22, "xu", "chen", 9.0, 29, (g) => { g.persons.mei.stats.body = 5.8; g.persons.mei.stats.mind = 5.8; });
  r.persons.qing.money = 40;
  assert.equal(G("worldChoose")(r, C, "qing", "pull", false).error, null);
  // 陈家修车：街坊记着这家的好，介绍去铺子里学徒，线低一截
  assert.equal(locksOf(r, "mei").street, undefined, "陈家街坊情：学徒那条开着");
  assert.ok(locksOf(r, "mei").craft, "自己学手艺的线够不着");
  fin(r, "mei", "street");
  assert.ok(r.persons.qing.flags.includes("owe_pa"), "托家里的关系：爸妈替你欠下的");
  assert.ok(r.persons.mei.flags.includes("job_craft") && r.persons.mei.flags.includes("owe_street") && !r.persons.mei.flags.includes("tie_street"));
  console.log("✓ 二十二岁：苏家的亲戚没走动灰着、走动了托得上；何家看不见；殷实托家里的欠爸妈的人情；陈家街坊介绍学徒");
}

// ---------- 6. 三十岁：托人买上内部的房 ----------
{
  const s = atGate(30, "zhao", "ma", 7.0, 29, (g) => { for (const r of ROLES) g.persons[r].money = opt("m_settle", "inside").min + 5; });
  assert.equal(s.world.event?.eventId, "m_settle");
  assert.equal(locksOf(s, "qing").inside, undefined, "赵家楼长：房管所有人");
  assert.ok(locksOf(s, "qing").buy, "自己买差一截");
  assert.ok(!shown(opt("m_settle", "inside"), locksOf(s, "mei").inside), "马家没有：看不见");
  assert.equal(G("worldChoose")(s, C, "qing", "inside", false).error, null);
  fin(s, "mei", "stay");
  assert.ok(s.persons.qing.flags.includes("home_own") && s.persons.qing.flags.includes("owe_house"));
  console.log("✓ 三十岁：赵家托人买上内部的房（自己买差一截），欠下一笔");
}

// ---------- 7. 机器人和影子不走动：校准过的数只多了开局带门路的那几户 ----------
{
  const s = dayAt(9, 3, "su", "he");
  at(s, "qing", "class_board");
  assert.equal(G("worldPickAction")(s, C, "qing", spot("class_board")).act?.id, "blackboard", "不点菜单：还是头一件（出黑板报）");
  console.log("✓ 不点菜单的（影子、机器人、旧安装包）轮不到走动");
}
