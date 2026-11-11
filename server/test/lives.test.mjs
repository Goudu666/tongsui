// 人生岔路（docs/MEANS.md 第六节）：同一道关不同的冲法、半路换掉的活法、奇遇开出来的去处。
// 钉住五件事：普通事件的选项也能上锁（看不见、灰着、服务器拦、影子不选、花了扣钱）/ 岔口换掉走的路 /
// 每样新去处只给该给的人 / 新内容守字数和方言预算 / 一世里真碰得上。
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parse } from "yaml";
import { G, C, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const fam = (id) => C.families.find((f) => f.id === id);
const ev = (id) => C.events.find((e) => e.id === id);
const RICH = C.families.find((f) => f.wealth === 2).id;
const MID = C.families.find((f) => f.wealth === 1).id;
const POOR = C.families.find((f) => f.wealth === 0).id;

function bornInto(s, r, id) {
  const p = s.persons[r];
  p.flags = p.flags.filter((f) => !fam(p.familyId).traits.includes(f)).concat(fam(id).traits);
  p.familyId = id;
  p.money = fam(id).money;
}
function lifeAt(seed, age, qf, mf, flags = []) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  bornInto(s, "qing", qf);
  bornInto(s, "mei", mf);
  for (const r of ROLES) s.persons[r].flags.push(...flags);
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  return s;
}
/** 让 r 碰上这件事（跳过地点和随机数） */
function meet(s, r, id) {
  s.world.event = { eventId: id, kind: ev(id).kind, roles: [r], choices: {}, shadow: [] };
  return (G("lifeMilestoneLocks")(s, C) || {})[r] || {};
}

// ---------- 1. 普通事件的选项也有门槛 ----------
{
  // 标记不对的人：那一项锁着（客户端不摆出来），服务器也拦
  const s = lifeAt(3, 36, MID, RICH, ["job_desk"]);
  const mine = meet(s, "qing", "lv_sea");
  assert.ok(mine.family, "小康人家的孩子没有「家里出本钱」");
  assert.ok(!mine.go && !mine.stay, "谁都能选的不上锁");
  assert.ok(G("worldChoose")(s, C, "qing", "family", false).error, "锁着的选项服务器不收");
  for (let i = 0; i < 40; i++) assert.notEqual(G("lifeShadowChoose")(s, C, "qing", "lv_sea"), "family", "影子不替人选锁着的");
  const theirs = meet(s, "mei", "lv_sea");
  assert.ok(!theirs.family, "殷实人家的孩子有这一项");
  assert.equal(G("worldChoose")(s, C, "mei", "family", false).error, null);
  assert.ok(G("lifeHasFlag")(s.persons.mei, "own_shop") && G("lifeHasFlag")(s.persons.mei, "quit_job"), "家里出了本钱，铺子开起来了");
  assert.ok(!(s.persons.mei.flags.includes("shop_shaky")), "家里出的本钱不看手气");

  // 没有门槛的事件照旧不上锁、不发 locks
  const t = lifeAt(3, 36, MID, MID);
  t.world.event = { eventId: "m_class_reunion", kind: "solo", roles: ["qing"], choices: {}, shadow: [] };
  assert.equal(G("lifeMilestoneLocks")(t, C), null, "没有门槛的事件不发 locks（旧安装包照旧）");
  console.log("✓ 门槛：标记不对的锁着、服务器拦、影子不选 / 殷实的选得了 / 没门槛的事件不发 locks");
}
{
  // 花钱的选项：钱不够灰着写差多少；选了扣积蓄
  const s = lifeAt(4, 42, MID, MID, ["own_shop"]);
  s.persons.qing.money = 12;
  assert.match(meet(s, "qing", "lv_shop_second").take, /积蓄 12 块，要 30 块/);
  s.persons.qing.money = 80;
  assert.ok(!meet(s, "qing", "lv_shop_second").take);
  assert.equal(G("worldChoose")(s, C, "qing", "take", false).error, null);
  assert.equal(s.persons.qing.money, 50, "盘第二家花掉 30 块（成没成都花了）");
  // 主线选项的 cost 原来只上锁不扣钱：现在也扣
  const st = C.story.events.find((e) => e.options.some((o) => o.cost && !(o.requires?.flags?.length)));
  const o = st.options.find((x) => x.cost && !(x.requires?.flags?.length));
  const u = lifeAt(5, 30, MID, MID);
  u.persons.qing.flags.push(...(st.requires.flags || []));
  u.persons.qing.money = 100;
  u.world.event = { eventId: st.id, kind: "solo", roles: ["qing"], choices: {}, shadow: [] };
  const lock = (G("lifeMilestoneLocks")(u, C) || {}).qing || {};
  if (!lock[o.id]) {
    assert.equal(G("worldChoose")(u, C, "qing", o.id, false).error, null);
    assert.equal(u.persons.qing.money, 100 - o.cost, `主线「${st.title}」选了「${o.text}」要扣 ${o.cost} 块`);
  }
  console.log("✓ 花钱：钱不够的灰着写差多少 / 选了扣积蓄 / 主线选项的钱也扣了");
}

// ---------- 2. 岔口换掉走的路 ----------
{
  const s = lifeAt(6, 39, MID, MID, ["job_desk"]);
  const track = (flags) => { const p = s.persons.qing; p.flags = ["job_desk", ...flags]; return G("lifeTrack")(C, p, 42).id; };
  assert.equal(track([]), "job_desk");
  assert.equal(track(["own_shop", "quit_job"]), "job_own", "下海：每天去看自己的铺子");
  assert.equal(track(["own_shop", "quit_job", "shop_shaky", "shop_closed", "no_job"]), "job_lost", "铺子关了：打零工");
  assert.equal(track(["laid_off", "own_stall"]), "job_stall", "下岗以后支摊");
  assert.equal(track(["laid_off", "left_city"]), "job_away", "下岗去南方");
  assert.equal(track(["laid_off", "no_job"]), "job_lost");
  assert.equal(track(["laid_off", "no_job", "own_stall"]), "job_stall", "再就业以后出摊");
  const money = (id) => C.tracks.find((t) => t.id === id).duty.money;
  assert.ok(money("job_own") < money("job_desk") && money("job_own") > money("job_trade"), "自己的铺子：比坐办公室少一点、比摆摊多");
  assert.ok(money("job_lost") < money("job_stall"), "支起摊来比打零工强");
  // 这些岔口谁碰得上
  const eligible = (id, flags, age) => G("lifeEligible")(ev(id), G("lifeTimeAt")(turnAtAge(age)), flags, {}, { bond: s.bond, alone: false });
  assert.ok(eligible("lv_sea", ["job_desk"], 39) && eligible("lv_sea", ["job_teach"], 39) && eligible("lv_sea", ["job_pull"], 39), "坐办公室、教书、托关系的碰得上下海");
  assert.ok(!eligible("lv_sea", ["job_trade"], 39) && !eligible("lv_sea", ["job_succeed"], 39), "做买卖、进厂的不碰下海");
  assert.ok(!eligible("m_layoff", ["job_teach"], 42) && !eligible("m_layoff", ["own_shop"], 42) && eligible("m_layoff", ["job_desk"], 42), "教书的、自己开铺子的不在下岗名单上");
  assert.ok(!eligible("lv_reform", ["job_succeed", "laid_off"], 39), "下过岗的不再碰改制");
  console.log("✓ 岔口：下海 / 铺子关了 / 下岗支摊、去南方、打零工 / 再就业，各换各的路；谁碰得上谁碰不上");
}

// ---------- 3. 新去处只给该给的人 ----------
{
  const act = (id) => C.map.actions.find((a) => a.id === id);
  const can = (id, flags, age) => {
    const rq = act(id).requires;
    return age >= (rq.minAge ?? 0) && age <= (rq.maxAge ?? 999) && (rq.flags ?? []).every((f) => flags.includes(f)) && !(rq.notFlags ?? []).some((f) => flags.includes(f));
  };
  // 殷实拿钱换分（要花钱），奇遇开出来的不要钱
  for (const id of ["swim_class", "lang_class", "banquet"]) {
    assert.ok(act(id).money < 0, `${id} 要花钱`);
    assert.ok(can(id, ["fam_rich"], act(id).requires.minAge) && !can(id, ["fam_poor"], act(id).requires.minAge), `${id} 只给殷实人家`);
  }
  for (const id of ["run_dawn", "old_lessons"]) assert.ok(!act(id).money && act(id).bring, `${id} 不要钱，能带上对门`);
  // 下了班的营生：每条路一样，都挣钱、都累
  const side = { side_tutor: "job_teach", side_fix: "job_craft", night_market: "job_trade", overtime: "job_desk" };
  for (const [id, job] of Object.entries(side)) {
    assert.ok(act(id).money > 0 && act(id).needs.energy < 0, `${id} 拿时间和精力换钱`);
    assert.ok(can(id, [job], 30) && !can(id, ["job_labor"], 30), `${id} 只给 ${job}`);
  }
  for (const job of ["job_labor", "job_succeed", "job_odd"]) assert.ok(can("night_shift", [job], 30), `码头夜活 ${job} 去得了`);
  for (const job of ["job_desk", "job_teach", "job_pull"]) assert.ok(!can("night_shift", [job], 30), `码头夜活不给 ${job}`);
  assert.ok(can("night_class", ["work_early"], 19) && !can("night_class", ["uni_near"], 19), "夜校给早早干活的人");
  // 每样都摆在地图上，挂在一个点位上
  for (const id of ["swim_class", "lang_class", "banquet", "night_class", "run_dawn", "old_lessons", ...Object.keys(side), "night_shift"]) {
    assert.ok(C.map.spots.some((sp) => (sp.actions ?? [sp.action]).includes(id)), `${id} 要有个点位`);
  }
  console.log("✓ 新去处：殷实的三样花钱、只给殷实 / 奇遇的两样不要钱、能带人 / 各条路下了班的营生 / 夜校给早早干活的 / 都在图上");
}

// ---------- 4. 字数和方言（docs/tianjin_style.md §1.2、§9.1） ----------
{
  const TEXT_MAX = { childhood: 60, teen: 55, young: 50, middle: 45, old: 30 };
  const MAX = { hint: 15, title: 7, option: 15 };
  const BANNED = ["嘛", "介", "倍儿", "哏儿", "甭", "您了", "得嘞", "崴泥", "打镲", "拔创", "好么", "嚯", "话匣子"];
  const len = (x) => [...String(x ?? "")].length;
  const NEW = ["lives", "chance"];
  const listed = NEW.flatMap((f) => parse(readFileSync(new URL(`../../content/events/${f}.yaml`, import.meta.url), "utf8")));
  const means = parse(readFileSync(new URL("../../content/events/means.yaml", import.meta.url), "utf8")).filter((e) => e.id.startsWith("mn_"));
  const all = [...listed, ...means];
  assert.ok(all.length >= 35, "岔路、奇遇、家境的新事件");
  for (const e of all) {
    assert.ok(len(e.text) <= TEXT_MAX[e.stage], `${e.id} 正文 ${len(e.text)} 字，${e.stage} 上限 ${TEXT_MAX[e.stage]}`);
    assert.ok(len(e.title) <= MAX.title, `${e.id} 标题太长`);
    if (e.hint) assert.ok(len(e.hint) <= MAX.hint, `${e.id} hint 太长`);
    for (const o of e.options) assert.ok(len(o.text) <= MAX.option, `${e.id}.${o.id} 选项 ${len(o.text)} 字`);
    for (const s of [e.text, ...e.options.map((o) => o.text)]) for (const w of BANNED) assert.ok(!s.includes(w), `${e.id}：旁白和选项不用方言词「${w}」`);
    assert.ok(!/\d/.test(e.text), `${e.id}：不写年份数字`);
  }
  // 每件新事件说得出挂在哪道关上：岔路篇和奇遇篇的文件头写着；这里只查一件事：带门槛的选项至少留两个谁都能选的（build-content 也拦）
  for (const e of all) {
    const open = e.options.filter((o) => !o.cost && !(o.requires?.flags?.length || o.requires?.notFlags?.length));
    if (open.length < e.options.length) assert.ok(open.length >= 2, `${e.id}：挂了门槛也要留两个谁都能选的`);
  }
  console.log(`✓ 文风：${all.length} 件新事件守字数上限，旁白和选项不用方言、不写年份 / 挂了门槛的都留着两个谁都能选的`);
}
