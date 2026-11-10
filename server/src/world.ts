// 河畔里的实时世界：共享时钟、走动、行动（吃饭/睡觉/上学/玩）、生存需求、同框、按地点触发事件。
// 纯函数，由 main.ts 的房间每 tick 调用；Node 单测里可以直接驱动。

var DAY_START = 390; // 06:30 醒来
var DAY_END = 1320; // 22:00 撑不住了
var SCHOOL_END = 930; // 15:30 放学
var MIN_PER_SEC = 4; // 现实 1 秒 = 游戏 4 分钟，一天约 4 分钟
var FAST_FORWARD = 10; // 两人都在忙（上学、睡觉、长行动）时时间快进
var WALK_SPEED = 360; // 像素/秒
var SPOT_RADIUS = 110;
var PLAY_ACTIONS = ["play_roof", "play_river", "play_alley"];

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
  }

  // 命运给今天准备的事：mirror 一件（两人都在世时），每人 solo 一件。要走到对的地方才会发生。
  var seen = lifeSeenIds(s);
  var fate: WorldState["fate"] = { mirror: null, qing: null, mei: null };
  var together: EligibleCtx = { bond: s.bond, alone: false };
  if (persons.qing.alive && persons.mei.alive) {
    var both = persons.qing.flags.concat(persons.mei.flags);
    var mirrors = c.events.filter(function (e) { return e.kind === "mirror" && lifeEligible(e, t, both, seen, together); });
    if (mirrors.length > 0 && lifeRand(s) < (t.stage === "childhood" ? 0.6 : 0.45)) {
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

  s.world = {
    minute: DAY_START,
    schoolDay: t.age >= 6 && t.age <= 17 && lifeRand(s) < 0.7,
    actors: actors,
    event: null,
    fate: fate,
    done: [],
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

function worldCanAct(s: LifeState, c: Content, role: Role, spotId: string): string | null {
  if (s.phase !== "life") return "人生还没开始";
  var w = s.world!;
  var a = w.actors[role];
  if (!s.persons![role].alive || a === null) return "你已经不在了";
  if (!worldIdle(a)) return "正在忙";
  if (w.event && w.event.roles.indexOf(role) >= 0) return "先做完眼前的选择";
  var sp: Spot;
  try { sp = lifeFind(c.map.spots, spotId); } catch (e) { return "没有这个地方"; }
  var dx = sp.at[0] - a.x, dy = sp.at[1] - a.y;
  if (dx * dx + dy * dy > SPOT_RADIUS * SPOT_RADIUS) return "走近一点";
  var act = worldFindAction(c, sp.action);
  var rq = act.requires || {};
  var age = lifeTimeAt(s.turn).age;
  if (rq.minAge !== undefined && age < rq.minAge) return "还太小了";
  if (rq.maxAge !== undefined && age > rq.maxAge) return "已经过了那个年纪";
  if (rq.owner && lifeFind(c.map.zones, sp.zone).owner !== role) return "这不是你的家";
  if (rq.hours && (w.minute < rq.hours[0] || w.minute > rq.hours[1])) return "现在不是时候";
  if (act.school && !w.schoolDay) return "今天不上学";
  if (act.money < 0 && s.persons![role].money < -act.money) return "兜里的钱不够";
  return null;
}

/** 开始一个行动。返回 [错误, 同框日志] */
function worldAct(s: LifeState, c: Content, role: Role, spotId: string): { error: string | null; together: LogEntry | null } {
  var err = worldCanAct(s, c, role, spotId);
  if (err) return { error: err, together: null };
  var w = s.world!;
  var a = w.actors[role]!;
  var sp = lifeFind(c.map.spots, spotId);
  var act = worldFindAction(c, sp.action);
  a.x = sp.at[0];
  a.y = sp.at[1];
  a.action = act.id;
  a.spot = sp.id;
  a.shadow = false;
  delete a.boost; // 上一件事没用掉的搭伴倍率不带过来（见 games.ts）
  if (act.sleep) {
    a.asleep = true;
    a.until = null;
  } else if (act.school) {
    a.until = SCHOOL_END;
  } else {
    a.until = w.minute + act.minutes;
  }

  // 同框：对方正在做同一件事
  var together: LogEntry | null = null;
  var b = w.actors[lifeOther(role)];
  var key = "together:" + act.id;
  if (act.together && b && b.action === act.id && !act.sleep && w.done.indexOf(key) < 0) {
    w.done.push(key); // 每种同框每天只算一次
    lifeApplySelf(s.persons!.qing, act.together.needs);
    lifeApplySelf(s.persons!.mei, act.together.needs);
    lifeApplyBond(s, act.together.bond);
    together = lifeEntry(s, "together", act.together.text || "你们一起" + act.label + "。");
    s.log.push(together);
  }
  return { error: null, together: together };
}

function worldFinish(s: LifeState, c: Content, role: Role) {
  var a = s.world!.actors[role]!;
  var act = worldFindAction(c, a.action!);
  var p = s.persons![role];
  var wealth = 1; // 这户人家在新内容里没了（见 save.ts）就按普通家境算
  for (var fi = 0; fi < c.families.length; fi++) if (c.families[fi].id === p.familyId) wealth = c.families[fi].wealth;
  var stats: SelfDelta = {};
  var boost = a.boost || 1; // 搭伴小游戏打出来的倍率，只乘这一次行动长的属性（见 games.ts）
  delete a.boost;
  for (var k in act.stats) (stats as any)[k] = ((act.stats as any)[k] as number) * (act.id === "study" && lifeHasFlag(p, "tal_memory") ? 2 : 1) * boost;
  lifeApplySelf(p, stats);
  lifeApplySelf(p, act.needs);
  if (act.id === "eat") lifeApplySelf(p, { mood: wealth * 3 + (lifeHasFlag(p, "tal_foodie") ? 6 : 0) });
  p.money += act.money;
  a.action = null;
  a.spot = null;
  a.until = null;
}

// ---------- 影子：离线时按需求和习惯自己过日子 ----------

function worldShadowAct(s: LifeState, c: Content, role: Role) {
  var w = s.world!;
  var p = s.persons![role];
  var age = lifeTimeAt(s.turn).age;
  var want: string;
  if (p.needs.hunger < 45) want = w.minute < 600 && p.money >= 2 && lifeRand(s) < 0.3 ? "eat_out" : "eat";
  else if (p.needs.energy < 25 || w.minute >= 1230) want = "sleep";
  else if (w.schoolDay && age >= 6 && age <= 17 && w.minute >= 420 && w.minute <= 540) want = "school";
  else if (p.needs.clean < 30) want = "wash";
  else {
    // 影子会去 TA 在的地方
    var partner = w.actors[lifeOther(role)];
    var zone = partner ? worldZoneAt(c, partner.x, partner.y) : null;
    var there = c.map.spots.filter(function (sp) { return sp.zone === zone && PLAY_ACTIONS.indexOf(sp.action) >= 0; });
    want = there.length > 0 ? there[0].action : PLAY_ACTIONS[Math.floor(lifeRand(s) * PLAY_ACTIONS.length)];
  }
  var spot = worldSpotFor(c, want, role);
  if (!spot) return;
  var a = w.actors[role]!;
  a.x = spot.at[0];
  a.y = spot.at[1];
  if (worldAct(s, c, role, spot.id).error) {
    // 做不了（比如不在上学时间）就回家写作业或发呆
    var fallback = worldSpotFor(c, age >= 6 ? "study" : "knock", role);
    if (fallback) { a.x = fallback.at[0]; a.y = fallback.at[1]; worldAct(s, c, role, fallback.id); }
  }
  if (a.action) a.shadow = true;
}

/** 本人回来了：影子正在做的事（睡觉、上学除外）停下，把身体还给他 */
function worldReclaim(s: LifeState, role: Role): boolean {
  if (s.phase !== "life" || !s.world) return false;
  var a = s.world.actors[role];
  if (!a || !a.shadow) return false;
  a.shadow = false;
  if (!a.action || a.asleep || a.action === "school") return false;
  a.action = null;
  a.spot = null;
  a.until = null;
  return true;
}

// ---------- 需求随时间变化 ----------

function worldDecay(p: Person, a: Actor, minute: number, dm: number) {
  var h = dm / 60;
  var hungerRate = (a.asleep ? 2 : 5) * (lifeHasFlag(p, "tal_foodie") ? 1.4 : 1);
  var energyRate = a.asleep ? -12 : 4;
  if (!a.asleep && lifeHasFlag(p, "tal_owl")) energyRate = minute >= 1200 ? 2 : minute < 480 ? 6 : 4;
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
    worldDecay(s.persons![roles[j]], a, w.minute, dm);
    if (a.until !== null && w.minute >= a.until) worldFinish(s, c, roles[j]);
  }

  if (w.minute >= DAY_END) {
    out.entries = lifeEndDay(s, c);
    out.dayEnded = true;
    return out;
  }

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
  if (!lifeFindOption(ev, optionId)) return { error: "没有这个选项", entry: null };
  w.event.choices[role] = optionId; // 结算前可以改主意
  if (fromShadow && w.event.shadow.indexOf(role) < 0) w.event.shadow.push(role);
  var pe = w.event;
  var missing = pe.roles.filter(function (r) { return !pe.choices[r]; });
  if (missing.length > 0) return { error: null, entry: null };
  var entry = lifeResolveEvent(s, c, pe);
  w.done.push(pe.eventId);
  w.event = null;
  return { error: null, entry: entry };
}
