// 成长、衰老、检定、寿命、亲近的数值规则。数都在 content/rules.yaml，设计说明见 docs/GROWTH.md。
// 纯函数，sim.ts / world.ts 在几个固定的地方调用：
//   lifeApplySelf  → growthApply      长属性（经历 × 年纪 × 底子）
//   lifeApplyBond  → growthBond       亲近和默契越高越难涨
//   lifeResolveEvent → growthCheck    选项上挂的检定
//   lifeEndDay     → growthDayEnd     记心气、亲近变淡、岁数不饶人
//                  → growthLimit      大限

/** 这次成长发生在什么场合：哪个阶段、是事件还是日常行动 */
interface GrowCtx {
  c: Content;
  stage: Stage;
  /** 事件里的 +1 和行动里的 +0.3 不是一个量级，各有各的系数 */
  scale: number;
}

function growthCtx(s: LifeState, c: Content, source: "event" | "action"): GrowCtx {
  var stage = lifeTimeAt(s.turn).stage;
  // 一个被记住的日子代表的时间越长（少年半年、成年一年），那天怎么过算得越重：每道关都有得拼（rules.yaml → growth.turnWeight）
  var tw = c.rules.growth.turnWeight ? c.rules.growth.turnWeight[stage] : 1;
  return { c: c, stage: stage, scale: source === "event" ? c.rules.growth.eventScale : c.rules.growth.actionScale * (typeof tw === "number" ? tw : 1) };
}

/** 年纪：这个人在这个阶段，这项属性长得多快 */
function growthPlasticity(c: Content, p: Person, stage: Stage, k: StatKey): number {
  var g = c.rules.growth;
  var v = g.plasticity[stage][k];
  if (lifeHasFlag(p, "tal_plain")) v *= g.plainBonus;
  return legacyPlasticity(c, p, stage, k, v); // 大器晚成、老灵魂
}

/**
 * 底子：这个人这项属性「本来该在哪」。出生时的属性只算一部分（bornWeight），其余按人人一样的平均数算，
 * 所以出身好的人起步高、上头的空间小，出身一般的人起步低、追得上来：出身决定从哪开始，活法决定走到哪。
 */
function growthBase(c: Content, p: Person, k: StatKey): number {
  var born = p.born ? p.born[k] : p.stats[k];
  var mid = c.rules.roll.budget / 4;
  // 规则表里没写时按 1 算（出身全算，和加这个参数之前一样），免得旧内容包算出 NaN
  var w = typeof c.rules.growth.bornWeight === "number" ? c.rules.growth.bornWeight : 1;
  return mid + (born - mid) * w;
}

/** 上头的空间：比底子最多高出多少。可以按阶段写（少年以后放宽，每道关都还有得长），老内容写一个数 */
function growthRoom(c: Content, stage: Stage): number {
  var r = c.rules.growth.room as any;
  return typeof r === "number" ? r : r[stage];
}

/** 给一个人长（或掉）一项属性。raw 是内容里写的数，返回实际变化 */
function growthApply(p: Person, k: StatKey, raw: number, g: GrowCtx): number {
  var before = p.stats[k];
  var v = raw * g.scale;
  if (raw > 0) {
    // 底子：离底子越远，长得越慢
    var room = lifeClamp(1 - (before - growthBase(g.c, p, k)) / (growthRoom(g.c, g.stage) + legacyRoom(g.c, p, g.stage)), g.c.rules.growth.floor, 1);
    v *= growthPlasticity(g.c, p, g.stage, k) * room;
    if (p.active && (k === "body" || k === "mind")) p.active[k] = true;
  }
  p.stats[k] = lifeClamp(Math.round((before + v) * 1000) / 1000, 0, 10);
  return p.stats[k] - before;
}

/**
 * 考场上手气差的时候，默契替你托回几成（0~syncSteady）。只用在坏手气上，好手气不加。
 * 默契在 syncSteadyFrom 以下不托，到 syncSteadyFull 托满；老内容没写这两个数就按默契 / 100 算（原来的算法）
 */
function growthSteadyShare(c: Content, sync: number): number {
  var r = c.rules.bond;
  if (typeof r.syncSteadyFrom !== "number" || typeof r.syncSteadyFull !== "number") return (sync / 100) * r.syncSteady;
  return lifeClamp((sync - r.syncSteadyFrom) / (r.syncSteadyFull - r.syncSteadyFrom), 0, 1) * r.syncSteady;
}

/** 亲近、默契：越高越难涨；往下掉不打折 */
function growthBond(s: LifeState, c: Content, d: Partial<Bond>) {
  var r = c.rules.bond;
  if (d.close) {
    var dc = d.close;
    if (dc > 0) dc *= r.closeScale * Math.max(r.closeFloor, 1 - s.bond.close / r.closeSoft);
    s.bond.close = lifeClamp(Math.round((s.bond.close + dc) * 100) / 100, -20, 100);
  }
  if (d.sync) {
    var ds = d.sync;
    if (ds > 0) ds *= Math.max(r.syncFloor, 1 - s.bond.sync / r.syncSoft);
    s.bond.sync = lifeClamp(Math.round((s.bond.sync + ds) * 100) / 100, 0, 100);
  }
  if (d.distance) s.bond.distance = lifeClamp(s.bond.distance + d.distance, 0, 5);
}

// ---------- 检定 ----------

function growthFindCheck(c: Content, eventId: string, optionId: string): Check | null {
  for (var i = 0; i < c.checks.length; i++) if (c.checks[i].event === eventId && c.checks[i].option === optionId) return c.checks[i];
  return null;
}

/** 成功率。partner 不为空时是默契事件：sameOption 表示两人选了同一项（搭把手） */
function growthCheckChance(c: Content, ck: Check, me: Person, partner: Person | null, sameOption: boolean): { p: number; help: boolean } {
  var r = c.rules.check;
  var eff = me.stats[ck.stat];
  var help = false;
  if (partner) {
    // 搭把手：两人选了同一项，按本事大的那个算，再多一点把握
    if (sameOption) {
      if (partner.stats[ck.stat] > eff) eff = partner.stats[ck.stat];
      eff += r.help;
      help = true;
    }
  }
  var p = r.base + (eff - ck.dc) * r.perPoint;
  if (ck.stat !== "luck") p += (me.stats.luck - 5) * r.luck;
  p += legacyCheckBonus(c, me); // 老灵魂
  return { p: lifeClamp(p, r.min, r.max), help: help };
}

/** 掷一次检定 */
function growthCheck(s: LifeState, c: Content, ck: Check, me: Person, partner: Person | null, sameOption: boolean): CheckResult {
  var ch = growthCheckChance(c, ck, me, partner, sameOption);
  var ok = lifeRand(s) < ch.p;
  return { stat: ck.stat, ok: ok, help: ch.help && ok, text: ok ? ck.pass : ck.fail.text };
}

/** 没成时的效果：检定表里写了就用写的，没写就是原来的效果去掉长属性的部分 */
function growthFailSelf(o: EventOption, ck: Check): SelfDelta {
  if (ck.fail.self) return ck.fail.self;
  var out: SelfDelta = {};
  for (var k in o.effects.self) {
    var v = (o.effects.self as any)[k] as number;
    var isStat = k === "body" || k === "mind" || k === "charm" || k === "luck";
    if (!(isStat && v > 0)) (out as any)[k] = v;
  }
  return out;
}

/**
 * 结算事件时调用：这个人选的这一项要是挂着检定，就掷一次，把结果记进日志。
 * 返回这一项实际生效的个人效果和标记（没挂检定就是选项原来的）。
 */
function growthResolveCheck(s: LifeState, c: Content, pe: PendingEvent, ev: LifeEvent, o: EventOption, role: Role, entry: LogEntry): { self: SelfDelta; flags: string[] } {
  var ck = growthFindCheck(c, ev.id, o.id);
  if (!ck) return { self: o.effects.self, flags: o.effects.flags };
  var me = s.persons![role];
  var other = s.persons![lifeOther(role)];
  var partner = pe.kind === "mirror" && other.alive ? other : null;
  var res = growthCheck(s, c, ck, me, partner, partner !== null && pe.choices[lifeOther(role)] === o.id);
  if (!entry.checks) entry.checks = {};
  entry.checks[role] = res;
  if (pe.kind === "solo") entry.text = res.text;
  if (res.ok) return { self: o.effects.self, flags: o.effects.flags };
  return { self: growthFailSelf(o, ck), flags: ck.fail.flags || o.effects.flags };
}

// ---------- 一个日子过完 ----------

/** 这个日子到下一个日子之间隔了几年（童年一个季节，老年五年） */
function growthYearsPerTurn(turn: number): number {
  var start = 0;
  for (var i = 0; i < STAGE_TABLE.length; i++) {
    var st = STAGE_TABLE[i];
    var turns = Math.round(st.years * st.turnsPerYear);
    if (turn < start + turns || i === STAGE_TABLE.length - 1) return 1 / st.turnsPerYear;
    start += turns;
  }
  return 1;
}

function growthAgingRate(table: number[][], age: number): number {
  var rate = 0;
  for (var i = 0; i < table.length; i++) if (age >= table[i][0]) rate = table[i][1];
  return rate;
}

/** 在 s.turn 还没 +1 的时候调用：记下今天的心情，亲近变淡，岁数不饶人 */
function growthDayEnd(s: LifeState, c: Content) {
  var t = lifeTimeAt(s.turn);
  var years = growthYearsPerTurn(s.turn);
  var persons = s.persons!;
  var bothAlive = persons.qing.alive && persons.mei.alive;

  // 不走动就淡了：这天既没同框也没共鸣，亲近往下掉一点。离得越远掉得越多，但住过对门，总归认识。
  // 一个在外地、这天是回来一趟（world.ts 的 back）：一起做的事照样加亲近，可挡不住这一年（中年是三年）的生分
  var rb = c.rules.bond;
  if (bothAlive && s.world && (!s.world.warm || s.world.back) && s.bond.close > rb.driftFloor) {
    var drift = legacyDrift(c, s, rb.drift[t.stage] * (1 + s.bond.distance * rb.driftDistance)); // 连心
    s.bond.close = Math.max(rb.driftFloor, Math.round((s.bond.close - drift) * 100) / 100);
  }

  for (var i = 0; i < ROLES.length; i++) {
    var p = persons[ROLES[i]];
    if (!p.alive) continue;
    legacyLinkedMood(c, p, persons[lifeOther(ROLES[i])]); // 连心：心情往对门那边靠
    p.moodSum = (p.moodSum || 0) + p.needs.mood;
    p.moodDays = (p.moodDays || 0) + 1;
    // 岁数不饶人：当天动过、用过脑子的掉得少
    var ag = c.rules.aging;
    var active = p.active || { body: false, mind: false };
    var db = growthAgingRate(ag.body, t.age) * years * (active.body ? ag.activeFactor : 1);
    var dm = growthAgingRate(ag.mind, t.age) * years * (active.mind ? ag.activeFactor : 1);
    if (db > 0) p.stats.body = lifeClamp(Math.round((p.stats.body - db) * 1000) / 1000, 0, 10);
    if (dm > 0) p.stats.mind = lifeClamp(Math.round((p.stats.mind - dm) * 1000) / 1000, 0, 10);
    p.active = { body: false, mind: false };
  }
}

// ---------- 寿命 ----------

/** 出生时定下的命数：base ± spread 的三角分布（两头少中间多） */
function growthBornLifespan(s: { rng: number }, c: Content): number {
  var r = c.rules.lifespan;
  return Math.round((r.base + (lifeRand(s) + lifeRand(s) - 1) * r.spread) * 10) / 10;
}

/** 一辈子的心气折成几年寿命 */
function growthMoodYears(c: Content, p: Person): number {
  var r = c.rules.lifespan;
  if (!p.moodDays) return 0;
  return lifeClamp((p.moodSum / p.moodDays - r.moodMid) / r.moodStep, r.moodMin, r.moodMax);
}

/** 大限：这个人现在看能活到几岁（会随着体魄、心气、对门的人变） */
function growthLimit(s: LifeState, c: Content, role: Role): number {
  var r = c.rules.lifespan;
  var p = s.persons![role];
  var other = s.persons![lifeOther(role)];
  var limit = p.lifespan + (p.stats.body - 5) * r.body + growthMoodYears(c, p);
  if (s.bond.close >= r.bondClose) limit += r.bond; // 有人惦记（人走了，惦记还在）
  // 中年把身体捡回来的、老了还自己下楼的、搭伙过的：关口上走的路折成几年
  if (r.flags) for (var f in r.flags) if (lifeHasFlag(p, f)) limit += r.flags[f];
  if (!other.alive && s.bond.close >= r.widowClose) limit -= r.widow; // 太亲的两个人，后走的那个撑不了太久
  return lifeClamp(limit, r.min, r.max);
}

/**
 * 生老病死。在 s.turn 已经 +1 之后调用：prevAge 是刚过完的那个日子的岁数。
 * 日子之间隔着好几年，人是在这几年中间的某一年走的，所以岁数按大限取整，不按下一个日子算。
 * 返回这次走了的人。
 */
function growthDeaths(s: LifeState, c: Content, prevAge: number): Role[] {
  var nextAge = lifeTimeAt(s.turn).age;
  var gone: Role[] = [];
  var persons = s.persons!;
  var check = function (role: Role, notBefore: number) {
    var p = persons[role];
    if (!p.alive) return;
    var limit = growthLimit(s, c, role);
    if (nextAge < limit) return;
    p.alive = false;
    p.diedAtAge = lifeClamp(Math.floor(limit), Math.max(prevAge, notBefore), nextAge);
    gone.push(role);
  };
  var aliveBefore = ROLES.filter(function (r) { return persons[r].alive; });
  for (var i = 0; i < aliveBefore.length; i++) check(aliveBefore[i], 0);
  // 一个人刚走，另一个人的大限跟着变（少了惦记的人）。再看一遍，但不会走在对方前头
  if (aliveBefore.length === 2 && gone.length === 1) check(lifeOther(gone[0]), persons[gone[0]].diedAtAge!);
  return gone;
}
