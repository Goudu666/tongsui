// 拍一张精灵：正交镜头框住精灵的世界框（往四周放宽，3D 会探出去），透明底，和底图同一套光（../scene3d/render.js 的 LOOKS.toy）。
// 精灵后面摆两块「接影子」的透明板（墙 z=0、地面），ShadowMaterial：只留影子，影子落在底图的墙上、地上。
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { SpriteBuilder, floorCover } from './sprite_build.js';
import { Builder } from '../scene3d/build.js';

// ---------------------------------------------------------------- 底图那一段（只读 ../scene3d/out/<图>.json）
// 精灵前后的底图家具、墙、楼板也搭出来，但不出颜色：
//   第一张（挡）：底图的东西写透明，挡住精灵被它挡着的那部分；底图照样投影子，精灵落在底图的影子里就是暗的；
//   第二张（接）：底图的东西换成只接影子的材质（ShadowMaterial），只有精灵投影子 —— 精灵落在墙上、桌上、地上的影子。
// 两张叠起来（第一张盖在第二张上）就是贴回底图上的样子。
const _scenes = new Map();
async function sceneOps(id) {
  if (!_scenes.has(id)) _scenes.set(id, await (await fetch('../scene3d/out/' + id + '.json')).json());
  return _scenes.get(id);
}
class BaseBuilder extends Builder {
  context(o) { const c = super.context(o); this._cn = c ? c.name : null; return c; }
  add(g, m, cast = true) { const me = super.add(g, m, cast); me.userData.ctx = this._cn; return me; }
}
async function baseModel(base) {
  const d = await sceneOps(base.scene);
  const M = 300;
  const keep = o => {
    if (o.k === 'call' || !o.p) return true;
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (const [x, y] of o.p) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    return x1 > base.x0 - M && x0 < base.x1 + M && y1 > base.y0 - M && y0 < base.y1 + M;
  };
  const bb = new BaseBuilder(Object.assign({}, d, { ops: d.ops.filter(keep) }), 'toy');
  bb.build();
  const ex = new Set(base.exclude || []);
  const meshes = [];
  for (const me of bb.root.children.slice()) {
    const m = me.material;
    if (!me.isMesh || (m && m.map && m.transparent) || ex.has(me.userData.ctx)) { bb.root.remove(me); continue; }
    // 头顶上那块楼板（剖开的模型，前沿伸到 z=300）不挡：底图里它往下盖住的那一截墙，老画法照样挂着钟、拉着帘子
    if (me.userData.ctx === 'slab' && base.floorY != null && -me.position.y < base.floorY - 20) { bb.root.remove(me); continue; }
    meshes.push(me);
  }
  return { root: bb.root, meshes };
}

// = ../scene3d/render.js 的 LOOKS.toy（那边没导出；改光要两边一起改）
const LOOK = { sun: { dir: [-0.72, 0.55, 0.5], col: '#FFE2BC', k: 3.4 }, hemi: ['#CFE0FF', '#B89A80', 0.85], radius: 5, exposure: 1.0 };
// 底图的影子贴图：4096 张铺 ~2200 世界像素，一个影子像素 ≈ 0.54 世界像素。精灵也按这个密度，软硬才一样
const SHADOW_TEXEL = 0.54;

let renderer = null;
function getRenderer(W, H) {
  if (!renderer) {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(1);
    renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = LOOK.exposure;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.setClearColor(0x000000, 0);
  }
  renderer.setSize(W, H);
  return renderer;
}

function dispose(obj) {
  obj.traverse(o => {
    if (o.geometry) o.geometry.dispose();
    if (o.material) { const ms = Array.isArray(o.material) ? o.material : [o.material]; for (const m of ms) { if (m.map) m.map.dispose(); m.dispose(); } }
  });
}

// job: {ops, floors, cfg, view: {x0, y0, x1, y1}（世界坐标）, scale, catchers: [{kind: 'wall'|'floor', ...}], custom, ao, shadowColor, shadowOpacity}
export async function renderJob(job) {
  const S = job.scale, v = job.view;
  const W = Math.round((v.x1 - v.x0) * S), H = Math.round((v.y1 - v.y0) * S);
  const r = getRenderer(W, H);
  const scene = new THREE.Scene();
  const b = new SpriteBuilder({ ops: job.ops, floors: job.floors, cfg: job.cfg }, job.variant || 'toy');
  if (job.custom && job.custom.kind === 'floorCover') {
    const c = job.custom; floorCover(b, c.x0, c.x1, c.y, c.z0, c.z1);
  } else b.build();
  scene.add(b.root);
  // 接影子的板：放在 b.root 里，跟着一起斜
  const shm = new THREE.ShadowMaterial({ color: new THREE.Color(job.shadowColor || '#1E1A2E'), opacity: job.shadowOpacity ?? 0.5, toneMapped: false });
  const catchMat = new THREE.ShadowMaterial({ color: new THREE.Color(job.shadowColor || '#1E1A2E'), opacity: job.shadowOpacity ?? 0.5, blending: THREE.NoBlending, premultipliedAlpha: true, toneMapped: false });
  const holdMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0, blending: THREE.NoBlending, premultipliedAlpha: true });
  for (const c of job.catchers || []) {
    let me;
    if (c.kind === 'wall') {
      me = new THREE.Mesh(new THREE.PlaneGeometry(c.x1 - c.x0, c.y1 - c.y0), shm);
      me.position.set((c.x0 + c.x1) / 2, -(c.y0 + c.y1) / 2, c.z ?? 0);
    } else {
      me = new THREE.Mesh(new THREE.PlaneGeometry(c.x1 - c.x0, c.z1 - c.z0), shm);
      me.rotation.x = -Math.PI / 2;
      me.position.set((c.x0 + c.x1) / 2, -c.y, (c.z0 + c.z1) / 2);
    }
    me.receiveShadow = true; me.castShadow = false;
    b.root.add(me);
  }
  let base = null;
  if (job.base) {
    base = await baseModel(job.base);
    for (const me of base.meshes) me.userData.cast = me.castShadow;
    scene.add(base.root);
    base.root.updateMatrixWorld(true);
  }
  b.root.updateMatrixWorld(true);

  const cam = new THREE.OrthographicCamera(v.x0, v.x1, -v.y0, -v.y1, 10, 20000);
  cam.position.set(0, 0, 8000); cam.lookAt(0, 0, 0); cam.updateProjectionMatrix();

  scene.add(new THREE.HemisphereLight(LOOK.hemi[0], LOOK.hemi[1], LOOK.hemi[2]));
  const sun = new THREE.DirectionalLight(LOOK.sun.col, LOOK.sun.k);
  const d = new THREE.Vector3(...LOOK.sun.dir).normalize();
  const cx = (v.x0 + v.x1) / 2, cy = -(v.y0 + v.y1) / 2;
  sun.position.set(cx + d.x * 4000, cy + d.y * 4000, d.z * 4000);
  sun.target.position.set(cx, cy, 0); scene.add(sun.target);
  sun.castShadow = true;
  const R = Math.max(v.x1 - v.x0, v.y1 - v.y0) / 2 + 260;
  const ms = Math.min(4096, Math.pow(2, Math.ceil(Math.log2(2 * R / SHADOW_TEXEL))));
  const RR = ms * SHADOW_TEXEL / 2;
  Object.assign(sun.shadow.camera, { left: -RR, right: RR, top: RR, bottom: -RR, near: 100, far: 9000 });
  sun.shadow.mapSize.set(ms, ms); sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.6; sun.shadow.radius = LOOK.radius;
  scene.add(sun);

  const composer = new EffectComposer(r, new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType, samples: 4 }));
  composer.addPass(new RenderPass(scene, cam));
  if (job.ao !== false) {
    const ao = new GTAOPass(scene, cam, W, H);
    ao.updateGtaoMaterial({ radius: 30 * (job.aoK ?? 1), distanceExponent: 1.4, thickness: 6, scale: 1.0 });
    ao.blendIntensity = 0.85;
    composer.addPass(ao);
  }
  composer.addPass(new OutputPass());
  if (base) for (const me of base.meshes) { me.material = holdMat; me.castShadow = me.userData.cast; me.receiveShadow = false; }
  composer.render();
  const url = r.domElement.toDataURL('image/png');
  let url2 = null;
  if (base) {
    for (const me of base.meshes) { me.material = catchMat; me.castShadow = false; me.receiveShadow = true; }
    r.setRenderTarget(null);
    r.render(scene, cam);
    url2 = r.domElement.toDataURL('image/png');
  }
  composer.dispose?.();
  dispose(scene);
  return url2 ? [url, url2] : url;
}
