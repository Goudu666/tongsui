// 一件一件做（world.ts 的 worldActOnce，2026-11-11）：按一下做一回，这个人自己的钟往前拨这件事的时长，当场结算。
// 钉住：当场看得到结果 / 一段的时间用完就算定了 / 和「做到点」同样的时间换同样的成长和累 / 时间对得上才算搭伴、后到的给先到的补上 /
// 进门钱一段只付一回 / 一段过去时钟从两个人里慢的那个往后走 / 被对门带着做也能一回一回地做。
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const SLOTS = G("SLOTS");
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const spot = (id) => C.map.spots.find((sp) => sp.id === id);
const act = (id) => C.map.actions.find((a) => a.id === id);
function at(s, r, id) { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; }
/** 两个八岁的孩子，歇着的一天，傍晚那一段刚开头。属性、需求拉齐，结果只看做了什么 */
function evening(seed = 5, age = 8) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  const w = s.world;
  w.fate = { mirror: null, qing: null, mei: null };
  w.rest = true;
  w.slot = 3;
  w.minute = SLOTS[3][0];
  for (const r of ROLES) {
    const p = s.persons[r];
    p.stats = { body: 5, mind: 5, charm: 5, luck: 5 };
    p.born = { body: 5, mind: 5, charm: 5, luck: 5 };
    p.needs = { hunger: 80, energy: 80, mood: 80, clean: 80 };
    p.flags = p.flags.filter((f) => !f.startsWith("tal_"));
    p.money = 20;
  }
  return s;
}
const once = (s, r, sp) => G("worldAct")(s, C, r, sp, true);
const view = (s) => G("worldView")({ record: { life: s }, moveSeq: {}, tick: 0 });
/** 走完这一段（两个人都定了以后） */
function pass(s) {
  const from = s.world.slot, turn = s.turn;
  for (let i = 0; i < 4000 && s.world.slot === from && s.turn === turn; i++) G("worldAdvance")(s, C, 0.5, ON);
}

// ---------- 1. 按一下做一回，当场结算 ----------
{
  const s = evening();
  at(s, "qing", "desk_qing");
  const m0 = s.persons.qing.stats.mind, e0 = s.persons.qing.needs.energy;
  assert.equal(once(s, "qing", "desk_qing").error, null);
  const a = s.world.actors.qing;
  assert.equal(a.action, null, "做完一回人还是空着的，能接着走、接着做");
  assert.ok(s.persons.qing.stats.mind > m0, "心智当场就涨了");
  assert.ok(s.persons.qing.needs.energy < e0, "精力当场就掉了");
  assert.equal(G("worldClock")(s.world, a), SLOTS[3][0] + act("study").minutes, "自己的钟拨了一个半钟头");
  assert.equal(s.world.minute, SLOTS[3][0], "两个人共用的钟不动（等对门）");
  assert.equal(a.did.n, 1);
  assert.equal(a.did.a, "study");
  assert.equal(a.did.t - a.did.f, 90);
  assert.ok(a.did.s.mind > 0 && a.did.nd.energy < 0, "did 里写着涨了什么、累了多少");
  assert.ok(!G("worldReady")(s, "qing"), "傍晚三个钟头还剩一半，还没定");
  const v = view(s);
  assert.equal(v.actors.qing.pm, SLOTS[3][0] + 90, "WORLD 里有自己的钟");
  assert.equal(J(v.actors.qing.did).n, 1);
  assert.equal(once(s, "qing", "desk_qing").error, null);
  assert.equal(s.world.actors.qing.did.n, 2);
  assert.ok(G("worldReady")(s, "qing"), "时间用完了，就算定了，不用再按就这么过");
  assert.equal(once(s, "qing", "desk_qing").error, "这一段已经定了");
  delete s.world.ready.qing;
  assert.equal(once(s, "qing", "desk_qing").error, "这一段的时间用完了");
  // 晚上那一段：剩的时间不够一整回，就做剩下那一截
  const s2 = evening();
  at(s2, "qing", "desk_qing");
  s2.world.slot = 0; s2.world.minute = SLOTS[0][0];
  once(s2, "qing", "desk_qing"); // 早上 90 分钟，写作业正好一回
  assert.ok(G("worldReady")(s2, "qing"));
  const s3 = evening();
  at(s3, "qing", "roof_pigeon");
  s3.world.slot = 0; s3.world.minute = SLOTS[0][0];
  once(s3, "qing", "roof_pigeon"); // 放鸽子 60 分钟
  at(s3, "qing", "desk_qing");
  once(s3, "qing", "desk_qing"); // 只剩 30 分钟：写三分之一
  assert.equal(s3.world.actors.qing.did.part, 0.33);
  assert.equal(s3.world.actors.qing.did.t, SLOTS[0][1]);
  console.log("✓ 一回一回：当场涨、当场累、自己的钟往前拨 / 时间用完就定了 / 不够一整回做剩下那一截");
}

// ---------- 2. 同样的时间换同样的成长：一件一件做 vs 做到点 ----------
{
  for (const [id, sp] of [["study", "desk_qing"], ["play_roof", "roof_pigeon"], ["listen", "tea_seat"]]) {
    const A = evening(9), B = evening(9);
    for (const s of [A, B]) { at(s, "qing", sp); s.world.ready.mei = true; }
    assert.equal(G("worldAct")(A, C, "qing", sp).error, null);
    let n = 0;
    while (!G("worldReady")(B, "qing") && n < 10) { assert.equal(once(B, "qing", sp).error, null, id); n++; }
    pass(A); pass(B);
    const pa = A.persons.qing, pb = B.persons.qing;
    for (const k of ["body", "mind", "charm"]) {
      const da = pa.stats[k] - 5, db = pb.stats[k] - 5;
      if (Math.abs(da) < 1e-6) { assert.ok(Math.abs(db) < 1e-6, `${id} ${k}`); continue; }
      // 一件一件做的时候心情、精力是一回一回变的（效率跟着变），差几个百分点
      assert.ok(Math.abs(db / da - 1) < 0.12, `${id} ${k}：整段 ${da.toFixed(3)}，一回回 ${db.toFixed(3)}`);
    }
    for (const k of ["energy", "mood", "hunger", "clean"]) assert.ok(Math.abs(pa.needs[k] - pb.needs[k]) <= 3, `${id} ${k}：整段 ${pa.needs[k]}，一回回 ${pb.needs[k]}`);
    assert.ok(Math.abs(pa.money - pb.money) < 1e-6, `${id} 钱一样`);
  }
  console.log("✓ 同样的时间：一件一件做和做到点涨得一样多、累得一样多、花得一样多（写作业、放鸽子、听书）");
}

// ---------- 3. 搭伴：时间对得上才算，后到的给先到的补上 ----------
{
  // 单练对照
  const solo = evening(3);
  at(solo, "qing", "hall_stool");
  once(solo, "qing", "hall_stool");
  const soloGain = solo.persons.qing.stats.mind - 5;

  const s = evening(3);
  for (const r of ROLES) at(s, r, "hall_stool");
  once(s, "qing", "hall_stool");
  assert.ok(Math.abs(s.persons.qing.stats.mind - 5 - soloGain) < 1e-9, "先到的那一回先按单练算");
  assert.equal(s.world.actors.qing.did.tg, false);
  const r = once(s, "mei", "hall_stool");
  assert.equal(s.world.actors.mei.did.tg, true, "梅这一回是搭伴");
  assert.ok(s.world.actors.mei.did.b >= 1.5);
  assert.ok(r.together && r.together.kind === "together", "搭伴那一句话、心情和亲近当场给");
  const q = s.world.actors.qing;
  assert.equal(q.did.n, 2, "青那边多一条：TA 来了，补上的那一份");
  assert.equal(q.did.j, true);
  const tgGain = s.persons.qing.stats.mind - 5;
  assert.ok(tgGain / soloGain > 1.4 && tgGain / soloGain < 1.6, `补上以后青这一回是单练的 ${(tgGain / soloGain).toFixed(2)} 倍`);
  // 同一回不补两次
  at(s, "mei", "hall_stool");
  once(s, "mei", "hall_stool");
  assert.equal(s.world.actors.mei.did.tg, false, "青的下一回还没做，梅这一回时间对不上");

  // 时间错开：青先去楼顶放了一个钟头鸽子再写，梅一开头就写，只重叠半个钟头
  const x = evening(3);
  at(x, "qing", "roof_pigeon");
  once(x, "qing", "roof_pigeon");
  for (const rr of ROLES) at(x, rr, "hall_stool");
  once(x, "qing", "hall_stool"); // 16:30 - 18:00
  once(x, "mei", "hall_stool"); // 15:30 - 17:00
  assert.equal(x.world.actors.mei.did.tg, false, "对不上一半，不算搭伴");

  // 一边做到点、一边一回回：青整段写，梅写一回，梅是搭伴，青按陪了几成给倍率
  const y = evening(3), y0 = evening(3);
  for (const t of [y, y0]) for (const rr of ROLES) at(t, rr, "hall_stool");
  G("worldAct")(y, C, "qing", "hall_stool");
  G("worldAct")(y0, C, "qing", "hall_stool");
  once(y, "mei", "hall_stool");
  assert.equal(y.world.actors.mei.did.tg, true, "对门整段在这儿写，一回回去陪也是搭伴");
  assert.equal(y.world.actors.qing.tgMin, 90);
  for (const t of [y, y0]) { t.world.ready.mei = true; pass(t); }
  const share = (y.persons.qing.stats.mind - 5) / (y0.persons.qing.stats.mind - 5);
  assert.ok(share > 1.15 && share < 1.35, `陪了一半时间，整段的那个多长 ${(share * 100 - 100).toFixed(0)}%（全陪是 50%）`);

  // 反过来：梅先一回回写，青后来整段写，梅那一回补上
  const z = evening(3);
  for (const rr of ROLES) at(z, rr, "hall_stool");
  once(z, "mei", "hall_stool");
  G("worldAct")(z, C, "qing", "hall_stool");
  assert.equal(z.world.actors.mei.did.j, true, "后来整段做的也给先到的补上");
  assert.equal(z.world.actors.qing.tgMin, 90);
  console.log(`✓ 搭伴：后到的当场是搭伴、先到的补上（${(tgGain / soloGain).toFixed(2)} 倍）/ 一回只补一次 / 时间对不上一半不算 / 和做到点的混着也认`);
}

// ---------- 4. 进门的钱一段只付一回；一段过去 ----------
{
  const s = evening(4);
  at(s, "qing", "tea_seat");
  const fee = -act("listen").money;
  const m0 = s.persons.qing.money;
  once(s, "qing", "tea_seat");
  once(s, "qing", "tea_seat");
  assert.equal(s.persons.qing.money, m0 - fee, "坐一下午茶社也只付一壶茶钱");
  assert.equal(s.world.actors.qing.did.m, 0, "第二回不花钱");
  s.persons.qing.money = 0;
  assert.equal(once(s, "qing", "tea_seat").error, null, "付过了，兜里没钱也能接着听");
  // 做到点也不再付
  const s2 = evening(4);
  at(s2, "qing", "tea_seat");
  once(s2, "qing", "tea_seat");
  const m1 = s2.persons.qing.money;
  G("worldAct")(s2, C, "qing", "tea_seat");
  assert.equal(s2.persons.qing.money, m1, "这一段付过了，接着做到点不再付");
  G("worldCancel")(s2, C, "qing");
  assert.equal(s2.persons.qing.money, m1, "改主意不退一回回付过的那份");

  // 两个人都做满了：这一段一下子就过去，钟从慢的那个往后走
  const t = evening(4);
  at(t, "qing", "desk_qing"); at(t, "mei", "desk_mei");
  once(t, "qing", "desk_qing"); once(t, "qing", "desk_qing");
  once(t, "mei", "desk_mei");
  t.world.ready.mei = true; // 梅做了一回就歇着了
  G("worldAdvance")(t, C, 0.05, ON);
  assert.equal(t.world.playing, true);
  assert.equal(t.world.minute, SLOTS[3][0] + 90, "钟从梅的钟（做了一回）往后走");
  const e = t.persons.mei.needs.energy;
  pass(t);
  assert.equal(t.world.slot, 4, "进了晚上");
  assert.ok(t.persons.mei.needs.energy < e, "梅剩下歇着的那一个半钟头照样掉精力");
  assert.equal(J(t.world.runs).qing, undefined, "新的一段，记录清了");
  assert.equal(G("worldClock")(t.world, t.world.actors.qing), SLOTS[4][0], "自己的钟回到段头");
  console.log("✓ 进门钱一段只付一回（一回回、做到点都认）/ 一段过去从慢的那个的钟往后走，剩下歇着的时间照样掉需求，新的一段从段头开始");
}

// ---------- 5. 被对门带着：一回一回地也能跟 ----------
{
  const s = evening(11);
  const fam = (id) => C.families.find((f) => f.id === id);
  const born = (r, id) => { const p = s.persons[r]; const old = fam(p.familyId).traits; p.familyId = id; p.flags = p.flags.filter((f) => !old.includes(f)).concat(fam(id).traits); };
  born("qing", "dong"); born("mei", "wu");
  for (const r of ROLES) at(s, r, "palace_piano");
  assert.ok(once(s, "mei", "palace_piano").error, "梅自己进不去");
  const q0 = s.persons.qing.money, m0 = s.persons.mei.money;
  assert.equal(once(s, "qing", "palace_piano").error, null);
  assert.ok(J(view(s).tracks.mei.unlocks).includes("piano"), "青刚学过一回，梅的单子里有它");
  assert.equal(once(s, "mei", "palace_piano").error, null, "梅跟着学一回");
  assert.equal(s.world.actors.mei.did.tg, true);
  const fee = -act("piano").money;
  assert.equal(s.persons.qing.money, q0 - 2 * fee, "两份钱都是青出");
  assert.equal(s.persons.mei.money, m0);
  console.log("✓ 带上对门：对门刚一回回做过，也能跟进去，两份钱带的人出");
}

// ---------- 6. 一天收工：今天的时间花在哪、朝下一道关挪了多少 ----------
{
  const s = evening(6);
  s.world.goal0 = {};
  for (const r of ROLES) {
    const g = G("lifeGoal")(s, C, r);
    if (g) s.world.goal0[r] = { id: g.id, have: Object.fromEntries(g.lines.map((l) => [l.id, l.have])) };
  }
  s.world.slot = 4; s.world.minute = SLOTS[4][0];
  at(s, "qing", "desk_qing");
  once(s, "qing", "desk_qing");
  once(s, "qing", "desk_qing");
  G("worldPass")(s, C, "qing"); // 剩半个钟头，歇着
  at(s, "mei", "desk_mei");
  assert.equal(G("worldAct")(s, C, "mei", "desk_mei").error, null);
  const g0 = J(s.world.goal0.qing);
  let ended = null;
  for (let i = 0; i < 4000 && !ended; i++) {
    const t = G("worldAdvance")(s, C, 0.5, ON);
    if (t.dayEnded) ended = t.entries.find((e) => e.kind === "day");
  }
  assert.ok(ended, "这一天过完了");
  const segs = J(ended.spent.qing);
  assert.equal(segs.length, 1, "挨着的两回写作业并成一截");
  assert.equal(segs[0].f, SLOTS[4][0]);
  assert.equal(segs[0].t, SLOTS[4][0] + 180);
  assert.equal(J(ended.spent.mei)[0].t, SLOTS[4][1], "做到点的那一截到段尾");
  const dg = J(ended.goal.qing);
  assert.ok(dg && dg.title && dg.line, "写着下一道关和正在够的那条线");
  assert.ok(dg.have >= dg.have0, "分只会往上挪");
  assert.ok(typeof dg.turns === "number" && dg.need > 0);
  const kept = s.log.find((e) => e.kind === "day" && e.turn === ended.turn);
  assert.equal(kept.spent, undefined, "长卷里那一份不带今天的时间");
  console.log(`✓ 一天收工：时间花在哪并成一截一截（${segs.map((x) => x.l + " " + x.f + "-" + x.t).join("，")}）/ 下一道关「${dg.title}」${dg.line}：${dg.have0} → ${dg.have} / ${dg.need}${dg.pace ? "，照这样还要 " + dg.pace + " 个日子" : ""}，还剩 ${dg.turns} 个日子 / 长卷里不带`);
}
