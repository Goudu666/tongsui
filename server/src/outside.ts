// 门外的世界：三档人家的孩子见到的是三个不同的地方（殷实的去海边，小康的回乡下姥姥家，清贫的跟着家里去早市），
// 生病去的地方不一样，清贫人家的少年家里有人住了院、放了学和歇着的日子都在医院里。
// 接口稿见线程「让不同人家见到不同的世界」的 SPEC.md 第三节；内容在 content/maps/{market,seaside,village}.yaml、content/events/outside.yaml。
//
// 这里的几样：
//   effects.goto       选项结算后把这个人送到那张图上（落在那张图的第一个出口跟前），手上的事撤掉，这一天剩下的日程免了（w.off）。
//                      第二天早上照常在自己床上醒（worldStartDay）。到了那儿，今天这一格空着、过完了、或者排在去不了的图上的，七成再排一件那张图上的小事（outsideFateThere）；
//                      两个人送到了同一张图上，两个人的事（mirror）也照早上的机会再排一件那儿的（outsideMirrorThere）
//   effects.tagAlong   跟着去：对门选的是列出的某一项、那一项带 goto，这个人也被送到同一张图；对门没选就什么也不发生
//   scene.trip         出门才到得了的图：worldSceneLock 一律回「得跟着家里出门才来得了」。
//                      人在这种图上，影子、被叫过去都只在这张图里（worldCanAct 的 anywhere）
//   w.trip[role]       今天 goto 把这个人送到了哪张图：这张图今天对他开着，unlock 说不行也开（六岁的小康孩子跟着对门去早市），
//                      trip 的图也开。新的一天 worldStartDay 换一个 s.world，自然清掉；存档、重连就是 s.world 里一个可选字段
//   scene.seen         来过这张图的人打上这个标记：被送来的、自己走进来的、在那儿做过事的（影子直接到点位上）
//   requires.either    mirror 事件：两个人里至少一个人自己满足（worldStartDay 里按各人自己的标记判，不是两人合起来的）
//   rules.daily.flagDuty  带着某个标记的人日程跟着变（worldDuty 里，返回副本，不改内容对象）
//
// 影子不出门（lifeShadowChoose → outsideShadowStays）：人不在，影子不替他把这一天搭到海边去，也不跟着对门走——
// 不然在线的那个人这一天对着一张空了的图。有别的项能选时，带 goto 或 tagAlong 的项影子都不选。

var OUTSIDE_TRIP_LOCK = "得跟着家里出门才来得了";

/** requires.either：flagsList 里至少有一个人自己满足。没写 either 的事件总是 true */
function outsideEither(ev: LifeEvent, flagsList: string[][]): boolean {
  var e = ev.requires && ev.requires.either;
  if (!e) return true;
  for (var i = 0; i < flagsList.length; i++) if (lifeHasAll(flagsList[i], e.flags) && lifeHasNone(flagsList[i], e.notFlags)) return true;
  return false;
}

/** 今天 goto 把这个人送到的就是这张图（w.trip） */
function outsideSent(s: LifeState, role: Role, sc: Scene): boolean {
  return !!s.world && !!s.world.trip && s.world.trip[role] === sc.id;
}

/** 这个选项带不带人出门（自己去，或者跟着对门去） */
function outsideGoes(o: EventOption): boolean {
  return !!o.effects.goto || !!(o.effects.tagAlong && o.effects.tagAlong.length);
}

/** 影子替选时跳不跳过这一项：带人出门的项，只要还有别的能选就跳过（影子不出门）。open 是这件事里影子能选的项 */
function outsideShadowStays(o: EventOption, open: EventOption[]): boolean {
  if (!outsideGoes(o)) return false;
  for (var i = 0; i < open.length; i++) if (!outsideGoes(open[i])) return true;
  return false;
}

/** 打上这张图的 seen 标记 */
function outsideSeen(s: LifeState, sc: Scene, role: Role) {
  if (sc.seen && s.persons) lifeAddFlags(s.persons[role], [sc.seen]);
}

/** 被送到一张图上站在哪：那张图的第一个出口跟前；没有出口就是第一个不在谁家屋里的点位；都没有就是左头 */
function outsideLanding(c: Content, sc: Scene): [number, number] {
  for (var i = 0; i < c.map.exits.length; i++) if (c.map.exits[i].scene === sc.id) return [c.map.exits[i].at[0], c.map.exits[i].at[1]];
  for (var j = 0; j < c.map.spots.length; j++) {
    var sp = c.map.spots[j];
    if (sp.scene === sc.id && !lifeFind(c.map.zones, sp.zone).owner) return [sp.at[0], sp.at[1]];
  }
  return [40, sc.floors[0]];
}

/**
 * 一件事结算完（worldChoose 里，w.event 已经清掉）：选了 goto 的人、跟着对门去的人，送到那张图上。
 * 先把两个人各去哪算好再送：tagAlong 看的是对门选的项，不是对门送没送到
 */
function outsideAfterEvent(s: LifeState, c: Content, pe: PendingEvent) {
  if (!s.world || pe.kind === "milestone") return;
  var ev = lifeFindEvent(c, pe.eventId);
  var dest: { [R in Role]?: string } = {};
  for (var i = 0; i < pe.roles.length; i++) {
    var r = pe.roles[i];
    var o = lifeFindOption(ev, pe.choices[r] || "");
    if (!o) continue;
    if (o.effects.goto) { dest[r] = o.effects.goto; continue; }
    var tag = o.effects.tagAlong;
    var other = lifeOther(r);
    if (!tag || !tag.length || pe.roles.indexOf(other) < 0) continue;
    var theirs = pe.choices[other];
    var to = theirs && tag.indexOf(theirs) >= 0 ? lifeFindOption(ev, theirs) : null;
    if (to && to.effects.goto) dest[r] = to.effects.goto;
  }
  var first: Actor | null = null;
  for (var k = 0; k < ROLES.length; k++) {
    var role = ROLES[k];
    if (!dest[role]) continue;
    var a = outsideSend(s, c, role, dest[role]!, first);
    if (a) first = a;
  }
  // 两个人今天被送到了同一张图上（叫上对门一块儿去了）：两个人的事也排一件那儿的（招待所的夜里、晒场上的露天电影）
  var w = s.world;
  var persons = s.persons!;
  if (w.trip && w.trip.qing && w.trip.qing === w.trip.mei && persons.qing.alive && persons.mei.alive) outsideMirrorThere(s, c, lifeFind(c.map.scenes, w.trip.qing));
}

/**
 * 两个人都在 sc 上（今天 goto 送来的）：今天的 mirror 空着、过完了、或者排在今天去不了的图上，再排一件这张图上的。
 * 主线不动。只在 where 落在这张图上、轮得到两个人的 mirror 里挑，权重和机会都和早上一样（worldStartDay）
 */
function outsideMirrorThere(s: LifeState, c: Content, sc: Scene) {
  var w = s.world!;
  var cur = w.fate.mirror;
  if (cur && storyFindEvent(c, cur)) return;
  if (cur && w.done.indexOf(cur) < 0) {
    var cev = lifeFindEvent(c, cur);
    if (!cev.where || lifeFind(c.map.zones, cev.where).scene === sc.id) return;
  }
  var persons = s.persons!;
  var t = lifeTimeAt(s.turn);
  var seen = lifeSeenIds(s);
  for (var d = 0; d < w.done.length; d++) seen[w.done[d]] = true;
  var kidAges: number[] = [];
  for (var ki = 0; ki < ROLES.length; ki++) { var ka = kidAgeFor(s, ROLES[ki]); if (ka !== null) kidAges.push(ka); }
  var together: EligibleCtx = { bond: s.bond, alone: false, kidAges: kidAges };
  var both = persons.qing.flags.concat(persons.mei.flags);
  var here = c.events.filter(function (e) {
    return e.kind === "mirror" && !!e.where && lifeFind(c.map.zones, e.where).scene === sc.id
      && lifeEligible(e, t, both, seen, together) && outsideEither(e, [persons.qing.flags, persons.mei.flags]);
  });
  if (!here.length) return;
  var luck = (persons.qing.stats.luck + persons.mei.stats.luck) / 2 - 5;
  if (lifeRand(s) >= (t.stage === "childhood" ? 0.6 : 0.45) + luck * c.rules.daily.luckFate) return;
  w.fate.mirror = lifePickWeighted(s, here, function (e) { return e.weight; })!.id;
}

/** 把这个人送到 sceneId 上。near：同一回送过去的另一个人（挨着站）。返回这个人，送不了返回 null */
function outsideSend(s: LifeState, c: Content, role: Role, sceneId: string, near: Actor | null): Actor | null {
  var w = s.world!;
  var a = w.actors[role];
  if (!a || !s.persons![role].alive) return null;
  var sc: Scene;
  try { sc = lifeFind(c.map.scenes, sceneId); } catch (e) { return null; }
  // 手上的事撤掉：前几段就开始的（日程）结算到这儿，这一段才定的撤回来、进门的钱退回去（同 worldMilestone）
  if (a.action) {
    if (a.from !== undefined && a.from < w.slot) worldFinish(s, c, role);
    else worldCancel(s, c, role);
  }
  worldClearAction(a);
  delete w.ready[role];
  var at = outsideLanding(c, sc);
  a.x = at[0] + (near && near.y === at[1] && Math.abs(near.x - at[0]) < 60 ? 60 : 0);
  a.y = at[1];
  a.shadow = false;
  if (!w.trip) w.trip = {};
  w.trip[role] = sc.id; // 今天这张图对他开着（worldSceneLock）
  if (!w.off) w.off = {};
  w.off[role] = true; // 这一天剩下的日程免了：跟着家里出门了、去医院了
  outsideSeen(s, sc, role);
  outsideFateThere(s, c, role, sc);
  return a;
}

/**
 * 到了那张图上，命运今天给这个人再准备一件那儿的事（海边第一次看见海、姥姥家的压水井）：
 * 早上排事的时候人在床上，出门才到得了的图上的事排不进来（worldStartDay 的 reach 不动），只能到了再排。
 * 今天这一格空着、已经发生过了，或者排的那件在别的图上（今天去不了了），才重排；主线不动，不挑地方的（where 为空）不动。
 * 只在那张图上的 solo 里挑，权重、七成的机会和早上一样；没有轮得到他的就不动
 */
function outsideFateThere(s: LifeState, c: Content, role: Role, sc: Scene) {
  var w = s.world!;
  var cur = w.fate[role];
  if (cur && storyFindEvent(c, cur)) return;
  if (cur && w.done.indexOf(cur) < 0) {
    var cev = lifeFindEvent(c, cur);
    if (!cev.where || lifeFind(c.map.zones, cev.where).scene === sc.id) return;
  }
  var persons = s.persons!;
  var t = lifeTimeAt(s.turn);
  var mine = lifeSeenIds(s, role);
  for (var d = 0; d < w.done.length; d++) mine[w.done[d]] = true;
  var other = lifeOther(role);
  if (w.fate[other]) mine[w.fate[other]!] = true; // 同一天两人不会是同一件
  var ctx: EligibleCtx = { bond: s.bond, alone: !persons[other].alive };
  var ka = kidAgeFor(s, role);
  if (ka !== null) ctx.kidAge = ka;
  var here = c.events.filter(function (e) {
    return e.kind === "solo" && !!e.where && lifeFind(c.map.zones, e.where).scene === sc.id
      && lifeEligible(e, t, persons[role].flags, mine, ctx) && outsideEither(e, [persons[role].flags]);
  });
  if (!here.length || lifeRand(s) >= 0.7) return;
  w.fate[role] = lifePickWeighted(s, here, function (e) { return e.weight; })!.id;
}

/**
 * 带着标记的人今天的日程（rules.yaml → daily.flagDuty）。d 是路上原来的那一段（上学的日子是 duty，歇着的日子是 restDuty）。
 * 上学的日子：拖到 until（只往后拖，不往前），拖了才换 label；歇着的日子：换成 rest（盖过 restDuty）。返回副本，不改内容对象
 */
function outsideFlagDuty(s: LifeState, c: Content, role: Role, d: Duty | null, rest: boolean): Duty | null {
  var fd = c.rules.daily.flagDuty;
  if (!fd) return d;
  var p = s.persons![role];
  var age = lifeTimeAt(s.turn).age;
  for (var f in fd) {
    var x = fd[f];
    if (!lifeHasFlag(p, f) || !lifeInRange(age, x.minAge, x.maxAge)) continue;
    if (rest) {
      if (x.rest) return outsideDutyCopy(x.rest);
      continue;
    }
    // 只往后拖。本来就上到这个钟点的（清贫「上学，放了学帮家里」）不拖，只换 label，看得出放了学去的是医院
    if (!d || x.until === undefined || x.until < d.until) continue;
    var out = outsideDutyCopy(d);
    out.until = x.until;
    if (x.label) out.label = x.label;
    return out;
  }
  return d;
}

function outsideDutyCopy(d: Duty): Duty {
  var out: any = {};
  for (var k in d) out[k] = (d as any)[k];
  if (!out.needs) out.needs = {};
  if (!out.stats) out.stats = {};
  if (typeof out.money !== "number") out.money = 0;
  return out as Duty;
}
