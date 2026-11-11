// 剧情测试：不走地图，只模拟「命运」——每个日子把命运准备好的事件直接结算（两个人都到场），
// 用随机选择探索所有分支，检查：
//   0) 各自的事按人算：两个人都会高考、都会面对要不要去外地
//   1) 每个事件都有机会被遇到（没有因为条件写错而永远触发不了的剧情）
//   2) 跨阶段的故事线索真的能连起来（标记被打上、被后面的事件读到）
//   3) 新的条件：亲近 / 默契 / 距离 / 对方离开以后、共鸣与错位的共同标记
//   4) 多结局：每种结局和一生小结的条件都有人能走到；结局按顺序匹配
//   5) 隔世的事：人生三世一串地连着过（带着上一世的传承投胎），上一世留下的痕迹这一世真的撞得见
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
const lifeApplyBond = G("lifeApplyBond"), lifeApplySelf = G("lifeApplySelf"), growthCtx = G("growthCtx");
const DAILY = C.map.actions.filter((a) => Object.keys(a.stats).length > 0);
const lifeEligible = G("lifeEligible"), lifeTimeAt = G("lifeTimeAt"), lifeEnding = G("lifeEnding");
const lifeMilestoneFor = G("lifeMilestoneFor"), lifeSeenIds = G("lifeSeenIds"), lifeOptionLock = G("lifeOptionLock"), lifeTrack = G("lifeTrack");

const CHAIN_PICK = ["h_photo_two", "h_nested_box", "h_noted_books", "h_photo", "h_tin_box", "h_books"];
const byId = new Map(C.events.concat(C.story.events).map((e) => [e.id, e]));

/**
 * 模拟一生。choose(s, role, ev) 返回选项 id。
 * near：这一天两个人碰上、一起做点什么的概率。这里不走地图，就用一次同框的亲近来代替
 *（亲近是走动出来的：一天既没同框也没共鸣就会淡，见 growth.ts）。
 * legacy：上一世留下的传承（不传就是头一世）。
 */
function story(seed, choose, rerolls = 0, near = 0.5, legacy = undefined) {
  const s = lifeCreate(seed, C, legacy, G("eraPickCohort")(C, seed)); // 五个出生年代都抽（只在某个年代才有的事也要出得来）
  for (let i = 0; i < rerolls; i++) { lifeReroll(s, C, "qing"); lifeReroll(s, C, "mei"); }
  // 老物件会变（atlas.ts）：面前摆着会变的那几件，就带上（先挑变过一回的），链尾那几个藏着的结局才走得到
  for (const r of ["qing", "mei"]) {
    const pick = CHAIN_PICK.find((id) => (s.rolls[r].offer || []).includes(id));
    if (pick) G("legacyPick")(s, r, pick);
  }
  lifeConfirm(s, C, "qing", { qing: "青", mei: "梅" });
  lifeConfirm(s, C, "mei", { qing: "青", mei: "梅" });
  // 这里不走地图，没人写作业也没人踢球，属性不会自己长。按种子把属性铺开，
  // 好让每条分数线都有人够得着、有人够不着（考上的和没考上的剧情都要有人走到）
  for (const r of ["qing", "mei"]) for (const k of ["body", "mind", "charm"]) s.persons[r].stats[k] = 3 + Math.floor(lifeRand(s) * 71) / 10;
  const seen = [];
  let guard = 0;
  while (s.phase !== "ended") {
    const w = s.world;
    const fate = w.fate;
    const alive = ["qing", "mei"].filter((r) => s.persons[r].alive);
    if (fate.milestone) {
      // 关口：轮得到的人从够得着的路里选
      const ev = byId.get(fate.milestone);
      const due = alive.filter((r) => lifeMilestoneFor(ev, s.persons[r]) && !lifeSeenIds(s, r)[ev.id]);
      if (due.length > 0) {
        const choices = {};
        for (const r of due) {
          const open = ev.options.filter((o) => !lifeOptionLock(ev, o, s.persons[r], 0, G("lifePairBond")(s, r)));
          assert.ok(open.length >= 1, `${ev.id}: ${r} 没有任何一条路可走`);
          choices[r] = choose(s, r, { ...ev, options: open });
          assert.ok(open.some((o) => o.id === choices[r]), `${ev.id}: 选了一条走不了的路 ${choices[r]}`);
        }
        const entry = lifeResolveEvent(s, C, { eventId: ev.id, kind: "milestone", roles: due, choices, shadow: [], swing: {} });
        for (const r of due) { seen.push(r + ":" + ev.id); assert.ok(entry.results[r].track, "关口之后每个人都要落在一条路上"); }
      }
    }
    // 出门（server/src/outside.ts）：这里不走 worldChoose，结算完照它的样子记一笔、再交给 outsideAfterEvent——选了 goto 的人真被送到海边、乡下、早市，
    // 命运给他换上那张图上的事（下面各自的事接着就过）。海边、乡下的小事只有这样排得进来（早上排事的时候人还在床上，trip 的图去不了），
    // 所以是真把人送过去，而不是在 sceneHeld 里把 trip 的图当成「等着」放过
    const settle = (pe) => { lifeResolveEvent(s, C, pe); w.done.push(pe.eventId); G("outsideAfterEvent")(s, C, pe); };
    // 两个人一块儿被送到海边、乡下：outsideAfterEvent 再给两个人排一件那儿的 mirror（招待所的夜里、露天电影），接着过
    for (let k = 0; k < 2 && fate.mirror && alive.length === 2 && !w.done.includes(fate.mirror); k++) {
      const ev = byId.get(fate.mirror);
      const choices = { qing: choose(s, "qing", ev), mei: choose(s, "mei", ev) };
      settle({ eventId: ev.id, kind: "mirror", roles: ["qing", "mei"], choices, shadow: [] });
      seen.push("pair:" + ev.id);
    }
    for (const r of alive) {
      if (!fate[r]) continue;
      const ev = byId.get(fate[r]);
      settle({ eventId: ev.id, kind: "solo", roles: [r], choices: { [r]: choose(s, r, ev) }, shadow: [] });
      seen.push(r + ":" + ev.id);
    }
    // 日子不只是事件：每人每天还会上学、写作业、玩、干活里挑两样（长属性，也让岁数大了不至于荒废）
    for (const r of alive) for (let i = 0; i < 2; i++) lifeApplySelf(s.persons[r], DAILY[Math.floor(lifeRand(s) * DAILY.length)].stats, growthCtx(s, C, "action"));
    if (alive.length === 2 && lifeRand(s) < near) {
      // 形影不离的一天里不止一起做一件事
      lifeApplyBond(s, C, { close: near > 0.9 ? 3 : 1 });
      w.warm = true;
    }
    for (const r of alive) w.actors[r].asleep = true;
    lifeEndDay(s, C);
    assert.ok(++guard < 200, "一生不该超过 200 个日子");
  }
  return { s, seen };
}

// 两种玩家：随手乱选的，和性格前后一致的（按自己攒下的性格标签选，和影子一样）
// 主线的选项有家底门槛（requires / cost），乱选也只在自己选得了的里面挑
const randomChoice = (s, role, ev) => {
  const open = ev.chapter === undefined ? ev.options : ev.options.filter((o) => !G("lifeOptionLock")(ev, o, s.persons[role], 0));
  return open[Math.floor(lifeRand(s) * open.length)].id;
};
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
    // 关口里只有一条路的（上小学、退休）不用选，也就不用标性格
    for (const o of ev.options) assert.ok(o.tags.length > 0 || (ev.kind === "milestone" && ev.options.length === 1), `${ev.id}.${o.id} 没有性格标签，影子不会学`);
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
// 形影不离的、常碰上的、偶尔碰上的、各过各的
const NEAR = [0.95, 0.7, 0.4, 0.1];
const hit = new Map(C.events.map((e) => [e.id, 0]));
const pairEnd = new Map(C.endings.pair.map((e) => [e.id, 0]));
const lifeEnd = new Map(C.endings.lives.map((e) => [e.id, 0]));
const flagsSeen = new Map();
const trackSeen = new Set(); // 40 岁时走在哪条路上
let turns = 0, evs = 0, mems = 0;
// 三世一串：第二、三世带着上一世的传承投胎，隔世的事才遇得到。
// 藏着的天赋要先出过事才抽得到，光靠三世撞不够，所以每隔一串当作「三件事都出过」的人生线
const CHAIN = 3;
const noted = new Map(C.remembered.map((a) => [a.id, 0]));
const talentSeen = new Map();
let legacy;
for (let seed = 1; seed <= LIVES; seed++) {
  const nth = (seed - 1) % CHAIN;
  if (nth === 0) legacy = undefined;
  if (nth === 1 && Math.floor(seed / CHAIN) % 2 === 0) legacy.marks = [...C.legacy.marks];
  // 老物件链要连着三世才走到头，三世一串撞不够：每隔一串当作链已经变过一回（面前摆着变过的那几件）。
  // 原来是每隔两串：「又一张」那个结局 1500 条里只走到 1 回，内容一动（多几件行动、几件小事）就抽成 0
  if (nth === 2 && Math.floor(seed / CHAIN) % 2 === 0) for (const id of ["h_photo_two", "h_nested_box", "h_noted_books"]) if (!legacy.heirlooms.includes(id)) legacy.heirlooms.unshift(id);
  // 「两家孩子同岁、一块儿长大」的痕迹（p_kids_tongsui）要上一世两家都有孩子、又在孩子的事上同路，1500 条里只有个位数的人带着投胎，
  // 读它的「暖气片后头」（l_door_marks）跟着内容一动就抽成 0（三扇门那一轮就是，docs/MEANS.md 第八节）：每四串当作有一串上一世留下了这个痕迹
  if (nth === 1 && Math.floor(seed / CHAIN) % 4 === 1 && !(legacy.traces || []).includes("p_kids_tongsui")) legacy.traces = [...(legacy.traces || []), "p_kids_tongsui"];
  const { s, seen } = story(seed * 2654435761, seed % 2 ? randomChoice : steadyChoice, seed % 4, NEAR[Math.floor(seed / 4) % NEAR.length], legacy);
  legacy = JSON.parse(JSON.stringify(s.legacy));
  assert.equal(s.life, nth + 1);
  for (const id of s.noted) noted.set(id, noted.get(id) + 1);
  for (const r of ["qing", "mei"]) talentSeen.set(s.persons[r].talentId, (talentSeen.get(s.persons[r].talentId) ?? 0) + 1);
  if (nth === 0) for (const r of ["qing", "mei"]) assert.ok(!s.persons[r].flags.some((f) => f.startsWith("leg_")), "头一世不带上一世的痕迹");
  for (const k of seen) { const id = k.split(":")[1]; if (hit.has(id)) hit.set(id, hit.get(id) + 1); }
  assert.equal(new Set(seen).size, seen.length, "默契事件一生只出现一次，各自的事和关口每人一生只遇一次");
  for (const r of ["qing", "mei"]) trackSeen.add(lifeTrack(C, s.persons[r], 40).id);
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
  // 等别的线程发的标记（tools/build-content.mjs 的 PENDING_FLAGS）：发标记的合进来以前，要它的事件出不来
  const PENDING = ["fam_factory", "uni_abroad", "school_paid", "job_pull", "job_succeed", "home_unit",
    // 十八岁的助学贷款：这里的机器人高考不怎么走清贫背贷款那条，还清了那两件事抽不到
    "loan",
    // 成家和下一代：孩子关口 kid_* 走地图那边（world.ts 按孩子岁数排的关口），这里不走地图，读它们的事件出不来
    "kid_prim_key", "kid_prim_near", "kid_mid_key", "kid_mid_near", "kid_high_key", "kid_high", "kid_trade", "kid_uni_top", "kid_uni", "kid_away", "kid_work"];
  // 这里不走地图，也就不攒钱：三十岁买不起房（m_settle 的 buy 要 200 块），要 home_own 的事件在这儿出不来，由 paths.test 那种过日子的模拟兜着
  const NO_MONEY = ["home_own"];
  const held = (flags) => (flags ?? []).some((f) => PENDING.includes(f) || NO_MONEY.includes(f));
  // 事情出在哪张图上，那张图得去得了：新房小区要先买上房（scene 的 unlock），这里也走不到
  const sceneHeld = (where) => {
    if (!where) return false;
    const u = C.map.scenes.find((x) => x.id === C.map.zones.find((z) => z.id === where).scene).unlock;
    return !!u && (held(u.flags) || (u.any?.length > 0 && u.any.every((q) => held(q.flags))));
  };
  // 主线顶替掉的旧事件（story.yaml 的 replaces）不再进随机池
  const replaced = new Set(C.story.events.flatMap((e) => e.replaces));
  const waits = (id) => replaced.has(id) || held(byId.get(id).requires?.flags) || sceneHeld(byId.get(id).where);
  const never = [...hit].filter(([id, n]) => n === 0 && !waits(id)).map(([id]) => id);
  assert.deepEqual(never, [], `${never.length} 个事件在 ${LIVES} 条人生里一次也没出现：${never.join(", ")}`);
  // 「又是对门」（藏着的，要上一世拉过钩 leg_p_promise）千里挑一，改之前 1500 世里 2 回，碰没碰上看随机数顺序：
  // 三扇门那次加的事挪了随机数，它落到 0 回。只放过这一个，而且它要的每个标记都得有人带着走完过一世
  const legRare = (id) => {
    if (id !== "e_again") return false;
    const e = C.endings.pair.find((x) => x.id === id), fl = e.requires.flags ?? [];
    return C.atlas.hidden.includes(id) && fl.every((f) => (flagsSeen.get(f) ?? 0) > 0);
  };
  const deadPair = [...pairEnd].filter(([id, n]) => n === 0 && !legRare(id)).map(([id]) => id);
  assert.deepEqual(deadPair, [], `走不到的结局：${deadPair.join(", ")}`);
  // 高寿的小结（长寿、冬泳的老人）靠的是一辈子吃好睡好心情好，这里不模拟过日子，放在 growth.test.mjs 里测
  const needsLongLife = new Set(C.endings.lives.filter((e) => (e.requires.minDiedAge ?? 0) >= 85).map((e) => e.id));
  // 「两家的孩子」（l_kids_tongsui）要这一世两家都有孩子、孩子的事又同路（p_kids_tongsui），1500 条里个位数，跟着随机数顺序在 0 和几回之间跳。
  // 走不走得到由 legacy.test「一生小结：两家的孩子」按标记直接钉着，这里不靠抽样
  const sampledRare = new Set(C.endings.lives.filter((e) => (e.requires.flags ?? []).includes("p_kids_tongsui")).map((e) => e.id));
  const deadLife = [...lifeEnd].filter(([id, n]) => n === 0 && !needsLongLife.has(id) && !sampledRare.has(id) && !held(C.endings.lives.find((e) => e.id === id).requires.flags)).map(([id]) => id);
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
  // 每一种行当都有人干上了
  // 升了级的路（content/tracks.yaml 的 <行当>_r1 / _r2，docs/CAREER.md）和原来那条算一个行当：干上了这一行、升没升到哪一级都算
  const career = (id) => id.replace(/_r[12]$/, "");
  const careerSeen = new Set([...trackSeen].map(career));
  for (const t of C.tracks.filter((x) => x.duty && (x.requires.minAge ?? 0) <= 40 && (x.requires.maxAge ?? 99) >= 40)) assert.ok(careerSeen.has(career(t.id)), `没有人走上「${t.label}」这条路`);
  for (const f of ["p_wall_names", "p_capsule", "p_pigeon", "p_promise", "p_seaside", "p_lovers", "p_married", "p_partners", "p_reunited", "took_over"]) {
    assert.ok((flagsSeen.get(f) ?? 0) > 0, `故事线索 ${f} 从来没被打上`);
  }
  // 隔世：每一种痕迹都有人带着出生过；藏着的天赋出过事以后抽得到；街坊记住的事每条都有人被记住过
  for (const f of ["leg_any", "leg_house", ...C.legacy.traces.map((t) => "leg_" + t)].filter((f) => !held([f]))) assert.ok((flagsSeen.get(f) ?? 0) > 0, `痕迹 ${f} 从来没人带着出生`);
  for (const t of C.talents.filter((t) => t.unlock)) assert.ok((talentSeen.get(t.id) ?? 0) > 0, `藏着的天赋 ${t.name} 出过事以后也没人抽到`);
  // 活过九十要一辈子吃好睡好，这里不模拟过日子（同上面高寿的小结）
  const slow = new Set(C.remembered.filter((a) => (a.requires.minDiedAge ?? 0) >= 85).map((a) => a.id));
  const deadNote = [...noted].filter(([id, n]) => n === 0 && !slow.has(id) && !held(C.remembered.find((a) => a.id === id).requires.flags)).map(([id]) => id);
  assert.deepEqual(deadNote, [], `街坊从来没记住过的事：${deadNote.join(", ")}`);
  console.log("  街坊记住的事（每 100 世）：" + [...noted].sort((a, b) => b[1] - a[1]).map(([id, n]) => `${C.remembered.find((a) => a.id === id).title} ${((n / LIVES) * 100).toFixed(1)}`).join("  "));
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
