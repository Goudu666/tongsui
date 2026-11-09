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
};

interface LifelineRecord {
  id: string;
  code: string;
  members: { qing: string; mei: string | null };
  names: { qing: string; mei: string };
  matchId: string | null;
  life: LifeState | null;
}

interface LifelineMatch {
  lifelineId: string;
  record: LifelineRecord;
  presences: { [R in Role]?: nkruntime.Presence };
  /** 上一次收到各自 MOVE 的 tick，用来限速 */
  lastMoveTick: { [R in Role]?: number };
  /** 当前事件开始等待离线搭档的 tick */
  eventWaitSince: number | null;
  lastSaveTick: number;
  emptyTicks: number;
}

// ---------- 存储 ----------

function loadLifeline(nk: nkruntime.Nakama, id: string): LifelineRecord | null {
  var r = nk.storageRead([{ collection: COL_LIFELINES, key: id, userId: SYSTEM_USER }]);
  return r.length ? (r[0].value as LifelineRecord) : null;
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
  logger.info("lifeline %s joined by %s", rec.id, ctx.userId);
  return JSON.stringify({ lifelineId: rec.id, role: "mei" });
};

/** 打开人生线：返回正在运行的房间，没有就从存档拉起一个 */
var rpcLifelineOpen: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  if (!ctx.userId) throw new Error("需要登录");
  var p = parsePayload(payload);
  var rec = loadLifeline(nk, String(p.lifelineId || ""));
  if (!rec) throw new Error("人生线不存在");
  var role = roleOf(rec, ctx.userId);
  if (!role) throw new Error("这不是你的人生线");
  if (!rec.life) return JSON.stringify({ lifelineId: rec.id, role: role, matchId: null, waitingForPartner: true, code: rec.code });

  if (rec.matchId && nk.matchGet(rec.matchId)) {
    return JSON.stringify({ lifelineId: rec.id, role: role, matchId: rec.matchId });
  }
  var matchId = nk.matchCreate(MATCH_NAME, { lifelineId: rec.id });
  rec.matchId = matchId;
  saveLifeline(nk, rec);
  return JSON.stringify({ lifelineId: rec.id, role: role, matchId: matchId });
};

/** 列出我的人生线 */
var rpcLifelineList: nkruntime.RpcFunction = function (ctx, logger, nk) {
  if (!ctx.userId) throw new Error("需要登录");
  var list = nk.storageList(ctx.userId, COL_MINE, 50);
  var items = (list.objects || []).map(function (o) {
    return { lifelineId: o.key, role: o.value.role, code: o.value.code };
  });
  return JSON.stringify({ lifelines: items });
};

// ---------- 权威房间 ----------

function online(s: LifelineMatch): { [R in Role]: boolean } {
  return { qing: !!s.presences.qing, mei: !!s.presences.mei };
}

function send(d: nkruntime.MatchDispatcher, op: number, body: any, to?: nkruntime.Presence[]) {
  d.broadcastMessage(op, JSON.stringify(body), to || null);
}

var SNAPSHOT_LOG_TAIL = 40;

/** 快照里只带最近的日志，完整的一生在结局时再取 */
function snapshot(s: LifelineMatch, role: Role) {
  var life = s.record.life!;
  var view: any = {};
  for (var k in life) view[k] = (life as any)[k];
  view.log = life.log.slice(-SNAPSHOT_LOG_TAIL);
  view.logTotal = life.log.length;
  if (life.phase === "ended") view.log = life.log;
  return { lifelineId: s.lifelineId, names: s.record.names, life: view, you: role, online: online(s) };
}

function worldView(life: LifeState) {
  var w = life.world;
  if (!w) return null;
  var r1 = function (n: number) { return Math.round(n); };
  var actors: any = {};
  var needs: any = {};
  var money: any = {};
  for (var i = 0; i < ROLES.length; i++) {
    var r = ROLES[i];
    var a = w.actors[r];
    actors[r] = a ? { x: r1(a.x), y: r1(a.y), act: a.action, spot: a.spot, sleep: a.asleep } : null;
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
  return { minute: Math.floor(w.minute), schoolDay: w.schoolDay, actors: actors, needs: needs, money: money, event: ev, bond: life.bond, hints: hints };
}

function save(nk: nkruntime.Nakama, s: LifelineMatch, tick: number) {
  saveLifeline(nk, s.record);
  s.lastSaveTick = tick;
}

var matchInit: nkruntime.MatchInitFunction<LifelineMatch> = function (ctx, logger, nk, params) {
  var rec = loadLifeline(nk, params.lifelineId);
  if (!rec || !rec.life) throw new Error("lifeline not ready: " + params.lifelineId);
  return {
    state: { lifelineId: rec.id, record: rec, presences: {}, lastMoveTick: {}, eventWaitSince: null, lastSaveTick: 0, emptyTicks: 0 },
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
  for (var i = 0; i < presences.length; i++) {
    var role = roleOf(state.record, presences[i].userId)!;
    state.presences[role] = presences[i];
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
      var last = state.lastMoveTick[role];
      var dt = last === undefined ? 0.2 : (tick - last) / TICK_RATE;
      state.lastMoveTick[role] = tick;
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
      var t = worldAdvance(life, CONTENT, 1 / TICK_RATE, online(state));
      if (t.started) send(dispatcher, OP.EVENT, { event: t.started });
      broadcastLog(dispatcher, t.entries);
      if (t.dayEnded) {
        save(nk, state, tick);
        for (var pr in state.presences) send(dispatcher, OP.SNAPSHOT, snapshot(state, pr as Role), [state.presences[pr as Role]!]);
      }
    }
    if (tick % WORLD_BROADCAST_EVERY === 0 && life.world) send(dispatcher, OP.WORLD, worldView(life));
  }

  if (tick - state.lastSaveTick >= SAVE_EVERY_SECONDS * TICK_RATE) save(nk, state, tick);

  // 空房间超时关闭
  if (!state.presences.qing && !state.presences.mei) {
    state.emptyTicks += 1;
    if (state.emptyTicks >= EMPTY_CLOSE_SECONDS * TICK_RATE) return null;
  }
  return { state: state };
};

var matchTerminate: nkruntime.MatchTerminateFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state) {
  saveLifeline(nk, state.record);
  return { state: state };
};

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
