// 主线：七章，每章三件一定会发生的事（content/story.yaml，tools/build-content.mjs 校验后原样带进 CONTENT.story）。
// 上面是类型，下面是引擎：怎么挑变体、纸带上的「下一件事」、章末强制发生（挑法和 test/mainline.test.mjs 一致）。

type StoryScene = "building" | "street" | "river" | "primary" | "middle" | "across" | "away" | "newhome" | "rental" | "park" | "hospital";
type StorySlot = "morning" | "am" | "pm" | "evening" | "night";

interface StoryChapter {
  id: string;
  title: string;
  /** [起始岁, 结束岁]，章和章首尾相接 */
  ages: number[];
  /** 这一章新开的地图 */
  opens: StoryScene[];
  /** 章首那一句 */
  intro: string;
  /** 收尾的关口（落在这一章里，或下一章的头一天） */
  closes: string[];
}

interface StoryOption extends EventOption {
  /** 只看选的那个人自己的标记（同关口选项） */
  requires: { flags?: string[]; notFlags?: string[] };
  /** 选了花掉的积蓄 */
  cost?: number;
}

interface StoryEvent extends LifeEvent {
  chapter: number;
  beat: number;
  scene: StoryScene;
  slot: StorySlot;
  /** 纸带上「下一件事」 */
  next: string;
  /** 顶替随机池里的哪些旧事件 */
  replaces: string[];
  options: StoryOption[];
}

interface StoryContent {
  chapters: StoryChapter[];
  events: StoryEvent[];
}

interface Content { story: StoryContent }

// ---------- 引擎 ----------
//
// 进度不另存：长卷里出现过某一件的哪个变体，这一件就算过了（lifeSeenIds）。所以老存档不用升级。
// 一章三件按这一章的日子摊开：这一章空着的日子（关口那天不算）有 D 个，第 k 件从第 ⌊(k−1)(D−1)/3⌋ 个起排上
//   （章长最多算 15 年，第七章 60~74）。中年以后一个日子是三五年，按岁数摊的话第三件排上那天就是章里最后一天。
//   关口那天（到了那个年纪的第一天）不排主线：考试、报到是那天早上的事。
// 排上了就占掉当天命运的那一格（mirror 或这个人的 solo），在纸带上写「下一件事」。走到那张图、那一段才发生。
// 过完一件，同一天后面的段还能接着排下一件（中老年一个日子是三五年，第七章只有一个空着的日子）。
// 一直没去：章里剩下的空日子不比剩下的件数多的时候，这一天到了它自己那一段就强制发生（fate.force），
//   人放到那张图上；那一段已经过去了（或者人都睡下了）才马上发生。
// 只欠这一章的：中途接进来的老存档，前几章没过的不补。

var STORY_SLOT_IDS: StorySlot[] = ["morning", "am", "pm", "evening", "night"];
var STORY_SPAN_MAX = 15;

function storyIs(ev: LifeEvent | null | undefined): ev is StoryEvent {
  return !!ev && (ev as StoryEvent).chapter !== undefined;
}

function storyFindEvent(c: Content, id: string): StoryEvent | null {
  var list = c.story ? c.story.events : [];
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
  return null;
}

/** 这个岁数在第几章（从 1 起；没有就是 0） */
function storyChapterAt(c: Content, age: number): number {
  var chs = c.story ? c.story.chapters : [];
  for (var i = 0; i < chs.length; i++) if (age >= chs[i].ages[0] && age <= chs[i].ages[1]) return i + 1;
  return 0;
}

/** 这一章最后排得上的那一岁（第七章到死，排法上按 15 年算） */
function storyChapterLast(ch: StoryChapter): number {
  return Math.min(ch.ages[1], ch.ages[0] + STORY_SPAN_MAX - 1);
}

/** 第 n 章的几件事，每件是一串变体（按文件顺序） */
function storyBeats(c: Content, n: number): StoryEvent[][] {
  var out: StoryEvent[][] = [];
  var list = c.story ? c.story.events : [];
  for (var i = 0; i < list.length; i++) {
    var e = list[i];
    if (e.chapter !== n) continue;
    while (out.length < e.beat) out.push([]);
    out[e.beat - 1].push(e);
  }
  return out;
}

/** 这个日子是不是关口那天：到了有关口的那个年纪的第一天 */
function storyMilestoneDay(c: Content, turn: number): boolean {
  var age = lifeTimeAt(turn).age;
  var ms = lifeMilestoneAt(c, age);
  return !!ms && !ms.withStory && (turn === 0 || lifeTimeAt(turn - 1).age < age);
}

/** 这一章的日子（withMilestones 为假时关口那天不算），按先后 */
function storyChapterDays(c: Content, ch: StoryChapter, withMilestones: boolean): number[] {
  var last = storyChapterLast(ch);
  var out: number[] = [];
  for (var t = 0; t < 400; t++) {
    var age = lifeTimeAt(t).age;
    if (age > last) break;
    if (age >= ch.ages[0] && (withMilestones || !storyMilestoneDay(c, t))) out.push(t);
  }
  return out;
}

/**
 * 这一章紧：不算关口那天，空着的日子比要过的事还少。第七章就是这样：60 岁以后五年一个日子，60、65、70 里
 * 60 退休、70 七十都是关口，只剩 65 一天，三件事（公园、挖盒子、长椅）原来全挤在 65 岁那一天、一件接一件硬塞。
 * 紧的章关口那天也排（关口在早上，主线在它写的那一段），一天一件：退休那天去公园，65 挖盒子，70 岁傍晚坐长椅。
 */
function storyTight(c: Content, ch: StoryChapter): boolean {
  var n = c.story ? c.story.chapters.indexOf(ch) + 1 : 0;
  return n > 0 && storyChapterDays(c, ch, false).length < storyBeats(c, n).length;
}

/** 这一章能排主线的日子（关口那天不算；紧的章算上），按先后 */
function storyFreeDays(c: Content, ch: StoryChapter): number[] {
  return storyChapterDays(c, ch, storyTight(c, ch));
}

/** 第 k 件（从 0 起）从哪个日子起排得上：按这一章空着的日子摊开。紧的章一天一件 */
function storyOpenTurn(c: Content, ch: StoryChapter, k: number, count: number): number {
  var days = storyFreeDays(c, ch);
  if (days.length === 0) return 0;
  if (storyTight(c, ch)) return days[Math.min(k, days.length - 1)];
  return days[Math.floor((k * (days.length - 1)) / Math.max(count, 1))];
}

/** 随机池里被主线顶替掉的旧事件（旧 id 不删：存档、传承还引用着） */
function storyReplaced(c: Content): { [id: string]: boolean } {
  var out: { [id: string]: boolean } = {};
  var list = c.story ? c.story.events : [];
  for (var i = 0; i < list.length; i++) for (var j = 0; j < list[i].replaces.length; j++) out[list[i].replaces[j]] = true;
  return out;
}

/** 这个人这一章该过第几件（从 0 起；这一章都过完了返回件数） */
function storyNextBeat(s: LifeState, beats: StoryEvent[][], role: Role): number {
  var seen = lifeSeenIds(s, role);
  for (var k = 0; k < beats.length; k++) {
    var done = false;
    for (var j = 0; j < beats[k].length; j++) if (seen[beats[k][j].id]) done = true;
    if (!done) return k;
  }
  return beats.length;
}

/** 从今天起，这一章还剩几个能排主线的日子（关口那天不算，tight 时算；数到 limit 为止） */
function storyDaysLeft(c: Content, turn: number, last: number, limit: number, tight?: boolean): number {
  var n = 0;
  for (var k = 0; n <= limit && lifeTimeAt(turn + k).age <= last; k++) if (tight || !storyMilestoneDay(c, turn + k)) n++;
  return n;
}

/**
 * 今天的主线：{ mirror, qing, mei, force }。挑法同 test/mainline.test.mjs：两个人都在、又在同一件上，
 * 先找头一个够得着的 mirror（两个人标记的并集）；没有就每人各找头一个够得着的 solo（只看自己，alone = 对门不在了）。
 */
function storyToday(s: LifeState, c: Content, t: TimeInfo, milestone: boolean): { mirror: string | null; qing: string | null; mei: string | null; force: string[] } {
  var out = { mirror: null as string | null, qing: null as string | null, mei: null as string | null, force: [] as string[] };
  var n = storyChapterAt(c, t.age);
  if (n === 0) return out;
  var ch = c.story.chapters[n - 1];
  var tight = storyTight(c, ch);
  if (milestone && !tight) return out; // 关口那天让给关口（紧的章除外，见 storyTight）
  var beats = storyBeats(c, n);
  var persons = s.persons!;
  var tt: TimeInfo = { age: t.age, stage: t.stage, season: null } as TimeInfo;
  var at: { [R in Role]?: number } = {};
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    if (!persons[r].alive) continue;
    var k = storyNextBeat(s, beats, r);
    if (k < beats.length && s.turn >= storyOpenTurn(c, ch, k, beats.length)) at[r] = k;
  }
  var left = function (r: Role) {
    var remain = beats.length - at[r]!;
    return storyDaysLeft(c, s.turn, storyChapterLast(ch), remain, tight) <= remain;
  };
  if (persons.qing.alive && persons.mei.alive && at.qing !== undefined && at.qing === at.mei) {
    var both = persons.qing.flags.concat(persons.mei.flags);
    var vs = beats[at.qing];
    for (var j = 0; j < vs.length; j++) {
      if (vs[j].kind === "mirror" && lifeEligible(vs[j], tt, both, {}, { bond: s.bond, alone: false })) { out.mirror = vs[j].id; break; }
    }
    if (out.mirror) {
      if (left("qing") || left("mei")) out.force.push(out.mirror);
      return out;
    }
  }
  for (var q = 0; q < ROLES.length; q++) {
    var role = ROLES[q];
    if (at[role] === undefined) continue;
    var alone = !persons[lifeOther(role)].alive;
    var list = beats[at[role]!];
    for (var m = 0; m < list.length; m++) {
      if (list[m].kind === "solo" && lifeEligible(list[m], tt, persons[role].flags, {}, { bond: s.bond, alone: alone })) { out[role] = list[m].id; break; }
    }
    if (out[role] && left(role)) out.force.push(out[role]!);
  }
  return out;
}

/** 这个人今天还没过的主线事件在哪张图（那张图今天给他开着：第一次自己过桥就是主线带过去的） */
function storySceneToday(s: LifeState, c: Content, role: Role): string | null {
  var w = s.world;
  if (!w) return null;
  var ids = [w.fate.mirror, w.fate[role]];
  for (var i = 0; i < ids.length; i++) {
    var e = ids[i] ? storyFindEvent(c, ids[i]!) : null;
    if (e && w.done.indexOf(e.id) < 0) return e.scene;
  }
  return null;
}

/** 事件这时候能不能在这儿发生：主线看图和那一段，随机的看地点和钟点 */
function storyHere(c: Content, ev: LifeEvent, a: Actor | null): boolean {
  if (!a) return false;
  if (storyIs(ev)) { var sc = worldSceneAt(c, a.y); return !!sc && sc.id === ev.scene; }
  return worldInZone(c, a, ev.where);
}

function storyNow(ev: LifeEvent, slot: number): boolean {
  if (storyIs(ev)) return STORY_SLOT_IDS[slot] === ev.slot;
  return worldOverlaps(ev.when, slot);
}

/** 主线事件写的那一段是第几段 */
function storySlotIndex(ev: StoryEvent): number {
  return STORY_SLOT_IDS.indexOf(ev.slot);
}

/** 强制发生时把人放到那张图上：头一个不在别人家的点位 */
function storyPlace(c: Content, scene: string, role: Role): Spot | null {
  for (var i = 0; i < c.map.spots.length; i++) {
    var sp = c.map.spots[i];
    if (sp.scene !== scene) continue;
    var z = lifeFind(c.map.zones, sp.zone);
    if (!z.owner || z.owner === role) return sp;
  }
  return null;
}

/** 过完一件主线：同一天后面的段还能接着排下一件。随机的那一格已经让给主线了，排不上就空着 */
function storyAfter(s: LifeState, c: Content, eventId: string) {
  var w = s.world;
  if (!w || !storyFindEvent(c, eventId)) return;
  var t = lifeTimeAt(s.turn);
  var next = storyToday(s, c, t, !!w.fate.milestone && !lifeFindEvent(c, w.fate.milestone).withStory); // withStory 的关口那天主线照排
  var slots: ("mirror" | "qing" | "mei")[] = ["mirror", "qing", "mei"];
  for (var i = 0; i < slots.length; i++) {
    var cur = w.fate[slots[i]];
    var mine = cur ? storyFindEvent(c, cur) : null;
    // 排得上下一件，那一格就换成它（哪怕那一格还是没发生的随机事件）；排不上，只把过完的主线清掉，没发生的随机事件留着
    if (next[slots[i]]) w.fate[slots[i]] = next[slots[i]];
    else if (mine && w.done.indexOf(mine.id) >= 0) w.fate[slots[i]] = null;
  }
  // 两个人这一件合着过完了，下一件是各自的：mirror 那一格空出来
  if (next.mirror === null && w.fate.mirror && storyFindEvent(c, w.fate.mirror) && w.done.indexOf(w.fate.mirror) >= 0) w.fate.mirror = null;
  w.fate.force = next.force.length ? next.force : undefined;
  if (!w.fate.force) delete w.fate.force;
}

/** 纸带：这一章、今天的下一件事（每个人一句，mirror 两个人是同一句） */
function storyView(s: LifeState, c: Content): { chapter: number; title: string; intro: string; next: { [R in Role]?: string | null }; force: boolean } | null {
  var w = s.world;
  if (!w || !c.story) return null;
  var n = storyChapterAt(c, lifeTimeAt(s.turn).age);
  if (n === 0) return null;
  var ch = c.story.chapters[n - 1];
  var next: { [R in Role]?: string | null } = {};
  var force = false;
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    next[r] = null;
    var ids = [w.fate.mirror, w.fate[r]];
    for (var j = 0; j < ids.length; j++) {
      var e = ids[j] ? storyFindEvent(c, ids[j]!) : null;
      if (e && w.done.indexOf(e.id) < 0 && (e.kind === "solo" || j === 0)) {
        next[r] = e.next;
        if ((w.fate.force || []).indexOf(e.id) >= 0) force = true;
        break;
      }
    }
  }
  return { chapter: n, title: ch.title, intro: ch.intro, next: next, force: force };
}
