// 三扇门（一）：时间和安全网（docs/MEANS.md 第八节）。考场公平，考场外不公平，三档人家是三种难度。
// 钉住：清贫人家放了学帮家里（日程拖到傍晚、歇着的日子看一上午摊），助学金把那一段还回来；殷实人家放了学是爸妈报的班；
// 关口上的助学金、中专、择校费谁出、爸妈攒的那笔钱、复读、助学贷款、爸妈心里那条线（记一回脸色）；退班；断了供以后锁上的路。
import assert from "node:assert/strict";
import { G, C, J, NAMES } from "./harness.mjs";

const ON = { qing: true, mei: true };
const ROLES = ["qing", "mei"];
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const fam = (id) => C.families.find((f) => f.id === id);
const ev = (id) => C.events.find((e) => e.id === id);
const track = (id) => C.tracks.find((t) => t.id === id);
const action = (id) => C.map.actions.find((a) => a.id === id);

/** 把一个人换成某户人家的孩子（标记、家底跟着换），再加几个标记 */
function bornInto(s, r, id, extra = []) {
  const p = s.persons[r];
  const old = fam(p.familyId).traits;
  p.familyId = id;
  p.flags = p.flags.filter((f) => !old.includes(f)).concat(fam(id).traits, extra);
  p.money = fam(id).money;
}
/** 青是 qf 家、梅是 mf 家，走到 age 岁那天早上；mind 给了就把两个人的心智设成这个数 */
function lifeAt(seed, age, qf, mf, opt = {}) {
  const s = G("lifeCreate")(seed, C);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  bornInto(s, "qing", qf, opt.qflags);
  bornInto(s, "mei", mf, opt.mflags);
  for (const r of ROLES) {
    s.persons[r].stats.luck = 5;
    if (opt.mind !== undefined) s.persons[r].stats.mind = opt.mind;
    if (opt.body !== undefined) s.persons[r].stats.body = opt.body;
  }
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  return s;
}
/** 走到今天的关口开考（发挥都按 0 算） */
function exam(s) {
  for (let i = 0; i < 600 && !s.world.event; i++) G("worldAdvance")(s, C, 0.1, ON);
  const pe = s.world.event;
  assert.ok(pe && ev(pe.eventId).kind === "milestone", "没走到关口");
  for (const r of pe.roles) { pe.swing[r] = 0; delete pe.choices[r]; if (pe.steady) delete pe.steady[r]; }
  return pe;
}
const locks = (s) => J(G("lifeMilestoneLocks")(s, C) || {});
/** 两个人各选一条，返回长卷那一条 */
function choose(s, picks) {
  for (const r of ROLES) if (picks[r] && s.world.event && s.world.event.roles.includes(r)) assert.equal(G("worldChoose")(s, C, r, picks[r], false).error, null, `${r} 选不了 ${picks[r]}`);
  return s.log.at(-1);
}
/** 客户端摆不摆这条路（client/scripts/main.gd：写了 hide、锁着的理由正好是 lock 那句才不摆） */
const shown = (s, r, ms, id) => { const o = ms.options.find((x) => x.id === id); const why = locks(s)[r]?.[id]; return !(o.hide && why === (o.lock || "这条路不是给你留的")); };

// ---------- 1. 日程：清贫人家借来的时间，殷实人家爸妈报的班 ----------
{
  const t = (flags, age) => G("lifeTrack")(C, { flags }, age);
  // 清贫：六到十七岁放了学帮家里，拖到傍晚；拿了助学金的还给自己
  assert.equal(t(["fam_poor", "in_school"], 8).id, "primary_help");
  assert.equal(t(["fam_poor", "lead_study"], 8).id, "primary_help_study");
  assert.equal(t(["fam_poor", "aid"], 8).id, "primary");
  assert.equal(t(["fam_poor"], 13).id, "junior_help");
  assert.equal(t(["fam_poor", "junior_key"], 13).id, "junior_key_help", "重点班的上学日子不另占，歇着的日子照样看摊");
  assert.equal(t(["fam_poor", "junior_key", "aid"], 13).id, "junior_key");
  assert.equal(t(["fam_poor", "vocational"], 16).id, "vocational_help");
  assert.equal(t(["fam_nest"], 8).id, "primary", "小康的傍晚是自己的");
  // 殷实：六到十四岁放了学是爸妈报的班，长的是爸妈想要的那一项；摊了牌、断了供的没有
  assert.equal(t(["fam_rich", "exp_book"], 8).id, "primary_class_book");
  assert.equal(t(["fam_rich", "exp_art"], 13).id, "junior_class_art");
  assert.equal(t(["fam_rich", "exp_book", "class_quit"], 8).id, "primary");
  assert.equal(t(["fam_rich", "exp_book", "fam_cut"], 8).id, "primary");
  assert.equal(t(["fam_rich", "exp_pull", "junior_key"], 13).id, "junior_key", "重点班本来就上到五点，不另报班");
  assert.equal(t(["fam_rich", "exp_pull"], 15).id, "vocational", "十五岁以后没有爸妈报的班");
  const slots = (id) => J(G("worldDutySlots")(track(id).duty));
  // 一天少一段：小学本来下午放学，帮家里的、上班的都拖到傍晚
  assert.deepEqual(slots("primary"), [1, 2]);
  for (const id of ["primary_help", "primary_help_study", "junior_help", "vocational_help", "zhongzhuan_help", "primary_class_book", "primary_class_pull", "junior_class_abroad", "junior_class_art"]) assert.deepEqual(slots(id), [1, 3], `${id} 要占到傍晚`);
  // 和同班同学还是同路：group 写原来那条的
  const road = (tr) => tr.group || tr.id;
  for (const [v, base] of [["primary_help", "primary"], ["primary_class_book", "primary"], ["junior_help", "junior"], ["junior_class_pull", "junior"], ["junior_key_help", "junior_key"], ["senior_key_help", "senior_key"], ["senior_help", "senior"], ["vocational_help", "vocational"]]) {
    assert.equal(road(track(v)), road(track(base)), `${v} 和 ${base} 要算同路`);
    assert.ok(C.tracks.indexOf(track(v)) < C.tracks.indexOf(track(base)), `${v} 要排在 ${base} 前头`);
  }
  // 爸妈报的班：长的是爸妈想要的那一项，比自己写作业那一段（0.4 × 两遍）搭伴 1.5 倍以后快三成上下
  const extra = (id, k) => (track(id).duty.stats[k] || 0) - (track("primary").duty.stats[k] || 0);
  const self = action("study").stats.mind * 2;
  assert.ok(extra("primary_class_book", "mind") * 1.5 >= self * 1.15 && extra("primary_class_book", "mind") * 1.5 <= self * 1.5, "奥数班比自己写作业快三成上下");
  assert.ok(extra("primary_class_pull", "charm") > extra("primary_class_pull", "mind"));
  assert.ok(extra("primary_class_art", "charm") > extra("primary_class_art", "mind"));
  assert.ok(Math.abs(extra("primary_class_abroad", "charm") - extra("primary_class_abroad", "mind")) < 0.05, "外语班心智魅力各半");
  for (const id of ["primary_class_book", "primary_class_pull", "primary_class_abroad", "primary_class_art"]) assert.ok(!track(id).duty.money, `${id} 不花钱`);
  // 帮家里：小学不挣钱（交给家里），初中以后一天一块，长一点体魄魅力
  assert.ok(!track("primary_help").duty.money && track("junior_help").duty.money === 1);
  assert.ok(track("primary_help").duty.stats.body > 0 && track("primary_help").duty.stats.charm > track("primary").duty.stats.charm);

  // 歇着的日子：清贫人家的孩子看一上午摊（restDuty），别人整天是自己的
  const s = lifeAt(3, 8, "jiang", "chen");
  s.world.rest = true;
  const dq = G("worldDuty")(s, C, "qing"), dm = G("worldDuty")(s, C, "mei");
  assert.equal(dm, null, "小康人家歇着的日子没有日程");
  assert.ok(dq && dq.spot === "veg_stall");
  assert.deepEqual(J(G("worldDutySlots")(dq)), [1, 1], "看一上午摊，就占上午那一段");
  assert.ok(C.tracks.filter((x) => x.restDuty).every((x) => (x.requires.flags || []).includes("fam_poor")), "只有清贫人家的路写 restDuty");
  // 真去看摊：上午那一段做完，长的是看摊的数
  const before = s.persons.qing.stats.charm;
  const sp = C.map.spots.find((x) => x.id === "veg_stall");
  s.world.slot = 1; s.world.minute = 480;
  s.world.actors.qing.x = sp.at[0]; s.world.actors.qing.y = sp.at[1];
  assert.equal(G("worldPickAction")(s, C, "qing", sp).act?.id, "duty");
  assert.equal(G("worldAct")(s, C, "qing", sp.id).error, null);
  G("worldFinish")(s, C, "qing");
  assert.ok(s.persons.qing.stats.charm > before, "看摊长魅力");
  console.log("✓ 日程：清贫放了学帮家里拖到傍晚、歇着的日子看一上午摊、助学金还回来 / 殷实六到十四岁爸妈报的班（长爸妈想要的那项，快三成上下，不花钱）/ 摊了牌、断了供、重点班的没有 / 和同班同学还是同路");
}

// ---------- 2. 小升初：助学金、谁出重点班的钱、爸妈心里那条线 ----------
{
  const ms = ev("m_junior");
  // 清贫：考进年级前三拿助学金，放学那一段还回来；小康看不见这一条
  const s = lifeAt(11, 12, "jiang", "chen", { mind: 9.9 });
  exam(s);
  const l = locks(s);
  assert.equal(l.qing.key_aid, undefined, "清贫的考进前三走得了助学金那条");
  assert.ok(!shown(s, "mei", ms, "key_aid"), "小康看不见助学金");
  assert.equal(l.qing.paid, "家里拿不出这笔钱");
  assert.ok(shown(s, "qing", ms, "paid"), "清贫的看得见交钱那条，灰着");
  const m0 = s.persons.qing.money;
  const e = choose(s, { qing: "key_aid", mei: "key" });
  assert.equal(e.resonance, true, "拿助学金进的和考进的同路");
  assert.ok(s.persons.qing.flags.includes("aid") && s.persons.qing.flags.includes("junior_key") && s.persons.qing.flags.includes("junior_top"));
  assert.equal(s.persons.qing.money, m0 + ms.options.find((o) => o.id === "key_aid").effects.money, "助学金进积蓄");
  assert.equal(G("lifeTrack")(C, s.persons.qing, 13).id, "junior_key", "拿了助学金，歇着的日子也不用看摊了");
  // 分数不够前三：灰着写差多少
  const s2 = lifeAt(12, 12, "jiang", "chen", { mind: 8 });
  exam(s2);
  assert.match(locks(s2).qing.key_aid, /心智/);

  // 殷实：念书考出去的人家（郑家）重点班家里出钱；别的人家自己出；没进重点班记一回脸色
  const r = lifeAt(13, 12, "zheng", "dong", { mind: 7.15 });
  exam(r);
  r.persons.qing.money = 0; r.persons.mei.money = 50;
  assert.equal(locks(r).qing.paid, undefined, "郑家的重点班家里出钱，兜里没钱也走得了");
  choose(r, { qing: "paid", mei: "paid" });
  assert.equal(r.persons.qing.money, 0, "家里出的钱不从自己的积蓄扣");
  assert.equal(r.persons.mei.money, 50 - ms.options.find((o) => o.id === "paid").cost, "董家交的是自己攒的");
  assert.ok(!r.persons.qing.flags.includes("strain1") && !r.persons.mei.flags.includes("strain1"), "进了重点班（交钱的也算）不记脸色");
  const f = lifeAt(14, 12, "zheng", "dong", { mind: 7.15 });
  exam(f);
  choose(f, { qing: "normal", mei: "normal" });
  assert.ok(f.persons.qing.flags.includes("strain1"), "郑家的孩子没进重点班：记一回脸色");
  assert.ok(!f.persons.mei.flags.includes("strain1"), "董家十二岁不看这个");
  // 断了供的：殷实那条路锁上，写着家里不管了，不藏
  const c = lifeAt(15, 12, "zheng", "chen", { mind: 9, qflags: ["fam_cut"] });
  exam(c);
  assert.equal(locks(c).qing.paid, "家里已经不管你了");
  assert.ok(shown(c, "qing", ms, "paid"));
  console.log("✓ 小升初：清贫考进前三拿助学金（同路、进积蓄、往后不用看摊）/ 小康看不见 / 郑家重点班家里出、董家自己出 / 念书人家没进重点班记一回脸色 / 断了供的锁上写为什么");
}

// ---------- 3. 中考：中专、爸妈攒的钱、择校费谁出、脸色记到第二回就是断供 ----------
{
  const ms = ev("m_senior");
  const s = lifeAt(21, 15, "jiang", "chen", { mind: 8.4 });
  exam(s);
  const l = locks(s);
  assert.match(l.qing.far, /心智/, "8.4 够不着市重点");
  assert.equal(l.qing.zhongzhuan, undefined, "清贫的够得着中专");
  assert.equal(l.mei.nest, undefined, "小康动得了爸妈攒的那笔钱");
  assert.ok(!shown(s, "mei", ms, "zhongzhuan") && !shown(s, "qing", ms, "nest") && !shown(s, "mei", ms, "far_aid"), "别人家的路看不见");
  assert.equal(l.qing.paid, "家里拿不出择校费");
  assert.ok(ms.options.find((o) => o.id === "zhongzhuan").min < ms.options.find((o) => o.id === "far").min, "中专的线比市重点低一点");
  const e = choose(s, { qing: "zhongzhuan", mei: "nest" });
  const q = s.persons.qing, m = s.persons.mei;
  assert.ok(q.flags.includes("zhongzhuan") && q.flags.includes("job_succeed"), "中专包分配");
  assert.ok(m.flags.includes("school_far") && !m.flags.includes("fam_nest"), "动了那笔钱就没了");
  assert.equal(e.resonance, false);
  assert.equal(G("lifeTrack")(C, q, 16).id, "zhongzhuan_help");
  assert.equal(G("lifeTrack")(C, q, 19).id, "zz_assigned", "中专毕业分配进厂");
  assert.equal(G("lifeTrack")(C, q, 25).id, "job_succeed", "二十二岁起是厂里那条路");
  assert.ok(!G("lifeMilestoneFor")(ev("m_gaokao"), q), "中专不考大学");
  assert.equal(G("lifeTrack")(C, m, 16).id, "senior_key");

  // 殷实：念书、出国的人家择校费家里出；董家（进单位）念家门口的高中也认，郑家不认
  const r = lifeAt(22, 15, "zheng", "dong", { mind: 8.0, qflags: ["strain1"] });
  exam(r);
  r.persons.qing.money = 0;
  assert.equal(locks(r).qing.paid, undefined, "郑家的择校费家里出");
  choose(r, { qing: "near", mei: "near" });
  assert.ok(r.persons.qing.flags.includes("fam_cut"), "郑家记过一回脸色，这回没上市重点：家里不管了");
  assert.ok(!r.persons.mei.flags.includes("strain1"), "董家上了高中就行");
  // 断了供以后：殷实人家的路、爸妈报的班、学琴补习都没了
  assert.equal(G("lifeTrack")(C, { flags: r.persons.qing.flags }, 13).id, "junior", "断了供，爸妈的班没了");
  for (const id of ["piano", "tutor", "swim_class", "lang_class", "tea_box"]) assert.ok((action(id).requires.notFlags || []).includes("fam_cut"), `${id} 断了供的做不了`);
  const ss = lifeAt(23, 18, "zheng", "chen", { mind: 9.5, qflags: ["fam_cut"] });
  exam(ss);
  assert.equal(locks(ss).qing.abroad, "家里已经不管你了");
  // 断了供的复读自己出钱：钱不够锁着写差多少，够了选了扣自己的
  ss.persons.qing.money = 5;
  assert.match(locks(ss).qing.retake || "", /积蓄/, "断了供、钱不够的复读锁着");
  ss.persons.qing.money = 50;
  assert.equal(locks(ss).qing.retake, undefined);
  choose(ss, { qing: "retake", mei: "work" });
  assert.equal(Math.round(ss.persons.qing.money), 50 - ev("m_gaokao").options.find((o) => o.id === "retake").cost, "断了供的复读自己出钱");
  console.log("✓ 中考：清贫的中专（线低一点、包分配、不考大学、二十二岁进厂）/ 小康动爸妈攒的钱上重点、动了就没了 / 别人家的路看不见 / 郑家择校费家里出、两回脸色就断供 / 断了供班没了、学琴补习做不了、出国锁上");
}

// ---------- 4. 高考和再考一回：复读、助学贷款 ----------
{
  const ms = ev("m_gaokao");
  // 清贫没有复读；考上了背助学贷款，拿过助学金的不背
  const s = lifeAt(31, 18, "jiang", "wu", { mind: 7.2, mflags: ["aid"] });
  exam(s);
  assert.equal(locks(s).qing.retake, "家里等着你挣钱");
  assert.ok(shown(s, "qing", ms, "retake"), "清贫的看得见复读，灰着");
  choose(s, { qing: "local", mei: "local" });
  assert.ok(s.persons.qing.flags.includes("loan") && s.persons.qing.flags.includes("uni_near"), "清贫的考上了背助学贷款");
  assert.ok(!s.persons.mei.flags.includes("loan"), "拿过助学金的不背");
  // 小康：复读一年可以动爸妈攒的那笔钱（不花自己的），也可以自己出
  const n = lifeAt(32, 18, "chen", "zheng", { mind: 6 });
  exam(n);
  const l = locks(n);
  assert.equal(l.qing.retake_nest, undefined);
  assert.ok(!shown(n, "mei", ms, "retake_nest"), "殷实看不见动存折那条");
  n.persons.mei.money = 0;
  assert.equal(locks(n).mei.retake, undefined, "殷实人家的复读家里出");
  const m0 = n.persons.qing.money;
  const e = choose(n, { qing: "retake_nest", mei: "retake" });
  assert.equal(e.resonance, true, "动存折复读的和自己复读的同路");
  assert.equal(n.persons.qing.money, m0, "不花自己的钱");
  assert.ok(n.persons.qing.flags.includes("retake") && !n.persons.qing.flags.includes("fam_nest"));
  assert.ok(!n.persons.mei.flags.includes("strain1"), "复读一年郑家也认");
  assert.equal(G("lifeTrack")(C, n.persons.qing, 18).id, "retake_class", "十八岁考完剩下的日子是复读的一年");
  // 十九岁早上再考一回：只给复读的人，没有复读这条
  const rt = ev("m_retake");
  assert.equal(G("lifeMilestoneAt")(C, 19).id, "m_retake");
  assert.ok(G("lifeMilestoneFor")(rt, n.persons.qing) && !G("lifeMilestoneFor")(rt, s.persons.mei));
  assert.ok(!rt.options.some((o) => o.id.startsWith("retake")), "再考一回不能再复读");
  assert.deepEqual(rt.options.filter((o) => o.min).map((o) => [o.id, o.min]), ms.options.filter((o) => o.min).map((o) => [o.id, o.min]), "再考一回的线和高考一样");
  for (const r of ROLES) n.persons[r].stats.mind = 7.4; // 复读一年长了点：够得着本地大学，有得选才弹窗
  n.turn = turnAtAge(19);
  G("worldStartDay")(n, C);
  assert.equal(n.world.fate.milestone, "m_retake");
  const pe = exam(n);
  assert.deepEqual(J(pe.roles), ["qing", "mei"]);
  // 自己出钱的复读：没有存折也没有家里出的
  const o = lifeAt(33, 18, "lin", "chen", { mind: 6, qflags: [] });
  exam(o);
  o.persons.qing.flags = o.persons.qing.flags.filter((f) => f !== "fam_nest");
  o.persons.qing.money = 5;
  assert.match(locks(o).qing.retake, /积蓄/);
  console.log("✓ 高考：清贫没有复读（灰着）、考上了背助学贷款、拿过助学金的不背 / 小康动存折复读不花自己的钱 / 殷实家里出 / 复读那一年在复读班 / 十九岁再考一回，线和高考一样，不能再复读");
}

// ---------- 5. 退班：记一回脸色；记过的再摊牌就是断供 ----------
{
  const evq = ev("h_class_quit_kid");
  const s = lifeAt(41, 10, "zheng", "tang", { qflags: [], mflags: ["strain1"] });
  for (const r of ROLES) s.world.fate[r] = null;
  s.world.event = { eventId: evq.id, kind: "solo", roles: ["qing"], choices: {}, shadow: [] };
  const l = locks(s);
  assert.equal(l.qing.quit, undefined);
  assert.ok(l.qing.quit_cut, "没记过脸色的，摆的是头一回那条");
  choose(s, { qing: "quit" });
  assert.ok(s.persons.qing.flags.includes("class_quit") && s.persons.qing.flags.includes("strain1"));
  assert.equal(G("lifeTrack")(C, s.persons.qing, 10).id, "primary", "班退了，傍晚还给自己");
  s.world.event = { eventId: evq.id, kind: "solo", roles: ["mei"], choices: {}, shadow: [] };
  assert.ok(locks(s).mei.quit, "记过一回的，摆的是第二回那条");
  choose(s, { mei: "quit_cut" });
  assert.ok(s.persons.mei.flags.includes("fam_cut"), "第二回：家里不管了");
  // 影子不选锁着的
  for (let i = 0; i < 20; i++) {
    const t = lifeAt(50 + i, 10, "zheng", "tang");
    assert.notEqual(G("lifeShadowChoose")(t, C, "qing", evq.id), "quit_cut");
  }
  console.log("✓ 退班：摊牌记一回脸色、班退了傍晚还回来 / 记过的再摊牌就断供 / 标记不对的那条不摆、影子不选");
}

// ---------- 6. 规则：lockBy、homePays、flagsIf、expect 的边角 ----------
{
  const o = { id: "x", text: "", tags: [], effects: {}, requires: { flags: ["fam_rich"], notFlags: ["fam_cut"] }, lock: "A", lockBy: { fam_cut: "B", fam_poor: "C" } };
  const e = { kind: "milestone", options: [o], score: { mind: 1 } };
  assert.equal(G("lifeOptionLock")(e, o, { flags: [], stats: {}, money: 0 }, 0), "A");
  assert.equal(G("lifeOptionLock")(e, o, { flags: ["fam_poor"], stats: {}, money: 0 }, 0), "C");
  assert.equal(G("lifeOptionLock")(e, o, { flags: ["fam_rich", "fam_cut"], stats: {}, money: 0 }, 0), "B");
  const c = { id: "y", cost: 30, homePays: ["exp_book"] };
  assert.equal(G("lifeOptionCost")(e, c, { flags: ["exp_book"] }), 0);
  assert.equal(G("lifeOptionCost")(e, c, { flags: ["exp_book", "fam_cut"] }), 30, "家里不管了就自己出");
  assert.equal(G("lifeOptionCost")(e, c, { flags: ["exp_pull"] }), 30);
  assert.deepEqual(J(G("lifeFlagsIf")({ flags: ["fam_poor"] }, [{ flags: ["fam_poor"], notFlags: ["aid"], add: ["loan"] }])), ["loan"]);
  assert.deepEqual(J(G("lifeFlagsIf")({ flags: ["fam_poor", "aid"] }, [{ flags: ["fam_poor"], notFlags: ["aid"], add: ["loan"] }])), []);
  const p = { flags: ["exp_book"] };
  G("lifeFace")(p); assert.deepEqual(p.flags, ["exp_book", "strain1"]);
  G("lifeFace")(p); assert.deepEqual(p.flags, ["exp_book", "strain1", "fam_cut"]);
  G("lifeFace")(p); assert.equal(p.flags.length, 3, "断了供的不再记");
  const x = { expect: { exp_book: ["key"] }, options: [] };
  assert.equal(G("lifeExpectMissed")(x, { id: "paid", joins: "key" }, { flags: ["exp_book"] }), false, "按 joins 算路");
  assert.equal(G("lifeExpectMissed")(x, { id: "normal" }, { flags: ["exp_book"] }), true);
  assert.equal(G("lifeExpectMissed")(x, { id: "normal" }, { flags: ["exp_pull"] }), false);
  assert.equal(G("lifeExpectMissed")(x, { id: "normal" }, { flags: ["exp_book", "fam_cut"] }), false);
  // 内容：每道有 expect 的关，四种 exp_* 都写了单子
  for (const id of ["m_senior", "m_gaokao", "m_retake"]) assert.deepEqual(Object.keys(ev(id).expect).sort(), ["exp_abroad", "exp_art", "exp_book", "exp_pull"], `${id} 四种人家都要写`);
  // 新事件守字数（build-content 也拦）
  for (const e2 of C.events.filter((x2) => x2.id.startsWith("h_"))) {
    const lim = { childhood: 60, teen: 55, young: 50 }[e2.stage];
    assert.ok([...e2.text].length <= lim, `${e2.id} 正文超过 ${lim} 字`);
    for (const o2 of e2.options) assert.ok([...o2.text].length <= 15, `${e2.id}.${o2.id} 选项超过 15 字`);
  }
  console.log("✓ 规则：lockBy 按标记换一句锁 / homePays 家里出、断了供自己出 / flagsIf 按选之前的标记打 / 记脸色头一回 strain1、第二回 fam_cut、断了不再记 / expect 按 joins 算路 / 新事件守字数");
}

// ---------- 7. 影子不替人跟爸妈翻脸、不替考过线的人复读（PR #68 评审） ----------
{
  let missed = 0, retook = 0;
  for (let seed = 1; seed <= 20; seed++) {
    // 郑家（exp_book）记过一回脸色，中考心智够市重点，性格偏「随和」：影子原来多半挑离家近的，一步就断供
    const s = lifeAt(300 + seed, 15, "zheng", "chen", { mind: 9.2, qflags: ["strain1"] });
    s.persons.qing.tags = { gentle: 6, competitive: 2 };
    exam(s);
    const id = G("lifeShadowChoose")(s, C, "qing", "m_senior");
    if (G("lifeExpectMissed")(ev("m_senior"), ev("m_senior").options.find((o) => o.id === id), s.persons.qing)) missed++;
    // 高考过了线的小康，影子不去复读（不白用那笔钱）
    const g = lifeAt(400 + seed, 18, "lin", "chen", { mind: 8.5 });
    g.persons.qing.tags = { patient: 6, competitive: 6 };
    exam(g);
    const gid = G("lifeShadowChoose")(g, C, "qing", "m_gaokao");
    if (!g.persons.qing.flags.includes("gaokao_bad") && ev("m_gaokao").options.find((o) => o.id === gid).effects.flags.includes("retake")) retook++;
  }
  assert.equal(missed, 0, `影子替人选了不在爸妈单子上的路 ${missed} 回`);
  assert.equal(retook, 0, `影子替考过线的人复读 ${retook} 回`);
  console.log("✓ 影子：爸妈单子上有够得着的路就不替人翻脸 / 考过了线不替人复读");
}
