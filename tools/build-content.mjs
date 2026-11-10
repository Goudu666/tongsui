#!/usr/bin/env node
// 把 content/ 下的 YAML 编译成：
//   client/data/content.json         客户端读取（画地图、显示文字）
//   server/src/content.generated.ts  服务端结算（Nakama JS 运行时不方便读文件，直接内联）
// 包含：events/*.yaml 剧情事件、families.yaml 家庭、talents.yaml 天赋、map.yaml 地图与行动、endings.yaml 结局
// 同时做基础校验，写剧情时出错能第一时间看到。
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(root, "content", "events");

const STAGES = ["childhood", "teen", "young", "middle", "old"];
const SEASONS = ["spring", "summer", "autumn", "winter"];
const KINDS = ["mirror", "solo", "milestone"];
const STAT_KEYS = ["body", "mind", "charm", "luck"];
const NEED_KEYS = ["hunger", "energy", "mood", "clean"];
const SELF_KEYS = [...STAT_KEYS, ...NEED_KEYS];
const BOND_KEYS = ["sync", "close", "distance"];
const TAGS = ["gentle", "adventure", "solitude", "responsible", "competitive", "patient"];
const REQ_KEYS = ["minAge", "maxAge", "flags", "notFlags", "minClose", "maxClose", "minSync", "maxSync", "minDistance", "maxDistance", "alone"];
const PAIR_REQ_KEYS = ["flags", "notFlags", "minClose", "maxClose", "minSync", "maxSync", "minDistance", "maxDistance", "minMemories", "maxMemories", "minRate", "maxRate", "minTogether"];
const LIFE_REQ_KEYS = ["flags", "notFlags", "stats", "minDiedAge", "maxDiedAge"];

// 每一层允许出现的字段。写错字段名（比如 require / option / effect）以前会被悄悄丢掉，
// 事件就变成「没有条件」「没有效果」；现在直接报错。加新字段时先加到这里，再去 types.ts 和 sim.ts 里用它。
const EVENT_KEYS = ["id", "kind", "stage", "where", "when", "hint", "seasons", "weight", "requires", "title", "text", "options", "resonance", "dissonance"];
// 关口（kind: milestone）多出来的字段，见 content/events/milestones.yaml 文件头
const MILESTONE_KEYS = [...EVENT_KEYS, "age", "score", "swing", "grades"];
const MILESTONE_OPTION_KEYS = ["id", "text", "tags", "effects", "min", "score", "cost", "requires"];
const SCORE_KEYS = ["body", "mind", "charm", "luck", "money"];
const GRADE_KEYS = ["min", "label", "flags"];
const TRACK_KEYS = ["id", "label", "requires", "duty"];
const TRACK_REQ_KEYS = ["minAge", "maxAge", "flags", "notFlags"];
const DUTY_KEYS = ["label", "spot", "arrive", "until", "needs", "stats", "money"];
const OPTION_KEYS = ["id", "text", "tags", "effects"];
const EFFECT_KEYS = ["self", "other", "bond", "flags"];
const RESONANCE_KEYS = ["text", "memory", "bond", "flags"];
const DISSONANCE_KEYS = ["text", "bond", "flags"];
const FAMILY_KEYS = ["id", "name", "wealth", "weight", "money", "desc", "bonus", "traits"];
const TALENT_KEYS = ["id", "name", "weight", "desc", "bonus", "flags"];
const ENDING_KEYS = ["id", "title", "text", "requires"];
const MAP_KEYS = ["size", "spawn", "zones", "spots", "actions"];
const ZONE_KEYS = ["id", "name", "rect", "owner"];
const SPOT_KEYS = ["id", "zone", "at", "action", "actions"];
const ACTION_KEYS = ["id", "label", "minutes", "sleep", "duty", "requires", "needs", "stats", "money", "together"];
const ACTION_REQ_KEYS = ["minAge", "maxAge", "owner", "hours"];
const TOGETHER_KEYS = ["needs", "bond", "text"];
// 规则代码（server/src/sim.ts、world.ts）里按名字写死的行动和标记：影子靠这些行动过日子，天赋效果靠这些标记生效。
// 在内容里改名或删掉它们，规则会悄悄失效，所以在这里钉住。
const ENGINE_ACTIONS = ["eat", "eat_out", "sleep", "duty", "wash", "knock", "play_roof"];
const ENGINE_FLAGS = ["tal_sunny", "tal_memory", "tal_foodie", "tal_owl", "tal_plain"];

const errors = [];
const events = [];
const seen = new Set();
// 标记的来龙去脉：谁打上的、谁要求的。要求了却没人能打上的标记 = 永远触发不了的剧情（多半是拼错了）
const produced = new Set();
const consumed = []; // [where, flag]

function checkKeys(where, obj, allowed) {
  if (obj == null || typeof obj !== "object" || Array.isArray(obj)) return;
  for (const k of Object.keys(obj)) if (!allowed.includes(k)) errors.push(`${where}: 未知字段 "${k}"（可用：${allowed.join(", ")}）`);
}

function checkRequires(where, rq, allowed) {
  if (rq == null) return;
  if (typeof rq !== "object" || Array.isArray(rq)) return errors.push(`${where}: requires 应为对象`);
  for (const [k, v] of Object.entries(rq)) {
    if (!allowed.includes(k)) errors.push(`${where}: requires 未知条件 "${k}"（可用：${allowed.join(", ")}）`);
    else if (k === "flags" || k === "notFlags") {
      if (!Array.isArray(v)) errors.push(`${where}.requires.${k}: 必须是列表`);
      else if (k === "flags") for (const f of v) consumed.push([where, f]);
    } else if (k === "alone") {
      if (typeof v !== "boolean") errors.push(`${where}.requires.alone: 必须是 true / false`);
    } else if (k === "stats") checkDeltas(`${where}.requires.stats`, v, STAT_KEYS);
    else if (typeof v !== "number") errors.push(`${where}.requires.${k}: 必须是数字`);
  }
}

function checkPairFlags(where, flags) {
  if (flags == null) return [];
  if (!Array.isArray(flags)) { errors.push(`${where}.flags: 必须是列表`); return []; }
  for (const f of flags) {
    if (!String(f).startsWith("p_")) errors.push(`${where}.flags: 共同标记 "${f}" 必须以 p_ 开头`);
    produced.add(f);
  }
  return flags;
}

function checkDeltas(where, obj, allowed) {
  if (obj == null) return;
  for (const [k, v] of Object.entries(obj)) {
    if (!allowed.includes(k)) errors.push(`${where}: 未知数值键 "${k}"（可用：${allowed.join(", ")}）`);
    if (typeof v !== "number") errors.push(`${where}.${k}: 必须是数字`);
  }
}

for (const file of readdirSync(dir).filter((f) => f.endsWith(".yaml")).sort()) {
  const list = parse(readFileSync(join(dir, file), "utf8")) ?? [];
  for (const ev of list) {
    const at = `${file}#${ev.id ?? "?"}`;
    if (!ev.id) errors.push(`${at}: 缺少 id`);
    const ms = ev.kind === "milestone";
    checkKeys(at, ev, ms ? MILESTONE_KEYS : EVENT_KEYS);
    if (seen.has(ev.id)) errors.push(`${at}: id 重复`);
    seen.add(ev.id);
    if (!KINDS.includes(ev.kind)) errors.push(`${at}: kind 必须是 ${KINDS.join(" / ")}`);
    if (!STAGES.includes(ev.stage)) errors.push(`${at}: stage 必须是 ${STAGES.join(" / ")}`);
    for (const s of ev.seasons ?? []) if (!SEASONS.includes(s)) errors.push(`${at}: 未知季节 ${s}`);
    if (!ev.title || !ev.text) errors.push(`${at}: 缺少 title 或 text`);
    if (ev.kind === "mirror" && !ev.where) errors.push(`${at}: mirror 事件需要 where（两人同时在这个地点才会触发）`);
    if (ev.when && !(Array.isArray(ev.when) && ev.when.length === 2)) errors.push(`${at}: when 应为 [起始分钟, 结束分钟]`);
    else if (ev.when && !(typeof ev.when[0] === "number" && typeof ev.when[1] === "number" && ev.when[0] < ev.when[1])) errors.push(`${at}: when 的起始分钟要小于结束分钟`);
    if (!Array.isArray(ev.options) || ev.options.length < (ms ? 1 : 2)) errors.push(`${at}: 至少${ms ? "一" : "两"}个选项`);
    if (ms) {
      if (!(Number.isInteger(ev.age) && ev.age >= 3)) errors.push(`${at}: 关口需要 age（到几岁的第一天发生）`);
      if (ev.where || ev.when || ev.hint || ev.seasons) errors.push(`${at}: 关口到了年纪的早上一定发生，不要写 where / when / hint / seasons`);
      checkDeltas(`${at}.score`, ev.score, SCORE_KEYS);
      for (const [gi, g] of (ev.grades ?? []).entries()) {
        checkKeys(`${at}.grades[${gi}]`, g, GRADE_KEYS);
        if (typeof g.min !== "number" || !g.label) errors.push(`${at}.grades[${gi}]: 需要 min 和 label`);
        for (const f of g.flags ?? []) produced.add(f);
        g.flags = g.flags ?? [];
      }
      if (ev.grades?.length && ev.grades.at(-1).min > 0) errors.push(`${at}.grades: 最后一档是兜底，min 必须是 0`);
      const open = (ev.options ?? []).filter((o) => !o.min && !o.requires && !o.cost);
      if (open.length === 0) errors.push(`${at}: 关口至少要有一条谁都能走的路（没有 min / cost / requires 的选项）`);
    }
    checkRequires(at, ev.requires, REQ_KEYS);
    if (ev.requires?.alone === true && ev.kind === "mirror") errors.push(`${at}: alone: true 只能用于 solo（mirror 需要两个人都在）`);
    if (ev.seasons?.length && ev.stage !== "childhood") errors.push(`${at}: 只有童年有季节，${ev.stage} 不要写 seasons`);
    const optionIds = new Set();
    for (const o of ev.options ?? []) {
      const oat = `${at}.${o.id}`;
      if (!o.id || !o.text) errors.push(`${oat}: 选项缺少 id 或 text`);
      checkKeys(oat, o, ms ? MILESTONE_OPTION_KEYS : OPTION_KEYS);
      if (ms) {
        checkDeltas(`${oat}.score`, o.score, SCORE_KEYS);
        checkRequires(oat, o.requires, ["flags", "notFlags"]);
        if (o.min !== undefined && typeof o.min !== "number") errors.push(`${oat}.min: 必须是数字`);
        if (o.min && !o.score && !ev.score) errors.push(`${oat}: 写了 min 却没有 score（选项或关口至少一处要写怎么算分）`);
        if (o.cost !== undefined && !(o.cost > 0)) errors.push(`${oat}.cost: 必须是正数`);
      }
      checkKeys(`${oat}.effects`, o.effects, EFFECT_KEYS);
      if (optionIds.has(o.id)) errors.push(`${oat}: 选项 id 重复`);
      optionIds.add(o.id);
      for (const tag of o.tags ?? []) if (!TAGS.includes(tag)) errors.push(`${oat}: 未知性格标签 ${tag}（可用：${TAGS.join(", ")}）`);
      const e = o.effects ?? {};
      for (const f of e.flags ?? []) produced.add(f);
      checkDeltas(`${oat}.self`, e.self, SELF_KEYS);
      checkDeltas(`${oat}.other`, e.other, SELF_KEYS);
      checkDeltas(`${oat}.bond`, e.bond, BOND_KEYS);
      o.tags = o.tags ?? [];
      o.effects = { self: e.self ?? {}, other: e.other ?? {}, bond: e.bond ?? {}, flags: e.flags ?? [] };
    }
    if (ev.kind === "mirror" || ms) {
      for (const [oid, r] of Object.entries(ev.resonance ?? {})) {
        if (!optionIds.has(oid)) errors.push(`${at}.resonance.${oid}: 没有这个选项`);
        if (!r.text) errors.push(`${at}.resonance.${oid}: 缺少 text`);
        checkKeys(`${at}.resonance.${oid}`, r, RESONANCE_KEYS);
        checkDeltas(`${at}.resonance.${oid}.bond`, r.bond, BOND_KEYS);
        r.bond = r.bond ?? {};
        r.flags = checkPairFlags(`${at}.resonance.${oid}`, r.flags);
      }
      if (!ms && !ev.dissonance?.text) errors.push(`${at}: mirror 事件需要 dissonance.text`);
      checkKeys(`${at}.dissonance`, ev.dissonance, DISSONANCE_KEYS);
      checkDeltas(`${at}.dissonance.bond`, ev.dissonance?.bond, BOND_KEYS);
      ev.resonance = ev.resonance ?? {};
      ev.dissonance = {
        text: ev.dissonance?.text ?? "",
        bond: ev.dissonance?.bond ?? {},
        flags: checkPairFlags(`${at}.dissonance`, ev.dissonance?.flags),
      };
    } else if (ev.resonance || ev.dissonance) {
      errors.push(`${at}: solo 事件不需要 resonance / dissonance`);
    }
    events.push({
      id: ev.id, kind: ev.kind, stage: ev.stage, seasons: ev.seasons ?? [], weight: ev.weight ?? 1,
      where: ev.where ?? null, when: ev.when ?? null, hint: ev.hint ?? null,
      requires: ev.requires ?? {}, title: ev.title, text: ev.text, options: ev.options,
      resonance: ev.resonance ?? null, dissonance: ev.dissonance ?? null,
      ...(ms ? { age: ev.age, score: ev.score ?? {}, swing: !!ev.swing, grades: ev.grades ?? [] } : {}),
    });
  }
}

// ---------- 家庭 / 天赋 ----------
const load = (f) => parse(readFileSync(join(root, "content", f), "utf8"));
const families = load("families.yaml").map((f) => {
  if (![0, 1, 2].includes(f.wealth)) errors.push(`families#${f.id}: wealth 必须是 0/1/2`);
  checkKeys(`families#${f.id}`, f, FAMILY_KEYS);
  checkDeltas(`families#${f.id}.bonus`, f.bonus, STAT_KEYS);
  return { id: f.id, name: f.name, wealth: f.wealth, weight: f.weight ?? 1, money: f.money ?? 0, desc: f.desc ?? "", bonus: f.bonus ?? {}, traits: f.traits ?? [] };
});
const talents = load("talents.yaml").map((t) => {
  checkDeltas(`talents#${t.id}.bonus`, t.bonus, STAT_KEYS);
  checkKeys(`talents#${t.id}`, t, TALENT_KEYS);
  return { id: t.id, name: t.name, weight: t.weight ?? 1, desc: t.desc ?? "", bonus: t.bonus ?? {}, flags: t.flags ?? [] };
});
if (families.length < 2) errors.push("families.yaml 至少需要两户人家");
for (const f of families) for (const x of f.traits) produced.add(x);
for (const x of talents) for (const f of x.flags) produced.add(f);

// ---------- 结局 ----------
const endingsRaw = load("endings.yaml");
const endings = { pair: [], lives: [] };
for (const [part, keys] of [["pair", PAIR_REQ_KEYS], ["lives", LIFE_REQ_KEYS]]) {
  const list = endingsRaw?.[part] ?? [];
  const ids = new Set();
  if (list.length === 0) errors.push(`endings.yaml: ${part} 至少要有一条`);
  for (const e of list) {
    const at = `endings.${part}#${e.id ?? "?"}`;
    if (!e.id || !e.title || !e.text) errors.push(`${at}: 需要 id / title / text`);
    checkKeys(at, e, ENDING_KEYS);
    if (ids.has(e.id)) errors.push(`${at}: id 重复`);
    ids.add(e.id);
    checkRequires(at, e.requires, keys);
    endings[part].push({ id: e.id, title: e.title, text: e.text, requires: e.requires ?? {} });
  }
  const last = list.at(-1);
  if (last && Object.keys(last.requires ?? {}).length > 0) errors.push(`endings.${part}: 最后一条是兜底结局，不能有 requires`);
}

// ---------- 数值规则 ----------
const rules = load("rules.yaml");
{
  const need = {
    roll: ["budget", "wealthAdjust", "statMin", "statMax", "rerolls"],
    growth: ["eventScale", "actionScale", "room", "floor", "plasticity", "plainBonus"],
    aging: ["body", "mind", "activeFactor"],
    daily: ["bodyEnergy", "charmTogether", "luckFate"],
    check: ["base", "perPoint", "luck", "min", "max", "help"],
    lifespan: ["base", "spread", "body", "moodMid", "moodStep", "moodMin", "moodMax", "bondClose", "bond", "widowClose", "widow", "min", "max"],
    bond: ["closeSoft", "closeFloor", "closeScale", "syncSoft", "syncFloor", "drift", "driftDistance", "driftFloor"],
  };
  checkKeys("rules", rules, Object.keys(need));
  for (const [sec, keys] of Object.entries(need)) {
    if (!rules?.[sec]) { errors.push(`rules.yaml: 缺少 ${sec}`); continue; }
    checkKeys(`rules.${sec}`, rules[sec], keys);
    for (const k of keys) if (rules[sec][k] === undefined) errors.push(`rules.yaml: 缺少 ${sec}.${k}`);
  }
  for (const st of STAGES) {
    for (const k of STAT_KEYS) if (typeof rules?.growth?.plasticity?.[st]?.[k] !== "number") errors.push(`rules.yaml: growth.plasticity.${st}.${k} 必须是数字`);
    if (typeof rules?.bond?.drift?.[st] !== "number") errors.push(`rules.yaml: bond.drift.${st} 必须是数字`);
  }
  if (rules?.roll && rules.roll.wealthAdjust?.length !== 3) errors.push("rules.yaml: roll.wealthAdjust 需要三个数（清贫 / 小康 / 殷实）");
  // 投胎的点数要分得下去：每种人家 × 天赋，按单项算。
  // 一项的底子在 [max(statMin, −加成), min(statMax, 10 − 加成)] 里（加完以后还得在 0~10），
  // 四项的下限加起来不能超过预算，上限加起来不能不够预算。和 server/src/sim.ts → lifeRollOnce 是同一套算法
  if (rules?.roll) {
    const { budget, wealthAdjust, statMin, statMax } = rules.roll;
    for (const f of families) for (const t of talents) {
      const target = budget + wealthAdjust[f.wealth];
      let least = 0, most = 0;
      for (const k of STAT_KEYS) {
        const bonus = (f.bonus?.[k] ?? 0) + (t.bonus?.[k] ?? 0);
        const lo = Math.max(statMin, -bonus);
        const hi = Math.min(statMax, 10 - bonus);
        if (hi < lo) errors.push(`rules.yaml: ${f.id} + ${t.id} 的 ${k} 加成 ${bonus} 太大，放不进 0~10`);
        least += lo + bonus;
        most += Math.max(lo, hi) + bonus;
      }
      if (target < least || target > most) errors.push(`rules.yaml: ${f.id} + ${t.id} 的合计应该是 ${target}，但四项加起来只能在 ${least}~${most} 之间，分不下去`);
    }
  }
}

// ---------- 检定 ----------
const CHECK_KEYS = ["event", "option", "stat", "dc", "pass", "fail"];
const checks = [];
{
  const byId = new Map(events.map((e) => [e.id, e]));
  const seenCheck = new Set();
  for (const ck of load("checks.yaml") ?? []) {
    const at = `checks#${ck.event}.${ck.option}`;
    checkKeys(at, ck, CHECK_KEYS);
    checkKeys(`${at}.fail`, ck.fail, ["text", "self", "flags"]);
    const ev = byId.get(ck.event);
    if (!ev) { errors.push(`${at}: 没有这个事件`); continue; }
    if (!ev.options.some((o) => o.id === ck.option)) errors.push(`${at}: 事件没有这个选项`);
    if (seenCheck.has(at)) errors.push(`${at}: 重复登记`);
    seenCheck.add(at);
    if (!STAT_KEYS.includes(ck.stat)) errors.push(`${at}: stat 必须是 ${STAT_KEYS.join(" / ")}`);
    if (typeof ck.dc !== "number") errors.push(`${at}: dc 必须是数字`);
    if (!ck.pass || !ck.fail?.text) errors.push(`${at}: 需要 pass 和 fail.text`);
    checkDeltas(`${at}.fail.self`, ck.fail?.self, SELF_KEYS);
    for (const f of ck.fail?.flags ?? []) produced.add(f);
    checks.push({ event: ck.event, option: ck.option, stat: ck.stat, dc: ck.dc, pass: ck.pass ?? "", fail: { text: ck.fail?.text ?? "", self: ck.fail?.self ?? null, flags: ck.fail?.flags ?? null } });
  }
}

// ---------- 地图 ----------
const map = load("map.yaml");
const zoneIds = new Set(map.zones.map((z) => z.id));
const actionIds = new Set(map.actions.map((a) => a.id));
checkKeys("map", map, MAP_KEYS);
for (const z of map.zones) checkKeys(`map.zones#${z.id}`, z, ZONE_KEYS);
for (const z of map.zones) if (!Array.isArray(z.rect) || z.rect.length !== 4) errors.push(`map.zones#${z.id}: rect 应为 [x, y, w, h]`);
for (const id of ENGINE_ACTIONS) if (!actionIds.has(id)) errors.push(`map.actions: 缺少行动 "${id}"（规则代码按这个名字找它，见 server/src/world.ts）`);
for (const f of ENGINE_FLAGS) if (!produced.has(f)) errors.push(`talents: 没有任何天赋带标记 "${f}"（规则代码按这个名字给天赋效果，见 server/src/sim.ts、world.ts）`);
for (const sp of map.spots) {
  checkKeys(`map.spots#${sp.id}`, sp, SPOT_KEYS);
  if (!zoneIds.has(sp.zone)) errors.push(`map.spots#${sp.id}: 未知 zone ${sp.zone}`);
  // action: x 是 actions: [x] 的简写。两种写法都输出成 actions（规则用）+ action（= 第一个，给旧代码）
  sp.actions = sp.actions ?? (sp.action ? [sp.action] : []);
  if (sp.actions.length === 0) errors.push(`map.spots#${sp.id}: 需要 action 或 actions`);
  for (const a of sp.actions) if (!actionIds.has(a)) errors.push(`map.spots#${sp.id}: 未知 action ${a}`);
  sp.action = sp.actions[0];
}
map.actions = map.actions.map((a) => {
  checkKeys(`map.actions#${a.id}`, a, ACTION_KEYS);
  checkKeys(`map.actions#${a.id}.requires`, a.requires, ACTION_REQ_KEYS);
  checkKeys(`map.actions#${a.id}.together`, a.together, TOGETHER_KEYS);
  checkDeltas(`map.actions#${a.id}.needs`, a.needs, NEED_KEYS);
  checkDeltas(`map.actions#${a.id}.stats`, a.stats, STAT_KEYS);
  checkDeltas(`map.actions#${a.id}.together.needs`, a.together?.needs, NEED_KEYS);
  checkDeltas(`map.actions#${a.id}.together.bond`, a.together?.bond, BOND_KEYS);
  if (!a.sleep && !a.duty && !(a.minutes > 0)) errors.push(`map.actions#${a.id}: 需要 minutes（睡觉和日程除外）`);
  if (a.stats?.luck) errors.push(`map.actions#${a.id}: 行动不给运气（运气是天生的）`);
  return {
    id: a.id, label: a.label, minutes: a.minutes ?? 0, sleep: !!a.sleep, duty: !!a.duty,
    requires: a.requires ?? {}, needs: a.needs ?? {}, stats: a.stats ?? {}, money: a.money ?? 0,
    together: a.together ? { needs: a.together.needs ?? {}, bond: a.together.bond ?? {}, text: a.together.text ?? "" } : null,
  };
});
for (const ev of events) if (ev.where && !zoneIds.has(ev.where)) errors.push(`${ev.id}: where 未知地点 ${ev.where}`);
for (const ev of events) if (ev.where && ev.where.startsWith("home_") && ev.kind === "mirror") errors.push(`${ev.id}: mirror 不能放在某一家屋里（${ev.where}）`);

// ---------- 人生路线 ----------
const spotById = new Map(map.spots.map((sp) => [sp.id, sp]));
const tracks = (load("tracks.yaml") ?? []).map((t) => {
  const at = `tracks#${t.id ?? "?"}`;
  checkKeys(at, t, TRACK_KEYS);
  if (!t.id || !t.label) errors.push(`${at}: 需要 id 和 label`);
  checkRequires(at, t.requires, TRACK_REQ_KEYS);
  const d = t.duty;
  if (d) {
    checkKeys(`${at}.duty`, d, DUTY_KEYS);
    const sp = spotById.get(d.spot);
    if (!sp) errors.push(`${at}.duty: 未知点位 ${d.spot}`);
    else if (!sp.actions.some((a) => map.actions.find((x) => x.id === a)?.duty)) errors.push(`${at}.duty: 点位 ${d.spot} 上没有日程行动（actions 里要有 duty）`);
    if (!(Array.isArray(d.arrive) && d.arrive.length === 2 && d.arrive[0] < d.arrive[1] && d.arrive[1] < d.until)) errors.push(`${at}.duty: 需要 arrive: [从, 到] 且早于 until`);
    if (!d.label) errors.push(`${at}.duty: 需要 label`);
    checkDeltas(`${at}.duty.needs`, d.needs, NEED_KEYS);
    checkDeltas(`${at}.duty.stats`, d.stats, STAT_KEYS);
  }
  return {
    id: t.id, label: t.label, requires: t.requires ?? {},
    duty: d ? { label: d.label, spot: d.spot, arrive: d.arrive, until: d.until, needs: d.needs ?? {}, stats: d.stats ?? {}, money: d.money ?? 0 } : null,
  };
});
if (tracks.length === 0 || Object.keys(tracks.at(-1).requires).length > 0) errors.push("tracks.yaml: 最后一条是兜底的路，不能有 requires");
if (new Set(tracks.map((t) => t.id)).size !== tracks.length) errors.push("tracks.yaml: id 重复");
const milestones = events.filter((e) => e.kind === "milestone");
if (new Set(milestones.map((e) => e.age)).size !== milestones.length) errors.push("milestones: 同一个年纪只能有一个关口");

const orphan = consumed.filter(([, f]) => !produced.has(f));
for (const [where, f] of orphan) errors.push(`${where}: 要求标记 "${f}"，但没有任何人家、天赋、选项或共鸣会打上它（多半是拼错了）`);

if (errors.length) {
  console.error(`内容校验失败（${errors.length} 处）：\n  - ` + errors.join("\n  - "));
  process.exit(1);
}

// 内容版本 = 内容本身的指纹。服务器在 lifeline_open 里报出它的版本，客户端发现和自己带的不一样，
// 就用 content_get 把服务器这份下载下来用（改剧情只需要更新服务器，不用两台手机重装 APK）。
const body = { events, families, talents, map, tracks, endings, rules, checks };
const version = createHash("sha256").update(JSON.stringify(body)).digest("hex").slice(0, 12);
const content = { version, ...body };
const json = JSON.stringify(content, null, 1);
writeFileSync(join(root, "client", "data", "content.json"), json + "\n");
writeFileSync(
  join(root, "server", "src", "content.generated.ts"),
  `// 由 tools/build-content.mjs 生成，请修改 content/*.yaml 后运行 npm run content\n` +
    `var CONTENT: Content = ${json};\n`,
);
const by = (k) => events.filter((e) => e.stage === k).length;
console.log(`✓ ${events.length} 个事件  ` + STAGES.map((s) => `${s}:${by(s)}`).join("  ") +
  `  |  ${families.length} 户人家  ${talents.length} 种天赋  ${map.zones.length} 个地点  ${map.actions.length} 种行动  ${tracks.length} 条路  ${milestones.length} 个关口` +
  `  |  结局 ${endings.pair.length} 种 · 一生 ${endings.lives.length} 种  |  检定 ${checks.length} 处  |  版本 ${version}`);
