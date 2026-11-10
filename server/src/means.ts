// 家底：两家人的家境差在哪（设计说明见 docs/MEANS.md）
//
// 家境本身只是两个标记（fam_rich / fam_poor），能走哪些路写在内容里：关口选项的 requires，行动的 requires.flags。
// 这里只管一条规矩：「带上对门」。
//
//   行动标了 bring 的（学琴、补习班、厂里的澡堂），标记不够的人本来做不了。
//   可要是对门正在同一个点做这件事，走过去就能跟着做：两个人是搭伴，长得一样快，
//   两份钱都记在带的那个人头上。家里有的东西能分给对门一半，但得是两个人凑到一块儿的时候。
//
// 影子不带人（人不在不替人花钱），也不被带（worldShadowGo 跳过要人带的事）。
// 进门的钱都是定下这一段时付的（worldAct）：被带的那份从带的人兜里扣，改主意退回给带的人（worldCancel）。
// 带的人改了主意，跟着来的那个一起撤（meansHostLeft），不然对门要替一件不存在的事付钱。

/** role 现在能不能被对门带着做 act（在 sp 这个点）。只看「带」这一条：年纪、钟点照常由调用方判 */
function meansGuestOk(s: LifeState, c: Content, role: Role, sp: Spot, act: Action): boolean {
  if (!act.bring || act.duty || act.sleep) return false;
  var w = s.world;
  if (!w) return false;
  var host = lifeOther(role);
  var b = w.actors[host];
  var hp = s.persons![host];
  if (!b || !hp.alive || b.shadow || b.guest) return false;
  if (b.action !== act.id || b.spot !== sp.id) return false;
  var rq = act.requires || {};
  return lifeHasAll(hp.flags, rq.flags) && lifeHasNone(hp.flags, rq.notFlags);
}

/** 这个人自己的标记够不够做 act：不够的话，只能被对门带着做 */
function meansNeedsHost(p: Person, act: Action): boolean {
  var rq = act.requires || {};
  return !lifeHasAll(p.flags, rq.flags) || !lifeHasNone(p.flags, rq.notFlags);
}

/** 钱够不够：被带着做的，看对门兜里还有没有这一份（对门自己那份定的时候已经付了）。够返回 null */
function meansCantPay(s: LifeState, role: Role, act: Action, guest: boolean): string | null {
  if (act.money >= 0) return null;
  if (!guest) return s.persons![role].money < -act.money ? "兜里的钱不够" : null;
  return s.persons![lifeOther(role)].money < -act.money ? "对门这回也掏不起了" : null;
}

/** role 刚撤了这一段的打算：对门要是被 role 带着做这件事，也撤回来，那份钱退给 role */
function meansHostLeft(s: LifeState, c: Content, role: Role) {
  var w = s.world;
  if (!w) return;
  var other = lifeOther(role);
  var b = w.actors[other];
  if (!b || !b.guest || !b.action || b.from !== w.slot) return;
  var act = worldFindAction(c, b.action);
  if (act.money < 0) s.persons![role].money -= act.money;
  worldClearAction(b);
}

/** 客户端那张「走得进去的」单子里，加上对门这会儿带得了你的事（对门正在做、你自己没那个标记） */
function meansGuestUnlocks(s: LifeState, c: Content, role: Role): string[] {
  var w = s.world;
  if (!w) return [];
  var b = w.actors[lifeOther(role)];
  if (!b || !b.action || !b.spot) return [];
  var out: string[] = [];
  for (var i = 0; i < c.map.spots.length; i++) {
    var sp = c.map.spots[i];
    if (sp.id !== b.spot) continue;
    for (var j = 0; j < sp.actions.length; j++) {
      var act = worldFindAction(c, sp.actions[j]);
      if (meansGuestOk(s, c, role, sp, act)) out.push(act.id);
    }
  }
  return out;
}
