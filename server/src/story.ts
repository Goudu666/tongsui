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
// 一章三件按岁数摊开：第 k 件从「章首 + (k−1)/3 章长」那年起才会排上（章长最多算 15 年，第七章 60~74）。
// 排上了就占掉当天命运的那一格（mirror 或这个人的 solo），在纸带上写「下一件事」。走到那张图、那一段才发生。
// 一直没去：章里剩下的日子不比剩下的件数多的时候，一早强制发生（fate.force）。
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

/** 第 k 件（从 0 起）从几岁起排得上 */
function storyOpenAge(ch: StoryChapter, k: number, count: number): number {
  var span = storyChapterLast(ch) - ch.ages[0] + 1;
  return ch.ages[0] + Math.floor((k * span) / Math.max(count, 1));
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

/** 从今天起，这一章还剩几个日子（数到 limit 为止） */
function storyDaysLeft(turn: number, last: number, limit: number): number {
  var n = 0;
  while (n <= limit && lifeTimeAt(turn + n).age <= last) n++;
  return n;
}

/**
 * 今天的主线：{ mirror, qing, mei, force }。挑法同 test/mainline.test.mjs：两个人都在、又在同一件上，
 * 先找头一个够得着的 mirror（两个人标记的并集）；没有就每人各找头一个够得着的 solo（只看自己，alone = 对门不在了）。
 */
function storyToday(s: LifeState, c: Content, t: TimeInfo): { mirror: string | null; qing: string | null; mei: string | null; force: string[] } {
  var out = { mirror: null as string | null, qing: null as string | null, mei: null as string | null, force: [] as string[] };
  var n = storyChapterAt(c, t.age);
  if (n === 0) return out;
  var ch = c.story.chapters[n - 1];
  var beats = storyBeats(c, n);
  var persons = s.persons!;
  var tt: TimeInfo = { age: t.age, stage: t.stage, season: null } as TimeInfo;
  var at: { [R in Role]?: number } = {};
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    if (!persons[r].alive) continue;
    var k = storyNextBeat(s, beats, r);
    if (k < beats.length && t.age >= storyOpenAge(ch, k, beats.length)) at[r] = k;
  }
  var left = function (r: Role) {
    var remain = beats.length - at[r]!;
    return storyDaysLeft(s.turn, storyChapterLast(ch), remain) <= remain;
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
