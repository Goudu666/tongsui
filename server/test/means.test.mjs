// 家境（docs/MEANS.md）：殷实人家能花钱买路，清贫人家有自己的路，家里有的东西能带上对门。
// 钉住四件事：带人的规矩 / 关口上锁着的路看得见、说得清 / 交钱进的和考进的是同路 / 出身不压过活法。
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";
import { WAYS, live, climb } from "../../tools/paths.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const fam = (id) => C.families.find((f) => f.id === id);
const ev = (id) => C.events.find((e) => e.id === id);

/** 把一个人换成某户人家的孩子（标记、家底跟着换） */
function bornInto(s, r, id) {
  const p = s.persons[r];
  const old = fam(p.familyId).traits;
  p.familyId = id;
  p.flags = p.flags.filter((f) => !old.includes(f)).concat(fam(id).traits);
  p.money = fam(id).money;
}
/** 青是 qf 家、梅是 mf 家，走到 age 岁那天早上 */
function lifeAt(seed, age, qf, mf, stat = null) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  bornInto(s, "qing", qf);
  bornInto(s, "mei", mf);
  if (stat !== null) for (const r of ROLES) for (const k of ["body", "mind", "charm"]) s.persons[r].stats[k] = stat;
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  return s;
}
const spot = (id) => C.map.spots.find((sp) => sp.id === id);
function at(s, r, id) { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; }
const pick = (s, r, id) => G("worldPickAction")(s, C, r, spot(id)).act?.id ?? null;

// ---------- 0. 内容：家境和标记对得上，每种人家都有自己的路 ----------
{
  for (const f of C.families) {
    assert.equal(f.wealth === 2, f.traits.includes("fam_rich"), `${f.name}：殷实和 fam_rich 要对得上`);
    assert.equal(f.wealth === 0, f.traits.includes("fam_poor"), `${f.name}：清贫和 fam_poor 要对得上`);
  }
  const w = C.families.reduce((a, f) => a + f.weight, 0);
  const rich = C.families.filter((f) => f.wealth === 2).reduce((a, f) => a + f.weight, 0) / w;
  // 一个人抽到殷实的约两成，两个人里有一个是的约三分之一：碰得上，又不是人人都是
  assert.ok(rich >= 0.12 && rich <= 0.25, `抽到殷实人家的机会 ${Math.round(rich * 100)}%`);
  const gated = (flag) => C.events.filter((e) => e.kind === "milestone").flatMap((e) => e.options).filter((o) => (o.requires?.flags ?? []).includes(flag) || (o.requires?.notFlags ?? []).includes(flag));
  assert.ok(gated("fam_rich").length >= 5, "殷实人家在关口上要有几条自己的路");
  assert.ok(C.map.actions.some((a) => (a.requires.flags ?? []).includes("fam_poor")), "清贫人家要有自己能做的事，不只是少几样");
  for (const o of C.events.flatMap((e) => e.kind === "milestone" ? e.options : [])) {
    if (o.requires?.flags?.length || o.requires?.notFlags?.length) assert.ok(o.lock, `${o.id}：锁着的路要说清楚为什么（lock）`);
  }
  console.log(`✓ 内容：殷实 ${Math.round(rich * 100)}% / 关口上殷实人家的路 ${gated("fam_rich").length} 条，不看家底的（接班、分房、当兵）${C.events.filter((e) => e.kind === "milestone").flatMap((e) => e.options).filter((o) => (o.requires?.flags?.length || o.requires?.notFlags?.length) && !(o.requires?.flags ?? []).includes("fam_rich")).length} 条 / 锁着的路都写了为什么`);
}

// ---------- 1. 带上对门 ----------
// 一段做一件事：进门的钱定下这一段时就付（worldAct），改主意退回（worldCancel）
{
  const SLOTS = G("SLOTS");
  const setSlot = (s, i) => { s.world.slot = i; s.world.minute = SLOTS[i][0]; s.world.dutyDone = { qing: true, mei: true }; };
  const fee = (id) => -C.map.actions.find((a) => a.id === id).money;
  const view = (st) => G("worldView")({ record: { life: st }, moveSeq: {}, tick: 0 });
  const pass = (s, online = ON) => { const from = s.world.slot, turn = s.turn; for (let i = 0; i < 4000 && s.world.slot === from && s.turn === turn; i++) G("worldAdvance")(s, C, 0.5, online); };

  // 董家（殷实）的青去学琴，吴家（清贫）的梅自己进不去，青定了学琴，梅走过去就能跟着学；两份钱都是青出
  const s = lifeAt(11, 8, "dong", "wu");
  setSlot(s, 3);
  for (const r of ROLES) at(s, r, "palace_piano");
  assert.equal(pick(s, "mei", "palace_piano"), null, "梅自己看不见学琴");
  assert.ok(G("worldAct")(s, C, "mei", "palace_piano").error, "也做不了");
  assert.equal(pick(s, "qing", "palace_piano"), "piano");
  // 钱：青只够自己那份的时候带不了人
  s.persons.qing.money = fee("piano");
  assert.equal(G("worldAct")(s, C, "qing", "palace_piano").error, null);
  assert.equal(pick(s, "mei", "palace_piano"), "piano", "青定了学琴，梅走过去就能跟着学");
  assert.equal(G("worldAct")(s, C, "mei", "palace_piano").error, "对门这回也掏不起了");
  s.persons.qing.money = 50;
  assert.ok(J(view(s).tracks.mei.unlocks).includes("piano"), "客户端的单子里有它，点位上才显示");
  const mm = s.persons.mei.money;
  assert.equal(G("worldAct")(s, C, "mei", "palace_piano").error, null);
  assert.equal(s.persons.qing.money, 50 - fee("piano"), "梅那份定的时候就记在青头上");
  assert.ok(s.world.actors.mei.guest && s.world.actors.mei.together && s.world.actors.qing.together, "跟着学也算搭伴");
  // 梅改主意：钱退给青；再定回来
  assert.equal(G("worldCancel")(s, C, "mei"), null);
  assert.equal(s.persons.qing.money, 50, "梅不去了，那份钱退给青");
  assert.ok(!s.world.actors.mei.guest);
  assert.equal(G("worldAct")(s, C, "mei", "palace_piano").error, null);
  pass(s);
  assert.equal(s.persons.qing.money, 50 - fee("piano"), "这一段过完不再多扣");
  assert.equal(s.persons.mei.money, mm, "梅一分钱没花");
  assert.ok(!s.world.actors.mei.guest, "做完就不再是被带着的");

  // 青改主意：跟着来的梅一起撤，两份钱都退给青
  const q = lifeAt(13, 8, "dong", "wu");
  setSlot(q, 3);
  for (const r of ROLES) at(q, r, "palace_piano");
  q.persons.qing.money = 50;
  assert.equal(G("worldAct")(q, C, "qing", "palace_piano").error, null);
  assert.equal(G("worldAct")(q, C, "mei", "palace_piano").error, null);
  assert.equal(G("worldCancel")(q, C, "qing"), null);
  assert.equal(q.world.actors.mei.action, null, "带的人不去了，跟着的也撤回来");
  assert.equal(q.persons.qing.money, 50, "两份钱都退给青");

  // 影子不带人：青不在线，梅跟不进去
  const t = lifeAt(11, 8, "dong", "wu");
  setSlot(t, 3);
  for (const r of ROLES) at(t, r, "palace_piano");
  assert.equal(G("worldAct")(t, C, "qing", "palace_piano").error, null);
  t.world.actors.qing.shadow = true;
  assert.equal(pick(t, "mei", "palace_piano"), null, "影子不替人花钱带人");

  // 也不被带：青在线学琴，梅不在线，梅的影子不跟过去（不然两份学费都从青兜里出）
  for (let seed = 1; seed <= 40; seed++) {
    const v = lifeAt(seed, 8, "dong", "wu");
    setSlot(v, 3);
    at(v, "qing", "palace_piano");
    v.persons.qing.money = 50;
    assert.equal(G("worldAct")(v, C, "qing", "palace_piano").error, null);
    assert.equal(G("worldShadowGo")(v, C, "mei", spot("palace_piano")), false, "影子不跟着学琴");
    for (let i = 0; i < 400 && v.world.slot === 3; i++) {
      G("worldAdvance")(v, C, 0.5, { qing: true, mei: false });
      assert.ok(!v.world.actors.mei.guest, "影子被带着做了事");
    }
    assert.ok(v.persons.qing.money >= 50 - fee("piano") - 1e-9, "青替影子付了学费");
  }

  // 反过来：吴家（爸妈在厂里）的梅带董家的青去厂里的澡堂，澡票梅出
  const u = lifeAt(12, 8, "dong", "wu");
  setSlot(u, 3);
  for (const r of ROLES) at(u, r, "factory_bath");
  assert.equal(pick(u, "qing", "factory_bath"), null, "厂长家的孩子进不了工人澡堂");
  u.persons.mei.money = 10;
  const qm = u.persons.qing.money;
  assert.equal(G("worldAct")(u, C, "mei", "factory_bath").error, null);
  assert.equal(G("worldAct")(u, C, "qing", "factory_bath").error, null, "梅带着就进得去");
  pass(u);
  assert.equal(u.persons.qing.money, qm);
  assert.equal(u.persons.mei.money, 10 - 2 * fee("factory_bath"));

  // 清贫人家自己的活不带人：那是你家的活
  assert.ok(!C.map.actions.find((a) => a.id === "help_out").bring);
  console.log("✓ 带上对门：自己进不去 / 对门定了就能跟着做、算搭伴、两份钱对门出、钱不够带不了 / 改主意退给带的人，带的人不去了跟着的也撤 / 影子不带人也不被带 / 清贫人家也能带殷实的 / 自家的活不带人");
}

// ---------- 2. 关口：锁着的路看得见、说得清；交钱进的和考进的是同路 ----------
{
  const s = lifeAt(21, 15, "zheng", "jiang", 9);
  for (let i = 0; i < 600 && !s.world.event; i++) G("worldAdvance")(s, C, 0.1, ON);
  assert.equal(s.world.event?.eventId, "m_senior");
  const locks = G("lifeMilestoneLocks")(s, C);
  assert.equal(locks.mei.paid, "家里拿不出择校费", "江家（清贫）看得见择校这条路，灰着");
  assert.equal(locks.qing.paid, undefined, "郑家（殷实）走得了");
  s.persons.qing.money = 10;
  assert.match(G("lifeMilestoneLocks")(s, C).qing.paid, /积蓄/, "殷实人家也得拿得出这笔钱");
  s.persons.qing.money = 120;
  // 一个交钱、一个考进去：还是同一所学校，是共鸣不是错位
  assert.equal(G("worldChoose")(s, C, "qing", "paid", false).error, null);
  assert.equal(G("worldChoose")(s, C, "mei", "far", false).error, null);
  const e = s.log.at(-1);
  assert.equal(e.resonance, true, "交钱进的和考进的同路");
  assert.equal(e.text, ev("m_senior").resonance.far.text);
  assert.equal(s.persons.qing.money, 120 - ev("m_senior").options.find((o) => o.id === "paid").cost, "择校费从自己的积蓄里扣");
  assert.ok(s.persons.qing.flags.includes("school_far") && s.persons.qing.flags.includes("school_paid"));
  assert.equal(G("lifeTrack")(C, s.persons.qing, 15).id, G("lifeTrack")(C, s.persons.mei, 15).id, "日程也是同一条路");

  // 反过来锁：殷实人家的孩子不去当兵，家里没人在厂里的接不了班
  const g = lifeAt(22, 18, "zheng", "jiang", 9);
  for (let i = 0; i < 600 && !g.world.event; i++) G("worldAdvance")(g, C, 0.1, ON);
  assert.equal(G("lifeMilestoneLocks")(g, C).qing.army, "家里舍不得");
  assert.equal(G("lifeMilestoneLocks")(g, C).mei.abroad, "家里供不起");
  const j = lifeAt(23, 22, "dong", "tong", 5);
  for (let i = 0; i < 600 && !j.world.event; i++) G("worldAdvance")(j, C, 0.1, ON);
  assert.equal(j.world.event?.eventId, "m_job");
  const jl = G("lifeMilestoneLocks")(j, C);
  assert.equal(jl.qing.succeed, "家里没人在厂里");
  assert.equal(jl.mei.succeed, undefined, "佟家爸爸在厂里看大门，能接班");
  assert.equal(jl.mei.pull, "家里没有这层关系");

  // 兜底不会落到挂了标记的路上：一条线都够不着的人，走的是谁都走得了的那条
  for (const m of C.events.filter((x) => x.kind === "milestone")) {
    const fb = G("lifeMilestoneFallback")(m);
    assert.ok(!fb.requires?.flags?.length && !fb.requires?.notFlags?.length, `${m.id} 的兜底是 ${fb.id}，挂着标记`);
  }
  // 目标条上只摆这个人走得了的路：清贫人家的孩子天天看着「交择校费」没意思
  const goal = lifeAt(24, 14, "zheng", "jiang");
  const lines = (r) => G("lifeGoal")(goal, C, r).lines.map((l) => l.id);
  assert.ok(lines("qing").includes("paid") && !lines("mei").includes("paid"));
  console.log("✓ 关口：清贫的看得见择校、灰着、写着为什么 / 殷实的也得拿得出钱 / 一个交钱一个考是同路 / 当兵、接班、托关系各锁各的 / 兜底不落在挂标记的路上 / 目标条只摆自己的路");
}

// ---------- 3. 出身决定起点，活法决定走到哪 ----------
// 同样的机器人活法，只换人家：殷实人家不上心，比不过清贫人家专心念书；殷实人家专心念书，花钱的路是给差一口气的人留的
{
  const N = 12;
  const both = (qf, mf) => (s) => { s.rolls.qing.familyId = qf; s.rolls.mei.familyId = mf; };
  const run = (way, qf, mf) => { const out = []; for (let seed = 1; seed <= N; seed++) out.push(live(seed * 104729, WAYS[way], 16, climb, both(qf, mf)).marks); return out; };
  const reach = (marks, opts) => { const ps = marks.flatMap((m) => Object.values(m.m_senior || {})); return ps.filter((p) => opts.some((o) => p.open.includes(o))).length / ps.length; };
  const richLazy = run("不上心", "dong", "zheng"), midLazy = run("不上心", "chen", "zhou"), poorSolo = run("一个人念书", "jiang", "wu"), richSolo = run("一个人念书", "dong", "zheng");
  const rl = reach(richLazy, ["far", "paid"]), ml = reach(midLazy, ["far"]), ps = reach(poorSolo, ["far"]), rs = reach(richSolo, ["far", "paid"]);
  assert.ok(rl < ps - 0.25, `殷实人家不上心有 ${Math.round(rl * 100)}% 上得了市重点（含交钱），清贫人家专心念书才 ${Math.round(ps * 100)}%：钱压过了活法`);
  assert.ok(rl - ml <= 0.25, `钱让不上心的人多上了 ${Math.round((rl - ml) * 100)} 个点的市重点（${Math.round(ml * 100)}% → ${Math.round(rl * 100)}%）：择校的线太低`);
  // 家底只够一两回：十二岁交了重点班，十五岁的择校费多半就拿不出了。这是殷实人家自己的取舍
  const paid = richLazy.flatMap((m) => [...Object.values(m.m_junior || {}), ...Object.values(m.m_senior || {})]).filter((p) => p.open.includes("paid")).length;
  assert.ok(rl >= ml && paid > 0, "交钱的路得真有人走得通，不然家底没处花");
  assert.ok(rs >= ps, `殷实人家专心念书 ${Math.round(rs * 100)}%，比清贫人家专心念书 ${Math.round(ps * 100)}% 还低`);
  console.log(`✓ 出身不压过活法：市重点（含交钱）殷实不上心 ${Math.round(rl * 100)}%（小康不上心 ${Math.round(ml * 100)}%）/ 清贫专心 ${Math.round(ps * 100)}% / 殷实专心 ${Math.round(rs * 100)}%`);
}

// ---------- 4. 托关系管一辈子：每种活法下，殷实人家比同活法的小康多够得着的不超过 15 个点 ----------
// 二十二岁那条路一天的工钱管到 59 岁，后面三道要钱的关都跟着它走，所以单独钉一条（玩法评审 #26）
{
  const RICH = ["xu", "tang", "dong", "zheng"], MID = ["lin", "zhou", "su", "gu"];
  const job = (way, fams, opts) => {
    const ps = [];
    for (let seed = 1; seed <= 16; seed++) {
      const { marks } = live(seed * 7919, WAYS[way], 23, climb, (s) => { s.rolls.qing.familyId = fams[seed % 4]; s.rolls.mei.familyId = fams[(seed + 1) % 4]; });
      ps.push(...Object.values(marks.m_job || {}));
    }
    return ps.filter((p) => opts.some((o) => p.open.includes(o))).length / ps.length;
  };
  const out = [];
  for (const way of ["嘴甜人缘好", "混着来"]) {
    const r = job(way, RICH, ["desk", "pull"]), m = job(way, MID, ["desk"]);
    assert.ok(r - m <= 0.15, `${way}：殷实 ${Math.round(r * 100)}% 进得了单位（含托关系），小康 ${Math.round(m * 100)}%：出身压过了活法`);
    out.push(`${way} 殷实 ${Math.round(r * 100)}% / 小康 ${Math.round(m * 100)}%`);
  }
  console.log(`✓ 托关系不压过活法：${out.join("，")}`);
}
