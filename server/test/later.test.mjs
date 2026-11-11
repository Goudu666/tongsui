// 后半生押时间（content/events/later.yaml、content/map.yaml 后半生那一节、docs/MEANS.md 第七节）：
// 退了休也挣得到零花 / 一回挣的钱和押出去的一段对得上 / 事开出来的去处只给碰上的人 / 花积蓄的选项上锁 / 碰得上的岁数 / 文风。
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parse } from "yaml";
import { G, C, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const ON = { qing: true, mei: true };
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const act = (id) => C.map.actions.find((a) => a.id === id);
const spot = (id) => C.map.spots.find((s) => s.id === id);
const ev = (id) => C.events.find((e) => e.id === id);
const MID = C.families.find((f) => f.wealth === 1).id;

function lifeAt(seed, age, flags = []) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  for (const r of ROLES) { const p = s.persons[r]; p.familyId = MID; p.flags.push(...flags); }
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  s.world.event = null; // 命运给的事先撇开：这里只看去处本身
  s.world.fate = {};
  return s;
}
const at = (s, r, id) => { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; };
const pick = (s, r, id) => G("worldPickAction")(s, C, r, spot(id)).act?.id ?? null;
const SLOTS = G("SLOTS");
const setSlot = (s, i) => { s.world.slot = i; s.world.minute = SLOTS[i][0]; s.world.dutyDone = { qing: true, mei: true }; };
const slotFor = (id) => SLOTS.findIndex((sl) => { const h = act(id).requires.hours; return !h || (sl[0] < h[1] && sl[1] > h[0]); });
const pass = (s) => { const from = s.world.slot, turn = s.turn; for (let i = 0; i < 4000 && s.world.slot === from && s.turn === turn; i++) G("worldAdvance")(s, C, 0.5, ON); };
const where = (id) => C.map.spots.find((sp) => (sp.actions ?? [sp.action]).includes(id));

// ---------- 1. 退了休的营生：谁都去得了，两个钟头挣三块，累 ----------
{
  for (const id of ["old_breakfast", "old_bikes", "mind_kids"]) {
    const a = act(id);
    assert.ok(a.money > 0 && a.needs.energy < 0, `${id} 拿时间和精力换钱`);
    assert.ok(!(a.requires.flags ?? []).length, `${id} 不看出身和走过的路`);
    assert.equal(a.requires.minAge, 60, `${id} 退了休才有`);
    assert.ok(where(id), `${id} 要有个点位`);
  }
  // 真去做一回：六十五岁的人在早点铺后厨，积蓄多三块
  const s = lifeAt(21, 65);
  const sp = where("old_breakfast").id;
  setSlot(s, slotFor("old_breakfast"));
  at(s, "qing", sp);
  assert.equal(pick(s, "qing", sp), "old_breakfast");
  const before = s.persons.qing.money;
  assert.equal(G("worldAct")(s, C, "qing", sp).error, null);
  const scale = s.world.actors.qing.scale; // 早上那一段只有一个半钟头，按做了几成算
  G("worldPass")(s, C, "mei");
  pass(s);
  assert.ok(scale > 0 && Math.abs(s.persons.qing.money - (before + act("old_breakfast").money * scale)) < 0.11, `包了一早上包子，积蓄 ${before} → ${s.persons.qing.money}`);
  // 五十九岁还在上班的人看不见
  const y = lifeAt(21, 57);
  setSlot(y, slotFor("old_breakfast"));
  at(y, "qing", sp);
  assert.notEqual(pick(y, "qing", sp), "old_breakfast", "没退休的人不去后厨包包子");
  // 六十到七十全押上也挣不出一辈子的积蓄：两天、一天至多五段
  const most = 2 * 5 * Math.max(...["old_breakfast", "old_bikes", "mind_kids"].map((id) => act(id).money));
  const care = ev("m_evening").options.find((o) => o.id === "care").min;
  assert.ok(most <= care / 4, `六十到七十全押上挣 ${most} 块，请人照应要 ${care}：够得着差一口气，顶不了积蓄`);
  console.log(`✓ 退了休的营生：三样谁都去得了、一段挣 ${act("old_breakfast").money} 块、累；六十到七十全押上至多 ${most} 块（照应要 ${care}）`);
}

// ---------- 2. 事开出来的去处：只给碰上的人；每样都由一件事的选项打上标记 ----------
{
  const opened = { square_dance: ["lt_dance", "join"], pair_cook: ["lt_meal", "share"], gk_pickup: ["lt_gk_class", "pick"] };
  for (const [id, [eid, oid]] of Object.entries(opened)) {
    const flag = act(id).requires.flags[0];
    assert.ok(ev(eid).options.find((o) => o.id === oid).effects.flags.includes(flag), `${eid}.${oid} 开出 ${id}`);
    assert.ok(where(id), `${id} 要有个点位`);
    const s = lifeAt(22, 65);
    const sp = where(id).id;
    setSlot(s, slotFor(id));
    at(s, "qing", sp);
    assert.notEqual(pick(s, "qing", sp), id, `没碰上 ${eid} 的人没有 ${id}`);
    s.persons.qing.flags.push(flag);
    assert.equal(pick(s, "qing", sp), id, `碰上了 ${eid} 选了 ${oid}，${id} 就开了`);
  }
  // 带孙辈：有孙辈的才有，能带上对门
  const g = act("grandkid_park");
  assert.ok(g.requires.flags.includes("has_kid") && g.bring && g.together, "带孙辈：要有孙辈，能带上对门，凑一块儿算搭伴");
  // 楼道拐角一个点位摆三样：小时候是老先生家，老了是一锅饭和看孩子（后面跟着人际圈子的「给楼里搭把手」，docs/CIRCLE.md）
  assert.equal(JSON.stringify(spot("hall_upstairs").actions.slice(0, 3)), JSON.stringify(["old_lessons", "pair_cook", "mind_kids"]));
  console.log("✓ 开出来的去处：跳舞、一锅饭、接孙辈只给碰上那件事的人 / 带孙辈要有孙辈、能带对门 / 都在图上");
}

// ---------- 3. 花积蓄的选项：钱不够灰着，选了扣；每件都留着两个不花钱的 ----------
{
  const s = lifeAt(23, 65, ["has_kid"]);
  s.persons.qing.money = 10;
  s.world.event = { eventId: "lt_gk_class", kind: "solo", roles: ["qing"], choices: {}, shadow: [] };
  const lock = (G("lifeMilestoneLocks")(s, C) || {}).qing || {};
  assert.ok(lock.pay, "积蓄十块，补习班那份钱出不起");
  assert.ok(!lock.pick && !lock.no, "不花钱的两条谁都能选");
  s.persons.qing.money = 100;
  G("worldChoose")(s, C, "qing", "pay", false);
  assert.equal(s.persons.qing.money, 100 - ev("lt_gk_class").options.find((o) => o.id === "pay").cost, "选了出钱，积蓄扣掉");
  console.log("✓ 花积蓄：补习班钱不够灰着、出了就扣");
}

// ---------- 4. 碰得上的岁数：老年的事落在六十五岁那个日子，中年的落在退休以前 ----------
{
  const elig = (id, age, flags = []) => {
    const s = lifeAt(24, age, flags);
    return G("lifeEligible")(ev(id), G("lifeTimeAt")(s.turn), s.persons.qing.flags.concat(s.persons.mei.flags), {}, { bond: s.bond, alone: false });
  };
  for (const id of ["lt_tour", "lt_borrow", "lt_fall", "lt_ward"]) {
    assert.ok(elig(id, 65) && !elig(id, 60), `${id}：六十五岁碰得上，六十岁那天（退休的关口）不冒出来`);
  }
  assert.ok(elig("lt_gk_class", 65, ["has_kid"]) && !elig("lt_gk_class", 65), "补习班只给有孙辈的");
  assert.ok(elig("lt_meal", 60) && ev("lt_meal").where, "一锅饭在楼道里碰上，退休那天傍晚就碰得上");
  for (const id of ["lt_dance", "lt_sea"]) assert.ok(elig(id, 54) && !elig(id, 60), `${id}：退休以前碰得上`);
  console.log("✓ 岁数：老年的事落在六十五岁那个日子（七十岁那道关之前），中年的在退休以前");
}

// ---------- 5. 文风（docs/tianjin_style.md §1.2、§9.1） ----------
{
  const TEXT_MAX = { middle: 45, old: 30 };
  const BANNED = ["嘛", "介", "倍儿", "哏儿", "甭", "您了", "得嘞", "崴泥", "打镲", "拔创", "好么", "嚯", "话匣子"];
  const len = (x) => [...String(x ?? "")].length;
  const all = parse(readFileSync(new URL("../../content/events/later.yaml", import.meta.url), "utf8"));
  assert.ok(all.length >= 8, "后半生的事");
  for (const e of all) {
    assert.ok(len(e.text) <= TEXT_MAX[e.stage], `${e.id} 正文 ${len(e.text)} 字，${e.stage} 上限 ${TEXT_MAX[e.stage]}`);
    assert.ok(len(e.title) <= 7, `${e.id} 标题太长`);
    if (e.hint) assert.ok(len(e.hint) <= 15, `${e.id} hint 太长`);
    for (const o of e.options) assert.ok(len(o.text) <= 15, `${e.id}.${o.id} 选项 ${len(o.text)} 字`);
    for (const s of [e.text, ...e.options.map((o) => o.text)]) for (const w of BANNED) assert.ok(!s.includes(w), `${e.id}：旁白和选项不用方言词「${w}」`);
    assert.ok(!/\d/.test(e.text), `${e.id}：不写年份数字`);
    const open = e.options.filter((o) => !o.cost && !(o.requires?.flags?.length));
    assert.ok(open.length >= 2, `${e.id}：留着两个不花钱、谁都能选的`);
  }
  for (const a of ["old_breakfast", "old_bikes", "mind_kids", "grandkid_park", "square_dance", "pair_cook", "gk_pickup"]) assert.ok(len(act(a).label) <= 10, `${a} 名字太长`);
  console.log(`✓ 文风：${all.length} 件后半生的事守字数上限，旁白和选项不用方言、不写年份`);
}
