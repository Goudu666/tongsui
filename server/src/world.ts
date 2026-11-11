// 河畔里的世界：一天五段、走动、行动（吃饭/睡觉/上学/玩）、生存需求、同框、按地点触发事件。
// 纯函数，由 main.ts 的房间每 tick 调用；Node 单测里可以直接驱动。
//
// 时间怎么走（2026-11 重做，见 docs/GDD.md「时间」）：
//   一天切成五段（SLOTS）。走路、看、顺手的事（吃饭、洗澡、买早点、敲门）不花时间。
//   每一段两个人各自挑一件正经事（或者「歇着」），两个人都定了，这一段才在眼前过去（PLAY_MIN_PER_SEC），
//   一段做一件事 = 那件事按分钟做了几遍（Actor.scale），所以内部还是按分钟算，成长数值不用推倒。
//   钟点仍然是一天里的第几分钟（w.minute）：定的时候停在这一段的开头，过的时候一路走到这一段的结尾。
//
// 一件一件做（2026-11-11，worldActOnce）：在点位上按一下，就做「一回」这件事——写作业 1.5 小时就是这个人自己的钟往前拨
//   1.5 小时，当场结算，当场看到涨了什么、累了多少。一段里能做好几件，这一段的时间用完（或按「就这么过」）才算这个人定了。
//   两个人各有各的钟（Actor.spent），同一个点做同一件事、各自钟上的时间对得上一半以上，才算搭伴；后到的那个人到的时候，
//   先做的那个也补上搭伴的那一份。「做到点」（worldAct 不带 once）还是原来那样：把这一段剩下的时间整段押上，段末结算。
//   两种做法同样的时间换同样的成长和需求（needs 的折算见 worldNeedsFactor），所以校准过的数不跟着变。

var DAY_START = 390; // 06:30 醒来
var DAY_END = 1320; // 22:00
/** 一天的五段：[从, 到, 名字]。上学上班占中间几段，见 worldDutySlots */
var SLOTS: [number, number, string][] = [[390, 480, "早上"], [480, 720, "上午"], [720, 930, "下午"], [930, 1110, "傍晚"], [1110, 1320, "晚上"]];
/** 两个人都定了以后，这一段在眼前过去有多快：游戏分钟 / 现实秒（三个半钟头约两秒半） */
var PLAY_MIN_PER_SEC = 90;
/** 对门早就定了，你还在转悠：等这么多秒，影子替你定这一段（不设倒计时，只防一个人走开了把另一个人晾着） */
var SLOT_PATIENCE = 90;
var WALK_SPEED = 360; // 像素/秒
var SPOT_RADIUS = 110;
var REST_DAY_CHANCE = 0.3; // 歇着的日子：不上学也不上班，两个人都有一整天
/**
 * 影子（不在线的人）替人过日子，不替人拼：吃饭睡觉、上学上班一样不落，
 * 可空下来的时间只有一部分会跟着对门搭伴（FOLLOW）、一部分会朝下一个关口使劲（STRIVE），不挣外快也不花钱。
 * 这两个数定的是「人不在的时候落下多少」：影子该落在不上心和一半一半之间，不能比本人在的时候还强（tools/paths.mjs 里有影子的活法）
 */
var SHADOW_FOLLOW = 0.2;
var SHADOW_STRIVE = 0.2;
/** 搭伴：两个人同时在同一个点做同一件事，这次的成长乘这个数 */
var TOGETHER_BOOST = 1.5;
var MEMORY_BOOST = 2;
/** 带：TA 这项属性每比你高 1 点，你再多 LEAD_PER_POINT，最多 LEAD_MAX */
var LEAD_PER_POINT = 0.1;
var LEAD_MAX = 0.5;

function worldFindAction(c: Content, id: string): Action {
  return lifeFind(c.map.actions, id);
}

function worldZoneAt(c: Content, x: number, y: number): string | null {
  for (var i = 0; i < c.map.zones.length; i++) {
    var r = c.map.zones[i].rect;
    if (x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3]) return c.map.zones[i].id;
  }
  return null;
}

/** 这个世界 y 落在哪张图上 */
function worldSceneAt(c: Content, y: number): Scene | null {
  var i = Math.floor(y / c.map.stride);
  for (var k = 0; k < c.map.scenes.length; k++) if (c.map.scenes[k].index === i) return c.map.scenes[k];
  return null;
}

/**
 * 这个人现在去不去得了这张图。unlock 顶上写的条件都要满足；any 里满足一条就行（河对岸：18 岁，或者 15 岁考上了市重点……）。
 * 今天要去这张图上报到的人（上学、上班）总去得了。去不了返回原因
 */
function worldSceneLock(s: LifeState, c: Content, sc: Scene, role: Role, today?: { duty: Duty | null; story: string | null }): string | null {
  var u = sc.unlock;
  if (!u) return null;
  var duty = today ? today.duty : worldDuty(s, c, role);
  if (duty && lifeFind(c.map.spots, duty.spot).scene === sc.id) return null;
  // 主线今天在这张图上等着他：第一次自己过桥看灯，就是主线带过去的
  if ((today ? today.story : storySceneToday(s, c, role)) === sc.id) return null;
  var age = lifeTimeAt(s.turn).age;
  var p = s.persons![role];
  var why = function (q: SceneUnlock): string | null {
    if (q.minAge !== undefined && age < q.minAge) return "还太小了，一个人去不了" + sc.name;
    if (q.maxAge !== undefined && age > q.maxAge) return "已经不去" + sc.name + "了";
    if (!lifeHasAll(p.flags, q.flags) || !lifeHasNone(p.flags, q.notFlags)) return "没有去" + sc.name + "的由头";
    return null;
  };
  var top = why(u);
  if (top || !u.any) return top;
  var first: string | null = null;
  for (var i = 0; i < u.any.length; i++) {
    var w = why(u.any[i]);
    if (!w) return null;
    if (!first) first = w;
  }
  return first;
}

/** 离这个位置最近的那层地面（人只在地面上走） */
function worldFloorY(sc: Scene, y: number): number {
  var best = sc.floors[0];
  for (var i = 1; i < sc.floors.length; i++) if (Math.abs(sc.floors[i] - y) < Math.abs(best - y)) best = sc.floors[i];
  return best;
}

function worldIdle(a: Actor | null): boolean {
  return a !== null && a.action === null && !a.asleep;
}

function worldAliveRoles(s: LifeState): Role[] {
  return ROLES.filter(function (r) { return s.persons![r].alive && s.world!.actors[r] !== null; });
}

/** 按归属找点位：自己家的床、自己家的饭桌 */
function worldSpotFor(c: Content, action: string, role: Role): Spot | null {
  var any: Spot | null = null;
  for (var i = 0; i < c.map.spots.length; i++) {
    var sp = c.map.spots[i];
    if (sp.action !== action) continue;
    var z = lifeFind(c.map.zones, sp.zone);
    if (z.owner === role) return sp;
    if (!z.owner && !any) any = sp;
  }
  return any;
}

/**
 * 这个人每天早上在哪张床上醒来：走了外地那条路的（上学上班的地方在外地那张图上）在出租屋，
 * 三十岁安家买了房的在新家，别的在楼里自己家。放假的日子也一样在那边醒来，想回来得自己坐车
 */
function worldHomeBed(s: LifeState, c: Content, role: Role): Spot {
  var p = s.persons![role];
  var age = lifeTimeAt(s.turn).age;
  var tr = lifeTrack(c, p, age);
  var want: string | null = null;
  if (tr.duty && worldSceneOf(c, lifeFind(c.map.spots, tr.duty.spot)).far) want = "rental";
  else if (age >= 30 && lifeHasFlag(p, "home_own")) want = "newhome";
  return (want ? worldBedIn(c, want) : null) || worldSpotFor(c, "sleep", role)!;
}

/** 一张图上的床（出租屋、新家：不分谁家） */
function worldBedIn(c: Content, scene: string): Spot | null {
  for (var i = 0; i < c.map.spots.length; i++) {
    var sp = c.map.spots[i];
    if (sp.scene === scene && sp.actions.indexOf("sleep") >= 0) return sp;
  }
  return null;
}

function worldSceneOf(c: Content, sp: Spot): Scene {
  return lifeFind(c.map.scenes, sp.scene);
}

/** 人在不在外地那一片（外地、出租屋）。两片之间只能自己坐车（worldExit），影子和被叫过去的都过不去 */
function worldFarAt(c: Content, a: Actor): boolean {
  var sc = worldSceneAt(c, a.y);
  return !!sc && sc.far;
}

/** 这一段的时间剩不到这么多分钟（最短的正经事也要二十分钟），就算这个人定了（不用再按「就这么过」） */
var READY_LEFT = 20;

/** 这一段在路上花掉的分钟（过桥、坐车） */
function worldRide(a: Actor, slot: number): number {
  return a.rideSlot === slot ? a.ride || 0 : 0;
}

// ---------- 一天五段 ----------

/** 这个钟点在第几段（22:00 以后算最后一段） */
function worldSlotAt(minute: number): number {
  for (var i = 0; i < SLOTS.length; i++) if (minute < SLOTS[i][1]) return i;
  return SLOTS.length - 1;
}

/** 一段钟点 [从, 到] 和第 i 段碰不碰得上。没写钟点的算碰得上 */
function worldOverlaps(win: [number, number] | null | undefined, i: number): boolean {
  if (!win) return true;
  return win[0] < SLOTS[i][1] && win[1] > SLOTS[i][0];
}

/**
 * 日程占哪几段 [第一段, 最后一段]：最晚报到的那一刻所在的段起，到下班那一刻所在的段止。
 * 下班时那一段还剩一大半（上到 16:00 的大学），那一段就还给自己。
 */
function worldDutySlots(d: Duty): [number, number] {
  var from = worldSlotAt(d.arrive[1] - 1);
  var to = worldSlotAt(d.until - 1);
  if (to > from && d.until - SLOTS[to][0] < (SLOTS[to][1] - SLOTS[to][0]) / 2) to -= 1;
  return [from, to];
}

/** 这一段真能花在一件事上的分钟：一段的长度 × slotUse，再扣掉路上的（过桥、坐车） */
function worldSlotLeft(c: Content, slot: number, ride: number): number {
  return (SLOTS[slot][1] - SLOTS[slot][0]) * c.rules.daily.slotUse - ride;
}

/** 这一段里一件一件做掉了多少分钟 */
function worldSpent(a: Actor, slot: number): number {
  return a.spentSlot === slot ? a.spent || 0 : 0;
}

/** 这个人自己的钟：段头 + 路上 + 一件一件做掉的（不超过段尾）。整段的事、上学、睡觉不拨这个钟 */
function worldClock(w: WorldState, a: Actor): number {
  return Math.min(SLOTS[w.slot][0] + worldRide(a, w.slot) + worldSpent(a, w.slot), SLOTS[w.slot][1]);
}

/** 这一段这个人还剩多少分钟能花在事情上 */
function worldTimeLeft(c: Content, w: WorldState, a: Actor): number {
  return worldSlotLeft(c, w.slot, worldRide(a, w.slot)) - worldSpent(a, w.slot);
}

/**
 * 需求按几回算。一段做满 K 回同一件事（K = 这一段的分钟 ÷ 这件事的分钟），需求一共按 1 + (K − 1) × needsUse 回算（rules.yaml）。
 * 摊到每一回上就是 needsUse + (1 − needsUse) ÷ K：一件一件做和「做到点」整段做，同样的时间累得一样多。
 * 一件事比一段还长（早上那一段修车）就按做了几分之几算
 */
function worldNeedsFactor(c: Content, slot: number, act: Action): number {
  var u = worldNeedsUse(c);
  var span = worldSlotLeft(c, slot, 0);
  if (span <= 0 || act.minutes <= 0) return 1;
  return Math.min(1, u + (1 - u) * act.minutes / span);
}

/** 这个人这一段定了没有：按了「就这么过」、在做一件这一段还没完的事、睡了、这一段的时间一件一件用完了，或者已经不在了 */
function worldReady(s: LifeState, role: Role): boolean {
  var w = s.world!;
  var a = w.actors[role];
  if (!a || !s.persons![role].alive) return true;
  if (w.ready[role] || a.asleep) return true;
  return a.action !== null && a.until !== null && a.until > SLOTS[w.slot][0];
}

/** 新的一段：这一段的打算、顺手的事、一件一件做的记录都清掉 */
function worldSlotReset(w: WorldState) {
  w.ready = {};
  w.quick = [];
  w.wait = 0;
  w.runs = {};
  w.paid = [];
}

// ---------- 新的一天 ----------

function worldStartDay(s: LifeState, c: Content) {
  var t = lifeTimeAt(s.turn);
  var persons = s.persons!;
  var actors: { [R in Role]: Actor | null } = { qing: null, mei: null };
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    if (!persons[r].alive) continue;
    // 在自己的床边醒来（外地的在出租屋，买了房的在新家）；两个人睡同一处（都在外地念书）就错开一点
    var bed = worldHomeBed(s, c, r);
    var bx = bed.at[0];
    if (r === "mei" && actors.qing && actors.qing.y === bed.at[1] && Math.abs(actors.qing.x - bx) < 60) bx += 80;
    actors[r] = { x: bx, y: bed.at[1], action: null, spot: null, until: null, asleep: false };
    var st = persons[r].stats;
    persons[r].dayStart = { body: st.body, mind: st.mind, charm: st.charm, luck: st.luck };
  }

  // 命运给今天准备的事：mirror 一件（两人都在世时），每人 solo 一件。要走到对的地方才会发生。
  var seen = lifeSeenIds(s);
  var fate: WorldState["fate"] = { mirror: null, qing: null, mei: null };
  // 主线（story.ts）：今天排上的那一件占掉命运的那一格。先算它，不吃随机数。关口那天不排
  var msToday = lifeMilestoneAt(c, t.age);
  var msDue = !!msToday && ROLES.some(function (r) { return lifeMilestoneFor(msToday!, persons[r]) && !lifeSeenIds(s, r)[msToday!.id]; });
  var story = storyToday(s, c, t, msDue);
  var storyScene = function (r: Role): string | null {
    var id = story[r] || story.mirror;
    return id ? storyFindEvent(c, id)!.scene : null;
  };
  // 被主线顶替掉的旧事件不再进随机池
  var replaced = storyReplaced(c);
  // 事情出在哪张图上，那张图这个人得去得了：八岁的孩子遇不上少年宫走廊里的事（除非家里送去学琴），不然这一天命运准备的事白白落空
  var reach = function (e: LifeEvent, r: Role): boolean {
    if (replaced[e.id]) return false;
    if (!e.where) return true;
    var z = lifeFind(c.map.zones, e.where);
    return !worldSceneLock(s, c, lifeFind(c.map.scenes, z.scene), r, { duty: lifeTrack(c, persons[r], t.age).duty, story: storyScene(r) });
  };
  var together: EligibleCtx = { bond: s.bond, alone: false };
  if (persons.qing.alive && persons.mei.alive) {
    var both = persons.qing.flags.concat(persons.mei.flags);
    var mirrors = c.events.filter(function (e) { return e.kind === "mirror" && lifeEligible(e, t, both, seen, together) && reach(e, "qing") && reach(e, "mei"); });
    // 运气好的两个人，命运准备的事也多一点
    var luck = (persons.qing.stats.luck + persons.mei.stats.luck) / 2 - 5;
    if (mirrors.length > 0 && lifeRand(s) < (t.stage === "childhood" ? 0.6 : 0.45) + luck * c.rules.daily.luckFate) {
      fate.mirror = lifePickWeighted(s, mirrors, function (e) { return e.weight; })!.id;
    }
  }
  for (var j = 0; j < ROLES.length; j++) {
    var role = ROLES[j];
    if (!persons[role].alive) continue;
    var flags = persons[role].flags;
    var ctx: EligibleCtx = { bond: s.bond, alone: !persons[lifeOther(role)].alive };
    // solo 按人算：对门遇到过的事，你也可能遇到（但同一天两人不会是同一件）
    var mine = lifeSeenIds(s, role);
    if (fate.qing) mine[fate.qing] = true;
    var solos = c.events.filter(function (e) { return e.kind === "solo" && lifeEligible(e, t, flags, mine, ctx) && reach(e, role); });
    if (solos.length > 0 && lifeRand(s) < 0.7) {
      var pick = lifePickWeighted(s, solos, function (e) { return e.weight; })!;
      fate[role] = pick.id;
    }
  }

  // 主线今天在另一片上（在外地念书的人，过年那天的楼里、临走那天的楼下）：这一天就在那一片醒来——放假回来了、要走的那天还在家。
  // 回来的这一天不上学不上班（歇着）
  var off: { [R in Role]?: boolean } = {};
  var back = false;
  for (var hr = 0; hr < ROLES.length; hr++) {
    var hrole = ROLES[hr], ha = actors[hrole], hs = storyScene(hrole);
    if (!ha || !hs) continue;
    var far = lifeFind(c.map.scenes, hs).far;
    if (far === worldFarAt(c, ha)) continue;
    var hb = far ? worldBedIn(c, "rental") : worldSpotFor(c, "sleep", hrole);
    if (!hb) continue;
    ha.x = hb.at[0] + (hrole === "mei" && actors.qing && actors.qing.y === hb.at[1] && Math.abs(actors.qing.x - hb.at[0]) < 60 ? 80 : 0);
    ha.y = hb.at[1];
    off[hrole] = true;
    back = true;
  }
  // 「回来一趟」只算平常分在两片的：两个人都在外地念书、一起回来过年的，平常就在一块儿
  if (back && persons.qing.alive && persons.mei.alive) {
    back = worldSceneOf(c, worldHomeBed(s, c, "qing")).far !== worldSceneOf(c, worldHomeBed(s, c, "mei")).far;
  }

  if (story.mirror) fate.mirror = story.mirror;
  for (var sr = 0; sr < ROLES.length; sr++) if (story[ROLES[sr]]) fate[ROLES[sr]] = story[ROLES[sr]];
  if (story.force.length > 0) fate.force = story.force;

  // 关口：到了年纪的第一天。还有人没过、而且轮得到他，今天早上就发生
  var ms = lifeMilestoneAt(c, t.age);
  if (ms) {
    var due = ROLES.some(function (r) { return lifeMilestoneFor(ms!, persons[r]) && !lifeSeenIds(s, r)[ms!.id]; });
    if (due) fate.milestone = ms.id;
  }

  // 关口那天不歇：考试、报到都在今天
  var rest = lifeRand(s) < REST_DAY_CHANCE && !fate.milestone;
  // 只给碰上主线的那个人放一天（off），对门照常上学上班：不然两个人白白多出一整天凑在一起，亲近涨得比活法还快
  //   - 回来的那一天（主线在另一片）
  //   - 主线那件事落在大人上班的钟点上（傍晚的楼下、对岸）。上学上班不逃，不然只有碰上歇班日才过得上，
  //     多半拖到章末强制。小孩上学的那几件（一路去上学）本来就写在上学的钟点，不算
  if (fate.milestone) off = {};
  else {
    for (var sri = 0; sri < ROLES.length; sri++) {
      var sr0 = ROLES[sri];
      var sid = story[sr0] || story.mirror;
      if (off[sr0] || !sid || !persons[sr0].alive || t.age < 18) continue;
      var sd = lifeTrack(c, persons[sr0], t.age).duty;
      var sk = storySlotIndex(storyFindEvent(c, sid)!);
      if (sd && sk >= worldDutySlots(sd)[0] && sk <= worldDutySlots(sd)[1]) off[sr0] = true;
    }
  }
  // 成年以后一个日子就是一年（中年是三年）：歇班那天工钱照发。不然这一年有没有收入全看歇不歇，攒不攒得下钱成了碰运气
  if (t.stage !== "childhood" && t.stage !== "teen") {
    for (var pi = 0; pi < ROLES.length; pi++) {
      var pp = persons[ROLES[pi]];
      if (!rest && !off[ROLES[pi]]) continue;
      var pd = pp.alive ? lifeTrack(c, pp, t.age).duty : null;
      if (pd && pd.money > 0) pp.money += worldWage(c, pp, pd);
    }
  }

  var goal0: WorldState["goal0"] = {};
  for (var gi = 0; gi < ROLES.length; gi++) {
    var g0 = persons[ROLES[gi]].alive ? lifeGoal(s, c, ROLES[gi]) : null;
    if (!g0) continue;
    var have0: { [line: string]: number } = {};
    for (var gl = 0; gl < g0.lines.length; gl++) have0[g0.lines[gl].id] = g0.lines[gl].have;
    goal0[ROLES[gi]] = { id: g0.id, have: have0 };
  }

  s.world = {
    goal0: goal0,
    segs: {},
    minute: DAY_START,
    slot: 0,
    ready: {},
    playing: false,
    wait: 0,
    quick: [],
    runs: {},
    paid: [],
    rest: rest,
    off: off,
    back: back,
    dutyDone: {},
    actors: actors,
    event: null,
    fate: fate,
    done: [],
    warm: false,
  };
}

/** 记下今天的一截时间（小结卡上画成一条）。挨着的同一件事并成一截 */
function worldSeg(w: WorldState, role: Role, act: Action, label: string, f: number, t: number, tg: boolean) {
  if (t - f < 1) return;
  if (!w.segs) w.segs = {};
  var list = w.segs[role] || (w.segs[role] = []);
  var last = list.length ? list[list.length - 1] : null;
  if (last && last.a === act.id && Math.abs(last.t - f) < 1 && !!last.tg === tg) { last.t = t; return; }
  var seg: DaySeg = { a: act.id, l: label, f: f, t: t };
  if (tg) seg.tg = true;
  list.push(seg);
}

/**
 * 一天收工：下一道关那条正在够的线，今天挪了多少、照这样还要几个日子。
 * 在 lifeEndDay 里 turn 已经加过一以后调（turns 从明天算起）。今天过了那道关（目标换了）就不写
 */
function worldDayGoal(s: LifeState, c: Content, role: Role, goal0: { id: string; have: { [line: string]: number } } | undefined): DayGoal | null {
  if (!goal0) return null;
  var g = lifeGoal(s, c, role);
  if (!g || g.id !== goal0.id || g.lines.length === 0) return null;
  // 够不着的线里，今天挪得最多的那条（你在冲的）；都没挪就最低那条；都够着了就最高那条
  var pick: GoalLine | null = null;
  var gain = function (l: GoalLine) { return l.have - (goal0.have[l.id] === undefined ? l.have : goal0.have[l.id]); };
  for (var i = 0; i < g.lines.length; i++) {
    var l = g.lines[i];
    if (!l.ok) {
      if (!pick || pick.ok || gain(l) > gain(pick) || (gain(l) === gain(pick) && l.need < pick.need)) pick = l;
    } else if (!pick || (pick.ok && l.need > pick.need)) pick = l;
  }
  if (!pick) return null;
  var have0 = goal0.have[pick.id] === undefined ? pick.have : goal0.have[pick.id];
  var out: DayGoal = { title: g.title, turns: g.turns, line: pick.text, unit: pick.unit, have0: have0, have: pick.have, need: pick.need, ok: pick.ok };
  var moved = pick.have - have0;
  if (!pick.ok && moved > 0) out.pace = Math.ceil((pick.need - pick.have) / moved);
  var crossed: string[] = [];
  for (var j = 0; j < g.lines.length; j++) {
    var h0 = goal0.have[g.lines[j].id];
    if (g.lines[j].ok && h0 !== undefined && h0 < g.lines[j].need) crossed.push(g.lines[j].text);
  }
  if (crossed.length) out.crossed = crossed;
  return out;
}

// ---------- 走动 ----------

/**
 * 客户端上报位置。服务器只做限速和边界，不做碰撞（合作游戏，信任客户端的走位）。
 * 人只在这一层地面上左右走：y 不认客户端的，上下楼、出门都走出口（worldExit）
 */
function worldMove(s: LifeState, c: Content, role: Role, x: number, y: number, dtSec: number): boolean {
  if (s.phase !== "life") return false;
  var a = s.world!.actors[role];
  if (!worldIdle(a) || !s.persons![role].alive) return false;
  if (typeof x !== "number" || isNaN(x)) return false;
  var sc = worldSceneAt(c, a!.y);
  x = lifeClamp(x, 0, sc ? sc.width : c.map.size[0]);
  var dx = x - a!.x;
  var max = WALK_SPEED * Math.max(dtSec, 0.05) * 1.6 + 30;
  if (Math.abs(dx) > max) x = a!.x + (dx > 0 ? max : -max);
  a!.x = x;
  return true;
}

/** 走出口：门、楼梯、街口。站在出口跟前才行，不花时间。去不了的图回原因 */
function worldExit(s: LifeState, c: Content, role: Role, exitId: string): string | null {
  if (s.phase !== "life" || !s.world) return "人生还没开始";
  var w = s.world;
  var a = w.actors[role];
  if (!a || !s.persons![role].alive) return "你已经不在了";
  if (w.playing) return "这一段正在过";
  if (w.event && w.event.roles.indexOf(role) >= 0) return "先做完眼前的选择";
  if (!worldIdle(a)) return a.asleep ? "已经睡下了" : "这一段已经定了";
  var ex: Exit;
  try { ex = lifeFind(c.map.exits, exitId); } catch (e) { return "没有这个出口"; }
  if (Math.abs(ex.at[0] - a.x) > SPOT_RADIUS || Math.abs(ex.at[1] - a.y) > 1) return "走近一点";
  var to = lifeFind(c.map.scenes, ex.to);
  var lock = worldSceneLock(s, c, to, role);
  if (lock) return lock;
  a.x = ex.arrive[0];
  a.y = ex.arrive[1];
  // 过桥、坐车：路上的时间从这一段里扣（这一段再做事就只剩扣掉以后的那些；去外地一趟就是一整段）
  if (ex.ride > 0) {
    if (a.rideSlot !== w.slot) a.ride = 0;
    a.ride = (a.ride || 0) + ex.ride;
    a.rideSlot = w.slot;
  }
  return null;
}

// ---------- 行动 ----------

/** 这个人今天的日程。没有（还没上学、退休了、今天歇着）返回 null */
function worldDuty(s: LifeState, c: Content, role: Role): Duty | null {
  if (s.world!.rest || (s.world!.off && s.world!.off[role])) return null;
  return lifeTrack(c, s.persons![role], lifeTimeAt(s.turn).age).duty;
}

/** 这一天的工钱：路上写的数，乘上关口挣来的那一级（rules.yaml → daily.wageFlags） */
function worldWage(c: Content, p: Person, duty: Duty): number {
  var m = duty.money;
  var wf = c.rules.daily.wageFlags;
  if (m > 0 && wf) for (var f in wf) if (lifeHasFlag(p, f)) m *= wf[f];
  return Math.round(m * 10) / 10;
}

/** 日程现在还去不去得了：今天有、还没去过、没迟到（日程的第一段过去了就是迟到，那一段拿去干别的了） */
function worldDutyOpen(s: LifeState, c: Content, role: Role): Duty | null {
  var d = worldDuty(s, c, role);
  if (!d || s.world!.dutyDone[role] || s.world!.slot > worldDutySlots(d)[0]) return null;
  return d;
}

/**
 * 这个点位现在给这个人做什么。同一个物件不同年纪做不同的事（书桌：翻小人书 → 写作业 → 看书），
 * 取第一个轮得到他的；日程行动只对今天要来这儿报到的人出现。都不合适时返回原因。
 */
function worldPickAction(s: LifeState, c: Content, role: Role, sp: Spot): { act: Action | null; why: string } {
  var age = lifeTimeAt(s.turn).age;
  var p = s.persons![role];
  var slot = s.world!.slot;
  var why = "这儿现在没什么可做的";
  var late: Action | null = null;
  for (var i = 0; i < sp.actions.length; i++) {
    var act = worldFindAction(c, sp.actions[i]);
    if (act.duty) {
      var d = worldDutyOpen(s, c, role);
      if (d && d.spot === sp.id) return { act: act, why: "" };
      continue;
    }
    var rq = act.requires || {};
    if (rq.minAge !== undefined && age < rq.minAge) { why = "还太小了"; continue; }
    if (rq.maxAge !== undefined && age > rq.maxAge) { why = "已经过了那个年纪"; continue; }
    // 关口上挣来的去处（少年宫、体校）、家里才有的（学琴、厂里的澡堂）：没有那个标记的人看不见它，轮到下一个行动。
    // 对门正在这儿做、而且这件事带得了人，就能跟着做（means.ts）
    if ((!lifeHasAll(p.flags, rq.flags) || !lifeHasNone(p.flags, rq.notFlags)) && !meansGuestOk(s, c, role, sp, act)) continue;
    // 不在钟点上先轮到下一个：体校四点开练，四点以前操场照样能踢球。
    // 后面没有别的事可做，还是把它给出去：点位上有名字，点了回「现在不是时候」（worldCanAct），不会变成没反应
    if (rq.hours && !worldOverlaps(rq.hours, slot)) { if (!late) late = act; continue; }
    return { act: act, why: "" };
  }
  return { act: late, why: late ? "" : why };
}

/**
 * 现在的状态做事有多少效率：心情越好学得越快（心情 100 → 1.2，50 → 0.9，0 → 0.6），饿着、困着再打折。
 * 所以玩不是浪费时间：玩够了再念书，比闷着头念一天划算。
 */
function worldEfficiency(p: Person): number {
  var e = 0.6 + (p.needs.mood / 100) * 0.6;
  if (p.needs.hunger < 30) e *= 0.6;
  if (p.needs.energy < 25) e *= 0.6;
  return Math.round(e * 100) / 100;
}

function worldCanAct(s: LifeState, c: Content, role: Role, spotId: string, anywhere?: boolean): string | null {
  if (s.phase !== "life") return "人生还没开始";
  var w = s.world!;
  var a = w.actors[role];
  if (!s.persons![role].alive || a === null) return "你已经不在了";
  if (w.playing) return "这一段正在过";
  if (w.event && w.event.roles.indexOf(role) >= 0) return "先做完眼前的选择";
  if (!worldIdle(a)) return a.asleep ? "已经睡下了" : "这一段已经定了";
  if (w.ready[role]) return "这一段已经定了";
  var sp: Spot;
  try { sp = lifeFind(c.map.spots, spotId); } catch (e) { return "没有这个地方"; }
  var dx = sp.at[0] - a.x, dy = sp.at[1] - a.y;
  if (!anywhere && dx * dx + dy * dy > SPOT_RADIUS * SPOT_RADIUS) return "走近一点";
  // 影子找事、跟着对门、睡觉都是直接到点位上的（anywhere）：那张图这个人去不了，就不能去（上学上班 worldSceneLock 自己放行）
  if (anywhere) {
    var lock = worldSceneLock(s, c, lifeFind(c.map.scenes, sp.scene), role);
    if (lock) return lock;
    // 外地和河畔里之间隔着一趟车：影子、跟着对门过去的都过不去，得本人坐车
    if (worldSceneOf(c, sp).far !== worldFarAt(c, a)) return "隔着老远";
  }
  var pick = worldPickAction(s, c, role, sp);
  if (!pick.act) return pick.why;
  var act = pick.act;
  var rq = act.requires || {};
  var p = s.persons![role];
  if (rq.owner && lifeFind(c.map.zones, sp.zone).owner !== role) return "这不是你的家";
  if (rq.hours && !worldOverlaps(rq.hours, w.slot)) return "现在不是时候";
  if (act.duty && w.slot < worldDutySlots(worldDuty(s, c, role)!)[0]) return "还没到点";
  if (act.id === "letter" && !postApart(s, c, role)) return s.persons![lifeOther(role)].alive ? "TA 就在跟前，用不着写信" : "信寄不到了";
  if (act.id === "letter" && postWroteToday(s, role)) return "今天写过了";
  if (!act.quick && !act.duty && !act.sleep && worldTimeLeft(c, w, a) <= 0) return worldSpent(a, w.slot) > 0 ? "这一段的时间用完了" : "路上把这一段花掉了";
  var guestHere = meansNeedsHost(p, act);
  var broke = worldFeePaid(w, role, act.id) ? null : meansCantPay(s, role, act, guestHere); // 被带着做的看对门兜里（means.ts）；这一段付过进门钱的不再付
  if (broke) return broke;
  if (act.quick) {
    // 顺手的事不花时间，可也不能一直做：一段里同一件只做一回，吃饱了就不用了
    if (w.quick.indexOf(role + ":" + act.id) >= 0) return "刚" + act.label + "过";
    if ((act.needs.hunger || 0) > 0 && p.needs.hunger >= 90) return "还不饿";
  }
  return null;
}

/**
 * 两个人这一段做同一件事（同一个点、同一个行动；日程还要走的是同一条路）。
 * 只看两边的计划，谁先定谁后定都一样，改了主意也跟着变。
 */
function worldSameThing(s: LifeState, c: Content, a: Actor | null, b: Actor | null): boolean {
  if (!a || !b || !a.action || a.action !== b.action || a.spot !== b.spot || a.asleep || b.asleep) return false;
  if (worldFindAction(c, a.action).duty) {
    var age = lifeTimeAt(s.turn).age;
    var tq = lifeTrack(c, s.persons!.qing, age), tm = lifeTrack(c, s.persons!.mei, age);
    return (tq.group || tq.id) === (tm.group || tm.id);
  }
  return true;
}

/** 搭伴的心情、亲近和那一句话：每种每天只给一次（成长的倍率每次都有）。给了返回日志 */
function worldTogetherBonus(s: LifeState, c: Content, act: Action): LogEntry | null {
  var w = s.world!;
  w.warm = true; // 今天走动过了：亲近不会淡（growth.ts）
  var key = "together:" + act.id;
  if (!act.together || w.done.indexOf(key) >= 0) return null;
  w.done.push(key);
  // 讨人喜欢的两个人凑一块儿更开心
  var charm = s.persons!.qing.stats.charm + s.persons!.mei.stats.charm - 10;
  var lift = Math.max(0.5, 1 + charm * c.rules.daily.charmTogether);
  var needs: SelfDelta = {};
  for (var nk in act.together.needs) (needs as any)[nk] = ((act.together.needs as any)[nk] as number) * (nk === "mood" ? lift : 1);
  lifeApplySelf(s.persons!.qing, needs);
  lifeApplySelf(s.persons!.mei, needs);
  var tb: any = {};
  var tk = act.quick ? 1 : c.rules.bond.slotTogether || 1;
  var cw = c.rules.bond.closeWeight ? c.rules.bond.closeWeight[lifeTimeAt(s.turn).stage] : 1; // 老了，凑一块儿的一段顶好几年
  for (var bk in act.together.bond) tb[bk] = bk === "close" || bk === "sync" ? (act.together.bond as any)[bk] * tk * (bk === "close" ? cw : 1) : (act.together.bond as any)[bk];
  lifeApplyBond(s, c, tb);
  var entry = lifeEntry(s, "together", act.together.text || "你们一起" + act.label + "。");
  s.log.push(entry);
  return entry;
}

/** 吃饭：家里的饭桌，殷实人家吃得更开心 */
function worldMealMood(c: Content, p: Person) {
  var wealth = 1; // 这户人家在新内容里没了（见 save.ts）就按普通家境算
  for (var fi = 0; fi < c.families.length; fi++) if (c.families[fi].id === p.familyId) wealth = c.families[fi].wealth;
  lifeApplySelf(p, { mood: wealth * 3 + (lifeHasFlag(p, "tal_foodie") ? 6 : 0) });
}

/**
 * 在一个点位上做事。顺手的事当场就做完；正经事就是这一段的打算（日程从今天该去的那段一直占到下班），
 * 定了这一段就等对门，两个人都定了才过去（worldAdvance）。返回 [错误, 搭伴日志]
 */
/** 这一段这个人做这件事的进门钱已经付过了（被带着的那份也按做事的人记，钱是对门出的） */
function worldFeePaid(w: WorldState, role: Role, actId: string): boolean {
  return !!w.paid && w.paid.indexOf(role + ":" + actId) >= 0;
}

/** 付进门的钱：这一段同一件事只付一回（坐一下午茶社也只付一壶茶钱）。返回付了多少（正数） */
function worldPayFee(s: LifeState, role: Role, act: Action, guest: boolean): number {
  var w = s.world!;
  if (act.money >= 0) return 0;
  var payer = guest ? lifeOther(role) : role;
  if (worldFeePaid(w, role, act.id)) return 0;
  s.persons![payer].money += act.money;
  if (!w.paid) w.paid = [];
  w.paid.push(role + ":" + act.id);
  return -act.money;
}

/** 两段时间 [f1, t1)、[f2, t2) 重叠了多少分钟 */
function worldOverlap(f1: number, t1: number, f2: number, t2: number): number {
  return Math.max(0, Math.min(t1, t2) - Math.max(f1, f2));
}

/** 搭伴的倍率：1.5，TA 这项比你高再多一点（带） */
function worldBoost(p: Person, other: Person, k: string): number {
  var lead = other.alive && k in p.stats ? lifeClamp((other.stats[k as StatKey] - p.stats[k as StatKey]) * LEAD_PER_POINT, 0, LEAD_MAX) : 0;
  return TOGETHER_BOOST + lead;
}

/**
 * 对门这一段一件一件做过的、和 [f, t) 在同一个点做同一件事、时间对得上一半以上的那一回（还没跟人搭过伴的）。
 * 「一半」按两回里短的那一回算
 */
function worldPartnerRun(w: WorldState, role: Role, actId: string, spotId: string, f: number, t: number): Run | null {
  var runs = (w.runs && w.runs[lifeOther(role)]) || [];
  for (var i = 0; i < runs.length; i++) {
    var r = runs[i];
    if (r.tg || r.a !== actId || r.sp !== spotId) continue;
    var ov = worldOverlap(f, t, r.f, r.t);
    if (ov > 0 && ov * 2 >= Math.min(t - f, r.t - r.f)) return r;
  }
  return null;
}

/** 对门后来赶上了：先做的那一回补上搭伴多出来的那一份（成长按现在的年纪和底子折算），记成一条 did 给他的客户端飘 */
function worldJoinLate(s: LifeState, c: Content, role: Role, run: Run) {
  var p = s.persons![role];
  var other = s.persons![lifeOther(role)];
  var a = s.world!.actors[role];
  run.tg = true;
  var segs = s.world!.segs && s.world!.segs[role];
  if (segs) for (var si = 0; si < segs.length; si++) if (segs[si].a === run.a && segs[si].f <= run.f && segs[si].t >= run.t) segs[si].tg = true;
  var extra: SelfDelta = {};
  var b = 0;
  for (var k in run.raw) {
    var m = worldBoost(p, other, k);
    b = Math.max(b, m);
    (extra as any)[k] = ((run.raw as any)[k] as number) * (m - 1);
  }
  var before = worldStatsCopy(p);
  lifeApplySelf(p, extra, growthCtx(s, c, "action"));
  if (!a) return;
  var act = worldFindAction(c, run.a);
  a.did = { n: ((a.did && a.did.n) || 0) + 1, a: run.a, l: act.label, f: run.f, t: run.t, s: worldStatsDiff(before, p), nd: {}, m: 0, tg: true, b: Math.round(b * 100) / 100, j: true };
}

function worldStatsCopy(p: Person): Stats {
  return { body: p.stats.body, mind: p.stats.mind, charm: p.stats.charm, luck: p.stats.luck };
}

function worldStatsDiff(before: Stats, p: Person): Partial<Stats> {
  var out: Partial<Stats> = {};
  for (var i = 0; i < STAT_KEYS.length; i++) {
    var k = STAT_KEYS[i];
    var d = Math.round((p.stats[k] - before[k]) * 1000) / 1000;
    if (d !== 0) out[k] = d;
  }
  return out;
}

function worldNeedsDiff(before: Needs, p: Person): Partial<Needs> {
  var out: Partial<Needs> = {};
  var keys: (keyof Needs)[] = ["hunger", "energy", "mood", "clean"];
  for (var i = 0; i < keys.length; i++) {
    var d = Math.round(p.needs[keys[i]] - before[keys[i]]);
    if (d !== 0) out[keys[i]] = d;
  }
  return out;
}

/**
 * 一件一件做：在这个点位上做「一回」这件事（写作业就是一个半钟头）。当场结算：这个人自己的钟往前拨这么多分钟，
 * 属性、需求、钱当场变，这段时间里饿了困了也当场掉。这一段剩的时间不够一整回，就做剩下的那一截（按比例）。
 * 搭伴：对门这一段在同一个点做过同一件事、时间对得上（worldPartnerRun），或者正整段地做着它，这一回就是搭伴。
 */
function worldActOnce(s: LifeState, c: Content, role: Role, sp: Spot, act: Action): { error: string | null; together: LogEntry | null } {
  var w = s.world!;
  var a = w.actors[role]!;
  var p = s.persons![role];
  var other = s.persons![lifeOther(role)];
  var b = w.actors[lifeOther(role)];
  var f = worldClock(w, a);
  var left = worldTimeLeft(c, w, a);
  var use = Math.min(act.minutes, left);
  var times = act.minutes > 0 ? use / act.minutes : 1;
  var t = f + use;
  var guest = meansNeedsHost(p, act);
  var beforeStats = worldStatsCopy(p);
  var beforeNeeds: Needs = { hunger: p.needs.hunger, energy: p.needs.energy, mood: p.needs.mood, clean: p.needs.clean };
  var moneyBefore = p.money;
  var fee = worldPayFee(s, role, act, guest);

  // 搭伴：对门一件一件做过的那一回，或者对门正整段地做着它（那一段从他的 start 一直到段尾）
  var run = other.alive ? worldPartnerRun(w, role, act.id, sp.id, f, t) : null;
  var deferred = !run && other.alive && !!b && !b.asleep && b.action === act.id && b.spot === sp.id && b.from === w.slot
    && worldOverlap(f, t, b.start === undefined ? SLOTS[w.slot][0] : b.start, SLOTS[w.slot][1]) * 2 >= use;
  var together = !!run || deferred;

  var eff = worldEfficiency(p);
  var raw: SelfDelta = {};
  var boosted: SelfDelta = {};
  var bmax = 0;
  for (var k in act.stats) {
    var v = ((act.stats as any)[k] as number) * eff * times;
    if (k === "mind" && lifeHasFlag(p, "tal_memory")) v *= MEMORY_BOOST; // 过目不忘：自己坐下来念的时候快一倍
    (raw as any)[k] = v;
    var m = together ? worldBoost(p, other, k) : 1;
    bmax = Math.max(bmax, m);
    (boosted as any)[k] = v * m;
  }
  var nf = times * worldNeedsFactor(c, w.slot, act);
  var needs: SelfDelta = {};
  for (var nk in act.needs) (needs as any)[nk] = ((act.needs as any)[nk] as number) * nf;
  lifeApplySelf(p, boosted, growthCtx(s, c, "action"));
  lifeApplySelf(p, needs);
  worldDecay(c, p, a, t, use); // 这一个半钟头里自己也饿了、困了
  p.money += Math.round(Math.max(0, act.money) * times * 10) / 10;
  if (act.id === "letter") postWrite(s, c, role); // 信第二天早上到对门（post.ts）

  a.x = sp.at[0];
  a.y = sp.at[1];
  a.shadow = false;
  a.spent = worldSpent(a, w.slot) + use;
  a.spentSlot = w.slot;
  if (!w.runs) w.runs = {};
  if (!w.runs[role]) w.runs[role] = [];
  w.runs[role]!.push({ a: act.id, sp: sp.id, f: f, t: t, raw: raw, tg: together });
  worldSeg(w, role, act, act.label, f, t, together);

  var entry: LogEntry | null = null;
  if (together) {
    if (run) worldJoinLate(s, c, lifeOther(role), run);
    else b!.tgMin = (b!.tgMin || 0) + use;
    entry = worldTogetherBonus(s, c, act);
  }
  a.did = {
    n: ((a.did && a.did.n) || 0) + 1, a: act.id, l: act.label, f: f, t: t,
    s: worldStatsDiff(beforeStats, p), nd: worldNeedsDiff(beforeNeeds, p), m: Math.round((p.money - moneyBefore) * 10) / 10, tg: together,
  };
  if (together) a.did.b = Math.round(bmax * 100) / 100;
  if (times < 1) a.did.part = Math.round(times * 100) / 100;
  if (fee > 0 && guest) a.did.m = 0; // 被带的那份钱记在对门头上
  if (worldTimeLeft(c, w, a) < READY_LEFT) w.ready[role] = true; // 这一段的时间用完了：定了
  return { error: null, together: entry };
}

/**
 * 在点位上做事。once：一件一件做，做一回当场结算（worldActOnce）；不带 once 是「做到点」，把这一段剩下的时间整段押上，段末结算。
 * 机器人、影子、旧安装包都走「做到点」。
 */
function worldAct(s: LifeState, c: Content, role: Role, spotId: string, once?: boolean): { error: string | null; together: LogEntry | null } {
  var err = worldCanAct(s, c, role, spotId);
  if (err) return { error: err, together: null };
  var w = s.world!;
  var a = w.actors[role]!;
  var p = s.persons![role];
  var sp = lifeFind(c.map.spots, spotId);
  var act = worldPickAction(s, c, role, sp).act!;
  a.x = sp.at[0];
  a.y = sp.at[1];
  a.shadow = false;
  if (once && !act.quick && !act.duty && !act.sleep) return worldActOnce(s, c, role, sp, act);
  if (act.quick) {
    lifeApplySelf(p, act.needs);
    p.money += act.money;
    if (act.id === "eat") worldMealMood(c, p);
    w.quick.push(role + ":" + act.id);
    // 顺手的事也能搭伴：这一段里对门在同一个点也做过这件事（两扇门同时开了）
    var partner = lifeOther(role);
    var pa = w.actors[partner];
    var near = !!pa && Math.abs(pa.x - sp.at[0]) + Math.abs(pa.y - sp.at[1]) < SPOT_RADIUS * 2;
    var mates = w.quick.indexOf(partner + ":" + act.id) >= 0 && near;
    return { error: null, together: mates ? worldTogetherBonus(s, c, act) : null };
  }
  a.action = act.id;
  a.spot = sp.id;
  a.from = w.slot;
  a.eff = worldEfficiency(p);
  if (act.sleep) {
    a.asleep = true;
    a.until = null;
  } else if (act.duty) {
    a.until = SLOTS[worldDutySlots(worldDuty(s, c, role)!)[1]][1];
    w.dutyDone[role] = true;
  } else {
    // 一段做一件事，就是这件事做了几遍。use：一段里真花在这件事上的那一份（路上、吃饭、发呆占掉的不算）
    a.until = SLOTS[w.slot][1];
    a.start = worldClock(w, a);
    a.scale = Math.round((worldTimeLeft(c, w, a) / act.minutes) * 100) / 100;
    a.guest = meansNeedsHost(p, act) || undefined; // 对门带着做的（means.ts）
    a.fee = worldPayFee(s, role, act, !!a.guest) || undefined; // 花的钱是进门的钱，坐一下午也只付一回；被带的那份对门出
    // 对门这一段一件一件做过同一件事（在这个人整段的时间里）：那几回补上搭伴，这一段按陪了多少分钟给倍率
    var pr = s.persons![lifeOther(role)].alive && w.runs ? w.runs[lifeOther(role)] || [] : [];
    for (var ri = 0; ri < pr.length; ri++) {
      var rr = pr[ri];
      if (rr.tg || rr.a !== act.id || rr.sp !== sp.id) continue;
      var ov = worldOverlap(a.start, a.until, rr.f, rr.t);
      if (ov * 2 < rr.t - rr.f) continue;
      worldJoinLate(s, c, lifeOther(role), rr);
      a.tgMin = (a.tgMin || 0) + (rr.t - rr.f);
      worldTogetherBonus(s, c, act);
    }
  }
  // 搭伴：先定后定都算，两个人这一段做的是同一件事
  var b = w.actors[lifeOther(role)];
  var same = worldSameThing(s, c, a, b);
  a.together = same;
  if (b && b.from === w.slot) b.together = same;
  return { error: null, together: null };
}

/** 这一段先歇着：不做正经事，等这一段过去 */
function worldPass(s: LifeState, c: Content, role: Role): string | null {
  if (s.phase !== "life" || !s.world) return "人生还没开始";
  var w = s.world;
  var a = w.actors[role];
  if (!a || !s.persons![role].alive) return "你已经不在了";
  if (w.playing) return "这一段正在过";
  if (w.event && w.event.roles.indexOf(role) >= 0) return "先做完眼前的选择";
  if (worldReady(s, role)) return "这一段已经定了";
  w.ready[role] = true;
  return null;
}

/** 改主意：这一段还没过，定下的打算（连睡觉、去上学）可以撤回来。前几段就开始了的日程撤不了 */
function worldCancel(s: LifeState, c: Content, role: Role): string | null {
  if (s.phase !== "life" || !s.world) return "人生还没开始";
  var w = s.world;
  var a = w.actors[role];
  if (!a || !s.persons![role].alive) return "你已经不在了";
  if (w.playing) return "这一段正在过";
  if (w.event && w.event.roles.indexOf(role) >= 0) return "先做完眼前的选择";
  if (w.ready[role]) {
    if (!a.action && worldSpent(a, w.slot) > 0 && worldTimeLeft(c, w, a) < READY_LEFT) return "这一段的时间用完了";
    delete w.ready[role];
    return null;
  }
  if (!a.action) return "这一段还没定";
  if (a.from !== undefined && a.from < w.slot) return "已经在" + worldFindAction(c, a.action).label + "了";
  var act = worldFindAction(c, a.action);
  if (act.duty) w.dutyDone[role] = false;
  if (!act.duty && !act.sleep && a.fee) { // 进门的钱退回来（被带的退给对门）
    var payer = a.guest ? lifeOther(role) : role;
    s.persons![payer].money += a.fee;
    if (w.paid) w.paid = w.paid.filter(function (k) { return k !== role + ":" + act.id; });
  }
  worldClearAction(a);
  meansHostLeft(s, c, role); // 带人的改了主意，跟着来的那个也撤回来
  var b = w.actors[lifeOther(role)];
  if (b && b.from === w.slot) b.together = false;
  return null;
}

function worldClearAction(a: Actor) {
  a.action = null;
  a.spot = null;
  a.until = null;
  a.asleep = false;
  delete a.from;
  delete a.eff;
  delete a.together;
  delete a.scale;
  delete a.guest;
  delete a.start;
  delete a.tgMin;
  delete a.fee;
}

function worldFinish(s: LifeState, c: Content, role: Role) {
  var a = s.world!.actors[role]!;
  var act = worldFindAction(c, a.action!);
  var p = s.persons![role];
  var other = s.persons![lifeOther(role)];
  // 日程的结果写在路上（tracks.yaml），别的行动写在行动自己身上，按这一段里做了几遍放大
  var duty = act.duty ? lifeTrack(c, p, lifeTimeAt(s.turn).age).duty : null;
  var times = duty || act.duty ? 1 : a.scale === undefined ? 1 : a.scale;
  var gains: Partial<Stats> = duty ? duty.stats : act.duty ? {} : act.stats;
  var needs: Partial<Needs> = duty ? duty.needs : act.duty ? {} : act.needs;
  var money = duty ? worldWage(c, p, duty) : act.duty ? 0 : Math.max(0, act.money) * times;
  var eff = a.eff === undefined ? 1 : a.eff;
  var stats: SelfDelta = {};
  for (var k in gains) {
    var v = ((gains as any)[k] as number) * eff * times;
    if (a.together) {
      var lead = other.alive ? lifeClamp((other.stats[k as StatKey] - p.stats[k as StatKey]) * LEAD_PER_POINT, 0, LEAD_MAX) : 0;
      v *= TOGETHER_BOOST + lead;
    } else if (a.tgMin && !act.duty && a.start !== undefined && a.until !== null) {
      // 对门只是一件一件地陪了一阵：陪了几成时间，搭伴的倍率就给几成
      var share = lifeClamp(a.tgMin / Math.max(1, a.until - a.start), 0, 1);
      v *= 1 + (worldBoost(p, other, k) - 1) * share;
    }
    if (k === "mind" && !act.duty && lifeHasFlag(p, "tal_memory")) v *= MEMORY_BOOST; // 过目不忘：自己坐下来念的时候快一倍
    (stats as any)[k] = v;
  }
  // 饱腹、精力、心情、清洁不按遍数整倍放大：一段四个钟头的跳皮筋不是八回跳皮筋那么累。
  // 只乘 1 + (遍数 − 1) × needsUse（rules.yaml），不然小孩上午做一件事精力就见底，下午只能睡，一天五段过成三段
  // （= 每一回按 worldNeedsFactor 算：整段做满的时候和 1 + (遍数 − 1) × needsUse 一样，和一件一件做同样的时间累得一样多）
  var ntimes = duty || act.duty ? times : a.from !== undefined && a.from >= 0 ? times * worldNeedsFactor(c, a.from, act) : times <= 1 ? times : 1 + (times - 1) * worldNeedsUse(c);
  var scaled: SelfDelta = {};
  for (var nk in needs) (scaled as any)[nk] = ((needs as any)[nk] as number) * ntimes;
  // 状态、搭伴、天赋先乘好，再交给成长规则按年纪和底子折算（growth.ts → growthApply）
  lifeApplySelf(p, stats, growthCtx(s, c, "action"));
  lifeApplySelf(p, scaled);
  if (act.id === "eat") worldMealMood(c, p); // 老存档里还在吃的那一顿
  if (act.id === "letter") postWrite(s, c, role); // 信第二天早上到对门（post.ts）
  p.money += Math.round(money * 10) / 10;
  if (a.until !== null && a.from !== undefined && a.from >= 0) {
    var segFrom = a.start !== undefined ? a.start : SLOTS[a.from][0];
    worldSeg(s.world!, role, act, duty ? duty.label : act.label, segFrom, Math.min(a.until, s.world!.minute), !!a.together || (a.tgMin || 0) * 2 >= a.until - segFrom);
  }
  worldClearAction(a);
}

/** 一段里做了好几遍的事，需求按几遍算（rules.yaml → daily.needsUse；没写是老内容，按 1 整倍算） */
function worldNeedsUse(c: Content): number {
  var u = c.rules.daily.needsUse;
  return typeof u === "number" ? u : 1;
}

// ---------- 影子：离线时按需求和习惯自己过日子 ----------

/** 影子去一个点位做事（它不用走路）。做不了返回 false */
function worldShadowGo(s: LifeState, c: Content, role: Role, spot: Spot | null): boolean {
  if (!spot || worldCanAct(s, c, role, spot.id, true)) return false;
  var pk = worldPickAction(s, c, role, spot).act;
  if (pk && meansNeedsHost(s.persons![role], pk)) return false; // 影子不被对门带着花钱（means.ts）
  var a = s.world!.actors[role]!;
  a.x = spot.at[0];
  a.y = spot.at[1];
  if (worldAct(s, c, role, spot.id).error) return false;
  a.shadow = true;
  return true;
}

/** 现在能去的点位里，第一个行动符合条件的 */
function worldShadowFind(s: LifeState, c: Content, role: Role, want: (act: Action, sp: Spot) => boolean): Spot | null {
  var found: Spot[] = [];
  for (var i = 0; i < c.map.spots.length; i++) {
    var sp = c.map.spots[i];
    var z = lifeFind(c.map.zones, sp.zone);
    if (z.owner && z.owner !== role) continue; // 影子不上别人家
    var pick = worldPickAction(s, c, role, sp);
    if (pick.act && want(pick.act, sp) && !worldCanAct(s, c, role, sp.id, true)) found.push(sp);
  }
  return found.length ? found[Math.floor(lifeRand(s) * found.length)] : null;
}

/** 下一个关口最缺的那项属性（没有关口了返回 null） */
function worldShadowNeed(s: LifeState, c: Content, role: Role): StatKey | null {
  var goal = lifeGoal(s, c, role);
  if (!goal) return null;
  var ev = lifeFindEvent(c, goal.id);
  var p = s.persons![role];
  // 盯着还没够着的线里最低的那条；都够着了就盯最高的那条
  var target: EventOption | null = null;
  for (var i = 0; i < ev.options.length; i++) {
    var o = ev.options[i];
    if (!o.min) continue;
    var short = lifeScore(p, lifeOptionWeights(ev, o), s.bond) < o.min;
    if (!target) { target = o; continue; }
    var tShort = lifeScore(p, lifeOptionWeights(ev, target), s.bond) < target.min!;
    if (short && (!tShort || o.min < target.min!)) target = o;
    else if (!short && !tShort && o.min > target.min!) target = o;
  }
  if (!target) return null;
  var w = lifeOptionWeights(ev, target);
  var best: StatKey | null = null;
  for (var k = 0; k < STAT_KEYS.length; k++) {
    var key = STAT_KEYS[k];
    if (key === "luck" || !w[key]) continue;
    if (!best || w[key]! > w[best]!) best = key;
  }
  return best;
}

/** 影子替不在的人过这一段：先把顺手的事做了（饿了吃、脏了洗），再定一件正经事；实在没有就歇着 */
function worldShadowAct(s: LifeState, c: Content, role: Role) {
  for (var i = 0; i < 4 && !worldReady(s, role); i++) worldShadowStep(s, c, role);
  if (!worldReady(s, role)) s.world!.ready[role] = true;
  s.world!.actors[role]!.shadow = true;
}

function worldShadowStep(s: LifeState, c: Content, role: Role) {
  var w = s.world!;
  var p = s.persons![role];
  var by = function (id: string) { return function (act: Action) { return act.id === id; }; };
  // 1. 过日子：饿了吃，脏了洗（顺手的事，做完还接着定这一段），困了睡，该上学上班就去
  if (p.needs.hunger < 45) {
    var out = w.slot <= 1 && p.money >= 2 && lifeRand(s) < 0.3;
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, by(out ? "eat_out" : "eat")))) return;
    if (out && worldShadowGo(s, c, role, worldShadowFind(s, c, role, by("eat")))) return;
  }
  // 主线今天（晚上的那几件也去：睡觉往后挪）这一段在哪张图上等着：去那儿找件事做（到了那儿，worldFate 会让它发生）
  var stId = w.fate[role] && storyFindEvent(c, w.fate[role]!) ? w.fate[role] : w.fate.mirror && storyFindEvent(c, w.fate.mirror) ? w.fate.mirror : null;
  var stEv = stId && w.done.indexOf(stId) < 0 ? storyFindEvent(c, stId) : null;
  var dutyNow = worldDutyOpen(s, c, role);
  if (stEv && storyNow(stEv, w.slot) && !(dutyNow && w.slot === worldDutySlots(dutyNow)[0])) { // 上学上班不逃
    var stScene = stEv.scene;
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, function (act, sp) { return sp.scene === stScene && !act.duty && !act.sleep && act.money >= 0; }))) return;
  }
  // 主线今天晚些时候还有一件（楼顶那一晚、过年那一夜）：困了也先撑着，别在那之前睡下
  var later = !!stEv && storySlotIndex(stEv) > w.slot && p.needs.energy >= 8;
  if ((p.needs.energy < 25 && !later) || w.slot >= SLOTS.length - 1) {
    // 先回自己今天醒来的那张床（外地的回出租屋）；去不了（人在另一片）再找这一片里别的床
    if (worldShadowGo(s, c, role, worldHomeBed(s, c, role))) return;
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, by("sleep")))) return;
  }
  var duty = worldDutyOpen(s, c, role);
  if (duty && w.slot === worldDutySlots(duty)[0]) {
    if (worldShadowGo(s, c, role, lifeFind(c.map.spots, duty.spot))) return;
  }
  // 2. TA 这一段定了一件我也能做的事：过去搭伴
  var partner = w.actors[lifeOther(role)];
  // TA 一件一件做的：跟着这一段里 TA 花时间最多的那一件
  var pRuns = (w.runs && w.runs[lifeOther(role)]) || [];
  var pAct = partner ? partner.action : null, pSpot = partner ? partner.spot : null;
  if (partner && !pAct && pRuns.length > 0) {
    var most: { [k: string]: number } = {};
    var best = "";
    for (var pr = 0; pr < pRuns.length; pr++) {
      var key = pRuns[pr].a + "@" + pRuns[pr].sp;
      most[key] = (most[key] || 0) + pRuns[pr].t - pRuns[pr].f;
      if (!best || most[key] > most[best]) best = key;
    }
    pAct = best.split("@")[0];
    pSpot = best.split("@")[1];
  }
  if (partner && pAct && pSpot && !partner.asleep && lifeRand(s) < SHADOW_FOLLOW) {
    var there = lifeFind(c.map.spots, pSpot);
    var mine = worldPickAction(s, c, role, there).act;
    if (mine && mine.id === pAct && !mine.duty && worldShadowGo(s, c, role, there)) return;
  }
  // 3. 心情差就去玩；不然朝下一个关口使劲；没有关口了就随便转转
  var need = p.needs.mood < 40 ? null : worldShadowNeed(s, c, role);
  if (need && lifeRand(s) < SHADOW_STRIVE) {
    var k = need;
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, function (act) { return !act.duty && !act.quick && act.money === 0 && (act.stats[k] || 0) > 0; }))) return;
  }
  if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, function (act) { return !act.duty && !act.sleep && !act.quick && act.money >= 0 && (act.needs.mood || 0) >= 8; }))) return;
  // 4. 实在没事做：这一段歇着
  w.ready[role] = true;
}

/** 本人回来了：影子替他定的这一段（还没开始过的）撤回来，让他自己定。睡着了、日程上了一半的不动 */
function worldReclaim(s: LifeState, role: Role): boolean {
  if (s.phase !== "life" || !s.world) return false;
  var w = s.world;
  var a = w.actors[role];
  w.wait = 0; // 本人回来了（影子接没接过手都一样）：重新开始等他，不接着掉线前的钟算
  if (!a || !a.shadow) return false;
  a.shadow = false;
  if (w.playing) return false;
  if (w.ready[role] && !a.action) {
    delete w.ready[role];
    return true;
  }
  if (!a.action || a.asleep || a.action === "duty" || a.from !== w.slot) return false;
  worldClearAction(a);
  var b = w.actors[lifeOther(role)];
  if (b && b.from === w.slot) b.together = false;
  return true;
}

// ---------- 需求随时间变化 ----------

function worldDecay(c: Content, p: Person, a: Actor, minute: number, dm: number) {
  var h = dm / 60;
  var hungerRate = (a.asleep ? 2 : 5) * (lifeHasFlag(p, "tal_foodie") ? 1.4 : 1);
  var energyRate = a.asleep ? -12 : 4;
  if (!a.asleep && lifeHasFlag(p, "tal_owl")) energyRate = minute >= 1200 ? 2 : minute < 480 ? 6 : 4;
  // 体魄好的人醒着不那么容易累
  if (!a.asleep) energyRate *= Math.max(0.5, 1 - (p.stats.body - 5) * c.rules.daily.bodyEnergy);
  // 清洁 11-11 砍了：顺手的事、不占时间，押时间的时候不构成取舍（存档里的 needs.clean 留着，不再变）
  var d: SelfDelta = { hunger: -hungerRate * h, energy: -energyRate * h };
  var moodDrop = 0;
  if (p.needs.hunger < 20) moodDrop += 3;
  if (p.needs.energy < 15) moodDrop += 3;
  if (moodDrop > 0) d.mood = -moodDrop * h;
  lifeApplySelf(p, d);
}

// ---------- 推进 ----------

interface WorldTick {
  entries: LogEntry[];
  started: PendingEvent | null;
  dayEnded: boolean;
}

function worldInZone(c: Content, a: Actor | null, zone: string | null): boolean {
  return a !== null && (zone === null || worldZoneAt(c, a.x, a.y) === zone);
}

/** 今天有关口，而且还没过 */
function worldMilestoneDue(s: LifeState): boolean {
  var w = s.world!;
  return !!w.fate.milestone && w.done.indexOf(w.fate.milestone) < 0;
}

/**
 * 过今天的关口。轮得到的人放下手里的事（睡着的叫醒）一起面对：
 * 两人都只剩一条路可走时不弹窗，直接记进长卷（out.entries）；否则开始事件（out.started）。
 * 返回 false：今天的关口没有人轮得到，记成过了，这一跳照常往下走。
 */
function worldMilestone(s: LifeState, c: Content, out: WorldTick): boolean {
  var w = s.world!;
  var ms = lifeFindEvent(c, w.fate.milestone!);
  var due = worldAliveRoles(s).filter(function (r) { return lifeMilestoneFor(ms, s.persons![r]) && !lifeSeenIds(s, r)[ms.id]; });
  if (due.length === 0) {
    w.done.push(ms.id);
    return false;
  }
  var pe: PendingEvent = { eventId: ms.id, kind: "milestone", roles: due, choices: {}, shadow: [], swing: {}, steady: {} };
  var forced = true;
  for (var i = 0; i < due.length; i++) {
    var r = due[i];
    var a = w.actors[r]!;
    if (a.action || a.asleep) {
      // 前几段就在做的事（日程）照常结算到这儿；这一段才定的撤回来，进门的钱退回去
      if (a.action && a.from !== undefined && a.from < w.slot) worldFinish(s, c, r);
      else if (a.action) worldCancel(s, c, r);
      worldClearAction(a);
    }
    delete w.ready[r];
    var luck = s.persons![r].stats.luck;
    var swing = 0;
    if (ms.swing) {
      var hand = (lifeRand(s) - 0.5) * SWING_RANGE;
      // 默契托底：知道对门在考场外头等着，手气差的那一半按默契折掉一些。手气好的时候不多给，属性也不动
      var steady = hand < 0 && lifePairBond(s, r) ? Math.round(-hand * growthSteadyShare(c, s.bond.sync) * 100) / 100 : 0;
      if (steady > 0) pe.steady![r] = steady;
      swing = Math.round((hand + steady + (luck - 5) * SWING_LUCK) * 100) / 100;
    }
    pe.swing![r] = swing;
    var open = ms.options.filter(function (o) { return !lifeOptionLock(ms, o, s.persons![r], swing, lifePairBond(s, r)); });
    // 一条都走不通（内容写漏了兜底的路）：走线最低的那条，不让这条人生卡在这里
    if (open.length === 0) pe.choices[r] = lifeMilestoneFallback(ms).id;
    else if (open.length === 1) pe.choices[r] = open[0].id;
    else forced = false;
  }
  if (forced) {
    out.entries.push(lifeResolveEvent(s, c, pe));
    w.done.push(ms.id);
  } else {
    // 只有一条路的人不用选，但要等另一个人选完一起揭晓
    w.event = pe;
    out.started = pe;
  }
  return true;
}

/** 两个人都定了：这一段开始在眼前过去。搭伴的那一句话、心情和亲近在这时候给（定了又改主意的不算） */
function worldStartPlay(s: LifeState, c: Content, out: WorldTick) {
  var w = s.world!;
  var q = w.actors.qing, m = w.actors.mei;
  if (q && m && s.persons!.qing.alive && s.persons!.mei.alive && q.together && m.together && worldSameThing(s, c, q, m) && q.from === w.slot) {
    var e = worldTogetherBonus(s, c, worldFindAction(c, q.action!));
    if (e) out.entries.push(e);
  }
  w.playing = true;
  w.wait = 0;
  // 两个人这一段一件一件做掉的那些已经过去了：钟从两个人里慢的那个的钟往后走（都做满了，这一段一下子就过去）
  var start = SLOTS[w.slot][1];
  var alive = worldAliveRoles(s);
  for (var i = 0; i < alive.length; i++) start = Math.min(start, SLOTS[w.slot][0] + worldSpent(w.actors[alive[i]]!, w.slot));
  w.minute = Math.max(w.minute, start);
}

/** 这一段在过：钟点往前走，需求跟着变，到点的事结算。走完这一段进下一段，晚上过完这一天就结束 */
function worldPlay(s: LifeState, c: Content, dtSec: number, out: WorldTick): WorldTick {
  var w = s.world!;
  var roles = worldAliveRoles(s);
  var end = SLOTS[w.slot][1];
  var dm = Math.min(Math.max(dtSec, 0) * PLAY_MIN_PER_SEC, end - w.minute);
  w.minute += dm;
  var from = w.minute - dm;
  for (var j = 0; j < roles.length; j++) {
    var a = w.actors[roles[j]]!;
    // 一件一件做掉的那几十分钟当场就掉过了（worldActOnce），这里只掉剩下的
    var ddm = worldOverlap(from, w.minute, SLOTS[w.slot][0] + worldSpent(a, w.slot), end);
    if (ddm > 0) worldDecay(c, s.persons![roles[j]], a, w.minute, ddm);
    if (a.action && a.until !== null && w.minute >= a.until - 1e-6) worldFinish(s, c, roles[j]);
  }
  if (w.minute < end - 1e-6) return out;
  w.minute = end;
  w.playing = false;
  worldSlotReset(w);
  var allAsleep = roles.every(function (r) { return w.actors[r]!.asleep; });
  // 都睡下了、今天却还有躲不过的主线：先不收这一天，下一跳 worldStoryForce 把人叫起来
  if (allAsleep && w.slot < SLOTS.length - 1 && worldStoryPending(s, c)) allAsleep = false;
  if (w.slot >= SLOTS.length - 1 || allAsleep) {
    out.entries = lifeEndDay(s, c);
    out.dayEnded = true;
    return out;
  }
  w.slot += 1;
  return out;
}

function worldAdvance(s: LifeState, c: Content, dtSec: number, online: { [R in Role]: boolean }): WorldTick {
  var out: WorldTick = { entries: [], started: null, dayEnded: false };
  if (s.phase !== "life") return out;
  var w = s.world!;
  if (w.event) return out; // 有人在做选择时，什么都停住
  if (w.playing) return worldPlay(s, c, dtSec, out);
  var roles = worldAliveRoles(s);

  // 关口躲不掉：一天一开头，轮得到的人放下手里的事（睡着的叫起来）一起面对
  if (worldMilestoneDue(s) && worldMilestone(s, c, out)) return out;
  // 主线到了章末还没碰上：一早就发生，不等人走过去
  if (worldStoryForce(s, c, out)) return out;

  // 触发命运（先于影子定这一段：影子一定下来就不空闲了）
  if (worldFate(s, c, online, out, false)) return out;

  // 影子：等在线的那个人定了再替不在的人定，这样才跟得上去搭伴；两个人都不在就直接定
  for (var i = 0; i < roles.length; i++) {
    var r = roles[i];
    if (online[r] || worldReady(s, r)) continue;
    var o = lifeOther(r);
    if (roles.indexOf(o) < 0 || !online[o] || worldReady(s, o)) worldShadowAct(s, c, r);
  }
  // 影子刚走到主线那张图上：这一段就发生（随机的事不这样，免得影子过的日子比人过的事多）
  if (worldFate(s, c, online, out, true)) return out;
  // 等人：对门在线却一直不定，等够了影子替他定这一段（人可能走开了）
  var waiting = roles.filter(function (r) { return !worldReady(s, r); });
  if (waiting.length > 0 && waiting.length < roles.length) {
    w.wait += Math.max(dtSec, 0);
    if (w.wait >= SLOT_PATIENCE) for (var wi = 0; wi < waiting.length; wi++) worldShadowAct(s, c, waiting[wi]);
  } else {
    w.wait = 0;
  }

  // 都睡了：这一天到头了（晚上没过完也一样）。今天还有躲不过的主线，先把人叫起来过了它
  if (roles.every(function (r) { return w.actors[r]!.asleep; })) {
    if (worldStoryForce(s, c, out)) return out;
    out.entries = lifeEndDay(s, c);
    out.dayEnded = true;
    return out;
  }
  if (roles.every(function (r) { return worldReady(s, r); })) worldStartPlay(s, c, out);
  return out;
}

/** 今天还有没发生的、躲不过的主线 */
function worldStoryPending(s: LifeState, c: Content): boolean {
  var w = s.world!;
  var list = w.fate.force || [];
  for (var i = 0; i < list.length; i++) if (w.done.indexOf(list[i]) < 0 && storyFindEvent(c, list[i])) return true;
  return false;
}

/**
 * 章末躲不过的主线：到了它自己那一段，放下手里的事（同关口；上学上班的那一段让出来），人放到那张图上，开始。
 * 那一段已经过去了、或者人都睡下了（今天就要到头了），马上开始。一次一件
 */
function worldStoryForce(s: LifeState, c: Content, out: WorldTick): boolean {
  var w = s.world!;
  var list = w.fate.force || [];
  var sleeping = worldAliveRoles(s).every(function (r) { return w.actors[r]!.asleep; });
  for (var i = 0; i < list.length; i++) {
    var id = list[i];
    if (w.done.indexOf(id) >= 0) continue;
    var ev = storyFindEvent(c, id);
    if (!ev) continue;
    if (storySlotIndex(ev) > w.slot) {
      if (!sleeping) continue; // 还没到它那一段
      // 人都早早睡下了：钟往后拨到它那一段（这中间睡着的人照睡，什么也不做），再把人叫起来
      w.slot = storySlotIndex(ev);
      w.minute = SLOTS[w.slot][0];
      worldSlotReset(w);
    }
    var roles = ev.kind === "mirror" ? worldAliveRoles(s) : ROLES.filter(function (r) { return w.fate[r] === id && s.persons![r].alive; });
    if (roles.length === 0 || (ev.kind === "mirror" && roles.length < 2)) { w.done.push(id); continue; }
    var spot0: Spot | null = null;
    // 硬塞：有人被叫醒、手上的事被撤下来、或者被挪到那张图上。人本来就在那张图上、闲着，就是照常碰上的，不算
    var pulled = sleeping;
    for (var k = 0; k < roles.length; k++) {
      var a = w.actors[roles[k]]!;
      var at = worldSceneAt(c, a.y);
      if (a.action || a.asleep || !at || at.id !== ev.scene) pulled = true;
      if (a.action && a.from !== undefined && a.from < w.slot) worldFinish(s, c, roles[k]);
      else if (a.action) { delete w.ready[roles[k]]; worldCancel(s, c, roles[k]); }
      worldClearAction(a);
      delete w.ready[roles[k]];
      // 不在那张图上的，放过去（两个人挨着站）
      var here = worldSceneAt(c, a.y);
      if (!here || here.id !== ev.scene) {
        var sp: Spot | null = spot0 || storyPlace(c, ev.scene, roles[k]);
        if (sp) { a.x = sp.at[0] + (spot0 ? 50 : 0); a.y = sp.at[1]; spot0 = spot0 || sp; }
      }
    }
    w.event = { eventId: id, kind: ev.kind, roles: roles, choices: {}, shadow: [] };
    if (pulled) w.event.forced = true;
    out.started = w.event;
    return true;
  }
  return false;
}

/**
 * 命运准备的事这时候发不发生。mirror 需要两人都空闲、都在那儿（随机的看地点，主线看图）、这一段碰得上；solo 只看当事人。
 * storyOnly：影子刚替人定完这一段，只再看一眼主线
 */
function worldFate(s: LifeState, c: Content, online: { [R in Role]: boolean }, out: WorldTick, storyOnly: boolean): boolean {
  var w = s.world!;
  var roles = worldAliveRoles(s);
  // 一世的头一个早上：人刚落地，先让他看看屋里、走两步、按一回，随机的事从上午起再来（主线照常）
  var calm = s.turn === 0 && w.slot === 0;
  if (w.fate.mirror && w.done.indexOf(w.fate.mirror) < 0 && (!(storyOnly || calm) || storyFindEvent(c, w.fate.mirror))) {
    var mev = lifeFindEvent(c, w.fate.mirror);
    // 在线的人要自己走到那里；离线的影子只要没睡着，就会被「叫过来」
    var anyOnline = roles.some(function (r) { return online[r]; });
    var host: Actor | null = null;
    for (var h0 = 0; h0 < roles.length; h0++) if (online[roles[h0]]) host = w.actors[roles[h0]];
    var hostScene = host ? worldSceneAt(c, host.y) : null;
    var available = function (r: Role) {
      var x = w.actors[r]!;
      if (online[r]) return worldIdle(x) && storyHere(c, mev, x);
      // 叫过来也得是他去得了的图（四岁的影子不会被叫到海河边）
      if (anyOnline) return !x.asleep && (x.from === undefined || x.from === w.slot) && !!hostScene && !!hostScene.far === worldFarAt(c, x) && !worldSceneLock(s, c, hostScene, r); // 两片之间叫不过来
      return !x.asleep && storyHere(c, mev, x);
    };
    if (roles.length === 2 && storyNow(mev, w.slot) && roles.every(available)) {
      var anchor: Actor | null = null;
      for (var q0 = 0; q0 < roles.length; q0++) if (online[roles[q0]]) anchor = w.actors[roles[q0]];
      for (var q = 0; q < roles.length; q++) {
        var ax = w.actors[roles[q]]!;
        if (ax.action) worldCancel(s, c, roles[q]);
        if (!online[roles[q]] && anchor) { ax.x = anchor.x + 50; ax.y = anchor.y; delete w.ready[roles[q]]; }
      }
      w.event = { eventId: mev.id, kind: "mirror", roles: roles.slice(), choices: {}, shadow: [] };
      out.started = w.event;
      return true;
    }
  }
  for (var k = 0; k < roles.length; k++) {
    var role = roles[k];
    var id = w.fate[role];
    if (!id || w.done.indexOf(id) >= 0) continue;
    var sev = lifeFindEvent(c, id);
    var st = storyIs(sev);
    if ((storyOnly || calm) && !st) continue;
    var ok = st || sev.where ? storyHere(c, sev, w.actors[role]) : true;
    // 影子刚替他定了这一段（主线那张图上的事）：撤下来去过主线
    var idle = worldIdle(w.actors[role]) || (storyOnly && !online[role] && !w.actors[role]!.asleep && w.actors[role]!.from === w.slot);
    if (ok && idle && storyNow(sev, w.slot)) {
      if (w.actors[role]!.action) { delete w.ready[role]; worldCancel(s, c, role); worldClearAction(w.actors[role]!); }
      w.event = { eventId: sev.id, kind: "solo", roles: [role], choices: {}, shadow: [] };
      out.started = w.event;
      return true;
    }
  }
  return false;
}

/** 在事件里做选择。全部人选完后结算并返回日志 */
function worldChoose(s: LifeState, c: Content, role: Role, optionId: string, fromShadow: boolean): { error: string | null; entry: LogEntry | null } {
  var w = s.world;
  if (!w || !w.event || w.event.roles.indexOf(role) < 0) return { error: "现在没有要你选的事", entry: null };
  var ev = lifeFindEvent(c, w.event.eventId);
  var opt = lifeFindOption(ev, optionId);
  if (!opt) return { error: "没有这个选项", entry: null };
  if (lifeGated(ev)) {
    var lock = lifeOptionLock(ev, opt, s.persons![role], (w.event.swing && w.event.swing[role]) || 0, lifePairBond(s, role));
    if (lock) return { error: "这条路现在走不了（" + lock + "）", entry: null };
  }
  w.event.choices[role] = optionId; // 结算前可以改主意
  if (fromShadow && w.event.shadow.indexOf(role) < 0) w.event.shadow.push(role);
  var pe = w.event;
  var missing = pe.roles.filter(function (r) { return !pe.choices[r]; });
  if (missing.length > 0) return { error: null, entry: null };
  var entry = lifeResolveEvent(s, c, pe);
  duetAfterEvent(s, c, pe, entry); // 猜 TA 的对错；影子替选的记一笔，等本人回话
  w.done.push(pe.eventId);
  w.event = null;
  storyAfter(s, c, pe.eventId); // 过完一件主线，同一天后面的段还能接着排下一件
  return { error: null, entry: entry };
}
