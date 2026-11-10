// 河畔里的实时世界：共享时钟、走动、行动（吃饭/睡觉/上学/玩）、生存需求、同框、按地点触发事件。
// 纯函数，由 main.ts 的房间每 tick 调用；Node 单测里可以直接驱动。

var DAY_START = 390; // 06:30 醒来
var DAY_END = 1320; // 22:00 撑不住了
var SCHOOL_END = 930; // 15:30 放学
var MIN_PER_SEC = 4; // 现实 1 秒 = 游戏 4 分钟，一天约 4 分钟
var FAST_FORWARD = 10; // 两人都在忙（上学、睡觉、长行动）时时间快进
var WALK_SPEED = 360; // 像素/秒
var SPOT_RADIUS = 110;
var REST_DAY_CHANCE = 0.3; // 歇着的日子：不上学也不上班，两个人都有一整天
var MILESTONE_AT = DAY_START + 10; // 关口在早上醒来不久发生
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

/** 客户端上报位置。服务器只做限速和边界，不做碰撞（合作游戏，信任客户端的走位） */
function worldMove(s: LifeState, c: Content, role: Role, x: number, y: number, dtSec: number): boolean {
  if (s.phase !== "life") return false;
  var a = s.world!.actors[role];
  if (!worldIdle(a) || !s.persons![role].alive) return false;
  if (typeof x !== "number" || typeof y !== "number" || isNaN(x) || isNaN(y)) return false;
  x = lifeClamp(x, 0, c.map.size[0]);
  y = lifeClamp(y, 0, c.map.size[1]);
  var dx = x - a!.x, dy = y - a!.y;
  var dist = Math.sqrt(dx * dx + dy * dy);
  var max = WALK_SPEED * Math.max(dtSec, 0.05) * 1.6 + 30;
  if (dist > max) {
    x = a!.x + (dx / dist) * max;
    y = a!.y + (dy / dist) * max;
  }
  a!.x = x;
  a!.y = y;
  return true;
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

/** 日程现在还去不去得了：今天有、还没去过、没迟到 */
function worldDutyOpen(s: LifeState, c: Content, role: Role): Duty | null {
  var d = worldDuty(s, c, role);
  if (!d || s.world!.dutyDone[role] || s.world!.minute > d.arrive[1]) return null;
  return d;
}

/**
 * 这个点位现在给这个人做什么。同一个物件不同年纪做不同的事（书桌：翻小人书 → 写作业 → 看书），
 * 取第一个轮得到他的；日程行动只对今天要来这儿报到的人出现。都不合适时返回原因。
 */
function worldPickAction(s: LifeState, c: Content, role: Role, sp: Spot): { act: Action | null; why: string } {
  var age = lifeTimeAt(s.turn).age;
  var p = s.persons![role];
  var minute = s.world!.minute;
  var why = "这儿现在没什么可做的";
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
    // 不在钟点上也轮到下一个：体校四点开练，四点以前操场照样能踢球
    if (rq.hours && (minute < rq.hours[0] || minute > rq.hours[1])) { why = "现在不是时候"; continue; }
    return { act: act, why: "" };
  }
  return { act: null, why: why };
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
  if (!worldIdle(a)) return "正在忙";
  if (w.event && w.event.roles.indexOf(role) >= 0) return "先做完眼前的选择";
  var sp: Spot;
  try { sp = lifeFind(c.map.spots, spotId); } catch (e) { return "没有这个地方"; }
  var dx = sp.at[0] - a.x, dy = sp.at[1] - a.y;
  if (!anywhere && dx * dx + dy * dy > SPOT_RADIUS * SPOT_RADIUS) return "走近一点";
  var pick = worldPickAction(s, c, role, sp);
  if (!pick.act) return pick.why;
  var act = pick.act;
  var rq = act.requires || {};
  if (rq.owner && lifeFind(c.map.zones, sp.zone).owner !== role) return "这不是你的家";
  if (rq.hours && (w.minute < rq.hours[0] || w.minute > rq.hours[1])) return "现在不是时候";
  if (act.duty && w.minute < worldDuty(s, c, role)!.arrive[0]) return "还没到点";
  if (act.money < 0 && s.persons![role].money < -act.money) return "兜里的钱不够";
  return null;
}

/** 开始一个行动。返回 [错误, 搭伴日志] */
function worldAct(s: LifeState, c: Content, role: Role, spotId: string): { error: string | null; together: LogEntry | null } {
  var err = worldCanAct(s, c, role, spotId);
  if (err) return { error: err, together: null };
  var w = s.world!;
  var a = w.actors[role]!;
  var sp = lifeFind(c.map.spots, spotId);
  var act = worldPickAction(s, c, role, sp).act!;
  a.x = sp.at[0];
  a.y = sp.at[1];
  a.action = act.id;
  a.spot = sp.id;
  a.shadow = false;
  a.eff = worldEfficiency(s.persons![role]);
  a.together = false;
  delete a.boost; // 上一件事没用掉的搭伴倍率不带过来（见 games.ts）
  if (act.sleep) {
    a.asleep = true;
    a.until = null;
  } else if (act.duty) {
    a.until = worldDuty(s, c, role)!.until;
    w.dutyDone[role] = true;
  } else {
    a.until = w.minute + act.minutes;
  }

  // 搭伴：TA 正在同一个点做同一件事（日程还要走的是同一条路：同一所学校、同一个行当）
  var together: LogEntry | null = null;
  var b = w.actors[lifeOther(role)];
  var same = !!b && b.action === act.id && b.spot === sp.id && !act.sleep;
  if (same && act.duty) {
    var age = lifeTimeAt(s.turn).age;
    var tq = lifeTrack(c, s.persons!.qing, age), tm = lifeTrack(c, s.persons!.mei, age);
    same = (tq.group || tq.id) === (tm.group || tm.id);
  }
  if (same) {
    a.together = true;
    b!.together = true;
    w.warm = true; // 今天走动过了：亲近不会淡（growth.ts）
    var key = "together:" + act.id;
    if (act.together && w.done.indexOf(key) < 0) {
      w.done.push(key); // 心情、亲近和这句话每种每天只给一次；成长的倍率每次都有
      // 讨人喜欢的两个人凑一块儿更开心
      var charm = s.persons!.qing.stats.charm + s.persons!.mei.stats.charm - 10;
      var lift = Math.max(0.5, 1 + charm * c.rules.daily.charmTogether);
      var needs: SelfDelta = {};
      for (var nk in act.together.needs) (needs as any)[nk] = ((act.together.needs as any)[nk] as number) * (nk === "mood" ? lift : 1);
      lifeApplySelf(s.persons!.qing, needs);
      lifeApplySelf(s.persons!.mei, needs);
      lifeApplyBond(s, c, act.together.bond);
      together = lifeEntry(s, "together", act.together.text || "你们一起" + act.label + "。");
      s.log.push(together);
    }
  }
  return { error: null, together: together };
}

function worldFinish(s: LifeState, c: Content, role: Role) {
  var a = s.world!.actors[role]!;
  var act = worldFindAction(c, a.action!);
  var p = s.persons![role];
  var other = s.persons![lifeOther(role)];
  // 日程的结果写在路上（tracks.yaml），别的行动写在行动自己身上
  var duty = act.duty ? lifeTrack(c, p, lifeTimeAt(s.turn).age).duty : null;
  var gains: Partial<Stats> = duty ? duty.stats : act.duty ? {} : act.stats;
  var needs: Partial<Needs> = duty ? duty.needs : act.duty ? {} : act.needs;
  var money = duty ? worldWage(c, p, duty) : act.duty ? 0 : act.money;
  var eff = a.eff === undefined ? 1 : a.eff;
  var stats: SelfDelta = {};
  for (var k in gains) {
    var v = ((gains as any)[k] as number) * eff;
    if (a.together) {
      var lead = other.alive ? lifeClamp((other.stats[k as StatKey] - p.stats[k as StatKey]) * LEAD_PER_POINT, 0, LEAD_MAX) : 0;
      // 搭伴的倍率：默认 TOGETHER_BOOST；一起玩了小游戏（games.ts）就用打出来的那个，但不会比默认的低
      v *= Math.max(TOGETHER_BOOST, a.boost || 0) + lead;
    }
    if (k === "mind" && !act.duty && lifeHasFlag(p, "tal_memory")) v *= MEMORY_BOOST; // 过目不忘：自己坐下来念的时候快一倍
    (stats as any)[k] = v;
  }
  // 状态、搭伴、天赋先乘好，再交给成长规则按年纪和底子折算（growth.ts → growthApply）
  lifeApplySelf(p, stats, growthCtx(s, c, "action"));
  lifeApplySelf(p, needs);
  if (act.id === "eat") {
    var wealth = 1; // 这户人家在新内容里没了（见 save.ts）就按普通家境算
    for (var fi = 0; fi < c.families.length; fi++) if (c.families[fi].id === p.familyId) wealth = c.families[fi].wealth;
    lifeApplySelf(p, { mood: wealth * 3 + (lifeHasFlag(p, "tal_foodie") ? 6 : 0) });
  }
  p.money += money;
  a.action = null;
  a.spot = null;
  a.until = null;
  delete a.eff;
  delete a.together;
  delete a.boost;
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

function worldShadowAct(s: LifeState, c: Content, role: Role) {
  var w = s.world!;
  var p = s.persons![role];
  var by = function (id: string) { return function (act: Action) { return act.id === id; }; };
  // 1. 过日子：饿了吃，困了睡，该上学上班就去，脏了洗
  if (p.needs.hunger < 45) {
    var out = w.minute < 600 && p.money >= 2 && lifeRand(s) < 0.3;
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, by(out ? "eat_out" : "eat")))) return;
  }
  if (p.needs.energy < 25 || w.minute >= 1230) {
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, by("sleep")))) return;
  }
  var duty = worldDutyOpen(s, c, role);
  if (duty && w.minute >= duty.arrive[0]) {
    if (worldShadowGo(s, c, role, lifeFind(c.map.spots, duty.spot))) return;
  }
  if (p.needs.clean < 30 && worldShadowGo(s, c, role, worldShadowFind(s, c, role, by("wash")))) return;
  // 2. TA 正在做一件我也能做的事：过去搭伴
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
    if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, function (act) { return !act.duty && act.money === 0 && (act.stats[k] || 0) > 0; }))) return;
  }
  if (worldShadowGo(s, c, role, worldShadowFind(s, c, role, function (act) { return !act.duty && !act.sleep && act.money >= 0 && (act.needs.mood || 0) >= 8; }))) return;
  // 4. 实在没事做：在楼道里站一会儿
  worldShadowGo(s, c, role, worldShadowFind(s, c, role, by("knock")));
}

/** 本人回来了：影子正在做的事（睡觉、上学除外）停下，把身体还给他 */
function worldReclaim(s: LifeState, role: Role): boolean {
  if (s.phase !== "life" || !s.world) return false;
  var a = s.world.actors[role];
  if (!a || !a.shadow) return false;
  a.shadow = false;
  // 睡着了、已经在学校或班上了，就让它过完（半路叫回来这一天的日程就白去了）
  if (!a.action || a.asleep || a.action === "duty") return false;
  delete a.eff;
  delete a.together;
  delete a.boost;
  a.action = null;
  a.spot = null;
  a.until = null;
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

function worldInWindow(ev: LifeEvent, minute: number): boolean {
  return !ev.when || (minute >= ev.when[0] && minute <= ev.when[1]);
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
  var pe: PendingEvent = { eventId: ms.id, kind: "milestone", roles: due, choices: {}, shadow: [], swing: {} };
  var forced = true;
  for (var i = 0; i < due.length; i++) {
    var r = due[i];
    var a = w.actors[r]!;
    if (a.action || a.asleep) { a.action = null; a.spot = null; a.until = null; a.asleep = false; delete a.eff; delete a.together; delete a.boost; }
    var luck = s.persons![r].stats.luck;
    var swing = ms.swing ? Math.round(((lifeRand(s) - 0.5) * SWING_RANGE + (luck - 5) * SWING_LUCK) * 100) / 100 : 0;
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

function worldAdvance(s: LifeState, c: Content, dtSec: number, online: { [R in Role]: boolean }): WorldTick {
  var out: WorldTick = { entries: [], started: null, dayEnded: false };
  if (s.phase !== "life") return out;
  var w = s.world!;
  if (w.event) return out; // 有人在做选择时，时间停住
  if (w.game) return out; // 搭伴小游戏（问 / 玩）的时候也停住，见 games.ts
  var roles = worldAliveRoles(s);

  for (var i = 0; i < roles.length; i++) {
    if (!online[roles[i]] && worldIdle(w.actors[roles[i]])) worldShadowAct(s, c, roles[i]);
  }

  var allAsleep = roles.every(function (r) { return w.actors[r]!.asleep; });
  // 关口躲不掉：一大早就都躺下了，也得先起来把这一关过了，这一天才能翻过去（青年以后一岁只有一天，错过就没有了）
  if (allAsleep && worldMilestoneDue(s) && worldMilestone(s, c, out)) return out;
  if (allAsleep) {
    out.entries = lifeEndDay(s, c);
    out.dayEnded = true;
    return out;
  }
  var allBusy = roles.every(function (r) { return !worldIdle(w.actors[r]); });
  var dm = dtSec * MIN_PER_SEC * (allBusy ? FAST_FORWARD : 1);
  w.minute += dm;

  for (var j = 0; j < roles.length; j++) {
    var a = w.actors[roles[j]]!;
    worldDecay(c, s.persons![roles[j]], a, w.minute, dm);
    if (a.until !== null && w.minute >= a.until) worldFinish(s, c, roles[j]);
  }

  if (w.minute >= DAY_END) {
    out.entries = lifeEndDay(s, c);
    out.dayEnded = true;
    return out;
  }

  // 关口：早上醒来不久，轮得到的人一起面对
  if (worldMilestoneDue(s) && w.minute >= MILESTONE_AT && worldMilestone(s, c, out)) return out;

  // 触发命运：mirror 需要两人都空闲、都在 where
  if (w.fate.mirror && w.done.indexOf(w.fate.mirror) < 0) {
    var mev = lifeFindEvent(c, w.fate.mirror);
    // 在线的人要自己走到那里；离线的影子只要没睡着，就会被「叫过来」
    var anyOnline = roles.some(function (r) { return online[r]; });
    var available = function (r: Role) {
      var x = w.actors[r]!;
      if (online[r]) return worldIdle(x) && worldInZone(c, x, mev.where);
      if (anyOnline) return !x.asleep;
      return !x.asleep && worldInZone(c, x, mev.where);
    };
    if (roles.length === 2 && worldInWindow(mev, w.minute) && roles.every(available)) {
      var anchor: Actor | null = null;
      for (var q0 = 0; q0 < roles.length; q0++) if (online[roles[q0]]) anchor = w.actors[roles[q0]];
      for (var q = 0; q < roles.length; q++) {
        var ax = w.actors[roles[q]]!;
        if (ax.action) { ax.action = null; ax.spot = null; ax.until = null; }
        if (!online[roles[q]] && anchor) { ax.x = anchor.x + 50; ax.y = anchor.y; }
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
    var ok = sev.where ? worldInZone(c, w.actors[role], sev.where) : w.minute >= DAY_START + 15;
    if (ok && worldIdle(w.actors[role]) && worldInWindow(sev, w.minute)) {
      w.event = { eventId: sev.id, kind: "solo", roles: [role], choices: {}, shadow: [] };
      out.started = w.event;
      return out;
    }
  }
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
