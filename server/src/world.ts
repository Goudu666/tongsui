// 河畔里的世界：一天五段、走动、行动（吃饭/睡觉/上学/玩）、生存需求、同框、按地点触发事件。
// 纯函数，由 main.ts 的房间每 tick 调用；Node 单测里可以直接驱动。
//
// 时间怎么走（2026-11 重做，见 docs/GDD.md「时间」）：
//   一天切成五段（SLOTS）。走路、看、顺手的事（吃饭、洗澡、买早点、敲门）不花时间。
//   每一段两个人各自挑一件正经事（或者「歇着」），两个人都定了，这一段才在眼前过去（PLAY_MIN_PER_SEC），
//   一段做一件事 = 那件事按分钟做了几遍（Actor.scale），所以内部还是按分钟算，成长数值不用推倒。
//   钟点仍然是一天里的第几分钟（w.minute）：定的时候停在这一段的开头，过的时候一路走到这一段的结尾。

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
function worldSceneLock(s: LifeState, c: Content, sc: Scene, role: Role): string | null {
  var u = sc.unlock;
  if (!u) return null;
  var duty = worldDuty(s, c, role);
  if (duty && lifeFind(c.map.spots, duty.spot).scene === sc.id) return null;
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

/** 这个人这一段定了没有：按了「就这么过」、在做一件这一段还没完的事、睡了，或者已经不在了 */
function worldReady(s: LifeState, role: Role): boolean {
  var w = s.world!;
  var a = w.actors[role];
  if (!a || !s.persons![role].alive) return true;
  if (w.ready[role] || a.asleep) return true;
  return a.action !== null && a.until !== null && a.until > SLOTS[w.slot][0];
}

// ---------- 新的一天 ----------

function worldStartDay(s: LifeState, c: Content) {
  var t = lifeTimeAt(s.turn);
  var persons = s.persons!;
  var actors: { [R in Role]: Actor | null } = { qing: null, mei: null };
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    if (!persons[r].alive) continue;
    var sp = c.map.spawn[r];
    actors[r] = { x: sp[0], y: sp[1], action: null, spot: null, until: null, asleep: false };
    var st = persons[r].stats;
    persons[r].dayStart = { body: st.body, mind: st.mind, charm: st.charm, luck: st.luck };
  }

  // 命运给今天准备的事：mirror 一件（两人都在世时），每人 solo 一件。要走到对的地方才会发生。
  var seen = lifeSeenIds(s);
  var fate: WorldState["fate"] = { mirror: null, qing: null, mei: null };
  var together: EligibleCtx = { bond: s.bond, alone: false };
  if (persons.qing.alive && persons.mei.alive) {
    var both = persons.qing.flags.concat(persons.mei.flags);
    var mirrors = c.events.filter(function (e) { return e.kind === "mirror" && lifeEligible(e, t, both, seen, together); });
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
    var solos = c.events.filter(function (e) { return e.kind === "solo" && lifeEligible(e, t, flags, mine, ctx); });
    if (solos.length > 0 && lifeRand(s) < 0.7) {
      var pick = lifePickWeighted(s, solos, function (e) { return e.weight; })!;
      fate[role] = pick.id;
    }
  }

  // 关口：到了年纪的第一天。还有人没过、而且轮得到他，今天早上就发生
  var ms = lifeMilestoneAt(c, t.age);
  if (ms) {
    var due = ROLES.some(function (r) { return lifeMilestoneFor(ms!, persons[r]) && !lifeSeenIds(s, r)[ms!.id]; });
    if (due) fate.milestone = ms.id;
  }

  // 关口那天不歇：考试、报到都在今天
  var rest = lifeRand(s) < REST_DAY_CHANCE && !fate.milestone;
  // 成年以后一个日子就是一年（中年是三年）：歇班那天工钱照发。不然这一年有没有收入全看歇不歇，攒不攒得下钱成了碰运气
  if (rest && t.stage !== "childhood" && t.stage !== "teen") {
    for (var pi = 0; pi < ROLES.length; pi++) {
      var pp = persons[ROLES[pi]];
      var pd = pp.alive ? lifeTrack(c, pp, t.age).duty : null;
      if (pd && pd.money > 0) pp.money += worldWage(c, pp, pd);
    }
  }

  s.world = {
    minute: DAY_START,
    slot: 0,
    ready: {},
    playing: false,
    wait: 0,
    quick: [],
    rest: rest,
    dutyDone: {},
    actors: actors,
    event: null,
    fate: fate,
    done: [],
    warm: false,
  };
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
  return null;
}

// ---------- 行动 ----------

/** 这个人今天的日程。没有（还没上学、退休了、今天歇着）返回 null */
function worldDuty(s: LifeState, c: Content, role: Role): Duty | null {
  if (s.world!.rest) return null;
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
    // 关口上挣来的去处（少年宫、体校）：没走那条路的人看不见它，轮到下一个行动
    if (!lifeHasAll(p.flags, rq.flags) || !lifeHasNone(p.flags, rq.notFlags)) continue;
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
  }
  var pick = worldPickAction(s, c, role, sp);
  if (!pick.act) return pick.why;
  var act = pick.act;
  var rq = act.requires || {};
  var p = s.persons![role];
  if (rq.owner && lifeFind(c.map.zones, sp.zone).owner !== role) return "这不是你的家";
  if (rq.hours && !worldOverlaps(rq.hours, w.slot)) return "现在不是时候";
  if (act.duty && w.slot < worldDutySlots(worldDuty(s, c, role)!)[0]) return "还没到点";
  if (act.money < 0 && p.money < -act.money) return "兜里的钱不够";
  if (act.quick) {
    // 顺手的事不花时间，可也不能一直做：一段里同一件只做一回，吃饱了、洗干净了就不用了
    if (w.quick.indexOf(role + ":" + act.id) >= 0) return "刚" + act.label + "过";
    if ((act.needs.hunger || 0) > 0 && p.needs.hunger >= 90) return "还不饿";
    if ((act.needs.clean || 0) > 0 && p.needs.clean >= 90) return "挺干净的";
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
  for (var bk in act.together.bond) tb[bk] = bk === "close" || bk === "sync" ? (act.together.bond as any)[bk] * tk : (act.together.bond as any)[bk];
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
function worldAct(s: LifeState, c: Content, role: Role, spotId: string): { error: string | null; together: LogEntry | null } {
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
    var len = SLOTS[w.slot][1] - SLOTS[w.slot][0];
    a.until = SLOTS[w.slot][1];
    a.scale = Math.round((len * c.rules.daily.slotUse / act.minutes) * 100) / 100;
    p.money += act.money < 0 ? act.money : 0; // 花的钱是进门的钱，坐一下午也只付一回
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
    delete w.ready[role];
    return null;
  }
  if (!a.action) return "这一段还没定";
  if (a.from !== undefined && a.from < w.slot) return "已经在" + worldFindAction(c, a.action).label + "了";
  var act = worldFindAction(c, a.action);
  if (act.duty) w.dutyDone[role] = false;
  if (!act.duty && !act.sleep && act.money < 0) s.persons![role].money -= act.money; // 进门的钱退回来
  worldClearAction(a);
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
    }
    if (k === "mind" && !act.duty && lifeHasFlag(p, "tal_memory")) v *= MEMORY_BOOST; // 过目不忘：自己坐下来念的时候快一倍
    (stats as any)[k] = v;
  }
  var scaled: SelfDelta = {};
  for (var nk in needs) (scaled as any)[nk] = ((needs as any)[nk] as number) * times;
  // 状态、搭伴、天赋先乘好，再交给成长规则按年纪和底子折算（growth.ts → growthApply）
  lifeApplySelf(p, stats, growthCtx(s, c, "action"));
  lifeApplySelf(p, scaled);
  if (act.id === "eat") worldMealMood(c, p); // 老存档里还在吃的那一顿
  p.money += Math.round(money * 10) / 10;
  worldClearAction(a);
}

// ---------- 影子：离线时按需求和习惯自己过日子 ----------

/** 影子去一个点位做事（它不用走路）。做不了返回 false */
function worldShadowGo(s: LifeState, c: Content, role: Role, spot: Spot | null): boolean {
  if (!spot || worldCanAct(s, c, role, spot.id, true)) return false;
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
  if (p.needs.clean < 30 && worldShadowGo(s, c, role, worldShadowFind(s, c, role, by("wash")))) return;
  if (p.needs.energy < 25 || w.slot >= SLOTS.length - 1) {
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, by("sleep")))) return;
  }
  var duty = worldDutyOpen(s, c, role);
  if (duty && w.slot === worldDutySlots(duty)[0]) {
    if (worldShadowGo(s, c, role, lifeFind(c.map.spots, duty.spot))) return;
  }
  // 2. TA 这一段定了一件我也能做的事：过去搭伴
  var partner = w.actors[lifeOther(role)];
  if (partner && partner.action && partner.spot && !partner.asleep && lifeRand(s) < SHADOW_FOLLOW) {
    var there = lifeFind(c.map.spots, partner.spot);
    var mine = worldPickAction(s, c, role, there).act;
    if (mine && mine.id === partner.action && !mine.duty && worldShadowGo(s, c, role, there)) return;
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
  var d: SelfDelta = { hunger: -hungerRate * h, energy: -energyRate * h, clean: -2 * h };
  var moodDrop = 0;
  if (p.needs.hunger < 20) moodDrop += 3;
  if (p.needs.energy < 15) moodDrop += 3;
  if (p.needs.clean < 20) moodDrop += 2;
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
      var steady = hand < 0 && lifePairBond(s, r) ? Math.round(-hand * (s.bond.sync / 100) * c.rules.bond.syncSteady * 100) / 100 : 0;
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
}

/** 这一段在过：钟点往前走，需求跟着变，到点的事结算。走完这一段进下一段，晚上过完这一天就结束 */
function worldPlay(s: LifeState, c: Content, dtSec: number, out: WorldTick): WorldTick {
  var w = s.world!;
  var roles = worldAliveRoles(s);
  var end = SLOTS[w.slot][1];
  var dm = Math.min(Math.max(dtSec, 0) * PLAY_MIN_PER_SEC, end - w.minute);
  w.minute += dm;
  for (var j = 0; j < roles.length; j++) {
    var a = w.actors[roles[j]]!;
    worldDecay(c, s.persons![roles[j]], a, w.minute, dm);
    if (a.action && a.until !== null && w.minute >= a.until - 1e-6) worldFinish(s, c, roles[j]);
  }
  if (w.minute < end - 1e-6) return out;
  w.minute = end;
  w.playing = false;
  w.ready = {};
  w.quick = [];
  w.wait = 0;
  var allAsleep = roles.every(function (r) { return w.actors[r]!.asleep; });
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

  // 触发命运（先于影子定这一段：影子一定下来就不空闲了）：mirror 需要两人都空闲、都在 where、这一段碰得上它的钟点
  if (w.fate.mirror && w.done.indexOf(w.fate.mirror) < 0) {
    var mev = lifeFindEvent(c, w.fate.mirror);
    // 在线的人要自己走到那里；离线的影子只要没睡着，就会被「叫过来」
    var anyOnline = roles.some(function (r) { return online[r]; });
    var host: Actor | null = null;
    for (var h0 = 0; h0 < roles.length; h0++) if (online[roles[h0]]) host = w.actors[roles[h0]];
    var hostScene = host ? worldSceneAt(c, host.y) : null;
    var available = function (r: Role) {
      var x = w.actors[r]!;
      if (online[r]) return worldIdle(x) && worldInZone(c, x, mev.where);
      // 叫过来也得是他去得了的图（四岁的影子不会被叫到海河边）
      if (anyOnline) return !x.asleep && (x.from === undefined || x.from === w.slot) && !!hostScene && !worldSceneLock(s, c, hostScene, r);
      return !x.asleep && worldInZone(c, x, mev.where);
    };
    if (roles.length === 2 && worldOverlaps(mev.when, w.slot) && roles.every(available)) {
      var anchor: Actor | null = null;
      for (var q0 = 0; q0 < roles.length; q0++) if (online[roles[q0]]) anchor = w.actors[roles[q0]];
      for (var q = 0; q < roles.length; q++) {
        var ax = w.actors[roles[q]]!;
        if (ax.action) worldCancel(s, c, roles[q]);
        if (!online[roles[q]] && anchor) { ax.x = anchor.x + 50; ax.y = anchor.y; delete w.ready[roles[q]]; }
      }
      w.event = { eventId: mev.id, kind: "mirror", roles: roles.slice(), choices: {}, shadow: [] };
      out.started = w.event;
      return out;
    }
  }
  for (var k = 0; k < roles.length; k++) {
    var role = roles[k];
    var id = w.fate[role];
    if (!id || w.done.indexOf(id) >= 0) continue;
    var sev = lifeFindEvent(c, id);
    var ok = sev.where ? worldInZone(c, w.actors[role], sev.where) : true;
    if (ok && worldIdle(w.actors[role]) && worldOverlaps(sev.when, w.slot)) {
      w.event = { eventId: sev.id, kind: "solo", roles: [role], choices: {}, shadow: [] };
      out.started = w.event;
      return out;
    }
  }

  // 影子：等在线的那个人定了再替不在的人定，这样才跟得上去搭伴；两个人都不在就直接定
  for (var i = 0; i < roles.length; i++) {
    var r = roles[i];
    if (online[r] || worldReady(s, r)) continue;
    var o = lifeOther(r);
    if (roles.indexOf(o) < 0 || !online[o] || worldReady(s, o)) worldShadowAct(s, c, r);
  }
  // 等人：对门在线却一直不定，等够了影子替他定这一段（人可能走开了）
  var waiting = roles.filter(function (r) { return !worldReady(s, r); });
  if (waiting.length > 0 && waiting.length < roles.length) {
    w.wait += Math.max(dtSec, 0);
    if (w.wait >= SLOT_PATIENCE) for (var wi = 0; wi < waiting.length; wi++) worldShadowAct(s, c, waiting[wi]);
  } else {
    w.wait = 0;
  }

  // 都睡了：这一天到头了（晚上没过完也一样）
  if (roles.every(function (r) { return w.actors[r]!.asleep; })) {
    out.entries = lifeEndDay(s, c);
    out.dayEnded = true;
    return out;
  }
  if (roles.every(function (r) { return worldReady(s, r); })) worldStartPlay(s, c, out);
  return out;
}

/** 在事件里做选择。全部人选完后结算并返回日志 */
function worldChoose(s: LifeState, c: Content, role: Role, optionId: string, fromShadow: boolean): { error: string | null; entry: LogEntry | null } {
  var w = s.world;
  if (!w || !w.event || w.event.roles.indexOf(role) < 0) return { error: "现在没有要你选的事", entry: null };
  var ev = lifeFindEvent(c, w.event.eventId);
  var opt = lifeFindOption(ev, optionId);
  if (!opt) return { error: "没有这个选项", entry: null };
  if (w.event.kind === "milestone") {
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
  return { error: null, entry: entry };
}
