// 家里的东西（content/home.yaml，说明见 docs/HOME.md）
//
// 同一年，三户人家不在同一个年代。一样东西哪一年进这户人家的门，看家境（殷实早、清贫晚或者没有），有的看人家。
// 进了门，这个人身上打 hm_<id>：「这个人爸妈家里有」。事件、关口用 requires.flags 读它；
// 行动用 requires.home 读，看的是**点位那一户**：去对门家，就用对门家的电视、对门家的书。
// 家里没有的，外头有卖的，自己攒钱买（行动的 buys），买回来就是这户人家的。
//
// 年份是日历年（era.ts 的 eraYear：出生年 + 岁数），只在引擎里算。
// 已经进门的东西不收走：家道中落（fam_fallen）以后按小康算新进门的，原来有的照样摆着；gone 那一年家家都收起来。
// 爸妈走了（parent_gone）以后家里不再添东西。

interface HomeItem {
  id: string;
  name: string;
  /** 进门的年份：rich / mid / poor，或者人家 id（压过家境那一档）。没写的那一档一直没有 */
  arrive: { [tierOrFamily: string]: number };
  /** 这一年起家家都收起来了（null = 一直在） */
  gone: number | null;
  text: string;
  buy?: { price: number; from: number; minAge: number };
}

interface Content { home?: { items: HomeItem[] } }

interface Action {
  /** 自己攒钱买这样东西（home.yaml 的 id）。顺手的事，钱数就是价 */
  buys?: string;
}

interface HomeLogInfo { role: Role; item: string; name: string; bought?: boolean }

interface LogEntry { home?: HomeLogInfo }

var HOME_PREFIX = "hm_";

function homeItems(c: Content): HomeItem[] {
  return c.home ? c.home.items : [];
}

function homeFindItem(c: Content, id: string): HomeItem | null {
  var list = homeItems(c);
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
  return null;
}

/** 这户人家按哪一档算：家道中落的没有 fam_rich 了，按小康 */
function homeTier(p: Person): string {
  return lifeHasFlag(p, "fam_rich") ? "rich" : lifeHasFlag(p, "fam_poor") ? "poor" : "mid";
}

/** 这样东西哪一年进这个人家的门（人家写了的压过家境那一档）；一直没有 = null */
function homeArrive(it: HomeItem, p: Person): number | null {
  if (it.arrive[p.familyId] !== undefined) return it.arrive[p.familyId];
  var y = it.arrive[homeTier(p)];
  return y === undefined ? null : y;
}

function homeHas(p: Person, id: string): boolean {
  return lifeHasFlag(p, HOME_PREFIX + id);
}

/** 点位那一户：屋里的点位看屋主，楼道、街上没有屋主的看自己家 */
function homeHolder(s: LifeState, c: Content, sp: Spot, role: Role): Person {
  var owner: Role | undefined;
  for (var i = 0; i < c.map.zones.length; i++) if (c.map.zones[i].id === sp.zone) owner = c.map.zones[i].owner;
  return s.persons![owner || role];
}

/** 这个人家里这会儿有的东西（物件 id） */
function homeList(c: Content, p: Person): string[] {
  var out: string[] = [];
  var list = homeItems(c);
  for (var i = 0; i < list.length; i++) if (homeHas(p, list[i].id)) out.push(list[i].id);
  return out;
}

/**
 * 两家的东西跟上今天的年份：到了年份的进门，过了 gone 的收起来。
 * out 给了就是正常过到新的一天（sim.ts 在 eraTick 后面调）：三岁以后进门的各记一条 kind "home" 的长卷；
 * 不给是开局、跳着过、修过的存档，悄悄补上
 */
function homeSync(s: LifeState, c: Content, out: LogEntry[] | null) {
  var list = homeItems(c);
  if (!list.length || !s.persons || !c.eras || !c.eras.cohorts.length) return;
  var age = lifeTimeAt(s.turn).age;
  var year = eraYear(s, c);
  for (var r = 0; r < ROLES.length; r++) {
    var role = ROLES[r];
    var p = s.persons[role];
    if (!p) continue;
    for (var i = 0; i < list.length; i++) {
      var it = list[i];
      var flag = HOME_PREFIX + it.id;
      var has = lifeHasFlag(p, flag);
      if (it.gone !== null && year >= it.gone) {
        if (has) p.flags = p.flags.filter(function (f) { return f !== flag; });
        continue;
      }
      if (has || !p.alive || lifeHasFlag(p, "parent_gone")) continue;
      var y = homeArrive(it, p);
      if (y === null || year < y) continue;
      p.flags.push(flag);
      if (out && age >= 3) homeLog(s, out, role, it, false);
    }
  }
}

function homeLog(s: LifeState, out: LogEntry[] | null, role: Role, it: HomeItem, bought: boolean) {
  var e = lifeEntry(s, "home", it.text);
  e.home = { role: role, item: it.id, name: it.name };
  if (bought) e.home.bought = true;
  if (out) out.push(e);
  s.log.push(e);
}

/** role 现在能不能在 sp 买 act 要的那样东西。能返回 null */
function homeCantBuy(s: LifeState, c: Content, role: Role, sp: Spot | null, act: Action): string | null {
  var it = act.buys ? homeFindItem(c, act.buys) : null;
  if (!it || !it.buy || !s.persons) return "外头没有卖的";
  var p = s.persons[role];
  if (sp && homeHolder(s, c, sp, role) !== p) return "这不是你的家";
  if (homeHas(p, it.id)) return "家里已经有了";
  var year = eraYear(s, c);
  if (year < it.buy.from) return "外头还没有卖的";
  if (it.gone !== null && year >= it.gone) return "早就没人用这个了";
  if (lifeTimeAt(s.turn).age < it.buy.minAge) return "还太小了";
  return null;
}

/** 买回来了（钱 worldAct 已经扣了）：这户人家有了，记一条长卷 */
function homeBuy(s: LifeState, c: Content, role: Role, act: Action): LogEntry | null {
  var it = act.buys ? homeFindItem(c, act.buys) : null;
  if (!it || !s.persons) return null;
  var p = s.persons[role];
  if (!homeHas(p, it.id)) p.flags.push(HOME_PREFIX + it.id);
  var e = lifeEntry(s, "home", "自己攒的钱，搬回来一台" + it.name + "。");
  e.home = { role: role, item: it.id, name: it.name, bought: true };
  s.log.push(e);
  return e;
}

/** role 这会儿在自己家买得了的（buy_* 行动 id）：客户端拿它决定屋里显示不显示「攒钱买」 */
function homeBuyList(s: LifeState, c: Content, role: Role): string[] {
  var out: string[] = [];
  for (var i = 0; i < c.map.actions.length; i++) {
    var a = c.map.actions[i];
    if (a.buys && !homeCantBuy(s, c, role, null, a)) out.push(a.id);
  }
  return out;
}

/** WORLD 里的 homes：两户人家这会儿各有什么（客户端照着摆屋里的东西、判 requires.home） */
function homeView(s: LifeState, c: Content): { [R in Role]: string[] } {
  return { qing: s.persons ? homeList(c, s.persons.qing) : [], mei: s.persons ? homeList(c, s.persons.mei) : [] };
}
