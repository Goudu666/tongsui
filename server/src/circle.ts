// 人际圈子：认识谁，决定能求谁（设计说明见 docs/CIRCLE.md）。纯函数，不依赖 Nakama。
//
// 门路是标记（tie_*，content/circle.yaml）。来路三条：
//   - 生下来就有：families.yaml 的 traits（林家爸妈是老师 → tie_school，赵家楼长 → tie_house，陈家修车、周家早点铺 → tie_street）
//   - 自己走动：map.yaml 里带 tie 的行动（放了学留下来帮老师、给楼里搭把手、跟家里去走亲戚、请人吃饭），做够 times 回认下。
//     这里只记数：Person.ties（可选字段，用到时才建，旧存档没有也不用升版本）。有了这个门路就不再记，
//     认下那一回在 did 上挂 tie（客户端飘「老师记住你了」），没认下的挂 tp（「帮老师 3/6」）
//   - 事件给的：events/circle.yaml（家长会、爷爷的老关系）
// 用在关口上（milestones.yaml 里 requires tie_* 的路）：内容里 drop 掉、打上 owe_*（欠的人情），后面有事来讨。
// 换了学校就换了老师：circle.yaml 里写了 fade 的门路，过了那几道关摘掉（sim.ts 的 lifeResolveEvent 调 circleFade）。
//
// 带 tie 的行动都是 menu（build-content 校验）：机器人、影子、旧安装包永远不走动，校准过的活法数不动。
// 被对门带着去走亲戚（bring，means.ts）的那个人也记一回：对门家的亲戚也就认得你了。

interface CircleTie { id: string; label: string; walk: string; fade: string[] }
interface CircleContent { ties: CircleTie[]; owes: string[] }
interface Content { circle?: CircleContent }
interface Person {
  /** 人际圈子（circle.ts）：攒到第几回的门路，tie_* → 回数（可以是小数：一段剩下的时间不够做完一整回） */
  ties?: { [flag: string]: number };
}
interface Did {
  /** 这一回认下的门路：{ f: tie_*, l: 飘的字 } */
  tie?: { f: string; l: string };
  /** 还在攒：[第几回, 要几回, 飘的字的前半截] */
  tp?: [number, number, string];
}

function circleTie(c: Content, flag: string): CircleTie | null {
  var list = c.circle ? c.circle.ties : [];
  for (var i = 0; i < list.length; i++) if (list[i].id === flag) return list[i];
  return null;
}

/**
 * 做完一回（或几回）带 tie 的事：记数，够了就认下。times 是这一回做了几遍（一件一件做是 use / minutes，整段是 scale）。
 * 返回给 did 挂的那一截（没有 tie 的事返回 null）
 */
function circleWalk(c: Content, p: Person, act: Action, times: number): { tie?: { f: string; l: string }; tp?: [number, number, string] } | null {
  var t = act.tie;
  if (!t || !(times > 0)) return null;
  if (lifeHasFlag(p, t.flag)) return null; // 已经认下了：再走动也不多一样
  var def = circleTie(c, t.flag);
  if (!p.ties) p.ties = {};
  var n = Math.round(((p.ties[t.flag] || 0) + times) * 100) / 100;
  if (n >= t.times - 1e-6) {
    delete p.ties[t.flag];
    lifeAddFlags(p, [t.flag]);
    return { tie: { f: t.flag, l: def ? def.label : t.flag } };
  }
  p.ties[t.flag] = n;
  return { tp: [Math.floor(n * 10) / 10, t.times, def ? def.walk : t.flag] };
}

/** 过了一道关：circle.yaml 里写了在这一关 fade 的门路摘掉，攒到一半的也清零（换了学校，换了老师） */
function circleFade(c: Content, ev: LifeEvent, p: Person) {
  var list = c.circle ? c.circle.ties : [];
  for (var i = 0; i < list.length; i++) {
    if (list[i].fade.indexOf(ev.id) < 0) continue;
    lifeDropFlags(p, [list[i].id]);
    if (p.ties) delete p.ties[list[i].id];
  }
}
