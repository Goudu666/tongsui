// 人生层：抽卡、时间、事件结算、生老病死。纯函数，不依赖 Nakama，可在 Node 里单测。
// 河畔里的实时部分（走动、吃饭睡觉、触发事件）在 world.ts。

var ROLES: Role[] = ["qing", "mei"];
var REROLLS = 3;
var MEMORY_FADE_EVERY = 8;
var SEASON_ORDER: Season[] = ["spring", "summer", "autumn", "winter"];
var SEASON_LABEL = ["立春", "立夏", "立秋", "立冬"];
/** 事件给的属性整体打折：日常行动是成长的大头，经历只是点缀。分量用标记、回忆和文字表达 */
var EVENT_STAT_SCALE = 0.15;
/** 考试的发挥：手气 ±SWING_RANGE/2，运气每高于 5 一点再加 SWING_LUCK */
var SWING_RANGE = 0.5;
var SWING_LUCK = 0.04;
var STAT_KEYS: StatKey[] = ["body", "mind", "charm", "luck"];
var STAT_LABEL: { [k: string]: string } = { body: "体魄", mind: "心智", charm: "魅力", luck: "运气", money: "积蓄" };

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

/** 抽一次。exceptFamily：两户人家是邻居，不能是同一家 */
function lifeRollOnce(s: { rng: number }, c: Content, exceptFamily: string | null): { familyId: string; talentId: string; stats: Stats } {
  var fams = c.families.filter(function (f) { return f.id !== exceptFamily; });
  var fam = lifePickWeighted(s, fams, function (f) { return f.weight; })!;
  var tal = lifePickWeighted(s, c.talents, function (t) { return t.weight; })!;
  // 16 点随机分给四项，每项 1~7
  var keys: StatKey[] = ["body", "mind", "charm", "luck"];
  var stats: Stats = { body: 1, mind: 1, charm: 1, luck: 1 };
  var pool = 12;
  while (pool > 0) {
    var k = keys[Math.floor(lifeRand(s) * 4)];
    if (stats[k] < 7) { stats[k] += 1; pool -= 1; }
  }
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i];
    stats[key] = lifeClamp(stats[key] + (fam.bonus[key] || 0) + (tal.bonus[key] || 0), 0, 10);
  }
  return { familyId: fam.id, talentId: tal.id, stats: stats };
}

function lifeCreate(seed: number, c: Content): LifeState {
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
  };
  var q = lifeRollOnce(s, c, null);
  var m = lifeRollOnce(s, c, q.familyId);
  s.rolls = {
    qing: { familyId: q.familyId, talentId: q.talentId, stats: q.stats, rerollsLeft: REROLLS, confirmed: false },
    mei: { familyId: m.familyId, talentId: m.talentId, stats: m.stats, rerollsLeft: REROLLS, confirmed: false },
  };
  return s;
}

/** 重抽。返回错误信息或 null */
function lifeReroll(s: LifeState, c: Content, role: Role): string | null {
  if (s.phase !== "roll") return "已经开始了";
  var r = s.rolls[role];
  if (r.confirmed) return "已经确认了";
  if (r.rerollsLeft <= 0) return "没有重抽次数了";
  var next = lifeRollOnce(s, c, s.rolls[lifeOther(role)].familyId);
  r.familyId = next.familyId;
  r.talentId = next.talentId;
  r.stats = next.stats;
  r.rerollsLeft -= 1;
  return null;
}

/** 确认抽卡。两人都确认后人生开始，返回 true */
function lifeConfirm(s: LifeState, c: Content, role: Role, names: { [R in Role]: string }): boolean {
  if (s.phase !== "roll") return false;
  s.rolls[role].confirmed = true;
  if (!s.rolls.qing.confirmed || !s.rolls.mei.confirmed) return false;
  s.persons = { qing: lifeNewPerson(s, c, s.rolls.qing, names.qing), mei: lifeNewPerson(s, c, s.rolls.mei, names.mei) };
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
    lifespan: 66 + Math.floor(lifeRand(s) * 24),
    diedAtAge: null,
    familyId: fam.id,
    talentId: tal.id,
    stats: { body: r.stats.body, mind: r.stats.mind, charm: r.stats.charm, luck: r.stats.luck },
    needs: { hunger: 80, energy: 90, mood: 70, clean: 80 },
    money: fam.money,
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

/** 按权重算分：属性乘权重相加，money 是积蓄 */
function lifeScore(p: Person, w: ScoreWeights): number {
  var total = 0;
  for (var k in w) {
    var weight = (w as any)[k] as number;
    total += weight * (k === "money" ? p.money : p.stats[k as StatKey]);
  }
  return Math.round(total * 100) / 100;
}

function lifeOptionWeights(ev: LifeEvent, o: EventOption): ScoreWeights {
  return o.score || ev.score || {};
}

/** 「心智」「心智和魅力」：这条线看的是什么 */
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
function lifeOptionLock(ev: LifeEvent, o: EventOption, p: Person, swing: number): string | null {
  var rq = o.requires || {};
  if (!lifeHasAll(p.flags, rq.flags) || !lifeHasNone(p.flags, rq.notFlags)) return "这条路不是给你留的";
  if (o.min) {
    var w = lifeOptionWeights(ev, o);
    var have = lifeScore(p, w) + (w.money ? 0 : swing);
    if (have < o.min) return lifeWeightsLabel(w) + " " + (w.money ? Math.floor(have) : lifeRound1(have)) + "，要 " + o.min;
  }
  if (o.cost && p.money < o.cost) return "积蓄 " + Math.floor(p.money) + "，要 " + o.cost;
  return null;
}

/** 正在进行的关口里，每个人哪些路是锁着的：{ role: { optionId: 原因 } }。不在关口里返回 null */
function lifeMilestoneLocks(s: LifeState, c: Content): { [R in Role]?: { [optionId: string]: string } } | null {
  var pe = s.world && s.world.event;
  if (!pe || pe.kind !== "milestone") return null;
  var ev = lifeFindEvent(c, pe.eventId);
  var out: { [R in Role]?: { [optionId: string]: string } } = {};
  for (var i = 0; i < pe.roles.length; i++) {
    var r = pe.roles[i];
    var locks: { [optionId: string]: string } = {};
    for (var j = 0; j < ev.options.length; j++) {
      var why = lifeOptionLock(ev, ev.options[j], s.persons![r], (pe.swing && pe.swing[r]) || 0);
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

interface GoalLine { id: string; text: string; by: string; have: number; need: number; ok: boolean }
interface GoalView { id: string; title: string; age: number; turns: number; lines: GoalLine[] }

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
    if (!ev.options.some(function (o) { return !!o.min; })) continue; // 上小学、退休：没有线，不算目标
    if (!best || ev.age! < best.age!) best = ev;
  }
  if (!best) return null;
  var lines: GoalLine[] = [];
  for (var j = 0; j < best.options.length; j++) {
    var o = best.options[j];
    if (!o.min) continue;
    var w = lifeOptionWeights(best, o);
    var have = lifeScore(p, w);
    lines.push({ id: o.id, text: o.text, by: lifeWeightsLabel(w), have: w.money ? Math.floor(have) : lifeRound1(have), need: o.min, ok: have >= o.min });
  }
  return { id: best.id, title: best.title, age: best.age!, turns: lifeTurnsUntilAge(s.turn, best.age!), lines: lines };
}

// ---------- 效果 ----------

function lifeHasFlag(p: Person, f: string): boolean {
  return p.flags.indexOf(f) >= 0;
}

function lifeApplySelf(p: Person, d: SelfDelta) {
  for (var k in d) {
    var v = (d as any)[k] as number;
    if (k === "body" || k === "mind" || k === "charm" || k === "luck") {
      // 越往上越难长：4 以下照常，7 只长一半，9 以上只长一点点（不然一辈子下来人人都是满属性）
      if (v > 0) v = v * lifeClamp((10 - p.stats[k]) / 6, 0.15, 1);
      p.stats[k] = lifeClamp(Math.round((p.stats[k] + v) * 100) / 100, 0, 10);
    } else if (k === "hunger" || k === "energy" || k === "mood" || k === "clean") {
      if (k === "mood" && v < 0 && lifeHasFlag(p, "tal_sunny")) v = v / 2;
      p.needs[k] = lifeClamp(p.needs[k] + v, 0, 100);
    }
  }
}

function lifeApplyBond(s: LifeState, d: Partial<Bond>) {
  if (d.sync) s.bond.sync = lifeClamp(s.bond.sync + d.sync, 0, 100);
  if (d.close) s.bond.close = lifeClamp(s.bond.close + d.close, -20, 100);
  if (d.distance) s.bond.distance = lifeClamp(s.bond.distance + d.distance, 0, 5);
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

/** 事件给的属性打折（需求不打折） */
function lifeScaleStats(d: SelfDelta): SelfDelta {
  var out: SelfDelta = {};
  for (var k in d) {
    var v = (d as any)[k] as number;
    (out as any)[k] = STAT_KEYS.indexOf(k as StatKey) >= 0 ? v * EVENT_STAT_SCALE : v;
  }
  return out;
}

/** 给人打标记（不重复） */
function lifeAddFlags(p: Person, flags: string[] | undefined) {
  if (!flags) return;
  for (var i = 0; i < flags.length; i++) if (!lifeHasFlag(p, flags[i])) p.flags.push(flags[i]);
}

function lifeFindEvent(c: Content, id: string): LifeEvent {
  return lifeFind(c.events, id);
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
  var best: EventOption[] = [];
  var bestScore = -1;
  for (var i = 0; i < ev.options.length; i++) {
    var o = ev.options[i];
    // 关口：走不了的路影子也不能替他选。够得着的路里，影子偏向线最高的那条（人往高处走），再看性格
    if (ev.kind === "milestone" && lifeOptionLock(ev, o, s.persons![role], swing)) continue;
    var score = ev.kind === "milestone" ? (o.min || 0) * 0.01 : 0;
    for (var j = 0; j < o.tags.length; j++) score += tags[o.tags[j]] || 0;
    if (score > bestScore) { bestScore = score; best = [o]; }
    else if (score === bestScore) best.push(o);
  }
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
  entry.shadow = pe.shadow.slice();
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
      var gscore = lifeScore(me, gw) + (gw.money ? 0 : swing);
      var grade: Grade | null = null;
      for (var g = 0; g < (ev.grades || []).length; g++) if (gscore >= ev.grades![g].min) { grade = ev.grades![g]; break; }
      if (grade) lifeAddFlags(me, grade.flags);
      if (o.cost) me.money = Math.max(0, me.money - o.cost);
      lifeApplySelf(me, o.effects.self);
      if (other.alive) lifeApplySelf(other, o.effects.other);
      lifeApplyBond(s, o.effects.bond);
      lifeAddFlags(me, o.effects.flags);
      if (!entry.results) entry.results = {};
      entry.results[role] = {
        score: lifeRound1(lifeScore(me, o.min ? w : gw) + ((o.min ? w : gw).money ? 0 : swing)),
        grade: grade ? grade.label : null,
        option: o.id,
        track: lifeTrack(c, me, entry.age).id,
      };
    } else {
      lifeApplySelf(me, lifeScaleStats(o.effects.self));
      if (other.alive) lifeApplySelf(other, lifeScaleStats(o.effects.other));
      lifeApplyBond(s, o.effects.bond);
      lifeAddFlags(me, o.effects.flags);
    }
    if (pe.shadow.indexOf(role) < 0) {
      for (var j = 0; j < o.tags.length; j++) me.tags[o.tags[j]] = (me.tags[o.tags[j]] || 0) + 1;
    }
  }
  if (pe.kind === "mirror" || (pe.kind === "milestone" && pe.roles.length === 2)) {
    if (pe.choices.qing === pe.choices.mei) {
      entry.resonance = true;
      var res = ev.resonance && ev.resonance[pe.choices.qing!];
      if (res) {
        lifeApplyBond(s, res.bond);
        lifeAddFlags(s.persons!.qing, res.flags);
        lifeAddFlags(s.persons!.mei, res.flags);
        entry.text = res.text;
        if (res.memory) s.memories.push({ title: res.memory, eventId: ev.id, turn: s.turn, age: entry.age, vivid: 3 });
      } else if (pe.kind === "mirror") {
        lifeApplyBond(s, { sync: 1 });
        entry.text = "你们选了同一个答案。";
      }
    } else {
      entry.resonance = false;
      if (ev.dissonance) {
        lifeApplyBond(s, ev.dissonance.bond);
        lifeAddFlags(s.persons!.qing, ev.dissonance.flags);
        lifeAddFlags(s.persons!.mei, ev.dissonance.flags);
        entry.text = ev.dissonance.text;
      }
    }
  }
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
  for (var i = 0; i < ROLES.length; i++) {
    var p = persons[ROLES[i]];
    if (!p.alive) continue;
    var a = w.actors[ROLES[i]];
    var slept = a !== null && a.asleep;
    parts.push(p.name + (slept ? "睡得很香" : "困得趴在了桌上"));
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
    p.needs.energy = slept ? 90 : 65;
    p.needs.clean = 75;
    p.needs.mood = Math.round(p.needs.mood * 0.6 + 60 * 0.4);
  }
  summary.text = "这一天过去了。" + parts.join("，") + "。";
  out.push(summary);
  s.log.push(summary);

  s.turn += 1;
  for (var m = 0; m < s.memories.length; m++) {
    var mem = s.memories[m];
    if (mem.vivid > 0 && (s.turn - mem.turn) % MEMORY_FADE_EVERY === 0) mem.vivid -= 1;
  }

  // 生老病死：体魄每高 1 点多活半年，长期心情差会折寿
  var nt = lifeTimeAt(s.turn);
  for (var d = 0; d < ROLES.length; d++) {
    var pp = persons[ROLES[d]];
    if (!pp.alive) continue;
    var limit = pp.lifespan + (pp.stats.body - 5) * 0.5 + (pp.needs.mood < 30 ? -3 : 0);
    if (nt.age >= limit || nt.age >= 100) {
      pp.alive = false;
      pp.diedAtAge = nt.age;
      var de = lifeEntry(s, "death", pp.name + " 在 " + nt.age + " 岁那年离开了。");
      out.push(de);
      s.log.push(de);
    }
  }

  if (!persons.qing.alive && !persons.mei.alive) {
    s.phase = "ended";
    s.world = null;
    s.ending = lifeEnding(s, c);
    var end = lifeEntry(s, "end", lifeEndingText(s, c, s.ending) + lifeEpitaph(s));
    out.push(end);
    s.log.push(end);
  } else {
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
