#!/usr/bin/env node
// 地点内容的校验：content/maps/*.yaml 和 content/events/places/*.yaml。
//
// 横版多地图的 loader 接进 build-content 以前，这两处不进内容构建，所以先用这个脚本看着：
//   node tools/check-places.mjs
// 查的是：字段名、引用（点位上的行动、出口、事件的 where）、字数上限（docs/tianjin_style.md §9.1 和 §4.1）、
// 方言预算（§1.2：旁白和选项不用；对白一个事件至多一个；带方言的事件不超过四分之一）、事件 id 不跟已有的撞。
// loader 接上以后，build-content 会接管前两项，这个脚本可以删掉或只留文风那部分。
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => parse(readFileSync(join(root, p), "utf8"));
const yamls = (d) => (existsSync(join(root, d)) ? readdirSync(join(root, d)).filter((f) => f.endsWith(".yaml")).sort() : []);

const SCENES = ["building", "street", "river", "primary", "middle", "across", "away", "newhome", "rental", "park", "hospital", "market", "seaside", "village"];
const ERAS = ["childhood", "teen", "young", "middle", "old"];
const SLOTS = ["morning", "am", "pm", "evening", "night"];
const TAGS = ["gentle", "adventure", "solitude", "responsible", "competitive", "patient"];
// trip / seen：门外的世界（server/src/outside.ts）。trip 的图只有事件的 goto 送得来，seen 是来过的人打上的标记
const MAP_KEYS = ["id", "name", "width", "floors", "unlock", "far", "trip", "seen", "areas", "exits", "spots", "npcs", "props", "art"];
const AREA_KEYS = ["id", "name", "span", "floor", "owner"];
const EXIT_KEYS = ["id", "at", "floor", "to", "arrive", "arriveFloor", "label", "ride"];
const SPOT_KEYS = ["id", "at", "area", "actions", "owner"];
const UNLOCK_KEYS = ["minAge", "maxAge", "flags", "notFlags", "any"];
const NPC_KEYS = ["id", "name", "at", "eras", "slots", "lines", "sprite", "hide_when", "phase", "fx"];
const EVENT_KEYS = ["id", "kind", "stage", "where", "when", "hint", "seasons", "weight", "requires", "title", "text", "options", "resonance", "dissonance"];
// 别的线程会加、这边先引用的行动：地图线程（letter 写信）。资源差异线程的四个已经在 content/map.yaml 里
const PENDING_ACTIONS = ["letter"];
// 别的线程会打上的标记：资源差异（fam_factory / school_paid / uni_abroad …）、主线（p_bridge 第一次自己过桥）
const PENDING_FLAGS = ["fam_factory", "school_paid", "uni_abroad", "job_pull", "job_succeed", "home_unit", "p_bridge"];
// 正文上限按阶段（§4.1），其余字段（§9.1）
const TEXT_MAX = { childhood: 60, teen: 55, young: 50, middle: 45, old: 30 };
const MAX = { hint: 15, title: 7, option: 15, resonance: 48, memory: 8, dissonance: 47, line: 30 };
// §13 小词表 + 手册点名不写的词。旁白和选项一个都不许有；对白只许小词表里的
const DIALECT_OK = ["嘛", "倍儿", "哏儿", "甭", "您了", "得嘞"];
const DIALECT_NO = ["介", "崴泥", "打镲", "拔创", "褶子了", "好么", "嚯", "话匣子", "园子", "大了"];

const errors = [];
const warns = [];
const len = (t) => [...String(t ?? "")].length;
const keys = (at, obj, allowed) => { for (const k of Object.keys(obj ?? {})) if (!allowed.includes(k)) errors.push(`${at}: 未知字段 "${k}"`); };
const text = (at, t, max) => { if (!t || typeof t !== "string") errors.push(`${at}: 缺少文字`); else if (len(t) > max) errors.push(`${at}: ${len(t)} 字，超过 ${max}（${t}）`); };
// 引号里的是对白，外面的是旁白
const split = (t) => { const said = [...String(t).matchAll(/「([^」]*)」/g)].map((m) => m[1]).join(" "); return { said, told: String(t).replace(/「[^」]*」/g, "") }; };

// ---------------------------------------------------------------- 已有内容
const mapYaml = read("content/map.yaml");
const actionIds = new Set(mapYaml.actions.map((a) => a.id));
const oldEvents = yamls("content/events").flatMap((f) => read(`content/events/${f}`) ?? []);
const oldIds = new Set(oldEvents.map((e) => e.id));
const produced = new Set(PENDING_FLAGS);
for (const f of read("content/families.yaml")) for (const t of f.traits ?? []) produced.add(t);
for (const t of read("content/talents.yaml")) for (const x of t.flags ?? []) produced.add(x);
for (const ev of oldEvents) {
  for (const o of ev.options ?? []) for (const x of o.effects?.flags ?? []) produced.add(x);
  for (const g of ev.grades ?? []) for (const x of g.flags ?? []) produced.add(x);
  for (const r of Object.values(ev.resonance ?? {})) for (const x of r.flags ?? []) produced.add(x);
}

// ---------------------------------------------------------------- 地图
const maps = new Map();
for (const f of yamls("content/maps")) {
  const m = read(`content/maps/${f}`);
  const at = `maps/${f}`;
  keys(at, m, MAP_KEYS);
  if (m.id !== basename(f, ".yaml")) errors.push(`${at}: id 应与文件名一致`);
  if (!SCENES.includes(m.id)) errors.push(`${at}: 未知 scene ${m.id}`);
  if (!(m.width >= 1920)) errors.push(`${at}: width 至少 1920`);
  const unlocks = m.unlock?.any ?? [m.unlock ?? {}];
  keys(`${at}.unlock`, m.unlock, UNLOCK_KEYS);
  for (const u of unlocks) { keys(`${at}.unlock`, u, UNLOCK_KEYS); for (const x of [...(u.flags ?? []), ...(u.notFlags ?? [])]) if (!produced.has(x)) errors.push(`${at}.unlock: 标记 ${x} 没有人会打上`); }
  const areas = new Set();
  for (const a of m.areas ?? []) {
    keys(`${at}.areas#${a.id}`, a, AREA_KEYS);
    if (areas.has(a.id)) errors.push(`${at}: area ${a.id} 重复`);
    areas.add(a.id);
    const [x0, x1] = a.span ?? [];
    if (!(x0 >= 0 && x1 <= m.width && x0 < x1)) errors.push(`${at}.areas#${a.id}: span 越界`);
    if (!(Number.isInteger(a.floor) && a.floor >= 0 && a.floor < (m.floors?.length ?? 1))) errors.push(`${at}.areas#${a.id}: floor 不对`);
  }
  const byFloor = (m.areas ?? []).slice().sort((p, q) => p.floor - q.floor || p.span[0] - q.span[0]);
  for (let i = 1; i < byFloor.length; i++) if (byFloor[i].floor === byFloor[i - 1].floor && byFloor[i].span[0] < byFloor[i - 1].span[1]) errors.push(`${at}: ${byFloor[i - 1].id} 和 ${byFloor[i].id} 在同一层上重叠`);
  const areaById = new Map((m.areas ?? []).map((a) => [a.id, a]));
  for (const e of m.exits ?? []) { keys(`${at}.exits#${e.id}`, e, EXIT_KEYS); if (!SCENES.includes(e.to)) errors.push(`${at}.exits#${e.id}: 未知去处 ${e.to}`); if (!(e.at >= 0 && e.at <= m.width)) errors.push(`${at}.exits#${e.id}: at 越界`); if (typeof e.arrive !== "number") errors.push(`${at}.exits#${e.id}: 要写 arrive`); }
  for (const s of m.spots ?? []) {
    keys(`${at}.spots#${s.id}`, s, SPOT_KEYS);
    const ar = areaById.get(s.area);
    if (!ar) errors.push(`${at}.spots#${s.id}: 没有 area ${s.area}`);
    else if (!(s.at >= ar.span[0] && s.at <= ar.span[1])) errors.push(`${at}.spots#${s.id}: at 不在 ${s.area} 里`);
    if (!Array.isArray(s.actions) || !s.actions.length) errors.push(`${at}.spots#${s.id}: 至少一个行动`);
    for (const a of s.actions ?? []) if (!actionIds.has(a) && !PENDING_ACTIONS.includes(a)) errors.push(`${at}.spots#${s.id}: 没有行动 ${a}`);
    for (const a of s.actions ?? []) if (PENDING_ACTIONS.includes(a) && !actionIds.has(a)) warns.push(`${at}.spots#${s.id}: ${a} 等别的线程加`);
  }
  for (const n of [...(m.npcs ?? []), ...(m.props ?? [])]) {
    keys(`${at}.npcs#${n.id}`, n, NPC_KEYS);
    for (const e of n.eras ?? []) if (!ERAS.includes(e)) errors.push(`${at}.npcs#${n.id}: 未知年代 ${e}`);
    for (const s of n.slots ?? []) if (!SLOTS.includes(s)) errors.push(`${at}.npcs#${n.id}: 未知时段 ${s}`);
    for (const [era, ls] of Object.entries(n.lines ?? {})) {
      if (era !== "default" && !ERAS.includes(era)) errors.push(`${at}.npcs#${n.id}.lines: 未知年代 ${era}`);
      for (const l of ls) { text(`${at}.npcs#${n.id}.lines.${era}`, l, MAX.line); for (const w of DIALECT_NO) if (l.includes(w)) errors.push(`${at}.npcs#${n.id}: 不用「${w}」（${l}）`); }
    }
  }
  if (m.seen) produced.add(m.seen); // 引擎打（outside.ts → outsideSeen）
  maps.set(m.id, { areas, owners: new Set((m.areas ?? []).filter((a) => a.owner).map((a) => a.id)), exits: m.exits ?? [], trip: !!m.trip });
}
for (const s of SCENES) if (!maps.has(s)) warns.push(`maps: 还没有 ${s}.yaml`);
// 每个出口都要有回来的那一个：从 A 的 (at, floor) 去 B 的 (arrive, arriveFloor)，B 里得有一个出口去 A，落脚点就在 A 那个出口附近
// 坐车回来、在车站下车的（海边、乡下、医院坐车回家）：落脚点 200 以内有一个坐车的出口（车站）就不用回去的那一个（同 build-content）
const atStation = (e) => e.ride > 0 && (maps.get(e.to)?.exits ?? []).some((b) => b.ride > 0 && Math.abs(b.at - e.arrive) <= 200 && (b.floor ?? 0) === (e.arriveFloor ?? 0));
for (const [id, m] of maps) for (const e of m.exits) if (maps.get(e.to)?.trip) errors.push(`maps/${id}.exits#${e.id}: ${e.to} 是出门才到得了的图（trip），出口不许指进去`);
for (const [id, m] of maps) for (const e of m.exits) {
  if (atStation(e)) continue;
  const back = maps.get(e.to)?.exits.find((b) => b.to === id && Math.abs(b.arrive - e.at) <= 120 && (b.arriveFloor ?? 0) === (e.floor ?? 0));
  if (maps.has(e.to) && !back) errors.push(`maps/${id}.exits#${e.id}: ${e.to} 里没有回来的出口`);
}

// ---------------------------------------------------------------- 事件
let total = 0;
let withDialect = 0;
const seen = new Set();
for (const f of yamls("content/events/places")) {
  const scene = basename(f, ".yaml");
  const map = maps.get(scene);
  if (!map) errors.push(`events/places/${f}: 没有对应的 maps/${scene}.yaml`);
  for (const ev of read(`content/events/places/${f}`) ?? []) {
    const at = `places/${f}#${ev.id}`;
    total++;
    keys(at, ev, EVENT_KEYS);
    if (seen.has(ev.id) || oldIds.has(ev.id)) errors.push(`${at}: id 重复`);
    seen.add(ev.id);
    if (!["mirror", "solo"].includes(ev.kind)) errors.push(`${at}: kind 只能是 mirror / solo`);
    if (!TEXT_MAX[ev.stage]) errors.push(`${at}: 未知 stage`);
    if (ev.where && map && !map.areas.has(ev.where)) errors.push(`${at}: where 不在 ${scene} 的 areas 里（${ev.where}）`);
    if (ev.kind === "mirror" && !ev.where) errors.push(`${at}: mirror 要写 where`);
    if (ev.kind === "mirror" && map?.owners.has(ev.where)) errors.push(`${at}: mirror 不能放在某一家屋里`);
    if (ev.seasons && ev.stage !== "childhood") errors.push(`${at}: 只有童年有季节`);
    if (ev.when && !(ev.when.length === 2 && ev.when[0] < ev.when[1])) errors.push(`${at}: when 应为 [起, 止]`);
    for (const x of [...(ev.requires?.flags ?? []), ...(ev.requires?.notFlags ?? [])]) if (!produced.has(x)) errors.push(`${at}: 标记 ${x} 没有人会打上`);
    if (ev.hint) text(`${at}.hint`, ev.hint, MAX.hint);
    text(`${at}.title`, ev.title, MAX.title);
    text(`${at}.text`, ev.text, TEXT_MAX[ev.stage] ?? 60);
    const opts = new Set();
    if (!(ev.options?.length >= 2)) errors.push(`${at}: 至少两个选项`);
    for (const o of ev.options ?? []) {
      text(`${at}.${o.id}`, o.text, MAX.option);
      opts.add(o.id);
      for (const t of o.tags ?? []) if (!TAGS.includes(t)) errors.push(`${at}.${o.id}: 未知标签 ${t}`);
    }
    if (ev.kind === "mirror") {
      for (const [oid, r] of Object.entries(ev.resonance ?? {})) {
        if (!opts.has(oid)) errors.push(`${at}.resonance.${oid}: 没有这个选项`);
        text(`${at}.resonance.${oid}`, r.text, MAX.resonance);
        if (r.memory) text(`${at}.resonance.${oid}.memory`, r.memory, MAX.memory);
      }
      for (const o of opts) if (!ev.resonance?.[o]) warns.push(`${at}: 选项 ${o} 没写共鸣`);
      text(`${at}.dissonance`, ev.dissonance?.text, MAX.dissonance);
      if ((ev.dissonance?.bond?.close ?? 0) > 0) errors.push(`${at}: 新 mirror 的错位亲近给 0 或负`);
    }
    // 方言：旁白（引号外）和选项一个都不许；对白（引号里）一个事件至多一个
    const narr = [ev.hint, ev.text, ...Object.values(ev.resonance ?? {}).map((r) => r.text), ev.dissonance?.text].filter(Boolean);
    let said = 0;
    for (const t of narr) {
      const { said: s, told } = split(t);
      for (const w of [...DIALECT_OK, ...DIALECT_NO]) if (told.includes(w)) errors.push(`${at}: 旁白里有方言词「${w}」（${t}）`);
      for (const w of DIALECT_NO) if (s.includes(w)) errors.push(`${at}: 对白里不用「${w}」`);
      for (const w of DIALECT_OK) if (s.includes(w)) said++;
    }
    for (const o of ev.options ?? []) for (const w of [...DIALECT_OK, ...DIALECT_NO]) if (o.text.includes(w)) errors.push(`${at}.${o.id}: 选项里有方言词「${w}」`);
    if (said > 1) errors.push(`${at}: 对白里方言词 ${said} 个，至多一个`);
    if (said) withDialect++;
  }
}
if (withDialect * 4 > total) errors.push(`方言：${withDialect}/${total} 个事件带方言词，超过四分之一`);

for (const w of warns) console.log(`  · ${w}`);
if (errors.length) {
  for (const e of errors) console.error(`✗ ${e}`);
  console.error(`\n${errors.length} 处问题`);
  process.exit(1);
}
console.log(`✓ ${maps.size} 张图  ${total} 个地点事件（带方言 ${withDialect}）  行动 ${actionIds.size} 种`);
