// 人生层：抽卡、时间、事件结算、生老病死。纯函数，不依赖 Nakama，可在 Node 里单测。
// 河畔里的实时部分（走动、吃饭睡觉、触发事件）在 world.ts。

var ROLES: Role[] = ["qing", "mei"];
var MEMORY_FADE_EVERY = 8;
var SEASON_ORDER: Season[] = ["spring", "summer", "autumn", "winter"];
var SEASON_LABEL = ["立春", "立夏", "立秋", "立冬"];
/** 考试的发挥：手气 ±SWING_RANGE/2，运气每高于 5 一点再加 SWING_LUCK */
var SWING_RANGE = 0.5;
var SWING_LUCK = 0.04;
var STAT_KEYS: StatKey[] = ["body", "mind", "charm", "luck"];
var STAT_LABEL: { [k: string]: string } = { body: "体魄", mind: "心智", charm: "魅力", luck: "运气", money: "积蓄", close: "亲近" };

/** 时间的密度：每个回合是人生里被「放大」的一天，回合之间的日子一笔带过。越长大，跳得越远。 */
var STAGE_TABLE: { stage: Stage; fromAge: number; turnsPerYear: number; years: number }[] = [
  { stage: "childhood", fromAge: 3, turnsPerYear: 4, years: 9 },
  { stage: "teen", fromAge: 12, turnsPerYear: 2, years: 6 },
  { stage: "young", fromAge: 18, turnsPerYear: 1, years: 12 },
  { stage: "middle", fromAge: 30, turnsPerYear: 1 / 3, years: 30 },
  { stage: "old", fromAge: 60, turnsPerYear: 1 / 5, years: 1000 },
];

// ---------- 随机数（mulberry32，状态存进存档，保证可复现） ----------

function lifeRand(s: { rng: number }): number {
  s.rng = (s.rng + 0x6d2b79f5) | 0;
  var t = s.rng;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

function lifePickWeighted<T>(s: { rng: number }, items: T[], weight: (x: T) => number): T | null {
  var total = 0;
  for (var i = 0; i < items.length; i++) total += weight(items[i]);
  if (total <= 0) return null;
  var r = lifeRand(s) * total;
  for (var j = 0; j < items.length; j++) {
    r -= weight(items[j]);
    if (r < 0) return items[j];
  }
  return items[items.length - 1];
}

function lifeClamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

function lifeOther(r: Role): Role {
  return r === "qing" ? "mei" : "qing";
}

// ---------- 时间 ----------

function lifeTimeAt(turn: number): TimeInfo {
  var start = 0;
  for (var i = 0; i < STAGE_TABLE.length; i++) {
    var st = STAGE_TABLE[i];
    var turns = Math.round(st.years * st.turnsPerYear);
    if (turn < start + turns || i === STAGE_TABLE.length - 1) {
      var k = turn - start;
      var age = Math.floor(st.fromAge + k / st.turnsPerYear);
      if (st.stage === "childhood") {
        var si = k % 4;
        return { age: age, stage: st.stage, season: SEASON_ORDER[si], label: age + " 岁 · " + SEASON_LABEL[si] };
      }
      if (st.stage === "teen") {
        return { age: age, stage: st.stage, season: null, label: age + " 岁 · " + (k % 2 === 0 ? "上学期" : "下学期") };
      }
      if (st.stage === "young") return { age: age, stage: st.stage, season: null, label: age + " 岁" };
      return { age: age, stage: st.stage, season: null, label: age + " 岁那几年" };
    }
    start += turns;
  }
  throw new Error("unreachable");
}

// ---------- 开局：抽家庭、天赋、属性 ----------

function lifeFind<T extends { id: string }>(list: T[], id: string): T {
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
  throw new Error("not found: " + id);
}

/**
 * 抽一次。exceptFamily：两户人家是邻居，不能是同一家。
 * 四项属性的合计人人一样（rules.roll.budget，清贫人家多 1 点、殷实人家少 1 点）：
 * 人家和天赋的加成先占掉一部分点数，剩下的随机分。所以没有「强」的出身，只有长得不一样的出身。
 */
function lifeRollOnce(s: { rng: number }, c: Content, exceptFamily: string | null, legacy?: Legacy): { familyId: string; talentId: string; stats: Stats } {
  var rr = c.rules.roll;
  var fams = c.families.filter(function (f) { return f.id !== exceptFamily; });
  var fam = lifePickWeighted(s, fams, function (f) { return f.weight; })!;
  var tal = lifePickWeighted(s, legacyTalents(c, legacy), function (t) { return t.weight; })!; // 藏着的天赋要先出过那件事
  var keys: StatKey[] = ["body", "mind", "charm", "luck"];
  // 每项随机分到的底子在 [lo, hi] 里。加成大的那一项上限要让出来、加成是负的下限要垫上去，
  // 这样加完以后还在 0~10 里，不用再夹（夹掉的点数就丢了，合计就不等了）
  var bonus: Stats = { body: 0, mind: 0, charm: 0, luck: 0 };
  var hi: Stats = { body: 0, mind: 0, charm: 0, luck: 0 };
  var stats: Stats = { body: 0, mind: 0, charm: 0, luck: 0 };
  var pool = rr.budget + rr.wealthAdjust[fam.wealth];
  var room = 0;
  for (var b = 0; b < keys.length; b++) {
    var kb = keys[b];
    bonus[kb] = (fam.bonus[kb] || 0) + (tal.bonus[kb] || 0);
    stats[kb] = Math.max(rr.statMin, -bonus[kb]);
    hi[kb] = Math.max(stats[kb], Math.min(rr.statMax, 10 - bonus[kb]));
    pool -= stats[kb] + bonus[kb];
    room += hi[kb] - stats[kb];
  }
  // 内容校验（build-content.mjs）保证每种人家 × 天赋都分得下去；这里再夹一次只是不让坏数据卡死循环
  pool = lifeClamp(pool, 0, room);
  while (pool > 0) {
    var k = keys[Math.floor(lifeRand(s) * 4)];
    if (stats[k] < hi[k]) { stats[k] += 1; pool -= 1; }
  }
  for (var i = 0; i < keys.length; i++) stats[keys[i]] = lifeClamp(stats[keys[i]] + bonus[keys[i]], 0, 10);
  return { familyId: fam.id, talentId: tal.id, stats: stats };
}

/** legacy：这条人生线之前几世留下的东西（legacy.ts）。头一世不传 */
/** cohort：出生年代（content/eras.yaml 的 id）。不写 = 默认年代（九十年代初生，数值按它校的）；真开局由 main.ts / 再来一世用 eraPickCohort 抽 */
function lifeCreate(seed: number, c: Content, legacy?: Legacy, cohort?: string): LifeState {
  var s: LifeState = {
    version: LIFE_VERSION,
    contentVersion: c.version,
    seed: seed,
    rng: seed | 0,
    phase: "roll",
    turn: 0,
    rolls: null as any,
    persons: null,
    bond: { sync: 0, close: 10, distance: 0 },
    memories: [],
    log: [],
    world: null,
    legacy: legacy || legacyNew(),
  };
  var q = lifeRollOnce(s, c, null, s.legacy);
  var m = lifeRollOnce(s, c, q.familyId, s.legacy);
  s.rolls = {
    qing: { familyId: q.familyId, talentId: q.talentId, stats: q.stats, rerollsLeft: c.rules.roll.rerolls, confirmed: false },
    mei: { familyId: m.familyId, talentId: m.talentId, stats: m.stats, rerollsLeft: c.rules.roll.rerolls, confirmed: false },
  };
  legacyRoll(s, c); // 第几世、家业、摆在面前的老物件
  var dc = eraDefaultCohort(c);
  s.cohort = cohort || (dc ? dc.id : undefined); // 两个人同一年生（era.ts）
  s.eras = [];
  return s;
}

/** 重抽。返回错误信息或 null */
function lifeReroll(s: LifeState, c: Content, role: Role): string | null {
  if (s.phase !== "roll") return "已经开始了";
  var r = s.rolls[role];
  if (r.confirmed) return "已经确认了";
  if (r.rerollsLeft <= 0) return "没有重抽次数了";
  var next = lifeRollOnce(s, c, s.rolls[lifeOther(role)].familyId, s.legacy);
  r.familyId = next.familyId;
  r.talentId = next.talentId;
  r.stats = next.stats;
  r.house = legacyHouse(c, s.legacy, next.familyId);
  r.rerollsLeft -= 1;
  return null;
}

/** 确认抽卡。两人都确认后人生开始，返回 true */
function lifeConfirm(s: LifeState, c: Content, role: Role, names: { [R in Role]: string }): boolean {
  if (s.phase !== "roll") return false;
  s.rolls[role].confirmed = true;
  if (!s.rolls.qing.confirmed || !s.rolls.mei.confirmed) return false;
  s.persons = { qing: lifeNewPerson(s, c, s.rolls.qing, names.qing), mei: lifeNewPerson(s, c, s.rolls.mei, names.mei) };
  legacyBirth(s, c); // 家业、带着的老物件、上一世留在河畔里的痕迹
  eraStart(s, c); // 生之前的年代大事悄悄生效（era.ts）
  s.phase = "life";
  worldStartDay(s, c);
  return true;
}

function lifeNewPerson(s: LifeState, c: Content, r: Roll, name: string): Person {
  var fam = lifeFind(c.families, r.familyId);
  var tal = lifeFind(c.talents, r.talentId);
  return {
    name: name,
    alive: true,
    lifespan: growthBornLifespan(s, c),
    diedAtAge: null,
    familyId: fam.id,
    talentId: tal.id,
    stats: { body: r.stats.body, mind: r.stats.mind, charm: r.stats.charm, luck: r.stats.luck },
    born: { body: r.stats.body, mind: r.stats.mind, charm: r.stats.charm, luck: r.stats.luck },
    needs: { hunger: 80, energy: 90, mood: 70, clean: 80 },
    money: fam.money,
    moodSum: 0,
    moodDays: 0,
    active: { body: false, mind: false },
    flags: fam.traits.concat(tal.flags),
    tags: {},
  };
}

// ---------- 人生路线与关口 ----------

/** 这个人现在走在哪条路上：按年龄和标记从上往下取第一条符合的（最后一条兜底） */
function lifeTrack(c: Content, p: Person, age: number): Track {
  for (var i = 0; i < c.tracks.length; i++) {
    var t = c.tracks[i];
    var rq = t.requires || {};
    if (lifeInRange(age, rq.minAge, rq.maxAge) && lifeHasAll(p.flags, rq.flags) && lifeHasNone(p.flags, rq.notFlags)) return t;
  }
  return c.tracks[c.tracks.length - 1];
}

function lifeRound1(v: number): number {
  return Math.round(v * 10) / 10;
}

/** 按权重算分：属性乘权重相加，money 是积蓄，close 是两个人的亲近（要传 bond，不传按 0 算） */
function lifeScore(p: Person, w: ScoreWeights, bond?: Bond): number {
  var total = 0;
  for (var k in w) {
    var weight = (w as any)[k] as number;
    total += weight * (k === "money" ? p.money : k === "close" ? (bond ? bond.close : 0) : p.stats[k as StatKey]);
  }
  return Math.round(total * 100) / 100;
}

/** 算关口的线用的亲近。对门不在了返回 undefined：要两个人才走得成的路，一个人走不了 */
function lifePairBond(s: LifeState, role: Role): Bond | undefined {
  var o = s.persons ? s.persons[lifeOther(role)] : null;
  return o && o.alive ? s.bond : undefined;
}

/** 这条线按原数给人看：积蓄是块，亲近本来就是 0~100。不乘 10，也不算考场上的发挥 */
function lifeScoreRaw(w: ScoreWeights): boolean {
  return !!(w.money || w.close);
}

function lifeOptionWeights(ev: LifeEvent, o: EventOption): ScoreWeights {
  return o.score || ev.score || {};
}

/** 「心智」「心智和魅力」：这条线看的是什么 */
/**
 * 给人看的分数：属性 × 10，往下取整（57.9 分不能显示成 58 分然后告诉他没过 58 的线）。
 * 属性本身还是 0~10，只有显示在关口和目标上的时候才换成百分制，读起来像考分。
 */
function lifePoints(v: number): number {
  return Math.floor(v * 10 + 1e-6);
}

/** 百分制带一位小数（往下取整）：整数部分和 lifePoints 一样 */
function lifeFinePoints(v: number): number {
  return Math.floor(v * 100 + 1e-5) / 10; // ε 是 lifePoints 的十倍：floor(这个数) 恒等于 lifePoints(v)
}

function lifeWeightsLabel(w: ScoreWeights): string {
  var parts: string[] = [];
  for (var k in w) parts.push(STAT_LABEL[k] || k);
  return parts.join("和");
}

/** 这个年纪的关口（没有就是 null） */
function lifeMilestoneAt(c: Content, age: number): LifeEvent | null {
  for (var i = 0; i < c.events.length; i++) if (c.events[i].kind === "milestone" && c.events[i].age === age) return c.events[i];
  return null;
}

/** 这个人过不过这个关口（辍学的人不参加中考） */
function lifeMilestoneFor(ev: LifeEvent, p: Person): boolean {
  var rq = ev.requires || {};
  return p.alive && lifeHasAll(p.flags, rq.flags) && lifeHasNone(p.flags, rq.notFlags);
}

/** 这条路走不走得了。走不了返回原因（给玩家看的），走得了返回 null。swing 是这次的发挥 */
function lifeOptionLock(ev: LifeEvent, o: EventOption, p: Person, swing: number, bond?: Bond): string | null {
  var rq = o.requires || {};
  if (!lifeHasAll(p.flags, rq.flags) || !lifeHasNone(p.flags, rq.notFlags)) return o.lock || "这条路不是给你留的"; // 家里拿不出这笔钱（docs/MEANS.md）
  var line = lifeOptionMin(o, p); // 年代挪过的线（era.ts）
  if (line) {
    var w = lifeOptionWeights(ev, o);
    if (w.close && !bond) return "对门已经空了";
    var have = lifeScore(p, w, bond) + (lifeScoreRaw(w) ? 0 : swing);
    if (have < line) {
      return w.money
        ? "积蓄 " + Math.floor(have) + " 块，要 " + line + " 块"
        : w.close
          ? "亲近 " + Math.floor(have) + " 分，线是 " + line + " 分"
          : lifeWeightsLabel(w) + " " + lifePoints(have) + " 分，线是 " + lifePoints(line) + " 分";
    }
  }
  var cost = lifeOptionCost(ev, o, p);
  if (cost && p.money < cost) return "积蓄 " + Math.floor(p.money) + " 块，要 " + cost + " 块";
  return null;
}

/**
 * 关口揭晓给人看的几样（client/scripts/ui/reveal.gd 拿它演：分数往上数、过线盖章、差几分停在线前）。
 * 只是把已经算出来的东西换成 score 的口径交出去，不影响结算。
 *   line   选的这条路的线
 *   luck   这一场的发挥（含默契托住的 steady）；看原数的线（积蓄、亲近）不算发挥，没有这两项
 *   差几分没够上的那条不在这儿：用 atlasMilestoneNear 给的 results.near（和锁上那句、结局页的「差一点」同一个数）
 */
function lifeReveal(ev: LifeEvent, o: EventOption, swing: number, steady: number, p?: Person) {
  var out: { line?: number; luck?: number; steady?: number } = {};
  var ow = lifeOptionWeights(ev, o);
  var line = p ? lifeOptionMin(o, p) : o.min || 0;
  if (line) out.line = lifeScoreRaw(ow) ? line : lifePoints(line);
  if (!lifeScoreRaw(o.min ? ow : ev.score || {})) {
    var sl = Math.round(swing * 10) || 0;
    if (sl !== 0) out.luck = sl;
    var st = Math.round(steady * 10);
    if (st > 0) out.steady = st;
  }
  return out;
}

function lifeRevealExtras(r: { line?: number; luck?: number; steady?: number }, x: ReturnType<typeof lifeReveal>) {
  if (x.line !== undefined) r.line = x.line;
  if (x.luck !== undefined) r.luck = x.luck;
  if (x.steady !== undefined) r.steady = x.steady;
}

/** 关口上这条路算哪条路：花钱进的重点、托关系进的单位，和考进去的是同一条（joins），两个人还是同路 */
function lifeRoad(ev: LifeEvent, optionId: string): string {
  var o = lifeFindOption(ev, optionId);
  return (o && o.joins) || optionId;
}

/** 关口一条路都走不通时走的那条：线最低的（一样低取写在后面的，内容里兜底的路习惯写在最后） */
function lifeMilestoneFallback(ev: LifeEvent): EventOption {
  // 只看谁都走得了的路：挂了标记的（接班、家里出钱的）不是兜底
  var open = ev.options.filter(function (o) { var rq = o.requires || {}; return !(rq.flags && rq.flags.length) && !(rq.notFlags && rq.notFlags.length); });
  if (!open.length) open = ev.options;
  var best = open[0];
  for (var i = 1; i < open.length; i++) {
    if ((open[i].min || 0) <= (best.min || 0)) best = open[i];
  }
  return best;
}

/** 这件事的选项有没有门槛：关口、主线，还有挂了家境标记或要花钱的普通事件（docs/MEANS.md 第三节） */
function lifeGated(ev: LifeEvent): boolean {
  if (ev.kind === "milestone" || storyIs(ev)) return true;
  for (var i = 0; i < ev.options.length; i++) {
    var rq = ev.options[i].requires;
    if (ev.options[i].cost || (rq && ((rq.flags && rq.flags.length) || (rq.notFlags && rq.notFlags.length)))) return true;
  }
  return false;
}

/** 正在进行的关口里，每个人哪些路是锁着的：{ role: { optionId: 原因 } }。不在关口里返回 null */
function lifeMilestoneLocks(s: LifeState, c: Content): { [R in Role]?: { [optionId: string]: string } } | null {
  var pe = s.world && s.world.event;
  if (!pe) return null;
  var ev = lifeFindEvent(c, pe.eventId);
  if (!lifeGated(ev)) return null; // 主线和普通事件的选项也可以有门槛：家底、积蓄
  var out: { [R in Role]?: { [optionId: string]: string } } = {};
  for (var i = 0; i < pe.roles.length; i++) {
    var r = pe.roles[i];
    var locks: { [optionId: string]: string } = {};
    for (var j = 0; j < ev.options.length; j++) {
      var why = lifeOptionLock(ev, ev.options[j], s.persons![r], (pe.swing && pe.swing[r]) || 0, lifePairBond(s, r));
      if (why) locks[ev.options[j].id] = why;
    }
    out[r] = locks;
  }
  return out;
}

/** 从现在到满 age 岁的第一天，还要过几个日子（今天就是那天返回 0） */
function lifeTurnsUntilAge(turn: number, age: number): number {
  for (var k = 0; k < 400; k++) if (lifeTimeAt(turn + k).age >= age) return k;
  return 400;
}

/** have / need：给人看的数。属性类的线按「分」算（属性 × 10，满分 100），钱类的按块 */
// hx：分数线的「攒着的」那一截，百分制带一位小数往下取整（have 是它的整数部分）。小时候一回只长零点几分，界面拿它让尺上的点和分数后面的小数挪一挪
/** era：这条线被哪几件年代大事挪了（「考大学 +7」，era.ts → eraLineWhy）；没挪就不发 */
interface GoalLine { id: string; text: string; by: string; unit: string; have: number; need: number; ok: boolean; hx?: number; era?: string }
interface GoalView { id: string; title: string; age: number; turns: number; lines: GoalLine[] }

/**
 * 目标条上摆哪几档名次（grades 的下标，从高到低）：比这个人走得了的最高那条路还高的。
 * 「差一点」（atlas.ts → atlasMilestoneNear）也只认这几档，两边是同一套线。
 */
function lifeTapeGrades(ev: LifeEvent, p: Person): number[] {
  var gw = ev.score || {};
  if (!ev.grades || lifeScoreRaw(gw) || !lifeWeightsLabel(gw)) return [];
  var top = 0;
  for (var j = 0; j < ev.options.length; j++) {
    var o = ev.options[j];
    if (!o.min) continue;
    var orq = o.requires || {};
    if (!lifeHasAll(p.flags, orq.flags) || !lifeHasNone(p.flags, orq.notFlags)) continue;
    var w = lifeOptionWeights(ev, o);
    if (w.money) continue;
    var line = lifeOptionMin(o, p);
    top = Math.max(top, lifeScoreRaw(w) ? line : lifePoints(line));
  }
  var out: number[] = [];
  for (var gi = ev.grades.length - 1; gi >= 0; gi--) if (lifePoints(ev.grades[gi].min) > top) out.push(gi);
  return out;
}

/**
 * 界面上常驻的那一条：下一个关口是什么、还有几个日子、每条路的线离你还有多远。
 * 这是日常行动的目的。没有带线的关口了（退休以后）返回 null。
 */
function lifeGoal(s: LifeState, c: Content, role: Role): GoalView | null {
  if (s.phase !== "life") return null;
  var p = s.persons![role];
  if (!p.alive) return null;
  var age = lifeTimeAt(s.turn).age;
  var seen = lifeSeenIds(s, role);
  var best: LifeEvent | null = null;
  for (var i = 0; i < c.events.length; i++) {
    var ev = c.events[i];
    if (ev.kind !== "milestone" || ev.age! < age || seen[ev.id] || !lifeMilestoneFor(ev, p)) continue;
    if (!ev.options.some(function (o) { return !!o.min; })) continue; // 没有线的关口不算目标
    if (!best || ev.age! < best.age!) best = ev;
  }
  if (!best) return null;
  // 线按关口那一年的年代标记算（era.ts）：关口那天早上才发生、才过期的大事，纸带上早早就是那天的数
  var at = { flags: eraFlagsAt(s, c, p, eraYear(s, c, best.age!)) } as Person;
  var lines: GoalLine[] = [];
  for (var j = 0; j < best.options.length; j++) {
    var o = best.options[j];
    if (!o.min) continue;
    var orq = o.requires || {};
    if (!lifeHasAll(at.flags, orq.flags) || !lifeHasNone(at.flags, orq.notFlags)) continue; // 不是给这个人留的路不摆在目标条上
    var w = lifeOptionWeights(best, o);
    var have = lifeScore(p, w, lifePairBond(s, role));
    var raw = lifeScoreRaw(w);
    var need = lifeOptionMin(o, at);
    var gl: GoalLine = { id: o.id, text: o.text, by: lifeWeightsLabel(w), unit: w.money ? "块" : "分", have: raw ? Math.floor(have) : lifePoints(have), need: raw ? need : lifePoints(need), ok: have >= need };
    if (!raw) gl.hx = lifeFinePoints(have);
    var why = eraLineWhy(c, o, at.flags, raw);
    if (why) gl.era = why;
    lines.push(gl);
  }
  // 比最高那条路还高的名次（grades）也摆上来：起点高的人不会开局就无事可冲，每道关都还有一条够一够的线
  var gw = best.score || {};
  var gis = lifeTapeGrades(best, at);
  var ghave = lifeScore(p, gw, lifePairBond(s, role));
  for (var gi = 0; gi < gis.length; gi++) {
    var gr = best.grades![gis[gi]];
    lines.push({ id: "grade:" + gis[gi], text: gr.label, by: lifeWeightsLabel(gw), unit: "分", have: lifePoints(ghave), need: lifePoints(gr.min), ok: ghave >= gr.min, hx: lifeFinePoints(ghave) });
  }
  return { id: best.id, title: best.title, age: best.age!, turns: lifeTurnsUntilAge(s.turn, best.age!), lines: lines };
}

// ---------- 效果 ----------

function lifeHasFlag(p: Person, f: string): boolean {
  return p.flags.indexOf(f) >= 0;
}

/** g：长属性时的场合（见 growth.ts → growthCtx）。只改需求的调用可以不传 */
function lifeApplySelf(p: Person, d: SelfDelta, g?: GrowCtx) {
  for (var k in d) {
    var v = (d as any)[k] as number;
    if (k === "body" || k === "mind" || k === "charm" || k === "luck") {
      if (g) growthApply(p, k, v, g);
      else p.stats[k] = lifeClamp(Math.round((p.stats[k] + v) * 1000) / 1000, 0, 10);
    } else if (k === "hunger" || k === "energy" || k === "mood") {
      // clean 11-11 砍了，旧存档里带着的清洁不再变
      if (k === "mood" && v < 0 && lifeHasFlag(p, "tal_sunny")) v = v / 2;
      p.needs[k] = lifeClamp(p.needs[k] + v, 0, 100);
    }
  }
}

/** 亲近和默契越高越难涨（见 growth.ts → growthBond） */
function lifeApplyBond(s: LifeState, c: Content, d: Partial<Bond>) {
  growthBond(s, c, d);
}

// ---------- 事件 ----------

function lifeHasAll(flags: string[], need: string[] | undefined): boolean {
  if (!need) return true;
  for (var i = 0; i < need.length; i++) if (flags.indexOf(need[i]) < 0) return false;
  return true;
}

function lifeHasNone(flags: string[], banned: string[] | undefined): boolean {
  if (!banned) return true;
  for (var i = 0; i < banned.length; i++) if (flags.indexOf(banned[i]) >= 0) return false;
  return true;
}

/** 已经遇到过的事件。传 role 时只算这个人遇到过的（solo 每个人一生各遇一次，比如两个人都要高考） */
function lifeSeenIds(s: LifeState, role?: Role): { [id: string]: boolean } {
  var seen: { [id: string]: boolean } = {};
  for (var i = 0; i < s.log.length; i++) {
    var e = s.log[i].events;
    if (e.qing && role !== "mei") seen[e.qing] = true;
    if (e.mei && role !== "qing") seen[e.mei] = true;
  }
  return seen;
}

/** 数值在 [lo, hi] 里（没写的一边不限） */
function lifeInRange(v: number, lo: number | undefined, hi: number | undefined): boolean {
  return (lo === undefined || v >= lo) && (hi === undefined || v <= hi);
}

function lifeEligible(ev: LifeEvent, t: TimeInfo, flags: string[], seen: { [id: string]: boolean }, ctx?: EligibleCtx): boolean {
  if (ev.stage !== t.stage) return false;
  if (seen[ev.id]) return false;
  if (ev.seasons.length > 0 && (t.season === null || ev.seasons.indexOf(t.season) < 0)) return false;
  var rq = ev.requires || {};
  if (!lifeInRange(t.age, rq.minAge, rq.maxAge)) return false;
  if (ctx) {
    var b = ctx.bond;
    if (!lifeInRange(b.close, rq.minClose, rq.maxClose)) return false;
    if (!lifeInRange(b.sync, rq.minSync, rq.maxSync)) return false;
    if (!lifeInRange(b.distance, rq.minDistance, rq.maxDistance)) return false;
    if (rq.alone !== undefined && rq.alone !== ctx.alone) return false;
  } else if (rq.alone === true) {
    return false;
  }
  return lifeHasAll(flags, rq.flags) && lifeHasNone(flags, rq.notFlags);
}

/** 给人打标记（不重复） */
function lifeAddFlags(p: Person, flags: string[] | undefined) {
  if (!flags) return;
  for (var i = 0; i < flags.length; i++) if (!lifeHasFlag(p, flags[i])) p.flags.push(flags[i]);
}

/** 随机池、关口，再找主线（content/story.yaml） */
function lifeFindEvent(c: Content, id: string): LifeEvent {
  for (var i = 0; i < c.events.length; i++) if (c.events[i].id === id) return c.events[i];
  var st = storyFindEvent(c, id);
  if (st) return st;
  throw new Error("not found: " + id);
}

function lifeHasEvent(c: Content, id: string | null | undefined): boolean {
  if (!id) return false;
  for (var i = 0; i < c.events.length; i++) if (c.events[i].id === id) return true;
  return !!storyFindEvent(c, id);
}

function lifeFindOption(ev: LifeEvent, optionId: string): EventOption | null {
  for (var i = 0; i < ev.options.length; i++) if (ev.options[i].id === optionId) return ev.options[i];
  return null;
}

/** 影子：按玩家过去的性格标签替他选择 */
function lifeShadowChoose(s: LifeState, c: Content, role: Role, eventId: string): string {
  var ev = lifeFindEvent(c, eventId);
  var tags = s.persons![role].tags;
  var pe = s.world && s.world.event;
  var swing = (pe && pe.eventId === eventId && pe.swing && pe.swing[role]) || 0;
  // 对门选了一条要你拉的路、你也走得了：影子跟着走这条（影子自己不去赌要人拉的路）
  var follow = pe && pe.eventId === eventId ? pullShadowFollow(s, c, ev, pe, role) : null;
  if (follow) return follow;
  var best: EventOption[] = [];
  var bestScore = -1;
  for (var i = 0; i < ev.options.length; i++) {
    var o = ev.options[i];
    // 关口：走不了的路影子也不能替他选。够得着的路里，影子偏向线最高的那条（人往高处走），再看性格
    if (lifeGated(ev) && lifeOptionLock(ev, o, s.persons![role], swing, lifePairBond(s, role))) continue;
    var score = ev.kind === "milestone" ? (o.min || 0) * 0.01 : 0;
    for (var j = 0; j < o.tags.length; j++) score += tags[o.tags[j]] || 0;
    if (score > bestScore) { bestScore = score; best = [o]; }
    else if (score === bestScore) best.push(o);
  }
  // 一条都走不通（内容写漏了兜底的路）：走线最低的那条。build-content 会拦，这里是热更新内容时的最后一道
  if (best.length === 0) return lifeMilestoneFallback(ev).id;
  return best[Math.floor(lifeRand(s) * best.length)].id;
}

function lifeEntry(s: LifeState, kind: LogEntry["kind"], text: string): LogEntry {
  var t = lifeTimeAt(s.turn);
  return {
    turn: s.turn, age: t.age, label: t.label, kind: kind, minute: s.world ? s.world.minute : null,
    events: { qing: null, mei: null }, choices: { qing: null, mei: null }, shadow: [], resonance: null, text: text,
  };
}

/** 结算一个事件（mirror 两人、solo 一人），返回日志 */
function lifeResolveEvent(s: LifeState, c: Content, pe: PendingEvent): LogEntry {
  var ev = lifeFindEvent(c, pe.eventId);
  var entry = lifeEntry(s, pe.kind, "");
  var grow = growthCtx(s, c, "event");
  entry.shadow = pe.shadow.slice();
  // 关口：要人拉的路，对门走了就拉过去（钱真塞过去），没走就换成自己够得着的（pull.ts）
  var gate = pullResolve(s, c, ev, pe);
  if (gate) entry.gate = gate;
  for (var i = 0; i < pe.roles.length; i++) {
    var role = pe.roles[i];
    var o = lifeFindOption(ev, pe.choices[role]!)!;
    entry.events[role] = ev.id;
    entry.choices[role] = o.id;
    var me = s.persons![role];
    var other = s.persons![lifeOther(role)];
    if (ev.kind === "milestone") {
      // 关口：先记成绩（事实），再走选的那条路（选择）
      var w = lifeOptionWeights(ev, o);
      var swing = (pe.swing && pe.swing[role]) || 0;
      var gw = ev.score || {};
      var gscore = lifeScore(me, gw, s.bond) + (lifeScoreRaw(gw) ? 0 : swing);
      var grade: Grade | null = null;
      for (var g = 0; g < (ev.grades || []).length; g++) if (gscore >= ev.grades![g].min) { grade = ev.grades![g]; break; }
      // 成绩单上的数要在扣钱、长属性之前算：那是走进考场那一刻的本事
      var sw = o.min ? w : gw;
      // 差一点：离哪条没走成的路最近（结局页上「差一点」读它，见 atlas.ts）。也是走进考场那一刻的数
      var near = atlasMilestoneNear(ev, o.id, me, swing, lifePairBond(s, role), gscore);
      var shown = lifeScoreRaw(sw) ? Math.floor(lifeScore(me, sw, s.bond)) : lifePoints(lifeScore(me, sw, s.bond) + swing);
      // 塞过去的钱：成绩单上记的是进门前自己兜里的数，塞的那一截揭晓时单画（entry.gate.pull）
      if (sw.money && pe.pull) {
        var pl = pe.pull[role], po = pe.pull[lifeOther(role)];
        if (pl && pl.unit === "块") shown = Math.floor(shown - pl.gap);
        if (po && po.unit === "块" && po.by === role) shown = Math.floor(shown + po.gap);
      }
      // 揭晓演出要的几样（线、发挥），也是走进考场那一刻的。差一点的那条就是上面的 near，不另算
      var reveal = lifeReveal(ev, o, swing, (pe.steady && pe.steady[role]) || 0, me);
      if (grade) lifeAddFlags(me, grade.flags);
      var cost = lifeOptionCost(ev, o, me);
      if (cost) me.money = Math.max(0, me.money - cost);
      lifeApplySelf(me, o.effects.self, grow);
      if (other.alive) lifeApplySelf(other, o.effects.other, grow);
      lifeApplyBond(s, c, o.effects.bond);
      lifeAddFlags(me, o.effects.flags);
      if (!entry.results) entry.results = {};
      var scored = false;
      for (var swk in sw) scored = true;
      entry.results[role] = {
        score: shown,
        // 走的是不看分的路、这一关也没有统一的卷子：没有分数可记。score 照旧是数字（旧安装包拿它当数字用），画不画看 scored
        scored: scored,
        unit: sw.money ? "块" : "分",
        grade: grade && grade.label ? grade.label : null, // 兜底那档不写字
        option: o.id,
        track: lifeTrack(c, me, entry.age).id,
      };
      lifeRevealExtras(entry.results[role]!, reveal);
      if (near) entry.results[role]!.near = near;
    } else {
      // 检定：这个选项成不成，看本事也看运气（见 growth.ts → growthResolveCheck）
      var out = growthResolveCheck(s, c, pe, ev, o, role, entry);
      if (o.cost) me.money = Math.max(0, me.money - o.cost); // 主线、普通事件里花的钱（选之前已经按积蓄上过锁）
      lifeApplySelf(me, out.self, grow);
      if (other.alive) lifeApplySelf(other, o.effects.other, grow);
      lifeApplyBond(s, c, o.effects.bond);
      lifeAddFlags(me, out.flags);
    }
    if (pe.shadow.indexOf(role) < 0) {
      for (var j = 0; j < o.tags.length; j++) me.tags[o.tags[j]] = (me.tags[o.tags[j]] || 0) + 1;
    }
  }
  // 默契事件：选得不一样、但一个抛一个接，duet.ts 按「搭上了」结算，就不走下面的共鸣 / 错位了。
  // 关口：两个人都过这一关时，走了同一条路算共鸣，分开走算错位（关口不接「搭上了」和猜 TA）
  if ((pe.kind === "mirror" && !duetCatch(s, c, pe, ev, entry)) || (pe.kind === "milestone" && pe.roles.length === 2)) {
    if (lifeRoad(ev, pe.choices.qing!) === lifeRoad(ev, pe.choices.mei!)) {
      entry.resonance = true;
      if (s.world) s.world.warm = true;
      var res = ev.resonance && ev.resonance[lifeRoad(ev, pe.choices.qing!)];
      if (res) {
        lifeApplyBond(s, c, res.bond);
        lifeAddFlags(s.persons!.qing, res.flags);
        lifeAddFlags(s.persons!.mei, res.flags);
        entry.text = res.text;
        if (res.memory) s.memories.push({ title: res.memory, eventId: ev.id, turn: s.turn, age: entry.age, vivid: 3 });
      } else if (pe.kind === "mirror") {
        lifeApplyBond(s, c, { sync: 1 });
        entry.text = "你们选了同一个答案。";
      }
    } else {
      entry.resonance = false;
      if (ev.dissonance) {
        lifeApplyBond(s, c, ev.dissonance.bond);
        lifeAddFlags(s.persons!.qing, ev.dissonance.flags);
        lifeAddFlags(s.persons!.mei, ev.dissonance.flags);
        entry.text = ev.dissonance.text;
      }
    }
  }
  if (pe.kind === "milestone" && pe.roles.length === 2) pullReunion(s, c, ev, entry); // 上一道关走散了，这一道又走到一块儿
  s.log.push(entry);
  return entry;
}

// ---------- 一天结束 → 跳到人生的下一个「被放大的一天」 ----------

function lifeEndDay(s: LifeState, c: Content): LogEntry[] {
  var out: LogEntry[] = [];
  var persons = s.persons!;
  var w = s.world!;
  var summary = lifeEntry(s, "day", "");
  var parts: string[] = [];
  // 记下今天的心气，亲近变淡，岁数不饶人（要赶在下面「心情回归日常」之前）
  growthDayEnd(s, c);
  var prevAge = lifeTimeAt(s.turn).age;
  for (var i = 0; i < ROLES.length; i++) {
    var p = persons[ROLES[i]];
    if (!p.alive) continue;
    // 晚上过完都去睡了。累狠了的人倒头就睡，第二天也缓不过来
    var tired = p.needs.energy < 15;
    parts.push(p.name + (tired ? "累得倒头就睡" : "睡得很香"));
    if (p.dayStart) {
      var gain: Partial<Stats> = {};
      for (var gk = 0; gk < STAT_KEYS.length; gk++) {
        var dv = Math.round((p.stats[STAT_KEYS[gk]] - p.dayStart[STAT_KEYS[gk]]) * 100) / 100;
        if (dv !== 0) gain[STAT_KEYS[gk]] = dv;
      }
      if (!summary.gains) summary.gains = {};
      summary.gains[ROLES[i]] = gain;
    }
    // 回合之间的日子：需求回到日常水平，心情慢慢回归
    p.needs.hunger = 75;
    p.needs.energy = tired ? 65 : 90;
    p.needs.mood = Math.round(p.needs.mood * 0.6 + 60 * 0.4);
  }
  summary.text = "这一天过去了。" + parts.join("，") + "。";
  out.push(summary);
  s.log.push(summary);

  s.turn += 1;
  // 朝下一道关挪了多少（「再过一天」的钩子：照这样还要几个日子）
  for (var gi = 0; gi < ROLES.length; gi++) {
    if (!persons[ROLES[gi]].alive || !w.goal0) continue;
    var dg = worldDayGoal(s, c, ROLES[gi], w.goal0[ROLES[gi]]);
    if (!dg) continue;
    if (!summary.goal) summary.goal = {};
    summary.goal[ROLES[gi]] = dg;
  }
  for (var m = 0; m < s.memories.length; m++) {
    var mem = s.memories[m];
    if (mem.vivid > 0 && (s.turn - mem.turn) % MEMORY_FADE_EVERY === 0) mem.vivid -= 1;
  }

  // 生老病死：大限看命数、体魄、一辈子的心气，还有对门的那个人（见 growth.ts → growthLimit）
  var gone = growthDeaths(s, c, prevAge);
  for (var d = 0; d < gone.length; d++) {
    var pp = persons[gone[d]];
    var de = lifeEntry(s, "death", pp.name + " 在 " + pp.diedAtAge + " 岁那年离开了。");
    de.age = pp.diedAtAge!;
    out.push(de);
    s.log.push(de);
  }

  // 路上的信：今天早上该到的送到（post.ts），挂在「这一天过去了」那条上
  postDeliver(s, c, summary);
  // 今天的时间花在了哪：只发给客户端的那一份带上，长卷里那一份不带（一辈子七十几天，存档不用背着）
  if (w.segs) {
    var si = out.indexOf(summary);
    if (si >= 0) {
      var copy: any = {};
      for (var ck in summary) copy[ck] = (summary as any)[ck];
      copy.spent = w.segs;
      out[si] = copy as LogEntry;
    }
  }

  if (!persons.qing.alive && !persons.mei.alive) {
    s.phase = "ended";
    s.world = null;
    legacyDerive(s); // 这一世走完才看得出来的事（同一年走的、干了一辈子同一行……），结局读得到
    s.ending = lifeEnding(s, c);
    legacyAbsorb(s, c); // 记进传承：各自留下了什么，街坊记住了什么
    atlasAbsorb(s, c); // 差一点就……；这一世的结局记进图鉴
    var end = lifeEntry(s, "end", lifeEndingText(s, c, s.ending) + lifeEpitaph(s));
    out.push(end);
    s.log.push(end);
  } else {
    eraTick(s, c, out); // 到了年份的年代大事（era.ts），赶在新一天开张之前：今天的行动和关口按新的规矩
    worldStartDay(s, c);
  }
  return out;
}

/** 一生的统计：默契事件数、共鸣数、默契率、同框次数 */
function lifeStats(s: LifeState): { mirrors: number; hits: number; rate: number; together: number } {
  var mirrors = 0, hits = 0, together = 0;
  for (var i = 0; i < s.log.length; i++) {
    var e = s.log[i];
    if (e.kind === "mirror") { mirrors++; if (e.resonance) hits++; }
    if (e.kind === "together") together++;
  }
  return { mirrors: mirrors, hits: hits, rate: mirrors > 0 ? Math.round((hits / mirrors) * 100) : 0, together: together };
}

// ---------- 结局 ----------

function lifePairEndingOk(s: LifeState, e: PairEnding, st: { rate: number; together: number }): boolean {
  var rq = e.requires || {};
  var flags = s.persons!.qing.flags.concat(s.persons!.mei.flags);
  if (!lifeHasAll(flags, rq.flags) || !lifeHasNone(flags, rq.notFlags)) return false;
  if (!lifeInRange(s.bond.close, rq.minClose, rq.maxClose)) return false;
  if (!lifeInRange(s.bond.sync, rq.minSync, rq.maxSync)) return false;
  if (!lifeInRange(s.bond.distance, rq.minDistance, rq.maxDistance)) return false;
  if (!lifeInRange(s.memories.length, rq.minMemories, rq.maxMemories)) return false;
  if (!lifeInRange(st.rate, rq.minRate, rq.maxRate)) return false;
  return rq.minTogether === undefined || st.together >= rq.minTogether;
}

function lifeLifeEndingOk(p: Person, e: LifeEnding): boolean {
  var rq = e.requires || {};
  if (!lifeHasAll(p.flags, rq.flags) || !lifeHasNone(p.flags, rq.notFlags)) return false;
  for (var k in rq.stats || {}) if (p.stats[k as StatKey] < ((rq.stats as any)[k] as number)) return false;
  return lifeInRange(p.diedAtAge === null ? 0 : p.diedAtAge, rq.minDiedAge, rq.maxDiedAge);
}

/** 按顺序取第一个满足条件的结局（内容校验保证最后一条没有条件，必然兜底） */
function lifeEnding(s: LifeState, c: Content): EndingResult {
  var st = lifeStats(s);
  var pair = c.endings.pair[c.endings.pair.length - 1].id;
  for (var i = 0; i < c.endings.pair.length; i++) {
    if (lifePairEndingOk(s, c.endings.pair[i], st)) { pair = c.endings.pair[i].id; break; }
  }
  var lives: { [R in Role]: string } = { qing: "", mei: "" };
  for (var r = 0; r < ROLES.length; r++) {
    var p = s.persons![ROLES[r]];
    lives[ROLES[r]] = c.endings.lives[c.endings.lives.length - 1].id;
    for (var j = 0; j < c.endings.lives.length; j++) {
      if (lifeLifeEndingOk(p, c.endings.lives[j])) { lives[ROLES[r]] = c.endings.lives[j].id; break; }
    }
  }
  return { pair: pair, lives: lives };
}

/** 长卷末尾的结局文字：两人的结局 + 各自的一生 */
function lifeEndingText(s: LifeState, c: Content, e: EndingResult): string {
  var pe = lifeFind(c.endings.pair, e.pair);
  var out = "「" + pe.title + "」" + pe.text + "\n";
  for (var r = 0; r < ROLES.length; r++) {
    var p = s.persons![ROLES[r]];
    var le = lifeFind(c.endings.lives, e.lives[ROLES[r]]);
    out += p.name + " ·「" + le.title + "」" + le.text.split("{name}").join(p.name) + "\n";
  }
  return out;
}

/** 人生长卷底部的题词 */
function lifeEpitaph(s: LifeState): string {
  var st = lifeStats(s);
  var together = st.together, rate = st.rate;
  return "你们一起过了 " + s.turn + " 个被记住的日子，同框 " + together + " 次，留下 " + s.memories.length + " 段共同回忆，默契率 " + rate + "%。";
}
