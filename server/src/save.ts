// 存档的两种「过期」，都在房间拉起时（matchInit）处理一次：
//
// 1. 结构过期：LifeState 的字段变了。lifeUpgrade 按版本号一级一级升上来。
//    改 LifeState 时：LIFE_VERSION + 1，在 lifeUpgrade 里加一段「从上一版升到这一版」。
// 2. 内容过期：存档是在旧剧情下存的，里面记着的事件、行动、点位在新内容里可能已经改名或删掉了。
//    lifeRepair 把这些悬空的引用摘掉（今天的命运作废、卡着的事件取消、做到一半的行动停下），人生接着过。
//    不处理的话，规则代码一查这个 id 就抛错，房间每次拉起都崩，这条人生线就再也打不开了。
//
// 纯函数，不依赖 Nakama。

var LIFE_VERSION = 8;

/** 结构升级。返回做了什么（写服务器日志用）；存档比服务器还新时抛错（服务器被回滚了，不能硬读） */
function lifeUpgrade(s: any): string[] {
  var notes: string[] = [];
  var v = Number(s.version) || 0;
  if (v > LIFE_VERSION) throw new Error("存档版本 " + v + " 比服务器支持的 " + LIFE_VERSION + " 新，请更新服务器");
  if (v < 2) throw new Error("存档版本 " + v + " 太旧，无法升级");
  if (v === 2) {
    // v3：记下存档是在哪一版内容下存的
    s.contentVersion = s.contentVersion || "";
    v = 3;
    notes.push("v2→v3");
  }
  if (v === 3) {
    // v4：成长规则（growth.ts）要的字段。出生时的属性没记过，就拿现在的当底子：
    // 老存档里的人往后长得和新规则下的新生儿一样慢，不会凭空多出或少掉属性
    for (var i = 0; i < ROLES.length; i++) {
      var p = s.persons ? s.persons[ROLES[i]] : null;
      if (!p) continue;
      if (!p.born) p.born = { body: p.stats.body, mind: p.stats.mind, charm: p.stats.charm, luck: p.stats.luck };
      if (p.moodSum === undefined) { p.moodSum = 0; p.moodDays = 0; }
      if (!p.active) p.active = { body: false, mind: false };
      // 「普通的孩子」以前没有标记（标记是出生时拷进 flags 的），补上才长得匀、才遇得到它的专属事件
      if (p.talentId === "none" && p.flags && p.flags.indexOf("tal_plain") < 0) p.flags.push("tal_plain");
    }
    if (s.world && s.world.warm === undefined) s.world.warm = false;
    v = 4;
    notes.push("v3→v4");
  }
  if (v === 4) {
    // v5：日程按人生路线走。schoolDay 换成 rest（今天歇着），多了 dutyDone 和关口
    if (s.world) {
      s.world.rest = !s.world.schoolDay;
      delete s.world.schoolDay;
      s.world.dutyDone = {};
      if (s.world.fate) s.world.fate.milestone = null;
    }
    v = 5;
    notes.push("v4→v5");
  }
  if (v === 5) {
    // v6：传承（legacy.ts）。老存档当作头一世：没有攒下的东西，抽卡和人身上补上空的老物件栏
    legacyUpgrade(s);
    v = 6;
    notes.push("v5→v6");
  }
  if (v === 6) {
    // v7：传承里多了痕迹、出过的事、街坊记住的事、干过的营生。旧存档从空的开始
    legacyUpgrade2(s);
    v = 7;
    notes.push("v6→v7");
  }
  if (v === 7) {
    // v8：一天切成五段（world.ts 的 SLOTS）。存在半路的那一天从当时所在的那一段接着定；
    // 正在做的事照旧做到原来的钟点（没有 scale 就是做一遍）。放风筝小游戏拿掉了，问到一半的作废
    var w = s.world;
    if (w) {
      w.slot = worldSlotAt(Number(w.minute) || DAY_START);
      w.minute = Math.max(Number(w.minute) || DAY_START, SLOTS[w.slot][0]);
      w.ready = {};
      w.playing = false;
      w.wait = 0;
      w.quick = [];
      delete w.game;
      for (var ai = 0; ai < ROLES.length; ai++) {
        var actor = w.actors ? w.actors[ROLES[ai]] : null;
        if (!actor) continue;
        delete actor.boost;
        // 正在做的事（上学上班、睡觉）是在前面哪一段就开始了的：撤不回，不然这一天的日程就没了
        if (actor.action || actor.asleep) actor.from = -1;
      }
    }
    v = 8;
    notes.push("v7→v8");
  }
  s.version = v;
  return notes;
}

function lifeHasId(list: { id: string }[], id: string | null | undefined): boolean {
  if (!id) return false;
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return true;
  return false;
}

/** 内容修复。返回摘掉了什么；什么都没动返回空数组 */
function lifeRepair(s: LifeState, c: Content): string[] {
  var notes: string[] = [];

  if (s.phase === "roll") {
    // 抽到的人家或天赋没了：替他重抽一次，不扣次数
    for (var i = 0; i < ROLES.length; i++) {
      var r = ROLES[i];
      var roll = s.rolls[r];
      if (lifeHasId(c.families, roll.familyId) && lifeHasId(c.talents, roll.talentId)) continue;
      var next = lifeRollOnce(s, c, s.rolls[lifeOther(r)].familyId, s.legacy);
      notes.push("roll." + r + " " + roll.familyId + "/" + roll.talentId + " 已不存在，重抽");
      roll.familyId = next.familyId;
      roll.talentId = next.talentId;
      roll.stats = next.stats;
      roll.house = legacyHouse(c, s.legacy, next.familyId);
      roll.confirmed = false;
    }
  }

  var w = s.world;
  if (s.phase === "life" && w) {
    var slots: ("mirror" | "qing" | "mei" | "milestone")[] = ["mirror", "qing", "mei", "milestone"];
    for (var f = 0; f < slots.length; f++) {
      var fid = w.fate[slots[f]];
      if (fid && !lifeHasId(c.events, fid)) {
        notes.push("fate." + slots[f] + " " + fid + " 已不存在，作废");
        w.fate[slots[f]] = null;
      }
    }
    if (w.event) {
      if (!lifeHasId(c.events, w.event.eventId)) {
        notes.push("event " + w.event.eventId + " 已不存在，取消");
        w.event = null;
      } else {
        // 事件还在，但已经选的选项被改掉了：让他重新选
        var ev = lifeFindEvent(c, w.event.eventId);
        for (var k = 0; k < ROLES.length; k++) {
          var picked = w.event.choices[ROLES[k]];
          if (picked && !lifeFindOption(ev, picked)) {
            notes.push("event " + ev.id + " 的选项 " + picked + " 已不存在，重选");
            delete w.event.choices[ROLES[k]];
            var si = w.event.shadow.indexOf(ROLES[k]);
            if (si >= 0) w.event.shadow.splice(si, 1);
          }
        }
      }
    }
    for (var j = 0; j < ROLES.length; j++) {
      var a = w.actors[ROLES[j]];
      if (!a) continue;
      if (a.action && !lifeHasId(c.map.actions, a.action)) {
        notes.push("actor." + ROLES[j] + " 的行动 " + a.action + " 已不存在，停下");
        worldClearAction(a);
        a.shadow = false;
      }
      if (a.spot && !lifeHasId(c.map.spots, a.spot)) a.spot = null;
      // 地图改了（变小了、某张图拿掉了、换成一张张横图以前的老坐标）：人得站在某张图的某层地面上。
      // 站不住的：手上有事就站回那个点位，没事就回自己家床边
      var sc = worldSceneAt(c, a.y);
      if (!sc || sc.floors.indexOf(a.y) < 0 || a.x < 0 || a.x > sc.width) {
        var home = a.spot ? lifeFind(c.map.spots, a.spot) : null;
        var at = home ? home.at : c.map.spawn[ROLES[j]];
        notes.push("actor." + ROLES[j] + " 站在地图外面（" + Math.round(a.x) + ", " + Math.round(a.y) + "），挪到 " + (home ? home.id : "家里"));
        a.x = at[0];
        a.y = at[1];
      }
    }
  }

  duetRepair(s, c, notes); // 欠着没回的话（duet.ts）也记着事件和选项的 id
  legacyRepair(s, c, notes); // 攒下的老物件（legacy.ts）记着内容里的 id

  if (s.contentVersion !== c.version) {
    if (notes.length === 0 && s.contentVersion) notes.push("内容 " + s.contentVersion + " → " + c.version + "，存档不用改");
    s.contentVersion = c.version;
  }
  return notes;
}
