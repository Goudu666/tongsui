// 人生结算核心：纯函数，不依赖 Nakama，可以在 Node 里单测。
// 客户端 client/scripts/sim/local_life.gd 是它的 GDScript 版本（只用于同屏原型），改规则时两边一起改。

var ROLES: Role[] = ["qing", "mei"];
var STAT_MIN = 0;
var STAT_MAX = 10;
var MEMORY_FADE_EVERY = 8;
var SEASON_ORDER: Season[] = ["spring", "summer", "autumn", "winter"];
var SEASON_LABEL = ["立春", "立夏", "立秋", "立冬"];

/** 时间的密度：越长大，一回合越长 */
var STAGE_TABLE: { stage: Stage; fromAge: number; turnsPerYear: number; years: number }[] = [
  { stage: "childhood", fromAge: 3, turnsPerYear: 4, years: 9 },
  { stage: "teen", fromAge: 12, turnsPerYear: 2, years: 6 },
  { stage: "young", fromAge: 18, turnsPerYear: 1, years: 12 },
  { stage: "middle", fromAge: 30, turnsPerYear: 1 / 3, years: 30 },
  { stage: "old", fromAge: 60, turnsPerYear: 1 / 5, years: 1000 },
];

var ORDINARY_EVENT: LifeEvent = {
  id: "_ordinary",
  kind: "solo",
  stage: "childhood",
  seasons: [],
  weight: 1,
  requires: {},
  title: "平淡的日子",
  text: "这段日子没有什么特别的事。",
  options: [
    { id: "rest", text: "好好休息", tags: ["solitude"], effects: { self: { heart: 1 }, other: {}, bond: {}, flags: [] } },
    { id: "work", text: "多做一点事", tags: ["competitive"], effects: { self: { mind: 1 }, other: {}, bond: {}, flags: [] } },
    { id: "visit", text: "去看看 TA", tags: ["gentle"], effects: { self: {}, other: { heart: 1 }, bond: { close: 1 }, flags: [] } },
  ],
  resonance: null,
  dissonance: null,
};

// ---------- 随机数（mulberry32，状态存进存档，保证可复现） ----------

function lifeRand(s: LifeState): number {
  s.rng = (s.rng + 0x6d2b79f5) | 0;
  var t = s.rng;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

function lifePickWeighted<T>(s: LifeState, items: T[], weight: (x: T) => number): T | null {
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

// ---------- 创建 ----------

function lifeNewPerson(s: LifeState, name: string): Person {
  return {
    name: name,
    alive: true,
    lifespan: 66 + Math.floor(lifeRand(s) * 24),
    diedAtAge: null,
    stats: {
      body: 3 + Math.floor(lifeRand(s) * 4),
      mind: 3 + Math.floor(lifeRand(s) * 4),
      charm: 3 + Math.floor(lifeRand(s) * 4),
      heart: 5,
    },
    flags: [],
    tags: {},
  };
}

function lifeCreate(seed: number, names: { [R in Role]: string }, events: LifeEvent[]): LifeState {
  var s: LifeState = {
    version: 1,
    seed: seed,
    rng: seed | 0,
    turn: 0,
    ended: false,
    persons: { qing: null as any, mei: null as any },
    bond: { sync: 0, close: 10, distance: 0 },
    memories: [],
    log: [],
    scene: null,
  };
  s.persons.qing = lifeNewPerson(s, names.qing);
  s.persons.mei = lifeNewPerson(s, names.mei);
  s.scene = lifePickScene(s, events);
  return s;
}

// ---------- 抽事件 ----------

function lifeOther(r: Role): Role {
  return r === "qing" ? "mei" : "qing";
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

function lifeEligible(ev: LifeEvent, t: TimeInfo, flags: string[], seen: { [id: string]: boolean }): boolean {
  if (ev.stage !== t.stage) return false;
  if (seen[ev.id]) return false;
  if (ev.seasons.length > 0 && (t.season === null || ev.seasons.indexOf(t.season) < 0)) return false;
  var rq = ev.requires || {};
  if (rq.minAge !== undefined && t.age < rq.minAge) return false;
  if (rq.maxAge !== undefined && t.age > rq.maxAge) return false;
  return lifeHasAll(flags, rq.flags) && lifeHasNone(flags, rq.notFlags);
}

function lifePickScene(s: LifeState, events: LifeEvent[]): Scene | null {
  var t = lifeTimeAt(s.turn);
  var seen = lifeSeenIds(s);
  var alive = ROLES.filter(function (r) { return s.persons[r].alive; });
  if (alive.length === 0) return null;

  // 两人都在世时，有一定概率抽默契场景（童年更高）
  if (alive.length === 2) {
    var both = s.persons.qing.flags.concat(s.persons.mei.flags);
    var mirrors = events.filter(function (e) { return e.kind === "mirror" && lifeEligible(e, t, both, seen); });
    var chance = t.stage === "childhood" ? 0.55 : 0.4;
    if (mirrors.length > 0 && lifeRand(s) < chance) {
      var m = lifePickWeighted(s, mirrors, function (e) { return e.weight; })!;
      return { kind: "mirror", events: { qing: m.id, mei: m.id } };
    }
  }

  var scene: Scene = { kind: "solo", events: { qing: null, mei: null } };
  for (var i = 0; i < alive.length; i++) {
    var r = alive[i];
    var flags = s.persons[r].flags;
    var solos = events.filter(function (e) {
      return e.kind === "solo" && lifeEligible(e, t, flags, seen);
    });
    var pick = lifePickWeighted(s, solos, function (e) { return e.weight; });
    scene.events[r] = pick ? pick.id : ORDINARY_EVENT.id;
    if (pick) seen[pick.id] = true; // 同一回合两人不抽到同一个各自事件
  }
  return scene;
}

function lifeFindEvent(events: LifeEvent[], id: string): LifeEvent {
  if (id === ORDINARY_EVENT.id) return ORDINARY_EVENT;
  for (var i = 0; i < events.length; i++) if (events[i].id === id) return events[i];
  throw new Error("unknown event " + id);
}

function lifeFindOption(ev: LifeEvent, optionId: string): EventOption | null {
  for (var i = 0; i < ev.options.length; i++) if (ev.options[i].id === optionId) return ev.options[i];
  return null;
}

/** 本回合需要谁来做选择 */
function lifeRequiredRoles(s: LifeState): Role[] {
  if (!s.scene) return [];
  return ROLES.filter(function (r) { return s.persons[r].alive && s.scene!.events[r] !== null; });
}

function lifeIsValidChoice(s: LifeState, events: LifeEvent[], role: Role, optionId: string): boolean {
  if (!s.scene || s.ended) return false;
  var id = s.scene.events[role];
  if (!id || !s.persons[role].alive) return false;
  return lifeFindOption(lifeFindEvent(events, id), optionId) !== null;
}

// ---------- 影子：按玩家过去的性格标签替他选择 ----------

function lifeShadowChoose(s: LifeState, events: LifeEvent[], role: Role): string {
  var ev = lifeFindEvent(events, s.scene!.events[role]!);
  var tags = s.persons[role].tags;
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

// ---------- 结算 ----------

function lifeClamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

function lifeApplyStats(p: Person, d: Partial<Stats>) {
  for (var k in d) {
    var key = k as StatKey;
    p.stats[key] = lifeClamp(p.stats[key] + (d[key] || 0), STAT_MIN, STAT_MAX);
  }
}

function lifeApplyBond(s: LifeState, d: Partial<Bond>) {
  if (d.sync) s.bond.sync = lifeClamp(s.bond.sync + d.sync, 0, 100);
  if (d.close) s.bond.close = lifeClamp(s.bond.close + d.close, -20, 100);
  if (d.distance) s.bond.distance = lifeClamp(s.bond.distance + d.distance, 0, 5);
}

function lifeApplyOption(s: LifeState, role: Role, o: EventOption, fromShadow: boolean) {
  var me = s.persons[role];
  lifeApplyStats(me, o.effects.self);
  var other = s.persons[lifeOther(role)];
  if (other.alive) lifeApplyStats(other, o.effects.other);
  lifeApplyBond(s, o.effects.bond);
  for (var i = 0; i < o.effects.flags.length; i++) {
    if (me.flags.indexOf(o.effects.flags[i]) < 0) me.flags.push(o.effects.flags[i]);
  }
  if (!fromShadow) {
    for (var j = 0; j < o.tags.length; j++) me.tags[o.tags[j]] = (me.tags[o.tags[j]] || 0) + 1;
  }
}

/**
 * 结算一回合。choices 必须覆盖 lifeRequiredRoles 中的所有人（影子代选的也放进去，并列在 shadow 里）。
 * 返回本回合产生的日志（包括可能发生的死亡与终局）。
 */
function lifeResolve(s: LifeState, events: LifeEvent[], choices: Choices, shadow: Role[]): LogEntry[] {
  if (s.ended || !s.scene) throw new Error("life already ended");
  var required = lifeRequiredRoles(s);
  for (var i = 0; i < required.length; i++) {
    var r = required[i];
    if (!choices[r] || !lifeIsValidChoice(s, events, r, choices[r]!)) throw new Error("missing or invalid choice for " + r);
  }

  var t = lifeTimeAt(s.turn);
  var scene = s.scene;
  var out: LogEntry[] = [];
  var entry: LogEntry = {
    turn: s.turn,
    age: t.age,
    label: t.label,
    kind: scene.kind,
    events: { qing: scene.events.qing, mei: scene.events.mei },
    choices: { qing: choices.qing || null, mei: choices.mei || null },
    shadow: shadow.slice(),
    resonance: null,
    text: "",
  };

  for (var k = 0; k < required.length; k++) {
    var role = required[k];
    var ev = lifeFindEvent(events, scene.events[role]!);
    lifeApplyOption(s, role, lifeFindOption(ev, choices[role]!)!, shadow.indexOf(role) >= 0);
  }

  if (scene.kind === "mirror") {
    var mev = lifeFindEvent(events, scene.events.qing!);
    if (choices.qing === choices.mei) {
      entry.resonance = true;
      var res = mev.resonance && mev.resonance[choices.qing!];
      if (res) {
        lifeApplyBond(s, res.bond);
        entry.text = res.text;
        if (res.memory) s.memories.push({ title: res.memory, eventId: mev.id, turn: s.turn, age: t.age, vivid: 3 });
      } else {
        lifeApplyBond(s, { sync: 1 });
        entry.text = "你们选了同一个答案。";
      }
    } else {
      entry.resonance = false;
      if (mev.dissonance) {
        lifeApplyBond(s, mev.dissonance.bond);
        entry.text = mev.dissonance.text;
      }
    }
  }
  out.push(entry);

  // 回忆褪色
  s.turn += 1;
  for (var m = 0; m < s.memories.length; m++) {
    var mem = s.memories[m];
    if (mem.vivid > 0 && (s.turn - mem.turn) % MEMORY_FADE_EVERY === 0) mem.vivid -= 1;
  }

  // 生老病死：体魄每高 1 点多活半年，心情太差会折寿
  var nt = lifeTimeAt(s.turn);
  for (var d = 0; d < ROLES.length; d++) {
    var p = s.persons[ROLES[d]];
    if (!p.alive) continue;
    var limit = p.lifespan + (p.stats.body - 5) * 0.5 + (p.stats.heart < 2 ? -3 : 0);
    if (nt.age >= limit || nt.age >= 100) {
      p.alive = false;
      p.diedAtAge = nt.age;
      out.push({
        turn: s.turn, age: nt.age, label: nt.label, kind: "death",
        events: { qing: null, mei: null }, choices: { qing: null, mei: null },
        shadow: [], resonance: null, text: p.name + " 在 " + nt.age + " 岁那年离开了。",
      });
    }
  }

  if (!s.persons.qing.alive && !s.persons.mei.alive) {
    s.ended = true;
    s.scene = null;
    out.push({
      turn: s.turn, age: nt.age, label: nt.label, kind: "end",
      events: { qing: null, mei: null }, choices: { qing: null, mei: null },
      shadow: [], resonance: null, text: lifeEpitaph(s),
    });
  } else {
    s.scene = lifePickScene(s, events);
  }
  s.log = s.log.concat(out);
  return out;
}

/** 人生长卷底部的题词 */
function lifeEpitaph(s: LifeState): string {
  var mirrors = 0, hits = 0;
  for (var i = 0; i < s.log.length; i++) {
    if (s.log[i].kind === "mirror") { mirrors++; if (s.log[i].resonance) hits++; }
  }
  var rate = mirrors > 0 ? Math.round((hits / mirrors) * 100) : 0;
  return "你们一起走过了 " + s.turn + " 个回合，留下 " + s.memories.length + " 段共同回忆，默契率 " + rate + "%。";
}
