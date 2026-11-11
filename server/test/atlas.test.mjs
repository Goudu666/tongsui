// 图鉴和「差一点」（atlas.ts）、老物件会变（heirlooms.yaml 的 from.carried）。设计见 docs/LEGACY.md 第十三节。
// 1) 内容：每个结局有谜面或者藏着  2) 关口的差一点和锁上写的是同一个数  3) 一世走完的差一点：先关口、只往前看、不说破藏着的
// 4) 图鉴按人生线攒、头一回是第几世  5) 图鉴不进投胎  6) 老物件会变、加成不涨、链尾走得到藏着的结局
// 7) 旧存档补记、结局删了以后  8) 连着过几世：差一点有多常见
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const LG = (o = {}) => ({ ...J(G("legacyNew")()), ...o });
const heir = (id) => C.heirlooms.find((h) => h.id === id);

function confirm(s) {
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  return s;
}

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

function reborn(s) {
  G("legacyAgain")(s, "qing", true);
  G("legacyAgain")(s, "mei", true);
  return G("legacyRebirth")(s, C);
}

const index = (list, id) => list.findIndex((e) => e.id === id);

// ---------- 1. 内容 ----------
{
  const a = C.atlas;
  assert.ok(a && a.riddles && a.says && Array.isArray(a.hidden) && Array.isArray(a.sad));
  for (const part of ["pair", "lives"]) {
    for (const e of C.endings[part]) {
      const hidden = a.hidden.includes(e.id);
      assert.ok(hidden !== !!a.riddles[e.id], `${e.id}：要么藏着，要么有谜面`);
    }
  }
  // 藏着的里头一定有老物件链尾那几个
  for (const id of ["e_album", "e_nested", "l_margin"]) assert.ok(a.hidden.includes(id), `${id} 应该藏着`);
  assert.equal(a.riddles.l_heir_breakfast, "生在周家，接下了家里的营生。", "接家里营生的一生按人家自动写谜面");
  console.log(`✓ 内容：${C.endings.pair.length + C.endings.lives.length} 个结局都有谜面或者藏着（藏着 ${a.hidden.length} 个），差一点能说的标记 ${Object.keys(a.says).length} 个`);
}

// ---------- 2. 关口：差一点和锁上写的是同一个数 ----------
{
  const ev = C.events.find((e) => e.id === "m_senior");
  const far = ev.options.find((o) => o.id === "far");
  let checked = 0;
  for (const mind of [7.0, 7.21, 7.35, 7.59, 7.6, 6.5]) {
    for (const swing of [0, -0.12, 0.2]) {
      const p = { flags: [], stats: { body: 5, mind, charm: 5, luck: 5 }, money: 0 };
      const lock = G("lifeOptionLock")(ev, far, p, swing, { close: 40 });
      const n = G("atlasOptionShort")(ev, far, p, swing, { close: 40 });
      if (!lock) { assert.equal(n, null, "够得着的路不算差"); continue; }
      const m = lock.match(/(\d+) 分，线是 (\d+) 分/);
      assert.ok(m, lock);
      assert.deepEqual([n.have, n.need], [Number(m[1]), Number(m[2])], `锁上写「${lock}」，差一点也得是这个数`);
      checked++;
    }
  }
  // 钱和亲近按原数；家里没有那个条件的路不算「差一点」
  const settle = C.events.find((e) => e.id === "m_settle");
  const poor = { flags: [], stats: { body: 5, mind: 5, charm: 5, luck: 5 }, money: 180 };
  const buy = G("atlasOptionShort")(settle, settle.options.find((o) => o.id === "buy"), poor, 0, { close: 40 });
  assert.deepEqual([buy.have, buy.need, buy.unit], [180, 200, "块"]);
  assert.equal(G("atlasOptionShort")(settle, settle.options.find((o) => o.id === "help"), poor, 0, { close: 40 }), null, "家里没出首付的那条不是差几块的事");
  const evening = C.events.find((e) => e.id === "m_evening");
  assert.equal(G("atlasOptionShort")(evening, evening.options.find((o) => o.id === "pair"), poor, 0, undefined), null, "对门不在了，两家并一家不是差几分的事");
  // 结算时挑最近的那条：差得太远的不算
  const p = { flags: [], stats: { body: 5, mind: 7.5, charm: 5, luck: 5 }, money: 0 };
  const near = G("atlasMilestoneNear")(ev, "near", p, 0, { close: 40 });
  assert.equal(near.option, "far");
  assert.equal(near.need - near.have, 1);
  assert.equal(G("atlasMilestoneNear")(ev, "near", { ...p, stats: { ...p.stats, mind: 5 } }, 0, { close: 40 }), null, "差二十多分的不叫差一点");
  // 名次也算（#43 目标条上的 grade:<n>）：只认目标条上摆着的那几档，分数是这一关真拿去评名次的那个
  const top = { flags: [], stats: { body: 5, mind: 9.4, charm: 5, luck: 5 }, money: 0 };
  const gw = ev.score || {};
  const gs = G("lifeScore")(top, gw, { close: 40 }) - 0.05;
  const tape = J(G("lifeTapeGrades")(ev, top));
  assert.ok(tape.includes(0), "比重点高中还高的那档名次在目标条上");
  const gn = G("atlasMilestoneNear")(ev, "far", top, 0, { close: 40 }, Math.min(gs, ev.grades[0].min - 0.03));
  assert.equal(gn && gn.option, "grade:0", "走了最高那条路、名次差一点：" + JSON.stringify(gn));
  assert.deepEqual([gn.need, gn.unit], [G("lifePoints")(ev.grades[0].min), "分"]);
  assert.equal(G("atlasNearWhat")(ev, "grade:0"), ev.grades[0].label);
  assert.equal(G("atlasNearWhat")(ev, "grade:1"), null, "兜底那档没有字，不说");
  assert.equal(G("atlasMilestoneNear")(ev, "far", top, 0, { close: 40 }, ev.grades[0].min + 0.1), null, "名次拿到了就不算差");
  const low = { ...top, stats: { ...top.stats, mind: 7.5 } };
  assert.equal(G("atlasMilestoneNear")(ev, "near", low, 0, { close: 40 }, ev.grades[0].min - 0.03).option, "far", "差一分的路比差得多的名次近");
  console.log(`✓ 关口：差一点和锁上那句是同一个数（${checked} 组对照）/ 钱按块 / 家里没那个条件、对门不在了的不算 / 差太远的不算 / 名次线也算`);
}

// ---------- 3. 一世走完的差一点 ----------
const lives = [];
{
  let lines = 0, withMilestone = 0;
  for (const seed of [1, 2, 3, 4, 5, 6, 7, 8]) {
    const s = liveOut(G("lifeCreate")(seed, C));
    lives.push(s);
    assert.ok(Array.isArray(s.near) && s.near.length <= 3);
    const kinds = J(s.near.map((n) => n.kind));
    assert.deepEqual(kinds, [...kinds].sort((a, b) => ["milestone", "pair", "life"].indexOf(a) - ["milestone", "pair", "life"].indexOf(b)), "先关口，再结局，再一生");
    assert.equal(new Set(kinds).size, kinds.length, "每样最多一行");
    for (const n of s.near) {
      assert.ok(n.text.length > 6 && !n.text.includes("undefined") && !n.text.includes("NaN"), n.text);
      if (n.kind === "pair") {
        assert.ok(index(C.endings.pair, n.id) < index(C.endings.pair, s.ending.pair), "只往更难得的那头看");
        assert.ok(!C.atlas.sad.includes(n.id) && !C.atlas.hidden.includes(n.id), "不说「差一点就走散」，也不说破藏着的");
      }
      if (n.kind === "life") {
        assert.ok(index(C.endings.lives, n.id) < index(C.endings.lives, s.ending.lives[n.role]));
        assert.ok(!C.atlas.sad.includes(n.id) && !C.atlas.hidden.includes(n.id));
      }
      if (n.kind === "milestone") {
        // 和那一天的成绩单对得上：那条日志上记着差多少
        const entry = s.log.find((e) => e.kind === "milestone" && e.events[n.role] === n.id && e.results?.[n.role]?.near);
        assert.ok(entry, "差一点的关口在日志上记着");
        const r = entry.results[n.role].near;
        assert.ok(n.text.includes(`差 ${r.need - r.have} ${r.unit}`), n.text);
        withMilestone++;
      }
    }
    lines += s.near.length;
    // 小传里留两行，下一世投胎页提
    assert.deepEqual(J(s.legacy.past.at(-1).near), J(s.near.slice(0, 2).map((n) => n.text)));
  }
  assert.ok(withMilestone >= 4, `八世里只有 ${withMilestone} 世有关口上的差一点`);
  console.log(`✓ 一世走完：八世平均 ${(lines / 8).toFixed(1)} 行差一点，${withMilestone} 世有关口上的 / 先关口再结局再一生 / 只往更难得的那头看 / 不说破藏着的 / 小传里留两行`);
  console.log("    例：" + lives[0].near.map((n) => n.text).join(" / "));
}

// ---------- 4. 图鉴按人生线攒 ----------
{
  const one = lives[0];
  const seen = one.legacy.seen;
  assert.equal(seen.pair[one.ending.pair], 1);
  for (const r of ROLES) assert.equal(seen.lives[one.ending.lives[r]], 1);
  // 第二世：头一回见到的记第 2 世，见过的还是第 1 世
  const two = liveOut(reborn(J(one)));
  assert.equal(two.life, 2);
  const s2 = two.legacy.seen;
  for (const id in seen.pair) assert.equal(s2.pair[id], seen.pair[id], "见过的不改成后来那一世");
  assert.equal(s2.pair[two.ending.pair], seen.pair[two.ending.pair] ?? 2);
  // 差一点按这一世之前见过的算：已经见过的排在没见过的后面
  const before = { pair: {}, lives: {} };
  const ss = G("atlasNear")(two, C, before);
  const all = G("atlasNear")(two, C, { pair: Object.fromEntries(C.endings.pair.map((e) => [e.id, 1])), lives: Object.fromEntries(C.endings.lives.map((e) => [e.id, 1])) });
  assert.equal(ss.filter((n) => n.kind === "milestone").length, all.filter((n) => n.kind === "milestone").length, "关口的差一点不看图鉴");
  // 有图鉴之前的人生线：从小传里补
  const lg = J(one.legacy);
  delete lg.seen;
  const back = G("atlasSeenOf")(lg);
  assert.deepEqual(J(back), J(seen));
  console.log(`✓ 图鉴：按人生线攒，记头一回是第几世（两世见过 ${Object.keys(s2.pair).length} 个结局、${Object.keys(s2.lives).length} 种一生）/ 没有图鉴的从小传里补`);
}

// ---------- 5. 图鉴不进投胎 ----------
{
  for (const seed of [3, 11, 20261111]) {
    const a = G("lifeCreate")(seed, C, LG({ lives: 2, heirlooms: ["h_photo", "h_books"] }));
    const full = { pair: Object.fromEntries(C.endings.pair.map((e) => [e.id, 1])), lives: Object.fromEntries(C.endings.lives.map((e) => [e.id, 1])) };
    const b = G("lifeCreate")(seed, C, LG({ lives: 2, heirlooms: ["h_photo", "h_books"], seen: full }));
    confirm(a); confirm(b);
    for (const r of ROLES) {
      assert.deepEqual(J(a.persons[r].stats), J(b.persons[r].stats), "见过多少结局，投胎出来的孩子一模一样");
      assert.deepEqual(J(a.persons[r].flags), J(b.persons[r].flags));
      assert.equal(a.persons[r].money, b.persons[r].money);
    }
    assert.equal(a.rng, b.rng, "图鉴不动随机数");
  }
  console.log("✓ 图鉴不进投胎：见过全部结局和一个没见过，同一个种子投出来的人属性、标记、钱、随机数都一样");
}

// ---------- 6. 老物件会变 ----------
{
  const blank = (o = {}) => ({ flags: [], stats: { body: 5, mind: 5, charm: 5, luck: 5 }, money: 0, diedAtAge: 75, heirloomId: null, ...o });
  const chains = C.heirlooms.filter((h) => h.from.carried);
  assert.ok(chains.length >= 5);
  for (const h of chains) {
    const prev = heir(h.from.carried);
    assert.ok(prev, h.id);
    assert.ok(h.hint && h.hint.length <= 20);
    const p = blank({ heirloomId: prev.id, flags: [...(h.from.flags || [])], stats: { ...blank().stats, ...(h.from.stats || {}) } });
    assert.equal(G("legacyLeave")(C, p), h.id, `带着${prev.name}、又做了那件事，留下${h.name}`);
    assert.notEqual(G("legacyLeave")(C, { ...p, heirloomId: null }), h.id, `没带着${prev.name}的，留不下${h.name}`);
    // 加成不涨：和上一件一样大（属性半点上限由构建拦着）
    const sum = (x) => Object.values(x.bonus).reduce((a, b) => a + b, 0) * 10 + x.money + x.close;
    assert.ok(sum(h) <= Math.max(sum(prev), 5), `${h.name} 比 ${prev.name} 给得多`);
  }
  // 链尾走得到藏着的结局
  const end = (flags, close) => {
    const s = J(lives[0]);
    for (const r of ROLES) s.persons[r].flags = [...s.persons[r].flags.filter((f) => !f.startsWith("heir_") && !f.startsWith("p_") && f !== "has_kid"), ...flags[r]];
    s.bond.close = close;
    return G("lifeEnding")(s, C);
  };
  assert.equal(end({ qing: ["heir_photo_two", "p_married"], mei: ["p_married"] }, 60).pair, "e_album");
  assert.equal(end({ qing: ["heir_nested", "p_capsule"], mei: ["p_capsule"] }, 60).pair, "e_nested");
  assert.notEqual(end({ qing: ["heir_nested", "p_capsule"], mei: ["p_capsule"] }, 40).pair, "e_nested", "一层套一层要亲近到 50");
  assert.equal(end({ qing: ["heir_noted", "has_kid"], mei: [] }, 40).lives.qing, "l_margin");
  // 一条链连着过：第一世合影 → 带着合影拉钩 → 两张合影
  const s = liveOut(G("lifeCreate")(5, C));
  const next = reborn(s);
  if (next.rolls.qing.offer.includes("h_photo")) {
    G("legacyPick")(next, "qing", "h_photo");
    confirm(next);
    assert.equal(next.persons.qing.heirloomId, "h_photo");
    assert.ok(next.persons.qing.flags.includes("heir_photo"));
  }
  console.log(`✓ 老物件会变：${chains.map((h) => `${heir(h.from.carried).name}→${h.name}`).join("、")} / 没带着的留不下 / 加成不涨 / 链尾走得到「又一张」「一层套一层」「页边」`);
}

// ---------- 7. 旧存档和内容变了 ----------
{
  const old = J(lives[1]);
  delete old.near;
  delete old.legacy.seen;
  delete old.legacy.past.at(-1).near;
  const notes = J(G("lifeRepair")(old, C));
  assert.ok(notes.some((n) => n.includes("图鉴")), "走完的旧存档补算一回差一点");
  assert.deepEqual(J(old.near), J(lives[1].near));
  assert.deepEqual(J(old.legacy.seen), J(lives[1].legacy.seen));
  assert.deepEqual(J(G("lifeRepair")(old, C)), [], "只补一回");
  // 结局从内容里删了：图鉴里摘掉
  const c2 = J(C);
  const gone = old.ending.pair === "e_doors" ? old.ending.lives.qing : old.ending.pair;
  c2.endings.pair = c2.endings.pair.filter((e) => e.id !== gone);
  c2.endings.lives = c2.endings.lives.filter((e) => e.id !== gone);
  const n2 = J(G("atlasRepair")(old, c2, []) ?? []);
  assert.ok(old.legacy.seen.pair[gone] === undefined && old.legacy.seen.lives[gone] === undefined, "删了的结局从图鉴里摘掉");
  // 没有 atlas 的旧内容包：不抛错，差一点只剩关口
  const c3 = J(C);
  delete c3.atlas;
  const s3 = J(lives[2]);
  const near3 = G("atlasNear")(s3, c3, { pair: {}, lives: {} });
  assert.ok(near3.every((n) => !n.text.includes("就差") && !n.text.includes("坏在") && !n.text.includes("undefined")), "没有 says 就不拿标记说差一点");
  void n2;
  console.log("✓ 旧存档：走完的补算一回差一点和图鉴，只补一回 / 结局删了从图鉴里摘掉 / 旧内容包没有 atlas 不抛错");
}

// ---------- 8. 连着过几世 ----------
{
  let s = liveOut(G("lifeCreate")(20261111, C));
  const firsts = [];
  for (let n = 2; n <= 4; n++) {
    s = liveOut(reborn(s));
    firsts.push(Object.values(s.legacy.seen.pair).filter((x) => x === n).length + Object.values(s.legacy.seen.lives).filter((x) => x === n).length);
    assert.ok(s.near.length >= 1, `第 ${n} 世一行差一点都没有`);
  }
  const seen = s.legacy.seen;
  console.log(`✓ 连过四世：图鉴里 ${Object.keys(seen.pair).length}/${C.endings.pair.length} 个结局、${Object.keys(seen.lives).length}/${C.endings.lives.length} 种一生；第二到四世各新见 ${firsts.join("、")} 个；每世都有差一点`);
}
