// 同一份场景描述（显示列表），四种画风各自去画。
// 坐标：1920×1080，y 向下；z 是离后墙的距离（正 = 往镜头这边凸出），d 是厚度。
// 地面线 G：z>0 的东西在 2D 里按 K 往下挪一点（俯视一点点），3D 里按真深度摆。

function buildScene(name) {
  const L = [];
  let seq = 0, grp = 0;
  const op = (t, o) => { o.t = t; o.z = o.z || 0; if (o.z < 0 && o.z >= -3) o.z = 0.1 + (o.z + 3) / 3 * 0.35; o.d = o.d || 0; o.i = seq++; L.push(o); return o; };
  const box = (x, y, w, h, m, o = {}) => op('box', { x, y, w, h, m, ...o });
  const poly = (pts, m, o = {}) => op('poly', { pts, m, ...o });
  const ell = (cx, cy, rx, ry, m, o = {}) => op('ell', { cx, cy, rx, ry, m, ...o });
  const line = (pts, m, w, o = {}) => op('line', { pts, m, w, ...o });
  const text = (s, x, y, size, m, o = {}) => op('text', { s, x, y, size, m, ...o });
  const light = (x, y, r, col, k, o = {}) => op('light', { x, y, r, col, k, ...o });
  const floor = (x, w, z0, z1, m, y, o = {}) => op('floor', { x, w, z0, z1, m, y, ...o, z: -0.5 });
  const G = () => ++grp;
  // 一点点随机，但固定种子
  let s = 7;
  const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647;

  // ---------- 零件 ----------
  function windowAt(x, y, w, h, o = {}) {
    const g = G();
    box(x - 6, y - 6, w + 12, h + 12, 'recess', { z: -1, g });
    box(x, y, w, h, o.lit ? 'glassLit' : 'glass', { z: -0.8, g, lit: o.lit });
    if (o.curtain) {
      box(x + 4, y + 4, w * 0.32, h - 8, o.curtain, { z: -0.7, g, soft: 1 });
      if (o.curtain2) box(x + w - 4 - w * 0.26, y + 4, w * 0.26, h - 8, o.curtain2, { z: -0.7, g, soft: 1 });
    }
    const fm = o.frame || 'frame';
    box(x - 2, y - 2, w + 4, 7, fm, { z: -0.5, g });
    box(x - 2, y + h - 5, w + 4, 7, fm, { z: -0.5, g });
    box(x - 2, y, 7, h, fm, { z: -0.5, g });
    box(x + w - 5, y, 7, h, fm, { z: -0.5, g });
    box(x + w / 2 - 3, y, 6, h, fm, { z: -0.5, g });
    box(x, y + h * 0.36, w, 5, fm, { z: -0.5, g });
    box(x - 12, y + h + 5, w + 24, 10, 'trim', { z: 12, d: 12, g, cast: 1 });
    box(x - 8, y - 18, w + 16, 12, 'trim', { z: 6, d: 6, g, cast: 1 });
  }
  function ac(x, y) {
    const g = G();
    box(x, y, 92, 62, 'acBox', { z: 34, d: 34, g, cast: 1, r: 4 });
    for (let i = 0; i < 6; i++) box(x + 10, y + 10 + i * 8, 46, 3, 'acGrill', { z: 34.2, g });
    ell(x + 72, y + 31, 14, 14, 'acGrill', { z: 34.2, g });
    box(x + 8, y + 62, 6, 10, 'metal', { z: 20, g });
    box(x + 78, y + 62, 6, 10, 'metal', { z: 20, g });
  }
  function laundryPole(x0, x1, y, items) {
    const g = G();
    line([[x0, y], [x1, y + 4]], 'metal', 4, { z: 70, g, cast: 1 });
    let x = x0 + 14;
    for (const it of items) {
      const [w, h, m] = it;
      box(x, y + 4, w, h, m, { z: 66, g, cast: 1, soft: 1, sway: 1 });
      line([[x + 4, y], [x + 4, y + 8]], 'pin', 2, { z: 70, g });
      x += w + 8;
    }
  }
  function plant(x, y, sc = 1, m = 'plant') {
    const g = G();
    box(x - 14 * sc, y - 22 * sc, 28 * sc, 22 * sc, 'pot', { z: 18, d: 20, g, cast: 1, r: 3 });
    for (let k = 0; k < 5; k++) {
      const a = -Math.PI / 2 + (k - 2) * 0.45;
      ell(x + Math.cos(a) * 16 * sc, y - 30 * sc + Math.sin(a) * 14 * sc, 12 * sc, 9 * sc, m, { z: 18, g, cast: 1 });
    }
  }
  function bike(x, y, z, m = 'bikeFrame', o = {}) {
    const g = G(); const st = { z, g, cast: 1, stand: 1, base: y };
    const r = 34;
    ell(x, y - r, r, r, 'tire', { ...st, ring: 5 });
    ell(x + 112, y - r, r, r, 'tire', { ...st, ring: 5 });
    line([[x, y - r], [x + 40, y - r - 2], [x + 76, y - r - 46], [x + 30, y - r - 46], [x, y - r]], m, 5, st);
    line([[x + 40, y - r - 2], [x + 26, y - r - 58]], m, 5, st);
    line([[x + 76, y - r - 46], [x + 112, y - r]], m, 5, st);
    line([[x + 76, y - r - 46], [x + 84, y - r - 70], [x + 70, y - r - 76]], m, 4, st);
    box(x + 12, y - r - 64, 30, 8, 'seat', { ...st, r: 4 });
    if (o.basket) box(x + 92, y - r - 66, 34, 24, 'basket', { ...st, r: 3 });
    if (o.rack) box(x - 18, y - r - 26, 44, 6, 'metal', st);
  }
  function kid(x, y, z, who, o = {}) {
    const g = G(); const st = { z, g, cast: 1, stand: 1, base: y, kid: who };
    const S = o.scale || 1;
    const P = (dx, dy) => [x + dx * S, y + dy * S];
    const coat = who === 'qing' ? 'qing' : 'mei';
    const coat2 = who === 'qing' ? 'qingDark' : 'meiDark';
    const step = o.step || 0;
    // 后腿、后臂
    poly([P(-6 - step, -54), P(4 - step, -54), P(2 - step * 1.4, -4), P(-8 - step * 1.4, -4)], 'pants', { ...st });
    box(...P(-14 - step * 1.4, -8), 18 * S, 8 * S, 'shoe', { ...st, r: 3 });
    poly([P(-2, -100), P(8, -100), P(-6 + step * 0.8, -62), P(-14 + step * 0.8, -64)], coat2, { ...st });
    // 前腿
    poly([P(-4 + step, -54), P(6 + step, -54), P(10 + step * 1.4, -4), P(0 + step * 1.4, -4)], 'pants2', { ...st });
    box(...P(-1 + step * 1.4, -8), 19 * S, 8 * S, 'shoe', { ...st, r: 3 });
    // 书包
    if (o.bag) box(...P(-24, -100), 16 * S, 34 * S, o.bag, { ...st, r: 5 });
    // 身子
    poly([P(-14, -104), P(14, -104), P(16, -50), P(-16, -50)], coat, { ...st, r: 6 });
    if (who === 'mei') poly([P(-16, -58), P(16, -58), P(20, -44), P(-20, -44)], coat, { ...st });
    box(...P(-14, -106), 28 * S, 6 * S, 'collar', { ...st, r: 2 });
    // 头
    ell(...P(2, -124), 18 * S, 19 * S, 'skin', { ...st });
    if (who === 'qing') {
      poly([P(-18, -122), P(-16, -140), P(-4, -146), P(14, -145), P(21, -133), P(16, -128), P(4, -134), P(-6, -128), P(-10, -114), P(-17, -112)], 'hair', { ...st });
    } else {
      poly([P(-18, -118), P(-16, -140), P(-4, -146), P(14, -145), P(21, -132), P(18, -126), P(6, -133), P(-6, -126), P(-10, -100), P(-20, -102)], 'hair', { ...st });
      ell(...P(-20, -110), 6 * S, 9 * S, 'hair', { ...st });
      box(...P(-24, -118), 6 * S, 6 * S, 'mei', { ...st, r: 2 });
    }
    ell(...P(12, -124), 2.2 * S, 2.8 * S, 'eye', { ...st, face: 1 });
    ell(...P(13, -115), 3 * S, 1.6 * S, 'cheek', { ...st, face: 1 });
    // 前臂
    poly([P(-4, -100), P(6, -100), P(12 - step * 0.8, -64), P(2 - step * 0.8, -62)], coat, { ...st });
    ell(...P(7 - step * 0.8, -60), 5 * S, 5 * S, 'skin', { ...st });
  }

  // =====================================================================
  if (name === 'street') {
    const Gy = 860;
    const env = { scene: 'street', time: 'dusk', G: Gy, K: 0.4, sun: { x: 1560, y: 300 }, shadow: [-0.9, 0.12] };

    // 远景：新楼（z 很负）
    const far = [[-80, 260, 150], [90, 300, 120], [230, 180, 140], [400, 330, 110], [540, 230, 160], [740, 150, 120], [890, 280, 130],
      [1050, 210, 170], [1250, 320, 120], [1390, 170, 150], [1570, 260, 120], [1720, 200, 160], [1900, 290, 120]];
    for (const [x, top, w] of far) {
      const g = G();
      box(x, top, w, 760 - top + 100, 'far', { z: -900, g, far: 1 });
      if (top < 240) box(x + w * 0.4, top - 40, 6, 40, 'far', { z: -900, g, far: 1 });
    }
    const mid = [[-40, 470, 260, 'tri'], [240, 430, 200], [450, 500, 220, 'tri'], [700, 450, 180], [900, 490, 240, 'tri'], [1160, 420, 200], [1380, 480, 220, 'tri'], [1620, 440, 200], [1820, 470, 200, 'tri']];
    for (const [x, top, w, k] of mid) {
      const g = G();
      box(x, top, w, Gy - top, 'mid', { z: -400, g, mid: 1 });
      if (k === 'tri') poly([[x - 10, top], [x + w / 2, top - 60], [x + w + 10, top]], 'mid', { z: -400, g, mid: 1 });
      else box(x + 20, top - 30, 40, 30, 'mid', { z: -400, g, mid: 1 });
    }

    // ---------- 楼 A：小卖部 ----------
    {
      const x0 = -60, x1 = 560, top = 340;
      box(x0, top, x1 - x0, Gy - top, 'brick', { z: 0, wall: 1 });
      box(x0 - 8, top - 10, x1 - x0 + 16, 22, 'trim', { z: 14, d: 14, cast: 1 });
      box(x0, Gy - 210, x1 - x0, 14, 'trim', { z: 10, d: 10, cast: 1 });
      for (let f = 0; f < 2; f++) {
        const y = top + 50 + f * 150;
        windowAt(40, y, 120, 92, { lit: f === 1, curtain: 'curtainA' });
        windowAt(300, y, 120, 92, { lit: f === 0, curtain: f ? null : 'curtainB', curtain2: f ? null : 'curtainB' });
      }
      ac(186, top + 168);
      laundryPole(424, 560, top + 46, [[30, 46, 'cloth1'], [22, 34, 'cloth2'], [36, 50, 'cloth3']]);
      // 屋顶
      plant(30, top - 10, 1); plant(80, top - 10, 0.8, 'plant2'); plant(460, top - 10, 1.1);
      { const g = G(); box(180, top - 110, 120, 100, 'tank', { z: -20, d: 60, g, cast: 1, r: 6 }); box(196, top - 10, 10, 10, 'metal', { z: -20, g }); box(274, top - 10, 10, 10, 'metal', { z: -20, g }); }
      line([[340, top - 10], [340, top - 130]], 'metal', 4, { z: -10, cast: 1 });
      line([[310, top - 120], [370, top - 120]], 'metal', 3, { z: -10, cast: 1 });
      line([[318, top - 100], [362, top - 100]], 'metal', 3, { z: -10, cast: 1 });
      // 小卖部门脸
      box(20, Gy - 180, 420, 180, 'shopDark', { z: -2 });
      box(30, Gy - 170, 190, 120, 'glassLit', { z: -1.5, lit: 1 });
      for (let k = 0; k < 5; k++) for (let j = 0; j < 3; j++) box(40 + k * 36, Gy - 160 + j * 38, 26, 24, ['goods1', 'goods2', 'goods3'][(k + j) % 3], { z: -1.2, r: 3 });
      box(250, Gy - 170, 170, 170, 'door', { z: -1.5 });
      box(20, Gy - 50, 210, 50, 'counter', { z: 8, d: 30, cast: 1 });
      // 雨棚（条纹）
      for (let k = 0; k < 9; k++) poly([[10 + k * 48, Gy - 214], [58 + k * 48, Gy - 214], [62 + k * 50, Gy - 176], [12 + k * 50, Gy - 176]], k % 2 ? 'awning2' : 'awning', { z: 60, d: 60, cast: 1, awn: 1 });
      box(10, Gy - 178, 452, 10, 'awningEdge', { z: 62, cast: 1 });
      box(70, Gy - 270, 270, 46, 'signRed', { z: 10, d: 8, cast: 1, r: 4 });
      text('小卖部', 205, Gy - 247, 32, 'signText', { z: 10.2 });
      // 冰柜 + 汽水箱
      box(250, Gy - 76, 110, 76, 'fridge', { z: 50, d: 40, cast: 1, r: 6 });
      box(258, Gy - 70, 94, 30, 'glassLit', { z: 50.2, lit: 1, r: 4 });
      box(372, Gy - 40, 56, 40, 'crate', { z: 70, d: 30, cast: 1 });
      box(380, Gy - 70, 46, 30, 'crate2', { z: 70, d: 30, cast: 1 });
    }

    // ---------- 楼门口 河畔里 ----------
    {
      box(560, 420, 90, Gy - 420, 'alley', { z: -60 });
      box(574, 520, 60, Gy - 520, 'alley2', { z: -120 });
      light(604, 600, 80, 'warm', 0.5, { z: -100 });
      box(552, 400, 106, 24, 'trim', { z: 16, d: 16, cast: 1 });
      box(552, 424, 12, Gy - 424, 'trim', { z: 10, d: 10, cast: 1 });
      box(646, 424, 12, Gy - 424, 'trim', { z: 10, d: 10, cast: 1 });
      box(578, 440, 52, 150, 'signWhite', { z: 14, d: 4, cast: 1, r: 3 });
      text('河', 604, 474, 34, 'signInk', { z: 14.2 });
      text('畔', 604, 515, 34, 'signInk', { z: 14.2 });
      text('里', 604, 556, 34, 'signInk', { z: 14.2 });
    }

    // ---------- 楼 B：自行车铺，四层抹灰楼 ----------
    {
      const x0 = 650, x1 = 1190, top = 190;
      box(x0, top, x1 - x0, Gy - top, 'plaster', { z: 0, wall: 1 });
      box(x0, Gy - 230, x1 - x0, 230, 'brick2', { z: 0, wall: 1 });
      box(x0 - 10, top - 12, x1 - x0 + 20, 24, 'trim', { z: 16, d: 16, cast: 1 });
      for (let f = 0; f < 3; f++) {
        const y = top + 52 + f * 150;
        windowAt(700, y, 110, 90, { lit: f !== 1, curtain: f === 2 ? 'curtainC' : null, frame: 'frame2' });
        if (f === 1) {
          // 封阳台
          const g = G();
          box(880, y - 26, 240, 132, 'balcony', { z: 46, d: 46, g, cast: 1 });
          box(888, y - 18, 224, 74, 'glassLit', { z: 46.3, g, lit: 1 });
          for (let k = 0; k < 4; k++) box(888 + k * 56, y - 18, 5, 74, 'frame2', { z: 46.5, g });
          box(880, y + 62, 240, 44, 'balconyLow', { z: 46.4, g });
          plant(920, y - 26, 0.7); plant(1080, y - 26, 0.8, 'plant2');
        } else windowAt(950, y, 110, 90, { lit: f === 0, curtain: 'curtainA', frame: 'frame2' });
      }
      ac(1080, top + 220);
      ac(1060, top + 70);
      // 屋顶天线、鸽子
      line([[760, top - 12], [760, top - 150]], 'metal', 4, { z: -10, cast: 1 });
      for (let k = 0; k < 4; k++) line([[730 + k * 4, top - 140 + k * 26], [790 - k * 4, top - 140 + k * 26]], 'metal', 3, { z: -10, cast: 1 });
      // 门脸
      box(670, Gy - 200, 500, 200, 'shopDark', { z: -2 });
      for (let k = 0; k < 6; k++) box(688 + k * 34, Gy - 196, 30, 196, 'shutter', { z: -1.6 });
      box(900, Gy - 186, 260, 186, 'shopIn', { z: -1.8 });
      light(1030, Gy - 150, 160, 'warm', 0.7, { z: -1 });
      // 墙上挂的车胎、工具板
      for (let k = 0; k < 3; k++) ell(940 + k * 74, Gy - 146, 30, 30, 'tire', { z: -1.2, ring: 6 });
      box(1100, Gy - 176, 52, 80, 'pegboard', { z: -1.2 });
      for (let k = 0; k < 4; k++) box(1108 + (k % 2) * 22, Gy - 168 + Math.floor(k / 2) * 34, 14, 26, 'metal', { z: -1.1 });
      box(680, Gy - 266, 210, 52, 'signDark', { z: 12, d: 8, cast: 1, r: 4 });
      text('修 车', 785, Gy - 240, 34, 'signText', { z: 12.2 });
      // 打气筒、工具箱、小板凳
      box(930, Gy - 40, 70, 40, 'toolbox', { z: 46, d: 30, cast: 1, r: 3 });
      line([[1020, Gy], [1020, Gy - 70]], 'metal', 5, { z: 60, cast: 1, stand: 1, base: Gy });
      line([[1008, Gy - 70], [1032, Gy - 70]], 'metal', 5, { z: 60, cast: 1, stand: 1, base: Gy });
      box(1060, Gy - 30, 40, 8, 'wood', { z: 64, d: 30, cast: 1, stand: 1, base: Gy });
      line([[1064, Gy - 22], [1064, Gy]], 'wood', 4, { z: 64 }); line([[1096, Gy - 22], [1096, Gy]], 'wood', 4, { z: 64 });
      bike(706, Gy, 40, 'bikeFrame2', { rack: 1 });
    }

    // ---------- 楼 C：河畔茶社 ----------
    {
      const x0 = 1210, x1 = 2000, top = 330;
      box(x0, top, x1 - x0, Gy - top, 'brick3', { z: 0, wall: 1 });
      box(x0 - 8, top - 10, x1 - x0 + 16, 22, 'trim', { z: 14, d: 14, cast: 1 });
      // 墙上的白线
      box(x0, top + 126, x1 - x0, 8, 'trim', { z: 4, d: 4, cast: 1 });
      for (let k = 0; k < 4; k++) windowAt(1250 + k * 180, top + 34 + (k % 2 ? 0 : 0), 104, 80, { lit: k === 1 || k === 3, curtain: k === 1 ? 'curtainB' : (k === 2 ? 'curtainA' : null) });
      for (let k = 0; k < 4; k++) if (k !== 2) windowAt(1250 + k * 180, top + 184, 104, 80, { lit: k === 0, curtain: k === 3 ? 'curtainC' : null });
      laundryPole(1560, 1710, top + 170, [[28, 40, 'cloth3'], [40, 54, 'cloth2']]);
      // 鸽子笼
      { const g = G(); box(1480, top - 96, 170, 86, 'coop', { z: -10, d: 50, g, cast: 1 }); poly([[1470, top - 96], [1565, top - 130], [1660, top - 96]], 'coopRoof', { z: -10, g, cast: 1 }); for (let k = 0; k < 6; k++) box(1490 + k * 27, top - 84, 3, 70, 'metal', { z: -9.8, g }); }
      plant(1290, top - 10, 0.9, 'plant2'); plant(1330, top - 10, 0.7); plant(1900, top - 10, 1.0);
      // 茶社门脸
      box(1230, Gy - 230, 740, 230, 'shopDark', { z: -2 });
      box(1250, Gy - 210, 440, 150, 'glassLit', { z: -1.5, lit: 1, big: 1 });
      for (let k = 0; k < 4; k++) box(1250 + k * 110, Gy - 210, 6, 150, 'frameWood', { z: -1.2 });
      box(1250, Gy - 64, 440, 64, 'woodPanel', { z: -1.3 });
      // 窗里的人影（剪影）
      { const g = G(); ell(1340, Gy - 120, 15, 16, 'silhouette', { z: -1.4, g }); poly([[1318, Gy - 102], [1362, Gy - 102], [1370, Gy - 60], [1310, Gy - 60]], 'silhouette', { z: -1.4, g }); }
      { const g = G(); ell(1540, Gy - 126, 15, 16, 'silhouette', { z: -1.4, g }); poly([[1516, Gy - 108], [1564, Gy - 108], [1574, Gy - 60], [1506, Gy - 60]], 'silhouette', { z: -1.4, g }); }
      box(1720, Gy - 210, 120, 210, 'doorRed', { z: -1.5 });
      box(1734, Gy - 196, 92, 110, 'glassLit', { z: -1.3, lit: 1 });
      light(1460, Gy - 140, 260, 'warm', 0.9, { z: 0 });
      box(1300, Gy - 300, 440, 66, 'signRed', { z: 14, d: 10, cast: 1, r: 4 });
      text('河畔茶社', 1520, Gy - 266, 44, 'signText', { z: 14.2 });
      // 红灯笼
      for (const lx of [1250, 1790]) {
        const g = G();
        line([[lx, Gy - 300], [lx, Gy - 270]], 'metal', 2, { z: 40, g });
        ell(lx, Gy - 238, 30, 34, 'lantern', { z: 40, d: 30, g, cast: 1, glow: 1 });
        box(lx - 14, Gy - 276, 28, 8, 'lanternCap', { z: 40.2, g });
        box(lx - 14, Gy - 206, 28, 8, 'lanternCap', { z: 40.2, g });
        light(lx, Gy - 238, 120, 'red', 0.7, { z: 42 });
      }
      // 门口的小桌小凳
      { const g = G(); const st = { z: 110, g, cast: 1, stand: 1, base: Gy };
        box(1820, Gy - 64, 110, 10, 'wood', { ...st, d: 60 });
        line([[1830, Gy - 54], [1830, Gy]], 'wood', 5, st); line([[1920, Gy - 54], [1920, Gy]], 'wood', 5, st);
        box(1850, Gy - 82, 18, 18, 'cup', { ...st, r: 3 });
        box(1884, Gy - 80, 14, 16, 'cup', { ...st, r: 3 });
        box(1780, Gy - 34, 34, 7, 'wood', st); line([[1784, Gy - 28], [1784, Gy]], 'wood', 4, st); line([[1810, Gy - 28], [1810, Gy]], 'wood', 4, st);
      }
      bike(1590, Gy, 70, 'bikeFrame', { basket: 1 });
    }
    // 楼 B、C 之间的落水管
    box(1192, 200, 16, Gy - 200, 'pipe', { z: 6, d: 8, cast: 1 });

    // ---------- 地面 ----------
    floor(-100, 2120, 0, 130, 'sidewalk', Gy);
    floor(-100, 2120, 130, 150, 'curb', Gy);
    floor(-100, 2120, 150, 1000, 'road', Gy);
    for (let k = 0; k < 9; k++) floor(-60 + k * 260, 140, 520, 540, 'roadLine', Gy);
    // 井盖
    op('floorEll', { cx: 560, z0: 60, rx: 34, m: 'manhole', y: Gy, z: -0.4 });

    // ---------- 街上的东西 ----------
    // 电线杆
    {
      const g = G(); const st = { z: 120, g, cast: 1, stand: 1, base: Gy };
      box(860, 120, 18, Gy - 120, 'pole', { ...st, r: 2 });
      box(800, 170, 140, 12, 'pole', { ...st });
      box(820, 220, 100, 10, 'pole', { ...st });
      for (const ix of [810, 850, 890, 928]) box(ix - 4, 160, 8, 12, 'insulator', { ...st, r: 2 });
      box(876, 300, 46, 70, 'xfmr', { ...st, r: 6 });
      box(842, 520, 54, 44, 'notice', { ...st });
      box(846, 590, 48, 28, 'notice2', { ...st });
    }
    // 电线（悬链）
    const sag = (x0, y0, x1, y1, h) => { const pts = []; for (let k = 0; k <= 24; k++) { const t = k / 24; pts.push([x0 + (x1 - x0) * t, y0 + (y1 - y0) * t + h * 4 * t * (1 - t)]); } return pts; };
    line(sag(-100, 140, 810, 166, 60), 'wire', 2.5, { z: 120, cast: 1 });
    line(sag(-100, 190, 850, 166, 50), 'wire', 2.5, { z: 120, cast: 1 });
    line(sag(890, 166, 2020, 120, 80), 'wire', 2.5, { z: 120, cast: 1 });
    line(sag(928, 166, 2020, 210, 60), 'wire', 2.5, { z: 120, cast: 1 });
    line(sag(820, 222, 1300, 360, 40), 'wire', 2, { z: 60, cast: 1 });
    line(sag(910, 222, 470, 344, 30), 'wire', 2, { z: 60, cast: 1 });
    // 电线上的鸟
    for (const bx of [1240, 1290, 1310]) { const t = (bx - 890) / 1130; const by = 166 + (120 - 166) * t + 80 * 4 * t * (1 - t); const g = G(); ell(bx, by - 8, 8, 7, 'bird', { z: 120, g }); ell(bx + 7, by - 14, 4.5, 4.5, 'bird', { z: 120, g }); }
    // 路灯
    {
      const g = G(); const st = { z: 140, g, cast: 1, stand: 1, base: Gy };
      box(1446, 360, 12, Gy - 360, 'lampPole', { ...st, r: 2 });
      line([[1452, 370], [1460, 340], [1520, 330]], 'lampPole', 8, st);
      poly([[1500, 322], [1556, 322], [1564, 340], [1492, 340]], 'lampHead', st);
      ell(1528, 344, 22, 7, 'lampBulb', { ...st, glow: 1 });
      light(1528, 350, 300, 'warm', 1.0, { z: 145, cone: 1 });
    }
    // 树
    {
      const g = G(); const st = { z: 120, g, cast: 1, stand: 1, base: Gy };
      const X = -170;
      poly([[300 + X, Gy], [340 + X, Gy], [332 + X, 600], [372 + X, 480], [356 + X, 470], [322 + X, 560], [312 + X, 470], [290 + X, 476], [306 + X, 600]], 'trunk', st);
      const blobs = [[320, 420, 130, 96], [220, 470, 100, 76], [420, 470, 100, 70], [300, 330, 110, 86], [390, 370, 96, 76], [240, 380, 90, 66], [150, 400, 80, 70]];
      for (const [cx, cy, rx, ry] of blobs) ell(cx + X, cy, rx, ry, 'leaf', { ...st, leaf: 1 });
      for (const [cx, cy, rx, ry] of [[300, 390, 76, 54], [400, 420, 64, 42], [330, 310, 64, 44], [200, 430, 50, 36]]) ell(cx + X + 10, cy - 10, rx, ry, 'leafHi', { ...st, leaf: 1 });
      box(294 + X, Gy - 6, 56, 6, 'treePit', { z: 120 });
    }
    // 两个人
    kid(1100, Gy, 90, 'qing', { bag: 'bagQ', step: 5, scale: 1.15 });
    kid(1180, Gy, 96, 'mei', { bag: 'bagM', step: -4, scale: 1.12 });
    // 前景：近处的灌木和栏杆（景深最浅）
    {
      const g = G(); const st = { z: 700, g, fg: 1 };
      for (let k = 0; k < 7; k++) box(1440 + k * 70, 940, 10, 140, 'fence', st);
      box(1430, 960, 520, 10, 'fence', st);
      box(1430, 1010, 520, 10, 'fence', st);
      for (const [cx, cy, rx, ry] of [[-20, 1040, 200, 110], [150, 1080, 160, 80], [70, 980, 120, 70]]) ell(cx, cy, rx, ry, 'bush', st);
    }
    // 飞的鸽子
    for (const [bx, by, sc] of [[520, 120, 1], [580, 96, 0.8], [640, 140, 0.9]]) { const g = G(); poly([[bx - 18 * sc, by - 6 * sc], [bx, by + 2 * sc], [bx + 18 * sc, by - 8 * sc], [bx + 4 * sc, by + 6 * sc], [bx - 4 * sc, by + 6 * sc]], 'birdFly', { z: -200, g }); }

    return { env, L };
  }

  // =====================================================================
  if (name === 'home') {
    const Gy = 800;
    const env = { scene: 'home', time: 'morning', G: Gy, K: 0.25, sun: { x: 260, y: 150 }, shadow: [0.9, 0.1] };
    // 远处
    const far = [[-60, 160, 160], [150, 220, 120], [320, 120, 150], [560, 210, 140], [820, 140, 120], [1010, 230, 170], [1260, 110, 130], [1480, 200, 160], [1700, 150, 130], [1880, 230, 120]];
    for (const [x, top, w] of far) box(x, top, w, 360 - top, 'far', { z: -900, far: 1 });
    // 楼的剖面
    box(0, 360, 1920, 720, 'section', { z: -5, sect: 1 });
    // 屋里后墙
    box(40, 380, 1110, Gy - 380, 'wallRoom', { z: 0, wall: 1 });
    box(40, Gy - 150, 1110, 150, 'wallLow', { z: 0.1, wall: 1 });
    box(40, Gy - 156, 1110, 8, 'trim', { z: 3, d: 3, cast: 1 });
    // 楼道后墙
    box(1190, 380, 690, Gy - 380, 'wallHall', { z: 0, wall: 1 });
    box(1190, Gy - 180, 690, 180, 'wallHallLow', { z: 0.1, wall: 1 });
    // 楼板、外墙剖面（盖在最前）
    box(-20, 350, 1960, 34, 'slab', { z: 300, sect: 1 });
    box(-20, Gy, 1960, 40, 'slab', { z: 300, sect: 1 });
    box(0, 384, 40, Gy - 384, 'brickCut', { z: 300, sect: 1 });
    box(1150, 384, 40, Gy - 384, 'brickCut', { z: 300, sect: 1 });
    box(1880, 384, 40, Gy - 384, 'brickCut', { z: 300, sect: 1 });
    // 楼梯口的楼板开洞
    box(1400, Gy, 250, 40, 'stairWell', { z: 300.1, sect: 1 });
    floor(40, 1110, 0, 240, 'floorRoom', Gy);
    floor(1190, 690, 0, 240, 'floorHall', Gy);
    // 楼下那层（暗）
    box(0, 840, 1920, 240, 'below', { z: 1 });
    box(1150, 840, 40, 240, 'brickCut', { z: 300, sect: 1 });
    light(600, 900, 300, 'warm', 0.35, { z: 2 });
    box(560, 840, 80, 14, 'lampShade', { z: 3 });

    // ---- 屋里 ----
    // 窗（看见早上的天）
    {
      const g = G();
      box(400, 440, 320, 220, 'recess', { z: -1, g });
      box(408, 448, 304, 204, 'skyWin', { z: -0.9, g });
      for (const [x, top, w] of [[420, 560, 60], [490, 520, 70], [570, 580, 50], [630, 540, 70]]) box(x, top, w, 652 - top, 'farWin', { z: -0.85, g });
      box(404, 444, 312, 8, 'frame', { z: -0.5, g }); box(404, 648, 312, 8, 'frame', { z: -0.5, g });
      box(404, 444, 8, 212, 'frame', { z: -0.5, g }); box(708, 444, 8, 212, 'frame', { z: -0.5, g }); box(556, 444, 8, 212, 'frame', { z: -0.5, g });
      box(408, 520, 304, 6, 'frame', { z: -0.5, g });
      box(380, 410, 360, 10, 'curtainRod', { z: 8, d: 8, g, cast: 1 });
      poly([[380, 418], [450, 418], [430, 520], [446, 680], [372, 680]], 'curtainHome', { z: 10, d: 4, g, cast: 1, soft: 1 });
      poly([[740, 418], [680, 418], [700, 520], [686, 680], [752, 680]], 'curtainHome', { z: 10, d: 4, g, cast: 1, soft: 1 });
      box(392, 656, 336, 12, 'trim', { z: 12, d: 12, g, cast: 1 });
      plant(690, 656, 0.7);
    }
    // 窗里照进来的光（落在后墙和地上）
    op('sunpatch', { pts: [[408, 448], [712, 448], [712, 652], [408, 652]], to: [[640, Gy], [980, Gy], [1100, Gy + 60], [760, Gy + 60]], z: 1 });
    // 床
    {
      const g = G(); const st = { z: 100, g, cast: 1, stand: 1, base: Gy };
      box(60, Gy - 150, 18, 150, 'woodDark', { ...st, d: 100, r: 3 });
      box(60, Gy - 70, 300, 40, 'wood', { ...st, d: 100 });
      box(64, Gy - 104, 296, 36, 'mattress', { ...st, d: 100, r: 8 });
      poly([[150, Gy - 112], [356, Gy - 112], [364, Gy - 60], [146, Gy - 64]], 'quilt', { ...st, d: 100, soft: 1 });
      for (let k = 0; k < 5; k++) ell(180 + k * 38, Gy - 88, 9, 9, 'quiltDot', { ...st, z: 100.2 });
      ell(110, Gy - 112, 40, 16, 'pillow', { ...st, d: 60 });
      line([[66, Gy - 30], [66, Gy]], 'woodDark', 8, st); line([[352, Gy - 30], [352, Gy]], 'woodDark', 8, st);
    }
    // 墙上的奖状、挂历、钟
    box(110, 470, 150, 104, 'paperWhite', { z: 2, d: 1, cast: 1 });
    box(118, 478, 134, 18, 'meiLite', { z: 2.1 });
    text('奖 状', 185, 535, 28, 'awardText', { z: 2.2 });
    box(800, 440, 90, 130, 'paperWhite', { z: 2, d: 1, cast: 1 });
    box(800, 440, 90, 32, 'mei', { z: 2.1 });
    text('12', 845, 528, 40, 'signInk', { z: 2.2 });
    ell(1000, 480, 40, 40, 'clockRim', { z: 6, d: 6, cast: 1 });
    ell(1000, 480, 32, 32, 'clockFace', { z: 6.2 });
    line([[1000, 480], [1000, 456]], 'signInk', 4, { z: 6.4 });
    line([[1000, 480], [1018, 488]], 'signInk', 4, { z: 6.4 });
    // 书桌、台灯、书
    {
      const g = G(); const st = { z: 60, g, cast: 1, stand: 1, base: Gy };
      box(420, Gy - 140, 280, 14, 'wood', { ...st, d: 60 });
      box(430, Gy - 126, 90, 70, 'woodDark', { ...st, d: 50 });
      box(436, Gy - 116, 78, 6, 'wood', { ...st, z: 60.1 });
      line([[440, Gy - 56], [440, Gy]], 'woodDark', 8, st);
      line([[690, Gy - 126], [690, Gy]], 'woodDark', 8, st);
      // 书
      const books = [['book1', 16, 52], ['book2', 12, 46], ['book3', 18, 56], ['book1', 10, 40], ['book2', 14, 50]];
      let bx = 560; for (const [m, w, h] of books) { box(bx, Gy - 140 - h, w, h, m, { ...st, z: 30, d: 30, r: 1 }); bx += w + 2; }
      // 台灯
      line([[660, Gy - 142], [646, Gy - 200], [672, Gy - 222]], 'lampArm', 5, st);
      poly([[652, Gy - 236], [690, Gy - 214], [680, Gy - 200], [644, Gy - 222]], 'lampShadeG', st);
      box(646, Gy - 146, 30, 6, 'lampArm', { ...st, r: 2 });
      // 作业本
      poly([[470, Gy - 142], [530, Gy - 142], [536, Gy - 138], [466, Gy - 138]], 'paperWhite', st);
      // 凳子
      box(560, Gy - 70, 70, 10, 'wood', { ...st, z: 120, d: 50 });
      line([[566, Gy - 62], [566, Gy]], 'woodDark', 6, { ...st, z: 120 }); line([[624, Gy - 62], [624, Gy]], 'woodDark', 6, { ...st, z: 120 });
    }
    // 五斗柜 + 电视 + 暖壶
    {
      const g = G(); const st = { z: 50, g, cast: 1, stand: 1, base: Gy };
      box(780, Gy - 170, 220, 170, 'cabinet', { ...st, d: 50, r: 3 });
      for (let k = 0; k < 3; k++) { box(792, Gy - 160 + k * 52, 196, 44, 'cabinet2', { ...st, z: 50.1, r: 2 }); box(880, Gy - 142 + k * 52, 20, 6, 'knob', { ...st, z: 50.2, r: 2 }); }
      box(810, Gy - 290, 140, 116, 'tvBody', { ...st, d: 60, r: 10 });
      box(824, Gy - 278, 96, 86, 'tvScreen', { ...st, z: 50.2, r: 12 });
      ell(934, Gy - 260, 6, 6, 'knob', { ...st, z: 50.2 }); ell(934, Gy - 236, 6, 6, 'knob', { ...st, z: 50.2 });
      line([[860, Gy - 290], [830, Gy - 340]], 'metal', 3, st); line([[880, Gy - 290], [916, Gy - 336]], 'metal', 3, st);
      box(812, Gy - 296, 136, 6, 'doily', { ...st, z: 50.3 });
      box(960, Gy - 230, 28, 60, 'thermos', { ...st, r: 8 });
      box(962, Gy - 238, 24, 10, 'thermosCap', { ...st, r: 3 });
    }
    // 饭桌、两把凳子
    {
      const g = G(); const st = { z: 150, g, cast: 1, stand: 1, base: Gy };
      box(760, Gy - 96, 300, 14, 'tableTop', { ...st, d: 120 });
      line([[776, Gy - 84], [776, Gy]], 'woodDark', 8, st); line([[1044, Gy - 84], [1044, Gy]], 'woodDark', 8, st);
      ell(860, Gy - 104, 34, 8, 'bowl', { ...st, z: 150.2 });
      ell(940, Gy - 104, 28, 8, 'bowl2', { ...st, z: 150.2 });
      box(986, Gy - 120, 30, 22, 'cup', { ...st, z: 150.2, r: 3 });
      ell(860, Gy - 112, 26, 8, 'steam', { ...st, z: 150.3, soft: 1 });
    }
    // 脸盆架
    {
      const g = G(); const st = { z: 40, g, cast: 1, stand: 1, base: Gy };
      line([[1080, Gy], [1086, Gy - 120]], 'metal', 4, st); line([[1130, Gy], [1124, Gy - 120]], 'metal', 4, st);
      ell(1105, Gy - 122, 34, 8, 'basin', st);
      box(1094, Gy - 262, 24, 4, 'metal', st);
      ell(1106, Gy - 210, 26, 34, 'mirror', { ...st, z: 4 });
      box(1076, Gy - 100, 56, 18, 'towel', { ...st, soft: 1 });
    }
    // 人
    kid(560, Gy, 170, 'qing', { scale: 1.05, step: 0 });
    kid(660, Gy, 176, 'mei', { scale: 1.02, step: 3 });

    // ---- 楼道 ----
    // 301、302 门
    for (const [x, m, n, hm] of [[1220, 'doorQing', '301', 'qingHi'], [1740, 'doorMei', '302', 'meiHi']]) {
      const g = G();
      box(x - 10, Gy - 270, 130, 270, 'doorFrame', { z: 2, d: 2, g, cast: 1 });
      box(x, Gy - 260, 110, 260, m, { z: 3, d: 3, g, cast: 1 });
      box(x + 12, Gy - 246, 86, 100, hm, { z: 3.2, g, r: 2 });
      box(x + 12, Gy - 130, 86, 110, hm, { z: 3.2, g, r: 2 });
      ell(x + 94, Gy - 130, 6, 6, 'knob', { z: 3.4, g });
      box(x + 30, Gy - 300, 50, 22, 'plate', { z: 3, g, r: 2 });
      text(n, x + 55, Gy - 288, 18, 'plateText', { z: 3.2 });
      // 福字（倒贴就不弄了）
      poly([[x + 55, Gy - 236], [x + 80, Gy - 211], [x + 55, Gy - 186], [x + 30, Gy - 211]], 'fu', { z: 3.4, g });
    }
    // 电表箱、通知、楼道灯
    box(1410, 450, 110, 80, 'meter', { z: 8, d: 8, cast: 1, r: 3 });
    box(1424, 462, 36, 22, 'glass', { z: 8.2 }); box(1468, 462, 36, 22, 'glass', { z: 8.2 });
    box(1560, 470, 80, 104, 'notice', { z: 1, d: 0.5, cast: 1 });
    for (let k = 0; k < 4; k++) box(1570, 490 + k * 18, 60 - (k % 2) * 16, 6, 'noticeLine', { z: 1.1 });
    line([[1500, 384], [1500, 440]], 'wire', 2, { z: 30 });
    ell(1500, 452, 12, 14, 'bulb', { z: 30, glow: 1 });
    light(1500, 456, 220, 'warm', 0.6, { z: 32 });
    // 往下的楼梯（扶手）
    {
      const g = G(); const st = { z: 140, g, cast: 1 };
      for (let k = 0; k < 7; k++) box(1400 + k * 36, Gy + k * 34, 36, 34, 'stair', { z: 60, g });
      line([[1400, Gy - 90], [1650, Gy + 150]], 'rail', 6, st);
      for (let k = 0; k < 6; k++) line([[1410 + k * 42, Gy - 80 + k * 40], [1410 + k * 42, Gy + k * 40 + 20]], 'rail', 3, st);
    }
    // 上屋顶的铁梯
    {
      const g = G(); const st = { z: 40, g, cast: 1 };
      line([[1660, Gy], [1660, 340]], 'ladder', 6, st); line([[1704, Gy], [1704, 340]], 'ladder', 6, st);
      for (let y = Gy - 30; y > 360; y -= 40) line([[1660, y], [1704, y]], 'ladder', 5, st);
    }
    // 楼道里的自行车、蜂窝煤
    bike(1250 + 150, Gy, 120, 'bikeFrame2', {});
    { const g = G(); for (let r = 0; r < 3; r++) for (let k = 0; k < 4 - r; k++) box(1580 + k * 30 + r * 15, Gy - 30 - r * 26, 28, 26, 'coal', { z: 90, d: 30, g, cast: 1, r: 3 }); }

    // ---- 屋顶 ----
    { const g = G(); box(-20, 330, 1960, 22, 'parapet', { z: 20, d: 20, g, cast: 1 }); }
    // 鸽子笼
    { const g = G(); const st = { z: 60, g, cast: 1, stand: 1, base: 330 };
      box(140, 220, 220, 110, 'coop', { ...st, d: 60 }); poly([[128, 222], [250, 170], [372, 222]], 'coopRoof', st);
      for (let k = 0; k < 8; k++) box(152 + k * 26, 234, 3, 84, 'metal', { ...st, z: 60.1 });
      for (const [bx, by] of [[200, 160], [236, 156], [310, 190]]) { ell(bx, by, 10, 8, 'pigeon', st); ell(bx + 8, by - 7, 5, 5, 'pigeon', st); }
    }
    // 泡沫箱种葱
    for (let k = 0; k < 3; k++) { const g = G(); const st = { z: 40, g, cast: 1, stand: 1, base: 330 }; box(520 + k * 90, 290, 76, 40, 'foam', { ...st, d: 40 }); for (let j = 0; j < 6; j++) line([[530 + k * 90 + j * 11, 290], [528 + k * 90 + j * 11 + (j % 2 ? 4 : -4), 248 + (j % 3) * 8]], 'scallion', 4, st); }
    // 晾衣绳
    {
      const g = G(); const st = { z: 80, g, cast: 1 };
      line([[1100, 330], [1100, 180]], 'metal', 5, { ...st, stand: 1, base: 330 }); line([[1560, 330], [1560, 180]], 'metal', 5, { ...st, stand: 1, base: 330 });
      line([[1100, 190], [1330, 206], [1560, 190]], 'wire', 2.5, st);
      box(1130, 194, 120, 110, 'sheet1', { ...st, soft: 1, sway: 1 });
      box(1266, 200, 46, 60, 'cloth2', { ...st, soft: 1, sway: 1 });
      box(1324, 202, 150, 96, 'sheet2', { ...st, soft: 1, sway: 1 });
      box(1490, 196, 40, 54, 'cloth1', { ...st, soft: 1, sway: 1 });
    }
    // 水箱、天线、屋顶门
    { const g = G(); box(1740, 160, 150, 170, 'roofHut', { z: 0, d: 80, g, cast: 1 }); box(1770, 220, 60, 110, 'doorQing', { z: 0.2, g }); box(1730, 150, 170, 16, 'trim', { z: 6, d: 6, g, cast: 1 }); }
    line([[900, 330], [900, 160]], 'metal', 4, { z: 10, cast: 1 });
    for (let k = 0; k < 4; k++) line([[870 + k * 4, 170 + k * 22], [930 - k * 4, 170 + k * 22]], 'metal', 3, { z: 10, cast: 1 });
    for (const [bx, by, sc] of [[620, 110, 1], [680, 86, 0.8], [740, 126, 0.9]]) { const g = G(); poly([[bx - 18 * sc, by - 6 * sc], [bx, by + 2 * sc], [bx + 18 * sc, by - 8 * sc], [bx + 4 * sc, by + 6 * sc], [bx - 4 * sc, by + 6 * sc]], 'birdFly', { z: -200, g }); }
    // 早上的阳光从左边窗进来
    light(560, 550, 360, 'sun', 0.6, { z: 5 });
    return { env, L };
  }
}

if (typeof module !== 'undefined') module.exports = { buildScene };
