// 把 record.py 录下来的显示列表搭成 3D（伪 3D：斜投影正交，见 ../README.md）。
// 老画法是一笔一笔「先挖空再上色」画的：每次挖空（clear）就是一样实的东西开始了，后面落在它里头的色块是它脸上的花样。
// 认得名字的东西（窗、门、招牌、桌椅、地面、楼板、剖开的墙……）按名字搭；不认得的按大小和离地多高猜它是靠墙的还是立在地上的。
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';

export const K = 0.28, KX = 0.10, ZREF = 120;

// ---------------------------------------------------------------- 颜色
const PAPER = [0xF2, 0xEA, 0xDB];
const INK = { ink: [0x3A, 0x30, 0x36], qing: [0x3A, 0x8E, 0x78], mei: [0xC2, 0x5B, 0x4B], paper: PAPER };
function riso(c, d) {
  const ink = INK[c] || INK.ink;
  d = Math.max(0, Math.min(1, d ?? 1));
  // 孔版的淡网点在纸上是「一层薄色」，搭成实物要压得实一点，不然满眼都是灰白
  d = Math.min(1, Math.pow(d * (c === 'ink' ? 1.9 : 1.6), 0.9));
  return PAPER.map((p, i) => p * (1 - d * (1 - ink[i] / 255)));
}
function sat(rgb, s, v = 1) {
  const m = (rgb[0] + rgb[1] + rgb[2]) / 3;
  return rgb.map(x => Math.max(0, Math.min(255, (m + (x - m) * s) * v)));
}
const css = c => `rgb(${c.map(x => x | 0).join(',')})`;

// ---------------------------------------------------------------- 质感
export const VARIANTS = {
  toy: { round: 0.14, roughness: 0.5, wallRough: 0.92, s: 1.08, v: 1.0, bevel: true, flat: false, noise: 0.05, metal: 0.05 },
  clay: { round: 0.3, roughness: 0.9, wallRough: 0.97, s: 0.82, v: 1.08, bevel: true, flat: false, noise: 0.16, metal: 0.0, bump: true },
  lowpoly: { round: 0, roughness: 0.85, wallRough: 0.9, s: 1.22, v: 1.03, bevel: false, flat: true, noise: 0.0, metal: 0.0 },
};

function noiseTex(amt, seed = 7, size = 128) {
  const c = document.createElement('canvas'); c.width = c.height = size; const x = c.getContext('2d');
  x.fillStyle = '#808080'; x.fillRect(0, 0, size, size);
  let s = seed; const r = () => (s = (s * 16807) % 2147483647) / 2147483647;
  for (let k = 0; k < size * 7; k++) { const v = 128 + (r() - 0.5) * 255 * amt * 4; x.fillStyle = `rgba(${v},${v},${v},0.6)`; x.fillRect(r() * size, r() * size, 1 + r() * 4, 1 + r() * 4); }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; return t;
}
function brickTex(base) {
  const c = document.createElement('canvas'); c.width = 256; c.height = 256; const x = c.getContext('2d');
  x.fillStyle = css(base.map(v => v * 0.72)); x.fillRect(0, 0, 256, 256);
  let s = 3; const r = () => (s = (s * 16807) % 2147483647) / 2147483647;
  for (let row = 0; row < 16; row++) for (let k = -1; k < 5; k++) {
    const bx = k * 64 + (row % 2) * 32, by = row * 16, v = 1 + (r() - 0.5) * 0.16;
    x.fillStyle = css(base.map(c => Math.min(255, c * v))); x.fillRect(bx + 2, by + 2, 60, 12);
  }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; return t;
}

// ---------------------------------------------------------------- 几何
function bbox(p) {
  let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (const [x, y] of p) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
}
function isRect(p) {
  if (p.length !== 4) return false;
  const b = bbox(p);
  return p.every(([x, y]) => (Math.abs(x - b.x0) < 0.6 || Math.abs(x - b.x1) < 0.6) && (Math.abs(y - b.y0) < 0.6 || Math.abs(y - b.y1) < 0.6));
}
const inside = (a, b, tol = 4) => a.x0 >= b.x0 - tol && a.x1 <= b.x1 + tol && a.y0 >= b.y0 - tol && a.y1 <= b.y1 + tol;
const same = (a, b, tol = 5) => Math.abs(a.x0 - b.x0) < tol && Math.abs(a.x1 - b.x1) < tol && Math.abs(a.y0 - b.y0) < tol && Math.abs(a.y1 - b.y1) < tol;

export class Builder {
  constructor(data, variant = 'toy') {
    this.d = data; this.V = VARIANTS[variant]; this.variant = variant;
    this.root = new THREE.Group();
    const M = new THREE.Matrix4();
    // three 坐标：(x, -y, z)。斜投影：近的往下（three 里是往 -y）、往右挪一点
    M.set(1, 0, KX, -KX * ZREF,
      0, 1, -K, K * ZREF,
      0, 0, 1, 0,
      0, 0, 0, 1);
    this.root.matrixAutoUpdate = false; this.root.matrix.copy(M);
    this.mats = new Map();
    this.noise = this.V.noise ? noiseTex(this.V.noise) : null;
    this.floors = data.floors.slice().sort((a, b) => a - b);
    this.lights = [];
  }

  floorOf(y) { // 东西的脚落在哪一层地上
    let best = this.floors[this.floors.length - 1];
    for (const f of this.floors) if (f >= y - 8) { best = f; break; }
    return best;
  }

  mat(rgb, kind = 'prop', opt = {}) {
    const V = this.V;
    let c = sat(rgb, V.s, V.v);
    const key = c.map(v => v | 0).join(',') + kind + (opt.emissive || '') + (opt.brick ? 'b' : '');
    if (this.mats.has(key)) return this.mats.get(key);
    const p = { color: new THREE.Color(css(c)), roughness: kind === 'wall' ? V.wallRough : V.roughness, metalness: V.metal, flatShading: V.flat };
    if (kind === 'glass') Object.assign(p, { roughness: 0.12, metalness: 0.25 });
    if (kind === 'metal') Object.assign(p, { roughness: 0.4, metalness: 0.45 });
    if (opt.emissive) Object.assign(p, { emissive: new THREE.Color(opt.emissive), emissiveIntensity: opt.ei ?? 1.2 });
    if (opt.brick) { p.map = brickTex(c); p.color = new THREE.Color('#fff'); }
    if (this.noise && kind !== 'glass') { p.roughnessMap = this.noise; if (V.bump) { p.bumpMap = this.noise; p.bumpScale = 3.0; } }
    const m = new THREE.MeshStandardMaterial(p);
    this.mats.set(key, m); return m;
  }

  add(geo, mat, cast = true) {
    const me = new THREE.Mesh(geo, mat); me.castShadow = cast; me.receiveShadow = true; this.root.add(me); return me;
  }

  // 一个立着的块：x/y 是世界坐标的框，z0~z1 是前后
  box(b, z0, z1, mat, round = null) {
    const w = Math.max(b.w, 0.5), h = Math.max(b.h, 0.5), d = Math.max(z1 - z0, 0.5);
    const r = round ?? Math.min(6, Math.min(w, h, d) * this.V.round);
    const geo = (r > 0.3 && this.V.bevel) ? new RoundedBoxGeometry(w, h, d, 2, r) : new THREE.BoxGeometry(w, h, d);
    const me = this.add(geo, mat);
    me.position.set(b.x0 + w / 2, -(b.y0 + h / 2), z0 + d / 2);
    return me;
  }

  slab(p, z0, z1, mat) {
    if (isRect(p)) return this.box(bbox(p), z0, z1, mat);
    const sh = new THREE.Shape(p.map(([x, y]) => new THREE.Vector2(x, -y)));
    const d = Math.max(z1 - z0, 0.5);
    const bev = this.V.bevel ? Math.min(2.5, d * 0.25) : 0;
    const geo = new THREE.ExtrudeGeometry(sh, { depth: Math.max(d - bev * 2, 0.2), bevelEnabled: bev > 0, bevelSize: bev, bevelThickness: bev, bevelSegments: 2, curveSegments: 6 });
    const me = this.add(geo, mat);
    me.position.z = z0 + bev;
    return me;
  }

  rod(pts, r, z, mat) {
    if (pts.length > 2) {
      const curve = new THREE.CatmullRomCurve3(pts.map(([x, y]) => new THREE.Vector3(x, -y, z)));
      return this.add(new THREE.TubeGeometry(curve, Math.min(64, pts.length * 3), r, 6, false), mat);
    }
    const [a, b] = pts; const A = new THREE.Vector3(a[0], -a[1], z), B = new THREE.Vector3(b[0], -b[1], z);
    const L = A.distanceTo(B); if (L < 0.5) return null;
    const geo = new THREE.CapsuleGeometry(r, L, 2, this.V.flat ? 5 : 8);
    const me = this.add(geo, mat);
    me.position.copy(A).add(B).multiplyScalar(0.5);
    me.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), B.clone().sub(A).normalize());
    return me;
  }

  text(o, z, color) {
    const S = 4, size = o.size * S, s = o.s;
    const c = document.createElement('canvas'); const x = c.getContext('2d');
    x.font = `900 ${size}px "Noto Sans SC", sans-serif`;
    let w, h;
    if (o.v) { w = size * 1.3; h = size * 1.1 * s.length; } else { w = x.measureText(s).width + 8; h = size * 1.3; }
    c.width = Math.ceil(w); c.height = Math.ceil(h);
    x.font = `900 ${size}px "Noto Sans SC", sans-serif`; x.fillStyle = color; x.textAlign = 'center'; x.textBaseline = 'middle';
    if (o.v) [...s].forEach((ch, i) => x.fillText(ch, w / 2, size * 1.1 * (i + 0.5)));
    else x.fillText(s, w / 2, h / 2 + size * 0.04);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
    const m = new THREE.MeshStandardMaterial({ map: t, transparent: true, roughness: 0.6, alphaTest: 0.3 });
    const me = this.add(new THREE.PlaneGeometry(w / S, h / S), m, false);
    me.position.set(o.p[0][0], -o.p[0][1], z);
    return me;
  }

  // ---------------------------------------------------------------- 主流程
  build() {
    const ops = this.d.ops;
    const calls = new Map();
    for (const o of ops) if (o.k === 'call') calls.set(o.id, o);
    this.calls = calls;
    let cur = null;        // 当前这样东西（最近一次挖空）
    const objs = [];
    let order = 0;
    const outlines = [];   // 已经有的色块框，用来认出「描边」
    for (const o of ops) {
      if (o.k === 'call') continue;
      order++;
      const t = o.t || [];
      if (t.includes('sky') || t.includes('skyline')) continue;
      const ctx = this.context(o);
      if (ctx && ctx.custom) { if (!ctx.done) { ctx.done = true; this.custom(ctx); } continue; }
      if (o.k === 'clear') {
        if (o.only) continue;
        cur = { b: bbox(o.p), p: o.p, body: null, order, ctx, z0: 0, z1: 0 };
        objs.push(cur);
        continue;
      }
      if (o.k === 'fill') {
        const b = bbox(o.p);
        outlines.push(b);
        if (this.skipFill(o, ctx)) continue;
        if (cur && cur.flat && inside(b, cur.b, 2)) {                    // 平铺的东西上头再画的：地上的水洼、地砖跟着躺平；水面上的波纹靠法线图
          if (cur.flat === 'ground' && b.w * b.h > 200) this.flatPoly(o.p, cur.floor, 0.5 + (order % 40) * 0.05, this.mat(this.colorOf(o), o.c === 'qing' ? 'glass' : 'wall'));
          continue;
        }
        if (cur && !cur.body && same(b, cur.b, 3)) { cur.body = o; this.placeObj(cur, o); continue; }
        if (cur && cur.body && cur.mesh && cur.col && same(b, cur.b, 3)) { // 同一块又压一版色：孔版叠印就是相乘
          cur.col = cur.col.map((v, i) => v * this.colorOf(o)[i] / 255 * 1.08);
          cur.mesh.material = this.mat(cur.col, cur.kind); continue;
        }
        if (cur && cur.body && inside(b, cur.b, 2) && b.w * b.h < cur.b.w * cur.b.h * 0.98) { this.decal(cur, o, order); continue; }
        if (cur && !cur.body && inside(b, cur.b, 2)) { // 挖空了但底色没铺满：拿它当身子
          cur.body = { k: 'fill', p: cur.p, c: 'paper', d: 1, t: o.t, g: o.g }; this.placeObj(cur, cur.body); this.decal(cur, o, order); continue;
        }
        const ob = { b, p: o.p, body: o, order, ctx };
        this.placeObj(ob, o); cur = ob; continue;
      }
      if (o.k === 'hatch') { // 排线压着的一大块：胡同口、门洞，往暗里压
        const hb = bbox(o.p);
        if (cur && cur.mesh && cur.col && same(hb, cur.b, 8) && (o.c === 'ink')) {
          // 门洞、胡同口（暗的方块）压成黑洞；石头、草垛这些只压暗一点，留着体积
          cur.col = cur.dark && isRect(cur.p) ? [0x34, 0x2B, 0x31] : cur.col.map(v => v * 0.74);
          cur.mesh.material = this.mat(cur.col, cur.kind);
        }
        continue;
      }
      if (o.k === 'bricks') { if (cur && cur.mesh && inside(bbox(o.p), cur.b, 30)) this.brickify(cur); continue; }
      if (o.k === 'ring') {
        const b = bbox(o.p);
        if (o.filled || outlines.some(q => same(q, b, 6))) continue;     // 描边
        if (cur && cur.flat && inside(b, cur.b, 6)) continue;
        if (cur && cur.body && same(b, cur.b, 6)) continue;
        this.frame(o, b, cur, ctx); continue;
      }
      if (o.k === 'line') { this.line(o, cur, ctx); continue; }
      if (o.k === 'dot') { if (cur && cur.flat && inside(bbox(o.p), cur.b, 4)) continue; this.dot(o, cur, ctx); continue; }
      if (o.k === 'text') {
        const lowest = this.floors[this.floors.length - 1];
        if ((cur && cur.flat === 'ground' && inside(bbox(o.p), cur.b, 4)) || (!(ctx && (ctx.prop || ctx.wall)) && o.p[0][1] > lowest + 4)) { this.flatText(o, lowest); continue; }
        this.textOp(o, cur); continue;
      }
    }
    // 没铺底色的挖空（比如价钱牌、告示栏的格子）：给一块浅色板
    for (const ob of objs) if (!ob.body && ob.b.w * ob.b.h > 30 && !(ob.ctx && ob.ctx.custom)) {
      ob.body = { k: 'fill', p: ob.p, c: 'paper', d: 1, t: [] }; this.placeObj(ob, ob.body);
    }
    return this.root;
  }

  // 这一笔属于哪个认得的东西（取最外层认得的那个）
  context(o) {
    const t = o.t || [], g = o.g || [];
    for (let i = 0; i < t.length; i++) {
      const n = t[i];
      if (CUSTOM.has(n)) {
        const id = g[i];
        this._ctx = this._ctx || new Map();
        if (!this._ctx.has(id)) this._ctx.set(id, { custom: true, name: n, call: this.calls.get(id) });
        return this._ctx.get(id);
      }
    }
    for (let i = 0; i < t.length; i++) if (PROPS[t[i]]) return { name: t[i], prop: PROPS[t[i]], id: g[i], call: this.calls.get(g[i]) };
    for (let i = t.length - 1; i >= 0; i--) if (WALLISH[t[i]]) return { name: t[i], wall: WALLISH[t[i]], id: g[i], call: this.calls.get(g[i]) };
    return null;
  }

  skipFill(o, ctx) {
    const d = o.d ?? 1;
    if (ctx && (ctx.name === 'lamp' || ctx.name === 'bulb') && o.c === 'mei' && d < 0.2 && bbox(o.p).w > 40) return true;   // 灯底下画的光：3D 里有真光
    if (o.c === 'ink' && d < 0.075) return true;                              // 淡墨的假影子
    return false;
  }

  colorOf(o) {
    if (o.c === 'paper') return PAPER.map(v => v * 0.97);
    // 街上一层的门脸里头：淡墨铺的一大片是铺子里，暗一点、暖一点，才像敞着的门脸
    const t = o.t || [];
    if (o.c === 'ink' && (o.d ?? 1) <= 0.12 && t[t.length - 1] === 'draw_street' && bbox(o.p).h > 180) return [0xB0, 0x94, 0x7C];
    return riso(o.c, o.d);
  }

  // 一样东西放在多前、多厚
  placeObj(ob, o) {
    const b = ob.b, ctx = ob.ctx;
    const floor = this.floorOf(b.y1);
    const onFloor = Math.abs(b.y1 - floor) < 26;
    let z0, z1, kind = 'prop';
    let col = this.colorOf(o);
    const dark = o.c === 'ink' && (o.d ?? 1) >= 0.45;
    ob.dark = dark;
    // 不认得名字、又宽又扁的一大片青：湖、池塘。是躺在地上的水面，不是立着的一块板
    if (!ctx && o.c === 'qing' && b.w > 600 && b.h < b.w * 0.3 && floor - b.y1 < 90 && floor - b.y1 >= 0) { this.flatWater(ob, o, floor); return; }
    // 最底下那层地面以下的一大片（沙滩、礁石滩、田、栈桥的石板）：老画里是俯着看的地面，搭成往前铺开的一块平地
    const lowest = this.floors[this.floors.length - 1];
    if (!ctx && b.y0 >= lowest - 6 && b.h > 120 && b.w > 150) {
      if (o.c === 'ink' && (o.d ?? 1) >= 0.3) col = [0x8C, 0x82, 0x7A].map(v => v * (1.12 - (o.d ?? 1) * 0.45));
      ob.col = col; ob.kind = 'wall'; ob.flat = 'ground'; ob.floor = lowest;
      ob.mesh = this.flatPoly(o.p, lowest, 0.3 + (ob.order % 40) * 0.01, this.mat(col, 'wall'), true);
      ob.z0 = ob.z1 = 0; return;
    }
    // 整个在地面线以下的小东西（水洼、海星、地上的砖）：贴在地上
    if (!ctx && b.y0 > lowest + 4) {
      ob.col = col; ob.kind = 'wall'; ob.flat = 'ground'; ob.floor = lowest;
      ob.mesh = this.flatPoly(o.p, lowest, 1.2 + (ob.order % 40) * 0.02, this.mat(col, o.c === 'qing' ? 'glass' : 'wall'));
      ob.z0 = ob.z1 = 0; return;
    }
    // 墨铺得重的不规则大块（礁石、石头滩）：是石头，灰褐色，不是一团黑
    const stone = !ctx && o.c === 'ink' && (o.d ?? 1) >= 0.3 && b.w * b.h > 6000 && (o.p.length > 6 || (b.y0 >= floor - 5 && b.h > 150));
    if (stone) col = [0x8C, 0x82, 0x7A].map(v => v * (1.12 - (o.d ?? 1) * 0.45));
    if (stone && o.p.length > 6) {
      ob.z0 = -50; ob.z1 = 70; ob.kind = 'wall'; ob.col = col;
      ob.mesh = this.slab(o.p, ob.z0, ob.z1, this.mat(col, 'wall')); return;
    }
    if (ctx && ctx.prop) {
      const P = ctx.prop; const zc = P.z; const dep = typeof P.d === 'function' ? P.d(b) : P.d;
      z0 = zc - dep / 2; z1 = zc + dep / 2;
    } else if (ctx && ctx.wall) {
      const W = ctx.wall; z0 = W.z0; z1 = W.z1; kind = W.kind || 'wall';
      if (W.recessDark && dark) { z0 = W.z0 - 30; z1 = z0 + 2; }
    } else if (dark && b.h > 120 && !stone) {            // 门洞、胡同口：一块暗的
      z0 = 0.2; z1 = 1.0; kind = 'wall';
    } else if (onFloor && b.h < 280 && b.w < 420) { // 立在地上的东西
      const dep = Math.max(24, Math.min(90, Math.min(b.w, b.h) * 0.7));
      z0 = 70 - dep / 2; z1 = 70 + dep / 2;
    } else if (b.h > 260 || b.w > 500) {      // 大片的墙
      z0 = -4; z1 = 0; kind = 'wall';
    } else {                                   // 挂在墙上的东西
      z0 = 0; z1 = Math.max(4, Math.min(16, Math.min(b.w, b.h) * 0.12));
    }
    // 后画的盖住先画的：同一面墙上的往前挪一丝
    const eps = (ob.order % 997) * 0.004;
    z0 += eps; z1 += eps;
    ob.z0 = z0; ob.z1 = z1; ob.kind = kind;
    // 家具：墨版铺的中间色是木头（孔版里拿墨网点代木色，搭成实物就该是木头）
    let c2 = col;
    if (ctx && ctx.prop && o.c === 'ink' && (o.d ?? 1) >= 0.2 && (o.d ?? 1) <= 0.75) c2 = [0x8E, 0x62, 0x44].map((v, i) => v * (1.1 - (o.d ?? 1) * 0.35));
    const small = Math.max(b.w, b.h) < 40;
    ob.col = c2;
    const m = this.mat(c2, kind, ctx && ctx.prop && ctx.prop.emit && small ? { emissive: ctx.prop.emit } : {});
    ob.mesh = this.slab(o.p, z0, z1, m);
  }

  // 躺平的水面：屏幕上的 y 换成往远处的 z（z = ZREF + (y − 地面) / K），水面贴着地
  flatWater(ob, o, floor) {
    const sh = new THREE.Shape(o.p.map(([x, y]) => new THREE.Vector2(x, -(ZREF + (y - floor) / K))));
    const geo = new THREE.ShapeGeometry(sh, 24);
    const uv = geo.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) / 220, uv.getY(i) / 220);
    const m = new THREE.MeshStandardMaterial({ color: new THREE.Color(css(sat([0x4E, 0x92, 0x8C], 1.05))), roughness: 0.16, metalness: 0.15, normalMap: this.waterNormal(), normalScale: new THREE.Vector2(0.3, 0.3) });
    const me = this.add(geo, m, false);
    me.rotation.x = -Math.PI / 2; me.position.y = -floor + 0.8;
    ob.flat = true; ob.mesh = null; ob.z0 = ob.z1 = 0;
  }

  // 屏幕上的一块（老画里地面以下的部分）→ 贴着地的平面：y 换成往前的 z。backFill：靠墙那一溜（z 0~ZREF）也铺上
  flatPoly(p, floor, lift, mat, backFill = false) {
    const zOf = y => ZREF + (y - floor) / K;
    let pts = p;
    if (backFill) { const b = bbox(p); if (b.y0 <= floor + 6) pts = p.map(([x, y]) => [x, y <= floor + 6 ? floor - ZREF * K : y]); }
    const sh = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, -zOf(y))));
    const geo = new THREE.ShapeGeometry(sh, 12);
    const me = this.add(geo, mat, false);
    me.rotation.x = -Math.PI / 2; me.position.y = -floor + lift;
    return me;
  }

  flatText(o, floor) {
    const me = this.text(o, 0, css(riso(o.c, Math.max(o.d ?? 1, 0.3))));
    me.rotation.x = -Math.PI / 2; me.scale.y = 1 / K;
    me.position.set(o.p[0][0], -floor + 0.9, ZREF + (o.p[0][1] - floor) / K);
  }

  brickify(ob) {
    if (ob.bricked) return; ob.bricked = true;
    if (ob.flat === 'ground') {
      ob.mesh.material = this.mat(ob.col, 'wall', { brick: true });
      const uv = ob.mesh.geometry.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) / 64, uv.getY(i) / 32);
      uv.needsUpdate = true; return;
    }
    ob.mesh.material = this.mat(this.colorOf(ob.body), ob.kind, { brick: true });
    this.worldUV(ob.mesh, ob.b.w, ob.b.h);
  }

  // 砖贴图按世界尺寸铺：一块贴图 = 64×32 世界像素（四排砖）
  worldUV(me, w, h) {
    const uv = me.geometry.attributes.uv; if (!uv) return;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * w / 64, uv.getY(i) * h / 32);
    uv.needsUpdate = true;
  }

  decal(ob, o, order) {
    const b = bbox(o.p);
    const z = ob.z1 + 0.2 + (order % 50) * 0.02;
    const thick = Math.max(0.6, Math.min(4, Math.min(b.w, b.h) * 0.08));
    const glass = o.c === 'qing' && (o.d ?? 1) < 0.35 && ob.ctx && ob.ctx.name === 'window';
    this.slab(o.p, z, z + thick, this.mat(this.colorOf(o), glass ? 'glass' : 'prop'));
  }

  frame(o, b, cur, ctx) {
    const w = Math.max(1.6, (o.w || 2) * 0.9);
    let z = cur && cur.mesh ? cur.z1 + 0.5 : (ctx && ctx.prop ? ctx.prop.z : 2);
    let dep = w;
    if (ctx && ctx.name === 'window') { z = 0; dep = w * 3; }
    const col = this.mat(riso(o.c, Math.max(o.d ?? 1, 0.6)), 'prop');
    const p = o.p.concat([o.p[0]]);
    for (let i = 0; i < p.length - 1; i++) {
      const [a, c] = [p[i], p[i + 1]]; const L = Math.hypot(c[0] - a[0], c[1] - a[1]); if (L < 1) continue;
      const bx = { x0: Math.min(a[0], c[0]) - w / 2, x1: Math.max(a[0], c[0]) + w / 2, y0: Math.min(a[1], c[1]) - w / 2, y1: Math.max(a[1], c[1]) + w / 2 };
      bx.w = bx.x1 - bx.x0; bx.h = bx.y1 - bx.y0;
      if (Math.abs(a[0] - c[0]) < 0.6 || Math.abs(a[1] - c[1]) < 0.6) this.box(bx, z, z + dep, col, Math.min(1.5, w * 0.3));
      else this.rod([a, c], w / 2, z + w / 2, col);
    }
  }

  line(o, cur, ctx) {
    const w = o.w || 2;
    if ((o.faint || w < 2.0) && !(ctx && ctx.prop)) return;          // 砖缝、地砖缝、细排线：3D 里靠材质
    const b = bbox(o.p);
    if (cur && cur.flat && inside(b, cur.b, 6)) return;
    let z, r = Math.max(ctx && ctx.name === 'wires' ? 0.9 : 1.2, w * 0.6);
    if (ctx && ctx.prop) z = ctx.prop.z;
    else if (cur && cur.mesh && inside(b, cur.b, 2)) z = cur.z1 + r;
    else {
      const floor = this.floorOf(b.y1);
      const onFloor = Math.abs(b.y1 - floor) < 24 && b.h > 30;
      z = onFloor ? 60 : 2 + r;
    }
    const col = this.mat(riso(o.c, Math.max(o.d ?? 1, 0.55)), /ink/.test(o.c) && w >= 4 ? 'metal' : 'prop');
    // 窗台：一道横着的粗线 → 往外挑的一条石板
    if (ctx && ctx.name === 'window' && o.p.length === 2 && Math.abs(o.p[0][1] - o.p[1][1]) < 1 && w >= 3) {
      const y = o.p[0][1];
      this.box({ x0: b.x0, x1: b.x1, y0: y - 3, y1: y + 4, w: b.w, h: 7 }, 0, 14, this.mat([0xE6, 0xDC, 0xCB], 'wall'), 1.5);
      return;
    }
    this.rod(o.p, r, z, col);
  }

  dot(o, cur, ctx) {
    const r = Math.max(1.5, o.w || 2);
    const z = ctx && ctx.prop ? ctx.prop.z + 6 : (cur && cur.mesh ? cur.z1 + r * 0.5 : 4);
    const me = this.add(new THREE.SphereGeometry(r, this.V.flat ? 6 : 12, this.V.flat ? 4 : 8), this.mat(riso(o.c, o.d ?? 1), 'metal'));
    me.position.set(o.p[0][0], -o.p[0][1], z);
  }

  textOp(o, cur) {
    const z = cur && cur.mesh ? cur.z1 + 0.6 : 3;
    const color = o.knock ? '#FFF6E2' : css(riso(o.c, o.d ?? 1));
    this.text(o, z, color);
  }

  waterNormal() {
    if (this._wn) return this._wn;
    const N = 256, c = document.createElement('canvas'); c.width = c.height = N; const x = c.getContext('2d');
    const img = x.createImageData(N, N);
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
      const u = i / N * Math.PI * 2, v = j / N * Math.PI * 2;
      const dx = Math.sin(u * 3 + Math.sin(v * 2) * 1.5) * 0.5 + Math.sin(u * 7 + v * 3) * 0.25;
      const dy = Math.sin(v * 5 + Math.sin(u * 2)) * 0.5 + Math.cos(v * 9 + u * 4) * 0.2;
      const k = (j * N + i) * 4; img.data[k] = 128 + dx * 90; img.data[k + 1] = 128 + dy * 90; img.data[k + 2] = 255; img.data[k + 3] = 255;
    }
    x.putImageData(img, 0, 0);
    const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; this._wn = t; return t;
  }

  // ---------------------------------------------------------------- 认得的东西
  custom(ctx) {
    const n = ctx.name, a = ctx.call.a, kw = ctx.call.kw || {};
    const W = this.d.width;
    if (n === 'ground_street') {
      const y = a[1] ?? 760;
      this.box({ x0: -400, x1: W + 400, y0: y, y1: y + 18, w: W + 800, h: 18 }, -300, 300, this.mat([0xC4, 0xB9, 0xAE], 'wall'), 2);
      // 路牙
      this.box({ x0: -400, x1: W + 400, y0: y, y1: y + 22, w: W + 800, h: 22 }, 290, 310, this.mat([0xDD, 0xD5, 0xCA], 'wall'), 3);
      this.box({ x0: -400, x1: W + 400, y0: y + 30, y1: y + 60, w: W + 800, h: 30 }, 310, 1400, this.mat([0x6A, 0x66, 0x70], 'wall'), 0);
      for (let x = 0; x < W + 200; x += 260) this.box({ x0: x, x1: x + 120, y0: y + 29, y1: y + 31, w: 120, h: 2 }, 560, 580, this.mat([0xE9, 0xE2, 0xD2], 'wall'), 0);
      // 人行道的方砖缝
      for (let x = 0; x < W + 200; x += 80) this.box({ x0: x, x1: x + 1.5, y0: y - 0.3, y1: y + 0.2, w: 1.5, h: 0.5 }, -100, 290, this.mat([0xA8, 0x9E, 0x94], 'wall'), 0);
    } else if (n === 'ground_floor') {
      const y = a[1] ?? 760; const col = kw.color || a[2] || 'ink', d = kw.d ?? a[3] ?? 0.18;
      const floorCol = col === 'ink' ? [0xB5, 0x8A, 0x62] : sat(riso(col, d * 2), 1.1);
      this.box({ x0: -400, x1: W + 400, y0: y, y1: y + 80, w: W + 800, h: 80 }, -300, 300, this.mat(floorCol, 'wall'), 2).castShadow = false;
    } else if (n === 'slab') {
      const [x0, x1, y0, y1] = a;
      const dz = (x1 - x0) < 600 ? 80 : 300;   // 小屋顶那种窄的板别伸那么长
      const me = this.box({ x0, x1, y0, y1, w: x1 - x0, h: y1 - y0 }, -dz, dz, this.mat([0x8A, 0x7E, 0x7E], 'wall'), 2);
      if (dz > 100) me.castShadow = false;     // 剖开的楼板不挡太阳：屋里要亮堂，像掀了盖的模型
    } else if (n === 'cut_wall') {
      const [x, y0, y1] = a; const w = kw.w ?? a[3] ?? 28;
      const me = this.box({ x0: x - w / 2, x1: x + w / 2, y0, y1, w, h: y1 - y0 }, -300, 300, this.mat([0xC0, 0x57, 0x4A], 'wall', { brick: true }), 2);
      this.worldUV(me, w, y1 - y0);
    } else if (n === 'water' || n === 'sea') {
      // 水是平的：老画里竖着的一条水，其实是一片往远处铺开的水面。水面的高度取近岸（y1），
      // 远岸（y0）在屏幕上那么高，是因为它远：z = ZREF − (y1 − y0) / K
      const [x0, x1, y0, y1] = a;
      // 海：岸在 y1 往上 30 那儿（sea() 的 shore + 30），水面比地面低一点，海滩那块平地盖在它上头
      const fl = n === 'sea' ? this.floorOf(y1) : y1;
      const zf = ZREF - (fl - y0) / K, zn = n === 'sea' ? ZREF + (y1 - 30 - fl) / K + 30 : ZREF + 40;
      const geo = new THREE.PlaneGeometry(x1 - x0, zn - zf, 1, 1);
      const col = n === 'sea' ? [0x3E, 0x8E, 0xA8] : [0x4A, 0x8C, 0x86];
      const m = new THREE.MeshStandardMaterial({ color: new THREE.Color(css(sat(col, 1.05))), roughness: 0.18, metalness: 0.15, normalMap: this.waterNormal(), normalScale: new THREE.Vector2(0.35, 0.35) });
      m.normalMap.repeat.set((x1 - x0) / 220, (zn - zf) / 220);
      const me = this.add(geo, m, false);
      me.rotation.x = -Math.PI / 2;
      me.position.set((x0 + x1) / 2, -(n === 'sea' ? fl + 1.5 : y1), (zf + zn) / 2);
    } else if (n === 'tree') {
      // 树在树层（引擎里随风晃），底图只要一个树坑
      const [x, base] = a;
      this.box({ x0: x - 46, x1: x + 46, y0: base - 3, y1: base + 1, w: 92, h: 4 }, 30, 110, this.mat([0x5B, 0x4A, 0x40], 'wall'), 2);
    }
  }
}

// 画法函数 → 前后放在哪、多厚（z 是中心）。人走在 z = 120，所以底图里的东西都在 110 以内
const PROPS = {
  table: { z: 62, d: 64 }, stool: { z: 70, d: 34 }, bench: { z: 66, d: 46 }, bicycle: { z: 80, d: 10 },
  pole: { z: 96, d: 14 }, lamp: { z: 92, d: 14 }, bed: { z: 60, d: 110 }, wardrobe: { z: 30, d: 56 },
  desk: { z: 40, d: 60 }, round_table: { z: 64, d: 70 }, basin_stand: { z: 40, d: 40 }, radiator: { z: 8, d: 14 },
  crate_stack: { z: 70, d: 50 }, cartons: { z: 60, d: 60 }, plank_stall: { z: 64, d: 70 }, tricycle: { z: 84, d: 40 },
  produce: { z: 64, d: 40 }, basket: { z: 76, d: 40 }, deckchair: { z: 70, d: 50 }, parasol: { z: 60, d: 40 },
  fence: { z: 24, d: 8 }, railing: { z: 100, d: 6 }, hen: { z: 80, d: 20 }, corn: { z: 40, d: 30 },
  steelyard: { z: 70, d: 8 }, lifebuoy: { z: 6, d: 10 }, desk_school: { z: 60, d: 50 }, bulb: { z: 50, d: 10, emit: '#FFD9A0' },
  stairs_down: { z: 60, d: 120 }, ladder_up: { z: 30, d: 10 }, wires: { z: 96, d: 4 }, tarp: { z: 70, d: 90 },
  bulb_string: { z: 80, d: 4 }, clock: { z: 4, d: 6 }, calendar: { z: 2, d: 3 }, frame_pic: { z: 3, d: 5 },
};
const WALLISH = {
  facade: { z0: -240, z1: 0, kind: 'wall' }, window: { z0: 0.3, z1: 1.2 }, door: { z0: 0.3, z1: 2.5 },
  signboard: { z0: 2, z1: 14 }, awning: { z0: 0, z1: 40 }, room: { z0: -4, z1: 0 }, hallway: { z0: -4, z1: 0 },
  downstairs: { z0: -4, z1: 0 }, lane: { z0: 0.2, z1: 1.0, kind: 'wall' }, roof_clutter: { z0: -150, z1: -110 },
};
const CUSTOM = new Set(['ground_street', 'ground_floor', 'slab', 'cut_wall', 'tree', 'water', 'sea']);
