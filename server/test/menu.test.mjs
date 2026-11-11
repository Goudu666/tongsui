// 点位菜单（协议 8，2026-11-11）：一个点位上几件事，ACT 带 action 点哪件做哪件；不带还是头一件（影子、机器人、旧安装包）。
// 钉住：点哪件做哪件 / 不带还是头一件 / 不在这个点位上的、年纪不到的、标记不对的、不在钟点上的都回一句话 /
// 两个人做菜单上同一件才算搭伴，同一个点位做不同的两件不算 / 做到点也能点菜单上的 / 菜单上的新事都守成长的上限。
import assert from "node:assert/strict";
import { G, C, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const SLOTS = G("SLOTS");
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const spot = (id) => C.map.spots.find((sp) => sp.id === id);
const act = (id) => C.map.actions.find((a) => a.id === id);
function at(s, r, id) { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; }
function day(age, slot, seed = 7) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  const w = s.world;
  w.fate = { mirror: null, qing: null, mei: null };
  w.rest = true;
  w.slot = slot;
  w.minute = SLOTS[slot][0];
  for (const r of ROLES) {
    const p = s.persons[r];
    p.stats = { body: 5, mind: 5, charm: 5, luck: 5 };
    p.needs = { hunger: 80, energy: 80, mood: 80, clean: 80 };
    p.flags = p.flags.filter((f) => !f.startsWith("tal_") && !f.startsWith("fam_"));
    p.money = 20;
  }
  return s;
}
const doIt = (s, r, sp, a, once = true) => G("worldAct")(s, C, r, sp, once, a);

// ---------- 1. 点哪件做哪件，不带还是头一件 ----------
{
  const s = day(17, 2);
  at(s, "qing", "tea_seat");
  const m0 = s.persons.qing.money;
  assert.equal(doIt(s, "qing", "tea_seat", "tea_runner").error, null);
  assert.equal(s.world.actors.qing.did.a, "tea_runner", "点的是跑堂，做的就是跑堂");
  assert.equal(s.persons.qing.money, m0 + act("tea_runner").money, "跑堂挣钱");
  at(s, "mei", "tea_seat");
  assert.equal(doIt(s, "mei", "tea_seat").error, null);
  assert.equal(s.world.actors.mei.did.a, "listen", "不带 action 是菜单头一件（喝茶听一段）");
}

// ---------- 2. 点不了的回一句话 ----------
{
  const s = day(8, 2);
  at(s, "qing", "tea_seat");
  assert.equal(doIt(s, "qing", "tea_seat", "study").error, "这儿没有这件事");
  assert.equal(doIt(s, "qing", "tea_seat", "tea_runner").error, "还太小了", "八岁跑不了堂");
  assert.equal(doIt(s, "qing", "tea_seat", "tea_box").error, "这件事轮不到你", "没有殷实的家底包不了座");
  s.persons.qing.flags.push("fam_rich");
  assert.equal(doIt(s, "qing", "tea_seat", "tea_box").error, null, "殷实人家的孩子包得了座");
  const s2 = day(30, 0);
  at(s2, "qing", "alley_rope");
  assert.equal(doIt(s2, "qing", "alley_rope", "cards").error, "现在不是时候", "打扑克是晚上的事");
  const s3 = day(30, 4);
  at(s3, "qing", "alley_rope");
  assert.equal(doIt(s3, "qing", "alley_rope", "cards").error, null, "晚上打得了");
}

// ---------- 3. 菜单上同一件才算搭伴 ----------
{
  const s = day(20, 4);
  for (const r of ROLES) at(s, r, "alley_rope");
  assert.equal(doIt(s, "qing", "alley_rope", "cards").error, null);
  assert.equal(doIt(s, "mei", "alley_rope", "chat").error, null);
  assert.equal(s.world.actors.mei.did.tg, false, "同一个点位、不同的两件事，不算搭伴");
  const t = day(20, 4);
  for (const r of ROLES) at(t, r, "alley_rope");
  assert.equal(doIt(t, "qing", "alley_rope", "cards").error, null);
  assert.equal(doIt(t, "mei", "alley_rope", "cards").error, null);
  assert.equal(t.world.actors.mei.did.tg, true, "都打扑克，算搭伴");
}

// ---------- 4. 做到点也能点菜单上的 ----------
{
  const s = day(16, 2);
  at(s, "qing", "mall_floor");
  s.persons.qing.flags.push("p_bridge");
  const err = doIt(s, "qing", "mall_floor", "mall_clerk", false).error;
  assert.equal(err, null);
  assert.equal(s.world.actors.qing.action, "mall_clerk", "整段押上的是站柜台，不是逛商场");
}

// ---------- 5. 菜单上后添的事守成长的上限 ----------
// 同一个阶段里，不靠标记的事每个钟头长得最多的那件，后添的不超过它：菜单是换着花时间，不是多给
{
  const ADDED = C.map.actions.filter((a) => a.menu).map((a) => a.id);
  assert.ok(ADDED.length >= 14, "后添的事都标了 menu");
  const STAGES = [[3, 11], [12, 17], [18, 29], [30, 59], [60, 90]];
  // 靠标记的（关口上挣来的、家境带的）和靠家里东西的（requires.home：家里有书柜、复读机，docs/HOME.md）不算：那是资源差异，本来就该快
  const open = (a, lo, hi) => !(a.requires?.minAge > hi) && !(a.requires?.maxAge < lo) && !a.requires?.flags && !a.requires?.home && !a.quick && !a.duty && !a.sleep;
  for (const [lo, hi] of STAGES) {
    const old = C.map.actions.filter((a) => open(a, lo, hi) && !ADDED.includes(a.id));
    for (const k of ["body", "mind", "charm"]) {
      const cap = Math.max(...old.map((a) => (a.stats?.[k] || 0) / a.minutes));
      for (const id of ADDED) {
        const a = act(id);
        if (!open(a, lo, hi)) continue;
        assert.ok((a.stats?.[k] || 0) / a.minutes <= cap + 1e-9, `${id} 在 ${lo}–${hi} 岁的${k}每分钟 ${((a.stats?.[k] || 0) / a.minutes).toFixed(4)}，超过了原来最快的 ${cap.toFixed(4)}`);
      }
    }
  }
}

// ---------- 6. 不点菜单的永远轮不到后添的事 ----------
// 旧安装包、影子、机器人不带 action：每个点位、每个年纪、每个时段、有没有家底，选出来的都不是 menu 的事。
// 头一件不在钟点上照旧回「现在不是时候」，不会掉到后添的划船、拉胡琴上去（交叉评审指出的）
{
  let n = 0;
  for (const age of [5, 10, 14, 20, 35, 50, 70]) for (let slot = 0; slot < SLOTS.length; slot++) for (const rich of [false, true]) {
    const s = day(age, slot);
    if (rich) s.persons.qing.flags.push("fam_rich");
    for (const sp of C.map.spots) {
      const pk = G("worldPickAction")(s, C, "qing", sp).act;
      if (pk) { assert.ok(!pk.menu, `${age} 岁时段 ${slot} 在 ${sp.id} 不点菜单落到了 ${pk.id}`); n++; }
    }
  }
  assert.ok(n > 500);
  const s = day(70, 2);
  at(s, "qing", "lake_walk");
  assert.equal(doIt(s, "qing", "lake_walk").error, "现在不是时候", "下午不点菜单：还是早上遛弯不是时候，不会去划船花钱");
  const m0 = s.persons.qing.money;
  assert.equal(doIt(s, "qing", "lake_walk", "boat").error, null, "点了划船才划船");
  assert.ok(s.persons.qing.money < m0);
}

// ---------- 7. 影子跟着对门做菜单上的那件 ----------
{
  let followed = 0;
  for (let seed = 1; seed <= 40 && !followed; seed++) {
    const s = day(17, 2, seed);
    at(s, "qing", "tea_seat");
    assert.equal(doIt(s, "qing", "tea_seat", "tea_runner", false).error, null);
    s.world.actors.mei.action = null;
    G("worldShadowStep")(s, C, "mei");
    if (s.world.actors.mei.action === "tea_runner") followed++;
  }
  assert.ok(followed > 0, "对门点了跑堂，影子跟过去也是跑堂");
}

console.log("✓ 点位菜单：点哪件做哪件、不带还是头一件 / 不在这儿、年纪不到、家底不够、不在钟点上的都回一句话 / 同一件才算搭伴 / 做到点也认 / 后添的事不超过原来最快的 / 不点菜单的轮不到后添的事 / 影子跟对门做菜单上的那件");
