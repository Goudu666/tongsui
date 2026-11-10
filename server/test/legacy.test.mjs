// 传承（legacy.ts）：一世走完留下老物件、两人都点了就再来一世、投胎时各挑一件带上。
// 1) 头一世和以前一模一样  2) 每件老物件都有人留得下  3) 一世走完记下了什么  4) 再来一世（票、可复现）
// 5) 摆和挑  6) 带上以后多了什么（不叠、不越带越强）  7) 家业  8) 旧存档升级  9) 老物件被删以后
// 10) 房间：票进存档、重开接着投、上一世归档、新旧安装包混搭  11) 连着过几世  12) 老物件压不过活法
// 第二步：13) 痕迹  14) 藏着的天赋（要先出过那件事 / 换一种活法，不是更强）  15) 街坊记住的事（只记一回、不给东西）
// 16) v6 存档升 v7、内容删了以后  17) 住户本读归档（只给两个人、只给挑过的那几样）
import assert from "node:assert/strict";
import { G, C, J, NAMES, SYSTEM_USER, fakeNakama, room } from "./harness.mjs";
import { WAYS, live, climb } from "../../tools/paths.mjs";

const ROLES = ["qing", "mei"];
const STATS = ["body", "mind", "charm", "luck"];
const OP = G("OP");
const heir = (id) => C.heirlooms.find((h) => h.id === id);
const sum = (st) => STATS.reduce((x, k) => x + st[k], 0);
/** 一份传承（没写的字段是空的） */
const LG = (o = {}) => ({ ...J(G("legacyNew")()), ...o });

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
    assert.deepEqual(J(s.legacy), { lives: 0, families: {}, heirlooms: [], past: [], traces: [], marks: [], remembered: {} });
    for (const r of ROLES) assert.ok(!C.talents.find((t) => t.id === s.rolls[r].talentId).unlock, "头一世抽到了藏着的天赋");
    for (const r of ROLES) assert.deepEqual([s.rolls[r].house, J(s.rolls[r].offer), s.rolls[r].heirloomId], [0, [], null]);
    // 没有东西可摆的时候不多抽一次随机数：抽完两张卡，随机数停在哪儿还停在哪儿
    const bare = { rng: seed | 0 };
    const q = G("lifeRollOnce")(bare, C, null);
    G("lifeRollOnce")(bare, C, q.familyId);
    assert.equal(s.rng, bare.rng, "头一世多动了随机数，老存档和别的测试里的种子就对不上了");
    // 有传承的时候，两张卡也还是先抽的：人家和天赋不因为攒了东西而变
    const later = G("lifeCreate")(seed, C, LG({ lives: 2, heirlooms: ["h_photo", "h_books", "h_mug"] }));
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
  p.stats.body = 5; p.money = heir("h_passbook").from.minMoney - 1;
  assert.equal(G("legacyLeave")(C, p), last.id);
  p.money += 1;
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
  // 第二步记的：街坊新记住的事（长卷和小传里是同一份）、留下的痕迹、出过的事
  assert.ok(Array.isArray(s.noted));
  assert.deepEqual(J(past.noted), J(s.noted));
  assert.deepEqual(Object.keys(lg.remembered).sort(), [...s.noted].sort());
  const anyone = (f) => ROLES.some((r) => s.persons[r].flags.includes(f));
  assert.deepEqual(J(lg.traces), J(C.legacy.traces).filter(anyone));
  assert.deepEqual(J(lg.marks), J(C.legacy.marks).filter(anyone));
  assert.deepEqual(Object.keys(lg).sort(), ["families", "heirlooms", "lives", "marks", "past", "remembered", "traces"], "河畔里不攒跨世的计数");
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
  const s = G("lifeCreate")(42, C, LG({ lives: 3, heirlooms: pool }));
  const oq = J(s.rolls.qing.offer), om = J(s.rolls.mei.offer);
  assert.deepEqual([oq.length, om.length], [3, 3]);
  assert.equal(new Set([...oq, ...om]).size, 6, "两人面前的不能重样");
  assert.ok([...oq, ...om].every((id) => pool.includes(id)));
  assert.deepEqual(J(G("lifeCreate")(42, C, LG({ lives: 3, heirlooms: pool })).rolls), J(s.rolls), "同一个种子摆出来的一样");
  // 只攒了一件、三件：轮着摆。谁先摆一世一换，多出来的那件不会回回落在同一个人面前
  const one = G("lifeCreate")(42, C, LG({ lives: 1, heirlooms: ["h_photo"] }));
  assert.deepEqual([J(one.rolls.qing.offer), J(one.rolls.mei.offer)], [["h_photo"], []]);
  const oneLater = G("lifeCreate")(42, C, LG({ lives: 2, heirlooms: ["h_photo"] }));
  assert.deepEqual([J(oneLater.rolls.qing.offer), J(oneLater.rolls.mei.offer)], [[], ["h_photo"]]);
  const three = G("lifeCreate")(42, C, LG({ lives: 1, heirlooms: ["h_photo", "h_books", "h_mug"] }));
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
    const s = G("lifeCreate")(seed, C, LG({ lives: 3, heirlooms }));
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
  const first = G("lifeCreate")(3, C, LG({ lives: 1, heirlooms: ["h_books"] }));
  const tenth = G("lifeCreate")(3, C, LG({ lives: 11, heirlooms: ["h_books"] }));
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
    const s = G("lifeCreate")(8, C, LG({ lives: n, families: kept(n) }));
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
  const s = G("lifeCreate")(8, C, LG({ lives: 2, families: { ...Object.fromEntries(C.families.map((f) => [f.id, { lived: 2, kept: 0 }])), [only]: { lived: 2, kept: 1 } } }));
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
    for (const k of ["legacy", "life", "left", "again", "noted"]) delete old[k];
    for (const r of ROLES) {
      for (const k of ["house", "offer", "heirloomId"]) delete old.rolls[r][k];
      if (old.persons) delete old.persons[r].heirloomId;
    }
    return old;
  };
  // 抽卡中、过到一半的
  for (const src of [G("lifeCreate")(6, C), confirm(G("lifeCreate")(6, C))]) {
    const old = strip(src);
    assert.deepEqual(J(G("lifeUpgrade")(old)), ["v5→v6", "v6→v7", "v7→v8"]);
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
  const s = G("lifeCreate")(42, C, LG({ lives: 3, heirlooms: [...pool] }));
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
  const PV = G("PROTOCOL_VERSION"), PMIN = G("MIN_CLIENT_PROTOCOL");
  assert.deepEqual(snap.protocols, { qing: PV, mei: 0 }, "青进来的时候梅还没到");
  assert.deepEqual(R.to(pb, OP.SNAPSHOT).at(-1).data.protocols, { qing: PV, mei: PMIN }, "快照里要有两边安装包的版本，没报的按最旧能进来的算");
  assert.deepEqual(R.to(pa, OP.PRESENCE).at(-1).data.protocols, { qing: PV, mei: PMIN });
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
  // 协议 4（一天五段）以后进得来的安装包都认识 31：两边都发
  assert.equal(acks.length, 1);
  assert.deepEqual(J(acks[0].to).sort(), ["sa", "sb"], "两边的安装包都够新");
  assert.deepEqual(acks[0].data, { again: { qing: true, mei: false } });
  assert.equal(R.life().phase, "ended");
  assert.equal(past(1), undefined, "还没换世，不归档");
  // 连着点：票没变就不写存储，回执照发
  const stored = () => env.nk.store.get(env.nk.k("lifelines", id, "00000000-0000-0000-0000-000000000000")).version;
  const v0 = stored();
  R.loop([R.msg(pa, OP.AGAIN, {}), R.msg(pa, OP.AGAIN, { yes: true })]);
  assert.equal(stored(), v0, "票没变不该再写一次存档");
  assert.equal(R.sent.filter((m) => m.op === OP.AGAIN).length, againBefore + 3);
  R.loop([R.msg(pa, OP.AGAIN, { yes: false })]);
  assert.notEqual(stored(), v0, "收回是变了，要存");
  assert.deepEqual(env.record(id).life.again, { qing: false, mei: false });
  R.loop([R.msg(pa, OP.AGAIN, {})]);
  assert.deepEqual(env.record(id).life.again, { qing: true, mei: false });

  // 服务器重启。梅更新了安装包，重新进来：快照里看得见青已经点了
  restart();
  R = open();
  enter(R, pb, NEW);
  const snapB = R.to(pb, OP.SNAPSHOT).at(-1).data;
  assert.deepEqual(snapB.life.again, { qing: true, mei: false }, "重开以后票还在");
  assert.deepEqual(snapB.protocols, { qing: 0, mei: PV }, "不在线的一边版本是 0");
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

// =====================================================================
// 第二步：痕迹、藏着的天赋、街坊记住的事、住户本
// =====================================================================

/** 一份走完的存档，传承清空、两个人身上这一世攒的共同标记摘掉：拿来单独试「一世走完记什么」 */
function endedBlank(life = 1, legacy = LG()) {
  const s = J(lifeOne);
  s.life = life;
  s.legacy = legacy;
  delete s.noted;
  for (const r of ROLES) s.persons[r].flags = s.persons[r].flags.filter((f) => !/^(p_|x_|leg_|job_)/.test(f) && !["took_over", "left_city", "came_back", "deja_vu", "retake"].includes(f));
  return s;
}
const give = (s, flags, roles = ROLES) => { for (const r of roles) s.persons[r].flags.push(...flags); return s; };

// ---------- 13. 痕迹：上一世两个人一起做过的事，下一世的孩子出生就带着 ----------
{
  const first = confirm(G("lifeCreate")(11, C));
  for (const r of ROLES) assert.ok(!first.persons[r].flags.some((f) => f.startsWith("leg_")), "头一世的孩子身上不该有上一世的痕迹");
  const second = confirm(G("lifeCreate")(11, C, LG({ lives: 1, traces: ["p_wall_names", "p_capsule"] })));
  for (const r of ROLES) {
    const f = second.persons[r].flags;
    assert.ok(f.includes("leg_any") && f.includes("leg_p_wall_names") && f.includes("leg_p_capsule"));
    assert.ok(!f.includes("leg_p_pigeon") && !f.includes("leg_house"));
    // 痕迹只是标记：属性、钱都和头一世同一个种子的孩子一样
    assert.deepEqual([J(second.persons[r].stats), second.persons[r].money], [J(first.persons[r].stats), first.persons[r].money]);
    assert.deepEqual(J(f).filter((x) => !x.startsWith("leg_")), J(first.persons[r].flags));
  }
  assert.deepEqual(J(second.bond), J(first.bond));
  // 家里的营生传下来过：多一个 leg_house（柜顶的匣子靠它）
  const house = confirm(G("lifeCreate")(11, C, LG({ lives: 1, families: Object.fromEntries(C.families.map((f) => [f.id, { lived: 1, kept: 1 }])) })));
  for (const r of ROLES) assert.ok(house.persons[r].flags.includes("leg_house"));

  // 只记上一世的：这一世接着做了才传得下去，没人再做就到此为止
  const fade = give(endedBlank(2, LG({ lives: 1, traces: ["p_capsule"] })), ["leg_any", "leg_p_capsule"]);
  G("legacyNote")(fade, C);
  assert.deepEqual(J(fade.legacy.traces), [], "上一世埋的盒子，这一世没人添东西，不该再往下传");
  const kept = give(endedBlank(2, LG({ lives: 1, traces: ["p_capsule"] })), ["leg_any", "leg_p_capsule", "p_capsule", "p_promise"]);
  G("legacyNote")(kept, C);
  assert.deepEqual(J(kept.legacy.traces), ["p_capsule", "p_promise"]);
  assert.ok(J(C.legacy.traces).every((t) => t.startsWith("p_")), "能留下痕迹的只有两个人一起做的事（共同标记）");

  // 隔世的事都得带着上一世的痕迹（或藏着的天赋）才遇得到：头一世一件也碰不上
  const cross = J(C.events).filter((e) => e.id.startsWith("l_"));
  assert.ok(cross.length >= 6);
  for (const e of cross) assert.ok((e.requires.flags || []).some((f) => /^(leg_|tal_(late|linked|oldsoul)$)/.test(f)), `${e.id} 没有挂在上一世的痕迹上`);
  for (const t of J(C.legacy.traces)) {
    const read = JSON.stringify([C.events, C.endings, C.remembered]).includes(`"leg_${t}"`);
    assert.ok(read, `痕迹 ${t} 留下了却没有东西读它`);
  }
  console.log(`✓ 痕迹：头一世没有 / 下一世的孩子带着 leg_ 标记，别的一样不多 / 这一世没接着做就不再传 / ${cross.length} 件隔世的事都挂在痕迹或藏着的天赋上`);
}

// ---------- 14. 藏着的天赋：这条人生线上出过那件事才抽得到；换一种活法，不是更强 ----------
{
  const all = J(C.talents);
  const hidden = all.filter((t) => t.unlock), plain = all.filter((t) => !t.unlock);
  assert.equal(hidden.length, 3);
  assert.deepEqual(hidden.map((t) => t.unlock).sort(), J(C.legacy.marks));
  assert.ok(hidden.every((t) => Object.keys(t.bonus).length === 0), "藏着的天赋不多给先天属性");
  const ids = (lg) => J(G("legacyTalents")(C, lg)).map((t) => t.id);
  assert.deepEqual(ids(undefined), plain.map((t) => t.id));
  assert.deepEqual(ids(LG({ lives: 5 })), plain.map((t) => t.id), "过了多少世都不算数，要出过那件事");
  for (const h of hidden) assert.deepEqual(ids(LG({ lives: 1, marks: [h.unlock] })), all.filter((t) => !t.unlock || t.id === h.id).map((t) => t.id));

  const roll = (legacy, n) => {
    const st = { rng: 20261110 }, seen = {};
    for (let i = 0; i < n; i++) { const t = G("lifeRollOnce")(st, C, null, legacy).talentId; seen[t] = (seen[t] || 0) + 1; }
    return seen;
  };
  const N = 6000;
  const before = roll(LG({ lives: 3 }), N), after = roll(LG({ lives: 3, marks: J(C.legacy.marks) }), N);
  const total = all.reduce((x, t) => x + t.weight, 0);
  for (const h of hidden) {
    assert.equal(before[h.id], undefined, `${h.name} 没出过那件事就抽到了`);
    const share = after[h.id] / N, want = h.weight / total;
    assert.ok(share > want * 0.6 && share < want * 1.5, `${h.name} 抽到的比例 ${share.toFixed(3)}，按权重该是 ${want.toFixed(3)}`);
  }

  // 出过的事：有一个人带着那个标记走完一世就记上，记上以后一直在
  const s = give(endedBlank(1), ["deja_vu"], ["mei"]);
  G("legacyNote")(s, C);
  assert.deepEqual(J(s.legacy.marks), ["deja_vu"]);
  const next = endedBlank(2, J(s.legacy));
  G("legacyNote")(next, C);
  assert.deepEqual(J(next.legacy.marks), ["deja_vu"], "下一世没再遇上，出过的事也还在");
  // 内容里把这种天赋摘了：出过的事跟着摘，抽到它的人重抽（save.ts 原有的修复）
  const C2 = { ...C, talents: C.talents.filter((t) => t.id !== "oldsoul"), legacy: { traces: C.legacy.traces, marks: J(C.legacy.marks).filter((m) => m !== "deja_vu") }, version: "test-no-oldsoul" };
  const st = G("lifeCreate")(5, C, LG({ lives: 1, marks: ["deja_vu", "retake"] }));
  st.rolls.qing.talentId = "oldsoul";
  const notes = J(G("lifeRepair")(st, C2));
  assert.deepEqual(J(st.legacy.marks), ["retake"]);
  assert.ok(st.rolls.qing.talentId !== "oldsoul" && notes.some((n) => n.includes("oldsoul")));

  // 换一种活法：同一批种子、同一种过法，两个人都换成这种天赋，和一个没有数值规则的天赋（夜猫子）比
  const SEEDS = 24;
  const as = (talent) => (life) => { for (const r of ROLES) life.rolls[r].talentId = talent; };
  const run = (way, talent, until) => Array.from({ length: SEEDS }, (_, i) => live((i + 1) * 7919, WAYS[way], until, climb, as(talent)));
  const at = (runs, id) => runs.flatMap((x) => Object.values(x.marks[id] || {}));
  const avg = (ps, f) => ps.reduce((a, p) => a + f(p), 0) / ps.length;
  const opens = (ps, o) => ps.filter((p) => p.open.includes(o)).length / ps.length;
  const total3 = (p) => p.stats.body + p.stats.mind + p.stats.charm;

  // 大器晚成：前面的关口吃亏，三十岁以后追上来，六十岁主项反超
  const late = run("一个人念书", "late", 61), owl = run("一个人念书", "owl", 61);
  const m = (runs, id) => avg(at(runs, id), (p) => p.stats.mind);
  assert.ok(m(late, "m_junior") < m(owl, "m_junior") - 0.3, `大器晚成 12 岁心智 ${m(late, "m_junior").toFixed(2)}，不比别人（${m(owl, "m_junior").toFixed(2)}）慢`);
  assert.ok(opens(at(late, "m_junior"), "key") < opens(at(owl, "m_junior"), "key"), "大器晚成进重点班的不该和别人一样多");
  assert.ok(opens(at(late, "m_gaokao"), "away") < opens(at(owl, "m_gaokao"), "away"), "大器晚成考去外地的不该和别人一样多");
  assert.ok(m(late, "m_retire") > m(owl, "m_retire") + 0.1, `大器晚成 60 岁心智 ${m(late, "m_retire").toFixed(2)}，没有追过别人（${m(owl, "m_retire").toFixed(2)}）`);
  const gap60 = avg(at(late, "m_retire"), total3) - avg(at(owl, "m_retire"), total3);
  assert.ok(Math.abs(gap60) < 1.2, `大器晚成 60 岁三项合计和别人差了 ${gap60.toFixed(2)}，换一种活法不该差出一大截`);

  // 连心：各顾各的也不容易生分；属性一点不多，心情跟着对门走
  const linked = run("各顾各的", "linked", 31), apart = run("各顾各的", "owl", 31);
  const close = (runs) => avg(runs, (x) => x.s.bond.close);
  assert.ok(close(linked) > close(apart) + 2, `连心的亲近 ${close(linked).toFixed(1)}，和别人（${close(apart).toFixed(1)}）没差`);
  const gapL = avg(at(linked, "m_settle"), total3) - avg(at(apart, "m_settle"), total3);
  assert.ok(Math.abs(gapL) < 0.4, `连心 30 岁三项合计和别人差了 ${gapL.toFixed(2)}`);
  const moodGap = (runs) => avg(runs, (x) => Math.abs(x.s.persons.qing.needs.mood - x.s.persons.mei.needs.mood));
  assert.ok(moodGap(linked) < moodGap(apart), "连心的两个人，心情应该比别人挨得近");
  // 它没有真的代价，靠窄站住：只帮本来就搭伴的人把七十岁那一关接住，而且不能接得太稳；各顾各的人够不着
  const pairUp = (runs) => opens(at(runs, "m_evening"), "pair");
  // 这一条两边只差几个百分点，24 条人生里一个人就能翻过来：多跑几条（一天五段以后机器人快多了）
  const runN = (n, way, talent, until) => Array.from({ length: n }, (_, i) => live((i + 1) * 7919, WAYS[way], until, climb, as(talent)));
  const nearL = runN(64, "搭伴念书", "linked", 71), nearO = runN(64, "搭伴念书", "owl", 71), farL = run("各顾各的", "linked", 71);
  assert.ok(pairUp(nearL) >= pairUp(nearO) - 0.05, "连心的两个人搭伴过，老了不该比别人更难并一家");
  assert.ok(pairUp(nearL) <= 0.6, `搭伴的连心七十岁能并一家的有 ${Math.round(pairUp(nearL) * 100)}%，超过六成就是白给了（linkedDrift 调得太低）`);
  assert.equal(pairUp(farL), 0, "各顾各的连心也够得着并一家：它不该替人把搭伴省了");

  // 老灵魂：检定多一点把握，小时候魅力长得慢
  const old = run("嘴甜人缘好", "oldsoul", 13), kid = run("嘴甜人缘好", "owl", 13);
  const ch = (runs) => avg(at(runs, "m_junior"), (p) => p.stats.charm);
  assert.ok(ch(old) < ch(kid) - 0.1, `老灵魂 12 岁魅力 ${ch(old).toFixed(2)}，不比别人（${ch(kid).toFixed(2)}）少`);
  const ck = J(C.checks)[0], me = (flags) => ({ flags, stats: { body: 5, mind: 5, charm: 5, luck: 5 } });
  const chance = (flags) => G("growthCheckChance")(C, ck, me(flags), null, false).p;
  assert.ok(Math.abs(chance(["tal_oldsoul"]) - chance([]) - C.rules.legacy.oldSoul) < 1e-9);

  console.log(`✓ 藏着的天赋：没出过那件事 ${N} 回一回也抽不到 / 出过的事记上就一直在 / 内容摘了跟着摘`);
  console.log(`  大器晚成：12 岁心智 ${m(late, "m_junior").toFixed(1)} 对 ${m(owl, "m_junior").toFixed(1)}，重点班 ${Math.round(opens(at(late, "m_junior"), "key") * 100)}% 对 ${Math.round(opens(at(owl, "m_junior"), "key") * 100)}%，60 岁 ${m(late, "m_retire").toFixed(1)} 对 ${m(owl, "m_retire").toFixed(1)}`);
  console.log(`  连心：各顾各的到 30 岁亲近 ${close(linked).toFixed(1)} 对 ${close(apart).toFixed(1)}，属性差 ${gapL.toFixed(2)}，搭伴念书七十岁能并一家 ${Math.round(pairUp(nearL) * 100)}% 对 ${Math.round(pairUp(nearO) * 100)}% / 老灵魂：12 岁魅力 ${ch(old).toFixed(1)} 对 ${ch(kid).toFixed(1)}，检定 +${C.rules.legacy.oldSoul}`);
}

// ---------- 15. 街坊记住的事：记的是怎么过的，只记一回，不给任何东西 ----------
{
  const list = J(C.remembered);
  assert.ok(list.length >= 10 && list.length <= 19, "街坊记住的事要少：一条人生线上凑不成一张要填满的表");
  const allowed = ["flags", "notFlags", "minClose", "maxClose", "minSync", "maxSync", "minDistance", "maxDistance", "minMemories", "maxMemories", "minRate", "maxRate", "minTogether", "minHelps", "minDiedAge", "maxDiedAge"];
  for (const a of list) {
    assert.ok([...a.title].length <= 7 && [...a.desc].length <= 32, `${a.id} 写长了`);
    assert.ok(Object.keys(a.requires).length > 0 && Object.keys(a.requires).every((k) => allowed.includes(k)), `${a.id} 的条件里有不该看的东西（属性、钱都不看）`);
  }
  const note = (s) => { G("legacyNote")(s, C); return J(s.noted); };

  // 两个人的事：对门住成了一家。记上是第几世，下一世再做到也不记第二回
  const one = give(endedBlank(1), ["p_married"]);
  assert.ok(note(one).includes("r_one_door"));
  assert.equal(one.legacy.remembered.r_one_door, 1);
  const two = give(endedBlank(2, J(one.legacy)), ["p_married"]);
  assert.ok(!note(two).includes("r_one_door"), "记过的不记第二回");
  assert.equal(two.legacy.remembered.r_one_door, 1, "记的还是头一回那一世");
  // each：有一个人做到就算。both：两个人都得做到
  assert.ok(note(give(endedBlank(), ["left_city", "came_back"], ["mei"])).includes("r_homecoming"));
  assert.ok(!note(give(endedBlank(), ["left_city"], ["mei"])).includes("r_homecoming"));
  assert.ok(!note(give(endedBlank(), ["took_over"], ["qing"])).includes("r_two_signs"));
  assert.ok(note(give(endedBlank(), ["took_over"])).includes("r_two_signs"));
  // 搭把手：数的是长卷里两个人一起才办成的检定
  const helped = (n) => { const s = endedBlank(); for (let i = 0; i < n; i++) s.log.push({ kind: "mirror", resonance: true, checks: { qing: { ok: true, help: true } } }); return s; };
  const need = list.find((a) => a.id === "r_helping").requires.minHelps;
  const base = G("legacyHelps")(endedBlank());
  assert.ok(!note(helped(Math.max(0, need - base - 1))).includes("r_helping") || base >= need);
  assert.ok(note(helped(need)).includes("r_helping"));
  // 隔着一世：上一世拉过钩，这一世又拉了一回
  assert.ok(!note(give(endedBlank(), ["p_promise"])).includes("r_again"));
  assert.ok(note(give(endedBlank(2, LG({ lives: 1 })), ["leg_p_promise", "p_promise"])).includes("r_again"));

  // 不给任何东西：街坊记住了多少，投胎出来的孩子一模一样
  const everything = Object.fromEntries(list.map((a) => [a.id, 1]));
  const bare = confirm(G("lifeCreate")(9, C, LG({ lives: 2 })));
  const full = confirm(G("lifeCreate")(9, C, LG({ lives: 2, remembered: everything })));
  assert.deepEqual([J(full.persons), J(full.bond), J(full.rolls)], [J(bare.persons), J(bare.bond), J(bare.rolls)]);
  console.log(`✓ 街坊记住的事：${list.length} 条，条件里不看属性和钱 / 记过的不记第二回 / 一个人、两个人、隔着一世各有各的算法 / 记了多少都不改投胎`);
}

// ---------- 16. v6 存档升 v7；记住的事从内容里删了以后 ----------
{
  const down = (src) => {
    const old = J(src);
    old.version = 6;
    delete old.noted;
    for (const k of ["traces", "marks", "remembered"]) delete old.legacy[k];
    for (const p of old.legacy.past) delete p.noted;
    if (old.persons) for (const r of ROLES) old.persons[r].flags = old.persons[r].flags.filter((f) => !f.startsWith("x_"));
    return old;
  };
  // 抽卡中、过到一半：升上来和现在新开的一模一样
  for (const src of [G("lifeCreate")(6, C), confirm(G("lifeCreate")(6, C))]) {
    const old = down(src);
    assert.deepEqual(J(G("lifeUpgrade")(old)), ["v6→v7", "v7→v8"]);
    assert.deepEqual(J(old), J(src));
    assert.deepEqual(J(G("lifeRepair")(old, C)), []);
  }
  // 只有老物件那会儿走完的一世：补记一回，和当时就记的一样
  const src = J(lifeOne);
  const old = down(src);
  G("lifeUpgrade")(old);
  assert.equal(old.noted, undefined);
  const notes = J(G("lifeRepair")(old, C));
  assert.ok(notes.some((n) => n.includes("街坊记住的事")), "走完的 v6 存档要补记");
  assert.deepEqual(J(old), src, "补记的和当时就记的一样");
  assert.deepEqual(J(G("lifeRepair")(old, C)), [], "只补一回");
  // 已经在第二世抽卡的 v6 存档：上一世的痕迹补不回来（从这一世起记），别的照常
  const second = reborn(J(lifeOne));
  const old2 = down(second);
  G("lifeUpgrade")(old2);
  assert.deepEqual([J(old2.legacy.traces), J(old2.legacy.marks), J(old2.legacy.remembered)], [[], [], {}]);
  assert.deepEqual(J(G("lifeRepair")(old2, C)), []);
  liveOut(old2);
  assert.ok(Array.isArray(old2.noted) && old2.legacy.lives === 2);

  // 记住的事从内容里删了：记着的、这一世新记的、小传里的都摘掉，别的不动
  const s = J(lifeOne);
  s.legacy.remembered = { r_one_door: 1, r_gone: 1 };
  s.noted = ["r_gone", "r_one_door"];
  s.legacy.past[0].noted = ["r_gone", "r_one_door"];
  const fixed = J(G("lifeRepair")(s, C));
  assert.ok(fixed.some((n) => n.includes("r_gone")));
  assert.deepEqual([J(s.legacy.remembered), J(s.noted), J(s.legacy.past[0].noted)], [{ r_one_door: 1 }, ["r_one_door"], ["r_one_door"]]);
  console.log("✓ v6 存档：抽卡中 / 过到一半升上来和新开的一样 / 走完的补记一回 / 第二世的从这一世起记；记住的事被删了就摘掉");
}

// ---------- 17. 住户本读归档：只给这条人生线上的两个人，只给挑过的那几样 ----------
{
  const pa = { userId: "user-a", sessionId: "sa" };
  const pb = { userId: "user-b", sessionId: "sb" };
  const NEW = { protocol: String(G("PROTOCOL_VERSION")) };
  const env = fakeNakama();
  const a = env.rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  env.rpc("rpcLifelineJoin", "user-b", { code: a.code, name: "小梅" });
  const id = a.lifelineId;
  const R = room(env.nk, env.rpc("rpcLifelineOpen", "user-a", { lifelineId: id }).matchId);
  for (const p of [pa, pb]) { assert.equal(R.attempt(p, NEW).accept, true); R.join([p]); }
  const past = (user, life) => env.rpc("rpcLifelinePast", user, { lifelineId: id, life });

  R.loop([R.msg(pa, OP.ROLL, { confirm: true }), R.msg(pb, OP.ROLL, { confirm: true })]);
  assert.throws(() => past("user-a", 1), /还没走完/);
  liveOut(R.life());
  // 这里是直接推规则把一世过完的，房间没经手，所以借一张票让它存一回档（点了再收回）
  R.loop([R.msg(pa, OP.AGAIN, {})]);
  R.loop([R.msg(pa, OP.AGAIN, { yes: false })]);
  const life = J(R.life());

  // 走完还没换世：从存档里读
  const v = past("user-b", 1);
  assert.equal(v.lifelineId, id);
  assert.deepEqual(v.names, { qing: "小青", mei: "小梅" });
  assert.deepEqual(Object.keys(v.past).sort(), ["close", "ending", "left", "life", "memories", "noted", "persons", "stats"]);
  assert.deepEqual(v.past.ending, { pair: life.ending.pair, lives: life.ending.lives });
  assert.deepEqual([v.past.life, v.past.left, v.past.noted, v.past.close], [1, life.left, life.noted, Math.round(life.bond.close)]);
  for (const r of ROLES) {
    const p = life.persons[r];
    assert.deepEqual(v.past.persons[r], { name: p.name, familyId: p.familyId, talentId: p.talentId, diedAtAge: p.diedAtAge, job: G("legacyJob")(p), heirloomId: p.heirloomId });
  }
  assert.ok(v.past.memories.length > 0 && v.past.memories.length <= 40);
  assert.deepEqual(Object.keys(v.past.memories[0]).sort(), ["age", "title", "vivid"]);
  assert.ok(v.past.memories.every((m, i, all) => i === 0 || all[i - 1].age <= m.age), "回忆按先后排");
  assert.deepEqual(v.past.stats, { mirrors: G("lifeStats")(life).mirrors, rate: G("lifeStats")(life).rate, together: G("lifeStats")(life).together });
  const text = JSON.stringify(v);
  for (const k of ["rng", "seed", "flags", "log", "world", "legacy", "members", "code", "user-a", "user-b"]) assert.ok(!text.includes(`"${k}"`), `住户本里不该有 ${k}`);
  assert.ok(text.length < 4000, `一世那一页 ${text.length} 字节，太大了`);

  // 不是这条人生线上的人、没有的世数、乱填的
  assert.throws(() => past("user-c", 1), /不是你的人生线/);
  assert.throws(() => env.rpc("rpcLifelinePast", "user-a", { lifelineId: "nope", life: 1 }), /人生线不存在/);
  for (const bad of [0, -1, 2, 99, "x", null, 1.5 - 2]) assert.throws(() => past("user-a", bad), /没有这一世/);

  // 换世以后：从归档里读，读出来的是同一页；新的这一世还没走完
  R.loop([R.msg(pa, OP.AGAIN, {}), R.msg(pb, OP.AGAIN, {})]);
  assert.equal(env.record(id).life.life, 2);
  assert.deepEqual(past("user-a", 1), v);
  assert.throws(() => past("user-a", 2), /还没走完/);
  // 归档坏了（读出来不是一世）：和没有这一世一样回话，不把运行时的报错原样给出去
  const slot = env.nk.store.get([...env.nk.store.keys()].find((key) => key.startsWith("lifeline_past/") && key.endsWith(`/${id}.1`)));
  const good = slot.value;
  for (const broken of [{}, { past: null }, { past: "x" }, null]) {
    slot.value = broken;
    assert.throws(() => past("user-a", 1), /^Error: 没有这一世$/);
  }
  slot.value = good;
  assert.deepEqual(past("user-a", 1), v);
  // 归档是旧版本存的、缺东西：照样给得出一页，不抛错
  const empty = J(G("legacyPastView")({}));
  assert.deepEqual(empty, { life: 1, ending: { pair: null, lives: { qing: null, mei: null } }, close: 0, persons: { qing: null, mei: null }, memories: [], left: { qing: null, mei: null }, noted: [], stats: { mirrors: 0, rate: 0, together: 0 } });
  console.log(`✓ 住户本：走完的从存档读、换世以后从归档读，是同一页（${text.length} 字节）/ 只有八样东西，没有随机数、标记、长卷 / 外人、没有的世数、没走完的、归档坏了的都读不到`);
}
