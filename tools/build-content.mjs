#!/usr/bin/env node
// 把 content/ 下的 YAML 编译成：
//   client/data/content.json         客户端读取（画地图、显示文字）
//   server/src/content.generated.ts  服务端结算（Nakama JS 运行时不方便读文件，直接内联）
// 另有 duet.yaml：两个人之间一抛一接的内容（搭上了 / 猜 TA / 回话），挂到事件的 catches 和 content.duet 上
// 包含：events/*.yaml 剧情事件、families.yaml 家庭、talents.yaml 天赋、map.yaml 地图与行动、endings.yaml 结局
// 传承（server/src/legacy.ts）：heirlooms.yaml 老物件、remembered.yaml 街坊记住的事、events/legacy.yaml 隔世的事
//   client/data/street.json          街景（street.yaml：街坊、车，随年代更替；只给客户端，不进结算也不进内容版本）
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
// 老物件的条件比一生小结多两样（server/src/legacy.ts → legacyPersonOk）
const HEIRLOOM_REQ_KEYS = [...LIFE_REQ_KEYS, "anyStat", "minMoney"];
const HEIRLOOM_KEYS = ["id", "name", "desc", "from", "bonus", "money", "close", "flags"];
// 老物件不占投胎的点数，所以要小（见 content/heirlooms.yaml 文件头）
const HEIRLOOM_MAX_BONUS = 0.5;
// 开局从上一世带来的钱，老物件和家业加起来的上限。买房那条线很陡（十块钱在线附近差十来个点），钱得是这辈子挣的
const LEGACY_MAX_MONEY = 10;
// 传承的规则（server/src/legacy.ts）按名字读的标记：接了家业、找工作那一关走的路。内容里改了名，家业和小传会悄悄失效
const LEGACY_ENGINE_FLAGS = ["took_over", "job_desk", "job_teach", "job_trade", "job_craft", "job_labor", "job_odd"];
// 人生结束时规则算出来的标记（legacyDerive），结局和街坊记住的事可以读；出生时带上的 leg_any / leg_house（legacyBirth）
const LEGACY_DERIVED_FLAGS = ["x_same_year", "x_opposites", "x_many_mirrors", "x_same_trade", "x_plain_life"];
const LEGACY_BIRTH_FLAGS = ["leg_any", "leg_house"];
// 藏着的天赋的效果按这几个标记给（legacy.ts 末尾那几个函数）
const LEGACY_TALENT_FLAGS = ["tal_late", "tal_linked", "tal_oldsoul"];
// 街坊记住的事：十几条，记的是活法。条件里不许出现属性和钱；标题和那一句话都要短
const REMEMBERED_KEYS = ["id", "title", "desc", "who", "requires"];
const REMEMBERED_PAIR_KEYS = [...PAIR_REQ_KEYS, "minHelps"];
const REMEMBERED_PERSON_KEYS = ["flags", "notFlags", "minDiedAge", "maxDiedAge"];
const REMEMBERED_MAX = 19;

// 每一层允许出现的字段。写错字段名（比如 require / option / effect）以前会被悄悄丢掉，
// 事件就变成「没有条件」「没有效果」；现在直接报错。加新字段时先加到这里，再去 types.ts 和 sim.ts 里用它。
const EVENT_KEYS = ["id", "kind", "stage", "where", "when", "hint", "seasons", "weight", "requires", "title", "text", "options", "resonance", "dissonance"];
// 关口（kind: milestone）多出来的字段，见 content/events/milestones.yaml 文件头
const MILESTONE_KEYS = [...EVENT_KEYS, "age", "score", "swing", "grades"];
const MILESTONE_OPTION_KEYS = ["id", "text", "tags", "effects", "min", "score", "cost", "requires", "lock", "joins"];
const SCORE_KEYS = ["body", "mind", "charm", "luck", "money", "close"];
const GRADE_KEYS = ["min", "label", "flags"];
const TRACK_KEYS = ["id", "label", "requires", "group", "duty"];
const TRACK_REQ_KEYS = ["minAge", "maxAge", "flags", "notFlags"];
const DUTY_KEYS = ["label", "spot", "arrive", "until", "needs", "stats", "money"];
const OPTION_KEYS = ["id", "text", "tags", "effects"];
const EFFECT_KEYS = ["self", "other", "bond", "flags"];
const RESONANCE_KEYS = ["text", "memory", "bond", "flags"];
const DISSONANCE_KEYS = ["text", "bond", "flags"];
const FAMILY_KEYS = ["id", "name", "wealth", "weight", "money", "desc", "bonus", "traits"];
const TALENT_KEYS = ["id", "name", "weight", "desc", "bonus", "flags", "unlock"];
const ENDING_KEYS = ["id", "title", "text", "requires"];
const MAP_KEYS = ["size", "spawn", "zones", "spots", "actions"];
const ZONE_KEYS = ["id", "name", "rect", "owner"];
const SPOT_KEYS = ["id", "zone", "at", "action", "actions"];
const ACTION_KEYS = ["id", "label", "minutes", "sleep", "duty", "requires", "needs", "stats", "money", "together", "bring"];
const ACTION_REQ_KEYS = ["minAge", "maxAge", "owner", "hours", "flags", "notFlags"];
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
        // lock：标记不对的人看到的那句（「家里拿不出这笔钱」）。只有挂了标记条件的路才用得上
        if (o.lock !== undefined && (typeof o.lock !== "string" || !(o.requires?.flags?.length || o.requires?.notFlags?.length))) errors.push(`${oat}.lock: 是一句话，只能写在带 requires 的选项上`);
        if (o.lock && [...o.lock].length > 12) errors.push(`${oat}.lock: 不超过 12 个字`);
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
    for (const o of ev.options ?? []) {
      if (o.joins !== undefined && (!optionIds.has(o.joins) || o.joins === o.id || ev.options.find((x) => x.id === o.joins)?.joins)) errors.push(`${at}.${o.id}.joins: 要写同一关里另一条不带 joins 的路`);
      if (o.joins && ev.resonance?.[o.id]) errors.push(`${at}.resonance.${o.id}: 这条路 joins ${o.joins}，同路的共鸣写在 ${o.joins} 下面`);
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
  // 内容里读家境只认这两个标记（docs/MEANS.md），所以它们必须和 wealth 一一对应
  const tr = f.traits ?? [];
  if ((f.wealth === 2) !== tr.includes("fam_rich")) errors.push(`families#${f.id}: 殷实人家（wealth 2）必须带 fam_rich，别的人家不能带`);
  if ((f.wealth === 0) !== tr.includes("fam_poor")) errors.push(`families#${f.id}: 清贫人家（wealth 0）必须带 fam_poor，别的人家不能带`);
  checkKeys(`families#${f.id}`, f, FAMILY_KEYS);
  checkDeltas(`families#${f.id}.bonus`, f.bonus, STAT_KEYS);
  return { id: f.id, name: f.name, wealth: f.wealth, weight: f.weight ?? 1, money: f.money ?? 0, desc: f.desc ?? "", bonus: f.bonus ?? {}, traits: f.traits ?? [] };
});
const talents = load("talents.yaml").map((t) => {
  checkDeltas(`talents#${t.id}.bonus`, t.bonus, STAT_KEYS);
  checkKeys(`talents#${t.id}`, t, TALENT_KEYS);
  // 藏着的天赋：unlock 是一个标记，这条人生线上有人带过它，往后才抽得到
  if (t.unlock != null) {
    if (typeof t.unlock !== "string") errors.push(`talents#${t.id}.unlock: 必须是一个标记`);
    else consumed.push([`talents#${t.id}.unlock`, t.unlock]);
  }
  return { id: t.id, name: t.name, weight: t.weight ?? 1, desc: t.desc ?? "", bonus: t.bonus ?? {}, flags: t.flags ?? [], unlock: t.unlock ?? null };
});
if (talents.filter((t) => !t.unlock).length === 0) errors.push("talents.yaml: 至少要有一种不用解开的天赋（头一世要抽得到）");
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
    growth: ["eventScale", "actionScale", "room", "floor", "bornWeight", "plasticity", "plainBonus"],
    aging: ["body", "mind", "activeFactor"],
    daily: ["bodyEnergy", "charmTogether", "luckFate", "wageFlags"],
    check: ["base", "perPoint", "luck", "min", "max", "help"],
    lifespan: ["base", "spread", "body", "moodMid", "moodStep", "moodMin", "moodMax", "bondClose", "bond", "widowClose", "widow", "min", "max", "flags"],
    bond: ["closeSoft", "closeFloor", "closeScale", "syncSoft", "syncFloor", "syncSteady", "drift", "driftDistance", "driftFloor"],
    legacy: ["pastKept", "heirloomOffer", "houseMax", "houseMoney", "lateEarly", "lateAfter", "lateRoom", "linkedDrift", "linkedMood", "oldSoul", "oldSoulCharm"],
  };
  checkKeys("rules", rules, Object.keys(need));
  for (const [sec, keys] of Object.entries(need)) {
    if (!rules?.[sec]) { errors.push(`rules.yaml: 缺少 ${sec}`); continue; }
    checkKeys(`rules.${sec}`, rules[sec], keys);
    for (const k of keys) if (rules[sec][k] === undefined) errors.push(`rules.yaml: 缺少 ${sec}.${k}`);
  }
  if (rules?.bond && (typeof rules.bond.syncSteady !== "number" || rules.bond.syncSteady < 0 || rules.bond.syncSteady > 1)) errors.push("rules.yaml: bond.syncSteady 是默契替考场托住的那一份，要在 0 到 1 之间");
  for (const [f, mul] of Object.entries(rules?.daily?.wageFlags ?? {})) {
    consumed.push(["rules.daily.wageFlags", f]);
    if (typeof mul !== "number" || mul < 1 || mul > 2) errors.push(`rules.yaml: daily.wageFlags.${f} 是工钱的倍数，要在 1 到 2 之间`);
  }
  // 关口上走的路折成的寿数：标记拼错了要报（没有任何选项打这个标记）
  for (const [f, years] of Object.entries(rules?.lifespan?.flags ?? {})) {
    consumed.push(["rules.lifespan.flags", f]);
    if (typeof years !== "number" || Math.abs(years) > 4) errors.push(`rules.yaml: lifespan.flags.${f} 必须是数字，而且一条路最多折 4 年`);
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

// ---------- 传承：老物件 ----------
const heirlooms = (load("heirlooms.yaml") ?? []).map((h) => {
  const at = `heirlooms#${h.id ?? "?"}`;
  checkKeys(at, h, HEIRLOOM_KEYS);
  if (!h.id || !h.name || !h.desc) errors.push(`${at}: 需要 id / name / desc`);
  checkRequires(at, h.from, HEIRLOOM_REQ_KEYS);
  checkDeltas(`${at}.bonus`, h.bonus, STAT_KEYS);
  const sum = Object.values(h.bonus ?? {}).reduce((a, b) => a + b, 0);
  if (sum > HEIRLOOM_MAX_BONUS || Object.values(h.bonus ?? {}).some((v) => v < 0)) errors.push(`${at}: bonus 合计不能超过 ${HEIRLOOM_MAX_BONUS}，也不能是负的`);
  if ((h.money ?? 0) < 0 || (h.money ?? 0) > LEGACY_MAX_MONEY) errors.push(`${at}: money 要在 0~${LEGACY_MAX_MONEY} 之间`);
  for (const f of h.flags ?? []) produced.add(f);
  return { id: h.id, name: h.name, desc: h.desc, from: h.from ?? {}, bonus: h.bonus ?? {}, money: h.money ?? 0, close: h.close ?? 0, flags: h.flags ?? [] };
});
if (heirlooms.length === 0 || Object.keys(heirlooms.at(-1).from).length > 0) errors.push("heirlooms.yaml: 最后一件是兜底，不能有 from 条件（每个人都得留下点什么）");
if (new Set(heirlooms.map((h) => h.id)).size !== heirlooms.length) errors.push("heirlooms.yaml: id 重复");
{
  const lg = rules.legacy ?? {};
  const most = (lg.houseMoney ?? 0) * (lg.houseMax ?? 0) + Math.max(0, ...heirlooms.map((h) => h.money));
  if (most > LEGACY_MAX_MONEY) errors.push(`传承：家业（${lg.houseMoney} × ${lg.houseMax}）加上最值钱的老物件，开局一共能多 ${most} 块，超过了 ${LEGACY_MAX_MONEY} 块`);
}
for (const f of LEGACY_ENGINE_FLAGS) if (!produced.has(f)) errors.push(`传承：没有任何选项会打上标记 "${f}"（规则代码按这个名字读它，见 server/src/legacy.ts）`);
for (const f of LEGACY_TALENT_FLAGS) if (!produced.has(f)) errors.push(`传承：没有任何天赋带标记 "${f}"（藏着的天赋的效果按这个名字给，见 server/src/legacy.ts）`);

// ---------- 传承：街坊记住的事 ----------
const remembered = (load("remembered.yaml") ?? []).map((a) => {
  const at = `remembered#${a.id ?? "?"}`;
  checkKeys(at, a, REMEMBERED_KEYS);
  const who = a.who ?? "pair";
  if (!["pair", "each", "both"].includes(who)) errors.push(`${at}: who 必须是 pair / each / both`);
  checkRequires(at, a.requires, who === "pair" ? REMEMBERED_PAIR_KEYS : REMEMBERED_PERSON_KEYS);
  const count = (t) => [...String(t ?? "")].length;
  if (!a.id || !a.title || !a.desc) errors.push(`${at}: 需要 id / title / desc`);
  if (count(a.title) > 7) errors.push(`${at}.title: ${count(a.title)} 字，超过 7 字`);
  if (count(a.desc) > 32) errors.push(`${at}.desc: ${count(a.desc)} 字，超过 32 字`);
  if (Object.keys(a.requires ?? {}).length === 0) errors.push(`${at}: 需要 requires（白给的不叫记住）`);
  return { id: a.id, title: a.title, desc: a.desc, who, requires: a.requires ?? {} };
});
if (new Set(remembered.map((a) => a.id)).size !== remembered.length) errors.push("remembered.yaml: id 重复");
if (remembered.length > REMEMBERED_MAX) errors.push(`remembered.yaml: ${remembered.length} 条，超过 ${REMEMBERED_MAX} 条（要的是十几条记得住的事，不是一张清单）`);

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
  for (const k of ["flags", "notFlags"]) if (a.requires?.[k] && !Array.isArray(a.requires[k])) errors.push(`map.actions#${a.id}.requires.${k}: 必须是列表`);
  // 客户端和服务器都按 hours[0]、hours[1] 读：形状不对的在这里拦下
  if (a.requires?.hours !== undefined) {
    const h = a.requires.hours;
    if (!(Array.isArray(h) && h.length === 2 && h.every((x) => typeof x === "number" && x >= 0 && x <= 1440) && h[0] < h[1])) errors.push(`map.actions#${a.id}.requires.hours: 应为 [起始分钟, 结束分钟]，0~1440，起小于止`);
  }
  for (const f of a.requires?.flags ?? []) consumed.push([`map.actions#${a.id}`, f]);
  if ((a.requires?.flags || a.requires?.notFlags) && (a.sleep || a.duty)) errors.push(`map.actions#${a.id}: 睡觉和日程不能挂标记条件`);
  // bring：标记够的人正在做，对门跟过去也能做，钱由带的人出（server/src/means.ts）
  if (a.bring !== undefined && (a.bring !== true || !a.requires?.flags?.length)) errors.push(`map.actions#${a.id}.bring: 只能写 true，而且要挂 requires.flags（谁带谁）`);
  return {
    id: a.id, label: a.label, minutes: a.minutes ?? 0, sleep: !!a.sleep, duty: !!a.duty,
    requires: a.requires ?? {}, needs: a.needs ?? {}, stats: a.stats ?? {}, money: a.money ?? 0,
    together: a.together ? { needs: a.together.needs ?? {}, bond: a.together.bond ?? {}, text: a.together.text ?? "" } : null,
    bring: !!a.bring,
  };
});
// ---------- 接话（duet.yaml）：搭上了 / 猜 TA / 回话 ----------
// 「搭上了」按事件 id 写在 duet.yaml 里（不改事件文件），这里挂到事件的 catches 上。
const duetRaw = load("duet.yaml") ?? {};
const len = (t) => [...String(t ?? "")].length;
const needText = (where, t, max) => {
  if (!t || typeof t !== "string") errors.push(`${where}: 缺少文字`);
  else if (len(t) > max) errors.push(`${where}: ${len(t)} 字，超过 ${max} 字（${t}）`);
};
checkKeys("duet.yaml", duetRaw, ["catches", "lines", "echo", "epitaph"]);
const eventById = new Map(events.map((e) => [e.id, e]));
for (const ev of events) ev.catches = [];
let catchCount = 0;
for (const [eventId, list] of Object.entries(duetRaw.catches ?? {})) {
  const ev = eventById.get(eventId);
  if (!ev) { errors.push(`duet.catches#${eventId}: 没有这个事件`); continue; }
  if (ev.kind !== "mirror") { errors.push(`duet.catches#${eventId}: 只有 mirror 事件才有「搭上了」`); continue; }
  const optionIds = new Set(ev.options.map((o) => o.id));
  const pairs = new Set();
  for (const [i, c] of (list ?? []).entries()) {
    const at = `duet.catches#${eventId}[${i}]`;
    checkKeys(at, c, ["pair", "text", "memory", "bond", "flags"]);
    if (!Array.isArray(c.pair) || c.pair.length !== 2 || c.pair[0] === c.pair[1]) { errors.push(`${at}: pair 应为两个不同的选项 id`); continue; }
    for (const o of c.pair) if (!optionIds.has(o)) errors.push(`${at}: 事件里没有选项 ${o}`);
    const key = [...c.pair].sort().join("+");
    if (pairs.has(key)) errors.push(`${at}: 这一对写了两遍`);
    pairs.add(key);
    needText(`${at}.text`, c.text, 48);
    if (c.memory != null) needText(`${at}.memory`, c.memory, 8);
    checkDeltas(`${at}.bond`, c.bond, BOND_KEYS);
    ev.catches.push({ pair: c.pair, text: c.text, memory: c.memory ?? null, bond: c.bond ?? {}, flags: checkPairFlags(at, c.flags) });
    catchCount++;
  }
}
const duetTexts = (name, keys) => {
  checkKeys(`duet.${name}`, duetRaw[name], keys.concat(name === "epitaph" ? ["last"] : []));
  const out = {};
  for (const k of keys) { needText(`duet.${name}.${k}`, duetRaw[name]?.[k], 40); out[k] = duetRaw[name]?.[k] ?? ""; }
  return out;
};
const duet = {
  lines: duetTexts("lines", ["knew_both_same", "knew_both_diff", "knew_one", "knew_none", "knew_single"]),
  echo: duetTexts("echo", ["ask", "res", "catch", "miss", "like", "unlike", "knew", "kept", "told"]),
  epitaph: duetTexts("epitaph", ["know", "shadow"]),
};
duet.epitaph.last = (duetRaw.epitaph?.last ?? []).map((l, i) => {
  needText(`duet.epitaph.last[${i}]`, l.text, 40);
  if (typeof l.minRate !== "number") errors.push(`duet.epitaph.last[${i}]: 需要 minRate`);
  return { minRate: l.minRate ?? 0, text: l.text ?? "" };
});
if (duet.epitaph.last.length === 0 || duet.epitaph.last.at(-1).minRate !== 0) errors.push("duet.epitaph.last: 最后一条的 minRate 必须是 0（兜底）");

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
    id: t.id, label: t.label, requires: t.requires ?? {}, group: t.group ?? null,
    duty: d ? { label: d.label, spot: d.spot, arrive: d.arrive, until: d.until, needs: d.needs ?? {}, stats: d.stats ?? {}, money: d.money ?? 0 } : null,
  };
});
if (tracks.length === 0 || Object.keys(tracks.at(-1).requires).length > 0) errors.push("tracks.yaml: 最后一条是兜底的路，不能有 requires");
if (new Set(tracks.map((t) => t.id)).size !== tracks.length) errors.push("tracks.yaml: id 重复");
const milestones = events.filter((e) => e.kind === "milestone");
if (new Set(milestones.map((e) => e.age)).size !== milestones.length) errors.push("milestones: 同一个年纪只能有一个关口");
// 每个关口都要有一条谁都走得了的路：不带线、不要钱、不看标记。没有的话，属性低的人到了这一关无路可走
const hasKeys = (x) => !!x && Object.values(x).some((v) => (Array.isArray(v) ? v.length > 0 : v != null));
for (const ev of milestones) {
  if (!ev.options.some((o) => !o.min && !o.cost && !hasKeys(o.requires))) errors.push(`milestones#${ev.id}: 至少要有一个不带 min / cost / requires 的选项（兜底的路）`);
}

// ---------- 传承：留给下一世的痕迹、能解开天赋的事 ----------
// 规则自己会打的标记，内容里不能发（发了分不清是谁打的）
for (const f of produced) {
  if (String(f).startsWith("leg_") || String(f).startsWith("x_")) errors.push(`标记 "${f}"：leg_ 和 x_ 开头的由规则打（server/src/legacy.ts），内容里不能发`);
}
for (const f of [...LEGACY_DERIVED_FLAGS, ...LEGACY_BIRTH_FLAGS]) produced.add(f);
// 内容里谁要求了 leg_<共同标记>，那个共同标记就会留给下一世（上一世两个人一起做过，这一世出生就带着 leg_ 标记）
const legacyTraces = [];
for (const [where, f] of consumed) {
  if (!String(f).startsWith("leg_") || LEGACY_BIRTH_FLAGS.includes(f)) continue;
  const from = String(f).slice(4);
  if (!from.startsWith("p_")) errors.push(`${where}: "${f}" 只能接共同标记（leg_p_…），上一世两个人一起做过的事才留得下来`);
  else if (!produced.has(from)) errors.push(`${where}: "${f}" 对应的共同标记 "${from}" 没有任何共鸣会打上`);
  else {
    if (!legacyTraces.includes(from)) legacyTraces.push(from);
    produced.add(f);
  }
}
legacyTraces.sort();
const legacyMarks = [...new Set(talents.filter((t) => t.unlock).map((t) => t.unlock))].sort();

const orphan = consumed.filter(([, f]) => !produced.has(f));
for (const [where, f] of orphan) errors.push(`${where}: 要求标记 "${f}"，但没有任何人家、天赋、选项或共鸣会打上它（多半是拼错了）`);

// ---------- 街景：街坊、摊子、车，随年代更替（只给客户端，不进服务端） ----------
const street = load("street.yaml");
{
  const spritesPath = join(root, "client", "art", "street", "sprites.json");
  let sprites = null;
  try { sprites = JSON.parse(readFileSync(spritesPath, "utf8")).sprites; } catch { /* 美术还没生成时不查精灵名 */ }
  const checkCommon = (at, o) => {
    if (!o.id) errors.push(`${at}: 缺少 id`);
    if (!o.sprite) errors.push(`${at}: 缺少 sprite`);
    else if (sprites && !sprites[o.sprite]) errors.push(`${at}: 没有精灵 ${o.sprite}（先在 tools/art/street.py 里画，再运行它）`);
    for (const e of o.eras ?? []) if (!STAGES.includes(e)) errors.push(`${at}: eras 里的 ${e} 不是人生阶段（${STAGES.join(" / ")}）`);
    if (o.hours && !(Array.isArray(o.hours) && o.hours.length === 2)) errors.push(`${at}: hours 应为 [起始分钟, 结束分钟]`);
    for (const k of Object.keys(o.lines ?? {})) if (k !== "default" && !STAGES.includes(k)) errors.push(`${at}: lines.${k} 不是人生阶段，也不是 default`);
    if (o.lines && !o.name) errors.push(`${at}: 会说话的要有 name`);
  };
  const ids = new Set();
  for (const st of STAGES) if (!street.eras?.[st]?.name) errors.push(`street.eras.${st}: 缺少 name`);
  for (const [part, list] of [["npcs", street.npcs ?? []], ["props", street.props ?? []]]) {
    for (const o of list) {
      const at = `street.${part}#${o.id ?? "?"}`;
      checkCommon(at, o);
      if (ids.has(o.id)) errors.push(`${at}: id 重复`);
      ids.add(o.id);
      if (!(Array.isArray(o.at) && o.at.length === 2)) errors.push(`${at}: at 应为 [x, y]`);
      if (o.hide_when && !actionIds.has(o.hide_when)) errors.push(`${at}: hide_when 未知行动 ${o.hide_when}`);
    }
  }
  for (const t of street.traffic ?? []) {
    const at = `street.traffic#${t.id ?? "?"}`;
    checkCommon(at, t);
    if (!["pass", "taxi"].includes(t.kind)) errors.push(`${at}: kind 必须是 pass / taxi`);
    if (!(t.speed > 0) || typeof t.lane !== "number") errors.push(`${at}: 需要 lane（y 坐标）和 speed`);
    if (!(Array.isArray(t.gap) && t.gap.length === 2)) errors.push(`${at}: gap 应为 [最短秒, 最长秒]`);
  }
}

if (errors.length) {
  console.error(`内容校验失败（${errors.length} 处）：\n  - ` + errors.join("\n  - "));
  process.exit(1);
}

// 内容版本 = 内容本身的指纹。服务器在 lifeline_open 里报出它的版本，客户端发现和自己带的不一样，
// 就用 content_get 把服务器这份下载下来用（改剧情只需要更新服务器，不用两台手机重装 APK）。
const body = { events, families, talents, map, tracks, endings, rules, checks, duet, heirlooms, remembered, legacy: { traces: legacyTraces, marks: legacyMarks } };
const version = createHash("sha256").update(JSON.stringify(body)).digest("hex").slice(0, 12);
const content = { version, ...body };
const json = JSON.stringify(content, null, 1);
writeFileSync(join(root, "client", "data", "content.json"), json + "\n");
writeFileSync(
  join(root, "server", "src", "content.generated.ts"),
  `// 由 tools/build-content.mjs 生成，请修改 content/*.yaml 后运行 npm run content\n` +
    `var CONTENT: Content = ${json};\n`,
);
writeFileSync(join(root, "client", "data", "street.json"), JSON.stringify(street, null, 1) + "\n");
const by = (k) => events.filter((e) => e.stage === k).length;
console.log(`✓ ${events.length} 个事件  ` + STAGES.map((s) => `${s}:${by(s)}`).join("  ") +
  `  |  ${families.length} 户人家  ${talents.length} 种天赋  ${map.zones.length} 个地点  ${map.actions.length} 种行动  ${tracks.length} 条路  ${milestones.length} 个关口` +
  `  |  结局 ${endings.pair.length} 种 · 一生 ${endings.lives.length} 种  |  检定 ${checks.length} 处  |  搭上了 ${catchCount} 组` +
  `  |  老物件 ${heirlooms.length} 件  街坊记住的事 ${remembered.length} 条  痕迹 ${legacyTraces.length} 种  藏着的天赋 ${talents.filter((t) => t.unlock).length} 种  |  版本 ${version}`);
