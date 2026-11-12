// 搭好的模型拍一张：正交镜头正对着，模型自己带斜投影（build.js 里的 root.matrix），所以横着切多少片都接得上。
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { Builder } from './build.js';

// 三种质感各自的光：塑料要亮、影子利落；黏土要软、影子大而虚；低多边形要硬光、面一块块分明
const LOOKS = {
  toy: { sun: { dir: [-0.72, 0.55, 0.5], col: '#FFE2BC', k: 3.4 }, hemi: ['#CFE0FF', '#B89A80', 0.85], radius: 5, exposure: 1.0, bloom: 0.35 },
  clay: { sun: { dir: [-0.6, 0.65, 0.55], col: '#FFE8CC', k: 2.4 }, hemi: ['#E6EEFF', '#C9AE94', 1.25], radius: 16, exposure: 1.04, bloom: 0.2 },
  lowpoly: { sun: { dir: [-0.78, 0.5, 0.42], col: '#FFF0D8', k: 3.8 }, hemi: ['#BFD6FF', '#A88C78', 0.75], radius: 1, exposure: 1.0, bloom: 0.25 },
};

export async function render(data, opt) {
  const S = opt.scale || 1, x = opt.x || 0, w = opt.w || 2133;
  const top = data.top, bottom = data.bottom, H = bottom - top;
  const W = Math.round(w * S), HH = Math.round(H * S);
  const LOOK = LOOKS[opt.variant] || LOOKS.toy;
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
  renderer.setSize(W, HH); renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = LOOK.exposure;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.setClearColor(0x000000, 0);
  const scene = new THREE.Scene();
  const b = new Builder(data, opt.variant);
  const t0 = performance.now();
  scene.add(b.build());
  const cam = new THREE.OrthographicCamera(x, x + w, -top, -bottom, 10, 20000);
  cam.position.set(0, 0, 8000); cam.lookAt(0, 0, 0);
  // 正交镜头的 left/right 是相对镜头的：镜头放在原点正前方，框住 [x, x+w]
  cam.updateProjectionMatrix();

  scene.add(new THREE.HemisphereLight(LOOK.hemi[0], LOOK.hemi[1], LOOK.hemi[2]));
  const sun = new THREE.DirectionalLight(LOOK.sun.col, LOOK.sun.k);
  const d = new THREE.Vector3(...LOOK.sun.dir).normalize();
  const cx = x + w / 2, cy = -(top + H / 2);
  sun.position.set(cx + d.x * 4000, cy + d.y * 4000, d.z * 4000);
  sun.target.position.set(cx, cy, 0); scene.add(sun.target);
  sun.castShadow = true;
  const R = Math.max(w, H) / 2 + 500;
  Object.assign(sun.shadow.camera, { left: -R, right: R, top: R, bottom: -R, near: 100, far: 9000 });
  sun.shadow.mapSize.set(4096, 4096); sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.6; sun.shadow.radius = LOOK.radius;
  if (opt.variant === 'lowpoly') renderer.shadowMap.type = THREE.PCFShadowMap;
  scene.add(sun);
  // 屋里的灯（白天也开一点点，暖）
  for (const [lx, ly] of (data.anchors.street_lamp || []).concat(data.anchors.hall_lamp || [])) {
    if (lx < x - 600 || lx > x + w + 600) continue;
    const p = new THREE.PointLight('#FFC27A', 0.0, 300, 2); p.position.set(lx, -ly, 60); scene.add(p);
  }

  if (opt.backdrop) {
    // 只给预览用：一块渐变的天 + 远处一排虚掉的楼（引擎里天和远景是各自的层）
    const c = document.createElement('canvas'); c.width = 4; c.height = 512; const g = c.getContext('2d');
    const gr = g.createLinearGradient(0, 0, 0, 512);
    gr.addColorStop(0, '#8DB8E0'); gr.addColorStop(0.55, '#CFE2EE'); gr.addColorStop(1, '#F6E3C6');
    g.fillStyle = gr; g.fillRect(0, 0, 4, 512);
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; scene.background = t;
  }

  // 切片：同一个模型挪镜头一片片拍（opt.tiles = [x0, x1, …]，每片宽 w）
  const place = (tx) => {
    cam.left = tx; cam.right = tx + w; cam.updateProjectionMatrix();
    const ccx = tx + w / 2;
    sun.position.set(ccx + d.x * 4000, cy + d.y * 4000, d.z * 4000);
    sun.target.position.set(ccx, cy, 0); sun.target.updateMatrixWorld();
  };
  const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(W, HH, { type: THREE.HalfFloatType, samples: 4 }));
  composer.addPass(new RenderPass(scene, cam));
  if (opt.ao !== false) {
    try {
      const ao = new GTAOPass(scene, cam, W, HH);
      ao.updateGtaoMaterial({ radius: 30, distanceExponent: 1.4, thickness: 6, scale: 1.0 });
      ao.blendIntensity = 0.85;
      composer.addPass(ao);
    } catch (e) { console.log('no ao', e.message); }
  }
  if (opt.backdrop) composer.addPass(new UnrealBloomPass(new THREE.Vector2(W, HH), LOOK.bloom, 0.6, 0.9));
  composer.addPass(new OutputPass());
  if (opt.tiles) {
    window.TILES = [];
    for (const tx of opt.tiles) { place(tx); composer.render(); window.TILES.push(renderer.domElement.toDataURL('image/png')); }
    return { ms: performance.now() - t0, meshes: b.root.children.length, tiles: opt.tiles.length };
  }
  composer.render();
  const out = renderer.domElement; out.id = 'out'; document.body.appendChild(out);
  return { ms: performance.now() - t0, meshes: b.root.children.length };
}
