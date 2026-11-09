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
  requires: { minAge?: number; maxAge?: number; flags?: string[]; notFlags?: string[] };
  title: string;
  text: string;
  options: EventOption[];
  resonance: { [optionId: string]: { text: string; memory?: string; bond: Partial<Bond> } } | null;
  dissonance: { text: string; bond: Partial<Bond> } | null;
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
  events: LifeEvent[];
  families: Family[];
  talents: Talent[];
  map: GameMap;
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
  needs: Needs;
  money: number;
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
}

interface LifeState {
  version: 2;
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
}

interface TimeInfo {
  age: number;
  stage: Stage;
  season: Season | null;
  label: string;
}
