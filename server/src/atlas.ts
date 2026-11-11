// 图鉴和「差一点」：让一世走完的人想马上再来一世。纯函数，不依赖 Nakama。设计说明见 docs/LEGACY.md 第十三节。
//
// 三样东西，都不给数值：
//   见过的结局  legacy.seen 按人生线记两个人走到过的结局、各自的一生。住户本里有一页图鉴：
//               见过的写全文，没见过的只有一句谜面（content/atlas.yaml），藏着的只有一个空框。
//   差一点      一世走完，挑出离得最近的那几样，写在结局页「再来一世」正上方（LifeState.near），下一世投胎页再提一句：
//               关口上差几分没够上的那条线（和关口上锁着的那条路用的是同一个数，lifeOptionLock），
//               差一样就能走到的结局、一生。只往「更难得」的那头看（结局表里排在这一世前面的）。
//   老物件会变  heirlooms.yaml 里 from.carried：带着那件出生、这一世又做了那件事，留下的是它的下一种样子。
//               加成不涨（构建拦着半点上限），链尾那件带出一个藏着的结局。
//
// 状态：Legacy.seen（跨世）、LifeState.near（这一世走完才有）、PastLife.near（小传里留一句给下一世投胎页）、
// 关口那一条日志的 results[role].near（考场上那一刻差多少，事后算不回来）。
// 都是纯新增的可选字段：旧存档、旧安装包不认识就不用（存档版本和协议版本都不动）。

/** 关口上一条没够上的路：差多少（和关口上锁着的路写的是同一个数） */
interface MilestoneNear {
  option: string;
  have: number;
  need: number;
  unit: string;
  label: string;
}

interface AtlasSeen {
  /** 两个人的结局 id → 第几世头一回走到 */
  pair: { [id: string]: number };
  /** 一生小结 id → 第几世头一回有人走到 */
  lives: { [id: string]: number };
}

interface Legacy {
  seen?: AtlasSeen;
}

/** 结局页上「差一点」的一行 */
interface NearLine {
  kind: "milestone" | "pair" | "life";
  /** 关口的事件 id / 结局 id / 一生小结 id */
  id: string;
  role?: Role;
  text: string;
}

interface LifeState {
  /** 一世走完：差一点就……（最多三行，先关口、再结局、再一生） */
  near?: NearLine[];
}

interface PastLife {
  /** 这一世的「差一点」（只留文字），下一世投胎页提一句 */
  near?: string[];
}

/** content/atlas.yaml */
interface Atlas {
  /** 藏着的结局、一生：没走到之前，图鉴里只有一个空框 */
  hidden: string[];
  /** 不往那头说「差一点」的结局（走散、早走这类，没人想差一点走到那儿） */
  sad: string[];
  /** 图鉴里没见过的结局的那一句 */
  riddles: { [id: string]: string };
  /** 差一点的时候，缺的那个标记怎么说（「就差在楼顶拉个钩」）。没写的标记不拿来说差一点 */
  says: { [flag: string]: string };
}

interface Content {
  atlas?: Atlas;
}

/** 关口上「差一点」最多差这么多才算：分数线差 10 分（一个阶段专心过大约动 4~12 分），钱差 40 块，亲近差 10 */
var ATLAS_NEAR_POINTS = 10;
var ATLAS_NEAR_MONEY = 40;
var ATLAS_NEAR_CLOSE = 10;
/** 结局的数值条件最多差这么多才算「差一点」 */
var ATLAS_NEAR_TOL: { [k: string]: number } = { close: 12, sync: 12, rate: 15, memories: 3, together: 10, stat: 1.0, diedAge: 5 };
/** 缺一个标记算多远（数值差在 0~1 之间，正好差到头是 1） */
var ATLAS_FLAG_GAP = 0.6;
/** 结局页上最多几行；小传里留几行 */
var ATLAS_NEAR_LINES = 3;
var ATLAS_PAST_NEAR = 2;

function atlasOf(c: Content): Atlas {
  return c.atlas || { hidden: [], sad: [], riddles: {}, says: {} };
}

function atlasSeenNew(): AtlasSeen {
  return { pair: {}, lives: {} };
}

/**
 * 这条人生线见过的结局。没有的话从小传里补（有图鉴之前走完的几世，小传里记着结局）：
 * 只补得回最近几世（rules.legacy.pastKept），更早的就算没见过，再走到一回就记上了。
 */
function atlasSeenOf(lg: Legacy): AtlasSeen {
  if (lg.seen) return lg.seen;
  var seen = atlasSeenNew();
  for (var i = 0; i < lg.past.length; i++) {
    var p = lg.past[i];
    if (p.pair && seen.pair[p.pair] === undefined) seen.pair[p.pair] = p.life;
    for (var r = 0; r < ROLES.length; r++) {
      var e = p.persons && p.persons[ROLES[r]] ? p.persons[ROLES[r]].ending : null;
      if (e && seen.lives[e] === undefined) seen.lives[e] = p.life;
    }
  }
  lg.seen = seen;
  return seen;
}

// ---------- 关口：差几分没够上的那条路 ----------

/**
 * 这条路是不是只差分数（不是家里没有那个条件、不是对门不在了、不是钱不够交）：差多少。够得着、或者不是分数的事返回 null。
 * 数和 lifeOptionLock 写在锁上的那句一样：属性类按百分制往下取整，钱和亲近按原数。
 */
function atlasOptionShort(ev: LifeEvent, o: EventOption, p: Person, swing: number, bond?: Bond): MilestoneNear | null {
  var rq = o.requires || {};
  if (!o.min || !lifeHasAll(p.flags, rq.flags) || !lifeHasNone(p.flags, rq.notFlags)) return null;
  var w = lifeOptionWeights(ev, o);
  if (w.close && !bond) return null;
  var have = lifeScore(p, w, bond) + (lifeScoreRaw(w) ? 0 : swing);
  if (have >= o.min) return null;
  if (w.money) return { option: o.id, have: Math.floor(have), need: o.min, unit: "块", label: "积蓄" };
  if (w.close) return { option: o.id, have: Math.floor(have), need: o.min, unit: "分", label: "亲近" };
  return { option: o.id, have: lifePoints(have), need: lifePoints(o.min), unit: "分", label: lifeWeightsLabel(w) };
}

/** 差得多远（0~1，超过 1 就不算差一点） */
function atlasMilestoneGap(n: MilestoneNear): number {
  var tol = n.unit === "块" ? ATLAS_NEAR_MONEY : n.label === "亲近" ? ATLAS_NEAR_CLOSE : ATLAS_NEAR_POINTS;
  return (n.need - n.have) / tol;
}

/**
 * 关口结算时调用（lifeResolveEvent，扣钱、长属性之前）：这个人离哪条没走成的路最近。
 * 走的就是那条、或者差得太远，返回 null。
 */
function atlasMilestoneNear(ev: LifeEvent, chosen: string, p: Person, swing: number, bond?: Bond, gscore?: number): MilestoneNear | null {
  var best: MilestoneNear | null = null, gap = 2;
  var cands: MilestoneNear[] = [];
  for (var i = 0; i < ev.options.length; i++) {
    var o = ev.options[i];
    if (o.id === chosen) continue;
    var n = atlasOptionShort(ev, o, p, swing, bond);
    if (n) cands.push(n);
  }
  // 名次也算：目标条上摆着的那几档（lifeTapeGrades），分数用的是这一关真拿去评名次的那个（gscore）
  if (gscore !== undefined) {
    var gis = lifeTapeGrades(ev, p);
    for (var k = 0; k < gis.length; k++) {
      var gr = ev.grades![gis[k]];
      if (gscore >= gr.min || !gr.label) continue;
      cands.push({ option: "grade:" + gis[k], have: lifePoints(gscore), need: lifePoints(gr.min), unit: "分", label: lifeWeightsLabel(ev.score || {}) });
    }
  }
  for (var j = 0; j < cands.length; j++) {
    var g = atlasMilestoneGap(cands[j]);
    if (g > 0 && g <= 1 && g < gap) { best = cands[j]; gap = g; }
  }
  return best;
}

// ---------- 结局：差一样就能走到的那个 ----------

/** 一个没满足的条件 */
interface AtlasMiss {
  /** 缺的标记 / 不该有的标记 / 数值 */
  flag?: string;
  not?: string;
  key?: string;
  have?: number;
  need?: number;
  /** 0~1；不能说「差一点」的（数太高了、出身定的）是 Infinity */
  gap: number;
}

function atlasFlagMiss(a: Atlas, flag: string, not: boolean): AtlasMiss {
  var ok = !!a.says[flag];
  return not ? { not: flag, gap: ok ? ATLAS_FLAG_GAP : Infinity } : { flag: flag, gap: ok ? ATLAS_FLAG_GAP : Infinity };
}

function atlasNumMiss(key: string, have: number, min: number | undefined, max: number | undefined, out: AtlasMiss[]) {
  if (min !== undefined && have < min) out.push({ key: key, have: have, need: min, gap: (min - have) / (ATLAS_NEAR_TOL[key] || 1) });
  if (max !== undefined && have > max) out.push({ key: key, have: have, need: max, gap: Infinity });
}

/** 两个人的结局还差哪几样 */
function atlasPairMiss(s: LifeState, c: Content, e: PairEnding, st: { rate: number; together: number }): AtlasMiss[] {
  var a = atlasOf(c);
  var rq = e.requires || {};
  var flags = s.persons!.qing.flags.concat(s.persons!.mei.flags);
  var out: AtlasMiss[] = [];
  for (var i = 0; i < (rq.flags || []).length; i++) if (flags.indexOf(rq.flags![i]) < 0) out.push(atlasFlagMiss(a, rq.flags![i], false));
  for (var j = 0; j < (rq.notFlags || []).length; j++) if (flags.indexOf(rq.notFlags![j]) >= 0) out.push(atlasFlagMiss(a, rq.notFlags![j], true));
  atlasNumMiss("close", Math.round(s.bond.close), rq.minClose, rq.maxClose, out);
  atlasNumMiss("sync", Math.round(s.bond.sync), rq.minSync, rq.maxSync, out);
  atlasNumMiss("memories", s.memories.length, rq.minMemories, rq.maxMemories, out);
  atlasNumMiss("rate", st.rate, rq.minRate, rq.maxRate, out);
  atlasNumMiss("together", st.together, rq.minTogether, undefined, out);
  // 距离只有 0~5 几档：差一档就当缺一样东西说（「住得近些」「走得远些」）
  var d = s.bond.distance;
  if (rq.maxDistance !== undefined && d > rq.maxDistance) out.push({ key: "near", gap: d - rq.maxDistance <= 1 ? ATLAS_FLAG_GAP : Infinity });
  if (rq.minDistance !== undefined && d < rq.minDistance) out.push({ key: "far", gap: rq.minDistance - d <= 1 ? ATLAS_FLAG_GAP : Infinity });
  return out;
}

/** 一个人的一生还差哪几样 */
function atlasLifeMiss(c: Content, p: Person, e: LifeEnding): AtlasMiss[] {
  var a = atlasOf(c);
  var rq = e.requires || {};
  var out: AtlasMiss[] = [];
  for (var i = 0; i < (rq.flags || []).length; i++) if (!lifeHasFlag(p, rq.flags![i])) out.push(atlasFlagMiss(a, rq.flags![i], false));
  for (var j = 0; j < (rq.notFlags || []).length; j++) if (lifeHasFlag(p, rq.notFlags![j])) out.push(atlasFlagMiss(a, rq.notFlags![j], true));
  for (var k in rq.stats || {}) {
    var need = (rq.stats as any)[k] as number;
    var have = p.stats[k as StatKey];
    if (have < need) out.push({ key: k, have: lifePoints(have), need: lifePoints(need), gap: (need - have) / ATLAS_NEAR_TOL.stat });
  }
  atlasNumMiss("diedAge", p.diedAtAge === null ? 0 : p.diedAtAge, rq.minDiedAge, rq.maxDiedAge, out);
  return out;
}

var ATLAS_NUM_LABEL: { [k: string]: string } = { close: "亲近", sync: "默契", memories: "共同回忆", rate: "默契率", together: "同框" };

/** 差的那一样写成半句话 */
function atlasReason(c: Content, m: AtlasMiss): string {
  var a = atlasOf(c);
  if (m.flag) return "就差" + a.says[m.flag];
  if (m.not) return "坏在" + a.says[m.not];
  if (m.key === "near") return "就差住得近些";
  if (m.key === "far") return "就差有一个走远";
  if (m.key === "diedAge") return "活到 " + m.have + " 岁，差 " + (m.need! - m.have!) + " 岁";
  if (m.key === "memories") return "共同回忆 " + m.have + " 段，要 " + m.need + " 段";
  if (m.key === "rate") return "默契率 " + m.have + "%，要 " + m.need + "%";
  if (m.key === "together") return "同框 " + m.have + " 回，要 " + m.need + " 回";
  if (STAT_LABEL[m.key!]) return STAT_LABEL[m.key!] + " " + m.have + " 分，要 " + m.need + " 分";
  return (ATLAS_NUM_LABEL[m.key!] || m.key) + " " + m.have + " 分，要 " + m.need + " 分";
}

/**
 * 在一张结局表里，排在这一世走到的那个前面的、只差一样的结局里挑最近的：没见过的优先，再按差得多少、再按表里的先后。
 * 返回 [结局, 差的那一样]，没有就是 null。
 */
function atlasPickNear<T extends { id: string; requires: any }>(c: Content, list: T[], got: string, seen: { [id: string]: number }, miss: (e: T) => AtlasMiss[]): [T, AtlasMiss] | null {
  var a = atlasOf(c);
  var best: [T, AtlasMiss] | null = null, bestKey = Infinity;
  for (var i = 0; i < list.length; i++) {
    var e = list[i];
    if (e.id === got) break;
    if (a.sad.indexOf(e.id) >= 0) continue;
    // 藏着的、还没见过的不说破（图鉴里也只是个空框）；走到过一回的，往后可以说
    if (a.hidden.indexOf(e.id) >= 0 && seen[e.id] === undefined) continue;
    var ms = miss(e);
    if (ms.length !== 1 || !(ms[0].gap <= 1)) continue;
    var key = (seen[e.id] === undefined ? 0 : 10) + ms[0].gap + i * 0.001;
    if (key < bestKey) { best = [e, ms[0]]; bestKey = key; }
  }
  return best;
}

/** 关口上差的那条线叫什么：一条路（option id）或一档名次（grade:<下标>，和目标条上的 id 一样） */
function atlasNearWhat(ev: LifeEvent, id: string): string | null {
  if (id.indexOf("grade:") === 0) {
    var gr = (ev.grades || [])[Number(id.slice(6))];
    return gr && gr.label ? gr.label : null;
  }
  var o = lifeFindOption(ev, id);
  return o ? o.text : null;
}

/** 一世走完：差一点就……（先关口，再两个人的结局，再一个人的一生） */
function atlasNear(s: LifeState, c: Content, seen: AtlasSeen): NearLine[] {
  var out: NearLine[] = [];
  // 关口：一辈子里差得最少的那一回
  var mBest: NearLine | null = null, mGap = 2;
  for (var i = 0; i < s.log.length; i++) {
    var en = s.log[i];
    if (en.kind !== "milestone" || !en.results) continue;
    for (var r = 0; r < ROLES.length; r++) {
      var res = en.results[ROLES[r]];
      var n = res && res.near;
      if (!n) continue;
      var g = atlasMilestoneGap(n);
      if (g <= 0 || g > 1 || g >= mGap) continue;
      var evId = en.events[ROLES[r]];
      var ev = evId ? lifeFindEventOrNull(c, evId) : null;
      var what = ev ? atlasNearWhat(ev, n.option) : null;
      if (!ev || !what) continue;
      mGap = g;
      mBest = {
        kind: "milestone", id: ev.id, role: ROLES[r],
        text: en.age + " 岁" + ev.title + "，" + s.persons![ROLES[r]].name + n.label + "差 " + (n.need - n.have) + " " + n.unit + "，没够上「" + what + "」。",
      };
    }
  }
  if (mBest) out.push(mBest);
  // 两个人的结局
  var st = lifeStats(s);
  var ending = s.ending!;
  var pr = atlasPickNear(c, c.endings.pair, ending.pair, seen.pair, function (e) { return atlasPairMiss(s, c, e, st); });
  if (pr) out.push({ kind: "pair", id: pr[0].id, text: "差一点就是「" + pr[0].title + "」：" + atlasReason(c, pr[1]) + "。" });
  // 一个人的一生：两个人里挑近的那个
  var lBest: NearLine | null = null, lKey = Infinity;
  for (var k = 0; k < ROLES.length; k++) {
    var p = s.persons![ROLES[k]];
    var lf = atlasPickNear(c, c.endings.lives, ending.lives[ROLES[k]], seen.lives, function (e) { return atlasLifeMiss(c, p, e); });
    if (!lf) continue;
    var lk = (seen.lives[lf[0].id] === undefined ? 0 : 10) + lf[1].gap;
    if (lk < lKey) {
      lKey = lk;
      lBest = { kind: "life", id: lf[0].id, role: ROLES[k], text: p.name + "差一点就是「" + lf[0].title + "」：" + atlasReason(c, lf[1]) + "。" };
    }
  }
  if (lBest) out.push(lBest);
  return out.slice(0, ATLAS_NEAR_LINES);
}

/** 内容里按 id 找事件，找不到不抛错（关口日志可能是旧内容下记的） */
function lifeFindEventOrNull(c: Content, id: string): LifeEvent | null {
  for (var i = 0; i < c.events.length; i++) if (c.events[i].id === id) return c.events[i];
  return null;
}

/**
 * 结局算出来、记进传承以后调用（lifeEndDay，legacyAbsorb 之后）：先按这一世之前见过的算「差一点」，再把这一世的结局记进图鉴。
 * 多调一回没关系：见过的只记头一回是第几世。
 */
function atlasAbsorb(s: LifeState, c: Content) {
  var lg = legacyOf(s);
  var seen = atlasSeenOf(lg);
  var life = s.life || lg.lives;
  var ending = s.ending!;
  // 「没见过」按这一世之前算：这一世头一回走到的，不算见过
  var before: AtlasSeen = { pair: {}, lives: {} };
  for (var a in seen.pair) if (seen.pair[a] < life) before.pair[a] = seen.pair[a];
  for (var b in seen.lives) if (seen.lives[b] < life) before.lives[b] = seen.lives[b];
  s.near = atlasNear(s, c, before);
  if (seen.pair[ending.pair] === undefined) seen.pair[ending.pair] = life;
  for (var r = 0; r < ROLES.length; r++) {
    var id = ending.lives[ROLES[r]];
    if (id && seen.lives[id] === undefined) seen.lives[id] = life;
  }
  var last = lg.past[lg.past.length - 1];
  if (last && last.life === life) {
    last.near = [];
    for (var i = 0; i < s.near.length && i < ATLAS_PAST_NEAR; i++) last.near.push(s.near[i].text);
  }
}

/**
 * 存档修复（legacyRepair 末尾调用）：有图鉴之前就走完的一世补算一回「差一点」；
 * 结局从内容里删了，图鉴里摘掉。
 */
function atlasRepair(s: LifeState, c: Content, notes: string[]) {
  var lg = legacyOf(s);
  if (s.phase === "ended" && s.ending && s.persons && s.near === undefined && s.left) {
    atlasAbsorb(s, c);
    notes.push("第 " + (s.life || 1) + " 世走完时还没有图鉴，补记");
  }
  if (!lg.seen) return;
  var known: { [id: string]: boolean } = {};
  for (var i = 0; i < c.endings.pair.length; i++) known[c.endings.pair[i].id] = true;
  for (var j = 0; j < c.endings.lives.length; j++) known[c.endings.lives[j].id] = true;
  for (var part in lg.seen) {
    var m = (lg.seen as any)[part] as { [id: string]: number };
    for (var id in m) if (!known[id]) { notes.push("legacy.seen " + id + " 已不存在，摘掉"); delete m[id]; }
  }
}
