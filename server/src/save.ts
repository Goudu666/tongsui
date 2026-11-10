// 存档的两种「过期」，都在房间拉起时（matchInit）处理一次：
//
// 1. 结构过期：LifeState 的字段变了。lifeUpgrade 按版本号一级一级升上来。
//    改 LifeState 时：LIFE_VERSION + 1，在 lifeUpgrade 里加一段「从上一版升到这一版」。
// 2. 内容过期：存档是在旧剧情下存的，里面记着的事件、行动、点位在新内容里可能已经改名或删掉了。
//    lifeRepair 把这些悬空的引用摘掉（今天的命运作废、卡着的事件取消、做到一半的行动停下），人生接着过。
//    不处理的话，规则代码一查这个 id 就抛错，房间每次拉起都崩，这条人生线就再也打不开了。
//
// 纯函数，不依赖 Nakama。

var LIFE_VERSION = 3;

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
      var next = lifeRollOnce(s, c, s.rolls[lifeOther(r)].familyId);
      notes.push("roll." + r + " " + roll.familyId + "/" + roll.talentId + " 已不存在，重抽");
      roll.familyId = next.familyId;
      roll.talentId = next.talentId;
      roll.stats = next.stats;
      roll.confirmed = false;
    }
  }

  var w = s.world;
  if (s.phase === "life" && w) {
    var slots: ("mirror" | "qing" | "mei")[] = ["mirror", "qing", "mei"];
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
        a.action = null;
        a.spot = null;
        a.until = null;
        a.asleep = false;
        a.shadow = false;
      }
      if (a.spot && !lifeHasId(c.map.spots, a.spot)) a.spot = null;
      // 地图变小了：人不能留在地图外面
      a.x = lifeClamp(a.x, 0, c.map.size[0]);
      a.y = lifeClamp(a.y, 0, c.map.size[1]);
    }
  }

  if (s.contentVersion !== c.version) {
    if (notes.length === 0 && s.contentVersion) notes.push("内容 " + s.contentVersion + " → " + c.version + "，存档不用改");
    s.contentVersion = c.version;
  }
  return notes;
}
