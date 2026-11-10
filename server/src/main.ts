// Nakama 入口：配对 RPC + 权威实时房间「lifeline」
//
// 一条 lifeline = 两个人的一生。存档在 storage(lifelines/<id>)，房间只是它在线时的载体：
// 两人都下线后房间会关闭，下次 lifeline_open 时从存档重新拉起。
// 房间流程：抽卡（roll）→ 人生（life：河畔里实时走动、行动、事件）→ 结束（ended）

var SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
var COL_LIFELINES = "lifelines";
var COL_CODES = "pair_codes";
var COL_MINE = "my_lifelines";
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

/** 客户端 ↔ 服务端消息号，client/scripts/net/protocol.gd 里保持一致 */
var OP = {
  SNAPSHOT: 1, // s→c 完整状态 { lifelineId, names, life, you, online }
  ROLL: 2, // c→s { reroll: true } | { confirm: true }
  ROLL_STATE: 3, // s→c { rolls }
  MOVE: 4, // c→s { x, y }
  ACT: 5, // c→s { spot }
  CHOOSE: 6, // c→s { optionId }
  WORLD: 7, // s→c 精简世界状态（5Hz）
  EVENT: 8, // s→c { event } 有事件开始了
  ERROR: 9, // s→c { message }
  LOG: 10, // s→c { entries } 事件结算、同框、一天结束、死亡
  PRESENCE: 11, // s→c { online }
  PING: 12, // c→s { t } 心跳，客户端用来测延迟、发现死连接
  PONG: 13, // s→c { t, tick } 原样带回 t，附上服务器 tick
};

interface LifelineRecord {
  id: string;
  code: string;
  members: { qing: string; mei: string | null };
  names: { qing: string; mei: string };
  matchId: string | null;
  /** matchId 写进存档的时间（ms）。刚拉起的房间要等 matchInit 返回后才能被 matchGet 查到，这段时间也算「活着」 */
  matchClaimedAt?: number;
  life: LifeState | null;
}

interface LifelineMatch {
  lifelineId: string;
  record: LifelineRecord;
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

function saveLifeline(nk: nkruntime.Nakama, rec: LifelineRecord) {
  nk.storageWrite([
    { collection: COL_LIFELINES, key: rec.id, userId: SYSTEM_USER, value: rec as any, permissionRead: 0, permissionWrite: 0 },
  ]);
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
  var rec = loadLifeline(nk, String(p.lifelineId || ""));
  if (!rec) throw new Error("人生线不存在");
  var role = roleOf(rec, ctx.userId);
  if (!role) throw new Error("这不是你的人生线");
  if (!rec.life) return JSON.stringify({ lifelineId: rec.id, role: role, matchId: null, waitingForPartner: true, code: rec.code });

  for (var attempt = 0; attempt < 4; attempt++) {
    if (roomUsable(nk, rec)) {
      return JSON.stringify({ lifelineId: rec.id, role: role, matchId: rec.matchId });
    }
    try {
      var matchId = nk.matchCreate(MATCH_NAME, { lifelineId: rec.id });
      return JSON.stringify({ lifelineId: rec.id, role: role, matchId: matchId });
    } catch (e) {
      // 另一个人刚好也在拉起房间：DUP_MATCH 里带着赢家的房间；版本冲突就重读存档再来
      var msg = String(e && (e as any).message ? (e as any).message : e);
      var dup = msg.match(/DUP_MATCH:([^\s"']+)/);
      if (dup) return JSON.stringify({ lifelineId: rec.id, role: role, matchId: dup[1] });
      logger.info("lifeline_open race on %s: %s", rec.id, msg);
      rec = loadLifeline(nk, rec.id)!;
    }
  }
  throw new Error("房间正忙，请再试一次");
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
      label: life && life.phase !== "roll" ? lifeTimeAt(life.turn).label : null,
      updateTime: o.updateTime,
    };
  });
  items.sort(function (a, b) { return (b.updateTime || 0) - (a.updateTime || 0); });
  return JSON.stringify({ lifelines: items });
};

// ---------- 权威房间 ----------

function online(s: LifelineMatch): { [R in Role]: boolean } {
  return { qing: !!s.presences.qing, mei: !!s.presences.mei };
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
    if (k === "rng" || k === "seed" || k === "world") continue;
    view[k] = (life as any)[k];
  }
  view.log = life.phase === "ended" ? life.log : life.log.slice(-SNAPSHOT_LOG_TAIL);
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
      };
    }
    view.world = { minute: Math.floor(w.minute), schoolDay: w.schoolDay, actors: w.actors, event: ev };
  } else {
    view.world = null;
  }
  return { lifelineId: s.lifelineId, names: s.record.names, life: view, you: role, online: online(s), tick: s.tick };
}

function worldView(s: LifelineMatch) {
  var life = s.record.life!;
  var w = life.world;
  if (!w) return null;
  var r1 = function (n: number) { return Math.round(n); };
  var actors: any = {};
  var needs: any = {};
  var money: any = {};
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    var a = w.actors[r];
    // seq：服务器已处理到这个人的第几条 MOVE，本地玩家拿它对照自己的历史位置做校正
    actors[r] = a ? { x: r1(a.x), y: r1(a.y), act: a.action, spot: a.spot, sleep: a.asleep, seq: s.moveSeq[r] || 0 } : null;
    var p = life.persons![r];
    needs[r] = { hunger: r1(p.needs.hunger), energy: r1(p.needs.energy), mood: r1(p.needs.mood), clean: r1(p.needs.clean) };
    money[r] = p.money;
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
  return { tick: s.tick, minute: Math.floor(w.minute), schoolDay: w.schoolDay, actors: actors, needs: needs, money: money, event: ev, bond: life.bond, hints: hints };
}

function save(nk: nkruntime.Nakama, s: LifelineMatch, tick: number) {
  saveLifeline(nk, s.record);
  s.lastSaveTick = tick;
}

var matchInit: nkruntime.MatchInitFunction<LifelineMatch> = function (ctx, logger, nk, params) {
  var got = loadLifelineVersioned(nk, params.lifelineId);
  if (!got || !got.rec.life) throw new Error("lifeline not ready: " + params.lifelineId);
  var rec = got.rec;
  if (rec.matchId && rec.matchId !== ctx.matchId && roomUsable(nk, rec)) throw new Error(DUP_MATCH + rec.matchId);
  // 一条人生线同一时间只能有一个房间：带版本号写入，和另一个同时拉起的房间比快
  rec.matchId = ctx.matchId || null;
  rec.matchClaimedAt = Date.now();
  nk.storageWrite([
    { collection: COL_LIFELINES, key: rec.id, userId: SYSTEM_USER, value: rec as any, version: got.version, permissionRead: 0, permissionWrite: 0 },
  ]);
  return {
    state: { lifelineId: rec.id, record: rec, presences: {}, lastMoveTick: {}, moveSeq: {}, eventWaitSince: null, lastSaveTick: 0, emptyTicks: 0, tick: 0, leftAt: {} },
    tickRate: TICK_RATE,
    label: JSON.stringify({ lifeline: rec.id }),
  };
};

var matchJoinAttempt: nkruntime.MatchJoinAttemptFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, presence) {
  var role = roleOf(state.record, presence.userId);
  if (!role) return { state: state, accept: false, rejectMessage: "not a member" };
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
  send(dispatcher, OP.PRESENCE, { online: online(state) });
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
  send(dispatcher, OP.PRESENCE, { online: online(state) });
  save(nk, state, tick);
  return { state: state };
};

function sendError(dispatcher: nkruntime.MatchDispatcher, to: nkruntime.Presence, msg: string) {
  send(dispatcher, OP.ERROR, { message: msg }, [to]);
}

function broadcastLog(dispatcher: nkruntime.MatchDispatcher, entries: LogEntry[]) {
  if (entries.length > 0) send(dispatcher, OP.LOG, { entries: entries });
}

var matchLoop: nkruntime.MatchLoopFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, messages) {
  var life = state.record.life!;
  state.tick = tick;

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
      } else if (body.confirm) {
        var started = lifeConfirm(life, CONTENT, role, state.record.names);
        send(dispatcher, OP.ROLL_STATE, { rolls: life.rolls });
        if (started) {
          save(nk, state, tick);
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
      var ch = worldChoose(life, CONTENT, role, String(body.optionId), false);
      if (ch.error) sendError(dispatcher, msg.sender, ch.error);
      if (ch.entry) {
        state.eventWaitSince = null;
        broadcastLog(dispatcher, [ch.entry]);
      }
    }
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

    if (state.presences.qing || state.presences.mei) {
      var t = worldAdvance(life, CONTENT, 1 / TICK_RATE, steering(state));
      if (t.started) send(dispatcher, OP.EVENT, { event: t.started });
      broadcastLog(dispatcher, t.entries);
      if (t.dayEnded) {
        save(nk, state, tick);
        for (var pr in state.presences) send(dispatcher, OP.SNAPSHOT, snapshot(state, pr as Role), [state.presences[pr as Role]!]);
      }
    }
    if (tick % WORLD_BROADCAST_EVERY === 0 && life.world) send(dispatcher, OP.WORLD, worldView(state));
  }

  if (tick - state.lastSaveTick >= SAVE_EVERY_SECONDS * TICK_RATE) save(nk, state, tick);

  // 空房间超时关闭
  if (!state.presences.qing && !state.presences.mei) {
    state.emptyTicks += 1;
    if (state.emptyTicks >= EMPTY_CLOSE_SECONDS * TICK_RATE) {
      closeRoom(nk, state);
      return null;
    }
  }
  return { state: state };
};

var matchTerminate: nkruntime.MatchTerminateFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state) {
  closeRoom(nk, state);
  return { state: state };
};

/** 房间关闭：存档，并清掉存档里的 matchId，下次 lifeline_open 重新拉起 */
function closeRoom(nk: nkruntime.Nakama, state: LifelineMatch) {
  state.record.matchId = null;
  state.record.matchClaimedAt = 0;
  saveLifeline(nk, state.record);
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
  initializer.registerMatch<LifelineMatch>(MATCH_NAME, {
    matchInit: matchInit,
    matchJoinAttempt: matchJoinAttempt,
    matchJoin: matchJoin,
    matchLeave: matchLeave,
    matchLoop: matchLoop,
    matchTerminate: matchTerminate,
    matchSignal: matchSignal,
  });
  logger.info("同岁 server module loaded: %d events, %d families", CONTENT.events.length, CONTENT.families.length);
};

// 防止 InitModule 被当作未使用代码删掉（Nakama 官方 TS 模板的写法）
// @ts-ignore
!InitModule && InitModule.bind(null);
