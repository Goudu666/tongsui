// 人生关口：躲不掉 / 无路可走时兜底 / 每个关口的年纪都到得了 / v4 存档升上来接着过。
// 关口的数值（多少人够得着哪条线）在 paths.test.mjs，这里只管「一定发生、一定过得去」。
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const MILESTONES = C.events.filter((e) => e.kind === "milestone");
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };

/** 一条走到 age 岁第一天早上的人生（没走过前面的日子，属性是出生时的；给了 stat 就三项都设成它） */
function lifeAt(seed, age, c = C, stat = null) {
  const s = G("lifeCreate")(seed, c);
  for (const r of ROLES) G("lifeConfirm")(s, c, r, NAMES);
  if (stat !== null) for (const r of ROLES) for (const k of ["body", "mind", "charm"]) s.persons[r].stats[k] = stat;
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, c);
  return s;
}
/** 走到关口发生（开始选，或者直接记进了长卷）或者这一天结束 */
function untilMilestone(s, c = C) {
  for (let i = 0; i < 600; i++) {
    const out = G("worldAdvance")(s, c, 0.1, ON);
    if (out.started || out.dayEnded || out.entries.some((e) => e.kind === "milestone")) return out;
  }
  assert.fail("这一天没有走完");
}
const bed = (r) => C.map.spots.find((sp) => sp.id === "bed_" + r);
function sleep(s, r) {
  const a = s.world.actors[r];
  a.x = bed(r).at[0]; a.y = bed(r).at[1];
  assert.equal(G("worldAct")(s, C, r, bed(r).id).error, null);
  assert.ok(a.asleep);
}

// ---------- 1. 关口躲不掉 ----------
{
  // 青年以后一岁只有一天：高考那天早上躺回去，考试也得来
  for (const who of [["qing"], ["mei"], ["qing", "mei"]]) {
    const s = lifeAt(7, 18, C, 9); // 两个人都有得选
    assert.equal(s.world.fate.milestone, "m_gaokao");
    for (const r of who) sleep(s, r);
    const out = untilMilestone(s);
    assert.ok(!out.dayEnded, `${who.join("+")} 一早睡下，这一天不能就这么翻过去`);
    assert.ok(out.started && out.started.eventId === "m_gaokao", `${who.join("+")} 一早睡下，高考照样来`);
    assert.deepEqual(J(out.started.roles).sort(), ["mei", "qing"]);
    for (const r of ROLES) {
      const a = s.world.actors[r];
      assert.ok(!a.asleep && a.action === null && a.until === null, "睡着的被叫起来，站在考场门口");
    }
    // 选完：成绩记进长卷，这一天接着过
    for (const r of ROLES) {
      if (s.world.event && !s.world.event.choices[r]) assert.equal(G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, "m_gaokao"), false).error, null);
    }
    assert.equal(s.world.event, null);
    const entry = s.log.at(-1);
    assert.equal(entry.kind, "milestone");
    for (const r of ROLES) assert.ok(entry.results[r].track, "考完每个人都落在一条路上");
    assert.ok(s.world.done.includes("m_gaokao"));
    assert.ok(!G("worldAdvance")(s, C, 0.1, ON).started, "过了就不再来第二遍");
  }

  // 正在做事的人也一样：放下手里的事
  const s = lifeAt(8, 18, C, 9);
  const a = s.world.actors.qing;
  const desk = C.map.spots.find((sp) => sp.zone === "home_qing" && (sp.actions || []).includes("study"));
  a.x = desk.at[0]; a.y = desk.at[1];
  assert.equal(G("worldAct")(s, C, "qing", desk.id).error, null);
  const out = untilMilestone(s);
  assert.ok(out.started && a.action === null, "做到一半的事放下");

  // 每一个关口：到了年纪的那天，两个人一早睡下也都会过
  for (const ms of MILESTONES) {
    const t = lifeAt(100 + ms.age, ms.age);
    const due = ROLES.filter((r) => G("lifeMilestoneFor")(ms, t.persons[r]));
    if (due.length === 0) continue;
    assert.equal(t.world.fate.milestone, ms.id);
    for (const r of ROLES) sleep(t, r);
    const o = untilMilestone(t);
    assert.ok(!o.dayEnded, `${ms.id}: 睡过去了`);
    assert.ok(t.world.event ? t.world.event.eventId === ms.id : t.log.at(-1).events[due[0]] === ms.id, `${ms.id}: 没有发生`);
  }
  console.log("✓ 关口躲不掉：一早睡下（一个人 / 两个人）照样来 / 睡着的叫醒、做事的放下 / 过了不来第二遍 / 七个关口都一样");
}

// ---------- 2. 一条路都走不通：不抛错，走线最低的那条 ----------
{
  // 把小升初的每条路都加上够不着的线（内容热更新时写漏了兜底的路）
  const c2 = J(C);
  const ms = c2.events.find((e) => e.id === "m_junior");
  ms.options.forEach((o, i) => { o.min = 50 + i; });
  const lowest = ms.options[0].id;
  assert.equal(G("lifeMilestoneFallback")(ms).id, lowest);
  // 线一样低：取写在后面的那条（兜底的路习惯写在最后）
  assert.equal(G("lifeMilestoneFallback")({ options: [{ id: "a", min: 3 }, { id: "b" }, { id: "c" }] }).id, "c");

  const s = lifeAt(21, 12, c2);
  assert.equal(s.world.fate.milestone, "m_junior");
  for (const r of ROLES) assert.ok(ms.options.every((o) => G("lifeOptionLock")(ms, o, s.persons[r], 0)), "这里要的是每条路都锁着");
  const out = untilMilestone(s, c2);
  assert.ok(!out.started, "没得选就不弹窗");
  const entry = out.entries.find((e) => e.kind === "milestone");
  for (const r of ROLES) assert.equal(entry.choices[r], lowest, "两个人都走线最低的那条");
  assert.ok(s.world.done.includes("m_junior"));
  // 影子代选走的是同一个兜底
  const s2 = lifeAt(22, 12, c2);
  assert.equal(G("lifeShadowChoose")(s2, c2, "qing", "m_junior"), lowest);
  // 一个人有得选、一个人无路可走：无路可走的先定下，等另一个选完一起揭晓
  const c3 = J(C);
  const ms3 = c3.events.find((e) => e.id === "m_junior");
  ms3.options.forEach((o, i) => { o.min = 6 + i * 0.1; });
  const s3 = lifeAt(23, 12, c3);
  for (const k of ["body", "mind", "charm"]) { s3.persons.qing.stats[k] = 9.5; s3.persons.mei.stats[k] = 1; }
  const o3 = untilMilestone(s3, c3);
  assert.ok(o3.started && o3.started.choices.mei === ms3.options[0].id && !o3.started.choices.qing);

  // 现在的内容：每个关口都有一条谁都走得了的路（build-content 也拦着）
  const none = (x) => !x || Object.values(x).every((v) => v == null || (Array.isArray(v) && v.length === 0));
  for (const m of MILESTONES) assert.ok(m.options.some((o) => !o.min && !o.cost && none(o.requires)), `${m.id} 没有兜底的路`);
  console.log("✓ 关口无路可走：不抛错不回滚，走线最低的那条 / 影子同一个兜底 / 一人无路一人有得选 / 现有七个关口都有兜底的路");
}

// ---------- 3. 每个关口的年纪都到得了 ----------
{
  // 中年三年一天（30、33、36……），老年五年一天：写个 40 岁的关口就永远不会发生
  for (const ms of MILESTONES) {
    const t = turnAtAge(ms.age);
    assert.ok(t >= 0, `${ms.id}: 人生里没有 ${ms.age} 岁这一天`);
    assert.equal(G("lifeTimeAt")(t).stage, ms.stage, `${ms.id}: ${ms.age} 岁不在 ${ms.stage}`);
    assert.equal(G("lifeMilestoneAt")(C, ms.age).id, ms.id);
  }
  console.log(`✓ 关口的年纪：${MILESTONES.map((m) => m.age).join(" / ")} 岁都有那一天，也都在写的那个阶段里`);
}

// ---------- 4. v4 存档（成长规则那一版）升到 v5 接着过 ----------
{
  const old = (seed, age) => {
    const s = lifeAt(seed, age);
    // 退回 v4 的样子：schoolDay 而不是 rest，没有 dutyDone 和关口
    s.version = 4;
    s.world.schoolDay = !s.world.rest;
    delete s.world.rest;
    delete s.world.dutyDone;
    delete s.world.fate.milestone;
    return s;
  };
  // 上着学的孩子：正在做已经没有了的 school 行动
  const s = old(31, 9);
  s.world.schoolDay = true;
  Object.assign(s.world.actors.qing, { action: "school", spot: "school_gate", until: 900 });
  // 卡在一个被删掉的事件上
  s.world.event = { eventId: "t_choose_school", kind: "mirror", roles: ["qing", "mei"], choices: { qing: "key" }, shadow: [] };
  s.world.fate.mirror = "t_choose_school";
  const up = G("lifeUpgrade")(s);
  assert.deepEqual(J(up), ["v4→v5"]);
  assert.equal(s.version, G("LIFE_VERSION"));
  assert.equal(s.world.rest, false, "上学日不是歇着的日子");
  assert.ok(!("schoolDay" in s.world));
  assert.deepEqual(J(s.world.dutyDone), {});
  assert.equal(s.world.fate.milestone, null);
  const notes = G("lifeRepair")(s, C);
  assert.ok(notes.some((n) => n.includes("school")) && notes.some((n) => n.includes("t_choose_school")), "没有了的行动和事件都摘掉");
  assert.equal(s.world.actors.qing.action, null);
  assert.equal(s.world.event, null);
  assert.equal(s.world.fate.mirror, null);
  assert.deepEqual(J(G("lifeUpgrade")(s)), [], "升过一次就不再升");
  // 接着过：过完这一天，再过到下一个关口（12 岁小升初）真的发生
  let guard = 0, met = false;
  while (s.phase === "life" && G("lifeTimeAt")(s.turn).age <= 12 && !met) {
    const out = G("worldAdvance")(s, C, 0.5, { qing: false, mei: false });
    if (s.world.event) for (const r of s.world.event.roles) if (!s.world.event.choices[r]) G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, s.world.event.eventId), true);
    met = s.log.some((e) => e.kind === "milestone" && (e.events.qing === "m_junior" || e.events.mei === "m_junior"));
    assert.ok(++guard < 200000 && out, "升上来的存档没走到小升初");
  }
  assert.ok(met, "升上来的存档到了 12 岁照样过关口");
  // 比服务器还新的存档不硬读
  assert.throws(() => G("lifeUpgrade")({ version: G("LIFE_VERSION") + 1 }));
  console.log("✓ v4 存档升 v5：schoolDay 换成 rest / 补上 dutyDone 和关口 / 没有了的 school 行动和择校事件摘掉 / 接着过到小升初");
}
