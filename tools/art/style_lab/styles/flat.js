// 风格 A：暖光平涂。没有描线，靠色块、冷暖和长影子立体；细颗粒，不要网点。
const LOOK = {
  dusk: {
    sky: [[0, '#26305E'], [0.32, '#5C4F8E'], [0.58, '#C9708A'], [0.8, '#F4A07C'], [1, '#FFD39A']],
    skyTop: 0, skyBot: 860,
    lightTop: [255, 236, 214], lightBot: [176, 160, 200],
    shade: [128, 112, 176], shadeA: 0.62,
    oppo: [[-100, 560], [700, 480], [1500, 430], [2020, 400]], oppoCol: [150, 132, 196],
    sunlit: [255, 196, 140], rim: '#FFC58A', rimDir: [-3, 2],
    farTint: [92, 78, 150], farMix: 0.38, midTint: [70, 58, 120], midMix: 0.58, farLights: true,
    sun: { r: 70, col: '#FFE7B8' },
  },
  morning: {
    sky: [[0, '#8EC3E6'], [0.55, '#CFE3EC'], [0.85, '#F8E2C8'], [1, '#FFD9AE']],
    skyTop: 0, skyBot: 380,
    lightTop: [255, 250, 240], lightBot: [222, 214, 230],
    shade: [150, 150, 196], shadeA: 0.4,
    oppo: null,
    sunlit: [255, 232, 196], rim: '#FFE2B0', rimDir: [3, 2],
    farTint: [170, 196, 222], farMix: 0.55, midTint: [140, 170, 200], midMix: 0.5, farLights: false,
    sun: { r: 60, col: '#FFF4D6' },
  },
};
const SIGNFONT = (size) => `900 ${size}px "Noto Sans SC"`;

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
  // 云：细长的，底下被照亮
  { const r = mkRnd(11); o.save(); o.filter = 'blur(3px)';
    const clouds = env.time === 'dusk' ? [[180, 120, 300], [520, 200, 220], [1020, 90, 360], [1260, 230, 260], [1700, 150, 240], [80, 260, 180]] : [[200, 90, 260], [760, 60, 300], [1300, 110, 240], [1650, 70, 200]];
    for (const [cx, cy, w] of clouds) {
      const top = env.time === 'dusk' ? [214, 130, 160] : [255, 255, 255];
      const bot = env.time === 'dusk' ? [255, 196, 150] : [236, 236, 246];
      for (let k = 0; k < 5; k++) {
        const x = cx + (r() - 0.5) * w * 0.6, y = cy + (r() - 0.5) * 14, rx = w * (0.25 + r() * 0.3), ry = 9 + r() * 10;
        o.fillStyle = rgb(top, 0.75); o.beginPath(); o.ellipse(x, y, rx, ry, 0, 0, 7); o.fill();
        o.fillStyle = rgb(bot, 0.8); o.beginPath(); o.ellipse(x + 6, y + ry * 0.55, rx * 0.85, ry * 0.45, 0, 0, 7); o.fill();
      }
    }
    o.restore(); }
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
  const top = (m) => rgb(lighten(matColor(m), 0.22));
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
    extrude(cc, op, env, top(op.m), rgb(matColor(op.m)));
    tex(op);
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
  if (lk.oppo) { s.beginPath(); s.moveTo(-100, H); for (const p of lk.oppo) s.lineTo(p[0], p[1]); s.lineTo(2020, H); s.closePath(); s.fillStyle = 'rgba(0,0,0,0.55)'; s.filter = 'blur(10px)'; s.fill(); s.filter = 'none'; }
  { // 影子上色：正片叠底
    const t = canvas(), tc = t.getContext('2d');
    tc.drawImage(sm, 0, 0); tc.globalCompositeOperation = 'source-in'; tc.fillStyle = rgb(lk.shade); tc.fillRect(0, 0, W, H);
    c.save(); c.globalCompositeOperation = 'multiply'; c.globalAlpha = lk.shadeA; c.filter = 'blur(1.5px)'; c.drawImage(t, 0, 0); c.restore();
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
    c.globalAlpha = 0.8; c.drawImage(t, 0, 0); c.globalAlpha = 1;
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

  // ---------- 前景（虚）----------
  // 前景已在主层里；再整体压暗、略虚
  // ---------- 收尾：暗角 + 颗粒 ----------
  { const vg = o.createRadialGradient(W / 2, H * 0.45, H * 0.4, W / 2, H * 0.5, H * 1.05);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, env.time === 'dusk' ? 'rgba(30,16,50,0.42)' : 'rgba(40,40,70,0.22)');
    o.fillStyle = vg; o.fillRect(0, 0, W, H); }
  grain(o, 9);
  return out;
}
