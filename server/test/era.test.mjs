// 年代大事（server/src/era.ts，docs/ERAS.md）：两个人同一年生，出生年代决定一路碰上的大事。
// 钉住：出生年代不动 s.rng / 日历年 / 生之前的悄悄生效 / 线和要掏的钱跟着年代挪 / 工钱乘数 / 大事当天记进长卷、落到人头上 /
// 分房和保障房只在那几年 / 九十年代初生那一世每道关的线和内容里写的一样（数值按它校的）/ 老存档补上 / 再来一世换一个年代
import assert from "node:assert/strict";
import { G, C, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const J = (x) => JSON.parse(JSON.stringify(x));
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const ms = (id) => C.events.find((e) => e.id === id);
const opt = (mid, oid) => ms(mid).options.find((o) => o.id === oid);
const cohort = (id) => C.eras.cohorts.find((c) => c.id === id);
const DEFAULT = C.eras.cohorts.find((c) => c.default).id;

function born(seed, co) {
  const s = G("lifeCreate")(seed, C, undefined, co);
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  return s;
}
/** 跳到这个岁数那一天（eraSync 在 worldStartDay 里补上这些年的标记） */
function at(s, age) {
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  return s;
}
const line = (s, r, mid, oid) => G("lifeOptionMin")(opt(mid, oid), s.persons[r]);

// ---------- 1. 出生年代 ----------
{
  assert.equal(C.eras.cohorts.length, 5, "五个出生年代");
  assert.equal(G("lifeCreate")(7, C).cohort, DEFAULT, "不指定就是默认年代（测试、平衡工具都按它跑）");
  // 指定年代不动随机数：同一个种子，投胎抽到的人家、天赋、属性一模一样
  for (const seed of [1, 2, 3, 99]) {
    const a = G("lifeCreate")(seed, C), b = G("lifeCreate")(seed, C, undefined, "c65");
    assert.deepEqual(J(a.rolls), J(b.rolls));
    assert.equal(a.rng, b.rng);
  }
  const seen = new Map();
  for (let seed = 1; seed <= 600; seed++) {
    const id = G("eraPickCohort")(C, seed);
    assert.equal(id, G("eraPickCohort")(C, seed), "同一个种子抽到同一个年代");
    seen.set(id, (seen.get(id) || 0) + 1);
  }
  assert.equal(seen.size, 5, "五个年代都抽得到");
  assert.ok(seen.get(DEFAULT) > seen.get("c65"), "默认年代权重高");
  // 再来一世换一个年代
  for (const co of C.eras.cohorts) for (let seed = 1; seed < 40; seed++) assert.notEqual(G("eraRebirthCohort")(C, seed, co.id), co.id);
  console.log(`✓ 出生年代：五个都抽得到（600 个种子 ${[...seen].map(([k, v]) => k + " " + v).join(" / ")}）/ 不动投胎的随机数 / 再来一世换一个年代`);
}

// ---------- 2. 日历年、年代名、生之前的事 ----------
{
  const s = born(5, "c65");
  assert.equal(G("eraYear")(s, C), 1968);
  assert.equal(G("eraYear")(s, C, 18), 1983);
  assert.equal(s.log.filter((e) => e.kind === "era").length, 0, "生之前的事不弹卡");
  for (const r of ROLES) for (const f of ["era_pre_kuozhao", "era_fenpei", "era_fenfang"]) assert.ok(s.persons[r].flags.includes(f), `六十年代生一落地就带着 ${f}`);
  const v = G("eraView")(s, C);
  assert.equal(v.cohort.name, cohort("c65").name);
  assert.equal(v.era.decade, "六十年代");
  assert.equal(v.era.look, "childhood");
  const t = born(5, "c02");
  assert.equal(G("eraView")(at(t, 30), C).era.look, "middle");
  assert.equal(G("eraView")(at(t, 75), C).era.look, "old");
  // 年份不给人看
  for (const e of C.eras.events) assert.ok(!/\d/.test(e.title + e.text), `${e.id} 正文里有数字`);
  for (const e of C.eras.events) for (const h of e.hits) assert.ok(!/\d/.test(h.text), `${e.id} hits 里有数字`);
  console.log("✓ 日历年 = 出生年 + 岁数 / 生之前的事只打标记不弹卡 / 年代名和街景 look / 正文不写年份");
}

// ---------- 3. 线、要掏的钱、工钱 ----------
{
  const old = at(born(5, "c65"), 15), mid = at(born(5, "c92"), 15), young = at(born(5, "c02"), 15);
  assert.equal(line(old, "qing", "m_gaokao", "away"), opt("m_gaokao", "away").min + 0.7, "六十年代生高考外地线高 7 分");
  assert.equal(line(mid, "qing", "m_gaokao", "away"), opt("m_gaokao", "away").min);
  assert.ok(line(young, "qing", "m_gaokao", "away") < opt("m_gaokao", "away").min, "〇〇后学校多了，线低");
  // 纸带（lifeGoal）上写的就是挪过的线
  old.persons.qing.stats.mind = 7;
  const g = G("lifeGoal")(at(old, 17), C, "qing");
  assert.equal(g.id, "m_gaokao");
  assert.equal(g.lines.find((l) => l.id === "away").need, Math.floor((opt("m_gaokao", "away").min + 0.7) * 10 + 1e-6));
  // 看积蓄的线挪了，要掏的钱跟着挪
  const h = at(born(5, "c65"), 29);
  const buy = opt("m_settle", "buy");
  assert.equal(line(h, "qing", "m_settle", "buy"), buy.min - 60);
  assert.equal(G("lifeOptionCost")(ms("m_settle"), buy, h.persons.qing), buy.cost - 60);
  h.persons.qing.money = buy.min - 30;
  assert.equal(G("lifeOptionLock")(ms("m_settle"), buy, h.persons.qing, 0), null, "分房那几年，原来差 30 块的买得起了");
  const h85 = at(born(5, "c85"), 29);
  h85.persons.qing.money = buy.min;
  assert.match(G("lifeOptionLock")(ms("m_settle"), buy, h85.persons.qing, 0), /要 2\d\d 块/, "八十年代生赶上房价两波");
  // 工钱：下岗那几年厂里的打八折，下海那几年做买卖的多挣
  const w = at(born(5, "c65"), 33);
  const p = w.persons.qing;
  p.flags.push("job_succeed");
  assert.ok(p.flags.includes("era_xiagang"));
  const duty = { money: 10 };
  assert.equal(G("worldWage")(C, p, duty), 8);
  const x = at(born(5, "c65"), 27).persons.qing;
  x.flags.push("job_trade");
  assert.equal(G("worldWage")(C, x, duty), 12.5);
  const y = at(born(5, "c92"), 27).persons.qing;
  y.flags.push("job_trade");
  assert.equal(G("worldWage")(C, y, duty), 10, "九十年代初生二十七岁做买卖，下海那几年早过了");
  console.log("✓ 线跟着年代挪（锁上那句、纸带都是挪过的数）/ 积蓄线挪了要掏的钱跟着挪 / 工钱乘数只在那几年");
}

// ---------- 4. 分房、保障房 ----------
{
  const open = (co) => {
    const s = at(born(5, co), 30);
    s.persons.qing.flags.push("job_succeed");
    s.persons.qing.money = 300;
    const ev = ms("m_settle");
    return ev.options.filter((o) => ["unit", "quota"].includes(o.id) && !G("lifeOptionLock")(ev, o, s.persons.qing, 0)).map((o) => o.id).join(",");
  };
  assert.equal(open("c65"), "unit", "六十年代生：厂里还分房");
  assert.equal(open("c75"), "", "七十年代生：房改以后没分房了，保障房还没盖");
  assert.equal(open("c85"), "");
  assert.equal(open("c92"), "quota", "九十年代初生：排得上保障房（顶上原来那条 40 块的路）");
  assert.equal(open("c02"), "quota");
  console.log("✓ 厂里分房只在分房那几年 / 保障房在回落以后 / 七十、八十年代生的工人夹在中间");
}

// ---------- 5. 大事当天发生：长卷、落到人头上 ----------
{
  const s = born(3, "c65");
  s.persons.qing.money = 100;
  // 一天一天过到 28 岁：抢购那年（二十三岁）积蓄打八五折，二十七岁赶上下海
  const cards = [];
  while (G("lifeTimeAt")(s.turn).age < 28 && s.phase === "life") {
    const out = G("lifeEndDay")(s, C);
    cards.push(...out.filter((e) => e.kind === "era"));
  }
  const ids = cards.map((e) => e.era.id);
  assert.ok(ids.includes("era_qianggou") && ids.includes("era_xiahai"), "抢购、下海都在长卷里：" + ids.join(","));
  assert.deepEqual(ids, [...new Set(ids)], "一件事只发生一回");
  const q = cards.find((e) => e.era.id === "era_qianggou");
  assert.ok(q.era.hits.qing && q.era.decade === "八十年代", "抢购落到青头上，写着八十年代");
  assert.ok(!s.persons.qing.flags.includes("era_qianggou"), "抢购两年就过去了（until）");
  assert.ok(s.log.filter((e) => e.kind === "era").length === cards.length, "长卷里也记着");
  assert.ok(s.eras.includes("era_qianggou") && s.eras.includes("era_pre_kuozhao"));
  console.log(`✓ 大事当天记进长卷（六十年代生到二十八岁见了 ${ids.length} 件）/ 落到人头上的那句 / until 摘掉`);
}

// ---------- 6. 九十年代初生：每道关的线和内容里写的一样 ----------
{
  for (const ev of C.events.filter((e) => e.kind === "milestone")) {
    const s = at(born(9, DEFAULT), ev.age);
    for (const o of ev.options) if (o.min) assert.equal(line(s, "qing", ev.id, o.id), o.min, `${ev.id}.${o.id}：九十年代初生的线应该没挪（数值按这一代校的）`);
  }
  console.log("✓ 九十年代初生那一世，每道关每条线都和内容里写的一样");
}

// ---------- 7. 存档：老存档补上、跳着过也跟得上 ----------
{
  const s = J(at(born(4, DEFAULT), 22));
  delete s.cohort;
  delete s.eras;
  for (const r of ROLES) s.persons[r].flags = s.persons[r].flags.filter((f) => !f.startsWith("era_"));
  s.version = 8;
  const notes = G("lifeUpgrade")(s).concat(G("lifeRepair")(s, C));
  assert.ok(notes.includes("v8→v9"));
  assert.equal(s.cohort, DEFAULT);
  assert.ok(s.eras.length > 0 && s.persons.qing.flags.includes("era_kuozhao") === false, "扩招那件到一〇年代初已经摘了");
  assert.equal(s.log.filter((e) => e.kind === "era").length, 0, "补上的不弹卡");
  const bad = J(s);
  bad.cohort = "c_gone";
  bad.eras.push("era_gone");
  G("lifeRepair")(bad, C);
  assert.equal(bad.cohort, undefined);
  assert.ok(!bad.eras.includes("era_gone"));
  console.log("✓ 存档：v8 升 v9 按默认年代补上过去的大事 / 年代或大事没了摘掉");
}
