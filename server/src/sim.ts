// 人生层：抽卡、时间、事件结算、生老病死。纯函数，不依赖 Nakama，可在 Node 里单测。
// 河畔里的实时部分（走动、吃饭睡觉、触发事件）在 world.ts。

var ROLES: Role[] = ["qing", "mei"];
var REROLLS = 3;
var MEMORY_FADE_EVERY = 8;
var SEASON_ORDER: Season[] = ["spring", "summer", "autumn", "winter"];
var SEASON_LABEL = ["立春", "立夏", "立秋", "立冬"];

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
    version: 2,
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

// ---------- 效果 ----------

function lifeHasFlag(p: Person, f: string): boolean {
  return p.flags.indexOf(f) >= 0;
}

function lifeApplySelf(p: Person, d: SelfDelta) {
  for (var k in d) {
    var v = (d as any)[k] as number;
    if (k === "body" || k === "mind" || k === "charm" || k === "luck") {
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

function lifeSeenIds(s: LifeState): { [id: string]: boolean } {
  var seen: { [id: string]: boolean } = {};
  for (var i = 0; i < s.log.length; i++) {
    var e = s.log[i].events;
    if (e.qing) seen[e.qing] = true;
    if (e.mei) seen[e.mei] = true;
  }
  return seen;
}

function lifeEligible(ev: LifeEvent, t: TimeInfo, flags: string[], seen: { [id: string]: boolean }): boolean {
  if (ev.stage !== t.stage) return false;
  if (seen[ev.id]) return false;
  if (ev.seasons.length > 0 && (t.season === null || ev.seasons.indexOf(t.season) < 0)) return false;
  var rq = ev.requires || {};
  if (rq.minAge !== undefined && t.age < rq.minAge) return false;
  if (rq.maxAge !== undefined && t.age > rq.maxAge) return false;
  return lifeHasAll(flags, rq.flags) && lifeHasNone(flags, rq.notFlags);
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
  var best: EventOption[] = [];
  var bestScore = -1;
  for (var i = 0; i < ev.options.length; i++) {
    var o = ev.options[i];
    var score = 0;
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
    lifeApplySelf(me, o.effects.self);
    var other = s.persons![lifeOther(role)];
    if (other.alive) lifeApplySelf(other, o.effects.other);
    lifeApplyBond(s, o.effects.bond);
    for (var f = 0; f < o.effects.flags.length; f++) if (!lifeHasFlag(me, o.effects.flags[f])) me.flags.push(o.effects.flags[f]);
    if (pe.shadow.indexOf(role) < 0) {
      for (var j = 0; j < o.tags.length; j++) me.tags[o.tags[j]] = (me.tags[o.tags[j]] || 0) + 1;
    }
  }
  if (pe.kind === "mirror") {
    if (pe.choices.qing === pe.choices.mei) {
      entry.resonance = true;
      var res = ev.resonance && ev.resonance[pe.choices.qing!];
      if (res) {
        lifeApplyBond(s, res.bond);
        entry.text = res.text;
        if (res.memory) s.memories.push({ title: res.memory, eventId: ev.id, turn: s.turn, age: entry.age, vivid: 3 });
      } else {
        lifeApplyBond(s, { sync: 1 });
        entry.text = "你们选了同一个答案。";
      }
    } else {
      entry.resonance = false;
      if (ev.dissonance) {
        lifeApplyBond(s, ev.dissonance.bond);
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
    var end = lifeEntry(s, "end", lifeEpitaph(s));
    out.push(end);
    s.log.push(end);
  } else {
    worldStartDay(s, c);
  }
  return out;
}

/** 人生长卷底部的题词 */
function lifeEpitaph(s: LifeState): string {
  var mirrors = 0, hits = 0, together = 0;
  for (var i = 0; i < s.log.length; i++) {
    var e = s.log[i];
    if (e.kind === "mirror") { mirrors++; if (e.resonance) hits++; }
    if (e.kind === "together") together++;
  }
  var rate = mirrors > 0 ? Math.round((hits / mirrors) * 100) : 0;
  return "你们一起过了 " + s.turn + " 个被记住的日子，同框 " + together + " 次，留下 " + s.memories.length + " 段共同回忆，默契率 " + rate + "%。";
}
