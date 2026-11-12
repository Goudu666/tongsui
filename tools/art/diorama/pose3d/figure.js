// 微缩模型小人：按 poses.py 给的关节搭一个 3D 小人（大圆头、雕出来的头发、画上去的脸、胶囊胳膊腿、手套手、圆头鞋），
// 斜投影正交镜头（README：屏幕 y = y + z·K）拍一格，透明底，脚下一团软的接触影。
// 三种材质：toy 塑料（亮）、clay 黏土（哑光 + 指纹）、lowpoly 低多边形（平面着色）。
// 坐标：poses.py 的世界像素（x 右、y 下、脚底在原点）→ three (x, −y, z)，z 朝镜头，人身中线 z = 0（= 场景的 Z_REF）。
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const K = 0.28;
const D2R = Math.PI / 180;
const V = (p, z = 0) => new THREE.Vector3(p[0], -p[1], z);

// ---------------------------------------------------------------- 颜色
export const PAL = {
  skin: '#F5BE96', skinOld: '#EBB892', blush: '#F28C8C',
  hair: '#3A2A2C', hairHi: '#5A4246', grey: '#B9B2B4',
  qing: '#2E8B6E', qingDk: '#236E58', qingLt: '#79C7AE', qingPale: '#A9DCC9',
  mei: '#D94A3A', meiDk: '#B0362C', meiLt: '#F08C7E', meiPale: '#F6B7AC',
  navy: '#3D4A6E', navyDk: '#2F3A58', denim: '#4F6A92', cloth: '#F5F0E6', cream: '#EFE2C8',
  shoe: '#46363C', sole: '#F2EDE4', bag: '#E3A33F', belt: '#5A3A30', cane: '#8A5A3A',
  ink: '#33283A', eye: '#2A1E26', mouth: '#B4434E', tie: '#F2C14E', glasses: '#3A2E36', gold: '#B98C4A',
};
const hexc = (h) => new THREE.Color(h);
function mixHex(a, b, t) { const c = hexc(a).lerp(hexc(b), t); return '#' + c.getHexString(); }

// 道具上 actors.py 的 (版, 浓度) → 颜色
function specColor(spec, role) {
  if (!spec) return PAL.cloth;
  const [c, d] = spec;
  if (c === 'paper') return PAL.cloth;
  if (c === 'skin') return PAL.skin;
  if (c === 'qing' || c === 'mei') {
    if (d == null || d >= 0.7) return PAL[c];
    return mixHex(PAL.cloth, PAL[c], Math.max(0.35, d));
  }
  if (c === 'ink') {
    if (d == null) return PAL.ink;
    if (d <= 0.01) return PAL.cloth;
    if (spec[2] === 'flat') return mixHex(PAL.navy, PAL.ink, 0.4);
    return mixHex('#EDE3D6', '#4A3C44', d);
  }
  return '#888888';
}

// ---------------------------------------------------------------- 材质
let NOISE = null;
function clayBump() {
  if (NOISE) return NOISE;
  const c = document.createElement('canvas'); c.width = c.height = 256; const x = c.getContext('2d');
  x.fillStyle = '#808080'; x.fillRect(0, 0, 256, 256);
  let s = 7; const r = () => (s = (s * 16807) % 2147483647) / 2147483647;
  for (let k = 0; k < 2600; k++) { const v = Math.floor(110 + r() * 40); x.fillStyle = `rgba(${v},${v},${v},0.5)`; x.beginPath(); x.arc(r() * 256, r() * 256, 0.6 + r() * 2.2, 0, 7); x.fill(); }
  // 指纹：几组同心的细弧
  x.lineWidth = 1.1;
  for (let f = 0; f < 7; f++) {
    const cx = r() * 256, cy = r() * 256, a0 = r() * 6;
    for (let i = 1; i < 9; i++) { x.strokeStyle = `rgba(${i % 2 ? 150 : 100},${i % 2 ? 150 : 100},${i % 2 ? 150 : 100},0.55)`; x.beginPath(); x.ellipse(cx, cy, i * 3.2, i * 2.3, a0, 0.3, 2.4); x.stroke(); }
  }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(2, 2);
  NOISE = t; return t;
}

class Mats {
  constructor(variant) { this.v = variant; this.cache = new Map(); }
  get(color, o = {}) {
    const key = color + JSON.stringify(o);
    if (this.cache.has(key)) return this.cache.get(key);
    let m;
    const col = hexc(this.v === 'clay' ? clayTone(color) : color);
    if (this.v === 'toy') {
      m = new THREE.MeshPhysicalMaterial({ color: col, roughness: o.rough ?? 0.42, clearcoat: o.matte ? 0 : 0.25, clearcoatRoughness: 0.35, map: o.map || null });
      m.envMapIntensity = 0.35;
    } else if (this.v === 'clay') {
      m = new THREE.MeshStandardMaterial({ color: col, roughness: o.rough ? Math.max(o.rough, 0.85) : 0.9, map: o.map || null, bumpMap: o.map ? null : clayBump(), bumpScale: 1.4 });
      m.envMapIntensity = 0.15;
    } else {
      m = new THREE.MeshStandardMaterial({ color: col, roughness: o.rough ?? 0.72, flatShading: !o.map, map: o.map || null });
      m.envMapIntensity = 0.2;
    }
    if (o.map) m.color.set('#ffffff');
    if (o.opacity != null) { m.transparent = true; m.opacity = o.opacity; m.depthWrite = false; }
    this.cache.set(key, m); return m;
  }
}
// 黏土：颜色稍暖、稍灰一点
function clayTone(h) { const c = hexc(h); const hsl = {}; c.getHSL(hsl); c.setHSL(hsl.h, hsl.s * 0.86, Math.min(0.92, hsl.l * 1.03 + 0.02)); return '#' + c.lerp(hexc('#FFDDB8'), 0.06).getHexString(); }

// ---------------------------------------------------------------- 几何零件
function segs(v, hi, lo) { return v === 'lowpoly' ? lo : hi; }

function ball(r, sx = 1, sy = 1, sz = 1, F, fine = false) { const g = new THREE.SphereGeometry(r, segs(F.v, 28, fine ? 18 : 8), segs(F.v, 20, fine ? 12 : 6)); g.scale(sx, sy, sz); return g; }

// 一截锥管：a→b，半径 ra→rb（两头不封口，关节上另放球）
function cone(a, b, ra, rb, F) {
  const d = b.clone().sub(a); const len = Math.max(0.01, d.length());
  const g = new THREE.CylinderGeometry(rb, ra, len, segs(F.v, 20, 6), 1, true);
  const m = new THREE.Matrix4().compose(a.clone().add(b).multiplyScalar(0.5), new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), d.normalize()), new THREE.Vector3(1, 1, 1));
  g.applyMatrix4(m); return g;
}

// 一根有粗细变化的管（马尾、翘毛、辫子）：沿 Catmull-Rom 曲线，每个截面一个半径
function taper(points, radii, F, n = 16) {
  const curve = new THREE.CatmullRomCurve3(points);
  const rs = segs(F.v, 14, 5);
  const fr = curve.computeFrenetFrames(n, false);
  const pos = [], idx = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n; const p = curve.getPointAt(t);
    const fi = t * (radii.length - 1); const i0 = Math.floor(fi), i1 = Math.min(radii.length - 1, i0 + 1);
    const r = radii[i0] + (radii[i1] - radii[i0]) * (fi - i0);
    for (let j = 0; j <= rs; j++) {
      const a = j / rs * Math.PI * 2;
      const nx = fr.normals[i].clone().multiplyScalar(Math.cos(a)).add(fr.binormals[i].clone().multiplyScalar(Math.sin(a)));
      pos.push(p.x + nx.x * r, p.y + nx.y * r, p.z + nx.z * r);
    }
  }
  for (let i = 0; i < n; i++) for (let j = 0; j < rs; j++) {
    const a = i * (rs + 1) + j, b = a + rs + 1;
    idx.push(a, b, a + 1, b, b + 1, a + 1);
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx);
  g.computeVertexNormals();
  const uv = []; for (let i = 0; i <= n; i++) for (let j = 0; j <= rs; j++) uv.push(j / rs, i / n);
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  return g;
}

// 绕竖轴的回转体（身子、裙子、外套下摆）：prof = [[半径, 高]]，xs/zs 是前后、左右的缩放
function lathe(prof, F, xs = 1, zs = 1, seg) {
  const g = new THREE.LatheGeometry(prof.map(([r, y]) => new THREE.Vector2(Math.max(0.001, r), y)), seg || segs(F.v, 32, 8));
  g.scale(xs, 1, zs); return g;
}

// ---------------------------------------------------------------- 画脸（贴在头那个球上，经纬度 → 贴图）
const TW = 1024, TH = 512;
const lonX = (L) => (0.5 - L / 360) * TW;
const latY = (E) => (90 - E) / 180 * TH;
const PXD = TW / 360; // 每度多少像素

function faceTexture(F, expr) {
  const c = document.createElement('canvas'); c.width = TW; c.height = TH; const x = c.getContext('2d');
  const skin = F.skin;
  x.fillStyle = skin; x.fillRect(0, 0, TW, TH);
  const D = F.design, st = F.spec.stage, girl = F.spec.role === 'mei';
  const es = (D.eyeScale || 1) * (st === 'child' ? 1.08 : 1) * (st === 'old' ? 0.9 : 1);
  const EL = D.eyeLon ?? 25, EE = D.eyeLat ?? -4, ML = D.mouthLon ?? 4, ME = D.mouthLat ?? -30;
  const style = D.eye || 'oval';
  // 在球面上 (经, 纬) 处画东西：局部坐标单位是「度」，横向按 1/cos(纬) 拉开
  const at = (L, E, fn) => { x.save(); x.translate(lonX(L), latY(E)); x.scale(PXD / Math.cos(E * D2R), PXD); fn(); x.restore(); };
  const col = PAL.eye;
  const ell = (rx, ry, fill) => { x.beginPath(); x.ellipse(0, 0, rx, ry, 0, 0, Math.PI * 2); x.fillStyle = fill; x.fill(); };
  const stroke = (w, color = col) => { x.lineWidth = w; x.strokeStyle = color; x.lineCap = 'round'; x.lineJoin = 'round'; x.stroke(); };

  // 腮红
  const blushK = { shy: 1.0, joy: 0.8, happy: 0.75, chew: 0.75, effort: 0.8 }[expr] ?? ((st === 'child' || st === 'teen' || (girl && st === 'young')) ? 0.6 : 0.3);
  for (const s of [1, -1]) at(s * (EL + 10), EE - 13, () => {
    const g = x.createRadialGradient(0, 0, 0, 0, 0, 7.5); g.addColorStop(0, `rgba(242,120,120,${0.55 * blushK})`); g.addColorStop(1, 'rgba(242,120,120,0)');
    x.fillStyle = g; x.beginPath(); x.ellipse(0, 0, 7.5, 5, 0, 0, 7); x.fill();
    if (expr === 'shy') for (let i = 0; i < 3; i++) { x.beginPath(); x.moveTo(-3 + i * 3, -1.8); x.lineTo(-4.2 + i * 3, 1.8); stroke(0.7, 'rgba(200,80,90,0.8)'); }
  });

  // 一只眼。s=+1 近眼（朝镜头那只），−1 远眼；外眼角在 s 那一侧
  const eye = (s, kind) => at(s * EL, EE, () => {
    x.scale(es, es);
    const rx = style === 'bean' ? 3.3 : style === 'anime' ? 6.0 : 5.3;
    const ry = style === 'bean' ? 5.0 : style === 'anime' ? 8.0 : 7.6;
    const lw = style === 'bean' ? 1.4 : 1.6;
    if (kind === 'open' || kind === 'wide' || kind === 'low' || kind === 'up') {
      const k = kind === 'wide' ? 1.18 : 1;
      const dy = kind === 'low' ? 1.0 : kind === 'up' ? -1.0 : 0;
      const sq = kind === 'low' ? 0.75 : 1;
      x.translate(0, dy);
      if (style === 'anime') {
        // 大眼：整只眼是虹膜（上深下浅的棕），黑瞳，上眼线粗、外眼角一挑，高光一大一小
        x.save(); x.beginPath(); x.ellipse(0, 0, rx * k, ry * k * sq, 0, 0, 7); x.clip();
        const g = x.createLinearGradient(0, -ry, 0, ry); g.addColorStop(0, '#24141A'); g.addColorStop(0.5, '#4E2A22'); g.addColorStop(1, '#A8683E');
        x.fillStyle = g; x.fillRect(-12, -12, 24, 24);
        x.beginPath(); x.ellipse(0, -0.3, rx * 0.5 * k, ry * 0.55 * k, 0, 0, 7); x.fillStyle = '#160A0E'; x.fill();
        const g2 = x.createRadialGradient(0, ry * 0.6, 0, 0, ry * 0.6, rx); g2.addColorStop(0, 'rgba(230,160,100,0.7)'); g2.addColorStop(1, 'rgba(230,160,100,0)');
        x.fillStyle = g2; x.fillRect(-12, -12, 24, 24);
        x.restore();
        x.beginPath(); x.ellipse(0, 0.2, rx * k * 1.08, ry * k * sq * 1.04, 0, Math.PI * 1.1, Math.PI * 1.9); stroke(2.2);
        x.beginPath(); x.moveTo(s * rx * 0.9, -ry * 0.45 * sq); x.lineTo(s * (rx + (girl ? 2.2 : 1.0)), -ry * (girl ? 0.95 : 0.7) * sq); stroke(girl ? 1.5 : 1.3);
        x.save(); x.translate(s * rx * 0.32, -ry * 0.38 * sq); ell(rx * 0.36, rx * 0.42, '#FFFFFF'); x.restore();
        x.save(); x.translate(-s * rx * 0.3, ry * 0.42 * sq); ell(rx * 0.16, rx * 0.16, 'rgba(255,255,255,0.9)'); x.restore();
      } else {
        ell(rx * k, ry * k * sq, col);
        // 高光：上方偏外一个大点、下方偏里一个小点
        x.save(); x.translate(s * rx * 0.3, -ry * 0.38 * sq); ell(rx * 0.42, rx * 0.46, '#FFFFFF'); x.restore();
        x.save(); x.translate(-s * rx * 0.35, ry * 0.45 * sq); ell(rx * 0.18, rx * 0.18, 'rgba(255,255,255,0.85)'); x.restore();
        if (girl && style !== 'bean') { x.beginPath(); x.moveTo(s * rx * 0.7, -ry * 0.62 * sq); x.lineTo(s * (rx + 1.7), -ry * 0.98 * sq); stroke(1.3); }
      }
      if (kind === 'wide') { x.beginPath(); x.arc(0, -ry * 1.6, rx * 1.1, Math.PI * 1.15, Math.PI * 1.85); stroke(1.1); }
    } else if (kind === 'happy') { // ∩ 笑眼
      x.beginPath(); x.ellipse(0, 1.6, rx * 1.15, ry * 0.62, 0, Math.PI * 1.05, Math.PI * 1.95); stroke(lw * 1.25);
    } else if (kind === 'closed') { // ∪ 闭眼
      x.beginPath(); x.ellipse(0, -0.6, rx * 1.1, ry * 0.5, 0, Math.PI * 0.08, Math.PI * 0.92); stroke(lw * 1.2);
      if (style === 'anime' || girl) { x.beginPath(); x.moveTo(s * rx * 1.05, 0.1); x.lineTo(s * (rx + 1.5), -1.0); stroke(1.0); }
    } else if (kind === 'line') { x.beginPath(); x.moveTo(-rx * 1.1, 0.6); x.lineTo(rx * 1.1, 0.6); stroke(lw * 1.2);
    } else if (kind === 'sleepy') { x.beginPath(); x.moveTo(-rx * 1.1, -0.2); x.lineTo(rx * 1.1, -0.2); stroke(lw * 1.2); x.beginPath(); x.ellipse(0, 0.2, rx * 0.9, ry * 0.4, 0, 0, Math.PI); x.fillStyle = col; x.fill();
    } else if (kind === 'squeeze') { // > <
      x.beginPath(); x.moveTo(-s * rx, -ry * 0.55); x.lineTo(s * rx * 0.8, 0); x.lineTo(-s * rx, ry * 0.55); stroke(lw * 1.25);
    }
  });
  const brow = (s, dy, slope) => at(s * EL, EE + 10.5 * es + dy, () => {
    x.beginPath(); x.moveTo(-4.2 * s, slope * s * 1.2 * 0 + slope * 1.0); x.lineTo(4.2 * s, -slope * 1.0); stroke(1.3, F.browCol);
  });
  // 嘴（以 ML, ME 为中心，单位度）
  const mouth = (kind) => at(ML, ME, () => {
    const mc = PAL.mouth; x.scale(D.mouthK || 1.4, D.mouthK || 1.4);
    if (kind === 'smile') { x.beginPath(); x.arc(0, -2.2, 3.2, Math.PI * 0.2, Math.PI * 0.8); stroke(1.2, '#7A3036'); }
    else if (kind === 'small') { x.beginPath(); x.arc(0, -1.6, 2.2, Math.PI * 0.25, Math.PI * 0.75); stroke(1.1, '#7A3036'); }
    else if (kind === 'flat') { x.beginPath(); x.moveTo(-2, 0); x.lineTo(2, 0); stroke(1.1, '#7A3036'); }
    else if (kind === 'grin') { x.beginPath(); x.moveTo(-4, -1.2); x.quadraticCurveTo(0, -1.8, 4, -1.2); x.quadraticCurveTo(0, 5.5, -4, -1.2); x.fillStyle = mc; x.fill(); stroke(0.8, '#6A2430');
      x.beginPath(); x.ellipse(0, 2.2, 1.9, 1.0, 0, 0, 7); x.fillStyle = '#F07A80'; x.fill(); }
    else if (kind === 'o') { x.beginPath(); x.ellipse(0, 0.5, 1.9, 2.5, 0, 0, 7); x.fillStyle = mc; x.fill(); stroke(0.7, '#6A2430'); }
    else if (kind === 'open') { x.beginPath(); x.ellipse(0, 0.5, 2.4, 1.9, 0, 0, 7); x.fillStyle = mc; x.fill(); stroke(0.7, '#6A2430'); }
    else if (kind === 'sad') { x.beginPath(); x.arc(0, 2.4, 2.6, Math.PI * 1.2, Math.PI * 1.8); stroke(1.1, '#7A3036'); }
    else if (kind === 'wavy') { x.beginPath(); x.moveTo(-3, 0); x.quadraticCurveTo(-1.5, -1.5, 0, 0); x.quadraticCurveTo(1.5, 1.5, 3, 0); stroke(1.1, '#7A3036'); }
    else if (kind === 'teeth') { x.beginPath(); x.roundRect(-3.4, -1.6, 6.8, 3.4, 1.2); x.fillStyle = '#FFFFFF'; x.fill(); stroke(0.9, '#6A2430'); x.beginPath(); x.moveTo(-3.2, 0.1); x.lineTo(3.2, 0.1); stroke(0.5, '#B09090'); }
    else if (kind === 'chew') { x.beginPath(); x.arc(0, -1.2, 2.2, Math.PI * 0.2, Math.PI * 0.8); stroke(1.1, '#7A3036'); }
    else if (kind === 'side') { x.beginPath(); x.moveTo(-2.4, 0.6); x.quadraticCurveTo(0.5, 0.4, 2.6, -0.8); stroke(1.1, '#7A3036'); }
  });

  const E = expr || '';
  const P = {
    '': ['open', 'small'], blink: ['line', 'small'], happy: ['happy', 'smile'], shy: ['happy', 'wavy'], joy: ['happy', 'grin'],
    open: ['open', 'open'], sing: ['closed', 'o'], surprise: ['wide', 'o'], bliss: ['closed', 'smile'], focus: ['low', 'flat'],
    think: ['up', 'side'], effort: ['squeeze', 'teeth'], sad: ['low', 'sad'], chew: ['happy', 'chew'], sleepy: ['sleepy', 'flat'], sleep: ['closed', 'small'],
  }[E] || ['open', 'small'];
  for (const s of [1, -1]) eye(s, P[0]);
  mouth(P[1]);
  if (E === 'focus') { brow(1, -1, 1); brow(-1, -1, 1); }
  else if (E === 'sad') { brow(1, 0, -1.2); brow(-1, 0, -1.2); }
  else if (E === 'think') { brow(1, 1.5, -0.6); brow(-1, -0.5, 0.4); }
  else if (E === 'surprise') { /* 眉毛在 wide 里 */ }
  else if (st !== 'child' && D.brows !== false) { brow(1, 0.5, 0); brow(-1, 0.5, 0); }
  if (E === 'chew') at(ML + 7, ME + 2, () => { x.beginPath(); x.ellipse(0, 0, 3.5, 3, 0, 0, 7); x.fillStyle = 'rgba(240,150,140,0.35)'; x.fill(); });
  if (st === 'old') {
    // 眼角的笑纹、法令纹
    for (const s of [1, -1]) at(s * (EL + 9 * es), EE, () => { for (const a of [-0.45, 0, 0.45]) { x.beginPath(); x.moveTo(s * 0.5, a * 3); x.lineTo(s * 3.2, a * 5); stroke(0.6, 'rgba(160,100,90,0.7)'); } });
    for (const s of [1, -1]) at(ML + s * 9, ME + 4, () => { x.beginPath(); x.arc(-s * 3, 0, 4, s > 0 ? -0.6 : Math.PI - 0.6 + 1.2 - 1.2, s > 0 ? 0.6 : Math.PI + 0.6); stroke(0.6, 'rgba(170,110,100,0.6)'); });
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
}

// ---------------------------------------------------------------- 头发
// 头上的局部坐标：x 朝前（脸）、y 朝上、z 朝人的右手（朝镜头那侧）。A = 方位角（0 前，±180 后，+90 朝镜头），E = 仰角。
function hairShell(F, r, hl, opts = {}) {
  const g = new THREE.SphereGeometry(1, segs(F.v, 192, 40), segs(F.v, 128, 26));
  const p = g.attributes.position;
  const tufts = opts.tufts || [];
  const v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i).normalize();
    const A = Math.atan2(v.z, v.x) / D2R, E = Math.asin(Math.max(-1, Math.min(1, v.y))) / D2R;
    const line = hl(A);
    const edge = opts.edge || 3.5;
    const h = THREE.MathUtils.smoothstep(E, line - edge, line + edge);
    let R = 1.0 + (opts.thick || 0.09);
    for (const t of tufts) { const d = v.dot(t.d); R += t.a * Math.exp(-(1 - d) / t.s); }
    if (opts.flare) R += opts.flare * THREE.MathUtils.smoothstep(-E, 5, 60);
    if (opts.tuck) R -= opts.tuck * (1 - THREE.MathUtils.smoothstep(E, line, line + 18)) * (E < 0 ? 1 : 0.3);
    const IN = F.v === 'lowpoly' ? 0.86 : 0.94;  // 没头发的地方缩进头里（低多边形的头面是平的，得缩深一点）
    const RR = IN + (R - IN) * h;
    let hx = v.x, hz = v.z, hy = v.y;
    // 低于赤道的头发往下垂（短发、齐耳）：水平半径不往里收
    if (opts.hang && E < 0 && h > 0.01) {
      const hk = opts.hang * h; const horiz = Math.hypot(v.x, v.z) || 1;
      const want = horiz + (1 - horiz) * hk;
      hx = v.x / horiz * want; hz = v.z / horiz * want; hy = v.y * (1 + 0.15 * hk);
    }
    p.setXYZ(i, hx * RR * r, hy * RR * r, hz * RR * r);
  }
  g.computeVertexNormals();
  return g;
}
const dirAE = (A, E) => new THREE.Vector3(Math.cos(E * D2R) * Math.cos(A * D2R), Math.sin(E * D2R), Math.cos(E * D2R) * Math.sin(A * D2R));
function rnd(seed) { let s = seed; return () => (s = (s * 16807) % 2147483647) / 2147483647; }
const mixA = (A, front, side, back) => { // 按方位角在 前 / 侧 / 后 三个值之间平滑地插
  const a = Math.abs(A);
  if (a <= 90) { const t = a / 90; const u = t * t * (3 - 2 * t); return front + (side - front) * u; }
  const t = (a - 90) / 90; const u = t * t * (3 - 2 * t); return side + (back - side) * u;
};

function buildHair(F, head, r) {
  const { spec } = F; const st = spec.stage; const q = spec.role === 'qing';
  const grey = spec.hair === 'grey';
  const col = grey ? PAL.grey : PAL.hair;
  const M = F.mats.get(col, { rough: grey ? 0.55 : 0.38 });
  const add = (g, m = M) => { const me = new THREE.Mesh(g, m); me.castShadow = true; me.receiveShadow = true; head.add(me); return me; };
  const R = rnd(q ? 11 : 23);
  const tufts = [];
  const mk = (n, a, s, emin, emax, amin = -180, amax = 180) => { for (let i = 0; i < n; i++) tufts.push({ d: dirAE(amin + R() * (amax - amin), emin + R() * (emax - emin)), a: a * (0.6 + R() * 0.6), s }); };
  if (q) {
    // 青：短发、乱一点，额前一排尖尖的刘海；小时候和中学头顶一撮翘毛
    const messy = st === 'child' || st === 'teen' ? 1 : st === 'young' ? 0.7 : 0.45;
    mk(grey ? 18 : 14, grey ? 0.035 : 0.05 * messy + 0.01, grey ? 0.012 : 0.02, 10, 80);
    mk(6, 0.035 * messy, 0.015, -20, 30, 100, 260);
    const front = grey ? 34 : st === 'middle' ? 26 : 20;
    const spikes = grey ? 0 : 9 * messy;
    const hl = (A) => {
      const fs = F.design.fringe || 'spiky';
      let fr = front + spikes * Math.abs(Math.sin(A * D2R * 7.5));
      if (fs === 'swept' && !grey) fr = front + 4 + A * 0.16 + 3 * Math.abs(Math.sin(A * D2R * 3));   // 侧分：靠镜头那边高、另一边低
      if (fs === 'chunky' && !grey) fr = front - 2 + 13 * messy * Math.pow(Math.abs(Math.sin(A * D2R * 4.2)), 0.7);
      return mixA(A, fr, grey ? 5 : -2, grey ? -30 : -38);
    };
    add(hairShell(F, r, hl, { tufts, thick: grey ? 0.06 : 0.1, edge: 3 }));
    // 鬓角压住耳朵上沿
    if ((st === 'child' || st === 'teen') && !grey) {
      // 翘毛：从头顶往后翘再往前勾一下
      const base = dirAE(-25, 74).multiplyScalar(r * 1.04);
      const pts = [base, base.clone().add(new THREE.Vector3(-0.12 * r, 0.28 * r, 0.02 * r)), base.clone().add(new THREE.Vector3(0.04 * r, 0.5 * r, 0.03 * r)), base.clone().add(new THREE.Vector3(0.24 * r, 0.52 * r, 0.04 * r))];
      add(taper(pts, [r * 0.16, r * 0.12, r * 0.07, r * 0.02], F));
    }
  } else {
    // 梅
    if (st === 'old') {
      mk(14, 0.03, 0.012, 0, 80);
      add(hairShell(F, r, (A) => mixA(A, 30, 2, -32) + 3 * Math.abs(Math.sin(A * D2R * 6)), { tufts, thick: 0.07, edge: 4 }));
      const bun = add(ball(r * 0.42, 1, 0.9, 1, F)); bun.position.copy(dirAE(180, 32).multiplyScalar(r * 1.05));
      const pin = add(cone(new THREE.Vector3(-r * 0.7, r * 0.75, -r * 0.5), new THREE.Vector3(-r * 1.0, r * 0.62, r * 0.5), r * 0.035, r * 0.035, F), F.mats.get(PAL.gold, { rough: 0.3 }));
    } else {
      // 齐刘海 + 齐耳短发（年轻时长到肩上）
      mk(8, 0.02, 0.02, 20, 80);
      const fr = st === 'teen' ? 14 : 12;
      const side = st === 'teen' ? -10 : st === 'middle' ? -50 : st === 'young' ? -66 : -34;
      const back = st === 'teen' ? -30 : st === 'middle' ? -58 : st === 'young' ? -76 : -44;
      const hl = (A) => {
        const a = Math.abs(A);
        const fs = F.design.fringe || 'spiky';
        let bang = fr + 2.5 * Math.abs(Math.sin(A * D2R * 9)) + (a > 40 ? (a - 40) * 0.4 : 0);
        if (fs === 'swept') bang = fr + 8 + 14 * Math.exp(-Math.pow((A - 8) / 16, 2)) + (a > 40 ? (a - 40) * 0.3 : 0);   // 中分的八字刘海
        if (fs === 'chunky') bang = fr + 6 * Math.pow(Math.abs(Math.sin(A * D2R * 4.5)), 0.6) + (a > 40 ? (a - 40) * 0.4 : 0);
        if (a < 55) return bang;
        if (st === 'teen') return mixA(A, bang, side, back);
        // 刘海往两边一转直接落到耳下
        const t = THREE.MathUtils.smoothstep(a, 55, 72);
        return bang + (mixA(A, 0, side, back) - bang) * t;
      };
      add(hairShell(F, r, hl, { tufts, thick: 0.11, hang: st === 'teen' ? 0.3 : st === 'child' ? 0.35 : 0.5, flare: st === 'young' ? 0.08 : 0.05, edge: 3.5, tuck: 0.07, thick: 0.1 }));
      if (st === 'child') {
        // 两个小揪揪，红头绳
        for (const s of [1, -1]) {
          const b0 = dirAE(s * 120, 8).multiplyScalar(r * 1.04);
          const o = dirAE(s * 120, 8);
          const tail = add(taper([b0, b0.clone().add(o.clone().multiplyScalar(0.25 * r)).add(new THREE.Vector3(0, 0.02 * r, 0)), b0.clone().add(o.clone().multiplyScalar(0.42 * r)).add(new THREE.Vector3(0, -0.22 * r, 0)), b0.clone().add(o.clone().multiplyScalar(0.4 * r)).add(new THREE.Vector3(0, -0.5 * r, 0))],
            [r * 0.2, r * 0.26, r * 0.2, r * 0.05], F));
          const tie = add(ball(r * 0.11, 1, 1, 1, F), F.mats.get(PAL.mei, {})); tie.position.copy(b0.clone().add(o.clone().multiplyScalar(0.06 * r)));
        }
      } else if (st === 'teen') {
        // 高马尾，红头绳
        const b0 = dirAE(180, 38).multiplyScalar(r * 1.05);
        add(taper([b0, b0.clone().add(new THREE.Vector3(-0.35 * r, 0.06 * r, 0)), b0.clone().add(new THREE.Vector3(-0.58 * r, -0.35 * r, 0.02 * r)), b0.clone().add(new THREE.Vector3(-0.5 * r, -0.9 * r, 0.05 * r)), b0.clone().add(new THREE.Vector3(-0.32 * r, -1.2 * r, 0.06 * r))],
          [r * 0.2, r * 0.27, r * 0.25, r * 0.16, r * 0.04], F, 24));
        const tie = add(new THREE.TorusGeometry(r * 0.17, r * 0.07, 8, 18), F.mats.get(PAL.mei, {}));
        tie.position.copy(b0.clone().add(new THREE.Vector3(-0.08 * r, 0.0, 0))); tie.rotation.y = Math.PI / 2; tie.rotation.x = 0.4;
      } else if (st === 'young') {
        // 披到肩上的那一片（背后）
        const back = add(ball(r * 0.82, 0.7, 1.1, 1.05, F)); back.position.set(-r * 0.48, -r * 0.58, 0);
      }
      if (st !== 'old') {
        // 小发卡（梅的标志色）
        const clip = add(new THREE.CapsuleGeometry(r * 0.05, r * 0.26, 4, 8), F.mats.get(st === 'child' ? PAL.tie : PAL.mei, {}));
        clip.position.copy(dirAE(62, 42).multiplyScalar(r * 1.1)); clip.lookAt(new THREE.Vector3(0, 0, 0)); clip.rotateX(Math.PI / 2); clip.rotateZ(0.6);
      }
    }
  }
}

// ---------------------------------------------------------------- 衣服配色
function outfit(spec) {
  const q = spec.role === 'qing', st = spec.stage;
  const R = q ? 'qing' : 'mei';
  const o = { skinLegs: false, socks: null, sole: null };
  if (st === 'child') {
    if (q) Object.assign(o, { top: PAL.qing, stripes: PAL.cloth, sleeve: 'short', bottom: PAL.navy, shorts: true, shoe: '#C0503E', sole: PAL.sole, socks: PAL.cloth, collar: PAL.cloth });
    else Object.assign(o, { top: PAL.mei, sleeve: 'short', bottom: PAL.meiPale, skirt: PAL.mei, shoe: PAL.meiDk, collar: PAL.cloth, socks: PAL.cloth, skinLegs: true });
  } else if (st === 'teen') {
    Object.assign(o, { top: PAL[R], bottom: PAL[R], trim: PAL.cloth, shoe: PAL.cloth, sole: '#D9D2C8', collar: PAL.cloth, zip: PAL.cloth, bag: PAL.bag });
  } else if (st === 'young') {
    if (q) Object.assign(o, { top: PAL.cloth, jacket: PAL.qing, bottom: PAL.denim, shoe: PAL.shoe, sole: PAL.sole, collar: PAL.qingDk });
    else Object.assign(o, { top: PAL.cloth, coat: PAL.mei, bottom: PAL.navy, shoe: PAL.shoe, belt: PAL.meiDk });
  } else if (st === 'middle') {
    if (q) Object.assign(o, { top: PAL.cloth, jacket: PAL.qing, bottom: PAL.navy, shoe: PAL.shoe, belly: spec.belly });
    else Object.assign(o, { top: PAL.cream, jacket: '#C4483E', buttons: PAL.cloth, bottom: PAL.navy, shoe: PAL.shoe });
  } else {
    if (q) Object.assign(o, { top: PAL.qingPale, jacket: PAL.qing, bottom: '#5A6070', shoe: PAL.shoe });
    else Object.assign(o, { top: PAL.meiPale, jacket: PAL.mei, buttons: PAL.cloth, bottom: '#5A6070', shoe: PAL.shoe });
  }
  return o;
}

// ---------------------------------------------------------------- 搭一个人
export function buildFigure(job, mats) {
  const { spec, frame: fr, design: D } = job;
  const F = { spec, design: D, v: job.variant, mats, skin: spec.stage === 'old' ? PAL.skinOld : PAL.skin, browCol: spec.hair === 'grey' ? '#9A8E94' : PAL.hair };
  const root = new THREE.Group();
  const add = (g, m, parent = root) => { const me = new THREE.Mesh(g, m); me.castShadow = true; me.receiveShadow = true; parent.add(me); return me; };
  const O = outfit(spec);
  const st = spec.stage;
  const LK = D.limbK || 1;
  const w = spec.waist, cw = spec.chest;
  const breadth = 1.3;                                // 肩宽 / 侧面厚度
  const zL = w * 0.27, zA = cw * 0.5 * breadth + spec.limb * 0.12 * LK;   // 腿、胳膊离中线多远
  const mSkin = mats.get(F.skin);
  if (fr.sleep) return buildSleep(job, F, root, add);

  // ---- 腿 ----
  const legR = spec.limb * 0.5 * LK, shinR = spec.shin_w * 0.5 * LK;
  const bottomM = mats.get(O.bottom);
  for (const side of ['near', 'far']) {
    const L = fr.legs[side]; const z = side === 'near' ? zL : -zL;
    const hip = V(fr.hip, z), knee = V(L.knee, z), ankle = V(L.ankle, z);
    hip.y += legR * 0.3;
    if (O.shorts || O.skinLegs) {
      // 短裤 / 裙子底下：大腿上半截是布，往下是腿（或白袜）
      const mid = hip.clone().lerp(knee, O.shorts ? 0.62 : 0.0);
      if (O.shorts) { add(cone(hip, mid, legR * 1.22, legR * 1.15, F), bottomM); add(ball(legR * 1.15, 1, 0.35, 1, F), bottomM).position.copy(mid); }
      const legM = O.skinLegs ? mats.get(O.bottom) : mSkin;
      add(cone(O.shorts ? mid : hip, knee, legR * 0.82, shinR * 0.8, F), O.shorts ? mSkin : legM);
      add(ball(shinR * 0.8, 1, 1, 1, F), O.shorts ? mSkin : legM).position.copy(knee);
      const sock = knee.clone().lerp(ankle, 0.55);
      add(cone(knee, sock, shinR * 0.8, shinR * 0.74, F), O.shorts ? mSkin : legM);
      add(cone(sock, ankle, shinR * 0.8, shinR * 0.78, F), mats.get(O.socks || O.bottom));
      add(ball(shinR * 0.8, 1, 1, 1, F), mats.get(O.socks || O.bottom)).position.copy(sock);
    } else {
      add(ball(legR * 1.02, 1, 1, 1, F), bottomM).position.copy(hip);
      add(cone(hip, knee, legR * 1.02, shinR * 0.98, F), bottomM);
      add(ball(shinR * 0.98, 1, 1, 1, F), bottomM).position.copy(knee);
      add(cone(knee, ankle, shinR * 0.98, shinR * 0.92, F), bottomM);
      if (O.trim) { // 校服裤腿外侧一道白杠
        const off = new THREE.Vector3(0, 0, (side === 'near' ? 1 : -1) * shinR * 0.92);
        add(cone(hip.clone().lerp(knee, 0.15).add(off), knee.clone().add(off), 0.9, 0.9, F), mats.get(O.trim));
        add(cone(knee.clone().add(off), ankle.clone().lerp(knee, 0.12).add(off), 0.9, 0.9, F), mats.get(O.trim));
      }
    }
    // 鞋：圆头，脚跟到脚尖
    const heel = V(L.heel, z), toe = V(L.toe, z);
    const len = heel.distanceTo(toe) * 1.08 + 2;
    const sh = (st === 'child' ? 6.2 : 6.6) * (D.shoeK || 1);
    const ang = Math.atan2(toe.y - heel.y, toe.x - heel.x);
    const sg = new THREE.Group(); root.add(sg);
    sg.position.copy(heel.clone().lerp(toe, 0.55)); sg.rotation.z = ang;
    const shoeW = shinR * 2.1;
    const body = add(ball(1, 1, 1, 1, F), mats.get(O.shoe), sg); body.scale.set(len * 0.5, sh * 0.62, shoeW * 0.5); body.position.set(0, sh * 0.45, 0);
    const toeB = add(ball(1, 1, 1, 1, F), mats.get(O.shoe), sg); toeB.scale.set(len * 0.3, sh * 0.6, shoeW * 0.52); toeB.position.set(len * 0.2, sh * 0.42, 0);
    if (O.sole) { const so = add(ball(1, 1, 1, 1, F), mats.get(O.sole), sg); so.scale.set(len * 0.52, sh * 0.26, shoeW * 0.53); so.position.set(0.5, sh * 0.16, 0); }
    if (spec.role === 'mei' && st === 'child') { const strap = add(new THREE.TorusGeometry(shoeW * 0.42, 0.7, 6, 16, Math.PI), mats.get(O.shoe), sg); strap.position.set(-len * 0.05, sh * 0.85, 0); strap.rotation.y = Math.PI / 2; }
  }

  // ---- 身子 ----
  const T = spec.torso;
  const lean = fr.lean * D2R;
  const torso = new THREE.Group(); root.add(torso);
  torso.position.copy(V(fr.hip)); torso.rotation.z = -lean;
  const tg = new THREE.Group(); torso.add(tg); tg.rotation.y = -(D.torsoYaw ?? 10) * D2R;
  const belly = spec.belly || 0;
  const rad = (t) => { // 躯干在高度 t（0 髋 ~ 1 肩）处的半径（侧面看的前后厚度的一半）
    const ww = w + (cw - w) * THREE.MathUtils.smoothstep(t, 0.2, 0.85);
    let r = ww * 0.5;
    if (t < -0.02) r *= Math.sqrt(Math.max(0, 1 - Math.pow((t + 0.02) / 0.2, 2)));
    if (t > 0.86) r *= Math.sqrt(Math.max(0, 1 - Math.pow((t - 0.86) / 0.24, 2))) * 0.75 + 0.25;
    return r;
  };
  const prof = (t0, t1, n = 14, grow = 0) => { const out = []; for (let i = 0; i <= n; i++) { const t = t0 + (t1 - t0) * i / n; out.push([rad(t) + grow, t * T]); } return out; };
  const T0 = -0.2, T1 = 1.1;
  const band = (t0, t1, color, grow = 0) => {
    let p = prof(t0, t1, Math.max(3, Math.round((t1 - t0) * 24)), grow);
    if (t0 <= T0 + 1e-6) p = [[0, T0 * T], ...p];
    if (t1 >= T1 - 1e-6) p = [...p, [0, T1 * T]];
    const g = lathe(p, F, 1, breadth);
    if (belly) { const a = g.attributes.position; for (let i = 0; i < a.count; i++) { const x = a.getX(i), y = a.getY(i) / T; if (x > 0) a.setX(i, x * (1 + belly * 1.6 * Math.exp(-Math.pow((y - 0.3) / 0.28, 2)))); } g.computeVertexNormals(); }
    return add(g, mats.get(color), tg);
  };
  const waist = O.coat ? -0.2 : 0.16;
  // 下身（裤腰）+ 上衣
  const topC = O.jacket || O.coat || O.top;
  if (!O.coat) band(T0, waist, O.skirt ? O.top : O.bottom);
  if (O.stripes) {
    let t = waist; let k = 0; const step = 0.14;
    while (t < T1 - 1e-6) { const t1 = Math.min(T1, t + (k % 2 ? 0.055 : step)); band(t, t1 > T1 - 0.08 ? T1 : t1, k % 2 ? O.stripes : O.top); if (t1 > T1 - 0.08) break; t = t1; k++; }
  } else band(O.coat ? T0 : waist, T1, topC);
  // 敞开的外套：前襟露出里面的衣服（一条竖着的面）
  if (O.jacket) {
    const inner = new THREE.Group(); tg.add(inner);
    const g = lathe(prof(0.0, 1.0, 14, 0.25), F, 1, breadth * 0.42, segs(F.v, 32, 8));
    const a = g.attributes.position; // 只留前面那一半
    const me = add(g, mats.get(O.top), inner); me.position.x = rad(0.5) * 0.08;
    if (O.buttons) for (const t of [0.25, 0.48, 0.71]) { const b = add(ball(1.3, 1, 1, 1, F), mats.get(O.buttons), tg); b.position.set(rad(t) + 0.6, t * T, 1.6); }
  }
  if (O.zip) { const z0 = new THREE.Vector3(rad(0.2) + 0.3, 0.2 * T, 0), z1 = new THREE.Vector3(rad(0.95) * 0.85, 0.97 * T, 0); add(cone(z0, z1, 0.7, 0.7, F), mats.get(O.zip), tg); }
  if (O.skirt) { // 小裙子：从腰往下撒开
    const sk = fr.sit ? [[rad(0.35) + 0.4, 0.35 * T], [w * 0.62, 0], [w * 0.7, -spec.thigh * 0.1], [w * 0.55, -spec.thigh * 0.18]] :
      [[rad(0.35) + 0.4, 0.35 * T], [w * 0.62, 0.05 * T], [w * 0.86, -spec.thigh * 0.45], [w * 0.92, -spec.thigh * 0.62], [w * 0.8, -spec.thigh * 0.66]];
    add(lathe(sk.slice().reverse(), F, 1, breadth * 0.92), mats.get(O.skirt), tg);
    const hem = add(lathe([[w * 0.88, -spec.thigh * 0.67], [w * 0.95, -spec.thigh * 0.64], [w * 0.92, -spec.thigh * 0.6]], F, 1, breadth * 0.92), mats.get(PAL.cloth), tg); hem.visible = !fr.sit;
  }
  if (O.coat) { // 长大衣：盖到大腿，系腰带
    const hemY = fr.sit ? -spec.thigh * 0.2 : -spec.thigh * 0.95;
    const c = [[rad(0.32) + 0.5, 0.32 * T], [rad(0.1) + 0.7, 0.1 * T], [w * 0.56, -spec.thigh * 0.25], [w * 0.64, hemY + 2], [w * 0.62, hemY], [w * 0.5, hemY - 0.8]];
    add(lathe(c.slice().reverse(), F, 1, breadth * 0.95), mats.get(O.coat), tg);
    add(lathe([[rad(0.3) + 0.9, 0.27 * T], [rad(0.3) + 1.1, 0.3 * T], [rad(0.3) + 0.9, 0.34 * T]], F, 1, breadth * 1.0), mats.get(O.belt), tg);
    // 领口露出的白衬衫
    const v = add(ball(1, 1, 1, 1, F), mats.get(O.top), tg); v.scale.set(1.6, 4.5, 3.2); v.position.set(rad(0.9) - 0.9, 0.93 * T, 0);
  }
  if (O.collar) { // 领子：脖子底下一圈
    const cg = new THREE.TorusGeometry(spec.neck * 0.0 + 4.8, 1.6, 8, 20); cg.rotateX(Math.PI / 2); cg.scale(1, 1, breadth * 0.9);
    const cm = add(cg, mats.get(O.collar), tg); cm.position.set(1, 1.03 * T, 0); cm.rotation.z = 0.15;
  }
  if (O.bag) { // 书包背在身后
    const bg = add(roundBox(w * 0.62, T * 0.62, cw * 1.05, 4, F), mats.get(O.bag), tg); bg.position.set(-rad(0.55) - w * 0.22, 0.52 * T, 0);
    const flap = add(roundBox(w * 0.3, T * 0.3, cw * 0.9, 2.5, F), mats.get(mixHex(O.bag, '#7A4A20', 0.25)), tg); flap.position.set(-rad(0.55) - w * 0.5, 0.4 * T, 0);
    for (const s of [1, -1]) { const strap = add(new THREE.TorusGeometry(T * 0.3, 1.1, 6, 16, Math.PI * 0.9), mats.get(mixHex(O.bag, '#7A4A20', 0.3)), tg); strap.position.set(0, 0.55 * T, s * cw * 0.42 * breadth); strap.rotation.z = Math.PI * 0.55; }
  }

  // ---- 脖子、头 ----
  const neckTop = V(fr.neck), shoulder = V(fr.shoulder);
  add(cone(shoulder, neckTop, 3.6, 3.4, F), mSkin);
  const r = spec.head;
  const head = new THREE.Group(); root.add(head);
  head.position.copy(V(fr.head));
  head.rotation.set(0, -(D.yaw ?? 38) * D2R, -(fr.tilt + (D.headPitch ?? 0)) * D2R);  // headPitch < 0：抬一点头，抵掉镜头往下看的那一点
  const hs = D.headShape || [1, 0.95, 1];
  const face = add(ball(r, hs[0], hs[1], hs[2], F, true), mats.get(F.skin, { map: faceTexture(F, fr.expr), rough: 0.5 }), head);
  face.rotation.y = 0; // 贴图的经度 0 = +x（脸朝前）
  // 耳朵
  if (spec.role === 'qing' || st === 'old') for (const s of [1, -1]) { const e = add(ball(r * 0.17, 0.7, 1.1, 0.55, F), mSkin, head); e.position.copy(dirAE(s * 92, -8).multiplyScalar(r * hs[2] * 0.97)); }
  if (D.nose !== false) { const n = add(ball(r * (D.noseK || 0.085), 1, 0.9, 1, F), mSkin, head); n.position.copy(dirAE(D.noseLon ?? 8, D.noseLat ?? -16).multiplyScalar(r * 0.99)); }
  buildHair(F, head, r);
  if (st === 'middle' || st === 'old') { // 眼镜
    const gm = mats.get(st === 'old' ? PAL.gold : PAL.glasses, { rough: 0.3 });
    const EL = D.eyeLon ?? 25, EE = D.eyeLat ?? -4; const es = D.eyeScale || 1;
    const ctr = [];
    for (const s of [1, -1]) {
      const d = dirAE(s * EL, EE); const c = d.clone().multiplyScalar(r * 1.06); ctr.push(c);
      const ring = add(new THREE.TorusGeometry(r * 0.2 * Math.min(1.25, es), r * 0.028, 6, 24), gm, head); ring.position.copy(c); ring.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), d);
      // 镜腿往耳朵
      add(cone(c.clone().add(dirAE(s * (EL + 20), EE).multiplyScalar(r * 0.02)), dirAE(s * 88, EE + 2).multiplyScalar(r * 1.04), r * 0.024, r * 0.024, F), gm, head);
    }
    add(cone(ctr[0].clone().lerp(ctr[1], 0.28), ctr[1].clone().lerp(ctr[0], 0.28), r * 0.024, r * 0.024, F), gm, head);
  }

  // ---- 胳膊 ----
  const sleeveM = mats.get(O.jacket || O.coat || O.top);
  for (const side of ['far', 'near']) {
    const z = side === 'near' ? zA : -zA;
    const sh = V(fr['sh_' + side], z), el = V(fr['elbow_' + side], z), hd = V(fr['hand_' + side], z);
    sh.y -= 2;
    const ar = (spec.limb - 1) * 0.5 * LK;
    add(ball(ar * 1.12, 1, 1, 1, F), sleeveM).position.copy(sh);
    if (O.sleeve === 'short') {
      const mid = sh.clone().lerp(el, 0.6);
      add(cone(sh, mid, ar * 1.15, ar * 1.1, F), sleeveM); add(ball(ar * 1.1, 1, 0.4, 1, F), sleeveM).position.copy(mid);
      add(cone(mid, el, ar * 0.78, ar * 0.76, F), mSkin); add(ball(ar * 0.76, 1, 1, 1, F), mSkin).position.copy(el);
      add(cone(el, hd, ar * 0.76, ar * 0.7, F), mSkin);
    } else {
      add(cone(sh, el, ar * 1.05, ar, F), sleeveM); add(ball(ar, 1, 1, 1, F), sleeveM).position.copy(el);
      const cuff = el.clone().lerp(hd, 0.82);
      add(cone(el, cuff, ar, ar * 0.95, F), sleeveM);
      if (O.trim) { const off = new THREE.Vector3(0, 0, (side === 'near' ? 1 : -1) * ar * 0.95); add(cone(sh.clone().lerp(el, 0.2).add(off), el.clone().add(off), 0.8, 0.8, F), mats.get(O.trim)); add(cone(el.clone().add(off), cuff.clone().add(off), 0.8, 0.8, F), mats.get(O.trim)); }
      add(ball(ar * 0.96, 1, 0.35, 1, F), sleeveM).position.copy(cuff);
    }
    // 手：圆圆的手套
    const hr = ar * (D.handK || 1.15);
    const hand = add(ball(hr, 1.05, 1.0, 0.85, F), mSkin); hand.position.copy(hd);
    const dir = hd.clone().sub(el).normalize(); hand.position.add(dir.multiplyScalar(hr * 0.35));
  }
  // 拐杖
  if (fr.cane) {
    const h = V(fr.hand_near, zA + 1.5); const tip = new THREE.Vector3(h.x + 10, 0, zA + 1.5);
    const cm = mats.get(PAL.cane, { rough: 0.5 });
    add(cone(h.clone().add(new THREE.Vector3(-2, 6, 0)), tip, 1.6, 1.4, F), cm);
    const hook = add(new THREE.TorusGeometry(3.4, 1.6, 8, 16, Math.PI), cm); hook.position.copy(h).add(new THREE.Vector3(1.4, 5.5, 0));
  }
  // 在忙：手里一只碗 / 一块布
  if (fr.busy) {
    const h = V(fr.hand_near, zA * 0.6);
    const bx = add(roundBox(14, 9, 12, 2.5, F), mats.get(mixHex(PAL.cloth, PAL[spec.role], 0.35))); bx.position.copy(h).add(new THREE.Vector3(5, 3, -2));
  }
  buildProps(job, F, root, add, { zA, zL, w, cw, breadth });
  return root;
}

function roundBox(wx, hy, dz, r, F) {
  // 简单的圆角盒：用拉伸的圆角矩形（侧面）
  const s = new THREE.Shape(); const x0 = -wx / 2, y0 = -hy / 2; r = Math.min(r, wx / 2 - 0.01, hy / 2 - 0.01);
  s.moveTo(x0 + r, y0); s.lineTo(x0 + wx - r, y0); s.quadraticCurveTo(x0 + wx, y0, x0 + wx, y0 + r); s.lineTo(x0 + wx, y0 + hy - r);
  s.quadraticCurveTo(x0 + wx, y0 + hy, x0 + wx - r, y0 + hy); s.lineTo(x0 + r, y0 + hy); s.quadraticCurveTo(x0, y0 + hy, x0, y0 + hy - r); s.lineTo(x0, y0 + r); s.quadraticCurveTo(x0, y0, x0 + r, y0);
  const bev = Math.min(r, dz / 3);
  const g = new THREE.ExtrudeGeometry(s, { depth: Math.max(0.1, dz - bev * 2), bevelEnabled: true, bevelThickness: bev, bevelSize: bev * 0.9, bevelSegments: segs(F.v, 3, 1), curveSegments: segs(F.v, 6, 2) });
  g.translate(0, 0, -(dz - bev * 2) / 2); return g;
}

// ---------------------------------------------------------------- 道具（actor_acts 的 hook 画的那些）
function buildProps(job, F, root, add, G) {
  const ops = job.frame.props || [];
  const role = job.spec.role;
  const baseZ = { back: -G.zA - 3, far: -G.zA, body: 0, front: G.zA * 0.75 };
  const placed = [];
  const bbox = (pts) => { let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9; for (const [x, y] of pts) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); } return { x0, y0, x1, y1 }; };
  // 叠在前面某个东西上的：放到它的正面上
  const zOn = (layer, bb, z0) => {
    let z = z0;
    for (const p of placed) {
      if (p.layer !== layer) continue;
      const cx = (bb.x0 + bb.x1) / 2, cy = (bb.y0 + bb.y1) / 2;
      if (cx >= p.bb.x0 - 1 && cx <= p.bb.x1 + 1 && cy >= p.bb.y0 - 1 && cy <= p.bb.y1 + 1) z = Math.max(z, p.zf);
    }
    return z;
  };
  for (const op of ops) {
    const layer = op.layer;
    const spec = op.spec || ['paper'];
    let color = specColor(spec, role);
    const steam = spec[0] === 'ink' && spec[1] != null && Math.abs(spec[1] - 0.35) < 0.01 && op.t === 'line';
    const groundish = (pts) => pts.every(([, y]) => y > -7);
    if (op.t === 'blot') {
      const bb = bbox(op.pts);
      if (bb.y1 > -3 && bb.y1 - bb.y0 < 8) { // 地上的影子
        const s = ground(F, (bb.x1 - bb.x0) / 2, (bb.x1 - bb.x0) / 2 * 0.7, 0.5 * (spec[1] ?? 0.3) / 0.34);
        s.position.set((bb.x0 + bb.x1) / 2, 0.15, baseZ.front); root.add(s);
        continue;
      }
      const m = F.mats.get(color, { opacity: 0.85 });
      const z = zOn(layer, bb, baseZ[layer]);
      const me = add(extrude(op.pts, 0.6, F), m); me.position.z = z + 0.2; me.castShadow = false;
      continue;
    }
    if (op.t === 'dot') {
      const r = Math.max(0.9, op.r);
      const bb = { x0: op.c[0] - r, x1: op.c[0] + r, y0: op.c[1] - r, y1: op.c[1] + r };
      const z = zOn(layer, bb, baseZ[layer]);
      const me = add(ball(r, 1, 1, 1, F), F.mats.get(color)); me.position.copy(V(op.c, z + (z !== baseZ[layer] ? r * 0.3 : 0)));
      placed.push({ layer, bb, zf: z + r });
      continue;
    }
    if (op.t === 'line') {
      const pts = op.pts; if (pts.length < 2) continue;
      const bb = bbox(pts);
      if (groundish(pts) && spec[0] === 'ink' && spec[1] != null && spec[1] < 0.5 && layer === 'back') { // 地上的水印
        for (let i = 0; i < pts.length - 1; i++) { const a = pts[i], b = pts[i + 1]; const s = ground(F, Math.hypot(b[0] - a[0], b[1] - a[1]) / 2 + 1.5, 2.6, 0.5); s.position.set((a[0] + b[0]) / 2, 0.12, G.zA); root.add(s); }
        continue;
      }
      const rr = Math.max(steam ? 0.6 : 0.75, op.w * 0.5);
      let z = zOn(layer, bb, baseZ[layer]);
      if (z !== baseZ[layer]) z += rr * 0.2;
      const m = steam ? F.mats.get('#FFFFFF', { opacity: 0.55 }) : F.mats.get(color, { rough: 0.5 });
      for (let i = 0; i < pts.length - 1; i++) {
        const a = V(pts[i], z), b = V(pts[i + 1], z);
        if (a.distanceTo(b) < 0.05) continue;
        const me = add(cone(a, b, rr, rr, F), m); if (steam) me.castShadow = false;
        if (i > 0) add(ball(rr, 1, 1, 1, F), m).position.copy(a);
      }
      add(ball(rr, 1, 1, 1, F), m).position.copy(V(pts[0], z)); add(ball(rr, 1, 1, 1, F), m).position.copy(V(pts[pts.length - 1], z));
      placed.push({ layer, bb, zf: z + rr });
      continue;
    }
    if (op.t === 'shape') {
      const pts = op.pts; const bb = bbox(pts);
      const bw = bb.x1 - bb.x0, bh = bb.y1 - bb.y0;
      // 圆的东西（球、碗、棋子）：做成球 / 扁球
      const cx = (bb.x0 + bb.x1) / 2, cy = (bb.y0 + bb.y1) / 2;
      let roundish = pts.length >= 10;
      if (roundish) { const rs = pts.map(([x, y]) => Math.hypot((x - cx) / (bw / 2 || 1), (y - cy) / (bh / 2 || 1))); roundish = Math.max(...rs) - Math.min(...rs) < 0.12; }
      const z0 = zOn(layer, bb, baseZ[layer]);
      const onTop = z0 !== baseZ[layer];
      if (roundish && !onTop) {
        const dz = layer === 'body' ? Math.min(bw, bh) : Math.min(bw, bh);
        const me = add(ball(1, 1, 1, 1, F), F.mats.get(color)); me.scale.set(bw / 2, bh / 2, Math.max(bw, bh) / 2 * (bh < bw * 0.6 ? 1 : 1)); me.position.copy(V([cx, cy], z0));
        placed.push({ layer, bb, zf: z0 + Math.max(bw, bh) / 2 });
        continue;
      }
      let dz = onTop ? 0.8 : layer === 'body' ? Math.min(Math.max(Math.min(bw, bh) * 0.9, 6), G.zA * 2) : Math.min(Math.max(Math.min(bw, bh) * 0.7, 2.5), 12);
      if (layer === 'body' && bh < 7 && bw > 15) dz = G.zA * 1.6; // 摊在腿上的本子、键盘、棋盘：横着有进深
      const me = add(extrude(pts, dz, F), F.mats.get(color));
      me.position.z = onTop ? z0 + 0.1 : z0 - dz / 2;
      placed.push({ layer, bb, zf: (onTop ? z0 + 0.1 : z0 - dz / 2) + dz });
    }
  }
}

function extrude(pts, depth, F) {
  const s = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, -y)));
  const bev = Math.min(1.2, depth / 3);
  const g = new THREE.ExtrudeGeometry(s, { depth: Math.max(0.1, depth - bev * 2), bevelEnabled: depth > 1.5, bevelThickness: bev, bevelSize: bev * 0.7, bevelSegments: segs(F.v, 2, 1), curveSegments: 4 });
  g.translate(0, 0, depth > 1.5 ? bev : 0);
  return g;
}

// 地上一团软影（接触影）：椭圆，中间深、往外淡
let BLOB = null;
function blobTex() {
  if (BLOB) return BLOB;
  const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d');
  const g = x.createRadialGradient(64, 64, 0, 64, 64, 64); g.addColorStop(0, 'rgba(0,0,0,1)'); g.addColorStop(0.45, 'rgba(0,0,0,0.6)'); g.addColorStop(1, 'rgba(0,0,0,0)');
  x.fillStyle = g; x.fillRect(0, 0, 128, 128); BLOB = new THREE.CanvasTexture(c); return BLOB;
}
function ground(F, rx, rz, a) {
  const m = new THREE.MeshBasicMaterial({ color: '#2A1C24', alphaMap: blobTex(), transparent: true, opacity: Math.max(0, Math.min(1, a)), depthWrite: false });
  const me = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), m); me.rotation.x = -Math.PI / 2; me.scale.set(rx, rz, 1); me.renderOrder = -1;
  return me;
}

function contactShadow(job, root) {
  const fr = job.frame, sp = job.spec;
  const g = new THREE.Group();
  if (fr.sleep) { const s = ground(null, 100, 26, 0.32); s.position.set(0, 0.1, 0); g.add(s); return g; }
  const zL = sp.waist * 0.27;
  for (const side of ['near', 'far']) {
    const L = fr.legs[side]; const h = -Math.max(L.heel[1], L.toe[1]);
    const a = 0.55 * Math.max(0, 1 - h / 40);
    const len = Math.abs(L.toe[0] - L.heel[0]) * 0.6 + 6;
    const s = ground(null, len * (1 + h / 60), 6 + h / 8, a); s.position.set((L.heel[0] + L.toe[0]) / 2 + 1, 0.1, side === 'near' ? zL : -zL); g.add(s);
  }
  const hipH = -fr.hip[1];
  const s = ground(null, sp.waist * 1.15, sp.waist * 0.75, 0.3 * Math.max(0.2, 1 - Math.max(0, hipH - sp.leg) / 80)); s.position.set(fr.hip[0] + 2, 0.08, 0); g.add(s);
  return g;
}

// ---------------------------------------------------------------- 睡觉：枕头 + 被窝 + 露出来的脑袋
function buildSleep(job, F, root, add) {
  const sp = job.spec, D = job.design; const r = sp.head;
  const br = job.frame.breathe || 0;
  const x0 = -92, x1 = 90;                       // 整个被窝在格子里（−100 ~ 100）
  const ph = r * 0.45;                           // 枕头厚
  const hx = x0 + r * 1.15;
  const pil = add(roundBox(r * 2.3, ph, r * 2.0, ph * 0.45, F), F.mats.get(PAL.cloth)); pil.position.set(hx - r * 0.15, ph / 2, 0);
  const head = new THREE.Group(); root.add(head); head.position.set(hx, ph + r * 0.92, 0);
  // 仰面躺着：先把脸转朝上（绕 z 90°），再往镜头这边偏一点（绕 x）
  head.rotation.set(42 * D2R, 0, 90 * D2R);
  const hs = D.headShape || [1, 0.95, 1];
  add(ball(r, hs[0], hs[1], hs[2], F, true), F.mats.get(F.skin, { map: faceTexture(F, 'sleep'), rough: 0.5 }), head);
  buildHair(F, head, r);
  // 被子：从下巴盖到脚，跟着呼吸起伏
  const qa = hx + r * 0.62, qw = x1 - qa, qh = r * 1.05 + sp.H * 0.08 + br;
  const qm = F.mats.get(mixHex(PAL.cloth, PAL[sp.role], 0.72));
  const q = add(roundBox(qw, qh, sp.waist * 2.6, Math.min(qh * 0.45, 10), F), qm); q.position.set(qa + qw / 2, qh / 2, 0);
  const fold = add(roundBox(r * 0.7, qh + 2, sp.waist * 2.7, 3, F), F.mats.get(PAL.cloth)); fold.position.set(qa + r * 0.35, (qh + 2) / 2, 0);
  for (let i = 0; i < 4; i++) { const d = add(ball(2.4, 1, 1, 0.45, F), F.mats.get(PAL.cloth)); d.position.set(qa + r * 1.2 + i * (qw - r * 1.6) / 3.2, qh * (0.35 + (i % 2) * 0.3), sp.waist * 1.3 + 0.4); }
  return root;
}

// ---------------------------------------------------------------- 渲染
let R = null, ENV = null;
export function obliqueCamera(view) {
  // 屏幕 x = x；屏幕 y（向下）= y + z·K。view：x0..x1、y0..y1 是屏幕上（世界像素）的取景框
  const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 1, 4000);
  cam.position.set(0, 0, 2000); cam.updateMatrixWorld();
  const w = view.x1 - view.x0, h = view.y1 - view.y0;
  const cx = (view.x0 + view.x1) / 2, cyUp = -(view.y0 + view.y1) / 2;
  const n = 1, f = 4000, Cz = 2000;
  // 视空间 (xv, yv, zv)，zv = z − Cz；屏幕向上 s = yv − K·(zv + Cz)
  const P = new THREE.Matrix4().set(
    2 / w, 0, 0, -2 * cx / w,
    0, 2 / h, -2 * K / h, (-2 * K * Cz - 2 * cyUp) / h,
    0, 0, -2 / (f - n), -(f + n) / (f - n),
    0, 0, 0, 1);
  cam.projectionMatrix.copy(P); cam.projectionMatrixInverse.copy(P).invert();
  return cam;
}

export function renderJob(job) {
  const W = job.px[0], H = job.px[1];
  if (!R) {
    R = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    R.setPixelRatio(1); R.shadowMap.enabled = true; R.shadowMap.type = THREE.PCFSoftShadowMap;
    R.toneMapping = THREE.ACESFilmicToneMapping; R.toneMappingExposure = 1.0; R.outputColorSpace = THREE.SRGBColorSpace;
    const pm = new THREE.PMREMGenerator(R); ENV = pm.fromScene(new RoomEnvironment(), 0.04).texture;
  }
  R.setSize(W, H, false);
  const scene = new THREE.Scene();
  scene.environment = ENV; scene.environmentIntensity = job.variant === 'toy' ? 0.55 : 0.35;
  if (job.bg) scene.background = new THREE.Color(job.bg);
  const mats = new Mats(job.variant);
  const fig = buildFigure(job, mats);
  scene.add(fig);
  if (job.shadow !== false) scene.add(contactShadow(job, fig));
  // 光：README 的太阳 + 半球光
  const dir = new THREE.Vector3(-0.55, 0.75, 0.62).normalize();
  const ctr = new THREE.Vector3(0, job.spec.H * 0.5, 0);
  const sun = new THREE.DirectionalLight('#FFE6C4', 3.2);
  sun.position.copy(ctr).add(dir.clone().multiplyScalar(600)); sun.target.position.copy(ctr);
  sun.castShadow = true; sun.shadow.mapSize.set(2048, 2048);
  const sc = sun.shadow.camera; sc.left = -170; sc.right = 170; sc.top = 170; sc.bottom = -170; sc.near = 100; sc.far = 1200;
  sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.6; sun.shadow.radius = 3;
  if (job.variant === 'lowpoly') { sun.shadow.radius = 1; }
  scene.add(sun, sun.target);
  scene.add(new THREE.HemisphereLight('#CFE0FF', '#B89A80', 0.9));
  // 正面一点补光，脸不至于发闷（场景里有墙反光）
  const fill = new THREE.DirectionalLight('#FFF1E0', 0.45); fill.position.set(200, 120, 600); scene.add(fill);
  const cam = obliqueCamera(job.view);
  R.setClearColor(0x000000, 0);
  R.render(scene, cam);
  const url = R.domElement.toDataURL('image/png');
  scene.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material) { if (o.material.map) o.material.map.dispose(); o.material.dispose(); } });
  return url;
}
