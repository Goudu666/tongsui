// 风格 B：像素。480×270 原生分辨率，每样东西按 50% 阈值栅格化（不要抗锯齿的糊边），
// 逐像素打光，再按这张图自己的颜色聚出 40 色调色板；天和光晕用 4×4 拜耳抖动，其余直接取最近色。
const PS = 4, PW = 480, PH = 270;
const PLOOK = {
  dusk: { sky: [[0, '#1F2350'], [0.3, '#47407E'], [0.55, '#A35A86'], [0.78, '#E88A6E'], [1, '#FFC98A']], skyBot: 860,
    top: [255, 232, 208], bot: [150, 132, 190], shade: [118, 100, 172], sunlit: [255, 190, 130],
    farTint: [80, 64, 140], farMix: 0.4, midTint: [58, 46, 108], midMix: 0.6, outline: [34, 22, 44], farLights: 1 },
  morning: { sky: [[0, '#6FAEE0'], [0.6, '#BFE0EE'], [0.88, '#FBE3C4'], [1, '#FFD7A6']], skyBot: 380,
    top: [255, 250, 238], bot: [208, 200, 226], shade: [150, 146, 200], sunlit: [255, 236, 200],
    farTint: [160, 190, 222], farMix: 0.55, midTint: [130, 160, 200], midMix: 0.5, outline: [40, 34, 56], farLights: 0 },
};
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map(v => (v + 0.5) / 16);

async function render(env, L) {
  const lk = PLOOK[env.time];
  const N = PW * PH;
  const alb = new Float32Array(N * 3), emi = new Uint8Array(N), sky = new Uint8Array(N), gid = new Int32Array(N), shad = new Float32Array(N);
  const scr = canvas(PW, PH), sc = scr.getContext('2d', { willReadFrequently: true });
  const skyAt = (y) => { const t = Math.max(0, Math.min(1, y / lk.skyBot));
    for (let k = 1; k < lk.sky.length; k++) if (t <= lk.sky[k][0]) { const a = lk.sky[k - 1], b = lk.sky[k]; return mix(hex(a[1]), hex(b[1]), (t - a[0]) / (b[0] - a[0])); }
    return hex(lk.sky[lk.sky.length - 1][1]); };
  // 天
  for (let y = 0; y < PH; y++) { const c = skyAt(y * PS); for (let x = 0; x < PW; x++) { const i = y * PW + x; alb.set(c, i * 3); sky[i] = 1; } }
  // 太阳：像素圆 + 两圈光环
  { const s = env.sun; const cx = s.x / PS, cy = s.y / PS;
    for (let y = 0; y < PH; y++) for (let x = 0; x < PW; x++) { const d = Math.hypot(x - cx, y - cy); const i = y * PW + x;
      if (d < 16) { alb.set(env.time === 'dusk' ? [255, 236, 190] : [255, 248, 226], i * 3); sky[i] = 0; emi[i] = 1; }
      else if (d < 70) { const t = (1 - (d - 16) / 54) * 0.35; for (let k = 0; k < 3; k++) alb[i * 3 + k] += (255 - alb[i * 3 + k]) * t * [1, 0.85, 0.6][k]; } } }
  // 像素云：横条
  { const r = mkRnd(4); const n = env.time === 'dusk' ? 9 : 6;
    for (let k = 0; k < n; k++) { const cx = r() * PW, cy = 18 + r() * 50, w = 30 + r() * 60;
      for (let j = 0; j < 3; j++) { const yy = Math.round(cy + j * 2), x0 = Math.round(cx - w / 2 + j * 6 * (r() - 0.3)), x1 = Math.round(x0 + w - j * 10);
        const col = env.time === 'dusk' ? (j === 2 ? [255, 180, 140] : [200, 120, 150]) : (j === 2 ? [226, 232, 244] : [255, 255, 255]);
        for (let x = Math.max(0, x0); x < Math.min(PW, x1); x++) for (let h = 0; h < 2; h++) { const i = (yy + h) * PW + x; if (i >= 0 && i < N) { alb.set(col, i * 3); sky[i] = 2; } } } } }

  // 栅格化一个 op（阈值），回调每个像素的颜色
  const ops = sorted(L);
  let shadowDone = false;
  function raster(draw, fn, thr = 128) {
    sc.setTransform(1, 0, 0, 1, 0, 0); sc.clearRect(0, 0, PW, PH);
    sc.setTransform(1 / PS, 0, 0, 1 / PS, 0, 0); draw(sc);
    const d = sc.getImageData(0, 0, PW, PH).data;
    for (let i = 0; i < N; i++) if (d[i * 4 + 3] >= thr) fn(i, d[i * 4], d[i * 4 + 1], d[i * 4 + 2]);
  }
  const put = (o) => (i, r, g, b) => { alb[i * 3] = r; alb[i * 3 + 1] = g; alb[i * 3 + 2] = b; sky[i] = 0; emi[i] = EMISSIVE.has(o.m) ? 1 : 0; gid[i] = o.stand ? (o.g || 0) : 0; if (shadowDone) shad[i] = 0; };
  const thrOf = (o) => (o.t === 'line' ? 70 : 128);
  const lw = (o) => Math.max(PS * 1.05, o.w);
  function drawOp(o) {
    const col = matColor(o.m);
    if (o.t === 'text' && o.size < 24 && /^[0-9]+$/.test(o.s)) { // 小号数字：3×5 点阵
      const F = { 0: '111101101101111', 1: '010110010010111', 2: '111001111100111', 3: '111001111001111', 4: '101101111001001', 5: '111100111001111', 6: '111100111101111', 7: '111001001001001', 8: '111101111101111', 9: '111101111001111' };
      const x0 = Math.round(o.x / PS - (o.s.length * 4 - 1) / 2), y0 = Math.round((o.y + shiftOf(env, o)) / PS - 2);
      [...o.s].forEach((ch, k) => { const f = F[ch]; for (let j = 0; j < 15; j++) if (f[j] === '1') { const i = (y0 + Math.floor(j / 3)) * PW + x0 + k * 4 + (j % 3); alb.set(col, i * 3); emi[i] = 0; } });
      return;
    }
    if (o.t === 'text') {
      raster((cx) => { cx.setTransform(1, 0, 0, 1, 0, 0); cx.font = '12px Pix'; cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillStyle = rgb(col); cx.fillText(o.s, Math.round(o.x / PS), Math.round((o.y + shiftOf(env, o)) / PS) + 1); }, put(o), 150);
      return;
    }
    if (o.face) { const x = Math.round(o.cx / PS), y = Math.round((o.cy + shiftOf(env, o)) / PS); const i = y * PW + x; if (o.m === 'eye') alb.set(col, i * 3); return; }
    if (o.far || o.mid) {
      const yb = o.t === 'box' ? o.y : o.pts[1][1];
      const base = skyAt(Math.min(yb + 120, lk.skyBot));
      const c = o.far ? mix(base, lk.farTint, lk.farMix) : mix(base, lk.midTint, lk.midMix);
      raster((cx) => paint(cx, o, env, rgb(c)), (i) => { alb.set(c, i * 3); sky[i] = 0; });
      return;
    }
    if (o.m === 'birdFly') { raster((cx) => paint(cx, o, env, '#000'), (i) => { alb.set(lk.outline, i * 3); sky[i] = 0; }); return; }
    const topc = rgb(lighten(col, 0.25));
    raster((cx) => { cx.lineWidth = lw(o); if (o.t === 'line') paint(cx, o, env, rgb(col), 0, shiftOf(env, o), lw(o)); else extrude(cx, o, env, topc, rgb(col)); }, put(o), thrOf(o));
    // 砖：4px 一层，8px 一块，错缝
    if (/^brick/.test(o.m) && o.t === 'box') {
      const x0 = Math.round(o.x / PS), y0 = Math.round(o.y / PS), x1 = Math.round((o.x + o.w) / PS), y1 = Math.round((o.y + o.h) / PS);
      const r = mkRnd(o.i + 3);
      for (let y = Math.max(0, y0); y < Math.min(PH, y1); y++) for (let x = Math.max(0, x0); x < Math.min(PW, x1); x++) {
        const i = y * PW + x; if (gid[i] || emi[i]) continue;
        const row = (y - y0) % 4, colx = (x - x0 + (Math.floor((y - y0) / 4) % 2) * 4) % 8;
        if (row === 3 || colx === 0) for (let k = 0; k < 3; k++) alb[i * 3 + k] *= 0.86;
      }
      // 零星的深砖
      for (let k = 0; k < (x1 - x0) * (y1 - y0) / 120; k++) { const bx = x0 + Math.floor(r() * (x1 - x0) / 8) * 8 + (r() < 0.5 ? 4 : 0), by = y0 + Math.floor(r() * (y1 - y0) / 4) * 4;
        const f = r() < 0.5 ? 0.9 : 1.08; for (let y = by; y < by + 3; y++) for (let x = bx + 1; x < bx + 8; x++) { if (x < 0 || y < 0 || x >= PW || y >= PH) continue; const i = y * PW + x; if (gid[i]) continue; for (let q = 0; q < 3; q++) alb[i * 3 + q] = Math.min(255, alb[i * 3 + q] * f); } }
    }
  }
  if (lk.farLights) { /* 远处楼的亮窗在后面画完远景后点 */ }
  const near = [];
  for (const o of ops) { if (o.t === 'light' || o.t === 'sunpatch') continue; if (o.far || o.mid || o.m === 'birdFly') drawOp(o); else near.push(o); }
  if (lk.farLights) { const r = mkRnd(5); for (const o of ops) if (o.far && o.t === 'box' && o.w > 20) for (let y = Math.round(o.y / PS) + 3; y < 760 / PS; y += 5) for (let x = Math.round(o.x / PS) + 2; x < (o.x + o.w) / PS - 2; x += 4) if (r() < 0.16) { const i = y * PW + x; alb.set([255, 206, 140], i * 3); emi[i] = 1; } }

  // 影子遮罩（低分辨率）
  const doShadow = () => {
    const [sx, sy] = env.shadow;
    raster((cx) => { cx.save(); cx.beginPath(); cx.rect(0, 0, 1920, env.G); cx.clip();
      for (const o of near) if (o.cast && o.z > 0.5 && !o.sect) paint(cx, o, env, '#000', sx * Math.min(o.z, 200) * 0.9, sy * o.z + shiftOf(env, o) * 0.2, o.t === 'line' ? Math.max(o.w, PS) : undefined);
      cx.restore();
      for (const o of near) if (o.stand && o.z > 0.5) { const base = o.base + shiftOf(env, o); cx.save(); cx.beginPath(); cx.rect(0, env.G, 1920, 1080); cx.clip();
        cx.transform(1, 0, sx * 1.6, -0.16, -sx * 1.6 * base, base + 0.16 * base); paint(cx, o, env, '#000', 0, 0, o.t === 'line' ? Math.max(o.w, PS) : undefined); cx.restore(); }
    }, (i) => { if (!sky[i]) shad[i] = 1; }, 110);
  };
  for (const o of near) { if (!shadowDone && o.z > 0.5) { doShadow(); shadowDone = true; } drawOp(o); }
  // 远景亮窗以后画的东西盖住了 → emi 只在可见处（drawOp 已覆盖 emi）

  // 选择性描边：站着的东西（人、车、树、杆）外面一圈深色
  const outl = new Uint8Array(N);
  for (let y = 1; y < PH - 1; y++) for (let x = 1; x < PW - 1; x++) { const i = y * PW + x; if (gid[i]) continue;
    const g = gid[i - 1] || gid[i + 1] || gid[i - PW] || gid[i + PW]; if (g) outl[i] = 1; }

  // 打光
  const out = new Float32Array(N * 3);
  const s = env.sun;
  for (let y = 0; y < PH; y++) for (let x = 0; x < PW; x++) {
    const i = y * PW + x;
    let r = alb[i * 3], g = alb[i * 3 + 1], b = alb[i * 3 + 2];
    if (!sky[i] && !emi[i]) {
      const t = y / PH; const L0 = mix(lk.top, lk.bot, t);
      const sd = Math.hypot(x * PS - s.x, y * PS - s.y) / 1400; const sl = mix(lk.sunlit, [255, 255, 255], Math.min(1, sd));
      let lr = L0[0] * sl[0] / 255, lg = L0[1] * sl[1] / 255, lb = L0[2] * sl[2] / 255;
      if (shad[i] && !gid[i]) { lr *= lk.shade[0] / 255 * 0.75 + 0.25; lg *= lk.shade[1] / 255 * 0.75 + 0.25; lb *= lk.shade[2] / 255 * 0.75 + 0.25; }
      r = r * lr / 255; g = g * lg / 255; b = b * lb / 255;
    }
    if (outl[i] && env.time === 'dusk') { r = r * 0.45 + lk.outline[0] * 0.2; g = g * 0.45 + lk.outline[1] * 0.2; b = b * 0.45 + lk.outline[2] * 0.2; }
    else if (outl[i]) { r *= 0.6; g *= 0.6; b *= 0.62; }
    out[i * 3] = r; out[i * 3 + 1] = g; out[i * 3 + 2] = b;
  }
  // 朝太阳那边的亮边（站着的东西）
  const rd = env.time === 'dusk' ? 1 : -1;
  for (let y = 1; y < PH - 1; y++) for (let x = 1; x < PW - 1; x++) { const i = y * PW + x; if (gid[i] && !gid[i + rd]) { out[i * 3] = Math.min(255, out[i * 3] * 1.25 + 30); out[i * 3 + 1] = Math.min(255, out[i * 3 + 1] * 1.15 + 16); out[i * 3 + 2] = out[i * 3 + 2] * 1.0; } }
  // 灯：加法光晕，记下要抖动的地方
  const glowMask = new Float32Array(N);
  const addGlow = (cx, cy, R, col, k) => { for (let y = Math.max(0, Math.floor(cy - R)); y < Math.min(PH, cy + R); y++) for (let x = Math.max(0, Math.floor(cx - R)); x < Math.min(PW, cx + R); x++) {
    const d = Math.hypot(x - cx, y - cy) / R; if (d >= 1) continue; const a = (1 - d) * (1 - d) * k; const i = y * PW + x;
    out[i * 3] += col[0] * a; out[i * 3 + 1] += col[1] * a; out[i * 3 + 2] += col[2] * a; glowMask[i] = Math.max(glowMask[i], a); } };
  for (const o of L) {
    if (o.t === 'light' && o.col !== 'sun' && o.y < env.G) { const col = o.col === 'red' ? [255, 80, 50] : o.col === 'sun' ? [255, 220, 160] : [255, 170, 80];
      addGlow(o.x / PS, (o.y + shiftOf(env, o)) / PS, o.r / PS, col, 0.55 * o.k);
      if (o.cone) { const y0 = (o.y + shiftOf(env, o)) / PS, y1 = (env.G + 70) / PS; for (let y = Math.ceil(y0); y < y1; y++) { const t = (y - y0) / (y1 - y0); const hw = 5 + t * 48; for (let x = Math.round(o.x / PS - hw); x <= o.x / PS + hw; x++) { const i = y * PW + x; const a = 0.22 * (1 - t * 0.7); out[i * 3] += 255 * a; out[i * 3 + 1] += 196 * a; out[i * 3 + 2] += 120 * a; glowMask[i] = Math.max(glowMask[i], a); } } }
    }
    if (o.t === 'sunpatch') { const [a, b, , ] = o.pts, [, , r2, s2] = o.to;
      raster((cx) => { cx.beginPath(); cx.moveTo(...a); cx.lineTo(...b); cx.lineTo(...r2); cx.lineTo(...s2); cx.closePath(); cx.fillStyle = '#fff'; cx.fill(); }, (i) => { const y = Math.floor(i / PW); const t = (y * PS - a[1]) / (s2[1] - a[1]); const k = 0.3 * (1 - t * 0.6); out[i * 3] += 255 * k; out[i * 3 + 1] += 226 * k; out[i * 3 + 2] += 170 * k; glowMask[i] = Math.max(glowMask[i], k); }); }
  }
  for (const o of near) if (o.lit || o.glow) { const [bx, by, bw, bh] = bbox(o); addGlow((bx + bw / 2) / PS, (by + bh / 2 + shiftOf(env, o)) / PS, Math.max(bw, bh) * 0.9 / PS, o.m === 'lantern' ? [255, 80, 50] : [255, 180, 90], env.time === 'dusk' ? 0.3 : 0.12); }

  // 调色板：这张图自己的颜色 k-means 出 40 色
  const K = 40; const r = mkRnd(17); const samp = [];
  for (let k = 0; k < 14000; k++) { const i = Math.floor(r() * N); samp.push([out[i * 3], out[i * 3 + 1], out[i * 3 + 2]].map(v => Math.min(255, v))); }
  let cent = []; for (let k = 0; k < K; k++) cent.push(samp[Math.floor(r() * samp.length)].slice());
  for (let it = 0; it < 12; it++) { const acc = cent.map(() => [0, 0, 0, 0]);
    for (const p of samp) { let bi = 0, bd = 1e9; for (let k = 0; k < K; k++) { const c = cent[k]; const d = (p[0] - c[0]) ** 2 * 0.3 + (p[1] - c[1]) ** 2 * 0.59 + (p[2] - c[2]) ** 2 * 0.11; if (d < bd) { bd = d; bi = k; } } const a = acc[bi]; a[0] += p[0]; a[1] += p[1]; a[2] += p[2]; a[3]++; }
    cent = cent.map((c, k) => acc[k][3] ? [acc[k][0] / acc[k][3], acc[k][1] / acc[k][3], acc[k][2] / acc[k][3]] : samp[Math.floor(r() * samp.length)].slice()); }
  // 调色板稍微提饱和，像素画的颜色要干脆
  cent = cent.map(c => { const m = (c[0] + c[1] + c[2]) / 3; return c.map(v => Math.max(0, Math.min(255, m + (v - m) * 1.18))); });
  const near2 = (p) => { let b1 = 0, d1 = 1e12, b2 = 0, d2 = 1e12; for (let k = 0; k < K; k++) { const c = cent[k]; const d = (p[0] - c[0]) ** 2 * 0.3 + (p[1] - c[1]) ** 2 * 0.59 + (p[2] - c[2]) ** 2 * 0.11; if (d < d1) { d2 = d1; b2 = b1; d1 = d; b1 = k; } else if (d < d2) { d2 = d; b2 = k; } } return [b1, b2, Math.sqrt(d1), Math.sqrt(d2)]; };
  const small = canvas(PW, PH), smc = small.getContext('2d'); const id = smc.createImageData(PW, PH);
  for (let y = 0; y < PH; y++) for (let x = 0; x < PW; x++) { const i = y * PW + x;
    const p = [Math.min(255, out[i * 3]), Math.min(255, out[i * 3 + 1]), Math.min(255, out[i * 3 + 2])];
    const [b1, b2, d1, d2] = near2(p); let k = b1;
    if (sky[i] === 1 || glowMask[i] > 0.07) { const t = d1 / (d1 + d2 + 1e-6); if (BAYER[(y % 4) * 4 + (x % 4)] < t) k = b2; }
    const c = cent[k]; id.data[i * 4] = c[0]; id.data[i * 4 + 1] = c[1]; id.data[i * 4 + 2] = c[2]; id.data[i * 4 + 3] = 255; }
  smc.putImageData(id, 0, 0);
  const big = canvas(), bc = big.getContext('2d'); bc.imageSmoothingEnabled = false; bc.drawImage(small, 0, 0, 1920, 1080);
  return big;
}
