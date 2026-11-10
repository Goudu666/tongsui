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
}

interface LifeEvent {
  id: string;
  kind: "mirror" | "solo";
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
    room: number;
    floor: number;
    plasticity: { [S in Stage]: Stats };
    plainBonus: number;
  };
  /** [从几岁起, 每年掉多少] */
  aging: { body: number[][]; mind: number[][]; activeFactor: number };
  daily: { bodyEnergy: number; charmTogether: number; luckFate: number };
  check: { base: number; perPoint: number; luck: number; min: number; max: number; help: number };
  lifespan: {
    base: number; spread: number; body: number;
    moodMid: number; moodStep: number; moodMin: number; moodMax: number;
    bondClose: number; bond: number; widowClose: number; widow: number;
    min: number; max: number;
  };
  bond: {
    closeSoft: number; closeFloor: number; closeScale: number; syncSoft: number; syncFloor: number;
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

interface Zone {
  id: string;
  name: string;
  rect: [number, number, number, number];
  owner?: Role;
}

interface Spot {
  id: string;
  zone: string;
  at: [number, number];
  action: string;
}

interface Action {
  id: string;
  label: string;
  minutes: number;
  sleep: boolean;
  school: boolean;
  requires: { minAge?: number; maxAge?: number; owner?: boolean; hours?: [number, number] };
  needs: Partial<Needs>;
  stats: Partial<Stats>;
  money: number;
  together: { needs: Partial<Needs>; bond: Partial<Bond>; text: string } | null;
}

interface GameMap {
  size: [number, number];
  spawn: { [R in Role]: [number, number] };
  zones: Zone[];
  spots: Spot[];
  actions: Action[];
}

interface Content {
  /** 内容指纹（tools/build-content.mjs 算的）。客户端拿它判断要不要从服务器下载新内容 */
  version: string;
  events: LifeEvent[];
  families: Family[];
  talents: Talent[];
  map: GameMap;
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
}

interface PendingEvent {
  eventId: string;
  kind: "mirror" | "solo";
  roles: Role[];
  choices: Choices;
  shadow: Role[];
}

interface WorldState {
  /** 当天的游戏分钟，390 = 06:30 */
  minute: number;
  schoolDay: boolean;
  actors: { [R in Role]: Actor | null };
  event: PendingEvent | null;
  /** 今天命运准备好的事件：要走到对的地方才会发生 */
  fate: { mirror: string | null; qing: string | null; mei: string | null };
  /** 已经触发过的 fate */
  done: string[];
  /** 今天有没有同框或共鸣过：没有的话，一天结束时亲近会淡一点 */
  warm: boolean;
}

interface LogEntry {
  turn: number;
  age: number;
  label: string;
  kind: "mirror" | "solo" | "together" | "day" | "death" | "end";
  minute: number | null;
  events: { [R in Role]: string | null };
  choices: { [R in Role]: string | null };
  shadow: Role[];
  resonance: boolean | null;
  text: string;
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
