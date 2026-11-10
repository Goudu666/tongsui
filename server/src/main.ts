// Nakama 入口：配对 RPC + 权威实时房间「lifeline」
//
// 一条 lifeline = 两个人的一生。存档在 storage(lifelines/<id>)，房间只是它在线时的载体：
// 两人都下线后房间会关闭，下次 lifeline_open 时从存档重新拉起。
// 房间流程：抽卡（roll）→ 人生（life：河畔里实时走动、行动、事件）→ 结束（ended）→ 两人都点了「再来一世」→ 抽卡……
// 再来一世还是同一条 lifeline、同一份存档：上一世攒下的东西在 life.legacy 里跟着走（legacy.ts）。

var SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
var COL_LIFELINES = "lifelines";
var COL_CODES = "pair_codes";
var COL_MINE = "my_lifelines";
var COL_PAST = "lifeline_past"; // 走完的一世（长卷在这儿）：键是 人生线 id + "." + 第几世，换世时从存档里挪过来
var MATCH_NAME = "lifeline";
var TICK_RATE = 10; // 走动需要实时，一秒十跳
var WORLD_BROADCAST_EVERY = 2; // 每 2 跳（5Hz）广播一次世界状态，客户端插值
var SAVE_EVERY_SECONDS = 30;
var SHADOW_WAIT_SECONDS = 30; // 事件里搭档离线时，等多久让影子代选
var EMPTY_CLOSE_SECONDS = 120; // 房间空了多久后关闭
var MOVE_MAX_DT = 1.0; // 两次 MOVE 之间最多按 1 秒算限速，防止站久了一步瞬移
var NOTIFY_PARTNER_JOINED = 101; // 通知码：TA 输入了配对码
var NOTIFY_PARTNER_ONLINE = 102; // 通知码：TA 进了人生线（你不在房间里时）
var DUP_MATCH = "DUP_MATCH:"; // matchInit 发现已有房间时抛出的错误前缀
var MATCH_CLAIM_GRACE_MS = 15000; // 刚写进存档的 matchId 在这段时间内一律当作活着
var SHADOW_GRACE_SECONDS = 10; // 掉线这么久之内不交给影子：切网络、进电梯的几秒钟，人还是自己的

/**
 * 协议版本。服务器和安装包是分开更新的（服务器 ship.sh 一下就换了，手机要重装 APK），所以进房间前先对一下：
 * - 改了消息的含义、加了客户端必须懂的东西：PROTOCOL_VERSION + 1，client/scripts/net/protocol.gd 的 VERSION 跟着改
 * - 旧客户端没法再用了：把 MIN_CLIENT_PROTOCOL 提到能用的最低版本，旧包会看到「请装新版」，而不是卡在看不懂的界面里
 * 剧情内容不走这个：内容有自己的指纹 CONTENT.version，客户端发现不一样会自己下载（content_get）。
 */
var PROTOCOL_VERSION = 3; // 2：关口（上锁的选项）、日程、目标、属性进了 WORLD；schoolDay 没了  3：传承（老物件、再来一世），旧包可以忽略
var MIN_CLIENT_PROTOCOL = 2;
/** 从这个协议版本起，安装包才认识传承的消息（31 AGAIN）。和 protocol.gd 的 LEGACY_SINCE 是同一个数 */
var LEGACY_SINCE_PROTOCOL = 3;
var CONTENT_CHUNK = 48000; // content_get 一次回多少个字符：整份内容约 17 万字符，分几次取，不撞单条消息的大小上限

/** 客户端 ↔ 服务端消息号，client/scripts/net/protocol.gd 里保持一致 */
var OP = {
  SNAPSHOT: 1, // s→c 完整状态 { lifelineId, names, life, you, online, protocols }  protocols：两人安装包的协议版本，不在线是 0
  ROLL: 2, // c→s { reroll: true } | { confirm: true } | { heirloom: 老物件 id | null } 挑一件老物件带上 / 放下
  ROLL_STATE: 3, // s→c { rolls }  每人带着 house（家业传了几代）、offer（摆在面前的老物件）、heirloomId（挑中的）
  MOVE: 4, // c→s { x, y }
  ACT: 5, // c→s { spot }
  CHOOSE: 6, // c→s { optionId, guess? } guess：默契事件里猜 TA 选了哪一项（可以不猜）
  WORLD: 7, // s→c 精简世界状态（5Hz）
  EVENT: 8, // s→c { event } 有事件开始了
  ERROR: 9, // s→c { message }
  LOG: 10, // s→c { entries } 事件结算、同框、一天结束、死亡
  PRESENCE: 11, // s→c { online }
  PING: 12, // c→s { t } 心跳，客户端用来测延迟、发现死连接
  PONG: 13, // s→c { t, tick } 原样带回 t，附上服务器 tick
  GAME: 20, // s→c { game: 视图 | null, result? } 搭伴小游戏的状态（games.ts）
  GAME_INPUT: 21, // c→s { k: "ready" | "pass" | "quit" | 小游戏自己的输入 }
  ECHO: 30, // c→s { turn, optionId } 回话：补答影子替我选过的默契事件；optionId 为 null 是「不提了」
  AGAIN: 31, // c→s { yes } 一世走完以后：再来一世（false 是收回）  s→c { again: { qing, mei } } 谁点了；两人都点了改发 SNAPSHOT
};
/** c→s 的消息号：只有这些会被处理，其余的回一个 ERROR */
var CLIENT_OPS = [OP.ROLL, OP.MOVE, OP.ACT, OP.CHOOSE, OP.PING, OP.GAME_INPUT, OP.ECHO, OP.AGAIN];

interface LifelineRecord {
  id: string;
  code: string;
  members: { qing: string; mei: string | null };
  names: { qing: string; mei: string };
  matchId: string | null;
  /** matchId 写进存档的时间（ms）。刚拉起的房间要等 matchInit 返回后才能被 matchGet 查到，这段时间也算「活着」 */
  matchClaimedAt?: number;
  life: LifeState | null;
  /** 房间因为规则代码出错而回滚过几次、最近一次的原因（排查用，见 faultClose） */
  faults?: number;
  lastFault?: string;
}

interface LifelineMatch {
  lifelineId: string;
  /** 这个房间自己的 id（存档里的 matchId 可能被别的房间改掉，拿这个来对） */
  matchId: string | null;
  record: LifelineRecord;
  /** 存档当前的版本号。房间是存档唯一的写入者，每次带着它做条件写入 */
  version: string;
  /** 存档已经被另一个房间接管：这个房间不再写存档，下一跳关闭 */
  superseded: boolean;
  presences: { [R in Role]?: nkruntime.Presence };
  /** 上一次收到各自 MOVE 的 tick，用来限速 */
  lastMoveTick: { [R in Role]?: number };
  /** 已处理的各自最后一条 MOVE 序号，随 WORLD 回给客户端做位置校正 */
  moveSeq: { [R in Role]?: number };
  /** 当前事件开始等待离线搭档的 tick */
  eventWaitSince: number | null;
  lastSaveTick: number;
  emptyTicks: number;
  /** 当前 tick，快照和 WORLD 都带上，客户端按它插值 */
  tick: number;
  /** 各自掉线时的 tick（重连宽限期用） */
  leftAt: { [R in Role]?: number };
  /** 各自这次连接的安装包协议版本（join 时报的；没报的是 3 以前的旧包）。连接状态，不进存档 */
  protocols: { [R in Role]?: number };
}

// ---------- 存储 ----------

function loadLifeline(nk: nkruntime.Nakama, id: string): LifelineRecord | null {
  var r = loadLifelineVersioned(nk, id);
  return r ? r.rec : null;
}

function loadLifelineVersioned(nk: nkruntime.Nakama, id: string): { rec: LifelineRecord; version: string } | null {
  if (!id) return null;
  var r = nk.storageRead([{ collection: COL_LIFELINES, key: id, userId: SYSTEM_USER }]);
  return r.length ? { rec: r[0].value as LifelineRecord, version: r[0].version } : null;
}

/** 房间还活着吗（Nakama 重启、房间超时关闭后，存档里的 matchId 会失效） */
function matchAlive(nk: nkruntime.Nakama, matchId: string | null): boolean {
  if (!matchId) return false;
  try {
    return !!nk.matchGet(matchId);
  } catch (e) {
    return false;
  }
}

/** 存档里记的房间能不能用：查得到，或者是刚刚拉起、还没登记完的 */
function roomUsable(nk: nkruntime.Nakama, rec: LifelineRecord): boolean {
  if (!rec.matchId) return false;
  if (rec.matchClaimedAt && Date.now() - rec.matchClaimedAt < MATCH_CLAIM_GRACE_MS) return true;
  return matchAlive(nk, rec.matchId);
}

/** 写存档，返回新的版本号。给了 version 就是条件写入：存档已经被别人改过时抛错 */
function saveLifeline(nk: nkruntime.Nakama, rec: LifelineRecord, version?: string): string {
  var w: nkruntime.StorageWriteRequest = { collection: COL_LIFELINES, key: rec.id, userId: SYSTEM_USER, value: rec as any, permissionRead: 0, permissionWrite: 0 };
  if (version) w.version = version;
  var acks = nk.storageWrite([w]);
  return acks && acks.length ? acks[0].version : "";
}

/**
 * 换世之前把走完的这一世挪到单独的存储对象里：长卷占了存档的绝大部分，而存档每天整份重写，不能跟着世数涨。
 * 键由人生线和世数定，内容由存档定，所以重跑一遍写下的是同一份（先归档、再换存档，中途断了下次接着来）。
 */
function archiveLife(nk: nkruntime.Nakama, rec: LifelineRecord) {
  var life = rec.life!;
  var past: { [k: string]: any } = {};
  for (var k in life) if (k !== "legacy" && k !== "again" && k !== "rng" && k !== "seed") past[k] = (life as any)[k];
  nk.storageWrite([{
    collection: COL_PAST, key: rec.id + "." + (life.life || 1), userId: SYSTEM_USER,
    value: { lifelineId: rec.id, life: life.life || 1, names: rec.names, past: past }, permissionRead: 0, permissionWrite: 0,
  }]);
}

function roleOf(rec: LifelineRecord, userId: string): Role | null {
  if (rec.members.qing === userId) return "qing";
  if (rec.members.mei === userId) return "mei";
  return null;
}

function randomCode(): string {
  // 去掉容易看错的 0/O/1/I
  var abc = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  var s = "";
  for (var i = 0; i < 6; i++) s += abc.charAt(Math.floor(Math.random() * abc.length));
  return s;
}

function parsePayload(payload: string): { [k: string]: any } {
  if (!payload) return {};
  try {
    return JSON.parse(payload);
  } catch (e) {
    throw new Error("payload 不是合法 JSON");
  }
}

function cleanName(v: any, fallback: string): string {
  var s = typeof v === "string" ? v.replace(/^\s+|\s+$/g, "") : "";
  return s.length > 0 ? s.substring(0, 12) : fallback;
}

// ---------- RPC ----------

/** 青：创建一条人生线，拿到 6 位配对码发给 TA */
var rpcLifelineCreate: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  if (!ctx.userId) throw new Error("需要登录");
  var p = parsePayload(payload);
  var code = "";
  for (var tries = 0; tries < 8; tries++) {
    code = randomCode();
    if (nk.storageRead([{ collection: COL_CODES, key: code, userId: SYSTEM_USER }]).length === 0) break;
  }
  var rec: LifelineRecord = {
    id: nk.uuidv4(),
    code: code,
    members: { qing: ctx.userId, mei: null },
    names: { qing: cleanName(p.name, "青"), mei: "梅" },
    matchId: null,
    life: null,
  };
  saveLifeline(nk, rec);
  nk.storageWrite([
    { collection: COL_CODES, key: code, userId: SYSTEM_USER, value: { lifelineId: rec.id }, permissionRead: 0, permissionWrite: 0 },
    { collection: COL_MINE, key: rec.id, userId: ctx.userId, value: { role: "qing", code: code }, permissionRead: 1, permissionWrite: 0 },
  ]);
  logger.info("lifeline created %s code=%s", rec.id, code);
  return JSON.stringify({ lifelineId: rec.id, code: code, role: "qing" });
};

/** 梅：输入配对码加入，人生从这一刻开始 */
var rpcLifelineJoin: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  if (!ctx.userId) throw new Error("需要登录");
  var p = parsePayload(payload);
  var code = String(p.code || "").toUpperCase();
  var found = nk.storageRead([{ collection: COL_CODES, key: code, userId: SYSTEM_USER }]);
  if (!found.length) throw new Error("配对码不存在");
  var rec = loadLifeline(nk, found[0].value.lifelineId);
  if (!rec) throw new Error("人生线不存在");
  var existing = roleOf(rec, ctx.userId);
  if (existing) return JSON.stringify({ lifelineId: rec.id, role: existing });
  if (rec.members.mei) throw new Error("这条人生线已经有两个人了");

  rec.members.mei = ctx.userId;
  rec.names.mei = cleanName(p.name, "梅");
  rec.life = lifeCreate(Math.floor(Math.random() * 0x7fffffff), CONTENT);
  saveLifeline(nk, rec);
  nk.storageWrite([
    { collection: COL_MINE, key: rec.id, userId: ctx.userId, value: { role: "mei", code: code }, permissionRead: 1, permissionWrite: 0 },
  ]);
  // 告诉青：TA 来了。青的客户端收到后自动进房间；青不在线的话，下次上线也能在通知里看到
  try {
    nk.notificationsSend([
      { userId: rec.members.qing, subject: "partner_joined", content: { lifelineId: rec.id, name: rec.names.mei }, code: NOTIFY_PARTNER_JOINED, persistent: true },
    ]);
  } catch (e) {
    logger.warn("notify qing failed: %s", String(e));
  }
  logger.info("lifeline %s joined by %s", rec.id, ctx.userId);
  return JSON.stringify({ lifelineId: rec.id, role: "mei" });
};

/**
 * 打开人生线：返回正在运行的房间，没有就从存档拉起一个。
 * 两个人可能同一瞬间打开，所以「谁拉起房间」由 matchInit 里带版本号的条件写入决定：
 * 输掉的那个房间在 matchInit 里抛 DUP_MATCH，这里重新读一次存档，返回赢家的房间。
 */
var rpcLifelineOpen: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  if (!ctx.userId) throw new Error("需要登录");
  var p = parsePayload(payload);
  // 先对版本：太旧的安装包在这里就拦下，给一句人话，不放进房间里卡住
  var clientProtocol = Number(p.protocol) || 0;
  if (clientProtocol < MIN_CLIENT_PROTOCOL) {
    throw new Error("这个安装包太旧了，和服务器对不上，请装最新版（CLIENT_TOO_OLD " + clientProtocol + " < " + MIN_CLIENT_PROTOCOL + "）");
  }
  var rec = loadLifeline(nk, String(p.lifelineId || ""));
  if (!rec) throw new Error("人生线不存在");
  var role = roleOf(rec, ctx.userId);
  if (!role) throw new Error("这不是你的人生线");
  // 每个回复都带上服务器的协议版本和内容指纹，客户端进房间前据此同步内容
  var reply = function (extra: { [k: string]: any }) {
    var out: { [k: string]: any } = { lifelineId: rec!.id, role: role, protocol: PROTOCOL_VERSION, content: CONTENT.version };
    for (var k in extra) out[k] = extra[k];
    return JSON.stringify(out);
  };
  if (!rec.life) return reply({ matchId: null, waitingForPartner: true, code: rec.code });

  var lastError = "";
  for (var attempt = 0; attempt < 4; attempt++) {
    if (roomUsable(nk, rec)) return reply({ matchId: rec.matchId });
    try {
      return reply({ matchId: nk.matchCreate(MATCH_NAME, { lifelineId: rec.id }) });
    } catch (e) {
      // 另一个人刚好也在拉起房间：DUP_MATCH 里带着赢家的房间；版本冲突就重读存档再来
      lastError = String(e && (e as any).message ? (e as any).message : e);
      var dup = lastError.match(/DUP_MATCH:([^\s"']+)/);
      if (dup) return reply({ matchId: dup[1] });
      logger.info("lifeline_open race on %s: %s", rec.id, lastError);
      rec = loadLifeline(nk, rec.id)!;
    }
  }
  // 四次都没拉起来就不是「撞车」了（比如存档升级失败）：把真正的原因带出去，别只说「正忙」
  logger.error("lifeline_open failed on %s: %s", rec.id, lastError);
  throw new Error("这条人生线暂时打不开：" + lastError);
};

/**
 * 取服务器这一版的剧情内容（和 client/data/content.json 同一份数据）。
 * 客户端在 lifeline_open 里发现内容指纹和自己带的不一样时调用，分块取完拼起来，缓存在手机上。
 * 这样改剧情只要更新服务器，两台手机不用重装。
 */
var rpcContentGet: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  var p = parsePayload(payload);
  var all = JSON.stringify(CONTENT);
  var offset = Math.min(all.length, Math.max(0, Math.floor(Number(p.offset) || 0)));
  var end = Math.min(all.length, offset + CONTENT_CHUNK);
  // 不把一个字拆成两半（UTF-16 代理对）
  var tail = all.charCodeAt(end - 1);
  if (end < all.length && tail >= 0xd800 && tail <= 0xdbff) end -= 1;
  return JSON.stringify({ version: CONTENT.version, total: all.length, offset: offset, chunk: all.substring(offset, end), done: end >= all.length });
};

/** 服务器是哪一版：部署后自检、客户端「服务器设置」里测试连接用 */
var rpcServerInfo: nkruntime.RpcFunction = function () {
  return JSON.stringify({
    protocol: PROTOCOL_VERSION,
    minClientProtocol: MIN_CLIENT_PROTOCOL,
    content: CONTENT.version,
    lifeVersion: LIFE_VERSION,
    events: CONTENT.events.length,
  });
};

/** 列出我的人生线（大厅里的「继续」），带上两人名字和走到了哪一天 */
var rpcLifelineList: nkruntime.RpcFunction = function (ctx, logger, nk) {
  if (!ctx.userId) throw new Error("需要登录");
  var list = nk.storageList(ctx.userId, COL_MINE, 50);
  var objs = list.objects || [];
  var recs = objs.length
    ? nk.storageRead(objs.map(function (o) { return { collection: COL_LIFELINES, key: o.key, userId: SYSTEM_USER }; }))
    : [];
  var byId: { [id: string]: LifelineRecord } = {};
  for (var i = 0; i < recs.length; i++) byId[recs[i].key] = recs[i].value as LifelineRecord;
  var items = objs.map(function (o) {
    var rec = byId[o.key];
    var life = rec ? rec.life : null;
    return {
      lifelineId: o.key,
      role: o.value.role,
      code: o.value.code,
      names: rec ? rec.names : null,
      paired: !!(rec && rec.members.mei),
      phase: life ? life.phase : "waiting",
      turn: life ? life.turn : 0,
      /** 第几世 */
      life: life ? life.life || 1 : 1,
      label: life && life.phase !== "roll" ? lifeTimeAt(life.turn).label : null,
      updateTime: o.updateTime,
    };
  });
  items.sort(function (a, b) { return (b.updateTime || 0) - (a.updateTime || 0); });
  return JSON.stringify({ lifelines: items });
};

/**
 * 住户本：翻看这条人生线上走完的某一世。只有这条人生线上的两个人能看；给出去的是 legacyPastView 挑过的那几样。
 * 走完还没换世的这一世从存档里读，换过世的从归档里读。
 */
var rpcLifelinePast: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  if (!ctx.userId) throw new Error("需要登录");
  var p = parsePayload(payload);
  var rec = loadLifeline(nk, String(p.lifelineId || ""));
  if (!rec) throw new Error("人生线不存在");
  if (!roleOf(rec, ctx.userId)) throw new Error("这不是你的人生线");
  var n = Math.floor(Number(p.life));
  if (!(n >= 1)) throw new Error("没有这一世");
  var names = rec.names;
  var src: any = null;
  if (rec.life && (rec.life.life || 1) === n) {
    if (rec.life.phase !== "ended") throw new Error("这一世还没走完");
    src = rec.life;
  } else {
    var found = nk.storageRead([{ collection: COL_PAST, key: rec.id + "." + n, userId: SYSTEM_USER }]);
    // 归档坏了（读出来不是一世）和没有这一世一样回话，不把运行时的报错原样给出去
    var kept: any = found.length ? found[0].value : null;
    if (!kept || !kept.past || typeof kept.past !== "object") throw new Error("没有这一世");
    src = kept.past;
    names = kept.names || names;
  }
  return JSON.stringify({ lifelineId: rec.id, names: names, past: legacyPastView(src) });
};

// ---------- 权威房间 ----------

function online(s: LifelineMatch): { [R in Role]: boolean } {
  return { qing: !!s.presences.qing, mei: !!s.presences.mei };
}

/** 在线的人各自的安装包协议版本（不在线的是 0）。客户端据此知道对门的包懂不懂新东西，比如「再来一世」 */
function protocols(s: LifelineMatch): { [R in Role]: number } {
  return { qing: s.presences.qing ? s.protocols.qing || 0 : 0, mei: s.presences.mei ? s.protocols.mei || 0 : 0 };
}

/** 只发给安装包够新的连接：旧包不认识的消息号不往它那儿送 */
function sendSince(d: nkruntime.MatchDispatcher, s: LifelineMatch, minProtocol: number, op: number, body: any) {
  var to: nkruntime.Presence[] = [];
  for (var i = 0; i < ROLES.length; i++) {
    var p = s.presences[ROLES[i]];
    if (p && (s.protocols[ROLES[i]] || 0) >= minProtocol) to.push(p);
  }
  if (to.length > 0) send(d, op, body, to);
}

/** 给世界用的「在不在」：刚掉线的宽限期内还算在，影子不接手 */
function steering(s: LifelineMatch): { [R in Role]: boolean } {
  var out = online(s);
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    var left = s.leftAt[r];
    if (!out[r] && left !== undefined && s.tick - left < SHADOW_GRACE_SECONDS * TICK_RATE) out[r] = true;
  }
  return out;
}

function send(d: nkruntime.MatchDispatcher, op: number, body: any, to?: nkruntime.Presence[]) {
  d.broadcastMessage(op, JSON.stringify(body), to || null);
}

var SNAPSHOT_LOG_TAIL = 40;

/**
 * 发给某一方的完整状态。进房、断线重连、开局、每天结束时发。
 * - 只带最近的日志，完整的一生在结局时再取
 * - 不能泄露：TA 在事件里选了什么（默契时刻要「不商量」）、命运给今天安排了什么事、随机数状态
 */
function snapshot(s: LifelineMatch, role: Role) {
  var life = s.record.life!;
  var view: any = {};
  for (var k in life) {
    // duet 不原样给：里面有「对门当年猜我会选什么」，只走 duetView()
    if (k === "rng" || k === "seed" || k === "world" || k === "duet") continue;
    view[k] = (life as any)[k];
  }
  if (life.phase !== "roll") view.duet = duetView(life, role);
  // 还欠着话的那几天，日志里的猜测也先摘掉，等回完话再揭晓
  view.log = duetLogView(life, role, life.phase === "ended" ? life.log : life.log.slice(-SNAPSHOT_LOG_TAIL));
  view.logTotal = life.log.length;
  var w = life.world;
  if (w) {
    var ev: any = null;
    if (w.event) {
      ev = {
        eventId: w.event.eventId,
        kind: w.event.kind,
        roles: w.event.roles,
        chosen: { qing: !!w.event.choices.qing, mei: !!w.event.choices.mei },
        mine: w.event.choices[role] || null,
        locks: lifeMilestoneLocks(life, CONTENT),
      };
    }
    view.world = { minute: Math.floor(w.minute), rest: w.rest, actors: w.actors, event: ev };
  } else {
    view.world = null;
  }
  return { lifelineId: s.lifelineId, names: s.record.names, life: view, you: role, online: online(s), protocols: protocols(s), tick: s.tick };
}

function worldView(s: LifelineMatch) {
  var life = s.record.life!;
  var w = life.world;
  if (!w) return null;
  var r1 = function (n: number) { return Math.round(n); };
  var actors: any = {};
  var needs: any = {};
  var money: any = {};
  var stats: any = {};
  var eff: any = {};
  var goals: any = {};
  var tracks: any = {};
  var age = lifeTimeAt(life.turn).age;
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    var a = w.actors[r];
    // seq：服务器已处理到这个人的第几条 MOVE，本地玩家拿它对照自己的历史位置做校正
    // tg：这次是搭伴做的；label：日程行动的名字跟着路走（上学 / 出摊 / 过桥上班）
    actors[r] = a ? { x: r1(a.x), y: r1(a.y), act: a.action, spot: a.spot, sleep: a.asleep, seq: s.moveSeq[r] || 0, tg: !!a.together } : null;
    var p = life.persons![r];
    needs[r] = { hunger: r1(p.needs.hunger), energy: r1(p.needs.energy), mood: r1(p.needs.mood), clean: r1(p.needs.clean) };
    money[r] = p.money;
    if (!p.alive || !a) continue;
    stats[r] = { body: lifeRound1(p.stats.body), mind: lifeRound1(p.stats.mind), charm: lifeRound1(p.stats.charm), luck: lifeRound1(p.stats.luck) };
    eff[r] = worldEfficiency(p);
    goals[r] = lifeGoal(life, CONTENT, r);
    var track = lifeTrack(CONTENT, p, age);
    var d = worldDuty(life, CONTENT, r);
    // open：现在还去不去得了（今天有、还没去、没迟到）。客户端靠它决定报到的点位上显示什么
    // unlocks：这个人在关口上挣来的去处（带 requires.flags 的行动里他走得进去的）。客户端不知道标记，靠这张单子决定点位上显示什么
    var unlocks: string[] = [];
    for (var ai = 0; ai < CONTENT.map.actions.length; ai++) {
      var arq = CONTENT.map.actions[ai].requires || {};
      if ((arq.flags || arq.notFlags) && lifeHasAll(p.flags, arq.flags) && lifeHasNone(p.flags, arq.notFlags)) unlocks.push(CONTENT.map.actions[ai].id);
    }
    tracks[r] = { id: track.id, label: track.label, unlocks: unlocks, duty: d ? { label: d.label, spot: d.spot, arrive: d.arrive, until: d.until, done: !!w.dutyDone[r], open: !!worldDutyOpen(life, CONTENT, r) } : null };
  }
  // 今天命运的「提示」：画在地图上，走近了才知道是什么事
  var hints: { zone: string; text: string }[] = [];
  var fates = [w.fate.mirror, w.fate.qing, w.fate.mei];
  for (var f = 0; f < fates.length; f++) {
    var id = fates[f];
    if (!id || w.done.indexOf(id) >= 0) continue;
    var fe = lifeFindEvent(CONTENT, id);
    if (fe.where && fe.hint) hints.push({ zone: fe.where, text: fe.hint });
  }
  var ev = w.event ? { eventId: w.event.eventId, kind: w.event.kind, roles: w.event.roles, chosen: { qing: !!w.event.choices.qing, mei: !!w.event.choices.mei } } : null;
  // tick：服务器时间轴（每秒 TICK_RATE 跳），客户端按它做插值缓冲
  return {
    tick: s.tick, minute: Math.floor(w.minute), rest: w.rest, actors: actors, needs: needs, money: money, event: ev, bond: life.bond, hints: hints,
    stats: stats, eff: eff, goals: goals, tracks: tracks,
  };
}

/**
 * 房间存档。一条人生线同一时间只有一个房间在写：带着上次写入的版本号做条件写入。
 * 写不进去说明存档被别人动过。还是我的房间（比如在 Nakama 控制台里手动改过）就以房间里的为准重写；
 * 已经是别的房间的了，就把自己标成 superseded，不再写，免得把对方的进度盖回去。
 */
function save(nk: nkruntime.Nakama, logger: nkruntime.Logger, s: LifelineMatch, tick: number): boolean {
  s.lastSaveTick = tick;
  if (s.superseded) return false;
  try {
    s.version = saveLifeline(nk, s.record, s.version);
    return true;
  } catch (e) {
    try {
      var cur = loadLifelineVersioned(nk, s.lifelineId);
      if (cur && cur.rec.matchId === s.matchId) {
        s.version = saveLifeline(nk, s.record, cur.version);
        return true;
      }
      s.superseded = true;
      logger.warn("lifeline %s: room %s superseded by %s, stop saving", s.lifelineId, String(s.matchId), String(cur ? cur.rec.matchId : null));
    } catch (e2) {
      // 存储暂时不可用：这次没存上，下个存档点再试
      logger.error("lifeline %s: save failed: %s / %s", s.lifelineId, String(e), String(e2));
    }
    return false;
  }
}

var matchInit: nkruntime.MatchInitFunction<LifelineMatch> = function (ctx, logger, nk, params) {
  var got = loadLifelineVersioned(nk, params.lifelineId);
  if (!got || !got.rec.life) throw new Error("lifeline not ready: " + params.lifelineId);
  var rec = got.rec;
  if (rec.matchId && rec.matchId !== ctx.matchId && roomUsable(nk, rec)) throw new Error(DUP_MATCH + rec.matchId);
  // 存档可能是旧结构、旧剧情下存的：先升级结构，再摘掉新内容里已经不存在的引用（见 save.ts）
  var fixed = lifeUpgrade(rec.life).concat(lifeRepair(rec.life!, CONTENT));
  if (fixed.length > 0) logger.info("lifeline %s save brought up to date: %s", rec.id, fixed.join("; "));
  // 一条人生线同一时间只能有一个房间：带版本号写入，和另一个同时拉起的房间比快
  rec.matchId = ctx.matchId || null;
  rec.matchClaimedAt = Date.now();
  var version = saveLifeline(nk, rec, got.version);
  logger.info("lifeline %s room %s opened: phase=%s turn=%d content=%s", rec.id, String(ctx.matchId), rec.life!.phase, rec.life!.turn, CONTENT.version);
  return {
    state: {
      lifelineId: rec.id, matchId: ctx.matchId || null, record: rec, version: version, superseded: false,
      presences: {}, lastMoveTick: {}, moveSeq: {}, eventWaitSince: null, lastSaveTick: 0, emptyTicks: 0, tick: 0, leftAt: {}, protocols: {},
    },
    tickRate: TICK_RATE,
    label: JSON.stringify({ lifeline: rec.id }),
  };
};

var matchJoinAttempt: nkruntime.MatchJoinAttemptFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, presence, metadata) {
  var role = roleOf(state.record, presence.userId);
  if (!role) return { state: state, accept: false, rejectMessage: "not a member" };
  // 进房时报上安装包的协议版本（3 起才报）。没报的按能进来的最旧版本算
  state.protocols[role] = Math.max(MIN_CLIENT_PROTOCOL, Math.floor(Number(metadata && metadata.protocol)) || 0);
  return { state: state, accept: true };
};

var matchJoin: nkruntime.MatchJoinFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, presences) {
  state.tick = tick;
  for (var i = 0; i < presences.length; i++) {
    var role = roleOf(state.record, presences[i].userId)!;
    // 同一个人换了连接（断线重连、切网络）：新连接顶掉旧的，旧连接的 leave 会被忽略
    state.presences[role] = presences[i];
    // 重连后客户端的 MOVE 序号从头开始
    delete state.moveSeq[role];
    delete state.lastMoveTick[role];
    delete state.leftAt[role];
    // 影子正替他做事的话，停下来把身体还给他
    if (state.record.life) worldReclaim(state.record.life, role);
    // TA 不在房间里：发一条通知，TA 在大厅也能知道「对门上线了」
    var other = lifeOther(role);
    var otherId = state.record.members[other];
    if (otherId && !state.presences[other]) {
      try {
        nk.notificationsSend([
          { userId: otherId, subject: "partner_online", content: { lifelineId: state.lifelineId, name: state.record.names[role] }, code: NOTIFY_PARTNER_ONLINE, persistent: false },
        ]);
      } catch (e) {
        logger.warn("notify partner failed: %s", String(e));
      }
    }
  }
  for (var j = 0; j < presences.length; j++) {
    send(dispatcher, OP.SNAPSHOT, snapshot(state, roleOf(state.record, presences[j].userId)!), [presences[j]]);
  }
  state.emptyTicks = 0;
  send(dispatcher, OP.PRESENCE, { online: online(state), protocols: protocols(state) });
  return { state: state };
};

var matchLeave: nkruntime.MatchLeaveFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, presences) {
  for (var i = 0; i < presences.length; i++) {
    var role = roleOf(state.record, presences[i].userId);
    if (role && state.presences[role] && state.presences[role]!.sessionId === presences[i].sessionId) {
      delete state.presences[role];
      state.leftAt[role] = tick;
    }
  }
  send(dispatcher, OP.PRESENCE, { online: online(state), protocols: protocols(state) });
  save(nk, logger, state, tick);
  return { state: state };
};

function sendError(dispatcher: nkruntime.MatchDispatcher, to: nkruntime.Presence, msg: string) {
  send(dispatcher, OP.ERROR, { message: msg }, [to]);
}

function broadcastLog(dispatcher: nkruntime.MatchDispatcher, entries: LogEntry[]) {
  if (entries.length > 0) send(dispatcher, OP.LOG, { entries: entries });
}

/**
 * 规则代码抛错了。这一跳可能只改了一半，内存里的状态不可信，不能存：
 * 丢掉它，回到上一次存档（最多丢 30 秒），关房。客户端会自动重连，从存档重新拉起房间接着玩。
 * 存档上只记一笔出错的次数和原因、清掉 matchId（让重连立刻能拉起新房间），不碰 life。
 */
function faultClose(nk: nkruntime.Nakama, logger: nkruntime.Logger, dispatcher: nkruntime.MatchDispatcher, state: LifelineMatch, tick: number, e: any): null {
  var msg = String(e && e.message ? e.message : e);
  var life = state.record.life;
  logger.error(
    "lifeline %s room fault at tick %d (phase=%s turn=%d minute=%s event=%s): %s\n%s",
    state.lifelineId, tick, life ? life.phase : "?", life ? life.turn : -1,
    String(life && life.world ? Math.floor(life.world.minute) : null),
    String(life && life.world && life.world.event ? life.world.event.eventId : null),
    msg, String((e && e.stack) || ""),
  );
  try {
    send(dispatcher, OP.ERROR, { message: "服务器这边出了点岔子，正在回到刚才的存档……", fault: true });
  } catch (e1) {
    // 通知发不出去也要把下面的善后做完
  }
  try {
    var cur = loadLifelineVersioned(nk, state.lifelineId);
    if (cur && cur.rec.matchId === state.matchId) {
      cur.rec.matchId = null;
      cur.rec.matchClaimedAt = 0;
      cur.rec.faults = (cur.rec.faults || 0) + 1;
      cur.rec.lastFault = msg.substring(0, 300);
      saveLifeline(nk, cur.rec, cur.version);
    }
  } catch (e2) {
    logger.error("lifeline %s: could not record fault: %s", state.lifelineId, String(e2));
  }
  return null;
}

var matchLoop: nkruntime.MatchLoopFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, messages) {
  try {
    return lifelineLoop(ctx, logger, nk, dispatcher, tick, state, messages);
  } catch (e) {
    return faultClose(nk, logger, dispatcher, state, tick, e);
  }
};

var lifelineLoop: nkruntime.MatchLoopFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, messages) {
  var life = state.record.life!;
  state.tick = tick;
  if (state.superseded) return null; // 存档归别的房间了：悄悄退场，不存档

  for (var i = 0; i < messages.length; i++) {
    var msg = messages[i];
    var role = roleOf(state.record, msg.sender.userId);
    if (!role) continue;
    var body: any;
    try {
      body = JSON.parse(nk.binaryToString(msg.data));
    } catch (e) {
      sendError(dispatcher, msg.sender, "bad json");
      continue;
    }
    // 边界上先把形状验了：消息体必须是对象（null、数字、数组都不行），消息号必须是客户端该发的
    if (!body || typeof body !== "object" || Array.isArray(body) || CLIENT_OPS.indexOf(msg.opCode) < 0) {
      sendError(dispatcher, msg.sender, "bad message");
      continue;
    }

    if (msg.opCode === OP.PING) {
      send(dispatcher, OP.PONG, { t: body.t, tick: tick }, [msg.sender]);
      continue;
    }
    // 旧连接（已被同一个人的新连接顶掉）发来的东西不算数
    var current = state.presences[role];
    if (!current || current.sessionId !== msg.sender.sessionId) continue;

    if (msg.opCode === OP.ROLL) {
      if (body.reroll) {
        var err = lifeReroll(life, CONTENT, role);
        if (err) sendError(dispatcher, msg.sender, err);
        send(dispatcher, OP.ROLL_STATE, { rolls: life.rolls });
      } else if (body.heirloom !== undefined) {
        var perr = legacyPick(life, role, body.heirloom === null ? null : String(body.heirloom));
        if (perr) sendError(dispatcher, msg.sender, perr);
        send(dispatcher, OP.ROLL_STATE, { rolls: life.rolls });
      } else if (body.confirm) {
        var started = lifeConfirm(life, CONTENT, role, state.record.names);
        send(dispatcher, OP.ROLL_STATE, { rolls: life.rolls });
        if (started) {
          save(nk, logger, state, tick);
          for (var rr in state.presences) send(dispatcher, OP.SNAPSHOT, snapshot(state, rr as Role), [state.presences[rr as Role]!]);
        }
      }
    } else if (msg.opCode === OP.MOVE) {
      var seq = Number(body.seq) || 0;
      var lastSeq = state.moveSeq[role] || 0;
      if (seq > 0 && seq <= lastSeq) continue; // 乱序或重复的旧包
      var last = state.lastMoveTick[role];
      var dt = last === undefined ? 0.2 : Math.min((tick - last) / TICK_RATE, MOVE_MAX_DT);
      state.lastMoveTick[role] = tick;
      if (seq > 0) state.moveSeq[role] = seq;
      worldMove(life, CONTENT, role, Number(body.x), Number(body.y), dt);
    } else if (msg.opCode === OP.ACT) {
      var res = worldAct(life, CONTENT, role, String(body.spot));
      if (res.error) sendError(dispatcher, msg.sender, res.error);
      if (res.together) broadcastLog(dispatcher, [res.together]);
    } else if (msg.opCode === OP.CHOOSE) {
      duetGuess(life, CONTENT, role, body.guess); // 要先记下，两人都选完那一刻就结算了
      var ch = worldChoose(life, CONTENT, role, String(body.optionId), false);
      if (ch.error) sendError(dispatcher, msg.sender, ch.error);
      if (ch.entry) {
        state.eventWaitSince = null;
        broadcastLog(dispatcher, [ch.entry]);
      }
    } else if (msg.opCode === OP.GAME_INPUT) {
      gameOnMessage(life, dispatcher, role, body);
    } else if (msg.opCode === OP.ECHO) {
      var echo = duetEcho(life, CONTENT, role, Number(body.turn), body.optionId);
      if (echo.error) sendError(dispatcher, msg.sender, echo.error);
      if (echo.entry) broadcastLog(dispatcher, [echo.entry]);
    } else if (msg.opCode === OP.AGAIN) {
      if (life.phase !== "ended") { sendError(dispatcher, msg.sender, "这一世还没走完"); continue; }
      // 票记在存档里（重连、重启、回滚都不丢），变了就马上存一次；换世在下面，两票齐了就换。
      // 没变的（连着点）不写存储，回执照发：客户端拿它对齐自己的按钮
      var want = body.yes !== false;
      var had = !!(life.again && life.again[role]);
      legacyAgain(life, role, want);
      if (had !== want) save(nk, logger, state, tick);
      sendSince(dispatcher, state, LEGACY_SINCE_PROTOCOL, OP.AGAIN, { again: life.again });
    }
  }

  // 两个人都点了「再来一世」：先把走完的这一世归档，再在同一份存档上换成新的一世，像翻天那样马上存。
  // 放在这里而不是消息处理里：票在存档里，上次归档完没来得及换就断了的，房间重新拉起后接着换
  if (legacyAgainReady(life)) {
    archiveLife(nk, state.record);
    life = state.record.life = legacyRebirth(life, CONTENT);
    state.eventWaitSince = null;
    save(nk, logger, state, tick);
    logger.info("lifeline %s: life %d begins", state.lifelineId, life.life || 1);
    for (var ar in state.presences) send(dispatcher, OP.SNAPSHOT, snapshot(state, ar as Role), [state.presences[ar as Role]!]);
  }

  if (life.phase === "life") {
    var w = life.world!;
    if (w.event) {
      // 事件里还没选的人如果都离线了，等一会儿让影子替他选
      var pe = w.event;
      var missing = pe.roles.filter(function (r) { return !pe.choices[r]; });
      var offlineMissing = missing.filter(function (r) { return !state.presences[r]; });
      if (missing.length > 0 && offlineMissing.length === missing.length) {
        if (state.eventWaitSince === null) state.eventWaitSince = tick;
        if (tick - state.eventWaitSince >= SHADOW_WAIT_SECONDS * TICK_RATE) {
          for (var k = 0; k < offlineMissing.length; k++) {
            var r = offlineMissing[k];
            var sc = worldChoose(life, CONTENT, r, lifeShadowChoose(life, CONTENT, r, pe.eventId), true);
            if (sc.entry) broadcastLog(dispatcher, [sc.entry]);
          }
          state.eventWaitSince = null;
        }
      } else {
        state.eventWaitSince = null;
      }
    }

    gameLoop(life, state, dispatcher, tick);
    if (state.presences.qing || state.presences.mei) {
      var t = worldAdvance(life, CONTENT, 1 / TICK_RATE, steering(state));
      if (t.started) send(dispatcher, OP.EVENT, { event: t.started, locks: lifeMilestoneLocks(life, CONTENT) });
      broadcastLog(dispatcher, t.entries);
      if (t.dayEnded) {
        save(nk, logger, state, tick);
        for (var pr in state.presences) send(dispatcher, OP.SNAPSHOT, snapshot(state, pr as Role), [state.presences[pr as Role]!]);
      }
    }
    if (tick % WORLD_BROADCAST_EVERY === 0 && life.world) send(dispatcher, OP.WORLD, worldView(state));
  }

  if (tick - state.lastSaveTick >= SAVE_EVERY_SECONDS * TICK_RATE) save(nk, logger, state, tick);

  // 空房间超时关闭
  if (!state.presences.qing && !state.presences.mei) {
    state.emptyTicks += 1;
    if (state.emptyTicks >= EMPTY_CLOSE_SECONDS * TICK_RATE) {
      closeRoom(nk, logger, state, "empty");
      return null;
    }
  }
  return { state: state };
};

var matchTerminate: nkruntime.MatchTerminateFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state) {
  closeRoom(nk, logger, state, "terminate");
  return { state: state };
};

/** 房间关闭：存档，并清掉存档里的 matchId，下次 lifeline_open 重新拉起 */
function closeRoom(nk: nkruntime.Nakama, logger: nkruntime.Logger, state: LifelineMatch, why: string) {
  state.record.matchId = null;
  state.record.matchClaimedAt = 0;
  var saved = save(nk, logger, state, state.tick);
  logger.info("lifeline %s room %s closed (%s): turn=%d saved=%s", state.lifelineId, String(state.matchId), why, state.record.life ? state.record.life.turn : -1, String(saved));
}

var matchSignal: nkruntime.MatchSignalFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, data) {
  return { state: state, data: data };
};

// ---------- 注册 ----------

var InitModule: nkruntime.InitModule = function (ctx, logger, nk, initializer) {
  initializer.registerRpc("lifeline_create", rpcLifelineCreate);
  initializer.registerRpc("lifeline_join", rpcLifelineJoin);
  initializer.registerRpc("lifeline_open", rpcLifelineOpen);
  initializer.registerRpc("lifeline_list", rpcLifelineList);
  initializer.registerRpc("lifeline_past", rpcLifelinePast);
  initializer.registerRpc("content_get", rpcContentGet);
  initializer.registerRpc("server_info", rpcServerInfo);
  initializer.registerMatch<LifelineMatch>(MATCH_NAME, {
    matchInit: matchInit,
    matchJoinAttempt: matchJoinAttempt,
    matchJoin: matchJoin,
    matchLeave: matchLeave,
    matchLoop: matchLoop,
    matchTerminate: matchTerminate,
    matchSignal: matchSignal,
  });
  logger.info("同岁 server module loaded: %d events, %d families, content %s, protocol %d", CONTENT.events.length, CONTENT.families.length, CONTENT.version, PROTOCOL_VERSION);
};

// 防止 InitModule 被当作未使用代码删掉（Nakama 官方 TS 模板的写法）
// @ts-ignore
!InitModule && InitModule.bind(null);
