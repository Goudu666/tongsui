// 树：槐树 / 柳树 / 小树 × 春夏秋冬（tools/art/layers.py 的 TREES：画布、树高、冠半径都沿用）。
// 脚底在画布底边正中往上 4（世界 x = 宽/2，y = 高-4，z = Z_REF），引擎按 anchors 里的 h 缩放。
// 骨架（树干、枝杈）每种树一个种子，四季一样，换季不跳；冬天枝杈全露出来，上沿积一层雪。
// 冠子学样张（diorama_street.jpg）：一团团软软的圆球挤在一起，几种绿深浅错开。
import { Kit, rng, mixHex, ZREF } from './kit.js';

export const TREES = {
  // 种：[画布宽, 高, 树高, 冠半径]
  huai: [620, 700, 620, 175],
  willow: [640, 680, 580, 155],
  young: [300, 380, 320, 84],
};

const BARK = { huai: '#6A4E3E', willow: '#6E5644', young: '#7A5A44' };
const SNOW = '#F4F6FA';

// 各季的叶色：几种绿（或黄）随机落在每一团上
const LEAF = {
  spring: ['#86BE5E', '#9CCB68', '#6FAE55', '#A9D27A'],
  summer: ['#3F7D48', '#4C8A4A', '#5C9646', '#356E44'],
  autumn: ['#E3A43A', '#D7792F', '#CFA33E', '#E8BE4E', '#8C9A44'],
};
const WILLOW_LEAF = {
  spring: ['#B3D56E', '#C4DE7E', '#9CC85E'],
  summer: ['#5E9A48', '#6FA650', '#4E8A44'],
  autumn: ['#D9BC4A', '#C9A23A', '#B9B04E', '#E2C760'],
};

// 往上长的枝杈：每一节一根锥台，节点一个圆球补缝；th 是和竖直向上的夹角，ph 是朝镜头歪多少（弧度）
function grow(R, segs, p, th, ph, L, r, depth, o) {
  const d = [Math.sin(th) * Math.cos(ph), -Math.cos(th) * Math.cos(ph), Math.sin(ph)];
  const bend = R.u(-0.12, 0.12);
  const mid = [p[0] + d[0] * L * 0.5 + bend * L * Math.cos(th), p[1] + d[1] * L * 0.5 + bend * L * Math.sin(th) * 0.5, p[2] + d[2] * L * 0.5];
  const q = [p[0] + d[0] * L, p[1] + d[1] * L, p[2] + d[2] * L];
  const r1 = r * 0.72;
  segs.push({ a: p, b: mid, r0: r, r1: (r + r1) / 2, depth, th });
  segs.push({ a: mid, b: q, r0: (r + r1) / 2, r1, depth, th, tip: depth <= 0 });
  if (depth <= 0) return;
  const n = depth > 2 ? 2 : (R() < 0.5 ? 2 : 3);
  for (let k = 0; k < n; k++) {
    const s = (k % 2 ? 1 : -1);
    let nt = th + s * R.u(0.24, 0.58) + R.u(-0.12, 0.12);
    nt = nt * (o.lift ?? 0.9);  // 往上收一点（向光）
    const np = ph + R.u(-0.45, 0.45);
    grow(R, segs, q, nt, Math.max(-0.9, Math.min(0.9, np)), L * R.u(o.shrink?.[0] ?? 0.62, o.shrink?.[1] ?? 0.8), r1 * 0.86, depth - 1, o);
  }
}

function skeleton(kind) {
  const [Wd, Hd, h, r] = TREES[kind];
  const R = rng({ huai: 19, willow: 3, young: 7 }[kind]);
  const x = Wd / 2, base = Hd - 4, z = ZREF;
  const segs = [];
  const trunkH = h - r * (kind === 'willow' ? 2.2 : 1.95);
  const tr = { huai: 17, willow: 16, young: 5.2 }[kind];
  // 主干：三节，略弯；根上粗一圈
  const lean = { huai: 6, willow: -14, young: 2 }[kind];
  const pts = [[x, base, z], [x + lean * 0.3 + R.u(-3, 3), base - trunkH * 0.38, z + R.u(-4, 4)], [x + lean * 0.7, base - trunkH * 0.72, z + R.u(-6, 6)], [x + lean, base - trunkH, z]];
  const rs = [tr * 1.0, tr * 0.9, tr * 0.8, tr * 0.7];
  for (let i = 0; i < 3; i++) segs.push({ a: pts[i], b: pts[i + 1], r0: rs[i], r1: rs[i + 1], depth: 9, th: 0 });
  segs.push({ a: [x, base + 2, z], b: [x, base - tr * 1.6, z], r0: tr * 1.45, r1: tr * 0.98, depth: 9, th: 0 }); // 根脚
  const top = pts[3];
  const limbs = kind === 'young' ? [-0.52, 0.06, 0.56] : kind === 'willow' ? [-0.95, -0.42, 0.12, 0.6, 1.0] : [-0.84, -0.3, 0.26, 0.78];
  const depth = kind === 'young' ? 2 : 3;
  const L0 = r * (kind === 'willow' ? 0.62 : kind === 'young' ? 0.58 : 0.5);
  const o = kind === 'willow' ? { lift: 0.95, shrink: [0.6, 0.75] } : { lift: 0.86 };
  limbs.forEach((a, k) => {
    const ph = R.u(-0.5, 0.5) + (k % 2 ? 0.25 : -0.25);
    grow(R, segs, top, a + R.u(-0.1, 0.1), ph, L0 * R.u(0.9, 1.1), tr * 0.6, depth, o);
  });
  return { segs, x, base, z, h, r, R };
}

function drawBranches(kit, segs, bark, snow) {
  for (const s of segs) {
    const rr0 = Math.max(0.9, s.r0), rr1 = Math.max(0.7, s.r1);
    kit.cyl(s.a, s.b, rr0, rr1, bark, { seg: rr0 > 4 ? 12 : 7 });
    if (rr0 > 1.6) kit.ball(s.a[0], s.a[1], s.a[2], rr0 * 0.98, rr0 * 0.98, rr0 * 0.98, bark, { lo: rr0 < 4 });
  }
  if (!snow) return;
  // 雪：顺着粗一点、横一点的枝杈上沿，压扁的白团
  for (const s of segs) {
    if (s.r0 < 1.6) continue;
    const dx = s.b[0] - s.a[0], dy = s.b[1] - s.a[1];
    const L = Math.hypot(dx, dy);
    const flat = Math.abs(dx) / (L + 1e-6);  // 越横越积得住
    if (flat < 0.3 && s.depth < 9) continue;
    if (s.depth === 9 && flat < 0.3) continue;
    const n = Math.max(1, Math.round(L / Math.max(6, s.r0 * 2.2)));
    for (let i = 0; i < n; i++) {
      const t = (i + 0.5) / n;
      const r = s.r0 + (s.r1 - s.r0) * t;
      const x = s.a[0] + dx * t, y = s.a[1] + dy * t, z = s.a[2] + (s.b[2] - s.a[2]) * t;
      kit.ball(x, y - r * 0.8 - 0.8, z, Math.max(4.5, r * 1.5) * (0.6 + 0.4 * flat), Math.max(2.2, r * 0.6), Math.max(3.5, r * 1.1), snow, { lo: true, rot: [0, 0, Math.atan2(-dy, dx)] });
    }
  }
}

// 冠子：枝梢上一团一团的圆球，再往里填几团，免得透亮；pick 选颜色
function crown(kit, sk, season, kind) {
  const { x, base, h, r } = sk;
  const Rp = rng(101 + kind.length * 7);  // 每团多大、落在哪：四季一样
  const Rc = rng(303 + kind.length * 7 + season.charCodeAt(1));  // 颜色、花：每季自己的
  const cols = LEAF[season];
  // 冠子是个扁一点的椭球：表面上摆一圈大团（朝镜头那半边多），里头再塞几团，免得透亮
  const ax = r * 1.08, ay = r * 0.76, az = r * 0.62;
  const cy = base - h + ay + r * 0.06;
  const blobs = [];
  const big = kind === 'young' ? 0.5 : 0.42;
  const sparse = season === 'autumn' ? 0.86 : 1.0;
  const n = kind === 'young' ? 11 : 17;
  for (let i = 0; i < n; i++) {
    // 黄金角螺旋铺在前半个椭球上
    const t = (i + 0.5) / n, el = Math.asin(1 - 2 * t) * 0.92, az0 = i * 2.39996 + Rp.u(-0.2, 0.2);
    const dx = Math.cos(el) * Math.cos(az0), dy = -Math.sin(el), dz = Math.cos(el) * Math.sin(az0);
    const rr = r * Rp.u(big * 0.82, big * 1.12) * sparse * (dy > 0.5 ? 0.85 : 1);  // 底下的小一点
    const drop = Rp() > 0.8;
    if (season === 'autumn' && drop) continue;  // 秋天稀了，枝杈透出来
    blobs.push([x + dx * (ax - rr * 0.45), cy + dy * (ay - rr * 0.5), ZREF + dz * (az - rr * 0.3) * 0.9 + 6, rr]);
  }
  for (let i = 0; i < (kind === 'young' ? 2 : 4); i++) {
    const a = i / 4 * Math.PI * 2 + Rp.u(-0.3, 0.3);
    blobs.push([x + Math.cos(a) * r * 0.3, cy + Math.sin(a) * r * 0.2, ZREF - r * 0.15, r * Rp.u(0.45, 0.55) * sparse]);
  }
  // 别出画布：往冠子中心拉
  const [Wd] = TREES[kind];
  for (const b of blobs) {
    const lim = Wd / 2 - 14 - b[3] - 12;
    const dx = b[0] - x;
    if (Math.abs(dx) > lim) b[0] = x + Math.sign(dx) * lim;
    if (b[1] - b[3] < 8) b[1] = 8 + b[3];
  }
  // 上头的团亮一点、偏暖，底下的暗一点、偏青：冠子才有个圆的体积
  for (const b of blobs) {
    const c = cols[Math.floor(Rc() * cols.length)];
    const v = (b[1] - cy) / ay;
    const col = v > 0 ? mixHex(c, '#1E3A30', Math.min(0.32, v * 0.32)) : mixHex(c, '#FFF0B8', Math.min(0.14, -v * 0.14));
    kit.ball(b[0], b[1], b[2], b[3], b[3] * 0.9, b[3] * 0.85, kit.mat(col, { r: 0.62 }));
  }
  if (season === 'spring') {
    // 花：白里透粉的小团，挂在朝外（朝上、朝镜头）的那一面
    const pal = kind === 'young' ? ['#F6C9D2', '#F9DDE2', '#F2B3C2'] : ['#F7F1DC', '#F2E6C4', '#F6D9DC'];
    const bm = pal.map(c => kit.mat(c, { r: 0.5 }));
    const n = kind === 'young' ? 30 : 90;
    for (let i = 0; i < n; i++) {
      const b = blobs[Math.floor(Rc() * blobs.length)];
      const a = Rc.u(-Math.PI * 0.95, -Math.PI * 0.05), e = Rc.u(0.15, 0.95);
      const dir = [Math.cos(a) * Math.cos(e), Math.sin(a) * Math.cos(e) * 0.8, Math.sin(e)];
      const px = b[0] + dir[0] * b[3] * 1.0, py = b[1] + dir[1] * b[3] * 0.92, pz = b[2] + dir[2] * b[3] * 0.88;
      const m = bm[Math.floor(Rc() * bm.length)];
      const k = Rc.i(3, 5);
      for (let j = 0; j < k; j++) kit.ball(px + Rc.u(-9, 9), py + Rc.u(-6, 6) + j * 5, pz + Rc.u(0, 4), Rc.u(5.5, 8), undefined, undefined, m, { lo: true });
    }
  }
}

// 柳条：从枝上垂下来的细管子，挂一串叶子（压扁的小橄榄）
function willowStrands(kit, sk, season) {
  const { segs, base, r } = sk;
  const R = rng(55);   // 柳条怎么垂：四季一样
  const Rc = rng(77 + season.length);
  const winter = season === 'winter';
  const leafCols = winter ? null : WILLOW_LEAF[season];
  const lm = leafCols && leafCols.map(c => kit.mat(c, { r: 0.6 }));
  const twig = kit.mat(winter ? '#B39A62' : mixHex(leafCols[0], '#5A4A30', 0.45), { r: 0.7 });
  const hosts = segs.filter(s => s.depth <= 2);
  const per = { spring: 4, summer: 5, autumn: 3, winter: 3 }[season];
  for (const s of hosts) {
    for (let k = 0; k < per; k++) {
      const t = R.u(0.15, 1.0);
      const sx = s.a[0] + (s.b[0] - s.a[0]) * t, sy = s.a[1] + (s.b[1] - s.a[1]) * t, sz = s.a[2] + (s.b[2] - s.a[2]) * t;
      let L = R.u(r * 0.7, r * 1.9) * (0.7 + 0.3 * t);
      L = Math.min(L, base - sy - 40);
      if (L < 30) continue;
      const out = Math.sign(sx - sk.x || 1) * R.u(4, 14), sway = R.u(-6, 12);
      const pts = [];
      for (let j = 0; j <= 6; j++) {
        const u = j / 6;
        // 先往外、往上翘一点，再垂下来
        pts.push([sx + out * Math.sin(u * Math.PI * 0.6) + sway * u * u, sy - 8 * Math.sin(u * Math.PI) * (1 - u) + L * u * u * 0.35 + L * u * 0.65, sz + R.u(-2, 2) + u * 6]);
      }
      if (winter || season === 'autumn' && Rc() < 0.3) {
        kit.tube(pts, 1.1, twig, { taper: 0.5, seg: 4 });
        continue;
      }
      kit.tube(pts, 1.0, twig, { taper: 0.6, seg: 4 });
      // 叶子：顺着条子一片一片
      const m = lm[Math.floor(Rc() * lm.length)];
      const n = Math.floor(L / 9);
      for (let j = 1; j < n; j++) {
        const u = j / n;
        const i = Math.min(5, Math.floor(u * 6)), f = u * 6 - i;
        const p = pts[i].map((v, q) => v + (pts[i + 1][q] - v) * f);
        const sz2 = 1 - 0.45 * u;
        const side = j % 2 ? 1 : -1;
        kit.ball(p[0] + side * 2.5, p[1], p[2] + 1, 3.6 * sz2, 8.5 * sz2, 2.8 * sz2, m, { lo: true, rot: [0, 0, side * 0.35] });
      }
    }
  }
}

export function buildTree(kind, season) {
  const kit = new Kit();
  const sk = skeleton(kind);
  const bark = kit.mat(BARK[kind], { r: 0.85 });
  const winter = season === 'winter';
  const snow = winter ? kit.mat(SNOW, { r: 0.9 }) : null;
  // 叶子盖住的细枝不用画（省得从冠子里戳出来）：不是冬天，只画到第二级
  const segs = winter || kind === 'willow' ? sk.segs : sk.segs.filter(s => s.depth >= 1);
  drawBranches(kit, segs, bark, snow);
  if (kind === 'young') {
    // 小树：三根撑杆斜着顶住树干，绑一道麻绳
    const pole = kit.mat('#B48A5A', { r: 0.8 });
    const { x, base, z } = sk;
    const yb = base - sk.h * 0.42;
    for (const [dx, dz] of [[-46, -10], [44, -14], [6, 40]]) kit.cyl([x + dx, base, z + dz], [x + dx * 0.08, yb, z + dz * 0.08], 2.6, 2.2, pole, { seg: 8 });
    kit.cyl([x, yb + 6, z], [x, yb - 4, z], 6.2, 6.2, kit.mat('#D8C08A', { r: 0.9 }), { seg: 12 });
  }
  if (kind === 'willow') willowStrands(kit, sk, season);
  else if (!winter) crown(kit, sk, season, kind);
  const [Wd, Hd] = TREES[kind];
  return { kit, frame: { x0: 0, y0: 0, w: Wd, h: Hd } };
}
