// 仿真微缩（real）的 look test：同一份显示列表（scene3d/out/<图>.json）搭的模型，换成程序化 PBR 材质（out/tex，textures.py 生成）、
// 墙根和窗台下的脏（贴花）、天空环境光 + 低一点的暖太阳、软影、GTAO，再按「拍一盒真模型」的路子做后期：移轴景深（焦平面落在人走的那条线）、
// 色差、暗角、颗粒、胶片的影调曲线。两个主角（pose3d/figure.js 的小人）摆进同一个场景、同一套光，换成手涂树脂手办的材质。
// 不动 toy / clay / lowpoly：这里只是继承 scene3d 的 Builder，换掉 mat() 和几样专门的搭法。
//
// 坐标照 ../README.md：世界 x 右、y 下、z 朝镜头；three 里 (x, -y, z)；斜投影在 builder.root.matrix 上（导 glb 时拿掉）。
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';
import { Builder, K, ZREF } from '../scene3d/build.js';
import { buildFigure, PAL, Mats } from '../pose3d/figure.js';
import { buildTree, TREES } from '../layers3d/trees.js';
import { mergeVertices, mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const TEX = './out/tex/';
const SETS = ['brick_red_tianjin', 'brick_grey', 'plaster', 'plaster_cement', 'paint', 'painted_wood_green', 'painted_wood_red', 'wood',
  'concrete_pavers', 'curb_stone', 'asphalt', 'concrete', 'roof_felt', 'metal', 'sheet_metal_rusty', 'glass', 'fabric', 'skin', 'hair', 'foliage'];
const DECALS = ['decal_grime_base', 'decal_streaks', 'decal_ground_dirt'];
// 一张贴图铺多大（世界像素）：和 materials.json 的 tile_m × 100 一样；小人身上的另算（FIG_TILE）
const TILE = { brick_red_tianjin: 128, brick_grey: 128, plaster: 256, plaster_cement: 256, paint: 96, painted_wood_green: 128, painted_wood_red: 128, wood: 128,
  concrete_pavers: 160, curb_stone: 100, asphalt: 192, concrete: 128, roof_felt: 128, metal: 96, sheet_metal_rusty: 100, glass: 64, fabric: 22, skin: 30, hair: 14, foliage: 70 };
const FIG_TILE = { fabric: 22, skin: 30, hair: 14, paint: 30 };

// ---------------------------------------------------------------- 贴图
export async function loadTextures(renderer) {
  const L = new THREE.TextureLoader();
  const aniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  const ld = async (f, srgb) => {
    try {
      const t = await L.loadAsync(TEX + f);
      t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = aniso;
      if (srgb) t.colorSpace = THREE.SRGBColorSpace;
      return t;
    } catch (e) { return null; }
  };
  const T = {};
  await Promise.all(SETS.map(async (s) => {
    const [map, normal, rough, ao] = await Promise.all([ld(`${s}_albedo.png`, true), ld(`${s}_normal.png`), ld(`${s}_rough.png`), ld(`${s}_ao.png`)]);
    T[s] = { map, normal, rough, ao };
  }));
  await Promise.all(DECALS.map(async (s) => { const t = await ld(`${s}_albedo.png`, true); t.wrapT = THREE.ClampToEdgeWrapping; T[s] = { map: t }; }));
  return T;
}

// 物件色 → 真实一点的颜色：降饱和、压一点亮度、往暖灰里拉（像手涂的模型漆，不是塑料）
function natural(rgb, s = 0.78, v = 0.9) {
  const m = (rgb[0] + rgb[1] + rgb[2]) / 3;
  return rgb.map((x, i) => Math.max(0, Math.min(255, (m + (x - m) * s) * v + [3, 1, -3][i])));
}
const cssc = (c) => new THREE.Color(`rgb(${c.map((x) => x | 0).join(',')})`);

export class RealMats {
  constructor(T) { this.T = T; this.cache = new Map(); }
  // set：贴图组；color：THREE.Color（乘在贴图上）；o：rough / metal / ns（法线强度）/ physical 参数 / tile
  make(set, color, o = {}) {
    const key = set + color.getHexString() + JSON.stringify(o);
    if (this.cache.has(key)) return this.cache.get(key);
    const t = this.T[set] || {};
    const P = o.phys ? THREE.MeshPhysicalMaterial : THREE.MeshStandardMaterial;
    const m = new P({ color, map: t.map, normalMap: t.normal, roughnessMap: t.rough, aoMap: t.ao, roughness: o.rough ?? 1, metalness: o.metal ?? 0, envMapIntensity: o.env ?? 1 });
    if (t.normal) m.normalScale.set(o.ns ?? 1, o.ns ?? 1);
    if (t.ao) m.aoMapIntensity = o.ao ?? 1;
    if (o.phys) Object.assign(m, o.phys);
    m.name = o.name || set;
    m.userData.tile = o.tile ?? TILE[set];
    this.cache.set(key, m); return m;
  }
  glass(c) {
    const col = new THREE.Color().setRGB(c.r * 0.35 + 0.02, c.g * 0.4 + 0.025, c.b * 0.45 + 0.03);
    return this.make('glass', col, { rough: 1, metal: 0, env: 1.6, phys: { clearcoat: 0.6, clearcoatRoughness: 0.08, reflectivity: 0.7 }, name: 'glass' });
  }
}

// ---------------------------------------------------------------- 按世界尺寸铺 UV：每个三角形按法线挑一个投影面（box 投影）
// 贴图在物件之间是连着的（同一面墙上的东西纹理接得上）；拼缝处在微缩尺度里看不出来
export function boxUV(mesh, toSpace, tileOverride) {
  const m = mesh.material; const tile = tileOverride ?? (m && m.userData.tile);
  if (!tile || !mesh.geometry || (m.userData && m.userData.keepUV)) return;
  let g = mesh.geometry.index ? mesh.geometry.toNonIndexed() : mesh.geometry.clone();
  const p = g.attributes.position; const n = p.count;
  const uv = new Float32Array(n * 2);
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3(), e1 = new THREE.Vector3(), e2 = new THREE.Vector3();
  const M = toSpace;
  for (let i = 0; i < n; i += 3) {
    a.fromBufferAttribute(p, i).applyMatrix4(M); b.fromBufferAttribute(p, i + 1).applyMatrix4(M); c.fromBufferAttribute(p, i + 2).applyMatrix4(M);
    e1.subVectors(b, a); e2.subVectors(c, a); e1.cross(e2);
    const ax = Math.abs(e1.x), ay = Math.abs(e1.y), az = Math.abs(e1.z);
    for (let k = 0; k < 3; k++) {
      const v = k === 0 ? a : k === 1 ? b : c;
      let u, w;
      if (ay >= ax && ay >= az) { u = v.x; w = -v.z; }        // 顶面、地面
      else if (az >= ax) { u = v.x; w = v.y; }                // 正面
      else { u = v.z; w = v.y; }                              // 侧面
      uv[(i + k) * 2] = u / tile; uv[(i + k) * 2 + 1] = w / tile;
    }
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  mesh.geometry = g;
}

// ---------------------------------------------------------------- 场景：继承 scene3d 的 Builder
export class RealBuilder extends Builder {
  constructor(data, RM, T) {
    super(data, 'toy');
    this.V = Object.assign({}, this.V, { round: 0.05, s: 1, v: 1, noise: 0 });   // 真房子边角利落，模型手工做的只留一点点圆
    this.noise = null;
    this.RM = RM; this.T = T;
    this.decals = [];
  }

  mat(rgb, kind = 'prop', opt = {}) {
    const key = rgb.map((v) => v | 0).join(',') + kind + (opt.emissive || '') + (opt.brick ? 'b' : '');
    if (this.mats.has(key)) return this.mats.get(key);
    const c = natural(rgb);
    const col = cssc(c);
    const hsl = {}; col.getHSL(hsl);
    const lum = 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b;
    let m;
    if (opt.emissive) {
      m = this.RM.make('paint', col, { rough: 0.6 }).clone();
      m.emissive = new THREE.Color(opt.emissive); m.emissiveIntensity = opt.ei ?? 1.2;
    } else if (kind === 'glass') m = this.RM.glass(col);
    else if (kind === 'metal') m = this.RM.make('metal', col, { rough: 1, metal: 0.2, ns: 0.6 });
    else if (opt.brick) {
      // 红砖：贴图本身就是砖色，物件色只当「这栋楼的砖深一点浅一点」
      const grey = hsl.s < 0.18;
      const ref = grey ? [0.33, 0.33, 0.32] : [0.5, 0.11, 0.07];
      const k = (lum / (0.2126 * ref[0] + 0.7152 * ref[1] + 0.0722 * ref[2]));
      const t = Math.max(0.75, Math.min(1.25, Math.pow(k, 0.35)));
      m = this.RM.make(grey ? 'brick_grey' : 'brick_red_tianjin', new THREE.Color(t, t * 0.98, t * 0.96), { ns: 1.2 });
    } else if (kind === 'wall' && (rgb[0] | 0) === 0xB0 && (rgb[1] | 0) === 0x94 && (rgb[2] | 0) === 0x7C) {
      // 街上一层的门脸（老画里拿暖灰铺的一大片）：水泥砂浆抹的底层，上头才是红砖
      m = this.RM.make('plaster_cement', new THREE.Color(1.12, 1.08, 1.02), { ns: 1 });
    } else if (kind === 'wall') {
      if (lum < 0.035) m = this.RM.make('plaster', col.clone().multiplyScalar(0.8), { ns: 0.6 });       // 门洞、胡同口：暗处
      else m = this.RM.make('plaster', col, { ns: 0.9 });
    } else {
      const h = hsl.h * 360;
      const woody = h > 12 && h < 45 && hsl.s > 0.2 && hsl.s < 0.75 && hsl.l > 0.12 && hsl.l < 0.5;
      if (woody) m = this.RM.make('wood', new THREE.Color().copy(col).lerp(new THREE.Color(1, 1, 1), 0.15).multiplyScalar(1.9), { ns: 1 });
      else m = this.RM.make('paint', col, { ns: 0.8 });
    }
    this.mats.set(key, m); return m;
  }

  // 认得的东西里，地面、楼板换搭法；别的照旧
  custom(ctx) {
    const n = ctx.name, a = ctx.call.a;
    const W = this.d.width;
    if (n === 'ground_street') {
      const y = a[1] ?? 760;
      const RM = this.RM;
      const walk = RM.make('concrete_pavers', new THREE.Color(1, 1, 1), { ns: 1.0 });
      const curbM = RM.make('curb_stone', new THREE.Color(1, 1, 1), { ns: 1.0 });
      const road = RM.make('asphalt', new THREE.Color(1, 1, 1), { ns: 1.2 });
      this.box({ x0: -400, x1: W + 400, y0: y, y1: y + 18, w: W + 800, h: 18 }, -300, 290, walk, 0.3);
      this.box({ x0: -400, x1: W + 400, y0: y, y1: y + 30, w: W + 800, h: 30 }, 290, 312, curbM, 1.2);   // 路牙：比人行道高一点点
      // 路沟（水箅子那条暗缝）
      this.box({ x0: -400, x1: W + 400, y0: y + 29.5, y1: y + 30.5, w: W + 800, h: 1 }, 312, 330, RM.make('concrete', new THREE.Color(0.45, 0.43, 0.4), {}), 0);
      this.box({ x0: -400, x1: W + 400, y0: y + 30, y1: y + 60, w: W + 800, h: 30 }, 312, 1400, road, 0);
      // 车道线：旧了、磨掉一截一截（漆 + 透明度）
      const line = RM.make('paint', new THREE.Color(0.78, 0.76, 0.7), { rough: 1, ns: 0.4 });
      for (let x = 0; x < W + 200; x += 260) {
        const me = this.box({ x0: x, x1: x + 120, y0: y + 29.7, y1: y + 30.2, w: 120, h: 0.5 }, 560, 578, line, 0);
        me.castShadow = false;
      }
      // 地上贴着墙根的一溜灰土
      this.groundDecal(-400, W + 400, y, 0.2, 46);
      return;
    }
    if (n === 'slab') {
      const [x0, x1, y0, y1] = a;
      const dz = (x1 - x0) < 600 ? 80 : 300;
      // 最上头那块是屋顶（油毡）；中间的楼板上面是屋里的地：刷了枣红漆的水泥地（老公房常见）
      const roof = y0 <= this.floors[0] + 4;
      const m = roof ? this.RM.make('roof_felt', new THREE.Color(1.15, 1.08, 1.0), { ns: 1 }) : this.RM.make('concrete', new THREE.Color(0.78, 0.5, 0.4), { ns: 0.8, rough: 0.85 });
      const me = this.box({ x0, x1, y0, y1, w: x1 - x0, h: y1 - y0 }, -dz, dz, m, 0.5);
      if (dz > 100) me.castShadow = false;
      return;
    }
    if (n === 'tree') {    // 树坑：一圈路牙石
      const [x, base] = a;
      this.box({ x0: x - 46, x1: x + 46, y0: base - 3, y1: base + 1, w: 92, h: 4 }, 30, 110, this.RM.make('curb_stone', new THREE.Color(0.9, 0.9, 0.9), {}), 0.5);
      this.box({ x0: x - 40, x1: x + 40, y0: base - 2, y1: base + 0.5, w: 80, h: 2.5 }, 36, 104, this.RM.make('roof_felt', new THREE.Color(0.55, 0.42, 0.3), {}), 0);
      return;
    }
    return super.custom(ctx);
  }

  // 墙根的脏：贴在立着的大块（墙、门脸、门）最底下一溜
  placeObj(ob, o) {
    super.placeObj(ob, o);
    if (!ob.mesh || ob.flat) return;
    // 窗户的身子是玻璃（老画里是浅色一块）：暗、反着天
    if (ob.ctx && ob.ctx.name === 'window' && !ob.dark) { ob.mesh.material = this.RM.glass(cssc(natural(ob.col))); ob.kind = 'glass'; return; }
    const b = ob.b, floor = this.floorOf(b.y1);
    if (Math.abs(b.y1 - floor) > 6 || b.h < 90 || b.w < 30) return;
    if (!(ob.kind === 'wall' || (ob.ctx && ob.ctx.wall))) return;
    const h = Math.min(70, b.h * 0.45);
    this.wallDecal('decal_grime_base', b.x0, b.x1, floor - h, floor + 0.5, ob.z1 + 0.12, 256, 0.9);
  }

  // 窗台下的雨水印
  line(o, cur, ctx) {
    super.line(o, cur, ctx);
    const w = o.w || 2;
    if (ctx && ctx.name === 'window' && o.p.length === 2 && Math.abs(o.p[0][1] - o.p[1][1]) < 1 && w >= 3) {
      const x0 = Math.min(o.p[0][0], o.p[1][0]), x1 = Math.max(o.p[0][0], o.p[1][0]); const y = o.p[0][1] + 4;
      const hh = Math.min(120, (x1 - x0) * 1.1);
      this.wallDecal('decal_streaks', x0 + 2, x1 - 2, y, y + hh, 0.08, 0, 0.75);
    }
  }

  wallDecal(set, x0, x1, y0, y1, z, tileW, op) {
    const T = this.T[set]; if (!T) return;
    const w = x1 - x0, h = y1 - y0;
    const g = new THREE.PlaneGeometry(w, h);
    if (tileW) { const uv = g.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setX(i, uv.getX(i) * w / tileW + x0 / tileW); }
    const m = new THREE.MeshStandardMaterial({ map: T.map, transparent: true, opacity: op, depthWrite: false, roughness: 0.95, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2, name: set });
    m.userData.keepUV = true;
    const me = new THREE.Mesh(g, m); me.receiveShadow = true; me.castShadow = false; me.name = set;
    me.position.set(x0 + w / 2, -(y0 + h / 2), z); me.renderOrder = 2;
    this.root.add(me); return me;
  }

  groundDecal(x0, x1, floor, z0, z1) {
    const T = this.T.decal_ground_dirt; if (!T) return;
    const w = x1 - x0, d = z1 - z0;
    const g = new THREE.PlaneGeometry(w, d);
    const uv = g.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setX(i, uv.getX(i) * w / 256);
    const m = new THREE.MeshStandardMaterial({ map: T.map, transparent: true, opacity: 0.85, depthWrite: false, roughness: 0.95, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2, name: 'decal_ground_dirt' });
    m.userData.keepUV = true;
    const me = new THREE.Mesh(g, m); me.rotation.x = -Math.PI / 2; me.receiveShadow = true; me.name = 'decal_ground_dirt';
    me.position.set(x0 + w / 2, -floor + 0.4, z0 + d / 2); me.renderOrder = 2;
    this.root.add(me);
  }
}

// ---------------------------------------------------------------- 小人：手涂的树脂手办
export class FigureMats {
  constructor(RM, opt = {}) { this.RM = RM; this.cache = new Map(); this.v = 'toy'; this.scale = opt.scale || 1; }
  get(color, o = {}) {
    const key = color + JSON.stringify(Object.assign({}, o, { map: o.map ? o.map.uuid : null }));
    if (this.cache.has(key)) return this.cache.get(key);
    const c0 = new THREE.Color(color);
    // 模型漆：比塑料稍灰一点、暗一点
    const hsl = {}; c0.getHSL(hsl);
    const c = new THREE.Color().setHSL(hsl.h, hsl.s * 0.86, hsl.l * 0.97);
    const S = this.scale;
    const lc = color.toLowerCase();
    let m;
    const skins = [PAL.skin, PAL.skinOld].map((s) => s.toLowerCase());
    if (o.map) {
      // 脸：画上去的五官在 map 上；哑光，一点暖的 sheen（像皮肤底下透出来的红）
      m = new THREE.MeshPhysicalMaterial({ map: o.map, roughness: 0.58, sheen: 0.35, sheenColor: new THREE.Color('#FF9C7A'), sheenRoughness: 0.55, name: 'face' });
      m.userData.keepUV = true;
    } else if (skins.includes(lc)) {
      m = this.RM.make('skin', c, { rough: 1, ns: 0.5, tile: FIG_TILE.skin * S, phys: { sheen: 0.35, sheenColor: new THREE.Color('#FF9C7A'), sheenRoughness: 0.55 }, name: 'skin' });
    } else if (lc === PAL.hair.toLowerCase() || lc === PAL.grey.toLowerCase()) {
      m = this.RM.make('hair', c, { rough: 1, ns: 1.2, tile: FIG_TILE.hair * S, phys: { clearcoat: 0.25, clearcoatRoughness: 0.45, sheen: 0.2, sheenColor: new THREE.Color('#a08070'), sheenRoughness: 0.4 }, name: 'hair' });
    } else if ([PAL.gold, PAL.glasses].map((s) => s.toLowerCase()).includes(lc)) {
      m = this.RM.make('metal', c, { rough: 0.6, metal: 0.6, tile: 30, name: 'metal' });
    } else if ([PAL.shoe, PAL.sole, PAL.cane, PAL.belt].map((s) => s.toLowerCase()).includes(lc)) {
      m = this.RM.make('paint', c, { rough: 0.9, ns: 0.6, tile: FIG_TILE.paint * S, name: 'paint_' + c.getHexString() });
    } else {
      const sheenC = c.clone().lerp(new THREE.Color(1, 1, 1), 0.35);
      m = this.RM.make('fabric', c, { rough: 1, ns: 0.9, tile: FIG_TILE.fabric * S, phys: { sheen: 0.6, sheenColor: sheenC, sheenRoughness: 0.7 }, name: 'fabric_' + c.getHexString() });
    }
    if (o.opacity != null) { m = m.clone(); m.transparent = true; m.opacity = o.opacity; m.depthWrite = false; }
    this.cache.set(key, m); return m;
  }
}

export function makeFigure(F, frameKey, RM, opt = {}) {
  const job = { spec: F.spec, frame: F.frames[frameKey], design: F.design, variant: 'toy' };
  const fm = new FigureMats(RM, opt);
  const g = buildFigure(job, fm);
  g.name = `${F.spec.role}_${F.spec.stage}_${frameKey}`;
  return g;
}

// ---------------------------------------------------------------- 树（layers3d/trees.js 的骨架）换成模型树：海绵团子 + 树皮
function lumpyBall(seed) {
  const g = mergeVertices(new THREE.IcosahedronGeometry(1, 3));
  const p = g.attributes.position; const v = new THREE.Vector3();
  const r = (k) => Math.sin(k * 12.9898 + seed * 78.233) * 43758.5453 % 1;
  const dirs = []; for (let i = 0; i < 14; i++) dirs.push(new THREE.Vector3(r(i * 3 + 1), r(i * 3 + 2), r(i * 3 + 3)).normalize());
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i).normalize();
    let d = 1;
    for (let k = 0; k < dirs.length; k++) d += 0.09 * Math.pow(Math.max(0, v.dot(dirs[k])), 6) * (k % 2 ? 1 : -0.7);
    // 海绵颗粒：几组不同方向、不同频率的波叠起来
    for (let k = 0; k < 10; k++) { const D = dirs[k], f = 9 + k * 2.3; d += (0.05 - k * 0.0035) * Math.sin((v.x * D.y + v.y * D.z + v.z * D.x) * f + k * 1.7 + seed); }
    p.setXYZ(i, v.x * d, v.y * d, v.z * d);
  }
  g.computeVertexNormals();
  return g;
}
// 一团叶子 = 七八个小海绵团挤在一起（模型树的做法），不是一个大球
function clump(seed) {
  const parts = [];
  const r = (k) => { const v = Math.sin(k * 91.17 + seed * 47.3) * 43758.5453; return v - Math.floor(v); };
  const n = 9;
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n, el = Math.asin(1 - 2 * t), az = i * 2.39996 + seed;
    const s = 0.42 + r(i) * 0.18;
    const g = lumpyBall(seed * 13 + i).clone();
    g.scale(s, s * 0.9, s);
    g.translate(Math.cos(el) * Math.cos(az) * (1 - s * 0.85), Math.sin(el) * (1 - s * 0.85) * 0.9, Math.cos(el) * Math.sin(az) * (1 - s * 0.85));
    parts.push(g);
  }
  const core = lumpyBall(seed + 99).clone(); core.scale(0.75, 0.7, 0.75); parts.push(core);
  return mergeGeometries(parts.map((g) => { g.deleteAttribute('uv'); return g; }));
}

function toyTree(kind, x, base, height) {
  const { kit } = buildTree(kind, 'summer');
  const [Wd, Hd, th] = TREES[kind]; const s = height / th;
  const g = new THREE.Group(); g.position.set(x - (Wd / 2) * s, -base + (Hd - 4) * s, ZREF * (1 - s)); g.scale.setScalar(s);
  for (const me of kit.root.children.slice()) g.add(me);
  return g;
}

export function makeTree(kind, season, x, base, height, RM) {
  const { kit } = buildTree(kind, season);
  const [Wd, Hd, th] = TREES[kind];
  const s = height / th;
  const g = new THREE.Group(); g.name = `tree_${kind}`;
  g.position.set(x - (Wd / 2) * s, -base + (Hd - 4) * s, ZREF * (1 - s)); g.scale.setScalar(s);
  const balls = [clump(1), clump(2), clump(3), clump(4)];
  let i = 0;
  for (const me of kit.root.children.slice()) {
    const c = me.material.color; const hsl = {}; c.getHSL(hsl);
    const green = hsl.h > 0.15 && hsl.h < 0.45 && hsl.s > 0.2;
    if (green && me.geometry.type === 'IcosahedronGeometry') {
      me.geometry = balls[i++ % 4];
      const col = new THREE.Color().setHSL(hsl.h * 0.97 + (i % 3 - 1) * 0.012, hsl.s * 0.7, hsl.l * (0.72 + (i % 4) * 0.05));
      me.material = RM.make('foliage', col, { rough: 1, ns: 2.5, tile: 70, ao: 1.0 });
    } else {
      const col = c.clone().multiplyScalar(0.8);
      me.material = RM.make('hair', col, { rough: 1, ns: 2.5, tile: 40, name: 'bark' });
    }
    me.castShadow = true; me.receiveShadow = true;
    g.add(me);
  }
  return g;
}

// ---------------------------------------------------------------- 远景、中景：印出来的背景板（模型铁路那种），按远近罩一层雾
async function backdropTex(file, haze, hazeCol, raw = false) {
  const img = new Image(); img.src = file; await img.decode();
  const c = document.createElement('canvas'); c.width = img.width; c.height = img.height; const x = c.getContext('2d');
  x.drawImage(img, 0, 0);
  // 降饱和 + 罩雾（只罩在有东西的地方）
  if (!raw) x.globalCompositeOperation = 'saturation'; else x.globalAlpha = 0; x.fillStyle = `rgba(128,128,128,${0.45})`; x.fillRect(0, 0, c.width, c.height);
  x.globalCompositeOperation = 'source-atop'; x.fillStyle = hazeCol; x.globalAlpha = haze; x.fillRect(0, 0, c.width, c.height);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = THREE.RepeatWrapping; t.anisotropy = 4;
  return t;
}
export async function makeBackdrop(era, x0, x1, toy = false) {
  const g = new THREE.Group(); g.name = 'backdrop';
  // [文件, z, 屏幕上底边在哪（世界 y）, 高（世界像素）, 雾]
  const L = [['far', -1500, 236, 620, 0.42], ['mid', -760, 362, 640, 0.18]];
  for (const [k, z, sb, h, haze] of L) {
    const t = await backdropTex(`../layers3d/out/raw/${k}_${era}.png`, toy ? 0 : haze, '#C9D3DC', toy);
    const w = 2048, reps = Math.ceil((x1 - x0 + 800) / w) + 1;
    const geo = new THREE.PlaneGeometry(w * reps, h);
    const uv = geo.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setX(i, uv.getX(i) * reps);
    const m = new THREE.MeshStandardMaterial({ map: t, alphaTest: 0.5, roughness: 0.92, metalness: 0, name: `backdrop_${k}`, envMapIntensity: 0.6 });
    m.userData.keepUV = true;
    const me = new THREE.Mesh(geo, m); me.name = `backdrop_${k}`;
    const yb = sb - (z - ZREF) * K;   // 斜投影：远的往上挪，补回来
    const cx = Math.floor((x0 - 400) / w) * w + (w * reps) / 2;
    me.position.set(cx, -(yb - h / 2), z);
    me.receiveShadow = false; me.castShadow = false;
    g.add(me);
  }
  return g;
}

// ---------------------------------------------------------------- 天：渐变 + 太阳那一侧亮一点（背景和环境光共用）
function skyCanvas(w, h, equirect) {
  const c = document.createElement('canvas'); c.width = w; c.height = h; const x = c.getContext('2d');
  const g = x.createLinearGradient(0, 0, 0, h);
  if (equirect) {
    g.addColorStop(0, '#6E95C4'); g.addColorStop(0.42, '#BCD0E2'); g.addColorStop(0.5, '#ECE4D6'); g.addColorStop(0.52, '#9A8E80'); g.addColorStop(1, '#5E564E');
    x.fillStyle = g; x.fillRect(0, 0, w, h);
    // 太阳（左上前方）：一团很亮的
    const sx = w * 0.62, sy = h * 0.22;
    const rg = x.createRadialGradient(sx, sy, 0, sx, sy, w * 0.08); rg.addColorStop(0, 'rgba(255,240,215,1)'); rg.addColorStop(0.2, 'rgba(255,230,200,0.7)'); rg.addColorStop(1, 'rgba(255,230,200,0)');
    x.fillStyle = rg; x.fillRect(0, 0, w, h);
  } else {
    g.addColorStop(0, '#8EAFCF'); g.addColorStop(0.5, '#BFD1DF'); g.addColorStop(1, '#E9E2D4');
    x.fillStyle = g; x.fillRect(0, 0, w, h);
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  if (equirect) t.mapping = THREE.EquirectangularReflectionMapping;
  return t;
}

// ---------------------------------------------------------------- 后期：景深（移轴：焦平面落在人走的那一线）
const DOF = {
  uniforms: { tDiffuse: { value: null }, tZ: { value: null }, res: { value: new THREE.Vector2() }, maxR: { value: 14 },
    yTop: { value: 0 }, yBot: { value: 1 }, yF: { value: 712 }, band: { value: 95 }, ramp: { value: 390 }, zRef: { value: ZREF }, tsK: { value: 1.0 } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `
    uniform sampler2D tDiffuse, tZ; uniform vec2 res; uniform float maxR, yTop, yBot, yF, band, ramp, zRef, tsK;
    varying vec2 vUv;
    float coc(vec2 uv) {
      float z = texture2D(tZ, uv).r - 4000.0;
      float sy = mix(yBot, yTop, uv.y);
      float ts = smoothstep(band, band + ramp, abs(sy - yF)) * tsK;
      float dz = z - zRef;
      float fr = smoothstep(50.0, 650.0, dz);
      float bk = smoothstep(160.0, 1500.0, -dz);
      return clamp(max(ts, max(fr, bk)), 0.0, 1.0) * maxR;
    }
    void main() {
      float c0 = coc(vUv);
      vec3 base = texture2D(tDiffuse, vUv).rgb;
      if (c0 < 0.6) { gl_FragColor = vec4(base, 1.0); return; }
      vec3 acc = base; float ws = 1.0;
      for (int i = 0; i < N; i++) {
        float fi = float(i);
        float rr = sqrt((fi + 0.5) / float(N)) * c0;
        float a = fi * 2.39996323;
        vec2 uv = vUv + vec2(cos(a), sin(a)) * rr / res;
        float ct = coc(uv);
        float w = smoothstep(rr - 1.5, rr + 0.5, ct + 0.75);
        vec3 c = texture2D(tDiffuse, uv).rgb;
        float l = dot(c, vec3(0.299, 0.587, 0.114));
        w *= 1.0 + 2.5 * smoothstep(0.72, 0.98, l);
        acc += c * w; ws += w;
      }
      gl_FragColor = vec4(acc / ws, 1.0);
    }`,
};
// 镜头和底片：色差、暗角、影调曲线、颗粒
const FILM = {
  uniforms: { tDiffuse: { value: null }, res: { value: new THREE.Vector2() }, ca: { value: 0.7 }, vig: { value: 0.32 }, grain: { value: 0.045 }, seed: { value: 3.0 }, gs: { value: 1.3 } },
  vertexShader: DOF.vertexShader,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform vec2 res; uniform float ca, vig, grain, seed, gs; varying vec2 vUv;
    float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32 + seed); return fract(p.x * p.y); }
    float vnoise(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
      return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
    void main() {
      vec2 d = vUv - 0.5; float r2 = dot(d * vec2(res.x / res.y, 1.0), d * vec2(res.x / res.y, 1.0));
      vec2 off = d * ca * r2 * 4.0 / res * vec2(res.x / res.y, 1.0) * 1.0;
      vec3 c;
      c.r = texture2D(tDiffuse, vUv + off).r; c.g = texture2D(tDiffuse, vUv).g; c.b = texture2D(tDiffuse, vUv - off).b;
      // 影调：黑位抬一点、轻 S 曲线、高光偏暖、整体稍降饱和
      float l = dot(c, vec3(0.299, 0.587, 0.114));
      c = mix(vec3(l), c, 0.96);
      vec3 s = c * c * (3.0 - 2.0 * c);
      c = mix(c, s, 0.22);
      c = 0.014 + c * 0.98;
      c *= vec3(1.01, 1.0, 0.985);
      // 暗角
      c *= 1.0 - vig * smoothstep(0.08, 0.75, r2);
      // 颗粒：1.3 像素大小的值噪声，暗处多一点
      float g = vnoise(gl_FragCoord.xy / gs) + vnoise(gl_FragCoord.xy / (gs * 0.55) + 17.0) * 0.5 - 0.75;
      c += g * grain * (1.1 - 0.6 * l);
      gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
    }`,
};
const ZMAT = () => new THREE.ShaderMaterial({
  vertexShader: 'varying float vz; void main(){ vec4 wp = modelMatrix * vec4(position, 1.0); vz = wp.z; gl_Position = projectionMatrix * viewMatrix * wp; }',
  fragmentShader: 'varying float vz; void main(){ gl_FragColor = vec4(vz + 4000.0, 0.0, 0.0, 1.0); }',
});

// ---------------------------------------------------------------- 搭 + 拍
export async function buildScene(data, opt, renderer) {
  const toy = opt.look === 'toy';
  const T = await loadTextures(renderer);
  const RM = new RealMats(T);
  const scene = new THREE.Scene();
  const b = toy ? new Builder(data, 'toy') : new RealBuilder(data, RM, T);
  const root = b.build();
  root.name = 'street';
  scene.add(root);
  const x = opt.x || 0, w = opt.w || 2133;
  const floor = data.floors[data.floors.length - 1];
  // 树（引擎里是单独一层，这里搭进来看效果）
  for (const [tx, tb, th, , kind] of (data.anchors.trees || [])) {
    if (tx < x - 500 || tx > x + w + 500) continue;
    root.add(toy ? toyTree(kind, tx, tb, th) : makeTree(kind, 'summer', tx, tb, th, RM));
  }
  // 两个主角
  const figs = opt.figs || [];
  const figGroups = [];
  for (const f of figs) {
    const g = toy ? buildFigure({ spec: f.F.spec, frame: f.F.frames[f.frame], design: f.F.design, variant: 'toy' }, new Mats('toy')) : makeFigure(f.F, f.frame, RM);
    g.position.set(f.x, -floor, ZREF + (f.dz || 0));
    root.add(g); figGroups.push(g);
  }
  if (opt.backdrop !== false) root.add(await makeBackdrop(opt.era || 'teen', x, x + w, toy));
  // UV：所有用贴图组的物件按世界尺寸铺（在没斜切的 root 空间里算）
  root.updateMatrixWorld(true);
  const inv = root.matrixWorld.clone().invert();
  root.traverse((o) => { if (o.isMesh) boxUV(o, inv.clone().multiply(o.matrixWorld)); });
  return { scene, root, builder: b, RM, T, figGroups };
}

export async function render(data, opt) {
  const S = opt.scale || 1, x = opt.x || 0, w = opt.w || 2133;
  const top = opt.top ?? data.top, bottom = opt.bottom ?? data.bottom, H = bottom - top;
  const W = Math.round(w * S), HH = Math.round(H * S);
  const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, preserveDrawingBuffer: true });
  renderer.setSize(W, HH); renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.toneMapping = opt.tone === 'agx' ? THREE.AgXToneMapping : THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = opt.exposure ?? 0.9;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const t0 = performance.now();
  const { scene, root } = await buildScene(data, opt, renderer);

  const toy = opt.look === 'toy';
  if (toy) {   // 现行的玩具版：scene3d/render.js 的 LOOKS.toy，没有环境贴图
    Object.assign(opt, { hemi: 0.85, hemiC: ['#CFE0FF', '#B89A80'], sunCol: '#FFE2BC', sunK: 3.4, sunDir: [-0.72, 0.55, 0.5], exposure: 1.0, aoR: 30, aoK: 0.85, post: false });
    renderer.toneMappingExposure = 1.0; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  } else {
    const pm = new THREE.PMREMGenerator(renderer);
    const env = pm.fromEquirectangular(skyCanvas(1024, 512, true)).texture;
    scene.environment = env; scene.environmentIntensity = opt.env ?? 0.55;
  }
  scene.background = skyCanvas(8, 512, false);

  const cam = new THREE.OrthographicCamera(x, x + w, -top, -bottom, 10, 20000);
  cam.position.set(0, 0, 8000); cam.lookAt(0, 0, 0); cam.updateProjectionMatrix();

  // 光：低一点的暖太阳（还是左上前方），天光弱一点（环境贴图给了大部分补光）
  scene.add(new THREE.HemisphereLight(...(opt.hemiC || ['#BCD2F0', '#A08870']), opt.hemi ?? 0.22));
  const sun = new THREE.DirectionalLight(opt.sunCol || '#FFDDB2', opt.sunK ?? 3.6);
  const d = new THREE.Vector3(...(opt.sunDir || [-0.66, 0.5, 0.56])).normalize();
  const cx = x + w / 2, cy = -(top + H / 2);
  sun.position.set(cx + d.x * 4000, cy + d.y * 4000, d.z * 4000);
  sun.target.position.set(cx, cy, 0); scene.add(sun.target);
  sun.castShadow = true;
  const R = Math.max(w, H) / 2 + 500;
  Object.assign(sun.shadow.camera, { left: -R, right: R, top: R, bottom: -R, near: 100, far: 9000 });
  sun.shadow.mapSize.set(opt.shadowMap || 4096, opt.shadowMap || 4096); sun.shadow.bias = -0.0003; sun.shadow.normalBias = 0.8; sun.shadow.radius = opt.shadowR ?? 2.5;
  scene.add(sun);

  const rt = new THREE.WebGLRenderTarget(W, HH, { type: THREE.HalfFloatType, samples: 4 });
  const composer = new EffectComposer(renderer, rt);
  composer.addPass(new RenderPass(scene, cam));
  if (opt.ao !== false) {
    const ao = new GTAOPass(scene, cam, W, HH);
    ao.updateGtaoMaterial(toy ? { radius: 30, distanceExponent: 1.4, thickness: 6, scale: 1.0 } : { radius: opt.aoR ?? 30, distanceExponent: 1.4, thickness: 6, scale: 1.1 });
    ao.blendIntensity = opt.aoK ?? 1.0;
    composer.addPass(ao);
  }
  composer.addPass(new OutputPass());
  if (opt.post) {
    // z 一张（景深用）：画面里每个点离后墙多远
    const zt = new THREE.WebGLRenderTarget(W, HH, { type: THREE.FloatType });
    const bg = scene.background; scene.background = null; scene.overrideMaterial = ZMAT();
    renderer.setRenderTarget(zt); renderer.setClearColor(0x000000, 0); renderer.clear(); renderer.render(scene, cam);
    renderer.setRenderTarget(null); scene.overrideMaterial = null; scene.background = bg; renderer.setClearColor(0x000000, 1);
    const dof = new ShaderPass(DOF);
    Object.assign(dof.uniforms.res.value, { x: W, y: HH });
    dof.uniforms.tZ.value = zt.texture; dof.uniforms.yTop.value = top; dof.uniforms.yBot.value = bottom;
    if (opt.focusY) dof.uniforms.yF.value = opt.focusY;
    dof.uniforms.maxR.value = (opt.dofR ?? 14) * S / 0.9;
    dof.material.defines.N = Math.round(56 * Math.max(1, S / 0.9) * 0.85); dof.material.needsUpdate = true;
    if (opt.band != null) dof.uniforms.band.value = opt.band;
    if (opt.ramp != null) dof.uniforms.ramp.value = opt.ramp;
    composer.addPass(dof);
    const film = new ShaderPass(FILM);
    Object.assign(film.uniforms.res.value, { x: W, y: HH });
    if (opt.grain != null) film.uniforms.grain.value = opt.grain;
    film.uniforms.gs.value = 1.3 * S / 0.9;
    composer.addPass(film);
  }
  composer.render();
  const out = renderer.domElement; out.id = 'out'; document.body.appendChild(out);
  return { ms: performance.now() - t0, meshes: root.children.length };
}

// ---------------------------------------------------------------- 导出 glb：拿掉斜切，按米（1 世界像素 = 1 cm）
export async function exportScene(data, opt) {
  const renderer = new THREE.WebGLRenderer({ antialias: false });
  const { root } = await buildScene(data, opt, renderer);
  const out = new THREE.Group(); out.name = `${data.id}_real`;
  out.scale.setScalar(0.01);   // 米
  const inner = new THREE.Group(); inner.name = 'world_px'; out.add(inner);
  // 只留镜头附近那一段（look test 的范围），省得 glb 太大
  const x0 = (opt.x || 0) - 300, x1 = (opt.x || 0) + (opt.w || 2133) + 300;
  for (const c of root.children.slice()) {
    if (c.isMesh) {
      c.geometry.computeBoundingBox(); const bb = c.geometry.boundingBox.clone().applyMatrix4(c.matrix);
      if (bb.max.x < x0 || bb.min.x > x1) continue;
    }
    inner.add(c);
  }
  // glb 瘦身：① 粗糙度贴图拿掉（GLTFExporter 会给每个材质另合一张 metallicRoughness 图，几十个材质就几十张 1024²），
  // 换成这组材质的平均粗糙度；Godot 那边用 textures/<材质>_rough.png。② box 投影 UV 拆开的顶点重新合并。
  const seen = new Set();
  inner.traverse((o) => {
    if (!o.isMesh) return;
    const m = o.material;
    if (m && !seen.has(m)) {
      seen.add(m); if (m.roughnessMap) { m.roughness = 0.85 * (m.roughness ?? 1); m.roughnessMap = null; } m.userData.set = m.name;
      // ③ 不透明的贴图（砖、灰泥的 albedo / normal / ao）存 JPEG：glb 里只是预览用，原图在 textures/
      for (const k of ['map', 'normalMap', 'aoMap']) { const t = m[k]; if (t && t.image && t.image.src && /\/tex\/(?!decal)/.test(t.image.src)) t.userData.mimeType = 'image/jpeg'; }
    }
    if (o.geometry && !o.geometry.index) { try { o.geometry = mergeVertices(o.geometry, 1e-4); } catch (e) { /* 属性不齐的就算了 */ } }
  });
  const ex = new GLTFExporter();
  const glb = await ex.parseAsync(out, { binary: true, onlyVisible: true, maxTextureSize: 512 });
  return glb;
}
