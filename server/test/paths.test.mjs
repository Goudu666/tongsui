// 核心玩法的形状：时间花在哪，决定够得着哪条线。
// 让机器人按几种活法把人生过到关口（tools/paths.mjs），钉住四件事。具体的数归 rules.yaml 和 milestones.yaml 调，
// 这里只管调完以后这四件事还成立；哪条不成立了，这个游戏就没有取舍可言了。
import assert from "node:assert/strict";
import { WAYS, live, climb } from "../../tools/paths.mjs";

const N = 16;
const run = (name, untilAge) => {
  const marks = [];
  for (let seed = 1; seed <= N; seed++) marks.push(live(seed * 7919, WAYS[name], untilAge, climb).marks);
  return marks;
};
const people = (marks, id) => marks.flatMap((m) => Object.values(m[id] || {}));
const rate = (marks, id, option) => { const ps = people(marks, id); return ps.filter((p) => p.open.includes(option)).length / ps.length; };
const mean = (marks, id, stat) => { const ps = people(marks, id); return ps.reduce((a, p) => a + p.stats[stat], 0) / ps.length; };

const lazy = run("不上心", 13), solo = run("一个人念书", 13), duo = run("搭伴念书", 13), half = run("一半念书一半玩", 13);

// 1. 不上心的够不着高线，专心的大多够得着，一半一半的在中间
//    现在（重点班线 7.0，tools/paths.mjs 每种活法 120 人）：不上心 25%，一半一半 75%，专心一个人 89%，搭伴 100%。
//    这里只跑 16 条人生，数会跳几个点；断言留的余量够大，不用跟着调。
const [rl, rh, rs] = [rate(lazy, "m_junior", "key"), rate(half, "m_junior", "key"), rate(solo, "m_junior", "key")];
assert.ok(rl <= 0.5, `不上心的人有 ${Math.round(rl * 100)}% 进了重点班，线太低了`);
assert.ok(rs >= 0.7, `专心念书的人只有 ${Math.round(rs * 100)}% 进重点班，线太高了`);
assert.ok(rl < rh && rh <= rs, `一半念书一半玩应该在两头中间（${rl} / ${rh} / ${rs}）`);

// 2. 活法比出身重要：专心的和不上心的，到 12 岁心智至少差 1.5
const gap = mean(solo, "m_junior", "mind") - mean(lazy, "m_junior", "mind");
assert.ok(gap >= 1.5, `专心念书只比不上心多 ${gap.toFixed(2)} 点心智，怎么过都差不多`);

// 3. 搭伴比一个人强：这是两个人一起玩的理由
const lift = mean(duo, "m_junior", "mind") - mean(solo, "m_junior", "mind");
assert.ok(lift >= 0.2, `搭伴念书只比一个人多 ${lift.toFixed(2)} 点心智，没有搭伴的理由`);

// 4. 一个人够不着所有的线：找工作那一关，没有谁五条路都走得通的活法占多数
const mixed = run("混着来", 23);
const all = people(mixed, "m_job").filter((p) => ["desk", "teach", "trade", "craft", "labor"].every((o) => p.open.includes(o))).length / people(mixed, "m_job").length;
assert.ok(all <= 0.25, `什么都练一点的人有 ${Math.round(all * 100)}% 五条路都走得通，没有取舍了`);

// 5. 影子替人过日子，不替人拼：梅不在线、青专心念书的时候，梅的影子不能比一个本人在场专心念书的人强；
//    也不能被落得比谁都差（至少不比两个人都不上心差）
const away = run("青念书，梅是影子", 13);
const shadows = away.map((m) => m.m_junior?.mei).filter(Boolean);
const shadowMind = shadows.reduce((a, p) => a + p.stats.mind, 0) / shadows.length;
const solom = mean(solo, "m_junior", "mind"), lazym = mean(lazy, "m_junior", "mind");
assert.ok(shadowMind <= solom - 0.3, `影子到 12 岁心智 ${shadowMind.toFixed(2)}，本人在场专心念书才 ${solom.toFixed(2)}：人不在反而更划算`);
assert.ok(shadowMind >= lazym, `影子到 12 岁心智 ${shadowMind.toFixed(2)}，比两个人都不上心（${lazym.toFixed(2)}）还差：人一走就全落下了`);

// 6. 钱是拿成长换的：从小帮爷爷修车的人攒得下钱，但够不着重点班的比一半念书一半玩的人少
const hustle = run("从小挣钱", 13);
const hk = rate(hustle, "m_junior", "key");
const purse = (marks) => { const ps = people(marks, "m_junior"); return ps.reduce((a, p) => a + p.money, 0) / ps.length; };
assert.ok(purse(hustle) > purse(solo) + 10, `从小挣钱的人到 12 岁只比念书的多 ${(purse(hustle) - purse(solo)).toFixed(0)} 块，没人会去挣`);
assert.ok(hk < rh, `从小挣钱的人有 ${Math.round(hk * 100)}% 进重点班，不比一半念书一半玩的（${Math.round(rh * 100)}%）少：钱是白捡的`);

console.log(`✓ 影子和钱：影子 12 岁心智 ${shadowMind.toFixed(1)}（不上心 ${lazym.toFixed(1)}，本人专心 ${solom.toFixed(1)}）/ 从小挣钱多攒 ${(purse(hustle) - purse(solo)).toFixed(0)} 块，重点班 ${Math.round(hk * 100)}%`);
console.log(`✓ 活法：重点班 不上心 ${Math.round(rl * 100)}% / 一半一半 ${Math.round(rh * 100)}% / 专心 ${Math.round(rs * 100)}% / 专心比不上心多 ${gap.toFixed(1)} 点心智 / 搭伴再多 ${lift.toFixed(1)} / 五条路全通的只有 ${Math.round(all * 100)}%`);
