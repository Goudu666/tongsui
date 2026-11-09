#!/usr/bin/env node
// 把 content/ 下的 YAML 编译成：
//   client/data/content.json         客户端读取（画地图、显示文字）
//   server/src/content.generated.ts  服务端结算（Nakama JS 运行时不方便读文件，直接内联）
// 包含：events/*.yaml 剧情事件、families.yaml 家庭、talents.yaml 天赋、map.yaml 地图与行动
// 同时做基础校验，写剧情时出错能第一时间看到。
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(root, "content", "events");

const STAGES = ["childhood", "teen", "young", "middle", "old"];
const SEASONS = ["spring", "summer", "autumn", "winter"];
const KINDS = ["mirror", "solo"];
const STAT_KEYS = ["body", "mind", "charm", "luck"];
const NEED_KEYS = ["hunger", "energy", "mood", "clean"];
const SELF_KEYS = [...STAT_KEYS, ...NEED_KEYS];
const BOND_KEYS = ["sync", "close", "distance"];

const errors = [];
const events = [];
const seen = new Set();

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
    if (seen.has(ev.id)) errors.push(`${at}: id 重复`);
    seen.add(ev.id);
    if (!KINDS.includes(ev.kind)) errors.push(`${at}: kind 必须是 ${KINDS.join(" / ")}`);
    if (!STAGES.includes(ev.stage)) errors.push(`${at}: stage 必须是 ${STAGES.join(" / ")}`);
    for (const s of ev.seasons ?? []) if (!SEASONS.includes(s)) errors.push(`${at}: 未知季节 ${s}`);
    if (!ev.title || !ev.text) errors.push(`${at}: 缺少 title 或 text`);
    if (ev.kind === "mirror" && !ev.where) errors.push(`${at}: mirror 事件需要 where（两人同时在这个地点才会触发）`);
    if (ev.when && !(Array.isArray(ev.when) && ev.when.length === 2)) errors.push(`${at}: when 应为 [起始分钟, 结束分钟]`);
    if (!Array.isArray(ev.options) || ev.options.length < 2) errors.push(`${at}: 至少两个选项`);
    const optionIds = new Set();
    for (const o of ev.options ?? []) {
      const oat = `${at}.${o.id}`;
      if (!o.id || !o.text) errors.push(`${oat}: 选项缺少 id 或 text`);
      optionIds.add(o.id);
      const e = o.effects ?? {};
      checkDeltas(`${oat}.self`, e.self, SELF_KEYS);
      checkDeltas(`${oat}.other`, e.other, SELF_KEYS);
      checkDeltas(`${oat}.bond`, e.bond, BOND_KEYS);
      o.tags = o.tags ?? [];
      o.effects = { self: e.self ?? {}, other: e.other ?? {}, bond: e.bond ?? {}, flags: e.flags ?? [] };
    }
    if (ev.kind === "mirror") {
      for (const [oid, r] of Object.entries(ev.resonance ?? {})) {
        if (!optionIds.has(oid)) errors.push(`${at}.resonance.${oid}: 没有这个选项`);
        if (!r.text) errors.push(`${at}.resonance.${oid}: 缺少 text`);
        checkDeltas(`${at}.resonance.${oid}.bond`, r.bond, BOND_KEYS);
        r.bond = r.bond ?? {};
      }
      if (!ev.dissonance?.text) errors.push(`${at}: mirror 事件需要 dissonance.text`);
      ev.resonance = ev.resonance ?? {};
      ev.dissonance = { text: ev.dissonance?.text ?? "", bond: ev.dissonance?.bond ?? {} };
    }
    events.push({
      id: ev.id, kind: ev.kind, stage: ev.stage, seasons: ev.seasons ?? [], weight: ev.weight ?? 1,
      where: ev.where ?? null, when: ev.when ?? null, hint: ev.hint ?? null,
      requires: ev.requires ?? {}, title: ev.title, text: ev.text, options: ev.options,
      resonance: ev.resonance ?? null, dissonance: ev.dissonance ?? null,
    });
  }
}

// ---------- 家庭 / 天赋 ----------
const load = (f) => parse(readFileSync(join(root, "content", f), "utf8"));
const families = load("families.yaml").map((f) => {
  if (![0, 1, 2].includes(f.wealth)) errors.push(`families#${f.id}: wealth 必须是 0/1/2`);
  checkDeltas(`families#${f.id}.bonus`, f.bonus, STAT_KEYS);
  return { id: f.id, name: f.name, wealth: f.wealth, weight: f.weight ?? 1, money: f.money ?? 0, desc: f.desc ?? "", bonus: f.bonus ?? {}, traits: f.traits ?? [] };
});
const talents = load("talents.yaml").map((t) => {
  checkDeltas(`talents#${t.id}.bonus`, t.bonus, STAT_KEYS);
  return { id: t.id, name: t.name, weight: t.weight ?? 1, desc: t.desc ?? "", bonus: t.bonus ?? {}, flags: t.flags ?? [] };
});
if (families.length < 2) errors.push("families.yaml 至少需要两户人家");

// ---------- 地图 ----------
const map = load("map.yaml");
const zoneIds = new Set(map.zones.map((z) => z.id));
const actionIds = new Set(map.actions.map((a) => a.id));
for (const z of map.zones) if (!Array.isArray(z.rect) || z.rect.length !== 4) errors.push(`map.zones#${z.id}: rect 应为 [x, y, w, h]`);
for (const sp of map.spots) {
  if (!zoneIds.has(sp.zone)) errors.push(`map.spots#${sp.id}: 未知 zone ${sp.zone}`);
  if (!actionIds.has(sp.action)) errors.push(`map.spots#${sp.id}: 未知 action ${sp.action}`);
}
map.actions = map.actions.map((a) => {
  checkDeltas(`map.actions#${a.id}.needs`, a.needs, NEED_KEYS);
  checkDeltas(`map.actions#${a.id}.stats`, a.stats, STAT_KEYS);
  checkDeltas(`map.actions#${a.id}.together.needs`, a.together?.needs, NEED_KEYS);
  checkDeltas(`map.actions#${a.id}.together.bond`, a.together?.bond, BOND_KEYS);
  if (!a.sleep && !a.school && !(a.minutes > 0)) errors.push(`map.actions#${a.id}: 需要 minutes（睡觉/上学除外）`);
  return {
    id: a.id, label: a.label, minutes: a.minutes ?? 0, sleep: !!a.sleep, school: !!a.school,
    requires: a.requires ?? {}, needs: a.needs ?? {}, stats: a.stats ?? {}, money: a.money ?? 0,
    together: a.together ? { needs: a.together.needs ?? {}, bond: a.together.bond ?? {}, text: a.together.text ?? "" } : null,
  };
});
for (const ev of events) if (ev.where && !zoneIds.has(ev.where)) errors.push(`${ev.id}: where 未知地点 ${ev.where}`);

if (errors.length) {
  console.error(`内容校验失败（${errors.length} 处）：\n  - ` + errors.join("\n  - "));
  process.exit(1);
}

const content = { events, families, talents, map };
const json = JSON.stringify(content, null, 1);
writeFileSync(join(root, "client", "data", "content.json"), json + "\n");
writeFileSync(
  join(root, "server", "src", "content.generated.ts"),
  `// 由 tools/build-content.mjs 生成，请修改 content/*.yaml 后运行 npm run content\n` +
    `var CONTENT: Content = ${json};\n`,
);
const by = (k) => events.filter((e) => e.stage === k).length;
console.log(`✓ ${events.length} 个事件  ` + STAGES.map((s) => `${s}:${by(s)}`).join("  ") +
  `  |  ${families.length} 户人家  ${talents.length} 种天赋  ${map.zones.length} 个地点  ${map.actions.length} 种行动`);
