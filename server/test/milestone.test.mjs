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
  console.log("✓ 关口躲不掉：一早睡下（一个人 / 两个人）照样来 / 睡着的叫醒、做事的放下 / 过了不来第二遍 / 每个关口都一样");
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
  for (const r of ROLES) assert.ok(ms.options.every((o) => G("lifeOptionLock")(ms, o, s.persons[r], 0, G("lifePairBond")(s, r))), "这里要的是每条路都锁着");
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
  console.log("✓ 关口无路可走：不抛错不回滚，走线最低的那条 / 影子同一个兜底 / 一人无路一人有得选 / 每个关口都有兜底的路");
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
  assert.equal(J(up)[0], "v4→v5"); // 后面还会接着往上升（v5→v6 ……），这里只看这一段
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
    if (s.world.event) for (const r of [...s.world.event.roles]) if (s.world.event && !s.world.event.choices[r]) G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, s.world.event.eventId), true);
    met = s.log.some((e) => e.kind === "milestone" && (e.events.qing === "m_junior" || e.events.mei === "m_junior"));
    assert.ok(++guard < 200000 && out, "升上来的存档没走到小升初");
  }
  assert.ok(met, "升上来的存档到了 12 岁照样过关口");
  // 比服务器还新的存档不硬读
  assert.throws(() => G("lifeUpgrade")({ version: G("LIFE_VERSION") + 1 }));
  console.log("✓ v4 存档升 v5：schoolDay 换成 rest / 补上 dutyDone 和关口 / 没有了的 school 行动和择校事件摘掉 / 接着过到小升初");
}

// ---------- 5. 成年后歇班那天工钱照发 ----------
{
  // 成年以后一个日子就是一年：歇班（三成的日子）要是没有工钱，八年里拿几年全看运气，三十岁安家那一关就成了碰运气
  const day = (age, flags, wantRest) => {
    for (let seed = 1; seed < 400; seed++) {
      const s = lifeAt(seed, age);
      const before = {};
      for (const r of ROLES) { s.persons[r].flags.push(...flags); before[r] = s.persons[r].money; }
      s.turn = turnAtAge(age);
      G("worldStartDay")(s, C);
      if (s.world.fate.milestone || s.world.rest !== wantRest) continue;
      return { s, before };
    }
    assert.fail("没抽到要的日子");
  };
  const desk = C.tracks.find((t) => t.id === "job_desk").duty;
  const off = day(25, ["job_desk"], true);
  for (const r of ROLES) {
    assert.equal(G("lifeTrack")(C, off.s.persons[r], 25).id, "job_desk");
    assert.equal(off.s.persons[r].money - off.before[r], desk.money, "歇班的那一年工钱照发");
    assert.equal(G("worldDuty")(off.s, C, r), null, "歇班就是歇班，不用去");
  }
  const on = day(25, ["job_desk"], false);
  for (const r of ROLES) assert.equal(on.s.persons[r].money, on.before[r], "上班的日子，钱是下班时候拿的，不会一早先发一遍");
  // 小时候和少年不算：一年有好几个日子，歇一天就是歇一天（辍学打工的少年歇了也没有工钱）
  const kid = day(13, ["dropout"], true);
  for (const r of ROLES) {
    assert.ok(G("lifeTrack")(C, kid.s.persons[r], 13).duty.money > 0);
    assert.equal(kid.s.persons[r].money, kid.before[r]);
  }
  console.log("✓ 歇班日：成年后工钱照发、不用去 / 上班日不多发 / 小时候和少年歇了就没有");
}

// ---------- 6. 关口上挣来的东西接得上后面的日子 ----------
{
  /** 找一个 age 岁的平常日子（不是关口、要上学或上班），两个人带着各自的标记 */
  const plain = (age, flags) => {
    for (let seed = 1; seed < 400; seed++) {
      const s = lifeAt(seed, age);
      for (const r of ROLES) s.persons[r].flags.push(...(flags[r] || []));
      s.turn = turnAtAge(age);
      G("worldStartDay")(s, C);
      if (!s.world.fate.milestone && !s.world.rest) return s;
    }
    assert.fail("没抽到要的日子");
  };
  const spot = (id) => C.map.spots.find((sp) => sp.id === id);
  // 一天五段：把这一天拨到某一段的开头（钟点只停在段的开头）
  const setSlot = (s, i) => { s.world.slot = i; s.world.minute = G("SLOTS")[i][0]; };
  const setMin = (s, m) => setSlot(s, G("worldSlotAt")(m));
  const pick = (s, r, id) => G("worldPickAction")(s, C, r, spot(id)).act?.id ?? null;
  const at = (s, r, id) => { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; };

  // 6 岁那一关：当了学习委员的和没当的还是同班，一起上学照样算搭伴
  {
    const s = plain(8, { qing: ["lead_study"] });
    assert.equal(G("lifeTrack")(C, s.persons.qing, 8).id, "primary_study");
    assert.equal(G("lifeTrack")(C, s.persons.mei, 8).id, "primary");
    setSlot(s, G("worldDutySlots")(G("worldDuty")(s, C, "qing"))[0]);
    for (const r of ROLES) { at(s, r, "school_gate"); assert.equal(G("worldAct")(s, C, r, "school_gate").error, null); }
    const before = { qing: s.persons.qing.stats.mind, mei: s.persons.mei.stats.mind };
    for (let i = 0; i < 4000 && s.world.actors.qing.action; i++) G("worldAdvance")(s, C, 0.5, ON);
    assert.ok(s.world.warm, "不同的小干部一起上学也是搭伴");
    assert.ok(s.persons.qing.stats.mind - before.qing > s.persons.mei.stats.mind - before.mei, "学习委员上一天学，心智长得多一点");
  }

  // 9 岁那一关：进了小组的人，放学以后校门口是小组；没进的、不在钟点上的、毕了业的都不是
  {
    const s = plain(10, { qing: ["club_math", "club_sport"] });
    const club = C.map.actions.find((a) => a.id === "club_math");
    setMin(s, club.requires.hours[0] - 30);
    s.world.dutyDone = { qing: true, mei: true };
    assert.equal(pick(s, "qing", "school_gate"), "club_math", "还没到钟点：点位上有名字");
    at(s, "qing", "school_gate");
    assert.equal(G("worldAct")(s, C, "qing", "school_gate").error, "现在不是时候", "但做不了");
    assert.equal(pick(s, "qing", "school_yard"), "ball", "体校没开练，操场照样能踢球");
    setMin(s, club.requires.hours[0] + 10);
    assert.equal(pick(s, "qing", "school_gate"), "club_math");
    assert.equal(pick(s, "qing", "school_yard"), "club_sport");
    assert.equal(pick(s, "mei", "school_gate"), null, "没进小组的人看不见它");
    assert.equal(pick(s, "mei", "school_yard"), "ball");
    at(s, "mei", "school_gate");
    assert.ok(G("worldAct")(s, C, "mei", "school_gate").error, "也做不了");
    setMin(s, club.requires.hours[1] + 100);
    assert.equal(G("worldAct")(s, C, "qing", "school_gate").error, "现在不是时候", "锁门以后也做不了");
    assert.equal(pick(s, "qing", "school_yard"), "ball", "操场又只能踢球了");
    // 小组比自己写作业长得快，但没有快到非进不可
    const study = C.map.actions.find((a) => a.id === "study");
    assert.ok(club.stats.mind > study.stats.mind && club.stats.mind <= study.stats.mind * 1.4);
    const older = plain(13, { qing: ["club_math"] });
    setMin(older, club.requires.hours[0] + 10);
    older.world.dutyDone = { qing: true, mei: true };
    assert.notEqual(pick(older, "qing", "school_gate"), "club_math", "小学毕业以后小组就散了");
    // 客户端不知道标记：WORLD 里带一张「我挣来的去处」的单子
    const view = G("worldView")({ record: { life: s }, moveSeq: {}, tick: 0 });
    // 单子里还有家境给的（学琴、帮家里干活，见 test/means.test.mjs），这里只看关口挣来的
    const clubs = (r) => J(view.tracks[r].unlocks).filter((id) => id.startsWith("club_")).sort();
    assert.deepEqual(clubs("qing"), ["club_math", "club_sport"]);
    assert.deepEqual(clubs("mei"), []);
  }

  // 45 岁那一关：争到位子的人工钱多五成（歇班那年也是）
  {
    const s = plain(48, { qing: ["job_desk", "mid_post"], mei: ["job_desk"] });
    const desk = C.tracks.find((t) => t.id === "job_desk").duty;
    assert.equal(G("worldWage")(C, s.persons.qing, desk), Math.round(desk.money * C.rules.daily.wageFlags.mid_post * 10) / 10);
    assert.equal(G("worldWage")(C, s.persons.mei, desk), desk.money);
  }

  // 70 岁那一关：搭伙过看的是亲近，原数给人看；对门不在了这条路就没有了
  {
    const s = lifeAt(9, 70, C, 2);
    assert.equal(s.world.fate.milestone, "m_evening");
    const ev = C.events.find((e) => e.id === "m_evening"), pair = ev.options.find((o) => o.id === "pair");
    const lock = (r) => G("lifeOptionLock")(ev, pair, s.persons[r], 0, G("lifePairBond")(s, r));
    s.bond.close = pair.min - 1;
    assert.ok(lock("qing").includes("亲近") && lock("qing").includes(String(pair.min)), "差一点：告诉他线在哪");
    assert.equal(G("lifeOptionLock")(ev, pair, s.persons.qing, 5, s.bond), lock("qing"), "亲近不看临场发挥");
    s.bond.close = pair.min;
    assert.equal(lock("qing"), null);
    const goal = G("lifeGoal")(s, C, "qing").lines.find((l) => l.id === "pair");
    assert.deepEqual([goal.have, goal.need, goal.ok], [pair.min, pair.min, true]);
    s.persons.mei.alive = false;
    assert.ok(lock("qing"), "一个人搭不了伙");
    assert.ok(ev.options.some((o) => !G("lifeOptionLock")(ev, o, s.persons.qing, 0, G("lifePairBond")(s, "qing"))), "但总有一条路");
  }

  // 走过的路折成寿数：每一条都在四年以内，加起来压不过命数本身的起伏
  {
    const s = lifeAt(9, 60, C, 5);
    const p = s.persons.qing;
    p.lifespan = 76; s.bond.close = 0;
    const base = G("growthLimit")(s, C, "qing");
    let sum = 0;
    for (const [f, years] of Object.entries(C.rules.lifespan.flags)) {
      p.flags.push(f);
      assert.equal(Math.round((G("growthLimit")(s, C, "qing") - base) * 10) / 10, years, f);
      p.flags.pop();
      assert.ok(Math.abs(years) <= 4);
      sum += Math.max(0, years);
    }
    assert.ok(sum <= 8, "所有的好路都走到也只多活 " + sum + " 年");
  }

  // 从三岁第一天起眼前就有一道关：上小学
  {
    const s = lifeAt(3, 3);
    const goal = G("lifeGoal")(s, C, "qing");
    assert.equal(goal.id, "m_school");
    assert.ok(goal.lines.length >= 3);
    // hx：带一位小数（往下取整），整数部分就是 have；小时候一回只长零点几分，界面靠它让纸带的数挪一挪
    s.persons.qing.stats.charm = 3.04;
    const art = G("lifeGoal")(s, C, "qing").lines.find((l) => l.id === "art");
    assert.deepEqual([art.have, art.hx], [30, 30.4]);
    s.persons.qing.stats.charm = 2.98;
    const art2 = G("lifeGoal")(s, C, "qing").lines.find((l) => l.id === "art");
    assert.deepEqual([art2.have, art2.hx], [29, 29.8], "往下取整");
  }
  // 一世的头一个早上不弹随机的事：人刚落地，先走两步、按一回（主线照常）。第二天的早上照旧
  {
    const s = lifeAt(3, 3);
    assert.equal(s.turn, 0);
    const calm = (turn) => {
      s.turn = turn;
      s.world.slot = 0; s.world.minute = 400; s.world.event = null; s.world.done = [];
      s.world.fate = { mirror: null, qing: "c_rainy_day", mei: null };
      for (const r of ROLES) { const a = s.world.actors[r]; a.asleep = false; G("worldClearAction")(a); }
      return G("worldAdvance")(s, C, 0.1, ON).started;
    };
    assert.equal(calm(0), null, "头一天早上不弹「下雨天」");
    assert.equal(calm(1)?.eventId, "c_rainy_day", "第二天早上照常");
  }
  // 走了不看分的那条路，长卷上不记「0 分」
  {
    const s = lifeAt(5, 6, C, 9);
    untilMilestone(s);
    assert.equal(G("worldChoose")(s, C, "qing", "go", false).error, null);
    assert.equal(G("worldChoose")(s, C, "mei", "study", false).error, null);
    const res = s.log.at(-1).results;
    assert.deepEqual([res.qing.score, res.qing.scored], [0, false], "分数照旧是数字（旧安装包拿它当数字用），画不画看 scored");
    assert.deepEqual([res.mei.score, res.mei.scored, res.mei.unit], [90, true, "分"]);
  }
  console.log("✓ 关口接得上日子：小干部还是同班 / 小组只给进了的人、只在放学后、毕业就散 / 位子多五成工钱 / 搭伙看亲近、对门空了就没有 / 走过的路折成寿数 / 三岁起眼前就有一道关、纸带带一位小数 / 头一个早上不弹随机的事 / 不看分的路不记 0 分");
}

// ---------- 7. 默契替考场托底 ----------
{
  // 同一个种子、同样的两个人，只差默契：手气好的时候一分不多，手气差的时候少丢一些，对门不在了就没有
  const swings = (sync, alone) => {
    const out = [];
    for (let seed = 1; seed <= 60; seed++) {
      const s = lifeAt(seed, 18, C, 9);
      s.bond.sync = sync;
      if (alone) s.persons.mei.alive = false;
      untilMilestone(s);
      if (s.world.event) out.push({ swing: s.world.event.swing.qing, steady: s.world.event.steady.qing || 0 });
    }
    return out;
  };
  const none = swings(0), full = swings(100), alone = swings(100, true);
  assert.ok(none.length >= 50 && none.length === full.length);
  let helped = 0;
  for (let i = 0; i < none.length; i++) {
    assert.equal(none[i].steady, 0);
    assert.ok(full[i].swing >= none[i].swing);
    assert.equal(Math.round((full[i].swing - none[i].swing) * 100), Math.round(full[i].steady * 100), "托住多少就告诉他多少");
    assert.ok(full[i].steady <= (G("SWING_RANGE") / 2) * C.rules.bond.syncSteady + 1e-9);
    if (full[i].steady > 0) helped++;
  }
  assert.ok(helped > none.length * 0.3 && helped < none.length * 0.7, "只有手气差的那一半有人托");
  assert.ok(alone.every((x) => x.steady === 0), "对门不在了，没有人在外头等");
  console.log(`✓ 默契托底：60 场高考里 ${helped} 场手气差，默契 100 最多托回 ${Math.round(Math.max(...full.map((x) => x.steady)) * 10)} 分 / 手气好不多给 / 一个人没有`);
}

// ---------- 8. 揭晓演出要的几样（client/scripts/ui/reveal.gd） ----------
{
  // 小学当小干部：心智 5.0（50 分）够不着学习委员 55 的线，走了兜底；最近的那条差一点的线要报出来（results.near，和结局页同一个数）
  // （一条路都够不着，不弹窗，直接记进长卷）
  const s = lifeAt(11, 6, C, 5);
  untilMilestone(s);
  assert.equal(s.world.event, null);
  const res = s.log.findLast((e) => e.kind === "milestone").results.qing;
  assert.equal(res.line, undefined, "不看分的路没有线");
  assert.equal(res.miss, undefined, "差一点不另算，读 near（atlasMilestoneNear）");
  assert.ok(res.near && res.near.need > res.near.have, "差一点的那条：线比分高");
  assert.ok(["study", "sport", "art"].includes(res.near.option));
  // 够着了：选的那条路的线按百分制给，比分低；够着了的路不算「差一点」
  const t = lifeAt(12, 6, C, 9);
  untilMilestone(t);
  assert.equal(G("worldChoose")(t, C, "qing", "study", false).error, null);
  assert.equal(G("worldChoose")(t, C, "mei", "go", false).error, null);
  const ok = t.log.at(-1).results.qing;
  assert.equal(ok.line, 55);
  assert.ok(ok.score >= ok.line);
  assert.equal(ok.near, undefined, "三项都 90 分，哪条线都够得着");
  // 发挥：高考有手气，报出来的数和这一场的 swing 对得上；托住的那截不超过发挥的绝对值
  const g = lifeAt(9, 18, C, 7);
  g.bond.sync = 100;
  untilMilestone(g);
  const pe = J(g.world.event);
  for (const r of ROLES) assert.equal(G("worldChoose")(g, C, r, G("lifeShadowChoose")(g, C, r, "m_gaokao"), false).error, null);
  const gr = g.log.at(-1).results;
  for (const r of ROLES) {
    assert.equal(gr[r].luck || 0, Math.round((pe.swing[r] || 0) * 10) || 0, "发挥按百分制报");
    assert.equal(gr[r].steady || 0, Math.round((pe.steady[r] || 0) * 10) || 0);
  }
  console.log("✓ 揭晓演出：选的路报线 / 走了兜底报差一点的那条 / 发挥和托底按百分制报");
}
