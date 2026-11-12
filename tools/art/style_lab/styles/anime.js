// 风格 D：动画电影背景。高饱和的天、成团的积云、硬边的冷色影子、玻璃反光、光束、辉光和镜头光斑。
const LOOK = {
  dusk: {
    sky: [[0, '#14205E'], [0.3, '#3C4AA6'], [0.56, '#C0609E'], [0.78, '#FF8E6A'], [1, '#FFD890']],
    skyTop: 0, skyBot: 860,
    lightTop: [255, 236, 214], lightBot: [176, 160, 200],
    shade: [96, 92, 196], shadeA: 0.7,
    oppo: [[-100, 560], [700, 480], [1500, 430], [2020, 400]], oppoCol: [150, 132, 196],
    sunlit: [255, 196, 140], rim: '#FFC58A', rimDir: [-3, 2],
    farTint: [92, 78, 150], farMix: 0.38, midTint: [70, 58, 120], midMix: 0.58, farLights: true,
    sun: { r: 70, col: '#FFE7B8' },
  },
  morning: {
    sky: [[0, '#2F7FE0'], [0.5, '#7DBDF2'], [0.85, '#DDF0FA'], [1, '#FFF0D2']],
    skyTop: 0, skyBot: 380,
    lightTop: [255, 250, 240], lightBot: [222, 214, 230],
    shade: [120, 140, 220], shadeA: 0.45,
    oppo: null,
    sunlit: [255, 232, 196], rim: '#FFE2B0', rimDir: [3, 2],
    farTint: [170, 196, 222], farMix: 0.55, midTint: [140, 170, 200], midMix: 0.5, farLights: false,
    sun: { r: 60, col: '#FFF4D6' },
  },
};
const SIGNFONT = (size) => `${size * 1.15}px Smiley`;

async function render(env, L) {
  const lk = LOOK[env.time];
  const W = 1920, H = 1080;
  const out = canvas(), o = out.getContext('2d');
  const ops = sorted(L);
  const skyAt = (y) => { // 天在 y 处的颜色
    const t = Math.max(0, Math.min(1, (y - lk.skyTop) / (lk.skyBot - lk.skyTop)));
    for (let k = 1; k < lk.sky.length; k++) if (t <= lk.sky[k][0]) { const a = lk.sky[k - 1], b = lk.sky[k]; return mix(hex(a[1]), hex(b[1]), (t - a[0]) / (b[0] - a[0])); }
    return hex(lk.sky[lk.sky.length - 1][1]);
  };

  // ---------- 天 ----------
  const g = o.createLinearGradient(0, lk.skyTop, 0, lk.skyBot);
  for (const [t, c] of lk.sky) g.addColorStop(t, c);
  o.fillStyle = g; o.fillRect(0, 0, W, H);
  // 太阳 + 光晕
  { const s = env.sun; const rg = o.createRadialGradient(s.x, s.y, 0, s.x, s.y, 520);
    rg.addColorStop(0, 'rgba(255,230,180,0.55)'); rg.addColorStop(0.3, 'rgba(255,200,150,0.18)'); rg.addColorStop(1, 'rgba(255,200,150,0)');
    o.fillStyle = rg; o.fillRect(0, 0, W, H);
    o.fillStyle = lk.sun.col; o.beginPath(); o.arc(s.x, s.y, lk.sun.r, 0, 7); o.fill(); }
  // 积云：一团团圆堆起来，顶上受光、底下压暗，太阳那边描一道亮边
  { const r = mkRnd(21);
    const dusk = env.time === 'dusk';
    const banks = dusk ? [[260, 150, 460, 0.75], [900, 110, 360, 0.6], [1380, 210, 300, 0.65], [1800, 90, 360, 0.6], [620, 290, 240, 0.45]] : [[240, 120, 360, 1], [1050, 80, 420, 0.9], [1620, 150, 300, 0.8]];
    for (const [cx, cy, w, sc] of banks) {
      const puffs = [];
      for (let k = 0; k < 16; k++) { const t = k / 15; const px = cx - w / 2 + t * w + (r() - 0.5) * 30; const hump = Math.sin(t * Math.PI) * 60 * sc; const pr = (28 + r() * 34 + hump * 0.6) * sc; puffs.push([px, cy - hump * 0.6 + (r() - 0.5) * 16, pr]); }
      const shadeC = dusk ? [96, 74, 150] : [196, 212, 236], litC = dusk ? [236, 128, 150] : [255, 255, 255], rimC = dusk ? [255, 196, 150] : [255, 252, 244];
      const blob = (dx, dy, k) => { o.beginPath(); for (const [x, y, pr] of puffs) { o.moveTo(x + dx + pr * k, y + dy); o.arc(x + dx, y + dy, pr * k, 0, 7); } };
      const vx = env.sun.x - cx, vy = (dusk ? 600 : env.sun.y) - cy, vl = Math.hypot(vx, vy); const dx = vx / vl * 16 * sc, dy = vy / vl * 16 * sc;
      blob(0, 0, 1); o.fillStyle = rgb(rimC); o.fill('nonzero'); o.fillRect(cx - w / 2, cy, w, 14 * sc);
      o.save(); blob(0, 0, 1); o.rect(cx - w / 2, cy, w, 14 * sc); o.clip('nonzero');
      blob(-dx * 0.3, -dy * 0.3, 1); o.fillStyle = rgb(litC); o.fill('nonzero');
      blob(-dx * 1.4, -dy * 1.4, 1); o.fillStyle = rgb(shadeC); o.fill('nonzero');
      o.restore();
    }
    // 高空的卷云
    o.save(); o.globalAlpha = dusk ? 0.45 : 0.6; o.strokeStyle = dusk ? '#FFB0A0' : '#FFFFFF'; o.lineCap = 'round';
    for (let k = 0; k < 14; k++) { const x = r() * W, y = 30 + r() * 120, len = 120 + r() * 220; o.lineWidth = 2 + r() * 4; o.beginPath(); o.moveTo(x, y); o.quadraticCurveTo(x + len / 2, y - 10, x + len, y + 6); o.stroke(); }
    o.restore();
  }
  function rays(kk) { const sx = env.sun.x, sy = env.sun.y; const r = mkRnd(31);
    o.save(); o.globalCompositeOperation = 'lighter';
    for (let k = 0; k < 14; k++) { const a0 = (env.time === 'dusk' ? -Math.PI * 0.62 : Math.PI * 0.05) + (r() - 0.5) * 1.6; const a1 = a0 + 0.02 + r() * 0.05; const R = 2600;
      const gg = o.createRadialGradient(sx, sy, 0, sx, sy, R * 0.6); const col = env.time === 'dusk' ? '255,190,140' : '255,246,220';
      gg.addColorStop(0, `rgba(${col},${(0.10 + r() * 0.1) * kk})`); gg.addColorStop(1, `rgba(${col},0)`);
      o.fillStyle = gg; o.beginPath(); o.moveTo(sx, sy); o.lineTo(sx + Math.cos(a0) * R, sy + Math.sin(a0) * R); o.lineTo(sx + Math.cos(a1) * R, sy + Math.sin(a1) * R); o.closePath(); o.fill(); }
    o.restore(); }
  if (env.time === 'dusk') rays(0.7);
  // 远景、中景：天色里的剪影
  for (const op of ops) if (op.far || op.mid) {
    const y = op.t === 'box' ? op.y : op.pts[1][1];
    const base = skyAt(Math.min(y + 120, lk.skyBot));
    const c = op.far ? mix(base, lk.farTint, lk.farMix) : mix(base, lk.midTint, lk.midMix);
    paint(o, op, env, rgb(c));
  }
  if (lk.farLights) { const r = mkRnd(5);
    for (const op of ops) if (op.far && op.t === 'box' && op.w > 20) for (let yy = op.y + 14; yy < 760; yy += 22) for (let xx = op.x + 10; xx < op.x + op.w - 10; xx += 18) if (r() < 0.16) { o.fillStyle = `rgba(255,${200 + r() * 40},${130 + r() * 40},${0.5 + r() * 0.4})`; o.fillRect(xx, yy, 7, 9); }
  }
  // 飞鸟
  for (const op of ops) if (op.m === 'birdFly') paint(o, op, env, rgb(env.time === 'dusk' ? [60, 44, 80] : [90, 96, 120]));

  // ---------- 主层（本色）----------
  const lay = canvas(), c = lay.getContext('2d');
  const near = ops.filter(op => !op.far && !op.mid && op.m !== 'birdFly' && op.t !== 'light' && op.t !== 'sunpatch');
  const sat = (cc) => { const m = (cc[0] + cc[1] + cc[2]) / 3; return cc.map(v => Math.max(0, Math.min(255, m + (v - m) * 1.22))); };
  const top = (m) => rgb(lighten(sat(matColor(m)), 0.3));
  const side = (m) => rgb(darken(matColor(m), 0.18));
  const tex = (op) => { // 砖墙一点点纹理
    if (!/^brick/.test(op.m) || op.t !== 'box') return;
    c.save(); trace(c, op, env, 0, shiftOf(env, op)); c.clip();
    const r = mkRnd(op.i + 1);
    for (let y = op.y; y < op.y + op.h; y += 16) {
      c.fillStyle = 'rgba(60,20,30,0.07)'; c.fillRect(op.x, y, op.w, 2);
      for (let x = op.x + (((y - op.y) / 16) % 2) * 22; x < op.x + op.w; x += 44) if (r() < 0.12) { c.fillStyle = r() < 0.5 ? 'rgba(255,220,200,0.08)' : 'rgba(60,20,30,0.08)'; c.fillRect(x, y + 2, 42, 14); }
    }
    c.restore();
  };
  const textOp = (cc, op, col) => { cc.save(); cc.font = SIGNFONT(op.size); cc.fillStyle = col; cc.textAlign = 'center'; cc.textBaseline = 'middle'; cc.letterSpacing = (op.size * 0.12) + 'px'; cc.fillText(op.s, op.x, op.y + shiftOf(env, op) + op.size * 0.04); cc.restore(); };
  const drawOp = (cc, op) => {
    if (op.t === 'text') return textOp(cc, op, rgb(matColor(op.m)));
    if (op.face) return paint(cc, op, env, rgb(matColor(op.m)), 0, shiftOf(env, op));
    if (op.m === 'glass' && op.t === 'box') { // 玻璃里反着天，斜一道高光
      const s0 = shiftOf(env, op); const gg = cc.createLinearGradient(0, op.y, 0, op.y + op.h);
      const top0 = skyAt(op.y - 200), bot0 = skyAt(op.y + 120);
      gg.addColorStop(0, rgb(mix(top0, [40, 40, 80], 0.35))); gg.addColorStop(1, rgb(mix(bot0, [40, 40, 80], 0.5)));
      paint(cc, op, env, gg, 0, s0);
      cc.save(); trace(cc, op, env, 0, s0); cc.clip(); cc.fillStyle = 'rgba(255,255,255,0.28)';
      cc.beginPath(); cc.moveTo(op.x + op.w * 0.15, op.y + op.h); cc.lineTo(op.x + op.w * 0.45, op.y); cc.lineTo(op.x + op.w * 0.62, op.y); cc.lineTo(op.x + op.w * 0.32, op.y + op.h); cc.fill();
      cc.fillStyle = 'rgba(255,255,255,0.18)'; cc.beginPath(); cc.moveTo(op.x + op.w * 0.5, op.y + op.h); cc.lineTo(op.x + op.w * 0.72, op.y); cc.lineTo(op.x + op.w * 0.78, op.y); cc.lineTo(op.x + op.w * 0.56, op.y + op.h); cc.fill();
      cc.restore(); return;
    }
    extrude(cc, op, env, top(op.m), rgb(sat(matColor(op.m))));
    tex(op);
    if (op.t === 'box' && op.d > 0 && !op.sect && op.w > 12) { // 顶边亮线、底边暗线
      const s0 = shiftOf(env, op); cc.fillStyle = 'rgba(255,240,220,0.55)'; cc.fillRect(op.x + 1, op.y + s0, op.w - 2, 2);
      cc.fillStyle = 'rgba(30,20,60,0.35)'; cc.fillRect(op.x + 1, op.y + op.h + s0 - 2, op.w - 2, 2); }
    if (op.wall) { // 窗台下的水渍、墙皮
      const r = mkRnd(op.i + 7); cc.save(); trace(cc, op, env, 0, 0); cc.clip();
      for (let k = 0; k < op.w / 40; k++) { const x = op.x + r() * op.w, y = op.y + r() * op.h * 0.8, h = 40 + r() * 120;
        const gg = cc.createLinearGradient(0, y, 0, y + h); gg.addColorStop(0, 'rgba(40,20,40,0.12)'); gg.addColorStop(1, 'rgba(40,20,40,0)'); cc.fillStyle = gg; cc.fillRect(x, y, 4 + r() * 14, h); }
      cc.restore(); }
  };
  const em = canvas(), e = em.getContext('2d');
  const emColor = (op) => { const [bx0, by0, bw0, bh0] = bbox(op); const s0 = shiftOf(env, op);
    const gg = e.createLinearGradient(0, by0 + s0, 0, by0 + s0 + Math.max(bh0, 4));
    gg.addColorStop(0, env.time === 'dusk' ? '#FFE3A6' : '#FFF0C8'); gg.addColorStop(1, env.time === 'dusk' ? '#F5A45A' : '#FFD08A'); return gg; };
  const emOp = (op) => {
    if (op.t === 'text') { if (EMISSIVE.has(op.m)) textOp(e, op, rgb(env.time === 'dusk' ? [255, 240, 214] : [250, 246, 236])); return; }
    if (EMISSIVE.has(op.m)) { e.globalCompositeOperation = 'source-over'; paint(e, op, env, emColor(op), 0, shiftOf(env, op));
      if (op.big) { e.save(); trace(e, op, env, 0, 0); e.clip(); const [bx0, by0, bw0, bh0] = bbox(op); e.fillStyle = 'rgba(200,100,60,0.25)'; e.fillRect(bx0, by0 + bh0 * 0.55, bw0, bh0); e.restore(); } }
    else { e.globalCompositeOperation = 'destination-out'; extrude(e, op, env, '#000', '#000'); e.globalCompositeOperation = 'source-over'; }
  };
  for (const op of near) if (op.z <= 0.5) { drawOp(c, op); emOp(op); }
  // 影子（只落在墙和地上）
  const sm = canvas(), s = sm.getContext('2d');
  const [sx, sy] = env.shadow;
  s.save(); s.beginPath(); s.rect(0, 0, W, env.G); s.clip();
  for (const op of near) if (op.cast && op.z > 0.5 && !op.sect) paint(s, op, env, '#000', sx * Math.min(op.z, 200) * 0.9, sy * op.z + shiftOf(env, op) * 0.2, op.t === 'line' ? op.w + 1 : undefined);
  s.restore();
  // 地上的长影子（站着的东西）
  for (const op of near) if (op.stand && op.z > 0.5) {
    const base = op.base + shiftOf(env, op);
    s.save(); s.beginPath(); s.rect(0, env.G, W, H); s.clip();
    s.setTransform(1, 0, sx * 1.6, -0.16, 0, base + 0.16 * base); // x' = x + 1.6*sx*(y-base)... 近似
    s.translate(-sx * 1.6 * base, 0);
    paint(s, op, env, '#000', 0, 0, op.t === 'line' ? op.w + 1 : undefined);
    s.restore();
  }
  // 楼对面投过来的大影子（傍晚压住一楼）
  if (lk.oppo) { s.beginPath(); s.moveTo(-100, H); for (const p of lk.oppo) s.lineTo(p[0], p[1]); s.lineTo(2020, H); s.closePath(); s.fillStyle = 'rgba(0,0,0,0.75)'; s.fill(); }
  { // 影子上色：正片叠底
    const t = canvas(), tc = t.getContext('2d');
    tc.drawImage(sm, 0, 0); tc.globalCompositeOperation = 'source-in'; tc.fillStyle = rgb(lk.shade); tc.fillRect(0, 0, W, H);
    c.save(); c.globalCompositeOperation = 'multiply'; c.globalAlpha = lk.shadeA; c.drawImage(t, 0, 0); c.restore();
    // multiply 会把透明处也盖上，裁回主层自己的形状
  }
  for (const op of near) if (op.z > 0.5) { drawOp(c, op); emOp(op); }

  // ---------- 打光：上暖下冷 ----------
  { c.save(); c.globalCompositeOperation = 'multiply';
    const lg = c.createLinearGradient(0, 0, 0, H); lg.addColorStop(0, rgb(lk.lightTop)); lg.addColorStop(0.55, rgb(mix(lk.lightTop, lk.lightBot, 0.45))); lg.addColorStop(1, rgb(lk.lightBot));
    c.fillStyle = lg; c.fillRect(0, 0, W, H);
    // 太阳那边更暖
    const sg = c.createRadialGradient(env.sun.x, env.sun.y, 0, env.sun.x, env.sun.y, 1400); sg.addColorStop(0, rgb(lk.sunlit)); sg.addColorStop(1, 'rgb(255,255,255)');
    c.fillStyle = sg; c.fillRect(0, 0, W, H);
    c.restore(); }
  // multiply 会把天的透明处也涂上 → 用主层原来的形状裁一次
  const shape = canvas(), shc = shape.getContext('2d');
  for (const op of near) { if (op.t === 'text') continue; extrude(shc, op, env, '#000', '#000'); }
  c.globalCompositeOperation = 'destination-in'; c.drawImage(shape, 0, 0); c.globalCompositeOperation = 'source-over';

  c.drawImage(em, 0, 0);
  // ---------- 轮廓光（站着的东西朝太阳那边一道亮边）----------
  const groups = groupsOf(near);
  for (const [gid, gops] of groups) {
    if (!gops.some(op => op.stand)) continue;
    const t = canvas(), tc = t.getContext('2d');
    for (const op of gops) if (op.t !== 'text') extrude(tc, op, env, '#fff', '#fff');
    tc.globalCompositeOperation = 'destination-out'; tc.drawImage(t, lk.rimDir[0], lk.rimDir[1]);
    tc.globalCompositeOperation = 'source-in'; tc.fillStyle = lk.rim; tc.fillRect(0, 0, W, H);
    c.globalAlpha = 0.9; c.drawImage(t, 0, 0); c.globalAlpha = 1;
    const u = canvas(), uc = u.getContext('2d');
    for (const op of gops) if (op.t !== 'text') extrude(uc, op, env, '#fff', '#fff');
    uc.globalCompositeOperation = 'destination-out'; uc.drawImage(u, lk.rimDir[0] * 3, -6);
    uc.globalCompositeOperation = 'source-in'; uc.fillStyle = env.time === 'dusk' ? 'rgb(120,100,200)' : 'rgb(170,180,230)'; uc.fillRect(0, 0, W, H);
    c.save(); c.globalCompositeOperation = 'multiply'; c.globalAlpha = 0.55; c.drawImage(u, 0, 0); c.restore();
  }

  o.drawImage(lay, 0, 0);

  // ---------- 光 ----------
  o.save(); o.globalCompositeOperation = 'lighter';
  for (const op of L) {
    if (op.t === 'light') {
      const col = op.col === 'red' ? [255, 90, 60] : op.col === 'sun' ? [255, 220, 160] : [255, 176, 90];
      const y = op.y + shiftOf(env, op);
      const rg = o.createRadialGradient(op.x, y, 0, op.x, y, op.r);
      rg.addColorStop(0, rgb(col, 0.32 * op.k)); rg.addColorStop(0.4, rgb(col, 0.12 * op.k)); rg.addColorStop(1, rgb(col, 0));
      o.fillStyle = rg; o.fillRect(op.x - op.r, y - op.r, op.r * 2, op.r * 2);
      if (op.cone) { // 路灯往下的光锥
        const cg = o.createLinearGradient(0, y, 0, env.G + 80);
        cg.addColorStop(0, 'rgba(255,200,120,0.28)'); cg.addColorStop(1, 'rgba(255,200,120,0.02)');
        o.fillStyle = cg; o.beginPath(); o.moveTo(op.x - 20, y); o.lineTo(op.x + 20, y); o.lineTo(op.x + 190, env.G + 70); o.lineTo(op.x - 190, env.G + 70); o.closePath(); o.fill();
        o.fillStyle = 'rgba(255,200,120,0.18)'; o.beginPath(); o.ellipse(op.x, env.G + 52, 200, 26, 0, 0, 7); o.fill();
      }
    }
    if (op.t === 'sunpatch') {
      const [a, b, cc, d] = op.pts, [p, q, r2, s2] = op.to;
      const gg = o.createLinearGradient(a[0], a[1], r2[0], r2[1]); gg.addColorStop(0, 'rgba(255,226,170,0.32)'); gg.addColorStop(1, 'rgba(255,226,170,0.04)');
      o.fillStyle = gg; o.beginPath(); o.moveTo(...a); o.lineTo(...b); o.lineTo(...r2); o.lineTo(...s2); o.closePath(); o.fill();
      o.fillStyle = 'rgba(255,220,160,0.28)'; o.beginPath(); o.moveTo(...p); o.lineTo(...q); o.lineTo(...r2); o.lineTo(...s2); o.closePath(); o.fill();
      // 光里的灰尘
      const r = mkRnd(9); for (let k = 0; k < 60; k++) { const t = r(), u = r(); const x = a[0] + (b[0] - a[0]) * u + (s2[0] - a[0]) * t, y = a[1] + (s2[1] - a[1]) * t; o.fillStyle = `rgba(255,240,210,${0.2 + r() * 0.4})`; o.beginPath(); o.arc(x, y, 1 + r() * 1.6, 0, 7); o.fill(); }
    }
  }
  // 亮窗、灯泡、灯笼的光晕
  for (const op of near) if (op.lit || op.glow) {
    const bx = op.t === 'box' ? op.x + op.w / 2 : op.cx, by = (op.t === 'box' ? op.y + op.h / 2 : op.cy) + shiftOf(env, op);
    const R = op.t === 'box' ? Math.max(op.w, op.h) * 0.9 : op.rx * 3;
    const col = op.m === 'lantern' ? [255, 80, 50] : [255, 180, 90];
    const rg = o.createRadialGradient(bx, by, 0, bx, by, R); rg.addColorStop(0, rgb(col, env.time === 'dusk' ? 0.26 : 0.1)); rg.addColorStop(1, rgb(col, 0));
    o.fillStyle = rg; o.fillRect(bx - R, by - R, R * 2, R * 2);
  }
  o.restore();

  if (env.time !== 'dusk') rays(0.55);
  // ---------- 辉光：亮处模糊了再加回去 ----------
  { const sm = canvas(480, 270), sc = sm.getContext('2d'); sc.filter = 'brightness(0.75) contrast(3.2) saturate(1.4)'; sc.drawImage(out, 0, 0, 480, 270);
    const sm2 = canvas(480, 270), s2 = sm2.getContext('2d'); s2.filter = 'blur(6px)'; s2.drawImage(sm, 0, 0);
    o.save(); o.globalCompositeOperation = 'screen'; o.globalAlpha = env.time === 'dusk' ? 0.55 : 0.4; o.drawImage(sm2, 0, 0, W, H); o.restore(); }
  // ---------- 镜头光斑：太阳和画面中心连线上几个淡色的圈 ----------
  { const sx = env.sun.x, sy = env.sun.y, cx = W / 2, cy = H / 2;
    o.save(); o.globalCompositeOperation = 'lighter';
    for (const [t, R, a, col] of [[0.35, 40, 0.10, '255,200,150'], [0.62, 70, 0.035, '160,200,255'], [0.9, 26, 0.12, '255,160,200'], [1.25, 110, 0.025, '200,255,220'], [1.5, 50, 0.08, '255,220,160']]) {
      const x = sx + (cx - sx) * t, y = sy + (cy - sy) * t; const gg = o.createRadialGradient(x, y, R * 0.6, x, y, R);
      gg.addColorStop(0, `rgba(${col},${a})`); gg.addColorStop(0.85, `rgba(${col},${a * 1.4})`); gg.addColorStop(1, `rgba(${col},0)`); o.fillStyle = gg; o.beginPath(); o.arc(x, y, R, 0, 7); o.fill(); }
    // 太阳那个角的漏光
    const lg = o.createRadialGradient(env.sun.x, env.sun.y, 0, env.sun.x, env.sun.y, 900); lg.addColorStop(0, env.time === 'dusk' ? 'rgba(255,150,90,0.22)' : 'rgba(255,240,200,0.25)'); lg.addColorStop(1, 'rgba(255,150,90,0)');
    o.fillStyle = lg; o.fillRect(0, 0, W, H);
    // 浮尘 / 光点
    const r = mkRnd(77); for (let k = 0; k < 90; k++) { const x = r() * W, y = r() * H * 0.9, rr = 1 + r() * 3; o.fillStyle = `rgba(255,236,200,${0.15 + r() * 0.35})`; o.beginPath(); o.arc(x, y, rr, 0, 7); o.fill(); }
    o.restore(); }
  // ---------- 调色 + 暗角 ----------
  { const t = canvas(), tc = t.getContext('2d'); tc.filter = 'saturate(1.12) contrast(1.06)'; tc.drawImage(out, 0, 0); o.clearRect(0, 0, W, H); o.drawImage(t, 0, 0);
    const vg = o.createRadialGradient(W / 2, H * 0.45, H * 0.45, W / 2, H * 0.5, H * 1.05);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, env.time === 'dusk' ? 'rgba(20,10,60,0.45)' : 'rgba(30,50,110,0.22)'); o.fillStyle = vg; o.fillRect(0, 0, W, H); }
  grain(o, 4);
  return out;
}
