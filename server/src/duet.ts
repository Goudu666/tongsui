// 接话：两个人之间一抛一接的规则。纯函数，不依赖 Nakama。设计说明见 docs/DUET.md。
//
// 默契不是选一样，是一个抛、一个接得住。这一轮做三件事，都长在默契事件（mirror）上：
//   搭上了  两人选得不一样，但正好是一个出招、一个接着（content/duet.yaml 的 catches）→ 也算默契，也留回忆
//   猜 TA   选完自己的，再猜对门选了什么。猜中是「懂」，有方向：青懂梅，不等于梅懂青
//   回话    一方不在时影子替他选过的事先欠着，本人回来后补答；可能补成共鸣，也接着教影子
//
// 状态：LifeState.duet（长期，可选字段，随快照发给客户端，不放当下的秘密）、PendingEvent.guess（当下的猜测，不外发）、
// LogEntry.duet（结算附带的数据，旧客户端可以不认识）。不改 bond 的含义，不用人生主线的随机数。

/** 欠着的话过了这么多个日子就接不上了（和回忆褪色一级的间隔一样） */
var DUET_ECHO_KEEP = 8;
/** 每人最多欠几句，再多就把最早的那句放下 */
var DUET_OWED_MAX = 6;

// ---------- 类型 ----------

interface DuetCatch {
  pair: string[];
  text: string;
  memory: string | null;
  bond: Partial<Bond>;
  flags: string[];
}

interface DuetContent {
  lines: { knew_both_same: string; knew_both_diff: string; knew_one: string; knew_none: string; knew_single: string };
  echo: { ask: string; res: string; catch: string; miss: string; like: string; unlike: string; knew: string; kept: string; told: string };
  epitaph: { know: string; shadow: string; last: { minRate: number; text: string }[] };
}

/** 影子替他选过、本人还没回话的一件事 */
interface DuetOwed {
  turn: number;
  age: number;
  label: string;
  eventId: string;
  /** 影子替他选的 */
  shadow: string;
  /** 对门当时选的 */
  partner: string;
  /** 对门当时猜他会选的（没猜是 null） */
  guess: string | null;
  /** 当时结算成了什么 */
  outcome: "res" | "catch" | "miss";
}

interface DuetState {
  /** 猜 TA：[猜中, 猜过] */
  know: { [R in Role]: number[] };
  /** 影子像不像本人：[选得一样, 回过话] */
  like: { [R in Role]: number[] };
  owed: { [R in Role]: DuetOwed[] };
  /** 一生的闲话。每次有变化就重算，结局时客户端直接用 */
  epitaph: string[];
}

interface LifeEvent { catches?: DuetCatch[] }
interface Content { duet: DuetContent }
interface LifeState { duet?: DuetState }
interface PendingEvent { guess?: Choices }
interface LogEntry { duet?: any }

// ---------- 小工具 ----------

/** 旧存档没有 duet：用到时才建（可选字段，不需要升存档版本） */
function duetOf(s: LifeState): DuetState {
  if (!s.duet) s.duet = { know: { qing: [0, 0], mei: [0, 0] }, like: { qing: [0, 0], mei: [0, 0] }, owed: { qing: [], mei: [] }, epitaph: [] };
  return s.duet;
}

function duetFill(tpl: string, vars: { [k: string]: string | number }): string {
  var out = tpl;
  for (var k in vars) out = out.split("{" + k + "}").join(String(vars[k]));
  return out;
}

var DUET_NUM = ["零", "一", "两", "三", "四", "五", "六", "七", "八", "九", "十"];

function duetCount(n: number): string {
  return n >= 0 && n <= 10 ? DUET_NUM[n] : String(n);
}

function duetFindCatch(ev: LifeEvent, a: string | undefined, b: string | undefined): DuetCatch | null {
  var list = ev.catches;
  if (!list || !a || !b || a === b) return null;
  for (var i = 0; i < list.length; i++) {
    var p = list[i].pair;
    if ((p[0] === a && p[1] === b) || (p[0] === b && p[1] === a)) return list[i];
  }
  return null;
}

function duetHasMemory(s: LifeState, title: string): boolean {
  for (var i = 0; i < s.memories.length; i++) if (s.memories[i].title === title) return true;
  return false;
}

// ---------- 搭上了 ----------

/** lifeResolveEvent 里，mirror 事件先问这里：两人选得不一样，但是不是一个抛、一个接？是就按「搭上了」结算，返回 true */
function duetCatch(s: LifeState, pe: PendingEvent, ev: LifeEvent, entry: LogEntry): boolean {
  var hit = duetFindCatch(ev, pe.choices.qing, pe.choices.mei);
  if (!hit) return false;
  entry.resonance = true; // 接住了也算默契，计入默契率
  entry.text = hit.text;
  entry.duet = { outcome: "catch" };
  lifeApplyBond(s, hit.bond);
  lifeAddFlags(s.persons!.qing, hit.flags);
  lifeAddFlags(s.persons!.mei, hit.flags);
  if (hit.memory) s.memories.push({ title: hit.memory, eventId: ev.id, turn: s.turn, age: entry.age, vivid: 3 });
  return true;
}

// ---------- 猜 TA ----------

/** 默契事件里猜对门选了什么。跟自己的选择一起发来（CHOOSE 的 guess 字段）；不合法的猜测当没猜 */
function duetGuess(s: LifeState, c: Content, role: Role, optionId: any) {
  var w = s.world;
  if (typeof optionId !== "string" || !w || !w.event || w.event.kind !== "mirror" || w.event.roles.indexOf(role) < 0) return;
  if (!lifeFindOption(lifeFindEvent(c, w.event.eventId), optionId)) return;
  if (!w.event.guess) w.event.guess = {};
  w.event.guess[role] = optionId;
}

/** 事件结算之后（worldChoose 里调用）：猜 TA 的对错；影子替选的记一笔欠着 */
function duetAfterEvent(s: LifeState, c: Content, pe: PendingEvent, entry: LogEntry) {
  if (pe.kind !== "mirror" || pe.roles.length !== 2) return;
  var d = duetOf(s);
  var info: any = entry.duet || (entry.duet = { outcome: entry.resonance ? "res" : "miss" });
  var guesses = pe.guess || {};
  var same = pe.choices.qing === pe.choices.mei;
  info.guess = { qing: null, mei: null };
  info.knew = { qing: null, mei: null };
  var guessed = 0, knew: Role[] = [];
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    var g = guesses[r];
    // 影子不猜；本人猜的才算
    if (typeof g !== "string" || pe.shadow.indexOf(r) >= 0) continue;
    var hit = g === pe.choices[lifeOther(r)];
    info.guess[r] = g;
    info.knew[r] = hit;
    guessed += 1;
    d.know[r][1] += 1;
    if (hit) { knew.push(r); d.know[r][0] += 1; lifeApplyBond(s, { sync: 1 }); }
  }
  var L = c.duet.lines;
  var line: string | null = null;
  if (guessed === 2) {
    if (knew.length === 2) {
      line = same ? L.knew_both_same : L.knew_both_diff;
      if (!same) lifeApplyBond(s, { close: 1 }); // 选得不一样，但知根知底
    } else if (knew.length === 1) {
      line = duetFill(L.knew_one, { a: s.persons![knew[0]].name, b: s.persons![lifeOther(knew[0])].name });
    } else {
      line = L.knew_none;
    }
  } else if (knew.length === 1) {
    line = duetFill(L.knew_single, { a: s.persons![knew[0]].name });
  }
  info.line = line;

  // 影子替选的：这句话先悬着，等本人回来接（两个人都是影子就算了，没人在场）
  if (pe.shadow.length === 1) {
    var sr = pe.shadow[0], other = lifeOther(sr);
    var og = guesses[other];
    d.owed[sr].push({
      turn: s.turn, age: entry.age, label: entry.label, eventId: pe.eventId,
      shadow: pe.choices[sr]!, partner: pe.choices[other]!, guess: typeof og === "string" ? og : null, outcome: info.outcome,
    });
    while (d.owed[sr].length > DUET_OWED_MAX) d.owed[sr].shift();
    info.owed = sr;
  }
  duetPrune(s);
  d.epitaph = duetEpitaph(s, c);
}

// ---------- 回话 ----------

/** 欠着的话，过了日子就接不上了 */
function duetPrune(s: LifeState) {
  var d = duetOf(s);
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    d.owed[r] = d.owed[r].filter(function (o) { return s.turn - o.turn < DUET_ECHO_KEEP; });
  }
}

/** 本人回来了，补答影子替他选过的那件事。optionId 不是字符串表示「不提了」 */
function duetEcho(s: LifeState, c: Content, role: Role, turn: number, optionId: any): { error: string | null; entry: LogEntry | null } {
  if (s.phase !== "life" || !s.persons || !s.persons[role].alive) return { error: "现在回不了话", entry: null };
  var d = duetOf(s);
  duetPrune(s);
  var list = d.owed[role];
  var idx = -1;
  for (var i = 0; i < list.length; i++) if (list[i].turn === turn) idx = i;
  if (idx < 0) return { error: "这句话已经接不上了", entry: null };
  var o = list[idx];
  // 「不提了」只认 null / 不带；别的类型是发错了，不能把这句话就这么丢掉
  if (optionId === null || optionId === undefined) { list.splice(idx, 1); return { error: null, entry: null }; }
  if (typeof optionId !== "string") return { error: "没有这个选项", entry: null };
  var ev: LifeEvent;
  try { ev = lifeFindEvent(c, o.eventId); } catch (e) { list.splice(idx, 1); return { error: "那件事已经记不清了", entry: null }; }
  var opt = lifeFindOption(ev, optionId);
  if (!opt) return { error: "没有这个选项", entry: null };
  list.splice(idx, 1);

  var other = lifeOther(role);
  var me = s.persons[role];
  // 本人的回答接着教影子：它就是这么学会你的
  for (var t = 0; t < opt.tags.length; t++) me.tags[opt.tags[t]] = (me.tags[opt.tags[t]] || 0) + 1;

  var E = c.duet.echo;
  var gap = duetCount(Math.max(1, s.turn - o.turn)) + "个日子";
  var outcome: "res" | "catch" | "miss";
  var text: string, memory: string | null = null, flags: string[] = [];
  var lines: string[] = [];
  var caught = duetFindCatch(ev, opt.id, o.partner);
  if (opt.id === o.partner) {
    outcome = "res";
    var res = ev.resonance && ev.resonance[opt.id];
    text = res ? res.text : "你们选了同一个答案。";
    memory = res && res.memory ? res.memory : null;
    flags = res ? res.flags : [];
    lines.push(duetFill(E.res, { gap: gap }));
  } else if (caught) {
    outcome = "catch";
    text = caught.text;
    memory = caught.memory;
    flags = caught.flags;
    lines.push(duetFill(E.catch, { gap: gap }));
  } else {
    outcome = "miss";
    text = E.miss;
  }
  // 当时没接上、现在接上了：补一段回忆（补的，鲜明度低一级）
  if (outcome !== "miss" && o.outcome === "miss") {
    lifeApplyBond(s, { sync: 2, close: 1 });
    lifeAddFlags(s.persons.qing, flags);
    lifeAddFlags(s.persons.mei, flags);
    if (memory && !duetHasMemory(s, memory)) s.memories.push({ title: memory, eventId: ev.id, turn: o.turn, age: o.age, vivid: 2 });
    // 长卷上当时那一笔也改过来：这一回算接上了，计入默契率
    for (var li = s.log.length - 1; li >= 0; li--) {
      var past = s.log[li];
      if (past.turn < o.turn) break;
      if (past.kind === "mirror" && past.turn === o.turn && past.events.qing === o.eventId) {
        past.resonance = true;
        if (!past.duet) past.duet = { outcome: "miss" };
        past.duet.mended = outcome;
        break;
      }
    }
  }

  var like = opt.id === o.shadow;
  d.like[role][1] += 1;
  if (like) d.like[role][0] += 1;
  var shadowOpt = lifeFindOption(ev, o.shadow);
  lines.push(like ? E.like : duetFill(E.unlike, { o: shadowOpt ? shadowOpt.text : o.shadow }));

  // 对门当时猜的，现在按本人的回答重新算
  var partnerKnew: boolean | null = null;
  if (o.guess !== null) {
    partnerKnew = o.guess === opt.id;
    var wasHit = o.guess === o.shadow;
    if (partnerKnew && !wasHit) { d.know[other][0] += 1; lifeApplyBond(s, { sync: 1 }); }
    if (!partnerKnew && wasHit) d.know[other][0] = Math.max(0, d.know[other][0] - 1);
    if (partnerKnew && !like) lines.push(duetFill(E.knew, { b: s.persons[other].name }));
  }

  var entry = lifeEntry(s, "solo", text);
  entry.events[role] = ev.id;
  entry.choices[role] = opt.id;
  entry.duet = {
    echo: true, role: role, outcome: outcome, was: o.outcome, like: like, shadow: o.shadow, partner: o.partner,
    partnerKnew: partnerKnew, turn: o.turn, label: o.label, lines: lines,
  };
  s.log.push(entry);
  d.epitaph = duetEpitaph(s, c);
  return { error: null, entry: entry };
}

// ---------- 一生的闲话 ----------

/** 谁懂谁、影子像不像、话有没有掉地上。接在人生长卷的题词后面 */
function duetEpitaph(s: LifeState, c: Content): string[] {
  var d = duetOf(s);
  var a = s.persons!.qing.name, b = s.persons!.mei.name;
  var E = c.duet.epitaph;
  var out: string[] = [];
  if (d.know.qing[1] + d.know.mei[1] > 0) out.push(duetFill(E.know, { a: a, b: b, x: d.know.qing[0], y: d.know.mei[0] }));
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    if (d.like[r][1] > 0) out.push(duetFill(E.shadow, { a: s.persons![r].name, x: d.like[r][1], y: d.like[r][0] }));
  }
  var st = lifeStats(s);
  if (st.mirrors > 0) {
    for (var m = 0; m < E.last.length; m++) if (st.rate >= E.last[m].minRate) { out.push(E.last[m].text); break; }
  }
  return out;
}

// ---------- 发给客户端的样子 ----------

/** 快照里的 duet：自己欠着的话可以看，但不带「对门当时猜我会选什么」——那句要等回完话才揭晓 */
function duetView(s: LifeState, role: Role): any {
  var d: DuetState = s.duet || { know: { qing: [0, 0], mei: [0, 0] }, like: { qing: [0, 0], mei: [0, 0] }, owed: { qing: [], mei: [] }, epitaph: [] };
  var owed: any = { qing: [], mei: [] };
  owed[role] = d.owed[role].filter(function (o) { return s.turn - o.turn < DUET_ECHO_KEEP; }).map(function (o) {
    return { turn: o.turn, age: o.age, label: o.label, eventId: o.eventId, shadow: o.shadow, partner: o.partner, outcome: o.outcome };
  });
  return { know: d.know, like: d.like, owed: owed, epitaph: d.epitaph, keep: DUET_ECHO_KEEP };
}

/**
 * 快照里的日志：我还欠着话的那几天，把那条默契事件的猜测（guess / knew / line）摘掉。
 * 不改存档里的日志，只在要摘的那几条上做一份浅拷贝。
 */
function duetLogView(s: LifeState, role: Role, log: LogEntry[]): LogEntry[] {
  var owed = s.duet ? s.duet.owed[role] : [];
  if (!owed || owed.length === 0) return log;
  return log.map(function (e) {
    if (e.kind !== "mirror" || !e.duet) return e;
    var mine = false;
    for (var i = 0; i < owed.length; i++) if (owed[i].turn === e.turn && owed[i].eventId === e.events.qing) mine = true;
    if (!mine) return e;
    var copy: any = {};
    for (var k in e) copy[k] = (e as any)[k];
    copy.duet = { outcome: e.duet.outcome, owed: e.duet.owed };
    return copy;
  });
}

// ---------- 存档修复 ----------

/** 剧情改了以后（save.ts 的 lifeRepair 调用）：欠着的话如果指向已经不存在的事件或选项，放下 */
function duetRepair(s: LifeState, c: Content, notes: string[]) {
  if (!s.duet) return;
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    var kept: DuetOwed[] = [];
    var list = s.duet.owed[r] || [];
    for (var j = 0; j < list.length; j++) {
      var o = list[j];
      var ok = lifeHasId(c.events, o.eventId);
      if (ok) {
        var ev = lifeFindEvent(c, o.eventId);
        ok = !!lifeFindOption(ev, o.shadow) && !!lifeFindOption(ev, o.partner);
        if (ok && o.guess !== null && !lifeFindOption(ev, o.guess)) o.guess = null;
      }
      if (ok) kept.push(o);
      else notes.push("duet.owed." + r + " " + o.eventId + " 已对不上，放下");
    }
    s.duet.owed[r] = kept;
  }
  var w = s.world;
  if (w && w.event && w.event.guess) {
    var pev = lifeFindEvent(c, w.event.eventId);
    for (var k = 0; k < ROLES.length; k++) {
      var g = w.event.guess[ROLES[k]];
      if (g && !lifeFindOption(pev, g)) delete w.event.guess[ROLES[k]];
    }
  }
}
