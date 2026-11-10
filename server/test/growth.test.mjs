// 成长规则的测试（server/src/growth.ts + content/rules.yaml，设计说明见 docs/GROWTH.md）。
// 这里只测「规则的形状」：谁该比谁多、什么不该发生。具体的数在 rules.yaml 里随便调，
// 调完用 `npm run balance` 看分布；这里的断言不应该因为调数而挂。
import assert from "node:assert/strict";
import { G, C, J } from "./harness.mjs";

const R = C.rules;
const NAMES = { qing: "青", mei: "梅" };
const lifeTimeAt = G("lifeTimeAt"), growthApply = G("growthApply"), growthCtx = G("growthCtx");
const growthLimit = G("growthLimit"), growthCheckChance = G("growthCheckChance");

function newLife(seed = 7) {
  const s = G("lifeCreate")(seed, C);
  G("lifeConfirm")(s, C, "qing", NAMES);
  G("lifeConfirm")(s, C, "mei", NAMES);
  return s;
}
/** 第一个到了这个岁数的日子 */
function turnAtAge(age) {
  for (let t = 0; t < 400; t++) if (lifeTimeAt(t).age >= age) return t;
  throw new Error("没有这个岁数");
}
const sum = (st) => st.body + st.mind + st.charm + st.luck;

// ---------- 1. 投胎：人人一样多，只是长的地方不一样 ----------
{
  const totals = new Map();
  for (let i = 0; i < 3000; i++) {
    const r = G("lifeRollOnce")({ rng: i * 7919 + 1 }, C, null);
    const fam = C.families.find((f) => f.id === r.familyId);
    const tal = C.talents.find((t) => t.id === r.talentId);
    for (const v of Object.values(r.stats)) assert.ok(v >= 0 && v <= 10 && Number.isInteger(v), "先天属性是 0~10 的整数");
    // 天赋带负加成的（犟脾气 魅力 −1）不会被夹掉，所以合计严格等于预算
    assert.equal(sum(r.stats), R.roll.budget + R.roll.wealthAdjust[fam.wealth], `${fam.name}+${tal.name} 的合计不对`);
    totals.set(fam.wealth, sum(r.stats));
  }
  assert.ok(totals.get(0) > totals.get(2), "清贫人家的孩子先天多一点（钱和饭桌上少的，这里补上）");
  const s = newLife();
  for (const r of ["qing", "mei"]) {
    assert.deepEqual(J(s.persons[r].born), J(s.persons[r].stats), "出生时的属性记作底子");
    assert.ok(s.persons[r].lifespan >= R.lifespan.base - R.lifespan.spread && s.persons[r].lifespan <= R.lifespan.base + R.lifespan.spread);
  }
  console.log(`✓ 投胎：四项合计人人是 ${R.roll.budget}（清贫 +${R.roll.wealthAdjust[0]}、殷实 ${R.roll.wealthAdjust[2]}）/ 出生属性记作底子 / 命数在 ${R.lifespan.base}±${R.lifespan.spread}`);
}

// ---------- 2. 成长：经历 × 年纪 × 底子 ----------
{
  const person = (stats, flags = []) => ({ stats: { ...stats }, born: { ...stats }, flags, active: { body: false, mind: false } });
  const base = { body: 4, mind: 4, charm: 4, luck: 4 };
  const at = (stage, source = "event") => ({ c: C, stage, scale: source === "event" ? R.growth.eventScale : R.growth.actionScale });

  // 底子：同样的经历，长过的人长得慢，而且永远长不过 10
  const fresh = person(base);
  const first = growthApply(fresh, "mind", 1, at("childhood"));
  const grown = person(base); grown.stats.mind = base.mind + R.growth.room * 0.8;
  const late = growthApply(grown, "mind", 1, at("childhood"));
  assert.ok(first > 0 && late > 0 && late < first * 0.5, `离底子越远长得越慢：${first} → ${late}`);
  const maxed = person(base); maxed.stats.mind = base.mind + R.growth.room + 0.5;
  assert.ok(Math.abs(growthApply(maxed, "mind", 1, at("childhood")) - R.growth.eventScale * R.growth.floor) < 1e-3, "超出 room 以后只剩 floor");
  const top = person({ ...base, mind: 10 });
  growthApply(top, "mind", 5, at("teen"));
  assert.equal(top.stats.mind, 10);

  // 年纪：少年长身体最快，老了最慢
  const gain = (stage, k) => growthApply(person(base), k, 1, at(stage));
  assert.ok(gain("teen", "body") > gain("young", "body") && gain("young", "body") > gain("middle", "body") && gain("middle", "body") > gain("old", "body"));
  assert.ok(gain("old", "mind") > gain("old", "body"), "老了脑子比身子耐用");

  // 事件和日常不是一个量级；掉属性不打折
  assert.ok(growthApply(person(base), "body", 1, at("childhood", "action")) < gain("childhood", "body"));
  const hurt = person(base); hurt.stats.body = 9;
  assert.ok(Math.abs(growthApply(hurt, "body", -1, at("old")) + R.growth.eventScale) < 1e-9, "往下掉不看年纪和底子");

  // 普通的孩子什么都长得快一点
  const plain = growthApply(person(base, ["tal_plain"]), "charm", 1, at("teen"));
  assert.ok(Math.abs(plain / gain("teen", "charm") - R.growth.plainBonus) < 0.02);

  // 长了体魄 / 心智的那天算「动过」
  const moved = person(base);
  growthApply(moved, "body", 1, at("teen"));
  assert.deepEqual(moved.active, { body: true, mind: false });

  // 接进规则里：行动走 actionScale，事件走 eventScale
  const s = newLife();
  const p = s.persons.qing;
  const before = p.stats.mind;
  s.world.actors.qing.action = "study";
  G("worldFinish")(s, C, "qing");
  const study = C.map.actions.find((a) => a.id === "study").stats.mind * (p.flags.includes("tal_memory") ? 2 : 1);
  assert.ok(p.stats.mind > before && p.stats.mind - before <= study * R.growth.actionScale * 1.3 * R.growth.plainBonus + 1e-9, "写一次作业只长一点点");
  assert.equal(growthCtx(s, C, "event").scale, R.growth.eventScale);
  console.log("✓ 成长：离底子越远越慢 / 少年长得最快、老了最慢 / 事件比日常长得多 / 掉属性不打折 / 普通的孩子长得匀 / 到不了 10 以上");
}

// ---------- 3. 岁数不饶人 ----------
{
  const run = (active) => {
    const s = newLife(11);
    s.turn = turnAtAge(76);
    for (const r of ["qing", "mei"]) { s.persons[r].stats.body = 7; s.persons[r].stats.mind = 7; s.persons[r].active = { body: active, mind: active }; }
    s.world.warm = true;
    G("growthDayEnd")(s, C);
    return s.persons.qing;
  };
  const idle = run(false), busy = run(true);
  assert.ok(idle.stats.body < 7 && idle.stats.mind < 7, "七十六岁，一年不如一年");
  assert.ok(busy.stats.body > idle.stats.body && busy.stats.mind > idle.stats.mind, "天天活动的掉得慢");
  assert.ok(Math.abs((7 - busy.stats.body) / (7 - idle.stats.body) - R.aging.activeFactor) < 0.05);
  assert.deepEqual(J(idle.active), { body: false, mind: false }, "每天重新算");
  const young = newLife(11);
  young.turn = turnAtAge(25);
  young.persons.qing.stats.body = 7;
  G("growthDayEnd")(young, C);
  assert.equal(young.persons.qing.stats.body, 7, "年轻时不掉");
  console.log(`✓ 衰老：体魄从 ${R.aging.body[0][0]} 岁、心智从 ${R.aging.mind[0][0]} 岁往下走 / 当天动过的只掉 ${R.aging.activeFactor * 100}% / 年轻时不掉`);
}

// ---------- 4. 检定 ----------
{
  assert.ok(C.checks.length > 0);
  const ck = { stat: "body", dc: 5 };
  const me = (body, luck = 5) => ({ stats: { body, mind: 5, charm: 5, luck } });
  const p = (...a) => growthCheckChance(C, ck, ...a).p;
  assert.ok(Math.abs(p(me(5), null, false) - R.check.base) < 1e-9, "属性刚好够难度，就是 base");
  assert.ok(p(me(7), null, false) > p(me(5), null, false) && p(me(5), null, false) > p(me(3), null, false));
  assert.ok(p(me(5, 9), null, false) > p(me(5, 1), null, false), "运气帮一点忙");
  assert.equal(p(me(0, 0), null, false), R.check.min);
  assert.equal(p(me(10, 10), null, false), R.check.max);
  // 搭把手：两个人选了同一项，按本事大的算，再多一点把握；各选各的就只能靠自己
  const weak = me(2), strong = me(8);
  const alone = growthCheckChance(C, ck, weak, strong, false), helped = growthCheckChance(C, ck, weak, strong, true);
  assert.ok(!alone.help && helped.help);
  assert.equal(alone.p, p(weak, null, false));
  assert.ok(helped.p > p(strong, null, false) - 1e-9 && helped.p > alone.p + 0.3, "弱的那个被带起来了");

  // 接进事件：成了拿原来的效果；没成就不长属性，标记按检定表里写的来
  const byId = new Map(C.events.map((e) => [e.id, e]));
  let pass = 0, fail = 0;
  for (const c of C.checks) {
    const ev = byId.get(c.event);
    const o = ev.options.find((x) => x.id === c.option);
    for (let seed = 1; seed <= 40; seed++) {
      const s = newLife(seed * 31);
      const before = J(s.persons.qing.stats);
      const flagsBefore = new Set(s.persons.qing.flags);
      const pe = ev.kind === "mirror"
        ? { eventId: ev.id, kind: "mirror", roles: ["qing", "mei"], choices: { qing: o.id, mei: o.id }, shadow: [] }
        : { eventId: ev.id, kind: "solo", roles: ["qing"], choices: { qing: o.id }, shadow: [] };
      const entry = G("lifeResolveEvent")(s, C, pe);
      const res = entry.checks.qing;
      assert.equal(res.stat, c.stat);
      assert.equal(res.text, res.ok ? c.pass : c.fail.text);
      if (ev.kind === "solo") assert.equal(entry.text, res.text, "各自的事：日志里写的就是检定的结果");
      if (ev.kind === "mirror") assert.equal(res.help, res.ok, "默契事件里两人选了同一项，成了就是搭把手");
      const got = s.persons.qing.flags.filter((f) => !flagsBefore.has(f));
      if (res.ok) {
        pass++;
        for (const f of o.effects.flags) assert.ok(s.persons.qing.flags.includes(f));
      } else {
        fail++;
        // 自己这一项没成就不长属性（默契事件的共鸣、对方给的另算，所以只查各自的事）
        if (ev.kind === "solo" && !c.fail.self) for (const k of ["body", "mind", "charm", "luck"]) assert.ok(s.persons.qing.stats[k] <= before[k] + 1e-9, `${c.event}.${c.option} 没成却长了 ${k}`);
        if (c.fail.flags) for (const f of got) assert.ok(c.fail.flags.includes(f) || ev.kind === "mirror", `${c.event}.${c.option} 没成却得到了 ${f}`);
      }
    }
  }
  assert.ok(pass > 0 && fail > 0);
  console.log(`✓ 检定：${C.checks.length} 处 / 成功率跟着属性和运气走，夹在 ${R.check.min}~${R.check.max} / 搭把手按本事大的算 / 没成不长属性、标记按检定表（成 ${pass} 次、没成 ${fail} 次）`);
}

// ---------- 5. 寿命 ----------
{
  const s = newLife(5);
  const set = (role, o) => Object.assign(s.persons[role], o);
  for (const r of ["qing", "mei"]) set(r, { lifespan: 76, moodSum: R.lifespan.moodMid * 10, moodDays: 10 });
  s.persons.qing.stats.body = 5; s.persons.mei.stats.body = 5;
  s.bond.close = 0;
  const base = growthLimit(s, C, "qing");
  assert.equal(base, 76, "体魄 5、心气平平、没人惦记：就是命数");
  s.persons.qing.stats.body = 8;
  assert.equal(growthLimit(s, C, "qing"), 76 + 3 * R.lifespan.body, "体魄好多活几年");
  s.persons.qing.stats.body = 5;
  s.persons.qing.moodSum = 100 * 10;
  assert.equal(growthLimit(s, C, "qing"), 76 + R.lifespan.moodMax, "一辈子开心多活几年，有上限");
  s.persons.qing.moodSum = 0;
  assert.equal(growthLimit(s, C, "qing"), 76 + R.lifespan.moodMin, "一辈子憋屈少活几年，有下限");
  s.persons.qing.moodSum = R.lifespan.moodMid * 10;
  s.bond.close = R.lifespan.bondClose;
  assert.equal(growthLimit(s, C, "qing"), 76 + R.lifespan.bond, "有人惦记");
  s.persons.mei.alive = false;
  assert.equal(growthLimit(s, C, "qing"), 76 + R.lifespan.bond, "人走了，惦记还在");
  s.bond.close = R.lifespan.widowClose;
  assert.equal(growthLimit(s, C, "qing"), 76 + R.lifespan.bond - R.lifespan.widow, "太亲的两个人，后走的那个撑不了太久");
  s.persons.qing.lifespan = 200;
  assert.equal(growthLimit(s, C, "qing"), R.lifespan.max);
  s.persons.qing.lifespan = 0;
  assert.equal(growthLimit(s, C, "qing"), R.lifespan.min);

  // 走的那一年：落在刚过完的日子和下一个日子之间，不会倒着走
  const live = (seed, tweak) => {
    const t = newLife(seed);
    tweak(t);
    let guard = 0;
    while (t.phase !== "ended") {
      for (const r of ["qing", "mei"]) if (t.persons[r].alive) { t.world.actors[r].asleep = true; t.persons[r].needs.mood = 90; }
      t.world.warm = true;
      const prev = lifeTimeAt(t.turn).age;
      const out = G("lifeEndDay")(t, C);
      for (const e of out) if (e.kind === "death") assert.ok(e.age >= prev && e.age <= lifeTimeAt(t.turn).age, `走的岁数 ${e.age} 不在 ${prev}~${lifeTimeAt(t.turn).age}`);
      assert.ok(++guard < 200);
    }
    return t;
  };
  const ages = new Set();
  for (let seed = 1; seed <= 150; seed++) {
    const t = live(seed, () => {});
    for (const r of ["qing", "mei"]) ages.add(t.persons[r].diedAtAge);
  }
  assert.ok(ages.size >= 20, `寿命要有很多种，不是五年一档：只有 ${ages.size} 种`);
  // 长寿和硬朗这两条一生小结走得到（剧情测试不模拟过日子，所以放在这里测）
  const old = live(3, (t) => { t.persons.qing.lifespan = 99; t.persons.mei.lifespan = 60; });
  assert.ok(old.persons.qing.diedAtAge >= 95);
  assert.ok(old.persons.mei.diedAtAge < old.persons.qing.diedAtAge);
  const long = C.endings.lives.find((e) => e.id === "l_long");
  if (long) assert.ok(G("lifeLifeEndingOk")(old.persons.qing, long), "活过九十五 → 长寿");
  // 内容和规则要对得上：一生小结里凡是「活到多少岁还要体魄多少」的，天天活动的人得做得到
  for (const e of C.endings.lives) {
    const rq = e.requires;
    if (!rq.stats || rq.stats.body === undefined || rq.minDiedAge === undefined) continue;
    let body = 10;
    for (let age = 0; age < rq.minDiedAge; age++) body -= G("growthAgingRate")(R.aging.body, age) * R.aging.activeFactor;
    assert.ok(body >= rq.stats.body, `${e.title}：要 ${rq.minDiedAge} 岁时体魄 ${rq.stats.body}，可天天活动的人到那时最多只剩 ${body.toFixed(2)}（改 endings.yaml 或 rules.yaml 的 aging）`);
  }
  console.log(`✓ 寿命：命数 + 体魄 + 一辈子的心气 + 有人惦记 − 撑不过那个冬天，夹在 ${R.lifespan.min}~${R.lifespan.max} / 走的岁数落在两个日子之间 / 150 条人生里有 ${ages.size} 种岁数`);
}

// ---------- 6. 亲近：越亲越难涨，不走动就淡 ----------
{
  const s = newLife(9);
  const add = (close, d) => { s.bond.close = close; s.bond.sync = close; G("lifeApplyBond")(s, C, d); return { close: s.bond.close - close, sync: s.bond.sync - close }; };
  const low = add(10, { close: 2, sync: 2 }), high = add(90, { close: 2, sync: 2 });
  assert.ok(low.close > high.close * 3 && high.close > 0, `越亲越难再涨：${low.close} / ${high.close}`);
  assert.ok(low.sync > high.sync && high.sync > 0);
  assert.equal(add(90, { close: -3 }).close, -3, "往下掉不打折");
  s.bond.close = 99.9; G("lifeApplyBond")(s, C, { close: 50 });
  assert.ok(s.bond.close <= 100);

  const day = (stage, warm, distance = 0, close = 50) => {
    const t = newLife(9);
    t.turn = turnAtAge({ childhood: 6, teen: 14, young: 22, middle: 40, old: 66 }[stage]);
    t.bond.close = close; t.bond.distance = distance; t.world.warm = warm;
    G("growthDayEnd")(t, C);
    return close - t.bond.close;
  };
  assert.equal(day("young", true), 0, "这天见过面，就不淡");
  assert.ok(day("young", false) > 0, "没走动就淡一点");
  assert.ok(day("middle", false) > day("childhood", false), "中年的日子隔得久，淡得快");
  assert.ok(day("young", false, 4) > day("young", false, 0), "离得远淡得更快");
  assert.equal(day("middle", false, 5, R.bond.driftFloor), 0, "住过对门，总归认识");
  // 同框和共鸣都算见过面
  const t = newLife(9);
  assert.equal(t.world.warm, false);
  const mirror = C.events.find((e) => e.kind === "mirror" && Object.keys(e.resonance).length > 0);
  const oid = Object.keys(mirror.resonance)[0];
  G("lifeResolveEvent")(t, C, { eventId: mirror.id, kind: "mirror", roles: ["qing", "mei"], choices: { qing: oid, mei: oid }, shadow: [] });
  assert.equal(t.world.warm, true);
  console.log("✓ 亲近：越亲越难再涨、往下掉不打折 / 这天同框或共鸣过就不淡 / 中年和离得远淡得快 / 淡到底也还认识");
}

// ---------- 7. 属性在日子里的用处 ----------
{
  const drain = (body) => {
    const s = newLife(13);
    s.persons.qing.stats.body = body;
    const before = s.persons.qing.needs.energy;
    G("worldDecay")(C, s.persons.qing, s.world.actors.qing, 600, 120);
    return before - s.persons.qing.needs.energy;
  };
  assert.ok(drain(9) < drain(5) && drain(5) < drain(1), "体魄好的人不容易累");
  console.log("✓ 用处：体魄好不容易累（魅力让同框更开心、运气多带来默契事件，见 world.ts；寿命和检定见上）");
}

// ---------- 8. 老存档 ----------
{
  const s = J(newLife(21));
  s.version = 3;
  s.persons.qing.stats.mind = 8.5;
  for (const r of ["qing", "mei"]) { delete s.persons[r].born; delete s.persons[r].moodSum; delete s.persons[r].moodDays; delete s.persons[r].active; }
  delete s.world.warm;
  const notes = G("lifeUpgrade")(s);
  assert.ok(notes.includes("v3→v4"));
  assert.equal(s.version, G("LIFE_VERSION"));
  assert.equal(s.persons.qing.born.mind, 8.5, "没记过出生属性的老存档，拿现在的当底子");
  assert.deepEqual(J(s.persons.mei.active), { body: false, mind: false });
  assert.equal(s.world.warm, false);
  // 升级完能接着过
  for (const r of ["qing", "mei"]) s.world.actors[r].asleep = true;
  G("lifeEndDay")(s, C);
  assert.equal(s.persons.qing.moodDays, 1);
  console.log("✓ 老存档：v3 升 v4 补上底子、心气、当天活动、见没见过面，升完接着过");
}
