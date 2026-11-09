// 全局类型（Nakama JS 运行时不支持 ES Module，所有文件都是全局脚本，最后由 tsc 拼成一个 build/index.js）

type Role = "qing" | "mei";
type Stage = "childhood" | "teen" | "young" | "middle" | "old";
type Season = "spring" | "summer" | "autumn" | "winter";
type StatKey = "body" | "mind" | "charm" | "heart";
type BondKey = "sync" | "close" | "distance";

type Stats = { [K in StatKey]: number };
type Bond = { [K in BondKey]: number };

interface OptionEffects {
  self: Partial<Stats>;
  other: Partial<Stats>;
  bond: Partial<Bond>;
  flags: string[];
}

interface EventOption {
  id: string;
  text: string;
  tags: string[];
  effects: OptionEffects;
}

interface Resonance {
  text: string;
  memory?: string;
  bond: Partial<Bond>;
}

interface LifeEvent {
  id: string;
  kind: "mirror" | "solo";
  stage: Stage;
  seasons: Season[];
  weight: number;
  requires: { minAge?: number; maxAge?: number; flags?: string[]; notFlags?: string[] };
  title: string;
  text: string;
  options: EventOption[];
  resonance: { [optionId: string]: Resonance } | null;
  dissonance: { text: string; bond: Partial<Bond> } | null;
}

interface Person {
  name: string;
  alive: boolean;
  /** 先天寿命，实际死亡年龄还受体魄影响 */
  lifespan: number;
  diedAtAge: number | null;
  stats: Stats;
  flags: string[];
  /** 性格标签计数，用来训练「影子」 */
  tags: { [tag: string]: number };
}

interface Memory {
  title: string;
  eventId: string;
  turn: number;
  age: number;
  /** 鲜明度 3 → 0 */
  vivid: number;
}

/** 当前回合摆在两人面前的场景。mirror 时两人的 eventId 相同。 */
interface Scene {
  kind: "mirror" | "solo";
  events: { [R in Role]: string | null };
}

interface LogEntry {
  turn: number;
  age: number;
  label: string;
  kind: "mirror" | "solo" | "death" | "end";
  events: { [R in Role]: string | null };
  choices: { [R in Role]: string | null };
  shadow: Role[];
  resonance: boolean | null;
  text: string;
}

interface LifeState {
  version: 1;
  seed: number;
  rng: number;
  turn: number;
  ended: boolean;
  persons: { [R in Role]: Person };
  bond: Bond;
  memories: Memory[];
  log: LogEntry[];
  scene: Scene | null;
}

interface TimeInfo {
  age: number;
  stage: Stage;
  season: Season | null;
  label: string;
}

type Choices = { [R in Role]?: string };
