// 传承（legacy.ts）：一世走完留下老物件、两人都点了就再来一世、投胎时各挑一件带上。
// 1) 头一世和以前一模一样  2) 每件老物件都有人留得下  3) 一世走完记下了什么  4) 再来一世（票、可复现）
// 5) 摆和挑  6) 带上以后多了什么（不叠、不越带越强）  7) 家业  8) 旧存档升级  9) 老物件被删以后
// 10) 房间：票进存档、重开接着投、上一世归档、新旧安装包混搭  11) 连着过几世  12) 老物件压不过活法
import assert from "node:assert/strict";
import { G, C, J, NAMES, SYSTEM_USER, fakeNakama, room } from "./harness.mjs";
import { WAYS, live, climb } from "../../tools/paths.mjs";

const ROLES = ["qing", "mei"];
const STATS = ["body", "mind", "charm", "luck"];
const OP = G("OP");
const heir = (id) => C.heirlooms.find((h) => h.id === id);
const sum = (st) => STATS.reduce((x, k) => x + st[k], 0);

/** 两个人都确认投胎 */
function confirm(s) {
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  assert.equal(s.phase, "life");
  return s;
}

/** 把一世过完（没人操作，事件让影子选） */
function liveOut(s) {
  if (s.phase === "roll") confirm(s);
  for (let tick = 0; s.phase !== "ended"; tick++) {
    G("worldAdvance")(s, C, 0.1, { qing: false, mei: false });
    const pe = s.world && s.world.event;
    if (pe) {
      for (const r of pe.roles) {
        if (s.world.event !== pe) break;
        if (!pe.choices[r]) assert.equal(G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, pe.eventId), false).error, null);
      }
    }
    assert.ok(tick < 400000, "人生没有结束");
  }
  return s;
}

/** 两人都点再来一世，换成下一世 */
function reborn(s) {
  G("legacyAgain")(s, "qing", true);
  assert.equal(G("legacyAgain")(s, "mei", true), true);
  return G("legacyRebirth")(s, C);
}

const lifeOne = liveOut(G("lifeCreate")(20261110, C));

// ---------- 1. 头一世和以前一模一样 ----------
{
  for (const seed of [1, 7, 20261110]) {
    const s = G("lifeCreate")(seed, C);
    assert.equal(s.life, 1);
    assert.deepEqual(J(s.legacy), { lives: 0, families: {}, heirlooms: [], past: [] });
    for (const r of ROLES) assert.deepEqual([s.rolls[r].house, J(s.rolls[r].offer), s.rolls[r].heirloomId], [0, [], null]);
    // 没有东西可摆的时候不多抽一次随机数：抽完两张卡，随机数停在哪儿还停在哪儿
    const bare = { rng: seed | 0 };
    const q = G("lifeRollOnce")(bare, C, null);
    G("lifeRollOnce")(bare, C, q.familyId);
    assert.equal(s.rng, bare.rng, "头一世多动了随机数，老存档和别的测试里的种子就对不上了");
    // 有传承的时候，两张卡也还是先抽的：人家和天赋不因为攒了东西而变
    const later = G("lifeCreate")(seed, C, { lives: 2, families: {}, heirlooms: ["h_photo", "h_books", "h_mug"], past: [] });
    for (const r of ROLES) assert.deepEqual([later.rolls[r].familyId, later.rolls[r].talentId, J(later.rolls[r].stats)], [s.rolls[r].familyId, s.rolls[r].talentId, J(s.rolls[r].stats)]);
    assert.equal(later.life, 3);
  }
  console.log("✓ 头一世：第 1 世、什么都不摆、不多动随机数；攒了东西也不改抽到的人家和天赋");
}

// ---------- 2. 每件老物件都有人留得下 ----------
{
  const blank = () => ({ flags: [], stats: { body: 5, mind: 5, charm: 5, luck: 5 }, money: 0, diedAtAge: 70 });
  for (const h of C.heirlooms) {
    const p = blank();
    const rq = h.from;
    p.flags = [...(rq.flags || [])];
    Object.assign(p.stats, rq.stats || {});
    if (rq.anyStat !== undefined) p.stats.luck = rq.anyStat;
    if (rq.minMoney !== undefined) p.money = rq.minMoney;
    if (rq.minDiedAge !== undefined) p.diedAtAge = rq.minDiedAge;
    assert.equal(G("legacyLeave")(C, p), h.id, `${h.name}：刚好够它的条件的人，留下的却是别的（被排在前面的挡住了）`);
    // 加成有上限：属性合计最多半点，钱最多十块，不许是负的
    const bonus = Object.values(h.bonus);
    assert.ok(bonus.every((v) => v > 0) && bonus.reduce((x, y) => x + y, 0) <= 0.5, `${h.name} 的属性加成超过半点`);
    assert.ok(h.money >= 0 && h.money + C.rules.legacy.houseMoney * C.rules.legacy.houseMax <= 10, `${h.name} 带的钱加上家业超过十块`);
  }
  const last = C.heirlooms.at(-1);
  assert.deepEqual(J(last.from), {}, "最后一件要没有条件，兜底");
  assert.equal(G("legacyLeave")(C, blank()), last.id);
  // 按顺序取第一件：又接了煎饼摊又结了婚，留下的是刮板
  const both = blank();
  both.flags = ["fam_breakfast", "took_over", "p_married", "retired", "job_trade"];
  assert.equal(G("legacyLeave")(C, both), "h_scraper");
  // 少一样就不算
  const p = blank();
  p.flags = ["job_teach"];
  assert.equal(G("legacyLeave")(C, p), last.id, "教了书没干到退休，不留粉笔");
  p.stats.body = 7; p.diedAtAge = 83;
  assert.equal(G("legacyLeave")(C, p), last.id);
  p.diedAtAge = 84;
  assert.equal(G("legacyLeave")(C, p), "h_towel");
  p.stats.body = 5; p.money = 149;
  assert.equal(G("legacyLeave")(C, p), last.id);
  p.money = 150;
  assert.equal(G("legacyLeave")(C, p), "h_passbook");
  // 两个人不留同一件：对门留了鸽哨，我接着往下找；都只剩兜底的时候不挑
  const pigeon = blank();
  pigeon.flags = ["p_pigeon", "p_capsule"];
  assert.equal(G("legacyLeave")(C, pigeon), "h_whistle");
  assert.equal(G("legacyLeave")(C, pigeon, "h_whistle"), "h_tin_box");
  pigeon.flags = ["p_pigeon"];
  assert.equal(G("legacyLeave")(C, pigeon, "h_whistle"), last.id);
  assert.equal(G("legacyLeave")(C, blank(), last.id), last.id);
  // 先走的先留；同一年走的一世一换
  const order = (q, m, life) => J(G("legacyLeaveOrder")({ life, persons: { qing: { diedAtAge: q }, mei: { diedAtAge: m } } }));
  assert.deepEqual([order(70, 80, 1), order(80, 70, 1), order(75, 75, 1), order(75, 75, 2)], [["qing", "mei"], ["mei", "qing"], ["qing", "mei"], ["mei", "qing"]]);
  console.log(`✓ 留下什么：${C.heirlooms.length} 件老物件各有人留得下 / 按顺序取第一件 / 兜底 / 两个人不留同一件 / 加成都在上限里`);
}

// ---------- 3. 一世走完记下了什么 ----------
{
  const s = lifeOne;
  const lg = s.legacy;
  assert.equal(lg.lives, 1);
  assert.equal(lg.past.length, 1);
  const past = lg.past[0];
  assert.equal(past.life, 1);
  assert.equal(past.pair, s.ending.pair);
  assert.equal(past.close, Math.round(s.bond.close));
  assert.ok(past.memories.length <= 4 && past.memories.every((t) => s.memories.some((m) => m.title === t)));
  assert.equal(s.log.at(-1).kind, "end");
  for (const r of ROLES) {
    const p = s.persons[r];
    const left = s.left[r];
    assert.ok(heir(left), "每个人都留下一件");
    assert.ok(lg.heirlooms.includes(left));
    assert.deepEqual(J(past.persons[r]), { name: p.name, familyId: p.familyId, talentId: p.talentId, diedAtAge: p.diedAtAge, ending: s.ending.lives[r], job: G("legacyJob")(p), heirloom: left });
    assert.ok(lg.families[p.familyId].lived >= 1);
    assert.equal(lg.families[p.familyId].kept, G("lifeHasFlag")(p, "took_over") ? 1 : 0);
  }
  const [first, second] = J(G("legacyLeaveOrder")(s));
  assert.equal(s.left[first], G("legacyLeave")(C, s.persons[first]));
  assert.equal(s.left[second], G("legacyLeave")(C, s.persons[second], s.left[first]));
  assert.ok(s.left.qing !== s.left.mei || s.left.qing === C.heirlooms.at(-1).id, "两个人不留同一件");
  assert.equal(new Set(lg.heirlooms).size, lg.heirlooms.length, "同一件不记两回");
  assert.deepEqual(J(G("lifeUpgrade")(J(s))), [], "刚存的档不用升级");
  console.log(`✓ 一世走完：留下 ${ROLES.map((r) => heir(s.left[r]).name).join("、")}，记了小传（${past.memories.length} 段回忆）和住过的人家`);
}

// ---------- 4. 再来一世：票、可复现、存档往返 ----------
{
  const living = confirm(G("lifeCreate")(5, C));
  assert.equal(G("legacyAgain")(living, "qing", true), false, "还没走完不能投");
  assert.equal(living.again, undefined);
  assert.equal(G("legacyAgainReady")(living), false);

  const s = J(lifeOne);
  assert.equal(G("legacyAgainReady")(s), false);
  assert.equal(G("legacyAgain")(s, "qing", true), false);
  assert.deepEqual(J(s.again), { qing: true, mei: false });
  assert.equal(G("legacyAgain")(s, "qing", false), false, "可以收回");
  assert.deepEqual(J(s.again), { qing: false, mei: false });
  G("legacyAgain")(s, "qing", true);
  // 一个人点了，存档，读档，另一个人再点：票还在，换出来的下一世和不读档的一样
  const reloaded = J(s);
  assert.equal(G("legacyAgain")(s, "mei", true), true);
  assert.equal(G("legacyAgain")(reloaded, "mei", true), true);
  assert.equal(G("legacyAgainReady")(reloaded), true);
  const a = G("legacyRebirth")(s, C), b = G("legacyRebirth")(reloaded, C);
  assert.deepEqual(J(a), J(b), "同一份存档换出来的下一世不一样");
  assert.deepEqual(J(G("legacyRebirth")(J(reloaded), C)), J(G("legacyRebirth")(J(reloaded), C)));

  assert.equal(a.phase, "roll");
  assert.equal(a.life, 2);
  assert.equal(a.turn, 0);
  assert.deepEqual([a.log.length, a.memories.length, a.persons, a.world, a.again, a.left, a.ending], [0, 0, null, null, undefined, undefined, undefined], "上一世的东西不带进下一世");
  assert.deepEqual(J(a.legacy), J(lifeOne.legacy), "传承原样带着");
  assert.equal(a.version, G("LIFE_VERSION"));
  console.log("✓ 再来一世：没走完不能投 / 票能收回 / 一人点了以后存档读档再点，换出来的是同一个下一世 / 只带传承");
}

// ---------- 5. 摆和挑 ----------
{
  // 攒了七件：两个人面前各三件，不重样，都是攒下的
  const pool = ["h_photo", "h_books", "h_mug", "h_candy_box", "h_passbook", "h_whistle", "h_scale"];
  const s = G("lifeCreate")(42, C, { lives: 3, families: {}, heirlooms: pool, past: [] });
  const oq = J(s.rolls.qing.offer), om = J(s.rolls.mei.offer);
  assert.deepEqual([oq.length, om.length], [3, 3]);
  assert.equal(new Set([...oq, ...om]).size, 6, "两人面前的不能重样");
  assert.ok([...oq, ...om].every((id) => pool.includes(id)));
  assert.deepEqual(J(G("lifeCreate")(42, C, { lives: 3, families: {}, heirlooms: pool, past: [] }).rolls), J(s.rolls), "同一个种子摆出来的一样");
  // 只攒了一件、三件：轮着摆。谁先摆一世一换，多出来的那件不会回回落在同一个人面前
  const one = G("lifeCreate")(42, C, { lives: 1, families: {}, heirlooms: ["h_photo"], past: [] });
  assert.deepEqual([J(one.rolls.qing.offer), J(one.rolls.mei.offer)], [["h_photo"], []]);
  const oneLater = G("lifeCreate")(42, C, { lives: 2, families: {}, heirlooms: ["h_photo"], past: [] });
  assert.deepEqual([J(oneLater.rolls.qing.offer), J(oneLater.rolls.mei.offer)], [[], ["h_photo"]]);
  const three = G("lifeCreate")(42, C, { lives: 1, families: {}, heirlooms: ["h_photo", "h_books", "h_mug"], past: [] });
  assert.deepEqual([three.rolls.qing.offer.length, three.rolls.mei.offer.length], [2, 1]);

  const pick = G("legacyPick");
  assert.equal(pick(s, "qing", om[0]), "这件东西不在你面前", "摆在对门面前的不能拿");
  assert.equal(pick(s, "qing", "h_nope"), "这件东西不在你面前");
  assert.equal(s.rolls.qing.heirloomId, null);
  assert.equal(pick(s, "qing", oq[0]), null);
  assert.equal(pick(s, "qing", oq[1]), null, "没确认之前可以换");
  assert.equal(s.rolls.qing.heirloomId, oq[1]);
  assert.equal(pick(s, "qing", null), null, "也可以放下不带");
  assert.equal(s.rolls.qing.heirloomId, null);
  pick(s, "qing", oq[2]);
  // 重抽人家不动面前摆的和手里挑的
  assert.equal(G("lifeReroll")(s, C, "qing"), null);
  assert.deepEqual([J(s.rolls.qing.offer), s.rolls.qing.heirloomId], [oq, oq[2]]);
  assert.equal(G("lifeConfirm")(s, C, "qing", NAMES), false);
  assert.equal(pick(s, "qing", oq[0]), "已经定下来了");
  assert.equal(pick(s, "mei", om[0]), null);
  assert.equal(G("lifeConfirm")(s, C, "mei", NAMES), true);
  assert.equal(pick(s, "mei", null), "已经开始了");
  assert.deepEqual([s.persons.qing.heirloomId, s.persons.mei.heirloomId], [oq[2], om[0]]);
  console.log("✓ 摆和挑：各三件不重样 / 对门面前的拿不了 / 确认前能换能放下 / 重抽不动 / 确认后定了");
}

// ---------- 6. 带上以后多了什么 ----------
{
  // 同一个种子投两回胎：一回空着手，一回带着东西。差出来的只能是那件东西写明的
  const born = (seed, heirlooms, take) => {
    const s = G("lifeCreate")(seed, C, { lives: 3, families: {}, heirlooms, past: [] });
    if (take) for (const r of ROLES) if (s.rolls[r].offer.length) assert.equal(G("legacyPick")(s, r, s.rolls[r].offer[0]), null);
    return confirm(s);
  };
  let checked = 0;
  for (const h of C.heirlooms) {
    for (const seed of [3, 99]) {
      const pool = [h.id];
      const plain = born(seed, pool, false), held = born(seed, pool, true);
      assert.equal(held.persons.qing.heirloomId, h.id);
      assert.equal(plain.persons.qing.heirloomId, null);
      const p0 = plain.persons.qing, p1 = held.persons.qing;
      for (const k of STATS) {
        const want = Math.min(10, p0.stats[k] + (h.bonus[k] || 0));
        assert.equal(p1.stats[k], want, `${h.name}：${k} 应该多 ${h.bonus[k] || 0}`);
        assert.equal(p1.born[k], p1.stats[k], "加成要算进出生的底子（成长规则按 born 算）");
      }
      assert.ok(sum(p1.born) - sum(p0.born) <= 0.5 + 1e-9);
      assert.equal(p1.money - p0.money, h.money);
      assert.equal(held.bond.close - plain.bond.close, h.close);
      for (const f of h.flags) assert.ok(p1.flags.includes(f), `${h.name} 的标记 ${f} 没带上`);
      // 对门没带，一点没变
      assert.deepEqual(J(held.persons.mei), J(plain.persons.mei));
      checked++;
    }
  }
  // 不越带越强：走完了多少世、这件东西带过多少回，带上以后多的都一样
  const first = G("lifeCreate")(3, C, { lives: 1, families: {}, heirlooms: ["h_books"], past: [] });
  const tenth = G("lifeCreate")(3, C, { lives: 11, families: {}, heirlooms: ["h_books"], past: [] });
  for (const s of [first, tenth]) { G("legacyPick")(s, "qing", "h_books"); confirm(s); }
  assert.deepEqual(J(first.persons.qing.stats), J(tenth.persons.qing.stats));
  console.log(`✓ 带上以后：${checked} 回对照，属性、钱、亲近、标记只多那件东西写明的；一人一件；走完 1 世带和走完 11 世带一样`);
}

// ---------- 7. 家业 ----------
{
  const R = C.rules.legacy;
  const kept = (n) => Object.fromEntries(C.families.map((f) => [f.id, { lived: n, kept: n }]));
  const base = confirm(G("lifeCreate")(8, C));
  for (const n of [1, 2, 3, 9]) { // 传了几代都试试，封顶在 houseMax
    const s = G("lifeCreate")(8, C, { lives: n, families: kept(n), heirlooms: [], past: [] });
    const house = Math.min(n, R.houseMax);
    for (const r of ROLES) assert.equal(s.rolls[r].house, house);
    confirm(s);
    for (const r of ROLES) {
      assert.equal(s.persons[r].money - base.persons[r].money, R.houseMoney * house, "家业只多几块钱的家底");
      assert.deepEqual(J(s.persons[r].stats), J(base.persons[r].stats), "家业不动属性");
    }
  }
  assert.ok(R.houseMoney * R.houseMax + Math.max(...C.heirlooms.map((h) => h.money)) <= 10, "家业加上最值钱的老物件，开局最多多十块");
  // 住过但没接下营生的不算；重抽到别的人家，家业跟着换
  const only = C.families[0].id;
  const s = G("lifeCreate")(8, C, { lives: 2, families: { ...Object.fromEntries(C.families.map((f) => [f.id, { lived: 2, kept: 0 }])), [only]: { lived: 2, kept: 1 } }, heirlooms: [], past: [] });
  for (let i = 0; i < C.rules.roll.rerolls; i++) {
    G("lifeReroll")(s, C, "qing");
    assert.equal(s.rolls.qing.house, s.rolls.qing.familyId === only ? 1 : 0);
  }
  console.log(`✓ 家业：接下过营生的人家，下一世家底多 ${R.houseMoney} 块一代，${R.houseMax} 代封顶；只住过不算；重抽跟着换`);
}

// ---------- 8. 旧存档升级（v5 → v6） ----------
{
  const strip = (s) => {
    const old = J(s);
    old.version = 5;
    for (const k of ["legacy", "life", "left", "again"]) delete old[k];
    for (const r of ROLES) {
      for (const k of ["house", "offer", "heirloomId"]) delete old.rolls[r][k];
      if (old.persons) delete old.persons[r].heirloomId;
    }
    return old;
  };
  // 抽卡中、过到一半的
  for (const src of [G("lifeCreate")(6, C), confirm(G("lifeCreate")(6, C))]) {
    const old = strip(src);
    assert.deepEqual(J(G("lifeUpgrade")(old)), ["v5→v6"]);
    assert.deepEqual(J(old), J(src), "升上来应该和现在新开的一模一样");
    assert.deepEqual(J(G("lifeRepair")(old, C)), []);
  }
  // 有传承之前就走完的：升级以后补记这一世，再来一世接得上
  const src = J(lifeOne);
  const old = strip(src);
  G("lifeUpgrade")(old);
  assert.equal(old.life, 1);
  assert.equal(old.left, undefined);
  const notes = J(G("lifeRepair")(old, C));
  assert.ok(notes.some((n) => n.includes("补记")), "走完的旧存档要补记");
  assert.deepEqual(J([old.left, old.legacy]), [src.left, src.legacy], "补记的和当时就记的一样");
  assert.deepEqual(J(G("lifeRepair")(old, C)), [], "只补一回");
  const next = reborn(old);
  assert.equal(next.life, 2);
  assert.ok(next.rolls.qing.offer.length + next.rolls.mei.offer.length >= 1);
  console.log("✓ 旧存档：v5 的抽卡中 / 过到一半 / 已经走完，升上来都能接着用；走完的补记一回");
}

// ---------- 9. 老物件从内容里删了以后 ----------
{
  const pool = ["h_photo", "h_books", "h_mug", "h_candy_box"];
  const s = G("lifeCreate")(42, C, { lives: 3, families: {}, heirlooms: [...pool], past: [] });
  const gone = s.rolls.qing.offer[0];
  G("legacyPick")(s, "qing", gone);
  const C2 = { ...C, heirlooms: C.heirlooms.filter((h) => h.id !== gone), version: "test-removed" };
  const notes = J(G("lifeRepair")(s, C2));
  assert.ok(notes.some((n) => n.includes(gone)), "要说清摘掉了哪件");
  assert.ok(!s.legacy.heirlooms.includes(gone) && s.legacy.heirlooms.length === pool.length - 1);
  assert.ok(!s.rolls.qing.offer.includes(gone));
  assert.equal(s.rolls.qing.heirloomId, null);
  confirm2(s, C2);
  // 走完以后留下的那件被删了：结局页不指着它，再来一世照常
  const ended = J(lifeOne);
  const lost = ended.left.qing;
  const C3 = { ...C, heirlooms: C.heirlooms.filter((h) => h.id !== lost), version: "test-removed-2" };
  G("lifeRepair")(ended, C3);
  assert.equal(ended.left.qing, null);
  assert.ok(!ended.legacy.heirlooms.includes(lost));
  G("legacyAgain")(ended, "qing", true); G("legacyAgain")(ended, "mei", true);
  const next = G("legacyRebirth")(ended, C3);
  assert.ok(![...next.rolls.qing.offer, ...next.rolls.mei.offer].includes(lost));
  console.log("✓ 内容改了：被删的老物件从攒下的、摆着的、挑中的、留下的里摘掉，投胎和换世照常");

  function confirm2(st, content) {
    for (const r of ROLES) G("lifeConfirm")(st, content, r, NAMES);
    assert.deepEqual([st.persons.qing.heirloomId, st.persons.mei.heirloomId], [null, null]);
  }
}

// ---------- 10. 房间：票进存档、重开接着投、上一世归档、新旧安装包混搭 ----------
{
  const pa = { userId: "user-a", sessionId: "sa" };
  const pb = { userId: "user-b", sessionId: "sb" };
  const NEW = { protocol: String(G("PROTOCOL_VERSION")) };
  const env = fakeNakama();
  const a = env.rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  env.rpc("rpcLifelineJoin", "user-b", { code: a.code, name: "小梅" });
  const id = a.lifelineId;
  const open = () => room(env.nk, env.rpc("rpcLifelineOpen", "user-a", { lifelineId: id }).matchId);
  const enter = (R, p, meta) => { assert.equal(R.attempt(p, meta).accept, true); R.join([p]); };
  const restart = () => { env.nk.matches.clear(); env.record(id).matchClaimedAt = Date.now() - 60000; };
  const past = (n) => env.nk.store.get(env.nk.k("lifeline_past", `${id}.${n}`, SYSTEM_USER));

  let R = open();
  // 青是新安装包，梅是旧的（进房时不报版本）
  enter(R, pa, NEW);
  enter(R, pb, undefined);
  const snap = R.to(pa, OP.SNAPSHOT).at(-1).data;
  assert.deepEqual(snap.protocols, { qing: 3, mei: 0 }, "青进来的时候梅还没到");
  assert.deepEqual(R.to(pb, OP.SNAPSHOT).at(-1).data.protocols, { qing: 3, mei: 2 }, "快照里要有两边安装包的版本，没报的按最旧能进来的算");
  assert.deepEqual(R.to(pa, OP.PRESENCE).at(-1).data.protocols, { qing: 3, mei: 2 });
  assert.equal(snap.life.life, 1);
  assert.deepEqual(snap.life.rolls.qing.offer, []);

  R.loop([R.msg(pa, OP.ROLL, { confirm: true }), R.msg(pb, OP.ROLL, { confirm: true })]);
  // 没走完就点：只回一个错，票不记
  R.loop([R.msg(pa, OP.AGAIN, {})]);
  assert.equal(R.to(pa, OP.ERROR).at(-1).data.message, "这一世还没走完");
  assert.equal(R.life().again, undefined);

  // 把这一世过完（直接推规则，房间里的存档就是这个对象），再让房间转一圈存下来
  liveOut(R.life());
  const leftNames = ROLES.map((r) => R.life().left[r]);
  assert.equal(R.loop(), true);
  const logLen = R.life().log.length;
  assert.ok(logLen > 50);

  // 青点了：票马上进存档；回执只发给版本够的连接
  const againBefore = R.sent.filter((m) => m.op === OP.AGAIN).length;
  R.loop([R.msg(pa, OP.AGAIN, {})]);
  assert.deepEqual(env.record(id).life.again, { qing: true, mei: false });
  const acks = R.sent.filter((m) => m.op === OP.AGAIN).slice(againBefore);
  assert.equal(acks.length, 1);
  assert.deepEqual(J(acks[0].to), ["sa"], "31 号消息不能发给旧安装包");
  assert.deepEqual(acks[0].data, { again: { qing: true, mei: false } });
  assert.equal(R.life().phase, "ended");
  assert.equal(past(1), undefined, "还没换世，不归档");

  // 服务器重启。梅更新了安装包，重新进来：快照里看得见青已经点了
  restart();
  R = open();
  enter(R, pb, NEW);
  const snapB = R.to(pb, OP.SNAPSHOT).at(-1).data;
  assert.deepEqual(snapB.life.again, { qing: true, mei: false }, "重开以后票还在");
  assert.deepEqual(snapB.protocols, { qing: 0, mei: 3 }, "不在线的一边版本是 0");
  assert.deepEqual(ROLES.map((r) => snapB.life.left[r]), leftNames);
  assert.equal(snapB.life.log.length, logLen, "结局页拿得到这一世的整卷");

  // 梅也点了：归档、换世、马上存、给在场的人发新的快照
  const snapsBefore = R.to(pb, OP.SNAPSHOT).length;
  R.loop([R.msg(pb, OP.AGAIN, { yes: true })]);
  const rec = env.record(id);
  assert.equal(rec.life.phase, "roll");
  assert.equal(rec.life.life, 2);
  assert.equal(rec.life.log.length, 0, "上一世的长卷不留在存档里");
  assert.equal(rec.life.again, undefined);
  assert.equal(rec.life.legacy.lives, 1);
  const arch = past(1);
  assert.ok(arch, "上一世要归档");
  assert.equal(arch.value.lifelineId, id);
  assert.equal(arch.value.life, 1);
  assert.deepEqual(arch.value.names, rec.names);
  assert.equal(arch.value.past.log.length, logLen, "归档里是整卷");
  assert.equal(arch.value.past.phase, "ended");
  assert.deepEqual(ROLES.map((r) => arch.value.past.left[r]), leftNames);
  for (const k of ["legacy", "again", "rng", "seed"]) assert.ok(!(k in arch.value.past), `归档里不该有 ${k}`);
  assert.equal(R.to(pb, OP.SNAPSHOT).length, snapsBefore + 1);
  const snap2 = R.to(pb, OP.SNAPSHOT).at(-1).data;
  assert.equal(snap2.life.phase, "roll");
  assert.equal(snap2.life.life, 2);
  assert.equal(snap2.life.log.length, 0);
  const offers = [...snap2.life.rolls.qing.offer, ...snap2.life.rolls.mei.offer];
  assert.deepEqual([...offers].sort(), [...new Set(leftNames)].sort(), "上一世留下的摆出来了");

  // 归档以后、存档之前断了：重开时票还齐着，接着换，换出来的是同一个下一世，归档不变
  const archVersion = arch.version;
  restart();
  const before = J(lifeOne); // 一份「票齐了、还没换」的存档
  before.again = { qing: true, mei: true };
  env.record(id).life = before;
  const want = J(G("legacyRebirth")(J(before), C));
  R = open();
  enter(R, pa, NEW);
  assert.equal(R.life().phase, "ended", "换世在房间转起来以后做，不在拉起时做");
  R.loop();
  assert.deepEqual(J(env.record(id).life), want, "重开接着换，和不断线换出来的一样");
  assert.ok(past(1).version !== archVersion, "归档重写了一遍（内容一样，写两遍不坏事）");
  assert.equal(past(2), undefined);
  assert.equal(want.life, 2);

  // 新的一世：挑一件，对门看得见；挑不在面前的回错
  enter(R, pb, NEW);
  const mine = R.life().rolls.qing.offer[0];
  R.loop([R.msg(pa, OP.ROLL, { heirloom: mine })]);
  const rs = R.to(pb, OP.ROLL_STATE).at(-1).data;
  assert.equal(rs.rolls.qing.heirloomId, mine, "对门要看得见我挑了哪件");
  R.loop([R.msg(pa, OP.ROLL, { heirloom: "h_nope" })]);
  assert.equal(R.to(pa, OP.ERROR).at(-1).data.message, "这件东西不在你面前");
  R.loop([R.msg(pa, OP.ROLL, { heirloom: null })]);
  assert.equal(R.life().rolls.qing.heirloomId, null);
  R.loop([R.msg(pa, OP.ROLL, { heirloom: mine })]);
  R.loop([R.msg(pa, OP.ROLL, { confirm: true }), R.msg(pb, OP.ROLL, { confirm: true })]);
  assert.equal(R.life().phase, "life");
  assert.equal(R.life().persons.qing.heirloomId, mine);
  // 大厅里看得见是第几世
  const list = env.rpc("rpcLifelineList", "user-a", {});
  assert.equal(list.lifelines.find((l) => l.lifelineId === id).life, 2);

  // 第二世走完再换：归档是第 2 世的，第 1 世的还在
  liveOut(R.life());
  R.loop([R.msg(pa, OP.AGAIN, {}), R.msg(pb, OP.AGAIN, {})]);
  assert.equal(env.record(id).life.life, 3);
  assert.equal(past(2).value.life, 2);
  assert.equal(past(1).value.life, 1);
  assert.equal(env.record(id).life.legacy.past.length, 2);
  assert.ok(JSON.stringify(env.record(id).life.legacy).length < 4000, "存档里跨世带着的东西要有界");
  console.log("✓ 房间：没走完不能投 / 票进存档、重启后还在 / 两票齐了归档再换世 / 断在半路重开接着换 / 31 只发给新安装包 / 挑的东西对门看得见 / 大厅显示第几世");
}

// ---------- 11. 连着过几世：攒下的东西有界，小传只留最近几世 ----------
{
  let s = lifeOne;
  const kept = C.rules.legacy.pastKept;
  const lives = kept + 2;
  for (let n = 2; n <= lives; n++) {
    s = reborn(J(s));
    assert.equal(s.life, n);
    for (const r of ROLES) if (s.rolls[r].offer.length) G("legacyPick")(s, r, s.rolls[r].offer[0]);
    const control = confirm(G("lifeCreate")(s.seed, C)); // 同一个种子、没有传承：属性的底子
    confirm(s);
    for (const r of ROLES) assert.ok(sum(s.persons[r].born) <= sum(control.persons[r].born) + 0.5 + 1e-9, `第 ${n} 世的先天属性比空着手多了不止半点`);
    liveOut(s);
  }
  const lg = s.legacy;
  assert.equal(lg.lives, lives);
  assert.equal(lg.past.length, kept, "小传只留最近几世");
  assert.deepEqual(lg.past.map((p) => p.life), Array.from({ length: kept }, (_, i) => lives - kept + 1 + i));
  assert.ok(lg.heirlooms.length <= C.heirlooms.length && new Set(lg.heirlooms).size === lg.heirlooms.length);
  assert.ok(JSON.stringify(lg).length < 8000, "传承在存档里的大小要有界");
  console.log(`✓ 连着过 ${lives} 世：攒下 ${lg.heirlooms.length} 件老物件，小传留 ${kept} 世，先天属性每世最多多半点，传承 ${JSON.stringify(lg).length} 字节`);
}

// ---------- 12. 老物件压不过活法 ----------
// 和 paths.test.mjs 用同一套机器人、同一批种子：一组空着手，一组两个人都带着东西。
// 老物件只该把线挪几个点；哪天它能顶替「这辈子怎么过」，前面的取舍就白做了。
{
  const N = 16;
  const carry = (id) => (s) => { for (const r of ROLES) s.rolls[r].heirloomId = id; };
  const run = (name, heirloom) => {
    const marks = [];
    for (let seed = 1; seed <= N; seed++) marks.push(live(seed * 7919, WAYS[name], 13, climb, heirloom ? carry(heirloom) : undefined).marks);
    return marks.flatMap((m) => Object.values(m.m_junior || {}));
  };
  const key = (ps) => ps.filter((p) => p.open.includes("key")).length / ps.length;
  const avg = (ps, f) => ps.reduce((a, p) => a + f(p), 0) / ps.length;
  const mind = (ps) => avg(ps, (p) => p.stats.mind), purse = (ps) => avg(ps, (p) => p.money);

  const lazy = run("不上心"), lazyBooks = run("不上心", "h_books"), half = run("一半念书一半玩"), solo = run("一个人念书");
  // 半点就是半点：到 12 岁多出来的不超过带上的那半点，也没有白带
  const kept = mind(lazyBooks) - mind(lazy);
  assert.ok(kept > 0.2 && kept <= 0.5 + 1e-9, `带着一箱书，到 12 岁心智多了 ${kept.toFixed(2)}，应该在半点以内、又不是白带`);
  // 带着书不上心，比不过空着手一半念书一半玩的；专心的空手人还是比他多 1.5 点（paths.test 的第 2 条）
  assert.ok(key(lazyBooks) < key(half), `带着一箱书的不上心有 ${Math.round(key(lazyBooks) * 100)}% 进重点班，不比空着手一半念书的（${Math.round(key(half) * 100)}%）少`);
  assert.ok(key(lazyBooks) <= 0.5, `带着一箱书的不上心有 ${Math.round(key(lazyBooks) * 100)}% 进重点班，线等于白划了`);
  const gap = mind(solo) - mind(lazyBooks);
  assert.ok(gap >= 1.5, `专心念书的空手人只比带着书的不上心多 ${gap.toFixed(2)} 点心智`);

  // 钱：带着存折念书的，攒的还是比不过从小挣钱的（paths.test 的第 6 条：钱是拿成长换的，不是带来的）
  const hustle = run("从小挣钱"), soloPurse = run("一个人念书", "h_passbook");
  const extra = purse(soloPurse) - purse(solo);
  assert.ok(extra <= heir("h_passbook").money + 1e-9, `带着存折到 12 岁多了 ${extra.toFixed(0)} 块，比存折里的还多`);
  assert.ok(purse(hustle) > purse(soloPurse) + 10, `从小挣钱的只比带着存折念书的多 ${(purse(hustle) - purse(soloPurse)).toFixed(0)} 块，钱成了带来的`);
  console.log(`✓ 压不过活法：带一箱书到 12 岁心智多 ${kept.toFixed(2)}，重点班 ${Math.round(key(lazy) * 100)}% → ${Math.round(key(lazyBooks) * 100)}%（空手一半念书 ${Math.round(key(half) * 100)}%）/ 专心的空手人还多 ${gap.toFixed(1)} 点 / 带存折多 ${extra.toFixed(0)} 块，从小挣钱的还多 ${(purse(hustle) - purse(soloPurse)).toFixed(0)} 块`);
}
