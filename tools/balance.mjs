#!/usr/bin/env node
// 平衡模拟：用几种「像人」的机器人在河畔里真实地过完很多条人生（走世界规则，不是只结算事件），
// 把成长曲线、投胎强度、寿命、结局和成就的分布打出来。改了数值以后跑一遍，看有没有哪户人家、哪种天赋、
// 哪种活法明显占便宜。
//
//   npm run balance                 # 默认 1200 条人生，打印报告
//   npm run balance -- --lives 4000 # 多跑一些
//   npm run balance -- --json out.json   # 把原始统计写出来（docs/GROWTH.md 里的图表用）
//   npm run balance -- --chain 4    # 四世一串地连着过（带着上一世的传承投胎）：看隔世的事、街坊记住的事、藏着的天赋
//   npm run balance -- --marks      # 当作「三件事都出过」的人生线：藏着的天赋从头一世就抽得到，用来和别的天赋比强度
//
// 机器人是「活法」的原型，不是最优解：
//   bookworm 书虫：有空就写作业      wild 野孩子：有空就在外面玩
//   earner 小财迷：够岁数了就去修车   drifter 随缘：什么都干一点    homebody 宅：吃了睡，睡了吃
// 两个人的相处方式也分三种：glued 形影不离 / casual 碰上了就一起 / apart 各过各的
import { readFileSync, writeFileSync } from "node:fs";
import vm from "node:vm";

const args = process.argv.slice(2);
const arg = (name, dflt) => { const i = args.indexOf("--" + name); return i >= 0 ? args[i + 1] : dflt; };
const LIVES = Number(arg("lives", 1200));
const JSON_OUT = arg("json", null);
const QUIET = args.includes("--quiet");
const TRACE = arg("trace", null);
const CHAIN = Math.max(1, Number(arg("chain", 1)));
const MARKS = args.includes("--marks");
const traceLog = [];

// --build <路径>：换一份编译好的规则来跑（比如拿改之前的分支做对照）
const BUILD = arg("build", null);
const code = readFileSync(BUILD ?? new URL("../server/build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math, Date });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);
const C = G("CONTENT");
const has = (name) => vm.runInContext(`typeof ${name} !== "undefined"`, ctx);

const ROLES = ["qing", "mei"];
const STATS = ["body", "mind", "charm", "luck"];
const STAT_CN = { body: "体魄", mind: "心智", charm: "魅力", luck: "运气" };
const STAGES = ["childhood", "teen", "young", "middle", "old"];
const STAGE_CN = { childhood: "童年", teen: "少年", young: "青年", middle: "中年", old: "老年" };
const BOTS = ["bookworm", "wild", "earner", "drifter", "homebody"];
const BOT_CN = { bookworm: "书虫", wild: "野孩子", earner: "小财迷", drifter: "随缘", homebody: "宅" };
const PAIRINGS = ["glued", "casual", "apart"];
const PAIR_CN = { glued: "形影不离", casual: "碰上就一起", apart: "各过各的" };

const lifeCreate = G("lifeCreate"), lifeConfirm = G("lifeConfirm"), lifeReroll = G("lifeReroll"), lifeTimeAt = G("lifeTimeAt");
const worldAdvance = G("worldAdvance"), worldAct = G("worldAct"), worldChoose = G("worldChoose"), worldCanAct = G("worldCanAct");
const lifeShadowChoose = G("lifeShadowChoose");

// 独立于存档的随机数（机器人的随机不应该影响游戏内的随机序列的可复现性，但两者都要可复现）
function rng(seed) {
  let a = seed | 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const zoneOf = new Map(C.map.zones.map((z) => [z.id, z]));
const eventOf = new Map(C.events.map((e) => [e.id, e]));
// 主线（content/story.yaml）写的是哪张图、哪一段，不是地点和钟点：折成那张图上第一块公共地方、那一段的钟点，机器人照样去等
for (const e of C.story?.events || []) {
  const z = C.map.zones.find((zz) => zz.scene === e.scene && !zz.owner) || C.map.zones.find((zz) => zz.scene === e.scene);
  const sl = G("SLOTS")[["morning", "am", "pm", "evening", "night"].indexOf(e.slot)];
  eventOf.set(e.id, { ...e, where: z.id, when: [sl[0], sl[1]] });
}
// 一个点位上挂着几件事，按年纪取第一件合适的（world.ts → worldPickAction），所以要带着存档去问「现在这儿能做什么」
const worldPickAction = G("worldPickAction"), worldDutyOpen = G("worldDutyOpen"), lifeOptionLock = G("lifeOptionLock");
// 机器人想做的事是按「哪一类」说的：念书在小时候是翻小人书、长大了是看书；河边小时候放风筝、大了是走一圈
const KIN = { study: ["study", "picture_book", "read"], play_river: ["play_river", "walk_river", "ball"], play_alley: ["play_alley", "chat"] };
const spotFor = (s, action, role) => {
  const ids = KIN[action] || [action];
  let any = null;
  for (const sp of C.map.spots) {
    const act = worldPickAction(s, C, role, sp).act;
    if (!act || !ids.includes(act.id)) continue;
    const z = zoneOf.get(sp.zone);
    if (z.owner === role) return sp;
    if (!z.owner && !any) any = sp;
  }
  return any;
};
const PLAY = ["play_roof", "play_river", "play_alley"];
const center = (zone) => { const r = zoneOf.get(zone).rect; return [r[0] + r[2] / 2, r[1] + r[3] / 2]; };

function tryAct(s, role, action) {
  const sp = spotFor(s, action, role);
  if (!sp) return false;
  const a = s.world.actors[role];
  const [ox, oy] = [a.x, a.y];
  a.x = sp.at[0]; a.y = sp.at[1];
  if (worldAct(s, C, role, sp.id).error) { a.x = ox; a.y = oy; return false; }
  return true;
}

// 一天五段（world.ts 的 SLOTS）：走路不花时间，机器人每段定一件事；顺手的事（吃、洗、敲门）做完接着定
const worldOverlaps = G("worldOverlaps"), worldDutySlots = G("worldDutySlots"), worldReady = G("worldReady"), worldPass = G("worldPass");

/** 机器人在空闲时决定做什么。返回 true 表示开始了一个行动（或原地等事件） */
function botStep(s, role, bot, pairing, R, day) {
  const w = s.world, p = s.persons[role], a = w.actors[role];
  const age = lifeTimeAt(s.turn).age;
  const other = role === "qing" ? "mei" : "qing";
  const b = w.actors[other];

  // 命运：今天打算去的话，到了那一段就去那个地方等着（对门这一段已经定了别处就不等了）
  if (day.attendMirror && w.fate.mirror && !w.done.includes(w.fate.mirror) && b && !b.asleep && !worldReady(s, other)) {
    const ev = eventOf.get(w.fate.mirror);
    if (worldOverlaps(ev.when, w.slot) && !day.waited[role + w.slot]) {
      [a.x, a.y] = center(ev.where);
      day.waited[role + w.slot] = true;
      return true; // 站着等对方
    }
  }
  const mine = w.fate[role];
  if (day.attendSolo[role] && mine && !w.done.includes(mine)) {
    const ev = eventOf.get(mine);
    if (ev.where && worldOverlaps(ev.when, w.slot) && !day.waited["s" + role + w.slot]) {
      [a.x, a.y] = center(ev.where);
      day.waited["s" + role + w.slot] = true;
      return true;
    }
  }

  if (p.needs.hunger < 45) {
    if (w.slot <= 1 && p.money >= 2 && R() < 0.4 && tryAct(s, role, "eat_out")) return true;
    if (tryAct(s, role, "eat")) return true;
  }
  // 宅的人晚上那一段直接睡；今天打算去的事还在后面几段，就先不睡
  const pending = [day.attendMirror ? w.fate.mirror : null, day.attendSolo[role] ? w.fate[role] : null]
    .filter((id) => id && !w.done.includes(id)).map((id) => eventOf.get(id)).filter((ev) => ev.where && ev.when && ev.when[1] > G("SLOTS")[w.slot][1]);
  const bedtime = bot === "homebody" && !pending.length ? 4 : 99;
  if (p.needs.energy < 12 || w.slot >= bedtime) { if (tryAct(s, role, "sleep")) return true; }
  // 今天该去的地方（上学、上班、出摊，跟着人生路线走）：到了那一段就去，野孩子和小财迷小时候偶尔逃学
  const duty = worldDutyOpen(s, C, role);
  if (duty && w.slot >= worldDutySlots(duty)[0]) {
    const truant = age > 17 ? 0 : bot === "wild" ? 0.25 : bot === "earner" ? 0.15 : 0.03;
    if (!day.truant[role] && R() < truant) day.truant[role] = true;
    if (!day.truant[role] && tryAct(s, role, "duty")) return true;
  }
  if (p.needs.clean < 30 && tryAct(s, role, "wash")) return true;

  // 相处：形影不离的会凑过去做同一件事
  if (b && b.action && pairing !== "apart") {
    const act = C.map.actions.find((x) => x.id === b.action);
    if (act && act.together && !act.duty && !w.done.includes("together:" + act.id) && R() < (pairing === "glued" ? 0.9 : 0.35)) {
      if (tryAct(s, role, act.id)) return true;
    }
  }
  if (pairing === "glued" && !w.done.includes("together:knock") && R() < 0.5 && tryAct(s, role, "knock")) return true;

  // 活法
  const r = R();
  let want;
  if (bot === "bookworm") want = r < 0.75 ? "study" : r < 0.9 ? PLAY[Math.floor(R() * 3)] : "knock";
  else if (bot === "wild") want = r < 0.85 ? PLAY[Math.floor(R() * 3)] : r < 0.93 ? "knock" : "study";
  else if (bot === "earner") want = r < 0.65 ? "work" : r < 0.85 ? PLAY[Math.floor(R() * 3)] : "study";
  else if (bot === "homebody") want = r < 0.35 ? "knock" : r < 0.55 ? "study" : r < 0.7 ? "wash" : "eat";
  else want = r < 0.3 ? "study" : r < 0.7 ? PLAY[Math.floor(R() * 3)] : r < 0.85 ? "work" : "knock";
  if (tryAct(s, role, want)) return true;
  if (tryAct(s, role, PLAY[Math.floor(R() * 3)])) return true;
  if (tryAct(s, role, "knock")) return true;
  return !worldPass(s, C, role); // 实在没事做：这一段歇着
}

/** 选项：agree 的概率下跟对方选一样（默契好的两个人），否则按性格（和影子一样）或乱选 */
function botChoose(s, role, ev, style, R) {
  if (style === "steady") return lifeShadowChoose(s, C, role, ev.id);
  // 人生关口上够不着的路选不了
  const swing = (s.world.event && s.world.event.swing && s.world.event.swing[role]) || 0;
  const open = ev.kind === "milestone" ? ev.options.filter((o) => !lifeOptionLock(ev, o, s.persons[role], swing, G("lifePairBond")(s, role))) : ev.options;
  return open[Math.floor(R() * open.length)].id;
}

function simulate(seed, cfg) {
  const R = rng(seed ^ 0x9e3779b9);
  const s = lifeCreate(seed, C, cfg.legacy);
  for (const r of ROLES) for (let i = 0; i < cfg.rerolls[r]; i++) lifeReroll(s, C, r);
  const rolls = JSON.parse(JSON.stringify(s.rolls));
  lifeConfirm(s, C, "qing", { qing: "青", mei: "梅" });
  lifeConfirm(s, C, "mei", { qing: "青", mei: "梅" });
  const born = { qing: { ...s.persons.qing.stats }, mei: { ...s.persons.mei.stats } };
  const track = { qing: [], mei: [] }; // 每个日子结束时的属性
  const moodSum = { qing: 0, mei: 0 }, moodN = { qing: 0, mei: 0 };
  const bondTrack = [];
  const online = { qing: true, mei: true };
  let day = null, lastTurn = -1, guard = 0, lastSlot = null;
  while (s.phase !== "ended") {
    if (s.turn !== lastTurn) {
      lastTurn = s.turn;
      day = { attendMirror: R() < cfg.attend, attendSolo: { qing: R() < 0.85, mei: R() < 0.85 }, truant: {}, waited: {} };
      if (TRACE && s.world.fate.mirror === TRACE) traceLog.push({ seed, turn: s.turn, attend: day.attendMirror, close: s.bond.close });
    }
    const w = s.world;
    if (w.event) {
      const ev = eventOf.get(w.event.eventId);
      const pe = w.event;
      if (pe.kind === "mirror" && R() < cfg.agree) {
        const o = botChoose(s, "qing", ev, cfg.style, R);
        worldChoose(s, C, "qing", o, false);
        worldChoose(s, C, "mei", o, false);
      } else {
        for (const r of pe.roles.slice()) worldChoose(s, C, r, botChoose(s, r, ev, cfg.style, R), false);
      }
      continue;
    }
    // 每一段开头先让世界看一眼（真人也是先站在那儿再定）：命运给的事这时候才碰得上
    const slotKey = s.turn + ":" + w.slot;
    if (!w.playing && slotKey !== lastSlot) { lastSlot = slotKey; worldAdvance(s, C, 0, online); continue; }
    for (const r of ROLES) {
      const a = w.actors[r];
      const idle = a && s.persons[r].alive && !w.playing && !worldReady(s, r);
      if (idle) botStep(s, r, cfg.bots[r], cfg.pairing, R, day);
    }
    const turnBefore = s.turn;
    const snap = {};
    for (const r of ROLES) if (s.persons[r].alive) snap[r] = { ...s.persons[r].stats, mood: s.persons[r].needs.mood };
    worldAdvance(s, C, 1, online);
    if (s.turn !== turnBefore || s.phase === "ended") {
      const t = lifeTimeAt(turnBefore);
      for (const r of ROLES) {
        if (!snap[r]) continue;
        track[r].push({ turn: turnBefore, age: t.age, stage: t.stage, ...s.persons[r].stats });
        moodSum[r] += snap[r].mood; moodN[r]++;
      }
      bondTrack.push({ turn: turnBefore, ...s.bond });
    }
    if (++guard > 400000) throw new Error("人生没有结束 seed=" + seed);
  }
  return { s, rolls, born, track, bondTrack, mood: { qing: moodSum.qing / Math.max(1, moodN.qing), mei: moodSum.mei / Math.max(1, moodN.mei) } };
}

// ---------- 统计工具 ----------
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
const sd = (a) => { const m = mean(a); return Math.sqrt(mean(a.map((x) => (x - m) ** 2))); };
const quant = (a, q) => { if (!a.length) return 0; const b = [...a].sort((x, y) => x - y); return b[Math.min(b.length - 1, Math.floor(q * b.length))]; };
const f1 = (x) => x.toFixed(1);
const f2 = (x) => x.toFixed(2);
const pct = (n, d) => (d ? ((n / d) * 100).toFixed(1) + "%" : "-");
const pad = (str, n) => { let w = 0; for (const ch of String(str)) w += ch.charCodeAt(0) > 255 ? 2 : 1; return String(str) + " ".repeat(Math.max(0, n - w)); };
const groupBy = (list, key) => { const m = new Map(); for (const x of list) { const k = key(x); if (!m.has(k)) m.set(k, []); m.get(k).push(x); } return m; };

// ---------- 跑 ----------
const people = []; // 每个人一行
const pairs = []; // 每条人生一行
let legacy = undefined;
const t0 = Date.now();
for (let i = 0; i < LIVES; i++) {
  const seed = (i + 1) * 2654435761 >>> 0;
  const R = rng(seed);
  const cfg = {
    bots: { qing: BOTS[Math.floor(R() * BOTS.length)], mei: BOTS[Math.floor(R() * BOTS.length)] },
    pairing: PAIRINGS[Math.floor(R() * PAIRINGS.length)],
    attend: [0.9, 0.7, 0.4][Math.floor(R() * 3)],
    agree: [0.1, 0.3, 0.6][Math.floor(R() * 3)],
    style: R() < 0.5 ? "steady" : "random",
    rerolls: { qing: Math.floor(R() * 4), mei: Math.floor(R() * 4) },
    legacy: undefined,
  };
  if (i % CHAIN === 0) legacy = MARKS ? { ...G("legacyNew")(), marks: [...C.legacy.marks] } : undefined;
  cfg.legacy = legacy;
  const out = simulate(seed, cfg);
  const s = out.s;
  legacy = JSON.parse(JSON.stringify(s.legacy));
  const st = G("lifeStats")(s);
  pairs.push({
    seed, cfg, turns: s.turn, ending: s.ending.pair, bond: { ...s.bond }, memories: s.memories.length, rate: st.rate, mirrors: st.mirrors, together: st.together,
    bondTrack: out.bondTrack, helps: has("legacyHelps") ? G("legacyHelps")(s) : 0, noted: s.noted ?? [], life: s.life ?? 1, traces: [...(s.legacy?.traces ?? [])], marks: [...(s.legacy?.marks ?? [])],
    seenEvents: s.log.filter((e) => e.kind !== "day").flatMap((e) => [e.events.qing, e.events.mei]).filter(Boolean),
  });
  for (const r of ROLES) {
    const p = s.persons[r];
    people.push({
      seed, role: r, bot: cfg.bots[r], pairing: cfg.pairing, family: p.familyId, talent: p.talentId, born: out.born[r], final: { ...p.stats },
      died: p.diedAtAge, money: p.money, mood: out.mood[r], ending: s.ending.lives[r], track: out.track[r],
      wealth: C.families.find((f) => f.id === p.familyId).wealth, heirloom: out.rolls[r].heirloomId ?? null, left: s.left ? s.left[r] : null,
    });
  }
}
const secs = (Date.now() - t0) / 1000;

// ---------- 报告 ----------
const report = { lives: LIVES };
const log = (...a) => { if (!QUIET) console.log(...a); };
log(`\n══ 平衡模拟：${LIVES} 条人生（${people.length} 个人），用时 ${secs.toFixed(1)} 秒 ══`);

// 1. 投胎
{
  const tot = people.map((p) => STATS.reduce((x, k) => x + p.born[k], 0));
  report.bornTotal = { mean: mean(tot), sd: sd(tot), p5: quant(tot, 0.05), p95: quant(tot, 0.95), min: Math.min(...tot), max: Math.max(...tot) };
  log(`\n【投胎】四项合计：平均 ${f1(report.bornTotal.mean)}  标准差 ${f2(report.bornTotal.sd)}  5%~95%：${report.bornTotal.p5}~${report.bornTotal.p95}  最低 ${report.bornTotal.min} 最高 ${report.bornTotal.max}`);
  report.bornStat = {};
  for (const k of STATS) { const v = people.map((p) => p.born[k]); report.bornStat[k] = { mean: mean(v), sd: sd(v) }; }
  log("  单项：" + STATS.map((k) => `${STAT_CN[k]} ${f1(report.bornStat[k].mean)}±${f1(report.bornStat[k].sd)}`).join("  "));
}

// 2. 成长曲线
{
  report.curve = {};
  log("\n【成长曲线】各阶段结束时的平均属性（活到那时候的人）");
  log("  " + pad("阶段", 8) + STATS.map((k) => pad(STAT_CN[k], 8)).join("") + pad("合计", 8) + "顶到 9.5 以上的人");
  const row = (name, pick) => {
    const rows = people.map(pick).filter(Boolean);
    const m = {}; for (const k of STATS) m[k] = mean(rows.map((x) => x[k]));
    const total = STATS.reduce((x, k) => x + m[k], 0);
    const capped = {}; for (const k of STATS) capped[k] = rows.filter((x) => x[k] >= 9.5).length / Math.max(1, rows.length);
    report.curve[name] = { ...m, total, capped };
    log("  " + pad(name, 8) + STATS.map((k) => pad(f2(m[k]), 8)).join("") + pad(f1(total), 8) + STATS.map((k) => `${STAT_CN[k]} ${pct(capped[k] * 100, 100)}`).join(" "));
  };
  row("出生", (p) => p.born);
  for (const st of STAGES) row(STAGE_CN[st], (p) => { const t = p.track.filter((x) => x.stage === st); return t.length ? t[t.length - 1] : null; });
  // 每岁曲线（给图表用）
  const byAge = new Map();
  for (const p of people) for (const x of p.track) { if (!byAge.has(x.age)) byAge.set(x.age, []); byAge.get(x.age).push(x); }
  report.byAge = [...byAge].sort((a, b) => a[0] - b[0]).map(([age, rows]) => ({ age, n: rows.length, ...Object.fromEntries(STATS.map((k) => [k, mean(rows.map((x) => x[k]))])) }));
}

// 3. 活法：不同机器人最后长成什么样
{
  report.bots = {};
  log("\n【活法】不同活法的人，60 岁时的属性 / 一生平均心情 / 寿命 / 攒下的钱");
  log("  " + pad("活法", 10) + STATS.map((k) => pad(STAT_CN[k], 7)).join("") + pad("心情", 7) + pad("寿命", 7) + "钱");
  for (const [bot, rows] of groupBy(people, (p) => p.bot)) {
    const at30 = rows.map((p) => { const t = p.track.filter((x) => x.age <= 30); return t[t.length - 1]; });
    const gain30 = Object.fromEntries(STATS.map((k) => [k, mean(rows.map((p, i) => at30[i][k] - p.born[k]))]));
    const at60 = rows.map((p) => { const t = p.track.filter((x) => x.age <= 60); return t[t.length - 1]; });
    const m = Object.fromEntries(STATS.map((k) => [k, mean(at60.map((x) => x[k]))]));
    report.bots[bot] = { ...m, gain30, mood: mean(rows.map((p) => p.mood)), died: mean(rows.map((p) => p.died)), money: mean(rows.map((p) => p.money)) };
    log("  " + pad(BOT_CN[bot], 10) + STATS.map((k) => pad(f2(m[k]), 7)).join("") + pad(f1(report.bots[bot].mood), 7) + pad(f1(report.bots[bot].died), 7) + pad(Math.round(report.bots[bot].money), 6) +
      "到 30 岁比出生多长了 " + STATS.map((k) => `${STAT_CN[k]}+${f1(gain30[k])}`).join(" "));
  }
}

// 4. 人家 / 天赋：强度是否离谱
function strength(name, key, labelOf) {
  report[name] = {};
  log(`\n【${name === "families" ? "人家" : "天赋"}】出生合计 / 60 岁合计 / 一生平均心情 / 寿命 / 人数`);
  const all60 = [];
  const rowsOut = [];
  for (const [id, rows] of groupBy(people, key)) {
    const bornT = mean(rows.map((p) => STATS.reduce((x, k) => x + p.born[k], 0)));
    const t60 = mean(rows.map((p) => { const t = p.track.filter((x) => x.age <= 60); const x = t[t.length - 1]; return STATS.reduce((y, k) => y + x[k], 0); }));
    const o = { born: bornT, at60: t60, mood: mean(rows.map((p) => p.mood)), died: mean(rows.map((p) => p.died)), n: rows.length };
    report[name][id] = o; all60.push(t60); rowsOut.push([id, o]);
  }
  rowsOut.sort((a, b) => b[1].at60 - a[1].at60);
  for (const [id, o] of rowsOut) log("  " + pad(labelOf(id), 22) + pad(f1(o.born), 7) + pad(f1(o.at60), 7) + pad(f1(o.mood), 7) + pad(f1(o.died), 7) + o.n);
  log(`  60 岁合计的极差：${f2(Math.max(...all60) - Math.min(...all60))}`);
  report[name + "Spread"] = Math.max(...all60) - Math.min(...all60);
}
strength("families", (p) => p.family, (id) => C.families.find((f) => f.id === id).name);
strength("talents", (p) => p.talent, (id) => C.talents.find((t) => t.id === id).name);

// 5. 寿命
{
  const d = people.map((p) => p.died);
  const hist = new Map();
  for (const x of d) { const b = Math.floor(x / 5) * 5; hist.set(b, (hist.get(b) ?? 0) + 1); }
  report.lifespan = { mean: mean(d), sd: sd(d), p5: quant(d, 0.05), p50: quant(d, 0.5), p95: quant(d, 0.95), min: Math.min(...d), max: Math.max(...d), distinct: new Set(d).size, hist: [...hist].sort((a, b) => a[0] - b[0]) };
  const gap = pairs.map((_, i) => Math.abs(people[i * 2].died - people[i * 2 + 1].died));
  report.lifespan.gap = { mean: mean(gap), same: gap.filter((g) => g === 0).length / gap.length };
  log(`\n【寿命】平均 ${f1(report.lifespan.mean)} 岁  标准差 ${f1(report.lifespan.sd)}  5%/50%/95%：${report.lifespan.p5}/${report.lifespan.p50}/${report.lifespan.p95}  最短 ${report.lifespan.min} 最长 ${report.lifespan.max}  共 ${report.lifespan.distinct} 种不同的岁数`);
  log("  分布：" + report.lifespan.hist.map(([b, n]) => `${b}~${b + 4}岁 ${pct(n, d.length)}`).join("  "));
  log(`  两个人相差：平均 ${f1(report.lifespan.gap.mean)} 年，同一年走的 ${pct(report.lifespan.gap.same * 100, 100)}`);
  const turns = pairs.map((p) => p.turns);
  report.turns = { mean: mean(turns), p5: quant(turns, 0.05), p95: quant(turns, 0.95) };
  log(`  一生的日子数：平均 ${f1(report.turns.mean)}（5%~95%：${report.turns.p5}~${report.turns.p95}）`);
  // 属性和寿命的关系
  const byBody = groupBy(people, (p) => Math.min(9, Math.floor(p.final.body)));
  log("  体魄与寿命：" + [...byBody].sort((a, b) => a[0] - b[0]).map(([b, rows]) => `体魄${b}→${f1(mean(rows.map((p) => p.died)))}岁`).join("  "));
}

// 6. 两个人
{
  report.pairings = {};
  log("\n【两个人】相处方式 → 结束时的亲近 / 默契 / 同框次数 / 共同回忆 / 默契率");
  for (const [k, rows] of groupBy(pairs, (p) => p.cfg.pairing)) {
    const o = { close: mean(rows.map((p) => p.bond.close)), sync: mean(rows.map((p) => p.bond.sync)), together: mean(rows.map((p) => p.together)), memories: mean(rows.map((p) => p.memories)), rate: mean(rows.map((p) => p.rate)), closeMax: rows.filter((p) => p.bond.close >= 100).length / rows.length };
    report.pairings[k] = o;
    log("  " + pad(PAIR_CN[k], 14) + `亲近 ${f1(o.close)}（顶到 100 的 ${pct(o.closeMax * 100, 100)}）  默契 ${f1(o.sync)}  同框 ${f1(o.together)}  回忆 ${f1(o.memories)}  默契率 ${f1(o.rate)}%`);
  }
  const closeAt = (turn) => mean(pairs.map((p) => { const t = p.bondTrack.filter((x) => x.turn <= turn); return t.length ? t[t.length - 1].close : 0; }));
  report.closeCurve = [12, 36, 48, 60, 70].map((t) => ({ turn: t, close: closeAt(t) }));
  log("  亲近随时间：" + report.closeCurve.map((x) => `第${x.turn}个日子 ${f1(x.close)}`).join("  "));
}

// 7. 结局
{
  const count = (list) => { const m = new Map(); for (const x of list) m.set(x, (m.get(x) ?? 0) + 1); return [...m].sort((a, b) => b[1] - a[1]); };
  const pe = count(pairs.map((p) => p.ending));
  const le = count(people.map((p) => p.ending));
  report.pairEndings = Object.fromEntries(pe.map(([id, n]) => [id, n / pairs.length]));
  report.lifeEndings = Object.fromEntries(le.map(([id, n]) => [id, n / people.length]));
  const title = (list, id) => list.find((x) => x.id === id).title;
  log(`\n【结局】两个人的结局：走到过 ${pe.length}/${C.endings.pair.length} 种`);
  log("  " + pe.map(([id, n]) => `${title(C.endings.pair, id)} ${pct(n, pairs.length)}`).join("  "));
  log(`  每个人的一生：走到过 ${le.length}/${C.endings.lives.length} 种`);
  log("  " + le.map(([id, n]) => `${title(C.endings.lives, id)} ${pct(n, people.length)}`).join("  "));
  const missP = C.endings.pair.filter((e) => !report.pairEndings[e.id]).map((e) => e.title);
  const missL = C.endings.lives.filter((e) => !report.lifeEndings[e.id]).map((e) => e.title);
  if (missP.length || missL.length) log("  没走到的：" + [...missP, ...missL].join("、"));
}

// 8. 传承：一世走完各自留下的老物件（docs/LEGACY.md）。留下什么看的是怎么过的，所以兜底那件不该占大头，也不该有谁都留不下的
if (C.heirlooms) {
  const m = new Map(C.heirlooms.map((h) => [h.id, 0]));
  for (const p of people) if (p.left) m.set(p.left, (m.get(p.left) ?? 0) + 1);
  report.heirlooms = Object.fromEntries([...m].map(([id, n]) => [id, n / people.length]));
  const same = pairs.filter((_, i) => people[i * 2].left === people[i * 2 + 1].left).length;
  report.heirloomsSame = same / pairs.length;
  log(`\n【留下的老物件】共 ${C.heirlooms.length} 件；两个人留下同一件的人生 ${pct(same, pairs.length)}`);
  log("  " + [...m].sort((a, b) => b[1] - a[1]).map(([id, n]) => `${C.heirlooms.find((h) => h.id === id).name} ${pct(n, people.length)}`).join("  "));
  const never = [...m].filter(([, n]) => n === 0).map(([id]) => C.heirlooms.find((h) => h.id === id).name);
  if (never.length) log("  没人留下的：" + never.join("、"));
}

// 9. 街坊记住的事、痕迹、藏着的天赋（docs/LEGACY.md 第二步）。记的是活法：不该有一条人人都有，也不该有一条谁都碰不上
if (C.remembered) {
  const m = new Map(C.remembered.map((a) => [a.id, 0]));
  for (const p of pairs) for (const id of p.noted) m.set(id, (m.get(id) ?? 0) + 1);
  report.remembered = Object.fromEntries([...m].map(([id, n]) => [id, n / pairs.length]));
  const per = pairs.map((p) => p.noted.length);
  log(`\n【街坊记住的事】共 ${C.remembered.length} 条；一世平均新记住 ${f2(mean(per))} 条，一条也没有的人生 ${pct(per.filter((n) => n === 0).length, per.length)}`);
  log("  每 100 世记住几回：" + [...m].sort((a, b) => b[1] - a[1]).map(([id, n]) => `${C.remembered.find((a) => a.id === id).title} ${f1((n / pairs.length) * 100)}`).join("  "));
  const helps = pairs.map((p) => p.helps);
  log(`  两个人一起才办成的事：平均 ${f1(mean(helps))} 回（50%/95%：${quant(helps, 0.5)}/${quant(helps, 0.95)}），够 3 回的 ${pct(helps.filter((n) => n >= 3).length, helps.length)}，够 5 回的 ${pct(helps.filter((n) => n >= 5).length, helps.length)}`);
  if (CHAIN > 1) {
    const byLife = groupBy(pairs, (p) => p.life);
    log("  第几世新记住几条：" + [...byLife].sort((a, b) => a[0] - b[0]).map(([n, rows]) => `第${n}世 ${f2(mean(rows.map((p) => p.noted.length)))}`).join("  "));
    const ends = pairs.filter((p) => p.life === CHAIN);
    const total = ends.map((_, k) => pairs.slice(k * CHAIN, k * CHAIN + CHAIN).reduce((n, p) => n + p.noted.length, 0));
    log(`  连过 ${CHAIN} 世一共记住：平均 ${f1(mean(total))} 条（5%~95%：${quant(total, 0.05)}~${quant(total, 0.95)}）`);
    const later = pairs.filter((p) => p.life > 1);
    const prev = pairs.filter((p) => p.life < CHAIN);
    log("  上一世留下的痕迹：" + C.legacy.traces.map((t) => `${t} ${pct(prev.filter((p) => p.traces.includes(t)).length, prev.length)}`).join("  "));
    log("  出过的事（到最后一世为止）：" + C.legacy.marks.map((t) => `${t} ${pct(ends.filter((p) => p.marks.includes(t)).length, ends.length)}`).join("  "));
    const legacyEvents = C.events.filter((e) => (e.requires.flags ?? []).some((f) => f.startsWith("leg_")));
    log("  隔世的事（第二世起，每 100 世遇到几回）：" + legacyEvents.map((e) => `${e.title} ${f1((later.filter((p) => p.seenEvents.includes(e.id)).length / Math.max(1, later.length)) * 100)}`).join("  "));
    const hiddenTal = C.talents.filter((t) => t.unlock);
    const laterPeople = people.filter((_, k) => pairs[Math.floor(k / 2)].life > 1);
    log("  藏着的天赋（第二世起抽到的人）：" + hiddenTal.map((t) => `${t.name} ${pct(laterPeople.filter((p) => p.talent === t.id).length, laterPeople.length)}`).join("  "));
  }
}

if (JSON_OUT) {
  writeFileSync(JSON_OUT, JSON.stringify(report, null, 1));
  log(`\n原始统计写到了 ${JSON_OUT}`);
}
export { report };

// 调试：--trace <事件 id> 看这件事被命运准备了几回、真发生了几回
if (arg("trace", null)) {
  const id = arg("trace");
  console.log(`被命运准备了 ${traceLog.length} 回，其中打算去的 ${traceLog.filter((x) => x.attend).length} 回`);
  console.log(`\n${id}: 发生 ${pairs.filter((p) => p.seenEvents.includes(id)).length} / ${pairs.length} 条人生`);
}
