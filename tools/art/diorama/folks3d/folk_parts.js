// 街坊、路人的零件：挂在 pose3d/figure.js 的 EXT 上（主角不挂这些，长相一点不变）。
//   EXT.hair   发型（平头、分头、寸头、谢顶、烫发、盘髻、短发、马尾、披肩）
//   EXT.torso  围裙（挂在躯干上，跟着弯腰）
//   EXT.extra  帽子、套袖、肩上的毛巾、小板凳、菜篮子、公文包
//   EXT.face   胡子、皱纹
// 长相写在 folks3d.py 的 LOOKS（spec.look），这里只管怎么搭。坐标同 figure.js：头上 x 朝脸、y 朝上、z 朝镜头那侧。
import * as THREE from 'three';
import { EXT, ball, cone, taper, dirAE, mixA, rnd, roundBox, mixHex, segs, lathe } from '../pose3d/figure.js';

const D2R = Math.PI / 180;
const V = (p, z = 0) => new THREE.Vector3(p[0], -p[1], z);

// ---------------------------------------------------------------- 头发
// 同 figure.js 的 hairShell，多一个 top(A)：只在 line(A) < 仰角 < top(A) 之间有头发（谢顶的一圈）
function shell(F, r, line, o = {}) {
  const g = new THREE.SphereGeometry(1, segs(F.v, 160, 36), segs(F.v, 110, 24));
  const p = g.attributes.position;
  const v = new THREE.Vector3();
  const tufts = o.tufts || [];
  const edge = o.edge || 3.5;
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i).normalize();
    const A = Math.atan2(v.z, v.x) / D2R, E = Math.asin(Math.max(-1, Math.min(1, v.y))) / D2R;
    let h = THREE.MathUtils.smoothstep(E, line(A) - edge, line(A) + edge);
    if (o.top) h *= 1 - THREE.MathUtils.smoothstep(E, o.top(A) - edge, o.top(A) + edge);
    let R = 1.0 + (o.thick ?? 0.09);
    for (const t of tufts) { const d = v.dot(t.d); R += t.a * Math.exp(-(1 - d) / t.s); }
    if (o.flare) R += o.flare * THREE.MathUtils.smoothstep(-E, 5, 60);
    if (o.puff) R += o.puff * Math.exp(-Math.pow((E - 35) / 35, 2));
    const IN = F.v === 'lowpoly' ? 0.86 : 0.94;
    const RR = IN + (R - IN) * h;
    let hx = v.x, hz = v.z, hy = v.y;
    if (o.hang && E < 0 && h > 0.01) {
      const hk = o.hang * h; const horiz = Math.hypot(v.x, v.z) || 1;
      const want = horiz + (1 - horiz) * hk;
      hx = v.x / horiz * want; hz = v.z / horiz * want; hy = v.y * (1 + 0.15 * hk);
    }
    p.setXYZ(i, hx * RR * r, hy * RR * r, hz * RR * r);
  }
  g.computeVertexNormals();
  return g;
}

EXT.hair = (F, head, r) => {
  const H = F.look.hair || {};
  const style = H.style || 'crew';
  const col = H.color || '#3A2A2C';
  const grey = !!H.grey;
  const M = F.mats.get(col, { rough: H.rough ?? (grey ? 0.55 : 0.4) });
  const add = (g, m = M) => { const me = new THREE.Mesh(g, m); me.castShadow = true; me.receiveShadow = true; head.add(me); return me; };
  const R = rnd(H.seed || 31);
  const tufts = [];
  const mk = (n, a, s, emin, emax, amin = -180, amax = 180) => { for (let i = 0; i < n; i++) tufts.push({ d: dirAE(amin + R() * (amax - amin), emin + R() * (emax - emin)), a: a * (0.6 + R() * 0.6), s }); };
  const hatted = !!F.look.hat;
  if (style === 'crew') {        // 平头：短、齐，额前一道浅浅的刘海
    mk(10, 0.03, 0.015, 10, 80);
    add(shell(F, r, (A) => mixA(A, 24 + 2.5 * Math.abs(Math.sin(A * D2R * 7)), -4, -34), { tufts, thick: 0.075, edge: 3 }));
  } else if (style === 'kid') {  // 小男孩：短，乱一点，前面一撮
    mk(14, 0.05, 0.02, 10, 80);
    add(shell(F, r, (A) => mixA(A, 18 + 7 * Math.abs(Math.sin(A * D2R * 6)), -2, -36), { tufts, thick: 0.1, edge: 3 }));
  } else if (style === 'buzz') { // 寸头：贴着头皮
    add(shell(F, r, (A) => mixA(A, 30, 0, -32), { thick: 0.035, edge: 2.5 }));
  } else if (style === 'side') { // 分头：靠镜头这边高、另一边压下来，发缝一道
    mk(6, 0.025, 0.02, 30, 80);
    add(shell(F, r, (A) => mixA(A, 22 + A * 0.14 + 2.5 * Math.abs(Math.sin(A * D2R * 3)), -4, -36), { tufts, thick: 0.09, edge: 3, puff: 0.04 }));
  } else if (style === 'bald') { // 谢顶：耳朵上面、后脑勺一圈
    mk(8, 0.025, 0.015, -20, 20, 70, 290);
    add(shell(F, r, (A) => mixA(A, 60, -6, -34), { tufts, thick: 0.06, edge: 4, top: (A) => mixA(A, 60, 22, 30) }));
  } else if (style === 'perm') { // 烫发：一头小卷，蓬起来、盖住耳朵
    mk(90, 0.075, 0.007, -30, 88);
    add(shell(F, r, (A) => { const a = Math.abs(A); return a < 50 ? 18 + 4 * Math.abs(Math.sin(A * D2R * 8)) : mixA(A, 18, -24, -40); }, { tufts, thick: 0.13, hang: 0.3, flare: 0.06, edge: 3.5, puff: 0.06 }));
  } else if (style === 'bun') {  // 盘髻：往后梳，后脑一个髻
    mk(12, 0.025, 0.012, 0, 80);
    add(shell(F, r, (A) => mixA(A, 28, 2, -30) + 2.5 * Math.abs(Math.sin(A * D2R * 6)), { tufts, thick: 0.07, edge: 4 }));
    if (!hatted || F.look.hat.kind === 'nurse') { const bun = add(ball(r * 0.4, 1, 0.9, 1, F)); bun.position.copy(dirAE(180, H.bunE ?? 30).multiplyScalar(r * 1.04)); }
  } else if (style === 'bob' || style === 'long') { // 齐耳短发 / 披肩
    mk(8, 0.02, 0.02, 20, 80);
    const side = style === 'bob' ? -40 : -64, back = style === 'bob' ? -50 : -74;
    const fr = 14 + (H.part ? 6 : 0);
    const hl = (A) => {
      const a = Math.abs(A);
      let bang = fr + 2.5 * Math.abs(Math.sin(A * D2R * 9)) + (a > 40 ? (a - 40) * 0.4 : 0);
      if (H.part) bang = fr + 14 * Math.exp(-Math.pow((A + 10) / 16, 2)) + (a > 40 ? (a - 40) * 0.3 : 0);
      if (a < 55) return bang;
      const t = THREE.MathUtils.smoothstep(a, 55, 72);
      return bang + (mixA(A, 0, side, back) - bang) * t;
    };
    add(shell(F, r, hl, { tufts, thick: 0.1, hang: 0.45, flare: style === 'long' ? 0.08 : 0.05, edge: 3.5 }));
    if (style === 'long') { const bk = add(ball(r * 0.8, 0.7, 1.1, 1.05, F)); bk.position.set(-r * 0.48, -r * 0.6, 0); }
  } else if (style === 'pony') { // 马尾：往后梳，扎一把（高 / 低）
    mk(8, 0.02, 0.02, 20, 80);
    add(shell(F, r, (A) => mixA(A, 20 + 9 * Math.exp(-Math.pow((A - 20) / 22, 2)), -8, -26), { tufts, thick: 0.09, edge: 3.5 }));
    const hi = H.high ? 40 : 12;
    const b0 = dirAE(180, hi).multiplyScalar(r * 1.05);
    const k = H.high ? 1.0 : 0.85;
    add(taper([b0, b0.clone().add(new THREE.Vector3(-0.3 * r, 0.02 * r, 0)), b0.clone().add(new THREE.Vector3(-0.42 * r, -0.4 * r * k, 0.02 * r)), b0.clone().add(new THREE.Vector3(-0.32 * r, -0.95 * r * k, 0.05 * r))],
      [r * 0.17, r * 0.24, r * 0.2, r * 0.05], F, 20));
    const tie = add(new THREE.TorusGeometry(r * 0.15, r * 0.06, 8, 18), F.mats.get(H.tie || '#5F86AE', {}));
    tie.position.copy(b0.clone().add(new THREE.Vector3(-0.06 * r, 0, 0))); tie.rotation.y = Math.PI / 2; tie.rotation.x = 0.3;
  }
  if (F.look.hat) buildHat(F, head, r, F.look.hat);
};

// ---------------------------------------------------------------- 帽子（扣在头上，跟着头转）
function buildHat(F, head, r, hat) {
  const add = (g, m) => { const me = new THREE.Mesh(g, m); me.castShadow = true; me.receiveShadow = true; head.add(me); return me; };
  const M = F.mats.get(hat.color, { rough: hat.rough ?? 0.6 });
  const g = new THREE.Group(); head.add(g);
  g.rotation.z = (hat.tilt ?? -6) * D2R;   // 帽子稍微往后扣一点
  const addG = (geo, m = M) => { const me = new THREE.Mesh(geo, m); me.castShadow = true; me.receiveShadow = true; g.add(me); return me; };
  const kind = hat.kind;
  if (kind === 'cap') {
    // 前进帽 / 工作帽：圆筒的帽身，顶上微微鼓、比帽口大一圈，前面一片短帽檐
    const y0 = r * 0.3;
    addG(lathe([[r * 1.1, 0], [r * 1.13, r * 0.26], [r * 1.2, r * 0.58], [r * 1.17, r * 0.72], [r * 0.95, r * 0.8], [0, r * 0.82]], F, 1, 1)).position.y = y0;
    const band = addG(new THREE.TorusGeometry(r * 1.11, r * 0.06, 8, 40), F.mats.get(mixHex(hat.color, '#000000', 0.25), {})); band.rotation.x = Math.PI / 2; band.position.y = y0 + r * 0.06;
    const brim = addG(new THREE.CylinderGeometry(r * 0.75, r * 0.75, r * 0.08, 24, 1, false, 0, Math.PI), F.mats.get(mixHex(hat.color, '#000000', 0.35), { rough: 0.4 }));
    brim.scale.set(0.85, 1, 1.3); brim.position.set(r * 0.72, y0 + r * 0.02, 0); brim.rotation.z = -0.22;
    if (hat.badge) { const s = addG(new THREE.SphereGeometry(r * 0.1, 12, 8), F.mats.get(hat.badge, { rough: 0.3 })); s.scale.set(0.5, 1, 1); s.position.set(r * 1.18, y0 + r * 0.45, 0); }
  } else if (kind === 'helmet') {
    // 安全帽：亮的半球、一道脊、一圈帽檐（前面长）
    const MH = F.mats.get(hat.color, { rough: 0.3 });
    addG(new THREE.SphereGeometry(r * 1.17, segs(F.v, 32, 10), segs(F.v, 16, 5), 0, Math.PI * 2, 0, Math.PI / 2), MH).position.y = r * 0.12;
    const ridge = addG(new THREE.CapsuleGeometry(r * 0.1, r * 1.2, 4, 10), MH); ridge.rotation.z = Math.PI / 2; ridge.position.y = r * 1.22; ridge.scale.set(1, 1, 1);
    const ridge2 = addG(new THREE.TorusGeometry(r * 1.12, r * 0.1, 8, 30, Math.PI), MH); ridge2.position.y = r * 0.12;
    const brim = addG(new THREE.CylinderGeometry(r * 1.32, r * 1.36, r * 0.08, 36), MH); brim.scale.set(1.12, 1, 1); brim.position.set(r * 0.14, r * 0.14, 0);
  } else if (kind === 'nurse') {
    // 护士帽：头顶前头一小块白，中间一个小红十字
    const cap = addG(roundBox(r * 1.1, r * 0.42, r * 1.25, r * 0.12, F), F.mats.get('#FBF8F2', {})); cap.position.set(r * 0.25, r * 0.98, 0); cap.rotation.z = 0.35;
    const red = F.mats.get('#D86A6A', {});
    const c1 = addG(roundBox(r * 0.07, r * 0.26, r * 0.08, 0.01, F), red); c1.position.set(r * 0.75, r * 1.18, 0); c1.rotation.z = 0.35 + Math.PI / 2 - 0.0; c1.rotation.set(0, Math.PI / 2, 0.35);
    c1.position.set(r * 0.62, r * 1.02, 0); c1.rotation.set(0, 0, 0.35); c1.scale.set(1, 1, 1);
    const c2 = addG(roundBox(r * 0.07, r * 0.07, r * 0.26, 0.01, F), red); c2.position.copy(c1.position); c2.rotation.copy(c1.rotation);
    c1.position.x += r * 0.06; c2.position.x += r * 0.06;
  } else if (kind === 'straw') {
    // 草帽：宽帽檐、浅顶、一道带子
    const MS = F.mats.get(hat.color || '#E3C88A', { rough: 0.8 });
    addG(lathe([[r * 1.12, 0], [r * 1.1, r * 0.5], [r * 0.92, r * 0.8], [0, r * 0.86]], F, 1, 1), MS).position.y = r * 0.36;
    const brim = addG(lathe([[r * 1.0, r * 0.06], [r * 1.6, -r * 0.02], [r * 2.0, -r * 0.14], [r * 2.02, -r * 0.2], [r * 1.6, -r * 0.1], [r * 1.0, -r * 0.02]], F, 1, 1), MS); brim.position.y = r * 0.34;
    const band = addG(lathe([[r * 1.06, 0], [r * 1.07, r * 0.13]], F, 1, 1), F.mats.get(hat.band || '#5F86AE', {})); band.position.y = r * 0.36;
  } else if (kind === 'bucket') {
    // 渔夫帽：软软的帽身、往下斜的一圈帽檐
    addG(lathe([[r * 1.12, 0], [r * 1.12, r * 0.45], [r * 0.98, r * 0.8], [0, r * 0.88]], F, 1, 1)).position.y = r * 0.3;
    addG(lathe([[r * 1.12, r * 0.02], [r * 1.5, -r * 0.3], [r * 1.52, -r * 0.36], [r * 1.1, -r * 0.06]], F, 1, 1)).position.y = r * 0.32;
  } else if (kind === 'ball') {
    // 鸭舌帽：半球帽身、长帽檐
    addG(new THREE.SphereGeometry(r * 1.1, segs(F.v, 32, 10), segs(F.v, 16, 5), 0, Math.PI * 2, 0, Math.PI / 2)).position.y = r * 0.14;
    const brim = addG(new THREE.CylinderGeometry(r * 0.85, r * 0.85, r * 0.07, 24, 1, false, 0, Math.PI), F.mats.get(hat.brim || hat.color, {}));
    brim.scale.set(1.1, 1, 1.05); brim.position.set(r * 0.7, r * 0.2, 0); brim.rotation.z = -0.12;
    const knob = addG(new THREE.SphereGeometry(r * 0.1, 10, 8)); knob.position.y = r * 1.24;
  } else if (kind === 'chef') {
    addG(lathe([[r * 1.06, 0], [r * 1.08, r * 0.3], [r * 1.18, r * 0.6], [r * 1.0, r * 0.8], [0, r * 0.84]], F, 1, 1), F.mats.get('#FBF8F2', {})).position.y = r * 0.2;
  }
}

// ---------------------------------------------------------------- 围裙
EXT.torso = (F, G) => {
  const ap = F.look.apron;
  if (!ap) return;
  const { tg, rad, T, w, breadth, fr } = G;
  const M = F.mats.get(ap, { rough: 0.6 });
  const pts = [];
  // 胸口往下到腰：贴着身子（往外让一点）；腰往下：站着垂到大腿，坐着就到腰
  for (let i = 0; i <= 10; i++) { const t = 0.72 - i * 0.07; pts.push(new THREE.Vector2(rad(t) + 1.0 + (F.spec.belly || 0) * 4 * Math.exp(-Math.pow((t - 0.3) / 0.28, 2)) * rad(t), t * T)); }
  if (!fr.sit) {
    const th = F.spec.thigh;
    pts.push(new THREE.Vector2(w * 0.62, -th * 0.25), new THREE.Vector2(w * 0.7, -th * 0.6), new THREE.Vector2(w * 0.74, -th * 0.82));
  }
  pts.reverse();
  const g = new THREE.LatheGeometry(pts, segs(F.v, 24, 8), Math.PI / 2 - 0.95, 1.9);
  g.scale(1, 1, breadth * 1.02);
  const me = new THREE.Mesh(g, M); me.castShadow = true; me.receiveShadow = true; me.material.side = THREE.DoubleSide; tg.add(me);
  // 系带：腰上一圈
  const tie = new THREE.Mesh(lathe([[rad(0.12) + 0.8, 0.1 * T], [rad(0.12) + 1.2, 0.13 * T], [rad(0.12) + 0.8, 0.16 * T]], F, 1, breadth), M); tg.add(tie);
  // 脖子上的带子：两根细管
  const top = 0.72 * T;
  for (const s of [1, -1]) {
    const a = new THREE.Vector3(rad(0.72) * 0.85, top, s * rad(0.72) * breadth * 0.45);
    const b = new THREE.Vector3(rad(1.0) * 0.2, 1.04 * T, s * rad(1.0) * breadth * 0.5);
    tg.add(new THREE.Mesh(cone(a, b, 0.7, 0.7, F), M));
  }
  if (fr.sit) { // 坐着：围裙下摆搭在腿上
    const L = fr.legs.near, hip = V(fr.hip, 0), knee = V(L.knee, 0);
    const m = new THREE.Mesh(roundBox(Math.max(4, knee.x - hip.x) * 0.75, 1.6, w * 1.05, 0.7, F), M);
    m.position.set(hip.x + (knee.x - hip.x) * 0.42, Math.max(hip.y, knee.y) + F.spec.limb * 0.55, 0);
    m.rotation.z = Math.atan2(knee.y - hip.y, knee.x - hip.x); m.castShadow = true;
    G.root.add(m);
  }
};

// ---------------------------------------------------------------- 帽子以外：套袖、毛巾、板凳、篮子、包
EXT.extra = (F, G) => {
  const L = F.look, fr = G.fr, add = G.add;
  const mats = F.mats;
  if (L.sleeves) { // 套袖：小臂上套一截
    const ar = (F.spec.limb - 1) * 0.5 * (F.design.limbK || 1);
    for (const side of ['far', 'near']) {
      const z = side === 'near' ? G.zA : -G.zA;
      const el = V(fr['elbow_' + side], z), hd = V(fr['hand_' + side], z);
      const a = el.clone().lerp(hd, 0.08), b = el.clone().lerp(hd, 0.8);
      add(cone(a, b, ar * 1.12, ar * 1.08, F), mats.get(L.sleeves));
      add(ball(ar * 1.08, 1, 0.4, 1, F), mats.get(L.sleeves)).position.copy(b);
      add(ball(ar * 1.12, 1, 0.4, 1, F), mats.get(L.sleeves)).position.copy(a);
    }
  }
  if (L.towel) { // 肩上搭一条毛巾
    const sh = V(fr.shoulder, 0);
    const t = add(roundBox(9, 3, G.cw * 1.25 * G.breadth, 1.4, F), mats.get(L.towel, { rough: 0.85 }));
    t.position.copy(sh).add(new THREE.Vector3(-1, 1.5, 0)); t.rotation.z = -fr.lean * D2R;
    const hang = add(roundBox(8, 16, 2.4, 1.2, F), mats.get(L.towel, { rough: 0.85 }));
    hang.position.copy(sh).add(new THREE.Vector3(3, -6, G.cw * 0.62 * G.breadth)); hang.rotation.z = -fr.lean * D2R;
  }
  if (fr.sit && L.stool !== false) { // 小板凳
    const wood = mats.get(L.stool || '#B98A5A', { rough: 0.7 });
    const hy = -fr.hip[1] - F.spec.limb * 0.65; // 凳面在屁股底下
    const cx = fr.hip[0] - 3;
    const top = add(roundBox(30, 4, 22, 1.6, F), wood); top.position.set(cx, hy - 2, 0);
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      add(cone(new THREE.Vector3(cx + sx * 11, hy - 3, sz * 7), new THREE.Vector3(cx + sx * 13, 0, sz * 8.5), 1.5, 1.5, F), wood);
    }
    const bar = add(cone(new THREE.Vector3(cx - 12, hy * 0.4, 8), new THREE.Vector3(cx + 12, hy * 0.4, 8), 1.1, 1.1, F), wood);
  }
  if (fr.stove) { // 烤山芋的汽油桶炉子：在人身后靠前一点，桶口上摆几块山芋
    const sx = fr.stove[0], sz = -G.zA - 6;
    const metal = mats.get('#4E4A52', { rough: 0.5 });
    const drum = add(new THREE.CylinderGeometry(17, 17, 58, segs(F.v, 28, 8)), metal); drum.position.set(sx, 29, sz);
    for (const y of [12, 40]) { const rib = add(new THREE.TorusGeometry(17.3, 1.1, 6, 28), metal); rib.rotation.x = Math.PI / 2; rib.position.set(sx, y, sz); }
    const rim = add(new THREE.TorusGeometry(17, 1.8, 8, 28), mats.get('#3A363C', { rough: 0.45 })); rim.rotation.x = Math.PI / 2; rim.position.set(sx, 58, sz);
    const door = add(roundBox(14, 9, 2, 1.5, F), mats.get('#2A2428', {})); door.position.set(sx + 1, 14, sz + 16.6);
    const glow = add(roundBox(10, 5, 1, 1, F), new THREE.MeshBasicMaterial({ color: '#F08A3A' })); glow.position.set(sx + 1, 14, sz + 17.4);
    const yam = mats.get('#9A5A48', { rough: 0.7 });
    for (const [dx, dz, a] of [[-7, -4, 0.3], [5, -3, -0.4], [-1, 6, 0.1], [8, 7, 0.6]]) { const y = add(ball(5, 1.6, 0.8, 0.9, F), yam); y.position.set(sx + dx, 60, sz + dz); y.rotation.y = a; }
    const tongs = add(cone(new THREE.Vector3(sx + 14, 72, sz + 10), new THREE.Vector3(sx + 4, 61, sz + 4), 0.8, 0.8, F), mats.get('#6A6670', {}));
  }
  if (fr.stroller) { // 婴儿车：把手在近侧手里，车筐往前，篷子罩在前头
    const h = V(fr.hand_near, 0);
    const x0 = h.x + 8, x1 = Math.min(94, x0 + 44), mid = (x0 + x1) / 2, len = x1 - x0;
    const body = mats.get(L.strollerColor || '#5F86AE', { rough: 0.5 }), trim = mats.get('#F5F0E6', {}), dark = mats.get('#3A363C', { rough: 0.5 });
    const wz = 11;
    const bk = add(roundBox(len, 16, 22, 5, F), body); bk.position.set(mid, 30, 0);
    const lip = add(roundBox(len + 2, 2.4, 23, 1.1, F), trim); lip.position.set(mid, 38.5, 0);
    const hood = add(new THREE.SphereGeometry(12, segs(F.v, 24, 8), segs(F.v, 12, 4), 0, Math.PI, 0, Math.PI / 2), body);
    hood.scale.set(1.0, 1.15, 0.95); hood.rotation.set(0, Math.PI / 2, 0); hood.position.set(x1 - 11, 38, 0); hood.material.side = THREE.DoubleSide;
    const baby = add(ball(4.6, 1, 1, 1, F), mats.get(F.skin || '#F5BE96', { rough: 0.5 })); baby.position.set(x1 - 24, 41, 3);
    const bonnet = add(ball(5, 1, 0.75, 1, F), trim); bonnet.position.set(x1 - 25.5, 43.5, 3);
    // 把手：从手到车筐后沿
    add(cone(new THREE.Vector3(h.x + 2, h.y, wz), new THREE.Vector3(x0 + 3, 34, wz), 1.2, 1.2, F), dark);
    add(cone(new THREE.Vector3(h.x + 2, h.y, -wz), new THREE.Vector3(x0 + 3, 34, -wz), 1.2, 1.2, F), dark);
    add(cone(new THREE.Vector3(h.x + 1, h.y, -wz), new THREE.Vector3(h.x + 1, h.y, wz), 1.5, 1.5, F), dark);
    for (const sz of [-1, 1]) {
      add(cone(new THREE.Vector3(x0 + 6, 22, sz * wz), new THREE.Vector3(x1 - 6, 22, sz * wz), 0.9, 0.9, F), dark);
      for (const wx of [x0 + 6, x1 - 6]) {
        add(cone(new THREE.Vector3(wx, 22, sz * wz), new THREE.Vector3(wx, 6, sz * wz), 0.9, 0.9, F), dark);
        const wh = add(new THREE.TorusGeometry(5.2, 1.5, 8, 18), dark); wh.position.set(wx, 6.5, sz * (wz + 1));
        const hub = add(ball(1.6, 1, 1, 1, F), trim); hub.position.set(wx, 6.5, sz * (wz + 1));
      }
    }
  }
  if (L.basket && fr.hand_near) { // 菜篮子：挎在近侧手上
    const h = V(fr.hand_near, G.zA + 2);
    const bm = mats.get('#C8A46A', { rough: 0.85 });
    const bk = add(lathe([[6.5, 0], [10, 2], [11, 12], [10.5, 13]], F, 1.25, 0.9), bm); bk.position.copy(h).add(new THREE.Vector3(0, -17, 0));
    const veg = add(ball(4.5, 1.2, 0.8, 1, F), mats.get('#6E9A4C', {})); veg.position.copy(h).add(new THREE.Vector3(-3, -3.5, 0));
    const veg2 = add(ball(3.5, 1, 1, 1, F), mats.get('#D9763A', {})); veg2.position.copy(h).add(new THREE.Vector3(5, -4, 2));
    const handle = add(new THREE.TorusGeometry(10, 1.1, 6, 18, Math.PI), bm); handle.position.copy(h).add(new THREE.Vector3(0, -4.5, 0)); handle.scale.set(1.1, 0.5, 1);
  }
  if (L.briefcase && fr.hand_far) { // 公文包：拎在远侧手上
    const h = V(fr.hand_far, -G.zA - 2);
    const bc = add(roundBox(22, 15, 6, 2, F), mats.get(L.briefcase, { rough: 0.5 })); bc.position.copy(h).add(new THREE.Vector3(2, -10, 0));
    const hd = add(new THREE.TorusGeometry(3.4, 0.9, 6, 12, Math.PI), mats.get(L.briefcase, {})); hd.position.copy(h).add(new THREE.Vector3(2, -2.6, 0));
  }
  if (L.satchel) { // 斜挎的包：背在身后一侧
    const hip = V(fr.hip, -G.zA * 0.2);
    const sb = add(roundBox(14, 12, 5, 2, F), mats.get(L.satchel, { rough: 0.6 })); sb.position.copy(hip).add(new THREE.Vector3(-G.w * 0.55, 4, -G.zA * 0.6));
  }
};

// ---------------------------------------------------------------- 脸上：胡子、抬头纹
EXT.face = (F, x, at, E, P) => {
  const f = F.look.face || {};
  if (f.moustache) at(P.ML, P.ME + 5.5, () => {
    x.fillStyle = f.moustache;
    for (const s of [1, -1]) { x.beginPath(); x.ellipse(s * 2.6, 0, 3.2, 1.5, s * -0.25, 0, 7); x.fill(); }
  });
  if (f.stubble) at(P.ML, P.ME - 2, () => {
    const g = x.createRadialGradient(0, 0, 0, 0, 0, 14); g.addColorStop(0, 'rgba(70,60,70,0.28)'); g.addColorStop(1, 'rgba(70,60,70,0)');
    x.fillStyle = g; x.beginPath(); x.ellipse(0, 0, 16, 11, 0, 0, 7); x.fill();
  });
  if (f.lines) for (const s of [1, -1]) at(s * (P.EL + 9 * P.es), P.EE, () => { for (const a of [-0.45, 0, 0.45]) { x.beginPath(); x.moveTo(s * 0.5, a * 3); x.lineTo(s * 3.2, a * 5); P.stroke(0.6, 'rgba(160,100,90,0.7)'); } });
  if (f.soot) at(P.EL + 18, P.EE - 14, () => { x.fillStyle = 'rgba(60,50,55,0.25)'; x.beginPath(); x.ellipse(0, 0, 5, 3, 0.3, 0, 7); x.fill(); });
};
