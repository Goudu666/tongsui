// 主线测试（content/story.yaml）：七章、每章三件一定会发生的事。
// 前四段按约定的规则挑变体，查内容本身有没有漏（和 server/src/story.ts 的 storyToday 是同一个挑法）：
//   挑法：同一章同一件的变体按文件里的顺序排。两个人都在时，先找头一个够得着的 mirror（看两个人标记的并集），
//         两个人一起过这件事；找不到，每个人各找头一个够得着的 solo（只看自己，alone = 对门不在了）。
//   1) 不管出身、走没走、成没成家，前四章每件事两个人都有得过；第五章往后对门不在了也有得过
//   2) 选项：每件事谁来都至少有两个能选的；殷实 / 清贫人家的孩子在几件事上真的多出一个自己的选项
//   3) 埋下的线前后接得上：主线发的共同标记后面有人读，读的标记前面有人发
//   4) 主线事件不在随机池里，replaces 的旧事件都还在（引擎从随机池里摘掉它们，旧 id 存档和传承还引用着）
// 第五段是引擎（server/src/story.ts）：
//   5) 全影子的人生里，活着的人每章三件按顺序都过到，每件一次；被顶替的旧事件一次也不出
//   6) 一章三件按岁数摊开；章末还没碰上的一早强制发生；主线所在的图今天给这个人开着；家底门槛在服务器上也拦
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

// ---------- 5) 引擎：全影子人生里每章三件都过到 ----------
{
  const NAMES = { qing: "青", mei: "梅" };
  const OFF = { qing: false, mei: false };
  const byId = new Map(S.events.map((e) => [e.id, e]));
  const replaced = new Set(S.events.flatMap((e) => e.replaces));
  const SLOT_AT = [[390, 480], [480, 720], [720, 930], [930, 1110], [1110, 1320]], SLOT_IDS = ["morning", "am", "pm", "evening", "night"];
  let lives = 0, beats = 0, there = 0;
  for (let seed = 1; seed <= 12; seed++) {
    const s = G("lifeCreate")(seed * 7919, C);
    G("lifeConfirm")(s, C, "qing", NAMES);
    G("lifeConfirm")(s, C, "mei", NAMES);
    for (let t = 0; s.phase !== "ended"; t++) {
      G("worldAdvance")(s, C, 0.1, OFF);
      if (s.world && s.world.event) {
        const pe = s.world.event;
        for (const r of pe.roles) if (!pe.choices[r] && s.world.event === pe) assert.equal(G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, pe.eventId), true).error, null, `${pe.eventId}: 影子选了一条走不了的路`);
      }
      assert.ok(t < 900000);
    }
    lives++;
    for (const e of s.log) for (const r of ["qing", "mei"]) assert.ok(!replaced.has(e.events[r]), `${e.events[r]} 让主线顶替了，不该再从随机池里出来`);
    for (const r of ["qing", "mei"]) {
      const got = s.log.filter((e) => byId.has(e.events[r])).map((e) => ({ ev: byId.get(e.events[r]), age: e.age, minute: e.minute }));
      const keys = Array.from(got, (g) => g.ev.chapter * 10 + g.ev.beat);
      assert.deepEqual(keys, [...keys].sort((a, b) => a - b), `${seed}/${r}：主线要按章、按件的顺序过（${keys.join(" ")}）`);
      assert.equal(new Set(keys).size, keys.length, `${seed}/${r}：同一件过了两回`);
      const died = s.persons[r].diedAtAge ?? 999;
      for (const [ci, ch] of S.chapters.entries()) {
        const last = Math.min(ch.ages[1], ch.ages[0] + 14);
        if (died <= last) continue; // 这一章没活完：后面的件可能还没排到
        for (let b = 1; b <= 3; b++) assert.ok(keys.includes((ci + 1) * 10 + b), `${seed}/${r}：第${ci + 1}章第${b}件没过到（活到 ${died === 999 ? "最后" : died} 岁）`);
      }
      for (const g of got) {
        const open = G("storyOpenAge")(S.chapters[g.ev.chapter - 1], g.ev.beat - 1, 3);
        assert.ok(g.age >= open, `${g.ev.id}：${g.age} 岁就发生了，第${g.ev.beat}件要到 ${open} 岁才排上`);
        beats++;
        const k = SLOT_IDS.indexOf(g.ev.slot);
        if (g.minute >= SLOT_AT[k][0] && g.minute < SLOT_AT[k][1] && !(k > 0 && g.minute === 390)) there++;
      }
    }
  }
  // 影子会往主线那张图上走：一大半是走到了那儿、那一段发生的，强制的是少数
  assert.ok(there / beats > 0.55, `影子过的人生里只有 ${Math.round((there / beats) * 100)}% 的主线是走到那儿发生的`);
  console.log(`✓ 引擎：${lives} 条全影子人生、${beats} 件主线，每章三件按顺序都过到，${Math.round((there / beats) * 100)}% 是走到那张图、那一段发生的，其余章末一早强制 / 被顶替的旧事件一次没出`);
}

// ---------- 6) 引擎的几条规矩 ----------
{
  const NAMES = { qing: "青", mei: "梅" };
  const J = (x) => JSON.parse(JSON.stringify(x));
  const at = (age, last = false) => {
    // 这一岁的头一天（last：这一章最后一个日子）
    let t = 0;
    while (G("lifeTimeAt")(t).age < age) t++;
    if (last) while (G("lifeTimeAt")(t + 1).age <= age) t++;
    return t;
  };
  const fresh = (seed = 11) => { const s = G("lifeCreate")(seed, C); G("lifeConfirm")(s, C, "qing", NAMES); G("lifeConfirm")(s, C, "mei", NAMES); return s; };
  const today = (s) => J(G("storyToday")(s, C, G("lifeTimeAt")(s.turn)));
  // 摊开：第二章（6~11 岁）第二件到 8 岁才排上（s2_names 自己写的是 7 岁）
  {
    const s = fresh();
    s.log.push({ turn: 0, age: 6, events: { qing: "s2_road", mei: "s2_road" }, choices: {} });
    s.turn = at(7);
    assert.equal(today(s).mirror, null, "7 岁还排不上第二章第二件");
    s.turn = at(8);
    assert.equal(today(s).mirror, "s2_names");
  }
  // 强制：第一章最后一个日子，一件都没过的人一早就遇上第一件
  {
    const s = fresh();
    s.turn = at(4);
    assert.deepEqual(today(s).force, [], "离章末还远，不强制");
    s.turn = at(5, true);
    G("worldStartDay")(s, C);
    assert.deepEqual(J(s.world.fate.force), ["s1_door"]);
    const tick = G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
    assert.ok(tick.started && tick.started.eventId === "s1_door" && s.world.minute === 390, "章末没碰上的一早就发生，不等人走过去");
  }
  // 主线带人过桥：12 岁、家里不送去学琴的孩子，平时去不了河对岸；排上「过桥」的那天能去
  {
    const s = fresh();
    for (const r of ["qing", "mei"]) s.persons[r].flags = s.persons[r].flags.filter((f) => !["fam_rich", "fam_factory"].includes(f));
    s.turn = at(12);
    G("worldStartDay")(s, C);
    const across = C.map.scenes.find((x) => x.id === "across");
    assert.equal(s.world.fate.mirror, "s3_bridge");
    assert.equal(G("worldSceneLock")(s, C, across, "qing"), null, "排上了过桥那件事，那天河对岸开着");
    s.world.fate.mirror = null;
    assert.match(G("worldSceneLock")(s, C, across, "qing") || "", /去/, "平时 12 岁还去不了河对岸");
  }
  // 家底门槛：不是殷实人家的孩子选不了铁皮青蛙；locks 里写着
  {
    const s = fresh();
    for (const r of ["qing", "mei"]) s.persons[r].flags = s.persons[r].flags.filter((f) => f !== "fam_rich");
    s.world.event = { eventId: "s1_door", kind: "mirror", roles: ["qing", "mei"], choices: {}, shadow: [] };
    assert.ok(J(G("lifeMilestoneLocks")(s, C)).qing.frog, "主线的锁也发给客户端");
    assert.match(G("worldChoose")(s, C, "qing", "frog", false).error || "", /走不了/);
    assert.equal(G("worldChoose")(s, C, "qing", "knock", false).error, null);
  }
  console.log("✓ 引擎规矩：一章三件按岁数摊开 / 章末一早强制 / 主线那张图当天开着 / 家底门槛服务器也拦");
}
