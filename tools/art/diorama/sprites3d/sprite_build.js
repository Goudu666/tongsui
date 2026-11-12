// 精灵的显示列表 → 3D（和底图同一套斜投影、同一套材质：借 ../scene3d/build.js 的 Builder，只换「怎么把一笔笔归成一样东西」）。
//
// 老画法一样东西是「挖空 → 铺底色（可能几层网点叠印）→ 墨线勾边 → 脸上的花样」。这里先归堆（pass 1），再摆前后（pass 2）：
//   - 挖空开一样东西；和它一样大的色块是它的底色（叠印的几层相乘），落在它里头的色块、线、点、字是它脸上的东西；
//   - 后画的盖住先画的：和先画的东西叠着的，前脸往前挪（嵌在里头的是一层薄贴片，探出来的是厚的一块）；
//   - 人（街坊）：椭圆的头、手是球，头发、帽子贴着头的弧面长，胳膊腿（tube）是圆管，身子是圆鼓鼓的厚片；
//   - 家具：和底图的 PROPS 一样，按精灵给中心 z 和厚度（sprites3d/bake.py 的 HOME / STREET 表）。
import * as THREE from 'three';
import { TessellateModifier } from 'three/addons/modifiers/TessellateModifier.js';
import { Builder, K, KX, ZREF } from '../scene3d/build.js';

export { K, KX, ZREF };

const PAPER = [0xF2, 0xEA, 0xDB];
const INK = { ink: [0x3A, 0x30, 0x36], qing: [0x3A, 0x8E, 0x78], mei: [0xC2, 0x5B, 0x4B], paper: PAPER };
// 和 build.js 的 riso() 一个算法（那边没导出）
function riso(c, d) {
  const ink = INK[c] || INK.ink;
  d = Math.max(0, Math.min(1, d ?? 1));
  d = Math.min(1, Math.pow(d * (c === 'ink' ? 1.9 : 1.6), 0.9));
  return PAPER.map((p, i) => p * (1 - d * (1 - ink[i] / 255)));
}
const mul = (a, b) => a.map((v, i) => v * b[i] / 255);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ---------------------------------------------------------------- 几何小工具
function bbox(p) {
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (const [x, y] of p) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
}
const inside = (a, b, tol = 2) => a.x0 >= b.x0 - tol && a.x1 <= b.x1 + tol && a.y0 >= b.y0 - tol && a.y1 <= b.y1 + tol;
const same = (a, b, tol = 3) => Math.abs(a.x0 - b.x0) < tol && Math.abs(a.x1 - b.x1) < tol && Math.abs(a.y0 - b.y0) < tol && Math.abs(a.y1 - b.y1) < tol;
function pip(x, y, p) {
  let c = false;
  for (let i = 0, j = p.length - 1; i < p.length; j = i++) {
    const [xi, yi] = p[i], [xj, yj] = p[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
  }
  return c;
}
// 多边形里撒一把点（量「叠了多少」用）
function samples(p, n = 9) {
  const b = bbox(p), out = [];
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
    const x = b.x0 + b.w * (i + 0.5) / n, y = b.y0 + b.h * (j + 0.5) / n;
    if (p.length < 3 || pip(x, y, p)) out.push([x, y]);
  }
  if (!out.length) out.push([b.x0 + b.w / 2, b.y0 + b.h / 2]);
  return out;
}
function lineSamples(p) {
  const out = [];
  for (let i = 0; i < p.length - 1; i++) for (let k = 0; k < 4; k++) {
    const t = k / 4; out.push([p[i][0] + (p[i + 1][0] - p[i][0]) * t, p[i][1] + (p[i + 1][1] - p[i][1]) * t]);
  }
  out.push(p[p.length - 1]);
  return out;
}
// 椭圆（ell / circle_pts 画出来的）：认出来做成球
function asEllipse(p) {
  if (p.length < 10) return null;
  const b = bbox(p), cx = b.x0 + b.w / 2, cy = b.y0 + b.h / 2, rx = b.w / 2, ry = b.h / 2;
  if (rx < 0.8 || ry < 0.8) return null;
  for (const [x, y] of p) { const e = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2; if (Math.abs(e - 1) > 0.14) return null; }
  return { cx, cy, rx, ry };
}
const has = (o, n) => (o.t || []).some(t => t === n || t.startsWith(n));

export class SpriteBuilder extends Builder {
  // data: {ops, floors, cfg: {zc, d, mode: 'furniture' | 'figure' | 'flat', wood, glossy}}
  constructor(data, variant = 'toy') {
    super({ floors: data.floors || [0], width: 4000, anchors: {}, ops: data.ops }, variant);
    this.cfg = Object.assign({ zc: 60, d: 40, mode: 'furniture' }, data.cfg || {});
    this.fig = this.cfg.mode === 'figure';
  }

  // ---------------------------------------------------------------- pass 1：归堆
  group() {
    const objs = [], free = [];
    let cur = null, cleared = false;
    const holder = (b, tol = 2) => { for (let i = objs.length - 1; i >= 0; i--) if (inside(b, objs[i].b, tol)) return objs[i]; return null; };
    const isShadow = o => has(o, 'floor_shadow') || has(o, 'ground_shadow') ||
      (!cleared && o.k === 'fill' && o.c === 'ink' && (o.d ?? 1) <= 0.25 && !has(o, 'fig'));
    for (const o of this.d.ops) {
      if (o.k === 'call') continue;
      if (o.k === 'fill' && isShadow(o)) continue;
      if (o.k === 'clear') {
        const b = bbox(o.p);
        if (o.only) { const h = holder(b, 3); if (h) h.glare = true; continue; }
        cleared = true;
        cur = { p: o.p, b, fills: [], decals: [], lines: [], dots: [], texts: [], hatches: [], rings: [], t: o.t || [], cleared: true };
        objs.push(cur); continue;
      }
      if (o.k === 'tube') {
        cur = { tube: true, p: o.p, b: bbox(o.p), o, t: o.t || [], fills: [], decals: [], lines: [], dots: [], texts: [], hatches: [], rings: [] };
        objs.push(cur); continue;
      }
      if (o.k === 'fill') {
        const b = bbox(o.p);
        if (cur && !cur.tube && same(b, cur.b, 3)) { cur.fills.push(o); continue; }
        const h = holder(b, 2);
        if (h && !h.tube && b.w * b.h < h.b.w * h.b.h * 0.97) { h.decals.push(o); continue; }
        if (h && !h.tube) { h.fills.push(o); continue; }
        cur = { p: o.p, b, fills: [o], decals: [], lines: [], dots: [], texts: [], hatches: [], rings: [], t: o.t || [] };
        objs.push(cur); continue;
      }
      if (o.k === 'ring') {
        const b = bbox(o.p);
        if (o.filled) continue;
        if (objs.some(q => !q.tube && same(q.b, b, 5)) || objs.some(q => q.decals.some(f => same(bbox(f.p), b, 5)))) continue; // 勾边
        const h = holder(b, 2);
        (h ? h.rings : free).push(o); continue;
      }
      const b = bbox(o.p);
      const h = holder(b, o.k === 'text' ? 30 : 1.5);
      if (o.k === 'line') (h && !h.tube ? h.lines : free).push(o);
      else if (o.k === 'dot') (h && !h.tube ? h.dots : free).push(o);
      else if (o.k === 'text') (h ? h.texts : free).push(o);
      else if (o.k === 'hatch') { if (h) h.hatches.push(o); }
    }
    return { objs, free };
  }

  // ---------------------------------------------------------------- 颜色
  objColor(ob) {
    let col = PAPER.map(v => v * 0.97);
    for (const f of ob.fills) if (f.c !== 'paper') col = mul(col, riso(f.c, f.d));
    const inks = ob.fills.filter(f => f.c !== 'paper');
    // 家具：墨版铺的中间色是木头（和底图 build.js 的规矩一样）
    if (this.cfg.wood !== false && !this.fig && inks.length && inks.every(f => f.c === 'ink') && ob.b.w * ob.b.h > 260) {
      const d = inks.reduce((a, f) => a + (f.d ?? 1), 0);
      if (d >= 0.18 && d <= 0.8) col = [0x8E, 0x62, 0x44].map(v => v * (1.12 - d * 0.4));
    }
    return col;
  }

  // ---------------------------------------------------------------- pass 2：前后
  build() {
    const { objs, free } = this.group();
    this.placed = [];
    const C = this.cfg;
    for (const ob of objs) {
      if (ob.tube) { this.placeTube(ob); continue; }
      const custom = this.customObj(ob);
      if (custom) continue;
      const sm = samples(ob.p);
      // 底下压着谁、压了多少
      let front = -1e9, cover = 0, under = null;
      for (const u of this.placed) {
        let n = 0, f = -1e9;
        for (const [x, y] of sm) if (u.hit(x, y)) { n++; f = Math.max(f, u.front(x, y)); }
        const frac = n / sm.length;
        if (frac > 0.12 && f > front) { front = f; }
        if (frac > cover) { cover = frac; under = u; }
      }
      const minD = Math.min(ob.b.w, ob.b.h);
      const el = asEllipse(ob.p);
      const col = this.objColor(ob);
      const glossy = ob.glare || (C.glossy && ob.fills.some(f => f.c === 'ink' && (f.d ?? 1) >= 0.5));
      const mat = this.mat(col, glossy ? 'glass' : 'prop');
      let rec;
      if (this.fig) {
        const dd = clamp(minD * 0.55, 2.5, 16);
        if (el && (has(ob, 'fig.head') || has(ob, 'fig.hand') || has(ob, 'fig.shoe') || minD < 10) && !(under && under.dome && cover > 0.5)) {
          const rz = Math.min(el.rx, el.ry) * (has(ob, 'fig.shoe') ? 1.6 : 0.92);
          let zc = C.zc;
          if (front > -1e8) zc = Math.max(zc, front - rz * 0.35);
          rec = this.dome(el, zc, rz, mat);
        } else if (under && under.dome && cover > 0.45) {
          rec = this.shell(ob.p, under, 0.9, mat);
        } else {
          let z0 = C.zc - dd / 2, z1 = C.zc + dd / 2;
          if (front > -1e8) {
            if (cover > 0.9 && under && under.area > ob.b.w * ob.b.h * 1.2) { z0 = under.z1 - 1; z1 = under.z1 + 0.9; }
            else z1 = Math.max(z1, front + 1.2);
          }
          rec = this.puff(ob.p, z0, z1, mat);
        }
      } else {
        let z0 = C.zc - C.d / 2, z1 = C.zc + C.d / 2;
        const tz = C.tagz && Object.keys(C.tagz).find(k => has(ob, k));
        if (tz) {
          // 指定了前后的部件（书柜顶上立着的相框：薄薄一块靠着墙）
          [z0, z1] = C.tagz[tz];
          rec = this.flatRec(ob.p, z0, z1, this.slab(ob.p, z0, z1, mat));
        } else if (el && minD < 16) {
          // 小圆的（旋钮、扣子、花）：半个球
          const rz = Math.min(el.rx, el.ry) * 0.6;
          rec = this.dome(el, front > -1e8 ? front - rz * 0.2 : z1 - rz * 0.4, rz, mat);
        } else {
          if (front > -1e8) {
            if (cover > 0.88 && under && under.area > ob.b.w * ob.b.h * 1.15) {      // 嵌在先画的那样东西脸上：薄薄一层
              z0 = under.z1 - 1; z1 = under.z1 + clamp(minD * 0.05, 0.6, 2.5);
            } else z1 = Math.max(z1, front + clamp(minD * 0.3, 1.5, 10));
          }
          rec = this.flatRec(ob.p, z0, z1, this.slab(ob.p, z0, z1, mat));
        }
      }
      rec.ob = ob; rec.col = col; rec.area = ob.b.w * ob.b.h;
      this.placed.push(rec);
      this.dress(ob, rec);
    }
    for (const o of free) this.freeOp(o);
    return this.root;
  }

  // 记一样摆好的东西：hit(x,y) 点在不在它上面，front(x,y) 那一点它的前脸在哪
  flatRec(p, z0, z1, mesh) {
    const b = bbox(p);
    return { p, b, z0, z1, mesh, hit: (x, y) => x >= b.x0 && x <= b.x1 && y >= b.y0 && y <= b.y1 && pip(x, y, p), front: () => z1, surf: () => z1 };
  }

  dome(el, zc, rz, mat) {
    const g = new THREE.SphereGeometry(1, this.V.flat ? 10 : 28, this.V.flat ? 7 : 18);
    const me = this.add(g, mat);
    me.scale.set(el.rx, el.ry, rz); me.position.set(el.cx, -el.cy, zc);
    const surf = (x, y, grow = 0) => {
      const u = ((x - el.cx) / (el.rx + grow)) ** 2 + ((y - el.cy) / (el.ry + grow)) ** 2;
      return zc + (rz + grow * 0.6) * Math.sqrt(Math.max(0, 1 - u));
    };
    return {
      p: null, b: { x0: el.cx - el.rx, x1: el.cx + el.rx, y0: el.cy - el.ry, y1: el.cy + el.ry, w: el.rx * 2, h: el.ry * 2 }, dome: true, el, zc, rz,
      z0: zc - rz, z1: zc + rz, mesh: me,
      hit: (x, y) => ((x - el.cx) / el.rx) ** 2 + ((y - el.cy) / el.ry) ** 2 <= 1,
      front: (x, y) => surf(x, y), surf,
    };
  }

  // 圆鼓鼓的一片（人身上的东西）：挤出来，倒一个大圆角，轮廓不长胖
  puff(p, z0, z1, mat) {
    const d = Math.max(z1 - z0, 0.6);
    const minD = Math.min(bbox(p).w, bbox(p).h);
    const bev = this.V.bevel ? Math.min(d * 0.42, minD * 0.3, 5) : 0;
    const sh = new THREE.Shape(p.map(([x, y]) => new THREE.Vector2(x, -y)));
    const geo = new THREE.ExtrudeGeometry(sh, { depth: Math.max(d - bev * 2, 0.2), bevelEnabled: bev > 0.2, bevelSize: bev, bevelThickness: bev, bevelOffset: -bev, bevelSegments: 4, curveSegments: 8 });
    const me = this.add(geo, mat);
    me.position.z = z0 + bev;
    return this.flatRec(p, z0, z1, me);
  }

  // 贴着球面长的一层（头发、帽子、腮红）：三角面细分，每个顶点抬到球面外 off
  shell(p, dome, off, mat) {
    const sh = new THREE.Shape(p.map(([x, y]) => new THREE.Vector2(x, -y)));
    let geo = new THREE.ShapeGeometry(sh, 8);
    geo = new TessellateModifier(1.4, 8).modify(geo);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), y = -pos.getY(i);
      pos.setZ(i, dome.surf(x, y, 3.5) + off);
    }
    geo.computeVertexNormals();
    const m = mat.clone(); m.side = THREE.DoubleSide;
    const me = this.add(geo, m);
    const b = bbox(p);
    return { p, b, z0: dome.zc, z1: dome.z1 + off, mesh: me, dome: true, el: dome.el, zc: dome.zc, rz: dome.rz + off,
      hit: (x, y) => pip(x, y, p), front: (x, y) => dome.surf(x, y, 3.5) + off, surf: (x, y, g = 0) => dome.surf(x, y, 3.5 + g) + off };
  }

  placeTube(ob) {
    const o = ob.o;
    const r = this.fig || has(ob, 'fig') || has(ob, 'rider') ? Math.max(1.2, (o.w + 2 * (o.lw || 0)) / 2 * 0.92) : Math.max(1.0, (o.w + (o.lw || 0)) / 2);
    let col = o.c === 'paper' ? PAPER.map(v => v * 0.97) : riso(o.c, o.d);
    if (o.shade) col = mul(col, riso('ink', o.shade));
    const sm = lineSamples(o.p);
    let front = -1e9;
    for (const u of this.placed) {
      let n = 0, f = -1e9;
      for (const [x, y] of sm) if (u.hit(x, y)) { n++; f = Math.max(f, u.front(x, y)); }
      if (n / sm.length > 0.25) front = Math.max(front, f);
    }
    const z = front > -1e8 ? Math.max(this.cfg.zc, front - r * 0.3) : this.cfg.zc;
    const mat = this.mat(col, 'prop');
    const pts = o.p.length > 2 ? o.p : o.p;
    const me = this.rod(pts, r, z, mat);
    const b = bbox(o.p);
    const rec = {
      p: null, b, z0: z - r, z1: z + r, mesh: me, area: b.w * b.h, tube: true,
      hit: (x, y) => { for (let i = 0; i < o.p.length - 1; i++) if (segDist(x, y, o.p[i], o.p[i + 1]) <= r) return true; return false; },
      front: () => z + r * 0.8, surf: () => z + r,
    };
    this.placed.push(rec);
  }

  // ---------------------------------------------------------------- 脸上的东西
  surfZ(rec, x, y) { return rec.surf ? rec.surf(x, y) : rec.z1; }

  dress(ob, rec) {
    let k = 0;
    for (const f of ob.decals) {
      k++;
      const col = mul(rec.col, riso(f.c, f.d));
      const glass = f.c === 'qing' && (f.d ?? 1) < 0.35 && ob.glare;
      const mat = this.mat(col, glass ? 'glass' : 'prop');
      if (rec.dome) { this.shell(f.p, rec, 0.25 + k * 0.05, mat); continue; }
      const b = bbox(f.p);
      const t = clamp(Math.min(b.w, b.h) * 0.06, 0.35, 1.6);
      const z = rec.z1 + 0.05 + (k % 40) * 0.03;
      this.slab(f.p, z, z + t, mat);
    }
    for (const h of ob.hatches) this.hatch(h, rec);
    for (const l of ob.lines) {
      const w = l.w || 1;
      const r = Math.max(0.45, w * (w < 2 ? 0.42 : 0.5));
      const col = this.mat(riso(l.c, Math.max(l.d ?? 1, 0.5)), 'prop');
      if (rec.dome) this.rod3(l.p.map(([x, y]) => [x, y, this.surfZ(rec, x, y) + r * 0.3]), r, col);
      else this.rod(l.p, r, rec.z1 + r * 0.35, col);
    }
    for (const d of ob.dots) {
      const r = Math.max(0.7, d.w || 1.5);
      const [x, y] = d.p[0];
      const z = rec.dome ? this.surfZ(rec, x, y) : rec.z1;
      const me = this.add(new THREE.SphereGeometry(r, 12, 8), this.mat(riso(d.c, d.d ?? 1), d.c === 'ink' ? 'metal' : 'prop'));
      me.position.set(x, -y, z + r * (rec.dome ? 0.1 : 0.25)); me.scale.z = 0.6;
    }
    for (const t of ob.texts) {
      const color = t.knock ? '#FFF6E2' : `rgb(${riso(t.c, t.d ?? 1).map(v => v | 0).join(',')})`;
      this.text(t, rec.z1 + 2.0, color);      // 字压在贴片（黑板、告示）上面：贴片最厚 1.6
    }
    for (const g of ob.rings) {
      const w = Math.max(0.5, (g.w || 1.5) * 0.45);
      const col = this.mat(riso(g.c, Math.max(g.d ?? 1, 0.6)), 'prop');
      const p = g.p.concat([g.p[0]]);
      if (rec.dome) this.rod3(p.map(([x, y]) => [x, y, this.surfZ(rec, x, y) + w * 0.3]), w, col);
      else this.rod(p, w, rec.z1 + w * 0.4, col);
    }
  }

  // 排线：一根根细棍，裁在多边形里（钢丝床的网、收音机的喇叭布）
  hatch(h, rec) {
    const b = bbox(h.p), a = (h.ang ?? 45) * Math.PI / 180, gap = h.gap || 8;
    const dx = Math.cos(a), dy = Math.sin(a), nx = -dy, ny = dx;
    const cx = b.x0 + b.w / 2, cy = b.y0 + b.h / 2, R = Math.hypot(b.w, b.h) / 2 + gap;
    const r = Math.max(0.35, (h.w || 1) * 0.4);
    const mat = this.mat(riso(h.c, Math.max(h.d ?? 1, 0.5)), 'metal');
    for (let k = -R; k <= R; k += gap) {
      const pts = [];
      const N = Math.ceil(2 * R / 0.8);
      let run = null;
      for (let i = 0; i <= N; i++) {
        const t = -R + i * 0.8, x = cx + nx * k + dx * t, y = cy + ny * k + dy * t;
        const inn = pip(x, y, h.p);
        if (inn && !run) run = [[x, y]];
        else if (inn) run[1] = [x, y];
        if ((!inn || i === N) && run) { if (run.length === 2) pts.push(run); run = null; }
      }
      for (const s of pts) this.rod(s, r, rec.z1 + r * 0.5, mat);
    }
  }

  rod3(pts, r, mat) {
    if (pts.length < 2) return;
    const v = pts.map(([x, y, z]) => new THREE.Vector3(x, -y, z));
    const curve = pts.length > 2 ? new THREE.CatmullRomCurve3(v) : new THREE.LineCurve3(v[0], v[1]);
    const g = new THREE.TubeGeometry(curve, Math.min(48, pts.length * 3), r, 6, false);
    this.add(g, mat);
    for (const e of [v[0], v[v.length - 1]]) { const s = this.add(new THREE.SphereGeometry(r, 8, 6), mat); s.position.copy(e); }
  }

  // 不挨着任何东西的线、点、字：摆在这样东西的中线上（天线、电线、钟摆……）
  freeOp(o) {
    const zc = this.cfg.zc;
    // 落在哪样东西前面：取盖着它的那样东西的前脸
    const at = (x, y) => { let z = -1e9; for (const u of this.placed) if (u.hit(x, y)) z = Math.max(z, u.front(x, y)); return z; };
    if (o.k === 'line') {
      const w = o.w || 1;
      if ((o.d ?? 1) < 0.3 && w < 1.2) return;
      const r = Math.max(0.5, w * 0.5);
      const col = this.mat(riso(o.c, Math.max(o.d ?? 1, 0.55)), o.c === 'ink' && w >= 2.4 ? 'metal' : 'prop');
      const zs = o.p.map(([x, y]) => at(x, y));
      if (zs.some(z => z > -1e8)) this.rod3(o.p.map(([x, y], i) => [x, y, Math.max(zc, (zs[i] > -1e8 ? zs[i] : zc) + r * 0.4)]), r, col);
      else this.rod(o.p, r, zc, col);
    } else if (o.k === 'dot') {
      const r = Math.max(0.8, o.w || 1.5), [x, y] = o.p[0];
      const z = at(x, y);
      const me = this.add(new THREE.SphereGeometry(r, 12, 8), this.mat(riso(o.c, o.d ?? 1), o.c === 'ink' ? 'metal' : 'prop'));
      me.position.set(x, -y, z > -1e8 ? z + r * 0.3 : zc);
    } else if (o.k === 'text') {
      const [x, y] = o.p[0]; const z = at(x, y);
      const color = o.knock ? '#FFF6E2' : `rgb(${riso(o.c, o.d ?? 1).map(v => v | 0).join(',')})`;
      this.text(o, (z > -1e8 ? z : zc) + 2.0, color);
    } else if (o.k === 'ring') {
      const w = Math.max(0.6, (o.w || 1.5) * 0.5);
      const col = this.mat(riso(o.c, Math.max(o.d ?? 1, 0.6)), 'prop');
      this.rod(o.p.concat([o.p[0]]), w, zc, col);
    }
  }

  // ---------------------------------------------------------------- 认得的东西
  customObj(ob) {
    // 车轮（_wheel）：前后两只轮胎，中间不连着
    if (has(ob, '_wheel') && ob.cleared) {
      const el = asEllipse(ob.p); if (!el) return false;
      const C = this.cfg, r = el.rx, th = 9;
      const tire = this.mat([0x3A, 0x34, 0x38], 'prop'), hub = this.mat([0xD8, 0xD2, 0xC8], 'metal');
      for (const zf of [C.zc + C.d / 2 - th / 2 + 2, C.zc - C.d / 2 + th / 2 - 2]) {
        const g = new THREE.TorusGeometry(r * 0.72, r * 0.3, 10, 28);
        const me = this.add(g, tire); me.position.set(el.cx, -el.cy, zf);
        const h = this.add(new THREE.CylinderGeometry(r * 0.46, r * 0.46, th * 0.7, 20), hub);
        h.rotation.x = Math.PI / 2; h.position.set(el.cx, -el.cy, zf + 0.5);
      }
      const rec = this.flatRec(ob.p, C.zc - C.d / 2, C.zc + C.d / 2 + 2, null);
      rec.col = [0x3A, 0x34, 0x38]; rec.area = ob.b.w * ob.b.h; rec.ob = ob;
      rec.hit = () => false;
      this.placed.push(rec);
      ob.decals = []; ob.dots = [];
      return true;
    }
    // 自行车的轮子（_cycle / _bike 里没挖空的圆）：一圈细轮胎
    if ((has(ob, '_cycle') || has(ob, '_bike')) && !ob.cleared) {
      const el = asEllipse(ob.p); if (!el || el.rx < 8) return false;
      const me = this.add(new THREE.TorusGeometry(el.rx - 1.2, 1.5, 8, 36), this.mat([0x40, 0x3A, 0x3E], 'prop'));
      me.position.set(el.cx, -el.cy, this.cfg.zc);
      // 辐条：细的十字
      const sp = this.mat([0xB8, 0xB4, 0xB0], 'metal');
      for (let a = 0; a < 4; a++) {
        const t = a * Math.PI / 4, R = el.rx - 2;
        this.rod([[el.cx - R * Math.cos(t), el.cy - R * Math.sin(t)], [el.cx + R * Math.cos(t), el.cy + R * Math.sin(t)]], 0.35, this.cfg.zc, sp);
      }
      return true;
    }
    return false;
  }
}

function segDist(x, y, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1], L = dx * dx + dy * dy;
  const t = L ? clamp(((x - a[0]) * dx + (y - a[1]) * dy) / L, 0, 1) : 0;
  return Math.hypot(x - a[0] - t * dx, y - a[1] - t * dy);
}

// 有的精灵整个是「特制」的：地板革（一条贴着地的人字纹）
export function floorCover(builder, x0, x1, y, z0, z1) {
  const c = document.createElement('canvas'); c.width = 256; c.height = 256; const g = c.getContext('2d');
  g.fillStyle = '#7E4A3A'; g.fillRect(0, 0, 256, 256);
  // 人字纹：一格往左斜一格往右斜
  for (let r = 0; r < 8; r++) for (let k = 0; k < 8; k++) {
    const x = k * 32, yy = r * 32, v = 0.9 + ((r * 7 + k * 3) % 5) * 0.04;
    g.fillStyle = `rgb(${0xA4 * v | 0},${0x62 * v | 0},${0x4A * v | 0})`;
    g.save(); g.translate(x + 16, yy + 16); g.rotate((k + r) % 2 ? Math.PI / 4 : -Math.PI / 4); g.fillRect(-20, -6, 40, 12); g.restore();
  }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace;
  t.repeat.set((x1 - x0) / 64, (z1 - z0) / 64);
  const m = new THREE.MeshStandardMaterial({ map: t, roughness: 0.55, metalness: 0.0 });
  const geo = new THREE.BoxGeometry(x1 - x0, 1.2, z1 - z0);
  const me = builder.add(geo, m, false);
  me.position.set((x0 + x1) / 2, -(y - 0.6), (z0 + z1) / 2);
  // 前沿一道压条
  const e = builder.add(new THREE.BoxGeometry(x1 - x0, 1.6, 2.5), builder.mat([0x8A, 0x5A, 0x40], 'prop'), false);
  e.position.set((x0 + x1) / 2, -(y - 0.8), z1);
  return me;
}
