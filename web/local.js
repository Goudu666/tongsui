// 网页单机版：把服务器（server/build/index.js，和 Nakama 上跑的是同一份规则）放进浏览器里跑，
// 对门那个人由电脑陪着过（下面的 Pal）。Godot 网页版通过 JavaScriptBridge 调 window.TongsuiLocal：
//   rpcCall(name, json) → json   和 Nakama 的 RPC 一样（lifeline_create / open / list / past / content_get）
//   joinMatch(matchId, metaJson) 进房间；对门的电脑同时进来
//   sendMsg(op, json)            房间消息（MOVE / ACT / CHOOSE …）
//   leaveMatch()                 回大厅
//   drain() → json               服务器发给我的消息，[{op, data}]，客户端每帧来取
// 存档：假 Nakama 的存储整份写进 localStorage（换浏览器、清缓存就没了）。
// 规则一行不改：房间、影子、主线、关口、结局都走 matchLoop，所以这里玩到的就是联机版的规则。
//
// 打包：node web/build.mjs 把 server/build/index.js 包进一个函数作用域（不污染 window、不用 eval），和本文件拼成 tongsui-local.js。
/* global TongsuiServer */
(function () {
  "use strict";
  var S = TongsuiServer; // build.mjs 包出来的：服务器所有顶层函数和常量
  var C = S.CONTENT;
  var OP = S.OP;
  var TICK = S.TICK_RATE || 10;
  var SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
  var STORE_KEY = "tongsui.local.v1";
  var ME = { userId: "u-me-0000000000", username: "me" };
  var PAL = { userId: "u-pal-000000000", username: "pal" };
  var PAL_NAME = "阿蘅";

  var logger = {
    info: function () {}, debug: function () {},
    warn: function () { console.warn.apply(console, ["[同岁]"].concat([].slice.call(arguments))); },
    error: function () { console.error.apply(console, ["[同岁]"].concat([].slice.call(arguments))); },
  };

  // ---------------- 假 Nakama：存储进 localStorage ----------------
  var store = new Map();
  var ver = 0, matchSeq = 0, clock = 1000;
  function k(c, key, u) { return c + "/" + u + "/" + key; }
  function loadStore() {
    try {
      var raw = localStorage.getItem(STORE_KEY);
      if (!raw) return;
      var o = JSON.parse(raw);
      ver = o.ver || 0; clock = o.clock || 1000;
      for (var key in o.items) store.set(key, o.items[key]);
      // 上一次开着的房间随页面一起没了：把存档里记的房间清掉，下次打开重新拉一个
      store.forEach(function (v, key) {
        if (key.indexOf("lifelines/" + SYSTEM_USER + "/") === 0 && v.value) { v.value.matchId = null; v.value.matchClaimedAt = null; }
      });
    } catch (e) { console.warn("[同岁] 读存档失败", e); }
  }
  var saveTimer = null;
  function writeStore() {
    try {
      var items = {};
      store.forEach(function (v, key) { items[key] = v; });
      localStorage.setItem(STORE_KEY, JSON.stringify({ ver: ver, clock: clock, items: items }));
    } catch (e) { console.warn("[同岁] 存档写不进浏览器", e); }
  }
  function saveStore() {
    if (saveTimer) return;
    saveTimer = setTimeout(function () { saveTimer = null; writeStore(); }, 300);
  }
  var clone = typeof structuredClone === "function" ? structuredClone : function (x) { return JSON.parse(JSON.stringify(x)); };
  var decoder = new TextDecoder(), encoder = new TextEncoder();
  var matches = new Map();
  var nk = {
    uuidv4: function () { return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (ch) { var r = (Math.random() * 16) | 0; return (ch === "x" ? r : (r & 3) | 8).toString(16); }); },
    storageRead: function (reqs) {
      var out = [];
      reqs.forEach(function (r) {
        var o = store.get(k(r.collection, r.key, r.userId));
        if (o) out.push({ key: r.key, value: clone(o.value), version: o.version, updateTime: o.updateTime });
      });
      return out;
    },
    storageWrite: function (ws) {
      ws.forEach(function (w) {
        var cur = store.get(k(w.collection, w.key, w.userId));
        if (w.version !== undefined) {
          var ok = w.version === "*" ? !cur : cur && cur.version === w.version;
          if (!ok) throw new Error("Storage write rejected - version check failed.");
        }
      });
      var res = ws.map(function (w) {
        var version = "v" + ++ver;
        store.set(k(w.collection, w.key, w.userId), { value: clone(w.value), version: version, updateTime: ++clock });
        return { collection: w.collection, key: w.key, userId: w.userId, version: version };
      });
      saveStore();
      return res;
    },
    storageList: function (u, c) {
      var objects = [];
      store.forEach(function (o, key) {
        if (key.indexOf(c + "/" + u + "/") === 0) objects.push({ key: key.split("/")[2], value: o.value, updateTime: o.updateTime });
      });
      return { objects: objects };
    },
    matchCreate: function (name, params) {
      var id = "local-" + ++matchSeq + ".web";
      var init = S.matchInit({ matchId: id }, logger, nk, params);
      matches.set(id, { id: id, state: init.state, tick: 1, inbox: [], pal: null, me: null });
      return id;
    },
    matchGet: function (id) { return matches.has(id) ? { matchId: id } : null; },
    notificationsSend: function () {},
    binaryToString: function (b) { return decoder.decode(b); },
  };

  // ---------------- 房间：一秒十跳 ----------------
  var outbox = [];
  var room = null;
  var sessionSeq = 0;
  var dispatcher = {
    broadcastMessage: function (op, data, to) {
      if (!room || !room.me) return;
      if (to && !to.some(function (p) { return p.sessionId === room.me.sessionId; })) return;
      outbox.push({ op: op, data: data });
    },
  };
  function msg(p, op, body) { return { sender: p, opCode: op, data: encoder.encode(JSON.stringify(body)) }; }
  function life() { return room && room.state.record.life; }

  function joinRoom(matchId, meta) {
    var m = matches.get(matchId);
    if (!m) return false;
    if (room && room !== m) room = null;
    room = m;
    var me = { userId: ME.userId, sessionId: "s-me-" + ++sessionSeq, username: ME.username, node: "web" };
    var pal = { userId: PAL.userId, sessionId: "s-pal-" + sessionSeq, username: PAL.username, node: "web" };
    var att = S.matchJoinAttempt({}, logger, nk, dispatcher, m.tick, m.state, me, meta || {});
    if (!att || !att.accept) { outbox.push({ op: OP.ERROR, data: JSON.stringify({ message: (att && att.rejectMessage) || "进不了房间" }) }); return false; }
    m.state = att.state;
    m.me = me;
    var patt = S.matchJoinAttempt({}, logger, nk, dispatcher, m.tick, m.state, pal, { protocol: String(S.PROTOCOL_VERSION) });
    m.state = patt.state;
    m.state = S.matchJoin({}, logger, nk, dispatcher, m.tick, m.state, [me, pal]).state;
    m.pal = new Pal(pal);
    return true;
  }

  function step() {
    if (!room || !room.me) return; // 你回了大厅：房间停着等你，不让影子替你过
    var m = room;
    var msgs = m.inbox; m.inbox = [];
    if (m.pal) { try { msgs = msgs.concat(m.pal.think(m.state.record.life)); } catch (e) { console.warn("[同岁] 对门的电脑出错了", e); } }
    if (m.auto) { try { msgs = msgs.concat(m.auto.think(m.state.record.life)); } catch (e) { console.warn("[同岁] 自动驾驶出错了", e); } }
    var res = S.matchLoop({}, logger, nk, dispatcher, m.tick++, m.state, msgs);
    if (res === null) {
      matches.delete(m.id);
      room = null;
      outbox.push({ op: OP.ERROR, data: JSON.stringify({ message: "房间出了点问题，回大厅再进一次" }) });
      return;
    }
    m.state = res.state;
  }

  // 页面在后台时不跑（浏览器本来也会把定时器压到一秒一次）；回来以后接着过，不追赶
  var last = performance.now(), acc = 0, speed = 1;
  setInterval(function () {
    var now = performance.now();
    if (document.hidden) { last = now; acc = 0; return; }
    acc += Math.min(now - last, 500);
    last = now;
    var dt = 1000 / TICK / speed;
    while (acc >= dt) { acc -= dt; step(); }
  }, 1000 / TICK / 2);

  // 关页面、切到后台：房间平时三十秒存一次，这时候马上存一次，关掉再开从刚才那一刻接着过
  function saveNow() {
    if (!room) return;
    try { S.save(nk, logger, room.state, room.tick); } catch (e) { console.warn("[同岁] 存不上", e); }
    if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
    writeStore();
  }
  if (typeof addEventListener === "function") {
    addEventListener("pagehide", saveNow);
    addEventListener("visibilitychange", function () { if (document.hidden) saveNow(); });
  }

  // ---------------- 对门：电脑陪着过 ----------------
  // 从 tools/playthrough.mjs 的「认真的人」改来，只管一个座位；另外会看你在干什么：你在做正经事，TA 多半过来一起。
  var SLOTS = ["morning", "am", "pm", "evening", "night"];
  var actionOf = new Map(C.map.actions.map(function (a) { return [a.id, a]; }));
  var sceneOf = new Map(C.map.scenes.map(function (s) { return [s.id, s]; }));
  var zoneOf = new Map(C.map.zones.map(function (z) { return [z.id, z]; }));
  var WALK = (S.WALK_SPEED || 360) * 0.9;
  function rand() { return Math.random(); }
  function pick(list) { return list[Math.floor(rand() * list.length)]; }
  function sceneAt(y) { return C.map.scenes.find(function (s) { return s.index === Math.floor(y / C.map.stride); }); }
  function storyOf(id) { return S.storyFindEvent(C, id); }

  function route(s, role, x, y, tx, ty) {
    if (y === ty) return { x: tx, exit: null };
    var dist = new Map([[x + "," + y, 0]]);
    var first = new Map([[x + "," + y, null]]);
    var todo = [[x, y]];
    var done = new Set();
    var best = null;
    while (todo.length) {
      todo.sort(function (a, b) { return dist.get(a[0] + "," + a[1]) - dist.get(b[0] + "," + b[1]); });
      var cur = todo.shift();
      var key = cur[0] + "," + cur[1];
      if (done.has(key)) continue;
      done.add(key);
      var d0 = dist.get(key);
      if (cur[1] === ty) {
        var total = d0 + Math.abs(cur[0] - tx);
        if (!best || total < best.total) best = { total: total, exit: first.get(key) };
        continue;
      }
      for (var i = 0; i < C.map.exits.length; i++) {
        var ex = C.map.exits[i];
        if (ex.at[1] !== cur[1]) continue;
        if (S.worldSceneLock(s, C, sceneOf.get(ex.to), role)) continue;
        var nkey = ex.arrive[0] + "," + ex.arrive[1];
        var nd = d0 + Math.abs(cur[0] - ex.at[0]) + 40 + (ex.ride || 0) * 40;
        if (!dist.has(nkey) || nd < dist.get(nkey)) {
          dist.set(nkey, nd);
          first.set(nkey, first.get(key) || ex);
          todo.push([ex.arrive[0], ex.arrive[1]]);
        }
      }
    }
    if (!best) return null;
    return { x: best.exit.at[0], exit: best.exit };
  }

  function spotsFor(s, role, test) {
    var out = [];
    C.map.spots.forEach(function (sp) {
      var z = zoneOf.get(sp.zone);
      if (z.owner && z.owner !== role) return;
      if (S.worldSceneLock(s, C, sceneOf.get(sp.scene), role)) return;
      var act = S.worldPickAction(s, C, role, sp).act;
      if (!act || S.worldCanAct(s, C, role, sp.id, true)) return;
      if (test(act, sp)) out.push({ spot: sp, act: act });
    });
    return out;
  }
  function nearest(list, a) {
    var best = null, bd = Infinity;
    list.forEach(function (o) {
      var d = Math.abs(o.spot.at[0] - a.x) + (o.spot.at[1] === a.y ? 0 : 3000);
      if (d < bd) { bd = d; best = o; }
    });
    return best;
  }

  function Pal(presence) {
    this.p = presence; this.role = null; this.wait = 3 * TICK; this.plan = null; this.moveSeq = 0;
    this.tried = new Set(); this.slotKey = ""; this.evKey = ""; this.joinedYou = false; this.rollAt = -1; this.againSent = false;
  }

  /** 你（另一边）现在在做的、TA 可以过来一起做的正经事 */
  Pal.prototype.yourThing = function (s) {
    var other = this.role === "qing" ? "mei" : "qing";
    var a = s.world.actors[other];
    if (!a || !a.action || !a.spot || a.asleep) return null;
    var act = actionOf.get(a.action);
    if (!act || act.quick || act.sleep || act.duty) return null;
    var sp = C.map.spots.find(function (x) { return x.id === a.spot; });
    if (!sp) return null;
    var me = this.role;
    var same = spotsFor(s, me, function (act2, sp2) { return act2.id === act.id && (sp2.id === sp.id || !zoneOf.get(sp2.zone).owner); });
    if (!same.length) return null;
    return same.find(function (o) { return o.spot.id === sp.id; }) || nearest(same, s.world.actors[me]);
  };

  Pal.prototype.decide = function (s) {
    var role = this.role, w = s.world, p = s.persons[role], a = w.actors[role];
    // 1. 纸带上的下一件事
    var ids = [w.fate.mirror, w.fate[role]].filter(Boolean);
    for (var i = 0; i < ids.length; i++) {
      var st = storyOf(ids[i]);
      if (!st || w.done.indexOf(ids[i]) >= 0) continue;
      if (SLOTS.indexOf(st.slot) === w.slot) {
        if (sceneAt(a.y).id === st.scene) return { pass: true, why: "story-wait" };
        var sc = sceneOf.get(st.scene);
        var tgt = C.map.spots.find(function (sp) { return sp.scene === st.scene && !zoneOf.get(sp.zone).owner; }) || { at: [sc.width / 2, sc.floors[sc.floors.length - 1]] };
        return { walkTo: tgt.at, why: "story" };
      }
    }
    // 2. 日程（上学、上班）
    var d = S.worldDutyOpen(s, C, role);
    if (d && w.slot >= S.worldDutySlots(d)[0]) {
      return { spot: C.map.spots.find(function (x) { return x.id === d.spot; }), act: { id: "duty" }, why: "duty" };
    }
    // 3. 命运今天准备的事：过去看看
    var fates = [w.fate.mirror, w.fate[role]];
    for (var j = 0; j < fates.length; j++) {
      var id = fates[j];
      if (!id || w.done.indexOf(id) >= 0 || storyOf(id)) continue;
      var fe = S.lifeFindEvent(C, id);
      if (!fe || !fe.where || !fe.hint || this.tried.has(id + ":" + w.slot)) continue;
      var z = zoneOf.get(fe.where);
      if (!z || (z.owner && z.owner !== role)) continue;
      if (S.worldSceneLock(s, C, sceneOf.get(z.scene), role)) continue;
      if (fe.when && !(fe.when[0] < S.SLOTS[w.slot][1] && fe.when[1] > S.SLOTS[w.slot][0])) continue;
      this.tried.add(id + ":" + w.slot);
      var sc2 = sceneOf.get(z.scene);
      return { walkTo: [z.span[0] + (z.span[1] - z.span[0]) / 2, sc2.floors[z.floor]], why: "hint", linger: true };
    }
    // 4. 过日子
    var quick = function (id) { return nearest(spotsFor(s, role, function (act) { return act.id === id; }), a); };
    var o;
    if (p.needs.hunger < 45 && (o = quick("eat") || quick("eat_out"))) return Object.assign({}, o, { why: "eat", quick: true });
    if (p.needs.clean < 30 && (o = quick("wash"))) return Object.assign({}, o, { why: "wash", quick: true });
    if (w.slot === 4 || p.needs.energy < 15) {
      o = nearest(spotsFor(s, role, function (act) { return act.sleep; }), a);
      if (o) return Object.assign({}, o, { why: "sleep" });
    }
    // 5. 你在做正经事：多半过来一起
    var yours = this.yourThing(s);
    if (yours && rand() < 0.8) { this.joinedYou = true; return Object.assign({}, yours, { why: "together" }); }
    // 6. 自己的事：朝下一道关使劲，心情差了先玩
    var free = spotsFor(s, role, function (act) { return !act.duty && !act.sleep && !act.quick && act.money >= -Math.max(0, p.money); });
    if (!free.length) return { pass: true, why: "nothing" };
    if (p.needs.mood < 40) {
      var fun = free.filter(function (x) { return (x.act.needs.mood || 0) >= 8; });
      if (fun.length) return Object.assign({}, nearest(fun, a), { why: "fun" });
    }
    var goal = S.lifeGoal(s, C, role);
    var want = goal && goal.stat ? goal.stat : ["mind", "body", "charm"][s.turn % 3];
    var grow = free.filter(function (x) { return (x.act.stats[want] || 0) > 0; }).sort(function (x, y) { return (y.act.stats[want] || 0) - (x.act.stats[want] || 0); });
    if (grow.length && rand() < 0.7) return Object.assign({}, nearest(grow.slice(0, 3), a), { why: "grow" });
    return Object.assign({}, pick(free), { why: "variety" });
  };

  /** 每跳调一次，返回这一跳 TA 要发的消息 */
  Pal.prototype.think = function (s) {
    var out = [];
    var self = this;
    var send = function (op, body) { out.push(msg(self.p, op, body)); };
    if (!this.role) this.role = S.roleOf(room.state.record, this.p.userId);
    var role = this.role;
    if (!role || !s) return out;

    if (s.phase === "roll") {
      this.againSent = false;
      var roll = s.rolls && s.rolls[role];
      if (roll && !roll.confirmed) {
        if (this.rollAt < 0) this.rollAt = 6 * TICK + Math.floor(rand() * 4 * TICK);
        if (--this.rollAt <= 0) { send(OP.ROLL, { confirm: true }); this.rollAt = 3 * TICK; }
      }
      return out;
    }
    this.rollAt = -1;
    if (s.phase === "ended") {
      var other = role === "qing" ? "mei" : "qing";
      if (s.again && s.again[other] && !(s.again[role]) && !this.againSent) { send(OP.AGAIN, { yes: true }); this.againSent = true; }
      return out;
    }
    if (s.phase !== "life") return out;
    var w = s.world;
    var person = s.persons[role];
    if (!person || !person.alive) return out;

    // 事件：看完字再选；默契事件里，默契越高越可能和你想到一块儿去
    if (w.event) {
      var pe = w.event;
      var key = s.turn + ":" + pe.eventId;
      if (this.evKey !== key) {
        this.evKey = key;
        var ev0 = S.lifeFindEvent(C, pe.eventId) || storyOf(pe.eventId) || {};
        var len = (ev0.text || "").length;
        this.wait = Math.round((pe.kind === "milestone" ? 8 : 3 + len / 14) * TICK);
      }
      if (pe.roles.indexOf(role) < 0 || pe.choices[role]) return out;
      if (this.wait-- > 0) return out;
      var ev = S.lifeFindEvent(C, pe.eventId) || storyOf(pe.eventId);
      if (!ev || !ev.options) return out;
      var locks = (S.lifeMilestoneLocks(s, C) || {})[role] || {};
      var ok = ev.options.filter(function (o) {
        if (locks[o.id]) return false;
        var rq = o.requires || {};
        if (rq.flags && !rq.flags.every(function (f) { return person.flags.indexOf(f) >= 0; })) return false;
        if (rq.notFlags && rq.notFlags.some(function (f) { return person.flags.indexOf(f) >= 0; })) return false;
        if (o.cost && person.money < o.cost) return false;
        return true;
      });
      if (!ok.length) ok = ev.options.slice(-1);
      var otherRole = role === "qing" ? "mei" : "qing";
      var yourPick = pe.choices[otherRole];
      var sync = (s.bond && s.bond.sync) || 0;
      var follow = pe.kind === "milestone" ? 0.7 : Math.min(0.85, 0.35 + sync / 150);
      var mine = null;
      if (yourPick && rand() < follow) mine = ok.find(function (o) { return o.id === yourPick; }) || null;
      if (!mine && !yourPick && pe.roles.length > 1 && this.wait > -12 * TICK) return out; // 等你先拿主意（最多再等十几秒）
      if (!mine) {
        try { var sh = S.lifeShadowChoose(s, C, role, pe.eventId); mine = ok.find(function (o) { return o.id === sh; }) || null; } catch (e) { mine = null; }
      }
      if (!mine) mine = rand() < 0.6 ? ok[0] : pick(ok);
      send(OP.CHOOSE, { optionId: mine.id });
      this.wait = 2 * TICK;
      return out;
    }
    if (w.playing) return out;

    var slotKey = s.turn + ":" + w.slot;
    if (slotKey !== this.slotKey) {
      if (String(s.turn) !== this.slotKey.split(":")[0]) this.tried.clear();
      this.slotKey = slotKey; this.plan = null; this.joinedYou = false;
      this.wait = Math.max(this.wait, Math.round((2.5 + rand() * 3) * TICK));
    }
    var a = w.actors[role];
    if (!a || S.worldReady(s, role)) return out;
    if (this.wait > 0) { this.wait--; return out; }
    // 走在路上看见你开始做正经事了：改主意，过去一起
    if (this.plan && !this.plan.sent && !this.joinedYou && this.plan.why !== "story" && this.plan.why !== "duty" && this.plan.why !== "sleep") {
      var yours = this.yourThing(s);
      if (yours && rand() < 0.7) { this.plan = Object.assign({}, yours, { why: "together" }); }
      this.joinedYou = true;
    }
    if (!this.plan) this.plan = this.decide(s);
    var plan = this.plan;
    var target = plan.spot ? plan.spot.at : plan.walkTo;
    if (target) {
      var rt = route(s, role, a.x, a.y, target[0], target[1]);
      if (!rt) { this.plan = { pass: true, why: "no-route" }; return out; }
      if (Math.abs(a.x - rt.x) > 4) {
        var nx = a.x + Math.sign(rt.x - a.x) * Math.min(WALK / TICK, Math.abs(rt.x - a.x));
        send(OP.MOVE, { x: Math.round(nx), y: a.y, seq: ++this.moveSeq });
        return out;
      }
      if (rt.exit) { send(OP.EXIT, { exit: rt.exit.id, seq: this.moveSeq }); this.wait = 4; return out; }
      if (plan.walkTo && plan.linger) { this.plan = null; this.wait = 3 * TICK; return out; }
      if (plan.walkTo) { this.plan = { pass: true, why: plan.why + "-arrived" }; this.wait = 5; return out; }
      if (!plan.sent && S.worldCanAct(s, C, role, plan.spot.id)) { this.plan = { pass: true, why: "greyed" }; return out; }
      if (plan.sent) { this.plan = { pass: true, why: "failed" }; return out; }
      send(OP.ACT, { spot: plan.spot.id });
      if (plan.quick) { this.plan = null; this.wait = Math.round(1.5 * TICK); } else { this.plan = Object.assign({}, plan, { sent: true }); this.wait = 5; }
      return out;
    }
    if (plan.pass) { send(OP.PASS, {}); this.wait = 10; }
    return out;
  };

  // ---------------- 给 Godot 的接口 ----------------
  var RPC = {
    lifeline_create: "rpcLifelineCreate", lifeline_join: "rpcLifelineJoin", lifeline_open: "rpcLifelineOpen",
    lifeline_list: "rpcLifelineList", lifeline_past: "rpcLifelinePast", content_get: "rpcContentGet", server_info: "rpcServerInfo",
  };
  function callRpc(name, payload, user) {
    var fn = S[RPC[name]];
    if (!fn) throw new Error("没有这个接口：" + name);
    return JSON.parse(fn({ userId: user.userId }, logger, nk, JSON.stringify(payload || {})));
  }
  loadStore();
  window.TongsuiLocal = {
    version: 1,
    rpcCall: function (name, json) {
      try {
        var payload = json ? JSON.parse(json) : {};
        var r = callRpc(name, payload, ME);
        // 单机：新开一条人生线，对门的电脑马上输配对码进来
        if (name === "lifeline_create" && r && r.code) callRpc("lifeline_join", { code: r.code, name: PAL_NAME, protocol: S.PROTOCOL_VERSION }, PAL);
        return JSON.stringify(r);
      } catch (e) {
        return JSON.stringify({ __error: String((e && e.message) || e) });
      }
    },
    joinMatch: function (matchId, metaJson) {
      try { return joinRoom(matchId, metaJson ? JSON.parse(metaJson) : {}); } catch (e) { console.error(e); return false; }
    },
    sendMsg: function (op, json) {
      if (!room || !room.me) return;
      room.inbox.push(msg(room.me, Number(op), JSON.parse(json)));
    },
    leaveMatch: function () {
      if (!room || !room.me) return;
      room.state = S.matchLeave({}, logger, nk, dispatcher, room.tick, room.state, [room.me]).state;
      room.me = null;
    },
    drain: function () {
      if (!outbox.length) return "";
      var s = JSON.stringify(outbox);
      outbox = [];
      return s;
    },
    /** 调试用：清掉整份存档 */
    wipe: function () { localStorage.removeItem(STORE_KEY); location.reload(); },
    _debug: function () { return { room: room, S: S, step: step, saveNow: saveNow }; },
    /** 调试用：让电脑替你也过（试玩、截图用），speed 是快进倍数 */
    _autopilot: function (on, x) {
      if (x) speed = Math.max(1, Math.min(8, Number(x)));
      if (room) room.auto = on && room.me ? new Pal(room.me) : null;
    },
  };
})();
