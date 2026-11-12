// 搭模型的小工具：斜投影的根、材质、圆角块、锥台、圆球、管子，和「拍一张」。
// 坐标照 ../README.md：世界 x 向右、y 向下、z 朝镜头（Z_REF = 120 那一面和贴图一一对上）；three 里是 (x, -y, z)。
// 光照 ../scene3d/render.js 的 LOOKS.toy（同一盒模型、同一个太阳）。
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';

export const K = 0.28, KX = 0.10, ZREF = 120;
export const LOOK = { sun: { dir: [-0.72, 0.55, 0.5], col: '#FFE2BC', k: 3.4 }, hemi: ['#CFE0FF', '#B89A80', 0.85], radius: 5, exposure: 1.0 };

// 定了种子的随机数（mulberry32）：同一个种子每回搭出来一样，四季的树骨架就不会跳
export function rng(seed) {
  let a = (seed * 2654435761) >>> 0;
  const f = () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  f.u = (a0, a1) => a0 + (a1 - a0) * f();
  f.i = (a0, a1) => Math.floor(a0 + (a1 - a0 + 1) * f());
  f.pick = arr => arr[Math.floor(f() * arr.length)];
  return f;
}

// 颜色：'#RRGGBB' 往另一个色拉一点
export function mixHex(a, b, t) {
  const ca = new THREE.Color(a), cb = new THREE.Color(b);
  return '#' + ca.lerp(cb, t).getHexString();
}

const UNIT_BALL = new THREE.IcosahedronGeometry(1, 3);
const UNIT_BALL_LO = new THREE.IcosahedronGeometry(1, 1);
const UNIT_BOX = new THREE.BoxGeometry(1, 1, 1);

export class Kit {
  constructor() {
    this.root = new THREE.Group();
    const M = new THREE.Matrix4();
    // 斜投影：近的往下（three 里往 -y）、往右挪一点
    M.set(1, 0, KX, -KX * ZREF,
      0, 1, -K, K * ZREF,
      0, 0, 1, 0,
      0, 0, 0, 1);
    this.root.matrixAutoUpdate = false; this.root.matrix.copy(M);
    this.mats = new Map();
  }

  // 材质：o.r 粗糙度，o.m 金属度，o.e 自发光色，o.ei 自发光强度，o.op 透明度
  mat(color, o = {}) {
    const key = [color, o.r, o.m, o.e, o.ei, o.op, o.flat].join('|');
    if (this.mats.has(key)) return this.mats.get(key);
    const p = { color: new THREE.Color(color), roughness: o.r ?? 0.6, metalness: o.m ?? 0.02, flatShading: !!o.flat };
    if (o.e) Object.assign(p, { emissive: new THREE.Color(o.e), emissiveIntensity: o.ei ?? 1.0 });
    if (o.op != null) Object.assign(p, { transparent: true, opacity: o.op, depthWrite: false });
    const m = new THREE.MeshStandardMaterial(p);
    this.mats.set(key, m);
    return m;
  }

  add(geo, mat, o = {}) {
    const me = new THREE.Mesh(geo, mat);
    me.castShadow = o.cast ?? true; me.receiveShadow = o.recv ?? true;
    if (o.lit) me.userData.lit = o.lit;      // 夜里亮的窗：0~1
    if (o.dark) me.userData.dark = true;     // 夜版里当挡光的黑块（默认就是）
    (o.parent || this.root).add(me);
    return me;
  }

  // 立着的块：x/y 是世界坐标左上角，w/h 宽高（h 向下），z0~z1 前后；round 圆角（null = 按最短边 × 0.12，最多 6）
  box(x, y, w, h, z0, z1, mat, o = {}) {
    w = Math.max(w, 0.3); h = Math.max(h, 0.3);
    const d = Math.max(z1 - z0, 0.3);
    const r = o.round ?? Math.min(6, Math.min(w, h, d) * 0.12);
    let me;
    if (r > 0.35) me = this.add(new RoundedBoxGeometry(w, h, d, 2, r), mat, o);
    else { me = this.add(UNIT_BOX, mat, o); me.scale.set(w, h, d); }
    me.position.set(x + w / 2, -(y + h / 2), z0 + d / 2);
    return me;
  }

  // 圆球（其实是细分的二十面体，平滑着色，玩具感）：中心 x,y,z，三个半径
  ball(x, y, z, rx, ry = rx, rz = rx, mat, o = {}) {
    const me = this.add(o.lo ? UNIT_BALL_LO : UNIT_BALL, mat, o);
    me.scale.set(rx, ry, rz);
    me.position.set(x, -y, z);
    if (o.rot) me.rotation.set(o.rot[0], o.rot[1], o.rot[2]);
    return me;
  }

  // 锥台：从 a 到 b（世界坐标 [x, y, z]，y 向下），两头半径 r0、r1
  cyl(a, b, r0, r1, mat, o = {}) {
    const A = new THREE.Vector3(a[0], -a[1], a[2]), B = new THREE.Vector3(b[0], -b[1], b[2]);
    const dir = B.clone().sub(A); const L = dir.length();
    if (L < 0.01) return null;
    const geo = new THREE.CylinderGeometry(r1, r0, L, o.seg ?? 12, 1, !!o.open);
    const me = this.add(geo, mat, o);
    me.position.copy(A.clone().add(B).multiplyScalar(0.5));
    me.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.normalize());
    return me;
  }

  // 顺着一串点的管子（柳条、电线、绳子）：pts 是世界坐标 [x, y, z]
  tube(pts, r, mat, o = {}) {
    const curve = new THREE.CatmullRomCurve3(pts.map(p => new THREE.Vector3(p[0], -p[1], p[2])));
    const geo = new THREE.TubeGeometry(curve, o.n ?? Math.max(6, pts.length * 4), r, o.seg ?? 5, false);
    if (o.taper) { // 越往梢越细：按管子长度方向把截面缩小
      const pos = geo.attributes.position, nseg = (o.n ?? Math.max(6, pts.length * 4)), ring = (o.seg ?? 5) + 1;
      const pt = new THREE.Vector3();
      for (let i = 0; i <= nseg; i++) {
        const t = i / nseg, s = 1 - (1 - o.taper) * t;
        curve.getPointAt(t, pt);
        for (let j = 0; j < ring; j++) {
          const k = i * ring + j;
          pos.setXYZ(k, pt.x + (pos.getX(k) - pt.x) * s, pt.y + (pos.getY(k) - pt.y) * s, pt.z + (pos.getZ(k) - pt.z) * s);
        }
      }
      geo.computeVertexNormals();
    }
    return this.add(geo, mat, o);
  }

  // 横着挤出来的面（三角屋顶、坡顶）：pts 是世界 x/y 的多边形，z0~z1 前后
  prism(pts, z0, z1, mat, o = {}) {
    const sh = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, -y)));
    const geo = new THREE.ExtrudeGeometry(sh, { depth: z1 - z0, bevelEnabled: !!o.bevel, bevelSize: 1.2, bevelThickness: 1.2, bevelSegments: 2 });
    const me = this.add(geo, mat, o);
    me.position.z = z0;
    return me;
  }
}

// 横着无缝：一样东西在 off = -W、0、+W 各搭一遍（只搭落在镜头附近的，省得白搭）
export function wrap(W, x0, x1, fn, margin = 420) {
  for (const off of [-W, 0, W]) if (x1 + off > -margin && x0 + off < W + margin) fn(off);
}

// 拍一张：框住世界 [x0, x0+w] × [y0, y0+h]，S 倍出图；返回白天的 RGBA 和（要的话）夜里亮窗的灰度
export function shoot(kit, { x0 = 0, y0 = 0, w, h, S = 2, ao = true, aoRadius = 24, lit = false, shadowMap = 4096 }) {
  const W = Math.round(w * S), H = Math.round(h * S);
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
  renderer.setPixelRatio(1); renderer.setSize(W, H);
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = LOOK.exposure;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.setClearColor(0x000000, 0);
  const scene = new THREE.Scene();
  scene.add(kit.root);
  const cam = new THREE.OrthographicCamera(x0, x0 + w, -y0, -(y0 + h), 10, 20000);
  cam.position.set(0, 0, 8000); cam.lookAt(0, 0, 0); cam.updateProjectionMatrix();

  scene.add(new THREE.HemisphereLight(LOOK.hemi[0], LOOK.hemi[1], LOOK.hemi[2]));
  const sun = new THREE.DirectionalLight(LOOK.sun.col, LOOK.sun.k);
  const d = new THREE.Vector3(...LOOK.sun.dir).normalize();
  const cx = x0 + w / 2, cy = -(y0 + h / 2);
  sun.position.set(cx + d.x * 4000, cy + d.y * 4000, d.z * 4000);
  sun.target.position.set(cx, cy, 0); scene.add(sun.target);
  sun.castShadow = true;
  const R = Math.max(w, h) / 2 + 400;
  Object.assign(sun.shadow.camera, { left: -R, right: R, top: R, bottom: -R, near: 100, far: 9000 });
  sun.shadow.mapSize.set(shadowMap, shadowMap); sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.6; sun.shadow.radius = LOOK.radius;
  scene.add(sun);

  const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType, samples: 4 }));
  composer.addPass(new RenderPass(scene, cam));
  if (ao) {
    try {
      const p = new GTAOPass(scene, cam, W, H);
      p.updateGtaoMaterial({ radius: aoRadius, distanceExponent: 1.4, thickness: 6, scale: 1.0 });
      p.blendIntensity = 0.8;
      composer.addPass(p);
    } catch (e) { console.log('no ao', e.message); }
  }
  composer.addPass(new OutputPass());
  composer.render();
  const out = { color: renderer.domElement.toDataURL('image/png') };

  if (lit) {
    // 夜版：别的都是黑的挡光块，亮着的窗按 userData.lit 发白光；不打光、不调色，读出来就是灰度
    const black = new THREE.MeshBasicMaterial({ color: 0x000000 });
    const lits = new Map();
    const keep = [];
    kit.root.traverse(o => {
      if (!o.isMesh) return;
      keep.push([o, o.material]);
      if (o.material.transparent) { o.visible = false; return; } // 烟、雾：夜里看不见
      const v = o.userData.lit;
      if (v) {
        const k = Math.round(v * 100);
        if (!lits.has(k)) lits.set(k, new THREE.MeshBasicMaterial({ color: new THREE.Color(v, v, v), toneMapped: false }));
        o.material = lits.get(k);
      } else o.material = black;
    });
    renderer.toneMapping = THREE.NoToneMapping;
    renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
    renderer.setClearColor(0x000000, 1);
    renderer.shadowMap.enabled = false;
    renderer.setRenderTarget(null);
    renderer.render(scene, cam);
    out.lit = renderer.domElement.toDataURL('image/png');
    for (const [o, m] of keep) { o.material = m; o.visible = true; }
  }
  renderer.dispose();
  return out;
}
