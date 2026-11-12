// 风格 C：微缩模型。同一份显示列表搭成 3D：圆角盒子、挤出的多边形、球、管子；
// 低太阳真投影 + 环境光遮蔽 + 移轴虚化 + 辉光，像桌上摆的一盒模型。
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';

const W = 1920, H = 1080;
const LOOKS = {
  dusk: { sky: [[0, '#2A2F63'], [0.45, '#7A5794'], [0.75, '#E58C84'], [1, '#FFC690']], fog: '#B97A90', fogNear: 3600, fogFar: 6200,
    sun: { pos: [2600, 900, 2100], col: '#FFAA70', k: 5.5 }, hemi: ['#8C8CD8', '#6B4A5A', 0.55], amb: 0.12, exposure: 1.0 },
  morning: { sky: [[0, '#7FB6E4'], [0.6, '#CFE4F0'], [1, '#FFE2BE']], fog: '#D6E4EE', fogNear: 3800, fogFar: 6400,
    sun: { pos: [-2400, 560, 2600], col: '#FFD9A8', k: 4.2 }, hemi: ['#CFE4FF', '#B89A80', 0.75], amb: 0.2, exposure: 1.0 },
};

function brickTex(base, w, h) {
  const c = document.createElement('canvas'); c.width = 256; c.height = 256; const x = c.getContext('2d');
  const b = hex(base); x.fillStyle = rgb(darken(b, 0.25)); x.fillRect(0, 0, 256, 256);
  const r = mkRnd(3);
  for (let row = 0; row < 16; row++) for (let k = -1; k < 5; k++) {
    const bx = k * 64 + (row % 2) * 32, by = row * 16; const v = (r() - 0.5) * 0.16;
    x.fillStyle = rgb(v > 0 ? lighten(b, v) : darken(b, -v)); x.fillRect(bx + 2, by + 2, 60, 12);
  }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace;
  t.repeat.set(w / 160, h / 40); t.anisotropy = 8; return t;
}
function noiseTex(base, w, h, amt = 0.06) {
  const c = document.createElement('canvas'); c.width = 128; c.height = 128; const x = c.getContext('2d');
  const b = hex(base); x.fillStyle = rgb(b); x.fillRect(0, 0, 128, 128); const r = mkRnd(9);
  for (let k = 0; k < 900; k++) { const v = (r() - 0.5) * amt * 2; x.fillStyle = rgb(v > 0 ? lighten(b, v) : darken(b, -v), 0.7); x.fillRect(r() * 128, r() * 128, 2 + r() * 6, 2 + r() * 6); }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; t.repeat.set(w / 300, h / 300); return t;
}

window.render = async function (env, L) {
  const lk = LOOKS[env.time];
  const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(W, H); renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = lk.exposure;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const scene = new THREE.Scene();
  { const c = document.createElement('canvas'); c.width = 4; c.height = 512; const x = c.getContext('2d'); const g = x.createLinearGradient(0, 0, 0, 512);
    for (const [t, col] of lk.sky) g.addColorStop(t, col); x.fillStyle = g; x.fillRect(0, 0, 4, 512);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; scene.background = t; }
  scene.fog = new THREE.Fog(lk.fog, lk.fogNear, lk.fogFar);

  const G = env.G;
  const cam = new THREE.PerspectiveCamera(17, W / H, 50, 12000);
  if (env.scene === 'street') { cam.position.set(960, 1150, 3900); cam.lookAt(960, 360, 120); }
  else { cam.position.set(960, 760, 3900); cam.lookAt(960, 250, 80); }

  const mats = new Map();
  const matFor = (m, op, w = 100, h = 100) => {
    const isBrick = /^brick/.test(m) && op && op.wall;
    const key = m + (isBrick ? ':' + Math.round(w) + 'x' + Math.round(h) : '') + (op && op.wall && !isBrick ? ':w' : '');
    if (mats.has(key)) return mats.get(key);
    const col = new THREE.Color(MAT[m] || '#ff00ff');
    let mt;
    if (m === 'text') mt = null;
    else if (EMISSIVE.has(m)) mt = new THREE.MeshStandardMaterial({ color: col, emissive: new THREE.Color(m === 'glassLit' ? '#FFB45E' : '#FFD9A0'), emissiveIntensity: m === 'glassLit' ? 0.75 : 2.0, roughness: 0.6 });
    else if (m === 'lantern') mt = new THREE.MeshStandardMaterial({ color: col, emissive: new THREE.Color('#FF3A20'), emissiveIntensity: 0.7, roughness: 0.5 });
    else if (m === 'glass' || m === 'skyWin' || m === 'mirror' || m === 'tvScreen') mt = new THREE.MeshStandardMaterial({ color: col, roughness: 0.15, metalness: 0.2 });
    else if (isBrick) mt = new THREE.MeshStandardMaterial({ map: brickTex(MAT[m], w, h), roughness: 0.92 });
    else if (op && op.wall) mt = new THREE.MeshStandardMaterial({ map: noiseTex(MAT[m], w, h), roughness: 0.95 });
    else if (/^(far|mid)$/.test(m)) mt = new THREE.MeshStandardMaterial({ color: col, roughness: 1 });
    else if (/metal|pole|lamp|rail|ladder|bikeFrame|wire/.test(m)) mt = new THREE.MeshStandardMaterial({ color: col, roughness: 0.45, metalness: 0.35 });
    else if (/qing|mei|pants|hair|skin|bag|shoe|collar/.test(m)) mt = new THREE.MeshStandardMaterial({ color: col, roughness: 0.42 }); // 小人：塑料
    else mt = new THREE.MeshStandardMaterial({ color: col, roughness: 0.75 });
    mats.set(key, mt); return mt;
  };
  const add = (geo, mat, op, cast = true) => { const me = new THREE.Mesh(geo, mat); me.castShadow = cast && !op.far && !op.mid; me.receiveShadow = true; scene.add(me); return me; };
  const gIdx = new Map();
  const nudge = (op) => { if (!op.g) return 0; const n = (gIdx.get(op.g) || 0) + 1; gIdx.set(op.g, n); return n * 0.35; };
  const depthOf = (op) => {
    if (op.wall) return 360;
    if (op.sect) return Math.max(op.z, 4);
    if (op.far) return 200;
    if (op.mid) return 160;
    if (op.d > 0) return op.d;
    if (op.leaf) return op.rx;
    if (op.stand || op.kid) return op.kid ? 22 : 12;
    if (op.fg) return 30;
    return 3;
  };
  const zFront = (op) => op.z + nudge(op);

  const BASEZ = env.scene === 'street' ? 640 : 330;
  for (let op of L) {
    if (op.t === 'light') {
      const col = op.col === 'red' ? '#FF5A3A' : op.col === 'sun' ? '#FFE0B0' : '#FFB060';
      if (op.col === 'sun') continue;
      const pl = new THREE.PointLight(col, op.k * (op.cone ? 3e4 : 1.2e4), op.r * 2.2, 2); pl.position.set(op.x, G - op.y, op.z + 20); scene.add(pl);
      continue;
    }
    if (op.t === 'sunpatch') {
      // 窗外照进来的一束光
      const [a, b, c, d] = op.pts; const sp = new THREE.SpotLight('#FFE2B0', 6e5, 2400, 0.32, 0.6, 1.6);
      sp.position.set(330, G - a[1] + 10, 40); sp.target.position.set(900, 0, 200); sp.distance = 1600; sp.intensity = 2.2e5; sp.angle = 0.42;
      sp.castShadow = true; sp.shadow.mapSize.set(2048, 2048); sp.shadow.bias = -0.0005; scene.add(sp); scene.add(sp.target);
      continue;
    }
    if (op.m === 'birdFly') {
      const shape = new THREE.Shape(op.pts.map(p => new THREE.Vector2(p[0], G - p[1])));
      add(new THREE.ExtrudeGeometry(shape, { depth: 2, bevelEnabled: false }), matFor('bird', op), op, false).position.z = 600;
      continue;
    }
    if (op.t === 'text') {
      const c = document.createElement('canvas'); const fs = 128; const ctx = c.getContext('2d'); ctx.font = `900 ${fs}px "Noto Sans SC"`;
      const tw = ctx.measureText(op.s).width + 20; c.width = Math.ceil(tw); c.height = fs * 1.3;
      ctx.font = `900 ${fs}px "Noto Sans SC"`; ctx.fillStyle = MAT[op.m]; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(op.s, c.width / 2, c.height / 2 + fs * 0.05);
      const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
      const h = op.size * 1.3, w = h * c.width / c.height;
      const mt = op.m === 'signText' ? new THREE.MeshBasicMaterial({ map: t, transparent: true, toneMapped: false, color: new THREE.Color(1.15, 1.08, 0.95) }) : new THREE.MeshStandardMaterial({ map: t, transparent: true, roughness: 0.8 });
      const me = new THREE.Mesh(new THREE.PlaneGeometry(w, h), mt); me.position.set(op.x, G - op.y, op.z + 3.2); scene.add(me);
      continue;
    }
    if (op.far || op.mid) continue;
    if (op.t === 'floor' && op.z1 > BASEZ) { op = { ...op, z1: BASEZ }; if (op.z0 >= BASEZ) continue; }
    if (op.t === 'floor') {
      const geo = new THREE.PlaneGeometry(op.w, op.z1 - op.z0); geo.rotateX(-Math.PI / 2);
      const mt = op.m === 'road' ? new THREE.MeshStandardMaterial({ map: noiseTex(MAT.road, op.w, op.z1 - op.z0, 0.1), roughness: 0.85 })
        : op.m === 'sidewalk' ? (() => { const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d'); const b = hex(MAT.sidewalk); x.fillStyle = rgb(darken(b, 0.2)); x.fillRect(0, 0, 128, 128); x.fillStyle = rgb(b); x.fillRect(2, 2, 124, 124); const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(op.w / 64, (op.z1 - op.z0) / 64); t.colorSpace = THREE.SRGBColorSpace; return new THREE.MeshStandardMaterial({ map: t, roughness: 0.9 }); })()
          : /floorRoom/.test(op.m) ? (() => { const c = document.createElement('canvas'); c.width = 256; c.height = 64; const x = c.getContext('2d'); const b = hex(MAT.floorRoom); const r = mkRnd(2); for (let k = 0; k < 4; k++) { x.fillStyle = rgb(mix(b, darken(b, 0.12), r())); x.fillRect(0, k * 16, 256, 15); } const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(op.w / 256, (op.z1 - op.z0) / 64); t.colorSpace = THREE.SRGBColorSpace; return new THREE.MeshStandardMaterial({ map: t, roughness: 0.55 }); })()
            : matFor(op.m, op);
      const me = add(geo, mt, op, false); me.position.set(op.x + op.w / 2, G - op.y + (op.m === 'roadLine' ? 0.6 : 0), (op.z0 + op.z1) / 2);
      continue;
    }
    if (op.t === 'floorEll') { const geo = new THREE.CylinderGeometry(op.rx, op.rx, 2, 32); const me = add(geo, matFor(op.m, op), op, false); me.position.set(op.cx, 1, op.z0); continue; }

    const depth = depthOf(op), zf = zFront(op), zc = zf - depth / 2;
    if (op.t === 'box') {
      const r = Math.min(op.r ? op.r : (op.wall || op.far || op.mid || op.sect ? 0 : 1.5), op.w / 2 - 0.01, op.h / 2 - 0.01, depth / 2 - 0.01);
      const geo = r > 0.3 ? new RoundedBoxGeometry(op.w, op.h, depth, 2, r) : new THREE.BoxGeometry(op.w, op.h, depth);
      const me = add(geo, matFor(op.m, op, op.w, op.h), op); me.position.set(op.x + op.w / 2, G - op.y - op.h / 2, zc);
      if (op.sway) me.rotation.z = 0.02;
    } else if (op.t === 'poly') {
      const shape = new THREE.Shape(op.pts.map(p => new THREE.Vector2(p[0], G - p[1])));
      const bev = Math.min(2.5, depth / 4);
      const geo = new THREE.ExtrudeGeometry(shape, { depth: Math.max(0.5, depth - bev * 2), bevelEnabled: depth > 4, bevelSize: bev * 0.8, bevelThickness: bev, bevelSegments: 2 });
      const me = add(geo, matFor(op.m, op), op); me.position.z = zf - depth + (depth > 4 ? bev : 0);
    } else if (op.t === 'ell') {
      let me;
      if (op.ring) { me = add(new THREE.TorusGeometry(op.rx - op.ring / 2, op.ring * 0.62, 10, 40), matFor(op.m, op), op); me.position.set(op.cx, G - op.cy, zf - 4); }
      else if (op.face) { me = add(new THREE.SphereGeometry(1, 10, 8), matFor(op.m, op), op, false); me.scale.set(op.rx, op.ry, 1.5); me.position.set(op.cx, G - op.cy, zf + 18); }
      else if (op.leaf) { me = add(new THREE.IcosahedronGeometry(1, 1), matFor(op.m, op), op); me.scale.set(op.rx, op.ry, op.rx * 0.7); me.position.set(op.cx, G - op.cy, zf - op.rx * 0.4); }
      else if (op.kid || op.d >= 20 || op.glow || op.stand) { const dz = op.kid ? op.rx * 0.95 : Math.max(op.d / 2, op.rx * 0.6); me = add(new THREE.SphereGeometry(1, 28, 20), matFor(op.m, op), op); me.scale.set(op.rx, op.ry, dz); me.position.set(op.cx, G - op.cy, zf - (op.kid ? 6 : dz)); }
      else { const geo = new THREE.CylinderGeometry(1, 1, depth, 36); geo.rotateX(Math.PI / 2); me = add(geo, matFor(op.m, op), op); me.scale.set(op.rx, op.ry, 1); me.position.set(op.cx, G - op.cy, zc); }
    } else if (op.t === 'line') {
      const rad = Math.max(1.2, op.w / 2) * (op.m === 'wire' ? 0.8 : 1);
      const zz = zf - (op.stand ? 6 : 2);
      const pts = op.pts.map(p => new THREE.Vector3(p[0], G - p[1], zz));
      for (let k = 0; k < pts.length - 1; k++) {
        const a = pts[k], b = pts[k + 1]; const len = a.distanceTo(b); if (len < 0.01) continue;
        const geo = new THREE.CylinderGeometry(rad, rad, len, 8, 1, false); const me = add(geo, matFor(op.m, op), op, op.m !== 'wire' || true);
        me.position.copy(a).add(b).multiplyScalar(0.5); me.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), b.clone().sub(a).normalize());
        if (k > 0) { const j = add(new THREE.SphereGeometry(rad, 8, 6), matFor(op.m, op), op); j.position.copy(a); }
      }
    }
  }

  // 背景板：画好的天 + 远处楼的剪影，立在后面
  { const c = document.createElement('canvas'); c.width = 2048; c.height = 1024; const x = c.getContext('2d');
    const g = x.createLinearGradient(0, 0, 0, 1024); for (const [t, col] of lk.sky) g.addColorStop(t, col); x.fillStyle = g; x.fillRect(0, 0, 2048, 1024);
    const sx = env.scene === 'street' ? 1650 : 330, sy = env.scene === 'street' ? 560 : 300;
    const rg = x.createRadialGradient(sx, sy, 0, sx, sy, 600); rg.addColorStop(0, env.time === 'dusk' ? 'rgba(255,220,170,0.9)' : 'rgba(255,250,230,0.9)'); rg.addColorStop(0.12, env.time === 'dusk' ? 'rgba(255,190,140,0.5)' : 'rgba(255,240,210,0.4)'); rg.addColorStop(1, 'rgba(255,190,140,0)'); x.fillStyle = rg; x.fillRect(0, 0, 2048, 1024);
    const r = mkRnd(4); x.fillStyle = env.time === 'dusk' ? 'rgba(90,70,140,0.85)' : 'rgba(150,175,205,0.8)';
    for (let k = 0; k < 26; k++) { const w = 60 + r() * 90, h = 120 + r() * 260, xx = k * 82 + r() * 30; x.fillRect(xx, 1024 - h, w, h); }
    if (env.time === 'dusk') { for (let k = 0; k < 400; k++) { x.fillStyle = `rgba(255,${200 + r() * 40},140,${0.4 + r() * 0.5})`; x.fillRect(r() * 2048, 760 + r() * 260, 5, 7); } }
    x.fillStyle = env.time === 'dusk' ? 'rgba(60,46,100,0.95)' : 'rgba(120,150,185,0.9)';
    for (let k = 0; k < 18; k++) { const w = 90 + r() * 120, h = 60 + r() * 140, xx = k * 120 + r() * 40; x.fillRect(xx, 1024 - h, w, h); }
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
    const bd = new THREE.Mesh(new THREE.PlaneGeometry(4200, 2100), new THREE.MeshBasicMaterial({ map: t, fog: false, toneMapped: false }));
    bd.position.set(960, (env.scene === 'street' ? 640 : 820) + 2100 / 2 - 1050 + 400, -1400); scene.add(bd); }
  // 模型底座：地面下一块木头台子，正面看得见切面
  { const yb = env.scene === 'street' ? 0 : -280;
    const soil = new THREE.Mesh(new THREE.BoxGeometry(2600, 70, BASEZ + 900), new THREE.MeshStandardMaterial({ color: '#4A3A34', roughness: 0.9 }));
    soil.position.set(960, yb - 36, BASEZ - (BASEZ + 900) / 2); soil.receiveShadow = true; scene.add(soil);
    const wood = new THREE.Mesh(new THREE.BoxGeometry(2640, 60, BASEZ + 920), new THREE.MeshStandardMaterial({ color: '#7A5236', roughness: 0.6 }));
    wood.position.set(960, yb - 100, BASEZ + 10 - (BASEZ + 920) / 2); wood.receiveShadow = true; scene.add(wood); }
  // 灯
  const hemi = new THREE.HemisphereLight(lk.hemi[0], lk.hemi[1], lk.hemi[2]); scene.add(hemi);
  scene.add(new THREE.AmbientLight('#ffffff', lk.amb));
  const sun = new THREE.DirectionalLight(lk.sun.col, lk.sun.k);
  sun.position.set(960 + lk.sun.pos[0], lk.sun.pos[1], lk.sun.pos[2]); sun.target.position.set(960, 300, 0);
  sun.castShadow = true; sun.shadow.mapSize.set(4096, 4096);
  const sc = sun.shadow.camera; sc.left = -1700; sc.right = 1700; sc.top = 1500; sc.bottom = -1500; sc.near = 100; sc.far = 8000;
  sun.shadow.bias = -0.0004; sun.shadow.normalBias = 1.5; sun.shadow.radius = 4;
  scene.add(sun); scene.add(sun.target);

  // 后期：环境光遮蔽 → 辉光 → 移轴 + 暗角
  const comp = new EffectComposer(renderer);
  comp.setSize(W, H);
  comp.addPass(new RenderPass(scene, cam));
  try { const ao = new GTAOPass(scene, cam, W, H); ao.updateGtaoMaterial({ radius: 40, distanceExponent: 1.5, thickness: 6, scale: 1.2, samples: 12 }); ao.blendIntensity = 0.85; comp.addPass(ao); } catch (e) { console.log('no AO', e.message); }
  comp.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), env.time === 'dusk' ? 0.32 : 0.15, 0.5, 0.9));
  comp.addPass(new OutputPass());
  const tilt = new ShaderPass({
    uniforms: { tDiffuse: { value: null }, focus: { value: env.scene === 'street' ? 0.45 : 0.56 }, band: { value: env.scene === 'street' ? 0.24 : 0.3 }, amt: { value: 3.0 } },
    vertexShader: 'varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);} ',
    fragmentShader: `uniform sampler2D tDiffuse; uniform float focus, band, amt; varying vec2 vUv;
      void main(){ float d = max(0.0, abs(vUv.y - focus) - band); float r = d * amt / 1080.0 * 60.0; vec4 acc = vec4(0.0); float wsum = 0.0;
        for (int i=-6;i<=6;i++) for (int j=-6;j<=6;j++){ vec2 o = vec2(float(i), float(j)) / 6.0; if (dot(o,o) > 1.0) continue; acc += texture2D(tDiffuse, vUv + o * r * vec2(1080.0/1920.0, 1.0)); wsum += 1.0; }
        vec4 c = acc / wsum; vec2 q = vUv - 0.5; float v = 1.0 - dot(q, q) * 0.9; gl_FragColor = vec4(c.rgb * v, 1.0); }`,
  });
  comp.addPass(tilt);
  comp.render();
  return renderer.domElement;
};
