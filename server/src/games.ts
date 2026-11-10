// 搭伴的手感层：两个人一起做同一件事时，可以点进去玩的小游戏。现在只有一款：放风筝。
//
// 它不是独立玩法，也不是第二套结算：
//   - 两人都在线、同时在做 GAME_ACTIONS 里的行动时，服务器问一句「一起放？」（每天只问一次）。
//   - 两人都点「放」才开始；有人点「不了」、没理、掉线，就当没问过，行动照常结算。
//   - 玩的结果只变成这一次搭伴的成长倍率，写在两人 Actor.boost 上，别的什么都不碰。
//   - 问和玩的时候世界时钟停住（和做选择时一样），所以玩不玩都不占这一天的时间。
//
// 谁管什么：风筝的物理在服务器上跑（10Hz，风筝本来就飘，延迟看不出来），客户端只报手指的位置。
// 类型用 interface 合并挂到 WorldState / Actor 上，不改 types.ts。

var GAME_OFFER_SECONDS = 8; // 问了以后等多久
var GAME_LEAD_IN = 3; // 开局先留三秒，看清自己管哪一头
/** 哪个行动带哪款小游戏（行动 id → 小游戏 id） */
var GAME_ACTIONS: { [actionId: string]: string } = { play_river: "kite" };
/** 玩得最差和最好时的搭伴倍率；不玩时不写，用世界规则里的默认值 */
var GAME_BOOST = [1.3, 1.8];

interface GameSession {
  gameId: string;
  /** 两人正在搭伴做的行动 */
  action: string;
  phase: "offer" | "play";
  /** offer：还等多少秒 */
  left: number;
  ready: { qing?: boolean; mei?: boolean };
  /** play：开局后的秒数，前 GAME_LEAD_IN 秒为负 */
  t: number;
  rng: number;
  /** 各款小游戏自己的状态 */
  d: any;
  dirty: boolean;
}

interface GameResult {
  gameId: string;
  /** 0~100 */
  score: number;
  boost: number;
}

interface WorldState {
  game?: GameSession | null;
}

interface Actor {
  /** 这一次行动的搭伴成长倍率（小游戏打出来的）。行动结束时由世界规则读走 */
  boost?: number;
}

interface GameRules {
  init: (s: LifeState, g: GameSession) => any;
  input: (s: LifeState, g: GameSession, role: Role, body: any) => void;
  /** 返回得分（0~100）表示打完了，否则返回 null */
  tick: (s: LifeState, g: GameSession, dt: number) => number | null;
  view: (s: LifeState, g: GameSession) => any;
}

function gameNum(v: any, lo: number, hi: number, fallback: number): number {
  var n = Number(v);
  if (isNaN(n)) return fallback;
  return lifeClamp(n, lo, hi);
}

function gameBoostOf(score: number): number {
  var k = lifeClamp(score, 0, 100) / 100;
  return Math.round((GAME_BOOST[0] + (GAME_BOOST[1] - GAME_BOOST[0]) * k) * 100) / 100;
}

/** 两人是不是正在搭伴做一件带小游戏的事；是就返回小游戏 id */
function gamePairing(s: LifeState): string | null {
  var w = s.world!;
  var a = w.actors.qing, b = w.actors.mei;
  if (!a || !b || !a.action || a.action !== b.action || a.asleep || b.asleep) return null;
  if (!s.persons!.qing.alive || !s.persons!.mei.alive) return null;
  return GAME_ACTIONS[a.action] || null;
}

interface GameTickOut {
  /** 这一跳里局关掉了 */
  closed: boolean;
  /** 打完了才有；没玩成（不了 / 超时 / 掉线 / 中途退出）是 null */
  result: GameResult | null;
}

function gameClose(s: LifeState, result: GameResult | null): GameTickOut {
  s.world!.game = null;
  return { closed: true, result: result };
}

/** 每跳调一次。online 要用真在线（不算掉线宽限期）：影子不玩小游戏 */
function gameTick(s: LifeState, c: Content, dtSec: number, online: { [R in Role]: boolean }): GameTickOut {
  var none: GameTickOut = { closed: false, result: null };
  var w = s.world;
  if (s.phase !== "life" || !w) return none;
  var both = online.qing && online.mei;
  var g = w.game;
  if (!g) {
    var gid = both && !w.event ? gamePairing(s) : null;
    var key = "game:" + gid;
    if (!gid || w.done.indexOf(key) >= 0) return none;
    w.done.push(key); // 每天只问一次
    w.game = {
      gameId: gid, action: w.actors.qing!.action!, phase: "offer", left: GAME_OFFER_SECONDS, ready: {},
      t: -GAME_LEAD_IN, rng: Math.floor(lifeRand(s) * 4294967296) | 0, d: null, dirty: true,
    };
    return none;
  }
  if (!both || gamePairing(s) !== g.gameId) return gameClose(s, null);
  if (g.phase === "offer") {
    g.left -= dtSec;
    if (g.ready.qing && g.ready.mei) {
      g.phase = "play";
      g.t = -GAME_LEAD_IN;
      g.d = GAME_RULES[g.gameId].init(s, g);
      g.dirty = true;
    } else if (g.left <= 0) {
      return gameClose(s, null);
    }
    return none;
  }
  g.t += dtSec;
  if (g.t < 0) return none;
  var score = GAME_RULES[g.gameId].tick(s, g, dtSec);
  if (score === null) return none;
  // 打完了：结果只落在这一次搭伴的倍率上
  var result: GameResult = { gameId: g.gameId, score: Math.round(lifeClamp(score, 0, 100)), boost: gameBoostOf(score) };
  w.actors.qing!.boost = result.boost;
  w.actors.mei!.boost = result.boost;
  return gameClose(s, result);
}

function gameInput(s: LifeState, role: Role, body: any): GameTickOut {
  var none: GameTickOut = { closed: false, result: null };
  var w = s.world;
  if (s.phase !== "life" || !w || !w.game || !body || typeof body !== "object") return none;
  var g = w.game;
  if (g.phase === "offer") {
    if (body.k === "ready") { g.ready[role] = true; g.dirty = true; }
    if (body.k === "pass") return gameClose(s, null);
    return none;
  }
  if (body.k === "quit") return gameClose(s, null); // 中途不玩了：当没玩过
  if (g.t >= 0) GAME_RULES[g.gameId].input(s, g, role, body);
  return none;
}

/** 发给客户端的样子 */
function gameView(s: LifeState, g: GameSession): any {
  return {
    gameId: g.gameId, phase: g.phase, left: Math.max(0, Math.ceil(g.left)), ready: g.ready,
    t: Math.round(g.t * 100) / 100, d: g.phase === "play" ? GAME_RULES[g.gameId].view(s, g) : null,
  };
}

// ---------- 房间里的两个钩子（main.ts 调） ----------

function gameBroadcastClosed(dispatcher: nkruntime.MatchDispatcher, out: GameTickOut) {
  if (out.closed) send(dispatcher, OP.GAME, { game: null, result: out.result });
}

function gameOnMessage(life: LifeState, dispatcher: nkruntime.MatchDispatcher, role: Role, body: any) {
  gameBroadcastClosed(dispatcher, gameInput(life, role, body));
}

function gameLoop(life: LifeState, state: LifelineMatch, dispatcher: nkruntime.MatchDispatcher, tick: number) {
  if (life.phase !== "life" || !life.world) return;
  gameBroadcastClosed(dispatcher, gameTick(life, CONTENT, 1 / TICK_RATE, online(state)));
  var g = life.world.game;
  // 有变化马上发；没变化每秒一次，掉线重连的人一秒内能接上
  if (g && (g.dirty || tick % TICK_RATE === 0)) {
    g.dirty = false;
    send(dispatcher, OP.GAME, { game: gameView(life, g) });
  }
}

// ======================================================================
// 放风筝：一个攥线管高低，一个牵着线跑管左右
// ======================================================================
// 场地归一化：x 0~1 沿河岸，h 0~1 高度。天上有一块飘着的「风口」，风筝待在风口里线才放得出去。
// 两个人各只管一个方向，谁也没法一个人把风筝送进风口。攥线的人每天换一个（按日子的单双）。

var KITE_SECONDS = 30;
var KITE_NEED = 0.75; // 在风口里待够四分之三的时间，线就放到头了（满分）

function kiteSweet(d: any, t: number): { x: number; h: number } {
  var ph = d.ph;
  return {
    x: 0.5 + 0.3 * Math.sin(0.5 * t + ph[0]) + 0.1 * Math.sin(1.13 * t + ph[1]),
    h: 0.6 + 0.2 * Math.sin(0.41 * t + ph[2]) + 0.08 * Math.sin(0.97 * t + ph[3]),
  };
}

function kiteInit(s: LifeState, g: GameSession): any {
  var ph: number[] = [];
  for (var i = 0; i < 6; i++) ph.push(lifeRand(g) * 6.2832);
  var d: any = {
    holder: s.turn % 2 === 0 ? "qing" : "mei", dur: KITE_SECONDS,
    kx: 0.5, kh: 0.06, rx: 0.5, line: 0.05, tx: 0.5, tl: 0.05, wx: 0.5, wh: 0.6, wr: 0.14,
    prog: 0, inside: false, snag: 0, snags: 0, ph: ph,
  };
  var w0 = kiteSweet(d, 0);
  d.wx = w0.x;
  d.wh = w0.h;
  return d;
}

function kiteInput(s: LifeState, g: GameSession, role: Role, body: any) {
  var d = g.d;
  if (body.k === "line" && role === d.holder) d.tl = gameNum(body.v, 0, 1, d.tl);
  if (body.k === "run" && role !== d.holder) d.tx = gameNum(body.v, 0, 1, d.tx);
}

function kiteTick(s: LifeState, g: GameSession, dt: number): number | null {
  var d = g.d;
  var t = g.t;
  var sw = kiteSweet(d, t);
  d.wx = sw.x;
  d.wh = sw.h;
  d.wr = 0.14 - 0.04 * lifeClamp(t / d.dur, 0, 1); // 风口越来越小

  var step = function (cur: number, target: number, speed: number) { return cur + lifeClamp(target - cur, -speed * dt, speed * dt); };
  d.rx = step(d.rx, d.tx, 0.5); // 人跑得没手指快
  d.line = step(d.line, d.tl, 0.45);
  if (d.snag > 0) {
    d.snag -= dt; // 挂在桥上了，等它自己挣下来
    if (d.snag <= 0) { d.kh = 0.24; d.line = Math.max(d.line, 0.22); d.tl = Math.max(d.tl, 0.22); }
  } else {
    var sway = 0.05 * Math.sin(1.7 * t + d.ph[4]) * (0.3 + d.line); // 线越长越晃
    var bob = 0.03 * Math.sin(2.3 * t + d.ph[5]);
    d.kx += (d.rx + sway - d.kx) * (1 - Math.exp(-dt / 0.45));
    d.kh += (0.06 + 0.9 * d.line + bob - d.kh) * (1 - Math.exp(-dt / 0.35));
    // 铁桥在左下角：飞得太低会挂上
    if (t > 4 && d.kx < 0.3 && d.kh < 0.16) {
      d.snag = 1.6;
      d.snags += 1;
      d.prog = Math.max(0, d.prog - 0.06);
    }
  }
  var dx = (d.kx - d.wx) * 0.6; // 竖屏：横向没有纵向长
  var dh = d.kh - d.wh;
  d.inside = d.snag <= 0 && Math.sqrt(dx * dx + dh * dh) < d.wr;
  if (d.inside) d.prog = Math.min(1, d.prog + dt / (d.dur * KITE_NEED));
  g.dirty = true; // 每跳都发
  if (t >= d.dur || d.prog >= 1) return d.prog * 100;
  return null;
}

function kiteView(s: LifeState, g: GameSession): any {
  var d = g.d;
  var r3 = function (n: number) { return Math.round(n * 1000) / 1000; };
  return {
    holder: d.holder, dur: d.dur, kx: r3(d.kx), kh: r3(d.kh), rx: r3(d.rx), line: r3(d.line),
    wx: r3(d.wx), wh: r3(d.wh), wr: r3(d.wr), prog: r3(d.prog), inside: d.inside, snag: d.snag > 0,
  };
}

var GAME_RULES: { [id: string]: GameRules } = {
  kite: { init: kiteInit, input: kiteInput, tick: kiteTick, view: kiteView },
};
