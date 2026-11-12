// 2D 画风共用：投影、路径、挤出
function shiftOf(env, o, z) { if (o.far || o.mid || o.fg) return 0; z = z === undefined ? o.z : z; return Math.max(0, Math.min(z, 400)) * env.K; }
function rr(ctx, x, y, w, h, r) {
  r = Math.min(r || 0, w / 2, h / 2);
  if (r <= 0) { ctx.rect(x, y, w, h); return; }
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
// 正面的路径（dy = 投影下移）
function trace(ctx, o, env, dx = 0, dy = 0) {
  ctx.beginPath();
  if (o.t === 'box') rr(ctx, o.x + dx, o.y + dy, o.w, o.h, o.r);
  else if (o.t === 'poly') { o.pts.forEach((p, k) => k ? ctx.lineTo(p[0] + dx, p[1] + dy) : ctx.moveTo(p[0] + dx, p[1] + dy)); ctx.closePath(); }
  else if (o.t === 'ell') {
    ctx.ellipse(o.cx + dx, o.cy + dy, o.rx, o.ry, 0, 0, Math.PI * 2);
    if (o.ring) ctx.ellipse(o.cx + dx, o.cy + dy, Math.max(1, o.rx - o.ring), Math.max(1, o.ry - o.ring), 0, Math.PI * 2, 0, true);
  }
  else if (o.t === 'floor') { const y0 = o.y + o.z0 * env.K, y1 = o.y + o.z1 * env.K; ctx.rect(o.x + dx, y0 + dy, o.w, y1 - y0); }
  else if (o.t === 'floorEll') ctx.ellipse(o.cx + dx, o.y + o.z0 * env.K + dy, o.rx, o.rx * 0.32, 0, 0, Math.PI * 2);
  else if (o.t === 'line') { o.pts.forEach((p, k) => k ? ctx.lineTo(p[0] + dx, p[1] + dy) : ctx.moveTo(p[0] + dx, p[1] + dy)); }
  else return false;
  return true;
}
function paint(ctx, o, env, fill, dx = 0, dy = 0, lw) {
  if (o.t === 'text') return;
  if (!trace(ctx, o, env, dx, dy)) return;
  if (o.t === 'line') { ctx.strokeStyle = fill; ctx.lineWidth = lw || o.w; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke(); }
  else { ctx.fillStyle = fill; ctx.fill('evenodd'); }
}
// 挤出：从后面 (z-d) 叠到正面 (z)，侧面颜色 side，正面 front
function extrude(ctx, o, env, side, front) {
  const s0 = shiftOf(env, o), s1 = shiftOf(env, o, o.z - o.d);
  if (o.d > 0 && s0 - s1 >= 1 && o.t !== 'line' && o.t !== 'text') {
    const n = Math.min(24, Math.ceil(s0 - s1));
    for (let k = 0; k < n; k++) paint(ctx, o, env, side, 0, s1 + (s0 - s1) * k / n);
  }
  paint(ctx, o, env, front, 0, s0);
}
function sorted(L) { return L.slice().sort((a, b) => (a.z - b.z) || (a.i - b.i)); }
function canvas(w = 1920, h = 1080) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function groupsOf(L) { const m = new Map(); for (const o of L) if (o.g) { if (!m.has(o.g)) m.set(o.g, []); m.get(o.g).push(o); } return m; }
// 固定种子的噪声
function mkRnd(seed) { let s = seed; return () => (s = (s * 16807) % 2147483647) / 2147483647; }
function grain(ctx, amt, seed = 3, w = 1920, h = 1080) {
  const id = ctx.getImageData(0, 0, w, h), d = id.data; const r = mkRnd(seed);
  for (let i = 0; i < d.length; i += 4) { const n = (r() - 0.5) * amt; d[i] += n; d[i + 1] += n; d[i + 2] += n; }
  ctx.putImageData(id, 0, 0);
}
function bbox(o) {
  if (o.t === 'box') return [o.x, o.y, o.w, o.h];
  if (o.t === 'ell') return [o.cx - o.rx, o.cy - o.ry, o.rx * 2, o.ry * 2];
  if (o.pts) { const xs = o.pts.map(p => p[0]), ys = o.pts.map(p => p[1]); const x = Math.min(...xs), y = Math.min(...ys); return [x, y, Math.max(...xs) - x, Math.max(...ys) - y]; }
  if (o.t === 'text') return [o.x - o.size, o.y - o.size / 2, o.size * 2, o.size];
  return [0, 0, 1, 1];
}
