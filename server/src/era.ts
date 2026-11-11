// 年代大事（content/eras.yaml，说明见 docs/ERAS.md）
//
// 两个人「同岁」：同一年生。开局按种子抽一个出生年代（cohort），日历年 = 出生年 + 岁数。
// 每件年代大事到了那一年发生在所有人身上：打上 era_* 标记（行动、关口选项、事件、路线用 requires 读它），
// 挪关口的线（lines，build-content 编进选项的 eraLines）、乘工钱（wages），落到个别人头上的（hits：拆迁款、厂里的工钱打折）。
// 同一个活法，生在六十年代和生在〇〇后，三十岁时走得通的路和攒下的钱不一样。
//
// 年份只在引擎里算，从不给人看（GDD：不写年份）；给人看的是年代名（decades）。

interface EraDecade { from: number; name: string; look: Stage }

interface EraCohort {
  id: string;
  name: string;
  /** 出生那一年：只给引擎算日历年 */
  born: number;
  weight: number;
  note: string;
  /** 老存档、没写年代的测试用这个。恰好一个 */
  default?: boolean;
}

interface EraHit {
  requires: { flags?: string[]; notFlags?: string[]; minAge?: number; maxAge?: number };
  text: string;
  flags: string[];
  clears: string[];
  money: number;
  /** 积蓄乘这个数（1 = 不动） */
  savings: number;
}

interface EraEvent {
  id: string;
  year: number;
  /** 到这一年本件的标记自动摘掉（null = 不摘） */
  until: number | null;
  title: string;
  text: string;
  flags: string[];
  clears: string[];
  /** 关口线挪动，键 <关口id>.<选项id>，单位给人看的（百分制分 / 块）。引擎读的是编进选项里的 eraLines */
  lines: { [key: string]: number };
  /** 带着本件标记、又带着键里这个标记的人，日程工钱乘这个数 */
  wages: { [flag: string]: number };
  hits: EraHit[];
}

interface EraContent { decades: EraDecade[]; cohorts: EraCohort[]; events: EraEvent[] }

interface Content { eras: EraContent }

/** build-content 把 eras.yaml 的 lines 编进关口选项：带着 flags 全部的人，这条线挪 d（和 min 同一个单位） */
interface EventOption { eraLines?: { flags: string[]; d: number }[] }

interface LifeState {
  /** 出生年代 id（content/eras.yaml cohorts） */
  cohort?: string;
  /** 已经发生过的年代大事 id */
  eras?: string[];
}

interface EraLogInfo { id: string; title: string; text: string; decade: string; hits: { [R in Role]?: string } }

interface LogEntry { era?: EraLogInfo }

// ---------- 出生年代 ----------

/** 按种子挑出生年代。用自己的一串随机数，不动 s.rng：老测试同一个种子走出来的人生不变 */
function eraPickCohort(c: Content, seed: number): string {
  var list = c.eras ? c.eras.cohorts : [];
  if (!list.length) return "";
  var st = { rng: (seed ^ 0x5bd1e995) | 0 };
  lifeRand(st);
  var pick = lifePickWeighted(st, list, function (x) { return x.weight; });
  return pick ? pick.id : list[0].id;
}

/** 再来一世：按种子抽，抽到和上一世同一个年代就往后挪一个。同样两个人，换一个年代再活一回 */
function eraRebirthCohort(c: Content, seed: number, last: string | undefined): string {
  var id = eraPickCohort(c, seed);
  var list = c.eras ? c.eras.cohorts : [];
  if (id !== last || list.length < 2) return id;
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[(i + 1) % list.length].id;
  return id;
}

function eraDefaultCohort(c: Content): EraCohort | null {
  var list = c.eras ? c.eras.cohorts : [];
  for (var i = 0; i < list.length; i++) if (list[i].default) return list[i];
  return list.length ? list[0] : null;
}

function eraCohort(s: LifeState, c: Content): EraCohort | null {
  var list = c.eras ? c.eras.cohorts : [];
  for (var i = 0; i < list.length; i++) if (list[i].id === s.cohort) return list[i];
  return eraDefaultCohort(c);
}

/** 今天（或给定岁数那年）的日历年。没有年代内容时返回 0 */
function eraYear(s: LifeState, c: Content, age?: number): number {
  var co = eraCohort(s, c);
  if (!co) return 0;
  return co.born + (age === undefined ? lifeTimeAt(s.turn).age : age);
}

function eraDecade(c: Content, year: number): EraDecade | null {
  var list = c.eras ? c.eras.decades : [];
  var out: EraDecade | null = null;
  for (var i = 0; i < list.length; i++) if (list[i].from <= year) out = list[i];
  return out;
}

/** 给客户端看的：出生年代、现在是哪个年代、街景用哪一套 */
function eraView(s: LifeState, c: Content): { cohort: { id: string; name: string; note: string } | null; era: { decade: string; look: string } | null } {
  var co = eraCohort(s, c);
  if (!co) return { cohort: null, era: null };
  var d = eraDecade(c, eraYear(s, c));
  return { cohort: { id: co.id, name: co.name, note: co.note }, era: d ? { decade: d.name, look: d.look } : null };
}

// ---------- 线和工钱 ----------

/** 这个人眼前这条线：内容里写的 min，加上他身上年代标记挪的那一截。没有线（0 / 不写）原样返回 */
function lifeOptionMin(o: EventOption, p: Person): number {
  var m = o.min || 0;
  if (!m || !o.eraLines) return m;
  for (var i = 0; i < o.eraLines.length; i++) if (lifeHasAll(p.flags, o.eraLines[i].flags)) m += o.eraLines[i].d;
  return Math.max(0.01, Math.round(m * 100) / 100);
}

/** 看积蓄的线挪了，要花的钱跟着挪（买房线 200、花 200：房价涨了，线和要掏的钱一起涨） */
function lifeOptionCost(ev: LifeEvent, o: EventOption, p: Person): number {
  var cost = o.cost || 0;
  if (!cost || !o.min || !o.eraLines || !lifeOptionWeights(ev, o).money) return cost;
  return Math.max(0, Math.round((cost + lifeOptionMin(o, p) - o.min) * 10) / 10);
}

/** 年代给这个人的工钱乘数 */
function eraWageFactor(c: Content, p: Person): number {
  var f = 1;
  var evs = c.eras ? c.eras.events : [];
  for (var i = 0; i < evs.length; i++) {
    var ev = evs[i];
    if (!ev.flags.length || !lifeHasAll(p.flags, ev.flags)) continue;
    for (var k in ev.wages) if (lifeHasFlag(p, k)) f *= ev.wages[k];
  }
  return f;
}

// ---------- 大事发生 ----------

function eraRemoveFlags(p: Person, flags: string[]) {
  if (!flags.length) return;
  p.flags = p.flags.filter(function (f) { return flags.indexOf(f) < 0; });
}

function eraHitFor(ev: EraEvent, p: Person, age: number): EraHit | null {
  for (var i = 0; i < ev.hits.length; i++) {
    var rq = ev.hits[i].requires || {};
    if (lifeInRange(age, rq.minAge, rq.maxAge) && lifeHasAll(p.flags, rq.flags) && lifeHasNone(p.flags, rq.notFlags)) return ev.hits[i];
  }
  return null;
}

/** 一件大事落下来。quiet：生之前的事，只打标记，不吃 hits、不记长卷 */
function eraApply(s: LifeState, c: Content, ev: EraEvent, quiet: boolean): EraLogInfo {
  if (!s.eras) s.eras = [];
  s.eras.push(ev.id);
  var age = lifeTimeAt(s.turn).age;
  var d = eraDecade(c, eraYear(s, c));
  var info: EraLogInfo = { id: ev.id, title: ev.title, text: ev.text, decade: d ? d.name : "", hits: {} };
  for (var i = 0; i < ROLES.length; i++) {
    var p = s.persons ? s.persons[ROLES[i]] : null;
    if (!p || !p.alive) continue;
    eraRemoveFlags(p, ev.clears);
    lifeAddFlags(p, ev.flags);
    if (quiet) continue;
    var h = eraHitFor(ev, p, age);
    if (!h) continue;
    eraRemoveFlags(p, h.clears);
    lifeAddFlags(p, h.flags);
    if (h.savings !== 1) p.money = Math.round(p.money * h.savings * 10) / 10;
    if (h.money) p.money = Math.max(0, Math.round((p.money + h.money) * 10) / 10);
    info.hits[ROLES[i]] = h.text;
  }
  return info;
}

/** 到了 until 的年份：本件的标记摘掉（后来的事又打上的不管：同一个标记只由一件事发） */
function eraExpire(s: LifeState, c: Content, year: number) {
  var evs = c.eras ? c.eras.events : [];
  for (var i = 0; i < evs.length; i++) {
    var ev = evs[i];
    if (ev.until === null || ev.until > year || !s.eras || s.eras.indexOf(ev.id) < 0) continue;
    for (var r = 0; r < ROLES.length; r++) {
      var p = s.persons ? s.persons[ROLES[r]] : null;
      if (p) eraRemoveFlags(p, ev.flags);
    }
  }
}

/** 按年份排好的、到今年为止还没发生的大事 */
function eraDue(s: LifeState, c: Content, year: number): EraEvent[] {
  var evs = c.eras ? c.eras.events : [];
  var done = s.eras || [];
  var out = evs.filter(function (e) { return e.year <= year && done.indexOf(e.id) < 0; });
  out.sort(function (a, b) { return a.year - b.year; });
  return out;
}

/** 人生开始（两人都确认那一刻）：生之前和三岁那年以前的事悄悄生效 */
function eraStart(s: LifeState, c: Content) {
  if (!c.eras || !c.eras.cohorts.length) return;
  if (!s.cohort) s.cohort = eraPickCohort(c, s.seed);
  if (!s.eras) s.eras = [];
  var year = eraYear(s, c);
  var due = eraDue(s, c, year);
  for (var i = 0; i < due.length; i++) {
    eraApply(s, c, due[i], true);
    eraExpire(s, c, due[i].year);
  }
  eraExpire(s, c, year);
}

/** 新的一天（s.turn 已经 +1）：过了期的摘掉，到了年份的大事发生，各记一条 kind "era" 的长卷 */
function eraTick(s: LifeState, c: Content, out: LogEntry[]) {
  if (!c.eras || !c.eras.cohorts.length || !s.persons) return;
  var year = eraYear(s, c);
  var due = eraDue(s, c, year);
  for (var i = 0; i < due.length; i++) {
    // 中年三年一天、老年五年一天：中间几年的事按发生的先后排，前一件的 until 先过期
    eraExpire(s, c, due[i].year);
    var info = eraApply(s, c, due[i], false);
    var e = lifeEntry(s, "era", info.title + "。" + info.text);
    e.era = info;
    out.push(e);
    s.log.push(e);
  }
  eraExpire(s, c, year);
}

/** 存档修复：年代不认识了换回默认；老存档没记过发生了哪些大事，按今天的年份悄悄补上（不弹卡、不吃 hits） */
function eraRepair(s: LifeState, c: Content, notes: string[]) {
  if (!c.eras || !c.eras.cohorts.length) return;
  if (s.cohort && !lifeHasId(c.eras.cohorts, s.cohort)) {
    notes.push("cohort " + s.cohort + " 已不存在，换成默认");
    s.cohort = undefined;
  }
  if (s.eras) {
    var before = s.eras.length;
    s.eras = s.eras.filter(function (id) { return lifeHasId(c.eras.events, id); });
    if (s.eras.length !== before) notes.push("eras 摘掉 " + (before - s.eras.length) + " 件已不存在的大事");
  }
  if (s.phase === "life" && s.persons && !s.eras) {
    if (!s.cohort) s.cohort = (eraDefaultCohort(c) || c.eras.cohorts[0]).id;
    eraStart(s, c);
    notes.push("eras 按 " + s.cohort + " 补上 " + s.eras!.length + " 件");
  }
}

/** 今天的年份该有的年代标记都在：还没发生的悄悄补上（不弹卡、不吃 hits），过了期的摘掉 */
function eraSync(s: LifeState, c: Content) {
  if (!c.eras || !c.eras.cohorts.length || !s.persons || !s.eras) return;
  var year = eraYear(s, c);
  var due = eraDue(s, c, year);
  for (var i = 0; i < due.length; i++) {
    eraExpire(s, c, due[i].year);
    eraApply(s, c, due[i], true);
  }
  eraExpire(s, c, year);
}
