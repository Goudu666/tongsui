// Nakama 入口：配对 RPC + 权威回合房间「lifeline」
//
// 一条 lifeline = 两个人的一生。存档在 storage(lifelines/<id>)，房间只是它在线时的载体：
// 两人都下线后房间会关闭，下次 lifeline_open 时从存档重新拉起。

var SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
var COL_LIFELINES = "lifelines";
var COL_CODES = "pair_codes";
var COL_MINE = "my_lifelines";
var MATCH_NAME = "lifeline";
var TICK_RATE = 1; // 回合制，一秒一跳足够
var SHADOW_WAIT_SECONDS = 30; // 搭档离线时，等多久让影子代选
var EMPTY_CLOSE_SECONDS = 120; // 房间空了多久后关闭

/** 客户端 ↔ 服务端消息号，client/scripts/net/protocol.gd 里保持一致 */
var OP = {
  SNAPSHOT: 1, // s→c 完整状态
  CHOOSE: 2, // c→s { optionId }
  RESOLVED: 3, // s→c { entries, state }
  PROGRESS: 4, // s→c { chosen, online }
  ERROR: 9, // s→c { message }
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
  choices: Choices;
  /** 有人已经选好、另一个人不在线时开始计时 */
  waitingSinceTick: number | null;
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
  rec.life = lifeCreate(Math.floor(Math.random() * 0x7fffffff), rec.names, CONTENT_EVENTS);
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

function publicState(s: LifelineMatch) {
  return { lifelineId: s.lifelineId, names: s.record.names, life: s.record.life };
}

function progress(s: LifelineMatch) {
  return {
    chosen: { qing: !!s.choices.qing, mei: !!s.choices.mei },
    online: { qing: !!s.presences.qing, mei: !!s.presences.mei },
  };
}

var matchInit: nkruntime.MatchInitFunction<LifelineMatch> = function (ctx, logger, nk, params) {
  var rec = loadLifeline(nk, params.lifelineId);
  if (!rec || !rec.life) throw new Error("lifeline not ready: " + params.lifelineId);
  return {
    state: { lifelineId: rec.id, record: rec, presences: {}, choices: {}, waitingSinceTick: null, emptyTicks: 0 },
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
    var snap = publicState(state) as any;
    snap.you = role;
    snap.progress = progress(state);
    dispatcher.broadcastMessage(OP.SNAPSHOT, JSON.stringify(snap), [presences[i]]);
  }
  state.emptyTicks = 0;
  dispatcher.broadcastMessage(OP.PROGRESS, JSON.stringify(progress(state)));
  return { state: state };
};

var matchLeave: nkruntime.MatchLeaveFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, presences) {
  for (var i = 0; i < presences.length; i++) {
    var role = roleOf(state.record, presences[i].userId);
    if (role && state.presences[role] && state.presences[role]!.sessionId === presences[i].sessionId) {
      delete state.presences[role];
    }
  }
  dispatcher.broadcastMessage(OP.PROGRESS, JSON.stringify(progress(state)));
  return { state: state };
};

function sendError(dispatcher: nkruntime.MatchDispatcher, to: nkruntime.Presence, msg: string) {
  dispatcher.broadcastMessage(OP.ERROR, JSON.stringify({ message: msg }), [to]);
}

var matchLoop: nkruntime.MatchLoopFunction<LifelineMatch> = function (ctx, logger, nk, dispatcher, tick, state, messages) {
  var life = state.record.life!;
  var changed = false;

  for (var i = 0; i < messages.length; i++) {
    var msg = messages[i];
    var role = roleOf(state.record, msg.sender.userId);
    if (!role) continue;
    if (msg.opCode !== OP.CHOOSE) continue;
    var body: any;
    try {
      body = JSON.parse(nk.binaryToString(msg.data));
    } catch (e) {
      sendError(dispatcher, msg.sender, "bad json");
      continue;
    }
    if (!lifeIsValidChoice(life, CONTENT_EVENTS, role, String(body.optionId))) {
      sendError(dispatcher, msg.sender, "invalid choice");
      continue;
    }
    state.choices[role] = String(body.optionId); // 允许在结算前改主意
    changed = true;
  }

  // 是否可以结算
  var required = lifeRequiredRoles(life);
  var missing = required.filter(function (r) { return !state.choices[r]; });
  var shadow: Role[] = [];
  if (!life.ended && required.length > 0 && missing.length < required.length) {
    var offlineMissing = missing.filter(function (r) { return !state.presences[r]; });
    if (offlineMissing.length > 0 && offlineMissing.length === missing.length) {
      if (state.waitingSinceTick === null) state.waitingSinceTick = tick;
      if (tick - state.waitingSinceTick >= SHADOW_WAIT_SECONDS * TICK_RATE) {
        for (var k = 0; k < offlineMissing.length; k++) {
          state.choices[offlineMissing[k]] = lifeShadowChoose(life, CONTENT_EVENTS, offlineMissing[k]);
          shadow.push(offlineMissing[k]);
        }
        missing = [];
      }
    } else {
      state.waitingSinceTick = null;
    }
  }

  if (!life.ended && required.length > 0 && missing.length === 0) {
    var entries = lifeResolve(life, CONTENT_EVENTS, state.choices, shadow);
    state.choices = {};
    state.waitingSinceTick = null;
    saveLifeline(nk, state.record);
    dispatcher.broadcastMessage(OP.RESOLVED, JSON.stringify({ entries: entries, state: publicState(state) }));
  } else if (changed) {
    dispatcher.broadcastMessage(OP.PROGRESS, JSON.stringify(progress(state)));
  }

  // 空房间超时关闭（存档已在每回合写入）
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
  logger.info("同岁 server module loaded: %d events", CONTENT_EVENTS.length);
};

// 防止 InitModule 被当作未使用代码删掉（Nakama 官方 TS 模板的写法）
// @ts-ignore
!InitModule && InitModule.bind(null);
