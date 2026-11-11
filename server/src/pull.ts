// 关口上两个人之间的三件事：拉一把、分岔、重逢。纯函数，不依赖 Nakama。设计说明见 docs/DUET.md 第五节。
//
// 拉一把  一道关两个人都在场、商量着选路。一个够上了线还有富余，一个差几分：两个人都走这条，差的那个就跟着过去了。
//         看分的线：最多拉几分看默契（rules.bond.pullFrom / pullFull，默契在 syncSteadyFrom 到 syncSteadyFull 之间线性）。
//         要钱的线（积蓄、交得起）：真把钱塞过去，最多塞多少看亲近（pullMoney / pullMoneyClose）。看亲近的线不拉（两个人是同一个数）。
//         拉的人得真有富余：多出来的不少于对方差的（钱也一样，塞完自己还走得了这条）。
//         差的那个选了这条、对门却走了别的路：没拉上，按他自己够得着的路里线最高的那条走（pullMiss）。
// 重逢    上一道两个人都过的关走散了，这一道又走到一条路上：多一段回忆，亲近默契各添一点（rules.bond.reunion）。
//
// 状态：PendingEvent.pull（这一道关上谁拉谁，结算时用，结算完就没了）；LogEntry.gate（结算附带的几句话和数，旧客户端不认识也不碍事）。
// 协议不变：EVENT 和快照的 event 里多一个可选的 pulls，旧安装包照旧把差分的路灰着（那条路它选不了，也就不会选错）。

interface PullOffer {
  /** 谁拉 */
  by: Role;
  /** 差多少（看分的线按百分制，钱按块） */
  gap: number;
  unit: string;
  /** 这一回最多拉得动多少（同 gap 的口径） */
  reach: number;
  /** 看分的线上分够了、塞的是要交的钱（坐办公室头一年垫的那一笔）：揭晓时不画在分的尺子上，记进 gate.pay */
  pay?: boolean;
}

interface GateLine { text: string; role?: Role }

interface PendingEvent {
  /** 关口结算时谁被拉过去了：{ role: { optionId, by, gap, unit } }（pullResolve 填，lifeResolveEvent 读） */
  pull?: { [R in Role]?: { option: string; by: Role; gap: number; unit: string } };
}

interface LogEntry {
  /** 关口上两个人之间的事：拉一把（pull[role]）、没拉上（miss[role] 是他原来想走的路）、重逢（reunion 隔了几年），lines 是给人看的几句 */
  gate?: {
    pull?: { [R in Role]?: { by: Role; gap: number; unit: string } };
    /** 看分的线上对门替他交了钱（PullOffer.pay）：和 pull 分开放，旧客户端照 pull 画分的尺子会画错 */
    pay?: { [R in Role]?: { by: Role; gap: number } };
    miss?: { [R in Role]?: string };
    reunion?: number;
    lines: GateLine[];
  };
}

interface DuetContent {
  gate?: { pull: string; money: string; miss: string; reunion: string; pullMemory: string; moneyMemory: string; reunionMemory: string };
}

/** 几年：十五、三十（一百以内写汉字） */
function pullYears(n: number): string {
  if (n <= 10) return duetCount(n);
  if (n >= 100) return String(n);
  var t = Math.floor(n / 10), u = n % 10;
  return (t === 1 ? "" : DUET_NUM[t]) + "十" + (u ? DUET_NUM[u] : "");
}

/** 默契在 syncSteadyFrom 到 syncSteadyFull 之间：0~1（和考场托底同一把尺子） */
function pullSyncShare(c: Content, sync: number): number {
  var r = c.rules.bond;
  var from = typeof r.syncSteadyFrom === "number" ? r.syncSteadyFrom : 0;
  var full = typeof r.syncSteadyFull === "number" ? r.syncSteadyFull : 100;
  return lifeClamp((sync - from) / Math.max(1, full - from), 0, 1);
}

/** 看分的线最多拉几分（百分制） */
function pullReachPoints(c: Content, sync: number): number {
  var r = c.rules.bond;
  if (typeof r.pullFrom !== "number" || typeof r.pullFull !== "number") return 0;
  return Math.floor((r.pullFrom + (r.pullFull - r.pullFrom) * pullSyncShare(c, sync)) * 10 + 1e-6);
}

/**
 * 要钱的线最多塞多少块。上限按塞钱的那个人的家境（rules.bond.pullMoneyBy：清贫 / 小康 / 殷实，docs/MEANS.md 第九节）：
 * 殷实人家塞得多，家里断了供的、家道中落的（摘了 fam_rich）按小康。没写 pullMoneyBy 的旧内容都按 pullMoney
 */
function pullReachMoney(c: Content, close: number, giver: Person): number {
  var r = c.rules.bond;
  if (typeof r.pullMoney !== "number" || !r.pullMoneyClose) return 0;
  var cap = r.pullMoney;
  if (r.pullMoneyBy && r.pullMoneyBy.length === 3) {
    var tier = lifeHasFlag(giver, "fam_poor") ? 0 : lifeHasFlag(giver, "fam_rich") && !lifeHasFlag(giver, "fam_cut") ? 2 : 1;
    cap = r.pullMoneyBy[tier];
  }
  return Math.floor(cap * lifeClamp(close / r.pullMoneyClose, 0, 1));
}

/** 这条路要多少钱才走得了（积蓄线和交的钱里大的那个）；不看钱返回 0 */
function pullMoneyNeed(ev: LifeEvent, o: EventOption, p: Person): number {
  var w = lifeOptionWeights(ev, o);
  var need = lifeOptionCost(ev, o, p); // 年代挪过的线和钱（era.ts）
  var min = lifeOptionMin(o, p);
  if (min && w.money && !w.close) {
    var other = 0;
    for (var k in w) if (k !== "money") other++;
    if (other === 0) need = Math.max(need, min / (w.money as number));
  }
  return need;
}

/**
 * role 在这道关上走 o 要不要人拉、谁拉得动：拉不了（本来就够得着、差太多、对门不在这一关、对门也够不着、家里没那个条件……）返回 null。
 * swing 是两个人这一场的发挥（pe.swing）
 */
function pullOffer(s: LifeState, c: Content, ev: LifeEvent, pe: PendingEvent, role: Role, o: EventOption): PullOffer | null {
  if (ev.kind !== "milestone" || pe.roles.length !== 2) return null;
  var other = lifeOther(role);
  var me = s.persons![role], them = s.persons![other];
  if (!me.alive || !them.alive) return null;
  var swingMe = (pe.swing && pe.swing[role]) || 0;
  var swingThem = (pe.swing && pe.swing[other]) || 0;
  if (!lifeOptionLock(ev, o, me, swingMe, lifePairBond(s, role))) return null; // 自己走得了，不用拉
  if (lifeOptionLock(ev, o, them, swingThem, lifePairBond(s, other))) return null; // 对门自己都走不了
  var rq = o.requires || {};
  if (!lifeHasAll(me.flags, rq.flags) || !lifeHasNone(me.flags, rq.notFlags)) return null; // 不是给这户人家留的路，拉不进来
  var w = lifeOptionWeights(ev, o);
  if (w.close) return null; // 亲近是两个人同一个数
  var moneyNeed = pullMoneyNeed(ev, o, me);
  var scoreLine = !!o.min && !lifeScoreRaw(w);
  if (scoreLine) {
    // 看分的线：差的分和富余的分都按百分制往下取整（和锁上那句、揭晓卡上的数一样）
    var line = lifePoints(lifeOptionMin(o, me)); // 两个人同一年生，年代挪的线是同一条
    var gap = line - lifePoints(lifeScore(me, w) + swingMe);
    var spare = lifePoints(lifeScore(them, w) + swingThem) - line;
    var myCost = o.cost ? lifeOptionCost(ev, o, me) : 0;
    if (gap <= 0 && myCost > me.money) {
      // 分够了、差的是要交的钱（坐办公室头一年垫的那一笔，docs/MEANS.md 第十节）：对门把钱塞过来，塞完自己还交得起
      var cgap = Math.ceil(myCost - me.money - 1e-6);
      var cspare = Math.floor(them.money - lifeOptionCost(ev, o, them) + 1e-6);
      var creach = pullReachMoney(c, s.bond.close, them);
      if (cgap > creach || cspare < cgap) return null;
      return { by: other, gap: cgap, unit: "块", reach: creach, pay: true };
    }
    if (gap <= 0 || myCost > me.money) return null; // 分和钱都差的，一把拉不过来
    var reach = pullReachPoints(c, s.bond.sync);
    if (gap > reach || spare < gap) return null;
    return { by: other, gap: gap, unit: "分", reach: reach };
  }
  if (moneyNeed <= 0) return null;
  var mgap = Math.ceil(moneyNeed - me.money - 1e-6);
  var mspare = Math.floor(them.money - moneyNeed + 1e-6);
  var mreach = pullReachMoney(c, s.bond.close, them);
  if (mgap <= 0 || mgap > mreach || mspare < mgap) return null;
  return { by: other, gap: mgap, unit: "块", reach: mreach };
}

/** 这道关上每个人哪些路有人拉：{ role: { optionId: PullOffer } }。不是两个人的关返回 null */
function lifeMilestonePulls(s: LifeState, c: Content): { [R in Role]?: { [optionId: string]: PullOffer } } | null {
  var pe = s.world && s.world.event;
  if (!pe || pe.kind !== "milestone" || pe.roles.length !== 2) return null;
  var ev = lifeFindEvent(c, pe.eventId);
  var out: { [R in Role]?: { [optionId: string]: PullOffer } } = {};
  var any = false;
  for (var i = 0; i < pe.roles.length; i++) {
    var r = pe.roles[i];
    var m: { [optionId: string]: PullOffer } = {};
    for (var j = 0; j < ev.options.length; j++) {
      var off = pullOffer(s, c, ev, pe, r, ev.options[j]);
      if (off) { m[ev.options[j].id] = off; any = true; }
    }
    out[r] = m;
  }
  return any ? out : null;
}

/** 这条路这个人自己走不走得了，或者有人拉得动（worldChoose 和 worldMilestone 用） */
function pullOpen(s: LifeState, c: Content, ev: LifeEvent, pe: PendingEvent, role: Role, o: EventOption): boolean {
  if (!lifeOptionLock(ev, o, s.persons![role], (pe.swing && pe.swing[role]) || 0, lifePairBond(s, role))) return true;
  return !!pullOffer(s, c, ev, pe, role, o);
}

/** 自己够得着的路里线最高的那条（没拉上的时候走它）；一条都没有走兜底 */
function pullBestOwn(s: LifeState, ev: LifeEvent, pe: PendingEvent, role: Role): EventOption {
  var best: EventOption | null = null;
  for (var i = 0; i < ev.options.length; i++) {
    var o = ev.options[i];
    if (lifeOptionLock(ev, o, s.persons![role], (pe.swing && pe.swing[role]) || 0, lifePairBond(s, role))) continue;
    if (!best || (o.min || 0) > (best.min || 0)) best = o;
  }
  return best || lifeMilestoneFallback(ev);
}

/**
 * 关口结算前（lifeResolveEvent 一开头）：选了要人拉的路的，看对门是不是也走了这条。
 * 走了：拉过去（钱真塞过去），记进 pe.pull；没走：换成自己够得着的路，记进 entry.gate.miss。返回要写进日志的 gate（没事返回 null）
 */
function pullResolve(s: LifeState, c: Content, ev: LifeEvent, pe: PendingEvent): LogEntry["gate"] | null {
  if (ev.kind !== "milestone" || pe.roles.length !== 2) return null;
  var gate: LogEntry["gate"] = { lines: [] };
  var G = c.duet.gate;
  var offers: { [R in Role]?: PullOffer | null } = {};
  for (var i = 0; i < pe.roles.length; i++) {
    var r = pe.roles[i];
    var o = lifeFindOption(ev, pe.choices[r]!);
    offers[r] = o ? pullOffer(s, c, ev, pe, r, o) : null;
  }
  for (var k = 0; k < pe.roles.length; k++) {
    var role = pe.roles[k];
    var off = offers[role];
    var chosen = pe.choices[role]!;
    if (!off) continue;
    var by = off.by;
    var names = { a: s.persons![by].name, b: s.persons![role].name };
    var theirs = pe.choices[by] ? lifeFindOption(ev, pe.choices[by]!) : null;
    // 塞钱的那个人塞完还得交得起自己选的那条（同一条路上可能是线更高、更贵的那一条，比如四十岁争位子的「坐那把椅子」）
    var canGive = off.unit !== "块" || !theirs || s.persons![by].money - off.gap >= pullMoneyNeed(ev, theirs, s.persons![by]) - 1e-6;
    if (theirs && lifeRoad(ev, theirs.id) === lifeRoad(ev, chosen) && canGive) {
      if (off.unit === "块") {
        s.persons![by].money = Math.round((s.persons![by].money - off.gap) * 10) / 10;
        s.persons![role].money = Math.round((s.persons![role].money + off.gap) * 10) / 10;
      }
      if (!pe.pull) pe.pull = {};
      pe.pull[role] = { option: chosen, by: by, gap: off.gap, unit: off.unit };
      if (off.pay) {
        if (!gate.pay) gate.pay = {};
        gate.pay[role] = { by: by, gap: off.gap };
      } else {
        if (!gate.pull) gate.pull = {};
        gate.pull[role] = { by: by, gap: off.gap, unit: off.unit };
      }
      if (G) {
        gate.lines.push({ text: duetFill(off.unit === "块" ? G.money : G.pull, { a: names.a, b: names.b, x: off.gap }), role: by });
        var mem = off.unit === "块" ? G.moneyMemory : G.pullMemory;
        if (mem) s.memories.push({ title: mem, eventId: ev.id, turn: s.turn, age: lifeTimeAt(s.turn).age, vivid: 3 });
      }
    } else {
      var own = pullBestOwn(s, ev, pe, role);
      pe.choices[role] = own.id;
      if (!gate.miss) gate.miss = {};
      gate.miss[role] = chosen;
      if (G) gate.lines.push({ text: duetFill(G.miss, { a: names.a, b: names.b, o: own.text }), role: role });
    }
  }
  return gate.lines.length || gate.pull || gate.pay || gate.miss ? gate : null;
}

/**
 * 重逢：两个人都过的上一道关走散了（resonance 为 false），这一道又走到一条路上。在 lifeResolveEvent 判完共鸣以后调。
 * 返回隔了几年（不是重逢返回 0）
 */
function pullReunion(s: LifeState, c: Content, ev: LifeEvent, entry: LogEntry): number {
  if (ev.kind !== "milestone" || entry.resonance !== true) return 0;
  var prev: LogEntry | null = null;
  for (var i = s.log.length - 1; i >= 0; i--) {
    var e = s.log[i];
    if (e === entry || e.kind !== "milestone" || !e.results || !e.results.qing || !e.results.mei || e.resonance === null) continue;
    prev = e;
    break;
  }
  if (!prev || prev.resonance !== false) return 0;
  var years = Math.max(1, entry.age - prev.age);
  var G = c.duet.gate;
  if (c.rules.bond.reunion) lifeApplyBond(s, c, c.rules.bond.reunion);
  if (G && G.reunionMemory) s.memories.push({ title: G.reunionMemory, eventId: ev.id, turn: s.turn, age: entry.age, vivid: 3 });
  if (!entry.gate) entry.gate = { lines: [] };
  entry.gate.reunion = years;
  if (G) entry.gate.lines.push({ text: duetFill(G.reunion, { x: pullYears(years) }) });
  return years;
}

/**
 * 影子替拉人的那个选：对门（本人）选了一条要你拉的路、你也走得了，影子就跟着走这条。
 * 影子不替被拉的人去赌（lifeShadowChoose 照旧不选锁着的路）。返回选项 id 或 null
 */
function pullShadowFollow(s: LifeState, c: Content, ev: LifeEvent, pe: PendingEvent, role: Role): string | null {
  if (ev.kind !== "milestone" || pe.roles.length !== 2) return null;
  var other = lifeOther(role);
  var theirs = pe.choices[other];
  if (!theirs) return null;
  var o = lifeFindOption(ev, theirs);
  if (!o) return null;
  var off = pullOffer(s, c, ev, pe, other, o);
  if (!off || off.by !== role) return null;
  return o.id;
}

/**
 * 考前的目标条上：这条线我还差、到时候对门拉不拉得动（照现在两个人的数、不算手气）。
 * 只看两个人下一道是同一关的；拉不动返回 null。拉一把因此是押时间时的一个决定，不只是揭晓时的惊喜
 */
function pullGoalHint(s: LifeState, c: Content, role: Role, ev: LifeEvent, o: EventOption): PullOffer | null {
  var other = lifeOther(role);
  var them = s.persons![other];
  if (!them || !them.alive || lifeSeenIds(s, other)[ev.id] || !lifeMilestoneFor(ev, them)) return null;
  var pe: PendingEvent = { eventId: ev.id, kind: "milestone", roles: ["qing", "mei"], choices: {}, shadow: [] };
  return pullOffer(s, c, ev, pe, role, o);
}
