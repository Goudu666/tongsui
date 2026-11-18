#!/usr/bin/env node
// 九到十二岁「小升初」冲刺量表（11-18 反思玩法，docs/GROWTH.md 5.6 节）：三年级那道关刚弹出来的九岁孩子，换几种过法过完十二个季节，
// 按 tools/sprint.mjs 的口径数小升初 无可冲 / 跨过 / 失手、一个阶段涨了几分（第 25 个日子早上 → 第 36 个日子早上）。
// 直接调 worldAct / worldAdvance，不走路、不算手速，一次二十秒上下；投胎按种子走，同样的参数重跑是同一个数（sprint 十四世这道关能抖十几个点）。
//
// 用法：npm run build && node tools/primary.mjs [--reps=4] [--x=1.8]
//   --x 临时换 growth.chosenWeight 那一段的倍数（1 = 不乘，看改之前的样子），不写就用 rules.yaml 里的
//   九岁的三项取自 main 0433914 上 sprint 14 --seed=5 认真 / 随便机器人九岁那天的纸带（KIDS9，心智 / 体魄 / 魅力的百分制）
//   认真 = 盯纸带上差得最少的线（worldShadowNeed）、能搭伴就搭伴、上学的日子早上和放学后押上、晚上睡、精力不到 15 也睡；
//   拼满 = 每一段都押上、晚上也念，精力不到 5 才睡；随便 = 交给影子（人不在线时的过法）
import { G, C, fakeNakama, room } from "../server/test/harness.mjs";

const KIDS9 = {"careful":[[67,64,72],[50,69,92],[86,65,62],[73,64,78],[63,88,52],[42,64,63],[64,64,47],[65,64,58],[75,87,58],[41,96,71],[65,86,62],[66,80,91],[69,66,61],[35,82,83],[74,76,58],[74,61,72],[77,66,66],[67,58,88],[100,66,77],[52,91,87],[44,64,63],[62,78,62],[67,75,35],[76,37,88],[75,64,81],[52,71,64],[83,67,73],[62,72,68]],"casual":[[94,63,40],[44,63,90],[57,39,73],[68,52,69],[77,34,62],[45,49,69],[47,73,55],[62,48,43],[44,94,38],[50,88,50],[55,58,39],[59,70,85],[59,62,73],[47,58,70],[69,68,27],[77,32,65],[58,83,58],[60,46,78],[77,43,79],[45,64,88],[80,61,65],[61,61,53],[59,66,71],[73,31,86],[43,62,70],[58,57,52],[63,89,54],[57,63,65]]};
const args = process.argv.slice(2);
const opt = (k, d) => { const a = args.find((x) => x.startsWith("--" + k + "=")); return a ? Number(a.slice(k.length + 3)) : d; };
const REPS = opt("reps", 4);
const X = opt("x", NaN);
if (!Number.isNaN(X)) C.rules.growth.chosenWeight = X > 1 ? (C.rules.growth.chosenWeight || [{ from: 9, to: 11 }]).map((b) => ({ ...b, x: X })) : undefined;

const OP = G("OP");
const ROLES = ["qing", "mei"];
const J = (x) => JSON.parse(JSON.stringify(x));
const spot = (id) => C.map.spots.find((s) => s.id === id);
const ALL = [0, 1, 2, 3, 4];

// 投胎（年代、人家、天赋、属性）在 rpcLifelineJoin 里用 Math.random 抽，换成按种子走的，同样的参数每回量出同一个数，--x 之间才比得了
let rnd = 1;
Math.random = () => { rnd = (Math.imul(rnd, 1664525) + 1013904223) >>> 0; return rnd / 4294967296; };

function newLife(seed) {
  rnd = (seed * 2654435761) >>> 0 || 1;
  const env = fakeNakama();
  const qa = { userId: "u-qing", sessionId: "s-qing", username: "qing" };
  const ma = { userId: "u-mei", sessionId: "s-mei", username: "mei" };
  const made = env.rpc("rpcLifelineCreate", qa.userId, { name: "小青" });
  env.rpc("rpcLifelineJoin", ma.userId, { code: made.code, name: "小梅" });
  const open = env.rpc("rpcLifelineOpen", qa.userId, { lifelineId: made.lifelineId });
  const R = room(env.nk, open.matchId);
  R.join([qa, ma]);
  R.state.record.life.rng = seed >>> 0 || 1;
  for (let i = 0; i < 80; i++) R.loop();
  R.loop([R.msg(ma, OP.ROLL, { reroll: true })]);
  for (let i = 0; i < 30; i++) R.loop();
  R.loop([R.msg(qa, OP.ROLL, { confirm: true }), R.msg(ma, OP.ROLL, { confirm: true })]);
  return J(R.life());
}

function tryAct(s, r, spotId, want, once) {
  const a = s.world.actors[r], sp = spot(spotId);
  const keep = [a.x, a.y];
  a.x = sp.at[0]; a.y = sp.at[1];
  const res = G("worldAct")(s, C, r, spotId, !!once, want);
  if (res.error) { a.x = keep[0]; a.y = keep[1]; return res.error; }
  return null;
}

function drive(s, pol, untilTurn) {
  const online = { qing: true, mei: true };
  let guard = 0;
  while (s.phase === "life" && s.turn < untilTurn && guard++ < 200000) {
    const w = s.world;
    if (w.event) {
      const pe = w.event;
      for (const r of pe.roles) if (!pe.choices[r]) { const res = G("worldChoose")(s, C, r, pol.choose(s, r, pe), false); if (res.error) G("worldChoose")(s, C, r, G("lifeShadowChoose")(s, C, r, pe.eventId), false); }
      continue;
    }
    if (!w.playing && !pol.shadow) for (const r of ROLES) if (s.persons[r].alive && !G("worldReady")(s, r)) pol.act(s, r);
    G("worldAdvance")(s, C, 3, pol.shadow ? { qing: false, mei: false } : online);
  }
}

/** 长这一项最快的几件（每分钟长多少），对门这一段定在哪件上就先挑那件（搭伴） */
function best(s, r, k, first) {
  const cands = [];
  for (const sp of C.map.spots) {
    const z = C.map.zones.find((z) => z.id === sp.zone);
    if (z.owner && z.owner !== r) continue;
    for (const id of sp.actions) {
      const a = G("worldPickAction")(s, C, r, sp, id).act;
      if (!a || a.id !== id || a.duty || a.sleep || a.quick || (a.money || 0) < 0 || !(a.stats && a.stats[k] > 0)) continue;
      if (G("worldCanAct")(s, C, r, sp.id, true, id)) continue;
      cands.push({ sp: sp.id, id, v: a.stats[k] / a.minutes + (first && first.sp === sp.id && first.id === id ? 1 : 0) });
    }
  }
  return cands.sort((a, b) => b.v - a.v);
}

/** 三年级挑头一个够得着的组（数学 / 体校 / 曲艺），都够不着回家 */
function clubOf(s, r) {
  const locks = (G("lifeMilestoneLocks")(s, C) || {})[r] || {};
  for (const id of ["math", "sport", "art"]) if (!locks[id]) return id;
  return "none";
}

function careful(o) {
  const plan = {};
  return {
    choose(s, r, pe) { return pe.eventId === "m_club" ? clubOf(s, r) : G("lifeShadowChoose")(s, C, r, pe.eventId); },
    act(s, r) {
      const w = s.world, p = s.persons[r];
      const duty = G("worldDutyOpen")(s, C, r);
      if (duty && w.slot >= G("worldDutySlots")(duty)[0]) { if (!tryAct(s, r, duty.spot)) return; }
      if (p.needs.hunger < 45 && !w.quick.includes(r + ":eat")) tryAct(s, r, "table_" + r);
      // 认真：晚上那段睡，精力不到 15 也睡；拼满：晚上也念，精力不到 5 才睡
      if ((w.slot === 4 && !o.night) || (o.e15 && p.needs.energy < 15) || p.needs.energy < 5) { if (!tryAct(s, r, "bed_" + r)) return; }
      const on = w.rest ? ALL : o.school;
      if (!on.includes(w.slot)) { G("worldPass")(s, C, r); return; }
      const k = G("worldShadowNeed")(s, C, r) || "mind";
      const other = r === "qing" ? "mei" : "qing";
      const first = plan[other] && plan[other].k === k && plan[other].slot === w.slot && plan[other].turn === s.turn ? plan[other] : null;
      for (const c of best(s, r, k, first)) if (!tryAct(s, r, c.sp, c.id, false)) { plan[r] = { k, sp: c.sp, id: c.id, slot: w.slot, turn: s.turn }; return; }
      G("worldPass")(s, C, r);
    },
  };
}
const shadow = { shadow: true, choose: (s, r, pe) => G("lifeShadowChoose")(s, C, r, pe.eventId), act() {} };

function lines(s, r) {
  const g = G("lifeGoal")(s, C, r);
  return g && g.title === "小升初" ? g.lines.map((l) => ({ id: l.id, have: l.have, need: l.need })) : null;
}
const med = (a) => { const b = a.slice().sort((x, y) => x - y); return b.length ? b[b.length >> 1] : NaN; };

function runSet(kids, pol) {
  const res = { none: 0, cross: 0, fail: 0, gain: [], near: 0, missed: 0 };
  for (let rep = 0; rep < REPS; rep++) for (let i = 0; i < kids.length; i += 2) {
    const s = newLife(1 + i / 2 + rep * 100);
    drive(s, shadow, 24); // 九岁那天早上（三年级那道关还没弹）
    ROLES.forEach((r, j) => { const k = kids[i + j]; if (k) Object.assign(s.persons[r].stats, { mind: k[0] / 10, body: k[1] / 10, charm: k[2] / 10 }); });
    drive(s, pol, 25);
    const a = { qing: lines(s, "qing"), mei: lines(s, "mei") };
    drive(s, pol, 36);
    for (const r of ROLES) {
      if (!a[r]) continue;
      const b = lines(s, r);
      const ls = a[r].map((l) => ({ ...l, end: b.find((x) => x.id === l.id).have }));
      if (ls.every((l) => l.have >= l.need)) res.none++;
      else if (ls.some((l) => l.have < l.need && l.end >= l.need)) res.cross++;
      else res.fail++;
      res.gain.push(Math.max(...ls.map((l) => l.end - l.have)));
      for (const l of ls) if (l.end < l.need) { res.missed++; if (l.need - l.end <= 5) res.near++; }
    }
  }
  const n = res.none + res.cross + res.fail, P = (v) => (Math.round((100 * v) / n) + "%").padStart(4);
  return `${n} 人  无可冲 ${P(res.none)}  跨过 ${P(res.cross)}  失手 ${P(res.fail)}  涨分中位 ${String(med(res.gain)).padStart(2)}  没够着的线里差 5 分以内 ${res.near}/${res.missed}`;
}

const cw = C.rules.growth.chosenWeight;
console.log(`小升初（九到十二岁，每人 ${REPS} 遍）  自己挑的事：${cw ? cw.map((b) => `${b.from}~${b.to} 岁 ×${b.x}`).join("、") : "不乘"}`);
console.log("  认真  " + runSet(KIDS9.careful, careful({ e15: true, school: [0, 3] })));
console.log("  拼满  " + runSet(KIDS9.careful, careful({ school: ALL, night: true })));
console.log("  随便  " + runSet(KIDS9.casual, shadow));
