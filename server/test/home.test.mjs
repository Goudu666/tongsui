// 家里的东西（content/home.yaml、server/src/home.ts、docs/HOME.md）。
// 钉住：同一年三档人家有的东西不一样 / 人家写了的压过家境 / 年代不一样差的东西也不一样 / 到了年份进门、记一条长卷 /
// 收起来的摘掉 / 爸妈走了不再添 / 去对门家用对门家的东西、两个人一起用是搭伴 / 自己攒钱买、只在自己家买 /
// 不点菜单的永远轮不到 / 家里有书柜的孩子一个钟头比写作业长得多、清贫的孩子去对门翻书也一样快。
import assert from "node:assert/strict";
import { G, C, NAMES } from "./harness.mjs";

const ROLES = ["qing", "mei"];
const SLOTS = G("SLOTS");
const turnAtAge = (age) => { for (let t = 0; t < 400; t++) if (G("lifeTimeAt")(t).age === age) return t; return -1; };
const spot = (id) => C.map.spots.find((sp) => sp.id === id);
const act = (id) => C.map.actions.find((a) => a.id === id);
const fam = (id) => C.families.find((f) => f.id === id);
function at(s, r, id) { const a = s.world.actors[r]; a.x = spot(id).at[0]; a.y = spot(id).at[1]; }
const has = (s, r) => G("homeList")(C, s.persons[r]);

/** 青是 qf 家、梅是 mf 家，生在 cohort 年代，过到 age 岁那天（家里的东西按那一年重新摆） */
function home(age, qf, mf, cohort = "c92", slot = 3) {
  const s = G("lifeCreate")(11, C);
  s.cohort = cohort;
  for (const r of ROLES) G("lifeConfirm")(s, C, r, NAMES);
  for (const [r, id] of [["qing", qf], ["mei", mf]]) {
    const p = s.persons[r];
    const old = fam(p.familyId).traits;
    p.familyId = id;
    p.flags = p.flags.filter((f) => !old.includes(f) && !f.startsWith("hm_") && !f.startsWith("tal_")).concat(fam(id).traits);
    p.money = 20;
  }
  s.turn = turnAtAge(age);
  G("worldStartDay")(s, C);
  const w = s.world;
  w.fate = { mirror: null, qing: null, mei: null };
  w.rest = true;
  w.slot = slot;
  w.minute = SLOTS[slot][0];
  for (const r of ROLES) {
    s.persons[r].stats = { body: 5, mind: 5, charm: 5, luck: 5 };
    s.persons[r].needs = { hunger: 80, energy: 80, mood: 80, clean: 80 };
  }
  return s;
}
const doIt = (s, r, sp, a) => { at(s, r, sp); return G("worldAct")(s, C, r, sp, true, a); };

// ---------- 0. 内容 ----------
{
  const items = C.home.items;
  assert.ok(items.length >= 8, "八样以上东西");
  for (const it of items) {
    const ys = ["rich", "mid", "poor"].map((k) => it.arrive[k] ?? Infinity);
    assert.ok(ys[0] <= ys[1] && ys[1] <= ys[2], `${it.name}：殷实不晚于小康、小康不晚于清贫`);
  }
  // 屋里的点位两家一样：青家有的，梅家也有
  for (const sp of C.map.spots.filter((x) => x.id.endsWith("_qing"))) {
    const twin = spot(sp.id.replace(/_qing$/, "_mei"));
    if (twin) assert.deepEqual(twin.actions, sp.actions, `${sp.id} 和 ${twin.id} 挂的事要一样`);
  }
  for (const a of C.map.actions.filter((x) => x.requires.home || x.buys)) {
    assert.ok(a.menu, `${a.id}：看家里东西的事都是 menu`);
    assert.ok(C.map.spots.some((sp) => sp.actions.includes(a.id) && sp.scene === "building"), `${a.id} 挂在家里`);
  }
}

// ---------- 1. 同一年，三户人家不在同一个年代 ----------
{
  // 九十年代初生、八岁那年（千禧年）：殷实人家书柜、电话、游戏机、复读机、电脑都有了；小康没有电脑；清贫只有电视、冰箱
  const s = home(8, "dong", "chen");
  const rich = has(s, "qing"), mid = has(s, "mei");
  for (const id of ["tv", "books", "phone", "console", "tape", "pc", "milk"]) assert.ok(rich.includes(id), `殷实人家八岁时有${id}`);
  for (const id of ["tv", "books", "phone", "console", "tape", "milk"]) assert.ok(mid.includes(id), `小康人家八岁时有${id}`);
  assert.ok(!mid.includes("pc"), "小康人家八岁时还没有电脑");
  const p = home(8, "wu", "ma");
  const poor = has(p, "qing");
  assert.ok(poor.includes("tv") && poor.includes("fridge"), "清贫人家也有电视、冰箱了");
  for (const id of ["books", "phone", "console", "tape", "pc", "milk"]) assert.ok(!poor.includes(id), `清贫人家八岁时没有${id}`);
  // 人家写了的压过家境：老城里搬来的金家穷了，书还在；教书先生家的书比别的小康人家早
  assert.ok(has(home(8, "jin", "wu"), "qing").includes("books"), "金家清贫，书柜还在");
  assert.ok(has(home(6, "lin", "chen", "c75"), "qing").includes("books") && !has(home(6, "lin", "chen", "c75"), "mei").includes("books"), "七十年代生六岁：林家有书，陈家还没有");
  // 年代不一样，差的东西也不一样：六十年代中生的八岁，殷实人家有收音机，清贫人家也有了，电视哪家都还没有
  const old = home(8, "dong", "wu", "c65");
  assert.ok(has(old, "qing").includes("radio") && has(old, "mei").includes("radio"), "六十年代：收音机");
  assert.ok(!has(old, "qing").includes("tv"), "六十年代：殷实人家也还没有电视");
  const o2 = home(15, "dong", "wu", "c65");
  assert.ok(has(o2, "qing").includes("tv") && !has(o2, "mei").includes("tv"), "六十年代生十五岁：殷实有电视，清贫还没有");
  console.log("✓ 同一年三档人家有的不一样：殷实 " + rich.join(",") + " / 小康 " + mid.join(",") + " / 清贫 " + poor.join(","));
}

// ---------- 2. 到了年份进门，记一条长卷；收起来的摘掉；爸妈走了不再添 ----------
{
  const s = home(11, "chen", "wu");
  assert.ok(!has(s, "qing").includes("pc"), "小康十一岁（〇三年）还没电脑");
  s.turn = turnAtAge(12);
  const out = [];
  G("homeSync")(s, C, out);
  const e = out.find((x) => x.kind === "home" && x.home.item === "pc");
  assert.ok(e && e.home.role === "qing" && e.text, "小康十二岁电脑进门，记一条长卷");
  assert.ok(s.log.includes(e), "进了长卷");
  assert.ok(!out.some((x) => x.home.role === "mei" && x.home.item === "pc"), "清贫人家那年没有");
  const g = home(25, "dong", "chen");
  assert.ok(!has(g, "qing").includes("phone") && !has(g, "qing").includes("tape"), "手机的年月，座机、复读机收起来了");
  assert.ok(has(g, "qing").includes("pc"), "电脑一直在");
  const pg = home(18, "wu", "wu");
  pg.persons.qing.flags.push("parent_gone");
  pg.turn = turnAtAge(30);
  G("homeSync")(pg, C, null);
  assert.ok(!has(pg, "qing").includes("pc") && has(pg, "mei").includes("pc"), "爸妈走了的家里不再添东西");
}

// ---------- 3. 去对门家用对门家的东西 ----------
{
  const s = home(10, "wu", "dong");
  assert.equal(doIt(s, "qing", "desk_qing", "hm_books").error, "家里没有这样东西", "清贫人家没有书柜");
  assert.equal(doIt(s, "qing", "table_qing", "hm_console").error, "家里没有这样东西");
  const m0 = s.persons.qing.stats.mind;
  assert.equal(doIt(s, "qing", "desk_mei", "hm_books").error, null, "去对门家翻书");
  assert.ok(s.persons.qing.stats.mind > m0, "翻书长心智");
  assert.equal(doIt(s, "mei", "desk_mei", "hm_books").error, null);
  assert.ok(s.world.actors.mei.did.tg, "两个人一起翻对门的书是搭伴");
  const t = home(10, "dong", "wu");
  assert.equal(doIt(t, "mei", "table_qing", "hm_console").error, null, "去对门打游戏机");
  assert.equal(doIt(t, "qing", "desk_mei", "hm_books").error, "TA 家没有这样东西", "殷实人家的孩子去清贫人家，没有书柜");
  // 不点菜单的（影子、机器人、旧安装包）还是吃饭、写作业，轮不到这些
  for (const sp of ["table_qing", "desk_qing", "corner_qing", "table_mei", "desk_mei"]) {
    const pk = G("worldPickAction")(t, C, "qing", spot(sp)).act;
    assert.ok(!pk || !pk.id.startsWith("hm_") && !pk.buys, `不点菜单在 ${sp} 落到了 ${pk?.id}`);
  }
}

// ---------- 4. 自己攒钱买 ----------
{
  const s = home(12, "wu", "wu");
  s.persons.qing.money = 20;
  assert.equal(doIt(s, "qing", "desk_mei", "buy_tape").error, "这不是你的家", "只在自己家买");
  assert.equal(doIt(s, "qing", "desk_qing", "buy_tape").error, null, "清贫人家的孩子攒钱买复读机");
  assert.equal(s.persons.qing.money, 20 - 15);
  assert.ok(has(s, "qing").includes("tape"), "买回来就是这户人家的");
  assert.equal(doIt(s, "qing", "desk_qing", "buy_tape").error, "家里已经有了");
  assert.equal(doIt(s, "mei", "desk_qing", "hm_tape").error, null, "对门也能过来用");
  const last = s.log.filter((e) => e.kind === "home").pop();
  assert.ok(last.home.bought && last.home.role === "qing", "买的记一条长卷");
  s.persons.mei.money = 10;
  assert.equal(doIt(s, "mei", "desk_mei", "buy_tape").error, "兜里的钱不够");
  const early = home(10, "wu", "wu", "c75");
  early.persons.qing.money = 50;
  assert.equal(doIt(early, "qing", "desk_qing", "buy_tape").error, "外头还没有卖的", "八十年代中还没有复读机卖");
  const small = home(7, "wu", "wu");
  small.persons.qing.money = 50;
  assert.equal(doIt(small, "qing", "desk_qing", "buy_tape").error, "还太小了");
  const v = G("homeBuyList")(s, C, "mei");
  assert.ok(v.includes("buy_console") && v.includes("buy_tape") && !v.includes("buy_pc"), `梅家能买的：${v.join(",")}（复读机是青家买的，梅家自己没有；十二岁买不了电脑）`);
}

// ---------- 5. 资源差异有多大：一个钟头长多少心智 ----------
// 写作业 0.4/90 分钟；家里有书柜的翻书 0.34/60，快三成；清贫的孩子去对门翻，一样快（东西是对门的，时间是自己的）
{
  const gain = (qf, mf, sp, a) => {
    const s = home(10, qf, mf, "c92", 2);
    const m0 = s.persons.qing.stats.mind;
    const r = doIt(s, "qing", sp, a);
    assert.equal(r.error, null, `${a} @ ${sp}`);
    const d = s.world.actors.qing.did;
    return (s.persons.qing.stats.mind - m0) / (d.t - d.f);
  };
  const study = gain("wu", "dong", "desk_qing", "study");
  const books = gain("dong", "wu", "desk_qing", "hm_books");
  const visit = gain("wu", "dong", "desk_mei", "hm_books");
  assert.ok(books > study * 1.2, `家里翻书每分钟 ${books.toFixed(4)}，写作业 ${study.toFixed(4)}`);
  assert.ok(Math.abs(visit - books) < 1e-9, "去对门翻书一样快");
  console.log(`✓ 每分钟心智：写作业 ${study.toFixed(4)} / 家里翻书 ${books.toFixed(4)}（${(books / study).toFixed(2)} 倍）/ 去对门翻 ${visit.toFixed(4)}`);
}

console.log("✓ home.test 全部通过");
