// 传承：一条人生线跨世保留的东西。纯函数，不依赖 Nakama。设计说明见 docs/LEGACY.md。
//
// 一世走完，每个人按这辈子怎么过的，给河畔里留下一件老物件；两个人都点了「再来一世」，
// 就在同一条人生线上重新投胎，每人可以从攒下的老物件里挑一件带上。
// 上一世留下的东西只进下一世的开局（先天属性半点、几块零花钱、一点亲近），不另起一套要攒的东西：
// 没有点数，没有进度；一世最多带一件，带过的不会越带越强。
//
// 状态都在存档里：LifeState.legacy（跨世，整条人生线一份）、LifeState.life（第几世）、
// Roll.house / offer / heirloomId（投胎时）、Person.heirloomId、LifeState.left（这一世留下了什么）、LifeState.again（谁点了再来一世）。
// sim.ts 里是三处单行的钩子：lifeCreate → legacyRoll，lifeConfirm → legacyBirth，lifeEndDay → legacyAbsorb。
// 不用人生主线之外的随机数；头一世不多抽一次随机数，所以老存档和测试里的种子都还对得上。

// ---------- 类型 ----------

/** 老物件的来历：写法同一生小结（endings.yaml 的 lives.requires），多两样 */
type LegacyPersonReq = LifeEnding["requires"] & {
  /** 任意一项属性达到这个数 */
  anyStat?: number;
  /** 走的时候兜里的钱 */
  minMoney?: number;
};

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
}

interface LegacyRules {
  pastKept: number;
  heirloomOffer: number;
  houseMax: number;
  houseMoney: number;
}

interface Rules { legacy: LegacyRules }
interface Content { heirlooms: Heirloom[] }
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
  /** 走完以后：谁点了「再来一世」 */
  again?: { [R in Role]: boolean };
}

var LEGACY_JOBS = ["job_desk", "job_teach", "job_trade", "job_craft", "job_labor", "job_odd"];
/** 小传里记几段共同回忆 */
var LEGACY_PAST_MEMORIES = 4;

function legacyNew(): Legacy {
  return { lives: 0, families: {}, heirlooms: [], past: [] };
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

/** lifeConfirm 造出两个人以后调用：家业的家底，和带着的那件老物件 */
function legacyBirth(s: LifeState, c: Content) {
  for (var i = 0; i < ROLES.length; i++) {
    var r = s.rolls[ROLES[i]];
    var p = s.persons![ROLES[i]];
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

/** 内容变了以后摘掉悬空的引用（save.ts 的 lifeRepair）：老物件被删了，攒下的、摆着的、挑中的都放下 */
function legacyRepair(s: LifeState, c: Content, notes: string[]) {
  var lg = legacyOf(s);
  // 有传承之前就走完的一世：当时没记，现在补记上（留下的老物件、小传），再来一世时才接得上
  if (s.phase === "ended" && !s.left && s.ending && s.persons) {
    legacyAbsorb(s, c);
    notes.push("第 " + (s.life || 1) + " 世走完时还没有传承，补记");
  }
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
