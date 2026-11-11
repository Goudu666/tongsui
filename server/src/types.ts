// 全局类型（Nakama JS 运行时不支持 ES Module，所有文件都是全局脚本，最后由 tsc 拼成一个 build/index.js）

type Role = "qing" | "mei";
type Stage = "childhood" | "teen" | "young" | "middle" | "old";
type Season = "spring" | "summer" | "autumn" | "winter";
type StatKey = "body" | "mind" | "charm" | "luck";
type NeedKey = "hunger" | "energy" | "mood" | "clean";
type BondKey = "sync" | "close" | "distance";

type Stats = { [K in StatKey]: number };
type Needs = { [K in NeedKey]: number };
type Bond = { [K in BondKey]: number };
type SelfDelta = Partial<Stats> & Partial<Needs>;
type Choices = { [R in Role]?: string };

// ---------- 内容（由 content/*.yaml 生成） ----------

interface OptionEffects {
  self: SelfDelta;
  other: SelfDelta;
  bond: Partial<Bond>;
  flags: string[];
}

interface EventOption {
  id: string;
  text: string;
  tags: string[];
  effects: OptionEffects;
  /** 只有关口（milestone）用：得分达到 min 才能选；score 不写就用关口自己的算法；cost 是选了以后花掉的积蓄 */
  min?: number;
  score?: ScoreWeights;
  cost?: number;
  requires?: { flags?: string[]; notFlags?: string[] };
  /** 标记不对的人看到的那句话（「家里拿不出这笔钱」）；不写就是「这条路不是给你留的」 */
  lock?: string;
  /** 和哪条路是同一条（花钱进的重点和考进去的同校）：两个人一个走这条、一个走那条，也算同路 */
  joins?: string;
}

/** 关口怎么算分：各项属性乘权重相加；money 表示积蓄 */
type ScoreWeights = Partial<Stats> & { money?: number; close?: number };

/** 关口的成绩档：从高到低，取第一个够得着的。和「选了哪条路」分开记：成绩是事实，路是选择 */
interface Grade {
  min: number;
  label: string;
  flags: string[];
}

interface LifeEvent {
  id: string;
  /** mirror 默契事件 / solo 各自的事 / milestone 人生关口（到了年纪的那天早上一定发生，选项按属性上锁） */
  kind: "mirror" | "solo" | "milestone";
  stage: Stage;
  seasons: Season[];
  weight: number;
  /** 触发地点（zone id）。mirror 需要两人同时在；solo 没有 where 时早上醒来触发 */
  where: string | null;
  when: [number, number] | null;
  hint: string | null;
  requires: EventRequires;
  title: string;
  text: string;
  options: EventOption[];
  /** flags：共同标记（p_ 开头），共鸣/错位时两个人都会得到 */
  resonance: { [optionId: string]: { text: string; memory?: string; bond: Partial<Bond>; flags: string[] } } | null;
  dissonance: { text: string; bond: Partial<Bond>; flags: string[] } | null;
  // ---- 以下只有 milestone 有 ----
  /** 到这个年纪的第一天发生 */
  age?: number;
  score?: ScoreWeights;
  /** 考试有发挥：得分会随手气和运气上下浮动一点 */
  swing?: boolean;
  grades?: Grade[];
}

interface EventRequires {
  minAge?: number;
  maxAge?: number;
  flags?: string[];
  notFlags?: string[];
  minClose?: number;
  maxClose?: number;
  minSync?: number;
  maxSync?: number;
  minDistance?: number;
  maxDistance?: number;
  /** true：只在对方已经离开以后；false：只在两人都在世时 */
  alone?: boolean;
}

/** 抽事件时除了年龄和标记以外还要看的东西 */
interface EligibleCtx {
  bond: Bond;
  alone: boolean;
}

// ---------- 结局（content/endings.yaml） ----------

/** 两个人一起走到的结局：按顺序取第一个满足条件的 */
interface PairEnding {
  id: string;
  title: string;
  text: string;
  requires: {
    flags?: string[];
    notFlags?: string[];
    minClose?: number;
    maxClose?: number;
    minSync?: number;
    maxSync?: number;
    minDistance?: number;
    maxDistance?: number;
    minMemories?: number;
    maxMemories?: number;
    /** 默契率（共鸣次数 / 默契事件次数，0~100） */
    minRate?: number;
    maxRate?: number;
    minTogether?: number;
  };
}

/** 每个人自己的一生小结：按顺序取第一个满足条件的。text 里的 {name} 换成名字 */
interface LifeEnding {
  id: string;
  title: string;
  text: string;
  requires: {
    flags?: string[];
    notFlags?: string[];
    /** 属性下限，如 { mind: 8 } */
    stats?: Partial<Stats>;
    minDiedAge?: number;
    maxDiedAge?: number;
  };
}

interface Endings {
  pair: PairEnding[];
  lives: LifeEnding[];
}

interface EndingResult {
  pair: string;
  lives: { [R in Role]: string };
}

interface Family {
  id: string;
  name: string;
  wealth: 0 | 1 | 2;
  weight: number;
  money: number;
  desc: string;
  bonus: Partial<Stats>;
  traits: string[];
}

interface Talent {
  id: string;
  name: string;
  weight: number;
  desc: string;
  bonus: Partial<Stats>;
  flags: string[];
}

// ---------- 数值规则（content/rules.yaml，说明见 docs/GROWTH.md） ----------

interface Rules {
  roll: { budget: number; wealthAdjust: number[]; statMin: number; statMax: number; rerolls: number };
  growth: {
    eventScale: number;
    actionScale: number;
    /** 一个数，或者按阶段写 */
    room: number | { [S in Stage]: number };
    floor: number;
    /** 底子里出身占多少：1 = 完全看出生时的属性，0 = 人人一样 */
    bornWeight: number;
    plasticity: { [S in Stage]: Stats };
    plainBonus: number;
    /** 日常行动的成长按阶段再乘这个数：一个日子代表的时间越长算得越重。老内容没写按 1 */
    turnWeight?: { [S in Stage]: number };
  };
  /** [从几岁起, 每年掉多少] */
  aging: { body: number[][]; mind: number[][]; activeFactor: number };
  daily: { bodyEnergy: number; charmTogether: number; luckFate: number; slotUse: number; needsUse?: number; wageFlags?: { [flag: string]: number } };
  check: { base: number; perPoint: number; luck: number; min: number; max: number; help: number };
  lifespan: {
    base: number; spread: number; body: number;
    moodMid: number; moodStep: number; moodMin: number; moodMax: number;
    bondClose: number; bond: number; widowClose: number; widow: number;
    min: number; max: number;
    /** 关口上走的路折成的寿数：带着这个标记的人多（或少）活几年 */
    flags?: { [flag: string]: number };
  };
  bond: {
    closeSoft: number; closeFloor: number; closeScale: number; syncSoft: number; syncFloor: number; syncSteady: number; syncSteadyFrom?: number; syncSteadyFull?: number; slotTogether?: number; closeWeight?: { [S in Stage]: number };
    drift: { [S in Stage]: number }; driftDistance: number; driftFloor: number;
  };
}

/** 检定：挂在某个事件的某个选项上的一次「成不成」（content/checks.yaml） */
interface Check {
  event: string;
  option: string;
  stat: StatKey;
  dc: number;
  pass: string;
  /** self / flags 为 null 时沿用选项原来的（self 会去掉长属性的部分） */
  fail: { text: string; self: SelfDelta | null; flags: string[] | null };
}

/** 一次检定的结果，写进日志给客户端显示 */
interface CheckResult {
  stat: StatKey;
  ok: boolean;
  /** 搭把手：两个人一起办成的 */
  help: boolean;
  text: string;
}

/** 一张图（content/maps/<id>.yaml）：横着的一条剖面 / 街景。在世界坐标里占 y ∈ [top, top + stride) 这一条 */
interface Scene {
  id: string;
  name: string;
  index: number;
  top: number;
  width: number;
  /** 每层地面的世界 y（从上往下）。人只在地面上左右走，换层走出口 */
  floors: number[];
  /** 什么人能去：年纪、标记（和行动的 requires 一个意思）；any 里满足一条就行 */
  unlock: (SceneUnlock & { any?: SceneUnlock[] }) | null;
  /** 外地：另一个人在别的图上，互相看不见 */
  far: boolean;
}

interface SceneUnlock { minAge?: number; maxAge?: number; flags?: string[]; notFlags?: string[] }

/** 出口：门、楼梯、街口。走到跟前点一下就到 to 那张图的 arrive（不花时间） */
interface Exit {
  id: string;
  scene: string;
  at: [number, number];
  to: string;
  arrive: [number, number];
  label: string;
  /** 路上花掉的分钟（过桥坐车 60、去外地 240），从这一段里扣；0 = 走过去，不花时间 */
  ride: number;
}

interface Zone {
  id: string;
  name: string;
  scene: string;
  floor: number;
  span: [number, number];
  /** 世界坐标里的框（由 span 和那一层地面算出来），判定「人在不在这儿」用 */
  rect: [number, number, number, number];
  owner?: Role;
}

interface Spot {
  id: string;
  zone: string;
  scene: string;
  at: [number, number];
  /** 这个地方能做的事。同一个物件不同年纪做不同的事：取第一个年龄合适的 */
  actions: string[];
  /** = actions[0]，给只认一个行动的旧代码用 */
  action: string;
}

interface Action {
  id: string;
  label: string;
  minutes: number;
  /** 顺手的事：当场做完，不占这一段（吃饭、洗澡、买早点、敲门） */
  quick: boolean;
  sleep: boolean;
  /** 日程：上学、上班。做多久、涨什么、挣多少由这个人走的路（Track.duty）决定 */
  duty: boolean;
  requires: { minAge?: number; maxAge?: number; owner?: boolean; hours?: [number, number]; flags?: string[]; notFlags?: string[] };
  needs: Partial<Needs>;
  stats: Partial<Stats>;
  money: number;
  together: { needs: Partial<Needs>; bond: Partial<Bond>; text: string } | null;
  /** 带上对门：标记够的人正在做，对门走过去也能跟着做，两份钱都由带的人出（means.ts） */
  bring: boolean;
}

interface GameMap {
  scenes: Scene[];
  exits: Exit[];
  /** 每张图在世界坐标里占多高 */
  stride: number;
  size: [number, number];
  spawn: { [R in Role]: [number, number] };
  zones: Zone[];
  spots: Spot[];
  actions: Action[];
}

/** 每天被占掉的那一块时间 */
interface Duty {
  label: string;
  spot: string;
  /** 几点到几点之间到 */
  arrive: [number, number];
  /** 几点结束 */
  until: number;
  needs: Partial<Needs>;
  stats: Partial<Stats>;
  money: number;
}

/**
 * 人生路线：这个人现在在过哪一种日子。不存进存档，每次按年龄和标记从上往下取第一条符合的，
 * 所以关口和事件只管打标记（考上了、辍学了、去外地了），日程自己会跟着变。
 */
interface Track {
  id: string;
  label: string;
  requires: { minAge?: number; maxAge?: number; flags?: string[]; notFlags?: string[] };
  /** 同一所学校、同一个行当里的不同位置（学习委员和体育委员还是同班）：group 一样就算同路，日程照样搭伴 */
  group: string | null;
  duty: Duty | null;
}

interface Content {
  /** 内容指纹（tools/build-content.mjs 算的）。客户端拿它判断要不要从服务器下载新内容 */
  version: string;
  events: LifeEvent[];
  families: Family[];
  talents: Talent[];
  map: GameMap;
  tracks: Track[];
  endings: Endings;
  rules: Rules;
  checks: Check[];
}

// ---------- 存档 ----------

/** 开局抽卡 */
interface Roll {
  familyId: string;
  talentId: string;
  stats: Stats;
  rerollsLeft: number;
  confirmed: boolean;
}

interface Person {
  name: string;
  alive: boolean;
  lifespan: number;
  diedAtAge: number | null;
  familyId: string;
  talentId: string;
  stats: Stats;
  /** 出生时的属性：成长的「底子」 */
  born: Stats;
  needs: Needs;
  money: number;
  /** 一辈子的心气：每个日子结束时的心情累加，用来算寿命 */
  moodSum: number;
  moodDays: number;
  /** 今天动没动过 / 用没用过脑子（岁数大了以后掉得慢一点） */
  active: { body: boolean; mind: boolean };
  flags: string[];
  /** 性格标签计数，用来训练「影子」 */
  tags: { [tag: string]: number };
  /** 今天早上的属性，用来算一天的小结 */
  dayStart?: Stats;
}

interface Memory {
  title: string;
  eventId: string;
  turn: number;
  age: number;
  vivid: number;
}

/** 河畔里的一个人 */
interface Actor {
  x: number;
  y: number;
  /** 正在做的行动 id；null = 空闲可走动 */
  action: string | null;
  spot: string | null;
  /** 行动结束的游戏分钟 */
  until: number | null;
  asleep: boolean;
  /** 这个行动是影子替他开始的（本人回来时可以收回） */
  shadow?: boolean;
  /** 开始时的状态效率（饿、困、心情差时成长打折） */
  eff?: number;
  /** 这次是和 TA 搭伴做的 */
  together?: boolean;
  /** 从第几段开始做的（日程会一直占到下班） */
  from?: number;
  /** 这一段里这件事做了几遍：一段的分钟 × slotUse ÷ 行动的分钟。成长、需求、工钱都乘它 */
  scale?: number;
  /** 这件事是对门带着做的（means.ts）：钱记在带的人头上 */
  guest?: boolean;
  /** 这一段（rideSlot）在路上花掉的分钟：过桥、坐车（worldExit）。这一段再做事，只剩下扣掉以后的那些 */
  ride?: number;
  rideSlot?: number;
}

interface PendingEvent {
  eventId: string;
  kind: "mirror" | "solo" | "milestone";
  roles: Role[];
  choices: Choices;
  shadow: Role[];
  /** 关口：每个人这次的发挥（加在得分上） */
  swing?: { [R in Role]?: number };
  /** 关口：默契替这个人托住的分（已经算在 swing 里了，单拿出来是给他看的） */
  steady?: { [R in Role]?: number };
  /** 章末躲不过的主线是硬塞的：有人被叫醒、撤下手上的事、或者被挪过去（world.ts 的 worldStoryForce）。人本来就在那儿就没有 */
  forced?: boolean;
}

interface WorldState {
  /** 当天的游戏分钟，390 = 06:30。定这一段的时候停在这一段的开头，过的时候一路走到结尾 */
  minute: number;
  /** 现在是第几段（world.ts 的 SLOTS：早上 / 上午 / 下午 / 傍晚 / 晚上） */
  slot: number;
  /** 这一段按了「歇着」的人（做事的、睡了的不用按，见 worldReady） */
  ready: { [R in Role]?: boolean };
  /** 两个人都定了，这一段正在过 */
  playing: boolean;
  /** 一个人定了、另一个人还没定，已经等了几秒（到 SLOT_PATIENCE 影子替他定） */
  wait: number;
  /** 这一段做过的顺手的事（"qing:eat"），同一件一段只做一回 */
  quick: string[];
  /** 今天歇着：不上学也不上班 */
  rest: boolean;
  /** 只给这一个人放的一天（回来了、主线落在上班的钟点上）。可选：旧存档没有 */
  off?: { [R in Role]?: boolean };
  /** 有人从另一片回来一趟（主线在这边）：这一天挡不住亲近淡下去（growth.ts）。可选：旧存档没有 */
  back?: boolean;
  /** 今天的日程去过了没有 */
  dutyDone: { [R in Role]?: boolean };
  actors: { [R in Role]: Actor | null };
  event: PendingEvent | null;
  /** 今天命运准备好的事件：要走到对的地方才会发生 */
  fate: {
    mirror: string | null; qing: string | null; mei: string | null; milestone?: string | null;
    /** 今天的主线事件（mirror / qing / mei 里是主线的那几件）到了章末还没碰上：一早就发生，不等人走过去（server/src/story.ts） */
    force?: string[];
  };
  /** 已经触发过的 fate */
  done: string[];
  /** 今天有没有同框或共鸣过：没有的话，一天结束时亲近会淡一点 */
  warm: boolean;
}

interface LogEntry {
  turn: number;
  age: number;
  label: string;
  kind: "mirror" | "solo" | "milestone" | "together" | "day" | "death" | "end";
  minute: number | null;
  events: { [R in Role]: string | null };
  choices: { [R in Role]: string | null };
  shadow: Role[];
  resonance: boolean | null;
  text: string;
  /** 关口：每个人的得分（属性类按百分制，钱类按块）、成绩和走上的路 */
  results?: { [R in Role]?: {
    score: number; scored?: boolean; unit: string; grade: string | null; option: string; track: string;
    /** 以下几项只给揭晓演出用（client/scripts/ui/reveal.gd），旧安装包不认也不碍事。都按 score 的口径（百分制或原数） */
    /** 走的这条路的线（这条路不看分就没有） */
    line?: number;
    /** 这一场的临场发挥（已经算在 score 里），和默契替他托住的那一截（也算在 luck 里了） */
    luck?: number;
    steady?: number;
    /** 差一点：离哪条没走成的路最近（atlas.ts → atlasMilestoneNear；揭晓卡和结局页读同一个数） */
    near?: MilestoneNear | null;
  } };
  /** 一天的小结：每个人今天涨了多少 */
  gains?: { [R in Role]?: Partial<Stats> };
  /** 这件事里做过的检定 */
  checks?: { [R in Role]?: CheckResult };
}

interface LifeState {
  /** 存档结构版本，见 save.ts 的 LIFE_VERSION / lifeUpgrade */
  version: number;
  /** 这份存档上次是在哪一版内容下跑的；和当前内容不一样时 lifeRepair 会检查悬空引用 */
  contentVersion?: string;
  seed: number;
  rng: number;
  phase: "roll" | "life" | "ended";
  turn: number;
  rolls: { [R in Role]: Roll };
  persons: { [R in Role]: Person } | null;
  bond: Bond;
  memories: Memory[];
  log: LogEntry[];
  world: WorldState | null;
  /** 人生结束时算出的结局 */
  ending?: EndingResult;
}

interface TimeInfo {
  age: number;
  stage: Stage;
  season: Season | null;
  label: string;
}
