// 传承：一条人生线跨世保留的东西。纯函数，不依赖 Nakama。设计说明见 docs/LEGACY.md。
//
// 一世走完，每个人按这辈子怎么过的，给河畔里留下一件老物件；两个人都点了「再来一世」，
// 就在同一条人生线上重新投胎，每人可以从攒下的老物件里挑一件带上。
// 上一世留下的东西只进下一世的开局（先天属性半点、几块零花钱、一点亲近），不另起一套要攒的东西：
// 没有点数，没有进度；一世最多带一件，带过的不会越带越强。
//
// 第二步往循环里放的东西（都不给数值）：
//   痕迹    上一世两个人一起做过的事（墙上的名字、埋的盒子……）留在河畔里，下一世的孩子出生就带着 leg_ 标记，
//           隔世的事（content/events/legacy.yaml）靠它才遇得到。只记上一世的：这一世接着做了，才传得下去。
//   街坊记住的事（content/remembered.yaml）  长卷上的一枚章。没有奖励，记过的不记第二回。
//   藏着的天赋（talents.yaml 的 unlock）      这条人生线上出过那件事（legacy.marks），往后投胎才抽得到。
//
// 状态都在存档里：LifeState.legacy（跨世，整条人生线一份）、LifeState.life（第几世）、
// Roll.house / offer / heirloomId（投胎时）、Person.heirloomId、LifeState.left / noted（这一世留下了什么、街坊记住了什么）、
// LifeState.again（谁点了再来一世）。
// sim.ts 里的钩子：lifeRollOnce → legacyTalents，lifeCreate → legacyRoll，lifeConfirm → legacyBirth，
// lifeEndDay → legacyDerive（算结局之前）、legacyAbsorb（之后）。growth.ts 里三种藏着的天赋各一两行。
// 不用人生主线之外的随机数；头一世不多抽一次随机数，所以老存档和测试里的种子都还对得上。

// ---------- 类型 ----------

/** 老物件的来历：写法同一生小结（endings.yaml 的 lives.requires），多两样 */
type LegacyPersonReq = LifeEnding["requires"] & {
  /** 任意一项属性达到这个数 */
  anyStat?: number;
  /** 走的时候兜里的钱 */
  minMoney?: number;
};

/** 街坊记住的事的条件：两个人一起看的，写法同结局（endings.yaml 的 pair.requires），多几样 */
type LegacyPairReq = PairEnding["requires"] & {
  /** 两个人一起才办成的事有几回（搭把手的检定） */
  minHelps?: number;
};

/** 街坊记住的事（content/remembered.yaml）：长卷上的一枚章，没有奖励 */
interface Remembered {
  id: string;
  title: string;
  desc: string;
  /** pair 看两个人一起 / each 有一个人做到就算 / both 两个人都得做到 */
  who: "pair" | "each" | "both";
  requires: LegacyPairReq & LegacyPersonReq;
}

/** 老物件：上一世留下、下一世可以带上的东西（content/heirlooms.yaml） */
interface Heirloom {
  id: string;
  name: string;
  desc: string;
  /** 上一世什么样的人会留下它 */
  from: LegacyPersonReq;
  /** 带上它的人，先天属性加多少（不占投胎的点数） */
  bonus: Partial<Stats>;
  money: number;
  close: number;
  flags: string[];
}

interface PastPerson {
  name: string;
  familyId: string;
  talentId: string;
  diedAtAge: number;
  /** 一生小结的 id */
  ending: string;
  /** 找工作那一关走的路（job_ 开头的标记），没有是 null */
  job: string | null;
  /** 留下的老物件 */
  heirloom: string | null;
}

/** 走完的一世的小传 */
interface PastLife {
  life: number;
  /** 两个人的结局 id */
  pair: string;
  close: number;
  /** 记得最清的几段共同回忆 */
  memories: string[];
  persons: { [R in Role]: PastPerson };
  /** 这一世街坊新记住的事 */
  noted?: string[];
}

interface Legacy {
  /** 已经走完了几世 */
  lives: number;
  /** 住过的人家：lived 住过几回，kept 有几回接下了家里的营生（家业传了几代） */
  families: { [id: string]: { lived: number; kept: number } };
  /** 攒下的老物件，先留下的在前。同一件不记两回 */
  heirlooms: string[];
  /** 最近几世的小传（rules.legacy.pastKept） */
  past: PastLife[];
  /** 上一世留在河畔里的痕迹：共同标记（不带 leg_ 前缀）。只记上一世的 */
  traces: string[];
  /** 这条人生线上出过的事（藏着的天赋靠它解开）。记过就一直在，最多和藏着的天赋一样多 */
  marks: string[];
  /** 街坊记住的事：id → 第几世记住的 */
  remembered: { [id: string]: number };
}

interface LegacyRules {
  pastKept: number;
  heirloomOffer: number;
  houseMax: number;
  houseMoney: number;
  /** 大器晚成：童年少年长得慢（乘这个数），成年以后长得快（系数至少这么多），上头的空间多一截（growth.room 之外再加） */
  lateEarly: number;
  lateAfter: number;
  lateRoom: number;
  /** 连心：不走动的日子亲近只淡这么多（比例）；每天的心情往对门那边靠这么多（比例） */
  linkedDrift: number;
  linkedMood: number;
  /** 老灵魂：检定多这么多把握；童年少年魅力只长这么多（比例） */
  oldSoul: number;
  oldSoulCharm: number;
}

interface Rules { legacy: LegacyRules }
interface Talent {
  /** 藏着的天赋：这条人生线上出过这件事（某个人带过这个标记），往后投胎才抽得到 */
  unlock?: string | null;
}
interface Content {
  heirlooms: Heirloom[];
  remembered: Remembered[];
  /** build-content.mjs 从内容里算出来的两张表：会留给下一世的共同标记、能解开天赋的标记 */
  legacy: { traces: string[]; marks: string[] };
}
interface Roll {
  /** 这户人家的营生之前传过几代 */
  house?: number;
  /** 摆在面前的老物件（两个人看得见彼此的） */
  offer?: string[];
  /** 挑中带上的那一件 */
  heirloomId?: string | null;
}
interface Person { heirloomId?: string | null }
interface LifeState {
  /** 这条人生线的第几世（从 1 起） */
  life?: number;
  legacy?: Legacy;
  /** 这一世各自给河畔里留下的老物件（走完才有） */
  left?: { [R in Role]: string | null };
  /** 这一世街坊新记住的事（走完才有） */
  noted?: string[];
  /** 走完以后：谁点了「再来一世」 */
  again?: { [R in Role]: boolean };
}

var LEGACY_JOBS = ["job_desk", "job_teach", "job_trade", "job_craft", "job_labor", "job_odd"];
/** 小传里记几段共同回忆 */
var LEGACY_PAST_MEMORIES = 4;

/** 人生结束时规则算出来的标记（legacyDerive），结局和街坊记住的事的条件可以读。清单钉在 build-content.mjs */
var LEGACY_MANY_MIRRORS = 20;
/** 一个人最常做的那类选择至少这么多次，才算有脾气 */
var LEGACY_TEMPER = 8;

function legacyNew(): Legacy {
  return { lives: 0, families: {}, heirlooms: [], past: [], traces: [], marks: [], remembered: {} };
}

/** 内容里那两张表（热更新的旧内容包里可能没有，当空的） */
function legacyTables(c: Content): { traces: string[]; marks: string[] } {
  return c.legacy || { traces: [], marks: [] };
}

function legacyOf(s: LifeState): Legacy {
  if (!s.legacy) s.legacy = legacyNew();
  return s.legacy;
}

function legacyFindHeirloom(c: Content, id: string | null | undefined): Heirloom | null {
  if (!id) return null;
  for (var i = 0; i < c.heirlooms.length; i++) if (c.heirlooms[i].id === id) return c.heirlooms[i];
  return null;
}

// ---------- 投胎 ----------

/**
 * 这条人生线现在抽得到的天赋：藏着的要先出过那件事。
 * 头一世（和没出过事的人生线）滤掉以后就是原来那张表，抽出来的和以前一样。
 */
function legacyTalents(c: Content, legacy: Legacy | undefined): Talent[] {
  var marks = legacy && legacy.marks ? legacy.marks : [];
  var pool = c.talents.filter(function (t) { return !t.unlock || marks.indexOf(t.unlock) >= 0; });
  return pool.length > 0 ? pool : c.talents; // 内容校验保证不会空；真空了也不能抽不出来
}

/** 家业传了几代：这户人家在之前几世里被接下过几回营生 */
function legacyHouse(c: Content, legacy: Legacy | undefined, familyId: string): number {
  var f = legacy ? legacy.families[familyId] : null;
  return f ? Math.min(f.kept, c.rules.legacy.houseMax) : 0;
}

/** 投胎时给两个人各摆几件老物件：两人面前的不重样，东西只有一件，谁带走就是谁的 */
function legacyOffer(s: { rng: number }, c: Content, legacy: Legacy): { [R in Role]: string[] } {
  var out: { [R in Role]: string[] } = { qing: [], mei: [] };
  var pool = legacy.heirlooms.filter(function (id) { return legacyFindHeirloom(c, id) !== null; });
  if (pool.length === 0) return out; // 头一世不摆，也不动随机数
  for (var i = pool.length - 1; i > 0; i--) {
    var j = Math.floor(lifeRand(s) * (i + 1));
    var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp;
  }
  var n = c.rules.legacy.heirloomOffer;
  // 轮着摆。谁先摆一世一换：东西是单数的时候，多出来的那件不会回回落在同一个人面前
  var first: Role = legacy.lives % 2 === 1 ? "qing" : "mei";
  var second = lifeOther(first);
  for (var k = 0; k < pool.length; k++) {
    var to: Role = out[first].length <= out[second].length ? first : second;
    if (out[to].length < n) out[to].push(pool[k]);
  }
  return out;
}

/** lifeCreate 抽完两张卡以后调用：记下第几世，补上家业和摆在面前的老物件 */
function legacyRoll(s: LifeState, c: Content) {
  var lg = legacyOf(s);
  s.life = lg.lives + 1;
  var offer = legacyOffer(s, c, lg);
  for (var i = 0; i < ROLES.length; i++) {
    var r = s.rolls[ROLES[i]];
    r.house = legacyHouse(c, lg, r.familyId);
    r.offer = offer[ROLES[i]];
    r.heirloomId = null;
  }
}

/** 挑一件老物件带上（id 传 null 是放下不带）。返回错误信息或 null */
function legacyPick(s: LifeState, role: Role, id: string | null): string | null {
  if (s.phase !== "roll") return "已经开始了";
  var r = s.rolls[role];
  if (r.confirmed) return "已经定下来了";
  if (id !== null && (r.offer || []).indexOf(id) < 0) return "这件东西不在你面前";
  r.heirloomId = id;
  return null;
}

/** lifeConfirm 造出两个人以后调用：家业的家底、带着的那件老物件、上一世留在河畔里的痕迹 */
function legacyBirth(s: LifeState, c: Content) {
  var lg = legacyOf(s);
  for (var i = 0; i < ROLES.length; i++) {
    var r = s.rolls[ROLES[i]];
    var p = s.persons![ROLES[i]];
    // 痕迹：不是头一世的孩子带着 leg_any；上一世两个人一起做过的事各带一个 leg_ 标记（隔世的事读它）
    if (lg.lives > 0) {
      var leg = ["leg_any"];
      for (var t = 0; t < (lg.traces || []).length; t++) leg.push("leg_" + lg.traces[t]);
      if ((r.house || 0) > 0) leg.push("leg_house");
      lifeAddFlags(p, leg);
    }
    // 家业：之前几世有人接下过这户人家的营生，这一世的家底厚几块钱
    p.money += c.rules.legacy.houseMoney * (r.house || 0);
    var h = legacyFindHeirloom(c, r.heirloomId);
    p.heirloomId = h ? h.id : null;
    if (!h) continue;
    // 属性的加成不占投胎的点数，算进出生时的底子（growth.ts 的 growthBase 按 born 算）
    for (var k = 0; k < STAT_KEYS.length; k++) {
      var add = h.bonus[STAT_KEYS[k]] || 0;
      if (!add) continue;
      p.stats[STAT_KEYS[k]] = lifeClamp(p.stats[STAT_KEYS[k]] + add, 0, 10);
      p.born[STAT_KEYS[k]] = p.stats[STAT_KEYS[k]];
    }
    p.money += h.money;
    lifeAddFlags(p, h.flags);
    if (h.close) s.bond.close = lifeClamp(s.bond.close + h.close, -20, 100);
  }
}

// ---------- 一世走完 ----------

function legacyPersonOk(p: Person, rq: LegacyPersonReq): boolean {
  if (!lifeLifeEndingOk(p, { id: "", title: "", text: "", requires: rq })) return false;
  if (rq.anyStat !== undefined && Math.max(p.stats.body, p.stats.mind, p.stats.charm, p.stats.luck) < rq.anyStat) return false;
  return rq.minMoney === undefined || p.money >= rq.minMoney;
}

/**
 * 这个人给河畔里留下的老物件：按顺序取第一件对得上的（内容校验保证最后一件没有条件，兜底）。
 * taken 是对门已经留下的那件：两个人不留同一件，接着往下找；找到兜底那件就不挑了。
 */
function legacyLeave(c: Content, p: Person, taken?: string | null): string | null {
  var last = c.heirlooms.length - 1;
  for (var i = 0; i <= last; i++) {
    if (c.heirlooms[i].id === taken && i < last) continue;
    if (legacyPersonOk(p, c.heirlooms[i].from)) return c.heirlooms[i].id;
  }
  return null;
}

/** 谁先留：先走的先留；同一年走的，一世一换 */
function legacyLeaveOrder(s: LifeState): Role[] {
  var q = s.persons!.qing.diedAtAge, m = s.persons!.mei.diedAtAge;
  var qingFirst = q === m || q === null || m === null ? (s.life || 1) % 2 === 1 : q < m;
  return qingFirst ? ["qing", "mei"] : ["mei", "qing"];
}

function legacyJob(p: Person): string | null {
  for (var i = 0; i < LEGACY_JOBS.length; i++) if (lifeHasFlag(p, LEGACY_JOBS[i])) return LEGACY_JOBS[i];
  return null;
}

// ---------- 人生结束时才算得出来的事 ----------

/** 一个人最常做的那类选择（次数够了才算有脾气） */
function legacyTemper(p: Person): string | null {
  var best: string | null = null, n = 0;
  for (var k in p.tags) if (p.tags[k] > n) { n = p.tags[k]; best = k; }
  return n >= LEGACY_TEMPER ? best : null;
}

/**
 * 在算结局之前调用：把这一世才看得出来的事打成 x_ 标记，结局和街坊记住的事都能读。
 *   x_same_year 同一年走的   x_opposites 两个人最常做的那类选择不一样   x_many_mirrors 遇到过不少默契事
 *   x_same_trade 两个人干了一辈子同一行   x_plain_life 普通的孩子，过了不拔尖也不垫底的一辈子
 * 打过的不重复打，所以多调几回没关系。
 */
function legacyDerive(s: LifeState) {
  var q = s.persons!.qing, m = s.persons!.mei;
  var both: string[] = [];
  if (q.diedAtAge !== null && q.diedAtAge === m.diedAtAge) both.push("x_same_year");
  var tq = legacyTemper(q), tm = legacyTemper(m);
  if (tq && tm && tq !== tm) both.push("x_opposites");
  if (lifeStats(s).mirrors >= LEGACY_MANY_MIRRORS) both.push("x_many_mirrors");
  var jq = legacyJob(q);
  if (jq && jq !== "job_odd" && jq === legacyJob(m) && (q.diedAtAge || 0) >= 60 && (m.diedAtAge || 0) >= 60) both.push("x_same_trade");
  lifeAddFlags(q, both);
  lifeAddFlags(m, both);
  for (var i = 0; i < ROLES.length; i++) {
    var p = s.persons![ROLES[i]];
    var hi = Math.max(p.stats.body, p.stats.mind, p.stats.charm, p.stats.luck);
    var lo = Math.min(p.stats.body, p.stats.mind, p.stats.charm, p.stats.luck);
    var age = p.diedAtAge || 0;
    if (lifeHasFlag(p, "tal_plain") && !lifeHasFlag(p, "took_over") && hi < 8 && lo >= 4 && age >= 70 && age <= 88) lifeAddFlags(p, ["x_plain_life"]);
  }
}

/** 一辈子里两个人一起才办成的事有几回（搭把手的检定成了） */
function legacyHelps(s: LifeState): number {
  var n = 0;
  for (var i = 0; i < s.log.length; i++) {
    var ck = s.log[i].checks;
    if (ck && ((ck.qing && ck.qing.ok && ck.qing.help) || (ck.mei && ck.mei.ok && ck.mei.help))) n++;
  }
  return n;
}

function legacyRememberedOk(s: LifeState, a: Remembered): boolean {
  var rq = a.requires || {};
  if (a.who !== "pair") {
    var q = legacyPersonOk(s.persons!.qing, rq), m = legacyPersonOk(s.persons!.mei, rq);
    return a.who === "both" ? q && m : q || m;
  }
  if (!lifePairEndingOk(s, { id: "", title: "", text: "", requires: rq }, lifeStats(s))) return false;
  return rq.minHelps === undefined || legacyHelps(s) >= rq.minHelps;
}

/**
 * 一世走完，往河畔里记的第二批东西：留下的痕迹、出过的事、街坊新记住的事。
 * 在 legacyAbsorb 里调用；有这些之前就走完的一世由 legacyRepair 补记一回（靠 s.noted 有没有来判断，不会记两遍）。
 */
function legacyNote(s: LifeState, c: Content) {
  var lg = legacyOf(s);
  legacyDerive(s);
  var q = s.persons!.qing, m = s.persons!.mei;
  var has = function (f: string) { return lifeHasFlag(q, f) || lifeHasFlag(m, f); };
  var tables = legacyTables(c);
  // 痕迹只记这一世的：上一世埋的盒子，这一世没人再添东西，就到此为止
  lg.traces = tables.traces.filter(has);
  for (var k = 0; k < tables.marks.length; k++) {
    if (has(tables.marks[k]) && lg.marks.indexOf(tables.marks[k]) < 0) lg.marks.push(tables.marks[k]);
  }
  var noted: string[] = [];
  var list = c.remembered || [];
  for (var a = 0; a < list.length; a++) {
    if (lg.remembered[list[a].id] !== undefined) continue;
    if (legacyRememberedOk(s, list[a])) { lg.remembered[list[a].id] = s.life || lg.lives; noted.push(list[a].id); }
  }
  s.noted = noted;
  var last = lg.past[lg.past.length - 1];
  if (last && last.life === (s.life || lg.lives)) last.noted = noted;
}

/** 在结局算出来以后调用：把这一世记进传承 */
function legacyAbsorb(s: LifeState, c: Content) {
  var lg = legacyOf(s);
  var ending = s.ending!;
  lg.lives += 1;
  // 记得最清的几段回忆，按发生的先后排
  var vivid = s.memories.slice().sort(function (a, b) { return b.vivid - a.vivid || a.turn - b.turn; }).slice(0, LEGACY_PAST_MEMORIES);
  vivid.sort(function (a, b) { return a.turn - b.turn; });
  var titles: string[] = [];
  for (var v = 0; v < vivid.length; v++) titles.push(vivid[v].title);
  var order = legacyLeaveOrder(s);
  var left: { [R in Role]: string | null } = { qing: null, mei: null };
  left[order[0]] = legacyLeave(c, s.persons![order[0]]);
  left[order[1]] = legacyLeave(c, s.persons![order[1]], left[order[0]]);
  var persons: any = {};
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    var p = s.persons![r];
    var fam = lg.families[p.familyId] || (lg.families[p.familyId] = { lived: 0, kept: 0 });
    fam.lived += 1;
    if (lifeHasFlag(p, "took_over")) fam.kept += 1;
    if (left[r] && lg.heirlooms.indexOf(left[r]!) < 0) lg.heirlooms.push(left[r]!);
    persons[r] = { name: p.name, familyId: p.familyId, talentId: p.talentId, diedAtAge: p.diedAtAge, ending: ending.lives[r], job: legacyJob(p), heirloom: left[r] };
  }
  lg.past.push({ life: s.life || lg.lives, pair: ending.pair, close: Math.round(s.bond.close), memories: titles, persons: persons });
  while (lg.past.length > c.rules.legacy.pastKept) lg.past.shift();
  s.left = left;
  legacyNote(s, c); // 痕迹、出过的事、街坊记住的事
}

// ---------- 住户本 ----------

/** 住户本里一世那一页最多列几段回忆 */
var LEGACY_VIEW_MEMORIES = 40;

/**
 * 住户本翻到某一世时给人看的东西：从归档（或刚走完的存档）里一样一样挑出来。
 * 白名单：归档是整份存档，往后存档里加了什么都不会自动漏到客户端；归档可能是旧版本存的，所以每样都当可能没有。
 */
function legacyPastView(s: any): { [k: string]: any } {
  var persons: { [k: string]: any } = {};
  for (var i = 0; i < ROLES.length; i++) {
    var p = s.persons ? s.persons[ROLES[i]] : null;
    persons[ROLES[i]] = p
      ? { name: String(p.name || ""), familyId: p.familyId || null, talentId: p.talentId || null, diedAtAge: typeof p.diedAtAge === "number" ? p.diedAtAge : null, job: p.flags ? legacyJob(p) : null, heirloomId: p.heirloomId || null }
      : null;
  }
  var memories: { title: string; age: number; vivid: number }[] = [];
  var all: any[] = (s.memories || []).slice().sort(function (a: any, b: any) { return (b.vivid || 0) - (a.vivid || 0) || (a.turn || 0) - (b.turn || 0); }).slice(0, LEGACY_VIEW_MEMORIES);
  all.sort(function (a: any, b: any) { return (a.turn || 0) - (b.turn || 0); });
  for (var m = 0; m < all.length; m++) memories.push({ title: String(all[m].title || ""), age: Number(all[m].age) || 0, vivid: Number(all[m].vivid) || 0 });
  var st = lifeStats({ log: s.log || [] } as any);
  var ending = s.ending || {};
  var lives = ending.lives || {};
  var left = s.left || {};
  var bond = s.bond || {};
  return {
    life: Number(s.life) || 1,
    ending: { pair: ending.pair || null, lives: { qing: lives.qing || null, mei: lives.mei || null } },
    close: Math.round(Number(bond.close) || 0),
    persons: persons,
    memories: memories,
    left: { qing: left.qing || null, mei: left.mei || null },
    noted: (s.noted || []).slice(),
    stats: { mirrors: st.mirrors, rate: st.rate, together: st.together },
  };
}

// ---------- 再来一世 ----------

/** 点「再来一世」（yes 为 false 是收回）。两人都点了返回 true，由调用方用 legacyRebirth 换成新的一世 */
function legacyAgain(s: LifeState, role: Role, yes: boolean): boolean {
  if (s.phase !== "ended") return false;
  if (!s.again) s.again = { qing: false, mei: false };
  s.again[role] = yes;
  return s.again.qing && s.again.mei;
}

/** 两个人都点了吗 */
function legacyAgainReady(s: LifeState): boolean {
  return s.phase === "ended" && !!s.again && s.again.qing && s.again.mei;
}

/**
 * 新的一世：同一条人生线，带着传承重新投胎。上一世的长卷不带走（调用方先归档），只留小传。
 * 纯函数：新一世的种子接着存档里的随机数走，同一份存档换出来的下一世是同一个。
 */
function legacyRebirth(s: LifeState, c: Content): LifeState {
  return lifeCreate(Math.floor(lifeRand(s) * 0x7fffffff), c, legacyOf(s));
}

// ---------- 三种藏着的天赋（growth.ts 里各一两行）----------
// 都是换一种活法，不是多给点数：一头宽了，另一头就窄。数在 rules.yaml 的 legacy 一节。

/**
 * 大器晚成：童年少年长得慢，成年以后才开始长。
 * 老灵魂：小时候像个小大人，和同龄的孩子玩不到一块儿（童年少年魅力长得慢）。
 */
function legacyPlasticity(c: Content, p: Person, stage: Stage, k: StatKey, v: number): number {
  var young = stage === "childhood" || stage === "teen";
  if (lifeHasFlag(p, "tal_late")) v = young ? v * c.rules.legacy.lateEarly : Math.max(v, c.rules.legacy.lateAfter);
  if (young && k === "charm" && lifeHasFlag(p, "tal_oldsoul")) v *= c.rules.legacy.oldSoulCharm;
  return v;
}

/** 大器晚成：成年以后，上头的空间比别人多一截（别人长不动了，他还在长） */
function legacyRoom(c: Content, p: Person, stage: Stage): number {
  if (stage === "childhood" || stage === "teen" || !lifeHasFlag(p, "tal_late")) return 0;
  return c.rules.legacy.lateRoom || 0;
}

/** 连心：两个人里有一个是，不走动的日子亲近就淡得慢 */
function legacyDrift(c: Content, s: LifeState, drift: number): number {
  var linked = lifeHasFlag(s.persons!.qing, "tal_linked") || lifeHasFlag(s.persons!.mei, "tal_linked");
  return linked ? drift * c.rules.legacy.linkedDrift : drift;
}

/** 连心：一天过完，心情往对门那边靠一截。TA 高兴你跟着高兴，TA 难受你也睡不踏实 */
function legacyLinkedMood(c: Content, p: Person, other: Person) {
  if (!lifeHasFlag(p, "tal_linked") || !other.alive) return;
  p.needs.mood = lifeClamp(Math.round(p.needs.mood + (other.needs.mood - p.needs.mood) * c.rules.legacy.linkedMood), 0, 100);
}

/** 老灵魂：头一回干的事，上手像干过（检定多一点把握） */
function legacyCheckBonus(c: Content, p: Person): number {
  return lifeHasFlag(p, "tal_oldsoul") ? c.rules.legacy.oldSoul : 0;
}

// ---------- 存档 ----------

/** 旧存档补上传承的字段（save.ts 的 v5 → v6）：当作头一世，什么都还没攒下 */
function legacyUpgrade(s: any) {
  if (!s.legacy) s.legacy = legacyNew();
  if (!s.life) s.life = s.legacy.lives + 1;
  for (var i = 0; i < ROLES.length; i++) {
    var r = s.rolls ? s.rolls[ROLES[i]] : null;
    if (r) {
      if (r.house === undefined) r.house = 0;
      if (!r.offer) r.offer = [];
      if (r.heirloomId === undefined) r.heirloomId = null;
    }
    var p = s.persons ? s.persons[ROLES[i]] : null;
    if (p && p.heirloomId === undefined) p.heirloomId = null;
  }
}

/** v6 → v7：痕迹、出过的事、街坊记住的事，都从这一世起记 */
function legacyUpgrade2(s: any) {
  var lg = s.legacy || (s.legacy = legacyNew());
  if (!lg.traces) lg.traces = [];
  if (!lg.marks) lg.marks = [];
  if (!lg.remembered) lg.remembered = {};
}

/** 内容变了以后摘掉悬空的引用（save.ts 的 lifeRepair）：老物件被删了，攒下的、摆着的、挑中的都放下 */
function legacyRepair(s: LifeState, c: Content, notes: string[]) {
  var lg = legacyOf(s);
  // 有传承之前就走完的一世：当时没记，现在补记上（留下的老物件、小传），再来一世时才接得上
  if (s.phase === "ended" && !s.left && s.ending && s.persons) {
    legacyAbsorb(s, c);
    notes.push("第 " + (s.life || 1) + " 世走完时还没有传承，补记");
  }
  // 只有老物件那会儿走完的一世：痕迹和街坊记住的事补记一回
  if (s.phase === "ended" && s.left && s.noted === undefined && s.persons) {
    legacyNote(s, c);
    notes.push("第 " + (s.life || 1) + " 世走完时还没有街坊记住的事，补记");
  }
  // 街坊记住的事、出过的事从内容里删了：摘掉（痕迹不用管，没人读的标记留着也没事，下一世走完就重记）
  var known: { [id: string]: boolean } = {};
  for (var a = 0; a < (c.remembered || []).length; a++) known[c.remembered[a].id] = true;
  for (var id in lg.remembered) {
    if (!known[id]) { notes.push("legacy.remembered " + id + " 已不存在，摘掉"); delete lg.remembered[id]; }
  }
  if (s.noted) s.noted = s.noted.filter(function (x) { return known[x]; });
  for (var pi = 0; pi < lg.past.length; pi++) {
    if (lg.past[pi].noted) lg.past[pi].noted = lg.past[pi].noted!.filter(function (x) { return known[x]; });
  }
  var marks = legacyTables(c).marks;
  lg.marks = lg.marks.filter(function (x) { return marks.indexOf(x) >= 0; });
  var kept = lg.heirlooms.filter(function (id) { return legacyFindHeirloom(c, id) !== null; });
  if (kept.length !== lg.heirlooms.length) {
    notes.push("legacy.heirlooms 里有 " + (lg.heirlooms.length - kept.length) + " 件老物件已不存在，摘掉");
    lg.heirlooms = kept;
  }
  for (var i = 0; i < ROLES.length; i++) {
    var role = ROLES[i];
    var r = s.rolls ? s.rolls[role] : null;
    if (r && r.offer) r.offer = r.offer.filter(function (h) { return legacyFindHeirloom(c, h) !== null; });
    if (r && r.heirloomId && !legacyFindHeirloom(c, r.heirloomId)) {
      notes.push("roll." + role + " 挑的老物件 " + r.heirloomId + " 已不存在，放下");
      r.heirloomId = null;
    }
    if (s.left && s.left[role] && !legacyFindHeirloom(c, s.left[role])) s.left[role] = null;
  }
}
