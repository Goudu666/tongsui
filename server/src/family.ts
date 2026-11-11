// 成家和下一代（docs/FAMILY.md）：生孩子、带孩子、孩子自己长、孩子的关口。
// 孩子用的是和人一样的三项属性（体魄 / 心智 / 魅力），孩子的关口是同一套 milestone（多一个 kidAge）。
// 只在拿到 has_kid、生孩子那一刻多用随机数（名字、出生属性的那一点浮动），不动开局和每天早上的随机数顺序。
//   kidSync        事件结算以后、一天过完：有 has_kid 没孩子的人生一个（两口子共用一个，对门也拿 has_kid）
//   kidGrow        带孩子的行动（Action.kid）长孩子（world.ts 的 worldActOnce / worldFinish / worldJoinLate）
//   kidDayEnd      不押也自己长一点
//   kidGateToday   孩子的关口今天该不该过（world.ts 的 worldStartDay）
//   lifeKidBind    关口按 kid_* 算分前，把孩子的属性挂到爹妈身上（不进存档）

var KID_KEYS: ("body" | "mind" | "charm")[] = ["body", "mind", "charm"];
var KID_SCORE: { [k: string]: "body" | "mind" | "charm" } = { kid_body: "body", kid_mind: "mind", kid_charm: "charm" };
/** 规则表里没写 family 时的数（老内容包） */
var FAMILY_DEFAULT: FamilyRules = {
  names: ["小宝"], start: { body: 2, mind: 2, charm: 2 }, inherit: 0.2, noise: 0.6, room: 6,
  selfGrow: { body: 0.08, mind: 0.08, charm: 0.08 }, sameAge: 2,
};

function familyRules(c: Content): FamilyRules {
  return c.rules.family || FAMILY_DEFAULT;
}

/** 这个人的孩子（没有返回 null） */
function kidOf(s: LifeState, role: Role): Kid | null {
  var ks = s.kids || [];
  for (var i = 0; i < ks.length; i++) if (ks[i].of.indexOf(role) >= 0) return ks[i];
  return null;
}

/** 孩子几岁：爹妈现在的岁数 − 生的时候爹妈的岁数（两个人同岁） */
function kidAgeOf(s: LifeState, kid: Kid): number {
  return lifeTimeAt(s.turn).age - kid.bornAge;
}

/** 这个人的孩子几岁（没孩子返回 null） */
function kidAgeFor(s: LifeState, role: Role): number | null {
  var k = kidOf(s, role);
  return k ? kidAgeOf(s, k) : null;
}

/** 两口子：两个人都有 p_married，对门还活着 */
function kidCouple(s: LifeState, role: Role): boolean {
  var p = s.persons![role], o = s.persons![lifeOther(role)];
  return o.alive && lifeHasFlag(p, "p_married") && lifeHasFlag(o, "p_married");
}

/**
 * 有 has_kid 没孩子的人：生一个。两口子是同一个孩子（对门有孩子就算进去，没有就一起生，对门也拿 has_kid）。
 * 两家各有一个、出生差不到 sameAge 岁：两个大人都打 kids_same_age。
 */
function kidSync(s: LifeState, c: Content) {
  if (!s.persons) return;
  if (!s.kids) s.kids = [];
  var fr = familyRules(c);
  var age = lifeTimeAt(s.turn).age;
  for (var i = 0; i < ROLES.length; i++) {
    var role = ROLES[i];
    var p = s.persons[role];
    if (!p.alive || !lifeHasFlag(p, "has_kid") || kidOf(s, role)) continue;
    var other = lifeOther(role);
    var couple = kidCouple(s, role);
    var theirs = couple ? kidOf(s, other) : null;
    if (theirs) {
      theirs.of.push(role);
      continue;
    }
    var of: Role[] = couple ? [role, other] : [role];
    var stats: Stats = { body: 0, mind: 0, charm: 0, luck: 5 };
    for (var k = 0; k < KID_KEYS.length; k++) {
      var key = KID_KEYS[k];
      var sum = 0;
      for (var j = 0; j < of.length; j++) sum += s.persons[of[j]].stats[key];
      var v = fr.start[key] + (sum / of.length) * fr.inherit + (lifeRand(s) - 0.5) * fr.noise;
      stats[key] = lifeClamp(Math.round(v * 1000) / 1000, 0, 10);
    }
    var name = fr.names[Math.floor(lifeRand(s) * fr.names.length)] || "孩子";
    // 两家孩子同名不好认：撞了就往后挪一个
    var twin = kidOf(s, other);
    if (twin && twin.name === name && fr.names.length > 1) name = fr.names[(fr.names.indexOf(name) + 1) % fr.names.length];
    s.kids.push({ id: "kid" + (s.kids.length + 1), name: name, of: of, bornAge: age, stats: stats });
    if (couple) lifeAddFlags(s.persons[other], ["has_kid"]);
  }
  var kq = kidOf(s, "qing"), km = kidOf(s, "mei");
  if (kq && km && kq !== km && Math.abs(kq.bornAge - km.bornAge) < fr.sameAge) {
    lifeAddFlags(s.persons.qing, ["kids_same_age"]);
    lifeAddFlags(s.persons.mei, ["kids_same_age"]);
  }
}

/** 孩子这个岁数在哪个阶段（长得快慢按孩子自己的年纪） */
function kidStage(age: number): Stage {
  var st: Stage = "childhood";
  for (var i = 0; i < STAGE_TABLE.length; i++) if (age >= STAGE_TABLE[i].fromAge) st = STAGE_TABLE[i].stage;
  return st;
}

/**
 * 给孩子长。raw 是行动里写的数（已经乘了状态效率、做了几遍、搭伴倍率），按和人一样的思路折算：
 * actionScale × 爹妈这个日子的 turnWeight × 孩子年纪的 plasticity × 离 room 的远近。返回实际长了多少
 */
function kidGrow(s: LifeState, c: Content, kid: Kid, raw: Partial<Stats>): Partial<Stats> {
  var fr = familyRules(c);
  var g = c.rules.growth;
  var stage = lifeTimeAt(s.turn).stage;
  var tw = g.turnWeight ? g.turnWeight[stage] : 1;
  var ks = kidStage(kidAgeOf(s, kid));
  var out: Partial<Stats> = {};
  for (var k in raw) {
    var key = k as StatKey;
    if (key !== "body" && key !== "mind" && key !== "charm") continue;
    var r = (raw as any)[k] as number;
    if (!(r > 0)) continue;
    var before = kid.stats[key];
    var room = lifeClamp(1 - (before - fr.start[key]) / fr.room, g.floor, 1);
    var v = r * g.actionScale * (typeof tw === "number" ? tw : 1) * g.plasticity[ks][key] * room;
    kid.stats[key] = lifeClamp(Math.round((before + v) * 1000) / 1000, 0, 10);
    var d = Math.round((kid.stats[key] - before) * 1000) / 1000;
    if (d !== 0) out[key] = d;
  }
  return out;
}

/** 一个日子过完：孩子不押也自己长一点（这个日子隔了几年就长几年的）。在 s.turn 还没 +1 时调 */
function kidDayEnd(s: LifeState, c: Content) {
  var ks = s.kids || [];
  if (!ks.length) return;
  var fr = familyRules(c);
  var years = growthYearsPerTurn(s.turn);
  for (var i = 0; i < ks.length; i++) {
    var kid = ks[i];
    var alive = false;
    for (var j = 0; j < kid.of.length; j++) if (s.persons![kid.of[j]].alive) alive = true;
    if (!alive) continue;
    for (var k = 0; k < KID_KEYS.length; k++) {
      var key = KID_KEYS[k];
      var room = lifeClamp(1 - (kid.stats[key] - fr.start[key]) / fr.room, c.rules.growth.floor, 1);
      kid.stats[key] = lifeClamp(Math.round((kid.stats[key] + fr.selfGrow[key] * years * room) * 1000) / 1000, 0, 10);
    }
  }
}

/** 关口按 kid_* 算分之前：把孩子的属性挂到爹妈身上（不可枚举，不进存档；没孩子的去掉） */
function lifeKidBind(s: LifeState) {
  if (!s.persons) return;
  for (var i = 0; i < ROLES.length; i++) {
    var kid = kidOf(s, ROLES[i]);
    Object.defineProperty(s.persons[ROLES[i]], "_kid", { value: kid ? kid.stats : null, enumerable: false, writable: true, configurable: true });
  }
}

/** 算分时读孩子的那项属性（没孩子按 0） */
function kidScoreStat(p: Person, k: string): number {
  var ks = (p as any)._kid as Stats | null | undefined;
  return ks ? ks[KID_SCORE[k]] : 0;
}

/** 这是孩子的关口 */
function kidIsGate(ev: LifeEvent): boolean {
  return ev.kind === "milestone" && typeof ev.kidAge === "number";
}

/** 这个人过不过这道关：自己的关口看年纪，孩子的关口还要有孩子、孩子到了岁数 */
function lifeMilestoneForRole(s: LifeState, ev: LifeEvent, role: Role): boolean {
  var p = s.persons![role];
  if (!lifeMilestoneFor(ev, p)) return false;
  if (!kidIsGate(ev)) return true;
  var ka = kidAgeFor(s, role);
  return ka !== null && ka >= ev.kidAge!;
}

/** 今天轮得到的孩子的关口（自己今天有关口就没有）：孩子岁数最小的那道先过，每道只一次 */
function kidGateToday(s: LifeState, c: Content): LifeEvent | null {
  var best: LifeEvent | null = null;
  for (var i = 0; i < c.events.length; i++) {
    var ev = c.events[i];
    if (!kidIsGate(ev)) continue;
    if (best && ev.kidAge! >= best.kidAge!) continue;
    for (var j = 0; j < ROLES.length; j++) {
      var r = ROLES[j];
      if (lifeMilestoneForRole(s, ev, r) && !lifeSeenIds(s, r)[ev.id]) { best = ev; break; }
    }
  }
  return best;
}

/** 孩子的这道关从现在起还要几个日子（落在自己有关口的那天就往后挪一天） */
function kidGateTurns(s: LifeState, c: Content, kid: Kid, ev: LifeEvent): number {
  var k = lifeTurnsUntilAge(s.turn, kid.bornAge + ev.kidAge!);
  for (var n = 0; n < 6; n++) {
    var own = lifeMilestoneAt(c, lifeTimeAt(s.turn + k).age);
    if (!own) break;
    k++;
  }
  return k;
}

/** WORLD 里每个人的孩子卡片（没有就不发）：shared 是两口子共用的这一个 */
function kidView(s: LifeState, role: Role): { name: string; age: number; stats: { body: number; mind: number; charm: number }; shared: boolean } | undefined {
  var kid = kidOf(s, role);
  if (!kid) return undefined;
  return {
    name: kid.name, age: kidAgeOf(s, kid),
    stats: { body: lifeRound1(kid.stats.body), mind: lifeRound1(kid.stats.mind), charm: lifeRound1(kid.stats.charm) },
    shared: kid.of.length > 1,
  };
}
