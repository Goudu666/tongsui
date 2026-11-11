#!/usr/bin/env node
// 活法模拟：让机器人按几种活法在河畔里把人生过完（最后一道关在 75 岁），看每个关口各种活法落在哪条线上。
// 用法：npm run server:build && node tools/paths.mjs [每种活法跑几条人生，默认 60] [只跑这几种活法…]
//       UNTIL=31 node tools/paths.mjs 只过到 30 岁那一关（快得多）
//
// 分数线（content/events/milestones.yaml 里的 min）是这个游戏最要紧的数值。调的时候看这张表：
//   - 「不上心」的活法应该够不着高线；「专心」的应该大多够得着；
//   - 「搭伴专心」应该比「一个人专心」明显好，这是两个人一起玩的理由；
//   - 一个人不该同时够着所有的线，不然就没有取舍了。
// server/test/paths.test.mjs 用同一套机器人把上面几条钉成断言。
import { readFileSync } from "node:fs";
import vm from "node:vm";

const code = readFileSync(new URL("../server/build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math, Date });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);
const C = G("CONTENT");
const ROLES = ["qing", "mei"];
const spotOf = new Map(C.map.spots.map((sp) => [sp.id, sp]));

/** 机器人去一个点位做事（不走路，直接到）。做不了返回 false */
function go(s, role, spotId) {
  const a = s.world.actors[role], sp = spotOf.get(spotId);
  if (!sp || G("worldCanAct")(s, C, role, spotId, true)) return false;
  a.x = sp.at[0]; a.y = sp.at[1];
  return !G("worldAct")(s, C, role, spotId).error;
}

/** 现在能做的事：[{ spot, act }]。visit：也算上对门家里的书桌（去 TA 家写作业） */
function options(s, role, visit) {
  const out = [];
  for (const sp of C.map.spots) {
    const owner = C.map.zones.find((z) => z.id === sp.zone).owner;
    if (owner && owner !== role && !visit) continue;
    const act = G("worldPickAction")(s, C, role, sp).act;
    if (act && !G("worldCanAct")(s, C, role, sp.id, true)) out.push({ spot: sp.id, act });
  }
  return out;
}

/**
 * 过日子的部分所有活法都一样：饿了吃、脏了洗（顺手的事，做完这一段还接着定）、累垮了睡、该去的去。
 * 一天五段：返回 true 表示这一回合动过了（吃了一口、定了这一段），下一回合接着看
 */
function upkeep(s, role) {
  const p = s.persons[role], w = s.world;
  const pick = (id) => options(s, role).find((o) => o.act.id === id);
  if (p.needs.hunger < 40) { const o = pick("eat"); if (o && go(s, role, o.spot)) return true; }
  if (p.needs.energy < 20) { const o = pick("sleep"); if (o && go(s, role, o.spot)) return true; }
  const d = G("worldDutyOpen")(s, C, role);
  if (d && w.slot >= G("worldDutySlots")(d)[0] && go(s, role, d.spot)) return true;
  return false;
}

/** 空闲时间怎么花。want(act) 给行动打分，取最高的；心情太差先去玩 */
function free(s, role, want, visit) {
  const p = s.persons[role];
  // 不搭伴的活法里，两个人不往同一个点凑（不然「一个人练」其实也是搭伴）
  const taken = visit ? null : s.world.actors[role === "qing" ? "mei" : "qing"]?.spot;
  let list = options(s, role, visit).filter((o) => !o.act.duty && !o.act.sleep && o.act.id !== "eat" && o.act.id !== "wash" && o.spot !== taken);
  if (p.needs.mood < 35) {
    const fun = list.filter((o) => (o.act.needs.mood || 0) >= 8 && o.act.money >= 0);
    if (fun.length) return go(s, role, fun[0].spot);
  }
  list = list.map((o) => ({ ...o, v: want(o.act) })).filter((o) => o.v > 0).sort((x, y) => y.v - x.v);
  return list.length ? go(s, role, list[0].spot) : false;
}

const grow = (key) => (act) => act.stats[key] || 0;
// 带孩子（docs/FAMILY.md）：纸带上孩子那道关看哪项，就带孩子去长哪项
const kidGrow = (key) => (act) => (act.kid && act.kid[key]) || 0;
/** 顾自己：「混着来」那样过（心智、体魄、魅力、玩轮着），三十以后盯四十五（看心智和魅力）。不押孩子的那份时间全在这儿 */
const mine = (s) => (G("lifeTimeAt")(s.turn).age < 30 ? [grow("mind"), grow("body"), grow("charm"), fun][s.turn % 4] : s.turn % 2 ? grow("charm") : grow("mind"));
/** 认真押孩子：孩子那道关是最近的时候，空闲时段一半给孩子（隔一段一回），另一半念书 */
const forKid = (s, role) => {
  const g = G("lifeGoal")(s, C, role);
  const kg = g && (g.kid ? g : g.also && g.also.kid ? g.also : null);
  if (!kg || (s.turn + s.world.slot) % 2) return mine(s);
  // 这道关看的那几项里权重最大的那项
  const ev = C.events.find((e) => e.id === kg.id);
  const w = ev.score || {};
  const key = ["kid_mind", "kid_body", "kid_charm"].sort((a, b) => (w[b] || 0) - (w[a] || 0))[0];
  return kidGrow(key.slice(4));
};
const fun = (act) => (act.money >= 0 && !Object.keys(act.stats).length ? (act.needs.mood || 0) : 0);

/**
 * 活法。each(s, role) 返回这个人空闲时想做的事的打分函数；together 表示两人凑到一个点一起做。
 * 「不上心」只玩；「专心」盯一项；「搭伴」是青带着梅一起盯同一项。
 */
export const WAYS = {
  "不上心": { each: () => fun },
  "一个人念书": { each: () => grow("mind") },
  "搭伴念书": { each: () => grow("mind"), together: true },
  "一个人练身体": { each: () => grow("body") },
  "搭伴练身体": { each: () => grow("body"), together: true },
  "嘴甜人缘好": { each: () => grow("charm") },
  "一半念书一半玩": { each: (s) => (s.turn % 2 ? grow("mind") : fun) },
  "各顾各的": { each: (s, role) => grow(role === "qing" ? "mind" : "body") },
  "混着来": { each: (s) => [grow("mind"), grow("body"), grow("charm"), fun][s.turn % 4] },
  // 钱的活法：能挣钱的事优先（小时候帮爷爷修车）。钱该是拿成长换来的，不能白捡
  "从小挣钱": { each: () => (act) => (act.money > 0 ? 10 : 0) + (act.stats.body || 0) },
  // 梅不在线，影子替她过。影子是替人过日子的，不是替人拼的：梅应该落在「不上心」和「一半一半」之间，不能比真人专心还强
  "青不上心，梅是影子": { each: () => fun, shadow: ["mei"] },
  "青念书，梅是影子": { each: () => grow("mind"), shadow: ["mei"] },
  // 成家和下一代：二十八岁两个人各有一个孩子（kids: true，live 里给 has_kid）。押孩子的空闲一半给孩子；不押的只顾自己念书
  "押孩子": { each: forKid, kids: true },
  "不押孩子": { each: (s) => mine(s), kids: true },
  "搭伴押孩子": { each: forKid, kids: true, together: true },
  "两口子押孩子": { each: forKid, kids: "married", together: true },
};
export const KID_WAYS = ["押孩子", "不押孩子", "搭伴押孩子", "两口子押孩子"];

/**
 * 把一条人生过到 untilAge 岁。pickOption(s, role, ev, open) 决定关口和事件怎么选。
 * way.shadow 里的人不在线：机器人不管他，由引擎的影子替他过（worldShadowAct、lifeShadowChoose）。
 * setup(s) 在投胎确认之前调用，可以动抽到的卡（比如让人带上一件老物件，看它压不压得过活法）。
 */
export function live(seed, way, untilAge, pickOption, setup) {
  const off = way.shadow || [];
  const online = { qing: !off.includes("qing"), mei: !off.includes("mei") };
  const s = G("lifeCreate")(seed, C);
  if (setup) setup(s);
  G("lifeConfirm")(s, C, "qing", { qing: "青", mei: "梅" });
  G("lifeConfirm")(s, C, "mei", { qing: "青", mei: "梅" });
  const marks = {}; // 关口 id → { role: { stats, money, open:[能走的路], chose } }
  let guard = 0, lastSlot = null;
  while (s.phase === "life" && G("lifeTimeAt")(s.turn).age < untilAge) {
    if (++guard > 2e6) throw new Error("人生没有往前走");
    const w = s.world;
    // 带孩子的活法：二十八岁那天早上两个人都拿 has_kid（married：先成两口子，共用一个）
    if (way.kids && G("lifeTimeAt")(s.turn).age >= 28 && !s.persons.qing.flags.includes("has_kid")) {
      for (const r of ROLES) {
        if (way.kids === "married") G("lifeAddFlags")(s.persons[r], ["p_married"]);
        G("lifeAddFlags")(s.persons[r], ["has_kid"]);
      }
      G("kidSync")(s, C);
    }
    // 关口那天一早，记下每个人够得着哪几条线（不算发挥）
    if (w.fate.milestone && w.slot === 0 && !w.playing && !marks[w.fate.milestone]) {
      const ms = C.events.find((e) => e.id === w.fate.milestone);
      marks[ms.id] = {};
      G("lifeKidBind")(s);
      for (const r of ROLES) {
        const p = s.persons[r];
        if (!G("lifeMilestoneForRole")(s, ms, r) || G("lifeSeenIds")(s, r)[ms.id]) continue;
        const kid = G("kidOf")(s, r);
        marks[ms.id][r] = { stats: { ...p.stats }, kid: kid ? { ...kid.stats } : null, money: p.money, close: s.bond.close, open: ms.options.filter((o) => !G("lifeOptionLock")(ms, o, p, 0, G("lifePairBond")(s, r))).map((o) => o.id) };
      }
    }
    if (w.event) {
      const pe = w.event, ev = G("lifeFindEvent")(C, pe.eventId);
      for (const r of pe.roles) {
        if (pe.choices[r]) continue;
        if (!online[r]) { G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, ev.id), true); if (!s.world || s.world.event !== pe) break; continue; }
        const swing = (pe.swing && pe.swing[r]) || 0;
        G("lifeKidBind")(s);
        const open = ev.options.filter((o) => !G("lifeGated")(ev) || !G("lifeOptionLock")(ev, o, s.persons[r], swing, G("lifePairBond")(s, r)));
        const id = pickOption ? pickOption(s, r, ev, open) : open[Math.floor(G("lifeRand")(s) * open.length)].id;
        G("worldChoose")(s, C, r, id, false);
        if (!s.world || s.world.event !== pe) break;
      }
      continue;
    }
    // 每一段开头先让世界看一眼（真人也是先站在那儿再定）：命运给的事这时候才碰得上
    const slotKey = s.turn + ":" + w.slot;
    if (!w.playing && slotKey !== lastSlot) { lastSlot = slotKey; G("worldAdvance")(s, C, 0, online); continue; }
    for (const r of ROLES) {
      const a = w.actors[r];
      if (!a || w.playing || G("worldReady")(s, r) || !s.persons[r].alive || !online[r]) continue;
      if (upkeep(s, r)) continue;
      const want = way.each(s, r);
      if (way.together && r === "mei") {
        // 梅跟着青：青这一段定了一件事就去同一个点搭伴，青还没定就等
        const q = w.actors.qing;
        if (q && q.action && q.spot && !q.asleep && G("worldPickAction")(s, C, r, spotOf.get(q.spot)).act?.id === q.action && go(s, r, q.spot)) continue;
        if (q && s.persons.qing.alive && !G("worldReady")(s, "qing")) continue;
      }
      // 没有想做的事：这一段歇着
      if (!free(s, r, want, way.together)) G("worldPass")(s, C, r);
    }
    G("worldAdvance")(s, C, 0.5, online);
  }
  return { s, marks };
}

/** 关口上总是选够得着的线里最高的那条 */
export const climb = (s, r, ev, open) => {
  if (ev.kind !== "milestone") return open[Math.floor(G("lifeRand")(s) * open.length)].id;
  // 线不是一个量纲的（分数、积蓄、亲近）比不了高低，按写的顺序取头一条带线的
  const lined = open.filter((o) => o.min);
  const raw = (o) => G("lifeScoreRaw")(o.score || ev.score || {});
  if (lined.length && lined.some((o) => raw(o) !== raw(lined[0]))) return lined[0].id;
  return [...open].sort((a, b) => (b.min || 0) - (a.min || 0))[0].id;
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const N = Number(process.argv[2]) || 60;
  const UNTIL = Number(process.env.UNTIL) || 76;
  const only = process.argv.slice(3);
  // 孩子的关口按孩子的岁数排在爹妈三十岁以后（kidAge + 30 只是排序用）
  const stones = C.events.filter((e) => e.kind === "milestone" && e.options.some((o) => o.min)).sort((a, b) => (a.age ?? a.kidAge + 30) - (b.age ?? b.kidAge + 30));
  console.log(`每种活法 ${N} 条人生（两个人 = ${N * 2} 个人），关口上总选够得着的最高那条线。数字是够得着这条线的人的比例。\n`);
  for (const [name, way] of Object.entries(WAYS)) {
    if (only.length && !only.includes(name)) continue;
    const rows = [];
    const acc = {};
    for (let seed = 1; seed <= N; seed++) {
      const { marks } = live(seed * 7919, way, UNTIL, climb);
      for (const ev of stones) for (const r of way.shadow || ROLES) {
        const m = marks[ev.id]?.[r];
        if (!m) continue;
        const a = (acc[ev.id] ||= { n: 0, open: {}, stat: { body: 0, mind: 0, charm: 0 }, kid: { body: 0, mind: 0, charm: 0 }, money: 0, close: 0 });
        if (m.kid) for (const k of Object.keys(a.kid)) a.kid[k] += m.kid[k];
        a.n++;
        for (const id of m.open) a.open[id] = (a.open[id] || 0) + 1;
        for (const k of Object.keys(a.stat)) a.stat[k] += m.stats[k];
        a.money += m.money;
        a.close += m.close;
      }
    }
    for (const ev of stones) {
      const a = acc[ev.id];
      if (!a) continue;
      const pct = ev.options.filter((o) => o.min).map((o) => `${o.id} ${Math.round(((a.open[o.id] || 0) / a.n) * 100)}%`).join("  ");
      const st = Object.entries(ev.kidAge !== undefined ? a.kid : a.stat).map(([k, v]) => `${ev.kidAge !== undefined ? "孩子" : ""}${k} ${(v / a.n).toFixed(1)}`).join(" ");
      rows.push(`  ${ev.kidAge !== undefined ? "孩" + String(ev.kidAge).padStart(2) : String(ev.age).padStart(2) + " 岁"} ${ev.title.padEnd(6, "　")} ${pct.padEnd(64)} | ${st}  积蓄 ${Math.round(a.money / a.n)}  亲近 ${Math.round(a.close / a.n)}  (${a.n} 人)`);
    }
    console.log(`【${name}】\n${rows.join("\n")}\n`);
  }
}
