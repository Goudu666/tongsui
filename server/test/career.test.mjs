// 职业路线（docs/CAREER.md）：26 岁「站住脚」、36 岁「挑大梁」两道升迁关，九个行当各升两级。
// 钉住七件事：别的行当的路锁着、藏着（hide），自己这行的只看分数 / 升了级换路、涨工钱，四十五争到位子再乘 /
// 跳槽转行摘掉原来那一行（effects.drop）/ 普通事件的 drop 也生效、检定没成不摘 / build-content 拦写坏的 hide 和 drop /
// 一条路都走不通走兜底 / 没有 rank 标记的老存档照旧走原来的路。
// 线和工钱的数另一头在调（tools/sprint.mjs、tools/paths.mjs），这里只钉「谁看得见哪条、走了落在哪」，不钉具体的数。
import assert from "node:assert/strict";
import { cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse, stringify } from "yaml";
import { G, C, J, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const ev = (id, c = C) => c.events.find((e) => e.id === id);
const opt = (e, id) => e.options.find((o) => o.id === id);
const track = (id) => C.tracks.find((t) => t.id === id);
const fam = (id) => C.families.find((f) => f.id === id);
const RICH = C.families.find((f) => f.wealth === 2).id;
const MID = C.families.find((f) => f.wealth === 1).id;
const POOR = C.families.find((f) => f.wealth === 0).id;
const RISE = ev("m_rise");
const RISE2 = ev("m_rise2");
const STATS = ["body", "mind", "charm", "luck"];
/** 九个行当（外地算一个）和它在两道关上的那条升级的路：从内容里读，requires.flags 的第一个就是行当 */
const JOBS = ["job_desk", "job_pull", "job_teach", "job_trade", "job_craft", "job_labor", "job_succeed", "job_odd", "left_city"];
const UP = Object.fromEntries(RISE.options.filter((o) => o.id.startsWith("up_")).map((o) => [o.requires.flags[0], o]));
const TOP = Object.fromEntries(RISE2.options.filter((o) => o.id.startsWith("top_")).map((o) => [o.requires.flags[0], o]));
/** 行当的标记 → 它在 tracks.yaml 里原来那条路（外地是 job_away） */
const BASE = { left_city: "job_away" };
for (const j of JOBS) if (!BASE[j]) BASE[j] = j;

function bornInto(s, r, id) {
  const p = s.persons[r];
  p.flags = p.flags.filter((f) => !fam(p.familyId).traits.includes(f)).concat(fam(id).traits);
  p.familyId = id;
  p.money = fam(id).money;
}
/** 一条走到 age 岁第一天早上的人生：两个人都是 family 人家，带上 flags，属性都设成 stat、积蓄设成 money */
function lifeAt(seed, age, { family = MID, flags = [], stat = null, money = null, c = C } = {}) {
  const s = G("lifeCreate")(seed, c);
  for (const r of ROLES) G("lifeConfirm")(s, c, r, NAMES);
  for (const r of ROLES) {
    bornInto(s, r, family);
    s.persons[r].flags.push(...flags);
    if (stat !== null) for (const k of STATS) s.persons[r].stats[k] = stat;
    if (money !== null) s.persons[r].money = money;
  }
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, c);
  return s;
}
/** 让 r 一个人碰上这件事（跳过地点、日子和发挥），返回他锁着的路 */
function meet(s, r, id, c = C) {
  s.world.event = { eventId: id, kind: ev(id, c).kind, roles: [r], choices: {}, shadow: [] };
  return (G("lifeMilestoneLocks")(s, c) || {})[r] || {};
}
/** 客户端 main.gd → milestone_options 的同一条规矩：写了 hide、锁着的理由正是它的 lock 那句，就不摆 */
const shown = (e, locks) => [...e.options].filter((o) => !(o.hide && locks[o.id] === (o.lock || "这条路不是给你留的")));
const wageOf = (p, age) => G("worldWage")(C, p, G("lifeTrack")(C, p, age).duty, age);

// ---------- 0. 内容的骨架：每个行当两级、路排在原来那份工前头 ----------
{
  for (const j of JOBS) {
    assert.ok(UP[j], `${j} 在 26 岁有一条升级的路`);
    assert.ok(TOP[j], `${j} 在 36 岁有一条再往上的路`);
    assert.ok(UP[j].hide && TOP[j].hide && UP[j].lock && TOP[j].lock, `${j} 的路只给这一行看（hide + lock）`);
    assert.deepEqual(J(UP[j].effects.flags), ["rank1"]);
    assert.deepEqual(J(TOP[j].effects.flags), ["rank2"]);
    assert.ok(TOP[j].requires.flags.includes("rank1"), `${TOP[j].id} 要先升过一级`);
    const base = BASE[j];
    const i0 = C.tracks.findIndex((t) => t.id === base);
    const i1 = C.tracks.findIndex((t) => t.id === `${base}_r1`);
    const i2 = C.tracks.findIndex((t) => t.id === `${base}_r2`);
    assert.ok(i2 >= 0 && i1 > i2 && i0 > i1, `${base}：_r2、_r1 要排在原来那条前头（lifeTrack 取第一条符合的）`);
    const rq = (t) => track(t).requires;
    // 打零工原来那条是兜底（不要标记），升了级的要 job_odd：只给二十二岁走了这条路的人
    const want = (rank) => [...new Set([...(rq(base).flags || []), j, rank])].sort();
    assert.deepEqual(J(rq(`${base}_r1`).flags).sort(), want("rank1"), `${base}_r1 的标记 = 这一行 + rank1`);
    assert.deepEqual(J(rq(`${base}_r2`).flags).sort(), want("rank2"), `${base}_r2 的标记 = 这一行 + rank2`);
    // 外地那条另加 laid_off：下了岗的不带着科长的工钱南下（job_away 本身留着兜底）
    const wantNot = [...new Set([...(rq(base).notFlags || []), ...(base === "job_away" ? ["laid_off"] : [])])];
    assert.deepEqual(J(rq(`${base}_r1`).notFlags || []), wantNot, `${base}_r1 的 notFlags 和原来一样`);
    for (const t of [`${base}_r1`, `${base}_r2`]) assert.equal(track(t).group, base, `${t} 和原来那条算同一件事（搭伴、worldSameThing）`);
    for (const t of [`${base}_r1`, `${base}_r2`]) assert.ok(track(t).label !== track(base).label && track(t).label.includes(" · "), `${t} 换了路名（「原来的 · 升到哪」）：${track(t).label}`);
  }
  for (const id of ["steady"]) assert.ok(!opt(RISE, id).requires && !opt(RISE, id).min, "26 岁有一条谁都走得了的兜底");
  for (const id of ["hold"]) assert.ok(!opt(RISE2, id).requires && !opt(RISE2, id).min, "36 岁有一条谁都走得了的兜底");
  // 关口真的在那一天：26、36 岁那天早上排上的就是这两道关
  for (const [age, id] of [[26, "m_rise"], [36, "m_rise2"]]) {
    const s = lifeAt(9, age, { flags: ["job_desk"] });
    assert.equal(s.world.fate.milestone, id, `${age} 岁那天是「${ev(id).title}」`);
  }
  // 挑大梁那天主线照排（withStory）：36 岁在第五章（30~44）中间，不让的话第五章只剩三天排三件，三十三岁起天天强制
  assert.equal(ev("m_rise2").withStory, true);
  assert.equal(G("storyMilestoneDay")(C, turnAtAge(36)), false, "36 岁不算关口日，主线能排");
  assert.deepEqual(J(G("storyToday")(lifeAt(9, 33), C, G("lifeTimeAt")(turnAtAge(33)), false).force), [], "三十三岁第五章还不紧，不强制");
  console.log(`✓ 骨架：${JOBS.length} 个行当各有 up_* / top_*（hide + lock）/ tracks 里 _r2、_r1 排在原来那条前头、标记多一级、换了路名 / 26、36 岁那天排上两道关、挑大梁那天主线照排`);
}

// ---------- 1. 26 岁那关：别的行当的路锁着、藏着，自己这行的只看分数 ----------
{
  const tally = [];
  for (const j of JOBS) {
    // 本事和积蓄都够：自己这行的路不锁
    const s = lifeAt(11, 26, { flags: [j], stat: 9.9, money: 500 });
    const locks = meet(s, "qing", "m_rise");
    for (const [k, o] of Object.entries(UP)) {
      if (k === j) assert.equal(locks[o.id], undefined, `${j}：自己这行的 ${o.id} 本事够就不锁（锁着：${locks[o.id]}）`);
      else assert.equal(locks[o.id], o.lock, `${j}：别的行当的 ${o.id} 锁着，理由就是它的 lock`);
    }
    // 客户端照 hide 摆：升级的路只摆自己这一条，藏起来的只有标记不对的
    const vis = shown(RISE, locks);
    assert.deepEqual(vis.filter((o) => o.id.startsWith("up_")).map((o) => o.id), [UP[j].id], `${j}：关口上只摆自己这行的升级路`);
    assert.ok(vis.some((o) => o.id === "steady"), `${j}：兜底的那条总摆着`);
    for (const o of RISE.options) if (!vis.includes(o)) assert.ok(o.hide && locks[o.id] === o.lock, `${j}：${o.id} 藏起来只能是因为标记`);
    tally.push(`${j}:${vis.length}`);
    // 服务器也拦：别的行当的路选不了
    const other = Object.values(UP).find((o) => o !== UP[j]);
    assert.match(G("worldChoose")(s, C, "qing", other.id, false).error, /走不了/, `${j}：选别的行当的 ${other.id} 服务器不收`);
    for (let i = 0; i < 30; i++) {
      const pick = G("lifeShadowChoose")(s, C, "qing", "m_rise");
      assert.ok(!locks[pick], `${j}：影子不替人选锁着的 ${pick}`);
    }

    // 本事不够：自己这行的路照旧锁着，可理由是分数（客户端照旧灰着摆出来）
    const w = lifeAt(12, 26, { flags: [j], stat: 1, money: 500 });
    const wl = meet(w, "qing", "m_rise");
    assert.match(wl[UP[j].id], /分，线是 \d+ 分/, `${j}：本事不够，${UP[j].id} 锁的理由是分数`);
    assert.notEqual(wl[UP[j].id], UP[j].lock);
    assert.ok(shown(RISE, wl).includes(UP[j]), `${j}：分数不够的照旧摆出来（灰着）`);
    // 本事够、钱不够（要本钱的那几行）：理由是积蓄
    if (UP[j].cost) {
      const m = lifeAt(13, 26, { flags: [j], stat: 9.9, money: 0 });
      assert.match(meet(m, "qing", "m_rise")[UP[j].id], /积蓄 0 块，要 \d+ 块/, `${j}：${UP[j].id} 钱不够，写差多少`);
    }

    // 目标条：22~25 岁看着的是 26 岁这关，只摆自己这行的线
    const g = lifeAt(14, 24, { flags: [j], stat: 5 });
    const goal = J(G("lifeGoal")(g, C, "qing"));
    assert.equal(goal.id, "m_rise", `${j}：二十四岁的目标是二十六岁站住脚`);
    const ids = goal.lines.map((l) => l.id);
    assert.deepEqual(ids.filter((id) => id.startsWith("up_")), [UP[j].id], `${j}：目标条上只有自己这行的升级线：${ids}`);
    for (const id of ids) {
      const o = opt(RISE, id);
      const rq = o.requires || {};
      assert.ok((rq.flags || []).every((f) => g.persons.qing.flags.includes(f)) && !(rq.notFlags || []).some((f) => g.persons.qing.flags.includes(f)), `${j}：目标条上的 ${id} 是给这个人留的`);
    }
  }
  // 殷实人家多一条「家里托人」：小康、清贫灰着看得见（seat 没写 hide），殷实的走得了
  const rich = lifeAt(15, 26, { family: RICH, flags: ["job_desk"], stat: 9.9, money: 500 });
  assert.equal(meet(rich, "qing", "m_rise").seat, undefined, "殷实：家里托人走得了");
  for (const f of [MID, POOR]) {
    const s = lifeAt(15, 26, { family: f, flags: ["job_desk"], stat: 9.9, money: 500 });
    const l = meet(s, "qing", "m_rise");
    assert.equal(l.seat, opt(RISE, "seat").lock, `${f}：家里托人锁着（${opt(RISE, "seat").lock}）`);
    assert.ok(shown(RISE, l).some((o) => o.id === "seat"), `${f}：没写 hide，灰着摆出来`);
  }
  console.log(`✓ 26 岁：每个行当别的 up_* 锁着、理由是 lock、客户端不摆、服务器拦、影子不选 / 自己这行的只因分数或积蓄锁 / 目标条只摆自己这行 / 殷实多一条托人（摆出来的路数 ${tally.join(" ")}）`);
}

// ---------- 2. 升了级：换路、涨工钱；36 岁再升；45 岁争到位子再乘 ----------
{
  const s = lifeAt(21, 26, { flags: ["job_desk"], stat: 9.9, money: 100 });
  const p = s.persons.qing;
  const base = wageOf(p, 26);
  assert.equal(G("lifeTrack")(C, p, 26).id, "job_desk");
  meet(s, "qing", "m_rise");
  const r = G("worldChoose")(s, C, "qing", "up_desk", false);
  assert.equal(r.error, null);
  assert.ok(p.flags.includes("rank1") && p.flags.includes("job_desk"), "评上组长：打 rank1，行当不变");
  assert.equal(r.entry.results.qing.track, "job_desk_r1", "关口的成绩单上写着新路");
  assert.equal(G("lifeTrack")(C, p, 27).id, "job_desk_r1");
  const r1 = wageOf(p, 27);
  assert.ok(r1 > base, `组长挣得比坐办公室多：${r1} > ${base}`);
  // 36 岁挑大梁：top_desk 要 rank1
  s.turn = turnAtAge(36);
  meet(s, "qing", "m_rise2");
  assert.equal(G("worldChoose")(s, C, "qing", "top_desk", false).error, null);
  assert.ok(p.flags.includes("rank2"));
  assert.equal(G("lifeTrack")(C, p, 37).id, "job_desk_r2");
  const r2 = wageOf(p, 37);
  assert.ok(r2 > r1, `科长再多：${r2} > ${r1}`);
  // 45 岁争到位子（mid_post）：rules.daily.wageFlags 在上面再乘
  const mult = C.rules.daily.wageFlags.mid_post;
  p.flags.push("mid_post");
  assert.equal(wageOf(p, 46), Math.round(track("job_desk_r2").duty.money * mult * 10) / 10, `争到位子的科长：×${mult}`);
  assert.ok(wageOf(p, 46) > r2);

  // 每个行当：原来 < 一级 < 二级，带 mid_post 都再乘
  const curve = [];
  for (const j of JOBS) {
    const q = lifeAt(22, 30, { flags: [j] }).persons.qing;
    const w0 = wageOf(q, 30);
    assert.equal(G("lifeTrack")(C, q, 30).id, BASE[j]);
    q.flags.push("rank1");
    assert.equal(G("lifeTrack")(C, q, 30).id, `${BASE[j]}_r1`);
    const w1 = wageOf(q, 30);
    q.flags.push("rank2");
    assert.equal(G("lifeTrack")(C, q, 30).id, `${BASE[j]}_r2`, `${j}：rank1、rank2 都有时取二级`);
    const w2 = wageOf(q, 30);
    q.flags.push("mid_post");
    const wp = wageOf(q, 46);
    assert.ok(w0 < w1 && w1 < w2, `${j}：工钱一级比一级高 ${w0} < ${w1} < ${w2}`);
    assert.equal(wp, Math.round(track(`${BASE[j]}_r2`).duty.money * mult * 10) / 10, `${j}：争到位子再乘 ${mult}`);
    curve.push(`${BASE[j]} ${w0}/${w1}/${w2}/${wp}`);
  }
  console.log(`✓ 升了级：up_desk → job_desk_r1（成绩单上写着）/ top_desk → job_desk_r2 / 带 mid_post 再乘 ${mult} / 每个行当工钱一级比一级高：${curve.join("，")}`);
}

// ---------- 3. 跳槽、转行：摘掉原来那一行，从头干 ----------
{
  // 转行做买卖：摘掉 job_desk 和 rank1，带上 job_trade、switched，花掉 20 块
  const s = lifeAt(31, 26, { flags: ["job_desk", "rank1"], stat: 9.9, money: 100 });
  const p = s.persons.qing;
  assert.equal(G("lifeTrack")(C, p, 26).id, "job_desk_r1");
  const locks = meet(s, "qing", "m_rise");
  assert.equal(locks.up_desk, opt(RISE, "up_desk").lock, "升过一级的不再升这一级");
  assert.equal(locks.to_trade, undefined);
  const before = p.money;
  const r = G("worldChoose")(s, C, "qing", "to_trade", false);
  assert.equal(r.error, null);
  for (const f of ["job_desk", "rank1"]) assert.ok(!p.flags.includes(f), `转了行，${f} 摘掉了`);
  for (const f of ["job_trade", "switched"]) assert.ok(p.flags.includes(f), `转了行，带上 ${f}`);
  assert.equal(G("lifeTrack")(C, p, 27).id, "job_trade", "从头干：做买卖，不是有了门脸的");
  assert.equal(r.entry.results.qing.track, "job_trade");
  assert.equal(p.money, before - opt(RISE, "to_trade").cost, "本钱扣了");
  // 转了行的人 36 岁那关：本行（做买卖）没升过级，top_trade 锁着；还有一回「熬出来」
  s.turn = turnAtAge(36);
  const l2 = meet(s, "qing", "m_rise2");
  assert.equal(l2.top_trade, opt(RISE2, "top_trade").lock);
  assert.equal(l2.top_desk, opt(RISE2, "top_desk").lock, "原来那一行的路也没了");
  assert.equal(l2.late, undefined, "没升过的还能熬出来");

  // 外地的、已经做买卖的不能转去做买卖
  for (const j of ["left_city", "job_trade"]) {
    const t = lifeAt(32, 26, { flags: [j], stat: 9.9, money: 100 });
    assert.equal(meet(t, "qing", "m_rise").to_trade, opt(RISE, "to_trade").lock, `${j} 看不见「辞了，出来做买卖」`);
  }
  // 拜师学手艺：不要本钱；摘掉原来那一行
  const k = lifeAt(33, 26, { flags: ["job_labor"], stat: 9.9, money: 0 });
  meet(k, "qing", "m_rise");
  assert.equal(G("worldChoose")(k, C, "qing", "to_craft", false).error, null);
  assert.deepEqual(["job_labor", "job_craft", "switched"].map((f) => k.persons.qing.flags.includes(f)), [false, true, true]);
  assert.equal(G("lifeTrack")(C, k.persons.qing, 27).id, "job_craft");
  // 跳槽：同一行换个东家，升一级（rank1 + jumped），行当不摘
  const jp = lifeAt(34, 26, { flags: ["job_teach"], stat: 9.9, money: 0 });
  meet(jp, "qing", "m_rise");
  assert.equal(G("worldChoose")(jp, C, "qing", "jump", false).error, null);
  assert.ok(["job_teach", "rank1", "jumped"].every((f) => jp.persons.qing.flags.includes(f)));
  assert.equal(G("lifeTrack")(C, jp.persons.qing, 27).id, "job_teach_r1");
  // 打零工的、接班的没有跳槽这条
  for (const j of ["job_odd", "job_succeed"]) {
    const t = lifeAt(35, 26, { flags: [j], stat: 9.9 });
    assert.equal(meet(t, "qing", "m_rise").jump, opt(RISE, "jump").lock, `${j} 看不见跳槽`);
  }
  // 36 岁被挖走：升过一级的才有人挖，直接 rank2 + jumped，亲近掉一点
  const pc = lifeAt(36, 36, { flags: ["job_desk", "rank1"], stat: 9.9, money: 0 });
  const nopc = lifeAt(36, 36, { flags: ["job_desk"], stat: 9.9, money: 0 });
  assert.equal(meet(nopc, "qing", "m_rise2").poach, opt(RISE2, "poach").lock, "没升过的没人挖");
  meet(pc, "qing", "m_rise2");
  const close = pc.bond.close;
  assert.equal(G("worldChoose")(pc, C, "qing", "poach", false).error, null);
  assert.ok(["job_desk", "rank1", "rank2", "jumped"].every((f) => pc.persons.qing.flags.includes(f)));
  assert.equal(G("lifeTrack")(C, pc.persons.qing, 37).id, "job_desk_r2");
  assert.ok(pc.bond.close < close, "老东家那头的人情没了，亲近掉一点");
  console.log("✓ 跳槽转行：to_trade 摘掉 job_desk、rank1，带上 job_trade、switched，路是 job_trade、扣了本钱 / 外地、本行的看不见 / to_craft 摘掉卖力气 / jump 打 rank1 + jumped 不摘行当 / poach 只给升过的");
}

// ---------- 4. 普通事件的 effects.drop：先摘再打，检定没成不摘 ----------
{
  const c2 = J(C);
  const opts = (flagsAdd, drop) => [
    { id: "quit", text: "辞了", tags: [], effects: { self: {}, other: {}, bond: {}, flags: flagsAdd, drop } },
    { id: "stay", text: "接着干", tags: [], effects: { self: {}, other: {}, bond: {}, flags: [] } },
  ];
  // 手造的事件照着编好的普通事件的样子（build-content 补齐的字段都在），年纪设得够不着：只在这儿用 meet 碰上
  const tpl = C.events.find((e) => e.kind === "solo" && !e.options.some((o) => o.requires || o.cost));
  const make = (id, options) => c2.events.push({ ...J(tpl), id, requires: { minAge: 200 }, resonance: null, dissonance: null, options });
  make("t_drop", opts(["switched"], ["job_desk", "rank1"]));
  make("t_keep", opts(["rank1", "switched"], ["rank1", "job_desk"]));
  make("t_check", opts(["switched"], ["job_desk"]));
  c2.checks.push({ event: "t_check", option: "quit", stat: "luck", dc: 5, pass: "成了。", fail: { text: "没成。", flags: ["tried"] } });
  const run = (eventId, rules) => {
    const s = lifeAt(41, 33, { flags: ["job_desk", "rank1"], c: c2 });
    if (rules) Object.assign(c2.rules.check, rules);
    meet(s, "qing", eventId, c2);
    assert.equal(G("lifeMilestoneLocks")(s, c2), null, "没门槛的普通事件不发 locks");
    const r = G("worldChoose")(s, c2, "qing", "quit", false);
    assert.equal(r.error, null);
    return s.persons.qing.flags;
  };
  let f = run("t_drop");
  assert.ok(!f.includes("job_desk") && !f.includes("rank1") && f.includes("switched"), `普通事件也摘：${f}`);
  f = run("t_keep");
  assert.ok(f.includes("rank1") && !f.includes("job_desk"), "先摘再打：两边都写的标记留着");
  const saved = { ...c2.rules.check };
  f = run("t_check", { min: 0, max: 0 }); // 一定没成
  assert.ok(f.includes("job_desk") && f.includes("tried") && !f.includes("switched"), `检定没成、换了 fail 的标记：不摘 ${f}`);
  f = run("t_check", { min: 1, max: 1 }); // 一定成
  assert.ok(!f.includes("job_desk") && f.includes("switched"), "检定成了：照样摘");
  Object.assign(c2.rules.check, saved);
  // fail 没写标记（用原来的）也算没换：照样摘（out.flags 就是 effects.flags）
  c2.checks.at(-1).fail.flags = null;
  f = run("t_check", { min: 0, max: 0 });
  assert.ok(!f.includes("job_desk") && f.includes("switched"), "fail 没写标记，标记照原样打，也照原样摘");
  console.log("✓ 普通事件的 drop：摘掉 / 两边都写的留着 / 检定没成换了 fail 标记的不摘、成了的摘、fail 没写标记的照样摘");
}

// ---------- 5. build-content 拦写坏的 hide 和 drop ----------
{
  // build-content.mjs 按自己所在的目录找 content/，不收参数：拷一份脚本和 content 到临时目录里跑，写不到仓库里
  const repo = fileURLToPath(new URL("../../", import.meta.url));
  const tmp = mkdtempSync(join(tmpdir(), "tongsui-career-"));
  try {
    mkdirSync(join(tmp, "tools"));
    cpSync(join(repo, "tools", "build-content.mjs"), join(tmp, "tools", "build-content.mjs"));
    cpSync(join(repo, "content"), join(tmp, "content"), { recursive: true });
    mkdirSync(join(tmp, "client", "data"), { recursive: true });
    mkdirSync(join(tmp, "client", "art", "street"), { recursive: true });
    const sprites = join(repo, "client", "art", "street", "sprites.json");
    if (existsSync(sprites)) cpSync(sprites, join(tmp, "client", "art", "street", "sprites.json"));
    mkdirSync(join(tmp, "server", "src"), { recursive: true });
    symlinkSync(join(repo, "node_modules"), join(tmp, "node_modules"), "dir"); // yaml
    const build = () => spawnSync(process.execPath, [join(tmp, "tools", "build-content.mjs")], { encoding: "utf8" });
    const careerPath = join(tmp, "content", "events", "career.yaml");
    const original = parse(readFileSync(careerPath, "utf8"));
    const write = (list) => writeFileSync(careerPath, stringify(list));

    // 原样的能过；普通事件的选项写 drop 也能过，进了 content.json
    const ok = J(original);
    const plain = parse(readFileSync(join(tmp, "content", "events", "lives.yaml"), "utf8"));
    const target = plain.find((e) => e.kind !== "milestone" && e.options.some((o) => !o.requires && !o.cost));
    const to = target.options.find((o) => !o.requires && !o.cost);
    to.effects = { ...(to.effects || {}), drop: ["job_desk"] };
    writeFileSync(join(tmp, "content", "events", "lives.yaml"), stringify(plain));
    write(ok);
    let r = build();
    assert.equal(r.status, 0, `原样的内容要能编过：\n${r.stderr}`);
    const built = JSON.parse(readFileSync(join(tmp, "client", "data", "content.json"), "utf8"));
    assert.deepEqual(built.events.find((e) => e.id === target.id).options.find((o) => o.id === to.id).effects.drop, ["job_desk"], "普通事件的 drop 编进了内容");
    assert.equal(built.events.find((e) => e.id === "m_rise").options.find((o) => o.id === "up_desk").hide, true, "hide 编进了内容（客户端读它）");
    assert.equal(built.events.find((e) => e.id === "m_rise").options.find((o) => o.id === "steady").effects.drop, undefined, "没写 drop 的不多出 drop");

    // 写坏：hide 不是 true / hide 写在没有标记条件的路上 / drop 不是列表 / drop 是空列表 / drop 里有不是字符串的
    const bad = J(original);
    const rise = bad.find((e) => e.id === "m_rise");
    rise.options.find((o) => o.id === "up_desk").hide = "yes";
    rise.options.find((o) => o.id === "steady").hide = true;
    rise.options.find((o) => o.id === "to_trade").effects.drop = "job_desk";
    rise.options.find((o) => o.id === "to_desk").effects.drop = [];
    rise.options.find((o) => o.id === "to_craft").effects.drop = ["job_labor", 3];
    write(bad);
    r = build();
    assert.equal(r.status, 1, "写坏了要报错退出");
    const err = r.stderr;
    for (const id of ["up_desk", "steady"]) assert.match(err, new RegExp(`${id}\\.hide: 只能写 true`), `${id} 的 hide 写坏了要报出来：\n${err}`);
    for (const id of ["to_trade", "to_desk", "to_craft"]) assert.match(err, new RegExp(`${id}\\.effects\\.drop: `), `${id} 的 drop 写坏了要报出来：\n${err}`);
    // 普通事件的选项不收 hide（只有关口用）
    const bad2 = J(original);
    write(bad2);
    to.hide = true;
    to.requires = { flags: ["job_desk"] };
    writeFileSync(join(tmp, "content", "events", "lives.yaml"), stringify(plain));
    r = build();
    assert.equal(r.status, 1, "普通事件的选项写 hide 要报错");
    assert.match(r.stderr, /hide/, r.stderr);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  console.log("✓ build-content：原样能过、普通事件的 drop 和关口的 hide 编进内容 / hide 不是 true、写在没标记条件的路上、drop 不是非空字符串列表都报错 / 普通事件不收 hide");
}

// ---------- 6. 兜底：一条路都走不通，走 steady / hold ----------
{
  assert.equal(G("lifeMilestoneFallback")(RISE).id, "steady");
  assert.equal(G("lifeMilestoneFallback")(RISE2).id, "hold");
  // 本事、积蓄都是零的人：只剩兜底那条，服务器替他定了，不弹窗
  for (const [age, id, fb] of [[26, "m_rise", "steady"], [36, "m_rise2", "hold"]]) {
    const s = lifeAt(51, age, { flags: ["job_desk"], stat: 0, money: 0 });
    for (const r of ROLES) {
      const locks = meet(s, r, id);
      assert.deepEqual([...ev(id).options].filter((o) => !locks[o.id]).map((o) => o.id), [fb], `${id}：本事是零只剩 ${fb}`);
      assert.equal(G("lifeShadowChoose")(s, C, r, id), fb);
    }
    s.world.event = null;
    let out = null;
    for (let i = 0; i < 600 && !out; i++) {
      const o = G("worldAdvance")(s, C, 0.1, { qing: true, mei: true });
      if (o.started || o.dayEnded || o.entries.some((e) => e.kind === "milestone")) out = o;
    }
    assert.ok(out && !out.started, `${id}：两个人都只有一条路，不弹窗`);
    const entry = out.entries.find((e) => e.kind === "milestone");
    for (const r of ROLES) assert.equal(entry.choices[r], fb, `${id}：两个人都走 ${fb}`);
    assert.equal(entry.resonance, true, "都走兜底也是同路");
  }
  // 内容热更新写漏：兜底的路也挂上够不着的线，照旧不抛错、走线最低的
  const c2 = J(C);
  c2.events.find((e) => e.id === "m_rise").options.forEach((o) => { o.min = 99; });
  const s = lifeAt(52, 26, { flags: ["job_desk"], stat: 0, money: 0, c: c2 });
  assert.equal(G("lifeShadowChoose")(s, c2, "qing", "m_rise"), "steady");
  console.log("✓ 兜底：m_rise 走 steady、m_rise2 走 hold / 只剩兜底时服务器替两个人定、不弹窗、算同路 / 兜底也锁上时照旧走它");
}

// ---------- 7. 老存档：没有 rank 标记的人照旧走原来的路 ----------
{
  for (const j of JOBS) {
    const s = lifeAt(61, 39, { flags: [j] }); // 中年三年一回合：39 岁是真有的一回合（40 岁找不到，会落到 turn −1 那年）
    const p = s.persons.qing;
    assert.equal(G("lifeTrack")(C, p, 40).id, BASE[j], `老存档的 ${j}：没有 rank 还是原来那条路`);
    assert.equal(wageOf(p, 40), track(BASE[j]).duty.money, `${j}：工钱是原来的`);
    p.flags.push("mid_post");
    assert.equal(wageOf(p, 46), Math.round(track(BASE[j]).duty.money * C.rules.daily.wageFlags.mid_post * 10) / 10, `${j}：老存档争到位子照旧乘`);
  }
  // 二十六岁以后才升上来的存档（开局时还没有这两道关）：碰不上 26 岁那关；33 岁看的目标是 36 岁，只有「熬出来」
  const s = lifeAt(62, 33, { flags: ["job_desk"], stat: 5 });
  assert.notEqual(s.world.fate.milestone, "m_rise");
  const goal = J(G("lifeGoal")(s, C, "qing"));
  assert.equal(goal.id, "m_rise2");
  const ids = goal.lines.map((l) => l.id);
  assert.ok(ids.includes("late") && !ids.some((id) => id.startsWith("top_")) && !ids.includes("poach"), `没升过的老存档：只有熬出来那条线 ${ids}`);
  // 36 岁那关照样过得去：熬出来升一级，或者兜底
  const t = lifeAt(63, 36, { flags: ["job_desk"], stat: 9.9 });
  const locks = meet(t, "qing", "m_rise2");
  assert.equal(locks.top_desk, opt(RISE2, "top_desk").lock, "没升过一级的直接当不了科长");
  assert.equal(locks.late, undefined);
  assert.equal(locks.hold, undefined);
  assert.equal(G("worldChoose")(t, C, "qing", "late", false).error, null);
  assert.equal(G("lifeTrack")(C, t.persons.qing, 37).id, "job_desk_r1", "熬出来：组长");
  // 外地回来的（came_back）不再走外地的路，也看不见外地的升级
  const back = lifeAt(64, 26, { flags: ["left_city", "came_back", "job_odd"], stat: 9.9 });
  assert.equal(meet(back, "qing", "m_rise").up_away, opt(RISE, "up_away").lock);
  console.log(`✓ 老存档：${JOBS.length} 个行当没 rank 还是原来那条路、原来的工钱、争到位子照旧乘 / 过了 26 岁的只看得见熬出来 / 36 岁照样过 / 回了城的不看外地的路`);
}
