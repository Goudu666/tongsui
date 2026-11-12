// 主角导成分件的 glb（给 Godot 实时 3D 用）：pose3d/figure.js 搭的同一个小人（造型甲），换成休息姿势（A 字：胳膊往外张 35°），
// 每个身体部件一个带名字的 mesh，轴心在关节上，按骨骼父子挂好；单位米（1 世界像素 = 1 cm），脸朝 +Z、右手在 −X（glTF 习惯）。
// 名字和层级见 GLB_README.md（会拷到 glb/README.md）。
import * as THREE from 'three';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';
import { mergeGeometries, mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { buildFigure, PAL, Mats } from '../pose3d/figure.js';
import { RealMats, FigureMats, boxUV, loadTextures } from './real.js';

const D2R = Math.PI / 180;
const A_POSE = 35;   // 胳膊离开身体多少度

// 站姿那一帧 → 直直站好的休息姿势：腿竖直、胳膊垂直往下、身子不前倾、头不歪
function restFrame(F) {
  const st = F.frames.stand, sp = F.spec;
  const hip = st.hip.slice();
  const fr = JSON.parse(JSON.stringify(st));
  Object.assign(fr, { lean: 0, tilt: 0, expr: null, props: [], busy: false, wave: false, sit: false, cane: false });
  const hx = hip[0];
  const up = (p) => [hx + (p[0] - st.shoulder[0]) * 0, p[1]];
  fr.shoulder = [hx, st.shoulder[1]]; fr.neck = [hx, st.neck[1]];
  fr.head = [hx + (st.head[0] - st.neck[0]) * 0.4, st.head[1]];
  for (const s of ['near', 'far']) {
    const sh = [hx + (st['sh_' + s][0] - st.shoulder[0]), st['sh_' + s][1]];
    fr['sh_' + s] = sh;
    fr['elbow_' + s] = [sh[0], sh[1] + sp.upper];
    fr['hand_' + s] = [sh[0] + 0.5, sh[1] + sp.upper + sp.fore];
    const L = st.legs.near;    // 两只脚一样：用近侧那只脚的脚跟、脚尖相对脚踝的位置
    const ah = Math.abs(L.ankle[1]);
    fr.legs[s] = {
      knee: [hx, -(ah + sp.shin)], ankle: [hx, -ah],
      heel: [hx + (L.heel[0] - L.ankle[0]), 0], toe: [hx + (L.toe[0] - L.ankle[0]), 0],
    };
    // 髋到脚踝的距离和原来的腿长对上（髋高不变，膝盖按大腿、小腿的比例放）
    const legLen = -hip[1] - ah;
    const k = sp.thigh / (sp.thigh + sp.shin);
    fr.legs[s].knee = [hx + 0.6, hip[1] + legLen * k];
  }
  void up;
  return fr;
}

// 线段到点的距离（分件用）
function segDist(p, a, b) {
  const ab = b.clone().sub(a), t = THREE.MathUtils.clamp(p.clone().sub(a).dot(ab) / Math.max(1e-6, ab.lengthSq()), 0, 1);
  return a.clone().add(ab.multiplyScalar(t)).distanceTo(p);
}

const PARENT = {
  pelvis: null, torso: 'pelvis', head: 'torso', hair: 'head',
  upper_arm_R: 'torso', lower_arm_R: 'upper_arm_R', hand_R: 'lower_arm_R',
  upper_arm_L: 'torso', lower_arm_L: 'upper_arm_L', hand_L: 'lower_arm_L',
  thigh_R: 'pelvis', shin_R: 'thigh_R', shoe_R: 'shin_R',
  thigh_L: 'pelvis', shin_L: 'thigh_L', shoe_L: 'shin_L',
};

export async function buildRig(F, opt = {}) {
  const fr = restFrame(F);
  const design = Object.assign({}, F.design, { yaw: 0, torsoYaw: 0, headPitch: 0 });
  const job = { spec: F.spec, frame: fr, design, variant: 'toy' };
  let mats;
  if (opt.mats === 'toy') mats = new Mats('toy');
  else {
    const T = await loadTextures(new THREE.WebGLRenderer());
    // 小人身上只留法线贴图（布纹、头发丝、皮肤刷痕）：颜色是纯色，albedo / 粗糙度贴图在这个尺度上近乎常数，省得 glb 变大
    for (const k of ['fabric', 'skin', 'hair', 'paint', 'metal']) T[k] = { normal: T[k].normal };
    mats = new FigureMats(new RealMats(T));
  }
  const fig = buildFigure(job, mats);
  fig.updateMatrixWorld(true);
  fig.traverse((o) => { if (o.isMesh) boxUV(o, o.matrixWorld.clone()); });
  fig.updateMatrixWorld(true);

  // ---- 关节（figure.js 的坐标：three (x, −y, z)，脚底在 y=0，近侧 z>0 = 人的右边）
  const sp = F.spec, D = design, LK = D.limbK || 1;
  const zL = sp.waist * 0.27, zA = sp.chest * 0.5 * 1.3 + sp.limb * 0.12 * LK;
  const V = (p, z = 0) => new THREE.Vector3(p[0], -p[1], z);
  const J = {};
  J.pelvis = V(fr.hip);
  J.torso = V(fr.hip).add(new THREE.Vector3(0, sp.torso * 0.16, 0));
  J.head = V(fr.neck);
  J.hair = J.head.clone();
  for (const [side, s, z] of [['near', 'R', 1], ['far', 'L', -1]]) {
    J['upper_arm_' + s] = V(fr['sh_' + side], z * zA).add(new THREE.Vector3(0, -2, 0));
    J['lower_arm_' + s] = V(fr['elbow_' + side], z * zA);
    J['hand_' + s] = V(fr['hand_' + side], z * zA);
    J['thigh_' + s] = V(fr.hip, z * zL);
    J['shin_' + s] = V(fr.legs[side].knee, z * zL);
    J['shoe_' + s] = V(fr.legs[side].ankle, z * zL);
  }
  const handTip = (s) => J['hand_' + s].clone().add(new THREE.Vector3(0, -sp.limb * 0.6, 0));
  const SEG = [];
  for (const s of ['R', 'L']) {
    SEG.push(['upper_arm_' + s, J['upper_arm_' + s], J['lower_arm_' + s]]);
    SEG.push(['lower_arm_' + s, J['lower_arm_' + s], J['hand_' + s]]);
    SEG.push(['hand_' + s, J['hand_' + s], handTip(s)]);
    SEG.push(['thigh_' + s, J['thigh_' + s], J['shin_' + s]]);
    SEG.push(['shin_' + s, J['shin_' + s], J['shoe_' + s]]);
  }
  SEG.push(['torso', J.torso, J.head]);
  SEG.push(['pelvis', J.pelvis, J.torso]);

  // ---- 分件：每个 mesh 按它挂在哪个组、离哪根骨头最近
  const isFace = (m) => m.map && m.map.image && m.map.image.width === 1024 && m.map.image.height === 512;
  const skinHex = [PAL.skin, PAL.skinOld].map((c) => new THREE.Color(c).getHex());
  const isSkinish = (m) => isFace(m) || m.name === 'skin' || m.name === 'metal' || skinHex.includes(m.color.getHex()) || [PAL.gold, PAL.glasses].map((c) => new THREE.Color(c).getHex()).includes(m.color.getHex());
  const parts = {};
  const put = (name, me) => { (parts[name] = parts[name] || []).push(me); };
  for (const top of fig.children) {
    const meshes = []; top.traverse((o) => { if (o.isMesh && o.visible) meshes.push(o); });
    if (top.isMesh) { meshes.length = 0; meshes.push(top); }
    let kind = 'loose';
    if (!top.isMesh) {
      let face = false, nested = false;
      top.traverse((o) => { if (o.isMesh && isFace(o.material)) face = true; if (o !== top && o.isGroup) nested = true; });
      kind = face ? 'head' : nested ? 'torso' : 'shoe';
    }
    for (const me of meshes) {
      const c = new THREE.Vector3(); me.geometry.computeBoundingBox(); me.geometry.boundingBox.getCenter(c); c.applyMatrix4(me.matrixWorld);
      if (kind === 'head') put(isSkinish(me.material) ? 'head' : 'hair', me);
      else if (kind === 'torso') put(c.y < J.torso.y ? 'pelvis' : 'torso', me);
      else if (kind === 'shoe') put(c.z >= 0 ? 'shoe_R' : 'shoe_L', me);
      else {
        let best = null, bd = 1e9;
        for (const [n, a, b] of SEG) { const d = segDist(c, a, b); if (d < bd - 1e-6) { bd = d; best = n; } }
        put(best, me);
      }
    }
  }

  // ---- 烤成一体：A 字胳膊、挪到原点、转成脸朝 +Z、按米
  const Fm = new THREE.Matrix4().makeScale(0.01, 0.01, 0.01)
    .multiply(new THREE.Matrix4().makeRotationY(-Math.PI / 2))
    .multiply(new THREE.Matrix4().makeTranslation(-J.pelvis.x, 0, 0));
  const armRot = {};
  for (const [s, sign] of [['R', -1], ['L', 1]]) {
    const sh = J['upper_arm_' + s];
    armRot[s] = new THREE.Matrix4().makeTranslation(sh.x, sh.y, sh.z).multiply(new THREE.Matrix4().makeRotationX(sign * A_POSE * D2R)).multiply(new THREE.Matrix4().makeTranslation(-sh.x, -sh.y, -sh.z));
  }
  const armOf = (n) => (/_arm_|hand_/.test(n) ? n.slice(-1) : null);
  const P = {};
  for (const n of Object.keys(PARENT)) {
    const p = J[n].clone(); const s = armOf(n);
    if (s) p.applyMatrix4(armRot[s]);
    P[n] = p.applyMatrix4(Fm);
  }
  const root = new THREE.Group(); root.name = `${sp.role}_${sp.stage}`;
  const nodes = {};
  for (const n of Object.keys(PARENT)) {
    const list = parts[n] || [];
    const byMat = new Map();
    for (const me of list) {
      let g = me.geometry.index ? me.geometry.toNonIndexed() : me.geometry.clone();
      for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      if (!g.attributes.normal) g.computeVertexNormals();
      let M = me.matrixWorld.clone(); const s = armOf(n); if (s) M = armRot[s].clone().multiply(M);
      g.applyMatrix4(Fm.clone().multiply(M));
      g.translate(-P[n].x, -P[n].y, -P[n].z);
      const k = me.material.uuid;
      if (!byMat.has(k)) byMat.set(k, { m: me.material, gs: [] });
      byMat.get(k).gs.push(g);
    }
    let geo, mat;
    if (byMat.size) {
      const groups = [...byMat.values()];
      geo = mergeGeometries(groups.map((x) => mergeGeometries(x.gs, false)), true);
      mat = groups.map((x) => x.m);
      if (mat.length === 1) { mat = mat[0]; geo.clearGroups(); }
      geo = mergeVertices(geo, 1e-5);   // 重新共用顶点（box 投影的 UV 让三角形各自独立了），glb 小好几倍
    } else { geo = new THREE.BufferGeometry(); mat = new THREE.MeshStandardMaterial(); }
    const node = new THREE.Mesh(geo, mat); node.name = n;
    nodes[n] = node;
  }
  for (const n of Object.keys(PARENT)) {
    const par = PARENT[n];
    const node = nodes[n];
    if (par) { node.position.copy(P[n]).sub(P[par]); nodes[par].add(node); }
    else { node.position.copy(P[n]); root.add(node); }
  }
  root.userData = { role: sp.role, stage: sp.stage, design: 'a', height_m: sp.H / 100, units: 'metres', forward: '+Z', rest_pose: `A-pose ${A_POSE}°` };
  return root;
}

export async function exportFigure(F, opt = {}) {
  const root = await buildRig(F, opt);
  const ex = new GLTFExporter();
  return ex.parseAsync(root, { binary: true, onlyVisible: true, maxTextureSize: 512 });
}

// 预览：把导出的 glb 读回来，正面、侧面、炸开（每个部件沿父子关系往外挪）各拍一张，确认分件和轴心
export async function previewGlbs(urls, px = 360) {
  const R = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  R.setPixelRatio(1); R.outputColorSpace = THREE.SRGBColorSpace; R.toneMapping = THREE.ACESFilmicToneMapping;
  const cols = 4, W = px * cols, H = px * 1.25 * urls.length;
  R.setSize(W, H); R.setScissorTest(true);
  R.setClearColor('#E9E2D6');
  R.clear();
  const L = new GLTFLoader();
  const pm = new THREE.PMREMGenerator(R);
  const { RoomEnvironment } = await import('three/addons/environments/RoomEnvironment.js');
  const env = pm.fromScene(new RoomEnvironment(), 0.04).texture;
  for (let i = 0; i < urls.length; i++) {
    const g = await L.loadAsync(urls[i]);
    const root = g.scene;
    for (let v = 0; v < cols; v++) {
      const scene = new THREE.Scene(); scene.environment = env; scene.environmentIntensity = 0.6;
      const sun = new THREE.DirectionalLight('#fff3e0', 2.5); sun.position.set(1, 2, 2); scene.add(sun);
      const r = root.clone(true);
      if (v === 3) r.traverse((o) => { if (o.isMesh && o.parent && o.parent !== r) o.position.multiplyScalar(1.35); });
      r.rotation.y = [0, Math.PI / 2, Math.PI / 4, 0][v];
      scene.add(r);
      const h = 1.9;
      const cam = new THREE.OrthographicCamera(-h * 0.4, h * 0.4, h * 0.95, -h * 0.05, 0.1, 50);
      cam.position.set(0, 0.5, 10); cam.lookAt(0, 0.5, 0);
      cam.position.y = 0; cam.lookAt(0, 0, -1);
      const x = v * px, y = H - (i + 1) * px * 1.25;
      R.setViewport(x, y, px, px * 1.25); R.setScissor(x, y, px, px * 1.25);
      R.render(scene, cam);
      // 关节：小红点
      if (v === 0) {
        R.autoClear = false; const dots = new THREE.Scene();
        r.updateMatrixWorld(true);
        r.traverse((o) => { if (o.isMesh) { const p = new THREE.Vector3().setFromMatrixPosition(o.matrixWorld); const d = new THREE.Mesh(new THREE.SphereGeometry(0.012), new THREE.MeshBasicMaterial({ color: '#e0201a', depthTest: false })); d.position.copy(p); d.position.z += 1; dots.add(d); } });
        R.render(dots, cam); R.autoClear = true;
      }
    }
  }
  return R.domElement.toDataURL('image/png');
}
