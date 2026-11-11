// 成家和下一代（docs/FAMILY.md，server/src/family.ts）：生孩子、两口子共用一个、两家孩子同岁、带孩子长孩子不长自己、
// 搭伴的倍率长在各自的孩子身上、孩子的关口落在没有自己关口的那天、存档升级、WORLD 里的 kid、事件的 kidAge。
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const SLOTS = G("SLOTS");
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age >= age) return t; return -1; };
const spot = (id) => C.map.spots.find((sp) => sp.id === id);
const ev = (id) => C.events.find((e) => e.id === id);
function at(s, r, id) { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; }
const view = (s) => G("worldView")({ record: { life: s }, moveSeq: {}, tick: 0 });
const kidOf = (s, r) => G("kidOf")(s, r);

/** 两个大人，到了 age 岁那天，傍晚那一段刚开头。属性、需求拉齐 */
function grown(age, seed = 7) {
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
    p.stats = { body: 6, mind: 6, charm: 6, luck: 5 };
    p.born = { body: 5, mind: 5, charm: 5, luck: 5 };
    p.needs = { hunger: 80, energy: 80, mood: 80, clean: 80 };
    p.flags = p.flags.filter((f) => !f.startsWith("tal_"));
    p.money = 50;
  }
  return s;
}
/** 给这个人一个 kidAge 岁的孩子（属性拉齐） */
function giveKid(s, r, kidAge, stats = { body: 3, mind: 3, charm: 3, luck: 5 }) {
  G("lifeAddFlags")(s.persons[r], ["has_kid"]);
  G("kidSync")(s, C);
  const k = kidOf(s, r);
  k.bornAge = G("lifeTimeAt")(s.turn).age - kidAge;
  k.stats = { ...stats };
  return k;
}
function pass(s) {
  const from = s.world.slot, turn = s.turn;
  for (let i = 0; i < 4000 && s.world.slot === from && s.turn === turn; i++) G("worldAdvance")(s, C, 0.5, ON);
}

// ---------- 1. 拿到 has_kid 就生一个 ----------
{
  const s = grown(28);
  assert.deepEqual(J(s.kids), [], "新开的一世 kids 是空的");
  const rng0 = s.rng;
  G("kidSync")(s, C);
  assert.equal(s.rng, rng0, "没人有 has_kid：不动随机数");
  G("lifeAddFlags")(s.persons.qing, ["has_kid"]);
  G("kidSync")(s, C);
  const k = kidOf(s, "qing");
  assert.ok(k, "生了一个");
  assert.deepEqual(J(k.of), ["qing"]);
  assert.equal(k.bornAge, 28);
  assert.ok(C.rules.family.names.includes(k.name), "名字从 rules.family.names 里挑");
  for (const key of ["body", "mind", "charm"]) {
    const base = C.rules.family.start[key] + 6 * C.rules.family.inherit;
    assert.ok(Math.abs(k.stats[key] - base) <= C.rules.family.noise / 2 + 1e-9, `出生属性 = 底 + 爹妈平均 × inherit ± 一点（${key} ${k.stats[key]}）`);
  }
  assert.equal(kidOf(s, "mei"), null, "不是两口子：对门没有");
  assert.ok(!s.persons.mei.flags.includes("has_kid"));
  G("kidSync")(s, C);
  assert.equal(s.kids.length, 1, "再 sync 不会再生一个");
  console.log(`✓ 拿到 has_kid 生一个：${k.name}，${k.bornAge} 岁生的，体魄 ${k.stats.body} 心智 ${k.stats.mind} 魅力 ${k.stats.charm}`);
}

// ---------- 2. 两口子共用一个孩子 ----------
{
  const s = grown(29);
  for (const r of ROLES) G("lifeAddFlags")(s.persons[r], ["p_married"]);
  G("lifeAddFlags")(s.persons.mei, ["has_kid"]);
  G("kidSync")(s, C);
  assert.equal(s.kids.length, 1);
  assert.deepEqual(J(s.kids[0].of).sort(), ["mei", "qing"]);
  assert.ok(s.persons.qing.flags.includes("has_kid"), "对门也拿 has_kid");
  assert.equal(kidOf(s, "qing"), kidOf(s, "mei"));
  assert.ok(!s.persons.qing.flags.includes("kids_same_age"), "同一个孩子不算两家孩子同岁");
  const v = view(s);
  assert.equal(v.actors.qing.kid.shared, true);
  assert.equal(v.actors.qing.kid.name, s.kids[0].name);
  console.log("✓ 两口子：一个孩子，两个人都拿 has_kid，WORLD 里 shared");
}

// ---------- 3. 两家孩子同岁 ----------
{
  const s = grown(28);
  G("lifeAddFlags")(s.persons.qing, ["has_kid"]);
  G("kidSync")(s, C);
  s.turn = turnAtAge(29);
  G("lifeAddFlags")(s.persons.mei, ["has_kid"]);
  G("kidSync")(s, C);
  assert.equal(s.kids.length, 2);
  assert.notEqual(s.kids[0].name, s.kids[1].name, "两家孩子不同名");
  for (const r of ROLES) assert.ok(s.persons[r].flags.includes("kids_same_age"), "差一岁：两个大人都打 kids_same_age");
  const s2 = grown(28);
  G("lifeAddFlags")(s2.persons.qing, ["has_kid"]);
  G("kidSync")(s2, C);
  s2.turn = turnAtAge(33);
  G("lifeAddFlags")(s2.persons.mei, ["has_kid"]);
  G("kidSync")(s2, C);
  assert.ok(!s2.persons.qing.flags.includes("kids_same_age"), "差五岁不算");
  console.log("✓ 两家孩子差不到两岁：kids_same_age；差五岁不打");
}

// ---------- 4. 带孩子长孩子不长自己（一回回、整段两条路） ----------
{
  const s = grown(36);
  const k = giveKid(s, "qing", 8);
  at(s, "qing", "kid_desk_qing");
  const me0 = J(s.persons.qing.stats), e0 = s.persons.qing.needs.energy, km0 = k.stats.mind;
  const r = G("worldAct")(s, C, "qing", "kid_desk_qing", true);
  assert.equal(r.error, null);
  assert.ok(k.stats.mind > km0, "孩子的心智长了");
  assert.deepEqual(J(s.persons.qing.stats), me0, "自己的属性一点没动");
  assert.ok(s.persons.qing.needs.energy < e0, "自己照样累");
  const did = s.world.actors.qing.did;
  assert.ok(did.k && did.k.mind > 0, "did.k 写着孩子长了多少");
  assert.deepEqual(J(did.s), {}, "did.s 是空的");
  // 整段
  const s2 = grown(36);
  const k2 = giveKid(s2, "qing", 8);
  at(s2, "qing", "kid_desk_qing");
  assert.equal(G("worldAct")(s2, C, "qing", "kid_desk_qing").error, null);
  G("worldPass")(s2, C, "mei");
  const before = J(s2.persons.qing.stats), m2 = k2.stats.mind;
  pass(s2);
  assert.ok(k2.stats.mind > m2, "做到点：段末孩子长了");
  for (const key of ["body", "mind", "charm"]) assert.ok(s2.persons.qing.stats[key] <= before[key] + 1e-9, "做到点：自己不长");
  // 没孩子 / 孩子太小
  const s3 = grown(36);
  at(s3, "qing", "kid_desk_qing");
  assert.equal(G("worldAct")(s3, C, "qing", "kid_desk_qing", true).error, "家里没有孩子");
  giveKid(s3, "qing", 3);
  assert.equal(G("worldAct")(s3, C, "qing", "kid_desk_qing", true).error, "孩子还太小");
  console.log(`✓ 带孩子：一回 心智 +${did.k.mind}，自己不长；做到点段末 +${Math.round((k2.stats.mind - m2) * 1000) / 1000}；没孩子、孩子太小做不了`);
}

// ---------- 5. 搭伴：两家各带各的，都按倍率长；两口子带同一个，两份都长在这一个身上 ----------
{
  const solo = grown(36);
  const ks = giveKid(solo, "qing", 8);
  at(solo, "qing", "kid_desk_qing");
  G("worldAct")(solo, C, "qing", "kid_desk_qing");
  G("worldPass")(solo, C, "mei");
  const s0 = ks.stats.mind;
  pass(solo);
  const soloGain = ks.stats.mind - s0;

  const pair = grown(36);
  const kq = giveKid(pair, "qing", 8), km = giveKid(pair, "mei", 8);
  for (const r of ROLES) { at(pair, r, "kid_desk_qing"); assert.equal(G("worldAct")(pair, C, r, "kid_desk_qing").error, null); }
  assert.ok(pair.world.actors.qing.together && pair.world.actors.mei.together, "同点同事：搭伴");
  const q0 = kq.stats.mind, m0 = km.stats.mind;
  pass(pair);
  const gq = kq.stats.mind - q0, gm = km.stats.mind - m0;
  assert.ok(gq > soloGain * 1.3 && gm > soloGain * 1.3, `两家的孩子都按搭伴倍率长（一个人带 ${soloGain.toFixed(3)}，搭伴 ${gq.toFixed(3)} / ${gm.toFixed(3)}）`);

  // 一回回：后到的给先到的补上孩子那份
  const late = grown(36);
  const lq = giveKid(late, "qing", 8), lm = giveKid(late, "mei", 8);
  for (const r of ROLES) at(late, r, "kid_desk_qing");
  G("worldAct")(late, C, "qing", "kid_desk_qing", true);
  const afterFirst = lq.stats.mind;
  G("worldAct")(late, C, "mei", "kid_desk_qing", true);
  assert.ok(lq.stats.mind > afterFirst, "对门后来赶上：先做的那家孩子补上搭伴那一份");
  assert.ok(late.world.actors.mei.did.tg && late.world.actors.mei.did.k.mind > 0);

  const cp = grown(36);
  for (const r of ROLES) G("lifeAddFlags")(cp.persons[r], ["p_married"]);
  const kc = giveKid(cp, "qing", 8);
  assert.equal(kidOf(cp, "mei"), kc);
  for (const r of ROLES) { at(cp, r, "kid_desk_qing"); G("worldAct")(cp, C, r, "kid_desk_qing"); }
  const c0 = kc.stats.mind;
  pass(cp);
  const gc = kc.stats.mind - c0;
  assert.ok(gc > gq * 1.6, `两口子带同一个孩子，两份都长在这一个身上（${gc.toFixed(3)}）`);
  console.log(`✓ 搭伴：一个人带 +${soloGain.toFixed(3)}，两家各带各的各 +${gq.toFixed(3)}，两口子一起带一个 +${gc.toFixed(3)}；一回回的后到补上`);
}

// ---------- 6. 不押也自己长 ----------
{
  const s = grown(33);
  const k = giveKid(s, "qing", 5);
  const b0 = J(k.stats);
  G("kidDayEnd")(s, C);
  for (const key of ["body", "mind", "charm"]) assert.ok(k.stats[key] > b0[key], `一个日子过完孩子自己长（${key}）`);
  console.log("✓ 不押孩子也自己长一点");
}

// ---------- 7. 孩子的关口：孩子快到岁数（提前两岁以内），落在没有自己关口的那天 ----------
{
  const gates = C.events.filter((e) => e.kind === "milestone" && e.kidAge !== undefined);
  assert.deepEqual(J(gates.map((e) => [e.id, e.kidAge])), [["mk_school", 6], ["mk_junior", 12], ["mk_senior", 15], ["mk_gaokao", 18]]);
  for (const g of gates) assert.ok(g.options.some((o) => !o.min && !o.cost && !o.requires), `${g.id} 有兜底`);
  // 没孩子：不发生
  const none = grown(39);
  G("worldStartDay")(none, C);
  assert.ok(!none.world.fate.milestone, "没孩子：孩子的关口不发生");
  // 孩子 6 岁以后、自己今天没有关口：今天早上发生
  const s = G("lifeCreate")(11, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  s.turn = turnAtAge(28);
  G("lifeAddFlags")(s.persons.qing, ["has_kid"]);
  G("kidSync")(s, C);
  const seenAt = {};
  for (let i = 0; i < 12 && s.phase === "life"; i++) {
    const age = G("lifeTimeAt")(s.turn).age;
    if (age > 52) break;
    s.persons.qing.alive = true; s.persons.mei.alive = true;
    G("worldStartDay")(s, C);
    const id = s.world.fate.milestone;
    const own = G("lifeMilestoneAt")(C, age);
    if (own) assert.equal(id, own.id, `${age} 岁有自己的关口：先过自己的`);
    if (id && ev(id).kidAge !== undefined) {
      seenAt[id] = age;
      assert.ok(age - kidOf(s, "qing").bornAge >= ev(id).kidAge - 2, "孩子快到岁数了（提前两岁以内）");
      const tk = { entries: [], started: null, dayEnded: false };
      G("worldMilestone")(s, C, tk);
      assert.deepEqual(J((s.world.event || { roles: tk.entries[0] && Object.keys(tk.entries[0].events).filter((r) => tk.entries[0].events[r]) }).roles), ["qing"], "只有有孩子的那个人过");
      if (s.world.event) G("worldChoose")(s, C, "qing", G("lifeMilestoneFallback")(ev(id)).id, false);
    }
    s.turn += 1;
  }
  assert.ok(seenAt.mk_school && seenAt.mk_junior && seenAt.mk_senior && seenAt.mk_gaokao, `四道都过了：${JSON.stringify(seenAt)}`);
  const ages = Object.values(seenAt);
  assert.equal(new Set(ages).size, ages.length, "一天只过一道");
  for (const a of ages) assert.ok(!G("lifeMilestoneAt")(C, a), "都落在没有自己关口的日子");
  assert.ok(s.persons.qing.flags.some((f) => f.startsWith("kid_")), "标记落在爹妈身上");
  console.log(`✓ 孩子的关口落在：${Object.entries(seenAt).map(([k, v]) => `${k} 爹妈 ${v} 岁`).join("，")}`);
}

// ---------- 8. 孩子的关口按孩子的属性算分；两口子一起过，共鸣发 p_kid_uni ----------
{
  const s = grown(48);
  for (const r of ROLES) G("lifeAddFlags")(s.persons[r], ["p_married"]);
  const k = giveKid(s, "qing", 20, { body: 9, mind: 9.5, charm: 9, luck: 5 });
  for (const r of ROLES) for (const id of ["mk_school", "mk_junior", "mk_senior"]) s.log.push({ ...G("lifeEntry")(s, "milestone", ""), events: { qing: r === "qing" ? id : null, mei: r === "mei" ? id : null } });
  G("worldStartDay")(s, C);
  assert.equal(s.world.fate.milestone, "mk_gaokao");
  for (const r of ROLES) { s.persons[r].stats.mind = 0; s.persons[r].stats.luck = 5; }
  const tk = { entries: [], started: null, dayEnded: false };
  G("worldMilestone")(s, C, tk);
  assert.deepEqual(J(s.world.event.roles), ["qing", "mei"], "两口子一起过");
  const locks = G("lifeMilestoneLocks")(s, C);
  assert.ok(!locks.qing.top, "爹妈自己心智是 0，孩子 9.5：高线开着（读的是孩子）");
  for (const r of ROLES) G("worldChoose")(s, C, r, "top", false);
  const e = s.log[s.log.length - 1];
  assert.equal(e.resonance, true);
  assert.ok(e.results.qing.score >= 90, "显示百分制");
  for (const r of ROLES) assert.ok(s.persons[r].flags.includes("p_kid_uni") && s.persons[r].flags.includes("kid_uni_top"));
  assert.ok(k.stats.mind === 9.5);
  console.log(`✓ 孩子高考：按孩子的心智算（${e.results.qing.score} 分），两口子同路发 p_kid_uni`);
}

// ---------- 9. 纸带：孩子的下一道关和自己的下一道关并排 ----------
{
  const s = grown(39);
  giveKid(s, "qing", 11);
  const g = G("lifeGoal")(s, C, "qing");
  assert.ok(g, "有目标");
  const ids = [g.id, g.also && g.also.id];
  assert.ok(ids.includes("mk_school") && ids.includes("m_midlife"), `孩子的、自己的都在（${ids}）：六岁那道还没过，先摆它`);
  assert.equal(g.id, "mk_school", "近的那道在前头");
  assert.equal(g.kid, true);
  assert.ok(g.lines.some((l) => l.by.includes("孩子")), "线上写着看的是孩子的心智");
  assert.ok(g.turns <= g.also.turns);
  const need = G("worldShadowNeed")(s, C, "qing");
  assert.equal(need, "kid_mind", "影子：孩子的关口最近时去做带孩子的事");
  console.log(`✓ 纸带：${g.title}（${g.turns} 个日子后）在前，${g.also.title} 挂在 also；影子盯 ${need}`);
}

// ---------- 10. 事件 requires.kidAge ----------
{
  const t = G("lifeTimeAt")(turnAtAge(36));
  const fake = { id: "x", kind: "solo", stage: t.stage, seasons: [], weight: 1, requires: { kidAge: [3, 6] }, options: [] };
  const elig = (ctx) => G("lifeEligible")(fake, t, [], {}, ctx);
  assert.equal(elig({ bond: { close: 0, sync: 0, distance: 0 }, alone: false, kidAge: 4 }), true);
  assert.equal(elig({ bond: { close: 0, sync: 0, distance: 0 }, alone: false, kidAge: 8 }), false);
  assert.equal(elig({ bond: { close: 0, sync: 0, distance: 0 }, alone: false }), false, "没孩子不发生");
  assert.equal(elig(undefined), false);
  assert.equal(elig({ bond: { close: 0, sync: 0, distance: 0 }, alone: false, kidAges: [9, 5] }), true, "mirror：两家里一个孩子在段里就行");
  console.log("✓ 事件 kidAge：孩子在段里才发生，没孩子不发生");
}

// ---------- 11. 存档：v8 升到 v9 补 kids，往返不丢孩子 ----------
{
  const s = grown(36);
  giveKid(s, "qing", 8);
  const old = J(s);
  delete old.kids;
  old.version = 8;
  const notes = G("lifeUpgrade")(old);
  assert.ok(notes.includes("v8→v9"));
  assert.equal(old.version, G("LIFE_VERSION"));
  assert.deepEqual(J(old.kids), []);
  const back = J(s);
  G("lifeUpgrade")(back);
  assert.deepEqual(back.kids, J(s.kids), "往返不丢孩子");
  assert.ok(!("_kid" in JSON.parse(JSON.stringify(s.persons.qing))), "算分时挂上的孩子属性不进存档");
  // 旧存档里已经有 has_kid 的人：下一个日子补上一个
  G("lifeAddFlags")(old.persons.mei, ["has_kid"]);
  G("kidSync")(old, C);
  assert.ok(kidOf(old, "mei"));
  const v = view(s);
  assert.equal(v.actors.mei.kid, undefined, "没孩子不发 kid");
  assert.deepEqual(Object.keys(v.actors.qing.kid).sort(), ["age", "name", "shared", "stats"]);
  assert.equal(v.actors.qing.kid.age, 8);
  console.log("✓ 存档 v8→v9 补 kids，往返不丢；WORLD 里 kid { name, age, stats, shared }，没孩子不发");
}

// ---------- 12. 先有孩子、后成两口子：对门算进这个孩子，不补过前面的关 ----------
{
  const s = grown(33);
  const k = giveKid(s, "qing", 6);
  s.log.push({ ...G("lifeEntry")(s, "milestone", ""), events: { qing: "mk_school", mei: null } });
  for (const r of ROLES) G("lifeAddFlags")(s.persons[r], ["p_married"]);
  G("kidSync")(s, C);
  assert.equal(kidOf(s, "mei"), k, "后成的两口子：对门也是这个孩子的爹妈");
  assert.ok(s.persons.mei.flags.includes("has_kid"));
  assert.equal(G("kidGateSeen")(s, "mei", "mk_school"), true, "上学那道对门已经过了，半路算进来的不补过");
  console.log("✓ 先有孩子后成家：两口子共用这一个孩子，前面过了的关不再补");
}

// ---------- 13. 家里的默契事不被主线挤掉：主线今天不是非过不可的，先让两家孩子的事 ----------
{
  let hit = 0, tried = 0;
  for (let seed = 1; seed <= 40 && hit === 0; seed++) {
    // 三十三岁：直接跳到这天的存档主线还没落下太多，不是章末强制的那种（强制的那天主线照样先过）
    const s = grown(33, seed);
    for (const r of ROLES) giveKid(s, r, 8);
    G("kidSync")(s, C);
    s.persons.qing.flags = s.persons.qing.flags.filter((f) => f !== "p_married");
    s.persons.mei.flags = s.persons.mei.flags.filter((f) => f !== "p_married");
    G("worldStartDay")(s, C);
    tried++;
    const m = s.world.fate.mirror;
    if (m && ev(m) && G("worldFamilyMirror")(ev(m))) hit++;
  }
  assert.ok(hit > 0, `中年两家各有孩子：${tried} 天里至少有一天命运那一格是家里的事`);
  console.log(`✓ 中年家里的默契事出得来：主线今天不是非过不可的，两家孩子的事先过（试到第 ${tried} 天碰上）`);
}
