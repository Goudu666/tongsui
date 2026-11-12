// 横条：远景（远处的城，五个年代）、门外的远景（海边、乡下）、中景（隔一两条街的屋顶）、前景（贴着镜头的一溜东西）。
// 画什么、多高多宽照 tools/art/layers.py（孔版时的那套），只是每样东西搭成一块块圆角的小模型。
// 条宽 STRIP = 2048，横着无缝：每样东西在左右各再搭一遍（kit.js 的 wrap），镜头只框 [0, STRIP]。
// 底边就是楼脚：楼的正面在 z = Z_REF（=120），往后退的东西斜投影往上挪，露出楼顶。
import { Kit, rng, wrap, mixHex, ZREF } from './kit.js';

const STRIP = 2048;
const FAR_H = 620, PLACE_H = 300, MID_H = 640, FORE_H = 240;

// ---------------------------------------------------------------- 远景
// 远处的楼：蓝灰里带一点紫（往天色上靠），引擎再按 haze 往天色里推；窗是更深的一格格，夜里有的亮
const FAR_BODY = ['#8E95BA', '#828AB0', '#9890BA', '#8794B0', '#9C9EBA', '#9288B0'];
const FAR_WIN = '#5A6086';

function farSpecs(era) {
  const R = rng(5 + era * 101);
  const items = [];
  let x = 0;
  while (x < STRIP) {
    const w = R.u(60, 150), h = R.u(50, 150) + era * 14;
    items.push({ k: 'low', x, w, h, r: R(), z: R.u(80, 120), d: R.u(40, 80), c: R.i(0, 5) });
    x += w + R.u(-14, 18);
  }
  const nTall = [1, 6, 12, 17, 17][era];
  for (let i = 0; i < nTall; i++) {
    const w = R.u(56, 110), h = R.u(200, 300) + era * R.u(25, 55);
    items.push({ k: 'tall', x: R.u(0, STRIP), w, h: Math.min(h, FAR_H - 60), r: R(), z: R.u(30, 80), d: R.u(50, 90), c: R.i(0, 5) });
  }
  for (let i = 0; i < [4, 2, 1, 0, 0][era]; i++) items.push({ k: 'chimney', x: R.u(0, STRIP), w: 26, h: R.u(240, 340), r: R(), z: R.u(40, 80) });
  if (era <= 1) {
    items.push({ k: 'gas', x: R.u(0, STRIP), w: 150, h: 120, z: 50 });
    items.push({ k: 'water', x: R.u(0, STRIP), w: 60, h: 210, z: 60 });
  }
  for (let i = 0; i < [1, 4, 3, 1, 0][era]; i++) items.push({ k: 'crane', x: R.u(0, STRIP), h: R.u(300, 420), r: R(), z: R.u(30, 60) });
  if (era >= 2) items.push({ k: 'mast', x: R.u(0, STRIP), h: R.u(470, 540), z: 20 });
  return items;
}

function windowsGrid(kit, x, y, w, h, zf, gx, gy, ww, wh, era, salt, win, litP, opt = {}, off = 0) {
  // 一面墙上一格格的窗：hash 定哪格有窗、哪格夜里亮（和老的一样是确定的，换年代不乱跳）
  for (let wy = y + (opt.top ?? 14); wy < y + h - (opt.bottom ?? 10); wy += gy) {
    for (let wx = x + (opt.left ?? 9); wx < x + w - ww - (opt.right ?? 5); wx += gx) {
      const hs = ((Math.round(wx - off) * 73856093) ^ (Math.round(wy) * 19349663) ^ (era * 977 + salt)) >>> 0;
      if (hs % 10 >= (opt.fill ?? 6)) continue;
      const lit = (hs >>> 4) % 10 < litP ? 0.55 + 0.45 * ((hs >>> 8) % 7) / 6 : 0;
      kit.box(wx, wy, ww, wh, zf - 0.4, zf + 0.7, win, { round: 0, lit, cast: false });
    }
  }
}

function buildFar(era) {
  const kit = new Kit();
  const win = kit.mat(FAR_WIN, { r: 0.4 });
  const body = FAR_BODY.map(c => kit.mat(mixHex(c, '#C9C4D8', era * 0.03), { r: 0.92 }));
  const roofM = kit.mat('#A6A9C2', { r: 0.9 });
  const glass = kit.mat('#8496BC', { r: 0.3, m: 0.15 });
  const mullion = kit.mat('#7F8CAE', { r: 0.6 });
  const base = FAR_H;
  const red = kit.mat('#C98A86', { r: 0.7 });
  const white = kit.mat('#D9D8E2', { r: 0.8 });
  const steel = kit.mat('#8D93AC', { r: 0.6 });
  const crane = kit.mat('#C8B482', { r: 0.6 });
  const smoke = kit.mat('#F0EEF2', { r: 1, op: 0.55 });
  const beacon = kit.mat('#D46A60', { r: 0.5 });
  for (const it of farSpecs(era)) {
    const x0 = it.x - 200, x1 = it.x + (it.w || 0) + 200;
    wrap(STRIP, x0, x1, off => {
      const x = it.x + off;
      if (it.k === 'low') {
        const z1 = it.z, z0 = z1 - it.d, top = base - it.h;
        kit.box(x, top, it.w, it.h + 4, z0, z1, body[it.c]);
        if (it.r < 0.35) kit.prism([[x + 4, top + 2], [x + it.w / 2, top - 22], [x + it.w - 4, top + 2]], z0 + 4, z1 - 4, roofM);
        else kit.box(x - 2, top - 4, it.w + 4, 5, z0 - 2, z1 + 2, roofM);
        windowsGrid(kit, x, top, it.w, it.h, z1, 18, 22, 7, 9, era, 1, win, 2, { fill: 5 }, off);
        if (era === 0 && it.r > 0.7) {  // 楼顶的电视天线
          const ax = x + it.w * 0.6, az = (z0 + z1) / 2;
          kit.cyl([ax, top, az], [ax, top - 30, az], 1, 1, steel, { seg: 5 });
          kit.cyl([ax - 12, top - 24, az], [ax + 12, top - 24, az], 0.8, 0.8, steel, { seg: 5 });
        }
      } else if (it.k === 'tall') {
        const z1 = it.z, z0 = z1 - it.d, top = base - it.h, cx = x + it.w / 2, zc = (z0 + z1) / 2;
        const glassy = era >= 2 && it.r > 0.4;
        kit.box(x, top, it.w, it.h + 4, z0, z1, glassy ? glass : body[it.c]);
        const crown = Math.floor(it.r * 4);
        if (crown === 0) kit.cyl([cx, top + 1, zc], [cx, top - 34, zc], it.w * 0.62, 0.5, roofM, { seg: 4 });
        else if (crown === 1) kit.box(x + it.w * 0.22, top - 24, it.w * 0.56, 26, z0 + 10, z1 - 10, roofM);
        else {
          kit.box(x - 2, top - 5, it.w + 4, 6, z0 - 2, z1 + 2, roofM);
          if (crown === 2 && era >= 2) kit.cyl([cx, top - 4, zc], [cx, top - 62, zc], 1.6, 0.8, steel, { seg: 6 });
        }
        if (glassy) {
          // 玻璃幕墙：几道竖的金属框；夜里一层层的走廊亮成一道道
          for (let k = 1; k < 5; k++) kit.box(x + it.w * k / 5 - 1.2, top + 6, 2.4, it.h - 8, z1 - 0.5, z1 + 1, mullion, { round: 0, cast: false });
          for (let wy = top + 20; wy < base - 12; wy += 30) {
            const hs = ((Math.round(it.x) * 31 + Math.round(wy) * 17) & 7);
            kit.box(x + 4, wy, it.w - 8, 3, z1 - 0.3, z1 + 0.4, mullion, { round: 0, lit: hs < 3 ? 0.5 : 0, cast: false });
          }
        } else windowsGrid(kit, x, top, it.w, it.h, z1, 14, 20, 6, 8, era, 7, win, 2, {}, off);
        // 楼顶的红灯（航空障碍灯）
        kit.ball(cx, top - (crown === 0 ? 36 : crown === 1 ? 26 : 8), zc, 2.4, 2.4, 2.4, beacon, { lit: 1, lo: true });
      } else if (it.k === 'chimney') {
        // 红白相间的烟囱，顶上冒烟
        const z = it.z, top = base - it.h;
        kit.cyl([x, base + 4, z], [x, top, z], 14, 9, white, { seg: 14 });
        for (const k of [0.06, 0.2]) kit.cyl([x, top + it.h * k, z], [x, top + it.h * k + 18, z], 9.6 + it.h * k * 0.017, 10.2 + it.h * k * 0.017, red, { seg: 14 });
        for (let k = 0; k < 5; k++) kit.ball(x + 14 + k * 30, top - 14 - k * 13, z - k * 4, 12 + k * 7, 9 + k * 4, 10 + k * 5, smoke, { cast: false });
        kit.ball(x, top - 4, z, 2.2, 2.2, 2.2, beacon, { lit: 1, lo: true });
      } else if (it.k === 'gas') {
        // 储气罐：一只大圆罐，几道箍
        const z = it.z;
        kit.cyl([x, base + 4, z], [x, base - it.h * 0.82, z], it.w / 2, it.w / 2, body[1], { seg: 28 });
        kit.ball(x, base - it.h * 0.82, z, it.w / 2, it.h * 0.2, it.w / 2, body[1]);
        for (let k = 1; k < 4; k++) kit.cyl([x, base - it.h * 0.82 * k / 4 - 2, z], [x, base - it.h * 0.82 * k / 4 + 2, z], it.w / 2 + 1.5, it.w / 2 + 1.5, steel, { seg: 28 });
      } else if (it.k === 'water') {
        const z = it.z;
        kit.cyl([x, base + 4, z], [x, base - it.h * 0.7, z], 9, 7, body[2], { seg: 12 });
        kit.cyl([x, base - it.h * 0.7, z], [x, base - it.h * 0.92, z], it.w / 2 - 4, it.w / 2, body[4], { seg: 20 });
        kit.cyl([x, base - it.h * 0.92, z], [x, base - it.h - 6, z], it.w / 2, 3, roofM, { seg: 20 });
      } else if (it.k === 'crane') {
        // 塔吊：一根格子塔身、一条长臂、配重、吊钩
        const z = it.z, top = base - it.h, r = it.r;
        kit.box(x - 4, top, 8, it.h + 4, z - 4, z + 4, crane, { round: 0.6 });
        kit.box(x - 70, top + 4, 260, 7, z - 3, z + 3, crane, { round: 0.6 });
        kit.box(x - 66, top + 11, 24, 14, z - 6, z + 6, steel, { round: 1 });
        kit.box(x - 3, top - 30, 6, 32, z - 3, z + 3, crane, { round: 0.6 });
        kit.cyl([x, top - 28, z], [x - 68, top + 5, z], 0.8, 0.8, steel, { seg: 4 });
        kit.cyl([x, top - 28, z], [x + 188, top + 5, z], 0.8, 0.8, steel, { seg: 4 });
        const hx = x + 60 + r * 110;
        kit.cyl([hx, top + 10, z], [hx, top + 90 + r * 60, z], 0.6, 0.6, steel, { seg: 4 });
        kit.box(hx - 4, top + 90 + r * 60, 8, 6, z - 3, z + 3, steel, { round: 0.5 });
        kit.box(x + 4, top + 12, 12, 12, z - 5, z + 5, white, { round: 1.5 });
        kit.ball(x, top - 32, z, 2.2, 2.2, 2.2, beacon, { lit: 1, lo: true });
      } else if (it.k === 'mast') {
        // 一根细长的广播塔（不是哪座真塔），半腰一只圆舱，夜里一圈亮
        const z = it.z, top = base - it.h;
        kit.cyl([x, base + 4, z], [x, top, z], 7, 2, white, { seg: 12 });
        const py = base - it.h * 0.72;
        kit.ball(x, py, z, 22, 10, 22, body[0]);
        kit.cyl([x, py - 1.5, z], [x, py + 1.5, z], 22.5, 22.5, win, { seg: 24, lit: 0.8 });
        kit.ball(x, py - 26, z, 9, 7, 9, body[4]);
        for (const k of [0.2, 0.4]) kit.cyl([x, top + it.h * k * 0.3, z], [x, top + it.h * k * 0.3 + 12, z], 4.5, 4.5, red, { seg: 12 });
        kit.ball(x, top, z, 2.4, 2.4, 2.4, beacon, { lit: 1, lo: true });
      }
    });
  }
  // 最底下一抹地气：远处的树连成一片
  const R = rng(7 + era);
  const treeM = ['#7D9798', '#738D92', '#87A09C'].map(c => kit.mat(c, { r: 0.8 }));
  let xx = 0;
  const balls = [];
  while (xx < STRIP) { const rr = R.u(16, 34); balls.push([xx, rr, R.i(0, 2), R.u(100, 125)]); xx += rr * 1.3; }
  for (const [bx, rr, c, z] of balls) wrap(STRIP, bx - rr, bx + rr, off => kit.ball(bx + off, base - rr * 0.35, z, rr, rr * 0.85, rr * 0.8, treeM[c]));
  return { kit, frame: { x0: 0, y0: 0, w: STRIP, h: FAR_H }, lit: true };
}

// ---------------------------------------------------------------- 门外的远景
function buildPlace(kind) {
  const kit = new Kit();
  const base = PLACE_H;
  const R = rng(17 + (kind === 'sea' ? 0 : 1));
  const beacon = kit.mat('#D46A60', { r: 0.5 });
  if (kind === 'sea') {
    const rock = kit.mat('#8C9C9A', { r: 0.95 }), grass = kit.mat('#7FA08A', { r: 0.9 }), pine = kit.mat('#55786A', { r: 0.85 });
    const white = kit.mat('#ECEAE4', { r: 0.7 }), red = kit.mat('#C8615A', { r: 0.6 }), dark = kit.mat('#48505E', { r: 0.7 });
    const capeH = t => 170 * Math.pow(Math.min(1, t * 5), 0.6) * Math.pow(1 - t, 0.55) + 8 * Math.sin(t * 23);
    // 岬角：从海里拱起来、到头一道陡崖；坡上一层黑松，崖顶一座白灯塔
    wrap(STRIP, 120, 980, off => {
      const x0 = 120 + off, x1 = 980 + off;
      const pts = [[x0, base + 6]];
      for (let i = 1; i < 40; i++) { const t = i / 40; pts.push([x0 + (x1 - x0) * t, base - capeH(t)]); }
      pts.push([x1, base + 6]);
      kit.prism(pts, 30, 110, rock, { bevel: true });
      const top = pts.map(([x, y]) => [x, y - 0]);
      // 坡顶一层草皮：沿着轮廓的扁圆
      for (let i = 2; i < 38; i += 1) { const t = i / 40; kit.ball(x0 + (x1 - x0) * t, base - capeH(t) + 4, 90, 16, 7, 24, grass, { lo: true }); }
      const R2 = rng(41);
      for (let k = 0; k < 26; k++) {
        const t = 0.18 + 0.6 * k / 26, tx = x0 + (x1 - x0) * t, ty = base - capeH(t) + 4, s = R2.u(8, 14);
        kit.cyl([tx, ty, 80 + R2.u(-20, 20)], [tx, ty - s * 2.6, 80], s, 0.6, pine, { seg: 8 });
      }
      const t = 0.2, lx = x0 + (x1 - x0) * t, ly = base - capeH(t) + 6;
      kit.cyl([lx, ly, 90], [lx, ly - 46, 90], 10, 7, white, { seg: 16 });
      for (let k = 0; k < 2; k++) kit.cyl([lx, ly - 30 + k * 14, 90], [lx, ly - 26 + k * 14, 90], 9.2 - k * 0.6 + 0.6, 9.2 - k * 0.6 + 0.6, red, { seg: 16 });
      kit.cyl([lx, ly - 46, 90], [lx, ly - 58, 90], 8, 8, kit.mat('#F2D58A', { r: 0.3 }), { seg: 16, lit: 1 });
      kit.cyl([lx, ly - 58, 90], [lx, ly - 70, 90], 10, 1, red, { seg: 16 });
    });
    // 远处一个小岛
    wrap(STRIP, 1560, 1760, off => {
      const pts = [[1560 + off, base + 4]];
      for (let i = 1; i < 16; i++) pts.push([1560 + off + 200 * i / 16, base - 34 * Math.pow(Math.sin(Math.PI * i / 16), 0.7)]);
      pts.push([1760 + off, base + 4]);
      kit.prism(pts, 0, 40, kit.mat('#A3B4B4', { r: 0.95 }), { bevel: true });
    });
    // 货轮：长长一条船身、红水线，甲板上码着集装箱，船尾白楼，烟囱冒一点烟
    wrap(STRIP, 1100, 1440, off => {
      const sx = 1120 + off, z = 70;
      kit.prism([[sx - 12, base - 38], [sx + 304, base - 38], [sx + 286, base - 8], [sx + 10, base - 8]], z - 18, z + 18, dark, { bevel: true });
      kit.box(sx - 4, base - 18, 300, 7, z - 19, z + 19, red, { round: 1 });
      const cc = ['#5E8FA8', '#C8615A', '#E2B65A', '#6FA08A', '#D88C5A', '#8C7AA8'].map(c => kit.mat(c, { r: 0.7 }));
      for (let c = 0; c < 9; c++) for (let r = 0; r < 2 + (c % 3 === 1 ? 1 : 0); r++) kit.box(sx + 70 + c * 22, base - 51 - r * 13, 21, 13, z - 14, z + 14, cc[(c * 2 + r) % cc.length], { round: 1 });
      kit.box(sx + 6, base - 92, 52, 56, z - 16, z + 16, white, { round: 2 });
      for (let r = 0; r < 3; r++) kit.box(sx + 10, base - 84 + r * 15, 44, 5, z + 15.6, z + 16.6, dark, { round: 0, lit: 0.8, cast: false });
      kit.box(sx + 22, base - 116, 16, 24, z - 7, z + 7, red, { round: 2 });
      const smoke = kit.mat('#F0EEF2', { r: 1, op: 0.5 });
      for (let k = 0; k < 4; k++) kit.ball(sx + 24 - k * 26, base - 128 - k * 10, z - k * 3, 10 + k * 6, 7 + k * 3, 8 + k * 4, smoke, { cast: false });
      kit.ball(sx + 298, base - 44, z, 2.2, 2.2, 2.2, beacon, { lit: 1, lo: true });
    });
    // 海平线上远远的几条渔船
    for (let k = 0; k < 5; k++) {
      const bx = 1500 + k * 90 + R.u(-20, 20);
      wrap(STRIP, bx, bx + 30, off => {
        kit.box(bx + off, base - 9, 26, 6, 20, 30, dark, { round: 1.5 });
        kit.box(bx + off + 4, base - 15, 9, 6, 22, 28, white, { round: 1 });
        kit.cyl([bx + off + 16, base - 9, 25], [bx + off + 16, base - 24, 25], 0.7, 0.7, dark, { seg: 4 });
      });
    }
  } else {
    // 乡下：一排排又高又瘦的杨树，一座水塔，几排红砖房，一座高压线铁塔，底下一抹庄稼
    const poplar = ['#7FA27A', '#8CAE80', '#739873'].map(c => kit.mat(c, { r: 0.85 }));
    const trunk = kit.mat('#7A6656', { r: 0.9 });
    for (const [depth, hmin, hmax, gap, z] of [[0.5, 100, 150, 22, 20], [0.75, 130, 190, 30, 70]]) {
      const R2 = rng(Math.round(depth * 100));
      let x = 0;
      while (x < STRIP) {
        if (R2() < 0.12) { x += R2.u(120, 300); continue; }
        const h = R2.u(hmin, hmax) * depth / 0.75, w = h * R2.u(0.16, 0.22), c = R2.i(0, 2), zz = z + R2.u(-10, 10);
        const xx = x;
        wrap(STRIP, x - w, x + w, off => {
          kit.cyl([xx + off, base + 4, zz], [xx + off, base - h * 0.35, zz], 2.4, 1.6, trunk, { seg: 6 });
          kit.ball(xx + off, base - h * 0.6, zz, w, h * 0.42, w, poplar[c]);
        });
        x += gap * R2.u(0.7, 1.4);
      }
    }
    const conc = kit.mat('#C9C2B8', { r: 0.9 }), tank = kit.mat('#B6B9BE', { r: 0.6 });
    wrap(STRIP, 600, 690, off => {
      const tx = 640 + off, z = 60;
      kit.cyl([tx, base + 4, z], [tx, base - 170, z], 16, 10, conc, { seg: 14 });
      kit.cyl([tx, base - 168, z], [tx, base - 214, z], 38, 45, tank, { seg: 24 });
      kit.cyl([tx, base - 214, z], [tx, base - 236, z], 45, 30, tank, { seg: 24 });
      kit.cyl([tx, base - 189, z], [tx, base - 192, z], 43.5, 43.5, conc, { seg: 24 });
      kit.ball(tx, base - 240, z, 2.2, 2.2, 2.2, beacon, { lit: 1, lo: true });
    });
    const brick = kit.mat('#C27A62', { r: 0.9 }), tile = kit.mat('#7E7A84', { r: 0.8 }), winM = kit.mat('#4E4A56', { r: 0.4 });
    for (const [x0, n] of [[220, 5], [1260, 7]]) {
      for (let k = 0; k < n; k++) {
        const hx = x0 + k * 46;
        wrap(STRIP, hx, hx + 46, off => {
          kit.box(hx + off, base - 30, 40, 34, 70, 100, brick, { round: 1.5 });
          kit.prism([[hx + off - 4, base - 29], [hx + off + 20, base - 44], [hx + off + 44, base - 29]], 68, 102, tile);
          kit.box(hx + off + 14, base - 22, 9, 9, 99.6, 100.6, winM, { round: 0, lit: k % 2 === 0 ? 0.8 : 0, cast: false });
        });
      }
    }
    const steel = kit.mat('#8E9098', { r: 0.6 });
    wrap(STRIP, 1640, 1760, off => {
      const px = 1700 + off, z = 50;
      for (const s of [-1, 1]) kit.cyl([px + s * 30, base + 4, z], [px + s * 6, base - 200, z], 1.6, 1.2, steel, { seg: 5 });
      for (let k = 0; k < 5; k++) {
        const y = base - k * 40, w = 30 - k * 5;
        kit.cyl([px - w, y, z], [px + w - 5, y - 40, z], 0.8, 0.8, steel, { seg: 4 });
        kit.cyl([px + w, y, z], [px - w + 5, y - 40, z], 0.8, 0.8, steel, { seg: 4 });
      }
      kit.cyl([px - 46, base - 160, z], [px + 46, base - 160, z], 1.5, 1.5, steel, { seg: 5 });
      kit.cyl([px - 36, base - 190, z], [px + 36, base - 190, z], 1.5, 1.5, steel, { seg: 5 });
    });
    const crop = ['#9DB27A', '#A9B886', '#B6B477'].map(c => kit.mat(c, { r: 0.9 }));
    const R3 = rng(29);
    let xx = 0;
    while (xx < STRIP) {
      const rr = R3.u(12, 26), c = R3.i(0, 2), x = xx;
      wrap(STRIP, x - rr * 2, x + rr * 2, off => kit.ball(x + off, base - rr * 0.15, 110, rr * 1.8, rr * 0.5, rr * 0.9, crop[c], { lo: false }));
      xx += rr * 2.6;
    }
  }
  return { kit, frame: { x0: 0, y0: 0, w: STRIP, h: PLACE_H }, lit: true };
}

// ---------------------------------------------------------------- 中景
const MID_COL = {
  mei: ['#B9634F', '#A9584A', '#C47258'],      // 红砖
  ink: ['#D5C7AE', '#C4BBAE', '#DCCFB8'],      // 水泥、米黄的抹灰
  qing: ['#8FB5A2', '#9DBBA8', '#86AA9C'],     // 刷了青绿的
};

function midSpecs(era) {
  const R = rng(11 + era * 37);
  const items = [];
  let x = 0;
  while (x < STRIP) {
    let w = R.u(210, 380), floors = R.i(4, 7);
    const tower = era >= 2 && R() < [0, 0, 0.15, 0.28, 0.3][era];
    if (tower) { floors = R.i(14, 18); w = R.u(160, 220); }
    items.push({ x, w, floors, tower, r: R(), r2: R(), r3: R(), color: R.pick(['mei', 'mei', 'ink', 'qing']), shade: R.i(0, 2), d: R.u(80, 110), z: R.u(104, 120), bands: R() < 0.5 });
    x += w + R.u(30, 120);
  }
  return items;
}

function buildMid(era) {
  const kit = new Kit();
  const base = MID_H, FL = 32;
  const glass = kit.mat('#4E5E78', { r: 0.25, m: 0.1 });
  const curtains = ['#E7B85C', '#D87A6A', '#8EB6A6', '#EDE2C8'].map(c => kit.mat(c, { r: 0.8 }));
  const trim = kit.mat('#EFE4CF', { r: 0.85 });
  const roofM = kit.mat('#B3AAA0', { r: 0.95 });
  const parapet = kit.mat('#CFC4B2', { r: 0.9 });
  const ac = kit.mat('#E8E4DA', { r: 0.6 }), acGrill = kit.mat('#8E8A84', { r: 0.6 });
  const metal = kit.mat('#56545E', { r: 0.45, m: 0.3 }), tankM = kit.mat('#A9B4B8', { r: 0.5, m: 0.15 });
  const solar = kit.mat('#3E4C64', { r: 0.25, m: 0.2 }), solarTank = kit.mat('#D9DDE2', { r: 0.4, m: 0.3 });
  const cloth = ['#F0EDE4', '#4E7FB0', '#E6A23C', '#D94A3A', '#2E8B6E'].map(c => kit.mat(c, { r: 0.85 }));
  const pot = kit.mat('#B4673F', { r: 0.8 }), plant = ['#4F8F55', '#7FA04A'].map(c => kit.mat(c, { r: 0.7 }));
  const coop = kit.mat('#A27A52', { r: 0.85 }), coopRoof = kit.mat('#5E5A62', { r: 0.8 });
  const towerM = kit.mat('#A9B9C6', { r: 0.35, m: 0.1 }), towerFrame = kit.mat('#E2E6EA', { r: 0.6 });
  const beacon = kit.mat('#D46A60', { r: 0.5 });

  for (const it of midSpecs(era)) {
    wrap(STRIP, it.x - 60, it.x + it.w + 60, off => {
      const x = it.x + off, w = it.w;
      const h = Math.min(it.floors * FL + 20, MID_H - 40), top = base - h;
      const z1 = it.z, z0 = z1 - it.d;
      const bodyM = it.tower ? towerM : kit.mat(MID_COL[it.color][it.shade], { r: 0.92 });
      kit.box(x, top, w, h + 4, z0, z1, bodyM);
      // 楼顶：一圈女儿墙 + 屋面
      kit.box(x - 3, top - 7, w + 6, 8, z0 - 2, z1 + 2, parapet, { round: 2 });
      kit.box(x + 3, top - 8, w - 6, 3, z0 + 3, z1 - 3, roofM, { round: 0.6, cast: false });
      // 窗
      const rows = Math.floor((h - 24) / FL);
      const cols = Math.max(2, Math.floor((w - 30) / 34));
      const gap = (w - 30) / cols;
      for (let ry = 0; ry < rows; ry++) {
        const wy = top + 16 + ry * FL;
        if (it.bands && !it.tower) kit.box(x - 1.5, wy + FL * 0.62 + 3, w + 3, 3, z1 - 1, z1 + 2.5, trim, { round: 0.8 });  // 每层一道腰线
        for (let cx = 0; cx < cols; cx++) {
          const wx = x + 15 + cx * gap + gap * 0.2, ww = gap * 0.56, wh = FL * 0.56;
          const hs = ((Math.round(it.x * 3) * 7919) ^ (ry * 104729) ^ (cx * 1299709) ^ (era * 31)) >>> 0;
          const lit = hs % 9 < 3 ? 0.65 + 0.35 * (hs % 4) / 3 : 0;
          if (it.tower) {
            kit.box(wx - 2, wy - 2, ww + 4, wh + 4, z1 - 0.3, z1 + 0.8, towerFrame, { round: 0, cast: false });
            kit.box(wx, wy, ww, wh, z1 + 0.5, z1 + 1.1, glass, { round: 0, lit, cast: false });
            continue;
          }
          kit.box(wx - 2.5, wy - 2.5, ww + 5, wh + 5, z1 - 0.3, z1 + 1.6, trim, { round: 0.8, cast: false });
          const g = hs % 5 === 0 ? curtains[(hs >>> 3) % 4] : glass;
          kit.box(wx, wy, ww, wh, z1 + 1.2, z1 + 1.8, g, { round: 0, lit, cast: false });
          kit.box(wx - 4, wy + wh + 1.5, ww + 8, 3, z1, z1 + 4, trim, { round: 0.8 });  // 窗台
          if (era >= 1 && hs % 7 === 0) {  // 空调外机（2000 年以后）
            kit.box(wx + ww + 4, wy + FL * 0.28, 13, 10, z1, z1 + 7, ac, { round: 1.2 });
            kit.cyl([wx + ww + 10.5, wy + FL * 0.28 + 5, z1 + 7.1], [wx + ww + 10.5, wy + FL * 0.28 + 5, z1 + 7.6], 3.4, 3.4, acGrill, { seg: 10 });
          }
        }
      }
      // 楼顶的东西：这一层最有年代感
      const r = it.r, r2 = it.r2, zr = (z0 + z1) / 2, rt = top - 8;
      if (it.tower) {
        kit.ball(x + w / 2, rt - 4, zr, 2.6, 2.6, 2.6, beacon, { lit: 1, lo: true });
        kit.box(x + w * 0.3, rt - 20, w * 0.4, 20, z0 + 15, z1 - 15, towerFrame);
        return;
      }
      if (era === 0) {
        // 九十年代：鱼骨天线、鸽子笼
        for (let k = 0; k < 1 + Math.floor(r * 3); k++) {
          const ax = x + 30 + k * (w - 60) / 3, az = zr + (k % 2 ? 12 : -10);
          kit.cyl([ax, rt, az], [ax, rt - 48, az], 1.1, 0.9, metal, { seg: 5 });
          for (let j = 0; j < 4; j++) kit.cyl([ax - 14 + j * 2, rt - 42 + j * 8, az], [ax + 14 - j * 2, rt - 42 + j * 8, az], 0.7, 0.7, metal, { seg: 4 });
        }
        if (it.r3 < 0.4) {
          const cx0 = x + w - 70;
          kit.box(cx0, rt - 26, 46, 26, zr - 14, zr + 14, coop, { round: 2 });
          kit.prism([[cx0 - 4, rt - 25], [cx0 + 23, rt - 38], [cx0 + 50, rt - 25]], zr - 16, zr + 16, coopRoof);
          kit.box(cx0 + 8, rt - 18, 30, 8, zr + 13.8, zr + 14.6, kit.mat('#3A3238', { r: 0.6 }), { round: 0, cast: false });
        }
      }
      if (era >= 1 && era <= 3) {
        // 太阳能热水器：一排斜着的管板 + 一根横水箱
        for (let k = 0; k < 1 + Math.floor(r * 2); k++) {
          const sx = x + 24 + k * 90 + r2 * 20;
          if (sx + 70 > x + w) break;
          const pz = zr + 4;
          const p = kit.box(sx, rt - 30, 66, 30, pz - 1.5, pz + 1.5, solar, { round: 0.6 });
          p.rotation.x = -0.75;  // 往后仰
          kit.cyl([sx, rt - 40, pz - 14], [sx + 66, rt - 40, pz - 14], 6, 6, solarTank, { seg: 14 });
          for (const lx of [sx + 4, sx + 62]) kit.cyl([lx, rt, pz + 6], [lx, rt - 34, pz - 14], 1, 1, metal, { seg: 4 });
        }
      }
      if (era >= 3 && r > 0.5) {
        // 后来的楼顶种了菜和花
        for (let k = 0; k < Math.floor(w / 40); k++) {
          const px = x + 20 + k * 40, pz = zr + (k % 2 ? 10 : -6);
          kit.box(px - 9, rt - 10, 18, 10, pz - 8, pz + 8, pot, { round: 1.5 });
          kit.ball(px, rt - 16, pz, 11, 9, 10, plant[k % 2]);
        }
      }
      if (r2 > 0.55) {
        // 水箱：架子上一只罐子
        const tx = x + w * (0.6 + 0.2 * r), tz = zr - 8;
        for (const [dx, dz] of [[-16, -10], [16, -10], [-16, 10], [16, 10]]) kit.cyl([tx + dx, rt, tz + dz], [tx + dx, rt - 16, tz + dz], 1.4, 1.4, metal, { seg: 5 });
        kit.box(tx - 24, rt - 52, 48, 36, tz - 18, tz + 18, tankM, { round: 4 });
      }
      if (r < 0.4) {
        // 晾的衣裳
        const lz = zr + 14;
        kit.cyl([x + 18, rt, lz], [x + 18, rt - 36, lz], 1, 1, metal, { seg: 4 });
        kit.cyl([x + 134, rt, lz], [x + 134, rt - 34, lz], 1, 1, metal, { seg: 4 });
        kit.tube([[x + 18, rt - 35, lz], [x + 76, rt - 31, lz], [x + 134, rt - 33, lz]], 0.5, metal, { seg: 3 });
        for (let k = 0; k < 4; k++) kit.box(x + 28 + k * 24, rt - 32, 16, 20 + (k % 2) * 8, lz - 0.8, lz + 0.8, cloth[(k + era) % cloth.length], { round: 0.4 });
      }
    });
  }
  // 楼脚一溜行道树
  const R = rng(3 + era);
  const treeM = ['#5F9A62', '#6EA466', '#55895A'].map(c => kit.mat(c, { r: 0.7 }));
  const trunk = kit.mat('#6A4E3E', { r: 0.85 });
  let xx = 0;
  while (xx < STRIP) {
    const rr = R.u(28, 56), c = R.i(0, 2), x = xx, z = R.u(118, 128);
    wrap(STRIP, x - rr * 1.3, x + rr * 1.3, off => {
      kit.cyl([x + off, base + 6, z], [x + off, base - rr * 0.6, z], 4, 3, trunk, { seg: 8 });
      kit.ball(x + off, base - rr * 0.9, z, rr, rr * 0.85, rr * 0.75, treeM[c]);
      kit.ball(x + off - rr * 0.55, base - rr * 0.6, z + 4, rr * 0.6, rr * 0.55, rr * 0.5, treeM[(c + 1) % 3]);
      kit.ball(x + off + rr * 0.6, base - rr * 0.55, z + 2, rr * 0.55, rr * 0.5, rr * 0.5, treeM[(c + 2) % 3]);
    });
    xx += rr * R.u(1.6, 3.4);
  }
  return { kit, frame: { x0: 0, y0: 0, w: STRIP, h: MID_H }, lit: true };
}

// ---------------------------------------------------------------- 前景
function buildFore(kind) {
  const kit = new Kit();
  const base = FORE_H, Z = ZREF;
  const KINDS = ['street', 'river', 'green', 'school', 'market', 'sea', 'field'];
  const R0 = rng(31 + KINDS.indexOf(kind));
  const items = [];
  let x = R0.u(60, 200);
  while (x < STRIP - 60) { items.push([x, R0(), R0()]); x += R0.u(340, 760); }
  let R = R0;  // 每样东西自己一个种子：左右各搭一遍时搭得一模一样
  const M = (c, o) => kit.mat(c, o || { r: 0.7 });
  const ink = M('#3A3640'), leaf = ['#4F8A55', '#5E9A58', '#457A4E'].map(c => M(c)), red = M('#D24A3E', { r: 0.45 }), stone = M('#A8A29A', { r: 0.95 });
  const bush = (x0, w, h, cols = leaf) => {
    const k = Math.max(3, Math.floor(w / 40));
    for (let i = 0; i < k; i++) {
      const cx = x0 + (i + 0.5) * w / k, rr = h * R.u(0.5, 0.72);
      kit.ball(cx, base - rr * 0.7, Z + R.u(-10, 10), rr, rr * 0.9, rr * 0.8, cols[i % cols.length]);
    }
  };
  const grass = (x0, w, h, col) => {
    for (let i = 0; i < w / 6; i++) {
      const gx = x0 + i * 6 + R.u(-2, 2), a = R.u(-0.4, 0.4), L = h * R.u(0.5, 1.0);
      kit.cyl([gx, base + 2, Z + R.u(-8, 8)], [gx + Math.sin(a) * L, base - Math.cos(a) * L, Z], 3, 0.3, col, { seg: 5 });
    }
  };
  const one = (x, r, r2) => {
    if (kind === 'street') {
      if (r < 0.3) {  // 路边一溜矮栏杆
        for (let k = 0; k < 5; k++) kit.cyl([x + k * 40, base + 4, Z], [x + k * 40, base - 82, Z], 4, 4, ink, { seg: 10 });
        kit.cyl([x - 10, base - 70, Z], [x + 170, base - 70, Z], 3.5, 3.5, ink, { seg: 8 });
        kit.cyl([x - 10, base - 40, Z], [x + 170, base - 40, Z], 3.5, 3.5, red, { seg: 8 });
      } else if (r < 0.55) {  // 消防栓
        kit.cyl([x, base + 4, Z], [x, base - 86, Z], 22, 22, red, { seg: 20 });
        kit.cyl([x, base - 86, Z], [x, base - 100, Z], 26, 18, red, { seg: 20 });
        kit.ball(x, base - 100, Z, 18, 12, 18, red);
        kit.cyl([x - 36, base - 63, Z], [x + 36, base - 63, Z], 7, 7, M('#3F3A44', { r: 0.4, m: 0.3 }), { seg: 12 });
        kit.cyl([x, base - 30, Z], [x, base - 26, Z], 23.5, 23.5, M('#F2E6D0'), { seg: 20 });
      } else if (r < 0.8) bush(x, R.u(160, 260), R.u(60, 90));  // 一小丛冬青
      else {  // 路边的石墩
        kit.cyl([x, base + 4, Z], [x, base - 80, Z], 30, 26, stone, { seg: 16 });
        kit.ball(x, base - 80, Z, 26, 8, 26, stone);
      }
    } else if (kind === 'river') {
      if (r < 0.6) {  // 芦苇：一丛细长的叶子、几根穗
        const reed = M('#6E8A4E'), plume = M('#C9A97A', { r: 0.95 });
        for (let k = 0; k < 14; k++) {
          const a = R.u(-0.35, 0.35), L = R.u(80, 150), sx = x + k * 7;
          kit.tube([[sx, base + 4, Z], [sx + Math.sin(a) * L * 0.4 + a * 10, base - L * 0.5, Z + k % 3 * 4], [sx + Math.sin(a) * L, base - Math.cos(a) * L, Z]], 2.6, reed, { taper: 0.15, seg: 5 });
        }
        for (let k = 0; k < 4; k++) {
          const px = x + 20 + k * 22, py = base - R.u(140, 170);
          kit.cyl([px, base + 4, Z], [px + 6, py, Z], 1.4, 1, M('#8C7A5A'), { seg: 5 });
          kit.ball(px + 8, py - 18, Z, 7, 22, 7, plume, { rot: [0, 0, -0.2] });
        }
      } else {  // 近处一截石栏杆
        kit.box(x, base - 110, 46, 114, Z - 22, Z + 22, stone, { round: 5 });
        kit.box(x - 8, base - 128, 62, 20, Z - 28, Z + 28, stone, { round: 6 });
        kit.box(x + 46, base - 92, 260, 20, Z - 10, Z + 10, stone, { round: 5 });
      }
    } else if (kind === 'green') {
      if (r < 0.5) {
        bush(x, R.u(200, 340), R.u(64, 100));
        if (r2 < 0.5) {
          const fl = ['#E8707E', '#F2C04E', '#F3EEE2'].map(c => M(c, { r: 0.5 }));
          for (let k = 0; k < 9; k++) kit.ball(x + R.u(20, 220), base - R.u(60, 120), Z + R.u(30, 50), 8, 8, 8, fl[k % 3], { lo: true });
        }
      } else grass(x, R.u(140, 260), R.u(50, 100), leaf[1]);
    } else if (kind === 'school') {
      if (r < 0.45) {  // 近处的铁栅栏：几根尖头的竖杆
        const iron = M('#2F5A50', { r: 0.45, m: 0.3 });
        for (let k = 0; k < 6; k++) {
          const px = x + k * 34;
          kit.cyl([px, base + 4, Z], [px, base - 100, Z], 4, 4, iron, { seg: 10 });
          kit.cyl([px, base - 100, Z], [px, base - 122, Z], 7, 0.5, iron, { seg: 10 });
        }
        kit.box(x - 10, base - 84, 190, 7, Z - 4, Z + 4, iron, { round: 2 });
        kit.box(x - 10, base - 44, 190, 7, Z - 4, Z + 4, iron, { round: 2 });
      } else bush(x, R.u(180, 280), R.u(60, 90));
    } else if (kind === 'market') {
      if (r < 0.4) {  // 一只竹筐，冒出几片菜叶
        const bam = M('#C9A46A', { r: 0.9 });
        kit.cyl([x + 60, base + 4, Z], [x + 60, base - 90, Z], 62, 72, bam, { seg: 24 });
        for (let k = 0; k < 4; k++) kit.cyl([x + 60, base - 14 - k * 22, Z], [x + 60, base - 10 - k * 22, Z], 63.5 + k * 2.6, 64 + k * 2.6, M('#A8834E', { r: 0.9 }), { seg: 24 });
        const veg = ['#6FAE55', '#9CCB68', '#E2554A'].map(c => M(c));
        for (let k = 0; k < 7; k++) kit.ball(x + 14 + k * 16, base - 96 - R.u(0, 10), Z + R.u(-20, 30), R.u(13, 20), R.u(11, 16), 14, veg[k % 3]);
      } else {  // 摞起来的塑料筐
        const cr = [M('#3C7A9A', { r: 0.45 }), M('#C84A3A', { r: 0.45 })];
        const hole = M('#2A2832');
        for (let k = 0; k < 2; k++) {
          const cx = x + k * 6, cy = base - 64 - k * 64;
          kit.box(cx, cy, 120, 62, Z - 40, Z + 40, cr[(k + (r2 > 0.5 ? 1 : 0)) % 2], { round: 5 });
          for (let j = 0; j < 5; j++) kit.box(cx + 12 + j * 21, cy + 14, 12, 14, Z + 39.6, Z + 40.6, hole, { round: 0, cast: false });
        }
      }
    } else if (kind === 'sea') {
      const sand = M('#E3CFA4', { r: 0.95 });
      if (r < 0.55) {  // 沙丘上一丛海草
        kit.ball(x + 60, base + 6, Z, 110, 40, 50, sand);
        grass(x, 100, 130, M('#7E9A5E'));
      } else if (r < 0.8) {  // 一截木桩，拴着一根缆绳
        const wood = M('#8A6446', { r: 0.9 });
        kit.cyl([x + 17, base + 4, Z], [x + 17, base - 140, Z], 17, 15, wood, { seg: 14 });
        kit.ball(x + 17, base - 140, Z, 15, 5, 15, M('#6E4A33', { r: 0.9 }));
        kit.tube([[x + 30, base - 100, Z + 10], [x + 120, base - 50, Z + 20], [x + 220, base - 10, Z + 10]], 3, M('#D8C8A0', { r: 0.9 }), { seg: 6 });
      } else {  // 一只倒扣在沙滩上的小舢板
        kit.ball(x + 140, base, Z, 140, 56, 46, M('#3F8A82', { r: 0.6 }));
        kit.ball(x + 140, base - 2, Z, 142, 10, 47, M('#F2E6D0', { r: 0.7 }));
      }
    } else if (kind === 'field') {
      if (r < 0.5) {  // 地头的玉米：几片长叶子从底下扫上来
        const corn = ['#7FA04A', '#6E9442'].map(c => M(c));
        kit.cyl([x + 40, base + 4, Z], [x + 46, base - 230, Z], 5, 3, M('#9AA35A'), { seg: 8 });
        for (let k = 0; k < 6; k++) {
          const s = k % 2 ? -1 : 1, L = R.u(120, 200), sx = x + 42, sy = base - 30 - k * 30;
          kit.tube([[sx, sy, Z], [sx + s * L * 0.35, sy - L * 0.3, Z + 6], [sx + s * L * 0.75, sy - L * 0.2, Z + 10], [sx + s * L, sy + 10, Z + 12]], 6.5, corn[k % 2], { taper: 0.1, seg: 6 });
        }
      } else {  // 狗尾巴草
        const stem = M('#8AA052'), head = M('#B9B86A', { r: 0.95 });
        for (let k = 0; k < 9; k++) {
          const px = x + k * 16, py = base - R.u(90, 150);
          kit.tube([[px, base + 4, Z], [px + 6, py + 10, Z], [px + 16, py, Z]], 1.4, stem, { seg: 4 });
          kit.ball(px + 18, py - 2, Z, 7, 16, 7, head, { rot: [0, 0, -0.6] });
        }
        grass(x - 20, 200, 60, stem);
      }
    }
  };
  items.forEach(([x, r, r2], i) => {
    wrap(STRIP, x - 60, x + 360, off => { R = rng(1000 + i * 17 + KINDS.indexOf(kind)); one(x + off, r, r2); });
  });
  return { kit, frame: { x0: 0, y0: 0, w: STRIP, h: FORE_H }, lit: false };
}

export function build(job) {
  if (job.type === 'far') return buildFar(job.era);
  if (job.type === 'place') return buildPlace(job.kind);
  if (job.type === 'mid') return buildMid(job.era);
  if (job.type === 'fore') return buildFore(job.kind);
  throw new Error('不认得 ' + job.type);
}
