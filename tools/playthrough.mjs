#!/usr/bin/env node
// 通关机器人：两个「人」从配对、投胎一直玩到这一世走完，走的是真房间（main.ts 的 matchLoop，一秒十跳），
// 发的是客户端会发的消息（MOVE 一跳一步地走过去、EXIT 换图、ACT、PASS、CHOOSE），所以量出来的是「真人大概要玩多久」。
// 用来找：卡死（一段过不去）、空转（一段又一段没事可做）、主线断档（很久碰不上一件主线）、报错（服务器回 ERROR）。
//
// 用法：npm run server:build && node tools/playthrough.mjs [几世，默认 3] [--seed=1] [--json=out.json] [--quiet]
//   PERSONA=careful|casual  careful：照着纸带上的「下一件事」走、能搭伴就搭伴；casual：一半时候随便逛、常常「就这么过」
//   AWAY=20:26              梅在第 20~26 个日子掉线（影子替她过），回来接着玩
//   --check                 当测试用（server 的 npm test 最后跑一世）：卡住、服务器回 ERROR、房间报错、主线少于 21 件、再来一世进不了投胎都算失败
//
// 「人」的手速（真人看字、想、点）按 THINK 表算进现实时间，走路按服务器的步速一跳一跳地走。
// 打出来的报告：每章用了多少现实分钟、每天几段是空转的、主线每件在哪一天、是走过去碰上的还是章末躲不过的，
// 第一个钟头里过到了几岁、遇到了几件事。
import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { G, C, fakeNakama, room, logger } from "../server/test/harness.mjs";

const args = process.argv.slice(2);
const LIVES = Number(args.find((a) => /^\d+$/.test(a)) || 3);
const SEED0 = Number((args.find((a) => a.startsWith("--seed=")) || "--seed=1").slice(7));
const JSON_OUT = (args.find((a) => a.startsWith("--json=")) || "").slice(7);
const QUIET = args.includes("--quiet");
const CHECK = args.includes("--check"); // 当测试用：卡住、服务器回错、房间出错、主线没走完、再来一世进不了投胎，就退出码 1
const PERSONA = process.env.PERSONA || "careful";
// 成家和下一代的校准（tools/sprint.mjs --kids）：KIDS=push 二十八岁两个人各有一个孩子、认真的人孩子那道关最近时押孩子；
// KIDS=none 一样有孩子，但从不带孩子（纸带上孩子那道关最近时也顾自己）
const KIDS = process.env.KIDS || "";
const AWAY = (process.env.AWAY || "").split(":").map(Number);
// ONCE=1：正经事一回一回地按（新安装包的默认按法，world.ts 的 worldActOnce），做完一回再按，偶尔换一件；不设就是「做到点」，整段押上
const ONCE = !!process.env.ONCE;
// MENU=1：点位菜单上的每一件都看（协议 8，ACT 带 action）；不设就是只看菜单头一件，和影子、旧安装包一样
const MENU = !!process.env.MENU;
// SNAP=1：每个日子收工时记下两个人纸带上的线（lifeGoal），tools/sprint.mjs 拿它量关口冲刺有没有得拼
const SNAP = !!process.env.SNAP;
function snapGoals(s) {
  return Object.fromEntries(["qing", "mei"].map((r) => {
    const g = s.persons[r].alive ? G("lifeGoal")(s, C, r) : null;
    return [r, { goal: g && { t: g.title, turns: g.turns, lines: g.lines.map((l) => ({ id: l.id, have: l.have, need: l.need })) } }];
  }));
}

const OP = G("OP");
const TICK = 10; // 一秒十跳（main.ts TICK_RATE）
const WALK = 360 * 0.95; // 一秒走多少（world.ts WALK_SPEED，略慢一点，别撞限速）
const SLOTS = ["morning", "am", "pm", "evening", "night"];
const SLOT_ZH = ["早上", "上午", "下午", "傍晚", "晚上"];
/** 真人手速（秒）：定一段干什么、读一件事、读关口、看一天的结算 */
const THINK = { slot: 3, quick: 1.2, event: 4, perChar: 1 / 9, milestone: 12, dayEnd: 3, roll: 8, once: 2 };

const actionOf = new Map(C.map.actions.map((a) => [a.id, a]));
const sceneOf = new Map(C.map.scenes.map((s) => [s.id, s]));
const zoneOf = new Map(C.map.zones.map((z) => [z.id, z]));
const evOf = (id) => G("lifeFindEvent")(C, id);
const storyOf = (id) => G("storyFindEvent")(C, id);

let rngState = SEED0 * 7919 + 13;
const rand = () => { rngState = (rngState * 1103515245 + 12345) % 2147483648; return rngState / 2147483648; };
const pick = (list) => list[Math.floor(rand() * list.length)];

// ---------- 走路：出口连成的图上找最近的路（每层地面是一个点，走出口不花时间） ----------

function sceneAt(y) { return C.map.scenes.find((s) => s.index === Math.floor(y / C.map.stride)); }

/** 从 (x, y) 走到 (tx, ty) 的下一步：同一层就直接走；不同层就先走到路上第一个出口。返回 { x, exit } */
function route(s, role, x, y, tx, ty) {
  if (y === ty) return { x: tx, exit: null };
  // Dijkstra：节点是「站在某层地面的某个横坐标」，边是走到出口（横向距离）再瞬移到出口那头
  const dist = new Map([[`${x},${y}`, 0]]);
  const first = new Map([[`${x},${y}`, null]]);
  const todo = [[x, y]];
  const done = new Set();
  let best = null;
  while (todo.length) {
    todo.sort((a, b) => dist.get(`${a[0]},${a[1]}`) - dist.get(`${b[0]},${b[1]}`));
    const [cx, cy] = todo.shift();
    const key = `${cx},${cy}`;
    if (done.has(key)) continue;
    done.add(key);
    const d0 = dist.get(key);
    if (cy === ty) {
      const total = d0 + Math.abs(cx - tx);
      if (!best || total < best.total) best = { total, exit: first.get(key) };
      continue;
    }
    for (const ex of C.map.exits) {
      if (ex.at[1] !== cy) continue;
      if (G("worldSceneLock")(s, C, sceneOf.get(ex.to), role)) continue;
      const nk = `${ex.arrive[0]},${ex.arrive[1]}`;
      // 过桥、坐车要花掉这一段的时间（world.ts 的 worldExit）：按一分钟 40 像素算进路程，能走过去就不绕桥
      const nd = d0 + Math.abs(cx - ex.at[0]) + 40 + (ex.ride || 0) * 40;
      if (!dist.has(nk) || nd < dist.get(nk)) {
        dist.set(nk, nd);
        first.set(nk, first.get(key) || ex);
        todo.push([ex.arrive[0], ex.arrive[1]]);
      }
    }
  }
  if (!best) return null;
  return { x: best.exit.at[0], exit: best.exit };
}

// ---------- 一个「人」 ----------

function makePlayer(role, presence) {
  return {
    role, presence, online: true,
    wait: 0, // 还要「想」多少跳
    plan: null, // { spot, act, why } | { scene, why } | { pass, why }
    planKey: "",
    errors: [],
    tried: new Set(), // 这一天去看过的提示
    moveSeq: 0,
  };
}

/** 这个人现在在哪个点位旁边能做这件事 */
function spotsFor(s, role, test) {
  const out = [];
  for (const sp of C.map.spots) {
    const z = zoneOf.get(sp.zone);
    if (z.owner && z.owner !== role) continue;
    if (G("worldSceneLock")(s, C, sceneOf.get(sp.scene), role)) continue;
    if (MENU) {
      // 点位菜单：每一件都看一眼（真人看得见那排小牌子）
      for (const id of sp.actions) {
        const act = G("worldPickAction")(s, C, role, sp, id).act;
        if (!act || act.id !== id || G("worldCanAct")(s, C, role, sp.id, true, id)) continue;
        if (test(act, sp)) out.push({ spot: sp, act });
      }
      continue;
    }
    const act = G("worldPickAction")(s, C, role, sp).act;
    if (!act || G("worldCanAct")(s, C, role, sp.id, true)) continue;
    if (test(act, sp)) out.push({ spot: sp, act });
  }
  return out;
}

function nearest(list, a) {
  let best = null, bd = Infinity;
  for (const o of list) {
    const d = Math.abs(o.spot.at[0] - a.x) + (o.spot.at[1] === a.y ? 0 : 3000);
    if (d < bd) { bd = d; best = o; }
  }
  return best;
}

/** 这一段打算干什么。careful 的人是一个认真玩、照着纸带走的人；casual 的人随便过 */
function decide(s, P, partnerPlan) {
  const role = P.role, w = s.world, p = s.persons[role], a = w.actors[role];
  const age = G("lifeTimeAt")(s.turn).age;
  // 1. 纸带上的下一件事：在这一段就去那张图
  const ids = [w.fate.mirror, w.fate[role]].filter(Boolean);
  for (const id of ids) {
    const st = storyOf(id);
    if (!st || w.done.includes(id)) continue;
    if (SLOTS.indexOf(st.slot) === w.slot && (PERSONA === "careful" || rand() < 0.6)) {
      if (sceneAt(a.y).id === st.scene) return { pass: true, why: "story-wait", scene: st.scene };
      const sc = sceneOf.get(st.scene);
      const tgt = C.map.spots.find((sp) => sp.scene === st.scene && !zoneOf.get(sp.zone).owner) || { at: [sc.width / 2, sc.floors[sc.floors.length - 1]] };
      return { walkTo: tgt.at, why: "story", scene: st.scene };
    }
  }
  // 2. 日程
  const d = G("worldDutyOpen")(s, C, role);
  if (d && w.slot >= G("worldDutySlots")(d)[0]) {
    const sp = C.map.spots.find((x) => x.id === d.spot);
    return { spot: sp, act: { id: "duty", label: d.label }, why: "duty" };
  }
  // 2.5 地图上飘着的提示（命运今天准备的事，走近了才知道是什么）：认真的人会过去看看，一段只去一回
  if (PERSONA === "careful" || rand() < 0.3) {
    for (const id of [w.fate.mirror, w.fate[role]]) {
      if (!id || w.done.includes(id) || storyOf(id)) continue;
      const fe = evOf(id);
      if (!fe.where || !fe.hint || P.tried.has(id + ":" + w.slot)) continue;
      const z = zoneOf.get(fe.where);
      if (z.owner && z.owner !== role) continue;
      if (G("worldSceneLock")(s, C, sceneOf.get(z.scene), role)) continue;
      if (fe.when && !(fe.when[0] < G("SLOTS")[w.slot][1] && fe.when[1] > G("SLOTS")[w.slot][0])) continue;
      P.tried.add(id + ":" + w.slot);
      const sc = sceneOf.get(z.scene);
      return { walkTo: [z.span[0] + (z.span[1] - z.span[0]) / 2, sc.floors[z.floor]], why: "hint", scene: z.id, linger: true };
    }
  }
  // 3. 过日子
  const quick = (id) => nearest(spotsFor(s, role, (act) => act.id === id), a);
  if (p.needs.hunger < 45) { const o = quick("eat") || quick("eat_out"); if (o) return { ...o, why: "eat", quick: true }; }
  if (w.slot === 4 || (p.needs.energy < 15 && !process.env.NIGHT_ONLY)) {
    const o = nearest(spotsFor(s, role, (act) => act.sleep), a);
    if (o) return { ...o, why: "sleep" };
  }
  // 4. 空下来的时间
  const free = spotsFor(s, role, (act) => !act.duty && !act.sleep && !act.quick && act.money >= -Math.max(0, p.money));
  if (!free.length) return { pass: true, why: "nothing" };
  if (PERSONA === "casual" && rand() < 0.35) return { pass: true, why: "lazy" };
  // 对门定了的事，能一起就一起（真人会看对门的牌子）
  if (partnerPlan && partnerPlan.spot && !partnerPlan.quick) {
    const same = free.find((o) => o.act.id === partnerPlan.act.id && (o.spot.id === partnerPlan.spot.id || !zoneOf.get(o.spot.zone).owner));
    if (same && (PERSONA === "careful" ? rand() < 0.8 : rand() < 0.4)) return { ...same, why: "together" };
  }
  if (PERSONA === "casual") return { ...pick(free), why: "random" };
  // 纸带上还没够着的最低那条线看亲近（退休、七十）：认真的人去找对门一块儿做事（真人会约）
  const gl = G("lifeGoal")(s, C, role);
  const low = gl && gl.lines.filter((l) => !l.ok).sort((x, y) => (x.need - x.have) / Math.max(1, x.need) - (y.need - y.have) / Math.max(1, y.need))[0]; // 和纸带一个算法（goal_panel.target_line）：差得最少的那条
  if (low && low.by === "亲近") {
    const tog = free.filter((o) => o.act.together && !w.done.includes("together:" + o.act.id)); // 同一件事搭伴一天只算一回，换着做
    if (tog.length && rand() < 0.75) return { ...(partnerPlan && tog.find((o) => o.act.id === partnerPlan.act?.id)) || nearest(tog, a), why: "together" };
  }
  // 看积蓄的线（安家、四十五、退休、七十）：挑挣钱最多的活儿
  if (low && low.by === "积蓄") {
    const earn = free.filter((o) => o.act.money > 0).sort((x, y) => y.act.money - x.act.money);
    if (earn.length && rand() < 0.75) return { ...earn[0], why: "earn" };
  }
  // 认真的人：心情差了先玩，不然朝下一个关口使劲（心智/体魄/魅力里最弱的那项），偶尔换换花样
  if (p.needs.mood < 40) {
    const fun = free.filter((o) => (o.act.needs.mood || 0) >= 8);
    if (fun.length) return { ...nearest(fun, a), why: "fun" };
  }
  // 盯着纸带上那条线练（和影子一个算法：还没够着的线里最低的那条，都够着了就最高的那条）。
  // 原来读的 goal.stat 在 GoalView 上不存在，「认真的人」其实是三项轮着练（11-11 玩法总把关查出来的）
  let want = G("worldShadowNeed")(s, C, role) || ["mind", "body", "charm"][s.turn % 3];
  if (KIDS === "none" && want.startsWith("kid_")) want = ["mind", "charm"][s.turn % 2]; // 不押孩子：顾自己的四十五（心智和魅力）
  // 孩子的关口是纸带上最近的那道（kid_mind 这样的键）：认真的人带孩子去长那一项（docs/FAMILY.md）
  const by = (act) => (want.startsWith("kid_") ? (act.kid && act.kid[want.slice(4)]) || 0 : act.stats[want] || 0);
  const grow = free.filter((o) => by(o.act) > 0).sort((x, y) => by(y.act) - by(x.act));
  if (grow.length && rand() < 0.75) return { ...grow[0], why: "grow:" + want };
  return { ...pick(free), why: "variety" };
}

// ---------- 一世 ----------

function playLife(seed) {
  rngState = seed * 7919 + 13;
  const env = fakeNakama();
  const qa = { userId: "u-qing", sessionId: "s-qing", username: "qing" };
  const ma = { userId: "u-mei", sessionId: "s-mei", username: "mei" };
  const made = env.rpc("rpcLifelineCreate", qa.userId, { name: "小青" });
  env.rpc("rpcLifelineJoin", ma.userId, { code: made.code, name: "小梅" });
  const open = env.rpc("rpcLifelineOpen", qa.userId, { lifelineId: made.lifelineId });
  const R = room(env.nk, open.matchId);
  R.join([qa, ma]);
  R.state.record.life.rng = seed >>> 0 || 1; // 每一世不同的种子，可复现
  const players = { qing: makePlayer("qing", qa), mei: makePlayer("mei", ma) };

  const rep = {
    seed, persona: PERSONA, ticks: 0, days: [], story: [], errors: {}, stalls: [], events: { story: 0, milestone: 0, mirror: 0, solo: 0, check: 0 },
    firstHour: null, gapMax: { sec: 0 }, gaps: [], hintMismatch: [], chapters: {}, together: 0, forced: 0, end: null, families: {},
  };
  const seconds = () => rep.ticks / TICK;
  rep.kids = {};
  const step = (msgs = []) => {
    const L = R.state.record.life;
    if (KIDS && L && L.phase === "life" && G("lifeTimeAt")(L.turn).age >= 28 && !L.persons.qing.flags.includes("has_kid")) {
      for (const r of ["qing", "mei"]) G("lifeAddFlags")(L.persons[r], ["has_kid"]);
      G("kidSync")(L, C);
    }
    // 四十五「去争那个位子」、孩子高考那条高线：关口一开就记下够不够得着（不算发挥）
    const pe = L && L.world && L.world.event;
    if (KIDS && pe && (pe.eventId === "m_midlife" || pe.eventId === "mk_gaokao") && !rep.kids[pe.eventId]) {
      const ev = evOf(pe.eventId), line = ev.options.find((o) => o.id === (pe.eventId === "m_midlife" ? "post" : "top"));
      G("lifeKidBind")(L);
      rep.kids[pe.eventId] = {};
      for (const r of pe.roles) rep.kids[pe.eventId][r] = !G("lifeOptionLock")(ev, line, L.persons[r], 0, G("lifePairBond")(L, r));
    }
    R.sent.length = 0;
    const ok = R.loop(msgs);
    rep.ticks++;
    for (const m of R.sent) {
      if (m.op === OP.ERROR) {
        const who = m.to ? Object.values(players).find((P) => m.to.includes(P.presence.sessionId)) : null;
        const key = `${who ? who.role : "all"}: ${m.data.message}`;
        rep.errors[key] = (rep.errors[key] || 0) + 1;
      }
      if (m.op === OP.LOG) for (const e of m.data.entries || []) if (e.type === "together" || e.kind === "together") rep.together++;
    }
    return ok;
  };

  // 投胎：两个人各看八秒，梅重抽一次
  for (let i = 0; i < THINK.roll * TICK; i++) step();
  step([R.msg(ma, OP.ROLL, { reroll: true })]);
  for (let i = 0; i < 3 * TICK; i++) step();
  step([R.msg(qa, OP.ROLL, { confirm: true }), R.msg(ma, OP.ROLL, { confirm: true })]);
  const life0 = R.life();
  assert.equal(life0.phase, "life", "两个人都定了应该开始过日子");
  for (const r of ["qing", "mei"]) rep.families[r] = life0.persons[r].familyId + "/" + life0.persons[r].talentId;

  let lastTurn = -1, dayStart = 0, daySlots = [], lastSlot = -1, slotStart = 0, lastEventAt = 0;
  let curEvent = null, eventSince = 0, dayStory = [], prevEnergy = 0;
  const MAX_TICKS = 6 * 3600 * TICK; // 六个钟头还没完就算卡住了
  while (rep.ticks < MAX_TICKS) {
    const s = R.life();
    if (s.phase === "ended") break;
    const w = s.world;
    const t = G("lifeTimeAt")(s.turn);
    // 新的一天
    if (s.turn !== lastTurn) {
      if (lastTurn >= 0 && lastSlot >= 0) daySlots.push(curSlotRec());
      if (lastTurn >= 0) rep.days.push({ ...(SNAP ? { snap: snapGoals(s) } : {}), turn: lastTurn, endEnergy: prevEnergy, sec: seconds() - dayStart, slots: daySlots, storyMiss: dayStory.filter((id) => !rep.story.some((x) => x.id === id && x.turn === lastTurn)) });
      dayStory = [w.fate.mirror, w.fate.qing, w.fate.mei].filter((id) => id && storyOf(id));
      lastTurn = s.turn; dayStart = seconds(); daySlots = []; lastSlot = -1;
      for (const P of Object.values(players)) { P.wait = THINK.dayEnd * TICK; P.plan = null; P.tried.clear(); }
      const ch = G("storyChapterAt")(C, t.age);
      rep.chapters[ch] = rep.chapters[ch] || { sec: 0, days: 0, from: t.age };
      rep.chapters[ch].days++;
      // 掉线：影子替梅过几天
      if (AWAY.length === 2) {
        if (s.turn === AWAY[0] && players.mei.online) { R.leave([ma]); players.mei.online = false; }
        if (s.turn === AWAY[1] && !players.mei.online) { R.join([ma]); players.mei.online = true; }
      }
    }
    if (s.persons.qing.alive) { const aq = w.actors.qing; if (aq && !aq.asleep) prevEnergy = s.persons.qing.needs.energy; }
    if (w.slot !== lastSlot) {
      if (lastSlot >= 0) daySlots.push(curSlotRec());
      lastSlot = w.slot; slotStart = seconds();
      for (const P of Object.values(players)) { P.plan = null; P.wait = Math.max(P.wait, THINK.slot * TICK); }
    }
    function curSlotRec() {
      const ss = R.life();
      return { slot: lastSlot, sec: seconds() - slotStart, did: Object.fromEntries(Object.values(players).map((P) => [P.role, (P.did || "?") + (process.env.DEBUG ? "(" + ["hunger", "energy", "mood", "clean"].map((k) => Math.round(ss.persons[P.role].needs[k])).join("/") + ")" : "")])) };
    }
    // 卡死：一段五分钟还没过去
    if (seconds() - slotStart > 300 && !rep.stalls.some((x) => x.turn === s.turn && x.slot === w.slot)) {
      rep.stalls.push({ turn: s.turn, age: t.age, slot: w.slot, ready: G("worldReadyView")(s), event: w.event && w.event.eventId, actors: JSON.parse(JSON.stringify(w.actors)), plans: Object.fromEntries(Object.values(players).map((P) => [P.role, P.plan && P.plan.why])) });
    }

    const msgs = [];
    // 事件
    if (w.event) {
      const pe = w.event;
      if (curEvent !== pe) {
        curEvent = pe; eventSince = seconds();
        const ev = evOf(pe.eventId);
        const st = storyOf(pe.eventId);
        const kind = pe.kind === "milestone" ? "milestone" : st ? "story" : pe.kind;
        rep.events[kind] = (rep.events[kind] || 0) + 1;
        const gap = seconds() - lastEventAt;
        if (gap > rep.gapMax.sec) rep.gapMax = { sec: Math.round(gap), turn: s.turn, age: t.age };
        if (gap > 180) rep.gaps.push({ sec: Math.round(gap), age: t.age });
        lastEventAt = seconds();
        if (st) {
          const forced = !!pe.forced; // 硬塞的：被叫醒、撤下手上的事、被挪过去（人本来就在那儿的躲不过的不算）
          if (forced) rep.forced++;
          rep.story.push({ id: pe.eventId, chapter: st.chapter, beat: st.beat, turn: s.turn, age: t.age, slot: SLOT_ZH[w.slot], want: SLOT_ZH[SLOTS.indexOf(st.slot)], forced, atSec: Math.round(seconds()) });
        }
        const len = (ev.text || "").length + (ev.options || []).reduce((n, o) => n + (o.text || "").length, 0);
        for (const r of pe.roles) players[r].wait = Math.round((pe.kind === "milestone" ? THINK.milestone : THINK.event + len * THINK.perChar) * TICK);
      }
      for (const r of pe.roles) {
        const P = players[r];
        if (!P.online || pe.choices[r]) continue;
        if (P.wait > 0) { P.wait--; continue; }
        const ev = evOf(pe.eventId);
        const locks = (G("lifeMilestoneLocks")(s, C) || {})[r] || {};
        const my = s.persons[r];
        const ok = ev.options.filter((o) => {
          if (locks[o.id]) return false;
          const rq = o.requires || {};
          if (rq.flags && !rq.flags.every((f) => my.flags.includes(f))) return false;
          if (rq.notFlags && rq.notFlags.some((f) => my.flags.includes(f))) return false;
          if (o.cost && my.money < o.cost) return false;
          return true;
        });
        // 默契事件：认真的两个人六成选到一块儿（先选第一个能选的）
        const o = PERSONA === "careful" && rand() < 0.6 ? ok[0] : pick(ok.length ? ok : ev.options);
        msgs.push(R.msg(P.presence, OP.CHOOSE, { optionId: o.id }));
        P.wait = 2 * TICK; // 看结算
      }
      if (seconds() - eventSince > 120 && !rep.stalls.some((x) => x.event === pe.eventId && x.turn === s.turn)) {
        rep.stalls.push({ turn: s.turn, age: t.age, slot: w.slot, event: pe.eventId, roles: pe.roles, choices: { ...pe.choices }, why: "event stuck" });
      }
      step(msgs);
      continue;
    }
    curEvent = null;
    if (w.playing) { step(); continue; }

    for (const P of Object.values(players)) {
      const r = P.role, a = w.actors[r];
      if (!P.online || !a || !s.persons[r].alive) continue;
      if (G("worldReady")(s, r)) continue;
      if (P.wait > 0) { P.wait--; continue; }
      if (!P.plan) {
        const other = players[r === "qing" ? "mei" : "qing"];
        P.plan = decide(s, P, other.plan);
        P.did = P.plan.why;
      }
      const plan = P.plan;
      // 先走到地方
      const target = plan.spot ? plan.spot.at : plan.walkTo;
      if (target) {
        const rt = route(s, r, a.x, a.y, target[0], target[1]);
        if (!rt) { if (process.env.DEBUG) console.log("no-route", r, t.age, w.slot, plan.why, plan.spot ? plan.spot.id : plan.scene); P.plan = { pass: true, why: "no-route:" + (plan.spot ? plan.spot.id : plan.scene) }; P.did = P.plan.why; continue; }
        if (Math.abs(a.x - rt.x) > 4) {
          const nx = a.x + Math.sign(rt.x - a.x) * Math.min(WALK / TICK, Math.abs(rt.x - a.x));
          msgs.push(R.msg(P.presence, OP.MOVE, { x: nx, y: a.y, seq: ++P.moveSeq }));
          continue;
        }
        if (rt.exit) { msgs.push(R.msg(P.presence, OP.EXIT, { exit: rt.exit.id, seq: P.moveSeq })); P.wait = 3; continue; }
        // 走到了
        if (plan.walkTo && plan.linger) { P.plan = null; P.wait = 3 * TICK; continue; } // 站一会儿，没事就接着干别的
        if (plan.walkTo) { P.plan = { pass: true, why: plan.why + "-arrived" }; P.wait = 5; continue; }
        // 客户端在按钮上写着做不了的原因（比如过了两趟桥，「路上把这一段花掉了」），真人不会再按：这一段歇着
        if (!plan.sent && G("worldCanAct")(s, C, r, plan.spot.id, false, MENU && plan.act ? plan.act.id : undefined)) { P.plan = { pass: true, why: plan.why + "-greyed" }; P.did = P.plan.why; continue; }
        if (ONCE && plan.sent && !plan.quick) {
          // 一回做完了（did 的序号变了）：看一眼结果、钟拨过去，再按一回；三成的时候换一件事
          if (((a.did && a.did.n) || 0) > plan.didN) { P.plan = rand() < 0.3 ? null : { ...plan, sent: false }; P.wait = Math.round(THINK.once * TICK); continue; }
          P.plan = { pass: true, why: plan.why + "-failed" }; P.did = P.plan.why; continue;
        }
        const body = ONCE ? { spot: plan.spot.id, once: true } : { spot: plan.spot.id };
        if (MENU && plan.act) body.action = plan.act.id;
        msgs.push(R.msg(P.presence, OP.ACT, body));
        if (plan.quick) { P.plan = null; P.wait = THINK.quick * TICK; } else { P.wait = 5; P.plan = { ...plan, sent: true, didN: (a.did && a.did.n) || 0 }; }
        if (plan.sent && !ONCE) { P.plan = { pass: true, why: plan.why + "-failed" }; } // 做不了：歇着
        continue;
      }
      if (plan.pass) { msgs.push(R.msg(P.presence, OP.PASS, {})); P.wait = 5; }
    }
    if (!step(msgs)) { rep.end = { error: "room closed", log: logger.lines.slice(-5) }; break; }
    // 第一个钟头
    if (!rep.firstHour && seconds() >= 3600) {
      const st = R.life();
      rep.firstHour = { age: G("lifeTimeAt")(st.turn).label, turn: st.turn, story: rep.story.length, events: { ...rep.events } };
    }
  }
  const s = R.life();
  if (lastTurn >= 0) rep.days.push({ ...(SNAP ? { snap: snapGoals(s) } : {}), turn: lastTurn, sec: seconds() - dayStart, slots: daySlots });
  rep.end = rep.end || { phase: s.phase, died: s.persons && Object.fromEntries(["qing", "mei"].map((r) => [r, s.persons[r].diedAtAge])), ending: s.ending && s.ending.pair, turns: s.turn };
  // 章耗时
  for (const d of rep.days) {
    const ch = G("storyChapterAt")(C, G("lifeTimeAt")(d.turn).age);
    rep.chapters[ch].sec += d.sec;
  }
  rep.misses = rep.days.filter((d) => d.storyMiss && d.storyMiss.length).map((d) => ({ turn: d.turn, age: G("lifeTimeAt")(d.turn).label, miss: d.storyMiss.map((id) => id + "@" + storyOf(id).slot + "/" + storyOf(id).scene + "/" + storyOf(id).kind), slots: d.slots.map((x) => SLOT_ZH[x.slot] + ":" + x.did.qing + "|" + x.did.mei).join("  ") }));
  rep.faults = logger.lines.filter((l) => l[0] === "error").map((l) => l[1]).slice(0, 10);
  // 每道关两个人的分（比较按法、调数时看成长总量有没有跑偏）
  rep.gates = (s.log || []).filter((e) => e.kind === "milestone" && e.results).map((e) => ({ age: e.age, qing: e.results.qing ? e.results.qing.score : null, mei: e.results.mei ? e.results.mei.score : null }));
  // 「再来一世」：两个人都点，换成新的一世的投胎
  if (s.phase === "ended") {
    step([R.msg(qa, OP.AGAIN, { yes: true }), R.msg(ma, OP.AGAIN, { yes: true })]);
    step();
    rep.again = R.life().phase;
  }
  return rep;
}

// ---------- 报告 ----------

const fmt = (sec) => `${Math.floor(sec / 60)}′${String(Math.round(sec % 60)).padStart(2, "0")}″`;
const all = [];
for (let i = 0; i < LIVES; i++) {
  const t0 = Date.now();
  const rep = playLife(SEED0 + i);
  rep.wall = (Date.now() - t0) / 1000;
  all.push(rep);
  if (QUIET) continue;
  const total = rep.ticks / TICK;
  console.log(`\n=== 第 ${i + 1} 世（seed ${rep.seed}，${rep.persona}）：现实 ${fmt(total)}，${rep.days.length} 个日子，结局 ${JSON.stringify(rep.end)}，再来一世 → ${rep.again}`);
  console.log(`  人家：青 ${rep.families.qing}  梅 ${rep.families.mei}`);
  console.log(`  事件：${JSON.stringify(rep.events)}  搭伴 ${rep.together} 回  主线 ${rep.story.length}/21 件（章末硬塞的 ${rep.forced} 件）`);
  if (rep.firstHour) console.log(`  第一个钟头：过到 ${rep.firstHour.age}（第 ${rep.firstHour.turn} 个日子），主线 ${rep.firstHour.story} 件，事件 ${JSON.stringify(rep.firstHour.events)}`);
  for (const [ch, v] of Object.entries(rep.chapters)) console.log(`  第 ${ch} 章：${v.days} 个日子，${fmt(v.sec)}（一天 ${fmt(v.sec / v.days)}）`);
  const idle = rep.days.flatMap((d) => d.slots.flatMap((x) => Object.values(x.did))).reduce((m, k) => { const kk = String(k).split(":")[0]; m[kk] = (m[kk] || 0) + 1; return m; }, {});
  console.log(`  两件事之间最久 ${fmt(rep.gapMax.sec)}（${rep.gapMax.age} 岁）；超过三分钟没事的 ${rep.gaps.length} 回 ${rep.gaps.slice(0, 8).map((g) => g.age + "岁" + fmt(g.sec)).join(" ")}`);
  const lens = rep.days.map((d) => d.slots.length);
  const hist = [1, 2, 3, 4, 5].map((n) => lens.filter((x) => x === n).length);
  const byStage = {};
  rep.days.forEach((d, i) => { const st = G("lifeTimeAt")(d.turn).stage; (byStage[st] = byStage[st] || []).push(lens[i]); });
  console.log(`  各阶段平均一天几段：${Object.entries(byStage).map(([k, v]) => k + " " + (v.reduce((a, b) => a + b, 0) / v.length).toFixed(1)).join("  ")}`);
  console.log(`  一天过了几段（1~5 段的日子数）：${hist.join(" / ")}；睡前的精力平均 ${Math.round(rep.days.reduce((n, d) => n + (d.endEnergy ?? 0), 0) / rep.days.length)}`);
  console.log(`  每段干了什么：${JSON.stringify(idle)}`);
  for (const st of rep.story) console.log(`    ${st.chapter}-${st.beat} ${st.id.padEnd(18)} ${String(st.age).padStart(2)} 岁 ${st.slot}${st.slot !== st.want ? `（写的是${st.want}）` : ""}${st.forced ? " · 章末硬塞" : ""}  @${fmt(st.atSec)}`);
  if (process.env.DEBUG) for (const m of rep.misses) console.log("  排上了没碰上", m.age, m.miss.join(","), "\n      ", m.slots);
  if (Object.keys(rep.errors).length) console.log(`  服务器回的错：${JSON.stringify(rep.errors)}`);
  if (rep.stalls.length) console.log(`  卡住：${JSON.stringify(rep.stalls).slice(0, 1500)}`);
  if (rep.faults.length) console.log(`  房间报错：${rep.faults.join(" | ")}`);
  console.log(`  （跑了 ${rep.wall.toFixed(1)} 秒）`);
}
if (JSON_OUT) writeFileSync(JSON_OUT, JSON.stringify(all, null, 1));
const avg = all.reduce((n, r) => n + r.ticks / TICK, 0) / all.length;
console.log(`\n${all.length} 世，平均现实 ${fmt(avg)}；卡住 ${all.reduce((n, r) => n + r.stalls.length, 0)} 回；主线平均 ${(all.reduce((n, r) => n + r.story.length, 0) / all.length).toFixed(1)}/21`);
if (CHECK) {
  const bad = [];
  for (const r of all) {
    if (r.stalls.length) bad.push(`seed ${r.seed} 卡住 ${r.stalls.length} 回：${JSON.stringify(r.stalls[0]).slice(0, 300)}`);
    if (Object.keys(r.errors).length) bad.push(`seed ${r.seed} 服务器回错：${JSON.stringify(r.errors)}`);
    if (r.faults.length) bad.push(`seed ${r.seed} 房间报错：${r.faults[0]}`);
    if (r.end.phase !== "ended") bad.push(`seed ${r.seed} 没走完：${JSON.stringify(r.end)}`);
    const beats = new Set(r.story.map((x) => x.chapter + "-" + x.beat));
    // 人走得早，排在那之后的主线（第七章 70 岁傍晚的长椅）本来就过不到：只数两个人里后走的那个还活着时排得上的
    const lastAge = r.end.died ? Math.max(...Object.values(r.end.died)) : 999;
    let want = 0;
    C.story.chapters.forEach((ch, i) => {
      const n = G("storyBeats")(C, i + 1).length;
      for (let k = 0; k < n; k++) if (G("lifeTimeAt")(G("storyOpenTurn")(C, ch, k, n)).age <= lastAge) want++;
    });
    if (beats.size < want) bad.push(`seed ${r.seed} 主线只走了 ${beats.size}/${want} 件（后走的那个活到 ${lastAge}）`);
    if (r.again !== "roll") bad.push(`seed ${r.seed} 再来一世没进投胎：${r.again}`);
  }
  if (bad.length) { console.error("✗ 通关：\n  " + bad.join("\n  ")); process.exit(1); }
  console.log(`✓ 通关：${all.length} 世从配对玩到结局再到下一世投胎，没卡住、没报错，主线 21 件都走到`);
}
