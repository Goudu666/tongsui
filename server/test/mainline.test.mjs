// 主线测试（content/story.yaml）：七章、每章三件一定会发生的事。
// 引擎接上主线之前，这里先按约定的规则挑变体，查内容本身有没有漏：
//   挑法：同一章同一件的变体按文件里的顺序排。两个人都在时，先找头一个够得着的 mirror（看两个人标记的并集），
//         两个人一起过这件事；找不到，每个人各找头一个够得着的 solo（只看自己，alone = 对门不在了）。
//   1) 不管出身、走没走、成没成家，前四章每件事两个人都有得过；第五章往后对门不在了也有得过
//   2) 选项：每件事谁来都至少有两个能选的；殷实 / 清贫人家的孩子在几件事上真的多出一个自己的选项
//   3) 埋下的线前后接得上：主线发的共同标记后面有人读，读的标记前面有人发
//   4) 主线事件不在随机池里（引擎没接之前，游戏里不会平白冒出来），replaces 的旧事件都还在
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const code = readFileSync(new URL("../build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);
const C = G("CONTENT");
const lifeEligible = G("lifeEligible");
const S = C.story;

const STAGE_OF = (age) => (age < 12 ? "childhood" : age < 18 ? "teen" : age < 30 ? "young" : age < 60 ? "middle" : "old");
const beatsOf = (n) => {
  const m = new Map();
  for (const e of S.events.filter((e) => e.chapter === n)) {
    if (!m.has(e.beat)) m.set(e.beat, []);
    m.get(e.beat).push(e);
  }
  return [...m.entries()].sort((a, b) => a[0] - b[0]).map(([, v]) => v);
};

/** 按约定挑这一件的变体：{ mirror } 或 { qing, mei }（某人没有就是 null） */
function pick(variants, age, P, bond) {
  const t = { age, stage: STAGE_OF(age), season: null };
  const bothAlive = P.qing.alive && P.mei.alive;
  if (bothAlive) {
    const both = P.qing.flags.concat(P.mei.flags);
    const m = variants.find((e) => e.kind === "mirror" && lifeEligible(e, t, both, {}, { bond, alone: false }));
    if (m) return { mirror: m };
  }
  const out = {};
  for (const r of ["qing", "mei"]) {
    if (!P[r].alive) { out[r] = null; continue; }
    const alone = !P[r === "qing" ? "mei" : "qing"].alive;
    out[r] = variants.find((e) => e.kind === "solo" && lifeEligible(e, t, P[r].flags, {}, { bond, alone })) ?? null;
  }
  return out;
}

// ---------- 0) 结构 ----------
assert.equal(S.chapters.length, 7, "七章");
for (const [i, ch] of S.chapters.entries()) {
  const beats = beatsOf(i + 1);
  assert.equal(beats.length, 3, `第${i + 1}章「${ch.title}」应该三件事`);
}
for (const e of S.events) assert.ok(!C.events.some((x) => x.id === e.id), `${e.id} 不该在随机池里`);
for (const e of S.events) for (const r of e.replaces) assert.ok(C.events.some((x) => x.id === r), `${e.id}.replaces: ${r} 不在随机池`);

// ---------- 1) 变体覆盖 ----------
// 两个人可能的样子：出身 × 走没走 × 成没成家 × 埋没埋盒子、刻没刻名字（这些是前面主线里可能没发生的共鸣）
const FAMS = [["fam_rich"], ["fam_poor"], []];
const ROUTES = [[], ["uni_away"], ["uni_abroad"], ["army"], ["left_city"]];
const PAIR = [[], ["p_married"], ["p_capsule", "p_wall_names", "p_knock", "p_note"], ["p_estranged"]];
let combos = 0;
for (const [ci, ch] of S.chapters.entries()) {
  const n = ci + 1;
  const age = n === 7 ? 70 : ch.ages[1]; // 章里最后一个日子：没去的事这天一早强制发生
  for (const [bi, variants] of beatsOf(n).entries()) {
    for (const fq of FAMS) for (const fm of FAMS) for (const rq of ROUTES) for (const rm of ROUTES) for (const pf of PAIR) {
      const married = n >= 5 && pf.length === 0 && rq.length === 0 ? ["married_other"] : [];
      const bond = { close: 40, sync: 30, distance: rq.length + rm.length > 0 ? 2 : 0 };
      const P = {
        qing: { alive: true, flags: [...fq, ...(n >= 4 ? rq : []), ...pf, ...married] },
        mei: { alive: true, flags: [...fm, ...(n >= 4 ? rm : []), ...pf] },
      };
      const got = pick(variants, age, P, bond);
      combos++;
      assert.ok(got.mirror || (got.qing && got.mei), `第${n}章第${bi + 1}件：${JSON.stringify(P)} 有人没得过（${JSON.stringify(Object.fromEntries(Object.entries(got).map(([k, v]) => [k, v && v.id])))}）`);
      // 两个人都在、又都没走：一定是一起过的
      if (rq.length === 0 && rm.length === 0) assert.ok(got.mirror, `第${n}章第${bi + 1}件：两个人都在河畔里，却没有一起过的那一份`);
      if (n >= 5) {
        const alone = pick(variants, age, { qing: P.qing, mei: { alive: false, flags: P.mei.flags } }, bond);
        assert.ok(alone.qing, `第${n}章第${bi + 1}件：对门不在了，${JSON.stringify(P.qing.flags)} 没得过`);
        assert.equal(alone.qing.requires.alone, true, `第${n}章第${bi + 1}件：对门不在了，挑到的 ${alone.qing.id} 不是写给一个人的`);
      }
    }
  }
}
// 第四章：一个走了一个留下，两边拿到的是各自那一份
{
  const variants = beatsOf(4)[1];
  const got = pick(variants, 19, { qing: { alive: true, flags: ["uni_away"] }, mei: { alive: true, flags: [] } }, { close: 40, sync: 30, distance: 2 });
  assert.equal(got.qing.scene, "away", "走的人在外地写信");
  assert.notEqual(got.mei.scene, "away", "留下的人在河畔里收信");
  for (const [flag, id] of [["uni_abroad", "s4_letter_abroad"], ["army", "s4_letter_army"]]) {
    const got2 = pick(variants, 19, { qing: { alive: true, flags: [flag] }, mei: { alive: true, flags: [] } }, { close: 40, sync: 30, distance: 3 });
    assert.equal(got2.qing.id, id, `${flag} 的人拿到的是自己那一份`);
    assert.equal(got2.mei.id, "s4_letter_home", `对门 ${flag} 了，留下的人收信`);
    const send = pick(beatsOf(4)[0], 18, { qing: { alive: true, flags: [flag] }, mei: { alive: true, flags: [] } }, { close: 40, sync: 30, distance: 3 });
    assert.ok(send.mirror && send.mirror.id.startsWith("s4_leave"), `${flag}：楼门口送行，不是「都没走」`);
  }
}

// ---------- 2) 选项和出身 ----------
const open = (o) => !(o.cost > 0) && !Object.values(o.requires ?? {}).some((v) => (Array.isArray(v) ? v.length > 0 : v != null));
for (const e of S.events) assert.ok(e.options.filter(open).length >= 2, `${e.id}: 谁来都至少两个能选的`);
const onlyFor = (flag) => S.events.filter((e) => e.options.some((o) => (o.requires?.flags ?? []).includes(flag)));
assert.ok(onlyFor("fam_rich").length >= 6, `殷实人家多出来的选项太少（${onlyFor("fam_rich").length} 件）`);
assert.ok(onlyFor("fam_poor").length >= 5, `清贫人家自己的选项太少（${onlyFor("fam_poor").length} 件）`);
// 每一章都有一处出身会让选项不一样
for (const [i] of S.chapters.entries()) {
  const evs = S.events.filter((e) => e.chapter === i + 1);
  assert.ok(evs.some((e) => e.options.some((o) => o.requires?.flags?.some((f) => f === "fam_rich" || f === "fam_poor") || o.requires?.flags?.includes("home_own") || o.requires?.notFlags?.includes("home_own"))) || i === 6,
    `第${i + 1}章没有一处看出身或家底的选项`);
}

// ---------- 3) 线接得上 ----------
const produced = new Set();
for (const e of S.events) for (const r of Object.values(e.resonance ?? {})) for (const f of r.flags) produced.add(f);
const readAnywhere = (f) =>
  S.events.some((e) => (e.requires.flags ?? []).includes(f) || (e.requires.notFlags ?? []).includes(f) || e.options.some((o) => (o.requires?.flags ?? []).includes(f))) ||
  C.endings.pair.some((x) => (x.requires.flags ?? []).includes(f)) || JSON.stringify(C.remembered ?? []).includes(`"${f}"`) || JSON.stringify(C.heirlooms ?? []).includes(`"${f}"`);
// 地图（content/maps/，地点内容那边的 PR）读、还没合进来的标记
const READ_BY_MAPS = ["p_bridge"];
for (const f of produced) assert.ok(readAnywhere(f) || READ_BY_MAPS.includes(f), `主线发了 ${f}，后面没人读`);
for (const f of ["p_knock", "p_promise", "p_wall_names", "p_capsule", "p_note"]) assert.ok(produced.has(f), `主线应该发 ${f}`);
// 第一章敲门 → 第七章长椅；第三章纸条 → 第七章长椅；第二章盒子 → 第七章挖
const bench = S.events.find((e) => e.id === "s7_bench");
assert.ok(bench.options.some((o) => o.requires?.flags?.includes("p_knock")) && bench.options.some((o) => o.requires?.flags?.includes("p_note")));
assert.ok(S.events.some((e) => e.chapter === 7 && (e.requires.flags ?? []).includes("p_capsule")));

console.log(`✓ 主线：${S.chapters.length} 章 ${S.events.length} 个变体，${combos} 种两人组合都有得过`);
