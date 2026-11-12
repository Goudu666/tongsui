// 家境（docs/MEANS.md）：考场公平，考场外不公平，三档人家是三种难度（第八、九节）。
// 钉住这几件事：带人的规矩 / 关口上锁着的路看得见、说得清 / 交钱进的和考进的是同路 /
// 钱和期望（寄回家的、助学贷款、家里的贴补、爸妈的意思、家里不管了、家道中落、塞钱按家境）/
// 三档拉开：只钉谁高谁低，不钉具体的数（具体的数看 tools/origin.mjs）。
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parse } from "yaml";
import { G, C, J, NAMES } from "./harness.mjs";
import { WAYS, live, climb } from "../../tools/paths.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const fam = (id) => C.families.find((f) => f.id === id);
const ev = (id) => C.events.find((e) => e.id === id);
const opt = (eid, oid) => ev(eid).options.find((o) => o.id === oid);

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
/** 客户端关口上摆不摆这一条（client/scripts/main.gd → milestone_options）：写了 hide、锁着的理由正是它的 lock 才不摆 */
const shown = (o, why) => !(o.hide && why === (o.lock || "这条路不是给你留的"));

// ---------- 0. 内容：家境和标记对得上，每种人家都有自己的路 ----------
{
  for (const f of C.families) {
    assert.equal(f.wealth === 2, f.traits.includes("fam_rich"), `${f.name}：殷实和 fam_rich 要对得上`);
    assert.equal(f.wealth === 0, f.traits.includes("fam_poor"), `${f.name}：清贫和 fam_poor 要对得上`);
    // 三种难度各带一个起手标记（第九节）
    if (f.wealth === 0) assert.ok(f.traits.includes("send_home"), `${f.name}：清贫人家成年后工钱寄一截回家`);
    if (f.wealth === 1) assert.ok(f.traits.includes("fam_nest"), `${f.name}：小康人家有爸妈攒的那笔钱`);
    if (f.wealth === 2) assert.equal(f.traits.filter((t) => t.startsWith("exp_")).length, 1, `${f.name}：殷实人家爸妈心里有一条路`);
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
  // 家里不管了（fam_cut）：二十二岁以后殷实人家专属的路全部锁上——关口、行动、事件的选项
  const adult = (e) => (e.kind === "milestone" ? (e.age ?? 99) >= 22 : (e.requires?.minAge ?? 0) >= 22);
  const richOnly = (rq) => (rq?.flags ?? []).includes("fam_rich");
  const cutOk = (rq) => (rq?.notFlags ?? []).includes("fam_cut");
  let n = 0;
  for (const e of C.events.filter(adult)) {
    if (richOnly(e.requires)) { assert.ok(cutOk(e.requires), `${e.id}：殷实人家的事，家里不管了的碰不上`); n++; }
    for (const o of e.options) if (richOnly(o.requires)) { assert.ok(cutOk(o.requires), `${e.id}.${o.id}：殷实人家的路，家里不管了的锁上`); n++; }
  }
  for (const a of C.map.actions) if (richOnly(a.requires) && (a.requires.minAge ?? 0) >= 22) { assert.ok(cutOk(a.requires), `${a.id}：殷实人家的去处，家里不管了的去不了`); n++; }
  // 主线：三十岁以后那几章（第四章跨着十八到二十九，归二十一岁以前那一段一起看）
  const late = new Set(C.story.chapters.map((ch, i) => (ch.ages[0] >= 30 ? i + 1 : 0)).filter(Boolean)); // 主线事件的 chapter 是第几章（从 1 数）
  for (const e of C.story.events.filter((x) => late.has(x.chapter))) for (const o of e.options) if (richOnly(o.requires)) { assert.ok(cutOk(o.requires), `主线 ${e.id}.${o.id}：殷实人家的路，家里不管了的锁上`); n++; }
  assert.ok(n >= 12, `二十二岁以后殷实人家专属的路只数出 ${n} 条`);
  console.log(`✓ 内容：殷实 ${Math.round(rich * 100)}% / 三档各带起手标记 / 关口上殷实人家的路 ${gated("fam_rich").length} 条 / 锁着的路都写了为什么 / 二十二岁以后殷实专属的 ${n} 处都给家里不管了的锁上`);
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
  // 董家（exp_pull）：中考择校不是爸妈心里那条（郑家 exp_book 的择校费家里出，见 hardship_time.test），钱从自己的积蓄里扣
  const s = lifeAt(21, 15, "dong", "jiang", 9);
  for (let i = 0; i < 600 && !s.world.event; i++) G("worldAdvance")(s, C, 0.1, ON);
  assert.equal(s.world.event?.eventId, "m_senior");
  const locks = G("lifeMilestoneLocks")(s, C);
  assert.equal(locks.mei.paid, "家里拿不出择校费", "江家（清贫）看得见择校这条路，灰着");
  assert.equal(locks.qing.paid, undefined, "董家（殷实）走得了");
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
  const road = (p) => { const t = G("lifeTrack")(C, p, 15); return t.group || t.id; }; // 清贫人家的变体（歇着的日子看摊）和原来那条同一个 group
  assert.equal(road(s.persons.qing), road(s.persons.mei), "日程也是同一条路");

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


// ---------- 3. 考场公平：清贫人家专心念书，中考比殷实人家不上心的强 ----------
// 同样的机器人活法，只换人家：殷实人家不上心，比不过清贫人家专心念书；殷实人家专心念书，花钱的路是给差一口气的人留的
{
  const N = 12;
  const both = (qf, mf) => (s) => { s.rolls.qing.familyId = qf; s.rolls.mei.familyId = mf; };
  const run = (way, qf, mf) => { const out = []; for (let seed = 1; seed <= N; seed++) out.push(live(seed * 104729, WAYS[way], 16, climb, both(qf, mf)).marks); return out; };
  const reach = (marks, opts) => { const ps = marks.flatMap((m) => Object.values(m.m_senior || {})); return ps.filter((p) => opts.some((o) => p.open.includes(o))).length / ps.length; };
  // 殷实不上心按四户都算（docs/MEANS.md 第八节）：郑家（exp_book）放了学是爸妈报的奥数班，路是铺好的，不上心的也有六七成进得了市重点；
  // 只看董家、郑家两户就成了「念书人家」的数，压不出「殷实不上心比不过清贫专心」这一条本来要说的事
  const richLazy = [...run("不上心", "dong", "zheng"), ...run("不上心", "xu", "tang")], midLazy = run("不上心", "chen", "zhou"), poorSolo = run("一个人念书", "jiang", "wu"), richSolo = run("一个人念书", "dong", "zheng");
  const rl = reach(richLazy, ["far", "paid"]), ml = reach(midLazy, ["far"]), ps = reach(poorSolo, ["far"]), rs = reach(richSolo, ["far", "paid"]);
  // 11-11 三扇门（docs/MEANS.md 第八节）：清贫专心不再是九成六（放了学帮家里，中考线进了专心的那一段），差距从 25 个点收到 15 个点
  assert.ok(rl < ps - 0.15, `殷实人家不上心有 ${Math.round(rl * 100)}% 上得了市重点（含交钱），清贫人家专心念书才 ${Math.round(ps * 100)}%：钱压过了活法`);
  // 三扇门以后（docs/MEANS.md 第八节）殷实的路本来就是铺好的：十二岁交钱进的重点班、中考线抬到 8.7 以后择校费那条 7.8 留的口子更大，
  // 不上心的殷实人家比小康多上三十来个点。这里只拦「钱一下子把不上心的全送进去」，从 25 个点放到 40 个点（means.test 的整体重写另有人接）
  assert.ok(rl - ml <= 0.4, `钱让不上心的人多上了 ${Math.round((rl - ml) * 100)} 个点的市重点（${Math.round(ml * 100)}% → ${Math.round(rl * 100)}%）：择校的线太低`);
  // 家底只够一两回：十二岁交了重点班，十五岁的择校费多半就拿不出了。这是殷实人家自己的取舍
  const paid = richLazy.flatMap((m) => [...Object.values(m.m_junior || {}), ...Object.values(m.m_senior || {})]).filter((p) => p.open.includes("paid")).length;
  assert.ok(rl >= ml && paid > 0, "交钱的路得真有人走得通，不然家底没处花");
  assert.ok(rs >= ps, `殷实人家专心念书 ${Math.round(rs * 100)}%，比清贫人家专心念书 ${Math.round(ps * 100)}% 还低`);
  console.log(`✓ 考场公平：市重点（含交钱）殷实不上心 ${Math.round(rl * 100)}%（小康不上心 ${Math.round(ml * 100)}%）/ 清贫专心 ${Math.round(ps * 100)}% / 殷实专心 ${Math.round(rs * 100)}%`);
}

// ---------- 4. 考场外不公平：工钱的倍数、塞钱的上限（rules.yaml 的 wageFlags、bond.pullMoneyBy） ----------
{
  const duty = C.tracks.find((t) => t.id === "job_desk").duty;
  const wage = (flags, age = 25) => G("worldWage")(C, { flags }, duty, age);
  const base = wage([]);
  assert.equal(base, duty.money, "小康人家拿的就是路上写的数");
  assert.ok(wage(["fam_poor", "send_home"]) < base, "清贫人家工钱寄一截回家");
  assert.ok(wage(["fam_poor", "send_home", "loan"]) < wage(["fam_poor", "send_home"]), "背着助学贷款的再少一截");
  assert.equal(wage(["fam_poor"]), base, "不往家里寄了，工钱照数拿");
  assert.ok(wage(["fam_rich"]) > base, "殷实人家家里每个月贴补一截");
  assert.ok(Math.abs(wage(["fam_rich", "fam_cut"]) - base) < 0.15, "家里不管了：贴补没了");
  assert.equal(wage(["fam_fallen"]), base, "家道中落（摘了 fam_rich）：按小康");
  // 家境那一截是二十二岁以后的事：二十二岁以前帮家里干活、打零工、头一份活挣的都照数拿（第八节那一段的钱不动）
  for (const f of [["fam_poor", "send_home", "loan"], ["fam_rich"]]) {
    assert.equal(wage(f, 21), base, `${f.join("+")}：二十一岁照数拿`);
    assert.notEqual(wage(f, 22), base, `${f.join("+")}：二十二岁起才乘`);
  }
  // 往家里寄到什么时候：四十五岁把钱和工夫花在家里（清贫人家多一条线低的「把爸妈接过来」），或者爸妈走了
  assert.ok(opt("m_midlife", "home").effects.drop.includes("send_home"));
  const take = opt("m_midlife", "take");
  assert.ok(take.hide && take.requires.flags.includes("send_home") && take.joins === "home" && take.min < opt("m_midlife", "home").min && take.effects.drop.includes("send_home"));
  assert.ok(ev("mx_last_remit").requires.flags.includes("parent_gone") && ev("mx_last_remit").options.every((o) => o.effects.drop?.includes("send_home")));
  for (const id of ["mx_loan_paid", "mx_loan_paid_late"]) assert.ok(ev(id).options.every((o) => o.effects.drop?.includes("loan")), `${id}：还清了就摘掉 loan`);
  // 塞钱：按塞的那个人的家境
  const reach = (flags) => G("pullReachMoney")(C, 100, { flags });
  assert.ok(reach(["fam_poor"]) < reach([]) && reach([]) < reach(["fam_rich"]), `塞钱的上限 清贫 ${reach(["fam_poor"])} / 小康 ${reach([])} / 殷实 ${reach(["fam_rich"])}`);
  assert.equal(reach(["fam_rich", "fam_cut"]), reach([]), "家里不管了的按小康");
  assert.equal(reach([]), C.rules.bond.pullMoney, "小康人家塞的还是原来那个数");
  const old = { ...C, rules: { ...C.rules, bond: { ...C.rules.bond, pullMoneyBy: undefined } } };
  assert.equal(G("pullReachMoney")(old, 100, { flags: ["fam_rich"] }), C.rules.bond.pullMoney, "没写 pullMoneyBy 的旧内容照旧");
  console.log(`✓ 工钱：坐办公室一天 清贫 ${wage(["fam_poor", "send_home"])}（背贷款 ${wage(["fam_poor", "send_home", "loan"])}）/ 小康 ${base} / 殷实 ${wage(["fam_rich"])}（家里不管了 ${wage(["fam_rich", "fam_cut"])}）/ 四十五岁接爸妈、爸妈走了、还清了都摘标记 / 塞钱上限 ${reach(["fam_poor"])}·${reach([])}·${reach(["fam_rich"])}`);
}

// ---------- 5. 三十岁安家：三档人家各有各的冲法 ----------
{
  const toGate = (s, id) => { for (let i = 0; i < 800 && !s.world.event; i++) G("worldAdvance")(s, C, 0.1, ON); assert.equal(s.world.event?.eventId, id); };
  // 青是江家（清贫），梅是林家（小康）
  const s = lifeAt(41, 30, "jiang", "lin");
  s.persons.qing.money = G("lifeOptionMin")(opt("m_settle", "fixed"), s.persons.qing) + 5; s.persons.mei.money = G("lifeOptionMin")(opt("m_settle", "nest"), s.persons.mei) + 5; // 年代挪过的线
  s.bond.close = 10;
  toGate(s, "m_settle");
  const L = G("lifeMilestoneLocks")(s, C);
  const vis = (r, id) => shown(opt("m_settle", id), L[r][id]);
  assert.ok(vis("qing", "fixed") && !L.qing.fixed, "清贫人家翻修老屋");
  assert.ok(!vis("mei", "fixed"), "别的人家看不见翻修");
  assert.ok(vis("mei", "nest") && !L.mei.nest, "小康人家爸妈拿出那笔钱");
  assert.ok(!vis("qing", "nest"), "别的人家看不见那笔钱");
  assert.equal(L.qing.help, "爸妈帮不上", "殷实人家的首付照旧灰着给人看");
  assert.match(L.qing.share, /亲近/, "合住看亲近");
  assert.ok(opt("m_settle", "nest").min < opt("m_settle", "buy").min && opt("m_settle", "help").min < opt("m_settle", "nest").min, "首付：殷实人家的线最低，小康的那笔次之");
  assert.equal(G("worldChoose")(s, C, "qing", "fixed", false).error, null);
  assert.equal(G("worldChoose")(s, C, "mei", "nest", false).error, null);
  const q = s.persons.qing, m = s.persons.mei;
  const qBefore = G("lifeOptionMin")(opt("m_settle", "fixed"), q) + 5;
  assert.ok(q.flags.includes("home_fixed") && q.flags.includes("home_old") && !q.flags.includes("home_own"), "翻修的还住老屋（拆迁照样补钱），不算自己的房");
  assert.ok(m.flags.includes("home_own") && !m.flags.includes("fam_nest"), "那笔钱一辈子动一回");
  assert.equal(Math.round(q.money), Math.round(qBefore - opt("m_settle", "fixed").cost));
  // 两家合住一个院：亲近够了谁都能走，两个人都选是「门对着门」
  const t = lifeAt(42, 30, "jiang", "dong");
  t.bond.close = opt("m_settle", "share").min + 1;
  toGate(t, "m_settle");
  assert.equal(G("lifeMilestoneLocks")(t, C).mei.share, undefined, "殷实人家也走得了");
  assert.equal(G("worldChoose")(t, C, "qing", "share", false).error, null);
  assert.equal(G("worldChoose")(t, C, "mei", "share", false).error, null);
  assert.equal(t.log.at(-1).resonance, true);
  assert.equal(t.log.at(-1).text, ev("m_settle").resonance.share.text);
  assert.ok(ROLES.every((r) => t.persons[r].flags.includes("home_share")));
  assert.ok(ev("m_settle").resonance.share.bond.close <= 2, "合住给的亲近和别的共鸣一样少（七十岁并一家那条线夹着）");
  console.log("✓ 三十岁：清贫翻修老屋、小康爸妈那笔钱只给自己人家看 / 殷实的首付灰着给人看 / 线 殷实 < 小康 < 自己买 / 合住看亲近、谁都能走、两个人都选是门对着门");
}

// ---------- 6. 爸妈的意思：记一回脸色，记两回家里就不管了 ----------
{
  const t24 = G("lifeTimeAt")(turnAtAge(24));
  const ctx = { bond: { close: 20, sync: 10, distance: 0 }, alone: false };
  const can = (id, flags) => G("lifeEligible")(ev(id), t24, flags, {}, ctx);
  const EXP = { mx_exp_book: "exp_book", mx_exp_pull: "exp_pull", mx_exp_abroad: "exp_abroad", mx_exp_art: "exp_art" };
  const MET = { exp_book: ["job_desk", "job_teach"], exp_pull: ["job_desk", "job_pull"], exp_abroad: ["job_desk", "job_pull"], exp_art: ["job_desk", "job_teach", "job_pull"] };
  for (const [id, exp] of Object.entries(EXP)) {
    const e = ev(id);
    assert.ok(C.families.some((f) => f.traits.includes(exp)), `${exp}：总得有一户人家带着它`);
    assert.ok(can(id, ["fam_rich", exp, "job_trade"]), `${id}：做买卖的碰得上`);
    for (const j of MET[exp]) assert.ok(!can(id, ["fam_rich", exp, j]), `${id}：${j} 够上了爸妈的意思`);
    assert.ok(!can(id, ["fam_rich", exp, "job_trade", "fam_cut"]), `${id}：家里已经不管了的碰不上`);
    assert.ok(!can(id, ["fam_rich", exp, "own_shop"]), `${id}：家里出本钱开的铺子不算`);
    const open = (flags) => e.options.filter((o) => !G("lifeOptionLock")(e, o, { flags }, 0));
    const fresh = open(["fam_rich", exp, "job_trade"]), once = open(["fam_rich", exp, "job_trade", "strain1"]);
    assert.deepEqual(fresh.map((o) => o.text), once.map((o) => o.text), `${id}：记没记过脸色，摆出来的几句话一样`);
    assert.equal(fresh.filter((o) => o.effects.flags.includes("strain1")).length, 2, `${id}：头一回，顶回去、不吭声都记一回脸色`);
    assert.ok(fresh.every((o) => !o.effects.flags.includes("fam_cut")));
    assert.equal(once.filter((o) => o.effects.flags.includes("fam_cut")).length, 2, `${id}：已经记过一回的，再顶回去、不吭声家里就不管了`);
    const free = e.options.filter((o) => !o.requires);
    assert.ok(free.length >= 2 && free.every((o) => !o.effects.flags.includes("strain1") && !o.effects.flags.includes("fam_cut")), `${id}：听家里的、问问对门谁都能选，不记脸色`);
    const yieldTo = e.options.find((o) => o.id === "yield").effects.flags;
    assert.ok(yieldTo.some((f) => MET[exp].includes(f)) && yieldTo.includes("switched"), `${id}：听家里的就换成爸妈那条路`);
    // 换路要真换过去：原来那一行（托关系进的单位也算没够上）全摘掉，不然 tracks.yaml 排在前头的那条路还管着他
    const yieldDrop = e.options.find((o) => o.id === "yield").effects.drop;
    for (const job of ["job_desk", "job_pull", "job_teach", "job_trade", "job_craft", "job_labor", "job_succeed", "job_odd"]) assert.ok(yieldDrop.includes(job), `${id}：听家里的要摘掉 ${job}`);
    const went = yieldTo.find((f) => f.startsWith("job_"));
    for (const before of ["job_pull", "job_trade", "job_craft", "job_labor", "job_odd"]) {
      if (!can(id, ["fam_rich", exp, before])) continue;
      const flags = ["fam_rich", exp, before].filter((f) => !yieldDrop.includes(f)).concat(yieldTo);
      const tr = G("lifeTrack")(C, { flags }, 24);
      assert.ok(tr.id === went || tr.group === went, `${id}：${before} 听家里的以后走的是 ${went}（实际 ${tr.id}）`);
    }
  }
  // 二十二岁坐办公室：线谁都一样，头一年得自己先垫一笔；殷实人家家里出，家里不管了的自己出（docs/MEANS.md 第十节）
  {
    const desk = opt("m_job", "desk"), mj = ev("m_job");
    const costOf = (flags) => G("lifeOptionCost")(mj, desk, { flags });
    assert.ok(desk.cost > 0 && !desk.requires, "坐办公室谁都考得，要垫一笔");
    assert.equal(costOf(["fam_poor"]), desk.cost);
    assert.equal(costOf([]), desk.cost);
    assert.equal(costOf(["fam_rich", "exp_book"]), 0, "殷实人家家里出");
    assert.equal(costOf(["fam_rich", "exp_book", "strain1", "fam_cut"]), desk.cost, "家里不管了的自己出");
    const lock = (flags, money) => G("lifeOptionLock")(mj, desk, { flags, money, stats: { mind: 10, body: 5, charm: 5, luck: 5 } }, 0);
    assert.ok(lock(["fam_poor"], desk.cost - 1), "清贫人家攒不够那一笔，坐不了办公室");
    assert.equal(lock(["fam_poor"], desk.cost), null);
    assert.equal(lock(["fam_rich"], 0), null, "殷实人家一分钱没有也坐得了");
    // 差的是那一笔钱、分够了：对门塞过来（上限按对门的家境），殷实的对门塞得动，清贫的对门塞不动
    const atGate = (mf, myMoney, theirMoney) => {
      const g = lifeAt(29, 22, "wu", mf, 9.5);
      g.persons.qing.money = myMoney; g.persons.mei.money = theirMoney; g.bond.close = 80;
      for (let i = 0; i < 800 && !g.world.event; i++) G("worldAdvance")(g, C, 0.1, ON);
      assert.equal(g.world.event?.eventId, "m_job");
      return g;
    };
    const rich = atGate("dong", desk.cost - 8, 60);
    const offer = G("lifeMilestonePulls")(rich, C)?.qing?.desk;
    assert.ok(offer && offer.unit === "块" && offer.gap === 8 && offer.by === "mei", "殷实的对门把差的八块塞过来");
    assert.equal(G("worldChoose")(rich, C, "qing", "desk", false).error, null);
    assert.equal(G("worldChoose")(rich, C, "mei", "desk", false).error, null);
    assert.ok(rich.persons.qing.flags.includes("job_desk"), "塞了钱，坐上了办公室");
    const gate = rich.log.findLast((e) => e.kind === "milestone").gate;
    assert.equal(gate.pay?.qing?.gap, 8, "塞的是交的钱：记在 gate.pay");
    assert.equal(gate.pull?.qing, undefined, "不记进 gate.pull（揭晓卡照 pull 画分的尺子）");
    // 目标条：二十一岁线已经够了、钱还差，写还差几块；对门殷实，写 TA 能垫多少
    const tape = (mf, myMoney) => {
      const g = lifeAt(31, 21, "wu", mf, 9.5);
      g.persons.qing.money = myMoney; g.persons.mei.money = 60; g.bond.close = 80;
      return G("lifeGoal")(g, C, "qing")?.lines?.find((l) => l.id === "desk");
    };
    const short = tape("ma", 5);
    assert.ok(short && short.ok && short.short === desk.cost - 5 && !short.pull, `目标条：线够了，还差 ${short?.short} 块`);
    const helped = tape("dong", desk.cost - 8);
    assert.ok(helped.short === 8 && helped.pull?.gap === 8 && helped.pull.unit === "块", "对门殷实：目标条上写 TA 能垫你八块");
    assert.equal(tape("ma", 50).short, undefined, "钱够就不写");
    const poor = atGate("ma", desk.cost - 15, 60);
    assert.equal(G("lifeMilestonePulls")(poor, C)?.qing?.desk, undefined, "清贫的对门最多塞十块，差十五块塞不动");
  }
  // 二十二岁：董家（exp_pull）的「爸妈安排好的单位」不掏钱；郑家（exp_book）看不见这一条，托关系照旧自己掏
  const s = lifeAt(23, 22, "dong", "zheng", 9.5);
  s.persons.qing.money = 50; s.persons.mei.money = 50;
  for (let i = 0; i < 800 && !s.world.event; i++) G("worldAdvance")(s, C, 0.1, ON);
  assert.equal(s.world.event?.eventId, "m_job");
  const L = G("lifeMilestoneLocks")(s, C);
  assert.equal(L.qing.pull_home, undefined);
  assert.ok(!shown(opt("m_job", "pull_home"), L.mei.pull_home), "别的殷实人家看不见爸妈安排的单位");
  assert.equal(G("worldChoose")(s, C, "qing", "pull_home", false).error, null);
  assert.equal(G("worldChoose")(s, C, "mei", "pull", false).error, null);
  assert.equal(s.log.at(-1).resonance, true, "爸妈安排的和托关系进的是同一个单位");
  assert.equal(s.persons.qing.money, 50, "钱家里出");
  assert.equal(s.persons.mei.money, 50 - opt("m_job", "pull").cost);
  assert.ok(s.persons.qing.flags.includes("job_pull"));
  // 家里不管了：殷实人家的路锁上，写「家里已经不管你了」；别的人家看到的照旧是自己那句
  const cut = lifeAt(24, 22, "dong", "lin", 9.5);
  cut.persons.qing.flags.push("strain1", "fam_cut");
  for (let i = 0; i < 800 && !cut.world.event; i++) G("worldAdvance")(cut, C, 0.1, ON);
  const K = G("lifeMilestoneLocks")(cut, C);
  assert.equal(K.qing.pull, C.rules.locks.fam_cut);
  assert.equal(K.mei.pull, opt("m_job", "pull").lock, "小康人家看到的还是「家里没有这层关系」");
  assert.ok(!shown(opt("m_job", "pull_home"), K.qing.pull_home), "爸妈安排的那一条也看不见了");
  const p30 = { flags: ["fam_rich", "exp_pull", "strain1", "fam_cut"] };
  assert.equal(G("lifeOptionLock")(ev("m_settle"), opt("m_settle", "help"), p30, 0), C.rules.locks.fam_cut, "三十岁爸妈不出首付了");
  assert.equal(G("lifeOptionLock")(ev("m_settle"), opt("m_settle", "help"), { flags: ["fam_poor"] }, 0), opt("m_settle", "help").lock);
  console.log("✓ 爸妈的意思：四户各一件、没够上才碰得上 / 头一回记脸色、再一回家里不管了、两样字一样 / 听家里的换成爸妈那条路 / 爸妈安排的单位不掏钱、和托关系同路 / 家里不管了的锁上写「家里已经不管你了」，别的人家照旧");
}

// ---------- 7. 家道中落、一生小结 ----------
{
  const fall = ev("mn_rich_fall");
  assert.ok(fall.requires.notFlags.includes("fam_cut"));
  for (const o of fall.options) {
    assert.ok(o.effects.drop?.includes("fam_rich") && o.effects.flags.includes("fam_fallen"), `${o.id}：买卖倒了，往后按小康过`);
    const p = { flags: ["fam_rich", "exp_book"], money: 100 };
    G("lifeDropFlags")(p, o.effects.drop); G("lifeAddFlags")(p, o.effects.flags);
    assert.equal(G("lifeOptionLock")(ev("lv_shop_month"), opt("lv_shop_month", "home"), p, 0) !== null, true, "家里兜不了底了");
    assert.equal(G("pullReachMoney")(C, 100, p), C.rules.bond.pullMoney);
  }
  const blank = (flags) => ({ flags, stats: { body: 5, mind: 5, charm: 5, luck: 5 }, diedAtAge: 75 });
  const life = (flags) => C.endings.lives.find((e) => G("lifeLifeEndingOk")(blank(flags), e)).id;
  assert.equal(life(["fam_rich", "fam_cut", "home_own"]), "l_self_house", "家里不管了，房是自己买的");
  assert.equal(life(["fam_rich", "fam_cut", "job_desk"]), "l_self_desk");
  assert.notEqual(life(["fam_rich", "home_own", "home_help"]), "l_self_house", "爸妈出的首付不算");
  assert.equal(life(["fam_poor", "send_home", "job_desk"]), "l_first_desk");
  assert.equal(life(["fam_poor", "fam_siblings", "home_own"]), "l_own_door");
  assert.equal(life(["fam_fallen", "exp_art"]), "l_spent");
  console.log("✓ 家道中落：四条路都摘 fam_rich、打 fam_fallen，家里兜不了底、塞钱按小康 / 一生小结：没靠家里、自己考的、头一个、自己的门、家底");
}

// ---------- 8. 新事件守文风（docs/tianjin_style.md §9.1） ----------
{
  const TEXT_MAX = { childhood: 60, teen: 55, young: 50, middle: 45, old: 30 };
  const len = (x) => [...String(x ?? "")].length;
  const BANNED = ["嘛", "介", "倍儿", "哏儿", "甭", "您了", "得嘞", "崴泥", "打镲", "拔创", "好么", "嚯", "话匣子"];
  const raw = parse(readFileSync(new URL("../../content/events/hardship_money.yaml", import.meta.url), "utf8"));
  for (const e of raw) {
    assert.ok(len(e.text) <= TEXT_MAX[e.stage], `${e.id} 正文 ${len(e.text)} 字`);
    assert.ok(len(e.title) <= 7 && !/\d/.test(e.text), `${e.id}：标题不过七个字，正文不写数字`);
    for (const o of e.options) assert.ok(len(o.text) <= 15, `${e.id}.${o.id} 选项太长`);
    for (const s of [e.text, ...e.options.map((o) => o.text)]) for (const w of BANNED) assert.ok(!s.includes(w), `${e.id}：旁白和选项不用方言词「${w}」`);
    assert.ok(e.kind === "solo" && (e.requires?.minAge ?? 0) >= 23, `${e.id}：各自碰上的，二十三岁起（关口那天早上不冒出来）`);
  }
  console.log(`✓ 文风：hardship_money ${raw.length} 件守字数上限、不用方言、不写数字`);
}

// ---------- 9. 三档拉开（tools/origin.mjs 的口径：两个人放进同一档人家，过到三十一岁） ----------
// 只钉谁高谁低，不钉具体的数。三十岁那道关想要个落脚的地方：够得着自己的房先买，再是翻修、合住，都够不着才按 climb
{
  // 20 世（40 个人）：14 世的时候一格只有 28 个人，有房的比例上下差十几个点，「一档隔开一截」碰运气
  const N = 20;
  const HOMES = ["home_own", "home_share", "home_fixed"];
  const homeOf = (o) => (o.effects.flags.includes("home_own") ? 2 : HOMES.some((h) => o.effects.flags.includes(h)) ? 1 : 0);
  const settleFirst = (s, r, e, open) => {
    if (e.id !== "m_settle") return climb(s, r, e, open);
    const homes = open.filter((o) => homeOf(o)).sort((a, b) => homeOf(b) - homeOf(a) || (b.min || 0) - (a.min || 0));
    return homes.length ? homes[0].id : climb(s, r, e, open);
  };
  const cell = (way, tier) => {
    const fams = C.families.filter((f) => f.wealth === tier).map((f) => f.id);
    const rows = [];
    for (let i = 0; i < N; i++) {
      const { s, marks } = live((i + 1) * 15013, WAYS[way], 31, settleFirst, (st) => { st.rolls.qing.familyId = fams[i % fams.length]; st.rolls.mei.familyId = fams[(i + 1) % fams.length]; });
      for (const r of ROLES) rows.push({ flags: s.persons[r].flags, key: ["far", "paid"].some((o) => marks.m_senior?.[r]?.open.includes(o)), desk: ["desk", "pull", "pull_home"].some((o) => marks.m_job?.[r]?.open.includes(o)), money: marks.m_settle?.[r]?.money ?? 0 });
    }
    const pct = (f) => rows.filter(f).length / rows.length;
    const med = rows.map((x) => x.money).sort((a, b) => a - b)[rows.length >> 1];
    return { own: pct((x) => x.flags.includes("home_own")), home: pct((x) => HOMES.some((h) => x.flags.includes(h))), key: pct((x) => x.key), desk: pct((x) => x.desk), med };
  };
  const T = ["清贫", "小康", "殷实"];
  const solo = T.map((_, i) => cell("一个人念书", i)), lazy = T.map((_, i) => cell("不上心", i));
  const P = (x) => Math.round(x * 100) + "%";
  // 三档拉开：同样一个人念书，三十岁自己的房 清贫 < 小康 < 殷实，一档隔开一截
  assert.ok(solo[0].own + 0.15 <= solo[1].own && solo[1].own + 0.15 <= solo[2].own, `一个人念书三十岁有房 ${solo.map((c) => P(c.own)).join(" / ")}：三档没拉开`);
  assert.ok(solo[0].med < solo[1].med && solo[1].med < solo[2].med, `三十岁的积蓄 ${solo.map((c) => c.med).join(" / ")}：三档没拉开`);
  // 二十二岁坐办公室：考的是同一条线，可头一年要自己垫一笔（殷实人家家里出），清贫人家二十二岁手里那点钱多半不够
  assert.ok(solo[0].desk + 0.2 <= solo[1].desk && solo[1].desk + 0.1 <= solo[2].desk, `一个人念书二十二岁坐办公室 ${solo.map((c) => P(c.desk)).join(" / ")}：三档没拉开`);
  // 清贫人家的安家是另一场冲刺：买不起房，落脚的地方（翻修、合住）够得着
  assert.ok(solo[0].home >= solo[0].own + 0.3, `清贫人家一个人念书 落脚 ${P(solo[0].home)}，自己的房 ${P(solo[0].own)}：翻修、合住没接住`);
  // 每档专心比不上心高：中考、找事由、三十岁的积蓄
  for (let i = 0; i < 3; i++) {
    assert.ok(solo[i].key > lazy[i].key && solo[i].desk > lazy[i].desk, `${T[i]}：专心念书的中考 ${P(solo[i].key)}、办公室 ${P(solo[i].desk)}，不上心的 ${P(lazy[i].key)}、${P(lazy[i].desk)}`);
    // 三十岁的积蓄只比小康、殷实：清贫人家专心念书的二十二岁要先垫坐办公室那一笔（第十节），origin.mjs 量的是专心 106、不上心 118，
    // 这里二十世抽样两边差不到十块、随机数一挪就换位（人际圈子加了事件以后 98 对 104）。清贫这一档的冲刺是落脚和办公室，不是存折
    if (i > 0) assert.ok(solo[i].med > lazy[i].med, `${T[i]}：专心念书三十岁积蓄 ${solo[i].med}，不上心的 ${lazy[i].med}`);
    // 清贫那档留一条下限（PR #73 评审）：100 局里专心 99~105、不上心 105~113，低一截是机制；跌破八成就是清贫念书的钱塌了
    else assert.ok(solo[i].med >= lazy[i].med * 0.8, `清贫：专心念书三十岁积蓄 ${solo[i].med}，不到不上心的（${lazy[i].med}）八成`);
  }
  // 考场公平：清贫专心的中考比殷实不上心的高
  assert.ok(solo[0].key > lazy[2].key + 0.25, `清贫专心中考 ${P(solo[0].key)}，殷实不上心 ${P(lazy[2].key)}`);
  console.log(`✓ 三档拉开（一个人念书）：二十二岁坐办公室 ${solo.map((c) => P(c.desk)).join(" / ")}，三十岁有房 ${solo.map((c) => P(c.own)).join(" / ")}，落脚 ${solo.map((c) => P(c.home)).join(" / ")}，积蓄 ${solo.map((c) => Math.round(c.med)).join(" / ")} / 每档专心比不上心高（中考、办公室、积蓄）/ 清贫专心中考 ${P(solo[0].key)} 高过殷实不上心 ${P(lazy[2].key)}`);
}
