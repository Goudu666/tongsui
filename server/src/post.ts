// 写信：一个人去了外地（念书、出国、当兵、上班），两个人分在两张图上，互相看不见，靠信。
// 纯函数，不依赖 Nakama。文字在 content/letters.yaml。
//
//   写    外地邮局的信筒、楼下小卖部门口的邮筒，「写信」做完一段（world.ts 的 worldFinish 调 postWrite）。
//         只有两个人分在两片（一个在外地那一片醒来，一个在河畔里）时才写得了（postApart）。
//   到    第二天早上到对门手里（出国的多走一天）：挂在「这一天过去了」那条日志的 post 上（sim.ts 的 lifeEndDay 调 postDeliver），
//         收信的人心情好一点，两个人亲近一点；同一天两个人都写了，信在路上错过去，再多一点默契。
//
// 状态：LifeState.post（可选，路上还没到的信；用到时才建，旧存档没有也不用升版本）、LogEntry.post（到了的信，旧安装包不认识就不画）。

/**
 * 收到一封信：亲近和心情。信是「隔着远还在」的那根线：能让分在两片的生分慢下来，大约抵一半，抵不平
 * （一个外地一个本地、天天写的机器人，七十岁的亲近：一直在本地 59 / 不写信 48 / 每封 2 → 59 抵平了 / 1.5 → 56 / 1 → 52）
 */
var POST_CLOSE = 1.5;
var POST_MOOD = 6;
/** 两封信在路上错过去：默契 */
var POST_CROSSED_SYNC = 2;
/** 出国的信多走几天 */
var POST_ABROAD_DAYS = 1;

interface LetterContent {
  lines: { [k: string]: string[] };
  ends: { text: string; in: "away" | "home" | null }[];
  crossed: string;
}

interface Letter {
  from: Role;
  /** 哪一天写的、哪一天早上到（到的那天的前一天结束时送到） */
  turn: number;
  due: number;
  lines: string[];
  /** 写信的人在哪一片：away 外地 / home 河畔里 */
  side: "away" | "home";
}

interface DeliveredLetter {
  from: Role;
  to: Role;
  /** 写信那天的标签（「21 岁」） */
  label: string;
  lines: string[];
  side: "away" | "home";
}

interface Content { letters: LetterContent }
interface LifeState { post?: Letter[]; postSent?: { [R in Role]?: number } }
interface LogEntry { post?: DeliveredLetter[]; crossed?: string }

/** 这个人醒来的那一片是不是外地（world.ts 的 worldHomeBed） */
function postSideOf(s: LifeState, c: Content, role: Role): "away" | "home" {
  return lifeFind(c.map.scenes, worldHomeBed(s, c, role).scene).far ? "away" : "home";
}

/** 两个人分在两片：一个在外地醒来，一个在河畔里。对门不在了也写不了 */
function postApart(s: LifeState, c: Content, role: Role): boolean {
  var o = lifeOther(role);
  if (!s.persons![o].alive || !s.persons![role].alive) return false;
  return postSideOf(s, c, role) !== postSideOf(s, c, o);
}

/** 今天已经写过一封了 */
function postWroteToday(s: LifeState, role: Role): boolean {
  var list = s.post || [];
  for (var i = 0; i < list.length; i++) if (list[i].from === role && list[i].turn === s.turn) return true;
  return false;
}

/** 写一封：两句近况按写信的人在过的日子挑，一句结尾。按顺序轮着用（不吃随机数） */
function postWrite(s: LifeState, c: Content, role: Role) {
  if (!postApart(s, c, role) || postWroteToday(s, role)) return;
  var L = c.letters;
  var p = s.persons![role];
  var age = lifeTimeAt(s.turn).age;
  var side = postSideOf(s, c, role);
  var tr = lifeTrack(c, p, age);
  // 家境的变体（课余打工、放了学帮家里，docs/MEANS.md 第八、九节）写的 group 是原来那条：信照原来那条挑
  var pool = L.lines[tr.id] || (tr.group ? L.lines[tr.group] : null) || L.lines[side === "away" ? "work" : "home"];
  var ends = L.ends.filter(function (e) { return e.in === null || e.in === side; });
  if (!s.postSent) s.postSent = {};
  var n = s.postSent[role] || 0;
  s.postSent[role] = n + 1;
  var a = (n * 2) % pool.length, b = (n * 2 + 1) % pool.length;
  var lines = [pool[a]];
  if (b !== a) lines.push(pool[b]);
  lines.push(ends[n % ends.length].text);
  var days = tr.id === "uni_abroad" ? 1 + POST_ABROAD_DAYS : 1; // 下一个日子的早上到；出国的再晚一个
  if (!s.post) s.post = [];
  s.post.push({ from: role, turn: s.turn, due: s.turn + days, lines: lines, side: side });
}

/**
 * 一天结束、换天之前（turn 已经加了一）：今天早上该到的信送到。挂在「这一天过去了」那条日志上，
 * 收信的人不在了就不送（信放下）
 */
function postDeliver(s: LifeState, c: Content, day: LogEntry) {
  if (!s.post || s.post.length === 0) return;
  var keep: Letter[] = [];
  var got: DeliveredLetter[] = [];
  for (var i = 0; i < s.post.length; i++) {
    var l = s.post[i];
    if (l.due > s.turn) { keep.push(l); continue; }
    var to = lifeOther(l.from);
    if (!s.persons![to].alive) continue;
    got.push({ from: l.from, to: to, label: lifeTimeAt(l.turn).label, lines: l.lines, side: l.side });
    lifeApplySelf(s.persons![to], { mood: POST_MOOD });
    lifeApplyBond(s, c, { close: POST_CLOSE });
  }
  s.post = keep;
  if (got.length === 0) return;
  day.post = got;
  if (got.length === 2 && got[0].from !== got[1].from) {
    day.crossed = c.letters.crossed;
    lifeApplyBond(s, c, { sync: POST_CROSSED_SYNC });
  }
}
