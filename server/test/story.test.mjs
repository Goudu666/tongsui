// 剧情测试：不走地图，只模拟「命运」——每个日子把命运准备好的事件直接结算（两个人都到场），
// 用随机选择探索所有分支，检查：
//   0) 各自的事按人算：两个人都会高考、都会面对要不要去外地
//   1) 每个事件都有机会被遇到（没有因为条件写错而永远触发不了的剧情）
//   2) 跨阶段的故事线索真的能连起来（标记被打上、被后面的事件读到）
//   3) 新的条件：亲近 / 默契 / 距离 / 对方离开以后、共鸣与错位的共同标记
//   4) 多结局：每种结局和一生小结的条件都有人能走到；结局按顺序匹配
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const code = readFileSync(new URL("../build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math });
vm.runInContext(code, ctx);
const G = (name) => vm.runInContext(name, ctx);
const C = G("CONTENT");
const lifeCreate = G("lifeCreate"), lifeConfirm = G("lifeConfirm"), lifeReroll = G("lifeReroll");
const lifeResolveEvent = G("lifeResolveEvent"), lifeEndDay = G("lifeEndDay"), lifeRand = G("lifeRand");
const lifeEligible = G("lifeEligible"), lifeTimeAt = G("lifeTimeAt"), lifeEnding = G("lifeEnding");

const byId = new Map(C.events.map((e) => [e.id, e]));

/** 模拟一生。choose(s, role, ev) 返回选项 id */
function story(seed, choose, rerolls = 0) {
  const s = lifeCreate(seed, C);
  for (let i = 0; i < rerolls; i++) { lifeReroll(s, C, "qing"); lifeReroll(s, C, "mei"); }
  lifeConfirm(s, C, "qing", { qing: "青", mei: "梅" });
  lifeConfirm(s, C, "mei", { qing: "青", mei: "梅" });
  const seen = [];
  let guard = 0;
  while (s.phase !== "ended") {
    const w = s.world;
    const fate = w.fate;
    const alive = ["qing", "mei"].filter((r) => s.persons[r].alive);
    if (fate.mirror && alive.length === 2) {
      const ev = byId.get(fate.mirror);
      const choices = { qing: choose(s, "qing", ev), mei: choose(s, "mei", ev) };
      lifeResolveEvent(s, C, { eventId: ev.id, kind: "mirror", roles: ["qing", "mei"], choices, shadow: [] });
      seen.push("pair:" + ev.id);
    }
    for (const r of alive) {
      if (!fate[r]) continue;
      const ev = byId.get(fate[r]);
      lifeResolveEvent(s, C, { eventId: ev.id, kind: "solo", roles: [r], choices: { [r]: choose(s, r, ev) }, shadow: [] });
      seen.push(r + ":" + ev.id);
    }
    for (const r of alive) w.actors[r].asleep = true;
    lifeEndDay(s, C);
    assert.ok(++guard < 200, "一生不该超过 200 个日子");
  }
  return { s, seen };
}

// 两种玩家：随手乱选的，和性格前后一致的（按自己攒下的性格标签选，和影子一样）
const randomChoice = (s, role, ev) => ev.options[Math.floor(lifeRand(s) * ev.options.length)].id;
const steadyChoice = (s, role, ev) => G("lifeShadowChoose")(s, C, role, ev.id);

// ---------- 1. 内容规模 ----------
{
  const count = (stage, kind) => C.events.filter((e) => e.stage === stage && (!kind || e.kind === kind)).length;
  const want = { childhood: 36, teen: 24, young: 24, middle: 16, old: 9 };
  for (const [stage, n] of Object.entries(want)) assert.ok(count(stage) >= n, `${stage} 事件太少：${count(stage)} < ${n}`);
  for (const season of ["spring", "summer", "autumn", "winter"]) {
    const m = C.events.filter((e) => e.stage === "childhood" && e.kind === "mirror" && (e.seasons.length === 0 || e.seasons.includes(season))).length;
    assert.ok(m >= 6, `童年${season}可抽的默契事件太少：${m}`);
  }
  const zones = new Set(C.events.filter((e) => e.kind === "mirror").map((e) => e.where));
  for (const z of ["roof", "hallway", "breakfast", "river", "alley", "school", "bikeshop"]) assert.ok(zones.has(z), `没有发生在 ${z} 的默契事件`);
  for (const f of C.families) {
    const own = C.events.filter((e) => f.traits.some((t) => (e.requires.flags ?? []).includes(t)));
    assert.ok(own.length >= 3, `${f.name} 的专属剧情不足 3 个`);
  }
  for (const t of C.talents.filter((t) => t.flags.length > 0)) {
    const own = C.events.filter((e) => t.flags.some((f) => (e.requires.flags ?? []).includes(f)));
    assert.ok(own.length >= 1, `${t.name} 没有专属剧情`);
  }
  for (const ev of C.events) {
    for (const o of ev.options) assert.ok(o.tags.length > 0, `${ev.id}.${o.id} 没有性格标签，影子不会学`);
    if (ev.kind === "mirror") assert.ok(Object.keys(ev.resonance).length >= 1, `${ev.id} 没有任何共鸣`);
  }
  console.log(`✓ 规模：${C.events.length} 个事件 / 每季都有默契事件 / 七个地点都有 / ${C.families.length} 户人家各有专属线 / ${C.talents.length - 1} 种天赋各有专属剧情`);
}

// ---------- 2. 新条件 ----------
{
  const t = lifeTimeAt(0);
  const bond = { sync: 20, close: 40, distance: 2 };
  const ev = (rq) => ({ id: "x", stage: "childhood", seasons: [], requires: rq });
  const ok = (rq, c = { bond, alone: false }) => lifeEligible(ev(rq), t, [], {}, c);
  assert.ok(ok({ minClose: 40, maxClose: 40 }));
  assert.ok(!ok({ minClose: 41 }));
  assert.ok(!ok({ maxSync: 19 }));
  assert.ok(ok({ minDistance: 2 }) && !ok({ maxDistance: 1 }));
  assert.ok(!ok({ alone: true }) && ok({ alone: false }));
  assert.ok(ok({ alone: true }, { bond, alone: true }) && !ok({ alone: false }, { bond, alone: true }));
  assert.ok(!lifeEligible(ev({ alone: true }), t, [], {}), "没有上下文时不出现 alone 事件");

  // 共鸣的共同标记两个人都拿到；错位的共同标记也是
  const withRes = C.events.find((e) => e.kind === "mirror" && Object.values(e.resonance).some((r) => r.flags.length > 0));
  assert.ok(withRes, "应该有带共同标记的共鸣");
  const [oid, res] = Object.entries(withRes.resonance).find(([, r]) => r.flags.length > 0);
  const { s } = { s: lifeCreate(3, C) };
  lifeConfirm(s, C, "qing", { qing: "青", mei: "梅" });
  lifeConfirm(s, C, "mei", { qing: "青", mei: "梅" });
  lifeResolveEvent(s, C, { eventId: withRes.id, kind: "mirror", roles: ["qing", "mei"], choices: { qing: oid, mei: oid }, shadow: [] });
  for (const f of res.flags) for (const r of ["qing", "mei"]) assert.ok(s.persons[r].flags.includes(f), `${r} 应得到 ${f}`);
  const withDis = C.events.find((e) => e.kind === "mirror" && e.dissonance.flags.length > 0);
  assert.ok(withDis, "应该有带共同标记的错位");
  lifeResolveEvent(s, C, { eventId: withDis.id, kind: "mirror", roles: ["qing", "mei"], choices: { qing: withDis.options[0].id, mei: withDis.options[1].id }, shadow: [] });
  for (const f of withDis.dissonance.flags) for (const r of ["qing", "mei"]) assert.ok(s.persons[r].flags.includes(f));
  console.log(`✓ 条件：亲近/默契/距离范围 / 对方离开以后 / 共鸣「${res.memory ?? oid}」和错位都给两人打上共同标记`);
}

// ---------- 3. 探索：一半随机、一半性格一致，跑很多条人生 ----------
const LIVES = 1500;
const hit = new Map(C.events.map((e) => [e.id, 0]));
const pairEnd = new Map(C.endings.pair.map((e) => [e.id, 0]));
const lifeEnd = new Map(C.endings.lives.map((e) => [e.id, 0]));
const flagsSeen = new Map();
let turns = 0, evs = 0, mems = 0;
for (let seed = 1; seed <= LIVES; seed++) {
  const { s, seen } = story(seed * 2654435761, seed % 2 ? randomChoice : steadyChoice, seed % 4);
  for (const k of seen) { const id = k.split(":")[1]; hit.set(id, hit.get(id) + 1); }
  assert.equal(new Set(seen).size, seen.length, "默契事件一生只出现一次，各自的事每人一生只遇一次");
  assert.ok(s.ending, "人生结束时要有结局");
  pairEnd.set(s.ending.pair, pairEnd.get(s.ending.pair) + 1);
  for (const r of ["qing", "mei"]) {
    lifeEnd.set(s.ending.lives[r], lifeEnd.get(s.ending.lives[r]) + 1);
    for (const f of s.persons[r].flags) flagsSeen.set(f, (flagsSeen.get(f) ?? 0) + 1);
    for (const v of Object.values(s.persons[r].stats)) assert.ok(v >= 0 && v <= 10);
  }
  const end = s.log.at(-1);
  assert.equal(end.kind, "end");
  assert.ok(end.text.includes("「") && end.text.includes("青") && end.text.includes("梅") && !end.text.includes("{name}"), "长卷末尾要写出结局和两人的一生");
  turns += s.turn; evs += seen.length; mems += s.memories.length;
}
{
  const never = [...hit].filter(([, n]) => n === 0).map(([id]) => id);
  assert.deepEqual(never, [], `${never.length} 个事件在 ${LIVES} 条人生里一次也没出现：${never.join(", ")}`);
  const deadPair = [...pairEnd].filter(([, n]) => n === 0).map(([id]) => id);
  assert.deepEqual(deadPair, [], `走不到的结局：${deadPair.join(", ")}`);
  const deadLife = [...lifeEnd].filter(([, n]) => n === 0).map(([id]) => id);
  assert.deepEqual(deadLife, [], `走不到的一生小结：${deadLife.join(", ")}`);
  // 结局不能一边倒：最常见的结局不超过一半
  const top = Math.max(...pairEnd.values());
  assert.ok(top / LIVES < 0.5, `结局太集中：${[...pairEnd].sort((a, b) => b[1] - a[1])[0].join(" ")}`);
  const pct = (n, d) => ((n / d) * 100).toFixed(1) + "%";
  console.log(`✓ ${LIVES} 条人生（一半乱选、一半性格一致）：平均 ${(turns / LIVES).toFixed(1)} 天 / 遇到 ${(evs / LIVES).toFixed(1)} 个事件 / ${(mems / LIVES).toFixed(1)} 段共同回忆 / 每个事件都出现过`);
  console.log("  结局分布：" + [...pairEnd].sort((a, b) => b[1] - a[1]).map(([id, n]) => `${C.endings.pair.find((e) => e.id === id).title} ${pct(n, LIVES)}`).join("  "));
  console.log("  一生分布：" + [...lifeEnd].sort((a, b) => b[1] - a[1]).map(([id, n]) => `${C.endings.lives.find((e) => e.id === id).title} ${pct(n, LIVES * 2)}`).join("  "));
  const rare = [...hit].sort((a, b) => a[1] - b[1]).slice(0, 8).map(([id, n]) => `${id}×${n}`);
  console.log("  最难遇到的事件：" + rare.join("  "));
  for (const f of ["p_wall_names", "p_capsule", "p_pigeon", "p_promise", "p_seaside", "p_lovers", "p_married", "p_partners", "p_reunited", "took_over"]) {
    assert.ok((flagsSeen.get(f) ?? 0) > 0, `故事线索 ${f} 从来没被打上`);
  }
}

// ---------- 4. 结局按顺序匹配 ----------
{
  const s = lifeCreate(11, C);
  lifeConfirm(s, C, "qing", { qing: "青", mei: "梅" });
  lifeConfirm(s, C, "mei", { qing: "青", mei: "梅" });
  for (const r of ["qing", "mei"]) { s.persons[r].alive = false; s.persons[r].diedAtAge = 80; }
  // 什么都没发生的一生 → 落到兜底之前、条件最宽的那条，至少不报错
  const e0 = lifeEnding(s, C);
  assert.ok(C.endings.pair.some((e) => e.id === e0.pair));
  // 结婚 + 很亲 → 第一条要求 p_married 的结局
  s.persons.qing.flags.push("p_married", "p_lovers");
  s.persons.mei.flags.push("p_married", "p_lovers");
  s.bond.close = 90; s.bond.sync = 60;
  const married = lifeEnding(s, C);
  const marriedEnd = C.endings.pair.find((e) => e.id === married.pair);
  assert.ok((marriedEnd.requires.flags ?? []).includes("p_married"), "结婚又很亲应该走到婚姻结局");
  // 再守住小时候的约定、又足够默契 → 排在最前面的「同岁」
  s.persons.qing.flags.push("p_promise");
  for (let i = 0; i < 10; i++) s.log.push({ kind: "mirror", resonance: true, events: { qing: null, mei: null } });
  const best = lifeEnding(s, C);
  assert.equal(best.pair, C.endings.pair[0].id, "条件全满足时取排在最前的结局");
  const firstMarried = marriedEnd;
  // 兜底：最后一条没有条件
  assert.equal(Object.keys(C.endings.pair.at(-1).requires).length, 0);
  assert.equal(Object.keys(C.endings.lives.at(-1).requires).length, 0);
  console.log(`✓ 结局：按顺序匹配 / 结婚又亲近 →「${firstMarried.title}」/ 再加上拉过的钩和默契 →「${C.endings.pair[0].title}」/ 两张表都有兜底`);
}
