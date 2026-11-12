// 门外的世界（server/src/outside.ts）：三档人家的孩子夏天见到三个不同的地方，生病去的地方不一样，清贫人家的少年家里有人住了院。
// 钉住：goto 送到、第二天回家 / tagAlong 只在对门邀请时跟去 / trip 的图走不进去 / seen 打上 / either 按各人自己的标记分档 /
// kin_care 拖日程、歇着的日子在医院 / 早市清贫六岁能进、别人十八岁 / 看病三档各看得见各的 / 影子不出门 / 存档带着今天出的门
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const turnAtAge = (age, season) => {
  for (let t = 0; t < 400; t++) { const ti = G("lifeTimeAt")(t); if (ti.age === age && (!season || ti.season === season)) return t; }
  return -1;
};
const fam = (id) => C.families.find((f) => f.id === id);
const ev = (id) => C.events.find((e) => e.id === id);
const scene = (id) => C.map.scenes.find((x) => x.id === id);
const spot = (id) => C.map.spots.find((x) => x.id === id);
const sceneOf = (s, r) => G("worldSceneAt")(C, s.world.actors[r].y)?.id;
// 殷实 xu、小康 chen、清贫 jiang
const RICH = "xu", MID = "chen", POOR = "jiang";

function bornInto(s, r, id, extra = []) {
  const p = s.persons[r];
  const old = fam(p.familyId).traits;
  p.familyId = id;
  p.flags = p.flags.filter((f) => !old.includes(f)).concat(fam(id).traits, extra);
  p.money = fam(id).money;
}
function lifeAt(seed, age, qf, mf, opt = {}) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  bornInto(s, "qing", qf, opt.qflags);
  bornInto(s, "mei", mf, opt.mflags);
  s.turn = turnAtAge(age, opt.season);
  G("worldStartDay")(s, C);
  s.world.rest = !!opt.rest;
  return s;
}
/** 让这件事现在就发生（两个人都在楼道里），各选各的 */
function happen(s, id, choices, shadow = []) {
  const e = ev(id);
  s.world.event = { eventId: id, kind: e.kind, roles: Object.keys(choices), choices: {}, shadow: [] };
  let last = null;
  for (const [r, o] of Object.entries(choices)) {
    const res = G("worldChoose")(s, C, r, o, shadow.includes(r));
    assert.equal(res.error, null, `${id}.${o}（${r}）选得了：${res.error}`);
    last = res;
  }
  assert.equal(s.world.event, null, `${id} 结算完了`);
  return last.entry;
}

// ---------- 0. 内容接上了 ----------
{
  for (const id of ["seaside", "village"]) {
    assert.ok(scene(id)?.trip && scene(id).far, `${id} 是出门才到得了的外地`);
    assert.ok(!C.map.exits.some((x) => x.to === id), `没有出口通往 ${id}`);
  }
  assert.ok(scene("market") && !scene("market").trip && !scene("market").far, "早市就在楼下，走得过去");
  assert.deepEqual(["market", "seaside", "village"].map((id) => scene(id).seen), ["saw_market", "saw_sea", "saw_village"]);
  assert.deepEqual(J(C.map.scenes.slice(-3).map((x) => x.id)), ["market", "seaside", "village"], "新图排在最后（存档里的坐标靠顺序）");
  const rd = C.tracks.filter((t) => t.restDuty);
  assert.ok(rd.length > 0 && rd.every((t) => t.restDuty.spot === "veg_stall"), "清贫人家歇着的日子都去早市看摊");
  assert.equal(scene(spot("veg_stall").scene).id, "market");
  const kc = C.rules.daily.flagDuty.kin_care;
  assert.ok(kc && kc.until === 1110 && kc.rest.spot === "ward_chair" && spot("ward_chair").actions.includes("duty"), "kin_care：放了学去医院，歇着的日子陪床（点位上有日程行动）");
  console.log("✓ 内容：海边、乡下 trip + far、没有出口进去 / 早市在楼下 / seen 三个标记 / restDuty 全在 veg_stall / flagDuty.kin_care");
}

// ---------- 1. either：两个人里有一个是那一档的就行 ----------
{
  const flags = (f) => fam(f).traits;
  const either = (id, a, b) => G("outsideEither")(ev(id), [flags(a), flags(b)]);
  assert.ok(either("out_sea_1", RICH, MID) && either("out_sea_1", MID, RICH) && !either("out_sea_1", MID, POOR), "海边：有一家殷实的");
  assert.ok(either("out_village_1", RICH, MID) && !either("out_village_1", RICH, POOR), "乡下：有一家小康的——殷实配小康也算（合起来的标记里有 fam_rich，按各人判才对）");
  assert.ok(!G("lifeHasNone")([...flags(RICH), ...flags(MID)], ev("out_village_1").requires.either.notFlags), "（合起来判会错拦）");
  assert.ok(either("out_market_1", POOR, RICH) && !either("out_market_1", RICH, MID), "早市：有一家清贫的");
  assert.ok(!G("outsideEither")(ev("out_sea_1"), [[...flags(RICH), "fam_cut"], flags(MID)]), "家里不管了的殷实人家不去海边");
  // 真抽的时候（worldStartDay）：殷实配小康的夏天，命运只会排海边、乡下，排不到早市。
  // 童年几乎天天排着一件主线 mirror，会顶掉随机抽的那件：这一段先让主线歇着，看随机池
  const storyToday = G("storyToday");
  G("storyToday = function () { return { mirror: null, qing: null, mei: null, force: [] }; }");
  const got = new Set();
  for (let seed = 1; seed <= 400; seed++) {
    const s = lifeAt(seed, 7, RICH, MID, { season: "summer" });
    if (s.world.fate.mirror) got.add(s.world.fate.mirror);
  }
  G("(function (f) { storyToday = f; })")(storyToday);
  assert.ok(got.has("out_sea_1") && got.has("out_village_1"), `殷实配小康：海边、乡下都排得上（${[...got].filter((x) => x.startsWith("out_")).join(" ")}）`);
  assert.ok(!got.has("out_market_1") && !got.has("out_market_2"), "殷实配小康排不到早市");
  console.log("✓ either：按各人自己的标记判（殷实配小康的夏天：海边、乡下都有，没有早市）/ 断了供的不去海边");
}

// ---------- 2. goto 和 tagAlong：叫上对门一块儿去 ----------
{
  const s = lifeAt(11, 7, RICH, MID, { season: "summer" });
  assert.match(G("worldSceneLock")(s, C, scene("seaside"), "qing") || "", /出门/, "平常去不了海边");
  const e = happen(s, "out_sea_1", { qing: "invite", mei: "follow" });
  assert.ok(e, "结算了");
  for (const r of ROLES) {
    assert.equal(sceneOf(s, r), "seaside", `${r} 被送到海边`);
    assert.ok(s.persons[r].flags.includes("saw_sea"), `${r} 打上 saw_sea`);
    assert.ok(s.world.off[r] && s.world.trip[r] === "seaside", `${r} 今天不上学，海边对他开着`);
    assert.equal(G("worldDuty")(s, C, r), null);
    assert.equal(G("worldSceneLock")(s, C, scene("seaside"), r), null);
  }
  assert.notEqual(s.world.actors.qing.x, s.world.actors.mei.x, "两个人挨着站，不叠在一起");
  // 在海边做事：两个人一块儿下海
  const sw = spot("sea_swim");
  s.world.slot = 1; s.world.minute = 480;
  for (const r of ROLES) { s.world.actors[r].x = sw.at[0]; s.world.actors[r].y = sw.at[1]; s.persons[r].needs.energy = 90; }
  assert.equal(G("worldAct")(s, C, "qing", sw.id).error, null);
  assert.equal(G("worldAct")(s, C, "mei", sw.id).error, null, "被带来的对门也做得了（海边的事不看家境）");
  assert.ok(s.world.actors.qing.together && s.world.actors.mei.together, "搭伴下海");
  // 夜里在招待所睡下（owner: true 的床在不分谁家的屋里也睡得了）
  G("worldCancel")(s, C, "qing"); G("worldCancel")(s, C, "mei");
  const bed = C.map.spots.find((x) => x.scene === "seaside" && x.actions.includes("sleep"));
  assert.ok(bed, "海边有床");
  assert.equal(G("worldCanAct")(s, C, "qing", bed.id, true), null, "招待所的床睡得了");
  // 第二天早上在自己家醒来
  const t0 = s.turn;
  s.turn += 1;
  G("worldStartDay")(s, C);
  for (const r of ROLES) assert.equal(sceneOf(s, r), "building", `${r} 第二天在家醒来`);
  assert.ok(!s.world.trip && !(s.world.off || {}).qing, "出的门新的一天就清掉了");
  assert.match(G("worldSceneLock")(s, C, scene("seaside"), "qing") || "", /出门/, "第二天又去不了海边了");
  assert.ok(s.persons.qing.flags.includes("saw_sea"), "来过的标记留着");
  s.turn = t0;
  console.log("✓ goto：叫上对门 → 两个人都到海边、打 saw_sea、今天不上学、搭伴下海、招待所睡得了 / 第二天在家醒来，海边又锁上");
}
{
  // 自己跟爸妈去（go）：选了 follow 的对门没被邀请，什么也不发生
  const s = lifeAt(12, 7, RICH, MID, { season: "summer" });
  const home = sceneOf(s, "mei");
  happen(s, "out_sea_1", { qing: "go", mei: "follow" });
  assert.equal(sceneOf(s, "qing"), "seaside");
  assert.equal(sceneOf(s, "mei"), home, "对门没叫，跟不去");
  assert.ok(!s.persons.mei.flags.includes("saw_sea") && !(s.world.off || {}).mei && !(s.world.trip || {}).mei);
  // 不出门的那两项：谁都不动
  const s2 = lifeAt(13, 7, RICH, MID, { season: "summer" });
  happen(s2, "out_sea_1", { qing: "stay", mei: "wait" });
  for (const r of ROLES) assert.ok(sceneOf(s2, r) !== "seaside" && !s2.persons[r].flags.includes("saw_sea"));
  // 对门叫了，我在家等着：也不去
  const s3 = lifeAt(14, 7, RICH, MID, { season: "summer" });
  happen(s3, "out_sea_1", { qing: "invite", mei: "wait" });
  assert.equal(sceneOf(s3, "qing"), "seaside");
  assert.notEqual(sceneOf(s3, "mei"), "seaside", "叫了也得自己愿意跟");
  // 选项只看选的人：小康的孩子看不见 invite，殷实的看不见 follow
  const lock = (s, r, o) => G("lifeOptionLock")(ev("out_sea_1"), ev("out_sea_1").options.find((x) => x.id === o), s.persons[r], 0);
  assert.ok(lock(s3, "mei", "invite") && !lock(s3, "mei", "follow") && lock(s3, "qing", "follow") && !lock(s3, "qing", "invite"));
  console.log("✓ tagAlong：对门选 invite 才跟去；对门自己去（go）、我在家等着（wait）都不动 / 邀请只给殷实的、跟着去只给别人家");
}

// ---------- 3. trip 的图走不进去 ----------
{
  const s = lifeAt(15, 9, RICH, MID, { season: "summer" });
  for (const id of ["sea_swim", "corn_row"]) {
    const sp = spot(id);
    assert.match(G("worldCanAct")(s, C, "qing", sp.id, true) || "", /出门/, `${id}：影子、被叫过去的都过不去`);
  }
  // 送到乡下的人：影子只在乡下找事做，不会被找到外地那一片（出租屋、外地也是 far）
  happen(s, "out_village_1", { mei: "go", qing: "wait" });
  assert.equal(sceneOf(s, "mei"), "village");
  assert.ok(s.persons.mei.flags.includes("saw_village"));
  s.world.slot = 1; s.world.minute = 480;
  for (let i = 0; i < 20; i++) {
    const found = G("worldShadowFind")(s, C, "mei", () => true);
    if (found) assert.equal(found.scene, "village", `影子在乡下只找乡下的事（找到了 ${found.id}）`);
  }
  G("worldShadowAct")(s, C, "mei");
  assert.equal(sceneOf(s, "mei"), "village", "影子替他过的这一段还在乡下");
  // 夜里：影子回不了家里的床，睡姥姥家的炕
  G("worldCancel")(s, C, "mei"); delete s.world.ready.mei;
  s.world.slot = 4; s.world.minute = 1110;
  G("worldShadowAct")(s, C, "mei");
  assert.ok(s.world.actors.mei.asleep && spot(s.world.actors.mei.spot).scene === "village", "在姥姥家睡下");
  console.log("✓ trip：海边、乡下走不进去、叫不过去 / 送去的影子只在那张图里找事、夜里睡在那儿");
}

// ---------- 4. 早市：清贫人家六岁能进，别人十八岁 ----------
{
  const lock = (s, r) => G("worldSceneLock")(s, C, scene("market"), r);
  const s = lifeAt(21, 6, POOR, MID, { season: "summer" });
  assert.equal(lock(s, "qing"), null, "清贫人家六岁就去早市");
  assert.ok(lock(s, "mei"), "小康人家六岁去不了早市");
  const adult = lifeAt(22, 18, MID, RICH);
  assert.equal(lock(adult, "qing"), null);
  assert.equal(lock(adult, "mei"), null, "十八岁以后谁都能来");
  // 清贫的叫上对门，天不亮去早市：小康的孩子今天也进得去
  happen(s, "out_market_1", { qing: "invite", mei: "follow" });
  assert.equal(sceneOf(s, "mei"), "market");
  assert.equal(lock(s, "mei"), null, "被带来的今天进得去（w.trip）");
  assert.ok(s.persons.mei.flags.includes("saw_market") && s.persons.qing.flags.includes("saw_market"));
  assert.equal(G("worldCanAct")(s, C, "mei", spot("market_walk").id, true), null, "早市上转转，对门也做得了");
  // 歇着的日子：清贫的孩子日程在早市看摊，走过去就是（楼下的胡同口）
  const r = lifeAt(23, 8, POOR, MID, { rest: true });
  const d = G("worldDuty")(r, C, "qing");
  assert.equal(d.spot, "veg_stall");
  assert.equal(lock(r, "qing"), null);
  const st = C.map.exits.find((x) => x.scene === "street" && x.to === "market");
  assert.ok(st, "楼下有去早市的胡同口");
  r.world.actors.qing.x = st.at[0]; r.world.actors.qing.y = st.at[1];
  r.persons.qing.flags = r.persons.qing.flags.filter((f) => f !== "saw_market");
  assert.equal(G("worldExit")(r, C, "qing", st.id), null);
  assert.ok(r.persons.qing.flags.includes("saw_market"), "自己走进早市也算来过");
  console.log("✓ 早市：清贫六岁能进、别人十八岁 / 叫上对门的那天对门也进得去 / 歇着的日子在早市看摊 / 走进去也打 saw_market");
}

// ---------- 5. 看病：三档人家各看得见各的 ----------
{
  const sick = ev("out_sick");
  const open = (s, r) => J(sick.options.filter((o) => !G("lifeOptionLock")(sick, o, s.persons[r], 0)).map((o) => o.id));
  const a = lifeAt(31, 8, RICH, MID, { season: "winter" });
  const b = lifeAt(32, 8, POOR, MID, { season: "winter" });
  assert.deepEqual(open(a, "qing"), ["expert", "ginger", "push"], "殷实：托人挂专家号");
  assert.deepEqual(open(a, "mei"), ["queue", "ginger", "push"], "小康：一早去排队");
  assert.deepEqual(open(b, "qing"), ["clinic", "ginger", "push"], "清贫：卫生所打一针");
  b.persons.mei.money = 1;
  assert.ok(!open(b, "mei").includes("queue"), "兜里没两块钱的排不了号");
  assert.ok(G("lifeGated")(sick), "看病是挂了门槛的事件，影子不选锁着的");
  // 托人挂了专家号：八岁的孩子被送到医院（平常四十五岁才来），看完坐车回家
  const hosp = scene("hospital");
  assert.ok(G("worldSceneLock")(a, C, hosp, "qing"), "平常孩子去不了医院");
  a.world.event = { eventId: "out_sick", kind: "solo", roles: ["qing"], choices: {}, shadow: [] };
  assert.equal(G("worldChoose")(a, C, "qing", "expert", false).error, null);
  assert.equal(sceneOf(a, "qing"), "hospital");
  assert.equal(G("worldSceneLock")(a, C, hosp, "qing"), null, "今天被送来的医院对他开着");
  assert.ok(a.world.off.qing, "今天不上学");
  const home = C.map.exits.find((x) => x.scene === "hospital" && x.to === "street");
  assert.ok(home && home.ride > 0, "医院门口坐车回家");
  console.log("✓ 看病：殷实专家号 / 小康排队（要两块）/ 清贫卫生所，姜汤和硬撑谁都有 / 专家号送到医院、今天不上学、坐车回家");
}

// ---------- 6. 家里有人住院：kin_care ----------
{
  const s = lifeAt(41, 14, POOR, MID);
  const base = G("worldDuty")(s, C, "qing");
  const untilBefore = base.until;
  s.persons.qing.flags.push("kin_care");
  const d = G("worldDuty")(s, C, "qing");
  assert.equal(d.until, Math.max(1110, untilBefore), "上学的日子拖到傍晚");
  assert.equal(d.spot, base.spot, "还是去上学");
  assert.equal(d.label, "上学，放了学去医院送饭", "本来就上到傍晚的也换 label");
  const tr = G("lifeTrack")(C, s.persons.qing, 14);
  assert.equal(tr.duty.until, untilBefore, "不改内容对象（返回副本）");
  s.world.rest = true;
  const r = G("worldDuty")(s, C, "qing");
  assert.equal(r.spot, "ward_chair", "歇着的日子在医院陪床（盖过早市的 restDuty）");
  assert.deepEqual(J(G("worldDutySlots")(r)), [1, 3], "上午到傍晚");
  assert.equal(G("worldSceneLock")(s, C, scene("hospital"), "qing"), null, "日程在医院，医院就开着");
  // 真去陪床：日程在病房那把椅子上
  const wc = spot("ward_chair");
  s.world.slot = 1; s.world.minute = 480;
  s.world.actors.qing.x = wc.at[0]; s.world.actors.qing.y = wc.at[1];
  assert.equal(G("worldPickAction")(s, C, "qing", wc).act?.id, "duty");
  assert.equal(G("worldAct")(s, C, "qing", wc.id).error, null);
  const charm = s.persons.qing.stats.charm;
  s.world.actors.qing.until = 1110;
  G("worldFinish")(s, C, "qing");
  assert.ok(s.persons.qing.stats.charm > charm, "陪床长一点魅力");
  // 没带标记的对门照旧；过了十七岁不再管
  assert.equal(G("worldDuty")(s, C, "mei"), null, "小康人家歇着的日子没有日程");
  const old = lifeAt(42, 18, POOR, MID, { qflags: ["kin_care"], rest: true });
  assert.notEqual((G("worldDuty")(old, C, "qing") || {}).spot, "ward_chair", "十八岁以后 flagDuty 不管了");
  console.log("✓ kin_care：上学拖到傍晚、换 label、不改内容 / 歇着的日子去医院陪床（上午到傍晚，长魅力）/ 十八岁以后不管");
}

// ---------- 7. 影子不出门 ----------
{
  const s = lifeAt(51, 7, RICH, MID, { season: "summer" });
  s.world.event = { eventId: "out_sea_1", kind: "mirror", roles: ["qing", "mei"], choices: {}, shadow: [] };
  const picks = { qing: new Set(), mei: new Set() };
  for (let i = 0; i < 200; i++) for (const r of ROLES) picks[r].add(G("lifeShadowChoose")(s, C, r, "out_sea_1"));
  for (const r of ROLES) assert.ok([...picks[r]].every((o) => o === "stay" || o === "wait"), `${r} 的影子只选在家的（选了 ${[...picks[r]].join(" ")}）`);
  const sick = lifeAt(52, 8, RICH, MID, { season: "winter" });
  sick.world.event = { eventId: "out_sick", kind: "solo", roles: ["qing"], choices: {}, shadow: [] };
  for (let i = 0; i < 100; i++) assert.ok(["ginger", "push"].includes(G("lifeShadowChoose")(sick, C, "qing", "out_sick")), "殷实的影子也不替人去医院（专家号是 goto）");
  sick.world.event.roles = ["mei"];
  for (let i = 0; i < 100; i++) assert.ok(["ginger", "push"].includes(G("lifeShadowChoose")(sick, C, "mei", "out_sick")));
  console.log("✓ 影子不出门：夏天只选不去 / 在家等着，看病只选姜汤、硬撑（带 goto 的项有别的可选就不选）");
}

// ---------- 8. 到了那张图上，命运换上那儿的事 ----------
{
  const there = C.events.filter((e) => e.kind === "solo" && e.where && C.map.zones.find((z) => z.id === e.where).scene === "seaside");
  assert.ok(there.length > 0, "海边有地点小事");
  let swapped = 0, tries = 0;
  for (let seed = 100; seed < 260; seed++) {
    const s = lifeAt(seed, 7, RICH, MID, { season: "summer" });
    s.world.fate.qing = null;
    happen(s, "out_sea_1", { qing: "go", mei: "stay" });
    tries++;
    const f = s.world.fate.qing;
    if (f) {
      const e = ev(f);
      assert.ok(e && e.where && C.map.zones.find((z) => z.id === e.where).scene === "seaside", `换上的是海边的事（${f}）`);
      swapped++;
    }
    assert.ok(!s.world.fate.mei || !there.some((e) => e.id === s.world.fate.mei), "没去的人不换");
  }
  assert.ok(swapped > tries * 0.4 && swapped < tries * 0.95, `大约七成的日子换上一件（${swapped}/${tries}）`);
  // 换上的事真碰得上：人在那个地方、空着，就发生
  let fired = false;
  for (let seed = 300; seed < 340 && !fired; seed++) {
    const s = lifeAt(seed, 7, RICH, MID, { season: "summer" });
    s.world.fate.qing = null;
    happen(s, "out_sea_1", { qing: "go", mei: "stay" });
    const f = s.world.fate.qing;
    if (!f) continue;
    const z = C.map.zones.find((x) => x.id === ev(f).where);
    s.world.actors.qing.x = (z.span[0] + z.span[1]) / 2;
    const e = ev(f);
    if (e.when) { s.world.slot = G("worldSlotAt")(e.when[0]); s.world.minute = Math.max(e.when[0], 390); }
    const out = { entries: [], started: null, dayEnded: false };
    G("worldFate")(s, C, { qing: true, mei: true }, out, false);
    if (out.started && out.started.eventId === f) fired = true;
  }
  assert.ok(fired, "海边的小事走到那儿就发生");
  console.log(`✓ 到了海边，命运换上海边的事（${swapped}/${tries} 天）/ 走到那儿就发生`);
}

// ---------- 8b. 两个人一块儿到了海边：两个人的事也排一件那儿的 ----------
{
  const seaPair = C.events.filter((e) => e.kind === "mirror" && e.where && C.map.zones.find((z) => z.id === e.where).scene === "seaside");
  assert.ok(seaPair.length > 0, "海边有两个人的小事（招待所的夜里）");
  let paired = 0, alone = 0, n = 0;
  for (let seed = 400; seed < 560; seed++) {
    const s = lifeAt(seed, 7, RICH, MID, { season: "summer" });
    s.world.fate.mirror = "out_sea_1"; // 夏天那件就是今天命运排的 mirror（主线不排的日子）
    happen(s, "out_sea_1", { qing: "invite", mei: "follow" });
    n++;
    const m = s.world.fate.mirror;
    if (m !== "out_sea_1") {
      assert.ok(seaPair.some((e) => e.id === m), `换上的是海边的 mirror（${m}）`);
      paired++;
    }
    const t = lifeAt(seed, 7, RICH, MID, { season: "summer" });
    t.world.fate.mirror = "out_sea_1";
    happen(t, "out_sea_1", { qing: "go", mei: "stay" });
    if (t.world.fate.mirror !== "out_sea_1") alone++;
  }
  assert.ok(paired > n * 0.3 && paired < n * 0.95, `一块儿去的日子大约六成排上一件（${paired}/${n}）`);
  assert.equal(alone, 0, "只有一个人去的不排两个人的事");
  console.log(`✓ 一块儿到了海边：两个人的事也排一件海边的（${paired}/${n} 天）/ 一个人去的不排`);
}

// ---------- 9. 存档、重连：今天出的门跟着 s.world 走 ----------
{
  const s = lifeAt(61, 7, RICH, MID, { season: "summer" });
  happen(s, "out_sea_1", { qing: "invite", mei: "follow" });
  const back = J(s);
  const notes = G("lifeRepair")(back, C);
  assert.ok(!notes.some((n) => n.includes("actor")), `海边的人站得住，不被挪回家（${notes.join(" / ")}）`);
  assert.equal(sceneOf(back, "qing"), "seaside");
  assert.equal(back.world.trip.qing, "seaside");
  assert.equal(G("worldSceneLock")(back, C, scene("seaside"), "mei"), null, "读回来海边还开着");
  // 旧存档没有 trip：照常
  delete back.world.trip;
  assert.match(G("worldSceneLock")(back, C, scene("seaside"), "mei") || "", /出门/);
  console.log("✓ 存档：今天出的门（w.trip、w.off、海边的坐标）存得下、读得回；旧存档没有 trip 照常");
}
